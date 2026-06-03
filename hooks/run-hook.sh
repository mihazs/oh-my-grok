#!/usr/bin/env bash
# Dispatch hook subcommands to omg-hook (Go) or legacy bash scripts.
set -euo pipefail
if [ $# -lt 1 ]; then
  echo "run-hook.sh: missing subcommand" >&2
  exit 1
fi
SUBCOMMAND="$1"
shift
# Legacy tests and docs used *.sh script names.
case "$SUBCOMMAND" in
  *.sh) SUBCOMMAND="${SUBCOMMAND%.sh}" ;;
esac
case "$SUBCOMMAND" in
  pre-tool-mutate) SUBCOMMAND="pre-tool-use" ;;
  stop-hook) SUBCOMMAND="stop" ;;
esac
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-$ROOT}"

# Subcommands implemented in Go (grow as migration proceeds).
GO_SUBCOMMANDS="session-start pre-tool-use post-tool-read stop"

legacy_script() {
  case "$1" in
    session-start) printf '%s' "session-start.sh" ;;
    user-prompt) printf '%s' "user-prompt.sh" ;;
    pre-tool-use) printf '%s' "pre-tool-mutate.sh" ;;
    post-tool-read) printf '%s' "post-tool-read.sh" ;;
    post-tool-todo-write) printf '%s' "post-tool-todo-write.sh" ;;
    post-tool-lsp) printf '%s' "post-tool-lsp.sh" ;;
    stop) printf '%s' "stop-hook.sh" ;;
    session-end) printf '%s' "session-end.sh" ;;
    *) return 1 ;;
  esac
}

if legacy="$(legacy_script "$SUBCOMMAND" 2>/dev/null)"; then
  :
else
  echo "run-hook.sh: unknown subcommand: $SUBCOMMAND" >&2
  exit 1
fi

use_go=0
if [[ " ${GO_SUBCOMMANDS} " == *" ${SUBCOMMAND} "* ]]; then
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *)
      echo "run-hook.sh: unsupported arch: $(uname -m)" >&2
      exit 1
      ;;
  esac
  case "$os" in
    linux) bin="${PLUGIN_ROOT}/bin/omg-hook-linux-${arch}" ;;
    darwin) bin="${PLUGIN_ROOT}/bin/omg-hook-darwin-${arch}" ;;
    mingw*|msys*|cygwin*|windows*)
      bin="${PLUGIN_ROOT}/bin/omg-hook-windows-amd64.exe"
      ;;
    *)
      echo "run-hook.sh: unsupported OS: $(uname -s)" >&2
      exit 1
      ;;
  esac
  if [ -x "$bin" ]; then
    use_go=1
  fi
fi

if [ "$use_go" -eq 1 ]; then
  exec "$bin" "$SUBCOMMAND" "$@"
fi

exec bash "${SCRIPT_DIR}/${legacy}" "$@"