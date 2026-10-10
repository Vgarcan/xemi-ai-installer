# Installation reports and readiness diagnostics.

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

# Context length and K/V cache must match what the manifest records (see ollama-tune).
doctor_check_ollama_memory() {
  local env ctx kv
  env="$(systemctl show ollama -p Environment --value --no-pager 2>/dev/null | tr ' ' '\n' || true)"
  ctx="$(sed -n 's/^OLLAMA_CONTEXT_LENGTH=//p' <<< "$env")"
  kv="$(sed -n 's/^OLLAMA_KV_CACHE_TYPE=//p' <<< "$env")"
  if [ -z "$ctx" ] || [ -z "$kv" ]; then
    doctor_warn "Ollama context length or K/V cache is not set (Ollama falls back to a 4096 context); run: ollama-tune"
  elif [ "$ctx" != "$OLLAMA_CONTEXT_LENGTH" ] || [ "$kv" != "$OLLAMA_KV_CACHE_TYPE" ]; then
    doctor_warn "Ollama runs with context ${ctx} / K/V ${kv}, but the manifest says ${OLLAMA_CONTEXT_LENGTH} / ${OLLAMA_KV_CACHE_TYPE}; run: ollama-tune"
  else
    doctor_ok "Ollama context ${ctx} tokens, K/V cache ${kv}"
  fi
}

doctor_check_ollama_exposure() {
  local host
  host="$(systemctl show ollama -p Environment --value --no-pager 2>/dev/null | tr ' ' '\n' | sed -n 's/^OLLAMA_HOST=//p' || true)"
  case "${host%:*}" in
    0.0.0.0|'*'|'')
      doctor_warn "Ollama listens on all interfaces (the firewall limits it to the LAN). If only Open WebUI uses it, set bind host 127.0.0.1: Ollama > Configure Ollama service for LAN"
      ;;
    *)
      doctor_ok "Ollama listens on ${host}"
      ;;
  esac
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

  local zone="${FIREWALL_ZONE:-}"
  if [ -z "$zone" ]; then zone="$(detect_firewall_zone)" || { doctor_fail "Cannot determine firewalld zone"; return 0; }; fi

  if [ "${FIREWALL_RULE_OLLAMA:-}" = "none" ] && { [ "${OLLAMA_BIND_HOST:-127.0.0.1}" = "127.0.0.1" ] || [ "${OLLAMA_BIND_HOST:-127.0.0.1}" = "localhost" ]; }; then
    doctor_ok "Ollama is local-only; no direct LAN rule needed"
  elif [ "${FIREWALL_RULE_OLLAMA:-}" = "none" ]; then
    local expected_ollama="rule family='ipv4' source address='${LAN_SUBNET:-$LAN_SUBNET_DEFAULT}' port protocol='tcp' port='${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}' accept"
    if firewall-cmd --permanent --zone="$zone" --query-rich-rule="$expected_ollama" >/dev/null 2>&1; then
      doctor_ok "External Ollama LAN rule exists"
    else
      doctor_fail "Ollama LAN rule missing"
    fi
  elif [ -n "${FIREWALL_RULE_OLLAMA:-}" ] && firewall-cmd --permanent --zone="$zone" --query-rich-rule="${FIREWALL_RULE_OLLAMA}" >/dev/null 2>&1; then
    doctor_ok "Firewall rule exists for Ollama"
  else
    doctor_fail "Firewall rule missing for Ollama"
  fi

  local webui_rule="${FIREWALL_RULE_WEBUI:-}"
  if [ "$webui_rule" = "none" ]; then
    webui_rule="rule family='ipv4' source address='${LAN_SUBNET:-$LAN_SUBNET_DEFAULT}' port protocol='tcp' port='${OPENWEBUI_PORT:-$WEBUI_PORT_DEFAULT}' accept"
  fi
  if [ -n "$webui_rule" ] && firewall-cmd --permanent --zone="$zone" --query-rich-rule="$webui_rule" >/dev/null 2>&1; then
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
  doctor_check_ollama_memory
  doctor_check_ollama_exposure
  echo ""

  doctor_check_service openwebui
  doctor_check_http "Open WebUI health" "http://127.0.0.1:${webui_port}/health"
  echo ""

  doctor_check_openwebui_extras

  doctor_check_firewall
  echo ""

  if [ "$DOCTOR_FAILURES" -eq 0 ]; then
    ok "Doctor completed: server is ready."
  else
    fail "Doctor completed with ${DOCTOR_FAILURES} failure(s)."
    pause
    return 1
  fi

  pause
}
