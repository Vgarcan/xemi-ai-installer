# Jupyter as Open WebUI's code interpreter: model-written Python runs on the server (instead of
# in each user's browser with Pyodide), with numpy, pandas and matplotlib, and charts come back
# into the chat. It runs as its own user with the same sandbox as Open Terminal.

install_jupyter() {
  header
  echo "Installing Jupyter as the Open WebUI code interpreter (${JUPYTER_PACKAGES})..."
  echo ""
  warn "Code written by the models runs on this server as user '${JUPYTER_USER}'."
  echo "The service has no sudo, a read-only system view, writes only to ${JUPYTER_HOME},"
  echo "cannot see other users' processes and listens on 127.0.0.1 with a token."
  echo "Its workspace is shared by everyone allowed to use the code interpreter."
  echo ""
  confirm_extra_install "Install Jupyter" || { pause; return 0; }

  load_manifest
  extras_preflight jupyter "$JUPYTER_VENV" JUPYTER_INSTALLED || { pause; return 1; }
  local port
  port="$(ask_free_port "Jupyter port" "${JUPYTER_PORT:-$JUPYTER_PORT_DEFAULT}")" || { fail "No free port for Jupyter."; pause; return 1; }
  run_extra_install "Jupyter" jupyter_install_steps remove_jupyter "$port" jupyter
}

write_jupyter_service() {
  local port="$1"
  write_extra_service jupyter "Jupyter code interpreter for Open WebUI" "$JUPYTER_USER" \
    "$JUPYTER_HOME" "$JUPYTER_HOME" \
    "${JUPYTER_VENV}/bin/jupyter server --ServerApp.ip=127.0.0.1 --ServerApp.port=${port} --ServerApp.root_dir=${JUPYTER_HOME} --ServerApp.open_browser=False --ServerApp.terminals_enabled=False --MappingKernelManager.cull_idle_timeout=900 --MappingKernelManager.cull_interval=120" \
    "EnvironmentFile=${JUPYTER_ENV_FILE}"
}

jupyter_install_steps() {
  local port="$1"
  local token kernel
  ensure_python311_ready || return 1
  ensure_extras_identity "$JUPYTER_USER" "$JUPYTER_HOME" /bin/bash JUPYTER_USER_CREATED || return 1
  record_manifest "JUPYTER_INSTALLED" "1" || return 1
  JUPYTER_INSTALLED=1
  # shellcheck disable=SC2086
  create_extras_venv "$JUPYTER_VENV" "$JUPYTER_USER" $JUPYTER_PACKAGES || return 1

  token="$(new_extras_secret)" || return 1
  # JUPYTER_TOKEN keeps the token out of the process list.
  (umask 077; printf 'JUPYTER_TOKEN=%s\n' "$token" > "$JUPYTER_ENV_FILE") || return 1
  write_jupyter_service "$port" || return 1
  record_manifest "JUPYTER_PORT" "$port" || return 1
  JUPYTER_PORT="$port"

  start_extra_service jupyter "http://127.0.0.1:${port}/api" || return 1
  # A kernel must start: that is what Open WebUI does for every code run.
  kernel="$(curl -fsS --max-time 60 -X POST -H @<(printf 'Authorization: token %s\n' "$token") \
    "http://127.0.0.1:${port}/api/kernels" 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true)"
  if [ -z "$kernel" ]; then
    fail "Jupyter runs but cannot start a Python kernel. Check: journalctl -u jupyter -e"
    return 1
  fi
  curl -fsS --max-time 30 -X DELETE -H @<(printf 'Authorization: token %s\n' "$token") \
    "http://127.0.0.1:${port}/api/kernels/${kernel}" >/dev/null 2>&1 || true
  ok "Jupyter ready on 127.0.0.1:${port} (test kernel started and stopped)."
  echo ""
  show_jupyter_connection
}

show_jupyter_connection() {
  echo "Jupyter -> Open WebUI: Admin settings > Code Execution"
  echo "  Code Execution and Code Interpreter engine: Jupyter"
  echo "  URL: http://127.0.0.1:${JUPYTER_PORT:-$JUPYTER_PORT_DEFAULT}   Auth: Token (sudo grep TOKEN ${JUPYTER_ENV_FILE})"
}

update_jupyter() {
  # shellcheck disable=SC2086
  run_required "Updating Jupyter and its libraries..." "${JUPYTER_VENV}/bin/pip" install --no-cache-dir -U $JUPYTER_PACKAGES || return 1
  grant_group_read "$JUPYTER_USER" "$JUPYTER_VENV" || return 1
  write_jupyter_service "${JUPYTER_PORT:-$JUPYTER_PORT_DEFAULT}" || return 1
  start_extra_service jupyter "http://127.0.0.1:${JUPYTER_PORT:-$JUPYTER_PORT_DEFAULT}/api"
}

# The workspace and the aijupyter user are removed by remove_unused_extras_identities.
remove_jupyter() {
  [ "${JUPYTER_INSTALLED:-}" = "1" ] || return 0
  remove_extra_service jupyter
  if [ -d "$JUPYTER_VENV" ]; then
    safe_rm_rf "$JUPYTER_VENV" /opt
  fi
  rm -f "$JUPYTER_ENV_FILE"
  remove_manifest_key JUPYTER_INSTALLED
  remove_manifest_key JUPYTER_PORT
  JUPYTER_INSTALLED=""
  ok "Jupyter removed."
  owui_was_disconnected jupyter || warn "Also set Code Execution back to Pyodide in Open WebUI: Admin settings > Code Execution."
  # Set back only by the Open WebUI disconnect; without it the restriction stays.
  if [ "${JUPYTER_PERMISSION_CHANGED:-}" = "1" ]; then
    warn "The code interpreter is still limited to admins. To give it back to all users: Admin settings > Users > Permissions > Code Interpreter."
    remove_manifest_key JUPYTER_PERMISSION_CHANGED
    JUPYTER_PERMISSION_CHANGED=""
  fi
}

# Files the kernels or Jupyter create for themselves are not user work.
jupyter_user_files() {
  [ -d "$JUPYTER_HOME" ] || return 0
  find "$JUPYTER_HOME" -mindepth 1 -type f \
    ! -path "${JUPYTER_HOME}/.bash_logout" \
    ! -path "${JUPYTER_HOME}/.bash_profile" \
    ! -path "${JUPYTER_HOME}/.bashrc" \
    ! -path "${JUPYTER_HOME}/.local/*" \
    ! -path "${JUPYTER_HOME}/.ipython/*" \
    ! -path "${JUPYTER_HOME}/.cache/*" \
    ! -path "${JUPYTER_HOME}/.config/*" \
    ! -path "${JUPYTER_HOME}/.jupyter/*" \
    -print
}
