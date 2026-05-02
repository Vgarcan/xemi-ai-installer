#!/bin/bash

set -euo pipefail
umask 027

APP_NAME="AI Node Manager Pro"
STATE_DIR="/var/lib/xemi-ai"
CONFIG_DIR="/etc/xemi-ai"
BACKUP_DIR="${STATE_DIR}/backups"
MANIFEST_FILE="${STATE_DIR}/manifest.env"
LOCK_FILE="${STATE_DIR}/install.lock"
LOG_DIR="/var/log/xemi-ai"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/install.log}"

SLEEP_SCREEN="0.66"

AI_USER="${AI_USER:-aiuser}"
AI_GROUP="${AI_GROUP:-aiuser}"

OLLAMA_PORT_DEFAULT="11434"
WEBUI_PORT_DEFAULT="3000"
LAN_SUBNET_DEFAULT="${LAN_SUBNET:-192.168.2.0/24}"

OPENWEBUI_DIR="/opt/open-webui"
OPENWEBUI_VENV="/opt/open-webui-venv"
OPENWEBUI_DATA_DIR="/var/lib/open-webui"
OPENWEBUI_ENV_FILE="/etc/xemi-ai/openwebui.env"
OPENWEBUI_PACKAGE="${OPENWEBUI_PACKAGE:-open-webui}"
PY311_BIN="/usr/bin/python3.11"
OPENWEBUI_REF="${OPENWEBUI_REF:-}"
ALLOW_CPU_FALLBACK="${ALLOW_CPU_FALLBACK:-0}"
OLLAMA_VERSION="${OLLAMA_VERSION:-}"
OLLAMA_BIND_HOST="${OLLAMA_BIND_HOST:-0.0.0.0}"
OLLAMA_MODELS_DIR="${OLLAMA_MODELS_DIR:-}"
OLLAMA_MODELS_DIR_FROM_CLI=0
if [ -n "$OLLAMA_MODELS_DIR" ]; then
  OLLAMA_MODELS_DIR_FROM_CLI=1
fi
OLLAMA_INSTALL_SHA256="${OLLAMA_INSTALL_SHA256:-}"
ASSUME_YES=0
DRY_RUN=0
COMMAND="menu"
AUTO_REBOOT="${AUTO_REBOOT:-0}"

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
NC="\e[0m"

log() {
  mkdir -p "$LOG_DIR" >/dev/null 2>&1 || true
  echo "$(date '+%F %T') , $1" >> "$LOG_FILE"
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

init_runtime() {
  mkdir -p "$STATE_DIR" "$CONFIG_DIR" "$BACKUP_DIR" "$LOG_DIR"
  touch "$MANIFEST_FILE" "$LOG_FILE"
  chmod 700 "$STATE_DIR" "$BACKUP_DIR" "$LOG_DIR" || true
  chmod 750 "$CONFIG_DIR" || true
  chmod 600 "$MANIFEST_FILE" || true
}

acquire_lock() {
  if ! cmd_exists flock; then
    warn "flock not found; continuing without single-run lock."
    return 0
  fi

  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    fail "Another installer run is already active. Lock: $LOCK_FILE"
    exit 1
  fi
  trap 'flock -u 9 2>/dev/null || true' EXIT
}

is_yes() {
  [[ "${1:-}" =~ ^([Yy][Ee][Ss]|[Yy]|[Ss][Ii]|[Ss])$ ]]
}

record_manifest() {
  local key="$1"
  local value="$2"
  local tmp
  if ! validate_manifest_key "$key" || ! manifest_key_allowed "$key"; then
    fail "Refusing to write unsupported manifest key: $key"
    return 1
  fi
  mkdir -p "$STATE_DIR"
  tmp="$(mktemp "${STATE_DIR}/manifest.XXXXXX")"
  if [ -f "$MANIFEST_FILE" ]; then
    grep -v "^${key}=" "$MANIFEST_FILE" > "$tmp" || true
  fi
  printf "%s=%q\n" "$key" "$value" >> "$tmp"
  command mv -f "$tmp" "$MANIFEST_FILE"
  chmod 600 "$MANIFEST_FILE" || true
}

validate_manifest_key() {
  [[ "${1:-}" =~ ^[A-Z0-9_]+$ ]]
}

manifest_key_allowed() {
  case "$1" in
    AI_GROUP_CREATED|AI_USER_CREATED|AI_USER|AI_GROUP|OLLAMA_VERSION|OLLAMA_INSTALL_SHA256|OLLAMA_INSTALLED_BY_XEMI|OLLAMA_OVERRIDE_CREATED|OLLAMA_PORT|OLLAMA_BIND_HOST|OLLAMA_MODELS_DIR|NVIDIA_GPU_UUIDS|OPENWEBUI_VENV_CREATED|OPENWEBUI_SERVICE_CREATED|OPENWEBUI_PORT|OPENWEBUI_VENV|OPENWEBUI_DATA_DIR|OPENWEBUI_ENV_FILE|OPENWEBUI_PACKAGE|OPENWEBUI_OLLAMA_BASE_URL|FIREWALL_CONFIGURED|FIREWALL_RULE_OLLAMA|FIREWALL_RULE_WEBUI|LAN_SUBNET)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

decode_manifest_value() {
  local raw="$1"
  printf '%s\n' "$raw" | xargs printf '%s\n' 2>/dev/null
}

load_manifest() {
  local line key raw value
  [ -f "$MANIFEST_FILE" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    [[ "$line" = \#* ]] && continue
    key="${line%%=*}"
    raw="${line#*=}"
    if ! validate_manifest_key "$key" || ! manifest_key_allowed "$key"; then
      warn "Ignoring unsupported manifest key: $key"
      continue
    fi
    if ! value="$(decode_manifest_value "$raw")"; then
      warn "Ignoring malformed manifest value for key: $key"
      continue
    fi
    printf -v "$key" "%s" "$value"
  done < "$MANIFEST_FILE"
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

preflight_supported_system() {
  local distro="unknown"
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    distro="${PRETTY_NAME:-${ID:-unknown}}"
  fi

  if ! cmd_exists dnf; then
    fail "dnf not found. This installer currently supports RHEL/Alma/Rocky/Fedora-like systems."
    return 1
  fi

  if ! cmd_exists systemctl; then
    fail "systemctl not found. This installer requires systemd."
    return 1
  fi

  ok "Supported system checks passed: ${distro}"
}

show_dry_run_plan() {
  local cmd="$1"
  echo "Dry run for command: ${cmd}"
  echo ""
  echo "No packages, services, files, firewall rules or users will be changed."
  echo ""
  echo "Resolved settings:"
  echo "  AI user/group: ${AI_USER}:${AI_GROUP}"
  echo "  Ollama port: ${OLLAMA_PORT_DEFAULT}"
  echo "  Open WebUI port: ${WEBUI_PORT_DEFAULT}"
  echo "  LAN subnet: ${LAN_SUBNET_DEFAULT}"
  echo "  Ollama bind host: ${OLLAMA_BIND_HOST}"
  if [ -n "$OLLAMA_MODELS_DIR" ]; then
    echo "  Ollama models directory: ${OLLAMA_MODELS_DIR}"
  else
    echo "  Ollama models directory: Ollama default/service-user default"
  fi
  echo "  Open WebUI package: ${OPENWEBUI_PACKAGE}"
  echo "  Python binary for Open WebUI: ${PY311_BIN}"
  echo "  Allow CPU fallback: ${ALLOW_CPU_FALLBACK}"
  echo "  Auto reboot after driver install: ${AUTO_REBOOT}"
  if [ -n "$OLLAMA_VERSION" ]; then
    echo "  Ollama version: ${OLLAMA_VERSION}"
  else
    echo "  Ollama version: latest official installer default"
  fi
  if [ -n "$OLLAMA_INSTALL_SHA256" ]; then
    echo "  Ollama installer SHA256 verification: enabled"
  else
    echo "  Ollama installer SHA256 verification: not configured"
  fi
  echo ""

  case "$cmd" in
    install|new-server|bootstrap)
      echo "Plan:"
      echo "  1. Check dnf/systemd support."
      echo "  2. Install base tools."
      echo "  3. Enable EPEL/RPM Fusion repositories."
      echo "  4. Check NVIDIA GPU with nvidia-smi."
      echo "  5. Install NVIDIA drivers if needed."
      echo "  6. Install Ollama."
      echo "  7. Configure Ollama systemd override for LAN/GPU/autostart."
      echo "  8. Configure custom Ollama model directory if provided."
      echo "  9. Offer model sets and optionally pull selected models."
      echo "  10. Install Python 3.11 side-by-side and Open WebUI in a venv."
      echo "  11. Create Open WebUI systemd service with autostart."
      echo "  12. Add firewall rich rules for LAN access."
      echo "  13. Run doctor readiness checks."
      ;;
    stack)
      echo "Plan:"
      echo "  1. Check dnf/systemd support."
      echo "  2. Install base tools and user."
      echo "  3. Install/configure Ollama."
      echo "  4. Configure custom Ollama model directory if provided."
      echo "  5. Offer model sets and optionally pull selected models."
      echo "  6. Install/configure Open WebUI."
      echo "  7. Configure firewall and run doctor."
      ;;
    models-dir)
      echo "Plan:"
      echo "  1. Ask for or use --ollama-models-dir."
      echo "  2. Create/chown the target directory."
      echo "  3. Optionally migrate existing model data."
      echo "  4. Update Ollama systemd override with OLLAMA_MODELS."
      echo "  5. Restart Ollama and verify /api/tags."
      ;;
    openwebui-update|webui-update)
      echo "Plan:"
      echo "  1. Check current Open WebUI version in the venv."
      echo "  2. Ask pip whether open-webui has an available update."
      echo "  3. If update exists, stop Open WebUI and upgrade the package."
      echo "  4. Reapply SQLite/cache/systemd compatibility settings."
      echo "  5. Restart Open WebUI and verify /health."
      ;;
    drivers)
      echo "Plan:"
      echo "  1. Check dnf/systemd support."
      echo "  2. Install base tools and repositories."
      echo "  3. Install NVIDIA driver packages."
      echo "  4. Offer reboot."
      ;;
    uninstall)
      echo "Plan:"
      echo "  1. Remove firewall rules recorded in manifest."
      echo "  2. Stop/disable Open WebUI and remove venv/service/env file."
      echo "  3. Remove Xemi Ollama override, keep Ollama binary and model data."
      ;;
    purge)
      echo "Plan:"
      echo "  1. Run uninstall cleanup."
      echo "  2. Remove Open WebUI data."
      echo "  3. Remove Ollama binary/libraries/model data."
      echo "  4. Remove created user/group and manifest."
      ;;
    doctor|status|state|report|info|menu)
      echo "Plan: run read-oriented command '${cmd}'."
      ;;
    *)
      echo "Plan: unknown command '${cmd}'."
      ;;
  esac
}

validate_identity() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

validate_cidr() {
  local cidr="$1"
  local ip prefix o1 o2 o3 o4
  [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || return 1
  ip="${cidr%/*}"
  prefix="${cidr#*/}"
  IFS=. read -r o1 o2 o3 o4 <<< "$ip"
  for o in "$o1" "$o2" "$o3" "$o4"; do
    [ "$o" -ge 0 ] && [ "$o" -le 255 ] || return 1
  done
  [ "$prefix" -ge 0 ] && [ "$prefix" -le 32 ]
}

validate_bind_host() {
  [[ "${1:-}" =~ ^[A-Za-z0-9_.:-]+$ ]]
}

validate_absolute_path() {
  local path="${1:-}"
  [ -n "$path" ] || return 1
  [[ "$path" = /* ]] || return 1
  [ "$path" != "/" ] || return 1
  [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 1
  [[ "$path" =~ ^/[A-Za-z0-9._/@+=:-]+$ ]]
}

validate_sha256() {
  [[ "${1:-}" =~ ^[A-Fa-f0-9]{64}$ ]]
}

validate_runtime_config() {
  validate_bind_host "$OLLAMA_BIND_HOST" || { echo "Invalid OLLAMA_BIND_HOST: $OLLAMA_BIND_HOST"; exit 1; }
  if [ -n "$OLLAMA_INSTALL_SHA256" ]; then
    validate_sha256 "$OLLAMA_INSTALL_SHA256" || { echo "Invalid OLLAMA_INSTALL_SHA256: $OLLAMA_INSTALL_SHA256"; exit 1; }
  fi
  if [ -n "$OLLAMA_MODELS_DIR" ]; then
    validate_absolute_path "$OLLAMA_MODELS_DIR" || { echo "Invalid OLLAMA_MODELS_DIR: $OLLAMA_MODELS_DIR"; exit 1; }
  fi
}

safe_rm_rf() {
  local path="$1"
  shift
  local resolved prefix resolved_prefix

  if [ -z "$path" ] || [ "$path" = "/" ] || [ "$path" = "." ] || [ "$path" = ".." ]; then
    fail "Refusing unsafe rm -rf path: ${path:-<empty>}"
    return 1
  fi
  if ! cmd_exists realpath; then
    fail "realpath is required for safe directory removal."
    return 1
  fi

  resolved="$(realpath -m -- "$path")"
  for prefix in "$@"; do
    resolved_prefix="$(realpath -m -- "$prefix")"
    if [ "$resolved" = "$resolved_prefix" ] || [[ "$resolved" = "$resolved_prefix"/* ]]; then
      rm -rf -- "$resolved"
      return 0
    fi
  done

  fail "Refusing rm -rf outside managed paths: $path"
  return 1
}

rpmfusion_release_urls() {
  local fedora_ver=""
  local rhel_ver=""

  fedora_ver="$(rpm -E %fedora 2>/dev/null || true)"
  if [[ "$fedora_ver" =~ ^[0-9]+$ ]]; then
    printf "%s\n" \
      "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" \
      "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm"
    return 0
  fi

  rhel_ver="$(rpm -E %rhel 2>/dev/null || true)"
  if [[ "$rhel_ver" =~ ^[0-9]+$ ]]; then
    printf "%s\n" \
      "https://download1.rpmfusion.org/free/el/rpmfusion-free-release-${rhel_ver}.noarch.rpm" \
      "https://download1.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-${rhel_ver}.noarch.rpm"
    return 0
  fi

  return 1
}

ask_port() {
  local prompt="$1"
  local default="$2"
  local value
  while true; do
    value="$(ask "$prompt" "$default")"
    if validate_port "$value"; then
      echo "$value"
      return 0
    fi
    warn "Invalid port. Use a number from 1 to 65535."
  done
}

ask_cidr() {
  local prompt="$1"
  local default="$2"
  local value
  while true; do
    value="$(ask "$prompt" "$default")"
    if validate_cidr "$value"; then
      echo "$value"
      return 0
    fi
    warn "Invalid subnet. Use CIDR format, for example 192.168.2.0/24."
  done
}

ask_absolute_path() {
  local prompt="$1"
  local default="$2"
  local value
  while true; do
    value="$(ask "$prompt" "$default")"
    if validate_absolute_path "$value"; then
      echo "$value"
      return 0
    fi
    warn "Invalid path. Use an absolute path without spaces, for example /mnt/ssd/ollama-models."
  done
}

backup_path() {
  local path="$1"
  local stamp dest
  [ -e "$path" ] || return 0
  stamp="$(date '+%Y%m%d-%H%M%S')"
  dest="${BACKUP_DIR}/$(basename "$path").${stamp}"
  cp -a "$path" "$dest"
  log "BACKUP , $path , $dest"
}

nvidia_gpu_uuids() {
  if ! cmd_exists nvidia-smi; then
    return 1
  fi
  nvidia-smi --query-gpu=uuid --format=csv,noheader 2>/dev/null | awk 'NF {gsub(/^[ \t]+|[ \t]+$/, ""); print}' | paste -sd, -
}

ensure_nvidia_gpu_ready() {
  if ! cmd_exists nvidia-smi; then
    fail "nvidia-smi not found. Install NVIDIA drivers first and reboot if needed."
    return 1
  fi

  if ! nvidia-smi >/dev/null 2>&1; then
    fail "nvidia-smi is installed but cannot talk to the GPU. Reboot after driver install or check NVIDIA drivers."
    return 1
  fi
}

enable_nvidia_persistence() {
  if ! cmd_exists nvidia-smi; then
    return 0
  fi

  mkdir -p /etc/modules-load.d
  cat > /etc/modules-load.d/nvidia.conf <<'EOF'
nvidia
nvidia_uvm
nvidia_modeset
nvidia_drm
EOF

  if systemctl list-unit-files nvidia-persistenced.service >/dev/null 2>&1; then
    run_optional "Enabling NVIDIA persistence daemon..." systemctl enable --now nvidia-persistenced || true
  fi
  run_optional "Enabling NVIDIA persistence mode..." nvidia-smi -pm 1 || true
}

is_ollama_service_installed() {
  if ! cmd_exists ollama; then
    return 1
  fi
  systemctl list-unit-files ollama.service >/dev/null 2>&1
}

is_openwebui_installed() {
  [ -x "$OPENWEBUI_VENV/bin/open-webui" ]
}

has_existing_installation() {
  load_manifest
  if [ -n "${OLLAMA_INSTALLED_BY_XEMI:-}" ] || [ -n "${OPENWEBUI_SERVICE_CREATED:-}" ]; then
    return 0
  fi

  if is_ollama_service_installed || is_openwebui_installed; then
    return 0
  fi
  return 1
}

ollama_current_compute_mode() {
  local pid logs
  pid="$(systemctl show ollama -p MainPID --value --no-pager 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  [ "$pid" -gt 0 ] || return 1

  logs="$(journalctl _PID="$pid" -o cat --no-pager 2>/dev/null || true)"
  if echo "$logs" | grep -q 'library=CUDA'; then
    echo "gpu"
    return 0
  fi
  if echo "$logs" | grep -q 'id=cpu library=cpu'; then
    echo "cpu"
    return 0
  fi
  return 1
}

wait_for_ollama_compute_mode() {
  local attempts="${1:-30}"
  local delay="${2:-2}"
  local mode=""
  local i

  for ((i=1; i<=attempts; i++)); do
    if mode="$(ollama_current_compute_mode 2>/dev/null || true)" && [ -n "$mode" ]; then
      echo "$mode"
      return 0
    fi
    sleep "$delay"
  done
  return 1
}

ensure_ollama_uses_gpu() {
  local allow_restart="${1:-1}"
  local mode=""

  if ! ensure_nvidia_gpu_ready; then
    return 0
  fi

  if ! mode="$(wait_for_ollama_compute_mode 45 2 || true)" || [ -z "$mode" ]; then
    fail "Could not determine whether Ollama started with GPU or CPU."
    return 1
  fi

  if [ "$mode" = "gpu" ]; then
    ok "Ollama detected CUDA and is ready to use the GPU."
    return 0
  fi

  if [ "$allow_restart" = "1" ]; then
    warn "Ollama started in CPU mode even though NVIDIA GPU is ready. Restarting Ollama once."
    systemctl restart ollama
    mode="$(wait_for_ollama_compute_mode 45 2 || true)"
    if [ "$mode" = "gpu" ]; then
      ok "Ollama switched to CUDA after restart."
      return 0
    fi
  fi

  fail "Ollama is still in CPU mode while NVIDIA GPU is available."
  return 1
}

repair_ollama_service_override() {
  local port="${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}"
  local bind_host="${OLLAMA_BIND_HOST:-0.0.0.0}"
  local models_dir="$(current_ollama_models_dir)"
  local gpu_uuids=""

  if ensure_nvidia_gpu_ready; then
    enable_nvidia_persistence
    gpu_uuids="$(nvidia_gpu_uuids || true)"
  fi

  write_ollama_override "$port" "$bind_host" "$gpu_uuids" "$models_dir"
  if [ -n "$gpu_uuids" ]; then
    record_manifest "NVIDIA_GPU_UUIDS" "$gpu_uuids"
  fi
  record_manifest "OLLAMA_OVERRIDE_CREATED" "1"
  record_manifest "OLLAMA_PORT" "$port"
  record_manifest "OLLAMA_BIND_HOST" "$bind_host"
  systemctl daemon-reload
  systemctl enable ollama >/dev/null 2>&1 || true
  systemctl enable xemi-ollama-gpu-guard.service >/dev/null 2>&1 || true
  systemctl restart ollama || true
  ensure_ollama_uses_gpu 1 || true
}

repair_ollama_installation() {
  header
  echo "Repairing Ollama installation..."
  load_manifest
  ensure_ai_user

  if ! cmd_exists ollama; then
    warn "Ollama binary missing; installing Ollama."
    install_ollama_official
    return
  fi

  if verify_ollama_runtime_libs; then
    ok "Ollama runtime libraries verified."
  else
    warn "Ollama runtime or CUDA libraries appear incomplete. Re-installing Ollama."
    install_ollama_official
    return
  fi

  if ! systemctl show ollama -p Environment --no-pager 2>/dev/null | grep -q 'OLLAMA_HOST='; then
    warn "Ollama systemd override missing or incomplete; reconfiguring."
    repair_ollama_service_override
  else
    ok "Ollama service configuration present."
    repair_ollama_service_override
  fi
  pause
}

repair_openwebui_installation() {
  header
  echo "Repairing Open WebUI installation..."
  load_manifest
  install_python311
  ensure_ai_user
  ensure_base_tools

  if [ ! -d "$OPENWEBUI_VENV" ] || [ ! -x "$OPENWEBUI_VENV/bin/open-webui" ]; then
    warn "Open WebUI venv missing or broken; reinstalling Open WebUI."
    install_openwebui
    return
  fi

  run_required "Upgrading pip in Open WebUI venv..." "$OPENWEBUI_VENV/bin/pip" install --upgrade pip
  run_required "Reinstalling Open WebUI package..." "$OPENWEBUI_VENV/bin/pip" install -U "$OPENWEBUI_PACKAGE"
  run_required "Ensuring modern SQLite compatibility package..." "$OPENWEBUI_VENV/bin/pip" install -U pysqlite3-binary
  write_openwebui_sqlite_compat

  local ollama_port="${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}"
  local ollama_host="${OLLAMA_BIND_HOST:-0.0.0.0}"
  local ollama_base_host="127.0.0.1"
  if [ "$ollama_host" != "0.0.0.0" ]; then
    ollama_base_host="$ollama_host"
  fi

  local webui_port="${OPENWEBUI_PORT:-$WEBUI_PORT_DEFAULT}"
  if [ -f "$OPENWEBUI_ENV_FILE" ]; then
    webui_port="$(grep -E '^PORT=' "$OPENWEBUI_ENV_FILE" | cut -d= -f2 || echo "$webui_port")"
  fi

  write_openwebui_env_file "$webui_port" "http://${ollama_base_host}:${ollama_port}"
  write_openwebui_service "$webui_port"
  record_manifest "OPENWEBUI_SERVICE_CREATED" "1"
  record_manifest "OPENWEBUI_PORT" "$webui_port"
  record_manifest "OPENWEBUI_VENV" "$OPENWEBUI_VENV"
  record_manifest "OPENWEBUI_DATA_DIR" "$OPENWEBUI_DATA_DIR"
  record_manifest "OPENWEBUI_ENV_FILE" "$OPENWEBUI_ENV_FILE"
  record_manifest "OPENWEBUI_PACKAGE" "$OPENWEBUI_PACKAGE"
  record_manifest "OPENWEBUI_OLLAMA_BASE_URL" "http://${ollama_base_host}:${ollama_port}"

  systemctl daemon-reload
  systemctl enable openwebui >/dev/null 2>&1 || true
  systemctl restart openwebui || true
  pause
}

repair_existing_installation() {
  header
  echo "Existing installation detected. Repairing system with GPU prioritized."
  load_manifest
  ensure_ai_user

  if ! ensure_nvidia_gpu_ready; then
    warn "NVIDIA GPU is not ready. Installing NVIDIA drivers now."
    install_nvidia_drivers
    if ! ensure_nvidia_gpu_ready; then
      fail "NVIDIA GPU is still not ready. Reboot, then run: $0 install"
      pause
      return 1
    fi
  fi

  enable_nvidia_persistence
  repair_ollama_installation
  repair_openwebui_installation
  if [ -z "${FIREWALL_CONFIGURED:-}" ]; then
    warn "Firewall rules not present or not recorded; configuring firewall."
    configure_firewall_lan_only
  fi
  doctor
}

verify_ollama_runtime_libs() {
  local ollama_lib_dir="/usr/local/lib/ollama"
  local llm_library=""
  if [ ! -e "${ollama_lib_dir}/libggml-base.so.0" ] && [ ! -e "${ollama_lib_dir}/libggml-base.so.0.0.0" ]; then
    fail "Ollama runtime libraries are incomplete: missing ${ollama_lib_dir}/libggml-base.so.0. Re-run the Ollama installer."
    return 1
  fi

  if ensure_nvidia_gpu_ready; then
    llm_library="$(detect_ollama_llm_library || true)"
    if [ -z "$llm_library" ]; then
      fail "No compatible Ollama CUDA runtime library found under ${ollama_lib_dir}. Re-run the Ollama installer."
      return 1
    fi
  fi
}

write_ollama_gpu_guard_script() {
  backup_path /usr/local/bin/xemi_ollama_gpu_guard.sh
  cat > /usr/local/bin/xemi_ollama_gpu_guard.sh <<'EOF'
#!/bin/bash
set -euo pipefail

STATE_DIR="/run/xemi-ai"
STAMP_FILE="${STATE_DIR}/ollama-gpu-guard.boot"
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)"

mkdir -p "$STATE_DIR"

if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi >/dev/null 2>&1; then
  exit 0
fi

for _ in $(seq 1 45); do
  pid="$(systemctl show ollama -p MainPID --value --no-pager 2>/dev/null || true)"
  if [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" -gt 0 ]; then
    logs="$(journalctl _PID="$pid" -o cat --no-pager 2>/dev/null || true)"
    if echo "$logs" | grep -q 'library=CUDA'; then
      exit 0
    fi
    if echo "$logs" | grep -q 'id=cpu library=cpu'; then
      if [ -f "$STAMP_FILE" ] && grep -Fxq "$BOOT_ID" "$STAMP_FILE"; then
        exit 0
      fi
      printf '%s\n' "$BOOT_ID" > "$STAMP_FILE"
      systemctl restart ollama
      exit 0
    fi
  fi
  sleep 2
done

exit 0
EOF
  chmod 755 /usr/local/bin/xemi_ollama_gpu_guard.sh
}

write_ollama_gpu_guard_service() {
  backup_path /etc/systemd/system/xemi-ollama-gpu-guard.service
  cat > /etc/systemd/system/xemi-ollama-gpu-guard.service <<'EOF'
[Unit]
Description=Xemi Ollama GPU Guard
After=ollama.service nvidia-persistenced.service
Requires=ollama.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/xemi_ollama_gpu_guard.sh

[Install]
WantedBy=ollama.service
EOF
}

remove_firewall_rule() {
  local rule="$1"
  [ -n "$rule" ] || return 0
  firewall-cmd --permanent --remove-rich-rule="$rule" >/dev/null 2>&1 || true
}

ensure_base_tools() {
  header
  echo "Installing base tools..."
  run_required "Installing base tools with dnf..." dnf install -y curl wget git firewalld nano tar gzip zstd jq bc pciutils util-linux coreutils procps-ng
  run_optional "Installing optional diagnostic tool htop..." dnf install -y htop || true
  run_optional "Enabling firewalld..." systemctl enable firewalld || true
  run_optional "Starting firewalld..." systemctl start firewalld || true
  ok "Base tools ready."
  pause
}

ensure_ai_user() {
  header
  echo "Ensuring user and group..."
  if ! validate_identity "$AI_USER" || ! validate_identity "$AI_GROUP"; then
    fail "Invalid AI_USER or AI_GROUP. Use Linux-safe names like aiuser."
    pause
    return 1
  fi
  if ! getent group "$AI_GROUP" >/dev/null 2>&1; then
    groupadd -f "$AI_GROUP"
    record_manifest "AI_GROUP_CREATED" "1"
  fi
  if ! id "$AI_USER" >/dev/null 2>&1; then
    useradd -m -g "$AI_GROUP" -s /bin/bash "$AI_USER"
    record_manifest "AI_USER_CREATED" "1"
  fi
  if getent group render >/dev/null 2>&1; then
    usermod -a -G render "$AI_USER" || true
  fi
  if getent group video >/dev/null 2>&1; then
    usermod -a -G video "$AI_USER" || true
  fi
  record_manifest "AI_USER" "$AI_USER"
  record_manifest "AI_GROUP" "$AI_GROUP"
  ok "User ready: $AI_USER"
  pause
}

enable_repos() {
  header
  echo "Enabling repositories..."
  local rpmfusion_urls=()
  mapfile -t rpmfusion_urls < <(rpmfusion_release_urls)
  if [ "${#rpmfusion_urls[@]}" -ne 2 ]; then
    fail "Could not determine Fedora/RHEL release version for RPM Fusion."
    pause
    return 1
  fi
  if [[ "$(rpm -E %rhel 2>/dev/null || true)" =~ ^[0-9]+$ ]]; then
    run_required "Installing EPEL release..." dnf install -y epel-release
  else
    warn "Skipping EPEL release package on non-RHEL platform."
  fi
  run_required "Installing RPM Fusion free release..." dnf install -y "${rpmfusion_urls[0]}"
  run_required "Installing RPM Fusion nonfree release..." dnf install -y "${rpmfusion_urls[1]}"
  ok "Repositories ready."
  pause
}

install_nvidia_drivers() {
  header
  echo "Installing NVIDIA drivers and CUDA runtime..."
  run_required "Installing NVIDIA packages..." dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
  enable_nvidia_persistence
  ok "NVIDIA packages installed."
  local ans
  if [ "$ASSUME_YES" = "1" ] && [ "$AUTO_REBOOT" != "1" ]; then
    ans="no"
    warn "Automatic reboot skipped. Use --reboot to allow reboot in --yes mode."
  else
    ans="$(ask "Reboot now (recommended) yes or no" "yes")"
  fi
  if is_yes "$ans"; then
    log "Reboot requested"
    reboot
  fi
  pause
}

gpu_info_and_recommendations() {
  header
  if ! cmd_exists nvidia-smi; then
    fail "nvidia-smi not found."
    pause
    return 1
  fi
  if ! nvidia-smi; then
    fail "nvidia-smi failed."
    pause
    return 1
  fi

  local vram
  vram="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1 | tr -d ' ')"
  echo ""
  echo -e "${YELLOW}VRAM detected: ${vram} MB${NC}"
  echo ""

  echo "Recommended model sets:"
  if [ "$vram" -ge 11000 ]; then
    echo "1) General RPA: mistral, llama3, phi3"
    echo "2) Coding RPA: mistral, deepseek-coder, phi3"
    echo "3) Minimal: phi3, mistral"
    echo "4) Custom selection"
  elif [ "$vram" -ge 8000 ]; then
    echo "1) General: mistral, phi3"
    echo "2) Minimal: phi3"
    echo "3) Custom selection"
  else
    echo "1) Minimal: phi3"
    echo "2) Custom selection"
  fi

  pause
}

find_ollama_binaries() {
  local found=()
  local candidates=(
    "/usr/local/bin/ollama"
    "/usr/bin/ollama"
    "/bin/ollama"
    "/opt/ollama/ollama"
    "/usr/local/sbin/ollama"
    "/usr/sbin/ollama"
  )

  for p in "${candidates[@]}"; do
    if [ -x "$p" ]; then
      found+=("$p")
    fi
  done

  if cmd_exists ollama; then
    local whichp
    whichp="$(command -v ollama)"
    if [ -n "$whichp" ] && [ -x "$whichp" ]; then
      local exists=0
      for p in "${found[@]:-}"; do
        if [ "$p" = "$whichp" ]; then exists=1; fi
      done
      if [ "$exists" -eq 0 ]; then
        found+=("$whichp")
      fi
    fi
  fi

  printf "%s\n" "${found[@]:-}"
}

choose_ollama_binary() {
  local bins
  mapfile -t bins < <(find_ollama_binaries || true)

  if [ "${#bins[@]}" -eq 0 ]; then
    echo ""
    return 1
  fi

  if [ "${#bins[@]}" -eq 1 ]; then
    echo "${bins[0]}"
    return 0
  fi

  echo ""
  echo "Multiple Ollama binaries detected:"
  local i=1
  for b in "${bins[@]}"; do
    echo "$i) $b"
    i=$((i+1))
  done
  echo ""
  local choice
  choice="$(ask "Select the Ollama binary number" "1")"
  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    echo "${bins[0]}"
    return 0
  fi
  local idx=$((choice-1))
  if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#bins[@]}" ]; then
    echo "${bins[0]}"
    return 0
  fi
  echo "${bins[$idx]}"
}

show_ollama_status_and_location() {
  header
  echo "Ollama binaries found:"
  local bins
  mapfile -t bins < <(find_ollama_binaries || true)
  if [ "${#bins[@]}" -eq 0 ]; then
    echo "None found."
  else
    for b in "${bins[@]}"; do
      echo "$b"
    done
  fi

  echo ""
  echo "Service status:"
  if [ "$(systemctl show ollama.service -p LoadState --value --no-pager 2>/dev/null || true)" = "loaded" ]; then
    systemctl status ollama --no-pager || true
    echo ""
    echo "Service environment:"
    systemctl show ollama -p Environment --no-pager || true
    echo ""
    echo "Service file path:"
    systemctl show ollama -p FragmentPath --no-pager || true
  else
    echo "ollama.service not installed."
  fi

  echo ""
  echo "Listening ports related to Ollama:"
  ss -tulpen | grep -E "(:${OLLAMA_PORT_DEFAULT}\b|ollama)" || true

  pause
}

install_ollama_official() {
  header
  local installer
  installer="$(mktemp /tmp/ollama-install.XXXXXX.sh)"
  echo "Installing Ollama using official installer..."
  run_required "Downloading Ollama official installer..." curl -fsSL -o "$installer" https://ollama.com/install.sh
  if [ -n "$OLLAMA_INSTALL_SHA256" ]; then
    validate_sha256 "$OLLAMA_INSTALL_SHA256" || {
      fail "Invalid OLLAMA_INSTALL_SHA256. Expected 64 hexadecimal characters."
      return 1
    }
    printf "%s  %s\n" "$OLLAMA_INSTALL_SHA256" "$installer" | sha256sum -c -
    record_manifest "OLLAMA_INSTALL_SHA256" "$OLLAMA_INSTALL_SHA256"
    ok "Ollama installer checksum verified."
  else
    warn "Ollama installer checksum not configured; relying on HTTPS transport."
  fi
  chmod 700 "$installer"
  if [ -n "$OLLAMA_VERSION" ]; then
    echo "Using Ollama version: $OLLAMA_VERSION"
    run_required "Running Ollama official installer..." env OLLAMA_VERSION="$OLLAMA_VERSION" sh "$installer"
    record_manifest "OLLAMA_VERSION" "$OLLAMA_VERSION"
  else
    run_required "Running Ollama official installer..." sh "$installer"
  fi
  rm -f "$installer"

  verify_ollama_runtime_libs
  record_manifest "OLLAMA_INSTALLED_BY_XEMI" "1"
  ok "Ollama installed."
  pause
}

default_ollama_models_dir() {
  echo "/home/${AI_USER}/.ollama/models"
}

current_ollama_models_dir() {
  local env_line
  if [ -n "${OLLAMA_MODELS_DIR:-}" ]; then
    echo "$OLLAMA_MODELS_DIR"
    return 0
  fi
  env_line="$(systemctl show ollama -p Environment --no-pager 2>/dev/null || true)"
  if echo "$env_line" | tr ' ' '\n' | grep -q '^OLLAMA_MODELS='; then
    echo "$env_line" | tr ' ' '\n' | awk -F= '/^OLLAMA_MODELS=/ {sub(/^OLLAMA_MODELS=/, ""); print; exit}'
    return 0
  fi
  default_ollama_models_dir
}

detect_ollama_llm_library() {
  local ollama_lib_dir="/usr/local/lib/ollama"
  local cuda_major=""

  if cmd_exists nvidia-smi && nvidia-smi >/dev/null 2>&1; then
    cuda_major="$(nvidia-smi 2>/dev/null | sed -n 's/.*CUDA Version: \([0-9][0-9]*\).*/\1/p' | head -n 1)"
  fi

  if [ "$cuda_major" -ge 13 ] 2>/dev/null && [ -d "${ollama_lib_dir}/cuda_v13" ]; then
    echo "cuda_v13"
  elif [ -d "${ollama_lib_dir}/cuda_v12" ]; then
    echo "cuda_v12"
  elif [ -d "${ollama_lib_dir}/cuda_v13" ]; then
    echo "cuda_v13"
  else
    echo ""
  fi
}

write_ollama_override() {
  local port="$1"
  local bind_host="$2"
  local gpu_uuids="$3"
  local models_dir="${4:-}"

  local llm_library
  local llm_library_path="/usr/local/lib/ollama"

  llm_library="$(detect_ollama_llm_library || true)"
  if [ -n "$llm_library" ] && [ -d "/usr/local/lib/ollama/$llm_library" ]; then
    llm_library_path="/usr/local/lib/ollama/$llm_library"
  fi

  write_ollama_gpu_guard_script
  write_ollama_gpu_guard_service
  backup_path /etc/systemd/system/ollama.service.d
  mkdir -p /etc/systemd/system/ollama.service.d
  cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Unit]
StartLimitIntervalSec=0
Wants=nvidia-persistenced.service
Wants=network-online.target
After=network-online.target systemd-modules-load.service nvidia-persistenced.service

[Service]
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="LD_LIBRARY_PATH=${llm_library_path}:/usr/local/lib/ollama"
ExecStartPre=/bin/sh -c 'for i in \$(seq 1 180); do if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then exit 0; fi; echo "Esperando NVIDIA GPU... (\$i/180)"; sleep 2; done; echo "NVIDIA GPU no está lista después de 360 segundos"; exit 1'
TimeoutStartSec=7min
Restart=on-failure
RestartSec=10s
Environment="OLLAMA_HOST=${bind_host}:${port}"
EOF
  if [ -n "$llm_library" ]; then
    cat >> /etc/systemd/system/ollama.service.d/override.conf <<EOF
Environment="OLLAMA_LLM_LIBRARY=${llm_library}"
EOF
  fi
  cat >> /etc/systemd/system/ollama.service.d/override.conf <<EOF
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_GPU_OVERHEAD=268435456"
Environment="OLLAMA_LOAD_TIMEOUT=10m"
Environment="OLLAMA_KEEP_ALIVE=30m"
User=${AI_USER}
Group=${AI_GROUP}
NoNewPrivileges=true
PrivateTmp=true
ProtectControlGroups=true
ProtectKernelModules=true
ProtectKernelTunables=true
RestrictSUIDSGID=true
EOF
  if [ -n "$models_dir" ]; then
    cat >> /etc/systemd/system/ollama.service.d/override.conf <<EOF
Environment="OLLAMA_MODELS=${models_dir}"
EOF
  fi
}

configure_ollama_service_lan() {
  header
  load_manifest
  local port
  local bind_host
  local gpu_uuids=""
  local models_dir="${OLLAMA_MODELS_DIR:-}"
  if [ "$OLLAMA_MODELS_DIR_FROM_CLI" = "1" ]; then
    models_dir=""
  fi
  port="$(ask_port "Ollama port" "$OLLAMA_PORT_DEFAULT")"
  bind_host="$(ask "Ollama bind host" "$OLLAMA_BIND_HOST")"
  if ! validate_bind_host "$bind_host"; then
    fail "Invalid Ollama bind host. Use an IP address or DNS-safe host name."
    pause
    return 1
  fi

  ensure_ai_user
  if ensure_nvidia_gpu_ready; then
    gpu_uuids="$(nvidia_gpu_uuids || true)"
    enable_nvidia_persistence
  elif [ "$ALLOW_CPU_FALLBACK" = "1" ]; then
    warn "Ollama will be configured without confirmed GPU because ALLOW_CPU_FALLBACK=1."
  else
    fail "GPU is required for this installer goal. Re-run after NVIDIA drivers are working, or set ALLOW_CPU_FALLBACK=1."
    pause
    return 1
  fi

  if [ -n "$models_dir" ]; then
    validate_absolute_path "$models_dir" || {
      fail "Invalid Ollama models directory: $models_dir"
      pause
      return 1
    }
    mkdir -p "$models_dir"
    chown -R "$AI_USER:$AI_GROUP" "$models_dir"
    record_manifest "OLLAMA_MODELS_DIR" "$models_dir"
  fi

  write_ollama_override "$port" "$bind_host" "$gpu_uuids" "$models_dir"
  if [ -n "$gpu_uuids" ]; then
    record_manifest "NVIDIA_GPU_UUIDS" "$gpu_uuids"
  fi

  record_manifest "OLLAMA_OVERRIDE_CREATED" "1"
  record_manifest "OLLAMA_PORT" "$port"
  record_manifest "OLLAMA_BIND_HOST" "$bind_host"
  OLLAMA_PORT="$port"
  OLLAMA_BIND_HOST="$bind_host"
  systemctl daemon-reload
  systemctl enable ollama >/dev/null 2>&1
  systemctl enable xemi-ollama-gpu-guard.service >/dev/null 2>&1
  systemctl restart ollama
  ensure_ollama_uses_gpu 1 || {
    pause
    return 1
  }

  ok "Ollama service configured on ${bind_host}:${port}."
  pause
}

configure_ollama_models_dir() {
  header
  echo "Configure Ollama model storage directory"
  echo ""
  ensure_ai_user
  load_manifest

  local current_dir
  local new_dir
  local old_resolved
  local new_resolved
  local port="${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}"
  local bind_host="${OLLAMA_BIND_HOST:-0.0.0.0}"
  local gpu_uuids="${NVIDIA_GPU_UUIDS:-}"
  local bin

  current_dir="$(current_ollama_models_dir)"
  echo "Current/default model directory: ${current_dir}"
  echo ""
  new_dir="$(ask_absolute_path "New Ollama models directory" "$current_dir")"

  old_resolved="$(realpath -m -- "$current_dir")"
  new_resolved="$(realpath -m -- "$new_dir")"
  if [ "$old_resolved" = "$new_resolved" ]; then
    ok "Ollama is already configured for this model directory."
    pause
    return 0
  fi
  if [[ "$new_resolved" = "$old_resolved"/* ]] || [[ "$old_resolved" = "$new_resolved"/* ]]; then
    fail "Refusing migration where old and new directories contain each other."
    pause
    return 1
  fi

  mkdir -p "$new_resolved"
  chown -R "$AI_USER:$AI_GROUP" "$new_resolved"
  echo ""
  echo "Target filesystem:"
  df -h "$new_resolved" || true
  if ! sudo -u "$AI_USER" test -w "$new_resolved"; then
    fail "AI user cannot write to model directory: $new_resolved"
    pause
    return 1
  fi

  if [ -d "$old_resolved" ] && [ -n "$(find "$old_resolved" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    echo ""
    echo "Existing model data found at: $old_resolved"
    local migrate
    migrate="$(ask "Migrate existing model data to the new directory yes or no" "yes")"
    if is_yes "$migrate"; then
      echo "Stopping Ollama before migration..."
      systemctl stop ollama >/dev/null 2>&1 || true
      echo "Copying model data. This may take a while..."
      cp -a "$old_resolved"/. "$new_resolved"/
      chown -R "$AI_USER:$AI_GROUP" "$new_resolved"
      ok "Model data copied to: $new_resolved"

      local remove_old
      remove_old="$(ask "Remove old model directory after successful copy yes or no" "no")"
      if is_yes "$remove_old"; then
        rm -rf -- "$old_resolved"
        ok "Old model directory removed: $old_resolved"
      fi
    fi
  fi

  if ensure_nvidia_gpu_ready; then
    gpu_uuids="$(nvidia_gpu_uuids || true)"
  fi

  write_ollama_override "$port" "$bind_host" "$gpu_uuids" "$new_resolved"
  record_manifest "OLLAMA_OVERRIDE_CREATED" "1"
  record_manifest "OLLAMA_PORT" "$port"
  record_manifest "OLLAMA_BIND_HOST" "$bind_host"
  record_manifest "OLLAMA_MODELS_DIR" "$new_resolved"
  if [ -n "$gpu_uuids" ]; then
    record_manifest "NVIDIA_GPU_UUIDS" "$gpu_uuids"
  fi
  OLLAMA_MODELS_DIR="$new_resolved"

  systemctl daemon-reload
  systemctl enable ollama >/dev/null 2>&1
  systemctl enable xemi-ollama-gpu-guard.service >/dev/null 2>&1
  systemctl restart ollama
  ensure_ollama_uses_gpu 1 || {
    pause
    return 1
  }

  echo "Testing Ollama with new model directory..."
  sleep 3
  if curl -fsS "http://127.0.0.1:${port}/api/tags" >/dev/null 2>&1; then
    ok "Ollama API responds using model directory: $new_resolved"
  else
    fail "Ollama API did not respond after changing model directory."
    journalctl -u ollama -n 80 --no-pager || true
    pause
    return 1
  fi

  if bin="$(choose_ollama_binary)"; then
    sudo -u "$AI_USER" "$bin" list || "$bin" list || true
  fi

  pause
}

ollama_health_check() {
  header
  local port
  port="$(ask_port "Ollama port" "$OLLAMA_PORT_DEFAULT")"
  if curl -fsS "http://127.0.0.1:${port}/api/tags" >/dev/null; then
    ok "Ollama API responding on localhost."
  else
    fail "Ollama API not responding."
  fi
  pause
}

list_ollama_models() {
  header
  local bin
  if ! bin="$(choose_ollama_binary)"; then
    fail "Ollama binary not found."
    pause
    return 1
  fi
  echo "Using: $bin"
  echo ""
  sudo -u "$AI_USER" "$bin" list || "$bin" list || true
  pause
}

test_ollama_model_interaction() {
  header
  local bin
  if ! bin="$(choose_ollama_binary)"; then
    fail "Ollama binary not found."
    pause
    return 1
  fi

  local models
  models="$({ sudo -u "$AI_USER" "$bin" list 2>/dev/null || "$bin" list 2>/dev/null; } | awk 'NR>1 {print $1}' | sed '/^$/d')"
  if [ -z "$models" ]; then
    fail "No Ollama models installed to test."
    pause
    return 1
  fi

  echo "Installed models:"
  printf '  %s\n' $models
  echo ""
  local model
  model="$(ask "Model to test" "$(printf '%s\n' $models | head -n 1)")"
  if [ -z "$model" ]; then
    fail "No model selected."
    pause
    return 1
  fi

  local prompt
  prompt="$(ask "Prompt to send to model" "Describe en una frase breve qué hace este modelo.")"
  if [ -z "$prompt" ]; then
    prompt="Describe en una frase breve qué hace este modelo."
  fi

  local stream_answer
  stream_answer="$(ask "Stream response live? yes or no" "no")"
  if ! [[ "$stream_answer" =~ ^([Yy][Ee][Ss]|[Yy]|[Ss][Ii]|[Ss])$ ]]; then
    stream_answer="no"
  fi
  local stream_mode="no"
  if [[ "$stream_answer" =~ ^([Yy][Ee][Ss]|[Yy]|[Ss][Ii]|[Ss])$ ]]; then
    stream_mode="yes"
  fi

  load_manifest
  local port="${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}"
  local host="127.0.0.1"
  local gpu_status="unknown"
  local gpu_info=""
  if cmd_exists nvidia-smi && nvidia-smi >/dev/null 2>&1; then
    gpu_status="ready"
    gpu_info="$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null | sed 's/^/  /')"
  else
    gpu_status="not ready"
  fi

  echo "== Resumen de prueba =="
  echo "Modelo: $model"
  echo "Prompt: $prompt"
  echo "Modo de stream: $stream_mode"
  echo "Puerto de Ollama: $port"
  echo "Estado GPU: $gpu_status"
  if [ -n "$gpu_info" ]; then
    echo "Detalles de GPU:"
    echo "$gpu_info"
  fi
  echo ""

  local start_ms end_ms elapsed_ms
  local payload_file
  local response_file
  payload_file="$(mktemp)"
  response_file="$(mktemp)"
  local stream_flag
  if [[ "$stream_answer" =~ ^([Yy][Ee][Ss]|[Yy]|[Ss][Ii]|[Ss])$ ]]; then
    stream_flag=true
  else
    stream_flag=false
  fi

  if cmd_exists python3; then
    python3 -c 'import json,sys; stream = sys.argv[3].lower() in ("true", "1", "yes", "y"); json.dump({"model": sys.argv[1], "prompt": sys.argv[2], "stream": stream}, sys.stdout)' "$model" "$prompt" "$stream_flag" > "$payload_file"
  elif cmd_exists python; then
    python -c 'import json,sys; stream = sys.argv[3].lower() in ("true", "1", "yes", "y"); json.dump({"model": sys.argv[1], "prompt": sys.argv[2], "stream": stream}, sys.stdout)' "$model" "$prompt" "$stream_flag" > "$payload_file"
  else
    printf '{"model":"%s","prompt":"%s","stream":%s}' "$(printf '%s' "$model" | json_escape)" "$(printf '%s' "$prompt" | json_escape)" "$stream_flag" > "$payload_file"
  fi

  echo "Enviando solicitud a Ollama; puede tardar si el modelo es grande."
  echo "Si el servicio está cargando el modelo o generando, espere por favor."

  start_ms="$(date +%s%3N)"
  local response
  local raw_response
  raw_response=""
  local rc=0
  if [ "$stream_flag" = true ]; then
    echo "Live stream enabled; chunks will appear as they arrive."
    set +e
    if cmd_exists stdbuf; then
      stdbuf -oL curl -S -N -m 300 --connect-timeout 10 -X POST "http://${host}:${port}/api/generate" -H 'Content-Type: application/json' --data-binary @"$payload_file" | tee "$response_file"
    else
      curl -S -N -m 300 --connect-timeout 10 -X POST "http://${host}:${port}/api/generate" -H 'Content-Type: application/json' --data-binary @"$payload_file" | tee "$response_file"
    fi
    rc=$?
    set -e
    raw_response="$(cat "$response_file" 2>/dev/null || true)"
    response="$raw_response"
  else
    echo "Esperando a que el modelo devuelva una respuesta completa..."
    response="$(curl -sS -m 300 --connect-timeout 10 -X POST "http://${host}:${port}/api/generate" -H 'Content-Type: application/json' --data-binary @"$payload_file" 2>&1)" || rc=$?
    raw_response="$response"
  fi

  end_ms="$(date +%s%3N)"
  elapsed_ms=$((end_ms - start_ms))
  rm -f "$payload_file" "$response_file"

  local error_message=""
  local model_output=""
  local usage=""
  local latency=""
  local done_reason=""
  local created_at=""
  local total_duration=""
  local load_duration=""
  local prompt_eval_duration=""
  local eval_duration=""
  if cmd_exists jq; then
    if [ "$stream_flag" = true ]; then
      response="$(printf '%s\n' "$raw_response" | jq -R -s 'split("\n") | map(select(length > 0) | fromjson? ) | last' 2>/dev/null || true)"
    fi
    if [ -n "$response" ]; then
      error_message="$(printf '%s' "$response" | jq -r '.error? // empty' 2>/dev/null || true)"
      model_output="$(printf '%s' "$response" | jq -r '.response? // empty' 2>/dev/null || true)"
      done_reason="$(printf '%s' "$response" | jq -r '.done_reason? // empty' 2>/dev/null || true)"
      created_at="$(printf '%s' "$response" | jq -r '.created_at? // empty' 2>/dev/null || true)"
      total_duration="$(printf '%s' "$response" | jq -r '.total_duration? // empty' 2>/dev/null || true)"
      load_duration="$(printf '%s' "$response" | jq -r '.load_duration? // empty' 2>/dev/null || true)"
      prompt_eval_duration="$(printf '%s' "$response" | jq -r '.prompt_eval_duration? // empty' 2>/dev/null || true)"
      eval_duration="$(printf '%s' "$response" | jq -r '.eval_duration? // empty' 2>/dev/null || true)"
      usage="$(printf '%s' "$response" | jq -r 'if has("usage") then "prompt_tokens: \(.usage.prompt_tokens // \"n/a\"), completion_tokens: \(.usage.completion_tokens // \"n/a\"), total_tokens: \(.usage.total_tokens // \"n/a\")" elif (has("total_duration") or has("load_duration") or has("prompt_eval_duration") or has("eval_duration")) then "total_duration: \(.total_duration // \"n/a\"), load_duration: \(.load_duration // \"n/a\"), prompt_eval_duration: \(.prompt_eval_duration // \"n/a\"), eval_duration: \(.eval_duration // \"n/a\")" else empty end' 2>/dev/null || true)"
      latency="$(printf '%s' "$response" | jq -r '.latency? // empty' 2>/dev/null || true)"
    fi
  fi

  if [ "$rc" -ne 0 ] || [ -n "$error_message" ]; then
    if [ -n "$error_message" ]; then
      fail "Model test request failed: $error_message"
    else
      fail "Model test request failed with curl exit code $rc."
    fi
    echo "Response output:"
    if [ -n "$raw_response" ]; then
      echo "$raw_response" | sed 's/^/  /'
    else
      echo "  <no response>"
    fi
    pause
    return 1
  fi

  local inference_device="unknown"
  if cmd_exists journalctl; then
    local olog
    olog="$(journalctl -u ollama -n 50 --no-pager 2>/dev/null || true)"
    if printf '%s' "$olog" | grep -Eiq 'cuda|nvidia|ggml_cuda|cublas|cuda_compute|gpu'; then
      inference_device="GPU"
    elif printf '%s' "$olog" | grep -Eiq 'CPU|cpu'; then
      inference_device="CPU"
    fi
  fi

  echo "== Resultado de la prueba =="
  echo "Tiempo transcurrido: ${elapsed_ms} ms"
  echo "Modo de stream: $stream_mode"
  echo "Dispositivo de inferencia estimado: $inference_device"
  if [ -n "$model_output" ]; then
    echo "Respuesta del modelo:"
    echo "$model_output" | sed 's/^/  /'
    echo ""
  fi
  if [ -n "$done_reason" ]; then
    echo "Motivo de finalización: $done_reason"
  fi
  if [ -n "$created_at" ]; then
    echo "Creado en: $created_at"
  fi
  if [ -n "$usage" ]; then
    echo "Resumen de uso: $usage"
  fi
  if [ -n "$latency" ]; then
    echo "Latencia reportada: $latency"
  fi
  echo "Respuesta cruda:"
  if [ -n "$raw_response" ]; then
    echo "$raw_response" | sed 's/^/  /'
  else
    echo "  <respuesta vacía>"
  fi
  echo ""

  if cmd_exists journalctl; then
    echo ""
    echo "Registros recientes de Ollama para señales GPU/CPU:"
    if journalctl -u ollama -n 50 --no-pager 2>/dev/null | grep -Eiq 'cuda|nvidia|gpu|ggml_cuda|library=cuda|compute'; then
      journalctl -u ollama -n 50 --no-pager 2>/dev/null | tail -n 20 | sed 's/^/  /'
    else
      echo "  No se encontraron señales explícitas de CUDA/GPU en las últimas 50 líneas del registro de Ollama."
    fi
  fi

  pause
}

remove_ollama_models_interactive() {
  header
  local bin
  if ! bin="$(choose_ollama_binary)"; then
    fail "Ollama binary not found."
    pause
    return 1
  fi

  echo "Using: $bin"
  echo ""
  echo "Models:"
  sudo -u "$AI_USER" "$bin" list || "$bin" list || true
  echo ""
  echo "Enter model names separated by spaces, or type ALL to remove everything."
  local targets
  targets="$(ask "Models to remove" "")"

  if [ -z "$targets" ]; then
    warn "No models selected."
    pause
    return 0
  fi

  if [[ "$targets" = "ALL" ]]; then
    local models
    models="$(sudo -u "$AI_USER" "$bin" list 2>/dev/null || "$bin" list 2>/dev/null || true)"
    echo "$models" | awk 'NR>1 {print $1}' | while read -r m; do
      [ -z "$m" ] && continue
      sudo -u "$AI_USER" "$bin" rm "$m" 2>/dev/null || "$bin" rm "$m" 2>/dev/null || true
    done
    ok "All models removed (best effort)."
    pause
    return 0
  fi

  for m in $targets; do
    sudo -u "$AI_USER" "$bin" rm "$m" 2>/dev/null || "$bin" rm "$m" 2>/dev/null || true
  done
  ok "Selected models removed (best effort)."
  pause
}

recommend_and_install_models() {
  header
  local bin
  if ! bin="$(choose_ollama_binary)"; then
    fail "Ollama binary not found."
    pause
    return 1
  fi

  local vram="0"
  if cmd_exists nvidia-smi; then
    vram="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1 | tr -d ' ' || echo 0)"
  fi

  echo "Using: $bin"
  echo ""
  echo "Detected VRAM: ${vram} MB"
  echo ""

  local options=()
  if [ "$vram" -ge 11000 ]; then
    options+=("mistral llama3 phi3")
    options+=("mistral deepseek-coder phi3")
    options+=("phi3 mistral")
    options+=("skip")
    options+=("custom")
  elif [ "$vram" -ge 8000 ]; then
    options+=("mistral phi3")
    options+=("phi3")
    options+=("skip")
    options+=("custom")
  else
    options+=("phi3")
    options+=("skip")
    options+=("custom")
  fi

  echo "Choose model set:"
  local i=1
  for o in "${options[@]}"; do
    if [ "$o" = "skip" ]; then
      echo "$i) Do not install models now"
    else
      echo "$i) $o"
    fi
    i=$((i+1))
  done
  echo ""

  local choice
  choice="$(ask "Selection number" "1")"
  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    warn "Invalid selection. Using option 1."
    choice=1
  fi
  local idx=$((choice-1))
  if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#options[@]}" ]; then
    idx=0
  fi

  local selected="${options[$idx]}"
  if [ "$selected" = "skip" ]; then
    ok "Model installation skipped."
    pause
    return 0
  fi

  if [ "$selected" = "custom" ]; then
    selected="$(ask "Enter model names separated by spaces" "mistral phi3")"
  fi

  echo ""
  echo "Installing: $selected"
  echo ""

  for m in $selected; do
    echo "Pulling model: $m"
    if ! sudo -u "$AI_USER" "$bin" pull "$m"; then
      warn "Pull as ${AI_USER} failed for ${m}; retrying as current user."
      "$bin" pull "$m" || warn "Could not pull model: $m"
    fi
    echo ""
  done

  ok "Model installation completed (best effort)."
  pause
}

remove_ollama_by_location() {
  header
  local bins
  mapfile -t bins < <(find_ollama_binaries || true)

  if [ "${#bins[@]}" -eq 0 ]; then
    warn "No Ollama binaries found."
    pause
    return 0
  fi

  echo "Detected Ollama binaries:"
  local i=1
  for b in "${bins[@]}"; do
    echo "$i) $b"
    i=$((i+1))
  done
  echo ""
  echo "Select numbers to remove separated by spaces, or type ALL to remove all binaries listed."
  local selection
  selection="$(ask "Selection" "")"

  echo ""
  echo "Stopping services..."
  stop_disable_service ollama

  if [[ "$selection" = "ALL" ]]; then
    for b in "${bins[@]}"; do
      rm -f "$b" || true
    done
    ok "Removed all detected Ollama binaries."
  else
    for s in $selection; do
      if [[ "$s" =~ ^[0-9]+$ ]]; then
        local idx=$((s-1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#bins[@]}" ]; then
          rm -f "${bins[$idx]}" || true
        fi
      fi
    done
    ok "Removed selected binaries (best effort)."
  fi

  echo ""
  echo "Optional cleanup:"
  echo "1) Keep model data"
  echo "2) Remove model data and caches"
  echo ""
  local c
  c="$(ask "Choose cleanup option" "1")"
  if [ "$c" = "2" ]; then
    safe_rm_rf "/usr/local/lib/ollama" /usr/local/lib || true
    safe_rm_rf "/usr/share/ollama" /usr/share || true
    safe_rm_rf "/var/lib/ollama" /var/lib || true
    safe_rm_rf "/home/${AI_USER}/.ollama" /home || true
    safe_rm_rf "/root/.ollama" /root || true
    ok "Model data removed (best effort)."
  else
    ok "Model data kept."
  fi

  echo ""
  echo "Removing service overrides and unit if present..."
  backup_path /etc/systemd/system/ollama.service.d
  backup_path /etc/systemd/system/ollama.service
  safe_rm_rf /etc/systemd/system/ollama.service.d /etc/systemd/system || true
  rm -f /etc/systemd/system/ollama.service || true
  systemctl daemon-reload || true

  pause
}

install_python311() {
  header
  echo "Installing Python 3.11 side-by-side..."
  echo "System python3 is not modified."
  run_required "Installing Python 3.11 packages..." dnf install -y python3.11 python3.11-pip python3.11-devel
  if [ ! -x "$PY311_BIN" ]; then
    fail "Python 3.11 not found at $PY311_BIN"
    pause
    return 1
  fi
  ok "Python 3.11 ready."
  pause
}

install_openwebui() {
  header
  echo "Installing Open WebUI (official Python package in Python 3.11 venv)..."
  echo "Open WebUI will use ${PY311_BIN}; system python3 is left untouched."

  install_python311
  ensure_ai_user
  ensure_base_tools

  if [ -d "$OPENWEBUI_VENV" ]; then
    safe_rm_rf "$OPENWEBUI_VENV" /opt
  fi
  run_required "Creating Open WebUI virtual environment..." "$PY311_BIN" -m venv "$OPENWEBUI_VENV"
  record_manifest "OPENWEBUI_VENV_CREATED" "1"

  run_required "Upgrading pip in Open WebUI venv..." "$OPENWEBUI_VENV/bin/pip" install --upgrade pip
  run_required "Installing Open WebUI package..." "$OPENWEBUI_VENV/bin/pip" install -U "$OPENWEBUI_PACKAGE"
  run_required "Installing modern SQLite compatibility package..." "$OPENWEBUI_VENV/bin/pip" install -U pysqlite3-binary
  if [ ! -x "$OPENWEBUI_VENV/bin/open-webui" ]; then
    fail "Open WebUI command not found at $OPENWEBUI_VENV/bin/open-webui"
    pause
    return 1
  fi

  write_openwebui_sqlite_compat

  mkdir -p "$OPENWEBUI_DATA_DIR"
  mkdir -p "${OPENWEBUI_DATA_DIR}/cache"
  chown -R "$AI_USER:$AI_GROUP" "$OPENWEBUI_DATA_DIR" "$OPENWEBUI_VENV"

  load_manifest
  local ollama_port="${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}"
  local ollama_host="${OLLAMA_BIND_HOST:-0.0.0.0}"
  local ollama_base_host="127.0.0.1"
  local webui_port
  if [ "$ollama_host" != "0.0.0.0" ]; then
    ollama_base_host="$ollama_host"
  fi
  webui_port="$(ask_port "WebUI port" "$WEBUI_PORT_DEFAULT")"

  write_openwebui_env_file "$webui_port" "http://${ollama_base_host}:${ollama_port}"
  write_openwebui_service "$webui_port"

  record_manifest "OPENWEBUI_SERVICE_CREATED" "1"
  record_manifest "OPENWEBUI_PORT" "$webui_port"
  record_manifest "OPENWEBUI_VENV" "$OPENWEBUI_VENV"
  record_manifest "OPENWEBUI_DATA_DIR" "$OPENWEBUI_DATA_DIR"
  record_manifest "OPENWEBUI_ENV_FILE" "$OPENWEBUI_ENV_FILE"
  record_manifest "OPENWEBUI_PACKAGE" "$OPENWEBUI_PACKAGE"
  record_manifest "OPENWEBUI_OLLAMA_BASE_URL" "http://${ollama_base_host}:${ollama_port}"
  OPENWEBUI_PORT="$webui_port"
  systemctl daemon-reload
  systemctl enable openwebui >/dev/null 2>&1
  systemctl restart openwebui

  if wait_openwebui_health "$webui_port"; then
    ok "Open WebUI installed and responding on port ${webui_port}."
  else
    warn "Open WebUI service started, but health did not respond yet. Check: journalctl -u openwebui -e --no-pager"
  fi
  pause
}

write_openwebui_sqlite_compat() {
  local site_packages
  site_packages="$("$OPENWEBUI_VENV/bin/python" -c 'import site; print(site.getsitepackages()[0])')"
  cat > "${site_packages}/sitecustomize.py" <<'EOF'
try:
    import sys
    import pysqlite3

    sys.modules["sqlite3"] = pysqlite3
except Exception:
    pass
EOF
}

write_openwebui_env_file() {
  local webui_port="$1"
  local ollama_base_url="$2"
  cat > "$OPENWEBUI_ENV_FILE" <<EOF
PORT=${webui_port}
DATA_DIR=${OPENWEBUI_DATA_DIR}
OLLAMA_BASE_URL=${ollama_base_url}
UVICORN_WORKERS=1
XDG_CACHE_HOME=${OPENWEBUI_DATA_DIR}/cache
HF_HOME=${OPENWEBUI_DATA_DIR}/cache/huggingface
SENTENCE_TRANSFORMERS_HOME=${OPENWEBUI_DATA_DIR}/cache/sentence-transformers
TRANSFORMERS_CACHE=${OPENWEBUI_DATA_DIR}/cache/transformers
EOF
  chmod 640 "$OPENWEBUI_ENV_FILE"
}

write_openwebui_service() {
  local webui_port="$1"
  backup_path /etc/systemd/system/openwebui.service
  cat > /etc/systemd/system/openwebui.service <<EOF
[Unit]
Description=Open WebUI
After=network-online.target ollama.service
Wants=network-online.target ollama.service

[Service]
Type=simple
WorkingDirectory=${OPENWEBUI_DATA_DIR}
EnvironmentFile=${OPENWEBUI_ENV_FILE}
ExecStart=${OPENWEBUI_VENV}/bin/open-webui serve --host 0.0.0.0 --port ${webui_port}
User=${AI_USER}
Group=${AI_GROUP}
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${OPENWEBUI_DATA_DIR}

[Install]
WantedBy=multi-user.target
EOF
}

wait_openwebui_health() {
  local webui_port="$1"
  echo "Waiting for Open WebUI to respond on port ${webui_port}..."
  echo "The first start may download embedding assets and can take several minutes."
  local attempt
  for attempt in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${webui_port}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  return 1
}

openwebui_package_version() {
  "$OPENWEBUI_VENV/bin/pip" show open-webui 2>/dev/null | awk -F': ' '/^Version:/ {print $2; exit}'
}

openwebui_outdated_versions() {
  local json
  set +e
  json="$("$OPENWEBUI_VENV/bin/pip" list --outdated --format=json 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" -eq 0 ] || return 1
  printf '%s' "$json" | "$OPENWEBUI_VENV/bin/python" -c 'import json,sys
name="open-webui"
for pkg in json.load(sys.stdin):
    pkg_name=pkg.get("name","").lower().replace("_","-")
    if pkg_name == name:
        print(pkg.get("version","") + " " + pkg.get("latest_version",""))
        break'
}

update_openwebui() {
  header
  echo "Checking Open WebUI updates..."
  load_manifest

  local webui_port="${OPENWEBUI_PORT:-$WEBUI_PORT_DEFAULT}"
  local ollama_base_url="${OPENWEBUI_OLLAMA_BASE_URL:-http://127.0.0.1:${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}}"
  local current
  local outdated
  local current_from_outdated
  local latest
  local ans

  if [ ! -x "$OPENWEBUI_VENV/bin/pip" ] || [ ! -x "$OPENWEBUI_VENV/bin/python" ]; then
    fail "Open WebUI venv not found at $OPENWEBUI_VENV. Install Open WebUI first."
    pause
    return 1
  fi

  current="$(openwebui_package_version || true)"
  if [ -z "$current" ]; then
    fail "Open WebUI package is not installed in $OPENWEBUI_VENV."
    pause
    return 1
  fi
  echo "Current Open WebUI version: $current"

  if ! outdated="$(openwebui_outdated_versions)"; then
    warn "Could not check PyPI for Open WebUI updates. Network or pip index may be unavailable."
    echo "Repairing service compatibility and running health check..."
    run_required "Ensuring modern SQLite compatibility package..." "$OPENWEBUI_VENV/bin/pip" install -U pysqlite3-binary
    write_openwebui_sqlite_compat
    mkdir -p "$OPENWEBUI_DATA_DIR/cache"
    chown -R "$AI_USER:$AI_GROUP" "$OPENWEBUI_DATA_DIR" "$OPENWEBUI_VENV"
    write_openwebui_env_file "$webui_port" "$ollama_base_url"
    write_openwebui_service "$webui_port"
    systemctl daemon-reload
    systemctl restart openwebui
    if wait_openwebui_health "$webui_port"; then
      ok "Open WebUI is healthy on port ${webui_port}."
    else
      fail "Open WebUI health check failed after repair."
      journalctl -u openwebui -n 120 --no-pager || true
      pause
      return 1
    fi
    pause
    return 0
  fi
  if [ -z "$outdated" ]; then
    ok "No Open WebUI update reported by pip."
    echo "Repairing service compatibility and running health check..."
    run_required "Ensuring modern SQLite compatibility package..." "$OPENWEBUI_VENV/bin/pip" install -U pysqlite3-binary
    write_openwebui_sqlite_compat
    mkdir -p "$OPENWEBUI_DATA_DIR/cache"
    chown -R "$AI_USER:$AI_GROUP" "$OPENWEBUI_DATA_DIR" "$OPENWEBUI_VENV"
    write_openwebui_env_file "$webui_port" "$ollama_base_url"
    write_openwebui_service "$webui_port"
    systemctl daemon-reload
    systemctl restart openwebui
    if wait_openwebui_health "$webui_port"; then
      ok "Open WebUI is healthy on port ${webui_port}."
    else
      fail "Open WebUI health check failed after repair."
      journalctl -u openwebui -n 120 --no-pager || true
      pause
      return 1
    fi
    pause
    return 0
  fi

  current_from_outdated="${outdated%% *}"
  latest="${outdated#* }"
  echo "Update available: ${current_from_outdated} -> ${latest}"
  ans="$(confirm_proceed "Apply Open WebUI update now yes or no" "yes")"
  if ! is_yes "$ans"; then
    warn "Update cancelled."
    pause
    return 0
  fi

  systemctl stop openwebui >/dev/null 2>&1 || true
  run_required "Upgrading pip in Open WebUI venv..." "$OPENWEBUI_VENV/bin/pip" install --upgrade pip
  run_required "Updating Open WebUI package..." "$OPENWEBUI_VENV/bin/pip" install -U "$OPENWEBUI_PACKAGE"
  run_required "Ensuring modern SQLite compatibility package..." "$OPENWEBUI_VENV/bin/pip" install -U pysqlite3-binary
  if [ ! -x "$OPENWEBUI_VENV/bin/open-webui" ]; then
    fail "Open WebUI command not found after update: $OPENWEBUI_VENV/bin/open-webui"
    pause
    return 1
  fi
  write_openwebui_sqlite_compat
  mkdir -p "$OPENWEBUI_DATA_DIR/cache"
  chown -R "$AI_USER:$AI_GROUP" "$OPENWEBUI_DATA_DIR" "$OPENWEBUI_VENV"
  write_openwebui_env_file "$webui_port" "$ollama_base_url"
  write_openwebui_service "$webui_port"
  record_manifest "OPENWEBUI_PACKAGE" "$OPENWEBUI_PACKAGE"
  record_manifest "OPENWEBUI_PORT" "$webui_port"
  record_manifest "OPENWEBUI_OLLAMA_BASE_URL" "$ollama_base_url"
  systemctl daemon-reload
  systemctl enable openwebui >/dev/null 2>&1
  systemctl restart openwebui

  if wait_openwebui_health "$webui_port"; then
    ok "Open WebUI updated and healthy: $(openwebui_package_version)"
  else
    fail "Open WebUI update completed, but health check failed."
    journalctl -u openwebui -n 120 --no-pager || true
    pause
    return 1
  fi
  pause
}

openwebui_health_check() {
  header
  local port
  port="$(ask_port "WebUI port" "$WEBUI_PORT_DEFAULT")"
  if curl -fsS "http://127.0.0.1:${port}/health" >/dev/null 2>&1 || curl -fsS "http://127.0.0.1:${port}" >/dev/null 2>&1; then
    ok "Open WebUI responding on localhost."
  else
    fail "Open WebUI not responding."
  fi
  pause
}

configure_firewall_lan_only() {
  header
  load_manifest
  local subnet
  subnet="$(ask_cidr "LAN subnet allowed" "$LAN_SUBNET_DEFAULT")"
  local oport
  oport="$(ask_port "Ollama port" "${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}")"
  local wport
  wport="$(ask_port "WebUI port" "${OPENWEBUI_PORT:-$WEBUI_PORT_DEFAULT}")"
  local ollama_rule
  local webui_rule

  ollama_rule="rule family='ipv4' source address='${subnet}' port protocol='tcp' port='${oport}' accept"
  webui_rule="rule family='ipv4' source address='${subnet}' port protocol='tcp' port='${wport}' accept"

  systemctl enable firewalld >/dev/null 2>&1
  systemctl start firewalld >/dev/null 2>&1

  firewall-cmd --permanent --add-rich-rule="$ollama_rule"
  firewall-cmd --permanent --add-rich-rule="$webui_rule"
  firewall-cmd --reload

  record_manifest "FIREWALL_CONFIGURED" "1"
  record_manifest "FIREWALL_RULE_OLLAMA" "$ollama_rule"
  record_manifest "FIREWALL_RULE_WEBUI" "$webui_rule"
  record_manifest "LAN_SUBNET" "$subnet"

  ok "Firewall configured for LAN only."
  pause
}

show_ports_and_services() {
  header
  echo "Listening ports and owning processes:"
  echo ""
  ss -tulpen || true
  echo ""
  echo "Service status summary:"
  echo ""
  systemctl status ollama --no-pager || true
  echo ""
  systemctl status openwebui --no-pager || true
  echo ""
  echo "Ollama environment and unit path:"
  systemctl show ollama -p Environment --no-pager || true
  systemctl show ollama -p FragmentPath --no-pager || true
  echo ""
  echo "Open WebUI unit path:"
  systemctl show openwebui -p FragmentPath --no-pager || true
  pause
}

stop_disable_service() {
  local service="$1"
  systemctl stop "$service" >/dev/null 2>&1 || true
  systemctl disable "$service" >/dev/null 2>&1 || true
}

remove_openwebui_installation() {
  local purge="$1"
  local service_file="/etc/systemd/system/openwebui.service"
  local legacy_dir="${OPENWEBUI_DIR:-/opt/open-webui}"
  local venv="${OPENWEBUI_VENV:-/opt/open-webui-venv}"
  local data_dir="${OPENWEBUI_DATA_DIR:-/var/lib/open-webui}"
  local env_file="${OPENWEBUI_ENV_FILE:-/etc/xemi-ai/openwebui.env}"

  if [ -n "${OPENWEBUI_VENV:-}" ]; then
    venv="$OPENWEBUI_VENV"
  fi
  if [ -n "${OPENWEBUI_DATA_DIR:-}" ]; then
    data_dir="$OPENWEBUI_DATA_DIR"
  fi
  if [ -n "${OPENWEBUI_ENV_FILE:-}" ]; then
    env_file="$OPENWEBUI_ENV_FILE"
  fi

  stop_disable_service openwebui

  if [ -f "$service_file" ]; then
    backup_path "$service_file"
    rm -f "$service_file"
    ok "Open WebUI service removed."
  fi

  if [ -d "$venv" ]; then
    safe_rm_rf "$venv" /opt
    ok "Open WebUI venv removed: $venv"
  fi

  if [ -f "$env_file" ]; then
    backup_path "$env_file"
    rm -f "$env_file"
    ok "Open WebUI env file removed: $env_file"
  fi

  if [ "$purge" = "1" ] && [ -d "$data_dir" ]; then
    backup_path "$data_dir"
    safe_rm_rf "$data_dir" /var/lib
    ok "Open WebUI data removed: $data_dir"
  elif [ -d "$data_dir" ]; then
    warn "Open WebUI data kept: $data_dir"
  fi

  if [ "$purge" = "1" ] && [ -d "$legacy_dir" ]; then
    backup_path "$legacy_dir"
    safe_rm_rf "$legacy_dir" /opt
    ok "Legacy Open WebUI source directory removed: $legacy_dir"
  fi
}

remove_ollama_installation() {
  local purge="$1"
  local bins=()

  stop_disable_service ollama

  if [ "${OLLAMA_OVERRIDE_CREATED:-}" = "1" ] || [ -f /etc/systemd/system/ollama.service.d/override.conf ]; then
    backup_path /etc/systemd/system/ollama.service.d
    rm -f /etc/systemd/system/ollama.service.d/override.conf
    rmdir /etc/systemd/system/ollama.service.d >/dev/null 2>&1 || true
    ok "Ollama systemd override removed."
  fi

  if [ "$purge" = "1" ]; then
    mapfile -t bins < <(find_ollama_binaries || true)
    for b in "${bins[@]:-}"; do
      rm -f "$b" || true
      ok "Ollama binary removed: $b"
    done

    backup_path /etc/systemd/system/ollama.service
    rm -f /etc/systemd/system/ollama.service
    safe_rm_rf /usr/local/lib/ollama /usr/local/lib
    safe_rm_rf /usr/share/ollama /usr/share
    safe_rm_rf /var/lib/ollama /var/lib
    safe_rm_rf "/home/${AI_USER}/.ollama" /home
    safe_rm_rf /root/.ollama /root
    ok "Ollama service, libraries and model data removed."
  else
    warn "Ollama binary and model data kept."
  fi
}

remove_firewall_configuration() {
  if [ "${FIREWALL_CONFIGURED:-}" != "1" ]; then
    return 0
  fi

  if systemctl is-active firewalld >/dev/null 2>&1; then
    remove_firewall_rule "${FIREWALL_RULE_OLLAMA:-}"
    remove_firewall_rule "${FIREWALL_RULE_WEBUI:-}"
    firewall-cmd --reload >/dev/null 2>&1 || true
    ok "Firewall rules removed."
  else
    warn "firewalld is not active; firewall rules were not removed."
  fi
}

remove_ai_identity_if_created() {
  if [ "${AI_USER_CREATED:-}" = "1" ] && id "$AI_USER" >/dev/null 2>&1; then
    userdel -r "$AI_USER" >/dev/null 2>&1 || userdel "$AI_USER" >/dev/null 2>&1 || true
    ok "User removed: $AI_USER"
  fi

  if [ "${AI_GROUP_CREATED:-}" = "1" ] && getent group "$AI_GROUP" >/dev/null 2>&1; then
    groupdel "$AI_GROUP" >/dev/null 2>&1 || true
    ok "Group removed: $AI_GROUP"
  fi
}

uninstall_stack() {
  local purge="${1:-0}"
  header
  load_manifest

  if [ "$purge" = "1" ]; then
    echo "This will purge services, Open WebUI, Ollama binaries/data, firewall rules and created user."
  else
    echo "This will uninstall services, Open WebUI venv and firewall rules while keeping Ollama binaries/models."
  fi

  local ans
  ans="$(confirm_proceed "Proceed yes or no" "no")"
  if ! is_yes "$ans"; then
    warn "Cancelled."
    pause
    return 0
  fi

  remove_firewall_configuration
  remove_openwebui_installation "$purge"
  remove_ollama_installation "$purge"
  systemctl daemon-reload || true

  if [ "$purge" = "1" ]; then
    remove_ai_identity_if_created
    backup_path "$MANIFEST_FILE"
    rm -f "$MANIFEST_FILE"
    safe_rm_rf "$CONFIG_DIR" /etc/xemi-ai
    ok "Purge completed."
  else
    ok "Uninstall completed."
  fi

  pause
}

redact_sensitive_stream() {
  sed -E 's/([A-Za-z0-9_]*(PASSWORD|PASS|SECRET|TOKEN|API_KEY|KEY)[A-Za-z0-9_]*=)[^[:space:]]+/\1<redacted>/g'
}

show_file_if_present() {
  local label="$1"
  local path="$2"
  echo "${label}: ${path}"
  if [ -e "$path" ]; then
    ls -ld "$path" || true
  else
    echo "  missing"
  fi
}

show_http_probe() {
  local label="$1"
  local url="$2"
  if curl -fsS --max-time 5 "$url" >/dev/null 2>&1; then
    echo "  OK    ${label}: ${url}"
  else
    echo "  FAIL  ${label}: ${url}"
  fi
}

show_install_state() {
  header
  load_manifest

  local host_ips
  local ollama_env
  local ollama_port="${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}"
  local ollama_bind="${OLLAMA_BIND_HOST:-0.0.0.0}"
  local ollama_models_dir
  local webui_port="${OPENWEBUI_PORT:-$WEBUI_PORT_DEFAULT}"
  local openwebui_data="${OPENWEBUI_DATA_DIR:-/var/lib/open-webui}"
  local openwebui_env="${OPENWEBUI_ENV_FILE:-/etc/xemi-ai/openwebui.env}"
  local openwebui_base_url="${OPENWEBUI_OLLAMA_BASE_URL:-http://127.0.0.1:${ollama_port}}"
  local first_ip=""
  local bin

  host_ips="$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $2 " " $4}' || true)"
  first_ip="$(printf '%s\n' "$host_ips" | awk 'NR==1 {sub(/\/.*/, "", $2); print $2}')"
  ollama_env="$(systemctl show ollama -p Environment --no-pager 2>/dev/null || true)"
  if echo "$ollama_env" | grep -q 'OLLAMA_HOST='; then
    ollama_bind="$(printf '%s\n' "$ollama_env" | tr ' ' '\n' | awk -F= '/^OLLAMA_HOST=/ {print $2; exit}' | sed -E 's/:[0-9]+$//')"
    ollama_port="$(printf '%s\n' "$ollama_env" | tr ' ' '\n' | awk -F= '/^OLLAMA_HOST=/ {print $2; exit}' | awk -F: '{print $NF}')"
  fi
  ollama_models_dir="$(current_ollama_models_dir 2>/dev/null || default_ollama_models_dir)"

  echo "Xemi AI installation report"
  echo "Generated: $(date '+%F %T %Z')"
  echo ""

  echo "== Host =="
  echo "Hostname: $(hostname -f 2>/dev/null || hostname)"
  echo "OS:"
  if [ -r /etc/os-release ]; then
    awk -F= '/^(PRETTY_NAME|VERSION_ID|ID)=/ {gsub(/"/, "", $2); print "  " $1 ": " $2}' /etc/os-release
  fi
  echo "Kernel: $(uname -r)"
  echo "IPv4 addresses:"
  if [ -n "$host_ips" ]; then
    printf '  %s\n' "$host_ips"
  else
    echo "  none detected"
  fi
  echo ""

  echo "== Installer State =="
  echo "State directory: $STATE_DIR"
  echo "Manifest: $MANIFEST_FILE"
  echo "Log: $LOG_FILE"
  if [ -f "$MANIFEST_FILE" ]; then
    echo "Manifest values (sensitive values redacted):"
    sed -n '1,240p' "$MANIFEST_FILE" | redact_sensitive_stream
  else
    echo "No manifest found."
  fi
  echo ""

  echo "== Service Users =="
  echo "Configured AI user/group: ${AI_USER}:${AI_GROUP}"
  if id "$AI_USER" >/dev/null 2>&1; then
    id "$AI_USER"
    echo "Home: $(getent passwd "$AI_USER" | awk -F: '{print $6}')"
  else
    echo "User missing: $AI_USER"
  fi
  if getent group "$AI_GROUP" >/dev/null 2>&1; then
    getent group "$AI_GROUP"
  else
    echo "Group missing: $AI_GROUP"
  fi
  echo "Passwords: Linux account passwords are not stored by this installer."
  echo ""

  echo "== Ollama =="
  echo "Binary: $(command -v ollama 2>/dev/null || echo missing)"
  ollama --version 2>/dev/null || true
  echo "Service active: $(systemctl is-active ollama 2>/dev/null || true)"
  echo "Service enabled: $(systemctl is-enabled ollama 2>/dev/null || true)"
  systemctl show ollama -p User -p Group -p FragmentPath --no-pager 2>/dev/null || true
  echo "Environment:"
  systemctl show ollama -p Environment --no-pager 2>/dev/null | redact_sensitive_stream || true
  echo "Bind: ${ollama_bind}:${ollama_port}"
  echo "Model directory: ${ollama_models_dir}"
  if [ -d "$ollama_models_dir" ]; then
    ls -ld "$ollama_models_dir" || true
    du -sh "$ollama_models_dir" 2>/dev/null || true
    df -h "$ollama_models_dir" 2>/dev/null || true
  else
    echo "Model directory missing."
  fi
  echo "Installed models:"
  if bin="$(choose_ollama_binary 2>/dev/null)"; then
    sudo -u "$AI_USER" "$bin" list 2>/dev/null || "$bin" list 2>/dev/null || true
  else
    echo "  Ollama binary not found."
  fi
  echo ""

  echo "== Open WebUI =="
  echo "Venv: $OPENWEBUI_VENV"
  echo "Command: $OPENWEBUI_VENV/bin/open-webui"
  if [ -x "$OPENWEBUI_VENV/bin/open-webui" ]; then
    "$OPENWEBUI_VENV/bin/pip" show open-webui 2>/dev/null | awk -F': ' '/^(Name|Version|Location):/ {print $1 ": " $2}' || true
  else
    echo "Open WebUI command missing."
  fi
  echo "Service active: $(systemctl is-active openwebui 2>/dev/null || true)"
  echo "Service enabled: $(systemctl is-enabled openwebui 2>/dev/null || true)"
  systemctl show openwebui -p User -p Group -p FragmentPath --no-pager 2>/dev/null || true
  show_file_if_present "Data directory" "$openwebui_data"
  du -sh "$openwebui_data" 2>/dev/null || true
  show_file_if_present "Environment file" "$openwebui_env"
  if [ -f "$openwebui_env" ]; then
    echo "Environment file values (sensitive values redacted):"
    sed -n '1,200p' "$openwebui_env" | redact_sensitive_stream
  fi
  echo "Configured Ollama base URL for Open WebUI: ${openwebui_base_url}"
  echo "Web UI port: ${webui_port}"
  echo "Open WebUI secret key file:"
  show_file_if_present "WEBUI_SECRET_KEY" "${openwebui_data}/.webui_secret_key"
  echo "  value: <redacted>"
  echo ""

  echo "== Open WebUI Users =="
  echo "Passwords are not recoverable in clear text. Stored hashes/secrets are not printed."
  if [ -f "${openwebui_data}/webui.db" ]; then
    "$OPENWEBUI_VENV/bin/python" - "$openwebui_data/webui.db" <<'PY' 2>/dev/null || true
import sqlite3, sys, datetime
db = sys.argv[1]
con = sqlite3.connect(db)
cur = con.cursor()
try:
    rows = cur.execute("""
        select u.email, coalesce(u.username, ''), u.name, u.role,
               coalesce(a.active, 0), case when length(coalesce(a.password, '')) > 0 then 1 else 0 end,
               u.created_at, u.last_active_at
        from user u left join auth a on a.id = u.id
        order by u.role, u.email
    """).fetchall()
except Exception as exc:
    print(f"  Could not read users: {exc}")
    sys.exit(0)
if not rows:
    print("  No Open WebUI users found yet.")
else:
    print("  email | username | name | role | active | password_hash | created | last_active")
    for email, username, name, role, active, has_hash, created, last_active in rows:
        def ts(v):
            try:
                v = int(v)
                if v > 1000000000000:
                    v = v / 1000
                return datetime.datetime.fromtimestamp(v).strftime("%Y-%m-%d %H:%M:%S")
            except Exception:
                return ""
        print(f"  {email} | {username} | {name} | {role} | {bool(active)} | {'present' if has_hash else 'missing'} | {ts(created)} | {ts(last_active)}")
PY
  else
    echo "  Open WebUI database not found at ${openwebui_data}/webui.db"
  fi
  echo ""

  echo "== Open WebUI API Keys And Tokens =="
  echo "API keys and OAuth tokens are sensitive and are not printed. This only reports presence/metadata."
  if [ -f "${openwebui_data}/webui.db" ]; then
    "$OPENWEBUI_VENV/bin/python" - "$openwebui_data/webui.db" <<'PY' 2>/dev/null || true
import sqlite3, sys, datetime
db = sys.argv[1]
con = sqlite3.connect(db)
cur = con.cursor()

def ts(v):
    try:
        if v is None:
            return ""
        v = int(v)
        if v > 1000000000000:
            v = v / 1000
        return datetime.datetime.fromtimestamp(v).strftime("%Y-%m-%d %H:%M:%S")
    except Exception:
        return ""

try:
    rows = cur.execute("""
        select coalesce(u.email, a.user_id), a.id, a.expires_at, a.last_used_at, a.created_at
        from api_key a left join user u on u.id = a.user_id
        order by a.created_at desc
    """).fetchall()
except Exception:
    rows = []

if rows:
    print("  API keys:")
    print("  owner | key_id | secret | expires | last_used | created")
    for owner, key_id, expires, last_used, created in rows:
        print(f"  {owner} | {key_id} | <redacted> | {ts(expires)} | {ts(last_used)} | {ts(created)}")
else:
    print("  API keys: none found")

try:
    oauth = cur.execute("""
        select coalesce(u.email, o.user_id), o.provider, count(*), max(o.expires_at), max(o.updated_at)
        from oauth_session o left join user u on u.id = o.user_id
        group by coalesce(u.email, o.user_id), o.provider
        order by coalesce(u.email, o.user_id), o.provider
    """).fetchall()
except Exception:
    oauth = []

if oauth:
    print("  OAuth sessions:")
    print("  owner | provider | count | max_expires | last_updated")
    for owner, provider, count, expires, updated in oauth:
        print(f"  {owner} | {provider} | {count} | {ts(expires)} | {ts(updated)}")
else:
    print("  OAuth sessions: none found")
PY
  else
    echo "  Open WebUI database not found at ${openwebui_data}/webui.db"
  fi
  echo ""

  echo "== Endpoints And How To Connect =="
  echo "Local endpoints:"
  echo "  Ollama API:       http://127.0.0.1:${ollama_port}"
  echo "  Ollama tags:      http://127.0.0.1:${ollama_port}/api/tags"
  echo "  Open WebUI:       http://127.0.0.1:${webui_port}"
  echo "  Open WebUI health:http://127.0.0.1:${webui_port}/health"
  if [ -n "$first_ip" ]; then
    echo "LAN endpoints:"
    echo "  Ollama API:       http://${first_ip}:${ollama_port}"
    echo "  Open WebUI:       http://${first_ip}:${webui_port}"
  fi
  echo "Example Ollama API calls:"
  echo "  curl http://127.0.0.1:${ollama_port}/api/tags"
  echo "  curl http://127.0.0.1:${ollama_port}/api/generate -d '{\"model\":\"phi3\",\"prompt\":\"hello\",\"stream\":false}'"
  echo "Open WebUI login/API keys:"
  echo "  Create/login users in the web UI. API keys, if enabled, are managed inside Open WebUI and are not printed here."
  echo ""

  echo "== Health Checks =="
  show_http_probe "Ollama API" "http://127.0.0.1:${ollama_port}/api/tags"
  show_http_probe "Open WebUI health" "http://127.0.0.1:${webui_port}/health"
  echo ""

  echo "== Firewall =="
  echo "firewalld active: $(systemctl is-active firewalld 2>/dev/null || true)"
  echo "Configured LAN subnet: ${LAN_SUBNET:-$LAN_SUBNET_DEFAULT}"
  if cmd_exists firewall-cmd; then
    echo "Permanent rich rules:"
    firewall-cmd --permanent --list-rich-rules 2>/dev/null | sed 's/^/  /' || true
  fi
  echo ""

  echo "== GPU =="
  if cmd_exists nvidia-smi; then
    nvidia-smi --query-gpu=name,uuid,memory.total,driver_version --format=csv,noheader 2>/dev/null | sed 's/^/  /' || true
  else
    echo "  nvidia-smi not found."
  fi
  echo ""

  echo "== Useful Commands =="
  echo "  sudo /usr/local/bin/xemi_ai_install.sh doctor"
  echo "  sudo /usr/local/bin/xemi_ai_install.sh openwebui-update"
  echo "  sudo /usr/local/bin/xemi_ai_install.sh models-dir"
  echo "  journalctl -u ollama -e --no-pager"
  echo "  journalctl -u openwebui -e --no-pager"
  pause
}

DOCTOR_FAILURES=0

doctor_ok() {
  echo -e "${GREEN}OK${NC} , $1"
}

doctor_fail() {
  echo -e "${RED}FAIL${NC} , $1"
  DOCTOR_FAILURES=$((DOCTOR_FAILURES+1))
}

doctor_warn() {
  echo -e "${YELLOW}WARN${NC} , $1"
}

doctor_check_command() {
  local cmd="$1"
  if cmd_exists "$cmd"; then
    doctor_ok "Command available: $cmd"
  else
    doctor_fail "Missing command: $cmd"
  fi
}

doctor_check_service() {
  local service="$1"
  if systemctl is-enabled "$service" >/dev/null 2>&1; then
    doctor_ok "${service} autostart enabled"
  else
    doctor_fail "${service} autostart is not enabled"
  fi

  if systemctl is-active "$service" >/dev/null 2>&1; then
    doctor_ok "${service} is running"
  else
    doctor_fail "${service} is not running"
  fi
}

doctor_check_gpu() {
  local mode=""
  if ensure_nvidia_gpu_ready; then
    doctor_ok "NVIDIA GPU is visible through nvidia-smi"
  elif [ "$ALLOW_CPU_FALLBACK" = "1" ]; then
    doctor_warn "GPU is not ready, but ALLOW_CPU_FALLBACK=1"
    return 0
  else
    doctor_fail "GPU is not ready; Ollama cannot be guaranteed to use GPU"
    return 0
  fi

  if verify_ollama_runtime_libs; then
    doctor_ok "Ollama runtime libraries are present"
  else
    doctor_fail "Ollama runtime libraries are incomplete"
  fi

  mode="$(ollama_current_compute_mode 2>/dev/null || true)"
  if [ "$mode" = "gpu" ]; then
    doctor_ok "Ollama bootstrapped with CUDA"
  elif [ "$mode" = "cpu" ]; then
    doctor_fail "Ollama bootstrapped in CPU mode despite NVIDIA GPU availability"
  else
    doctor_warn "Could not determine Ollama compute mode from current service logs yet"
  fi
}

doctor_check_http() {
  local name="$1"
  local url="$2"
  local attempts=6
  local delay=3
  local i

  for ((i=1; i<=attempts; i++)); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      doctor_ok "${name} responds: ${url}"
      return 0
    fi
    sleep "$delay"
  done

  doctor_fail "${name} does not respond: ${url}"
}

doctor_check_ollama_gpu_logs() {
  local logs
  if ! cmd_exists journalctl; then
    doctor_warn "journalctl not found; cannot inspect Ollama GPU logs"
    return 0
  fi

  logs="$(journalctl -u ollama -n 400 --no-pager 2>/dev/null || true)"
  if [ -z "$logs" ]; then
    doctor_warn "No Ollama journal logs available yet; run a model and re-run doctor"
    return 0
  fi

  if echo "$logs" | grep -Eiq "cuda|nvidia|gpu|ggml_cuda|library=cuda|compute capability"; then
    doctor_ok "Ollama logs include GPU/CUDA signals"
  else
    doctor_warn "Ollama logs do not yet show GPU/CUDA signals; pull/run a model and re-run doctor"
  fi
}

doctor_check_ollama_models_dir() {
  local env_line
  if [ -z "${OLLAMA_MODELS_DIR:-}" ]; then
    doctor_warn "Custom Ollama model directory is not configured; using Ollama default"
    return 0
  fi
  if [ -d "$OLLAMA_MODELS_DIR" ]; then
    doctor_ok "Ollama model directory exists: $OLLAMA_MODELS_DIR"
  else
    doctor_fail "Ollama model directory missing: $OLLAMA_MODELS_DIR"
    return 0
  fi
  env_line="$(systemctl show ollama -p Environment --no-pager 2>/dev/null || true)"
  if echo "$env_line" | grep -Fq "OLLAMA_MODELS=${OLLAMA_MODELS_DIR}"; then
    doctor_ok "Ollama service uses configured model directory"
  else
    doctor_fail "Ollama service does not expose OLLAMA_MODELS=${OLLAMA_MODELS_DIR}"
  fi
}

doctor_check_firewall() {
  if [ "${FIREWALL_CONFIGURED:-}" != "1" ]; then
    doctor_warn "Firewall was not configured by this installer yet"
    return 0
  fi

  if ! systemctl is-active firewalld >/dev/null 2>&1; then
    doctor_fail "firewalld is not running"
    return 0
  fi

  if [ -n "${FIREWALL_RULE_OLLAMA:-}" ] && firewall-cmd --permanent --query-rich-rule="${FIREWALL_RULE_OLLAMA}" >/dev/null 2>&1; then
    doctor_ok "Firewall rule exists for Ollama"
  else
    doctor_fail "Firewall rule missing for Ollama"
  fi

  if [ -n "${FIREWALL_RULE_WEBUI:-}" ] && firewall-cmd --permanent --query-rich-rule="${FIREWALL_RULE_WEBUI}" >/dev/null 2>&1; then
    doctor_ok "Firewall rule exists for Open WebUI"
  else
    doctor_fail "Firewall rule missing for Open WebUI"
  fi
}

doctor() {
  header
  load_manifest
  DOCTOR_FAILURES=0

  local ollama_port="${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}"
  local webui_port="${OPENWEBUI_PORT:-$WEBUI_PORT_DEFAULT}"

  echo "Checking server readiness..."
  echo ""

  doctor_check_command dnf
  doctor_check_command systemctl
  doctor_check_command curl
  doctor_check_command "$PY311_BIN"
  doctor_check_command ollama
  doctor_check_command "$OPENWEBUI_VENV/bin/open-webui"
  echo ""

  doctor_check_gpu
  echo ""

  doctor_check_service ollama
  doctor_check_http "Ollama API" "http://127.0.0.1:${ollama_port}/api/tags"
  doctor_check_ollama_gpu_logs
  doctor_check_ollama_models_dir
  echo ""

  doctor_check_service openwebui
  doctor_check_http "Open WebUI health" "http://127.0.0.1:${webui_port}/health"
  echo ""

  doctor_check_firewall
  echo ""

  if [ "$DOCTOR_FAILURES" -eq 0 ]; then
    ok "Doctor completed: server is ready."
  else
    fail "Doctor completed with ${DOCTOR_FAILURES} failure(s)."
  fi

  pause
}

full_install_drivers() {
  header
  echo "Stage 1, drivers and reboot"
  local ans
  ans="$(confirm_proceed "Proceed yes or no" "yes")"
  if ! is_yes "$ans"; then
    warn "Cancelled."
    pause
    return 0
  fi
  preflight_supported_system
  ensure_base_tools
  enable_repos
  install_nvidia_drivers
}

full_install_stack() {
  header
  echo "Stage 2, AI stack"
  local ans
  ans="$(confirm_proceed "Proceed yes or no" "yes")"
  if ! is_yes "$ans"; then
    warn "Cancelled."
    pause
    return 0
  fi
  preflight_supported_system
  ensure_base_tools
  ensure_ai_user
  install_ollama_official
  configure_ollama_service_lan
  if [ -n "${OLLAMA_MODELS_DIR:-}" ]; then
    configure_ollama_models_dir
  fi
  recommend_and_install_models
  install_openwebui
  configure_firewall_lan_only
  doctor
  ok "AI stack installed."
  pause
}

full_new_server_setup() {
  header
  echo "Full new server setup"
  echo "This will prepare repositories/tools, ensure NVIDIA GPU readiness, install Ollama, Open WebUI, autostart services, models and firewall rules."
  local ans existing_action
  ans="$(confirm_proceed "Proceed yes or no" "yes")"
  if ! is_yes "$ans"; then
    warn "Cancelled."
    pause
    return 0
  fi

  preflight_supported_system
  ensure_base_tools
  enable_repos

  if ! ensure_nvidia_gpu_ready; then
    warn "NVIDIA GPU is not ready. Installing NVIDIA drivers now."
    install_nvidia_drivers
    if ! ensure_nvidia_gpu_ready; then
      fail "NVIDIA GPU is still not ready. Reboot, then run: $0 install"
      pause
      return 1
    fi
  fi

  if has_existing_installation; then
    echo ""
    echo "Existing installation detected."
    echo "1) Exit without changes"
    echo "2) Repair and verify the existing installation"
    existing_action="$(ask "Choose 1 or 2" "2")"
    case "$existing_action" in
      1)
        warn "No changes made."
        pause
        return 0
        ;;
      2)
        ok "Running repair and integrity checks instead of a full reinstall."
        repair_existing_installation
        ;;
      *)
        warn "Invalid choice. No changes made."
        pause
        return 0
        ;;
    esac
  else
    full_install_stack
  fi
}

menu() {
  while true; do
    header
    menu_section "Guided Installation"
    menu_item 1 "Full new server setup or repair existing installation (GPU prioritized)"
    menu_item 2 "Stage 1, install NVIDIA drivers and reboot"
    menu_item 3 "Stage 2, install AI stack (Ollama, models, WebUI, firewall)"
    echo ""

    menu_section "Hardware And Status"
    menu_item 4 "Show GPU info and recommendations"
    menu_item 5 "Show Ollama status, service, location"
    echo ""

    menu_section "Ollama Service"
    menu_item 6 "Install Ollama (official installer)"
    menu_item 7 "Configure Ollama service for LAN"
    menu_item 8 "Ollama health check"
    echo ""

    menu_section "Models"
    menu_item 9 "Configure Ollama models directory / migrate model data"
    menu_item 10 "Recommend and install models (choose set)"
    menu_item 11 "List models"
    menu_item 12 "Test a model interaction and verify GPU/CPU usage"
    menu_item 13 "Remove models (interactive)"
    echo ""

    menu_section "Ollama Removal"
    menu_item 14 "Remove Ollama by location (discover multiple and remove)"
    echo ""

    menu_section "Open WebUI"
    menu_item 14 "Install Python 3.11"
    menu_item 15 "Install Open WebUI (Python 3.11 venv service)"
    menu_item 16 "Check/apply Open WebUI updates"
    menu_item 17 "Open WebUI health check"
    echo ""

    menu_section "Network"
    menu_item 18 "Configure firewall (LAN only)"
    menu_item 19 "Show ports in use and service bindings"
    echo ""

    menu_section "Diagnostics And Maintenance"
    menu_item 20 "Show detailed installation report"
    menu_item 21 "Run doctor readiness check"
    menu_item 22 "Uninstall stack (keep Ollama data)"
    menu_item 23 "Purge stack (reset to zero)"
    echo ""

    menu_section "Session"
    menu_item 25 "Exit"
    echo ""

    local opt
    opt="$(ask "Select option" "25")"
    sleep_screen

    case "$opt" in
      1) full_new_server_setup ;;
      2) full_install_drivers ;;
      3) full_install_stack ;;
      4) gpu_info_and_recommendations ;;
      5) show_ollama_status_and_location ;;
      6) install_ollama_official ;;
      7) configure_ollama_service_lan ;;
      8) ollama_health_check ;;
      9) configure_ollama_models_dir ;;
      10) recommend_and_install_models ;;
      11) list_ollama_models ;;
      12) test_ollama_model_interaction ;;
      13) remove_ollama_models_interactive ;;
      14) remove_ollama_by_location ;;
      15) install_python311 ;;
      16) install_openwebui ;;
      17) update_openwebui ;;
      18) openwebui_health_check ;;
      19) configure_firewall_lan_only ;;
      20) show_ports_and_services ;;
      21) show_install_state ;;
      22) doctor ;;
      23) uninstall_stack 0 ;;
      24) uninstall_stack 1 ;;
      25) exit 0 ;;
      *) warn "Invalid option." ; sleep_screen ;;
    esac
  done
}

usage() {
  cat <<EOF
Usage: $0 [command] [options]

Commands:
  menu        Open interactive menu (default)
  install     Full new server setup
  repair      Repair and verify existing installation
  stack       Install AI stack only, assuming drivers are ready
  drivers     Install NVIDIA driver stage
  models-dir  Configure/migrate Ollama model storage directory
  openwebui-update
              Check/apply Open WebUI package updates
  doctor      Run readiness checks
  uninstall   Remove services/Open WebUI, keep Ollama data
  purge       Reset installation to zero
  status      Show ports and service status
  state       Show detailed installed configuration report
  report      Alias for state

Options:
  -y, --yes                    Use defaults and skip pauses
  -n, --dry-run                Print the resolved plan without changing the system
  --ollama-port PORT           Set Ollama port (default: ${OLLAMA_PORT_DEFAULT})
  --webui-port PORT            Set Open WebUI port (default: ${WEBUI_PORT_DEFAULT})
  --lan CIDR                   Set allowed LAN subnet (default: ${LAN_SUBNET_DEFAULT})
  --ollama-bind-host HOST      Set Ollama bind host (default: ${OLLAMA_BIND_HOST})
  --ollama-models-dir PATH     Set custom Ollama model directory
  --ai-user USER               Set service user (default: ${AI_USER})
  --ai-group GROUP             Set service group (default: ${AI_GROUP})
  --openwebui-package PACKAGE  Set pip package, for example open-webui==0.7.2
  --ollama-version VERSION     Set OLLAMA_VERSION for the official installer
  --ollama-install-sha256 SUM  Verify downloaded Ollama installer script
  --allow-cpu-fallback         Allow install without confirmed NVIDIA GPU
  --reboot                     Allow automatic reboot after driver install
  -h, --help                   Show this help
EOF
}

parse_args() {
  COMMAND="menu"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help|help)
        COMMAND="help"
        shift
        ;;
      -y|--yes)
        ASSUME_YES=1
        shift
        ;;
      -n|--dry-run)
        DRY_RUN=1
        ASSUME_YES=1
        shift
        ;;
      --ollama-port)
        [ "$#" -ge 2 ] || { echo "Missing value for --ollama-port"; exit 1; }
        validate_port "$2" || { echo "Invalid --ollama-port: $2"; exit 1; }
        OLLAMA_PORT_DEFAULT="$2"
        OLLAMA_PORT="$2"
        shift 2
        ;;
      --webui-port)
        [ "$#" -ge 2 ] || { echo "Missing value for --webui-port"; exit 1; }
        validate_port "$2" || { echo "Invalid --webui-port: $2"; exit 1; }
        WEBUI_PORT_DEFAULT="$2"
        OPENWEBUI_PORT="$2"
        shift 2
        ;;
      --lan)
        [ "$#" -ge 2 ] || { echo "Missing value for --lan"; exit 1; }
        validate_cidr "$2" || { echo "Invalid --lan CIDR: $2"; exit 1; }
        LAN_SUBNET_DEFAULT="$2"
        shift 2
        ;;
      --ollama-bind-host)
        [ "$#" -ge 2 ] || { echo "Missing value for --ollama-bind-host"; exit 1; }
        validate_bind_host "$2" || { echo "Invalid --ollama-bind-host: $2"; exit 1; }
        OLLAMA_BIND_HOST="$2"
        shift 2
        ;;
      --ollama-models-dir)
        [ "$#" -ge 2 ] || { echo "Missing value for --ollama-models-dir"; exit 1; }
        validate_absolute_path "$2" || { echo "Invalid --ollama-models-dir: $2"; exit 1; }
        OLLAMA_MODELS_DIR="$2"
        OLLAMA_MODELS_DIR_FROM_CLI=1
        shift 2
        ;;
      --ai-user)
        [ "$#" -ge 2 ] || { echo "Missing value for --ai-user"; exit 1; }
        validate_identity "$2" || { echo "Invalid --ai-user: $2"; exit 1; }
        AI_USER="$2"
        shift 2
        ;;
      --ai-group)
        [ "$#" -ge 2 ] || { echo "Missing value for --ai-group"; exit 1; }
        validate_identity "$2" || { echo "Invalid --ai-group: $2"; exit 1; }
        AI_GROUP="$2"
        shift 2
        ;;
      --openwebui-package)
        [ "$#" -ge 2 ] || { echo "Missing value for --openwebui-package"; exit 1; }
        OPENWEBUI_PACKAGE="$2"
        shift 2
        ;;
      --ollama-version)
        [ "$#" -ge 2 ] || { echo "Missing value for --ollama-version"; exit 1; }
        OLLAMA_VERSION="$2"
        shift 2
        ;;
      --ollama-install-sha256)
        [ "$#" -ge 2 ] || { echo "Missing value for --ollama-install-sha256"; exit 1; }
        validate_sha256 "$2" || { echo "Invalid --ollama-install-sha256: $2"; exit 1; }
        OLLAMA_INSTALL_SHA256="$2"
        shift 2
        ;;
      --allow-cpu-fallback)
        ALLOW_CPU_FALLBACK=1
        shift
        ;;
      --reboot)
        AUTO_REBOOT=1
        shift
        ;;
      --)
        shift
        break
        ;;
      -*)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
      *)
        COMMAND="$1"
        shift
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  if [ "$COMMAND" = "help" ]; then
    usage
    return 0
  fi

  validate_runtime_config

  if [ "$DRY_RUN" = "1" ]; then
    show_dry_run_plan "$COMMAND"
    return 0
  fi

  require_root
  init_runtime
  acquire_lock

  case "$COMMAND" in
    menu) menu ;;
    install|new-server|bootstrap) full_new_server_setup ;;
    repair) repair_existing_installation ;;
    drivers) full_install_drivers ;;
    stack) full_install_stack ;;
    models-dir) configure_ollama_models_dir ;;
    openwebui-update|webui-update) update_openwebui ;;
    doctor) doctor ;;
    uninstall) uninstall_stack 0 ;;
    purge) uninstall_stack 1 ;;
    status) show_ports_and_services ;;
    state|report|info) show_install_state ;;
    *) usage; exit 1 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  echo "Do not source this installer. Run it as a command instead: sudo $BASH_SOURCE install"
  return 1
fi

main "$@"
