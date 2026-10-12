# Removal and cleanup workflows for the managed stack.

stop_disable_service() {
  local service="$1"
  systemctl stop "$service" >/dev/null 2>&1 || true
  systemctl disable "$service" >/dev/null 2>&1 || true
}

remove_managed_webui_venv() {
  local path="$1"
  local target
  if [ -L "$path" ]; then
    target="$(readlink -f -- "$path")"
    [[ "$target" = "${OPENWEBUI_VENV}.candidate."* ]] || {
      fail "Unexpected Open WebUI release target: $target"
      return 1
    }
    rm -- "$path"
    safe_rm_rf "$target" /opt
  elif [ -d "$path" ]; then
    safe_rm_rf "$path" /opt
  fi
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

  if [ "${OPENWEBUI_SERVICE_CREATED:-}" != "1" ] && [ "${OPENWEBUI_VENV_CREATED:-}" != "1" ]; then
    warn "Open WebUI is not recorded as managed by Xemi; leaving it untouched."
    return 0
  fi

  if [ "${OPENWEBUI_SERVICE_CREATED:-}" = "1" ]; then
    stop_disable_service openwebui
  fi

  if [ "${OPENWEBUI_SERVICE_CREATED:-}" = "1" ] && [ -f "$service_file" ]; then
    backup_path "$service_file"
    rm -f "$service_file"
    ok "Open WebUI service removed."
  fi

  if [ "${OPENWEBUI_VENV_CREATED:-}" = "1" ] && { [ -d "$venv" ] || [ -L "$venv" ]; }; then
    remove_managed_webui_venv "$venv"
    ok "Open WebUI venv removed: $venv"
  fi
  if [ "${OPENWEBUI_VENV_CREATED:-}" = "1" ] && [ -n "${OPENWEBUI_PREVIOUS_VENV:-}" ] && { [ -e "$OPENWEBUI_PREVIOUS_VENV" ] || [ -L "$OPENWEBUI_PREVIOUS_VENV" ]; }; then
    remove_managed_webui_venv "$OPENWEBUI_PREVIOUS_VENV"
  fi

  if [ "${OPENWEBUI_SERVICE_CREATED:-}" = "1" ] && [ -f "$env_file" ]; then
    backup_path "$env_file"
    rm -f "$env_file"
    ok "Open WebUI env file removed: $env_file"
  fi

  if [ "$purge" = "1" ] && [ "${OPENWEBUI_DATA_CREATED:-}" = "1" ] && [ -d "$data_dir" ]; then
    backup_path "$data_dir"
    safe_rm_rf "$data_dir" /var/lib
    ok "Open WebUI data removed: $data_dir"
  elif [ -d "$data_dir" ]; then
    warn "Open WebUI data kept: $data_dir"
  fi

  # Legacy source trees were not created by this installer.
}

remove_ollama_installation() {
  local purge="$1"

  if [ "${OLLAMA_OVERRIDE_CREATED:-}" != "1" ] && [ "${OLLAMA_INSTALLED_BY_XEMI:-}" != "1" ]; then
    warn "Ollama is not recorded as managed by Xemi; leaving it untouched."
    return 0
  fi
  if [ "$purge" = "1" ] && [ "${OLLAMA_INSTALLED_BY_XEMI:-}" = "1" ]; then
    stop_disable_service ollama
  fi

  if [ "${OLLAMA_OVERRIDE_CREATED:-}" = "1" ] && [ -f /etc/systemd/system/ollama.service.d/override.conf ]; then
    backup_path /etc/systemd/system/ollama.service.d
    rm -f /etc/systemd/system/ollama.service.d/override.conf
    rmdir /etc/systemd/system/ollama.service.d >/dev/null 2>&1 || true
    ok "Ollama systemd override removed."
  fi
  if [ "${OLLAMA_OVERRIDE_CREATED:-}" = "1" ]; then
    stop_disable_service xemi-ollama-gpu-guard
    rm -f /etc/systemd/system/xemi-ollama-gpu-guard.service /usr/local/bin/xemi_ollama_gpu_guard.sh
  fi

  if [ "$purge" = "1" ] && [ "${OLLAMA_INSTALLED_BY_XEMI:-}" = "1" ]; then
    local lib_dir
    if lib_dir="$(ollama_lib_dir_for_binary "${OLLAMA_BINARY_PATH:-}")"; then
      rm -f -- "$OLLAMA_BINARY_PATH"
      safe_rm_rf "$lib_dir" "$(dirname "$lib_dir")"
      ok "Ollama binary removed: $OLLAMA_BINARY_PATH"
    else
      warn "No safe recorded Ollama binary path; binary kept."
    fi

    backup_path /etc/systemd/system/ollama.service
    rm -f /etc/systemd/system/ollama.service
    safe_rm_rf /usr/share/ollama /usr/share
    safe_rm_rf /var/lib/ollama /var/lib
    safe_rm_rf "/home/${AI_USER}/.ollama" /home
    if [ "${OLLAMA_USER_CREATED_BY_XEMI:-}" = "1" ]; then
      userdel -r ollama >/dev/null 2>&1 || userdel ollama >/dev/null 2>&1 || true
      groupdel ollama >/dev/null 2>&1 || true
    fi
    ok "Ollama service, libraries and model data removed."
  elif [ "$purge" = "1" ]; then
    warn "Ollama binary and data are not recorded as Xemi-owned; keeping them."
  else
    warn "Ollama binary and model data kept."
  fi
  if [ "$purge" != "1" ]; then
    systemctl daemon-reload
    systemctl restart ollama || warn "Ollama could not restart after removing the Xemi override."
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
    echo "This will purge services, Open WebUI, Open WebUI tools, HTTPS access, Ollama binaries/data, firewall rules and created users."
    echo "Open WebUI backup archives are kept."
  else
    echo "This will uninstall services, Open WebUI venv, Open WebUI tools, HTTPS access, scheduled backups and firewall rules while keeping Ollama binaries/models and backup archives."
  fi

  local ans
  ans="$(confirm_proceed "Proceed yes or no" "no")"
  if ! is_yes "$ans"; then
    warn "Cancelled."
    pause
    return 0
  fi

  remove_firewall_configuration
  remove_https
  remove_openwebui_backups "$purge"
  remove_openwebui_extras "$purge"
  remove_openwebui_installation "$purge"
  remove_ollama_installation "$purge"
  systemctl daemon-reload || true

  if [ "$purge" = "1" ]; then
    remove_ai_identity_if_created
    backup_path "$MANIFEST_FILE"
    rm -f "$MANIFEST_FILE"
    safe_rm_rf "$CONFIG_DIR" /etc
    ok "Purge completed."
    # Keep backups (they hold the removed Open WebUI data), the run lock and the log.
    echo "Backups kept in ${BACKUP_DIR} and the log in ${LOG_DIR}."
    echo "Delete them when no longer needed: rm -rf ${STATE_DIR} ${LOG_DIR}"
  else
    ok "Uninstall completed."
  fi

  pause
}
