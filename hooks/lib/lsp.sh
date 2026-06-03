#!/usr/bin/env bash
# LSP diagnostics stash, post-edit collection, UserPrompt context, Stop enforcement.

lsp_stash_path() {
  local session_id="${1:-${GROK_SESSION_ID:-unknown}}"
  printf '%s/state/lsp-diagnostics/%s.json' "$GROK_HOME" "$session_id"
}

lsp_enforce_enabled() {
  [ "${OMG_LSP_ENFORCE:-1}" != "0" ]
}

_lsp_tools_module() {
  local root="${GROK_PLUGIN_ROOT:-${PLUGIN_ROOT:-}}"
  [ -n "$root" ] || return 1
  local mod="${root}/vendor/lsp-tools-mcp/dist/tools.js"
  [ -f "$mod" ] || return 1
  printf '%s' "$mod"
}

# Returns diagnostic text on stdout; non-zero if skipped/unavailable.
lsp_run_diagnostics() {
  local file_path="$1"
  [ -n "$file_path" ] || return 1

  if [ -n "${OMG_LSP_MOCK_DIAG:-}" ]; then
    printf '%s' "$OMG_LSP_MOCK_DIAG"
    return 0
  fi

  local tools_mod
  tools_mod="$(_lsp_tools_module)" || return 1
  command -v node >/dev/null 2>&1 || return 1

  local workspace="${GROK_WORKSPACE_ROOT:-${PWD:-}}"
  local abs_path="$file_path"
  if [[ "$abs_path" != /* ]] && [ -n "$workspace" ]; then
    abs_path="${workspace%/}/${file_path#./}"
  fi
  [ -f "$abs_path" ] || return 1

  node --input-type=module - "$tools_mod" "$abs_path" <<'NODE' 2>/dev/null
import { pathToFileURL } from "node:url";
import { executeLspDiagnostics } from pathToFileURL(process.argv[2]).href;

const filePath = process.argv[3];
try {
  const result = await executeLspDiagnostics({ filePath, severity: "error" });
  const text = result.content.map((block) => block.text).join("\n").trim();
  process.stdout.write(text);
} catch (error) {
  const message =
    error instanceof Error ? (error.message || String(error)) : String(error);
  process.stderr.write(message);
  process.exit(1);
}
NODE
}

extract_mutated_file_paths() {
  local input_file="${1:-}"
  [ -n "$input_file" ] && [ -s "$input_file" ] || return 0
  python3 - "$input_file" <<'PY'
import json
import sys

MUTATION_TOOLS = {
    "apply_patch",
    "write",
    "strreplace",
    "str_replace",
    "edit",
    "multiedit",
    "multi_edit",
    "editnotebook",
}

PATCH_PREFIXES = ("*** Add File: ", "*** Update File: ", "*** Move to: ")


def is_record(value):
    return isinstance(value, dict)


def dig(obj, *keys):
    for key in keys:
        if not is_record(obj) or key not in obj:
            return None
        obj = obj[key]
    return obj


def tool_name(data):
    for key in ("toolName", "tool_name", "tool"):
        value = data.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def tool_input(data):
    for key in ("toolInput", "tool_input", "input", "arguments", "rawInput"):
        block = data.get(key)
        if is_record(block):
            return block
    return {}


def tool_response(data):
    for key in ("toolResponse", "tool_response", "response", "output"):
        block = data.get(key)
        if is_record(block):
            return block
    return None


def is_mutation_tool(name):
    return name.lower() in MUTATION_TOOLS


def is_failed_response(response):
    if not is_record(response):
        return False
    return (
        response.get("isError") is True
        or response.get("is_error") is True
        or response.get("error") is True
        or response.get("status") == "error"
    )


def add_string(paths, value):
    if isinstance(value, str) and value:
        paths.add(value)


def add_array(paths, value):
    if not isinstance(value, list):
        return
    for item in value:
        add_string(paths, item)


def extract_patch_header(line):
    for prefix in PATCH_PREFIXES:
        if line.startswith(prefix):
            return line[len(prefix) :].strip()
    return None


def add_patch_payload(paths, value):
    if not isinstance(value, str):
        return
    for line in value.split("\n"):
        path = extract_patch_header(line)
        if path:
            paths.add(path)


def add_patch_files(paths, value):
    if not isinstance(value, list):
        return
    for item in value:
        if not is_record(item):
            continue
        for key in ("path", "filePath", "file_path", "movePath", "move_path"):
            add_string(paths, item.get(key))


def extract_paths(data):
    name = tool_name(data)
    if name and not is_mutation_tool(name):
        return []
    if is_failed_response(tool_response(data)):
        return []

    block = tool_input(data)
    paths = set()
    for key in ("path", "filePath", "file_path", "target_file", "targetFile"):
        add_string(paths, block.get(key))
    for key in ("paths", "filePaths", "file_paths"):
        add_array(paths, block.get(key))
    for key in ("input", "patch", "command"):
        add_patch_payload(paths, block.get(key))
    for key in ("files", "changes"):
        add_patch_files(paths, block.get(key))
    return sorted(paths)


try:
    with open(sys.argv[1], encoding="utf-8") as f:
        payload = json.load(f)
except (OSError, json.JSONDecodeError):
    raise SystemExit(0)

if not is_record(payload):
    raise SystemExit(0)

for path in extract_paths(payload):
    print(path)
PY
}

lsp_merge_diagnostics_into_stash() {
  local stash_path="$1"
  local file_path="$2"
  local diagnostics="$3"
  LSP_STASH_PATH="$stash_path" LSP_FILE_PATH="$file_path" LSP_DIAGNOSTICS_TEXT="$diagnostics" \
    python3 - <<'PY'
import json
import os
import re
import sys
from datetime import datetime, timezone

stash_path = os.environ["LSP_STASH_PATH"]
file_path = os.environ["LSP_FILE_PATH"]
diagnostics = os.environ.get("LSP_DIAGNOSTICS_TEXT", "")

CLEAN_TEXT = "No diagnostics found"
UNSUPPORTED_PREFIX = "No LSP server configured for extension:"
ERROR_PATTERN = re.compile(
    r"^(?:error|warning|information|hint)\[[^\]\r\n]+\] \(\d+:\d+:",
    re.MULTILINE,
)


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def is_unavailable(text):
    normalized = (text or "").strip()
    if not normalized:
        return False
    markers = (
        "LSP request timeout (method: initialize)",
        "LSP server is still initializing",
        "NOT INSTALLED",
        "Command not found:",
    )
    return any(marker in normalized for marker in markers)


def has_errors(text):
    normalized = (text or "").strip()
    if not normalized:
        return False
    if normalized == CLEAN_TEXT:
        return False
    if normalized.startswith(UNSUPPORTED_PREFIX):
        return False
    if is_unavailable(normalized):
        return False
    if ERROR_PATTERN.search(normalized):
        return True
    lowered = normalized.lower()
    return lowered.startswith("error") or "error[" in lowered


def read_stash(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return {"version": 1, "files": {}, "updated_at": now_iso()}
    if not isinstance(data, dict):
        return {"version": 1, "files": {}, "updated_at": now_iso()}
    files = data.get("files")
    if not isinstance(files, dict):
        files = {}
    return {
        "version": data.get("version", 1),
        "files": files,
        "updated_at": data.get("updated_at") or now_iso(),
    }


def write_stash(path, stash):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    stash["updated_at"] = now_iso()
    with open(path, "w", encoding="utf-8") as f:
        json.dump(stash, f, indent=2)
        f.write("\n")


stash = read_stash(stash_path)
entry = {
    "diagnostics": diagnostics,
    "has_errors": has_errors(diagnostics),
    "unavailable": is_unavailable(diagnostics),
    "updated_at": now_iso(),
}
if entry["has_errors"]:
    stash["files"][file_path] = entry
else:
    stash["files"].pop(file_path, None)
write_stash(stash_path, stash)
PY
}

lsp_update_stash_for_paths() {
  local input_file="${1:-}"
  local workspace="${GROK_WORKSPACE_ROOT:-${PWD:-}}"
  local stash_path
  stash_path="$(lsp_stash_path)"
  mkdir -p "$(dirname "$stash_path")"

  local rel_path abs_path diag
  while IFS= read -r rel_path; do
    [ -n "$rel_path" ] || continue
    abs_path="$rel_path"
    if [[ "$abs_path" != /* ]] && [ -n "$workspace" ]; then
      abs_path="${workspace%/}/${rel_path#./}"
    fi
    if [ ! -f "$abs_path" ]; then
      continue
    fi
    diag=""
    if ! diag="$(lsp_run_diagnostics "$abs_path" 2>/dev/null)"; then
      continue
    fi
    lsp_merge_diagnostics_into_stash "$stash_path" "$abs_path" "$diag"
  done < <(extract_mutated_file_paths "$input_file")
}

collect_lsp_context() {
  local stash_path
  stash_path="$(lsp_stash_path)"
  [ -f "$stash_path" ] || return 0
  LSP_STASH_PATH="$stash_path" python3 - <<'PY'
import json
import os
import re

stash_path = os.environ["LSP_STASH_PATH"]
ERROR_PATTERN = re.compile(
    r"^(?:error|warning|information|hint)\[[^\]\r\n]+\] \(\d+:\d+:",
    re.MULTILINE,
)

try:
    with open(stash_path, encoding="utf-8") as f:
        stash = json.load(f)
except (OSError, json.JSONDecodeError):
    raise SystemExit(0)

files = stash.get("files") if isinstance(stash, dict) else {}
if not isinstance(files, dict):
    raise SystemExit(0)

blocks = []
for file_path in sorted(files):
    entry = files.get(file_path)
    if not isinstance(entry, dict) or not entry.get("has_errors"):
        continue
    diagnostics = (entry.get("diagnostics") or "").strip()
    lines = [f"LSP diagnostics for {file_path}:"]
    if diagnostics:
        for chunk in diagnostics.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
            chunk = chunk.strip()
            if not chunk:
                continue
            if ERROR_PATTERN.match(chunk):
                lines.append(f"- {chunk}")
            else:
                lines.append(chunk)
    else:
        lines.append("(empty)")
    blocks.append("\n".join(lines))

if not blocks:
    raise SystemExit(0)

body = "\n\n".join(blocks)
print(
    "<LSP_DIAGNOSTICS>\n"
    "Unresolved LSP errors remain from recent edits. Fix these before stopping.\n\n"
    f"{body}\n"
    "</LSP_DIAGNOSTICS>"
)
PY
}

# Prints block reason to stdout and returns 0 to block; returns 1 to allow stop.
evaluate_lsp_stop() {
  local _stdin_file="${1:-}"
  lsp_enforce_enabled || return 1
  local stash_path reason
  stash_path="$(lsp_stash_path)"
  [ -f "$stash_path" ] || return 1
  reason="$(
    LSP_STASH_PATH="$stash_path" python3 - <<'PY'
import json
import os
import re

stash_path = os.environ["LSP_STASH_PATH"]
ERROR_PATTERN = re.compile(
    r"^(?:error|warning|information|hint)\[[^\]\r\n]+\] \(\d+:\d+:",
    re.MULTILINE,
)

try:
    with open(stash_path, encoding="utf-8") as f:
        stash = json.load(f)
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)

files = stash.get("files") if isinstance(stash, dict) else {}
if not isinstance(files, dict):
    raise SystemExit(1)

blocks = []
for file_path in sorted(files):
    entry = files.get(file_path)
    if not isinstance(entry, dict) or not entry.get("has_errors"):
        continue
    diagnostics = (entry.get("diagnostics") or "").strip()
    lines = [f"LSP diagnostics for {file_path}:"]
    if diagnostics:
        for chunk in diagnostics.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
            chunk = chunk.strip()
            if not chunk:
                continue
            if ERROR_PATTERN.match(chunk):
                lines.append(f"- {chunk}")
            else:
                lines.append(chunk)
    else:
        lines.append("(empty)")
    blocks.append("\n".join(lines))

if not blocks:
    raise SystemExit(1)

lines = [
    "Stop blocked: LSP errors remain in files you edited this session.",
    "Run diagnostics on each file and fix errors before stopping.",
    "",
]
lines.extend("\n\n".join(blocks).splitlines())
print("\n".join(lines).rstrip())
PY
  )" || return 1
  [ -n "$reason" ] || return 1
  printf '%s' "$reason"
  return 0
}

cleanup_lsp_session_state() {
  local session_id="${GROK_SESSION_ID:-}"
  [ -n "$session_id" ] || return 0
  rm -f "$(lsp_stash_path "$session_id")" 2>/dev/null || true
}