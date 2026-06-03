#!/usr/bin/env bash
# Dispatch hook subcommands to omg-hook (Go binary).
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
if [ ! -x "$bin" ]; then
  echo "run-hook.sh: missing hook binary: $bin" >&2
  echo "run-hook.sh: run scripts/build-hook.sh from the plugin root" >&2
  exit 1
fi
exec "$bin" "$SUBCOMMAND" "$@"