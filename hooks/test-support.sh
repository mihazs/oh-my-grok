#!/usr/bin/env bash
# Minimal helpers for hooks/test-*.sh (runtime is Go omg-hook).
set -euo pipefail

resolve_grok_home() {
  local candidate="${GROK_HOME:-}"
  if [ -n "$candidate" ] && [[ "$candidate" != *'${'* ]] && [[ "$candidate" == /* ]]; then
    printf '%s' "$candidate"
    return 0
  fi
  if [ -n "${HOME:-}" ]; then
    printf '%s' "${HOME}/.grok"
    return 0
  fi
  printf '%s' "/tmp/.grok"
}

hashline_cache_dir() {
  printf '%s/state/hashline/%s' "$(resolve_grok_home)" "${GROK_SESSION_ID:-unknown}"
}

hashline_cache_path() {
  local file_path="$1"
  local digest
  digest="$(printf '%s' "$file_path" | sha256sum | awk '{print $1}')"
  mkdir -p "$(hashline_cache_dir)"
  printf '%s/%s.json' "$(hashline_cache_dir)" "$digest"
}

lsp_stash_path() {
  local session_id="${1:-${GROK_SESSION_ID:-unknown}}"
  printf '%s/state/lsp-diagnostics/%s.json' "$(resolve_grok_home)" "$session_id"
}