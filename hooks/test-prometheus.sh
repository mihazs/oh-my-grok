#!/usr/bin/env bash
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-support.sh
source "${HOOKS_DIR}/test-support.sh"

export GROK_PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-$(cd "${HOOKS_DIR}/.." && pwd)}"
export GROK_SESSION_ID="test-prom-$$"
tmpdir="$(mktemp -d)"
export GROK_WORKSPACE_ROOT="$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/.omg/plans"

printf '%s\n' '{"hookEventName":"UserPromptSubmit","prompt":"/plan add OAuth"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt >"${tmpdir}/plan.json"
rg -q 'PROMETHEUS_PLAN_MODE' "${tmpdir}/plan.json" || { cat "${tmpdir}/plan.json"; exit 1; }

# Deny write outside .omg during plan mode
export OMG_PLAN_MODE=1
printf '%s\n' '{"hookEventName":"PreToolUse","toolName":"Write","toolInput":{"path":"src/foo.ts","contents":"x"}}' \
  | GROK_HOOK_EVENT=pre_tool_use bash "${HOOKS_DIR}/run-hook.sh" pre-tool-use >"${tmpdir}/deny.json" || true
rg -q '"decision":"deny"' "${tmpdir}/deny.json" || { cat "${tmpdir}/deny.json"; exit 1; }

echo "prometheus hooks: OK"