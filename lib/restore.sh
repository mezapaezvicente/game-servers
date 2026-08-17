#!/usr/bin/env bash
set -euo pipefail

# Usage: restore.sh <game-name> <data-dir> [snapshot]
#
# snapshot defaults to "latest". Restores the most recent restic snapshot
# tagged <game-name> into <data-dir>, overwriting what's there.
#
# Safe to run against an empty box before the container has ever been
# started. This is the migration path:
#   1. provision a new box, run infra-base's playbook against it
#   2. clone this repo onto the box, put .env files in place (see the
#      "gap" note in the top-level README — .env is not backed up)
#   3. cd games/<game> && make restore && make up
#   4. flip DNS

GAME_NAME="${1:?usage: restore.sh <game-name> <data-dir> [snapshot]}"
DATA_DIR="${2:?usage: restore.sh <game-name> <data-dir> [snapshot]}"
SNAPSHOT="${3:-latest}"
RESTIC_ENV_FILE="${RESTIC_ENV_FILE:-/etc/restic/restic.env}"

if [ ! -f "$RESTIC_ENV_FILE" ]; then
  echo "restore.sh: $RESTIC_ENV_FILE not found. Run infra-base's playbook on this box first." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$RESTIC_ENV_FILE"

echo "==> [$GAME_NAME] stopping container if it's running"
docker compose stop 2>/dev/null || true

mkdir -p "$DATA_DIR"

echo "==> [$GAME_NAME] restoring snapshot '$SNAPSHOT' tagged $GAME_NAME into $DATA_DIR"
RESTORE_TARGET="$(mktemp -d)"
trap 'rm -rf "$RESTORE_TARGET"' EXIT

restic restore "$SNAPSHOT" --tag "$GAME_NAME" --target "$RESTORE_TARGET"

# restic restores under $RESTORE_TARGET/<original absolute path>.
SNAPSHOT_DATA_DIR="$RESTORE_TARGET$(realpath -m "$DATA_DIR")"
if [ ! -d "$SNAPSHOT_DATA_DIR" ]; then
  echo "restore.sh: expected restored path $SNAPSHOT_DATA_DIR not found in snapshot" >&2
  exit 1
fi

rm -rf "${DATA_DIR:?}"/*
cp -a "$SNAPSHOT_DATA_DIR"/. "$DATA_DIR"/

echo "==> [$GAME_NAME] restore complete. Run 'make up' to start the container."
