#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/using-superpowers.sh
source "${SCRIPT_DIR}/lib/using-superpowers.sh"
# shellcheck source=lib/todo-boulder.sh
source "${SCRIPT_DIR}/lib/todo-boulder.sh"
# shellcheck source=lib/lsp.sh
source "${SCRIPT_DIR}/lib/lsp.sh"

cleanup_session_state
cleanup_stop_verify_state
cleanup_using_superpowers_state
cleanup_omo_session_state
cleanup_lsp_session_state
exit 0