# Connects the installed tools to Open WebUI through its admin API, and removes those
# connections again. Open WebUI keeps these settings in its database, so environment
# variables only work on a first start; the admin API is the only safe way afterwards.
#
# Credentials are asked when needed and never stored. The session token lives only in
# a shell variable and reaches curl through a process substitution, so it is neither
# written to disk nor visible in the process list. Every endpoint shape is checked
# before writing; if Open WebUI changed its API, the manual instructions are shown.

OWUI_TOKEN=""
# Expected response shapes. The key must exist: a missing key would read as null and pass.
OWUI_TERMINAL_SHAPE='has("TERMINAL_SERVER_CONNECTIONS") and (.TERMINAL_SERVER_CONNECTIONS | . == null or type == "array")'
OWUI_TOOL_SHAPE='has("TOOL_SERVER_CONNECTIONS") and (.TOOL_SERVER_CONNECTIONS | . == null or type == "array")'
# Tools whose Open WebUI connection was removed in this run (space separated).
OWUI_DISCONNECTED=" "

owui_base_url() {
  echo "http://127.0.0.1:${OPENWEBUI_PORT:-$WEBUI_PORT_DEFAULT}"
}

# Usage: owui_api GET PATH  |  owui_api POST PATH < json
owui_api() {
  local method="$1"
  local path="$2"
  if [ "$method" = "GET" ]; then
    curl -fsS --max-time 30 -H @<(printf 'Authorization: Bearer %s\n' "$OWUI_TOKEN") \
      "$(owui_base_url)${path}"
  else
    curl -fsS --max-time 120 -X "$method" -H @<(printf 'Authorization: Bearer %s\n' "$OWUI_TOKEN") \
      -H 'Content-Type: application/json' --data-binary @- "$(owui_base_url)${path}"
  fi
}

owui_logout() {
  OWUI_TOKEN=""
}

# Asks for an Open WebUI administrator and keeps a session token for this run.
owui_login() {
  local email password response role
  [ -n "$OWUI_TOKEN" ] && return 0
  if [ "$ASSUME_YES" = "1" ]; then
    warn "Connecting to Open WebUI needs an administrator login; skipped in unattended mode."
    return 1
  fi
  if ! cmd_exists jq; then
    warn "jq is required to talk to the Open WebUI API (install the base tools first)."
    return 1
  fi
  if ! curl -fsS --max-time 5 "$(owui_base_url)/health" >/dev/null 2>&1; then
    warn "Open WebUI is not responding at $(owui_base_url)."
    return 1
  fi

  echo ""
  echo "Open WebUI administrator login (used for this step only, never stored):"
  email="$(ask "Admin e-mail" "")"
  read -r -s -p "Password: " password
  echo "" >&2
  response="$(OWUI_EMAIL="$email" OWUI_PASSWORD="$password" jq -n '{email: env.OWUI_EMAIL, password: env.OWUI_PASSWORD}' \
    | curl -sS --max-time 30 -H 'Content-Type: application/json' --data-binary @- \
      "$(owui_base_url)/api/v1/auths/signin" 2>/dev/null || true)"
  password=""
  OWUI_TOKEN="$(jq -r '.token // empty' <<< "$response" 2>/dev/null || true)"
  role="$(jq -r '.role // empty' <<< "$response" 2>/dev/null || true)"
  if [ -z "$OWUI_TOKEN" ]; then
    fail "Open WebUI login failed. Check the e-mail and password."
    return 1
  fi
  if [ "$role" != "admin" ]; then
    owui_logout
    fail "That account is not an Open WebUI administrator."
    return 1
  fi
  ok "Logged in to Open WebUI."
}

# Fetches PATH and checks it with the jq filter SHAPE; prints the JSON when it matches.
owui_get_checked() {
  local path="$1"
  local shape="$2"
  local json
  json="$(owui_api GET "$path" 2>/dev/null)" || return 1
  jq -e "$shape" <<< "$json" >/dev/null 2>&1 || return 1
  printf '%s\n' "$json"
}

owui_api_changed() {
  warn "The Open WebUI API at $1 does not look as expected (Open WebUI was probably updated)."
  warn "Nothing was changed there; use the manual steps below."
}

# ---------------------------------------------------------------------------
# Per-tool connect / disconnect
# ---------------------------------------------------------------------------

owui_connect_open_terminal() {
  local path="/api/v1/configs/terminal_servers"
  local current body key url
  current="$(owui_get_checked "$path" "$OWUI_TERMINAL_SHAPE")" \
    || { owui_api_changed "$path"; show_open_terminal_connection; return 1; }
  key="$(sed -n 's/^OPEN_TERMINAL_API_KEY=//p' "$OPEN_TERMINAL_ENV_FILE")"
  url="http://127.0.0.1:${OPEN_TERMINAL_PORT:-$OPEN_TERMINAL_PORT_DEFAULT}"
  # Replaces only our entry and keeps any access grants an admin gave it.
  body="$(XEMI_KEY="$key" jq --arg url "$url" '
    (.TERMINAL_SERVER_CONNECTIONS // []) as $all
    | (($all | map(select(.id == "xemi-open-terminal")) | first) // {}) as $old
    | {TERMINAL_SERVER_CONNECTIONS: (($all | map(select(.id != "xemi-open-terminal"))) + [{
        id: "xemi-open-terminal", name: "Open Terminal (this server)", enabled: true,
        url: $url, path: "/openapi.json", key: env.XEMI_KEY, auth_type: "bearer",
        config: ($old.config // {})
      }])}' <<< "$current")" || return 1
  if ! owui_api POST "$path" <<< "$body" >/dev/null; then
    fail "Open WebUI rejected the Open Terminal connection."
    show_open_terminal_connection
    return 1
  fi
  ok "Open Terminal connected to Open WebUI (administrators only until you grant groups access)."
}

owui_disconnect_open_terminal() {
  local path="/api/v1/configs/terminal_servers"
  local current body
  current="$(owui_get_checked "$path" "$OWUI_TERMINAL_SHAPE")" \
    || { owui_api_changed "$path"; return 1; }
  if ! jq -e '(.TERMINAL_SERVER_CONNECTIONS // []) | any(.id == "xemi-open-terminal")' <<< "$current" >/dev/null; then
    OWUI_DISCONNECTED+="open-terminal "
    return 0
  fi
  body="$(jq '{TERMINAL_SERVER_CONNECTIONS: ((.TERMINAL_SERVER_CONNECTIONS // []) | map(select(.id != "xemi-open-terminal")))}' <<< "$current")" || return 1
  owui_api POST "$path" <<< "$body" >/dev/null || { fail "Could not remove the Open Terminal connection from Open WebUI."; return 1; }
  OWUI_DISCONNECTED+="open-terminal "
  ok "Open Terminal connection removed from Open WebUI."
}

owui_connect_mcpo() {
  local path="/api/v1/configs/tool_servers"
  local current body key servers
  current="$(owui_get_checked "$path" "$OWUI_TOOL_SHAPE")" \
    || { owui_api_changed "$path"; show_mcpo_connection; return 1; }
  key="$(sed -n 's/^MCPO_API_KEY=//p' "$MCPO_ENV_FILE")"
  servers="$(jq -c '.mcpServers | keys' "${MCPO_CONFIG_DIR}/config.json")" || return 1
  # One OpenAPI tool server per MCP server in mcpo's config; our entries are tagged xemi-mcpo-*.
  body="$(XEMI_KEY="$key" jq --arg base "http://127.0.0.1:${MCPO_PORT:-$MCPO_PORT_DEFAULT}" --argjson servers "$servers" '
    (.TOOL_SERVER_CONNECTIONS // []) as $all
    | {TOOL_SERVER_CONNECTIONS: (($all | map(select((.info.id // "") | startswith("xemi-mcpo-") | not)))
        + [$servers[] as $name
           | (($all | map(select(.info.id == ("xemi-mcpo-" + $name))) | first) // {}) as $old
           | {url: ($base + "/" + $name), path: "openapi.json", type: "openapi", auth_type: "bearer",
              key: env.XEMI_KEY, config: (($old.config // {}) + {enable: true}),
              info: {id: ("xemi-mcpo-" + $name), name: ($name + " (mcpo)"),
                     description: ("MCP server " + $name + " on this server, through mcpo")}}])}' <<< "$current")" || return 1
  if ! owui_api POST "$path" <<< "$body" >/dev/null; then
    fail "Open WebUI rejected the mcpo tool servers."
    show_mcpo_connection
    return 1
  fi
  ok "mcpo tool servers connected to Open WebUI: $(jq -r 'join(", ")' <<< "$servers") (administrators only until you grant access)."
}

owui_disconnect_mcpo() {
  local path="/api/v1/configs/tool_servers"
  local current body
  current="$(owui_get_checked "$path" "$OWUI_TOOL_SHAPE")" \
    || { owui_api_changed "$path"; return 1; }
  if ! jq -e '(.TOOL_SERVER_CONNECTIONS // []) | any((.info.id // "") | startswith("xemi-mcpo-"))' <<< "$current" >/dev/null; then
    OWUI_DISCONNECTED+="mcpo "
    return 0
  fi
  body="$(jq '{TOOL_SERVER_CONNECTIONS: ((.TOOL_SERVER_CONNECTIONS // []) | map(select((.info.id // "") | startswith("xemi-mcpo-") | not)))}' <<< "$current")" || return 1
  owui_api POST "$path" <<< "$body" >/dev/null || { fail "Could not remove the mcpo tool servers from Open WebUI."; return 1; }
  OWUI_DISCONNECTED+="mcpo "
  ok "mcpo tool servers removed from Open WebUI."
}

# The web section is replaced as a whole by Open WebUI, so it is read, changed and sent back complete.
owui_connect_searxng() {
  local path="/api/v1/retrieval/config"
  local current body
  current="$(owui_get_checked "$path" '.web | type == "object" and has("SEARXNG_QUERY_URL") and has("WEB_SEARCH_ENGINE") and has("ENABLE_WEB_SEARCH")')" \
    || { owui_api_changed "$path"; show_searxng_connection; return 1; }
  body="$(jq --arg url "http://127.0.0.1:${SEARXNG_PORT:-$SEARXNG_PORT_DEFAULT}/search?q=<query>" \
    '{web: (.web + {ENABLE_WEB_SEARCH: true, WEB_SEARCH_ENGINE: "searxng", SEARXNG_QUERY_URL: $url})}' <<< "$current")" || return 1
  if ! owui_api POST "/api/v1/retrieval/config/update" <<< "$body" >/dev/null; then
    fail "Open WebUI rejected the SearXNG web search settings."
    show_searxng_connection
    return 1
  fi
  ok "SearXNG set as the Open WebUI web search engine."
}

owui_disconnect_searxng() {
  local path="/api/v1/retrieval/config"
  local current body
  current="$(owui_get_checked "$path" '.web | type == "object" and has("SEARXNG_QUERY_URL") and has("WEB_SEARCH_ENGINE")')" \
    || { owui_api_changed "$path"; return 1; }
  # Only undo settings that still point to this installer's SearXNG.
  if ! jq -e '.web.WEB_SEARCH_ENGINE == "searxng" and (.web.SEARXNG_QUERY_URL // "" | startswith("http://127.0.0.1:"))' <<< "$current" >/dev/null; then
    OWUI_DISCONNECTED+="searxng "
    return 0
  fi
  body="$(jq '{web: (.web + {ENABLE_WEB_SEARCH: false, WEB_SEARCH_ENGINE: "", SEARXNG_QUERY_URL: ""})}' <<< "$current")" || return 1
  owui_api POST "/api/v1/retrieval/config/update" <<< "$body" >/dev/null || { fail "Could not reset web search in Open WebUI."; return 1; }
  OWUI_DISCONNECTED+="searxng "
  ok "Open WebUI web search turned off (SearXNG removed)."
}

owui_connect_tika() {
  local path="/api/v1/retrieval/config"
  local body
  owui_get_checked "$path" 'has("CONTENT_EXTRACTION_ENGINE") and has("TIKA_SERVER_URL")' >/dev/null \
    || { owui_api_changed "$path"; show_tika_connection; return 1; }
  body="$(jq -n --arg url "http://127.0.0.1:${TIKA_PORT:-$TIKA_PORT_DEFAULT}" \
    '{CONTENT_EXTRACTION_ENGINE: "tika", TIKA_SERVER_URL: $url}')" || return 1
  if ! owui_api POST "/api/v1/retrieval/config/update" <<< "$body" >/dev/null; then
    fail "Open WebUI rejected the Apache Tika settings."
    show_tika_connection
    return 1
  fi
  ok "Apache Tika set as the Open WebUI content extraction engine."
}

owui_disconnect_tika() {
  local path="/api/v1/retrieval/config"
  local current body
  current="$(owui_get_checked "$path" 'has("CONTENT_EXTRACTION_ENGINE") and has("TIKA_SERVER_URL")')" \
    || { owui_api_changed "$path"; return 1; }
  if ! jq -e '.CONTENT_EXTRACTION_ENGINE == "tika" and (.TIKA_SERVER_URL // "" | startswith("http://127.0.0.1:"))' <<< "$current" >/dev/null; then
    OWUI_DISCONNECTED+="tika "
    return 0
  fi
  # Back to Open WebUI's own defaults.
  body="$(jq -n '{CONTENT_EXTRACTION_ENGINE: "", TIKA_SERVER_URL: "http://tika:9998"}')" || return 1
  owui_api POST "/api/v1/retrieval/config/update" <<< "$body" >/dev/null || { fail "Could not reset content extraction in Open WebUI."; return 1; }
  OWUI_DISCONNECTED+="tika "
  ok "Open WebUI content extraction set back to the default engine (Tika removed)."
}

# ---------------------------------------------------------------------------
# Entry points used by the installers, removal and the menu
# ---------------------------------------------------------------------------

# Offers to connect one freshly installed tool.
offer_openwebui_connect() {
  local tool="$1"
  local ans
  if [ "$ASSUME_YES" = "1" ]; then
    echo "Connect it to Open WebUI later from: 5) Open WebUI tools > Connect installed tools to Open WebUI."
    return 0
  fi
  echo ""
  ans="$(ask "Connect ${tool} to Open WebUI now (needs an Open WebUI admin login) yes or no" "yes")"
  is_yes "$ans" || return 0
  if owui_login; then
    "owui_connect_${tool//-/_}" || true
    owui_logout
  fi
}

connect_openwebui_extras() {
  header
  load_manifest
  local service label url flag any=0
  local -a tools=()
  while IFS='|' read -r service label url flag; do
    if [ "${!flag:-}" = "1" ]; then
      tools+=("$service")
    fi
  done < <(openwebui_extras_table)
  if [ "${#tools[@]}" -eq 0 ]; then
    warn "No Open WebUI tools are installed."
    pause
    return 0
  fi
  echo "This connects to Open WebUI: ${tools[*]}"
  echo "Existing connections created by this installer are refreshed; your own are kept."
  if owui_login; then
    for service in "${tools[@]}"; do
      "owui_connect_${service//-/_}" || any=1
    done
    owui_logout
  else
    any=1
  fi
  if [ "$any" = "0" ]; then
    ok "All installed tools are connected to Open WebUI."
  fi
  pause
}

# Asks once and removes the Open WebUI connections of TOOLS (service names) before removal.
offer_openwebui_disconnect() {
  local tool ans
  [ "$#" -gt 0 ] || return 0
  if [ "$ASSUME_YES" = "1" ] || ! curl -fsS --max-time 5 "$(owui_base_url)/health" >/dev/null 2>&1; then
    return 0
  fi
  ans="$(ask "Also remove their connections in Open WebUI (needs an admin login) yes or no" "yes")"
  is_yes "$ans" || return 0
  owui_login || return 0
  for tool in "$@"; do
    "owui_disconnect_${tool//-/_}" || true
  done
  owui_logout
}

# True when TOOL's Open WebUI connection was removed in this run.
owui_was_disconnected() {
  [[ "$OWUI_DISCONNECTED" = *" $1 "* ]]
}

# Task model and retrieval sizes recommended for this server (see README, Ollama Model Memory).
apply_openwebui_recommended_settings() {
  header
  load_manifest
  local tasks retrieval body task_model="$OPENWEBUI_TASK_MODEL" ans follow_up=""
  if ! ollama_has_model "$task_model"; then
    ans="$(ask "Task model ${task_model} is not in Ollama. Pull it now (about 0.4 GB) yes or no" "yes")"
    if ! is_yes "$ans" || ! pull_ollama_model "$task_model" || ! ollama_has_model "$task_model"; then
      warn "Task model ${task_model} is not available; settings were not changed."
      pause
      return 0
    fi
  fi
  echo "Recommended Open WebUI settings:"
  echo "  - Task model (titles, tags, search queries): ${task_model}, so these jobs do not"
  echo "    queue in front of your answer on the main model (about 0.5-0.9 GiB of VRAM)."
  echo "  - Documents Top K: ${OPENWEBUI_RAG_TOP_K} and web search results: ${OPENWEBUI_WEB_SEARCH_RESULT_COUNT} (fits the ${OLLAMA_CONTEXT_LENGTH}-token context)."
  echo "  - Embedding model is not changed here: it needs re-indexing; see the README."
  echo ""
  ans="$(ask "Turn off follow-up suggestions after each answer yes or no" "no")"
  is_yes "$ans" && follow_up="false"
  ans="$(confirm_proceed "Apply these settings yes or no" "yes")"
  if ! is_yes "$ans"; then
    warn "Cancelled."
    pause
    return 0
  fi
  owui_login || { pause; return 0; }

  # The task form must be sent complete, so it is read, changed and sent back.
  if tasks="$(owui_get_checked "/api/v1/tasks/config" 'has("TASK_MODEL") and has("ENABLE_FOLLOW_UP_GENERATION")')"; then
    body="$(jq --arg m "$task_model" --arg fu "$follow_up" \
      '. + {TASK_MODEL: $m} + (if $fu == "false" then {ENABLE_FOLLOW_UP_GENERATION: false} else {} end)' <<< "$tasks")"
    if owui_api POST "/api/v1/tasks/config/update" <<< "$body" >/dev/null; then
      ok "Task model set to ${task_model}."
    else
      fail "Open WebUI rejected the task settings."
    fi
  else
    owui_api_changed "/api/v1/tasks/config"
  fi

  if retrieval="$(owui_get_checked "/api/v1/retrieval/config" 'has("TOP_K") and (.web | type == "object" and has("WEB_SEARCH_RESULT_COUNT"))')"; then
    body="$(jq --argjson k "$OPENWEBUI_RAG_TOP_K" --argjson n "$OPENWEBUI_WEB_SEARCH_RESULT_COUNT" \
      '{TOP_K: $k, web: (.web + {WEB_SEARCH_RESULT_COUNT: $n})}' <<< "$retrieval")"
    if owui_api POST "/api/v1/retrieval/config/update" <<< "$body" >/dev/null; then
      ok "Documents Top K set to ${OPENWEBUI_RAG_TOP_K} and web search results to ${OPENWEBUI_WEB_SEARCH_RESULT_COUNT}."
    else
      fail "Open WebUI rejected the retrieval settings."
    fi
  else
    owui_api_changed "/api/v1/retrieval/config"
  fi
  owui_logout
  pause
}
