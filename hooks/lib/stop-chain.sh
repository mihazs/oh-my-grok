#!/usr/bin/env bash
# Ordered Stop-hook continuation chain (first match wins).

# shellcheck source=lib/ralph-loop.sh
# shellcheck source=lib/todo-boulder.sh
# shellcheck source=lib/stop-pending.sh
# shellcheck source=lib/lsp.sh

# Priority:
#   1. Ralph / ultrawork (explicit loop state; not gated by /stop-continuation)
#   2. Boulder plan (.omg/boulder.json) — skipped when auto-continue paused
#   3. Todo list (TodoWrite) — skipped when paused
#   4. LSP diagnostics stash — skipped when OMG_LSP_ENFORCE=0
#   5. Root plan.md checkboxes — skipped when paused
#
# Prints block reason to stdout and returns 0 to block; returns 1 to allow stop.
evaluate_stop_hook_chain() {
  local stdin_file="${1:-}"
  local reason=""

  if reason="$(evaluate_ralph_loop_stop "$stdin_file")"; then
    printf '%s' "$reason"
    return 0
  fi

  if auto_continue_paused; then
    return 1
  fi

  if reason="$(evaluate_boulder_stop "$stdin_file")"; then
    printf '%s' "$reason"
    return 0
  fi

  if reason="$(evaluate_todo_continuation_stop "$stdin_file")"; then
    printf '%s' "$reason"
    return 0
  fi

  if reason="$(evaluate_lsp_stop "$stdin_file")"; then
    printf '%s' "$reason"
    return 0
  fi

  if reason="$(evaluate_stop_pending_work "$stdin_file")"; then
    printf '%s' "$reason"
    return 0
  fi

  return 1
}