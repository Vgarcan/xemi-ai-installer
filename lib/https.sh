# HTTPS front end for Open WebUI: Caddy as a reverse proxy with its own local certificate
# authority. Browsers only allow the microphone (dictation, voice mode) on HTTPS pages, and
# HTTPS keeps chats and passwords encrypted on the LAN.
#
# Caddy runs from /opt as an unprivileged user that only gets CAP_NET_BIND_SERVICE. Users
# install the root certificate once (downloadable at /xemi-ca.crt) to remove browser warnings.

https_root_ca() {
  echo "${HTTPS_DATA_DIR}/caddy/pki/authorities/local/root.crt"
}

# Names and IPv4 addresses users are likely to type: short hostname, FQDN and global IPv4s.
https_default_hosts() {
  local short fqdn
  local -a hosts=()
  short="$(hostname -s 2>/dev/null || hostname)"
  fqdn="$(hostname -f 2>/dev/null || true)"
  [ -n "$short" ] && hosts+=("$short")
  if [ -n "$fqdn" ] && [ "$fqdn" != "$short" ] && [[ "$fqdn" = *.* ]]; then
    hosts+=("$fqdn")
  fi
  while read -r ip; do
    [ -n "$ip" ] && hosts+=("$ip")
  done < <(ip -4 -o addr show scope global 2>/dev/null | awk '{sub(/\/.*/, "", $4); print $4}')
  local IFS=,
  echo "${hosts[*]}"
}

validate_https_hosts() {
  local list="${1:-}"
  local host
  [ -n "$list" ] || return 1
  [[ "$list" != *[[:space:]]* ]] || return 1
  local -a hosts=()
  IFS=, read -r -a hosts <<< "$list"
  [ "${#hosts[@]}" -gt 0 ] || return 1
  for host in "${hosts[@]}"; do
    validate_bind_host "$host" || return 1
  done
}

write_https_caddyfile() {
  local port="$1"
  local hosts="$2"
  local host first_ip="" sites=""
  local -a list=()
  IFS=, read -r -a list <<< "$hosts"
  for host in "${list[@]}"; do
    sites+="${sites:+, }https://${host}:${port}"
    if [ -z "$first_ip" ] && validate_ipv4 "$host"; then
      first_ip="$host"
    fi
  done
  # Local health checks use 127.0.0.1: without its own site Caddy answers them with an empty
  # 200 instead of proxying to Open WebUI.
  if [[ ",${hosts}," != *",127.0.0.1,"* ]]; then
    sites+=", https://127.0.0.1:${port}"
  fi
  mkdir -p "$HTTPS_CONFIG_DIR" || return 1
  {
    echo "# Written by xemi_ai_install.sh: HTTPS front end for Open WebUI."
    echo "{"
    echo "	skip_install_trust"
    echo "	admin off"
    echo "	auto_https disable_redirects"
    echo "	https_port ${port}"
    # Browsers send no server name when the address is an IP; this picks its certificate.
    if [ -n "$first_ip" ]; then
      echo "	default_sni ${first_ip}"
    fi
    echo "}"
    echo ""
    echo "${sites} {"
    echo "	tls internal"
    echo "	handle /xemi-ca.crt {"
    echo "		root * $(dirname "$(https_root_ca)")"
    echo "		rewrite * /root.crt"
    echo "		header Content-Type application/x-x509-ca-cert"
    echo "		header Content-Disposition \"attachment; filename=xemi-ca.crt\""
    echo "		file_server"
    echo "	}"
    echo "	handle {"
    echo "		reverse_proxy 127.0.0.1:${OPENWEBUI_PORT:-$WEBUI_PORT_DEFAULT}"
    echo "	}"
    echo "}"
  } > "${HTTPS_CONFIG_DIR}/Caddyfile"
}

https_download_caddy() {
  local tmp
  mkdir -p "$HTTPS_BIN_DIR" || return 1
  tmp="$(mktemp "${HTTPS_BIN_DIR}/download.XXXXXX")" || return 1
  if ! curl -fsSL --retry 3 -o "$tmp" \
    "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz"; then
    rm -f "$tmp"
    fail "Could not download Caddy ${CADDY_VERSION}."
    return 1
  fi
  if ! echo "${CADDY_SHA512}  ${tmp}" | sha512sum -c --status -; then
    rm -f "$tmp"
    fail "Caddy download failed SHA512 verification."
    return 1
  fi
  tar -xzf "$tmp" -C "$HTTPS_BIN_DIR" caddy || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
  chmod 755 "${HTTPS_BIN_DIR}/caddy"
}

# Parses the Caddyfile without provisioning: "caddy validate" would create a certificate
# authority in root's home directory that nothing removes.
https_check_caddyfile() {
  "${HTTPS_BIN_DIR}/caddy" adapt --config "${HTTPS_CONFIG_DIR}/Caddyfile" --adapter caddyfile >/dev/null 2>&1 \
    || { fail "Generated Caddy configuration is not valid."; return 1; }
}

# Rewrites the Caddyfile from the manifest (tools-update), so existing installs get fixes.
refresh_https() {
  [ "${HTTPS_INSTALLED:-}" = "1" ] || return 0
  local port="${HTTPS_PORT:-$HTTPS_PORT_DEFAULT}"
  validate_https_hosts "${HTTPS_HOSTS:-}" || { fail "HTTPS host names missing from the manifest."; return 1; }
  write_https_caddyfile "$port" "$HTTPS_HOSTS" || return 1
  https_check_caddyfile || return 1
  grant_group_read "$HTTPS_USER" "$HTTPS_CONFIG_DIR" || return 1
  systemctl restart "$HTTPS_SERVICE" || return 1
  https_wait_ready "$port"
}

https_wait_ready() {
  local port="$1"
  local i
  for ((i = 1; i <= 30; i++)); do
    # Local health check only: the certificate is checked by browsers, not here.
    if curl -fsk --max-time 5 "https://127.0.0.1:${port}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

install_https() {
  header
  echo "HTTPS access for Open WebUI (Caddy ${CADDY_VERSION}, local certificate authority)."
  echo ""
  echo "  - Encrypts chats and passwords on the LAN."
  echo "  - Needed for the microphone: browsers only allow dictation and voice mode on HTTPS."
  echo "  - Users install the server's root certificate once to avoid browser warnings."
  echo ""
  confirm_extra_install "Enable HTTPS access" || { pause; return 0; }

  load_manifest
  if [ "${HTTPS_INSTALLED:-}" = "1" ]; then
    warn "HTTPS access is already enabled. Remove it first to change names or port."
    pause
    return 1
  fi
  if [ -e "/etc/systemd/system/${HTTPS_SERVICE}.service" ] || [ -e "$HTTPS_BIN_DIR" ]; then
    fail "An existing ${HTTPS_SERVICE} setup is not managed by this installer; leaving it untouched."
    pause
    return 1
  fi
  if ! curl -fsS --max-time 5 "http://127.0.0.1:${OPENWEBUI_PORT:-$WEBUI_PORT_DEFAULT}/health" >/dev/null 2>&1; then
    fail "Open WebUI does not respond on port ${OPENWEBUI_PORT:-$WEBUI_PORT_DEFAULT}; install or start it first."
    pause
    return 1
  fi
  cmd_exists firewall-cmd || { fail "firewall-cmd is not installed. Run the base tools stage first."; pause; return 1; }

  local hosts port
  while true; do
    hosts="$(ask "Names and IPs users type in the browser (comma separated)" "$(https_default_hosts)")"
    validate_https_hosts "$hosts" && break
    warn "Use host names or IPv4 addresses separated by commas, without spaces." >&2
    [ "$ASSUME_YES" = "1" ] && { pause; return 1; }
  done
  port="$(ask_free_port "HTTPS port" "${HTTPS_PORT:-$HTTPS_PORT_DEFAULT}")" || { fail "No free port for HTTPS."; pause; return 1; }

  # The steps check every command explicitly: errexit is suspended inside an if condition.
  if ! https_install_steps "$port" "$hosts"; then
    fail "HTTPS setup failed; removing the partial installation."
    load_manifest
    remove_https
    pause
    return 1
  fi
  pause
}

https_install_steps() {
  local port="$1"
  local hosts="$2"
  local zone rule subnet
  ensure_extras_identity "$HTTPS_USER" "$HTTPS_DATA_DIR" /sbin/nologin HTTPS_USER_CREATED || return 1
  record_manifest "HTTPS_INSTALLED" "1" || return 1
  HTTPS_INSTALLED=1

  https_download_caddy || return 1
  # The directory is created 750 root:root (umask 027): the service user needs to enter it.
  grant_group_read "$HTTPS_USER" "$HTTPS_BIN_DIR" || return 1
  write_https_caddyfile "$port" "$hosts" || return 1
  https_check_caddyfile || return 1
  grant_group_read "$HTTPS_USER" "$HTTPS_CONFIG_DIR" || return 1

  write_extra_service "$HTTPS_SERVICE" "HTTPS front end for Open WebUI (Caddy)" "$HTTPS_USER" \
    "$HTTPS_DATA_DIR" "$HTTPS_DATA_DIR" \
    "${HTTPS_BIN_DIR}/caddy run --config ${HTTPS_CONFIG_DIR}/Caddyfile --adapter caddyfile" \
    "Environment=XDG_DATA_HOME=${HTTPS_DATA_DIR}" \
    "Environment=XDG_CONFIG_HOME=${HTTPS_DATA_DIR}" || return 1
  record_manifest "HTTPS_PORT" "$port" || return 1
  record_manifest "HTTPS_HOSTS" "$hosts" || return 1
  HTTPS_PORT="$port"
  HTTPS_HOSTS="$hosts"

  systemctl daemon-reload || return 1
  systemctl enable "$HTTPS_SERVICE" >/dev/null 2>&1 || return 1
  systemctl restart "$HTTPS_SERVICE" || { fail "${HTTPS_SERVICE} failed to start. Check: journalctl -u ${HTTPS_SERVICE} -e"; return 1; }
  https_wait_ready "$port" || { fail "HTTPS front end does not respond. Check: journalctl -u ${HTTPS_SERVICE} -e"; return 1; }

  # LAN-only access to the HTTPS port, like the Open WebUI rule.
  subnet="${LAN_SUBNET:-$LAN_SUBNET_DEFAULT}"
  zone="$(detect_firewall_zone)" || return 1
  rule="rule family='ipv4' source address='${subnet}' port protocol='tcp' port='${port}' accept"
  if ! firewall-cmd --permanent --zone="$zone" --query-rich-rule="$rule" >/dev/null 2>&1; then
    firewall-cmd --permanent --zone="$zone" --add-rich-rule="$rule" >/dev/null || return 1
    record_manifest "HTTPS_FIREWALL_RULE" "$rule" || return 1
    record_manifest "HTTPS_FIREWALL_ZONE" "$zone" || return 1
  fi
  firewall-cmd --reload >/dev/null || return 1

  ok "HTTPS access ready."
  echo ""
  show_https_info_body
}

# Address list, root certificate and how to trust it; used after install and from the menu.
show_https_info_body() {
  local host fingerprint
  local -a list=()
  IFS=, read -r -a list <<< "${HTTPS_HOSTS:-}"
  echo "Open WebUI over HTTPS:"
  for host in "${list[@]}"; do
    if [ "${HTTPS_PORT:-443}" = "443" ]; then
      echo "  https://${host}"
    else
      echo "  https://${host}:${HTTPS_PORT}"
    fi
  done
  echo ""
  if [ -f "$(https_root_ca)" ]; then
    fingerprint="$(openssl x509 -in "$(https_root_ca)" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)"
    echo "Root certificate (install it once on each device to remove the browser warning):"
    echo "  Download: https://${list[0]}$([ "${HTTPS_PORT:-443}" = "443" ] || echo ":${HTTPS_PORT}")/xemi-ca.crt"
    echo "  On the server: $(https_root_ca)"
    echo "  SHA-256 fingerprint (check it matches before trusting): ${fingerprint:-unknown}"
    echo ""
    echo "  Windows: open the file > Install certificate > Local machine > Trusted Root Certification Authorities."
    echo "  macOS:   open it in Keychain Access > System > set Always Trust."
    echo "  Linux:   copy to /etc/pki/ca-trust/source/anchors/ and run update-ca-trust (Fedora/EL),"
    echo "           or /usr/local/share/ca-certificates/ and update-ca-certificates (Debian/Ubuntu)."
    echo "  Android: Settings > Security > Encryption > Install a certificate > CA certificate."
    echo "  iOS:     open it, install the profile, then enable it in Settings > General > About > Certificate Trust."
    echo "  Firefox uses its own store: Settings > Certificates > Import, trust for websites."
  else
    warn "The root certificate is not there yet: ${HTTPS_SERVICE} creates it on its first start."
  fi
  echo ""
  echo "Plain http://...:${OPENWEBUI_PORT:-$WEBUI_PORT_DEFAULT} keeps working; tell users to use the HTTPS address."
}

show_https_info() {
  header
  load_manifest
  if [ "${HTTPS_INSTALLED:-}" != "1" ]; then
    warn "HTTPS access is not enabled."
    pause
    return 0
  fi
  echo "Service: $(systemctl is-active "$HTTPS_SERVICE" 2>/dev/null || true)"
  echo ""
  show_https_info_body
  pause
}

remove_https() {
  [ "${HTTPS_INSTALLED:-}" = "1" ] || return 0
  remove_extra_service "$HTTPS_SERVICE"
  if [ -n "${HTTPS_FIREWALL_RULE:-}" ] && cmd_exists firewall-cmd; then
    remove_firewall_rule "$HTTPS_FIREWALL_RULE" "${HTTPS_FIREWALL_ZONE:-$(firewall-cmd --get-default-zone 2>/dev/null)}"
    firewall-cmd --reload >/dev/null 2>&1 || true
  fi
  if [ -d "$HTTPS_BIN_DIR" ]; then
    safe_rm_rf "$HTTPS_BIN_DIR" /opt
  fi
  if [ -d "$HTTPS_CONFIG_DIR" ]; then
    safe_rm_rf "$HTTPS_CONFIG_DIR" /etc
  fi
  # The data directory holds the CA private key; it goes with the service user (or alone).
  if [ "${HTTPS_USER_CREATED:-}" = "1" ]; then
    remove_extras_identity "$HTTPS_USER" "$HTTPS_DATA_DIR" HTTPS_USER_CREATED /var/lib
  elif [ -d "$HTTPS_DATA_DIR" ]; then
    safe_rm_rf "$HTTPS_DATA_DIR" /var/lib
  fi
  local key
  for key in HTTPS_INSTALLED HTTPS_PORT HTTPS_HOSTS HTTPS_FIREWALL_RULE HTTPS_FIREWALL_ZONE; do
    remove_manifest_key "$key"
  done
  HTTPS_INSTALLED=""
  ok "HTTPS access removed (service, certificates, firewall rule and service user)."
  echo "Devices that trusted the old root certificate can delete it; a new install creates a new one."
}

remove_https_interactive() {
  header
  load_manifest
  if [ "${HTTPS_INSTALLED:-}" != "1" ]; then
    warn "HTTPS access is not enabled."
    pause
    return 0
  fi
  local ans
  ans="$(confirm_proceed "Remove HTTPS access (users go back to http://...:${OPENWEBUI_PORT:-$WEBUI_PORT_DEFAULT}) yes or no" "no")"
  if is_yes "$ans"; then
    remove_https
  else
    warn "Cancelled."
  fi
  pause
}

doctor_check_https() {
  [ "${HTTPS_INSTALLED:-}" = "1" ] || return 0
  doctor_check_service "$HTTPS_SERVICE"
  if curl -fsk --max-time 5 "https://127.0.0.1:${HTTPS_PORT:-$HTTPS_PORT_DEFAULT}/health" >/dev/null 2>&1; then
    doctor_ok "Open WebUI responds over HTTPS on port ${HTTPS_PORT:-$HTTPS_PORT_DEFAULT}"
  else
    doctor_fail "Open WebUI does not respond over HTTPS on port ${HTTPS_PORT:-$HTTPS_PORT_DEFAULT}"
  fi
  if [ -n "${HTTPS_FIREWALL_RULE:-}" ]; then
    if firewall-cmd --permanent --zone="${HTTPS_FIREWALL_ZONE:-public}" --query-rich-rule="$HTTPS_FIREWALL_RULE" >/dev/null 2>&1; then
      doctor_ok "Firewall rule exists for HTTPS"
    else
      doctor_fail "Firewall rule missing for HTTPS"
    fi
  fi
}
