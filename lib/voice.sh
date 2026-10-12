# Voice for Open WebUI.
#   Text to speech: Piper voices behind a small OpenAI-compatible server (piper_openai_server.py),
#   installed like the other tools (own venv, hardened service on 127.0.0.1, clean removal).
#   Speech to text: Open WebUI's built-in faster-whisper; this file only sets model and language.
# Browsers only allow the microphone on HTTPS pages, so dictation needs the HTTPS front end.

PIPER_SERVER_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/piper_openai_server.py"

install_piper_tts() {
  header
  echo "Installing Piper text to speech (natural voices on the CPU, Spanish and English)..."
  echo "Voices: ${PIPER_VOICES} (about 65 MB each)."
  echo ""
  confirm_extra_install "Install Piper text to speech" || { pause; return 0; }

  load_manifest
  extras_preflight piper-tts "$PIPER_DIR" PIPER_INSTALLED || { pause; return 1; }
  local port
  port="$(ask_free_port "Piper TTS port" "${PIPER_PORT:-$PIPER_PORT_DEFAULT}")" || { fail "No free port for Piper."; pause; return 1; }
  run_extra_install "Piper TTS" piper_install_steps remove_piper_tts "$port" piper-tts
}

# Copies the server, downloads the voices and checks they are all there.
piper_install_files() {
  local voice
  install -m 0644 "$PIPER_SERVER_SOURCE" "${PIPER_DIR}/server.py" || return 1
  mkdir -p "${PIPER_DIR}/voices" || return 1
  # shellcheck disable=SC2086
  run_required "Downloading Piper voices..." "${PIPER_DIR}/venv/bin/python" -m piper.download_voices \
    --data-dir "${PIPER_DIR}/voices" $PIPER_VOICES || return 1
  for voice in $PIPER_VOICES; do
    [ -f "${PIPER_DIR}/voices/${voice}.onnx" ] || { fail "Piper voice missing after download: ${voice}"; return 1; }
  done
  grant_group_read "$EXTRAS_USER" "$PIPER_DIR"
}

write_piper_service() {
  local port="$1"
  write_extra_service piper-tts "Piper text to speech for Open WebUI" "$EXTRAS_USER" \
    "$EXTRAS_HOME" "$EXTRAS_HOME" \
    "${PIPER_DIR}/venv/bin/python -I ${PIPER_DIR}/server.py" \
    "Environment=PIPER_VOICES_DIR=${PIPER_DIR}/voices" \
    "Environment=PIPER_DEFAULT_VOICE=${PIPER_DEFAULT_VOICE}" \
    "Environment=PIPER_HOST=127.0.0.1" \
    "Environment=PIPER_PORT=${port}"
}

piper_install_steps() {
  local port="$1"
  local type
  ensure_python311_ready || return 1
  ensure_extras_identity "$EXTRAS_USER" "$EXTRAS_HOME" /sbin/nologin EXTRAS_USER_CREATED || return 1
  record_manifest "PIPER_INSTALLED" "1" || return 1
  PIPER_INSTALLED=1
  mkdir -p "$PIPER_DIR" || return 1
  create_extras_venv "${PIPER_DIR}/venv" "$EXTRAS_USER" piper-tts lameenc || return 1
  piper_install_files || return 1
  write_piper_service "$port" || return 1
  record_manifest "PIPER_PORT" "$port" || return 1
  PIPER_PORT="$port"

  start_extra_service piper-tts "http://127.0.0.1:${port}/health" || return 1
  type="$(curl -fsS --max-time 60 -o /dev/null -w '%{content_type}' -X POST "http://127.0.0.1:${port}/v1/audio/speech" \
    -H 'Content-Type: application/json' -d '{"input":"Prueba de voz.","voice":"'"${PIPER_DEFAULT_VOICE}"'"}' 2>/dev/null || true)"
  [ "$type" = "audio/mpeg" ] || { fail "Piper is running but did not return speech. Check: journalctl -u piper-tts -e"; return 1; }
  ok "Piper text to speech ready on 127.0.0.1:${port} (test sentence synthesized)."
  echo ""
  show_piper_connection
}

show_piper_connection() {
  echo "Piper -> Open WebUI: Admin settings > Audio > Text-to-Speech"
  echo "  Engine: OpenAI   URL: http://127.0.0.1:${PIPER_PORT:-$PIPER_PORT_DEFAULT}/v1   Key: any text"
  echo "  Model: piper     Voice: ${PIPER_DEFAULT_VOICE} (others: ${PIPER_VOICES})"
}

update_piper_tts() {
  run_required "Updating Piper..." "${PIPER_DIR}/venv/bin/pip" install --no-cache-dir -U piper-tts lameenc || return 1
  piper_install_files || return 1
  write_piper_service "${PIPER_PORT:-$PIPER_PORT_DEFAULT}" || return 1
  start_extra_service piper-tts "http://127.0.0.1:${PIPER_PORT:-$PIPER_PORT_DEFAULT}/health"
}

remove_piper_tts() {
  [ "${PIPER_INSTALLED:-}" = "1" ] || return 0
  remove_extra_service piper-tts
  if [ -d "$PIPER_DIR" ]; then
    safe_rm_rf "$PIPER_DIR" /opt
  fi
  remove_manifest_key PIPER_INSTALLED
  remove_manifest_key PIPER_PORT
  PIPER_INSTALLED=""
  ok "Piper text to speech removed."
  owui_was_disconnected piper-tts || warn "Also set Text-to-Speech back to the browser engine in Open WebUI: Admin settings > Audio."
}

# Rewrites /etc/xemi-ai/openwebui.env from the manifest and restarts Open WebUI.
restart_openwebui_with_env() {
  local port="${OPENWEBUI_PORT:-$WEBUI_PORT_DEFAULT}"
  local base_url="${OPENWEBUI_OLLAMA_BASE_URL:-http://127.0.0.1:${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}}"
  write_openwebui_env_file "$port" "$base_url" || return 1
  systemctl restart openwebui || return 1
  wait_openwebui_health "$port"
}

validate_whisper_language() {
  [[ "${1:-}" =~ ^([a-z]{2}|auto)$ ]]
}

# Speech to text (Whisper model and language) and, when Piper is installed, text to speech.
configure_openwebui_voice() {
  header
  load_manifest
  local lang current ans
  echo "Voice in Open WebUI:"
  echo "  - Dictation and voice mode: Open WebUI's local Whisper, model ${OPENWEBUI_WHISPER_MODEL}"
  echo "    (accurate in Spanish, faster than real time on this CPU; about 480 MB, downloaded now)."
  if [ "${PIPER_INSTALLED:-}" = "1" ]; then
    echo "  - Spoken answers: Piper (${PIPER_DEFAULT_VOICE})."
  else
    echo "  - Spoken answers: the browser's own voices (install Piper in Open WebUI tools for better ones)."
  fi
  if [ "${HTTPS_INSTALLED:-}" != "1" ]; then
    warn "Browsers only allow the microphone on HTTPS pages: enable Network > HTTPS access for dictation."
  fi
  echo ""
  current="${OPENWEBUI_WHISPER_LANGUAGE:-$OPENWEBUI_WHISPER_LANGUAGE_DEFAULT}"
  while true; do
    lang="$(ask "Dictation language (two-letter code such as es or en, or auto to detect)" "$current")"
    validate_whisper_language "$lang" && break
    warn "Use a two-letter language code or auto." >&2
  done
  ans="$(confirm_proceed "Apply voice settings yes or no" "yes")"
  if ! is_yes "$ans"; then
    warn "Cancelled."
    pause
    return 0
  fi

  owui_login || { pause; return 0; }
  owui_set_whisper || true
  if [ "${PIPER_INSTALLED:-}" = "1" ]; then
    owui_connect_piper_tts || true
  fi
  owui_logout

  # The Whisper language is read from the environment when Open WebUI starts.
  if [ "$lang" != "${OPENWEBUI_WHISPER_LANGUAGE:-}" ]; then
    warn "Applying the dictation language restarts Open WebUI: answers being generated right now are cut off."
    ans="$(confirm_proceed "Restart Open WebUI now yes or no" "yes")"
    if ! is_yes "$ans"; then
      warn "Dictation language not changed; run Voice settings again when nobody is chatting."
      pause
      return 0
    fi
    record_manifest "OPENWEBUI_WHISPER_LANGUAGE" "$lang"
    OPENWEBUI_WHISPER_LANGUAGE="$lang"
    echo "Restarting Open WebUI to apply the dictation language (about a minute)..."
    if restart_openwebui_with_env; then
      ok "Dictation language set to ${lang}."
    else
      fail "Open WebUI did not come back after the restart. Check: journalctl -u openwebui -e"
    fi
  fi
  pause
}
