#!/usr/bin/env bash
# Smoke-test stop-verify-pending hook (no block vs block).
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-support.sh
source "${HOOKS_DIR}/test-support.sh"

export GROK_HOME="${GROK_HOME:-$(resolve_grok_home)}"
export GROK_SESSION_ID="test-stop-verify-$$"
export GROK_WORKSPACE_ROOT="${HOME}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Allow: no session todos
printf '%s\n' '{"hookEventName":"stop","sessionId":"'"$GROK_SESSION_ID"'","cwd":"'"$GROK_WORKSPACE_ROOT"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","stopReason":"end_turn"}' \
  | GROK_HOOK_EVENT=stop bash "${HOOKS_DIR}/run-hook.sh" stop >"${tmpdir}/allow.json"
rg -q '^\{\}$|^$' "${tmpdir}/allow.json" || { echo "expected empty allow JSON, got:"; cat "${tmpdir}/allow.json"; exit 1; }

# Block: fake todos via resources_state.json
sess_dir="${GROK_HOME}/sessions/%2Ftest%2F/${GROK_SESSION_ID}"
mkdir -p "$sess_dir"
cat >"${sess_dir}/resources_state.json" <<'JSON'
{
  "grok_build.TodoState/todo_write/test": {
    "state": "{\"todos\":[{\"id\":\"1\",\"content\":\"Finish stop hook\",\"status\":\"in_progress\"}]}"
  }
}
JSON

printf '%s\n' '{"hookEventName":"stop","sessionId":"'"$GROK_SESSION_ID"'","cwd":"'"$GROK_WORKSPACE_ROOT"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","stopReason":"end_turn"}' \
  | GROK_HOOK_EVENT=stop bash "${HOOKS_DIR}/run-hook.sh" stop >"${tmpdir}/block.json"
rg -q '"decision":"block"' "${tmpdir}/block.json" || { echo "expected block decision, got:"; cat "${tmpdir}/block.json"; exit 1; }

rm -rf "${GROK_HOME}/state/stop-verify/${GROK_SESSION_ID}" "${sess_dir}"

echo "stop-hook (todo continuation): OK"