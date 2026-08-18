#!/usr/bin/env bash
# Shared by every game's setup.sh. Source it, don't copy it — logging and
# .env-editing logic stays here so every game fails and prints the same way,
# the same principle already applied to backup.sh/restore.sh.
#
# Expects GAME_NAME to be set by the caller before logging anything (falls
# back to "setup" if not, so sourcing this alone doesn't error).

: "${GAME_NAME:=setup}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  _C_INFO='\033[36m'; _C_WARN='\033[33m'; _C_ERROR='\033[31m'; _C_OK='\033[32m'; _C_RESET='\033[0m'
else
  _C_INFO=''; _C_WARN=''; _C_ERROR=''; _C_OK=''; _C_RESET=''
fi

_ts() { date '+%H:%M:%S'; }

log_info()    { printf "%b[%s] [%s] INFO  %s%b\n"  "$_C_INFO"  "$(_ts)" "$GAME_NAME" "$*" "$_C_RESET"; }
log_warn()    { printf "%b[%s] [%s] WARN  %s%b\n"  "$_C_WARN"  "$(_ts)" "$GAME_NAME" "$*" "$_C_RESET" >&2; }
log_error()   { printf "%b[%s] [%s] ERROR %s%b\n"  "$_C_ERROR" "$(_ts)" "$GAME_NAME" "$*" "$_C_RESET" >&2; }
log_success() { printf "%b[%s] [%s] OK    %s%b\n"  "$_C_OK"    "$(_ts)" "$GAME_NAME" "$*" "$_C_RESET"; }

# require_cmd <cmd> <install-hint>
# Errors with a clear, actionable message instead of a raw "command not found".
require_cmd() {
  local cmd="$1" hint="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "required command '$cmd' not found."
    log_error "  $hint"
    exit 1
  fi
}

# setup_trap_errors
# Installs an ERR trap so an unexpected failure anywhere in the calling
# script prints a consistent, greppable message with the failing line
# instead of a bare bash stack dump. Call after logging is set up.
setup_trap_errors() {
  trap 'log_error "setup failed at line $LINENO (exit $?). Re-run with the same flags after fixing the issue above."' ERR
}

# _sed_escape <string>
# Escapes characters that are special inside a sed replacement / pattern
# built with '|' as the delimiter.
_sed_escape() {
  printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'
}

# env_get <env_file> <KEY>
# Prints KEY's current value from env_file, or nothing if unset.
env_get() {
  local env_file="$1" key="$2"
  [ -f "$env_file" ] || return 0
  sed -n "s/^${key}=//p" "$env_file" | tail -n1
}

# env_set <env_file> <KEY> <VALUE>
# Upserts KEY=VALUE into env_file: replaces the existing line if KEY is
# already set, appends a new line otherwise. Used to back --set overrides.
env_set() {
  local env_file="$1" key="$2" value="$3"
  local esc_value
  esc_value="$(_sed_escape "$value")"
  if [ -f "$env_file" ] && grep -q "^${key}=" "$env_file"; then
    sed -i "s|^${key}=.*|${key}=${esc_value}|" "$env_file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$env_file"
  fi
}

# mask <value>
# Returns a fixed-length mask for printing secrets in a config summary.
mask() {
  if [ -z "$1" ]; then
    printf '(blank)'
  else
    printf '********'
  fi
}
