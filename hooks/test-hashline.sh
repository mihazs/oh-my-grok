#!/usr/bin/env bash
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HOOKS_DIR}/.." && pwd)"

GOFLAGS=-mod=mod go test "${ROOT}/internal/hashline/..." -run 'Golden|TrimEnd' -count=1

# shellcheck source=test-support.sh
source "${HOOKS_DIR}/test-support.sh"

reset_session_state() {
  local dir
  dir="$(printf '%s/state/skill-gate/%s' "$(resolve_grok_home)" "${GROK_SESSION_ID:-unknown}")"
  mkdir -p "$dir"
  : >"${dir}/skills.loaded"
  printf '[]\n' >"${dir}/all-skills.json"
}

mark_skill_loaded() {
  local id="$1"
  local dir
  dir="$(printf '%s/state/skill-gate/%s' "$(resolve_grok_home)" "${GROK_SESSION_ID:-unknown}")"
  mkdir -p "$dir"
  printf '%s\n' "$id" >>"${dir}/skills.loaded"
}

export GROK_HOME="${GROK_HOME:-$(resolve_grok_home)}"
export GROK_SESSION_ID="test-hashline-hook-$$"
export GROK_PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-$ROOT}"
export OMG_HASHLINE=1

ws="$(mktemp -d)"
export GROK_WORKSPACE_ROOT="$ws"
trap 'rm -rf "$ws" "$(hashline_cache_dir)"' EXIT

printf 'hello world\n' >"${ws}/foo.ts"

printf '%s\n' '{"hookEventName":"PostToolUse","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","toolName":"Read","toolInput":{"path":"'"${ws}/foo.ts"'"}}' \
  | GROK_HOOK_EVENT=post_tool_use bash "${HOOKS_DIR}/run-hook.sh" post-tool-read >/dev/null
cache_file="$(hashline_cache_path "${ws}/foo.ts")"
test -f "$cache_file" || {
  echo "post-tool-read did not write hashline cache at $cache_file"
  exit 1
}

good_tag="$(python3 -c "import json; print(json.load(open('${cache_file}'))['lines']['1'])")"

printf '%s\n' '{"hookEventName":"PreToolUse","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","toolName":"StrReplace","toolInput":{"path":"foo.ts","old_string":"1#ZZ\nhello world","new_string":"hi\nhello world"}}' \
  | GROK_HOOK_EVENT=pre_tool_use bash "${HOOKS_DIR}/run-hook.sh" pre-tool-use >"${ws}/deny.json" || true
rg -q '"decision":"deny"' "${ws}/deny.json" || { echo "expected deny for stale hash"; cat "${ws}/deny.json"; exit 1; }
rg -q 'stale LINE#ID' "${ws}/deny.json" || { echo "expected stale message"; cat "${ws}/deny.json"; exit 1; }

reset_session_state
mark_skill_loaded "agent-skill-gate"
printf '%s\n' '{"hookEventName":"PreToolUse","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","toolName":"StrReplace","toolInput":{"path":"foo.ts","old_string":"1#'"${good_tag}"'\nhello world","new_string":"hi\nhello world"}}' \
  | GROK_HOOK_EVENT=pre_tool_use bash "${HOOKS_DIR}/run-hook.sh" pre-tool-use >"${ws}/allow.json"
rg -q '"decision":"allow"' "${ws}/allow.json" || { echo "expected allow for fresh hash"; cat "${ws}/allow.json"; exit 1; }

printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"continue"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt >"${ws}/prompt.json"
rg -q 'HASHLINE_CACHE' "${ws}/prompt.json" || { echo "missing HASHLINE_CACHE"; cat "${ws}/prompt.json"; exit 1; }
rg -q 'foo.ts' "${ws}/prompt.json" || { echo "missing cached path in prompt"; cat "${ws}/prompt.json"; exit 1; }

echo "hashline: OK"