#!/usr/bin/env bash
# LSP diagnostics stash + Stop enforcement (mock diagnostics).
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-support.sh
source "${HOOKS_DIR}/test-support.sh"

export GROK_HOME="${GROK_HOME:-$(resolve_grok_home)}"
export GROK_PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-$(cd "${HOOKS_DIR}/.." && pwd)}"
export GROK_SESSION_ID="test-lsp-$$"
export OMG_LSP_MOCK_DIAG='error[typescript] (1) at 1:1: syntax error'
export OMG_LSP_ENFORCE=1

tmpdir="$(mktemp -d)"
export GROK_WORKSPACE_ROOT="$tmpdir"
trap 'rm -rf "$tmpdir" "$(lsp_stash_path)"' EXIT
mkdir -p "$tmpdir"
printf '// broken\n' >"${tmpdir}/bad.ts"

# Post-tool: simulate Write on bad.ts
printf '%s\n' '{"hookEventName":"PostToolUse","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","toolName":"Write","toolInput":{"path":"'"${tmpdir}/bad.ts"'"}}' \
  | GROK_HOOK_EVENT=post_tool_use bash "${HOOKS_DIR}/run-hook.sh" post-tool-lsp >/dev/null

stash="$(lsp_stash_path)"
[ -f "$stash" ] || { echo "missing stash: $stash"; exit 1; }
rg -q 'syntax error' "$stash" || { echo "stash missing mock error:"; cat "$stash"; exit 1; }
rg -q '"has_errors": true' "$stash" || { echo "stash missing has_errors:"; cat "$stash"; exit 1; }

# UserPrompt should surface LSP context
printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"continue"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt >"${tmpdir}/prompt.json"
rg -q 'LSP_DIAGNOSTICS' "${tmpdir}/prompt.json" || { echo "missing LSP_DIAGNOSTICS in prompt"; cat "${tmpdir}/prompt.json"; exit 1; }

# Stop should block while errors remain
printf '%s\n' '{"hookEventName":"Stop","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","stopReason":"end_turn"}' \
  | GROK_HOOK_EVENT=stop bash "${HOOKS_DIR}/run-hook.sh" stop >"${tmpdir}/block.json"
rg -q '"decision":"block"' "${tmpdir}/block.json" || { echo "expected stop block"; cat "${tmpdir}/block.json"; exit 1; }
rg -q 'LSP errors remain' "${tmpdir}/block.json" || { echo "expected LSP block reason"; cat "${tmpdir}/block.json"; exit 1; }

# OMG_LSP_ENFORCE=0 allows stop even with stash errors
export OMG_LSP_ENFORCE=0
printf '%s\n' '{"hookEventName":"Stop","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","stopReason":"end_turn"}' \
  | GROK_HOOK_EVENT=stop bash "${HOOKS_DIR}/run-hook.sh" stop >"${tmpdir}/allow.json"
rg -q '"decision":"block"' "${tmpdir}/allow.json" && { echo "unexpected block with OMG_LSP_ENFORCE=0"; cat "${tmpdir}/allow.json"; exit 1; }

# Clean stash -> allow stop with enforcement on
export OMG_LSP_ENFORCE=1
printf '{"version":1,"files":{},"updated_at":"2026-06-02T00:00:00+00:00"}\n' >"$stash"
printf '%s\n' '{"hookEventName":"Stop","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","stopReason":"end_turn"}' \
  | GROK_HOOK_EVENT=stop bash "${HOOKS_DIR}/run-hook.sh" stop >"${tmpdir}/allow2.json"
rg -q '"decision":"block"' "${tmpdir}/allow2.json" && { echo "unexpected block after clean stash"; cat "${tmpdir}/allow2.json"; exit 1; }

echo "lsp hooks: OK"