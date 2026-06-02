#!/usr/bin/env bash
# Ralph + Ultrawork loops (oh-my-openagent compatible) for Grok hooks.

RALPH_DEFAULT_MAX_ITERATIONS="${RALPH_DEFAULT_MAX_ITERATIONS:-100}"
ULW_DEFAULT_MAX_ITERATIONS="${ULW_DEFAULT_MAX_ITERATIONS:-500}"
RALPH_DEFAULT_COMPLETION_PROMISE="${RALPH_DEFAULT_COMPLETION_PROMISE:-DONE}"
ULW_VERIFICATION_PROMISE="${ULW_VERIFICATION_PROMISE:-VERIFIED}"
RALPH_STATE_REL_PATH="${RALPH_STATE_REL_PATH:-.omg/ralph-loop.local.md}"
RALPH_ORACLE_SUBAGENT="${RALPH_ORACLE_SUBAGENT:-code-reviewer}"

ralph_state_path() {
  local workspace="${1:-}"
  if [ -z "$workspace" ] || [ ! -d "$workspace" ]; then
    return 1
  fi
  printf '%s/%s' "$workspace" "$RALPH_STATE_REL_PATH"
}

ralph_loop_template() {
  local max="${1:-$RALPH_DEFAULT_MAX_ITERATIONS}"
  local promise="${2:-$RALPH_DEFAULT_COMPLETION_PROMISE}"
  cat <<EOF
You are in a **Ralph Loop** — a self-referential development loop that runs until the task is complete.

## How it works

1. Work on the task continuously until it is **fully** done.
2. When complete, output exactly: \`<promise>${promise}</promise>\`
3. If you stop without that tag, the Stop hook injects a continuation prompt.
4. Maximum iterations: ${max}.

## Rules

- Finish the whole task, not a partial slice.
- Do not emit the completion promise until the work is truly complete.
- Use todos to track multi-step work.

## Cancel

\`/cancel-ralph\`

## Your task

EOF
}

ulw_loop_template() {
  local max="${1:-$ULW_DEFAULT_MAX_ITERATIONS}"
  local promise="${2:-$RALPH_DEFAULT_COMPLETION_PROMISE}"
  local oracle="${3:-$RALPH_ORACLE_SUBAGENT}"
  cat <<EOF
You are in an **ULTRAWORK Loop** — Ralph loop with mandatory verification before exit.

## How it works

1. Work continuously until the task is **fully** complete.
2. When done, output: \`<promise>${promise}</promise>\` — this does **not** end the loop.
3. The Stop hook will require **Oracle verification** via \`task(subagent_type="${oracle}", ...)\`.
4. The loop ends only after verification emits \`<promise>${ULW_VERIFICATION_PROMISE}</promise>\` (Agent: oracle in the verification report).
5. Maximum iterations: ${max}.

## Rules

- Do not treat \`<promise>${promise}</promise>\` as final completion until Oracle verifies.
- After emitting DONE, run the verification subagent when the hook instructs you.
- Ask Oracle to review skeptically; include the original task and evidence of what changed.
- Use todos for multi-step work.

## Cancel

\`/cancel-ralph\`

## Your task

EOF
}

_ralph_py() {
  python3 - "$@" <<'PY'
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ACTION = os.environ.get("RALPH_ACTION", "")
ULW_VERIFICATION_PROMISE = os.environ.get("ULW_VERIFICATION_PROMISE", "VERIFIED")
RALPH_ORACLE_SUBAGENT = os.environ.get("RALPH_ORACLE_SUBAGENT", "code-reviewer")


def strip_quotes(s: str) -> str:
    s = (s or "").strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'":
        return s[1:-1]
    return s


def parse_frontmatter(text: str):
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---\n", 4)
    if end < 0:
        return {}, text
    header = text[4:end]
    body = text[end + 5 :]
    data = {}
    for line in header.splitlines():
        if ":" not in line:
            continue
        key, val = line.split(":", 1)
        key, val = key.strip(), val.strip()
        if val.lower() == "true":
            data[key] = True
        elif val.lower() == "false":
            data[key] = False
        elif val.isdigit():
            data[key] = int(val)
        else:
            data[key] = strip_quotes(val)
    return data, body


def write_state(path: Path, state: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "---",
        f"active: {str(state.get('active', True)).lower()}",
        f"iteration: {state.get('iteration', 1)}",
    ]
    if state.get("max_iterations") is not None:
        lines.append(f"max_iterations: {state['max_iterations']}")
    lines.append(f'completion_promise: "{state.get("completion_promise", "DONE")}"')
    if state.get("initial_completion_promise"):
        lines.append(
            f'initial_completion_promise: "{state["initial_completion_promise"]}"'
        )
    if state.get("session_id"):
        lines.append(f'session_id: "{state["session_id"]}"')
    if state.get("strategy"):
        lines.append(f'strategy: "{state["strategy"]}"')
    if state.get("ultrawork") is not None:
        lines.append(f"ultrawork: {str(state['ultrawork']).lower()}")
    if state.get("verification_pending") is not None:
        lines.append(
            f"verification_pending: {str(state['verification_pending']).lower()}"
        )
    lines.append(f'started_at: "{state.get("started_at", datetime.now(timezone.utc).isoformat())}"')
    lines.append("---")
    lines.append(state.get("prompt", "").strip())
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def read_state(path: Path):
    if not path.is_file():
        return None
    try:
        data, body = parse_frontmatter(path.read_text(encoding="utf-8"))
    except OSError:
        return None
    active = data.get("active") in (True, "true", "True")
    if not active:
        return None
    try:
        iteration = int(data.get("iteration", 0))
    except (TypeError, ValueError):
        return None
    ultrawork = data.get("ultrawork") in (True, "true", "True")
    default_max = (
        int(os.environ.get("ULW_DEFAULT_MAX_ITERATIONS", "500"))
        if ultrawork
        else int(os.environ.get("RALPH_DEFAULT_MAX_ITERATIONS", "100"))
    )
    max_it = data.get("max_iterations")
    if max_it in ("", None):
        max_it = default_max
    else:
        max_it = int(max_it)
    return {
        "active": True,
        "iteration": iteration,
        "max_iterations": max_it,
        "completion_promise": str(data.get("completion_promise") or "DONE"),
        "initial_completion_promise": str(
            data.get("initial_completion_promise")
            or data.get("completion_promise")
            or "DONE"
        ),
        "session_id": str(data.get("session_id") or ""),
        "strategy": str(data.get("strategy") or "continue"),
        "started_at": str(data.get("started_at") or ""),
        "prompt": body.strip(),
        "ultrawork": ultrawork,
        "verification_pending": data.get("verification_pending")
        in (True, "true", "True"),
    }


def clear_state(path: Path):
    try:
        if path.is_file():
            path.unlink()
        return True
    except OSError:
        return False


def parse_loop_args(text: str):
    text = text.strip()
    ultrawork = False
    m = re.match(r"^/?(?:ralph-loop)(?:\s+|$)(.*)$", text, re.I | re.S)
    if not m:
        m = re.match(r"^/?(?:ulw-loop|ultrawork)(?:\s+|$)(.*)$", text, re.I | re.S)
        if not m:
            m = re.match(r"^ultrawork\s+(.+)$", text, re.I | re.S)
            if not m:
                return None
        ultrawork = True
    rest = m.group(1).strip()
    completion_promise = os.environ.get("RALPH_DEFAULT_COMPLETION_PROMISE", "DONE")
    max_iterations = (
        int(os.environ.get("ULW_DEFAULT_MAX_ITERATIONS", "500"))
        if ultrawork
        else int(os.environ.get("RALPH_DEFAULT_MAX_ITERATIONS", "100"))
    )
    strategy = "continue"
    for flag, pattern in (
        ("completion_promise", r"--completion-promise=(\S+)"),
        ("max_iterations", r"--max-iterations=(\d+)"),
        ("strategy", r"--strategy=(reset|continue)"),
    ):
        fm = re.search(pattern, rest, re.I)
        if fm:
            val = fm.group(1)
            if flag == "completion_promise":
                completion_promise = val
            elif flag == "max_iterations":
                max_iterations = int(val)
            elif flag == "strategy":
                strategy = val.lower()
            rest = re.sub(pattern, "", rest, flags=re.I).strip()
    if rest.startswith(('"', "'")):
        q = rest[0]
        end = rest.find(q, 1)
        task = rest[1:end] if end > 0 else rest.strip(q)
    else:
        task = rest.strip()
    return {
        "task": task,
        "completion_promise": completion_promise,
        "max_iterations": max_iterations,
        "strategy": strategy,
        "ultrawork": ultrawork,
    }


def has_promise(text: str, promise: str) -> bool:
    if not text or not promise:
        return False
    pat = re.compile(
        r"<promise>\s*" + re.escape(promise) + r"\s*</promise>",
        re.I,
    )
    return bool(pat.search(text))


def is_oracle_verified(text: str) -> bool:
    if not text:
        return False
    agent_m = re.search(r"^Agent:\s*(\S+)\s*$", text, re.I | re.M)
    if not agent_m or agent_m.group(1).strip().lower() != "oracle":
        return False
    return has_promise(text, ULW_VERIFICATION_PROMISE)


def build_ralph_continuation(state: dict) -> str:
    return (
        "[RALPH LOOP {}/{}]\n"
        "Continue. Output <promise>{}</promise> when fully done.\n\n"
        "Original task:\n{}"
    ).format(
        state["iteration"],
        state["max_iterations"],
        state["completion_promise"],
        state["prompt"],
    )


def build_ulw_verification(state: dict) -> str:
    oracle = RALPH_ORACLE_SUBAGENT
    initial = state.get("initial_completion_promise") or state["completion_promise"]
    return (
        "[ULTRAWORK LOOP VERIFICATION {}/{}]\n"
        "You already emitted <promise>{}</promise>. That does NOT finish the loop.\n\n"
        "REQUIRED NOW:\n"
        f"- Call task(subagent_type=\"{oracle}\", load_skills=[], run_in_background=false, ...)\n"
        "- Ask the verifier to confirm the original task is actually complete\n"
        "- Tell them to review skeptically and look for gaps, regressions, or missing tests\n"
        "- The verifier must end with: Agent: oracle\\n<promise>VERIFIED</promise>\n"
        "- Do not claim final completion until you see <promise>VERIFIED</promise>\n\n"
        "Original task:\n"
        "{}"
    ).format(
        state["iteration"],
        state["max_iterations"],
        initial,
        state["prompt"],
    )


def build_ulw_verification_failed(state: dict) -> str:
    return (
        "[ULTRAWORK LOOP VERIFICATION FAILED {}/{}]\n"
        "Oracle did not emit <promise>VERIFIED</promise>. Fix remaining issues, then request verification again.\n"
        "When ready for another review, output <promise>{}</promise> again.\n\n"
        "Original task:\n{}"
    ).format(
        state["iteration"],
        state["max_iterations"],
        state["completion_promise"],
        state["prompt"],
    )


def build_continuation(state: dict) -> str:
    if state.get("verification_pending"):
        return build_ulw_verification_failed(state)
    if state.get("ultrawork"):
        return (
            "[ULTRAWORK LOOP {}/{}]\n"
            "Continue. Output <promise>{}</promise> when done (verification follows).\n\n"
            "Original task:\n{}"
        ).format(
            state["iteration"],
            state["max_iterations"],
            state["completion_promise"],
            state["prompt"],
        )
    return build_ralph_continuation(state)


if ACTION == "parse_start":
    print(json.dumps(parse_loop_args(sys.argv[1]) or {}))
    raise SystemExit(0)

if ACTION == "write_state":
    write_state(Path(sys.argv[1]), json.loads(sys.argv[2]))
    raise SystemExit(0)

if ACTION == "read_state":
    st = read_state(Path(sys.argv[1]))
    print(json.dumps(st) if st else "null")
    raise SystemExit(0)

if ACTION == "clear_state":
    clear_state(Path(sys.argv[1]))
    raise SystemExit(0)

if ACTION == "evaluate_stop":
    path = Path(sys.argv[1])
    session_id = sys.argv[2]
    stdin_path = sys.argv[3]
    data = {}
    if stdin_path and Path(stdin_path).is_file():
        try:
            data = json.loads(Path(stdin_path).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            pass

    def pick(*keys):
        for k in keys:
            v = data.get(k)
            if isinstance(v, str) and v.strip():
                return v.strip()
        return ""

    stop_reason = pick("stopReason", "stop_reason")
    if stop_reason and stop_reason.lower() not in ("end_turn", "endturn", ""):
        raise SystemExit(1)

    bg = data.get("background_tasks") or data.get("backgroundTasks") or []
    if isinstance(bg, list):
        for t in bg:
            if isinstance(t, dict) and str(t.get("status", "")).lower() in (
                "running",
                "pending",
                "in_progress",
                "active",
            ):
                raise SystemExit(1)

    st = read_state(path)
    if not st:
        raise SystemExit(1)
    if st.get("session_id") and session_id and st["session_id"] != session_id:
        raise SystemExit(1)

    last_msg = pick(
        "last_assistant_message",
        "lastAssistantMessage",
        "last_assistant_message_text",
    )

    # Ultrawork: verified -> done
    if st.get("ultrawork") and st.get("verification_pending"):
        if is_oracle_verified(last_msg):
            clear_state(path)
            raise SystemExit(1)
        if has_promise(last_msg, st["completion_promise"]):
            print(build_ulw_verification(st))
            raise SystemExit(0)
        print(build_ulw_verification_failed(st))
        raise SystemExit(0)

    # Ultrawork: DONE emitted -> enter verification (no iteration bump)
    if st.get("ultrawork") and has_promise(last_msg, st["completion_promise"]):
        st["verification_pending"] = True
        st["initial_completion_promise"] = st.get("initial_completion_promise") or st[
            "completion_promise"
        ]
        write_state(path, st)
        print(build_ulw_verification(st))
        raise SystemExit(0)

    # Standard ralph: DONE -> complete
    if not st.get("ultrawork") and has_promise(last_msg, st["completion_promise"]):
        clear_state(path)
        raise SystemExit(1)

    if st["iteration"] >= st["max_iterations"]:
        clear_state(path)
        raise SystemExit(1)

    st["iteration"] = int(st["iteration"]) + 1
    write_state(path, st)
    if st["iteration"] > st["max_iterations"]:
        clear_state(path)
        raise SystemExit(1)

    print(build_continuation(st))
    raise SystemExit(0)

if ACTION == "build_start_context":
    args = json.loads(sys.argv[1])
    template = os.environ.get("RALPH_TEMPLATE", "")
    print(template + "\n" + args.get("task", ""))
    raise SystemExit(0)

raise SystemExit(2)
PY
}

ralph_parse_start_args() {
  RALPH_ACTION=parse_start _ralph_py "$1"
}

ralph_write_state() {
  RALPH_ACTION=write_state _ralph_py "$1" "$2"
}

ralph_clear_state() {
  RALPH_ACTION=clear_state _ralph_py "$1"
}

ralph_evaluate_stop() {
  RALPH_ACTION=evaluate_stop _ralph_py "$1" "$2" "$3"
}

handle_user_prompt_ralph() {
  local stdin_file="$1"
  local workspace="${GROK_WORKSPACE_ROOT:-}"

  if [ -z "$workspace" ]; then
    return 0
  fi

  local state_path prompt
  state_path="$(ralph_state_path "$workspace")" || return 0

  prompt="$(
    python3 - "$stdin_file" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
except (OSError, json.JSONDecodeError):
    raise SystemExit(0)
for k in ("prompt", "userPrompt", "user_prompt", "message"):
    v = data.get(k)
    if isinstance(v, str) and v.strip():
        print(v.strip())
        break
PY
  )"
  [ -n "$prompt" ] || return 0

  if printf '%s' "$prompt" | rg -qi '^/?cancel-ralph\b'; then
    ralph_clear_state "$state_path" >/dev/null 2>&1 || true
    printf '%s\n' "<RALPH_LOOP>Canceled active loop (ralph or ultrawork). Cleared ${RALPH_STATE_REL_PATH}.</RALPH_LOOP>"
    return 0
  fi

  local args_json
  args_json="$(ralph_parse_start_args "$prompt")"
  if [ -z "$args_json" ] || [ "$args_json" = "{}" ]; then
    return 0
  fi

  local task ultrawork
  task="$(printf '%s' "$args_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("task",""))')"
  ultrawork="$(printf '%s' "$args_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("1" if d.get("ultrawork") else "0")')"
  if [ -z "$task" ]; then
    printf '%s\n' '<RALPH_LOOP>Provide a task. Examples:
/ralph-loop "fix bug"
/ulw-loop "fix bug" --max-iterations=200
ultrawork refactor auth module</RALPH_LOOP>'
    return 0
  fi

  local state_json
  state_json="$(printf '%s' "$args_json" | python3 -c "
import json, os, sys
from datetime import datetime, timezone
args = json.load(sys.stdin)
ultrawork = bool(args.get('ultrawork'))
print(json.dumps({
  'active': True,
  'iteration': 1,
  'max_iterations': args.get('max_iterations'),
  'completion_promise': args.get('completion_promise', 'DONE'),
  'initial_completion_promise': args.get('completion_promise', 'DONE'),
  'session_id': os.environ.get('GROK_SESSION_ID', ''),
  'strategy': args.get('strategy', 'continue'),
  'started_at': datetime.now(timezone.utc).isoformat(),
  'prompt': args.get('task', ''),
  'ultrawork': ultrawork,
  'verification_pending': False,
}))
")"

  ralph_write_state "$state_path" "$state_json" || return 0

  if [ "$ultrawork" = "1" ]; then
    mark_skill_loaded "ulw-loop" 2>/dev/null || true
  else
    mark_skill_loaded "ralph-loop" 2>/dev/null || true
  fi

  local max_it promise template message
  max_it="$(printf '%s' "$args_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("max_iterations",100))')"
  promise="$(printf '%s' "$args_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("completion_promise","DONE"))')"
  if [ "$ultrawork" = "1" ]; then
    template="$(ulw_loop_template "$max_it" "$promise" "$RALPH_ORACLE_SUBAGENT")"
  else
    template="$(ralph_loop_template "$max_it" "$promise")"
  fi
  message="$(
    RALPH_TEMPLATE="$template" RALPH_ACTION=build_start_context _ralph_py "$args_json"
  )"
  printf '%s\n' "$message"
}

collect_user_prompt_ralph() {
  handle_user_prompt_ralph "$1" 2>/dev/null || true
}

evaluate_ralph_loop_stop() {
  local stdin_file="${1:-}"
  local workspace="${GROK_WORKSPACE_ROOT:-}"
  local session_id="${GROK_SESSION_ID:-}"
  if [ -z "$workspace" ]; then
    return 1
  fi
  local state_path
  state_path="$(ralph_state_path "$workspace")" || return 1
  ralph_evaluate_stop "$state_path" "$session_id" "$stdin_file"
}