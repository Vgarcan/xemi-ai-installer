# Installer runtime state, manifest persistence, and locking.

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
  if ! validate_manifest_key "$key" || ! manifest_key_allowed "$key" || ! manifest_value_allowed "$key" "$value"; then
    fail "Refusing to write unsupported manifest key or invalid value: $key"
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

remove_manifest_key() {
  local key="$1"
  local tmp
  manifest_key_allowed "$key" || return 1
  [ -f "$MANIFEST_FILE" ] || return 0
  tmp="$(mktemp "${STATE_DIR}/manifest.XXXXXX")"
  grep -v "^${key}=" "$MANIFEST_FILE" > "$tmp" || true
  command mv -f "$tmp" "$MANIFEST_FILE"
  chmod 600 "$MANIFEST_FILE" || true
}

validate_manifest_key() {
  [[ "${1:-}" =~ ^[A-Z0-9_]+$ ]]
}

manifest_key_allowed() {
  case "$1" in
    AI_GROUP_CREATED|AI_USER_CREATED|AI_USER|AI_GROUP|OLLAMA_VERSION|OLLAMA_INSTALL_SHA256|OLLAMA_INSTALLED_BY_XEMI|OLLAMA_USER_CREATED_BY_XEMI|OLLAMA_BINARY_PATH|OLLAMA_OVERRIDE_CREATED|OLLAMA_PORT|OLLAMA_BIND_HOST|OLLAMA_MODELS_DIR|NVIDIA_GPU_UUIDS|OPENWEBUI_VENV_CREATED|OPENWEBUI_DATA_CREATED|OPENWEBUI_SERVICE_CREATED|OPENWEBUI_PORT|OPENWEBUI_VENV|OPENWEBUI_PREVIOUS_VENV|OPENWEBUI_DATA_DIR|OPENWEBUI_DATA_SNAPSHOT|OPENWEBUI_ENV_FILE|OPENWEBUI_PACKAGE|OPENWEBUI_OLLAMA_BASE_URL|FIREWALL_CONFIGURED|FIREWALL_ZONE|FIREWALL_RULE_OLLAMA|FIREWALL_RULE_WEBUI|LAN_SUBNET|EXTRAS_USER_CREATED|TERMINAL_USER_CREATED|OPEN_TERMINAL_INSTALLED|OPEN_TERMINAL_PORT|MCPO_INSTALLED|MCPO_PORT|SEARXNG_INSTALLED|SEARXNG_PORT|SEARXNG_COMMIT|TIKA_INSTALLED|TIKA_PORT|TIKA_INSTALLED_VERSION|OLLAMA_CONTEXT_LENGTH|OLLAMA_KV_CACHE_TYPE|HTTPS_INSTALLED|HTTPS_USER_CREATED|HTTPS_PORT|HTTPS_HOSTS|HTTPS_FIREWALL_RULE|HTTPS_FIREWALL_ZONE|OWUI_BACKUP_ENABLED|OWUI_BACKUP_DIR|OWUI_BACKUP_KEEP|OWUI_BACKUP_TIME|MCP_EXTRA_SERVERS|PIPER_INSTALLED|PIPER_PORT|OPENWEBUI_WHISPER_LANGUAGE|JUPYTER_INSTALLED|JUPYTER_PORT|JUPYTER_USER_CREATED|JUPYTER_PERMISSION_CHANGED|PLAYWRIGHT_INSTALLED|PLAYWRIGHT_PORT|PLAYWRIGHT_VERSION|BROWSER_USER_CREATED)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

manifest_value_allowed() {
  local key="$1"
  local value="$2"
  case "$key" in
    AI_USER|AI_GROUP)
      validate_identity "$value"
      ;;
    OLLAMA_PORT|OPENWEBUI_PORT|OPEN_TERMINAL_PORT|MCPO_PORT|SEARXNG_PORT|TIKA_PORT|HTTPS_PORT|PIPER_PORT|JUPYTER_PORT|PLAYWRIGHT_PORT)
      validate_port "$value"
      ;;
    OLLAMA_BIND_HOST)
      validate_bind_host "$value"
      ;;
    OLLAMA_MODELS_DIR|OLLAMA_BINARY_PATH|OPENWEBUI_VENV|OPENWEBUI_PREVIOUS_VENV|OPENWEBUI_DATA_DIR|OPENWEBUI_DATA_SNAPSHOT|OPENWEBUI_ENV_FILE)
      validate_absolute_path "$value"
      ;;
    OLLAMA_INSTALL_SHA256)
      validate_sha256 "$value"
      ;;
    OLLAMA_VERSION|TIKA_INSTALLED_VERSION)
      validate_version "$value"
      ;;
    OPENWEBUI_PACKAGE)
      validate_package_spec "$value"
      ;;
    AI_GROUP_CREATED|AI_USER_CREATED|OLLAMA_INSTALLED_BY_XEMI|OLLAMA_USER_CREATED_BY_XEMI|OLLAMA_OVERRIDE_CREATED|OPENWEBUI_VENV_CREATED|OPENWEBUI_DATA_CREATED|OPENWEBUI_SERVICE_CREATED|FIREWALL_CONFIGURED|EXTRAS_USER_CREATED|TERMINAL_USER_CREATED|OPEN_TERMINAL_INSTALLED|MCPO_INSTALLED|SEARXNG_INSTALLED|TIKA_INSTALLED|HTTPS_INSTALLED|HTTPS_USER_CREATED|OWUI_BACKUP_ENABLED|PIPER_INSTALLED|JUPYTER_INSTALLED|JUPYTER_USER_CREATED|JUPYTER_PERMISSION_CHANGED|PLAYWRIGHT_INSTALLED|BROWSER_USER_CREATED)
      [ "$value" = "1" ]
      ;;
    NVIDIA_GPU_UUIDS)
      [[ "$value" =~ ^GPU-[A-Za-z0-9-]+(,GPU-[A-Za-z0-9-]+)*$ ]]
      ;;
    SEARXNG_COMMIT)
      [[ "$value" =~ ^[0-9a-f]{40}$ ]]
      ;;
    HTTPS_HOSTS)
      validate_https_hosts "$value"
      ;;
    MCP_EXTRA_SERVERS)
      [[ "$value" =~ ^[a-z]+(,[a-z]+)*$ ]]
      ;;
    OPENWEBUI_WHISPER_LANGUAGE)
      validate_whisper_language "$value"
      ;;
    PLAYWRIGHT_VERSION)
      [[ "$value" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]]
      ;;
    HTTPS_FIREWALL_RULE)
      validate_single_line_value "$value"
      ;;
    HTTPS_FIREWALL_ZONE)
      validate_firewall_zone "$value"
      ;;
    OWUI_BACKUP_DIR)
      validate_absolute_path "$value"
      ;;
    OWUI_BACKUP_KEEP)
      validate_backup_keep "$value"
      ;;
    OWUI_BACKUP_TIME)
      validate_backup_time "$value"
      ;;
    OLLAMA_CONTEXT_LENGTH)
      validate_context_length "$value"
      ;;
    OLLAMA_KV_CACHE_TYPE)
      validate_kv_cache_type "$value"
      ;;
    LAN_SUBNET)
      validate_cidr "$value"
      ;;
    FIREWALL_ZONE)
      validate_firewall_zone "$value"
      ;;
    OPENWEBUI_OLLAMA_BASE_URL|FIREWALL_RULE_WEBUI)
      validate_single_line_value "$value"
      ;;
    FIREWALL_RULE_OLLAMA)
      [ "$value" = "none" ] || validate_single_line_value "$value"
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
    if ! manifest_value_allowed "$key" "$value"; then
      warn "Ignoring invalid manifest value for key: $key"
      continue
    fi
    if [ "$key" = "FIREWALL_ZONE" ]; then RECORDED_FIREWALL_ZONE="$value"; fi
    case "$key" in
      OLLAMA_PORT) [ "$OLLAMA_PORT_FROM_CLI" = "1" ] && continue ;;
      OPENWEBUI_PORT) [ "$WEBUI_PORT_FROM_CLI" = "1" ] && continue ;;
      OLLAMA_BIND_HOST) [ "$OLLAMA_BIND_HOST_FROM_CLI" = "1" ] && continue ;;
      LAN_SUBNET) [ "$LAN_SUBNET_FROM_CLI" = "1" ] && continue ;;
      FIREWALL_ZONE) [ "$FIREWALL_ZONE_FROM_CLI" = "1" ] && continue ;;
      OLLAMA_MODELS_DIR) [ "$OLLAMA_MODELS_DIR_FROM_CLI" = "1" ] && continue ;;
      OLLAMA_CONTEXT_LENGTH) [ "$OLLAMA_CONTEXT_LENGTH_FROM_CLI" = "1" ] && continue ;;
      OLLAMA_KV_CACHE_TYPE) [ "$OLLAMA_KV_CACHE_TYPE_FROM_CLI" = "1" ] && continue ;;
    esac
    printf -v "$key" "%s" "$value"
  done < "$MANIFEST_FILE"
}
