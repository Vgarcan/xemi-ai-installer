# Installer configuration defaults. This file is sourced by xemi_ai_install.sh.
APP_NAME="AI Node Manager Pro"
STATE_DIR="/var/lib/xemi-ai"
CONFIG_DIR="/etc/xemi-ai"
BACKUP_DIR="${STATE_DIR}/backups"
MANIFEST_FILE="${STATE_DIR}/manifest.env"
LOCK_FILE="${STATE_DIR}/install.lock"
LOG_DIR="/var/log/xemi-ai"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/install.log}"

SLEEP_SCREEN="0.66"

AI_USER="${AI_USER:-aiuser}"
AI_GROUP="${AI_GROUP:-aiuser}"

OLLAMA_PORT_DEFAULT="11434"
WEBUI_PORT_DEFAULT="3000"
LAN_SUBNET_DEFAULT="${LAN_SUBNET:-192.168.2.0/24}"
FIREWALL_ZONE="${FIREWALL_ZONE:-}"
FIREWALL_ZONE_FROM_CLI=0
RECORDED_FIREWALL_ZONE=""

OPENWEBUI_DIR="/opt/open-webui"
OPENWEBUI_VENV="/opt/open-webui-venv"
OPENWEBUI_DATA_DIR="/var/lib/open-webui"
OPENWEBUI_ENV_FILE="/etc/xemi-ai/openwebui.env"
OPENWEBUI_PACKAGE="${OPENWEBUI_PACKAGE:-open-webui}"
# Open WebUI defaults for a new installation. Open WebUI reads them only on its first start;
# afterwards its database wins, so existing installations are not changed.
OPENWEBUI_TASK_MODEL="qwen2.5:0.5b"
OPENWEBUI_EMBEDDING_MODEL="sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
OPENWEBUI_RAG_TOP_K="5"
OPENWEBUI_WEB_SEARCH_RESULT_COUNT="5"
PY311_BIN="/usr/bin/python3.11"
OPENWEBUI_REF="${OPENWEBUI_REF:-}"
ALLOW_CPU_FALLBACK="${ALLOW_CPU_FALLBACK:-0}"
OLLAMA_VERSION="${OLLAMA_VERSION:-}"
OLLAMA_BIND_HOST="${OLLAMA_BIND_HOST:-127.0.0.1}"
OLLAMA_MODELS_DIR="${OLLAMA_MODELS_DIR:-}"
OLLAMA_MODELS_DIR_FROM_CLI=0
# Default context and K/V cache for every model. 16k fits web search and document context;
# q8_0 halves the K/V cache versus f16 with negligible quality loss (needs flash attention, always on).
OLLAMA_CONTEXT_LENGTH_DEFAULT="16384"
OLLAMA_KV_CACHE_TYPE_DEFAULT="q8_0"
OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-$OLLAMA_CONTEXT_LENGTH_DEFAULT}"
OLLAMA_KV_CACHE_TYPE="${OLLAMA_KV_CACHE_TYPE:-$OLLAMA_KV_CACHE_TYPE_DEFAULT}"
OLLAMA_CONTEXT_LENGTH_FROM_CLI=0
OLLAMA_KV_CACHE_TYPE_FROM_CLI=0
OLLAMA_PORT_FROM_CLI=0
WEBUI_PORT_FROM_CLI=0
OLLAMA_BIND_HOST_FROM_CLI=0
LAN_SUBNET_FROM_CLI=0
if [ -n "$OLLAMA_MODELS_DIR" ]; then
  OLLAMA_MODELS_DIR_FROM_CLI=1
fi
OLLAMA_INSTALL_SHA256="${OLLAMA_INSTALL_SHA256:-}"

# Optional Open WebUI tools (lib/extras.sh). All listen on 127.0.0.1 only.
EXTRAS_USER="aitools"
EXTRAS_HOME="/var/lib/ai-tools"
EXTRAS_PACKAGES_DIR="${STATE_DIR}/packages"
DIAG_DIR="${STATE_DIR}/diagnostics"
TERMINAL_USER="aiterminal"
OPEN_TERMINAL_VENV="/opt/open-terminal-venv"
OPEN_TERMINAL_HOME="/var/lib/open-terminal"
OPEN_TERMINAL_ENV_FILE="${CONFIG_DIR}/open-terminal.env"
OPEN_TERMINAL_PORT_DEFAULT="8000"
MCPO_VENV="/opt/mcpo-venv"
MCPO_CONFIG_DIR="/etc/mcpo"
MCPO_ENV_FILE="${CONFIG_DIR}/mcpo.env"
MCPO_PORT_DEFAULT="8001"
SEARXNG_DIR="/opt/searxng"
SEARXNG_REPO="https://github.com/searxng/searxng"
SEARXNG_CONFIG_DIR="/etc/searxng"
SEARXNG_PORT_DEFAULT="8888"
TIKA_DIR="/opt/tika"
TIKA_VERSION="3.3.2"
TIKA_SHA512="fb1f2fe57ac458b09d44d41d816f582e1d2fc93488acff6275caf414d8d5ef94e42166edc0b488dc2fb6ef3aa21fab62b107c43b9060385ff6d675e393c2c9e9"
TIKA_PORT_DEFAULT="9998"
ASSUME_YES=0
DRY_RUN=0
COMMAND="menu"
AUTO_REBOOT="${AUTO_REBOOT:-0}"

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
NC="\e[0m"
