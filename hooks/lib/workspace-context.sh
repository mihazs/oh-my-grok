#!/usr/bin/env bash
# Per-prompt workspace AGENTS.md + oh-my-grok plugin rules (merged UserPromptSubmit).
set -euo pipefail

# Max bytes per file / total injected block (avoid context blow-up on huge AGENTS.md).
WORKSPACE_AGENTS_MAX_BYTES="${WORKSPACE_AGENTS_MAX_BYTES:-16384}"
PLUGIN_RULE_MAX_BYTES="${PLUGIN_RULE_MAX_BYTES:-8192}"
WORKSPACE_CONTEXT_MAX_BYTES="${WORKSPACE_CONTEXT_MAX_BYTES:-32768}"

collect_workspace_prompt_context() {
  local workspace="${GROK_WORKSPACE_ROOT:-${PWD:-}}"
  local plugin_root="${PLUGIN_ROOT:-}"
  [ -n "$workspace" ] || return 0
  WORKSPACE="$workspace" PLUGIN_ROOT="$plugin_root" \
    WORKSPACE_AGENTS_MAX_BYTES="$WORKSPACE_AGENTS_MAX_BYTES" \
    PLUGIN_RULE_MAX_BYTES="$PLUGIN_RULE_MAX_BYTES" \
    WORKSPACE_CONTEXT_MAX_BYTES="$WORKSPACE_CONTEXT_MAX_BYTES" \
    python3 <<'PY'
import os, sys

workspace = os.environ.get("WORKSPACE") or ""
plugin_root = os.environ.get("PLUGIN_ROOT") or ""
agents_max = int(os.environ.get("WORKSPACE_AGENTS_MAX_BYTES", "16384"))
rule_max = int(os.environ.get("PLUGIN_RULE_MAX_BYTES", "8192"))
total_max = int(os.environ.get("WORKSPACE_CONTEXT_MAX_BYTES", "32768"))

def read_capped(path: str, limit: int) -> tuple[str, bool]:
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            data = f.read(limit + 1)
    except OSError:
        return "", False
    truncated = len(data) > limit
    if truncated:
        data = data[:limit]
    return data.rstrip(), truncated

parts: list[str] = []
used = 0

agents_path = os.path.join(workspace, "AGENTS.md")
if os.path.isfile(agents_path):
    body, trunc = read_capped(agents_path, min(agents_max, total_max - used))
    if body:
        rel = os.path.relpath(agents_path, workspace) if workspace else "AGENTS.md"
        header = f"<WORKSPACE_AGENTS path=\"{rel}\">"
        if trunc:
            header = f"<WORKSPACE_AGENTS path=\"{rel}\" truncated=\"true\">"
        block = header + "\n" + body + "\n</WORKSPACE_AGENTS>"
        parts.append(block)
        used += len(block.encode("utf-8"))

rules_dir = os.path.join(plugin_root, "rules") if plugin_root else ""
if rules_dir and os.path.isdir(rules_dir):
    rule_files = sorted(
        f for f in os.listdir(rules_dir) if f.endswith(".md") and os.path.isfile(os.path.join(rules_dir, f))
    )
    for name in rule_files:
        if used >= total_max:
            break
        path = os.path.join(rules_dir, name)
        cap = min(rule_max, total_max - used)
        if cap <= 0:
            break
        body, trunc = read_capped(path, cap)
        if not body:
            continue
        tag = f"<OMG_PLUGIN_RULE file=\"rules/{name}\">"
        if trunc:
            tag = f"<OMG_PLUGIN_RULE file=\"rules/{name}\" truncated=\"true\">"
        block = tag + "\n" + body + f"\n</OMG_PLUGIN_RULE>"
        parts.append(block)
        used += len(block.encode("utf-8"))

if parts:
    print("\n\n".join(parts))
PY
}