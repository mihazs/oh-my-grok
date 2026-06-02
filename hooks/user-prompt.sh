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
# shellcheck source=lib/todo-boulder.sh
source "${SCRIPT_DIR}/lib/todo-boulder.sh"
# shellcheck source=lib/handoff.sh
source "${SCRIPT_DIR}/lib/handoff.sh"

stdin_tmp="$(mktemp)"
trap 'rm -f "$stdin_tmp"' EXIT
cat >"$stdin_tmp" || true
apply_hook_env_from_stdin "$stdin_tmp"
ensure_skill_catalog

part_super=""
part_ralph=""
part_handoff=""
part_stop=""
part_boulder=""
part_gate=""

part_super="$(collect_using_superpowers_on_first_prompt 2>/dev/null || true)"
part_ralph="$(collect_user_prompt_ralph "$stdin_tmp" 2>/dev/null || true)"
part_handoff="$(collect_user_prompt_handoff "$stdin_tmp" 2>/dev/null || true)"
part_stop="$(collect_stop_continuation_prompt "$stdin_tmp" 2>/dev/null || true)"
part_boulder="$(collect_boulder_prompt_context 2>/dev/null || true)"
part_gate="$(build_prompt_reminder 2>/dev/null || true)"

emit_user_prompt_context \
  "$part_super" \
  "$part_ralph" \
  "$part_handoff" \
  "$part_stop" \
  "$part_boulder" \
  "$part_gate"