#!/usr/bin/env bash
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${HOOKS_DIR}/lib/common.sh"

export GROK_HOME="${GROK_HOME:-$(resolve_grok_home)}"
export GROK_SESSION_ID="test-ulw-$$"

tmpdir="$(mktemp -d)"
export GROK_WORKSPACE_ROOT="$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/.omg"

# Start ultrawork
printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"/ulw-loop \"ship feature\" --max-iterations=5"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt.sh \
  >"${tmpdir}/start.json"
rg -q 'ULTRAWORK|VERIFIED|ultrawork' "${tmpdir}/start.json" \
  || { echo "ulw start failed:"; cat "${tmpdir}/start.json"; exit 1; }
rg -q 'ultrawork: true' "${tmpdir}/.omg/ralph-loop.local.md" || { cat "${tmpdir}/.omg/ralph-loop.local.md"; exit 1; }

# Stop without promise -> block (ultrawork continuation)
printf '%s\n' '{"hookEventName":"stop","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","stopReason":"end_turn","last_assistant_message":"wip"}' \
  | GROK_HOOK_EVENT=stop bash "${HOOKS_DIR}/run-hook.sh" stop-hook.sh >"${tmpdir}/block.json"
rg -q '"decision":"block"' "${tmpdir}/block.json" || { cat "${tmpdir}/block.json"; exit 1; }
rg -q 'ULTRAWORK LOOP' "${tmpdir}/block.json" || { cat "${tmpdir}/block.json"; exit 1; }

# DONE -> verification phase (still block, not cleared)
printf '%s\n' '{"hookEventName":"stop","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","stopReason":"end_turn","last_assistant_message":"finished <promise>DONE</promise>"}' \
  | GROK_HOOK_EVENT=stop bash "${HOOKS_DIR}/run-hook.sh" stop-hook.sh >"${tmpdir}/verify.json"
rg -q '"decision":"block"' "${tmpdir}/verify.json" || { cat "${tmpdir}/verify.json"; exit 1; }
rg -q 'VERIFICATION' "${tmpdir}/verify.json" || { cat "${tmpdir}/verify.json"; exit 1; }
rg -q 'code-reviewer' "${tmpdir}/verify.json" || { cat "${tmpdir}/verify.json"; exit 1; }
test -f "${tmpdir}/.omg/ralph-loop.local.md" || { echo "state cleared too early"; exit 1; }
rg -q 'verification_pending: true' "${tmpdir}/.omg/ralph-loop.local.md" || { cat "${tmpdir}/.omg/ralph-loop.local.md"; exit 1; }

# VERIFIED without Agent: oracle -> still block
printf '%s\n' '{"hookEventName":"stop","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","stopReason":"end_turn","last_assistant_message":"<promise>VERIFIED</promise>"}' \
  | GROK_HOOK_EVENT=stop bash "${HOOKS_DIR}/run-hook.sh" stop-hook.sh >"${tmpdir}/bad-verify.json"
rg -q '"decision":"block"' "${tmpdir}/bad-verify.json" || { cat "${tmpdir}/bad-verify.json"; exit 1; }
rg -q 'VERIFICATION FAILED' "${tmpdir}/bad-verify.json" || { cat "${tmpdir}/bad-verify.json"; exit 1; }

# Oracle VERIFIED -> allow
printf '%s\n' '{"hookEventName":"stop","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","stopReason":"end_turn","last_assistant_message":"Agent: oracle\n<promise>VERIFIED</promise>"}' \
  | GROK_HOOK_EVENT=stop bash "${HOOKS_DIR}/run-hook.sh" stop-hook.sh >"${tmpdir}/done.json"
test "$(cat "${tmpdir}/done.json")" = "{}" || { echo "expected allow:"; cat "${tmpdir}/done.json"; exit 1; }
test ! -f "${tmpdir}/.omg/ralph-loop.local.md" || { echo "state should be cleared"; exit 1; }

# Bare ultrawork prefix
printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"ultrawork fix lint in src"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt.sh >"${tmpdir}/bare.json"
rg -q 'ULTRAWORK' "${tmpdir}/bare.json" || { cat "${tmpdir}/bare.json"; exit 1; }

echo "ulw-loop hooks: OK"