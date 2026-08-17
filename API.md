# API design

This is a design document. Nothing here is built yet. It exists so the
shape is decided before the bot exists, not discovered while writing it.

## Why an API instead of the bot shelling out

The Discord bot is the first client, not the only one, and not the thing
with privileges. Anything that can restart a container on this box is
effectively root on that box — it can bind-mount `/`, read every secret in
every other game's `.env`, and reach the Docker socket if one is handed to
it. A Discord bot's job is "listen to messages and call an API." Its trust
boundary should stop there.

So: the bot talks to a local API over HTTP. The API is the only thing that
runs `make` targets. The bot never touches Docker, SSH, or the filesystem
on the box directly.

```
Discord message → bot → HTTP request → API (on the box) → make <target> in games/<game>/
```

## Two hard rules

**1. Closed verb list.** No endpoint ever accepts a free-form command
string. The full set of verbs, forever, unless this doc is revised:

- `status` — is the container up, how long has it been running
- `start`
- `stop`
- `restart`
- `backup-now` — runs `make backup` for the game
- `logs-tail` — last N lines, N capped server-side
- `players` — best-effort player count/list if the game image exposes one

That's it. Adding a verb means editing this document and the API's
whitelist together, not passing a new string through an existing endpoint.
If a future need doesn't fit one of these seven, it's a sign the need
should be met a different way (SSH in and do it by hand), not a reason to
add `exec`.

**2. The API is not root, and neither is its caller.** The API process runs
as a dedicated system user that:

- is not `deploy`, and is not in the `docker` group
- cannot reach `/var/run/docker.sock`
- can run exactly one command shape: `make <whitelisted-target>` inside
  one of `games/<game>/`, via a narrow `sudo` rule (or equivalent) that
  names the allowed targets explicitly — not "this user can sudo make"
- has no shell access to anything outside that

Concretely, on the box this looks like a sudoers entry (or a small setuid
wrapper, TBD at build time) that permits e.g.:

```
api ALL=(deploy) NOPASSWD: /usr/bin/make -C /home/deploy/game-servers/games/* up, \
                            /usr/bin/make -C /home/deploy/game-servers/games/* down, \
                            /usr/bin/make -C /home/deploy/game-servers/games/* status, \
                            /usr/bin/make -C /home/deploy/game-servers/games/* backup
```

`restart` = `down` then `up` at the API layer, not a new Make target.
`logs-tail` and `players` read, they don't invoke Make at all — `logs-tail`
runs `docker compose logs --tail=N` scoped the same restrictive way,
`players` is per-game (see below).

Whatever the exact mechanism ends up being, the rule doesn't change: the
API can cause exactly seven things to happen, all of them already defined
in `games/*/Makefile`, and nothing else.

## Verbs

| Verb         | Maps to                              | Notes |
|--------------|----------------------------------------|-------|
| `status`     | `make status` (+ uptime)              | read-only |
| `start`      | `make up`                              | |
| `stop`       | `make down`                            | |
| `restart`    | `make down && make up`                 | not `update` — restart never changes the image tag |
| `backup-now` | `make backup`                          | synchronous; can take a while, API should respond and let the bot poll or follow up |
| `logs-tail`  | `docker compose logs --tail=N`         | N capped (e.g. 200) server-side regardless of what's requested |
| `players`    | game-specific, best-effort             | not every placeholder/game image exposes this; return "unknown" rather than guessing |

Every request identifies a `game` (one of the directories under `games/`).
There is no "all games" verb — the closed list operates on one game at a
time, which keeps the blast radius of a single bad request to one game.

`update` (pull a new pinned tag) is deliberately **not** in the API. That's
a deploy-time action gated by a PR touching `.env`, reviewed by a human,
run by CI or by hand — not a Discord command. Same for `restore`: it's
destructive and rare enough that it should require being on the box.

## Auth

Discord roles are the auth system — the community already lives there, so
this reuses trust that already exists instead of inventing a second one.
The bot checks the caller's Discord role before it makes the API call at
all; the API also checks a shared secret / bearer token from the bot so it
isn't just trusting network position. Only one Discord bot instance talks
to the API for now, since access is only me.

## Future web client

The bot is the first client, not a hardcoded one. A web client (something
I or eventually other admins could use from a browser instead of Discord)
is a second consumer of the same seven verbs, same auth pattern adapted to
whatever session mechanism the web client uses. When that gets built, the
API itself shouldn't need to change — only a new client. If building the
web client requires adding a verb, that's a sign the API design was wrong,
not that the web client is special.

## Explicitly out of scope for this document

- Transport details (REST vs gRPC vs a Unix socket) — undecided, doesn't
  affect the two hard rules above
- The bot's command syntax in Discord
- Rate limiting specifics
- Multi-admin auth (only one person has access today, see the repo
  README)
