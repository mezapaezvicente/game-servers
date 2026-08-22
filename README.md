# game-servers

One monorepo, one directory per game. Isolation between games comes from
path-filtered CI and from each game only touching its own
`/srv/games/<game>/data`, not from separate repos. If a game ever needs to
be handed to someone else, split it out then with `git filter-repo` —
don't pre-split for a need that doesn't exist yet.

Pairs with the `infra-base` repo, which hardens the box this runs on and
sets up the shared `restic` config these Makefiles depend on.

## Layout

```
_template/          copy this to start a new game
games/
  zomboid/            Project Zomboid dedicated server
lib/
  backup.sh           shared, called by every game's `make backup`
  restore.sh          shared, called by every game's `make restore`
test/                shellcheck/bats/compose-integration checks, see Testing below
PORTS.md             source of truth for port allocation on the box
API.md                design doc for a future local API + Discord bot
.github/workflows/
  deploy.yml           path-filtered: pushes to games/<x>/ deploy only <x>
  test.yml             shellcheck + bats + docker-compose integration, every push/PR
```

## Adding a game

See `_template/README.md`. Short version: copy `_template/` to
`games/<name>/`, fill in the image/health check/ports, register the port
in `PORTS.md`, open it in `infra-base`, add `.env` on the box, `make up`.

## Every game has the same Makefile targets

`up`, `down`, `logs`, `status`, `backup`, `restore`, `update`. Same names,
same behavior shape, across every game, so there's nothing per-game to
remember. See `_template/README.md` for what each one does.

## Secrets

Never committed. `.env` lives on the box only; `.env.example` is the
committed placeholder. The restic repository and credentials live in
`infra-base`'s `group_vars/all.yml` (also not committed) and get written
to `/etc/restic/restic.env` on the box by that playbook — `lib/backup.sh`
and `lib/restore.sh` here read that file.

GitHub Actions needs these repo secrets for `deploy.yml`:

- `DEPLOY_HOST`
- `DEPLOY_USER` (the `deploy` user from infra-base)
- `DEPLOY_SSH_KEY` (private key; the box needs the matching public key
  authorized for `DEPLOY_USER`, separate from any key used for git pulls)
- `DEPLOY_SSH_PORT` (optional, defaults to 22)
- `DEPLOY_REPO_PATH` (where this repo is cloned on the box, e.g.
  `/home/deploy/game-servers`)
- `GAME_ENV_JSON` (used by `sync-env.yml` only, see below)

The workflow assumes this repo is already `git clone`d on the box and that
the deploy user can `git pull` it (its own deploy key, read-only, separate
from the GitHub Actions SSH key above). That clone isn't automated by
either repo — do it once by hand when you provision a box.

## Backup, restore, migration

`make backup` in a game directory stops that game's container, takes a
restic snapshot of its `DATA_DIR` tagged with the game's name, and
restarts it. `make restore` does the reverse and is safe to run against an
empty box — that's what makes it the migration path:

```
new box
  → run infra-base's playbook
  → clone this repo onto the box
  → run sync-env.yml for each game (writes .env from the GAME_ENV_JSON
    GitHub secret)
  → cd games/<game> && make restore && make up   (repeat per game)
  → flip DNS
```

**Why `.env` needed its own recovery path:** restic backs up
`/srv/games`, which is data only. It does not back up `.env` files, and
`.env` files are never committed to git — so on a fresh box, `make
restore` brings the world save back but there was nothing bringing the
port/tag/name config back. `sync-env.yml` closes that: every game's real
`.env` contents live in one GitHub repo secret, `GAME_ENV_JSON`, keyed by
game directory name. GitHub becomes the durable store instead of a
personal note somewhere. Two things to actually do, not just have
available:

- Update `GAME_ENV_JSON` by hand whenever you change a real `.env` value
  on the box, or the secret silently goes stale and migration restores
  old config.
- Test it: run `sync-env.yml` against a scratch path at least once and
  confirm the file lands correctly, the same way you're testing
  `make restore` below. An unexercised recovery path is not a recovery
  path.

## Testing

Runs in CI on every push/PR (`.github/workflows/test.yml`) and locally the
same way — all of it is plain Bash/Docker, nothing here needs a real box:

- `./test/run-shellcheck.sh` — shellchecks every `setup.sh` from its own
  directory (so `-x` resolves `../../lib/setup-common.sh` correctly) plus
  `lib/*.sh`.
- `./test/check-reserved-env-names.sh` — flags any `.env.example` variable
  that collides with a built-in Windows/POSIX env var name (how the
  `PUBLIC`/`SERVER_PUBLIC` bug happened — see `games/zomboid/README.md`'s
  Troubleshooting section). Run this whenever a new game's `.env.example`
  is added.
- `bats test/setup_common.bats test/setup_sh.bats` — unit/behavioral tests
  for `lib/setup-common.sh` and both `_template/setup.sh` and each game's
  `setup.sh`, against a stub `docker` on `PATH` (`test/fixtures/stub-bin`)
  so no real daemon is needed. Install bats-core locally with `git clone
  https://github.com/bats-core/bats-core.git && ./bats-core/install.sh
  ~/.local` (no sudo required) — do this inside WSL on Windows, not native
  PowerShell.
- `./test/integration-zomboid.sh` — the one test that needs a real Docker
  daemon: brings zomboid's real `docker-compose.yml` up against a synthetic
  `.env` and waits for the healthcheck. Slow (image pull + up to a few
  minutes of JVM boot) and the layer that actually catches
  `docker compose config` bugs like the `PUBLIC` collision — not something
  the bats suite can see, since that only exercises `setup.sh` in
  isolation.

On Windows, run all of this from WSL2 — it's the same Docker daemon Docker
Desktop already exposes there, so nothing needs a second install, and
results match the `ubuntu-latest` CI runner exactly (same Linux/Docker
stack, not something WSL is standing in for).

## Before you invite anyone

Test the restore path for real: delete a game's data directory on the box
and run `make restore` before there's a community depending on it not
being broken. This is called out because it's the step most likely to get
skipped under time pressure, and the step where a mistake is worst felt.

## What's not here yet

- The API and Discord bot: designed in `API.md`, not built
- Uptime check + Discord webhook alert: not part of this repo's scaffold;
  do it as an hour of work once the first game is live, don't defer it
