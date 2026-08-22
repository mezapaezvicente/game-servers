# Shared helpers for the bats suites in this directory. Sourced with
# `load test_helper` from each .bats file.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STUB_BIN="$REPO_ROOT/test/fixtures/stub-bin"

# copy_game_dir <relative-game-dir>
# Recreates the slice of the repo a game's setup.sh actually touches
# (lib/, PORTS.md, and the game dir itself) under BATS_TEST_TMPDIR, always
# placing the game two levels below the copied root (under games/<name>) —
# the same depth setup.sh's `../../lib`/`../../PORTS.md` paths expect.
# _template/ is never run in place (see _template/README.md step 1: it's
# always `cp -r`'d to games/<name>/ first), so this mirrors real usage for
# it too rather than testing a layout nobody actually runs.
# Never touches the real repo's .env.example/.env. Sets GAME_PATH to the
# copied game dir; run setup.sh from there.
copy_game_dir() {
  local rel="$1"
  local name
  name="$(basename "$rel")"
  local root="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$root/games"
  cp -r "$REPO_ROOT/lib" "$root/lib"
  cp "$REPO_ROOT/PORTS.md" "$root/PORTS.md"
  cp -r "$REPO_ROOT/$rel" "$root/games/$name"
  GAME_PATH="$root/games/$name"
}

# stub_docker
# Prepends the stub docker/docker-compose to PATH for the current test.
stub_docker() {
  PATH="$STUB_BIN:$PATH"
}

# env_value <env-file> <KEY>
# Reads KEY's value out of a .env file for assertions (last match wins,
# same as setup-common.sh's env_get).
env_value() {
  local file="$1" key="$2"
  sed -n "s/^${key}=//p" "$file" | tail -n1
}
