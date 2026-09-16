# Open WebUI installation, configuration, updates, and health checks.

is_openwebui_installed() {
  [ -x "$OPENWEBUI_VENV/bin/open-webui" ]
}

repair_openwebui_installation() {
  header
  echo "Repairing Open WebUI installation..."
  load_manifest
  if [ "${OPENWEBUI_SERVICE_CREATED:-}" != "1" ]; then
    fail "Existing Open WebUI service is not recorded as Xemi-managed; repair needs explicit migration."
    return 1
  fi
  install_python311
  ensure_ai_user
  ensure_base_tools

  if [ ! -d "$OPENWEBUI_VENV" ] || [ ! -x "$OPENWEBUI_VENV/bin/open-webui" ]; then
    warn "Open WebUI venv missing or broken; reinstalling Open WebUI."
    install_openwebui
    return
  fi

  "$OPENWEBUI_VENV/bin/pip" check || { fail "Open WebUI dependencies are inconsistent; run openwebui-update."; return 1; }

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
  systemctl enable openwebui >/dev/null 2>&1
  systemctl restart openwebui
  openwebui_verify_runtime "$webui_port"
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

  load_manifest
  if [ -e "$OPENWEBUI_DATA_DIR" ] && [ "${OPENWEBUI_DATA_CREATED:-}" != "1" ] && [ "${OPENWEBUI_SERVICE_CREATED:-}" != "1" ]; then
    fail "Existing Open WebUI data is not Xemi-managed: $OPENWEBUI_DATA_DIR"
    return 1
  fi
  if [ -e /etc/systemd/system/openwebui.service ] && [ "${OPENWEBUI_SERVICE_CREATED:-}" != "1" ]; then
    fail "Existing Open WebUI service is not Xemi-managed."
    return 1
  fi
  if [ -e "$OPENWEBUI_ENV_FILE" ] && [ "${OPENWEBUI_SERVICE_CREATED:-}" != "1" ]; then
    fail "Existing Open WebUI environment file is not Xemi-managed."
    return 1
  fi

  install_python311
  ensure_ai_user
  ensure_base_tools

  if [ -e "$OPENWEBUI_VENV" ] || [ -L "$OPENWEBUI_VENV" ]; then
    fail "Open WebUI already has an environment at $OPENWEBUI_VENV. Use openwebui-update or repair."
    return 1
  fi
  run_required "Creating Open WebUI virtual environment..." "$PY311_BIN" -m venv "$OPENWEBUI_VENV"
  record_manifest "OPENWEBUI_VENV_CREATED" "1"

  run_required "Upgrading pip in Open WebUI venv..." "$OPENWEBUI_VENV/bin/pip" install --upgrade pip
  run_required "Installing Open WebUI package..." "$OPENWEBUI_VENV/bin/pip" install -U "$OPENWEBUI_PACKAGE"
  run_required "Installing modern SQLite compatibility package..." "$OPENWEBUI_VENV/bin/pip" install -U pysqlite3-binary
  "$OPENWEBUI_VENV/bin/pip" check || { fail "Open WebUI dependencies are inconsistent."; return 1; }
  "$OPENWEBUI_VENV/bin/python" -c 'import pysqlite3' || { fail "SQLite compatibility package cannot be imported."; return 1; }
  if [ ! -x "$OPENWEBUI_VENV/bin/open-webui" ]; then
    fail "Open WebUI command not found at $OPENWEBUI_VENV/bin/open-webui"
    pause
    return 1
  fi

  write_openwebui_sqlite_compat

  if [ ! -e "$OPENWEBUI_DATA_DIR" ]; then
    mkdir -p "$OPENWEBUI_DATA_DIR"
    record_manifest "OPENWEBUI_DATA_CREATED" "1"
  fi
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

  if openwebui_verify_runtime "$webui_port"; then
    ok "Open WebUI installed and responding on port ${webui_port}."
  else
    fail "Open WebUI service started, but health did not respond. Check: journalctl -u openwebui -e --no-pager"
    pause
    return 1
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
  validate_port "$webui_port" || { fail "Invalid Open WebUI port: $webui_port"; return 1; }
  validate_absolute_path "$OPENWEBUI_DATA_DIR" || { fail "Invalid Open WebUI data directory: $OPENWEBUI_DATA_DIR"; return 1; }
  validate_single_line_value "$ollama_base_url" || { fail "Invalid Ollama base URL."; return 1; }
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
  validate_port "$webui_port" || { fail "Invalid Open WebUI port: $webui_port"; return 1; }
  validate_identity "$AI_USER" || { fail "Invalid Open WebUI service user: $AI_USER"; return 1; }
  validate_identity "$AI_GROUP" || { fail "Invalid Open WebUI service group: $AI_GROUP"; return 1; }
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
    if curl -fsS --connect-timeout 3 --max-time 10 "http://127.0.0.1:${webui_port}/health" >/dev/null 2>&1; then
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

openwebui_check_updates() {
  local current outdated
  if [ ! -x "$OPENWEBUI_VENV/bin/pip" ]; then
    fail "Open WebUI is not installed at $OPENWEBUI_VENV."
    return 1
  fi
  current="$(openwebui_package_version)"
  [ -n "$current" ] || { fail "Cannot read the installed Open WebUI version."; return 1; }
  echo "Installed Open WebUI: $current"
  if ! outdated="$(openwebui_outdated_versions)"; then
    fail "Cannot check the package index. No changes were made."
    return 1
  fi
  OPENWEBUI_AVAILABLE_UPDATE="$outdated"
  if [ -n "$outdated" ]; then
    echo "Available update: ${outdated%% *} -> ${outdated#* }"
  else
    echo "No update reported by the package index."
  fi
}

openwebui_verify_runtime() {
  local port="$1"
  if ! systemctl is-active --quiet openwebui; then
    fail "Open WebUI service is not active."
    return 1
  fi
  if ! wait_openwebui_health "$port"; then
    fail "Open WebUI /health did not respond on port $port."
    return 1
  fi
  if ! systemctl is-active --quiet openwebui; then
    fail "Open WebUI stopped after its health response."
    return 1
  fi
}

openwebui_backup_data() {
  local snapshot="$1"
  local required available
  required="$(du -sk -- "$OPENWEBUI_DATA_DIR" | awk '{print $1}')"
  available="$(df -Pk -- "$BACKUP_DIR" | awk 'END {print $4}')"
  if [ "$available" -le "$((required + 102400))" ]; then
    fail "Not enough free space to back up Open WebUI data (need at least $((required + 102400)) KiB)."
    return 1
  fi
  if ! cp -a -- "$OPENWEBUI_DATA_DIR" "$snapshot"; then
    if [ -d "$snapshot" ]; then safe_rm_rf "$snapshot" "$BACKUP_DIR" || true; fi
    fail "Could not complete the Open WebUI data snapshot."
    return 1
  fi
}

openwebui_restore_release() {
  local previous="$1"
  local snapshot="$2"
  local port="$3"
  systemctl stop openwebui >/dev/null 2>&1 || true
  if [ -d "$previous" ]; then
    if [ -L "$OPENWEBUI_VENV" ]; then
      rm -- "$OPENWEBUI_VENV"
    elif [ -e "$OPENWEBUI_VENV" ]; then
      fail "Cannot restore: active environment is not the expected symlink."
      return 1
    fi
    mv -- "$previous" "$OPENWEBUI_VENV"
  fi
  if [ -d "$snapshot" ]; then
    local failed_data="${OPENWEBUI_DATA_DIR}.failed.$(date +%Y%m%d%H%M%S).$$"
    if [ -e "$OPENWEBUI_DATA_DIR" ]; then
      mv -- "$OPENWEBUI_DATA_DIR" "$failed_data"
    fi
    if ! cp -a -- "$snapshot" "$OPENWEBUI_DATA_DIR"; then
      if [ -d "$OPENWEBUI_DATA_DIR" ]; then safe_rm_rf "$OPENWEBUI_DATA_DIR" /var/lib || true; fi
      if [ -d "$failed_data" ]; then mv -- "$failed_data" "$OPENWEBUI_DATA_DIR" || true; fi
      fail "Data snapshot restore failed; original data was moved to $failed_data."
      return 1
    fi
  fi
  systemctl daemon-reload
  systemctl restart openwebui
  openwebui_verify_runtime "$port"
}

update_openwebui() {
  header
  echo "Checking Open WebUI updates..."
  load_manifest

  if [ "${OPENWEBUI_SERVICE_CREATED:-}" != "1" ] || [ "${OPENWEBUI_VENV_CREATED:-}" != "1" ]; then
    fail "Open WebUI update requires a Xemi-managed service and environment."
    return 1
  fi

  local webui_port="${OPENWEBUI_PORT:-$WEBUI_PORT_DEFAULT}"
  local current outdated latest answer candidate previous snapshot package_spec
  local release_id
  if ! openwebui_check_updates; then return 1; fi
  outdated="$OPENWEBUI_AVAILABLE_UPDATE"
  if [ -z "$outdated" ] && [ "$OPENWEBUI_PACKAGE" = "open-webui" ]; then
    ok "Open WebUI is already current."
    return 0
  fi
  current="$(openwebui_package_version)"
  latest="${outdated#* }"
  package_spec="open-webui==${latest}"
  if [ "$OPENWEBUI_PACKAGE" != "open-webui" ]; then
    latest="$OPENWEBUI_PACKAGE"
    package_spec="$OPENWEBUI_PACKAGE"
  fi
  echo "Planned update: $current -> $latest"
  answer="$(confirm_proceed "Apply Open WebUI update now yes or no" "no")"
  if ! is_yes "$answer"; then
    warn "Update cancelled."
    return 0
  fi
  if [ ! -d "$OPENWEBUI_DATA_DIR" ]; then
    fail "Open WebUI data directory is missing: $OPENWEBUI_DATA_DIR"
    return 1
  fi
  if ! openwebui_verify_runtime "$webui_port"; then
    fail "Repair the existing service before attempting an update."
    return 1
  fi
  mkdir -p "$BACKUP_DIR"
  release_id="$(date +%Y%m%d%H%M%S).$$"
  candidate="${OPENWEBUI_VENV}.candidate.${release_id}"
  previous="${OPENWEBUI_VENV}.previous.${release_id}"
  snapshot="${BACKUP_DIR}/openwebui-data.${release_id}"
  echo "Preparing candidate environment: $candidate"
  if ! "$PY311_BIN" -m venv "$candidate"; then
    if [ -d "$candidate" ]; then safe_rm_rf "$candidate" /opt || true; fi
    return 1
  fi
  if ! run_required "Installing candidate Open WebUI..." "$candidate/bin/pip" --isolated install "$package_spec" pysqlite3-binary; then
    safe_rm_rf "$candidate" /opt
    return 1
  fi
  if ! "$candidate/bin/pip" check || [ ! -x "$candidate/bin/open-webui" ]; then
    fail "Candidate environment did not pass dependency or executable checks."
    safe_rm_rf "$candidate" /opt
    return 1
  fi
  if ! "$candidate/bin/python" -c 'import pysqlite3'; then
    fail "Candidate SQLite compatibility package cannot be imported."
    safe_rm_rf "$candidate" /opt
    return 1
  fi
  local saved_venv="$OPENWEBUI_VENV"
  OPENWEBUI_VENV="$candidate"
  write_openwebui_sqlite_compat
  OPENWEBUI_VENV="$saved_venv"
  chown -R "$AI_USER:$AI_GROUP" "$candidate"

  if ! systemctl stop openwebui; then
    safe_rm_rf "$candidate" /opt
    fail "Could not stop Open WebUI."
    return 1
  fi
  if ! openwebui_backup_data "$snapshot"; then
    systemctl start openwebui || true
    safe_rm_rf "$candidate" /opt
    return 1
  fi
  if ! mv -- "$OPENWEBUI_VENV" "$previous"; then
    systemctl start openwebui || true
    safe_rm_rf "$candidate" /opt
    return 1
  fi
  if ! ln -s -- "$candidate" "$OPENWEBUI_VENV"; then
    mv -- "$previous" "$OPENWEBUI_VENV"
    systemctl start openwebui || true
    return 1
  fi
  if ! systemctl restart openwebui || ! openwebui_verify_runtime "$webui_port"; then
    fail "Update health check failed; restoring previous version and data."
    journalctl -u openwebui -n 80 --no-pager || true
    if ! openwebui_restore_release "$previous" "$snapshot" "$webui_port"; then
      fail "Automatic rollback failed. Previous snapshot: $snapshot; old environment: $previous"
      return 1
    fi
    warn "Previous Open WebUI version restored."
    return 1
  fi
  record_manifest "OPENWEBUI_PREVIOUS_VENV" "$previous"
  record_manifest "OPENWEBUI_DATA_SNAPSHOT" "$snapshot"
  record_manifest "OPENWEBUI_PACKAGE" "$OPENWEBUI_PACKAGE"
  ok "Open WebUI updated to $(openwebui_package_version)."
  echo "Rollback copy: $previous; data snapshot: $snapshot"
  pause
}

rollback_openwebui() {
  header
  load_manifest
  if [ "${OPENWEBUI_SERVICE_CREATED:-}" != "1" ] || [ "${OPENWEBUI_VENV_CREATED:-}" != "1" ]; then
    fail "Open WebUI rollback requires a Xemi-managed installation."
    return 1
  fi
  local previous="${OPENWEBUI_PREVIOUS_VENV:-}"
  local snapshot="${OPENWEBUI_DATA_SNAPSHOT:-}"
  local port="${OPENWEBUI_PORT:-$WEBUI_PORT_DEFAULT}"
  if [ -z "$previous" ] || [ ! -d "$previous" ] || [ -z "$snapshot" ] || [ ! -d "$snapshot" ]; then
    fail "No complete Open WebUI rollback pair is recorded."
    return 1
  fi
  echo "Previous environment: $previous"
  echo "Data snapshot: $snapshot"
  local answer
  answer="$(confirm_proceed "Restore this version and data snapshot yes or no" "no")"
  if ! is_yes "$answer"; then
    warn "Rollback cancelled."
    return 0
  fi
  openwebui_restore_release "$previous" "$snapshot" "$port" || return 1
  remove_manifest_key OPENWEBUI_PREVIOUS_VENV
  remove_manifest_key OPENWEBUI_DATA_SNAPSHOT
  ok "Open WebUI rollback completed."
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
