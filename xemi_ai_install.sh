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
  mv "$tmp" "$MANIFEST_FILE"
  chmod 600 "$MANIFEST_FILE" || true
}

validate_manifest_key() {
  [[ "${1:-}" =~ ^[A-Z0-9_]+$ ]]
}

manifest_key_allowed() {
  case "$1" in
    AI_GROUP_CREATED|AI_USER_CREATED|AI_USER|AI_GROUP|OLLAMA_VERSION|OLLAMA_INSTALL_SHA256|OLLAMA_INSTALLED_BY_XEMI|OLLAMA_OVERRIDE_CREATED|OLLAMA_PORT|OLLAMA_BIND_HOST|NVIDIA_GPU_UUIDS|OPENWEBUI_VENV_CREATED|OPENWEBUI_SERVICE_CREATED|OPENWEBUI_PORT|OPENWEBUI_VENV|OPENWEBUI_DATA_DIR|OPENWEBUI_ENV_FILE|OPENWEBUI_PACKAGE|OPENWEBUI_OLLAMA_BASE_URL|FIREWALL_CONFIGURED|FIREWALL_RULE_OLLAMA|FIREWALL_RULE_WEBUI|LAN_SUBNET)
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
      echo "  8. Pull recommended models."
      echo "  9. Install Python 3.11 side-by-side and Open WebUI in a venv."
      echo "  10. Create Open WebUI systemd service with autostart."
      echo "  11. Add firewall rich rules for LAN access."
      echo "  12. Run doctor readiness checks."
      ;;
    stack)
      echo "Plan:"
      echo "  1. Check dnf/systemd support."
      echo "  2. Install base tools and user."
      echo "  3. Install/configure Ollama."
      echo "  4. Pull models."
      echo "  5. Install/configure Open WebUI."
      echo "  6. Configure firewall and run doctor."
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
    doctor|status|state|menu)
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

validate_sha256() {
  [[ "${1:-}" =~ ^[A-Fa-f0-9]{64}$ ]]
}

validate_runtime_config() {
  validate_bind_host "$OLLAMA_BIND_HOST" || { echo "Invalid OLLAMA_BIND_HOST: $OLLAMA_BIND_HOST"; exit 1; }
  if [ -n "$OLLAMA_INSTALL_SHA256" ]; then
    validate_sha256 "$OLLAMA_INSTALL_SHA256" || { echo "Invalid OLLAMA_INSTALL_SHA256: $OLLAMA_INSTALL_SHA256"; exit 1; }
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

remove_firewall_rule() {
  local rule="$1"
  [ -n "$rule" ] || return 0
  firewall-cmd --permanent --remove-rich-rule="$rule" >/dev/null 2>&1 || true
}

ensure_base_tools() {
  header
  echo "Installing base tools..."
  run_required "Installing base tools with dnf..." dnf install -y curl wget git firewalld htop nano tar gzip jq bc pciutils util-linux coreutils procps-ng
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
  if systemctl list-unit-files | grep -q "^ollama\.service"; then
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

  record_manifest "OLLAMA_INSTALLED_BY_XEMI" "1"
  ok "Ollama installed."
  pause
}

configure_ollama_service_lan() {
  header
  local port
  local bind_host
  local gpu_uuids=""
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
  elif [ "$ALLOW_CPU_FALLBACK" = "1" ]; then
    warn "Ollama will be configured without confirmed GPU because ALLOW_CPU_FALLBACK=1."
  else
    fail "GPU is required for this installer goal. Re-run after NVIDIA drivers are working, or set ALLOW_CPU_FALLBACK=1."
    pause
    return 1
  fi

  backup_path /etc/systemd/system/ollama.service.d
  mkdir -p /etc/systemd/system/ollama.service.d
  cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
Environment="OLLAMA_HOST=${bind_host}:${port}"
Environment="OLLAMA_FLASH_ATTENTION=1"
User=${AI_USER}
Group=${AI_GROUP}
NoNewPrivileges=true
PrivateTmp=true
ProtectControlGroups=true
ProtectKernelModules=true
ProtectKernelTunables=true
RestrictSUIDSGID=true
EOF
  if [ -n "$gpu_uuids" ]; then
    cat >> /etc/systemd/system/ollama.service.d/override.conf <<EOF
Environment="CUDA_VISIBLE_DEVICES=${gpu_uuids}"
EOF
    record_manifest "NVIDIA_GPU_UUIDS" "$gpu_uuids"
  fi

  record_manifest "OLLAMA_OVERRIDE_CREATED" "1"
  record_manifest "OLLAMA_PORT" "$port"
  record_manifest "OLLAMA_BIND_HOST" "$bind_host"
  OLLAMA_PORT="$port"
  OLLAMA_BIND_HOST="$bind_host"
  systemctl daemon-reload
  systemctl enable ollama >/dev/null 2>&1
  systemctl restart ollama

  ok "Ollama service configured on ${bind_host}:${port}."
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
    options+=("custom")
  elif [ "$vram" -ge 8000 ]; then
    options+=("mistral phi3")
    options+=("phi3")
    options+=("custom")
  else
    options+=("phi3")
    options+=("custom")
  fi

  echo "Choose model set:"
  local i=1
  for o in "${options[@]}"; do
    echo "$i) $o"
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
  if [ "$selected" = "custom" ]; then
    selected="$(ask "Enter model names separated by spaces" "mistral phi3")"
  fi

  echo ""
  echo "Installing: $selected"
  echo ""

  for m in $selected; do
    sudo -u "$AI_USER" "$bin" pull "$m" 2>/dev/null || "$bin" pull "$m" 2>/dev/null || true
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

  mkdir -p "$OPENWEBUI_DATA_DIR"
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

  cat > "$OPENWEBUI_ENV_FILE" <<EOF
PORT=${webui_port}
DATA_DIR=${OPENWEBUI_DATA_DIR}
OLLAMA_BASE_URL=http://${ollama_base_host}:${ollama_port}
UVICORN_WORKERS=1
EOF
  chmod 640 "$OPENWEBUI_ENV_FILE"

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
ExecStart=${OPENWEBUI_VENV}/bin/python -m open_webui serve
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

  ok "Open WebUI installed and running on port ${webui_port}."
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

show_install_state() {
  header
  echo "State directory: $STATE_DIR"
  echo "Manifest: $MANIFEST_FILE"
  echo "Log: $LOG_FILE"
  echo ""
  if [ -f "$MANIFEST_FILE" ]; then
    sed -n '1,200p' "$MANIFEST_FILE"
  else
    echo "No manifest found."
  fi
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
  local env_line
  if ensure_nvidia_gpu_ready; then
    doctor_ok "NVIDIA GPU is visible through nvidia-smi"
  elif [ "$ALLOW_CPU_FALLBACK" = "1" ]; then
    doctor_warn "GPU is not ready, but ALLOW_CPU_FALLBACK=1"
    return 0
  else
    doctor_fail "GPU is not ready; Ollama cannot be guaranteed to use GPU"
    return 0
  fi

  env_line="$(systemctl show ollama -p Environment --no-pager 2>/dev/null || true)"
  if echo "$env_line" | grep -q "CUDA_VISIBLE_DEVICES="; then
    doctor_ok "Ollama service has explicit CUDA_VISIBLE_DEVICES"
  else
    doctor_warn "Ollama service has no explicit CUDA_VISIBLE_DEVICES; default CUDA visibility may still use all GPUs"
  fi
}

doctor_check_http() {
  local name="$1"
  local url="$2"
  if curl -fsS "$url" >/dev/null 2>&1; then
    doctor_ok "${name} responds: ${url}"
  else
    doctor_fail "${name} does not respond: ${url}"
  fi
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
  echo ""

  doctor_check_gpu
  echo ""

  doctor_check_service ollama
  doctor_check_http "Ollama API" "http://127.0.0.1:${ollama_port}/api/tags"
  doctor_check_ollama_gpu_logs
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

  if ! ensure_nvidia_gpu_ready; then
    warn "NVIDIA GPU is not ready. Installing NVIDIA drivers now."
    install_nvidia_drivers
    if ! ensure_nvidia_gpu_ready; then
      fail "NVIDIA GPU is still not ready. Reboot, then run: $0 install"
      pause
      return 1
    fi
  fi

  full_install_stack
}

menu() {
  while true; do
    header
    echo "1) Full new server setup (drivers, Ollama, WebUI, GPU, firewall)"
    echo "2) Stage 1, install NVIDIA drivers and reboot"
    echo "3) Stage 2, install AI stack (Ollama, models, WebUI, firewall)"
    echo ""
    echo "4) Show GPU info and recommendations"
    echo "5) Show Ollama status, service, location"
    echo ""
    echo "6) Install Ollama (official installer)"
    echo "7) Configure Ollama service for LAN"
    echo "8) Ollama health check"
    echo ""
    echo "9) Recommend and install models (choose set)"
    echo "10) List models"
    echo "11) Remove models (interactive)"
    echo ""
    echo "12) Remove Ollama by location (discover multiple and remove)"
    echo ""
    echo "13) Install Python 3.11"
    echo "14) Install Open WebUI (Python 3.11 venv service)"
    echo "15) Open WebUI health check"
    echo ""
    echo "16) Configure firewall (LAN only)"
    echo "17) Show ports in use and service bindings"
    echo ""
    echo "18) Show install state"
    echo "19) Run doctor readiness check"
    echo "20) Uninstall stack (keep Ollama data)"
    echo "21) Purge stack (reset to zero)"
    echo ""
    echo "22) Exit"
    echo ""

    local opt
    opt="$(ask "Select option" "22")"
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
      9) recommend_and_install_models ;;
      10) list_ollama_models ;;
      11) remove_ollama_models_interactive ;;
      12) remove_ollama_by_location ;;
      13) install_python311 ;;
      14) install_openwebui ;;
      15) openwebui_health_check ;;
      16) configure_firewall_lan_only ;;
      17) show_ports_and_services ;;
      18) show_install_state ;;
      19) doctor ;;
      20) uninstall_stack 0 ;;
      21) uninstall_stack 1 ;;
      22) exit 0 ;;
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
  stack       Install AI stack only, assuming drivers are ready
  drivers     Install NVIDIA driver stage
  doctor      Run readiness checks
  uninstall   Remove services/Open WebUI, keep Ollama data
  purge       Reset installation to zero
  status      Show ports and service status
  state       Show installer manifest

Options:
  -y, --yes                    Use defaults and skip pauses
  -n, --dry-run                Print the resolved plan without changing the system
  --ollama-port PORT           Set Ollama port (default: ${OLLAMA_PORT_DEFAULT})
  --webui-port PORT            Set Open WebUI port (default: ${WEBUI_PORT_DEFAULT})
  --lan CIDR                   Set allowed LAN subnet (default: ${LAN_SUBNET_DEFAULT})
  --ollama-bind-host HOST      Set Ollama bind host (default: ${OLLAMA_BIND_HOST})
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
    drivers) full_install_drivers ;;
    stack) full_install_stack ;;
    doctor) doctor ;;
    uninstall) uninstall_stack 0 ;;
    purge) uninstall_stack 1 ;;
    status) show_ports_and_services ;;
    state) show_install_state ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
