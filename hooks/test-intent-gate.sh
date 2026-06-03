#!/usr/bin/env bash
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-support.sh
source "${HOOKS_DIR}/test-support.sh"

export GROK_PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-$(cd "${HOOKS_DIR}/.." && pwd)}"
export GROK_SESSION_ID="test-intent-$$"
tmpdir="$(mktemp -d)"
export GROK_WORKSPACE_ROOT="$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT

# search keyword outside code fence -> INTENT_GATE banner
printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"please search for auth middleware"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt >"${tmpdir}/out.json"
rg -q 'INTENT_GATE' "${tmpdir}/out.json" || { cat "${tmpdir}/out.json"; exit 1; }
rg -q 'search' "${tmpdir}/out.json" || { cat "${tmpdir}/out.json"; exit 1; }

# keyword inside fenced code -> no search mode (ralph may still fire separately)
printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"```\nsearch for bugs\n```"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt >"${tmpdir}/out2.json"
! rg -q 'SEARCH_MODE' "${tmpdir}/out2.json" || { cat "${tmpdir}/out2.json"; exit 1; }

echo "intent-gate: OK"