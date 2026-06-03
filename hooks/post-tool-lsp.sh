#!/usr/bin/env bash
# PostToolUse (Write|StrReplace): run LSP diagnostics on mutated files and merge stash.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/lsp.sh
source "${SCRIPT_DIR}/lib/lsp.sh"

stdin_tmp="$(mktemp)"
trap 'rm -f "$stdin_tmp"' EXIT
cat >"$stdin_tmp" || true
apply_hook_env_from_stdin "$stdin_tmp"
lsp_update_stash_for_paths "$stdin_tmp"
exit 0