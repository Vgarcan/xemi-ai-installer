# systemd overview and control for every service the installer creates or relies on.

# Prints "unit|label|health URL" for each managed or supporting unit present on this host.
managed_services_table() {
  local ollama_port="${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}"
  local webui_port="${OPENWEBUI_PORT:-$WEBUI_PORT_DEFAULT}"
  local unit label url flag
  {
    echo "ollama|Ollama|http://127.0.0.1:${ollama_port}/api/tags"
    echo "xemi-ollama-gpu-guard|Ollama GPU guard|"
    echo "openwebui|Open WebUI|http://127.0.0.1:${webui_port}/health"
    while IFS='|' read -r unit label url flag; do
      echo "${unit}|${label}|${url}"
    done < <(openwebui_extras_table)
    echo "nvidia-persistenced|NVIDIA persistence|"
    echo "firewalld|Firewall|"
  } | while IFS='|' read -r unit label url; do
    if [ "$(systemctl show "$unit" -p LoadState --value 2>/dev/null)" = "loaded" ]; then
      echo "${unit}|${label}|${url}"
    fi
  done
}

service_health_url() {
  local unit label url
  while IFS='|' read -r unit label url; do
    if [ "$unit" = "$1" ]; then
      echo "$url"
      return 0
    fi
  done < <(managed_services_table)
}

# Prints the TCP addresses that UNIT's processes listen on, e.g. "127.0.0.1:9998 *:11434".
service_listen_ports() {
  local unit="$1"
  local cgroup procs
  cgroup="$(systemctl show "$unit" -p ControlGroup --value 2>/dev/null || true)"
  procs="/sys/fs/cgroup${cgroup}/cgroup.procs"
  if [ -z "$cgroup" ] || [ ! -r "$procs" ]; then
    return 0
  fi
  ss -ltnpH 2>/dev/null | normalize_listen_ports " $(tr '\n' ' ' < "$procs")"
}

# Reads `ss -ltnpH` lines and prints, space separated, the local addresses owned by PIDS
# (a space-padded list). 0.0.0.0/[::] become "*" and IPv4-mapped IPv6 becomes plain IPv4.
normalize_listen_ports() {
  awk -v pids="$1" '
    {
      addr = $4
      n = split($0, parts, "pid=")
      for (i = 2; i <= n; i++) {
        split(parts[i], fields, ",")
        if (index(pids, " " fields[1] " ")) {
          sub(/^(0\.0\.0\.0|\[::\]):/, "*:", addr)
          if (sub(/^\[::ffff:/, "", addr)) {
            sub(/\]:/, ":", addr)
          }
          print addr
        }
      }
    }' | sort -u | paste -sd' ' -
}

human_bytes() {
  # systemd reports "[not set]" or 2^64-1 when memory accounting is unavailable.
  if [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "${#1}" -lt 19 ]; then
    numfmt --to=iec --suffix=B "$1"
  else
    echo "-"
  fi
}

show_services_status() {
  header
  load_manifest
  local unit label url state boot pid mem restarts errors health since color key value ports
  local -A prop

  echo "Services managed or used by the installer:"
  echo ""
  printf "%-22s %-12s %-9s %-7s %-7s %-4s %-6s %-6s %-16s %s\n" \
    SERVICE STATE BOOT PID MEMORY RST ERR24H HEALTH SINCE LISTEN
  while IFS='|' read -r unit label url; do
    prop=()
    while IFS='=' read -r key value; do
      prop[$key]="$value"
    done < <(systemctl show "$unit" --no-pager \
      -p ActiveState -p SubState -p UnitFileState -p MainPID -p MemoryCurrent \
      -p NRestarts -p Type -p Result -p ActiveEnterTimestamp 2>/dev/null)

    state="${prop[SubState]:-?}"
    # A oneshot unit that finished successfully is "inactive (dead)" by design.
    if [ "${prop[Type]:-}" = "oneshot" ] && [ "${prop[ActiveState]:-}" = "inactive" ]; then
      [ "${prop[Result]:-}" = "success" ] && state="done" || state="${prop[Result]:-?}"
    fi
    boot="${prop[UnitFileState]:-?}"
    pid="${prop[MainPID]:-0}"
    [ "$pid" = "0" ] && pid="-"
    mem="$(human_bytes "${prop[MemoryCurrent]:-}")"
    restarts="${prop[NRestarts]:-0}"
    errors="$({ journalctl -u "$unit" -p err --since "24 hours ago" -q --no-pager 2>/dev/null || true; } | wc -l)"
    if [ -z "$url" ]; then
      health="-"
    elif curl -fsS --max-time 5 "$url" >/dev/null 2>&1; then
      health="ok"
    else
      health="FAIL"
    fi
    since="-"
    if [ -n "${prop[ActiveEnterTimestamp]:-}" ]; then
      since="$(date -d "${prop[ActiveEnterTimestamp]}" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "-")"
    fi

    ports="$(service_listen_ports "$unit")"

    color=""
    if [ "${prop[ActiveState]:-}" = "failed" ] || [ "$health" = "FAIL" ] || [ "$state" = "failed" ]; then
      color="$RED"
    elif { [ "${prop[ActiveState]:-}" != "active" ] && [ "$state" != "done" ]; } || [ "$restarts" != "0" ] || [ "$errors" != "0" ]; then
      color="$YELLOW"
    fi
    printf "${color}%-22s %-12s %-9s %-7s %-7s %-4s %-6s %-6s %-16s %s${color:+$NC}\n" \
      "$unit" "$state" "$boot" "$pid" "$mem" "$restarts" "$errors" "$health" "$since" "${ports:--}"
  done < <(managed_services_table)

  echo ""
  echo "BOOT enabled = starts with the server. RST = automatic restarts since start (crash loops)."
  echo "ERR24H = error-level log lines in the last 24 hours. Details: Services > Manage a service."
  echo "LISTEN = TCP addresses the service listens on; 127.0.0.1 is local only, * is every interface."
  pause
}

# Lets the operator pick one unit, then opens its control submenu.
manage_service() {
  header
  load_manifest
  local -a rows=()
  local row unit label url i opt ports
  mapfile -t rows < <(managed_services_table)
  menu_section "Choose a service"
  for i in "${!rows[@]}"; do
    IFS='|' read -r unit label url <<< "${rows[$i]}"
    menu_item "$((i + 1))" "$(printf '%-22s %-20s %s' "$unit" "$label" "$(service_listen_ports "$unit")")"
  done
  echo ""
  menu_item 0 "Back"
  echo ""
  opt="$(ask "Select service" "0")"
  case "$opt" in
    0|'') return 0 ;;
    *[!0-9]*) warn "Invalid option."; pause; return 0 ;;
  esac
  opt=$((10#$opt))
  if [ "$opt" -lt 1 ] || [ "$opt" -gt "${#rows[@]}" ]; then
    warn "Invalid option."
    pause
    return 0
  fi
  IFS='|' read -r unit label url <<< "${rows[$((opt - 1))]}"
  ports="$(service_listen_ports "$unit")"

  run_submenu "Service: ${label} (${unit}), listening on ${ports:-no TCP port}" \
    "Status and recent log lines|service_status ${unit}" \
    "Start|service_control start ${unit}" \
    "Stop|service_control stop ${unit}" \
    "Restart|service_control restart ${unit}" \
    "Start with the server (enable)|service_control enable ${unit}" \
    "Do not start with the server (disable)|service_control disable ${unit}" \
    "Browse log (last 500 lines, q to exit)|service_logs ${unit}" \
    "Follow log live (Ctrl+C to return)|service_follow_logs ${unit}" \
    "Errors since last boot|service_errors ${unit}" \
    "Unit file and overrides|service_unit_files ${unit}" \
    "Security exposure analysis|service_security ${unit}"
}

service_stop_warning() {
  case "$1" in
    ollama) echo "Open WebUI will lose access to all models while Ollama is stopped." ;;
    openwebui) echo "Users will lose access to the web interface." ;;
    firewalld) echo "DANGER: stopping the firewall removes the LAN-only protection of every port." ;;
    nvidia-persistenced) echo "Ollama may start slower or fall back to CPU without NVIDIA persistence." ;;
    *) echo "Open WebUI features that use ${1} will stop working." ;;
  esac
}

service_control() {
  local action="$1"
  local unit="$2"
  local url ans
  header
  case "$action" in
    stop|disable)
      service_stop_warning "$unit"
      ans="$(confirm_proceed "$(printf '%s %s yes or no' "${action^}" "$unit")" "no")"
      if ! is_yes "$ans"; then
        warn "Cancelled."
        pause
        return 0
      fi
      ;;
  esac

  if systemctl "$action" "$unit"; then
    ok "systemctl ${action} ${unit}: done."
  else
    fail "systemctl ${action} ${unit} failed. Check: journalctl -u ${unit} -e"
  fi

  url="$(service_health_url "$unit")"
  if [ -n "$url" ] && { [ "$action" = "start" ] || [ "$action" = "restart" ]; }; then
    echo "Waiting for ${unit} to respond..."
    if wait_http_ok "$url" 90; then
      ok "${unit} responds: ${url}"
    else
      fail "${unit} does not respond: ${url}"
    fi
  fi
  echo "Now: $(systemctl is-active "$unit" 2>/dev/null || true), boot: $(systemctl is-enabled "$unit" 2>/dev/null || true)"
  pause
}

service_status() {
  header
  systemctl status "$1" --no-pager -l -n 20 || true
  pause
}

service_logs() {
  header
  journalctl -u "$1" -n 500 -e -o short-iso || true
  pause
}

service_follow_logs() {
  header
  echo "Following the ${1} log. Press Ctrl+C to return to the menu."
  echo ""
  # Ctrl+C must stop only journalctl, not the installer.
  trap ':' INT
  journalctl -u "$1" -f -n 30 -o short-iso --no-pager || true
  trap - INT
  echo ""
  pause
}

service_errors() {
  header
  local lines
  lines="$(journalctl -u "$1" -b -p err -o short-iso --no-pager -q 2>/dev/null || true)"
  if [ -n "$lines" ]; then
    printf '%s\n' "$lines" | tail -n 200
  else
    ok "No error-level log lines for ${1} since the last boot."
  fi
  pause
}

service_unit_files() {
  header
  systemctl cat "$1" --no-pager || true
  pause
}

service_security() {
  header
  echo "Exposure score: lower is better. 'UNSAFE' does not always mean a problem; it lists"
  echo "sandboxing options the service does not use."
  echo ""
  systemd-analyze security "$1" --no-pager || true
  pause
}

restart_ai_services() {
  header
  load_manifest
  local unit label url ans
  local -a rows=()
  mapfile -t rows < <(managed_services_table)
  echo "This restarts Ollama, Open WebUI and the installed Open WebUI tools, in that order."
  echo "Chats in progress are interrupted."
  ans="$(confirm_proceed "Restart AI services yes or no" "no")"
  if ! is_yes "$ans"; then
    warn "Cancelled."
    pause
    return 0
  fi
  local row
  for row in "${rows[@]}"; do
    IFS='|' read -r unit label url <<< "$row"
    case "$unit" in
      firewalld|nvidia-persistenced|xemi-ollama-gpu-guard) continue ;;
    esac
    if ! systemctl restart "$unit"; then
      fail "${label}: restart failed. Check: journalctl -u ${unit} -e"
      continue
    fi
    if [ -n "$url" ] && ! wait_http_ok "$url" 90; then
      fail "${label}: restarted but does not respond at ${url}"
    else
      ok "${label}: restarted."
    fi
  done
  pause
}

# Maps a PID to the systemd service that owns it, e.g. "ollama".
pid_service_name() {
  local cg
  cg="$(awk -F: '$1 == "0" {print $3}' "/proc/$1/cgroup" 2>/dev/null || true)"
  cg="${cg##*/}"
  if [[ "$cg" = *.service ]]; then
    echo "${cg%.service}"
  else
    echo "-"
  fi
}

show_gpu_usage() {
  header
  load_manifest
  local index name util used total temp power pid process vram
  if ! cmd_exists nvidia-smi; then
    warn "nvidia-smi not found; GPU usage is not available."
    pause
    return 0
  fi

  echo "GPU:"
  printf "  %-3s %-28s %-6s %-19s %-6s %s\n" ID NAME UTIL MEMORY TEMP POWER
  while IFS=',' read -r index name util used total temp power; do
    printf "  %-3s %-28s %-6s %-19s %-6s %s\n" "$index" "${name# }" "${util# }%" "${used# } / ${total# } MiB" "${temp# }C" "${power# }W"
  done < <(nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw \
    --format=csv,noheader,nounits 2>/dev/null || true)
  echo ""

  echo "GPU memory by service:"
  printf "  %-20s %-8s %-28s %s\n" SERVICE PID PROCESS VRAM
  while IFS=',' read -r pid process vram; do
    [ -n "$pid" ] || continue
    printf "  %-20s %-8s %-28s %s\n" "$(pid_service_name "${pid// /}")" "${pid// /}" "$(basename "${process# }")" "${vram# } MiB"
  done < <(nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader,nounits 2>/dev/null || true)
  echo ""

  echo "Models loaded in Ollama:"
  local ps_json
  ps_json="$(curl -fsS --max-time 5 "http://127.0.0.1:${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}/api/ps" 2>/dev/null || true)"
  if [ -z "$ps_json" ]; then
    warn "  Ollama API is not responding."
  elif ! cmd_exists jq; then
    echo "  $ps_json"
  elif [ "$(jq '.models | length' <<< "$ps_json")" = "0" ]; then
    echo "  none (models load on first use and unload after OLLAMA_KEEP_ALIVE)"
  else
    printf "  %-40s %-10s %-10s %-8s %s\n" MODEL VRAM TOTAL ON_GPU "UNLOADS"
    jq -r '.models[] | [.name, .size_vram, .size, .expires_at] | @tsv' <<< "$ps_json" \
      | while IFS=$'\t' read -r name vram total until; do
        printf "  %-40s %-10s %-10s %-8s %s\n" "$name" "$(human_bytes "$vram")" "$(human_bytes "$total")" \
          "$(( total > 0 ? vram * 100 / total : 0 ))%" "$(date -d "$until" '+%H:%M' 2>/dev/null || echo "-")"
      done
  fi
  echo ""
  echo "ON_GPU below 100% means part of the model runs on CPU (slower). A smaller model or"
  echo "quantization keeps it fully on the GPU."
  pause
}

show_boot_timeline() {
  header
  local unit label url
  local -a units=()
  while IFS='|' read -r unit label url; do
    units+=("$unit")
  done < <(managed_services_table)

  echo "Last boot:"
  systemd-analyze --no-pager 2>/dev/null | sed 's/^/  /' || true
  echo ""
  echo "Start time of each service (slowest first):"
  systemd-analyze blame --no-pager 2>/dev/null \
    | grep -E "[[:space:]]($(IFS='|'; echo "${units[*]}"))\.service$" | sed 's/^/  /' || true
  echo ""
  echo "What Ollama and Open WebUI waited for (@ = started at, + = took):"
  for unit in ollama openwebui; do
    if [[ " ${units[*]} " = *" ${unit} "* ]]; then
      systemd-analyze critical-chain "${unit}.service" --no-pager 2>/dev/null | tail -n +3 | sed 's/^/  /' || true
    fi
  done
  echo ""
  echo "The Ollama unit waits for the NVIDIA GPU before starting; a long wait there points to the driver."
  pause
}

# Removes secrets and personal data from diagnostic text.
redact_diagnostics() {
  sed -E \
    -e 's/\x1b\[[0-9;]*m//g' \
    -e 's/([A-Za-z0-9_]*(PASSWORD|PASS|SECRET|TOKEN|API_KEY|KEY)[A-Za-z0-9_]*[[:space:]]*[=:][[:space:]]*)[^[:space:]]+/\1<redacted>/g' \
    -e 's/(--api-key[= ])[^[:space:]]+/\1<redacted>/g' \
    -e 's/(secret_key:[[:space:]]*).*/\1<redacted>/' \
    -e 's/(Bearer )[A-Za-z0-9._~+\/=-]+/\1<redacted>/g' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g'
}

export_diagnostic_bundle() {
  header
  load_manifest
  local stamp host work out unit label url
  stamp="$(date '+%Y%m%d-%H%M%S')"
  host="$(hostname -s 2>/dev/null || echo host)"
  mkdir -p "$DIAG_DIR"
  chmod 700 "$DIAG_DIR"
  work="$(mktemp -d "${DIAG_DIR}/bundle.XXXXXX")"
  out="${DIAG_DIR}/xemi-diag-${host}-${stamp}.tar.gz"
  echo "Collecting diagnostics (this can take a minute)..."

  {
    date '+%F %T %Z'
    hostname -f 2>/dev/null || hostname
    cat /etc/os-release 2>/dev/null
    uname -a
    uptime
    free -h
    df -h -x tmpfs -x devtmpfs
    nvidia-smi 2>&1 || true
  } 2>&1 | redact_diagnostics > "${work}/system.txt"
  {
    echo "ollama: $(ollama --version 2>&1 | tail -n 1)"
    echo "open-webui: $(openwebui_package_version 2>/dev/null || true)"
    echo "python3.11: $("$PY311_BIN" --version 2>&1 || echo "-")"
    [ -x "$OPEN_TERMINAL_VENV/bin/pip" ] && echo "open-terminal: $("$OPEN_TERMINAL_VENV/bin/pip" show open-terminal 2>/dev/null | awk '/^Version:/ {print $2}')"
    [ -x "$MCPO_VENV/bin/pip" ] && echo "mcpo: $("$MCPO_VENV/bin/pip" show mcpo 2>/dev/null | awk '/^Version:/ {print $2}')"
    [ -n "${SEARXNG_COMMIT:-}" ] && echo "searxng commit: ${SEARXNG_COMMIT}"
    [ -n "${TIKA_INSTALLED_VERSION:-}" ] && echo "tika: ${TIKA_INSTALLED_VERSION}"
    true
  } 2>&1 | redact_diagnostics > "${work}/versions.txt"
  (ASSUME_YES=1; show_services_status) 2>&1 | redact_diagnostics > "${work}/services.txt" || true
  (ASSUME_YES=1; doctor) 2>&1 | redact_diagnostics > "${work}/doctor.txt" || true
  (ASSUME_YES=1; show_install_state) 2>&1 | redact_diagnostics > "${work}/install-report.txt" || true
  ss -ltnp 2>&1 | redact_diagnostics > "${work}/listening-ports.txt" || true
  firewall-cmd --list-all 2>&1 | redact_diagnostics > "${work}/firewall.txt" || true

  mkdir -p "${work}/units" "${work}/logs"
  while IFS='|' read -r unit label url; do
    { systemctl cat "$unit" --no-pager; echo; systemctl status "$unit" --no-pager -n 0; } 2>&1 \
      | redact_diagnostics > "${work}/units/${unit}.txt" || true
    journalctl -u "$unit" -b -n 1000 -o short-iso --no-pager 2>&1 \
      | redact_diagnostics > "${work}/logs/${unit}.log" || true
  done < <(managed_services_table)
  tail -n 2000 "$LOG_FILE" 2>/dev/null | redact_diagnostics > "${work}/installer.log" || true

  tar -czf "$out" -C "$work" .
  chmod 600 "$out"
  safe_rm_rf "$work" "$DIAG_DIR"
  ok "Diagnostic bundle created: ${out} ($(du -h "$out" | cut -f1))"
  echo "API keys, tokens, passwords and e-mail addresses are redacted. Review it before sharing:"
  echo "  tar -tzf ${out}"
  pause
}
