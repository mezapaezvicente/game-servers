# _template

Copy this directory to `games/<your-game>/` and fill in the placeholders.
Anything hardcoded that should have come from `.env` is a template bug —
fix the template, not just the copy.

## Steps for a new game

1. `cp -r _template games/<your-game>`
2. In `games/<your-game>/docker-compose.yml`:
   - replace the placeholder `image:` with the real image
   - replace the placeholder `healthcheck.test` with a real check
   - adjust the port protocol (tcp/udp/both) if this game isn't UDP-only
3. In `games/<your-game>/.env.example`:
   - set `GAME_NAME` to `<your-game>`
   - pick a `GAME_PORT` not already used — check `../../PORTS.md` first
   - set `DATA_DIR` to `/srv/games/<your-game>/data`
   - set `IMAGE_TAG` to a real pinned version, never `latest`
4. In `games/<your-game>/setup.sh`: copied as-is if the game only needs
   `GAME_NAME`/`IMAGE_TAG`/`GAME_PORT`/`DATA_DIR` and password/secret
   variables (it already prompts generically for any `*PASSWORD*`/`*SECRET*`
   variable). If the game needs extra validation — more ports, like
   `games/zomboid/setup.sh` — add that after the generic checks, but keep
   sourcing `../../lib/setup-common.sh` rather than duplicating its logging
   or `.env`-editing logic, same rule as `backup`/`restore` below.
5. Add the game and its port to `../../PORTS.md`.
6. Add the port to `ufw_allowed_ports` in the `infra-base` repo's
   `group_vars/all.yml` and re-run that playbook.
7. Add real values for `<your-game>` to the `GAME_ENV_JSON` GitHub secret
   (see `../README.md`), then run the `sync-env` workflow to write
   `games/<your-game>/.env` onto the box. Or do it by hand the first time
   with `./setup.sh` (or `cp .env.example .env`) on the box and fill in real
   values — but also add it to `GAME_ENV_JSON` afterward, or a lost box
   loses this game's config even though the world data is backed up.
8. `make up`

## Makefile targets

Every game exposes the same targets, all defined here and copied as-is:

- `make setup` — run that game's `setup.sh`: creates `.env` from
  `.env.example` if missing, prompts for secrets still at placeholder
  values, validates ports/`DATA_DIR`. For scripted/customized use:
  `make setup ARGS="--set GAME_PORT=27016 --yes"` (see `./setup.sh --help`).
- `make up` / `make down` — start/stop via docker compose
- `make logs` — tail container logs
- `make status` — `docker compose ps`
- `make backup` — stop, restic snapshot `DATA_DIR` tagged `GAME_NAME`, restart
- `make restore` — restic restore the latest snapshot for `GAME_NAME` into
  `DATA_DIR`; safe to run on an empty box, this is the migration path
- `make update` — backup, pull the pinned tag, recreate, health check

`backup`/`restore` call the shared scripts in `../../lib/`, and `setup` calls
that game's own `setup.sh`, which sources shared logging/`.env`-editing
helpers from `../../lib/setup-common.sh`. Don't duplicate that logic per
game. If a game needs different behavior (an in-game save/flush command
instead of stopping the container for backups, or extra `setup.sh`
validation), override just that target/script — the shared scripts stay
generic.

Also note: the Makefile uses `-include .env`, not `include .env` — a plain
`include` fails hard when `.env` doesn't exist yet, which would make
`make setup` (the thing that creates `.env`) unable to run on a fresh
checkout. Keep it as `-include` in any copy.
