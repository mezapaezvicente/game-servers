#!/usr/bin/env bash
set -euo pipefail

# Usage: backup.sh <game-name> <data-dir>
#
# Must be run from the game's own directory (so `docker compose` targets
# the right project). Called by `make backup` and by `make update` before
# it pulls a new tag.
#
# Stops the container for a filesystem-consistent copy, snapshots
# <data-dir> into the shared restic repository tagged with <game-name>,
# then restarts the container.
#
# If a game has an in-game save/flush command and you'd rather not stop the
# container for backups, override the `backup` target in that game's
# Makefile to send the flush command instead of calling this script. Don't
# special-case that here — this script stays generic.

GAME_NAME="${1:?usage: backup.sh <game-name> <data-dir>}"
DATA_DIR="${2:?usage: backup.sh <game-name> <data-dir>}"
RESTIC_ENV_FILE="${RESTIC_ENV_FILE:-/etc/restic/restic.env}"

if [ ! -f "$RESTIC_ENV_FILE" ]; then
  echo "backup.sh: $RESTIC_ENV_FILE not found. Run infra-base's playbook on this box first." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$RESTIC_ENV_FILE"

echo "==> [$GAME_NAME] stopping container for a consistent backup"
docker compose stop

echo "==> [$GAME_NAME] snapshotting $DATA_DIR"
restic backup "$DATA_DIR" --tag "$GAME_NAME" --tag manual

echo "==> [$GAME_NAME] restarting container"
docker compose start

echo "==> [$GAME_NAME] backup complete"
