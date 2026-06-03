#!/usr/bin/env bash
# IntentGate keyword detector (omo keyword-detector port for Grok UserPromptSubmit).

intent_gate_disabled() {
  case "${OMG_INTENT_GATE:-1}" in
    0|false|no|off) return 0 ;;
    *) return 1 ;;
  esac
}

collect_intent_gate_context() {
  intent_gate_disabled && return 0
  local stdin_file="${1:-}"
  local prompt=""
  prompt="$(intent_gate_extract_prompt "$stdin_file")"
  [ -n "$prompt" ] || return 0
  # Skip if ralph/ulw slash command (ralph-loop.sh owns those)
  if printf '%s' "$prompt" | rg -qi '^/?(ralph-loop|ulw-loop|cancel-ralph)\b'; then
    return 0
  fi
  intent_gate_detect "$prompt"
}

intent_gate_extract_prompt() {
  python3 - "${1:-}" <<'PY'
import json, sys
path = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else ""
data = {}
if path:
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        pass
for k in ("prompt", "userPrompt", "user_prompt", "message"):
    v = data.get(k)
    if isinstance(v, str) and v.strip():
        print(v.strip())
        break
PY
}

intent_gate_detect() {
  python3 - "$@" <<'PY'
import re, sys

text = sys.argv[1] if len(sys.argv) > 1 else ""
# Strip code blocks (omo removeCodeBlocks)
text = re.sub(r"```[\s\S]*?```", "", text)
text = re.sub(r"`[^`]+`", "", text)

SEARCH = re.compile(
    r"\b(search|find|locate|lookup|explore|discover|scan|grep|query)\b|where\s+is|show\s+me",
    re.I,
)
ANALYZE = re.compile(
    r"\b(analyze|analyse|investigate|audit|review|assess|evaluate|diagnose|debug|root\s+cause)\b",
    re.I,
)
TEAM = re.compile(r"\b(team\s+mode|team\s+up|parallel\s+agents?)\b", re.I)
HYPERPLAN = re.compile(r"\b(hpp|hyperplan)\b", re.I)
HYPER_ULW = re.compile(
    r"\b(?:hpp|hyperplan)\s+(?:ulw|ultrawork)\b|\b(?:ulw|ultrawork)\s+(?:hpp|hyperplan)\b",
    re.I,
)

modes = []
if HYPER_ULW.search(text):
    modes.append(("hyperplan-ultrawork", "HYPERPLAN ULTRAWORK MODE: load hyperplan skill; apply ultrawork execution."))
elif HYPERPLAN.search(text):
    modes.append(("hyperplan", "HYPERPLAN MODE: adversarial planning — load hyperplan skill before writing plans."))
if SEARCH.search(text):
    modes.append(("search", "SEARCH MODE: read-only exploration first; cite file paths; do not mutate until intent is clear."))
if ANALYZE.search(text):
    modes.append(("analyze", "ANALYZE MODE: investigation/report first; minimal diffs until root cause is confirmed."))
if TEAM.search(text):
    modes.append(("team", "TEAM MODE: fan out independent work via Task tool with isolated subagents."))

if not modes:
    raise SystemExit(0)

lines = ["<INTENT_GATE>", "Classified intent from this message (turn-local; not conversation momentum):"]
for _t, msg in modes:
    lines.append(f"- {msg}")
lines.append("</INTENT_GATE>")
print("\n".join(lines))
PY
}