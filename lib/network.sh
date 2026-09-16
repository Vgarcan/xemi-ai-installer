# LAN firewall and service binding operations.

detect_firewall_zone() {
  local zones=()
  if [ -n "${FIREWALL_ZONE:-}" ]; then
    printf '%s\n' "$FIREWALL_ZONE"
    return 0
  fi
  mapfile -t zones < <(firewall-cmd --get-active-zones | awk '/^[^[:space:]]/ {print $1}')
  if [ "${#zones[@]}" -eq 1 ]; then
    printf '%s\n' "${zones[0]}"
  elif [ "${#zones[@]}" -eq 0 ]; then
    firewall-cmd --get-default-zone
  else
    fail "Several firewalld zones are active. Select one with --firewall-zone."
    return 1
  fi
}

remove_firewall_rule() {
  local rule="$1"
  local zone="${2:-$FIREWALL_ZONE}"
  [ -n "$rule" ] && [ "$rule" != "none" ] || return 0
  firewall-cmd --permanent --zone="$zone" --remove-rich-rule="$rule" >/dev/null 2>&1 || true
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
  local zone
  local managed_ollama_rule="none"
  local managed_webui_rule="none"

  ollama_rule="none"
  if [ "${OLLAMA_BIND_HOST:-127.0.0.1}" != "127.0.0.1" ] && [ "${OLLAMA_BIND_HOST:-127.0.0.1}" != "localhost" ]; then
    ollama_rule="rule family='ipv4' source address='${subnet}' port protocol='tcp' port='${oport}' accept"
  fi
  webui_rule="rule family='ipv4' source address='${subnet}' port protocol='tcp' port='${wport}' accept"

  if ! cmd_exists firewall-cmd; then
    fail "firewall-cmd is not installed. Run the base tools stage first."
    pause
    return 1
  fi

  systemctl enable --now firewalld >/dev/null 2>&1
  zone="$(detect_firewall_zone)" || return 1
  validate_firewall_zone "$zone" || { fail "Invalid detected firewalld zone: $zone"; return 1; }
  FIREWALL_ZONE="$zone"

  if [ "$ollama_rule" != "none" ]; then
    if ! firewall-cmd --permanent --zone="$zone" --query-rich-rule="$ollama_rule" >/dev/null 2>&1; then
      firewall-cmd --permanent --zone="$zone" --add-rich-rule="$ollama_rule"
      managed_ollama_rule="$ollama_rule"
    elif [ "${FIREWALL_RULE_OLLAMA:-}" = "$ollama_rule" ] && [ "${RECORDED_FIREWALL_ZONE:-$zone}" = "$zone" ]; then
      managed_ollama_rule="$ollama_rule"
    fi
  fi
  if ! firewall-cmd --permanent --zone="$zone" --query-rich-rule="$webui_rule" >/dev/null 2>&1; then
    firewall-cmd --permanent --zone="$zone" --add-rich-rule="$webui_rule"
    managed_webui_rule="$webui_rule"
  elif [ "${FIREWALL_RULE_WEBUI:-}" = "$webui_rule" ] && [ "${RECORDED_FIREWALL_ZONE:-$zone}" = "$zone" ]; then
    managed_webui_rule="$webui_rule"
  fi

  if [ "${FIREWALL_RULE_OLLAMA:-}" != "$ollama_rule" ] || { [ -n "${RECORDED_FIREWALL_ZONE:-}" ] && [ "$RECORDED_FIREWALL_ZONE" != "$zone" ]; }; then
    remove_firewall_rule "${FIREWALL_RULE_OLLAMA:-}" "${RECORDED_FIREWALL_ZONE:-$zone}"
  fi
  if [ "${FIREWALL_RULE_WEBUI:-}" != "$webui_rule" ] || { [ -n "${RECORDED_FIREWALL_ZONE:-}" ] && [ "$RECORDED_FIREWALL_ZONE" != "$zone" ]; }; then
    remove_firewall_rule "${FIREWALL_RULE_WEBUI:-}" "${RECORDED_FIREWALL_ZONE:-$zone}"
  fi
  firewall-cmd --reload

  record_manifest "FIREWALL_CONFIGURED" "1"
  record_manifest "FIREWALL_ZONE" "$zone"
  record_manifest "FIREWALL_RULE_OLLAMA" "$managed_ollama_rule"
  record_manifest "FIREWALL_RULE_WEBUI" "$managed_webui_rule"
  record_manifest "LAN_SUBNET" "$subnet"

  ok "Firewall checked for LAN access; only Xemi-added rules are tracked for removal."
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

remove_firewall_configuration() {
  if [ "${FIREWALL_CONFIGURED:-}" != "1" ]; then
    return 0
  fi

  if systemctl is-active firewalld >/dev/null 2>&1; then
    FIREWALL_ZONE="${FIREWALL_ZONE:-$(firewall-cmd --get-default-zone)}"
    remove_firewall_rule "${FIREWALL_RULE_OLLAMA:-}" "${RECORDED_FIREWALL_ZONE:-$FIREWALL_ZONE}"
    remove_firewall_rule "${FIREWALL_RULE_WEBUI:-}" "${RECORDED_FIREWALL_ZONE:-$FIREWALL_ZONE}"
    firewall-cmd --reload >/dev/null 2>&1 || true
    ok "Firewall rules removed."
  else
    warn "firewalld is not active; firewall rules were not removed."
  fi
}
