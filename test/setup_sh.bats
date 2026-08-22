# Behavioral tests for setup.sh, run against both _template/ (the pattern
# every new game copies) and games/zomboid/ (the one real, extended
# example — 5 ports instead of 1, named secret prompts). Each test copies
# just the slice of the repo setup.sh touches into a temp dir (see
# test_helper.bash's copy_game_dir) so nothing here ever writes to the
# real .env.example or leaves a stray .env in the actual repo.
load test_helper

setup() {
  stub_docker
}

# ---- _template/setup.sh ----

@test "[template] fresh run creates .env from .env.example" {
  copy_game_dir _template
  cd "$GAME_PATH"
  run ./setup.sh --yes --set DATA_DIR="$BATS_TEST_TMPDIR/data"
  [ "$status" -eq 0 ]
  [ -f .env ]
  [[ "$output" == *"configuration valid"* ]]
}

@test "[template] --set overrides a value in the generated .env" {
  copy_game_dir _template
  cd "$GAME_PATH"
  run ./setup.sh --yes --set DATA_DIR="$BATS_TEST_TMPDIR/data" --set GAME_PORT=27016
  [ "$status" -eq 0 ]
  [ "$(env_value .env GAME_PORT)" = "27016" ]
}

@test "[template] re-run applies new overrides on top of the existing .env" {
  copy_game_dir _template
  cd "$GAME_PATH"
  ./setup.sh --yes --set DATA_DIR="$BATS_TEST_TMPDIR/data" >/dev/null
  run ./setup.sh --yes --set GAME_PORT=27017
  [ "$status" -eq 0 ]
  [[ "$output" == *"found existing .env"* ]]
  [ "$(env_value .env GAME_PORT)" = "27017" ]
  # DATA_DIR from the first run must still be there — re-run doesn't reset it.
  [ "$(env_value .env DATA_DIR)" = "$BATS_TEST_TMPDIR/data" ]
}

@test "[template] invalid GAME_PORT fails validation with exit 2" {
  copy_game_dir _template
  cd "$GAME_PATH"
  run ./setup.sh --yes --set DATA_DIR="$BATS_TEST_TMPDIR/data" --set GAME_PORT=not-a-port
  [ "$status" -eq 2 ]
}

@test "[template] an unwritable DATA_DIR fails validation with exit 2 and a sudo hint" {
  copy_game_dir _template
  cd "$GAME_PATH"
  # A regular file where a directory is expected makes mkdir -p fail.
  touch "$BATS_TEST_TMPDIR/blocked"
  run ./setup.sh --yes --set DATA_DIR="$BATS_TEST_TMPDIR/blocked/data"
  [ "$status" -eq 2 ]
  [[ "$output" == *"sudo mkdir"* ]]
}

@test "[template] --set with no KEY=VALUE fails with exit 1" {
  copy_game_dir _template
  cd "$GAME_PATH"
  run ./setup.sh --yes --set DATA_DIR="$BATS_TEST_TMPDIR/data" --set not-a-kv-pair
  [ "$status" -eq 1 ]
}

@test "[template] --set with a lowercase key fails with exit 1" {
  copy_game_dir _template
  cd "$GAME_PATH"
  run ./setup.sh --yes --set DATA_DIR="$BATS_TEST_TMPDIR/data" --set lower_case=1
  [ "$status" -eq 1 ]
}

@test "[template] missing docker fails with exit 1" {
  copy_game_dir _template
  cd "$GAME_PATH"
  PATH="/usr/bin:/bin"
  run ./setup.sh --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"docker"* ]]
}

# ---- games/zomboid/setup.sh ----

zomboid_dir() { echo "games/zomboid"; }

@test "[zomboid] fresh run creates .env and warns on placeholder passwords" {
  copy_game_dir "$(zomboid_dir)"
  cd "$GAME_PATH"
  run ./setup.sh --yes --set DATA_DIR="$BATS_TEST_TMPDIR/data"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ADMIN_PASSWORD is still the default placeholder"* ]]
  [[ "$output" == *"RCON_PASSWORD is still the default placeholder"* ]]
}

@test "[zomboid] setting ADMIN_PASSWORD clears its placeholder warning and masks it in the summary" {
  copy_game_dir "$(zomboid_dir)"
  cd "$GAME_PATH"
  run ./setup.sh --yes --set DATA_DIR="$BATS_TEST_TMPDIR/data" --set ADMIN_PASSWORD=hunter2
  [ "$status" -eq 0 ]
  [[ "$output" != *"ADMIN_PASSWORD is still the default placeholder"* ]]
  [[ "$output" == *"ADMIN_PASSWORD  ********"* ]]
  [[ "$output" != *"hunter2"* ]]
}

@test "[zomboid] validates all 5 ports, not just GAME_PORT" {
  copy_game_dir "$(zomboid_dir)"
  cd "$GAME_PATH"
  run ./setup.sh --yes --set DATA_DIR="$BATS_TEST_TMPDIR/data" --set STEAM_PORT1=not-a-port
  [ "$status" -eq 2 ]
}

@test "[zomboid] a port not registered in PORTS.md warns but still succeeds" {
  copy_game_dir "$(zomboid_dir)"
  cd "$GAME_PATH"
  run ./setup.sh --yes --set DATA_DIR="$BATS_TEST_TMPDIR/data" --set GAME_PORT=59999
  [ "$status" -eq 0 ]
  [[ "$output" == *"doesn't appear in ../../PORTS.md"* ]]
}

@test "[zomboid] missing 'docker compose' plugin fails with exit 1" {
  copy_game_dir "$(zomboid_dir)"
  cd "$GAME_PATH"
  mkdir -p "$BATS_TEST_TMPDIR/no-compose-bin"
  cat > "$BATS_TEST_TMPDIR/no-compose-bin/docker" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "compose" ] && exit 1
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/no-compose-bin/docker"
  PATH="$BATS_TEST_TMPDIR/no-compose-bin:/usr/bin:/bin"
  run ./setup.sh --yes --set DATA_DIR="$BATS_TEST_TMPDIR/data"
  [ "$status" -eq 1 ]
  [[ "$output" == *"compose"* ]]
}
