# zomboid

Project Zomboid dedicated server, Build 42, using
[`danixu86/project-zomboid-dedicated-server`](https://hub.docker.com/r/danixu86/project-zomboid-dedicated-server)
(source: https://github.com/Danixu/project-zomboid-server-docker) — actively
maintained, tags track the game's own build number.

See `../../_template/README.md` for what every Makefile target does and
`../../PORTS.md` for the ports this reserves.

## Quick start

1. `./setup.sh` — creates `.env` from `.env.example`, prompts (masked) for
   `ADMIN_PASSWORD`/`RCON_PASSWORD` if they're still placeholders, validates
   ports and `DATA_DIR`, and prints a config summary. Run `./setup.sh --help`
   for all options, or see "Customizing from the command line" below.
   Equivalent Makefile form: `make setup`.
2. `make up`
3. `make logs` until you see the server finish initializing (JVM boot is
   slow, commonly 1-3+ minutes).

Manual fallback, if you'd rather edit `.env` by hand instead of using
`setup.sh`: `cp .env.example .env` and fill in real values yourself — at
minimum change `ADMIN_PASSWORD` and `RCON_PASSWORD`.

## Customizing from the command line

`./setup.sh --set KEY=VALUE` overrides any variable in `.env` (repeatable,
works whether `.env` exists yet or not). A few examples:

```sh
# Change the game port
./setup.sh --set GAME_PORT=16265

# Give the JVM more heap for a heavily modded server
./setup.sh --set MEMORY=8192m

# Add a Workshop mod (IDs are semicolon-separated if you add more than one)
./setup.sh --set MOD_IDS=2559634787 --set WORKSHOP_IDS=2559634787

# Fully non-interactive, e.g. from a provisioning script — skips all
# prompts and uses whatever is already in .env / just passed via --set
./setup.sh --set GAME_PORT=16265 --set MEMORY=8192m --yes
```

`--yes` skips the interactive password prompts; if `ADMIN_PASSWORD` or
`RCON_PASSWORD` are still at their placeholder values when it does, the
script logs a loud warning instead of silently shipping insecure defaults —
watch for that in scripted runs.

## Ports

Zomboid needs five, not the template's usual one — see `.env.example` for
the full list with explanations, and `../../PORTS.md` for the box-wide
registry. `RCON_PORT` (27015/tcp) is the admin console: make sure
`infra-base`'s firewall only opens it to admin IPs, never `0.0.0.0`.

## Known quirks (documented, not engineered around)

- **`ADMIN_PASSWORD` is only required on first boot.** The image logs every
  launch argument in clear text on every start, so once the server has come
  up successfully at least once, blank `ADMIN_PASSWORD` out in the real
  `.env` on the box. The admin account itself isn't affected.
- **Mods take three restarts to fully apply.** Setting `MOD_IDS` /
  `WORKSHOP_IDS` and running `make up` installs the mods on the *second*
  start after that and their maps on the *third* — this is how the image's
  entrypoint script works, not a bug. After changing mods, plan on
  `docker compose restart` twice more, watching `make logs` each time.
- **`make backup`'s stop-based snapshot does NOT flush saves cleanly —
  confirmed by testing.** `../../lib/backup.sh` sends SIGTERM via `docker
  compose stop` before snapshotting `DATA_DIR`. The image's entrypoint chain
  is `entry.sh` (PID 1, no trap) → `su` → `sh` → `start-server.sh` → the
  actual game process, four levels deep with no `exec`. `docker compose
  stop` kills the whole container in a few seconds with exit code 137
  (SIGKILL) and no save/shutdown log lines — the JVM never gets a chance to
  flush. Until fixed, treat `make backup`/`make update` snapshots as
  potentially missing the last few minutes of an in-progress save. The fix
  is an RCON `save` command before stopping — override just the `backup`
  target in this file per `_template/README.md`'s guidance, not the shared
  script. No RCON CLI is bundled in the image today, so this needs adding
  one first.

## Troubleshooting

- **`setup.sh` says `docker` or `docker compose` not found.** Install
  Docker Engine + the compose plugin
  (https://docs.docker.com/engine/install/), not the standalone `docker-compose`
  v1 — this repo uses `docker compose` (v2, space, no hyphen) everywhere.
- **`setup.sh` warns a port "doesn't appear in `../../PORTS.md`".** Not
  fatal, but means the port isn't registered as reserved on this box. Add it
  to `../../PORTS.md` before deploying, so a future game doesn't collide
  with it.
- **`setup.sh` fails to create `DATA_DIR` (permission denied).** It prints
  the exact `sudo mkdir -p ... && sudo chown ...` command to run — `/srv/games`
  is typically root-owned until `infra-base`'s `games_dir` role has run on
  the box.
- **`make update` reports `unhealthy` or times out.** The health check
  (`docker-compose.yml`) waits for `RCON_PORT` to start accepting TCP
  connections, which only happens once the server core has finished
  initializing — a timeout after several minutes usually means the new
  image tag is actually broken, not just slow. `make update`'s own output
  prints the rollback steps: set `IMAGE_TAG` back in `.env`, `make update`
  again, then `make restore` too if the bad version wrote data you don't
  want. Check `make logs` for the underlying Java stack trace first.
- **Mods don't show up in-game after the first `make up`.** Expected — see
  "Mods take three restarts to fully apply" above. Not a bug.
- **Players report they can connect directly but not via the in-game
  browser (or vice versa).** Usually a `PUBLIC` or port mismatch — double
  check `PUBLIC=true` if you want it listed, and that all 5 ports in
  `.env` are actually open in `infra-base`'s firewall, not just `GAME_PORT`.
- **RCON port reachable from outside admin IPs.** This is a firewall
  misconfiguration in `infra-base`, not this repo — `27015/tcp` must only
  be opened to admin IPs in `ufw_allowed_ports`, never `0.0.0.0`.
- **Where do logs actually live?** `make logs` (`docker compose logs -f`)
  is the container's stdout/stderr, which is where this image writes
  everything, including the Java process's own log lines. There's no
  separate log file to `tail` on the host outside of that.
- **Testing locally on Windows: `docker compose config` shows
  `PUBLIC: C:\Users\Public` instead of `.env`'s value.** `PUBLIC` is a
  built-in Windows environment variable, and Docker Compose gives shell
  environment variables precedence over `.env` file values. Doesn't affect
  the Linux production box (no such variable there), but locally you need
  `$env:PUBLIC = "false"` (or whatever `.env` has) before `docker compose`
  commands, or it silently lists the server publicly regardless of what
  `.env` says.

## Before relying on this

Test the restore path for real (`../../README.md`'s "Before you invite
anyone" section) before a community depends on it. Also outside this repo,
still required before this is actually reachable:

- Open all 5 ports (see `.env.example`) in `infra-base`'s
  `group_vars/all.yml` `ufw_allowed_ports` and re-run that playbook.
- Add this game's real `.env` values to the `GAME_ENV_JSON` GitHub secret
  (see `../../README.md`) so a lost box doesn't lose this config even
  though the world data is backed up separately.
