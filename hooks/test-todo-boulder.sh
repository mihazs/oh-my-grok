#!/usr/bin/env bash
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-support.sh
source "${HOOKS_DIR}/test-support.sh"

export GROK_HOME="${GROK_HOME:-$(resolve_grok_home)}"
export GROK_SESSION_ID="test-todo-boulder-$$"

tmpdir="$(mktemp -d)"
export GROK_WORKSPACE_ROOT="$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/.omg/plans"

# Boulder state + plan
cat >"${tmpdir}/.omg/plans/auth.md" <<'PLAN'
## TODOs
- [ ] 1. Add login
- [x] 2. Add logout
PLAN

cat >"${tmpdir}/.omg/boulder.json" <<JSON
{
  "schema_version": 2,
  "active_work_id": "auth-work",
  "active_plan": ".omg/plans/auth.md",
  "plan_name": "auth",
  "status": "active",
  "started_at": "2026-06-02T10:00:00+00:00",
  "updated_at": "2026-06-02T10:00:00+00:00",
  "session_ids": ["${GROK_SESSION_ID}"],
  "works": {
    "auth-work": {
      "work_id": "auth-work",
      "active_plan": ".omg/plans/auth.md",
      "plan_name": "auth",
      "status": "active",
      "started_at": "2026-06-02T10:00:00+00:00",
      "updated_at": "2026-06-02T10:00:00+00:00",
      "session_ids": ["${GROK_SESSION_ID}"],
      "task_sessions": {}
    }
  }
}
JSON

# Session dir with incomplete todo
sess_root="${GROK_HOME}/sessions/test-ws-${GROK_SESSION_ID}"
mkdir -p "${sess_root}/${GROK_SESSION_ID}"
cat >"${sess_root}/${GROK_SESSION_ID}/resources_state.json" <<JSON
{
  "TodoState_1": {
    "state": "{\"todos\":[{\"id\":\"1\",\"content\":\"fix tests\",\"status\":\"pending\"}]}"
  }
}
JSON

# Boulder context on prompt
printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"continue"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt >"${tmpdir}/ctx.json"
rg -q 'BOULDER_STATE' "${tmpdir}/ctx.json" || { cat "${tmpdir}/ctx.json"; exit 1; }

# Boulder stop -> block
printf '%s\n' '{"hookEventName":"stop","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","stopReason":"end_turn"}' \
  | GROK_HOOK_EVENT=stop bash "${HOOKS_DIR}/run-hook.sh" stop >"${tmpdir}/boulder-block.json"
rg -q '"decision":"block"' "${tmpdir}/boulder-block.json" || { cat "${tmpdir}/boulder-block.json"; exit 1; }
rg -q 'BOULDER CONTINUATION' "${tmpdir}/boulder-block.json" || { cat "${tmpdir}/boulder-block.json"; exit 1; }

# Stop continuation pauses boulder
printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"/stop-continuation"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt >/dev/null
test ! -f "${tmpdir}/.omg/boulder.json" || { echo "boulder should be cleared"; exit 1; }

# Resume continuation for todo-only test (paused boulder does not block)
printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"/resume-continuation"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt >/dev/null

printf '%s\n' '{"hookEventName":"stop","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","stopReason":"end_turn"}' \
  | GROK_HOOK_EVENT=stop bash "${HOOKS_DIR}/run-hook.sh" stop >"${tmpdir}/todo-block.json"
rg -q 'TODO CONTINUATION' "${tmpdir}/todo-block.json" || { cat "${tmpdir}/todo-block.json"; exit 1; }

# Mirror todos via post-tool hook
printf '%s\n' '{"hookEventName":"PostToolUse","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'"}' \
  | GROK_HOOK_EVENT=post_tool_use bash "${HOOKS_DIR}/run-hook.sh" post-tool-todo-write >/dev/null
test -f "${tmpdir}/.omg/todos/${GROK_SESSION_ID}.json" || { echo "todo mirror missing"; exit 1; }

# Todo cooldown: second stop within 5s should allow (no TODO CONTINUATION)
printf '%s\n' '{"hookEventName":"stop","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","stopReason":"end_turn"}' \
  | GROK_HOOK_EVENT=stop bash "${HOOKS_DIR}/run-hook.sh" stop >"${tmpdir}/todo-block2.json"
if rg -q 'TODO CONTINUATION' "${tmpdir}/todo-block2.json" 2>/dev/null; then
  echo "expected no TODO CONTINUATION on cooldown (second stop)"
  cat "${tmpdir}/todo-block2.json"
  exit 1
fi

sleep 6

printf '%s\n' '{"hookEventName":"stop","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","stopReason":"end_turn"}' \
  | GROK_HOOK_EVENT=stop bash "${HOOKS_DIR}/run-hook.sh" stop >"${tmpdir}/todo-block3.json"
rg -q 'TODO CONTINUATION' "${tmpdir}/todo-block3.json" || { cat "${tmpdir}/todo-block3.json"; exit 1; }

echo "todo-boulder hooks: OK"