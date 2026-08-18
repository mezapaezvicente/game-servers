#!/usr/bin/env bash
# Guided + scriptable setup for this game server. Creates .env from
# .env.example if missing, applies any --set overrides, prompts for any
# PASSWORD/SECRET variable still left at its .env.example placeholder value
# (unless --yes), validates the result, and prints what to run next.
#
# Copied from _template/ when scaffolding a new game — see
# _template/README.md. Zomboid's games/zomboid/setup.sh is a worked example
# that adds game-specific validation (5 ports instead of 1, admin/RCON
# prompts) on top of this same shape. Don't duplicate lib/setup-common.sh's
# logging/env-editing logic here or in any game's copy — source it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

GAME_NAME="$(basename "$(pwd)")"
# shellcheck source=../lib/setup-common.sh
source ../../lib/setup-common.sh
setup_trap_errors

ENV_FILE=.env
ENV_EXAMPLE=.env.example
YES=0
declare -a OVERRIDES=()

usage() {
  cat <<'EOF'
Usage: ./setup.sh [options]

Options:
  --set KEY=VALUE   Override an .env variable. Repeatable.
  --yes             Non-interactive: skip prompts, keep/accept current or
                     example values instead of asking for secrets.
  --force           Skip the confirmation before touching an existing .env.
  -h, --help        Show this help and exit.

Examples:
  ./setup.sh
      Interactive first-time setup: copies .env.example to .env and prompts
      for any PASSWORD/SECRET variable still at its placeholder value.

  ./setup.sh --set GAME_PORT=27016
      Change the game port on an existing or new .env.

  ./setup.sh --yes
      Fully non-interactive: use defaults/existing values as-is, no prompts.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --set)
      [ $# -ge 2 ] || { log_error "--set requires a KEY=VALUE argument"; exit 1; }
      OVERRIDES+=("$2")
      shift 2
      ;;
    --set=*)
      OVERRIDES+=("${1#--set=}")
      shift
      ;;
    --yes)
      YES=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "unknown option: $1 (see --help)"
      exit 1
      ;;
  esac
done
FORCE="${FORCE:-0}"

log_info "checking prerequisites"
require_cmd docker "Install Docker: https://docs.docker.com/engine/install/"
if ! docker compose version >/dev/null 2>&1; then
  log_error "'docker compose' (v2 plugin) not available."
  log_error "  Install the compose plugin: https://docs.docker.com/compose/install/linux/"
  exit 1
fi

if [ ! -f "$ENV_EXAMPLE" ]; then
  log_error "$ENV_EXAMPLE not found — run this script from the game's own directory"
  exit 1
fi

if [ -f "$ENV_FILE" ]; then
  log_info "found existing $ENV_FILE, applying overrides on top of it"
else
  if [ "$FORCE" -ne 1 ] && [ "$YES" -ne 1 ] && [ -t 0 ]; then
    read -r -p "No $ENV_FILE yet — create it from $ENV_EXAMPLE? [Y/n] " reply
    case "$reply" in [nN]*) log_info "aborted"; exit 0 ;; esac
  fi
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  log_success "created $ENV_FILE from $ENV_EXAMPLE"
fi

for kv in "${OVERRIDES[@]+"${OVERRIDES[@]}"}"; do
  key="${kv%%=*}"
  value="${kv#*=}"
  if [ "$key" = "$kv" ]; then
    log_error "--set value '$kv' is not KEY=VALUE"
    exit 1
  fi
  if ! [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
    log_error "--set key '$key' doesn't look like an env var name (expected UPPER_SNAKE_CASE)"
    exit 1
  fi
  old="$(env_get "$ENV_FILE" "$key")"
  env_set "$ENV_FILE" "$key" "$value"
  log_info "$key: '${old}' -> '${value}'"
done

# Prompt for any PASSWORD/SECRET variable still at its .env.example
# placeholder, unless --yes. Generic across every game's .env shape.
# Collected into an array first (not a `while read < file` loop) so the
# interactive `read -s -p` prompts below still read from the real terminal
# instead of the .env.example file descriptor.
mapfile -t _secret_lines < <(grep -E '^[A-Za-z_]*(PASSWORD|SECRET)[A-Za-z_]*=' "$ENV_EXAMPLE" || true)
for line in "${_secret_lines[@]+"${_secret_lines[@]}"}"; do
  key="${line%%=*}"
  placeholder="${line#*=}"
  current="$(env_get "$ENV_FILE" "$key")"
  [ "$current" = "$placeholder" ] || continue
  if [ "$YES" -eq 1 ] || [ ! -t 0 ]; then
    log_warn "$key is still the placeholder value — pass --set $key=... to change it."
    continue
  fi
  value=""
  confirm=""
  while true; do
    read -r -s -p "Set $key (leave blank to keep placeholder): " value
    echo
    if [ -z "$value" ]; then
      log_warn "$key left at placeholder value"
      break
    fi
    read -r -s -p "Confirm $key: " confirm
    echo
    if [ "$value" = "$confirm" ]; then
      env_set "$ENV_FILE" "$key" "$value"
      log_success "$key updated"
      break
    fi
    log_warn "values didn't match, try again"
  done
done

log_info "validating configuration"

DATA_DIR="$(env_get "$ENV_FILE" DATA_DIR)"
if [ -z "$DATA_DIR" ]; then
  log_error "DATA_DIR is not set in $ENV_FILE"
  exit 2
fi
if ! mkdir -p "$DATA_DIR" 2>/dev/null; then
  log_error "could not create DATA_DIR ($DATA_DIR) — likely a permissions issue."
  log_error "  Fix: sudo mkdir -p '$DATA_DIR' && sudo chown \$USER '$DATA_DIR'"
  exit 2
fi

GAME_PORT_VAL="$(env_get "$ENV_FILE" GAME_PORT)"
if ! [[ "$GAME_PORT_VAL" =~ ^[0-9]+$ ]]; then
  log_error "GAME_PORT is not a valid port number: '$GAME_PORT_VAL'"
  exit 2
fi
if ! grep -q "$GAME_PORT_VAL" ../../PORTS.md 2>/dev/null; then
  log_warn "port $GAME_PORT_VAL (GAME_PORT) doesn't appear in ../../PORTS.md — register it there before deploying, to avoid colliding with another game on this box."
fi

log_success "configuration valid"
echo
echo "  GAME_NAME  $(env_get "$ENV_FILE" GAME_NAME)"
echo "  IMAGE_TAG  $(env_get "$ENV_FILE" IMAGE_TAG)"
echo "  DATA_DIR   $DATA_DIR"
echo "  GAME_PORT  $GAME_PORT_VAL"
echo

log_info "next steps: make up, then make logs"
log_info "See README.md's Troubleshooting section if anything above looks wrong."
