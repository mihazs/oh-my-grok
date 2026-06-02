#!/usr/bin/env bash
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${HOOKS_DIR}/lib/common.sh"

export GROK_HOME="${GROK_HOME:-$(resolve_grok_home)}"
export GROK_SESSION_ID="test-ralph-$$"
export GROK_WORKSPACE_ROOT="${tmpdir:-}"

tmpdir="$(mktemp -d)"
export GROK_WORKSPACE_ROOT="$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/.omg"

# Start loop
printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"/ralph-loop \"fix tests\" --max-iterations=3"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt.sh \
  >"${tmpdir}/start.json"
rg -q 'Ralph Loop|ralph-loop.local' "${tmpdir}/start.json" \
  || { echo "start failed:"; cat "${tmpdir}/start.json"; exit 1; }
test -f "${tmpdir}/.omg/ralph-loop.local.md" || { echo "state file missing"; exit 1; }

# Stop without promise -> block
printf '%s\n' '{"hookEventName":"stop","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","stopReason":"end_turn","last_assistant_message":"still working"}' \
  | GROK_HOOK_EVENT=stop bash "${HOOKS_DIR}/run-hook.sh" stop-hook.sh >"${tmpdir}/block.json"
rg -q '"decision":"block"' "${tmpdir}/block.json" \
  || { echo "expected block:"; cat "${tmpdir}/block.json"; exit 1; }
rg -q 'RALPH LOOP' "${tmpdir}/block.json" || { cat "${tmpdir}/block.json"; exit 1; }

# Stop with promise -> allow
printf '%s\n' '{"hookEventName":"stop","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","stopReason":"end_turn","last_assistant_message":"done <promise>DONE</promise>"}' \
  | GROK_HOOK_EVENT=stop bash "${HOOKS_DIR}/run-hook.sh" stop-hook.sh >"${tmpdir}/done.json"
test "$(cat "${tmpdir}/done.json")" = "{}" || { echo "expected allow:"; cat "${tmpdir}/done.json"; exit 1; }
test ! -f "${tmpdir}/.omg/ralph-loop.local.md" || { echo "state should be cleared"; exit 1; }

# Cancel
printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"/ralph-loop again"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt.sh >/dev/null
printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"/cancel-ralph"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt.sh >"${tmpdir}/cancel.json"
rg -q 'Canceled' "${tmpdir}/cancel.json" || { cat "${tmpdir}/cancel.json"; exit 1; }

echo "ralph-loop hooks: OK"