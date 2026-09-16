# Interactive menu, command-line parsing, and command dispatch.

show_dry_run_plan() {
  local cmd="$1"
  echo "Dry run for command: ${cmd}"
  echo ""
  echo "No packages, services, files, firewall rules or users will be changed."
  echo ""
  echo "Resolved settings:"
  echo "  AI user/group: ${AI_USER}:${AI_GROUP}"
  echo "  Ollama port: ${OLLAMA_PORT_DEFAULT}"
  echo "  Open WebUI port: ${WEBUI_PORT_DEFAULT}"
  echo "  LAN subnet: ${LAN_SUBNET_DEFAULT}"
  echo "  Firewall zone: ${FIREWALL_ZONE:-auto}"
  echo "  Ollama bind host: ${OLLAMA_BIND_HOST}"
  if [ -n "$OLLAMA_MODELS_DIR" ]; then
    echo "  Ollama models directory: ${OLLAMA_MODELS_DIR}"
  else
    echo "  Ollama models directory: Ollama default/service-user default"
  fi
  echo "  Open WebUI package: ${OPENWEBUI_PACKAGE}"
  echo "  Python binary for Open WebUI: ${PY311_BIN}"
  echo "  Allow CPU fallback: ${ALLOW_CPU_FALLBACK}"
  echo "  Auto reboot after driver install: ${AUTO_REBOOT}"
  if [ -n "$OLLAMA_VERSION" ]; then
    echo "  Ollama version: ${OLLAMA_VERSION}"
  else
    echo "  Ollama version: latest official installer default"
  fi
  if [ -n "$OLLAMA_INSTALL_SHA256" ]; then
    echo "  Ollama installer SHA256 verification: enabled"
  else
    echo "  Ollama installer SHA256 verification: not configured"
  fi
  echo ""

  case "$cmd" in
    install|new-server|bootstrap)
      echo "Plan:"
      echo "  1. Check dnf/systemd support."
      echo "  2. Install base tools."
      echo "  3. Enable EPEL/RPM Fusion repositories."
      echo "  4. Check NVIDIA GPU with nvidia-smi."
      echo "  5. Install NVIDIA drivers if needed."
      echo "  6. Install Ollama."
      echo "  7. Configure Ollama systemd override for local API/GPU/autostart."
      echo "  8. Configure custom Ollama model directory if provided."
      echo "  9. Offer model sets and optionally pull selected models."
      echo "  10. Install Python 3.11 side-by-side and Open WebUI in a venv."
      echo "  11. Create Open WebUI systemd service with autostart."
      echo "  12. Add the WebUI LAN rule (and Ollama only if exposed)."
      echo "  13. Run doctor readiness checks."
      ;;
    stack)
      echo "Plan:"
      echo "  1. Check dnf/systemd support."
      echo "  2. Install base tools and user."
      echo "  3. Install/configure Ollama."
      echo "  4. Configure custom Ollama model directory if provided."
      echo "  5. Offer model sets and optionally pull selected models."
      echo "  6. Install/configure Open WebUI."
      echo "  7. Configure firewall and run doctor."
      ;;
    models-dir)
      echo "Plan:"
      echo "  1. Ask for or use --ollama-models-dir."
      echo "  2. Create/chown the target directory."
      echo "  3. Optionally migrate existing model data."
      echo "  4. Update Ollama systemd override with OLLAMA_MODELS."
      echo "  5. Restart Ollama and verify /api/tags."
      ;;
    openwebui-update|webui-update)
      echo "Plan:"
      echo "  1. Check installed and available versions."
      echo "  2. Build and validate a candidate environment."
      echo "  3. Stop the service and copy its data."
      echo "  4. Activate the candidate and check /health."
      echo "  5. Restore the previous version and data on failure."
      ;;
    openwebui-check|webui-check)
      echo "Plan: check available Open WebUI updates without changing the installation."
      ;;
    openwebui-rollback|webui-rollback)
      echo "Plan: restore the recorded previous Open WebUI version and data snapshot."
      ;;
    drivers)
      echo "Plan:"
      echo "  1. Check dnf/systemd support."
      echo "  2. Install base tools and repositories."
      echo "  3. Install NVIDIA driver packages."
      echo "  4. Offer reboot."
      ;;
    uninstall)
      echo "Plan:"
      echo "  1. Remove firewall rules recorded in manifest."
      echo "  2. Stop/disable Open WebUI and remove venv/service/env file."
      echo "  3. Remove Xemi Ollama override, keep Ollama binary and model data."
      ;;
    purge)
      echo "Plan:"
      echo "  1. Run uninstall cleanup."
      echo "  2. Remove Open WebUI data only if recorded as installer-created."
      echo "  3. Remove Ollama only if recorded as installer-created."
      echo "  4. Remove created user/group and manifest."
      ;;
    doctor|status|state|report|info|menu)
      echo "Plan: run read-oriented command '${cmd}'."
      ;;
    *)
      echo "Plan: unknown command '${cmd}'."
      ;;
  esac
}

menu() {
  while true; do
    header
    menu_section "Guided Installation"
    menu_item 1 "Full new server setup or repair existing installation (GPU prioritized)"
    menu_item 2 "Stage 1, install NVIDIA drivers and reboot"
    menu_item 3 "Stage 2, install AI stack (Ollama, models, WebUI, firewall)"
    echo ""

    menu_section "Hardware And Status"
    menu_item 4 "Show GPU info and recommendations"
    menu_item 5 "Show Ollama status, service, location"
    echo ""

    menu_section "Ollama Service"
    menu_item 6 "Install Ollama (official installer)"
    menu_item 7 "Configure Ollama service for LAN"
    menu_item 8 "Ollama health check"
    echo ""

    menu_section "Models"
    menu_item 9 "Configure Ollama models directory / migrate model data"
    menu_item 10 "Recommend and install models (choose set)"
    menu_item 11 "List models"
    menu_item 12 "Test a model interaction and verify GPU/CPU usage"
    menu_item 13 "Remove models (interactive)"
    echo ""

    menu_section "Ollama Removal"
    menu_item 14 "Remove Ollama by location (discover multiple and remove)"
    echo ""

    menu_section "Open WebUI"
    menu_item 15 "Install Python 3.11"
    menu_item 16 "Install Open WebUI (Python 3.11 venv service)"
    menu_item 17 "Check/apply Open WebUI updates"
    menu_item 18 "Open WebUI health check"
    echo ""

    menu_section "Network"
    menu_item 19 "Configure firewall (LAN only)"
    menu_item 20 "Show ports in use and service bindings"
    echo ""

    menu_section "Diagnostics And Maintenance"
    menu_item 21 "Show detailed installation report"
    menu_item 22 "Run doctor readiness check"
    menu_item 23 "Uninstall stack (keep Ollama data)"
    menu_item 24 "Purge stack (reset to zero)"
    menu_item 25 "Rollback last Open WebUI update"
    echo ""

    menu_section "Session"
    menu_item 26 "Exit"
    echo ""

    local opt
    opt="$(ask "Select option" "26")"
    sleep_screen

    case "$opt" in
      1) full_new_server_setup ;;
      2) full_install_drivers ;;
      3) full_install_stack ;;
      4) gpu_info_and_recommendations ;;
      5) show_ollama_status_and_location ;;
      6) install_ollama_official ;;
      7) configure_ollama_service_lan ;;
      8) ollama_health_check ;;
      9) configure_ollama_models_dir ;;
      10) recommend_and_install_models ;;
      11) list_ollama_models ;;
      12) test_ollama_model_interaction ;;
      13) remove_ollama_models_interactive ;;
      14) remove_ollama_by_location ;;
      15) install_python311 ;;
      16) install_openwebui ;;
      17) update_openwebui ;;
      18) openwebui_health_check ;;
      19) configure_firewall_lan_only ;;
      20) show_ports_and_services ;;
      21) show_install_state ;;
      22) doctor ;;
      23) uninstall_stack 0 ;;
      24) uninstall_stack 1 ;;
      25) rollback_openwebui ;;
      26) exit 0 ;;
      *) warn "Invalid option." ; sleep_screen ;;
    esac
  done
}

usage() {
  cat <<EOF
Usage: $0 [command] [options]

Commands:
  menu        Open interactive menu (default)
  install     Full new server setup
  repair      Repair and verify existing installation
  stack       Install AI stack only, assuming drivers are ready
  drivers     Install NVIDIA driver stage
  models-dir  Configure/migrate Ollama model storage directory
  openwebui-update
              Prepare and apply a checked Open WebUI update
  openwebui-check
              Check for updates without changing the installation
  openwebui-rollback
              Restore the previous Open WebUI release and data snapshot
  doctor      Run readiness checks
  uninstall   Remove services/Open WebUI, keep Ollama data
  purge       Reset installation to zero
  status      Show ports and service status
  state       Show detailed installed configuration report
  report      Alias for state

Options:
  -y, --yes                    Use defaults and skip pauses
  -n, --dry-run                Print the resolved plan without changing the system
  --ollama-port PORT           Set Ollama port (default: ${OLLAMA_PORT_DEFAULT})
  --webui-port PORT            Set Open WebUI port (default: ${WEBUI_PORT_DEFAULT})
  --lan CIDR                   Set allowed LAN subnet (default: ${LAN_SUBNET_DEFAULT})
  --firewall-zone ZONE         Select firewalld zone (default: detect active zone)
  --ollama-bind-host HOST      Set Ollama bind host (IPv4/DNS; default: ${OLLAMA_BIND_HOST})
  --expose-ollama              Bind Ollama to all interfaces for direct LAN access
  --ollama-models-dir PATH     Set custom Ollama model directory
  --ai-user USER               Set service user (default: ${AI_USER})
  --ai-group GROUP             Set service group (default: ${AI_GROUP})
  --openwebui-package PACKAGE  Set pip package, for example open-webui==0.7.2
  --ollama-version VERSION     Set OLLAMA_VERSION for the official installer
  --ollama-install-sha256 SUM  Verify downloaded Ollama installer script
  --allow-cpu-fallback         Allow install without confirmed NVIDIA GPU
  --reboot                     Allow automatic reboot after driver install
  -h, --help                   Show this help
EOF
}

parse_args() {
  COMMAND="menu"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help|help)
        COMMAND="help"
        shift
        ;;
      -y|--yes)
        ASSUME_YES=1
        shift
        ;;
      -n|--dry-run)
        DRY_RUN=1
        ASSUME_YES=1
        shift
        ;;
      --ollama-port)
        [ "$#" -ge 2 ] || { echo "Missing value for --ollama-port"; exit 1; }
        validate_port "$2" || { echo "Invalid --ollama-port: $2"; exit 1; }
        OLLAMA_PORT_DEFAULT="$2"
        OLLAMA_PORT="$2"
        OLLAMA_PORT_FROM_CLI=1
        shift 2
        ;;
      --webui-port)
        [ "$#" -ge 2 ] || { echo "Missing value for --webui-port"; exit 1; }
        validate_port "$2" || { echo "Invalid --webui-port: $2"; exit 1; }
        WEBUI_PORT_DEFAULT="$2"
        OPENWEBUI_PORT="$2"
        WEBUI_PORT_FROM_CLI=1
        shift 2
        ;;
      --lan)
        [ "$#" -ge 2 ] || { echo "Missing value for --lan"; exit 1; }
        validate_cidr "$2" || { echo "Invalid --lan CIDR: $2"; exit 1; }
        LAN_SUBNET_DEFAULT="$2"
        LAN_SUBNET_FROM_CLI=1
        shift 2
        ;;
      --firewall-zone)
        [ "$#" -ge 2 ] || { echo "Missing value for --firewall-zone"; exit 1; }
        validate_firewall_zone "$2" || { echo "Invalid --firewall-zone: $2"; exit 1; }
        FIREWALL_ZONE="$2"
        FIREWALL_ZONE_FROM_CLI=1
        shift 2
        ;;
      --ollama-bind-host)
        [ "$#" -ge 2 ] || { echo "Missing value for --ollama-bind-host"; exit 1; }
        validate_bind_host "$2" || { echo "Invalid --ollama-bind-host: $2"; exit 1; }
        OLLAMA_BIND_HOST="$2"
        OLLAMA_BIND_HOST_FROM_CLI=1
        shift 2
        ;;
      --expose-ollama)
        OLLAMA_BIND_HOST="0.0.0.0"
        OLLAMA_BIND_HOST_FROM_CLI=1
        shift
        ;;
      --ollama-models-dir)
        [ "$#" -ge 2 ] || { echo "Missing value for --ollama-models-dir"; exit 1; }
        validate_absolute_path "$2" || { echo "Invalid --ollama-models-dir: $2"; exit 1; }
        OLLAMA_MODELS_DIR="$2"
        OLLAMA_MODELS_DIR_FROM_CLI=1
        shift 2
        ;;
      --ai-user)
        [ "$#" -ge 2 ] || { echo "Missing value for --ai-user"; exit 1; }
        validate_identity "$2" || { echo "Invalid --ai-user: $2"; exit 1; }
        AI_USER="$2"
        shift 2
        ;;
      --ai-group)
        [ "$#" -ge 2 ] || { echo "Missing value for --ai-group"; exit 1; }
        validate_identity "$2" || { echo "Invalid --ai-group: $2"; exit 1; }
        AI_GROUP="$2"
        shift 2
        ;;
      --openwebui-package)
        [ "$#" -ge 2 ] || { echo "Missing value for --openwebui-package"; exit 1; }
        OPENWEBUI_PACKAGE="$2"
        shift 2
        ;;
      --ollama-version)
        [ "$#" -ge 2 ] || { echo "Missing value for --ollama-version"; exit 1; }
        OLLAMA_VERSION="$2"
        shift 2
        ;;
      --ollama-install-sha256)
        [ "$#" -ge 2 ] || { echo "Missing value for --ollama-install-sha256"; exit 1; }
        validate_sha256 "$2" || { echo "Invalid --ollama-install-sha256: $2"; exit 1; }
        OLLAMA_INSTALL_SHA256="$2"
        shift 2
        ;;
      --allow-cpu-fallback)
        ALLOW_CPU_FALLBACK=1
        shift
        ;;
      --reboot)
        AUTO_REBOOT=1
        shift
        ;;
      --)
        shift
        break
        ;;
      -*)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
      *)
        COMMAND="$1"
        shift
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  if [ "$COMMAND" = "help" ]; then
    usage
    return 0
  fi

  validate_runtime_config

  if [ "$DRY_RUN" = "1" ]; then
    show_dry_run_plan "$COMMAND"
    return 0
  fi

  case "$COMMAND" in
    openwebui-check|webui-check)
      openwebui_check_updates
      return
      ;;
  esac

  require_root
  init_runtime
  acquire_lock

  case "$COMMAND" in
    menu) menu ;;
    install|new-server|bootstrap) full_new_server_setup ;;
    repair) repair_existing_installation ;;
    drivers) full_install_drivers ;;
    stack) full_install_stack ;;
    models-dir) configure_ollama_models_dir ;;
    openwebui-update|webui-update) update_openwebui ;;
    openwebui-check|webui-check) openwebui_check_updates ;;
    openwebui-rollback|webui-rollback) rollback_openwebui ;;
    doctor) doctor ;;
    uninstall) uninstall_stack 0 ;;
    purge) uninstall_stack 1 ;;
    status) show_ports_and_services ;;
    state|report|info) show_install_state ;;
    *) usage; exit 1 ;;
  esac
}
