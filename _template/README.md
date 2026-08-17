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
4. Add the game and its port to `../../PORTS.md`.
5. Add the port to `ufw_allowed_ports` in the `infra-base` repo's
   `group_vars/all.yml` and re-run that playbook.
6. Add real values for `<your-game>` to the `GAME_ENV_JSON` GitHub secret
   (see `../README.md`), then run the `sync-env` workflow to write
   `games/<your-game>/.env` onto the box. Or do it by hand the first time
   with `cp .env.example .env` on the box and fill in real values — but
   also add it to `GAME_ENV_JSON` afterward, or a lost box loses this
   game's config even though the world data is backed up.
7. `make up`

## Makefile targets

Every game exposes the same targets, all defined here and copied as-is:

- `make up` / `make down` — start/stop via docker compose
- `make logs` — tail container logs
- `make status` — `docker compose ps`
- `make backup` — stop, restic snapshot `DATA_DIR` tagged `GAME_NAME`, restart
- `make restore` — restic restore the latest snapshot for `GAME_NAME` into
  `DATA_DIR`; safe to run on an empty box, this is the migration path
- `make update` — backup, pull the pinned tag, recreate, health check

`backup` and `restore` call the shared scripts in `../../lib/`. Don't
duplicate that logic per game. If a game needs different backup behavior
(an in-game save/flush command instead of stopping the container), override
the `backup` target in that game's own Makefile — the shared script stays
generic.
