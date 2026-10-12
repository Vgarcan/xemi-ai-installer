# Ollama installation, configuration, models, and GPU integration.

nvidia_gpu_uuids() {
  if ! cmd_exists nvidia-smi; then
    return 1
  fi
  nvidia-smi --query-gpu=uuid --format=csv,noheader 2>/dev/null | awk 'NF {gsub(/^[ \t]+|[ \t]+$/, ""); print}' | paste -sd, -
}

ensure_nvidia_gpu_ready() {
  if ! cmd_exists nvidia-smi; then
    fail "nvidia-smi not found. Install NVIDIA drivers first and reboot if needed."
    return 1
  fi

  if ! nvidia-smi >/dev/null 2>&1; then
    fail "nvidia-smi is installed but cannot talk to the GPU. Reboot after driver install or check NVIDIA drivers."
    return 1
  fi
}

enable_nvidia_persistence() {
  if ! cmd_exists nvidia-smi; then
    return 0
  fi

  mkdir -p /etc/modules-load.d
  cat > /etc/modules-load.d/nvidia.conf <<'EOF'
nvidia
nvidia_uvm
nvidia_modeset
nvidia_drm
EOF

  if systemctl list-unit-files nvidia-persistenced.service >/dev/null 2>&1; then
    run_optional "Enabling NVIDIA persistence daemon..." systemctl enable --now nvidia-persistenced || true
  fi
  run_optional "Enabling NVIDIA persistence mode..." nvidia-smi -pm 1 || true
}

is_ollama_service_installed() {
  if ! cmd_exists ollama; then
    return 1
  fi
  systemctl list-unit-files ollama.service >/dev/null 2>&1
}

has_existing_installation() {
  load_manifest
  if [ -n "${OLLAMA_INSTALLED_BY_XEMI:-}" ] || [ -n "${OPENWEBUI_SERVICE_CREATED:-}" ]; then
    return 0
  fi

  if is_ollama_service_installed || is_openwebui_installed; then
    return 0
  fi
  return 1
}

ollama_current_compute_mode() {
  local pid logs
  pid="$(systemctl show ollama -p MainPID --value --no-pager 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  [ "$pid" -gt 0 ] || return 1

  logs="$(journalctl _PID="$pid" -o cat --no-pager 2>/dev/null || true)"
  if echo "$logs" | grep -q 'library=CUDA'; then
    echo "gpu"
    return 0
  fi
  if echo "$logs" | grep -q 'id=cpu library=cpu'; then
    echo "cpu"
    return 0
  fi
  return 1
}

wait_for_ollama_compute_mode() {
  local attempts="${1:-30}"
  local delay="${2:-2}"
  local mode=""
  local i

  for ((i=1; i<=attempts; i++)); do
    if mode="$(ollama_current_compute_mode 2>/dev/null || true)" && [ -n "$mode" ]; then
      echo "$mode"
      return 0
    fi
    sleep "$delay"
  done
  return 1
}

ensure_ollama_uses_gpu() {
  local allow_restart="${1:-1}"
  local mode=""

  if ! ensure_nvidia_gpu_ready; then
    return 0
  fi

  if ! mode="$(wait_for_ollama_compute_mode 45 2 || true)" || [ -z "$mode" ]; then
    fail "Could not determine whether Ollama started with GPU or CPU."
    return 1
  fi

  if [ "$mode" = "gpu" ]; then
    ok "Ollama detected CUDA and is ready to use the GPU."
    return 0
  fi

  if [ "$allow_restart" = "1" ]; then
    warn "Ollama started in CPU mode even though NVIDIA GPU is ready. Restarting Ollama once."
    systemctl restart ollama
    mode="$(wait_for_ollama_compute_mode 45 2 || true)"
    if [ "$mode" = "gpu" ]; then
      ok "Ollama switched to CUDA after restart."
      return 0
    fi
  fi

  fail "Ollama is still in CPU mode while NVIDIA GPU is available."
  return 1
}

repair_ollama_service_override() {
  local port="${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}"
  local bind_host="${OLLAMA_BIND_HOST:-0.0.0.0}"
  local models_dir="$(current_ollama_models_dir)"
  local gpu_uuids=""

  if ensure_nvidia_gpu_ready; then
    enable_nvidia_persistence
    gpu_uuids="$(nvidia_gpu_uuids || true)"
  fi

  write_ollama_override "$port" "$bind_host" "$gpu_uuids" "$models_dir"
  if [ -n "$gpu_uuids" ]; then
    record_manifest "NVIDIA_GPU_UUIDS" "$gpu_uuids"
  fi
  record_manifest "OLLAMA_OVERRIDE_CREATED" "1"
  record_manifest "OLLAMA_PORT" "$port"
  record_manifest "OLLAMA_BIND_HOST" "$bind_host"
  record_manifest "OLLAMA_CONTEXT_LENGTH" "$OLLAMA_CONTEXT_LENGTH"
  record_manifest "OLLAMA_KV_CACHE_TYPE" "$OLLAMA_KV_CACHE_TYPE"
  systemctl daemon-reload
  systemctl enable ollama >/dev/null 2>&1 || true
  systemctl enable xemi-ollama-gpu-guard.service >/dev/null 2>&1 || true
  systemctl restart ollama || true
  ensure_ollama_uses_gpu 1 || true
}

repair_ollama_installation() {
  header
  echo "Repairing Ollama installation..."
  load_manifest
  ensure_ai_user

  if ! cmd_exists ollama; then
    warn "Ollama binary missing; installing Ollama."
    install_ollama_official
    repair_ollama_service_override
    return
  fi

  if verify_ollama_runtime_libs; then
    ok "Ollama runtime libraries verified."
  else
    warn "Ollama runtime or CUDA libraries appear incomplete. Re-installing Ollama."
    install_ollama_official
    repair_ollama_service_override
    return
  fi

  if ! systemctl show ollama -p Environment --no-pager 2>/dev/null | grep -q 'OLLAMA_HOST='; then
    warn "Ollama systemd override missing or incomplete; reconfiguring."
    repair_ollama_service_override
  else
    ok "Ollama service configuration present."
    repair_ollama_service_override
  fi
  pause
}

ollama_lib_dir_for_binary() {
  case "$1" in
    /usr/local/bin/ollama) echo /usr/local/lib/ollama ;;
    /usr/bin/ollama|/bin/ollama) echo /usr/lib/ollama ;;
    *) return 1 ;;
  esac
}

ollama_runtime_lib_dir() {
  local binary
  binary="$(command -v ollama || true)"
  ollama_lib_dir_for_binary "$binary"
}

verify_ollama_runtime_libs() {
  local ollama_lib_dir
  ollama_lib_dir="$(ollama_runtime_lib_dir)" || {
    fail "Cannot determine Ollama runtime library directory from the installed binary."
    return 1
  }
  local llm_library=""
  if [ ! -e "${ollama_lib_dir}/libggml-base.so.0" ] && [ ! -e "${ollama_lib_dir}/libggml-base.so.0.0.0" ]; then
    fail "Ollama runtime libraries are incomplete: missing ${ollama_lib_dir}/libggml-base.so.0. Re-run the Ollama installer."
    return 1
  fi

  if ensure_nvidia_gpu_ready; then
    llm_library="$(detect_ollama_llm_library || true)"
    if [ -z "$llm_library" ]; then
      fail "No compatible Ollama CUDA runtime library found under ${ollama_lib_dir}. Re-run the Ollama installer."
      return 1
    fi
  fi
}

write_ollama_gpu_guard_script() {
  backup_path /usr/local/bin/xemi_ollama_gpu_guard.sh
  cat > /usr/local/bin/xemi_ollama_gpu_guard.sh <<'EOF'
#!/bin/bash
set -euo pipefail

STATE_DIR="/run/xemi-ai"
STAMP_FILE="${STATE_DIR}/ollama-gpu-guard.boot"
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)"

mkdir -p "$STATE_DIR"

if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi >/dev/null 2>&1; then
  exit 0
fi

for _ in $(seq 1 45); do
  pid="$(systemctl show ollama -p MainPID --value --no-pager 2>/dev/null || true)"
  if [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" -gt 0 ]; then
    logs="$(journalctl _PID="$pid" -o cat --no-pager 2>/dev/null || true)"
    if echo "$logs" | grep -q 'library=CUDA'; then
      exit 0
    fi
    if echo "$logs" | grep -q 'id=cpu library=cpu'; then
      if [ -f "$STAMP_FILE" ] && grep -Fxq "$BOOT_ID" "$STAMP_FILE"; then
        exit 0
      fi
      printf '%s\n' "$BOOT_ID" > "$STAMP_FILE"
      systemctl restart ollama
      exit 0
    fi
  fi
  sleep 2
done

exit 0
EOF
  chmod 755 /usr/local/bin/xemi_ollama_gpu_guard.sh
}

write_ollama_gpu_guard_service() {
  backup_path /etc/systemd/system/xemi-ollama-gpu-guard.service
  cat > /etc/systemd/system/xemi-ollama-gpu-guard.service <<'EOF'
[Unit]
Description=Xemi Ollama GPU Guard
After=ollama.service nvidia-persistenced.service
Requires=ollama.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/xemi_ollama_gpu_guard.sh

[Install]
WantedBy=ollama.service
EOF
}

find_ollama_binaries() {
  local found=()
  local candidates=(
    "/usr/local/bin/ollama"
    "/usr/bin/ollama"
    "/bin/ollama"
    "/opt/ollama/ollama"
    "/usr/local/sbin/ollama"
    "/usr/sbin/ollama"
  )

  for p in "${candidates[@]}"; do
    if [ -x "$p" ]; then
      found+=("$p")
    fi
  done

  if cmd_exists ollama; then
    local whichp
    whichp="$(command -v ollama)"
    if [ -n "$whichp" ] && [ -x "$whichp" ]; then
      local exists=0
      for p in "${found[@]:-}"; do
        if [ "$p" = "$whichp" ]; then exists=1; fi
      done
      if [ "$exists" -eq 0 ]; then
        found+=("$whichp")
      fi
    fi
  fi

  printf "%s\n" "${found[@]:-}"
}

choose_ollama_binary() {
  local bins
  mapfile -t bins < <(find_ollama_binaries || true)

  if [ "${#bins[@]}" -eq 0 ]; then
    echo ""
    return 1
  fi

  if [ "${#bins[@]}" -eq 1 ]; then
    echo "${bins[0]}"
    return 0
  fi

  # The list goes to stderr: callers capture stdout, which must hold only the chosen path.
  {
    echo ""
    echo "Multiple Ollama binaries detected:"
    local i=1
    for b in "${bins[@]}"; do
      echo "$i) $b"
      i=$((i+1))
    done
    echo ""
  } >&2
  local choice
  choice="$(ask "Select the Ollama binary number" "1")"
  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    echo "${bins[0]}"
    return 0
  fi
  local idx=$((choice-1))
  if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#bins[@]}" ]; then
    echo "${bins[0]}"
    return 0
  fi
  echo "${bins[$idx]}"
}

show_ollama_status_and_location() {
  header
  echo "Ollama binaries found:"
  local bins
  mapfile -t bins < <(find_ollama_binaries || true)
  if [ "${#bins[@]}" -eq 0 ]; then
    echo "None found."
  else
    for b in "${bins[@]}"; do
      echo "$b"
    done
  fi

  echo ""
  echo "Service status:"
  if [ "$(systemctl show ollama.service -p LoadState --value --no-pager 2>/dev/null || true)" = "loaded" ]; then
    systemctl status ollama --no-pager || true
    echo ""
    echo "Service environment:"
    systemctl show ollama -p Environment --no-pager || true
    echo ""
    echo "Service file path:"
    systemctl show ollama -p FragmentPath --no-pager || true
  else
    echo "ollama.service not installed."
  fi

  echo ""
  echo "Listening ports related to Ollama:"
  ss -tulpen | grep -E "(:${OLLAMA_PORT_DEFAULT}\b|ollama)" || true

  pause
}

install_ollama_official() {
  header
  local installer binary_before binary_after service_before ollama_user_before
  binary_before="$(command -v ollama || true)"
  service_before="$(systemctl show ollama.service -p LoadState --value --no-pager 2>/dev/null || true)"
  ollama_user_before="$(getent passwd ollama || true)"
  installer="$(mktemp /tmp/ollama-install.XXXXXX.sh)"
  echo "Installing Ollama using official installer..."
  if ! run_required "Downloading Ollama official installer..." curl -fsSL -o "$installer" https://ollama.com/install.sh; then
    rm -f "$installer"
    return 1
  fi
  if [ -n "$OLLAMA_INSTALL_SHA256" ]; then
    validate_sha256 "$OLLAMA_INSTALL_SHA256" || {
      fail "Invalid OLLAMA_INSTALL_SHA256. Expected 64 hexadecimal characters."
      return 1
    }
    if ! printf "%s  %s\n" "$OLLAMA_INSTALL_SHA256" "$installer" | sha256sum -c -; then
      fail "Ollama installer checksum verification failed."
      rm -f "$installer"
      return 1
    fi
    record_manifest "OLLAMA_INSTALL_SHA256" "$OLLAMA_INSTALL_SHA256"
    ok "Ollama installer checksum verified."
  else
    warn "Ollama installer checksum not configured; relying on HTTPS transport."
  fi
  chmod 700 "$installer"
  if [ -n "$OLLAMA_VERSION" ]; then
    echo "Using Ollama version: $OLLAMA_VERSION"
    if ! run_required "Running Ollama official installer..." env OLLAMA_VERSION="$OLLAMA_VERSION" sh "$installer"; then
      rm -f "$installer"
      return 1
    fi
    record_manifest "OLLAMA_VERSION" "$OLLAMA_VERSION"
  else
    if ! run_required "Running Ollama official installer..." sh "$installer"; then
      rm -f "$installer"
      return 1
    fi
  fi
  rm -f "$installer"

  # Record ownership before verifying, so purge can clean up even if verification fails.
  if [ -z "$ollama_user_before" ] && getent passwd ollama >/dev/null 2>&1; then
    record_manifest "OLLAMA_USER_CREATED_BY_XEMI" "1"
  fi
  binary_after="$(command -v ollama || true)"
  if [ -z "$binary_before" ] && [ "$service_before" != "loaded" ] && [ -n "$binary_after" ]; then
    record_manifest "OLLAMA_INSTALLED_BY_XEMI" "1"
    record_manifest "OLLAMA_BINARY_PATH" "$binary_after"
  elif [ -n "$binary_before" ] || [ "$service_before" = "loaded" ]; then
    warn "Ollama components existed before installation; purge will preserve its binary and data."
  fi
  verify_ollama_runtime_libs || { pause; return 1; }
  ok "Ollama installed."
  pause
}

default_ollama_models_dir() {
  echo "/home/${AI_USER}/.ollama/models"
}

current_ollama_models_dir() {
  local env_line
  if [ -n "${OLLAMA_MODELS_DIR:-}" ]; then
    echo "$OLLAMA_MODELS_DIR"
    return 0
  fi
  env_line="$(systemctl show ollama -p Environment --no-pager 2>/dev/null || true)"
  if echo "$env_line" | tr ' ' '\n' | grep -q '^OLLAMA_MODELS='; then
    echo "$env_line" | tr ' ' '\n' | awk -F= '/^OLLAMA_MODELS=/ {sub(/^OLLAMA_MODELS=/, ""); print; exit}'
    return 0
  fi
  default_ollama_models_dir
}

detect_ollama_llm_library() {
  local ollama_lib_dir
  ollama_lib_dir="$(ollama_runtime_lib_dir)" || return 1
  local cuda_major=""

  if cmd_exists nvidia-smi && nvidia-smi >/dev/null 2>&1; then
    cuda_major="$(nvidia-smi 2>/dev/null | sed -n 's/.*CUDA Version: \([0-9][0-9]*\).*/\1/p' | head -n 1)"
  fi

  if [ "$cuda_major" -ge 13 ] 2>/dev/null && [ -d "${ollama_lib_dir}/cuda_v13" ]; then
    echo "cuda_v13"
  elif [ -d "${ollama_lib_dir}/cuda_v12" ]; then
    echo "cuda_v12"
  elif [ -d "${ollama_lib_dir}/cuda_v13" ]; then
    echo "cuda_v13"
  else
    echo ""
  fi
}

write_ollama_override() {
  local port="$1"
  local bind_host="$2"
  local gpu_uuids="$3"
  local models_dir="${4:-}"

  local llm_library ollama_lib_dir llm_library_path
  ollama_lib_dir="$(ollama_runtime_lib_dir)" || {
    fail "Cannot determine Ollama runtime library directory."
    return 1
  }
  llm_library_path="$ollama_lib_dir"

  validate_port "$port" || { fail "Invalid Ollama port: $port"; return 1; }
  validate_bind_host "$bind_host" || { fail "Invalid Ollama bind host: $bind_host"; return 1; }
  validate_context_length "$OLLAMA_CONTEXT_LENGTH" || { fail "Invalid Ollama context length: $OLLAMA_CONTEXT_LENGTH"; return 1; }
  validate_kv_cache_type "$OLLAMA_KV_CACHE_TYPE" || { fail "Invalid Ollama K/V cache type: $OLLAMA_KV_CACHE_TYPE"; return 1; }
  if [ -n "$models_dir" ]; then
    validate_absolute_path "$models_dir" || { fail "Invalid Ollama models directory: $models_dir"; return 1; }
  fi

  llm_library="$(detect_ollama_llm_library || true)"
  if [ -n "$llm_library" ] && [ -d "$ollama_lib_dir/$llm_library" ]; then
    llm_library_path="$ollama_lib_dir/$llm_library"
  fi

  write_ollama_gpu_guard_script
  write_ollama_gpu_guard_service
  backup_path /etc/systemd/system/ollama.service.d
  mkdir -p /etc/systemd/system/ollama.service.d
  cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Unit]
StartLimitIntervalSec=0
Wants=nvidia-persistenced.service
Wants=network-online.target
After=network-online.target systemd-modules-load.service nvidia-persistenced.service

[Service]
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="LD_LIBRARY_PATH=${llm_library_path}:${ollama_lib_dir}"
TimeoutStartSec=7min
Restart=on-failure
RestartSec=10s
Environment="OLLAMA_HOST=${bind_host}:${port}"
EOF
  if [ -n "$gpu_uuids" ]; then
    cat >> /etc/systemd/system/ollama.service.d/override.conf <<'EOF'
ExecStartPre=/bin/sh -c 'for i in $(seq 1 180); do if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then exit 0; fi; echo "Waiting for NVIDIA GPU... ($i/180)"; sleep 2; done; echo "NVIDIA GPU was not ready after 360 seconds"; exit 1'
EOF
  fi
  if [ -n "$llm_library" ]; then
    cat >> /etc/systemd/system/ollama.service.d/override.conf <<EOF
Environment="OLLAMA_LLM_LIBRARY=${llm_library}"
EOF
  fi
  cat >> /etc/systemd/system/ollama.service.d/override.conf <<EOF
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_CONTEXT_LENGTH=${OLLAMA_CONTEXT_LENGTH}"
Environment="OLLAMA_KV_CACHE_TYPE=${OLLAMA_KV_CACHE_TYPE}"
Environment="OLLAMA_GPU_OVERHEAD=268435456"
Environment="OLLAMA_LOAD_TIMEOUT=10m"
Environment="OLLAMA_KEEP_ALIVE=30m"
User=${AI_USER}
Group=${AI_GROUP}
NoNewPrivileges=true
PrivateTmp=true
ProtectControlGroups=true
ProtectKernelModules=true
ProtectKernelTunables=true
RestrictSUIDSGID=true
EOF
  if [ -n "$models_dir" ]; then
    cat >> /etc/systemd/system/ollama.service.d/override.conf <<EOF
Environment="OLLAMA_MODELS=${models_dir}"
EOF
  fi
}

configure_ollama_service_lan() {
  header
  load_manifest
  local port
  local bind_host
  local gpu_uuids=""
  local models_dir="${OLLAMA_MODELS_DIR:-}"
  if [ "$OLLAMA_MODELS_DIR_FROM_CLI" = "1" ]; then
    models_dir=""
  fi
  port="$(ask_port "Ollama port" "$OLLAMA_PORT_DEFAULT")"
  bind_host="$(ask "Ollama bind host" "$OLLAMA_BIND_HOST")"
  if ! validate_bind_host "$bind_host"; then
    fail "Invalid Ollama bind host. Use an IP address or DNS-safe host name."
    pause
    return 1
  fi

  ensure_ai_user
  if ensure_nvidia_gpu_ready; then
    gpu_uuids="$(nvidia_gpu_uuids || true)"
    enable_nvidia_persistence
  elif [ "$ALLOW_CPU_FALLBACK" = "1" ]; then
    warn "Ollama will be configured without confirmed GPU because ALLOW_CPU_FALLBACK=1."
  else
    fail "GPU is required for this installer goal. Re-run after NVIDIA drivers are working, or set ALLOW_CPU_FALLBACK=1."
    pause
    return 1
  fi

  if [ -n "$models_dir" ]; then
    validate_absolute_path "$models_dir" || {
      fail "Invalid Ollama models directory: $models_dir"
      pause
      return 1
    }
    mkdir -p "$models_dir"
    chown -R "$AI_USER:$AI_GROUP" "$models_dir"
    record_manifest "OLLAMA_MODELS_DIR" "$models_dir"
  fi

  write_ollama_override "$port" "$bind_host" "$gpu_uuids" "$models_dir"
  if [ -n "$gpu_uuids" ]; then
    record_manifest "NVIDIA_GPU_UUIDS" "$gpu_uuids"
  fi

  record_manifest "OLLAMA_OVERRIDE_CREATED" "1"
  record_manifest "OLLAMA_PORT" "$port"
  record_manifest "OLLAMA_BIND_HOST" "$bind_host"
  record_manifest "OLLAMA_CONTEXT_LENGTH" "$OLLAMA_CONTEXT_LENGTH"
  record_manifest "OLLAMA_KV_CACHE_TYPE" "$OLLAMA_KV_CACHE_TYPE"
  OLLAMA_PORT="$port"
  OLLAMA_BIND_HOST="$bind_host"
  systemctl daemon-reload
  systemctl enable ollama >/dev/null 2>&1
  systemctl enable xemi-ollama-gpu-guard.service >/dev/null 2>&1
  systemctl restart ollama
  ensure_ollama_uses_gpu 1 || {
    pause
    return 1
  }

  ok "Ollama service configured on ${bind_host}:${port}."
  pause
}

configure_ollama_models_dir() {
  header
  echo "Configure Ollama model storage directory"
  echo ""
  ensure_ai_user
  load_manifest

  local current_dir
  local new_dir
  local old_resolved
  local new_resolved
  local port="${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}"
  local bind_host="${OLLAMA_BIND_HOST:-0.0.0.0}"
  local gpu_uuids="${NVIDIA_GPU_UUIDS:-}"
  local bin

  current_dir="$(current_ollama_models_dir)"
  echo "Current/default model directory: ${current_dir}"
  echo ""
  new_dir="$(ask_absolute_path "New Ollama models directory" "$current_dir")"

  old_resolved="$(realpath -m -- "$current_dir")"
  new_resolved="$(realpath -m -- "$new_dir")"
  if [ "$old_resolved" = "$new_resolved" ]; then
    ok "Ollama is already configured for this model directory."
    pause
    return 0
  fi
  if [[ "$new_resolved" = "$old_resolved"/* ]] || [[ "$old_resolved" = "$new_resolved"/* ]]; then
    fail "Refusing migration where old and new directories contain each other."
    pause
    return 1
  fi

  mkdir -p "$new_resolved"
  chown -R "$AI_USER:$AI_GROUP" "$new_resolved"
  echo ""
  echo "Target filesystem:"
  df -h "$new_resolved" || true
  if ! sudo -u "$AI_USER" test -w "$new_resolved"; then
    fail "AI user cannot write to model directory: $new_resolved"
    pause
    return 1
  fi

  if [ -d "$old_resolved" ] && [ -n "$(find "$old_resolved" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    echo ""
    echo "Existing model data found at: $old_resolved"
    local migrate
    migrate="$(ask "Migrate existing model data to the new directory yes or no" "yes")"
    if is_yes "$migrate"; then
      echo "Stopping Ollama before migration..."
      systemctl stop ollama >/dev/null 2>&1 || true
      echo "Copying model data. This may take a while..."
      cp -a "$old_resolved"/. "$new_resolved"/
      chown -R "$AI_USER:$AI_GROUP" "$new_resolved"
      ok "Model data copied to: $new_resolved"

      local remove_old
      remove_old="$(ask "Remove old model directory after successful copy yes or no" "no")"
      if is_yes "$remove_old"; then
        if safe_rm_rf "$old_resolved" "$(dirname "$old_resolved")"; then
          ok "Old model directory removed: $old_resolved"
        else
          warn "Old model directory was kept because its path did not pass the safety check: $old_resolved"
        fi
      fi
    fi
  fi

  if ensure_nvidia_gpu_ready; then
    gpu_uuids="$(nvidia_gpu_uuids || true)"
  fi

  write_ollama_override "$port" "$bind_host" "$gpu_uuids" "$new_resolved"
  record_manifest "OLLAMA_OVERRIDE_CREATED" "1"
  record_manifest "OLLAMA_PORT" "$port"
  record_manifest "OLLAMA_BIND_HOST" "$bind_host"
  record_manifest "OLLAMA_CONTEXT_LENGTH" "$OLLAMA_CONTEXT_LENGTH"
  record_manifest "OLLAMA_KV_CACHE_TYPE" "$OLLAMA_KV_CACHE_TYPE"
  record_manifest "OLLAMA_MODELS_DIR" "$new_resolved"
  if [ -n "$gpu_uuids" ]; then
    record_manifest "NVIDIA_GPU_UUIDS" "$gpu_uuids"
  fi
  OLLAMA_MODELS_DIR="$new_resolved"

  systemctl daemon-reload
  systemctl enable ollama >/dev/null 2>&1
  systemctl enable xemi-ollama-gpu-guard.service >/dev/null 2>&1
  systemctl restart ollama
  ensure_ollama_uses_gpu 1 || {
    pause
    return 1
  }

  echo "Testing Ollama with new model directory..."
  sleep 3
  if curl -fsS "http://127.0.0.1:${port}/api/tags" >/dev/null 2>&1; then
    ok "Ollama API responds using model directory: $new_resolved"
  else
    fail "Ollama API did not respond after changing model directory."
    journalctl -u ollama -n 80 --no-pager || true
    pause
    return 1
  fi

  if bin="$(choose_ollama_binary)"; then
    sudo -u "$AI_USER" "$bin" list || "$bin" list || true
  fi

  pause
}

ollama_health_check() {
  header
  local port
  port="$(ask_port "Ollama port" "$OLLAMA_PORT_DEFAULT")"
  if curl -fsS "http://127.0.0.1:${port}/api/tags" >/dev/null; then
    ok "Ollama API responding on localhost."
  else
    fail "Ollama API not responding."
  fi
  pause
}

list_ollama_models() {
  header
  local bin
  if ! bin="$(choose_ollama_binary)"; then
    fail "Ollama binary not found."
    pause
    return 1
  fi
  echo "Using: $bin"
  echo ""
  sudo -u "$AI_USER" "$bin" list || "$bin" list || true
  pause
}

test_ollama_model_interaction() {
  header
  local bin
  if ! bin="$(choose_ollama_binary)"; then
    fail "Ollama binary not found."
    pause
    return 1
  fi

  local models
  models="$({ sudo -u "$AI_USER" "$bin" list 2>/dev/null || "$bin" list 2>/dev/null; } | awk 'NR>1 {print $1}' | sed '/^$/d')"
  if [ -z "$models" ]; then
    fail "No Ollama models installed to test."
    pause
    return 1
  fi

  echo "Installed models:"
  printf '  %s\n' $models
  echo ""
  local model
  model="$(ask "Model to test" "$(printf '%s\n' $models | head -n 1)")"
  if [ -z "$model" ]; then
    fail "No model selected."
    pause
    return 1
  fi

  local prompt
  prompt="$(ask "Prompt to send to model" "Describe en una frase breve quÃƒÂ© hace este modelo.")"
  if [ -z "$prompt" ]; then
    prompt="Describe en una frase breve quÃƒÂ© hace este modelo."
  fi

  local stream_answer
  stream_answer="$(ask "Stream response live? yes or no" "no")"
  if ! [[ "$stream_answer" =~ ^([Yy][Ee][Ss]|[Yy]|[Ss][Ii]|[Ss])$ ]]; then
    stream_answer="no"
  fi
  local stream_mode="no"
  if [[ "$stream_answer" =~ ^([Yy][Ee][Ss]|[Yy]|[Ss][Ii]|[Ss])$ ]]; then
    stream_mode="yes"
  fi

  load_manifest
  local port="${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}"
  local host="127.0.0.1"
  local gpu_status="unknown"
  local gpu_info=""
  if cmd_exists nvidia-smi && nvidia-smi >/dev/null 2>&1; then
    gpu_status="ready"
    gpu_info="$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null | sed 's/^/  /')"
  else
    gpu_status="not ready"
  fi

  echo "== Resumen de prueba =="
  echo "Modelo: $model"
  echo "Prompt: $prompt"
  echo "Modo de stream: $stream_mode"
  echo "Puerto de Ollama: $port"
  echo "Estado GPU: $gpu_status"
  if [ -n "$gpu_info" ]; then
    echo "Detalles de GPU:"
    echo "$gpu_info"
  fi
  echo ""

  local start_ms end_ms elapsed_ms
  local payload_file
  local response_file
  payload_file="$(mktemp)"
  response_file="$(mktemp)"
  local stream_flag
  if [[ "$stream_answer" =~ ^([Yy][Ee][Ss]|[Yy]|[Ss][Ii]|[Ss])$ ]]; then
    stream_flag=true
  else
    stream_flag=false
  fi

  if cmd_exists python3; then
    python3 -c 'import json,sys; stream = sys.argv[3].lower() in ("true", "1", "yes", "y"); json.dump({"model": sys.argv[1], "prompt": sys.argv[2], "stream": stream}, sys.stdout)' "$model" "$prompt" "$stream_flag" > "$payload_file"
  elif cmd_exists python; then
    python -c 'import json,sys; stream = sys.argv[3].lower() in ("true", "1", "yes", "y"); json.dump({"model": sys.argv[1], "prompt": sys.argv[2], "stream": stream}, sys.stdout)' "$model" "$prompt" "$stream_flag" > "$payload_file"
  else
    printf '{"model":"%s","prompt":"%s","stream":%s}' "$(printf '%s' "$model" | json_escape)" "$(printf '%s' "$prompt" | json_escape)" "$stream_flag" > "$payload_file"
  fi

  echo "Enviando solicitud a Ollama; puede tardar si el modelo es grande."
  echo "Si el servicio estÃƒÂ¡ cargando el modelo o generando, espere por favor."

  start_ms="$(date +%s%3N)"
  local response
  local raw_response
  raw_response=""
  local rc=0
  if [ "$stream_flag" = true ]; then
    echo "Live stream enabled; chunks will appear as they arrive."
    set +e
    if cmd_exists stdbuf; then
      stdbuf -oL curl -S -N -m 300 --connect-timeout 10 -X POST "http://${host}:${port}/api/generate" -H 'Content-Type: application/json' --data-binary @"$payload_file" | tee "$response_file"
    else
      curl -S -N -m 300 --connect-timeout 10 -X POST "http://${host}:${port}/api/generate" -H 'Content-Type: application/json' --data-binary @"$payload_file" | tee "$response_file"
    fi
    rc=$?
    set -e
    raw_response="$(cat "$response_file" 2>/dev/null || true)"
    response="$raw_response"
  else
    echo "Esperando a que el modelo devuelva una respuesta completa..."
    response="$(curl -sS -m 300 --connect-timeout 10 -X POST "http://${host}:${port}/api/generate" -H 'Content-Type: application/json' --data-binary @"$payload_file" 2>&1)" || rc=$?
    raw_response="$response"
  fi

  end_ms="$(date +%s%3N)"
  elapsed_ms=$((end_ms - start_ms))
  rm -f "$payload_file" "$response_file"

  local error_message=""
  local model_output=""
  local usage=""
  local latency=""
  local done_reason=""
  local created_at=""
  local total_duration=""
  local load_duration=""
  local prompt_eval_duration=""
  local eval_duration=""
  if cmd_exists jq; then
    if [ "$stream_flag" = true ]; then
      response="$(printf '%s\n' "$raw_response" | jq -R -s 'split("\n") | map(select(length > 0) | fromjson? ) | last' 2>/dev/null || true)"
    fi
    if [ -n "$response" ]; then
      error_message="$(printf '%s' "$response" | jq -r '.error? // empty' 2>/dev/null || true)"
      model_output="$(printf '%s' "$response" | jq -r '.response? // empty' 2>/dev/null || true)"
      done_reason="$(printf '%s' "$response" | jq -r '.done_reason? // empty' 2>/dev/null || true)"
      created_at="$(printf '%s' "$response" | jq -r '.created_at? // empty' 2>/dev/null || true)"
      total_duration="$(printf '%s' "$response" | jq -r '.total_duration? // empty' 2>/dev/null || true)"
      load_duration="$(printf '%s' "$response" | jq -r '.load_duration? // empty' 2>/dev/null || true)"
      prompt_eval_duration="$(printf '%s' "$response" | jq -r '.prompt_eval_duration? // empty' 2>/dev/null || true)"
      eval_duration="$(printf '%s' "$response" | jq -r '.eval_duration? // empty' 2>/dev/null || true)"
      usage="$(printf '%s' "$response" | jq -r 'if has("usage") then "prompt_tokens: \(.usage.prompt_tokens // \"n/a\"), completion_tokens: \(.usage.completion_tokens // \"n/a\"), total_tokens: \(.usage.total_tokens // \"n/a\")" elif (has("total_duration") or has("load_duration") or has("prompt_eval_duration") or has("eval_duration")) then "total_duration: \(.total_duration // \"n/a\"), load_duration: \(.load_duration // \"n/a\"), prompt_eval_duration: \(.prompt_eval_duration // \"n/a\"), eval_duration: \(.eval_duration // \"n/a\")" else empty end' 2>/dev/null || true)"
      latency="$(printf '%s' "$response" | jq -r '.latency? // empty' 2>/dev/null || true)"
    fi
  fi

  if [ "$rc" -ne 0 ] || [ -n "$error_message" ]; then
    if [ -n "$error_message" ]; then
      fail "Model test request failed: $error_message"
    else
      fail "Model test request failed with curl exit code $rc."
    fi
    echo "Response output:"
    if [ -n "$raw_response" ]; then
      echo "$raw_response" | sed 's/^/  /'
    else
      echo "  <no response>"
    fi
    pause
    return 1
  fi

  local inference_device="unknown"
  if cmd_exists journalctl; then
    local olog
    olog="$(journalctl -u ollama -n 50 --no-pager 2>/dev/null || true)"
    if printf '%s' "$olog" | grep -Eiq 'cuda|nvidia|ggml_cuda|cublas|cuda_compute|gpu'; then
      inference_device="GPU"
    elif printf '%s' "$olog" | grep -Eiq 'CPU|cpu'; then
      inference_device="CPU"
    fi
  fi

  echo "== Resultado de la prueba =="
  echo "Tiempo transcurrido: ${elapsed_ms} ms"
  echo "Modo de stream: $stream_mode"
  echo "Dispositivo de inferencia estimado: $inference_device"
  if [ -n "$model_output" ]; then
    echo "Respuesta del modelo:"
    echo "$model_output" | sed 's/^/  /'
    echo ""
  fi
  if [ -n "$done_reason" ]; then
    echo "Motivo de finalizaciÃƒÂ³n: $done_reason"
  fi
  if [ -n "$created_at" ]; then
    echo "Creado en: $created_at"
  fi
  if [ -n "$usage" ]; then
    echo "Resumen de uso: $usage"
  fi
  if [ -n "$latency" ]; then
    echo "Latencia reportada: $latency"
  fi
  echo "Respuesta cruda:"
  if [ -n "$raw_response" ]; then
    echo "$raw_response" | sed 's/^/  /'
  else
    echo "  <respuesta vacÃƒÂ­a>"
  fi
  echo ""

  if cmd_exists journalctl; then
    echo ""
    echo "Registros recientes de Ollama para seÃƒÂ±ales GPU/CPU:"
    if journalctl -u ollama -n 50 --no-pager 2>/dev/null | grep -Eiq 'cuda|nvidia|gpu|ggml_cuda|library=cuda|compute'; then
      journalctl -u ollama -n 50 --no-pager 2>/dev/null | tail -n 20 | sed 's/^/  /'
    else
      echo "  No se encontraron seÃƒÂ±ales explÃƒÂ­citas de CUDA/GPU en las ÃƒÂºltimas 50 lÃƒÂ­neas del registro de Ollama."
    fi
  fi

  pause
}

remove_ollama_models_interactive() {
  header
  local bin
  if ! bin="$(choose_ollama_binary)"; then
    fail "Ollama binary not found."
    pause
    return 1
  fi

  echo "Using: $bin"
  echo ""
  echo "Models:"
  sudo -u "$AI_USER" "$bin" list || "$bin" list || true
  echo ""
  echo "Enter model names separated by spaces, or type ALL to remove everything."
  local targets
  targets="$(ask "Models to remove" "")"

  if [ -z "$targets" ]; then
    warn "No models selected."
    pause
    return 0
  fi

  if [[ "$targets" = "ALL" ]]; then
    local models
    models="$(sudo -u "$AI_USER" "$bin" list 2>/dev/null || "$bin" list 2>/dev/null || true)"
    echo "$models" | awk 'NR>1 {print $1}' | while read -r m; do
      [ -z "$m" ] && continue
      sudo -u "$AI_USER" "$bin" rm "$m" 2>/dev/null || "$bin" rm "$m" 2>/dev/null || true
    done
    ok "All models removed (best effort)."
    pause
    return 0
  fi

  for m in $targets; do
    sudo -u "$AI_USER" "$bin" rm "$m" 2>/dev/null || "$bin" rm "$m" 2>/dev/null || true
  done
  ok "Selected models removed (best effort)."
  pause
}

# True when Ollama already has MODEL (name:tag as shown by `ollama list`).
ollama_has_model() {
  curl -fsS --max-time 5 "http://127.0.0.1:${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}/api/tags" 2>/dev/null \
    | jq -e --arg m "$1" '.models | any(.name == $m)' >/dev/null 2>&1
}

# Pulls MODEL as the AI user, falling back to the current user.
pull_ollama_model() {
  local model="$1"
  local bin
  bin="$(choose_ollama_binary)" || { fail "Ollama binary not found."; return 1; }
  echo "Pulling model: $model"
  if sudo -u "$AI_USER" "$bin" pull "$model"; then
    return 0
  fi
  warn "Pull as ${AI_USER} failed for ${model}; retrying as current user."
  "$bin" pull "$model"
}

recommend_and_install_models() {
  header
  if [ "$ASSUME_YES" = "1" ]; then
    ok "Skipping optional model downloads in unattended mode. Use the menu to choose models."
    return 0
  fi
  local bin
  if ! bin="$(choose_ollama_binary)"; then
    fail "Ollama binary not found."
    pause
    return 1
  fi

  local vram="0"
  if cmd_exists nvidia-smi; then
    vram="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1 | tr -d ' ' || echo 0)"
  fi

  echo "Using: $bin"
  echo ""
  echo "Detected VRAM: ${vram} MB"
  echo ""

  local options=()
  if [ "$vram" -ge 11000 ]; then
    options+=("mistral llama3 phi3")
    options+=("mistral deepseek-coder phi3")
    options+=("phi3 mistral")
    options+=("skip")
    options+=("custom")
  elif [ "$vram" -ge 8000 ]; then
    options+=("mistral phi3")
    options+=("phi3")
    options+=("skip")
    options+=("custom")
  else
    options+=("phi3")
    options+=("skip")
    options+=("custom")
  fi

  echo "Choose model set:"
  local i=1
  for o in "${options[@]}"; do
    if [ "$o" = "skip" ]; then
      echo "$i) Do not install models now"
    else
      echo "$i) $o"
    fi
    i=$((i+1))
  done
  echo ""

  local choice
  choice="$(ask "Selection number" "1")"
  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    warn "Invalid selection. Using option 1."
    choice=1
  fi
  local idx=$((choice-1))
  if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#options[@]}" ]; then
    idx=0
  fi

  local selected="${options[$idx]}"
  if [ "$selected" = "skip" ]; then
    ok "Model installation skipped."
    pause
    return 0
  fi

  if [ "$selected" = "custom" ]; then
    selected="$(ask "Enter model names separated by spaces" "mistral phi3")"
  fi

  echo ""
  echo "Installing: $selected"
  echo ""

  # The small Open WebUI task model (titles, tags, search queries) comes with every set.
  if ! ollama_has_model "$OPENWEBUI_TASK_MODEL" && [[ " $selected " != *" $OPENWEBUI_TASK_MODEL "* ]]; then
    selected="$selected $OPENWEBUI_TASK_MODEL"
    echo "Adding ${OPENWEBUI_TASK_MODEL} for Open WebUI background tasks (about 0.4 GB)."
    echo ""
  fi

  for m in $selected; do
    echo "Pulling model: $m"
    if ! sudo -u "$AI_USER" "$bin" pull "$m"; then
      warn "Pull as ${AI_USER} failed for ${m}; retrying as current user."
      "$bin" pull "$m" || warn "Could not pull model: $m"
    fi
    echo ""
  done

  ok "Model installation completed (best effort)."
  pause
}

remove_ollama_by_location() {
  header
  local bins
  mapfile -t bins < <(find_ollama_binaries || true)

  if [ "${#bins[@]}" -eq 0 ]; then
    warn "No Ollama binaries found."
    pause
    return 0
  fi

  echo "Detected Ollama binaries:"
  local i=1
  for b in "${bins[@]}"; do
    echo "$i) $b"
    i=$((i+1))
  done
  echo ""
  echo "Select numbers to remove separated by spaces, or type ALL to remove all binaries listed."
  local selection
  selection="$(ask "Selection" "")"

  echo ""
  echo "Stopping services..."
  stop_disable_service ollama

  if [[ "$selection" = "ALL" ]]; then
    for b in "${bins[@]}"; do
      rm -f "$b" || true
    done
    ok "Removed all detected Ollama binaries."
  else
    for s in $selection; do
      if [[ "$s" =~ ^[0-9]+$ ]]; then
        local idx=$((s-1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#bins[@]}" ]; then
          rm -f "${bins[$idx]}" || true
        fi
      fi
    done
    ok "Removed selected binaries (best effort)."
  fi

  echo ""
  echo "Optional cleanup:"
  echo "1) Keep model data"
  echo "2) Remove model data and caches"
  echo ""
  local c
  c="$(ask "Choose cleanup option" "1")"
  if [ "$c" = "2" ]; then
    safe_rm_rf "/usr/local/lib/ollama" /usr/local/lib || true
    safe_rm_rf "/usr/share/ollama" /usr/share || true
    safe_rm_rf "/var/lib/ollama" /var/lib || true
    safe_rm_rf "/home/${AI_USER}/.ollama" /home || true
    safe_rm_rf "/root/.ollama" /root || true
    ok "Model data removed (best effort)."
  else
    ok "Model data kept."
  fi

  echo ""
  echo "Removing service overrides and unit if present..."
  backup_path /etc/systemd/system/ollama.service.d
  backup_path /etc/systemd/system/ollama.service
  safe_rm_rf /etc/systemd/system/ollama.service.d /etc/systemd/system || true
  rm -f /etc/systemd/system/ollama.service || true
  systemctl daemon-reload || true

  pause
}

# Context length and K/V cache type for every model Ollama loads.
tune_ollama_memory() {
  header
  load_manifest
  local current_ctx current_kv context kv ans
  current_ctx="$(systemctl show ollama -p Environment --value 2>/dev/null | tr ' ' '\n' | sed -n 's/^OLLAMA_CONTEXT_LENGTH=//p')"
  current_kv="$(systemctl show ollama -p Environment --value 2>/dev/null | tr ' ' '\n' | sed -n 's/^OLLAMA_KV_CACHE_TYPE=//p')"
  echo "Model memory settings (apply to every model unless a chat or model sets num_ctx):"
  echo ""
  echo "  Context length now: ${current_ctx:-Ollama default (4096 on this GPU)}   recommended: ${OLLAMA_CONTEXT_LENGTH_DEFAULT}"
  echo "  K/V cache now:      ${current_kv:-f16 (Ollama default)}   recommended: ${OLLAMA_KV_CACHE_TYPE_DEFAULT}"
  echo ""
  echo "Longer context lets web search results and documents fit in one request, but each"
  echo "loaded model uses more VRAM. q8_0 halves the K/V cache with negligible quality loss;"
  echo "q4_0 saves more but can lower answer quality. Keep each model under the free VRAM:"
  echo "a model that does not fit runs partly on the CPU and becomes much slower."
  echo ""

  while true; do
    context="$(ask "Context length (2048-262144)" "$OLLAMA_CONTEXT_LENGTH")"
    validate_context_length "$context" && break
    warn "Use a number from 2048 to 262144, for example 8192, 16384 or 32768." >&2
  done
  while true; do
    kv="$(ask "K/V cache type (f16, q8_0, q4_0)" "$OLLAMA_KV_CACHE_TYPE")"
    validate_kv_cache_type "$kv" && break
    warn "Use f16, q8_0 or q4_0." >&2
  done

  if [ "$context" = "$current_ctx" ] && [ "$kv" = "$current_kv" ]; then
    ok "Ollama already uses these settings."
    pause
    return 0
  fi
  warn "Applying restarts Ollama: loaded models are unloaded and chats in progress are interrupted."
  ans="$(confirm_proceed "Apply and restart Ollama yes or no" "yes")"
  if ! is_yes "$ans"; then
    warn "Cancelled."
    pause
    return 0
  fi

  OLLAMA_CONTEXT_LENGTH="$context"
  OLLAMA_KV_CACHE_TYPE="$kv"
  repair_ollama_service_override
  if wait_http_ok "http://127.0.0.1:${OLLAMA_PORT:-$OLLAMA_PORT_DEFAULT}/api/tags" 60; then
    ok "Ollama restarted with context ${context} and K/V cache ${kv}."
    echo "Check VRAM per model after the next chat in Services > GPU usage."
  else
    fail "Ollama does not respond after the restart. Check: journalctl -u ollama -e"
  fi
  pause
}
