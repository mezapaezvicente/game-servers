#!/usr/bin/env bash
# Guided + scriptable setup for the zomboid game server. Creates .env from
# .env.example if missing, applies any --set overrides, prompts for secrets
# left at their placeholder values (unless --yes), validates the result, and
# prints exactly what to run next. Safe to re-run.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

GAME_NAME="zomboid"
# shellcheck source=../../lib/setup-common.sh
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
      for admin/RCON/server passwords.

  ./setup.sh --set GAME_PORT=16265 --set MEMORY=8192m
      Change the game port and JVM heap size on an existing or new .env.

  ./setup.sh --set MOD_IDS=2559634787 --set WORKSHOP_IDS=2559634787 --yes
      Add a mod non-interactively (e.g. from a provisioning script). Reminder:
      mods need two more restarts after this to fully register (see README).

  ./setup.sh --yes
      Fully non-interactive: use defaults/existing values as-is, no prompts.
      Loudly warns if ADMIN_PASSWORD/RCON_PASSWORD are still placeholders.
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
  log_error "$ENV_EXAMPLE not found — run this script from game-servers/games/zomboid/"
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
  if [[ "$key" =~ (PASSWORD|SECRET) ]]; then
    log_info "$key: $(mask "$old") -> $(mask "$value")"
  else
    log_info "$key: '${old}' -> '${value}'"
  fi
done

# Prompt for secrets still at their .env.example placeholder, unless --yes.
prompt_secret_if_placeholder() {
  local key="$1" placeholder="$2"
  local current
  current="$(env_get "$ENV_FILE" "$key")"
  [ "$current" = "$placeholder" ] || return 0
  if [ "$YES" -eq 1 ] || [ ! -t 0 ]; then
    log_warn "$key is still the placeholder value '$placeholder' — pass --set $key=... to change it."
    return 0
  fi
  local value confirm
  while true; do
    read -r -s -p "Set $key (leave blank to keep placeholder): " value
    echo
    if [ -z "$value" ]; then
      log_warn "$key left at placeholder value '$placeholder'"
      return 0
    fi
    read -r -s -p "Confirm $key: " confirm
    echo
    [ "$value" = "$confirm" ] && break
    log_warn "values didn't match, try again"
  done
  env_set "$ENV_FILE" "$key" "$value"
  log_success "$key updated"
}

prompt_secret_if_placeholder ADMIN_PASSWORD changeme
prompt_secret_if_placeholder RCON_PASSWORD changeme_rcon

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

for port_var in GAME_PORT DIRECT_PORT STEAM_PORT1 STEAM_PORT2 RCON_PORT; do
  val="$(env_get "$ENV_FILE" "$port_var")"
  if ! [[ "$val" =~ ^[0-9]+$ ]]; then
    log_error "$port_var is not a valid port number: '$val'"
    exit 2
  fi
  if ! grep -q "$val" ../../PORTS.md 2>/dev/null; then
    log_warn "port $val ($port_var) doesn't appear in ../../PORTS.md — register it there before deploying, to avoid colliding with another game on this box."
  fi
done

ADMIN_PASSWORD_VAL="$(env_get "$ENV_FILE" ADMIN_PASSWORD)"
RCON_PASSWORD_VAL="$(env_get "$ENV_FILE" RCON_PASSWORD)"
[ "$ADMIN_PASSWORD_VAL" = "changeme" ] && log_warn "ADMIN_PASSWORD is still the default placeholder."
[ "$RCON_PASSWORD_VAL" = "changeme_rcon" ] && log_warn "RCON_PASSWORD is still the default placeholder."

log_success "configuration valid"
echo
echo "  GAME_NAME       $(env_get "$ENV_FILE" GAME_NAME)"
echo "  IMAGE_TAG       $(env_get "$ENV_FILE" IMAGE_TAG)"
echo "  DATA_DIR        $DATA_DIR"
echo "  GAME_PORT       $(env_get "$ENV_FILE" GAME_PORT)/udp"
echo "  DIRECT_PORT     $(env_get "$ENV_FILE" DIRECT_PORT)/udp"
echo "  STEAM_PORT1     $(env_get "$ENV_FILE" STEAM_PORT1)/udp"
echo "  STEAM_PORT2     $(env_get "$ENV_FILE" STEAM_PORT2)/udp"
echo "  RCON_PORT       $(env_get "$ENV_FILE" RCON_PORT)/tcp (admin IPs only!)"
echo "  SERVER_NAME     $(env_get "$ENV_FILE" SERVER_NAME)"
echo "  ADMIN_PASSWORD  $(mask "$ADMIN_PASSWORD_VAL")"
echo "  RCON_PASSWORD   $(mask "$RCON_PASSWORD_VAL")"
echo "  SERVER_PASSWORD $(mask "$(env_get "$ENV_FILE" SERVER_PASSWORD)")"
echo "  MOD_IDS         $(env_get "$ENV_FILE" MOD_IDS)"
echo

log_info "next steps:"
log_info "  make up      # start the server"
log_info "  make logs    # tail logs — JVM boot is slow, commonly 1-3+ minutes"
log_info "If you set MOD_IDS/WORKSHOP_IDS, they need two more restarts to fully"
log_info "register (three if they add maps) — see README.md's Known quirks."
log_info "See README.md's Troubleshooting section if anything above looks wrong."
