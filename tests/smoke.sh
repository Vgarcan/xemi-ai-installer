#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/config.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/validation.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/state.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/diagnostics.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/openwebui.sh"
source "${ROOT_DIR}/lib/ollama.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/extras.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/owui_api.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/https.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/backup.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/voice.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/jupyter.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/browser.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/services.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/cli.sh"

STATE_DIR="$TEST_DIR/state"
MANIFEST_FILE="${STATE_DIR}/manifest.env"
LOG_DIR="$TEST_DIR/log"
LOG_FILE="${LOG_DIR}/install.log"
mkdir -p "$STATE_DIR" "$LOG_DIR"

assert_rejected() {
  if "$@"; then
    echo "Expected rejection: $*" >&2
    exit 1
  fi
}

validate_cidr "192.168.2.0/24"
assert_rejected validate_cidr "999.168.2.0/24"
validate_bind_host "localhost"
validate_bind_host "192.168.2.10"
test "$(ollama_lib_dir_for_binary /usr/bin/ollama)" = /usr/lib/ollama
test "$(ollama_lib_dir_for_binary /bin/ollama)" = /usr/lib/ollama
test "$(ollama_lib_dir_for_binary /usr/local/bin/ollama)" = /usr/local/lib/ollama
assert_rejected ollama_lib_dir_for_binary /opt/other/ollama
assert_rejected validate_bind_host "2001:db8::1"
assert_rejected validate_package_spec "--user"

fail() { :; }
assert_rejected safe_rm_rf "$TEST_DIR" "$TEST_DIR"
assert_rejected record_manifest OLLAMA_PORT "not-a-port"

rule="rule family='ipv4' source address='192.168.2.0/24' port protocol='tcp' port='11434' accept"
record_manifest FIREWALL_RULE_OLLAMA "$rule"
FIREWALL_RULE_OLLAMA=""
load_manifest
[ "$FIREWALL_RULE_OLLAMA" = "$rule" ]
remove_manifest_key FIREWALL_RULE_OLLAMA
! grep -q '^FIREWALL_RULE_OLLAMA=' "$MANIFEST_FILE"

record_manifest OPEN_TERMINAL_PORT "8000"
record_manifest SEARXNG_COMMIT "f4822b3fc46726bb259d14c6332b702c76b98f82"
record_manifest TIKA_INSTALLED_VERSION "3.3.2"
assert_rejected record_manifest SEARXNG_COMMIT "main; rm -rf /"
assert_rejected record_manifest MCPO_INSTALLED "yes"
load_manifest
[ "$OPEN_TERMINAL_PORT" = "8000" ]
[ "$TIKA_INSTALLED_VERSION" = "3.3.2" ]
[ "$TIKA_VERSION" != "" ]
[ "$(openwebui_extras_table | cut -d'|' -f1 | paste -sd' ' -)" = "open-terminal mcpo searxng tika piper-tts jupyter playwright" ]

OPEN_TERMINAL_HOME="$TEST_DIR/open-terminal"
mkdir -p "$OPEN_TERMINAL_HOME/.local/state/open-terminal/logs"
touch "$OPEN_TERMINAL_HOME/.bashrc" "$OPEN_TERMINAL_HOME/.bash_history" "$OPEN_TERMINAL_HOME/.local/state/open-terminal/logs/a.log"
[ "$(open_terminal_user_files | wc -l)" = "0" ]
touch "$OPEN_TERMINAL_HOME/report.py"
[ "$(open_terminal_user_files)" = "$OPEN_TERMINAL_HOME/report.py" ]

# Package tracking runs in a subshell so the rpm/dnf stubs do not leak into later tests.
(
  EXTRAS_PACKAGES_DIR="$TEST_DIR/packages"
  FAKE_RPMS="base"
  rpm() {
    case "$1" in
      -q) [[ " $FAKE_RPMS " = *" $2 "* ]] ;;
      -qa) printf '%s\n' $FAKE_RPMS ;;
    esac
  }
  dnf() { FAKE_RPMS="$FAKE_RPMS java-21-openjdk-headless tzdata-java"; }
  run_required() { shift; "$@"; }
  install_tracked_package java-21-openjdk-headless tika
  [ "$(sort "$EXTRAS_PACKAGES_DIR/tika.list" | tr '\n' ' ')" = "java-21-openjdk-headless tzdata-java " ]
  install_tracked_package base other
  [ ! -e "$EXTRAS_PACKAGES_DIR/other.list" ]
)

ss_sample='LISTEN 0 4096 *:11434 *:* users:(("ollama",pid=32375,fd=3))
LISTEN 0 50 [::ffff:127.0.0.1]:9998 *:* users:(("java",pid=106280,fd=8))
LISTEN 0 2048 0.0.0.0:3000 0.0.0.0:* users:(("open-webui",pid=3193,fd=20))
LISTEN 0 128 [::1]:9000 [::]:* users:(("open-terminal",pid=700,fd=6))
LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=1,fd=3))'
[ "$(normalize_listen_ports " 106252 106280 " <<< "$ss_sample")" = "127.0.0.1:9998" ]
[ "$(normalize_listen_ports " 32375 3193 " <<< "$ss_sample")" = "*:11434 *:3000" ]
[ "$(normalize_listen_ports " 700 " <<< "$ss_sample")" = "[::1]:9000" ]
[ -z "$(normalize_listen_ports " 999 " <<< "$ss_sample")" ]
[ "$(printf 'MCPO_API_KEY=abc --api-key s3cr3t Bearer xyz a.b@c.io\n' | redact_diagnostics)" = "MCPO_API_KEY=<redacted> --api-key <redacted> Bearer <redacted> <email>" ]

validate_context_length 16384
assert_rejected validate_context_length 1024
assert_rejected validate_context_length "16k"
validate_kv_cache_type q8_0
assert_rejected validate_kv_cache_type q5_1
record_manifest OLLAMA_CONTEXT_LENGTH 32768
record_manifest OLLAMA_KV_CACHE_TYPE q4_0
assert_rejected record_manifest OLLAMA_KV_CACHE_TYPE "q8_0;id"
load_manifest
[ "$OLLAMA_CONTEXT_LENGTH" = "32768" ] && [ "$OLLAMA_KV_CACHE_TYPE" = "q4_0" ]
parse_args --ollama-context-length 8192 ollama-tune
load_manifest
[ "$OLLAMA_CONTEXT_LENGTH" = "8192" ] && [ "$OLLAMA_KV_CACHE_TYPE" = "q4_0" ] && [ "$COMMAND" = "ollama-tune" ]
OLLAMA_CONTEXT_LENGTH_FROM_CLI=0
remove_manifest_key OLLAMA_CONTEXT_LENGTH
remove_manifest_key OLLAMA_KV_CACHE_TYPE

record_manifest OLLAMA_BIND_HOST "127.0.0.1"
record_manifest FIREWALL_ZONE "public"
parse_args --expose-ollama --firewall-zone trusted --ollama-port 11435 install
load_manifest
[ "$OLLAMA_BIND_HOST" = "0.0.0.0" ]
[ "$OLLAMA_PORT" = "11435" ]
[ "$FIREWALL_ZONE" = "trusted" ]
[ "$RECORDED_FIREWALL_ZONE" = "public" ]

OPENWEBUI_VENV="$TEST_DIR/openwebui-venv"
OPENWEBUI_DATA_DIR="$TEST_DIR/openwebui-data"
previous="$TEST_DIR/openwebui-venv.previous"
candidate="$TEST_DIR/openwebui-venv.candidate"
snapshot="$TEST_DIR/openwebui-snapshot"
mkdir -p "$previous" "$candidate" "$snapshot" "$OPENWEBUI_DATA_DIR"
printf 'old\n' > "$previous/release"
printf 'new\n' > "$candidate/release"
printf 'original\n' > "$snapshot/db"
printf 'migrated\n' > "$OPENWEBUI_DATA_DIR/db"
ln -s "$candidate" "$OPENWEBUI_VENV"
systemctl() { :; }
wait_openwebui_health() { :; }
if [ -L "$OPENWEBUI_VENV" ]; then
  openwebui_restore_release "$previous" "$snapshot" "3000"
  [ ! -L "$OPENWEBUI_VENV" ]
  [ "$(head -n 1 "$OPENWEBUI_VENV/release")" = "old" ]
  [ "$(head -n 1 "$OPENWEBUI_DATA_DIR/db")" = "original" ]
else
  # Git Bash without Windows symlink privileges creates a regular path.
  assert_rejected openwebui_restore_release "$previous" "$snapshot" "3000"
fi

header() { :; }
pause() { :; }
load_manifest() { :; }
doctor_check_command() { doctor_fail "simulated failure"; }
doctor_check_gpu() { :; }
doctor_check_service() { :; }
doctor_check_http() { :; }
doctor_check_ollama_gpu_logs() { :; }
doctor_check_ollama_models_dir() { :; }
doctor_check_firewall() { :; }
doctor_ok() { :; }
doctor_fail() { DOCTOR_FAILURES=$((DOCTOR_FAILURES + 1)); }

assert_rejected doctor

# Doctor warns when Ollama does not run with the recorded context/K/V settings.
(
  doctor_warn() { echo "WARN $1"; }
  systemctl() { echo "OLLAMA_HOST=127.0.0.1:11434 OLLAMA_CONTEXT_LENGTH=19000 OLLAMA_KV_CACHE_TYPE=q8_0"; }
  OLLAMA_CONTEXT_LENGTH=19000
  OLLAMA_KV_CACHE_TYPE=q8_0
  [ -z "$(doctor_check_ollama_memory)" ]
  OLLAMA_CONTEXT_LENGTH=16384
  [[ "$(doctor_check_ollama_memory)" = WARN*"run: ollama-tune" ]]
  systemctl() { echo "OLLAMA_HOST=127.0.0.1:11434"; }
  [[ "$(doctor_check_ollama_memory)" = WARN*"not set"* ]]
  [ -z "$(doctor_check_ollama_exposure | grep WARN)" ]
  systemctl() { echo "OLLAMA_HOST=0.0.0.0:11434"; }
  [[ "$(doctor_check_ollama_exposure)" = WARN*"all interfaces"* ]]
)

# HTTPS front end: host list validation, generated Caddyfile and the capability it keeps.
(
  validate_https_hosts "svr32ai,svr32ai.lan,192.168.2.132"
  assert_rejected validate_https_hosts ""
  assert_rejected validate_https_hosts "svr32ai, 192.168.2.132"
  assert_rejected validate_https_hosts "svr32ai;id"
  HTTPS_CONFIG_DIR="$TEST_DIR/https"
  HTTPS_DATA_DIR="$TEST_DIR/https-data"
  OPENWEBUI_PORT=3000
  write_https_caddyfile 443 "svr32ai,192.168.2.132"
  grep -q '^	default_sni 192.168.2.132$' "$HTTPS_CONFIG_DIR/Caddyfile"
  # 127.0.0.1 gets its own site so local health checks reach Open WebUI, not Caddy's empty 200.
  grep -q '^https://svr32ai:443, https://192.168.2.132:443, https://127.0.0.1:443 {$' "$HTTPS_CONFIG_DIR/Caddyfile"
  write_https_caddyfile 8443 "127.0.0.1,svr32ai"
  grep -q '^https://127.0.0.1:8443, https://svr32ai:8443 {$' "$HTTPS_CONFIG_DIR/Caddyfile"
  grep -q 'reverse_proxy 127.0.0.1:3000' "$HTTPS_CONFIG_DIR/Caddyfile"
  eval "$(declare -f write_extra_hardening | sed "s#/etc/systemd/system/#$TEST_DIR/units/#")"
  write_extra_hardening "$HTTPS_SERVICE"
  write_extra_hardening tika
  grep -qx 'CapabilityBoundingSet=CAP_NET_BIND_SERVICE' "$TEST_DIR/units/${HTTPS_SERVICE}.service.d/xemi-hardening.conf"
  grep -qx 'CapabilityBoundingSet=' "$TEST_DIR/units/tika.service.d/xemi-hardening.conf"
  grep -qx 'SuccessExitStatus=143' "$TEST_DIR/units/tika.service.d/xemi-hardening.conf"
)

# Backups: the generated script copies a live SQLite database, rotates, and keeps tagged archives.
(
  validate_backup_time "03:30"
  assert_rejected validate_backup_time "24:00"
  validate_backup_keep 7
  assert_rejected validate_backup_keep 0
  OPENWEBUI_DATA_DIR="$TEST_DIR/owui-data"
  OPENWEBUI_VENV="$TEST_DIR/owui-venv"
  OWUI_BACKUP_SCRIPT="$TEST_DIR/xemi-openwebui-backup"
  dest="$TEST_DIR/backups"
  mkdir -p "$OPENWEBUI_DATA_DIR/uploads" "$OPENWEBUI_VENV/bin"
  ln -s "$(command -v python3)" "$OPENWEBUI_VENV/bin/python"
  printf '#!/bin/sh\necho "Version: 0.11.3"\n' > "$OPENWEBUI_VENV/bin/pip"
  chmod +x "$OPENWEBUI_VENV/bin/pip"
  python3 -c 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute("pragma journal_mode=wal"); c.execute("create table chat(id)"); c.execute("insert into chat values (42)"); c.commit()' "$OPENWEBUI_DATA_DIR/webui.db"
  echo "secret" > "$OPENWEBUI_DATA_DIR/.webui_secret_key"
  echo "doc" > "$OPENWEBUI_DATA_DIR/uploads/a.txt"
  write_owui_backup_script "$dest" 1
  bash -n "$OWUI_BACKUP_SCRIPT"
  "$OWUI_BACKUP_SCRIPT" > /dev/null
  sleep 1
  "$OWUI_BACKUP_SCRIPT" > /dev/null
  "$OWUI_BACKUP_SCRIPT" pre-restore > /dev/null
  [ "$(ls "$dest"/openwebui-2*.tar.gz | wc -l)" = "1" ]
  [ "$(ls "$dest"/openwebui-pre-restore-*.tar.gz | wc -l)" = "1" ]
  archive="$(ls "$dest"/openwebui-2*.tar.gz)"
  [ "$(tar -xzOf "$archive" open-webui-version)" = "0.11.3" ]
  tar -tzf "$archive" | grep -qx 'data/uploads/a.txt'
  mkdir -p "$TEST_DIR/restored"
  tar -xzf "$archive" -C "$TEST_DIR/restored"
  [ "$(python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("select id from chat").fetchone()[0])' "$TEST_DIR/restored/data/webui.db")" = "42" ]
  # The temporary work directory is always cleaned up.
  ! compgen -G "$dest/.work.*" > /dev/null
)

# Extra MCP servers: catalog lookup and the argument list written to mcpo's config.
[ "$(mcp_catalog_field wikipedia 2)" = "wikipedia-mcp" ]
[ "$(printf '%s\n' $(mcp_catalog_field wikipedia 4) | jq -R . | jq -s -c .)" = '["--language","es"]' ]
assert_rejected mcp_catalog_field nosuchserver 2
# mcpo installed without extra servers: removal and update must not trip over set -u.
(
  unset MCP_EXTRA_SERVERS
  MCP_SERVERS_DIR="$TEST_DIR/no-mcp-servers"
  remove_manifest_key() { :; }
  remove_all_mcp_extras
  update_mcp_extras
)
# Syntax check without writing __pycache__ into the repository.
python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "${ROOT_DIR}/lib/piper_openai_server.py"

# Voice: Whisper language validation and the value written to openwebui.env.
(
  validate_whisper_language es
  validate_whisper_language auto
  assert_rejected validate_whisper_language spanish
  OPENWEBUI_ENV_FILE="$TEST_DIR/openwebui.env"
  OPENWEBUI_WHISPER_LANGUAGE=es
  write_openwebui_env_file 3000 http://127.0.0.1:11434
  grep -qx 'WHISPER_LANGUAGE=es' "$OPENWEBUI_ENV_FILE"
  OPENWEBUI_WHISPER_LANGUAGE=auto
  write_openwebui_env_file 3000 http://127.0.0.1:11434
  grep -qx 'WHISPER_LANGUAGE=' "$OPENWEBUI_ENV_FILE"
)

# Open WebUI connections against a fake API: GET serves canned JSON, POST records the body.
(
  OWUI="$TEST_DIR/owui"
  mkdir -p "$OWUI"
  owui_api() {
    local file
    file="$(printf '%s' "$2" | tr '/' '_')"
    if [ "$1" = "GET" ]; then
      cat "$OWUI/get$file.json"
    else
      cat > "$OWUI/post$file.json"
      echo '{}'
    fi
  }
  serve() { printf '%s\n' "$2" > "$OWUI/get$(printf '%s' "$1" | tr '/' '_').json"; }
  posted() { cat "$OWUI/post$(printf '%s' "$1" | tr '/' '_').json"; }
  ok() { :; }
  OPEN_TERMINAL_ENV_FILE="$OWUI/ot.env"
  echo "OPEN_TERMINAL_API_KEY=otkey" > "$OPEN_TERMINAL_ENV_FILE"
  OPEN_TERMINAL_PORT=9000

  # Our entry is replaced, the admin's own connection and access grants are kept.
  serve /api/v1/configs/terminal_servers '{"TERMINAL_SERVER_CONNECTIONS":[{"id":"mine"},{"id":"xemi-open-terminal","config":{"access_grants":["g1"]}}]}'
  owui_connect_open_terminal
  [ "$(posted /api/v1/configs/terminal_servers | jq -c '[.TERMINAL_SERVER_CONNECTIONS[] | [.id, .url, .key, .config.access_grants]]')" \
    = '[["mine",null,null,null],["xemi-open-terminal","http://127.0.0.1:9000","otkey",["g1"]]]' ]

  # A response without the expected key is refused and nothing is written.
  serve /api/v1/configs/terminal_servers '{"connections":[]}'
  : > "$OWUI/post_api_v1_configs_terminal_servers.json"
  assert_rejected owui_connect_open_terminal > /dev/null
  [ ! -s "$OWUI/post_api_v1_configs_terminal_servers.json" ]

  # The web search section is sent back complete with only the SearXNG fields changed.
  serve /api/v1/retrieval/config '{"web":{"ENABLE_WEB_SEARCH":false,"WEB_SEARCH_ENGINE":"","SEARXNG_QUERY_URL":"","KEEP":1}}'
  SEARXNG_PORT=8888
  owui_connect_searxng
  [ "$(posted /api/v1/retrieval/config/update | jq -c '.web')" \
    = '{"ENABLE_WEB_SEARCH":true,"WEB_SEARCH_ENGINE":"searxng","SEARXNG_QUERY_URL":"http://127.0.0.1:8888/search?q=<query>","KEEP":1}' ]

  # Settings that point to another SearXNG are not touched on removal.
  serve /api/v1/retrieval/config '{"web":{"WEB_SEARCH_ENGINE":"searxng","SEARXNG_QUERY_URL":"https://search.example.org/?q=<query>"}}'
  : > "$OWUI/post_api_v1_retrieval_config_update.json"
  owui_disconnect_searxng
  [ ! -s "$OWUI/post_api_v1_retrieval_config_update.json" ]

  # Piper: only the tts part changes; stt stays as it was. Removal undoes only our own setting.
  serve /api/v1/audio/config '{"tts":{"ENGINE":"","OPENAI_API_BASE_URL":"https://api.openai.com/v1","OPENAI_API_KEY":"","MODEL":"tts-1","VOICE":"alloy","SPLIT_ON":"punctuation"},"stt":{"ENGINE":"","WHISPER_MODEL":"base","KEEP":1}}'
  PIPER_PORT=8002
  owui_connect_piper_tts
  [ "$(posted /api/v1/audio/config/update | jq -c '[.tts.ENGINE, .tts.OPENAI_API_BASE_URL, .tts.VOICE, .stt.WHISPER_MODEL, .stt.KEEP]')" \
    = "[\"openai\",\"http://127.0.0.1:8002/v1\",\"${PIPER_DEFAULT_VOICE}\",\"base\",1]" ]
  serve /api/v1/audio/config '{"tts":{"ENGINE":"openai","OPENAI_API_BASE_URL":"https://tts.example.org/v1","VOICE":"x"},"stt":{"ENGINE":"","WHISPER_MODEL":"small"}}'
  : > "$OWUI/post_api_v1_audio_config_update.json"
  owui_disconnect_piper_tts
  [ ! -s "$OWUI/post_api_v1_audio_config_update.json" ]

  # Jupyter: both engines move to Jupyter; "no" (the default) limits the interpreter to admins.
  JUPYTER_ENV_FILE="$OWUI/jupyter.env"
  echo "JUPYTER_TOKEN=jtok" > "$JUPYTER_ENV_FILE"
  JUPYTER_PORT=8890
  ASSUME_YES=1
  serve /api/v1/configs/code_execution '{"ENABLE_CODE_EXECUTION":true,"CODE_EXECUTION_ENGINE":"pyodide","CODE_EXECUTION_JUPYTER_URL":"","ENABLE_CODE_INTERPRETER":true,"CODE_INTERPRETER_ENGINE":"pyodide","CODE_INTERPRETER_JUPYTER_URL":"","CODE_INTERPRETER_PROMPT_TEMPLATE":"keep"}'
  serve /api/v1/users/default/permissions '{"workspace":{},"chat":{},"features":{"code_interpreter":true,"web_search":true}}'
  owui_connect_jupyter
  [ "$(posted /api/v1/configs/code_execution | jq -c '[.CODE_EXECUTION_ENGINE, .CODE_INTERPRETER_ENGINE, .CODE_INTERPRETER_JUPYTER_URL, .CODE_INTERPRETER_JUPYTER_AUTH_TOKEN, .CODE_INTERPRETER_PROMPT_TEMPLATE]')" \
    = '["jupyter","jupyter","http://127.0.0.1:8890","jtok","keep"]' ]
  [ "$(posted /api/v1/users/default/permissions | jq -c '.features')" = '{"code_interpreter":false,"web_search":true}' ]
  grep -q '^JUPYTER_PERMISSION_CHANGED=1$' "$MANIFEST_FILE"
  remove_manifest_key JUPYTER_PERMISSION_CHANGED
  ASSUME_YES=0

  # Chromium web loader: the web section is sent back complete with only the loader fields changed.
  serve /api/v1/retrieval/config '{"web":{"WEB_LOADER_ENGINE":"","PLAYWRIGHT_WS_URL":"","SEARXNG_QUERY_URL":"keep"}}'
  PLAYWRIGHT_PORT=8003
  owui_connect_playwright
  [ "$(posted /api/v1/retrieval/config/update | jq -c '.web')" \
    = '{"WEB_LOADER_ENGINE":"playwright","PLAYWRIGHT_WS_URL":"ws://127.0.0.1:8003/","SEARXNG_QUERY_URL":"keep","PLAYWRIGHT_TIMEOUT":15000}' ]
)

echo "Smoke tests passed."
