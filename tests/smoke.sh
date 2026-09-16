#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/config.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/validation.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/state.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/diagnostics.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/openwebui.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/cli.sh"

STATE_DIR="$TEST_DIR/state"
MANIFEST_FILE="${STATE_DIR}/manifest.env"
LOG_DIR="$TEST_DIR/log"
LOG_FILE="${LOG_DIR}/install.log"
mkdir -p "$STATE_DIR" "$LOG_DIR"

assert_rejected() {
  if "$@"; then
    echo "Expected rejection: $*" >&2
    exit 1
  fi
}

validate_cidr "192.168.2.0/24"
assert_rejected validate_cidr "999.168.2.0/24"
validate_bind_host "localhost"
validate_bind_host "192.168.2.10"
assert_rejected validate_bind_host "2001:db8::1"
assert_rejected validate_package_spec "--user"

fail() { :; }
assert_rejected safe_rm_rf "$TEST_DIR" "$TEST_DIR"
assert_rejected record_manifest OLLAMA_PORT "not-a-port"

rule="rule family='ipv4' source address='192.168.2.0/24' port protocol='tcp' port='11434' accept"
record_manifest FIREWALL_RULE_OLLAMA "$rule"
FIREWALL_RULE_OLLAMA=""
load_manifest
[ "$FIREWALL_RULE_OLLAMA" = "$rule" ]
remove_manifest_key FIREWALL_RULE_OLLAMA
! grep -q '^FIREWALL_RULE_OLLAMA=' "$MANIFEST_FILE"

record_manifest OLLAMA_BIND_HOST "127.0.0.1"
record_manifest FIREWALL_ZONE "public"
parse_args --expose-ollama --firewall-zone trusted --ollama-port 11435 install
load_manifest
[ "$OLLAMA_BIND_HOST" = "0.0.0.0" ]
[ "$OLLAMA_PORT" = "11435" ]
[ "$FIREWALL_ZONE" = "trusted" ]
[ "$RECORDED_FIREWALL_ZONE" = "public" ]

OPENWEBUI_VENV="$TEST_DIR/openwebui-venv"
OPENWEBUI_DATA_DIR="$TEST_DIR/openwebui-data"
previous="$TEST_DIR/openwebui-venv.previous"
candidate="$TEST_DIR/openwebui-venv.candidate"
snapshot="$TEST_DIR/openwebui-snapshot"
mkdir -p "$previous" "$candidate" "$snapshot" "$OPENWEBUI_DATA_DIR"
printf 'old\n' > "$previous/release"
printf 'new\n' > "$candidate/release"
printf 'original\n' > "$snapshot/db"
printf 'migrated\n' > "$OPENWEBUI_DATA_DIR/db"
ln -s "$candidate" "$OPENWEBUI_VENV"
systemctl() { :; }
wait_openwebui_health() { :; }
if [ -L "$OPENWEBUI_VENV" ]; then
  openwebui_restore_release "$previous" "$snapshot" "3000"
  [ ! -L "$OPENWEBUI_VENV" ]
  [ "$(head -n 1 "$OPENWEBUI_VENV/release")" = "old" ]
  [ "$(head -n 1 "$OPENWEBUI_DATA_DIR/db")" = "original" ]
else
  # Git Bash without Windows symlink privileges creates a regular path.
  assert_rejected openwebui_restore_release "$previous" "$snapshot" "3000"
fi

header() { :; }
pause() { :; }
load_manifest() { :; }
doctor_check_command() { doctor_fail "simulated failure"; }
doctor_check_gpu() { :; }
doctor_check_service() { :; }
doctor_check_http() { :; }
doctor_check_ollama_gpu_logs() { :; }
doctor_check_ollama_models_dir() { :; }
doctor_check_firewall() { :; }
doctor_ok() { :; }
doctor_fail() { DOCTOR_FAILURES=$((DOCTOR_FAILURES + 1)); }

assert_rejected doctor

echo "Smoke tests passed."
