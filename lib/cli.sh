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
  echo "  Ollama context length: ${OLLAMA_CONTEXT_LENGTH}"
  echo "  Ollama K/V cache type: ${OLLAMA_KV_CACHE_TYPE}"
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
    open-terminal|mcpo|searxng|tika)
      echo "Plan:"
      echo "  1. Ensure Python 3.11 (or Java 21 for tika) and a dedicated service user."
      echo "  2. Install ${cmd} natively under /opt with a pinned or latest upstream release."
      echo "  3. Create a hardened systemd service listening on 127.0.0.1 only."
      echo "  4. Start it, verify its health endpoint, and print Open WebUI connection settings."
      ;;
    ollama-tune)
      echo "Plan: write OLLAMA_CONTEXT_LENGTH=${OLLAMA_CONTEXT_LENGTH} and OLLAMA_KV_CACHE_TYPE=${OLLAMA_KV_CACHE_TYPE}"
      echo "      into the Ollama systemd override, record them in the manifest and restart Ollama."
      ;;
    tools-update)
      echo "Plan: update installed Open WebUI tools in place, refresh their hardening and restart them."
      ;;
    diag-bundle)
      echo "Plan: collect status, units, logs and reports, redact secrets and e-mails, and write"
      echo "      ${DIAG_DIR}/xemi-diag-<host>-<time>.tar.gz (mode 600)."
      ;;
    piper-tts|jupyter|chromium|mcp-servers)
      echo "Plan: install ${cmd} natively under /opt as a hardened service on 127.0.0.1;"
      echo "      with --yes the Open WebUI connection is skipped (run tools-connect afterwards)."
      ;;
    backup-setup|voice-setup)
      echo "Plan: change Open WebUI settings (${cmd}); voice-setup needs an Open WebUI admin login."
      ;;
    https-setup)
      echo "Plan:"
      echo "  1. Download Caddy ${CADDY_VERSION} (SHA512 verified) into ${HTTPS_BIN_DIR}; no RPM, no SELinux changes."
      echo "  2. Create the ${HTTPS_USER} service user and a local certificate authority in ${HTTPS_DATA_DIR}."
      echo "  3. Proxy https://<names>:${HTTPS_PORT_DEFAULT} to Open WebUI, hardened unit ${HTTPS_SERVICE}."
      echo "  4. Allow the HTTPS port from the LAN subnet in firewalld."
      ;;
    backup-now)
      echo "Plan: run ${OWUI_BACKUP_SCRIPT} once (consistent SQLite copy, uploads, vector index)."
      ;;
    doctor|status|state|report|info|menu|tools-status|services|gpu|https-info)
      echo "Plan: run read-oriented command '${cmd}'."
      ;;
    *)
      echo "Plan: unknown command '${cmd}'."
      ;;
  esac
}

# Shows a numbered submenu until the user picks 0. Each entry is "Label|command args".
run_submenu() {
  local title="$1"
  shift
  local -a labels=() actions=()
  local entry i opt rc
  for entry in "$@"; do
    labels+=("${entry%%|*}")
    actions+=("${entry#*|}")
  done

  while true; do
    header
    menu_section "$title"
    for i in "${!labels[@]}"; do
      menu_item "$((i + 1))" "${labels[$i]}"
    done
    echo ""
    menu_item 0 "Back"
    echo ""

    opt="$(ask "Select option" "0")"
    sleep_screen

    case "$opt" in
      0) return 0 ;;
      ''|*[!0-9]*) warn "Invalid option." ; sleep_screen ;;
      *)
        opt=$((10#$opt))
        if [ "$opt" -ge 1 ] && [ "$opt" -le "${#actions[@]}" ]; then
          # Run the action in a subshell with errexit on, so an unexpected error still stops
          # the action, but a failed action returns here instead of closing the installer.
          # Actions reload the manifest themselves; word splitting passes their arguments.
          set +e
          (set -e; ${actions[$((opt - 1))]})
          rc=$?
          set -e
          if [ "$rc" -ne 0 ]; then
            warn "The action did not complete (exit ${rc}). Details: ${LOG_FILE}"
            pause
          fi
        else
          warn "Invalid option." ; sleep_screen
        fi
        ;;
    esac
  done
}

menu() {
  while true; do
    header
    menu_section "Main Menu"
    menu_group 1 "Guided installation" "full setup / repair, NVIDIA drivers, AI stack"
    menu_group 2 "Ollama" "install, LAN service, model memory, status, health, remove"
    menu_group 3 "Models" "storage directory, install, list, test, remove"
    menu_group 4 "Open WebUI" "install, updates, rollback, recommended settings, backups"
    menu_group 5 "Open WebUI tools" "terminal, MCP tools, web search, documents + OCR, voice, Jupyter, Chromium"
    menu_group 6 "Network" "LAN firewall, HTTPS access, ports and service bindings"
    menu_group 7 "Services" "status and ports, start/stop/restart, logs, GPU, diagnostics"
    menu_group 8 "Diagnostics" "GPU info, doctor check, installation report"
    menu_group 9 "Uninstall" "remove stack (keep Ollama data), purge to zero"
    echo ""
    menu_item 0 "Exit"
    echo ""

    local opt
    opt="$(ask "Select option" "0")"
    sleep_screen

    case "$opt" in
      1) run_submenu "Guided Installation" \
           "Full new server setup or repair existing installation (GPU prioritized)|full_new_server_setup" \
           "Stage 1, install NVIDIA drivers and reboot|full_install_drivers" \
           "Stage 2, install AI stack (Ollama, models, WebUI, firewall)|full_install_stack" ;;
      2) run_submenu "Ollama" \
           "Install Ollama (official installer)|install_ollama_official" \
           "Configure Ollama service for LAN|configure_ollama_service_lan" \
           "Tune model memory (context length, K/V cache)|tune_ollama_memory" \
           "Show Ollama status, service, location|show_ollama_status_and_location" \
           "Ollama health check|ollama_health_check" \
           "Remove Ollama by location (discover multiple and remove)|remove_ollama_by_location" ;;
      3) run_submenu "Models" \
           "Configure Ollama models directory / migrate model data|configure_ollama_models_dir" \
           "Recommend and install models (choose set)|recommend_and_install_models" \
           "List models|list_ollama_models" \
           "Test a model interaction and verify GPU/CPU usage|test_ollama_model_interaction" \
           "Remove models (interactive)|remove_ollama_models_interactive" ;;
      4) run_submenu "Open WebUI" \
           "Install Python 3.11|install_python311" \
           "Install Open WebUI (Python 3.11 venv service)|install_openwebui" \
           "Check/apply Open WebUI updates|update_openwebui" \
           "Rollback last Open WebUI update|rollback_openwebui" \
           "Open WebUI health check|openwebui_health_check" \
           "Apply recommended settings (task model, document search, web search)|apply_openwebui_recommended_settings" \
           "Backups (schedule, run now, list, restore)|openwebui_backups_menu" \
           "Voice settings (dictation language and Whisper, Piper voices)|configure_openwebui_voice" ;;
      5) run_submenu "Open WebUI Tools" \
           "Install Open Terminal (shell, files and code execution for models)|install_open_terminal" \
           "Install mcpo (MCP tools: time, web page fetch)|install_mcpo" \
           "Install SearXNG (private web search)|install_searxng" \
           "Install Apache Tika (PDF/Office text extraction)|install_tika" \
           "Install Piper text to speech (natural voices)|install_piper_tts" \
           "Install Jupyter code interpreter (Python on the server)|install_jupyter" \
           "Install Chromium web loader (Playwright, JavaScript pages)|install_browser" \
           "Add or remove MCP servers in mcpo (Wikipedia, arXiv)|manage_mcp_extras" \
           "Connect installed tools to Open WebUI|connect_openwebui_extras" \
           "Show tools status and Open WebUI connection settings|show_openwebui_extras_status" \
           "Update installed tools|update_openwebui_extras" \
           "Remove tools (interactive)|remove_openwebui_extras_interactive" ;;
      6) run_submenu "Network" \
           "Configure firewall (LAN only)|configure_firewall_lan_only" \
           "Enable HTTPS access for Open WebUI (local certificate)|install_https" \
           "Show HTTPS addresses and root certificate|show_https_info" \
           "Remove HTTPS access|remove_https_interactive" \
           "Show ports in use and service bindings|show_ports_and_services" ;;
      7) run_submenu "Services" \
           "Show status of all services|show_services_status" \
           "Manage a service (start, stop, restart, boot, logs, analysis)|manage_service" \
           "Restart AI services (Ollama, Open WebUI, tools)|restart_ai_services" \
           "GPU usage by service and models loaded in Ollama|show_gpu_usage" \
           "Boot timeline (what delays startup)|show_boot_timeline" \
           "Export diagnostic bundle (redacted .tar.gz)|export_diagnostic_bundle" ;;
      8) run_submenu "Diagnostics" \
           "Show GPU info and recommendations|gpu_info_and_recommendations" \
           "Run doctor readiness check|doctor" \
           "Show detailed installation report|show_install_state" ;;
      9) run_submenu "Uninstall" \
           "Uninstall stack (keep Ollama data)|uninstall_stack 0" \
           "Purge stack (reset to zero)|uninstall_stack 1" ;;
      0) exit 0 ;;
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
  ollama-tune Set context length and K/V cache type for all models
  openwebui-update
              Prepare and apply a checked Open WebUI update
  openwebui-check
              Check for updates without changing the installation
  openwebui-rollback
              Restore the previous Open WebUI release and data snapshot
  open-terminal
              Install Open Terminal for Open WebUI
  mcpo        Install mcpo MCP tool proxy (time, fetch)
  searxng     Install SearXNG private web search
  tika        Install Apache Tika document extraction
  tools-status
              Show Open WebUI tools and connection settings
  tools-connect
              Connect installed tools to Open WebUI (asks for an admin login)
  services    Show status and ports of all managed systemd services
  gpu         Show GPU usage by service and models loaded in Ollama
  diag-bundle Export a redacted diagnostic bundle (.tar.gz)
  https-setup Enable HTTPS access for Open WebUI (Caddy, local certificate)
  piper-tts   Install Piper text to speech
  jupyter     Install Jupyter as the Open WebUI code interpreter
  chromium    Install the Chromium (Playwright) web loader
  mcp-servers Add or remove extra MCP servers in mcpo (Wikipedia, arXiv)
  backup-setup
              Schedule daily Open WebUI backups
  voice-setup Set dictation (Whisper model and language) and Piper voice in Open WebUI
  https-info  Show HTTPS addresses and the root certificate to install
  backup-now  Run an Open WebUI backup now (after scheduling them)
  tools-update
              Update installed Open WebUI tools
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
  --ollama-context-length N    Default context for all models (default: ${OLLAMA_CONTEXT_LENGTH_DEFAULT})
  --ollama-kv-cache-type TYPE  K/V cache type: f16, q8_0, q4_0 (default: ${OLLAMA_KV_CACHE_TYPE_DEFAULT})
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
      --ollama-context-length)
        [ "$#" -ge 2 ] || { echo "Missing value for --ollama-context-length"; exit 1; }
        validate_context_length "$2" || { echo "Invalid --ollama-context-length (2048-262144): $2"; exit 1; }
        OLLAMA_CONTEXT_LENGTH="$2"
        OLLAMA_CONTEXT_LENGTH_FROM_CLI=1
        shift 2
        ;;
      --ollama-kv-cache-type)
        [ "$#" -ge 2 ] || { echo "Missing value for --ollama-kv-cache-type"; exit 1; }
        validate_kv_cache_type "$2" || { echo "Invalid --ollama-kv-cache-type (f16, q8_0, q4_0): $2"; exit 1; }
        OLLAMA_KV_CACHE_TYPE="$2"
        OLLAMA_KV_CACHE_TYPE_FROM_CLI=1
        shift 2
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
    ollama-tune) tune_ollama_memory ;;
    openwebui-update|webui-update) update_openwebui ;;
    openwebui-check|webui-check) openwebui_check_updates ;;
    openwebui-rollback|webui-rollback) rollback_openwebui ;;
    open-terminal) install_open_terminal ;;
    mcpo) install_mcpo ;;
    searxng) install_searxng ;;
    tika) install_tika ;;
    tools-status) show_openwebui_extras_status ;;
    tools-connect) connect_openwebui_extras ;;
    services) show_services_status ;;
    gpu) show_gpu_usage ;;
    https-setup) install_https ;;
    piper-tts) install_piper_tts ;;
    jupyter) install_jupyter ;;
    chromium) install_browser ;;
    mcp-servers) manage_mcp_extras ;;
    backup-setup) configure_openwebui_backups ;;
    voice-setup) configure_openwebui_voice ;;
    https-info) show_https_info ;;
    backup-now) run_openwebui_backup_now ;;
    diag-bundle) export_diagnostic_bundle ;;
    tools-update) update_openwebui_extras ;;
    doctor) doctor ;;
    uninstall) uninstall_stack 0 ;;
    purge) uninstall_stack 1 ;;
    status) show_ports_and_services ;;
    state|report|info) show_install_state ;;
    *) usage; exit 1 ;;
  esac
}
