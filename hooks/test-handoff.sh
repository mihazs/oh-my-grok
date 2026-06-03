#!/usr/bin/env bash
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-support.sh
source "${HOOKS_DIR}/test-support.sh"

export GROK_HOME="${GROK_HOME:-$(resolve_grok_home)}"
export GROK_PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-$(cd "${HOOKS_DIR}/.." && pwd)}"
export GROK_SESSION_ID="test-handoff-$$"
tmpdir="$(mktemp -d)"
export GROK_WORKSPACE_ROOT="$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT

printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"/handoff"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt >"${tmpdir}/out.json"

rg -q 'HANDOFF_COMMAND' "${tmpdir}/out.json" || { echo "missing HANDOFF_COMMAND"; cat "${tmpdir}/out.json"; exit 1; }
rg -q 'PHASE 0' "${tmpdir}/out.json" || { echo "missing phases"; cat "${tmpdir}/out.json"; exit 1; }

printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"hello"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt >"${tmpdir}/plain.json"
rg -q 'HANDOFF_COMMAND' "${tmpdir}/plain.json" && { echo "unexpected handoff on plain prompt"; exit 1; }

echo "handoff hook: OK"