#!/usr/bin/env bash
# Shellchecks every setup.sh (which sources ../../lib relatively) from its
# own directory with -x, plus lib/*.sh from the repo root. Run from
# anywhere; paths are resolved off this script's location.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

status=0

for game_setup in _template/setup.sh games/*/setup.sh; do
  dir="$(dirname "$game_setup")"
  echo "==> shellcheck -x $game_setup"
  (cd "$dir" && shellcheck -x setup.sh) || status=1
done

echo "==> shellcheck lib/*.sh"
shellcheck lib/*.sh || status=1

exit "$status"
