#!/usr/bin/env bash
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-support.sh
source "${HOOKS_DIR}/test-support.sh"

export GROK_HOME="${GROK_HOME:-$(resolve_grok_home)}"
export GROK_SESSION_ID="test-using-superpowers-$$"
export GROK_WORKSPACE_ROOT="${HOME}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir" "${GROK_HOME}/state/using-superpowers/${GROK_SESSION_ID}"' EXIT

payload='{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","cwd":"'"$GROK_WORKSPACE_ROOT"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"hello"}'

# First prompt: must inject using-superpowers
printf '%s\n' "$payload" \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt \
  >"${tmpdir}/first.json"
rg -q 'USING_SUPERPOWERS_FIRST_PROMPT|using-superpowers' "${tmpdir}/first.json" \
  || { echo "first prompt: expected skill injection"; cat "${tmpdir}/first.json"; exit 1; }

# Second prompt: no using-superpowers block (skill-gate reminder is OK)
printf '%s\n' "$payload" \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt \
  >"${tmpdir}/second.json"
rg -q 'USING_SUPERPOWERS_FIRST_PROMPT' "${tmpdir}/second.json" 2>/dev/null && {
  echo "second prompt: must not re-inject using-superpowers:"
  cat "${tmpdir}/second.json"
  exit 1
}

echo "using-superpowers first-prompt hook: OK"