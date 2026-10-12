#!/bin/bash

set -euo pipefail
umask 027

# sudo's secure_path on EL9 omits /usr/local/bin, where the Ollama installer may place its binary.
case ":${PATH}:" in
  *:/usr/local/bin:*) ;;
  *) PATH="/usr/local/sbin:/usr/local/bin:${PATH}" ;;
esac

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  SCRIPT_PATH="$(readlink -f -- "$SCRIPT_PATH")"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/state.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/validation.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/system.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/ollama.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/openwebui.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/network.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/lifecycle.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/extras.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/owui_api.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/https.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/backup.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/voice.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/jupyter.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/browser.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/services.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/diagnostics.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/workflows.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/cli.sh"

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  echo "Do not source this installer. Run it as a command instead: sudo ${BASH_SOURCE[0]} install"
  return 1
fi

main "$@"
