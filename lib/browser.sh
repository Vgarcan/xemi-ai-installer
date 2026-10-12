# Headless Chromium for Open WebUI's web loader. Open WebUI fetches web pages (search results,
# URLs in chats) with a plain HTTP request, which misses pages that build their content with
# JavaScript. With this tool it asks a Playwright server, running Chromium as its own user in
# the usual sandbox, to load the page like a browser.
#
# Open WebUI imports the Playwright client inside its own process, so the client goes into the
# Open WebUI venv. Client and server must be the same Playwright version: both follow the
# version Open WebUI declares, and they are re-synchronised after Open WebUI updates.

BROWSER_HOME="/var/lib/ai-browser"
PLAYWRIGHT_CLIENT_RECORD="openwebui-playwright-client"

# The version of PACKAGE pinned by the installed Open WebUI in its optional extras, e.g.
# playwright -> 1.60.0, unstructured -> 0.22.31. Prints nothing when it is not declared.
owui_pinned_version() {
  local package="$1"
  local venv="${2:-$OPENWEBUI_VENV}"
  "${venv}/bin/python" - "$package" <<'EOF' 2>/dev/null
import importlib.metadata as m, re, sys
for req in m.requires("open-webui") or []:
    found = re.match(re.escape(sys.argv[1]) + r"==([0-9][0-9.]*)", req.replace(" ", ""))
    if found:
        print(found.group(1))
        break
EOF
}

owui_playwright_version() {
  owui_pinned_version playwright "${1:-$OPENWEBUI_VENV}"
}

normalize_pip_names() {
  cut -d= -f1 | tr 'A-Z_.' 'a-z--' | sort -u
}

# Open WebUI's own exact pins (no extras), as a pip constraints file: new packages must fit
# around them. Without it, unstructured pulled a newer unstructured-client that upgraded pypdf
# past Open WebUI's pin.
owui_pins_constraints() {
  local venv="$1"
  "${venv}/bin/python" - <<'EOF' 2>/dev/null | sed -E 's/\[[^]]*\]//'
import importlib.metadata as m
for req in m.requires("open-webui") or []:
    spec = req.split(";")[0].strip()
    if "extra ==" not in req and "==" in spec:
        print(spec)
EOF
}

# Installs into an Open WebUI venv what its Playwright web loader imports: the Playwright client
# and "unstructured" (LangChain's Playwright loader parses pages with it), both at the versions
# Open WebUI declares. Every package pip adds is recorded, so removal can take them out again.
playwright_client_install() {
  local venv="$1"
  local version="$2"
  local record="${EXTRAS_PACKAGES_DIR}/${PLAYWRIGHT_CLIENT_RECORD}.list"
  local pins="${EXTRAS_PACKAGES_DIR}/openwebui-pins.txt"
  local before after unstructured_version rc=0
  local -a specs=("playwright==${version}")
  unstructured_version="$(owui_pinned_version unstructured "$venv")"
  if [ -n "$unstructured_version" ]; then
    specs+=("unstructured==${unstructured_version}")
  else
    specs+=("unstructured")
  fi
  mkdir -p "$EXTRAS_PACKAGES_DIR" || return 1
  before="$("${venv}/bin/pip" freeze 2>/dev/null | normalize_pip_names)" || return 1
  if ! owui_pins_constraints "$venv" > "$pins" || [ ! -s "$pins" ]; then
    rm -f "$pins"
    fail "Could not read Open WebUI's pinned requirements."
    return 1
  fi
  run_required "Installing the web loader client into Open WebUI (${specs[*]})..." \
    "${venv}/bin/pip" install --no-cache-dir -c "$pins" "${specs[@]}" || rc=1
  rm -f "$pins"
  # Recorded even after a failure, so removal can take back whatever pip managed to add.
  # Union with earlier records: an Open WebUI update rebuilds the venv and installs them again.
  after="$("${venv}/bin/pip" freeze 2>/dev/null | normalize_pip_names)" || return 1
  { cat "$record" 2>/dev/null || true; comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"); } \
    | grep -v '^$' | sort -u > "${record}.new" && mv -f "${record}.new" "$record" || return 1
  chown -R "$AI_USER:$AI_GROUP" "${venv}/"
  [ "$rc" = "0" ] || return 1
  "${venv}/bin/pip" check >/dev/null || { fail "Open WebUI dependencies broke after adding the web loader client."; return 1; }
}

# Removes the recorded packages that nothing outside the record needs any more (pip's
# Required-by), so a package that Open WebUI itself came to depend on is kept.
playwright_client_remove() {
  local record="${EXTRAS_PACKAGES_DIR}/${PLAYWRIGHT_CLIENT_RECORD}.list"
  local pip="${OPENWEBUI_VENV}/bin/pip"
  local package needed_by user keep
  local -a removable=() kept=()
  [ -f "$record" ] || return 0
  if [ -x "$pip" ]; then
    while IFS= read -r package; do
      [ -n "$package" ] || continue
      keep=0
      needed_by="$("$pip" show "$package" 2>/dev/null | sed -n 's/^Required-by: //p' | tr ',' '\n' | tr -d ' ' | normalize_pip_names)"
      for user in $needed_by; do
        grep -qx "$user" "$record" || keep=1
      done
      if [ "$keep" = "1" ]; then kept+=("$package"); else removable+=("$package"); fi
    done < "$record"
    if [ "${#removable[@]}" -gt 0 ]; then
      run_optional "Removing the web loader client from Open WebUI..." \
        "$pip" uninstall -y "${removable[@]}" || warn "Could not remove: ${removable[*]}"
    fi
    if [ "${#kept[@]}" -gt 0 ]; then
      warn "Kept in Open WebUI because other packages need them: ${kept[*]}"
    fi
    "$pip" check >/dev/null || warn "Open WebUI reports inconsistent dependencies; run: ${pip} check"
  fi
  rm -f "$record"
}

# Server venv and Chromium for VERSION (replaces older browser builds).
playwright_server_install() {
  local version="$1"
  if [ ! -x "${PLAYWRIGHT_DIR}/venv/bin/pip" ]; then
    create_extras_venv "${PLAYWRIGHT_DIR}/venv" "$BROWSER_USER" "playwright==${version}" || return 1
  else
    run_required "Installing Playwright ${version} server..." \
      "${PLAYWRIGHT_DIR}/venv/bin/pip" install --no-cache-dir "playwright==${version}" || return 1
  fi
  if [ -d "${PLAYWRIGHT_DIR}/browsers" ]; then
    safe_rm_rf "${PLAYWRIGHT_DIR}/browsers" /opt
  fi
  run_required "Downloading headless Chromium..." env PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_DIR}/browsers" \
    "${PLAYWRIGHT_DIR}/venv/bin/playwright" install --only-shell chromium || return 1
  grant_group_read "$BROWSER_USER" "$PLAYWRIGHT_DIR" || return 1
  local shell missing
  shell="$(find "${PLAYWRIGHT_DIR}/browsers" -type f -name chrome-headless-shell | head -n 1)"
  [ -n "$shell" ] || { fail "Chromium was not downloaded."; return 1; }
  missing="$(ldd "$shell" 2>/dev/null | awk '/not found/ {print $1}' | sort -u | tr '\n' ' ')"
  [ -z "$missing" ] || { fail "Chromium is missing system libraries: ${missing}"; return 1; }
}

write_playwright_service() {
  local port="$1"
  write_extra_service playwright "Headless Chromium (Playwright) for Open WebUI" "$BROWSER_USER" \
    "$BROWSER_HOME" "$BROWSER_HOME" \
    "${PLAYWRIGHT_DIR}/venv/bin/playwright run-server --host 127.0.0.1 --port ${port}" \
    "Environment=PLAYWRIGHT_BROWSERS_PATH=${PLAYWRIGHT_DIR}/browsers"
}

# Loads a JavaScript-built page through the server from Open WebUI's own Python, as Open WebUI would.
playwright_end_to_end_check() {
  local port="$1"
  local count
  # Same path as Open WebUI's loader: render with Chromium, then parse the HTML with unstructured.
  count="$(sudo -u "$AI_USER" "${OPENWEBUI_VENV}/bin/python" -I - "$port" <<'EOF' 2>/dev/null || true
import sys
from playwright.sync_api import sync_playwright
from unstructured.partition.html import partition_html
with sync_playwright() as p:
    browser = p.chromium.connect(f"ws://127.0.0.1:{sys.argv[1]}/")
    page = browser.new_page()
    page.goto("https://quotes.toscrape.com/js/", wait_until="networkidle", timeout=45000)
    text = "\n".join(str(el) for el in partition_html(text=page.content()))
    browser.close()
print(text.count("“"))
EOF
)"
  [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -gt 0 ]
}

install_browser() {
  header
  echo "Installing headless Chromium (Playwright) for Open WebUI's web pages..."
  echo "Pages that build their content with JavaScript become readable for web search and URLs."
  echo "Downloads Chromium (about 270 MB) and a few X11/accessibility libraries from AppStream."
  echo ""
  confirm_extra_install "Install the Chromium web loader" || { pause; return 0; }

  load_manifest
  extras_preflight playwright "$PLAYWRIGHT_DIR" PLAYWRIGHT_INSTALLED || { pause; return 1; }
  if [ -z "$(owui_playwright_version)" ]; then
    fail "The installed Open WebUI does not declare a Playwright version; cannot match client and server."
    pause
    return 1
  fi
  local port
  port="$(ask_free_port "Playwright port" "${PLAYWRIGHT_PORT:-$PLAYWRIGHT_PORT_DEFAULT}")" || { fail "No free port for Playwright."; pause; return 1; }
  run_extra_install "Chromium web loader" browser_install_steps remove_browser "$port" playwright
}

browser_install_steps() {
  local port="$1"
  local version
  version="$(owui_playwright_version)" || return 1
  ensure_python311_ready || return 1
  ensure_extras_identity "$BROWSER_USER" "$BROWSER_HOME" /sbin/nologin BROWSER_USER_CREATED || return 1
  record_manifest "PLAYWRIGHT_INSTALLED" "1" || return 1
  PLAYWRIGHT_INSTALLED=1
  install_tracked_package "$PLAYWRIGHT_LIBS" playwright-libs || return 1
  install_tracked_package "$PLAYWRIGHT_FONTS" playwright-fonts || return 1
  mkdir -p "$PLAYWRIGHT_DIR" || return 1
  playwright_server_install "$version" || return 1
  playwright_client_install "$OPENWEBUI_VENV" "$version" || return 1
  write_playwright_service "$port" || return 1
  record_manifest "PLAYWRIGHT_PORT" "$port" || return 1
  record_manifest "PLAYWRIGHT_VERSION" "$version" || return 1
  PLAYWRIGHT_PORT="$port"

  start_extra_service playwright "http://127.0.0.1:${port}/" || return 1
  echo "Loading a JavaScript test page through Chromium from Open WebUI..."
  playwright_end_to_end_check "$port" || { fail "Chromium did not render the test page. Check: journalctl -u playwright -e"; return 1; }
  ok "Chromium web loader ready on 127.0.0.1:${port} (Playwright ${version}, test page rendered)."
  echo ""
  show_playwright_connection
}

show_playwright_connection() {
  echo "Chromium -> Open WebUI: Admin settings > Web Search > Loader"
  echo "  Web Loader Engine: playwright   Playwright WebSocket URL: ws://127.0.0.1:${PLAYWRIGHT_PORT:-$PLAYWRIGHT_PORT_DEFAULT}/"
}

# Brings server and client back to the Playwright version of the installed Open WebUI.
sync_playwright_with_openwebui() {
  [ "${PLAYWRIGHT_INSTALLED:-}" = "1" ] || return 0
  local version
  version="$(owui_playwright_version)"
  if [ -z "$version" ]; then
    warn "Open WebUI no longer declares a Playwright version; the Chromium web loader may stop working."
    return 1
  fi
  # Installs made before the fonts were added need them too.
  install_tracked_package "$PLAYWRIGHT_FONTS" playwright-fonts || return 1
  if [ "$version" != "${PLAYWRIGHT_VERSION:-}" ]; then
    echo "Open WebUI now uses Playwright ${version}; updating the Chromium web loader to match..."
    playwright_server_install "$version" || return 1
    record_manifest "PLAYWRIGHT_VERSION" "$version" || return 1
    PLAYWRIGHT_VERSION="$version"
  fi
  playwright_client_install "$OPENWEBUI_VENV" "$version" || return 1
  write_playwright_service "${PLAYWRIGHT_PORT:-$PLAYWRIGHT_PORT_DEFAULT}" || return 1
  start_extra_service playwright "http://127.0.0.1:${PLAYWRIGHT_PORT:-$PLAYWRIGHT_PORT_DEFAULT}/"
}

remove_browser() {
  [ "${PLAYWRIGHT_INSTALLED:-}" = "1" ] || return 0
  remove_extra_service playwright
  playwright_client_remove
  if [ -d "$PLAYWRIGHT_DIR" ]; then
    safe_rm_rf "$PLAYWRIGHT_DIR" /opt
  fi
  remove_tracked_packages playwright-fonts
  remove_tracked_packages playwright-libs
  local key
  for key in PLAYWRIGHT_INSTALLED PLAYWRIGHT_PORT PLAYWRIGHT_VERSION; do
    remove_manifest_key "$key"
  done
  PLAYWRIGHT_INSTALLED=""
  ok "Chromium web loader removed (service, browser, libraries and the client in Open WebUI)."
  owui_was_disconnected playwright || warn "Also set the web loader back to Default in Open WebUI: Admin settings > Web Search."
}
