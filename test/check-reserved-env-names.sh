#!/usr/bin/env bash
# Flags any .env.example variable name that collides with a built-in
# Windows (or common POSIX) environment variable. Docker Compose gives
# shell environment variables precedence over .env file values, so a
# collision silently mis-resolves on that host instead of failing loudly —
# this is exactly what happened with PUBLIC (see todo.md, games/zomboid/
# README.md's Troubleshooting section). Catches the bug class before a new
# game's .env.example reintroduces it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Common built-in Windows env vars most likely to collide with a short,
# single-word .env key. Not exhaustive — extend if another collision shows
# up in practice.
RESERVED='^(PUBLIC|PATH|HOME|USER|USERNAME|USERPROFILE|USERDOMAIN|TEMP|TMP|APPDATA|LOCALAPPDATA|PROGRAMDATA|PROGRAMFILES|COMSPEC|SYSTEMROOT|SYSTEMDRIVE|WINDIR|OS|LOGONSERVER|HOMEDRIVE|HOMEPATH|NUMBER_OF_PROCESSORS|PROCESSOR_ARCHITECTURE|PSMODULEPATH|PATHEXT|ALLUSERSPROFILE)$'

status=0
for env_example in _template/.env.example games/*/.env.example; do
  while IFS='=' read -r key _; do
    [ -z "$key" ] && continue
    upper="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
    if [[ "$upper" =~ $RESERVED ]]; then
      echo "$env_example: variable '$key' collides with a reserved/built-in env var name — rename it (see games/zomboid/README.md's Troubleshooting section for why)." >&2
      status=1
    fi
  done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$env_example")
done

exit "$status"
