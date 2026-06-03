#!/usr/bin/env bash
# Stop hook: unified continuation chain (see lib/stop-chain.sh).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/ralph-loop.sh
source "${SCRIPT_DIR}/lib/ralph-loop.sh"
# shellcheck source=lib/todo-boulder.sh
source "${SCRIPT_DIR}/lib/todo-boulder.sh"
# shellcheck source=lib/stop-pending.sh
source "${SCRIPT_DIR}/lib/stop-pending.sh"
# shellcheck source=lib/lsp.sh
source "${SCRIPT_DIR}/lib/lsp.sh"
# shellcheck source=lib/stop-chain.sh
source "${SCRIPT_DIR}/lib/stop-chain.sh"

stdin_tmp="$(mktemp)"
trap 'rm -f "$stdin_tmp"' EXIT
cat >"$stdin_tmp" || true
apply_hook_env_from_stdin "$stdin_tmp"

if reason="$(evaluate_stop_hook_chain "$stdin_tmp")"; then
  emit_stop_block "$reason"
fi

emit_stop_allow