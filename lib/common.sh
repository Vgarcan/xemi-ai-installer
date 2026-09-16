# Common output, interaction, and command execution helpers.

log() {
  if mkdir -p "$LOG_DIR" >/dev/null 2>&1; then
    echo "$(date '+%F %T') , $1" >> "$LOG_FILE" 2>/dev/null || true
  fi
}

sleep_screen() { sleep "$SLEEP_SCREEN"; }

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    echo -e "${RED}Run as root (sudo).${NC}"
    exit 1
  fi
}

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

json_escape() {
  if cmd_exists python3; then
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])' < /dev/stdin
  elif cmd_exists python; then
    python -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])' < /dev/stdin
  else
    sed -e 's/\\/\\\\/g' -e 's/"/\\\"/g' -e 's/\t/\\t/g' -e 's/\r/\\r/g' -e 's/\n/\\n/g'
  fi
}

header() {
  if [ "$ASSUME_YES" != "1" ]; then
    clear || true
  fi
  echo -e "${BLUE}==================================================${NC}"
  echo -e "${BLUE} ${APP_NAME}${NC}"
  echo -e "${BLUE}==================================================${NC}"
  echo ""
  sleep_screen
}

pause() {
  if [ "$ASSUME_YES" = "1" ]; then
    return 0
  fi
  echo ""
  read -r -p "Press Enter to continue... " _
  sleep_screen
}

ok() { echo -e "${GREEN}$1${NC}"; log "OK , $1"; }

warn() { echo -e "${YELLOW}$1${NC}"; log "WARN , $1"; }

fail() { echo -e "${RED}$1${NC}"; log "ERROR , $1"; }

menu_section() {
  echo -e "${BLUE}-- $1 --${NC}"
}

menu_item() {
  local number="$1"
  local text="$2"
  printf "  ${GREEN}%2s${NC}) %s\n" "$number" "$text"
}

ask() {
  local prompt="$1"
  local default="${2:-}"
  local ans=""
  if [ "$ASSUME_YES" = "1" ] && [ -n "$default" ]; then
    echo "$default"
    return 0
  fi
  if [ -n "$default" ]; then
    read -r -p "${prompt} [${default}]: " ans
    echo "${ans:-$default}"
  else
    read -r -p "${prompt}: " ans
    echo "$ans"
  fi
}

confirm_proceed() {
  local prompt="$1"
  local default="${2:-yes}"
  if [ "$ASSUME_YES" = "1" ]; then
    echo "yes"
    return 0
  fi
  ask "$prompt" "$default"
}

run_required() {
  local desc="$1"
  local rc
  shift
  echo "$desc"
  log "RUN , $desc , $*"
  set +e
  "$@" 2>&1 | tee -a "$LOG_FILE"
  rc=${PIPESTATUS[0]}
  set -e
  if [ "$rc" -ne 0 ]; then
    fail "Required step failed (${rc}): $desc"
    return "$rc"
  fi
}

run_optional() {
  local desc="$1"
  local rc
  shift
  echo "$desc"
  log "RUN_OPTIONAL , $desc , $*"
  set +e
  "$@" 2>&1 | tee -a "$LOG_FILE"
  rc=${PIPESTATUS[0]}
  set -e
  if [ "$rc" -ne 0 ]; then
    warn "Optional step failed (${rc}): $desc"
    return 1
  fi
}
