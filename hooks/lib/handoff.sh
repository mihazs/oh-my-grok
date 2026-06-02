#!/usr/bin/env bash
# Session handoff (/handoff) — ported from oh-my-openagent HANDOFF_TEMPLATE.

HANDOFF_STATE_DIR="${HANDOFF_STATE_DIR:-.omg/handoffs}"

handoff_prompt_matches() {
  local prompt="$1"
  python3 - "$prompt" <<'PY'
import re, sys
text = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
if re.match(r"^/?handoff(?:\s|$)", text, re.I):
    raise SystemExit(0)
raise SystemExit(1)
PY
}

# Injected on /handoff — mirrors omo builtin command wrapper (execute skill phases).
handoff_inject_template() {
  local session_id="${GROK_SESSION_ID:-unknown}"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S)"
  cat <<EOF
<HANDOFF_COMMAND>
The user invoked **/handoff** (oh-my-openagent handoff port).

**Read the handoff skill now** if you have not already, then follow it exactly (PHASE 0 → 4).

<session-context>
Session ID: ${session_id}
Timestamp: ${ts}
</session-context>

## EXECUTE NOW

PHASE 0: Validate there is meaningful context to hand off.
PHASE 1: Gather todos, .omg/ state, git status/diff, AGENTS.md.
PHASE 2–3: Emit the HANDOFF CONTEXT block (verbatim user requests; max 10 key files).
Save copy to .omg/handoffs/handoff-<timestamp>.md
PHASE 4: Tell the user how to paste into a **new Grok session**.

Do not start unrelated work until the handoff is delivered.
</HANDOFF_COMMAND>
EOF
}

collect_user_prompt_handoff() {
  local stdin_file="${1:-}"
  local prompt=""
  if [ -n "$stdin_file" ] && [ -s "$stdin_file" ]; then
    prompt="$(
      python3 - "$stdin_file" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
for key in ("prompt", "userPrompt", "user_prompt", "message", "text"):
    v = data.get(key)
    if isinstance(v, str) and v.strip():
        print(v.strip())
        raise SystemExit(0)
raise SystemExit(1)
PY
    )" || true
  fi
  [ -n "$prompt" ] || return 0
  handoff_prompt_matches "$prompt" || return 0
  mark_skill_loaded "handoff" 2>/dev/null || true
  handoff_inject_template
}