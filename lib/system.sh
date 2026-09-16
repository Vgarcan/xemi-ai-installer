# Host preparation, repositories, users, and NVIDIA driver setup.

preflight_supported_system() {
  local distro="unknown"
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    distro="${PRETTY_NAME:-${ID:-unknown}}"
  fi

  if ! cmd_exists dnf; then
    fail "dnf not found. This installer currently supports RHEL/Alma/Rocky/Fedora-like systems."
    return 1
  fi

  if ! cmd_exists systemctl; then
    fail "systemctl not found. This installer requires systemd."
    return 1
  fi

  ok "Supported system checks passed: ${distro}"
}

rpmfusion_release_urls() {
  local fedora_ver=""
  local rhel_ver=""

  fedora_ver="$(rpm -E %fedora 2>/dev/null || true)"
  if [[ "$fedora_ver" =~ ^[0-9]+$ ]]; then
    printf "%s\n" \
      "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" \
      "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm"
    return 0
  fi

  rhel_ver="$(rpm -E %rhel 2>/dev/null || true)"
  if [[ "$rhel_ver" =~ ^[0-9]+$ ]]; then
    printf "%s\n" \
      "https://download1.rpmfusion.org/free/el/rpmfusion-free-release-${rhel_ver}.noarch.rpm" \
      "https://download1.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-${rhel_ver}.noarch.rpm"
    return 0
  fi

  return 1
}

ensure_base_tools() {
  header
  echo "Installing base tools..."
  run_required "Installing base tools with dnf..." dnf install -y curl wget git firewalld nano tar gzip zstd jq bc pciutils util-linux coreutils procps-ng
  run_optional "Installing optional diagnostic tool htop..." dnf install -y htop || true
  run_optional "Enabling firewalld..." systemctl enable firewalld || true
  run_optional "Starting firewalld..." systemctl start firewalld || true
  ok "Base tools ready."
  pause
}

ensure_ai_user() {
  header
  echo "Ensuring user and group..."
  if ! validate_identity "$AI_USER" || ! validate_identity "$AI_GROUP"; then
    fail "Invalid AI_USER or AI_GROUP. Use Linux-safe names like aiuser."
    pause
    return 1
  fi
  if ! getent group "$AI_GROUP" >/dev/null 2>&1; then
    groupadd -f "$AI_GROUP"
    record_manifest "AI_GROUP_CREATED" "1"
  fi
  if ! id "$AI_USER" >/dev/null 2>&1; then
    useradd -m -g "$AI_GROUP" -s /bin/bash "$AI_USER"
    record_manifest "AI_USER_CREATED" "1"
  fi
  if getent group render >/dev/null 2>&1; then
    usermod -a -G render "$AI_USER" || true
  fi
  if getent group video >/dev/null 2>&1; then
    usermod -a -G video "$AI_USER" || true
  fi
  record_manifest "AI_USER" "$AI_USER"
  record_manifest "AI_GROUP" "$AI_GROUP"
  ok "User ready: $AI_USER"
  pause
}

enable_repos() {
  header
  echo "Enabling repositories..."
  local rpmfusion_urls=()
  mapfile -t rpmfusion_urls < <(rpmfusion_release_urls)
  if [ "${#rpmfusion_urls[@]}" -ne 2 ]; then
    fail "Could not determine Fedora/RHEL release version for RPM Fusion."
    pause
    return 1
  fi
  if [[ "$(rpm -E %rhel 2>/dev/null || true)" =~ ^[0-9]+$ ]]; then
    run_required "Installing EPEL release..." dnf install -y epel-release
  else
    warn "Skipping EPEL release package on non-RHEL platform."
  fi
  run_required "Installing RPM Fusion free release..." dnf install -y "${rpmfusion_urls[0]}"
  run_required "Installing RPM Fusion nonfree release..." dnf install -y "${rpmfusion_urls[1]}"
  ok "Repositories ready."
  pause
}

install_nvidia_drivers() {
  header
  echo "Installing NVIDIA drivers and CUDA runtime..."
  run_required "Installing NVIDIA packages..." dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
  enable_nvidia_persistence
  ok "NVIDIA packages installed."
  local ans
  if [ "$ASSUME_YES" = "1" ] && [ "$AUTO_REBOOT" != "1" ]; then
    ans="no"
    warn "Automatic reboot skipped. Use --reboot to allow reboot in --yes mode."
  else
    ans="$(ask "Reboot now (recommended) yes or no" "yes")"
  fi
  if is_yes "$ans"; then
    log "Reboot requested"
    reboot
  fi
  pause
}

gpu_info_and_recommendations() {
  header
  if ! cmd_exists nvidia-smi; then
    fail "nvidia-smi not found."
    pause
    return 1
  fi
  if ! nvidia-smi; then
    fail "nvidia-smi failed."
    pause
    return 1
  fi

  local vram
  vram="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1 | tr -d ' ')"
  echo ""
  echo -e "${YELLOW}VRAM detected: ${vram} MB${NC}"
  echo ""

  echo "Recommended model sets:"
  if [ "$vram" -ge 11000 ]; then
    echo "1) General RPA: mistral, llama3, phi3"
    echo "2) Coding RPA: mistral, deepseek-coder, phi3"
    echo "3) Minimal: phi3, mistral"
    echo "4) Custom selection"
  elif [ "$vram" -ge 8000 ]; then
    echo "1) General: mistral, phi3"
    echo "2) Minimal: phi3"
    echo "3) Custom selection"
  else
    echo "1) Minimal: phi3"
    echo "2) Custom selection"
  fi

  pause
}

