#!/usr/bin/env bash
# UserPromptSubmit: single merged additionalContext (avoids multi-hook overwrite).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/using-superpowers.sh
source "${SCRIPT_DIR}/lib/using-superpowers.sh"
# shellcheck source=lib/ralph-loop.sh
source "${SCRIPT_DIR}/lib/ralph-loop.sh"
# shellcheck source=lib/intent-gate.sh
source "${SCRIPT_DIR}/lib/intent-gate.sh"
# shellcheck source=lib/prometheus.sh
source "${SCRIPT_DIR}/lib/prometheus.sh"
# shellcheck source=lib/todo-boulder.sh
source "${SCRIPT_DIR}/lib/todo-boulder.sh"
# shellcheck source=lib/handoff.sh
source "${SCRIPT_DIR}/lib/handoff.sh"
# shellcheck source=lib/workspace-context.sh
source "${SCRIPT_DIR}/lib/workspace-context.sh"
# shellcheck source=lib/lsp.sh
source "${SCRIPT_DIR}/lib/lsp.sh"

stdin_tmp="$(mktemp)"
trap 'rm -f "$stdin_tmp"' EXIT
cat >"$stdin_tmp" || true
apply_hook_env_from_stdin "$stdin_tmp"
ensure_skill_catalog

part_super=""
part_workspace=""
part_ralph=""
part_intent=""
part_prometheus=""
part_handoff=""
part_stop=""
part_boulder=""
part_lsp=""
part_gate=""

part_super="$(collect_using_superpowers_on_first_prompt 2>/dev/null || true)"
part_workspace="$(collect_workspace_prompt_context 2>/dev/null || true)"
part_ralph="$(collect_user_prompt_ralph "$stdin_tmp" 2>/dev/null || true)"
part_intent="$(collect_intent_gate_context "$stdin_tmp" 2>/dev/null || true)"
part_prometheus="$(collect_user_prompt_prometheus "$stdin_tmp" 2>/dev/null || true)"
part_handoff="$(collect_user_prompt_handoff "$stdin_tmp" 2>/dev/null || true)"
part_stop="$(collect_stop_continuation_prompt "$stdin_tmp" 2>/dev/null || true)"
part_boulder="$(collect_boulder_prompt_context 2>/dev/null || true)"
part_lsp="$(collect_lsp_context 2>/dev/null || true)"
part_gate="$(build_prompt_reminder 2>/dev/null || true)"

emit_user_prompt_context \
  "$part_super" \
  "$part_workspace" \
  "$part_ralph" \
  "$part_intent" \
  "$part_prometheus" \
  "$part_handoff" \
  "$part_stop" \
  "$part_boulder" \
  "$part_lsp" \
  "$part_gate"