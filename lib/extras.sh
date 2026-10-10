# Optional Open WebUI tools: Open Terminal, mcpo, SearXNG and Apache Tika.
# Each tool runs natively (venv or jar) as a hardened systemd service bound to 127.0.0.1;
# Open WebUI reaches them from its backend, so no firewall rules are needed.

port_in_use() {
  ss -ltnH "( sport = :$1 )" 2>/dev/null | grep -q .
}

ask_free_port() {
  local prompt="$1"
  local default="$2"
  local port
  while true; do
    port="$(ask_port "$prompt" "$default")"
    if ! port_in_use "$port"; then
      echo "$port"
      return 0
    fi
    warn "Port ${port} is already in use." >&2
    if [ "$ASSUME_YES" = "1" ]; then
      return 1
    fi
  done
}

new_extras_secret() {
  "$PY311_BIN" -c 'import secrets; print(secrets.token_urlsafe(32))'
}

wait_http_ok() {
  local url="$1"
  local attempts="${2:-60}"
  local i
  for ((i=1; i<=attempts; i++)); do
    if curl -fsS --max-time 5 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

ensure_python311_ready() {
  if [ ! -x "$PY311_BIN" ]; then
    install_python311 || return 1
  fi
}

ensure_extras_identity() {
  local name="$1"
  local home="$2"
  local shell="$3"
  local created_key="$4"
  validate_identity "$name" || { fail "Invalid service user name: $name"; return 1; }
  if ! id "$name" >/dev/null 2>&1; then
    useradd --system --user-group --home-dir "$home" --create-home --shell "$shell" "$name" || return 1
    record_manifest "$created_key" "1" || return 1
  fi
  mkdir -p "$home" || return 1
  # "user:" assigns the user's own primary group, whatever its name is.
  chown "$name:" "$home" || return 1
  chmod 750 "$home"
}

# Code stays root-owned; the service user's primary group only gets read/execute access.
grant_group_read() {
  local user="$1"
  local group
  shift
  group="$(id -gn "$user")" || return 1
  chgrp -R "$group" "$@" || return 1
  chmod -R g+rX,g-w "$@"
}

# Installs PACKAGE if missing and records the RPMs that transaction added, so removal can undo it.
install_tracked_package() {
  local package="$1"
  local record="${EXTRAS_PACKAGES_DIR}/$2.list"
  local before after
  if rpm -q "$package" >/dev/null 2>&1; then
    return 0
  fi
  mkdir -p "$EXTRAS_PACKAGES_DIR" || return 1
  before="$(rpm -qa --qf '%{NAME}\n' | sort -u)" || return 1
  run_required "Installing ${package}..." dnf install -y "$package" || return 1
  after="$(rpm -qa --qf '%{NAME}\n' | sort -u)" || return 1
  comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") > "$record"
}

# Removes the RPMs recorded by install_tracked_package unless other software now needs them.
remove_tracked_packages() {
  local name="$1"
  local record="${EXTRAS_PACKAGES_DIR}/${name}.list"
  local -a packages=()
  local package
  [ -f "$record" ] || return 0
  # Only packages still installed; some may have been removed by hand since.
  while IFS= read -r package; do
    if [ -n "$package" ] && rpm -q --quiet "$package"; then
      packages+=("$package")
    fi
  done < "$record"
  if [ "${#packages[@]}" -gt 0 ]; then
    if rpm -e --test "${packages[@]}" >/dev/null 2>&1; then
      run_optional "Removing packages installed for ${name}: ${packages[*]}" \
        dnf remove -y --setopt=clean_requirements_on_remove=False "${packages[@]}" \
        || warn "Could not remove packages installed for ${name}: ${packages[*]}"
    else
      warn "Packages installed for ${name} are now needed by other software; kept: ${packages[*]}"
    fi
  fi
  rm -f "$record"
  rmdir "$EXTRAS_PACKAGES_DIR" >/dev/null 2>&1 || true
}

# Files Open Terminal or the shell create on their own are not user work.
open_terminal_user_files() {
  [ -d "$OPEN_TERMINAL_HOME" ] || return 0
  find "$OPEN_TERMINAL_HOME" -mindepth 1 -type f \
    ! -path "${OPEN_TERMINAL_HOME}/.bash_logout" \
    ! -path "${OPEN_TERMINAL_HOME}/.bash_profile" \
    ! -path "${OPEN_TERMINAL_HOME}/.bashrc" \
    ! -path "${OPEN_TERMINAL_HOME}/.bash_history" \
    ! -path "${OPEN_TERMINAL_HOME}/.local/state/open-terminal/*" \
    ! -path "${OPEN_TERMINAL_HOME}/.cache/*" \
    -print
}

remove_extras_identity() {
  local name="$1"
  local home="$2"
  local flag="$3"
  local base="$4"
  if id "$name" >/dev/null 2>&1 && ! userdel "$name"; then
    warn "Could not remove user ${name}; it is kept."
    return 0
  fi
  if getent group "$name" >/dev/null 2>&1; then
    groupdel "$name" >/dev/null 2>&1 || warn "Could not remove group ${name}."
  fi
  if [ -d "$home" ]; then
    safe_rm_rf "$home" "$base"
  fi
  rm -f "/var/spool/mail/${name}"
  remove_manifest_key "$flag"
  printf -v "$flag" '%s' ""
  ok "Service user and home removed: ${name} (${home})"
}

# Removes the service users this installer created once no installed tool needs them,
# so removing every tool leaves nothing behind. Kept: an Open Terminal workspace with
# user files that the operator chose to keep (its owner is kept with it).
remove_unused_extras_identities() {
  local purge="${1:-0}"
  local count ans
  if [ "${TERMINAL_USER_CREATED:-}" = "1" ] && [ "${OPEN_TERMINAL_INSTALLED:-}" != "1" ]; then
    count="$(open_terminal_user_files | wc -l)"
    ans="yes"
    if [ "$purge" != "1" ] && [ "$count" -gt 0 ]; then
      ans="$(ask "Open Terminal workspace ${OPEN_TERMINAL_HOME} has ${count} file(s). Delete it yes or no" "no")"
    fi
    if is_yes "$ans"; then
      remove_extras_identity "$TERMINAL_USER" "$OPEN_TERMINAL_HOME" TERMINAL_USER_CREATED /var/lib
    else
      warn "Open Terminal workspace kept with its owner ${TERMINAL_USER}: ${OPEN_TERMINAL_HOME}"
    fi
  fi
  if [ "${EXTRAS_USER_CREATED:-}" = "1" ] && [ "${MCPO_INSTALLED:-}" != "1" ] \
    && [ "${SEARXNG_INSTALLED:-}" != "1" ] && [ "${TIKA_INSTALLED:-}" != "1" ]; then
    remove_extras_identity "$EXTRAS_USER" "$EXTRAS_HOME" EXTRAS_USER_CREATED /var/lib
  fi
}

# Common teardown for a tool's systemd service.
remove_extra_service() {
  local service="$1"
  stop_disable_service "$service"
  rm -f "/etc/systemd/system/${service}.service"
  if [ -d "/etc/systemd/system/${service}.service.d" ]; then
    safe_rm_rf "/etc/systemd/system/${service}.service.d" /etc/systemd/system
  fi
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl reset-failed "$service" >/dev/null 2>&1 || true
}

create_extras_venv() {
  local venv="$1"
  local user="$2"
  shift 2
  run_required "Creating virtual environment ${venv}..." "$PY311_BIN" -m venv "$venv" || return 1
  run_required "Upgrading pip in ${venv}..." "$venv/bin/pip" install --no-cache-dir --upgrade pip || return 1
  run_required "Installing $*..." "$venv/bin/pip" install --no-cache-dir -U "$@" || return 1
  "$venv/bin/pip" check || { fail "Dependencies in ${venv} are inconsistent."; return 1; }
  grant_group_read "$user" "$venv"
}

# Refuses to touch services or paths this installer did not create.
extras_preflight() {
  local service="$1"
  local path="$2"
  local flag="$3"
  if [ "${!flag:-}" = "1" ]; then
    warn "${service} is already installed. Use 'Update installed tools' or remove it first."
    return 1
  fi
  if [ -e "/etc/systemd/system/${service}.service" ]; then
    fail "An existing ${service}.service is not managed by this installer; leaving it untouched."
    return 1
  fi
  if [ -e "$path" ] || [ -L "$path" ]; then
    fail "Path already exists and is not managed by this installer: $path"
    return 1
  fi
}

# Usage: write_extra_service NAME DESCRIPTION USER WORKDIR RW_PATHS EXEC_START [extra [Service] lines...]
# Group= is omitted so systemd uses the user's primary group.
write_extra_service() {
  local name="$1"
  local description="$2"
  local user="$3"
  local workdir="$4"
  local rw_paths="$5"
  local exec_start="$6"
  shift 6
  local unit="/etc/systemd/system/${name}.service"
  backup_path "$unit" || return 1
  {
    cat <<EOF
[Unit]
Description=${description}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${user}
WorkingDirectory=${workdir}
ExecStart=${exec_start}
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectProc=invisible
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ReadWritePaths=${rw_paths}
EOF
    if [ "$#" -gt 0 ]; then
      printf '%s\n' "$@"
    fi
    cat <<'EOF'

[Install]
WantedBy=multi-user.target
EOF
  } > "$unit" || return 1
  write_extra_hardening "$name"
}

# Extra sandboxing lives in a drop-in so existing installs receive it on "Update installed tools".
# Verified with all four tools: exposure score drops from 7.4 (MEDIUM) to 1.5 (OK).
write_extra_hardening() {
  local name="$1"
  local dir="/etc/systemd/system/${name}.service.d"
  mkdir -p "$dir" || return 1
  {
    cat <<'EOF'
[Service]
UMask=0027
CapabilityBoundingSet=
AmbientCapabilities=
PrivateDevices=true
ProtectKernelLogs=true
ProtectClock=true
ProtectHostname=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
RemoveIPC=true
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM
EOF
    # The JVM exits with 143 on SIGTERM; without this every stop is reported as a failure.
    if [ "$name" = "tika" ]; then
      echo "SuccessExitStatus=143"
    fi
  } > "${dir}/xemi-hardening.conf"
}

start_extra_service() {
  local service="$1"
  local health_url="$2"
  systemctl daemon-reload || return 1
  systemctl enable "$service" >/dev/null 2>&1 || return 1
  systemctl restart "$service" || { fail "${service} failed to start. Check: journalctl -u ${service} -e --no-pager"; return 1; }
  echo "Waiting for ${service} to respond..."
  if ! wait_http_ok "$health_url" 60; then
    fail "${service} did not respond at ${health_url}. Check: journalctl -u ${service} -e --no-pager"
    return 1
  fi
}

confirm_extra_install() {
  local ans
  ans="$(confirm_proceed "$1 yes or no" "yes")"
  if ! is_yes "$ans"; then
    warn "Cancelled."
    return 1
  fi
}

# Runs STEPS_FUNCTION PORT; on failure removes the partial install so it can be retried.
# On success offers to connect SERVICE to Open WebUI.
run_extra_install() {
  local label="$1"
  local steps="$2"
  local remover="$3"
  local port="$4"
  local service="$5"
  # The steps check every command explicitly: errexit is suspended inside an if condition.
  if ! "$steps" "$port"; then
    fail "${label} installation failed; removing the partial installation."
    load_manifest
    "$remover" 0
    remove_unused_extras_identities 0
    pause
    return 1
  fi
  offer_openwebui_connect "$service"
  pause
}

# ---------------------------------------------------------------------------
# Open Terminal
# ---------------------------------------------------------------------------

install_open_terminal() {
  header
  echo "Installing Open Terminal (shell, files and code execution for models)..."
  echo ""
  warn "Models connected to Open Terminal can run any command as user '${TERMINAL_USER}'."
  echo "The service has no sudo, a read-only system view, writes only to ${OPEN_TERMINAL_HOME},"
  echo "cannot see other users' processes and listens on 127.0.0.1 only."
  echo "It can still read world-readable files and reach the network."
  echo ""
  confirm_extra_install "Install Open Terminal" || { pause; return 0; }

  load_manifest
  extras_preflight open-terminal "$OPEN_TERMINAL_VENV" OPEN_TERMINAL_INSTALLED || { pause; return 1; }
  local port
  port="$(ask_free_port "Open Terminal port" "${OPEN_TERMINAL_PORT:-$OPEN_TERMINAL_PORT_DEFAULT}")" || { fail "No free port for Open Terminal."; pause; return 1; }
  run_extra_install "Open Terminal" open_terminal_install_steps remove_open_terminal "$port" open-terminal
}

open_terminal_install_steps() {
  local port="$1"
  local key
  ensure_python311_ready || return 1
  ensure_extras_identity "$TERMINAL_USER" "$OPEN_TERMINAL_HOME" /bin/bash TERMINAL_USER_CREATED || return 1
  record_manifest "OPEN_TERMINAL_INSTALLED" "1" || return 1
  OPEN_TERMINAL_INSTALLED=1
  create_extras_venv "$OPEN_TERMINAL_VENV" "$TERMINAL_USER" open-terminal || return 1

  key="$(new_extras_secret)" || return 1
  (umask 077; printf 'OPEN_TERMINAL_API_KEY=%s\n' "$key" > "$OPEN_TERMINAL_ENV_FILE") || return 1

  write_extra_service open-terminal "Open Terminal for Open WebUI" "$TERMINAL_USER" \
    "$OPEN_TERMINAL_HOME" "$OPEN_TERMINAL_HOME" \
    "${OPEN_TERMINAL_VENV}/bin/open-terminal run --host 127.0.0.1 --port ${port} --cwd ${OPEN_TERMINAL_HOME}" \
    "EnvironmentFile=${OPEN_TERMINAL_ENV_FILE}" || return 1
  record_manifest "OPEN_TERMINAL_PORT" "$port" || return 1
  OPEN_TERMINAL_PORT="$port"

  start_extra_service open-terminal "http://127.0.0.1:${port}/health" || return 1
  ok "Open Terminal ready on 127.0.0.1:${port}."
  echo ""
  show_open_terminal_connection
  echo "  API key:  ${key}"
}

show_open_terminal_connection() {
  echo "Open Terminal -> Open WebUI: Admin settings > Integrations > Open Terminal > +"
  echo "  URL:      http://127.0.0.1:${OPEN_TERMINAL_PORT:-$OPEN_TERMINAL_PORT_DEFAULT}"
  echo "  Auth:     Bearer (key: sudo grep KEY ${OPEN_TERMINAL_ENV_FILE})"
  echo "  Models:   Workspace > Models > Function Calling = Native"
}

# The workspace and the aiterminal user are removed by remove_unused_extras_identities.
remove_open_terminal() {
  [ "${OPEN_TERMINAL_INSTALLED:-}" = "1" ] || return 0
  remove_extra_service open-terminal
  if [ -d "$OPEN_TERMINAL_VENV" ]; then
    safe_rm_rf "$OPEN_TERMINAL_VENV" /opt
  fi
  rm -f "$OPEN_TERMINAL_ENV_FILE"
  remove_manifest_key OPEN_TERMINAL_INSTALLED
  remove_manifest_key OPEN_TERMINAL_PORT
  OPEN_TERMINAL_INSTALLED=""
  ok "Open Terminal removed."
  owui_was_disconnected open-terminal || warn "Also delete its connection in Open WebUI: Admin settings > Integrations > Open Terminal."
}

# ---------------------------------------------------------------------------
# mcpo (MCP tools exposed as OpenAPI tool servers)
# ---------------------------------------------------------------------------

install_mcpo() {
  header
  echo "Installing mcpo with MCP servers 'time' and 'fetch'..."
  echo "More MCP servers can be added later in ${MCPO_CONFIG_DIR}/config.json."
  echo ""
  confirm_extra_install "Install mcpo" || { pause; return 0; }

  load_manifest
  extras_preflight mcpo "$MCPO_VENV" MCPO_INSTALLED || { pause; return 1; }
  local port
  port="$(ask_free_port "mcpo port" "${MCPO_PORT:-$MCPO_PORT_DEFAULT}")" || { fail "No free port for mcpo."; pause; return 1; }
  run_extra_install "mcpo" mcpo_install_steps remove_mcpo "$port" mcpo
}

mcpo_install_steps() {
  local port="$1"
  local key timezone
  timezone="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
  [[ "$timezone" =~ ^[A-Za-z0-9_+/-]+$ ]] || timezone="UTC"

  ensure_python311_ready || return 1
  ensure_extras_identity "$EXTRAS_USER" "$EXTRAS_HOME" /sbin/nologin EXTRAS_USER_CREATED || return 1
  record_manifest "MCPO_INSTALLED" "1" || return 1
  MCPO_INSTALLED=1
  create_extras_venv "$MCPO_VENV" "$EXTRAS_USER" mcpo mcp-server-time mcp-server-fetch || return 1

  mkdir -p "$MCPO_CONFIG_DIR" || return 1
  cat > "${MCPO_CONFIG_DIR}/config.json" <<EOF || return 1
{
  "mcpServers": {
    "time": {
      "command": "${MCPO_VENV}/bin/mcp-server-time",
      "args": ["--local-timezone=${timezone}"]
    },
    "fetch": {
      "command": "${MCPO_VENV}/bin/mcp-server-fetch",
      "args": []
    }
  }
}
EOF
  grant_group_read "$EXTRAS_USER" "$MCPO_CONFIG_DIR" || return 1

  key="$(new_extras_secret)" || return 1
  (umask 077; printf 'MCPO_API_KEY=%s\n' "$key" > "$MCPO_ENV_FILE") || return 1

  # mcpo only accepts the key as an argument. ProtectProc=invisible keeps the Open Terminal
  # user from reading it in the process list; other local login users can still see it.
  write_extra_service mcpo "mcpo MCP tool proxy for Open WebUI" "$EXTRAS_USER" \
    "$EXTRAS_HOME" "$EXTRAS_HOME" \
    "${MCPO_VENV}/bin/mcpo --host 127.0.0.1 --port ${port} --config ${MCPO_CONFIG_DIR}/config.json --api-key \${MCPO_API_KEY}" \
    "EnvironmentFile=${MCPO_ENV_FILE}" || return 1
  record_manifest "MCPO_PORT" "$port" || return 1
  MCPO_PORT="$port"

  start_extra_service mcpo "http://127.0.0.1:${port}/time/openapi.json" || return 1
  ok "mcpo ready on 127.0.0.1:${port}."
  echo ""
  show_mcpo_connection
  echo "  API key:  ${key}"
}

show_mcpo_connection() {
  local port="${MCPO_PORT:-$MCPO_PORT_DEFAULT}"
  echo "mcpo -> Open WebUI: Admin settings > Integrations > Manage Tool Servers > + (OpenAPI)"
  echo "  URLs:     http://127.0.0.1:${port}/time  and  http://127.0.0.1:${port}/fetch"
  echo "  Auth:     Bearer (key: sudo grep KEY ${MCPO_ENV_FILE})"
}

remove_mcpo() {
  [ "${MCPO_INSTALLED:-}" = "1" ] || return 0
  remove_extra_service mcpo
  if [ -d "$MCPO_VENV" ]; then
    safe_rm_rf "$MCPO_VENV" /opt
  fi
  if [ -d "$MCPO_CONFIG_DIR" ]; then
    safe_rm_rf "$MCPO_CONFIG_DIR" /etc
  fi
  rm -f "$MCPO_ENV_FILE"
  remove_manifest_key MCPO_INSTALLED
  remove_manifest_key MCPO_PORT
  MCPO_INSTALLED=""
  ok "mcpo removed."
  owui_was_disconnected mcpo || warn "Also delete its tool server connections in Open WebUI: Admin settings > Integrations."
}

# ---------------------------------------------------------------------------
# SearXNG (private web search)
# ---------------------------------------------------------------------------

install_searxng() {
  header
  echo "Installing SearXNG (private metasearch for Open WebUI web search)..."
  echo ""
  confirm_extra_install "Install SearXNG" || { pause; return 0; }

  load_manifest
  extras_preflight searxng "$SEARXNG_DIR" SEARXNG_INSTALLED || { pause; return 1; }
  local port
  port="$(ask_free_port "SearXNG port" "${SEARXNG_PORT:-$SEARXNG_PORT_DEFAULT}")" || { fail "No free port for SearXNG."; pause; return 1; }
  run_extra_install "SearXNG" searxng_install_steps remove_searxng "$port" searxng
}

searxng_install_steps() {
  local port="$1"
  local commit secret
  ensure_python311_ready || return 1
  ensure_extras_identity "$EXTRAS_USER" "$EXTRAS_HOME" /sbin/nologin EXTRAS_USER_CREATED || return 1
  record_manifest "SEARXNG_INSTALLED" "1" || return 1
  SEARXNG_INSTALLED=1
  install_tracked_package git searxng || return 1

  mkdir -p "$SEARXNG_DIR" || return 1
  run_required "Downloading SearXNG source..." git clone --depth 1 "$SEARXNG_REPO" "${SEARXNG_DIR}/src" || return 1
  commit="$(git -C "${SEARXNG_DIR}/src" rev-parse HEAD)" || return 1
  searxng_install_python_env || return 1

  secret="$(new_extras_secret)" || return 1
  mkdir -p "$SEARXNG_CONFIG_DIR" || return 1
  cat > "${SEARXNG_CONFIG_DIR}/settings.yml" <<EOF || return 1
use_default_settings: true
general:
  instance_name: "Xemi SearXNG"
server:
  secret_key: "${secret}"
  limiter: false
  image_proxy: false
search:
  formats:
    - html
    - json
EOF
  grant_group_read "$EXTRAS_USER" "$SEARXNG_CONFIG_DIR" || return 1

  write_extra_service searxng "SearXNG for Open WebUI" "$EXTRAS_USER" \
    "${SEARXNG_DIR}/src" "$EXTRAS_HOME" \
    "${SEARXNG_DIR}/venv/bin/granian searx.webapp:app" \
    "Environment=SEARXNG_SETTINGS_PATH=${SEARXNG_CONFIG_DIR}/settings.yml" \
    "Environment=GRANIAN_INTERFACE=wsgi" \
    "Environment=GRANIAN_HOST=127.0.0.1" \
    "Environment=GRANIAN_PORT=${port}" \
    "Environment=GRANIAN_WEBSOCKETS=false" \
    "Environment=GRANIAN_BLOCKING_THREADS=4" || return 1
  record_manifest "SEARXNG_PORT" "$port" || return 1
  record_manifest "SEARXNG_COMMIT" "$commit" || return 1
  SEARXNG_PORT="$port"

  start_extra_service searxng "http://127.0.0.1:${port}/healthz" || return 1
  if curl -fsS --max-time 30 "http://127.0.0.1:${port}/search?q=test&format=json" >/dev/null 2>&1; then
    ok "SearXNG ready on 127.0.0.1:${port} (JSON search verified)."
  else
    warn "SearXNG is running, but a test search failed. Check internet access and: journalctl -u searxng -e"
  fi
  echo ""
  show_searxng_connection
}

# Installs or refreshes the SearXNG venv from ${SEARXNG_DIR}/src (official manual-install steps).
searxng_install_python_env() {
  local venv="${SEARXNG_DIR}/venv"
  if [ ! -d "$venv" ]; then
    run_required "Creating SearXNG virtual environment..." "$PY311_BIN" -m venv "$venv" || return 1
  fi
  run_required "Installing SearXNG build requirements..." "$venv/bin/pip" install --no-cache-dir -U pip setuptools wheel pyyaml msgspec typing-extensions pybind11 || return 1
  run_required "Installing SearXNG..." "$venv/bin/pip" install --no-cache-dir --use-pep517 --no-build-isolation -e "${SEARXNG_DIR}/src" || return 1
  # EL9 ships SQLite 3.34; SearXNG needs 3.35+, same fix as Open WebUI.
  run_required "Installing Granian server and SQLite compatibility..." "$venv/bin/pip" install --no-cache-dir -U granian pysqlite3-binary || return 1
  "$venv/bin/pip" check || { fail "SearXNG dependencies are inconsistent."; return 1; }
  write_sqlite_compat "$venv" || return 1
  grant_group_read "$EXTRAS_USER" "$SEARXNG_DIR"
}

# Moves SearXNG to the latest upstream commit; returns to the previous commit if it fails.
update_searxng() {
  local src="${SEARXNG_DIR}/src"
  local url="http://127.0.0.1:${SEARXNG_PORT:-$SEARXNG_PORT_DEFAULT}/healthz"
  local old new
  old="$(git -C "$src" rev-parse HEAD)" || return 1
  run_required "Fetching latest SearXNG..." git -C "$src" fetch --depth 1 origin HEAD || return 1
  new="$(git -C "$src" rev-parse FETCH_HEAD)" || return 1
  if [ "$old" = "$new" ]; then
    # Restart anyway so refreshed service settings (hardening drop-in) take effect.
    start_extra_service searxng "$url" || return 1
    ok "SearXNG is already up to date (${old:0:12}); service settings refreshed."
    return 0
  fi

  if git -C "$src" reset -q --hard "$new" && searxng_install_python_env && start_extra_service searxng "$url"; then
    record_manifest "SEARXNG_COMMIT" "$new" || return 1
    ok "SearXNG updated to ${new:0:12}."
    return 0
  fi

  warn "SearXNG update failed; restoring ${old:0:12}."
  if git -C "$src" reset -q --hard "$old" && searxng_install_python_env && start_extra_service searxng "$url"; then
    ok "SearXNG restored to ${old:0:12}."
  else
    fail "SearXNG rollback failed. Check: journalctl -u searxng -e --no-pager"
  fi
  return 1
}

show_searxng_connection() {
  echo "SearXNG -> Open WebUI: Admin settings > Web Search"
  echo "  Enable web search, engine: searxng"
  echo "  Query URL: http://127.0.0.1:${SEARXNG_PORT:-$SEARXNG_PORT_DEFAULT}/search?q=<query>"
}

remove_searxng() {
  [ "${SEARXNG_INSTALLED:-}" = "1" ] || return 0
  remove_extra_service searxng
  if [ -d "$SEARXNG_DIR" ]; then
    safe_rm_rf "$SEARXNG_DIR" /opt
  fi
  if [ -d "$SEARXNG_CONFIG_DIR" ]; then
    safe_rm_rf "$SEARXNG_CONFIG_DIR" /etc
  fi
  remove_manifest_key SEARXNG_INSTALLED
  remove_manifest_key SEARXNG_PORT
  remove_manifest_key SEARXNG_COMMIT
  remove_tracked_packages searxng
  SEARXNG_INSTALLED=""
  ok "SearXNG removed."
  owui_was_disconnected searxng || warn "Also turn off SearXNG web search in Open WebUI: Admin settings > Web Search."
}

# ---------------------------------------------------------------------------
# Apache Tika (document text extraction)
# ---------------------------------------------------------------------------

tika_java_home() {
  local dir
  for dir in /usr/lib/jvm/jre-21 /usr/lib/jvm/jre-21-openjdk; do
    if [ -x "${dir}/bin/java" ]; then
      echo "$dir"
      return 0
    fi
  done
  return 1
}

install_tika() {
  header
  echo "Installing Apache Tika ${TIKA_VERSION} server (PDF/Office text extraction for documents)..."
  echo ""
  confirm_extra_install "Install Apache Tika" || { pause; return 0; }

  load_manifest
  extras_preflight tika "$TIKA_DIR" TIKA_INSTALLED || { pause; return 1; }
  local port
  port="$(ask_free_port "Tika port" "${TIKA_PORT:-$TIKA_PORT_DEFAULT}")" || { fail "No free port for Tika."; pause; return 1; }
  run_extra_install "Apache Tika" tika_install_steps remove_tika "$port" tika
}

tika_install_steps() {
  local port="$1"
  local java_home tmp jar
  ensure_extras_identity "$EXTRAS_USER" "$EXTRAS_HOME" /sbin/nologin EXTRAS_USER_CREATED || return 1
  record_manifest "TIKA_INSTALLED" "1" || return 1
  TIKA_INSTALLED=1
  install_tracked_package java-21-openjdk-headless tika || return 1
  java_home="$(tika_java_home)" || { fail "Java 21 runtime not found under /usr/lib/jvm."; return 1; }

  mkdir -p "$TIKA_DIR" || return 1
  jar="${TIKA_DIR}/tika-server-standard-${TIKA_VERSION}.jar"
  tmp="$(mktemp "${TIKA_DIR}/download.XXXXXX")" || return 1
  if ! curl -fL --retry 3 -o "$tmp" "https://dlcdn.apache.org/tika/${TIKA_VERSION}/tika-server-standard-${TIKA_VERSION}.jar" \
    && ! curl -fL --retry 3 -o "$tmp" "https://archive.apache.org/dist/tika/${TIKA_VERSION}/tika-server-standard-${TIKA_VERSION}.jar"; then
    fail "Could not download Apache Tika ${TIKA_VERSION}."
    return 1
  fi
  if ! echo "${TIKA_SHA512}  ${tmp}" | sha512sum -c --status -; then
    fail "Apache Tika download failed SHA512 verification."
    return 1
  fi
  mv -f "$tmp" "$jar" || return 1
  grant_group_read "$EXTRAS_USER" "$TIKA_DIR" || return 1

  # Tika forks a child JVM found through PATH, so the runtime must be first in PATH.
  write_extra_service tika "Apache Tika server for Open WebUI" "$EXTRAS_USER" \
    "$EXTRAS_HOME" "$EXTRAS_HOME" \
    "${java_home}/bin/java -jar ${jar} --host 127.0.0.1 --port ${port}" \
    "Environment=PATH=${java_home}/bin:/usr/bin:/bin" || return 1
  record_manifest "TIKA_PORT" "$port" || return 1
  record_manifest "TIKA_INSTALLED_VERSION" "$TIKA_VERSION" || return 1
  TIKA_PORT="$port"

  start_extra_service tika "http://127.0.0.1:${port}/version" || return 1
  ok "Apache Tika ready on 127.0.0.1:${port}."
  echo ""
  show_tika_connection
}

show_tika_connection() {
  echo "Apache Tika -> Open WebUI: Admin settings > Documents"
  echo "  Content Extraction Engine: Tika"
  echo "  URL: http://127.0.0.1:${TIKA_PORT:-$TIKA_PORT_DEFAULT}"
}

remove_tika() {
  [ "${TIKA_INSTALLED:-}" = "1" ] || return 0
  remove_extra_service tika
  if [ -d "$TIKA_DIR" ]; then
    safe_rm_rf "$TIKA_DIR" /opt
  fi
  remove_manifest_key TIKA_INSTALLED
  remove_manifest_key TIKA_PORT
  remove_manifest_key TIKA_INSTALLED_VERSION
  remove_tracked_packages tika
  TIKA_INSTALLED=""
  ok "Apache Tika removed."
  owui_was_disconnected tika || warn "Also set the content extraction engine back to Default in Open WebUI: Admin settings > Documents."
}

# ---------------------------------------------------------------------------
# Shared status, update and removal
# ---------------------------------------------------------------------------

# Prints "service|label|health URL|manifest flag" for every supported tool.
openwebui_extras_table() {
  echo "open-terminal|Open Terminal|http://127.0.0.1:${OPEN_TERMINAL_PORT:-$OPEN_TERMINAL_PORT_DEFAULT}/health|OPEN_TERMINAL_INSTALLED"
  echo "mcpo|mcpo|http://127.0.0.1:${MCPO_PORT:-$MCPO_PORT_DEFAULT}/time/openapi.json|MCPO_INSTALLED"
  echo "searxng|SearXNG|http://127.0.0.1:${SEARXNG_PORT:-$SEARXNG_PORT_DEFAULT}/healthz|SEARXNG_INSTALLED"
  echo "tika|Apache Tika|http://127.0.0.1:${TIKA_PORT:-$TIKA_PORT_DEFAULT}/version|TIKA_INSTALLED"
}

show_openwebui_extras_status() {
  header
  load_manifest
  local service label url flag state health any=0
  echo "Open WebUI tools:"
  echo ""
  while IFS='|' read -r service label url flag; do
    if [ "${!flag:-}" != "1" ]; then
      printf "  %-14s not installed\n" "$label"
      continue
    fi
    any=1
    state="$(systemctl is-active "$service" 2>/dev/null || true)"
    if curl -fsS --max-time 5 "$url" >/dev/null 2>&1; then health="responds"; else health="NOT responding"; fi
    printf "  %-14s service %-9s %s (%s)\n" "$label" "$state" "$health" "$url"
  done < <(openwebui_extras_table)
  echo ""

  if [ "$any" = "1" ]; then
    echo "Connection settings for Open WebUI:"
    echo ""
    [ "${OPEN_TERMINAL_INSTALLED:-}" = "1" ] && { show_open_terminal_connection; echo ""; }
    [ "${MCPO_INSTALLED:-}" = "1" ] && { show_mcpo_connection; echo ""; }
    [ "${SEARXNG_INSTALLED:-}" = "1" ] && { show_searxng_connection; echo ""; }
    [ "${TIKA_INSTALLED:-}" = "1" ] && { show_tika_connection; echo ""; }
  fi
  pause
}

update_openwebui_extras() {
  header
  load_manifest
  local updated=0

  if [ "${OPEN_TERMINAL_INSTALLED:-}" = "1" ]; then
    if run_required "Updating Open Terminal..." "$OPEN_TERMINAL_VENV/bin/pip" install --no-cache-dir -U open-terminal \
      && grant_group_read "$TERMINAL_USER" "$OPEN_TERMINAL_VENV" \
      && write_extra_hardening open-terminal \
      && start_extra_service open-terminal "http://127.0.0.1:${OPEN_TERMINAL_PORT:-$OPEN_TERMINAL_PORT_DEFAULT}/health"; then
      ok "Open Terminal updated."
    else
      warn "Open Terminal update failed."
    fi
    updated=1
  fi

  if [ "${MCPO_INSTALLED:-}" = "1" ]; then
    if run_required "Updating mcpo and MCP servers..." "$MCPO_VENV/bin/pip" install --no-cache-dir -U mcpo mcp-server-time mcp-server-fetch \
      && grant_group_read "$EXTRAS_USER" "$MCPO_VENV" \
      && write_extra_hardening mcpo \
      && start_extra_service mcpo "http://127.0.0.1:${MCPO_PORT:-$MCPO_PORT_DEFAULT}/time/openapi.json"; then
      ok "mcpo updated."
    else
      warn "mcpo update failed."
    fi
    updated=1
  fi

  if [ "${SEARXNG_INSTALLED:-}" = "1" ]; then
    write_extra_hardening searxng || warn "Could not write SearXNG hardening drop-in."
    update_searxng || true
    updated=1
  fi

  if [ "${TIKA_INSTALLED:-}" = "1" ]; then
    if write_extra_hardening tika && start_extra_service tika "http://127.0.0.1:${TIKA_PORT:-$TIKA_PORT_DEFAULT}/version"; then
      ok "Apache Tika service settings refreshed."
    else
      warn "Apache Tika could not be restarted with the refreshed settings."
    fi
    warn "Apache Tika is pinned to ${TIKA_INSTALLED_VERSION:-$TIKA_VERSION} with a verified checksum; it changes only with installer updates."
    updated=1
  fi

  if [ "$updated" != "1" ]; then
    warn "No Open WebUI tools are installed."
  fi
  pause
}

remove_openwebui_extras_interactive() {
  header
  load_manifest
  local service label url flag ans any=0 row
  local -a rows=() selected=()
  # Read the table first: prompts inside the loop must read from the terminal.
  mapfile -t rows < <(openwebui_extras_table)
  for row in "${rows[@]}"; do
    IFS='|' read -r service label url flag <<< "$row"
    [ "${!flag:-}" = "1" ] || continue
    any=1
    ans="$(ask "Remove ${label} yes or no" "no")"
    if is_yes "$ans"; then
      selected+=("$service")
    fi
  done

  # One Open WebUI login removes the connections of everything selected, then the tools go.
  if [ "${#selected[@]}" -gt 0 ]; then
    offer_openwebui_disconnect "${selected[@]}"
    for service in "${selected[@]}"; do
      case "$service" in
        open-terminal) remove_open_terminal ;;
        mcpo) remove_mcpo ;;
        searxng) remove_searxng ;;
        tika) remove_tika ;;
      esac
    done
  fi
  remove_unused_extras_identities 0
  [ "$any" = "1" ] || warn "No Open WebUI tools are installed."
  pause
}

# Prints the service names of the installed tools, space separated.
installed_openwebui_extras() {
  local service label url flag
  local -a found=()
  while IFS='|' read -r service label url flag; do
    if [ "${!flag:-}" = "1" ]; then
      found+=("$service")
    fi
  done < <(openwebui_extras_table)
  echo "${found[*]}"
}

remove_openwebui_extras() {
  local purge="$1"
  local -a installed=()
  read -r -a installed <<< "$(installed_openwebui_extras)"
  # Purge deletes the Open WebUI data it created, connections included; otherwise offer to clean them.
  if [ "${#installed[@]}" -gt 0 ] && ! { [ "$purge" = "1" ] && [ "${OPENWEBUI_DATA_CREATED:-}" = "1" ]; }; then
    offer_openwebui_disconnect "${installed[@]}"
  fi
  remove_open_terminal
  remove_mcpo
  remove_searxng
  remove_tika
  remove_unused_extras_identities "$purge"
}

doctor_check_openwebui_extras() {
  local service label url flag any=0
  while IFS='|' read -r service label url flag; do
    [ "${!flag:-}" = "1" ] || continue
    any=1
    doctor_check_service "$service"
    doctor_check_http "$label" "$url"
    if [ -f "/etc/systemd/system/${service}.service.d/xemi-hardening.conf" ]; then
      doctor_ok "${service} runs with the hardening drop-in"
    else
      doctor_warn "${service} runs without the hardening drop-in; run: tools-update"
    fi
  done < <(openwebui_extras_table)
  if [ "$any" = "1" ]; then
    echo ""
  fi
}
