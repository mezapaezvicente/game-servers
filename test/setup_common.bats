load test_helper

setup() {
  source "$REPO_ROOT/lib/setup-common.sh"
  ENV_FILE="$BATS_TEST_TMPDIR/.env"
}

@test "env_get returns unset for a missing file" {
  result="$(env_get "$BATS_TEST_TMPDIR/does-not-exist" KEY)"
  [ -z "$result" ]
}

@test "env_get returns empty for an unset key" {
  printf 'OTHER=1\n' > "$ENV_FILE"
  result="$(env_get "$ENV_FILE" KEY)"
  [ -z "$result" ]
}

@test "env_get reads a set key" {
  printf 'KEY=value\n' > "$ENV_FILE"
  result="$(env_get "$ENV_FILE" KEY)"
  [ "$result" = "value" ]
}

@test "env_get returns the last match when a key is duplicated" {
  printf 'KEY=first\nKEY=second\n' > "$ENV_FILE"
  result="$(env_get "$ENV_FILE" KEY)"
  [ "$result" = "second" ]
}

@test "env_set appends a new key that doesn't exist yet" {
  printf 'OTHER=1\n' > "$ENV_FILE"
  env_set "$ENV_FILE" KEY value
  [ "$(env_get "$ENV_FILE" KEY)" = "value" ]
  [ "$(env_get "$ENV_FILE" OTHER)" = "1" ]
}

@test "env_set replaces an existing key in place rather than appending" {
  printf 'KEY=old\nOTHER=1\n' > "$ENV_FILE"
  env_set "$ENV_FILE" KEY new
  [ "$(wc -l < "$ENV_FILE")" -eq 2 ]
  [ "$(env_get "$ENV_FILE" KEY)" = "new" ]
}

@test "env_set handles values containing sed-special characters" {
  printf 'KEY=old\n' > "$ENV_FILE"
  env_set "$ENV_FILE" KEY 'a|b&c\d'
  [ "$(env_get "$ENV_FILE" KEY)" = 'a|b&c\d' ]
}

@test "mask returns (blank) for an empty value" {
  result="$(mask "")"
  [ "$result" = "(blank)" ]
}

@test "mask returns a fixed-length mask for a non-empty value" {
  result="$(mask "supersecret")"
  [ "$result" = "********" ]
}

@test "require_cmd succeeds for a command on PATH" {
  run require_cmd bash "unreachable hint"
  [ "$status" -eq 0 ]
}

@test "require_cmd exits 1 with the hint for a missing command" {
  run require_cmd definitely-not-a-real-command "install it from https://example.invalid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"definitely-not-a-real-command"* ]]
  [[ "$output" == *"https://example.invalid"* ]]
}
