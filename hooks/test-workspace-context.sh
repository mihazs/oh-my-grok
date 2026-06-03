#!/usr/bin/env bash
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-support.sh
source "${HOOKS_DIR}/test-support.sh"

export GROK_HOME="${GROK_HOME:-$(resolve_grok_home)}"
export GROK_SESSION_ID="test-workspace-context-$$"
export GROK_PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-$(cd "${HOOKS_DIR}/.." && pwd)}"
export PLUGIN_ROOT="$GROK_PLUGIN_ROOT"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

ws="${tmpdir}/workspace"
mkdir -p "$ws"
printf '# Test workspace agents\n\nUse rg not grep.\n' >"${ws}/AGENTS.md"

export GROK_WORKSPACE_ROOT="$ws"
payload='{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","cwd":"'"$ws"'","workspaceRoot":"'"$ws"'","prompt":"continue work"}'

printf '%s\n' "$payload" \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt \
  >"${tmpdir}/out.json"

rg -q 'WORKSPACE_AGENTS' "${tmpdir}/out.json" \
  || { echo "expected WORKSPACE_AGENTS in output"; cat "${tmpdir}/out.json"; exit 1; }
rg -q 'Use rg not grep' "${tmpdir}/out.json" \
  || { echo "expected AGENTS.md body"; cat "${tmpdir}/out.json"; exit 1; }
rg -q 'OMG_PLUGIN_RULE' "${tmpdir}/out.json" \
  || { echo "expected plugin rules injection"; cat "${tmpdir}/out.json"; exit 1; }
rg -q 'agent-skill-gate' "${tmpdir}/out.json" \
  || { echo "expected 00-agent-skill-gate rule"; cat "${tmpdir}/out.json"; exit 1; }

# Second prompt still injects workspace context (not first-prompt-only)
printf '%s\n' "$payload" \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt \
  >"${tmpdir}/out2.json"
rg -q 'WORKSPACE_AGENTS' "${tmpdir}/out2.json" \
  || { echo "second prompt: expected WORKSPACE_AGENTS"; cat "${tmpdir}/out2.json"; exit 1; }

echo "workspace-context UserPromptSubmit hook: OK"