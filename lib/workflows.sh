# High-level installation, repair, and bootstrap flows.

repair_existing_installation() {
  header
  echo "Existing installation detected. Repairing system with GPU prioritized."
  load_manifest
  ensure_ai_user

  if ! ensure_nvidia_gpu_ready; then
    if [ "$ALLOW_CPU_FALLBACK" = "1" ]; then
      warn "NVIDIA GPU is not ready; continuing because ALLOW_CPU_FALLBACK=1."
    else
      warn "NVIDIA GPU is not ready. Installing NVIDIA drivers now."
      install_nvidia_drivers
      if ! ensure_nvidia_gpu_ready; then
        fail "NVIDIA GPU is still not ready. Reboot, then run: $0 install"
        pause
        return 1
      fi
    fi
  fi

  if ensure_nvidia_gpu_ready; then
    enable_nvidia_persistence
  fi
  repair_ollama_installation
  repair_openwebui_installation
  if [ -z "${FIREWALL_CONFIGURED:-}" ]; then
    warn "Firewall rules not present or not recorded; configuring firewall."
    configure_firewall_lan_only
  fi
  doctor
}

full_install_drivers() {
  header
  echo "Stage 1, drivers and reboot"
  local ans
  ans="$(confirm_proceed "Proceed yes or no" "yes")"
  if ! is_yes "$ans"; then
    warn "Cancelled."
    pause
    return 0
  fi
  preflight_supported_system
  ensure_base_tools
  enable_repos
  install_nvidia_drivers
}

full_install_stack() {
  header
  echo "Stage 2, AI stack"
  local ans
  ans="$(confirm_proceed "Proceed yes or no" "yes")"
  if ! is_yes "$ans"; then
    warn "Cancelled."
    pause
    return 0
  fi
  preflight_supported_system
  ensure_base_tools
  ensure_ai_user
  install_ollama_official
  configure_ollama_service_lan
  if [ -n "${OLLAMA_MODELS_DIR:-}" ]; then
    configure_ollama_models_dir
  fi
  recommend_and_install_models
  install_openwebui
  configure_firewall_lan_only
  doctor
  ok "AI stack installed."
  pause
}

full_new_server_setup() {
  header
  echo "Full new server setup"
  echo "This will prepare repositories/tools, ensure NVIDIA GPU readiness, install Ollama, Open WebUI, autostart services, models and firewall rules."
  local ans existing_action
  ans="$(confirm_proceed "Proceed yes or no" "yes")"
  if ! is_yes "$ans"; then
    warn "Cancelled."
    pause
    return 0
  fi

  preflight_supported_system
  ensure_base_tools
  enable_repos

  if ! ensure_nvidia_gpu_ready; then
    if [ "$ALLOW_CPU_FALLBACK" = "1" ]; then
      warn "NVIDIA GPU is not ready; continuing because ALLOW_CPU_FALLBACK=1."
    else
      warn "NVIDIA GPU is not ready. Installing NVIDIA drivers now."
      install_nvidia_drivers
      if ! ensure_nvidia_gpu_ready; then
        fail "NVIDIA GPU is still not ready. Reboot, then run: $0 install"
        pause
        return 1
      fi
    fi
  fi

  if has_existing_installation; then
    echo ""
    echo "Existing installation detected."
    echo "1) Exit without changes"
    echo "2) Repair and verify the existing installation"
    existing_action="$(ask "Choose 1 or 2" "2")"
    case "$existing_action" in
      1)
        warn "No changes made."
        pause
        return 0
        ;;
      2)
        ok "Running repair and integrity checks instead of a full reinstall."
        repair_existing_installation
        ;;
      *)
        warn "Invalid choice. No changes made."
        pause
        return 0
        ;;
    esac
  else
    full_install_stack
  fi
}
