#!/bin/bash

set -euo pipefail
umask 027

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
