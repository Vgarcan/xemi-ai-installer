# Input validation, runtime configuration, and safe path helpers.

validate_identity() {
  [[ "${1:-}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

validate_port() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

validate_ipv4() {
  local ip="${1:-}"
  local o1 o2 o3 o4 o
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r o1 o2 o3 o4 <<< "$ip"
  for o in "$o1" "$o2" "$o3" "$o4"; do
    ((10#$o >= 0 && 10#$o <= 255)) || return 1
  done
}

validate_cidr() {
  local cidr="${1:-}"
  local ip prefix
  [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || return 1
  ip="${cidr%/*}"
  prefix="${cidr#*/}"
  validate_ipv4 "$ip" || return 1
  [ "$prefix" -ge 0 ] && [ "$prefix" -le 32 ]
}

validate_bind_host() {
  local host="${1:-}"
  [ -n "$host" ] || return 1
  [[ "$host" != *$'\n'* && "$host" != *$'\r'* ]] || return 1
  if validate_ipv4 "$host"; then
    return 0
  fi
  [[ "$host" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$ ]] || return 1
  [[ "$host" != *..* && "$host" != .* && "$host" != *.-* && "$host" != *-. ]]
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

validate_single_line_value() {
  local value="${1:-}"
  [ -n "$value" ] && [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]]
}

validate_package_spec() {
  local package="${1:-}"
  validate_single_line_value "$package" || return 1
  [[ "$package" != -* && "$package" != *[[:space:]]* ]]
}

validate_version() {
  local version="${1:-}"
  validate_single_line_value "$version" || return 1
  [[ "$version" != *[[:space:]]* ]]
}

validate_firewall_zone() {
  [[ "${1:-}" =~ ^[A-Za-z0-9_-]+$ ]]
}

validate_runtime_config() {
  validate_identity "$AI_USER" || { echo "Invalid AI_USER: $AI_USER"; return 1; }
  validate_identity "$AI_GROUP" || { echo "Invalid AI_GROUP: $AI_GROUP"; return 1; }
  validate_port "$OLLAMA_PORT_DEFAULT" || { echo "Invalid OLLAMA_PORT_DEFAULT: $OLLAMA_PORT_DEFAULT"; return 1; }
  validate_port "$WEBUI_PORT_DEFAULT" || { echo "Invalid WEBUI_PORT_DEFAULT: $WEBUI_PORT_DEFAULT"; return 1; }
  validate_cidr "$LAN_SUBNET_DEFAULT" || { echo "Invalid LAN_SUBNET_DEFAULT: $LAN_SUBNET_DEFAULT"; return 1; }
  if [ -n "$FIREWALL_ZONE" ]; then
    validate_firewall_zone "$FIREWALL_ZONE" || { echo "Invalid FIREWALL_ZONE: $FIREWALL_ZONE"; return 1; }
  fi
  validate_bind_host "$OLLAMA_BIND_HOST" || { echo "Invalid OLLAMA_BIND_HOST: $OLLAMA_BIND_HOST"; return 1; }
  validate_package_spec "$OPENWEBUI_PACKAGE" || { echo "Invalid OPENWEBUI_PACKAGE: $OPENWEBUI_PACKAGE"; return 1; }
  if [ -n "$OLLAMA_INSTALL_SHA256" ]; then
    validate_sha256 "$OLLAMA_INSTALL_SHA256" || { echo "Invalid OLLAMA_INSTALL_SHA256: $OLLAMA_INSTALL_SHA256"; return 1; }
  fi
  if [ -n "$OLLAMA_VERSION" ]; then
    validate_version "$OLLAMA_VERSION" || { echo "Invalid OLLAMA_VERSION: $OLLAMA_VERSION"; return 1; }
  fi
  if [ -n "$OLLAMA_MODELS_DIR" ]; then
    validate_absolute_path "$OLLAMA_MODELS_DIR" || { echo "Invalid OLLAMA_MODELS_DIR: $OLLAMA_MODELS_DIR"; return 1; }
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
    if [ "$resolved_prefix" = "/" ]; then
      continue
    fi
    if [ "$resolved" = "$resolved_prefix" ]; then
      fail "Refusing to remove managed parent directory itself: $path"
      return 1
    fi
    if [[ "$resolved" = "$resolved_prefix"/* ]]; then
      rm -rf -- "$resolved"
      return 0
    fi
  done

  fail "Refusing rm -rf outside managed paths: $path"
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
