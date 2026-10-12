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
# Hybrid search: TOP_K candidates from the vector and keyword searches, then a multilingual
# reranker (CPU, about 0.5 s per query on an i7-3770) keeps the best TOP_K_RERANKER for the model.
OPENWEBUI_RAG_TOP_K="10"
OPENWEBUI_RAG_TOP_K_RERANKER="5"
OPENWEBUI_RERANKING_MODEL="cross-encoder/mmarco-mMiniLMv2-L12-H384-v1"
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
# Python in the terminal: Word, Excel, PowerPoint and PDF files the model creates and shows in the chat.
OPEN_TERMINAL_OFFICE_PACKAGES="python-docx openpyxl python-pptx reportlab"
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
# OCR for scanned PDFs and images (Tesseract from AppStream; eng comes with tesseract).
TIKA_OCR_PACKAGES="tesseract tesseract-langpack-spa"
TIKA_OCR_LANGUAGES="spa+eng"

# Extra MCP servers for mcpo, each in its own venv under MCP_SERVERS_DIR so they cannot break
# mcpo's dependencies. Catalog entries: "name|pip package|command|arguments".
MCP_SERVERS_DIR="/opt/mcpo-servers"
MCP_EXTRA_CATALOG=(
  "wikipedia|wikipedia-mcp|wikipedia-mcp|--language es"
  "arxiv|arxiv-mcp-server|arxiv-mcp-server|--storage-path ${EXTRAS_HOME}/arxiv-papers"
)

# Text to speech: Piper voices behind a small OpenAI-compatible server (lib/voice.sh).
PIPER_DIR="/opt/piper-tts"
PIPER_PORT_DEFAULT="8002"
PIPER_VOICES="es_ES-davefx-medium es_ES-sharvard-medium en_US-lessac-medium"
PIPER_DEFAULT_VOICE="es_ES-davefx-medium"
# Speech to text runs inside Open WebUI (faster-whisper); small is accurate in Spanish on CPU.
OPENWEBUI_WHISPER_MODEL="small"
OPENWEBUI_WHISPER_LANGUAGE_DEFAULT="es"

# Jupyter as the Open WebUI code interpreter (lib/jupyter.sh): runs model-written code on the server.
JUPYTER_USER="aijupyter"
JUPYTER_VENV="/opt/jupyter-venv"
JUPYTER_HOME="/var/lib/jupyter"
JUPYTER_ENV_FILE="${CONFIG_DIR}/jupyter.env"
JUPYTER_PORT_DEFAULT="8890"
JUPYTER_PACKAGES="jupyter_server ipykernel numpy pandas matplotlib openpyxl"

# Headless Chromium for Open WebUI's web loader (lib/browser.sh), pinned to the Playwright
# version Open WebUI declares, so client and server always speak the same protocol.
BROWSER_USER="aibrowser"
PLAYWRIGHT_DIR="/opt/playwright"
PLAYWRIGHT_PORT_DEFAULT="8003"
PLAYWRIGHT_LIBS="libXcomposite libXdamage libXfixes libXrandr atk at-spi2-atk at-spi2-core libxkbcommon"
# Without a fontconfig setup Chromium aborts (SIGTRAP) on the first page that uses web fonts.
PLAYWRIGHT_FONTS="fontconfig dejavu-sans-fonts liberation-sans-fonts liberation-serif-fonts liberation-mono-fonts"

# HTTPS front end for Open WebUI (lib/https.sh): the official Caddy binary (pinned, checksum
# verified) with its own local certificate authority. The EPEL package is not used: its
# scriptlets turn on the global SELinux boolean httpd_can_network_connect.
HTTPS_SERVICE="xemi-https"
HTTPS_PORT_DEFAULT="443"
HTTPS_BIN_DIR="/opt/xemi-https"
HTTPS_CONFIG_DIR="/etc/xemi-https"
HTTPS_DATA_DIR="/var/lib/xemi-https"
HTTPS_USER="aiproxy"
CADDY_VERSION="2.10.0"
CADDY_SHA512="626682d623ca04356ab3c9a93a82386cfde6d8243b11f2d0eea9e97ba630c7ada62373401e96b72c6690c98ae8dd004d61fafe477f5249690d5cb251ebbfd2d9"

# Scheduled Open WebUI backups (lib/backup.sh).
OWUI_BACKUP_SERVICE="xemi-openwebui-backup"
OWUI_BACKUP_SCRIPT="/usr/local/bin/xemi-openwebui-backup"
OWUI_BACKUP_DIR_DEFAULT="/var/backups/open-webui"
OWUI_BACKUP_KEEP_DEFAULT="7"
OWUI_BACKUP_TIME_DEFAULT="03:30"
ASSUME_YES=0
DRY_RUN=0
COMMAND="menu"
AUTO_REBOOT="${AUTO_REBOOT:-0}"

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
NC="\e[0m"
