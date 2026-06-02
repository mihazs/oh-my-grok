#!/usr/bin/env bash
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${HOOKS_DIR}/lib/common.sh"
# shellcheck source=lib/handoff.sh
source "${HOOKS_DIR}/lib/handoff.sh"

export GROK_HOME="${GROK_HOME:-$(resolve_grok_home)}"
export GROK_SESSION_ID="test-handoff-$$"
tmpdir="$(mktemp -d)"
export GROK_WORKSPACE_ROOT="$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT

printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"/handoff"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt.sh >"${tmpdir}/out.json"

rg -q 'HANDOFF_COMMAND' "${tmpdir}/out.json" || { echo "missing HANDOFF_COMMAND"; cat "${tmpdir}/out.json"; exit 1; }
rg -q 'PHASE 0' "${tmpdir}/out.json" || { echo "missing phases"; cat "${tmpdir}/out.json"; exit 1; }

printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"hello"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt.sh >"${tmpdir}/plain.json"
rg -q 'HANDOFF_COMMAND' "${tmpdir}/plain.json" && { echo "unexpected handoff on plain prompt"; exit 1; }

echo "handoff hook: OK"