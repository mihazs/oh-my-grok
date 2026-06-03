# omo Features Port — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port IntentGate, Hash-Anchored edits, AST-Grep MCP, Todo Enforcer hardening, Prometheus planner (with subagents), and LSP integration from oh-my-openagent into oh-my-grok as Grok-native hooks, skills, bundled MCP, and plugin agents.

**Architecture:** Extend the existing merged `user-prompt.sh` / unified `pre-tool-mutate.sh` / `stop-chain.sh` patterns; persist session state under `~/.grok/state/` and workspace state under `.omg/`; bundle MCP servers in `vendor/` + `.mcp.json`. Grok cannot replace the Edit tool or inject PostToolUse context—hashline and LSP use cache + next-prompt/Stop injection instead.

**Tech Stack:** Bash (`set -euo pipefail`), Python 3 (`omo_state.py`, `hashline.py`), Node MCP runtimes (vendored from omo), Grok plugin hooks/skills/rules/agents.

**Prerequisites:** `export GROK_PLUGIN_ROOT="$(pwd)"`, `grok plugin validate .`, `rg`, `python3`, `node` (for Phase C+).

**Reference clone (read-only):** `/tmp/omo-research` or `git clone --depth 1 -b dev https://github.com/code-yeongyu/oh-my-openagent.git`

---

## File map (all phases)

| Path | Responsibility |
|------|----------------|
| `hooks/lib/intent-gate.sh` | Keyword detection + mode banners for UserPromptSubmit |
| `hooks/lib/prometheus.sh` | `/plan`, `/start-work`, plan-mode state, boulder bootstrap |
| `hooks/lib/hashline.sh` | Source `hashline.py`; cache paths; PreToolUse helpers |
| `hooks/lib/hashline.py` | xxHash32 + LINE#ID (port of `packages/hashline-core`) |
| `hooks/lib/omo_state.py` | Todo enforcer cooldown/backoff; optional LSP stop eval |
| `hooks/lib/lsp.sh` | Diagnostics stash + Stop/UserPrompt collectors |
| `hooks/pre-tool-mutate.sh` | Orchestrate skill-gate → plan-mode → hashline |
| `hooks/post-tool-read.sh` | Skill gate + hashline cache on Read |
| `hooks/post-tool-lsp.sh` | Run diagnostics after Write/StrReplace |
| `hooks/user-prompt.sh` | Wire all collectors (single JSON) |
| `hooks/lib/stop-chain.sh` | Add LSP step before plan.md fallback |
| `hooks/hooks.json` | PostToolUse matchers for LSP |
| `rules/13-intent-gate.md` | Always-on Phase 0 verbalization |
| `rules/14-ast-grep.md` | Prefer structural search MCP |
| `skills/prometheus-plan/SKILL.md` | `/plan` interview workflow |
| `skills/hashline-edit/SKILL.md` | LINE#ID edit discipline |
| `skills/ast-grep/SKILL.md` | MCP tool usage |
| `skills/lsp/SKILL.md` | Post-edit diagnostics |
| `agents/prometheus-planner.md` | Read-only planner agent |
| `agents/metis-consultant.md` | Plan gap analysis subagent |
| `agents/momus-reviewer.md` | Plan review subagent |
| `.mcp.json` | `ast_grep` + `lsp` servers |
| `.lsp.json` | Template language server entries |
| `scripts/build-mcp-runtimes.sh` | Vendor + build MCP dist |
| `vendor/ast-grep-mcp/` | Vendored package (git submodule or copy) |
| `vendor/lsp-tools-mcp/` | Vendored package |
| `hooks/test-intent-gate.sh` | IntentGate smoke |
| `hooks/test-prometheus.sh` | Plan mode + boulder |
| `hooks/test-hashline.sh` | Hash compute + deny stale |
| `hooks/test-lsp.sh` | Diagnostics stash + stop |
| `docs/configuration.md` | `OMG_*` env flags |

---

## Phase A — IntentGate + Todo Enforcer

### Task 1: IntentGate library

**Files:**
- Create: `hooks/lib/intent-gate.sh`
- Test: `hooks/test-intent-gate.sh`

- [ ] **Step 1: Write failing test**

Create `hooks/test-intent-gate.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${HOOKS_DIR}/lib/common.sh"
# shellcheck source=lib/intent-gate.sh
source "${HOOKS_DIR}/lib/intent-gate.sh"

export GROK_SESSION_ID="test-intent-$$"
tmpdir="$(mktemp -d)"
export GROK_WORKSPACE_ROOT="$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT

# search keyword outside code fence -> INTENT_GATE banner
printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"please search for auth middleware"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt.sh >"${tmpdir}/out.json"
rg -q 'INTENT_GATE' "${tmpdir}/out.json" || { cat "${tmpdir}/out.json"; exit 1; }
rg -q 'search' "${tmpdir}/out.json" || { cat "${tmpdir}/out.json"; exit 1; }

# keyword inside fenced code -> no search mode (ralph may still fire separately)
printf '%s\n' '{"hookEventName":"UserPromptSubmit","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","prompt":"```\nsearch for bugs\n```"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt.sh >"${tmpdir}/out2.json"
! rg -q 'SEARCH_MODE' "${tmpdir}/out2.json" || { cat "${tmpdir}/out2.json"; exit 1; }

echo "intent-gate: OK"
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/mihazs/Dev/oh-my-grok
export GROK_PLUGIN_ROOT="$(pwd)"
bash hooks/test-intent-gate.sh
```

Expected: FAIL (`intent-gate.sh` missing or no `INTENT_GATE` in output)

- [ ] **Step 3: Implement `hooks/lib/intent-gate.sh`**

```bash
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
```

- [ ] **Step 4: Wire into `hooks/user-prompt.sh`**

After `part_ralph=...` add:

```bash
# shellcheck source=lib/intent-gate.sh
source "${SCRIPT_DIR}/lib/intent-gate.sh"
part_intent="$(collect_intent_gate_context "$stdin_tmp" 2>/dev/null || true)"
```

Extend `emit_user_prompt_context` call to include `"$part_intent"` after `"$part_ralph"`.

- [ ] **Step 5: Add `rules/13-intent-gate.md`**

Condensed Phase 0 table from omo `src/agents/sisyphus/default.ts` (verbalize intent → routing; use Task for exploration; do not implement on "explain/how" prompts).

- [ ] **Step 6: Run test**

```bash
export GROK_PLUGIN_ROOT="$(pwd)"
bash hooks/test-intent-gate.sh
```

Expected: `intent-gate: OK`

- [ ] **Step 7: Commit**

```bash
git add hooks/lib/intent-gate.sh hooks/user-prompt.sh hooks/test-intent-gate.sh rules/13-intent-gate.md
git commit -m "feat(intent-gate): keyword modes on UserPromptSubmit"
```

---

### Task 2: Todo Enforcer hardening

**Files:**
- Modify: `hooks/lib/omo_state.py`
- Modify: `hooks/test-todo-boulder.sh`
- Modify: `hooks/README.md`

- [ ] **Step 1: Write failing test (cooldown)**

Append to `hooks/test-todo-boulder.sh` before final `echo`:

```bash
# Todo cooldown: second stop within 5s should allow (no TODO CONTINUATION)
printf '%s\n' '{"hookEventName":"stop","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","stopReason":"end_turn"}' \
  | GROK_HOOK_EVENT=stop bash "${HOOKS_DIR}/run-hook.sh" stop-hook.sh >"${tmpdir}/todo-block2.json"
rg -q 'TODO CONTINUATION' "${tmpdir}/todo-block2.json"

sleep 6

printf '%s\n' '{"hookEventName":"stop","sessionId":"'"$GROK_SESSION_ID"'","workspaceRoot":"'"$GROK_WORKSPACE_ROOT"'","stopReason":"end_turn"}' \
  | GROK_HOOK_EVENT=stop bash "${HOOKS_DIR}/run-hook.sh" stop-hook.sh >"${tmpdir}/todo-block3.json"
rg -q 'TODO CONTINUATION' "${tmpdir}/todo-block3.json" || { cat "${tmpdir}/todo-block3.json"; exit 1; }
```

- [ ] **Step 2: Run test — expect FAIL** on second immediate stop (currently blocks twice)

```bash
export GROK_PLUGIN_ROOT="$(pwd)"
bash hooks/test-todo-boulder.sh
```

- [ ] **Step 3: Add enforcer state to `omo_state.py`**

Near top constants:

```python
TODO_ENFORCER_DIR = "todo-enforcer"
CONTINUATION_COOLDOWN_MS = 5_000
MAX_CONSECUTIVE_FAILURES = 5
FAILURE_RESET_WINDOW_MS = 5 * 60_000
ABORT_WINDOW_MS = 3_000
```

Add functions:

```python
def enforcer_state_path(session_id: str) -> Path:
    return grok_home() / "state" / TODO_ENFORCER_DIR / session_id / "state.json"

def read_enforcer_state(session_id: str) -> dict:
    p = enforcer_state_path(session_id)
    if not p.is_file():
        return {}
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}

def write_enforcer_state(session_id: str, state: dict) -> None:
    p = enforcer_state_path(session_id)
    p.parent.mkdir(parents=True, exist_ok=True)
    state["updated_at"] = now_iso()
    p.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")

def should_skip_todo_continuation(session_id: str, stdin_data: dict) -> str | None:
    """Return skip reason or None if continuation allowed."""
    state = read_enforcer_state(session_id)
    now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
    cooldown_until = state.get("cooldown_until_ms")
    if isinstance(cooldown_until, int) and now_ms < cooldown_until:
        return "cooldown"
    abort_at = state.get("abort_detected_at_ms")
    if isinstance(abort_at, int) and now_ms - abort_at < ABORT_WINDOW_MS:
        return "abort_window"
    failures = int(state.get("failure_count") or 0)
    if failures >= MAX_CONSECUTIVE_FAILURES:
        return "failure_backoff"
    stop_reason = pick(stdin_data, "stopReason", "stop_reason")
    if stop_reason and stop_reason.lower() not in ("end_turn", "endturn", ""):
        state["abort_detected_at_ms"] = now_ms
        write_enforcer_state(session_id, state)
    return None

def record_todo_continuation_fire(session_id: str) -> None:
    state = read_enforcer_state(session_id)
    now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
    state["last_fire_ms"] = now_ms
    state["cooldown_until_ms"] = now_ms + CONTINUATION_COOLDOWN_MS
    state["fire_count"] = int(state.get("fire_count") or 0) + 1
    write_enforcer_state(session_id, state)
```

In `evaluate_todo_stop`, after `incomplete` check and before printing message:

```python
    skip = should_skip_todo_continuation(session_id, data)
    if skip:
        raise SystemExit(1)
    record_todo_continuation_fire(session_id)
```

- [ ] **Step 4: Run tests**

```bash
bash hooks/test-todo-boulder.sh
```

Expected: `todo-boulder hooks: OK`

- [ ] **Step 5: Document in `hooks/README.md`** — Grok uses Stop not `session.idle`; cooldown 5s.

- [ ] **Step 6: Commit**

```bash
git add hooks/lib/omo_state.py hooks/test-todo-boulder.sh hooks/README.md
git commit -m "feat(todo-enforcer): cooldown and abort window on Stop chain"
```

---

## Phase B — Prometheus planner + subagents

### Task 3: Prometheus hooks and state

**Files:**
- Create: `hooks/lib/prometheus.sh`
- Modify: `hooks/user-prompt.sh`, `hooks/pre-tool-mutate.sh`
- Create: `hooks/test-prometheus.sh`

- [ ] **Step 1: Write failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HOOKS_DIR}/lib/common.sh"
source "${HOOKS_DIR}/lib/prometheus.sh"

export GROK_SESSION_ID="test-prom-$$"
tmpdir="$(mktemp -d)"
export GROK_WORKSPACE_ROOT="$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/.omg/plans"

printf '%s\n' '{"hookEventName":"UserPromptSubmit","prompt":"/plan add OAuth"}' \
  | GROK_HOOK_EVENT=user_prompt_submit bash "${HOOKS_DIR}/run-hook.sh" user-prompt.sh >"${tmpdir}/plan.json"
rg -q 'PROMETHEUS_PLAN_MODE' "${tmpdir}/plan.json" || { cat "${tmpdir}/plan.json"; exit 1; }

# Deny write outside .omg during plan mode
export OMG_PLAN_MODE=1
printf '%s\n' '{"hookEventName":"PreToolUse","toolName":"Write","toolInput":{"path":"src/foo.ts","contents":"x"}}' \
  | GROK_HOOK_EVENT=pre_tool_use bash "${HOOKS_DIR}/run-hook.sh" pre-tool-mutate.sh >"${tmpdir}/deny.json" || true
rg -q '"decision":"deny"' "${tmpdir}/deny.json" || { cat "${tmpdir}/deny.json"; exit 1; }

echo "prometheus hooks: OK"
```

- [ ] **Step 2: Implement `hooks/lib/prometheus.sh`**

Key functions:

```bash
plan_mode_flag() {
  printf '%s/state/plan-mode/%s/enabled' "$GROK_HOME" "${GROK_SESSION_ID:-unknown}"
}

prometheus_plan_mode_on() {
  local f
  f="$(plan_mode_flag)"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$f"
}

prometheus_plan_mode_off() {
  rm -f "$(plan_mode_flag)" 2>/dev/null || true
}

prometheus_plan_mode_active() {
  [ -f "$(plan_mode_flag)" ]
}

collect_user_prompt_prometheus() {
  local stdin_file="$1"
  local prompt
  prompt="$(intent_gate_extract_prompt "$stdin_file" 2>/dev/null || true)"
  [ -n "$prompt" ] || return 0
  if printf '%s' "$prompt" | rg -qi '^/?plan\b|^/?prometheus\b'; then
    prometheus_plan_mode_on
    cat <<'EOF'
<PROMETHEUS_PLAN_MODE>
You are in planning mode. ONLY create or edit files under `.omg/` (plans, drafts).
Interview the user, then Task(metis-consultant) for gaps, write plan to `.omg/plans/<name>.md`, optional Task(momus-reviewer).
Implementation starts only after `/start-work <plan-file>`.
</PROMETHEUS_PLAN_MODE>
EOF
    return 0
  fi
  if printf '%s' "$prompt" | rg -qi '^/?start-work\b'; then
    prometheus_handle_start_work "$prompt"
    return 0
  fi
  if printf '%s' "$prompt" | rg -qi '^/?cancel-plan\b'; then
    prometheus_plan_mode_off
    printf '%s\n' '<PROMETHEUS_PLAN_MODE>Plan mode cancelled.</PROMETHEUS_PLAN_MODE>'
  fi
}

prometheus_handle_start_work() {
  # Parse plan path from prompt; write .omg/boulder.json via python inline (reuse BOULDER schema)
  prometheus_plan_mode_off
  printf '%s\n' '<PROMETHEUS_PLAN_MODE>Start-work: boulder.json activated. Execute the plan.</PROMETHEUS_PLAN_MODE>'
}

evaluate_prometheus_pre_tool() {
  prometheus_plan_mode_active || return 0
  local stdin_file="$1"
  python3 - "$stdin_file" <<'PY'
import json, sys, os
workspace = os.environ.get("GROK_WORKSPACE_ROOT", "")
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
tool = (data.get("toolName") or data.get("tool_name") or "").lower()
block = data.get("toolInput") or data.get("tool_input") or {}
path = block.get("path") or block.get("file_path") or block.get("filePath") or ""
if tool not in ("write", "strreplace", "editnotebook", "delete"):
    raise SystemExit(0)
if not path:
    raise SystemExit(0)
rel = path
if workspace and path.startswith(workspace):
    rel = path[len(workspace):].lstrip("/")
if rel.startswith(".omg/") and rel.endswith(".md"):
    raise SystemExit(0)
print(f"Prometheus plan mode: only .omg/**/*.md writes allowed; blocked: {path}")
raise SystemExit(2)
PY
}
```

Wire `evaluate_prometheus_pre_tool` at top of `pre-tool-mutate.sh` (before skill-gate): on exit 2, `emit_deny` with captured reason.

- [ ] **Step 3: Create skill `skills/prometheus-plan/SKILL.md`**

Frontmatter: `name: prometheus-plan`, `user_invocable: true`, description for `/plan`.

Body: 5-step workflow from omo `packages/prompts-core/prompts/prometheus/default.md` (trim OpenCode `task(agent=...)` → `Task(subagent_type="metis-consultant")`).

- [ ] **Step 4: Create agents**

`agents/prometheus-planner.md` — copy structure from `~/.grok/bundled/agents/plan.md`; `permission_mode: plan`; prompt: read-only, `.omg` only.

`agents/metis-consultant.md` — gap analysis, returns questions list.

`agents/momus-reviewer.md` — plan critic, OKAY/NEEDS_REVISION verdict.

- [ ] **Step 5: Run test + commit**

```bash
bash hooks/test-prometheus.sh
git add hooks/lib/prometheus.sh hooks/user-prompt.sh hooks/pre-tool-mutate.sh hooks/test-prometheus.sh skills/prometheus-plan agents/
git commit -m "feat(prometheus): plan mode, md-only guard, start-work boulder"
```

---

## Phase C — Bundled MCP (AST-Grep + LSP)

### Task 4: Vendor MCP runtimes

**Files:**
- Create: `scripts/build-mcp-runtimes.sh`
- Create: `.mcp.json`
- Modify: `.gitignore` (if ignoring `vendor/*/node_modules`)

- [ ] **Step 1: Add build script**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OMO_REF="${OMO_SRC:-/tmp/omo-research}"
VENDOR="$ROOT/vendor"
mkdir -p "$VENDOR"
for pkg in ast-grep-mcp lsp-tools-mcp; do
  src="$OMO_REF/packages/$pkg"
  dest="$VENDOR/$pkg"
  rm -rf "$dest"
  cp -a "$src" "$dest"
  (cd "$dest" && npm ci && npm run build)
done
echo "Built MCP runtimes under $VENDOR"
```

- [ ] **Step 2: Run build**

```bash
bash scripts/build-mcp-runtimes.sh
test -f vendor/ast-grep-mcp/dist/cli.js
test -f vendor/lsp-tools-mcp/dist/cli.js
```

- [ ] **Step 3: Add `.mcp.json`**

```json
{
  "mcpServers": {
    "ast_grep": {
      "command": "node",
      "args": ["${GROK_PLUGIN_ROOT}/vendor/ast-grep-mcp/dist/cli.js", "mcp"]
    },
    "lsp": {
      "command": "node",
      "args": ["${GROK_PLUGIN_ROOT}/vendor/lsp-tools-mcp/dist/cli.js", "mcp"]
    }
  }
}
```

- [ ] **Step 4: Skills + rules**

Create `skills/ast-grep/SKILL.md`, `skills/lsp/SKILL.md`, `rules/14-ast-grep.md`.

- [ ] **Step 5: Validate plugin**

```bash
grok plugin validate .
```

- [ ] **Step 6: Commit**

```bash
git add scripts/build-mcp-runtimes.sh .mcp.json vendor/ skills/ast-grep skills/lsp rules/14-ast-grep.md
git commit -m "feat(mcp): bundle ast-grep and lsp-tools MCP servers"
```

---

### Task 5: LSP post-edit + Stop enforcement

**Files:**
- Create: `hooks/lib/lsp.sh`, `hooks/post-tool-lsp.sh`
- Modify: `hooks/hooks.json`, `hooks/lib/stop-chain.sh`, `hooks/user-prompt.sh`
- Create: `hooks/test-lsp.sh`

- [ ] **Step 1: Write failing test** — after fake Write, stash errors; Stop blocks.

Use mock runner in test:

```bash
export OMG_LSP_MOCK_DIAG='error[typescript] (1) at 1:1: syntax error'
```

- [ ] **Step 2: Implement `hooks/lib/lsp.sh`**

- `lsp_stash_path()` → `$GROK_HOME/state/lsp-diagnostics/$session.json`
- `lsp_run_diagnostics(file)` → call `node "$GROK_PLUGIN_ROOT/vendor/lsp-tools-mcp/dist/cli.js" diagnostics "$file"` or mock env
- `collect_lsp_context()` → read stash, emit `<LSP_DIAGNOSTICS>...</LSP_DIAGNOSTICS>`
- `evaluate_lsp_stop(stdin)` → if errors remain and `OMG_LSP_ENFORCE!=0`, print block reason

- [ ] **Step 3: `hooks/post-tool-lsp.sh`**

Parse mutated paths from stdin (port `extractMutatedFilePaths` logic from omo `mutated-file-paths.ts` in Python), run diagnostics, merge into stash JSON.

- [ ] **Step 4: Register in `hooks/hooks.json`**

```json
{
  "matcher": "Write|StrReplace",
  "hooks": [
    {
      "type": "command",
      "command": "bash \"${GROK_PLUGIN_ROOT}/hooks/run-hook.sh\" post-tool-lsp.sh",
      "timeout": 60
    }
  ]
}
```

- [ ] **Step 5: Insert in `stop-chain.sh` after todo, before plan.md:**

```bash
  if reason="$(evaluate_lsp_stop "$stdin_file")"; then
    printf '%s' "$reason"
    return 0
  fi
```

- [ ] **Step 6: Run tests + commit**

```bash
bash hooks/test-lsp.sh
git add hooks/lib/lsp.sh hooks/post-tool-lsp.sh hooks/hooks.json hooks/lib/stop-chain.sh hooks/user-prompt.sh hooks/test-lsp.sh
git commit -m "feat(lsp): post-edit diagnostics stash and Stop enforcement"
```

---

## Phase D — Hash-Anchored edits

### Task 6: hashline.py core

**Files:**
- Create: `hooks/lib/hashline.py`
- Test: `hooks/test-hashline.sh`

- [ ] **Step 1: Port hash algorithm**

Copy logic from omo `packages/hashline-core/src/xxhash32.ts` (full `xxHash32Js`) and `hash-computation.ts` into `hooks/lib/hashline.py`:

```python
NIBBLE_STR = "ZPMQVRWSNKTXJBYH"
HASHLINE_DICT = [NIBBLE_STR[(i >> 4)] + NIBBLE_STR[(i & 0xF)] for i in range(256)]

def compute_line_hash(line_number: int, content: str) -> str:
    normalized = content.replace("\r", "").rstrip()
    seed = line_number if not re.search(r"[\w]", normalized, re.UNICODE) else 0
    h = xxhash32(normalized.encode("utf-8"), seed) % 256
    return HASHLINE_DICT[h]
```

Add `if __name__ == "__main__"` CLI: `hashline.py compute 1 "hello"` prints `1#XX`.

- [ ] **Step 2: Failing test**

```bash
result="$(python3 hooks/lib/hashline.py compute 1 "  hello  ")"
# Golden from omo: run once against omo package and pin expected hash in test
test "$result" = "1#??"  # replace ?? after golden capture
```

Capture golden:

```bash
cd /tmp/omo-research/packages/hashline-core && npm test -- hash-computation 2>/dev/null || \
  node -e "const {computeLineHash}=require('./dist/hash-computation'); console.log('1#'+computeLineHash(1,'  hello  '))"
```

- [ ] **Step 3: Implement + pass test**

- [ ] **Step 4: Commit**

```bash
git add hooks/lib/hashline.py hooks/test-hashline.sh
git commit -m "feat(hashline): port line hash computation from hashline-core"
```

---

### Task 7: Read cache + PreToolUse validation

**Files:**
- Create: `hooks/lib/hashline.sh`
- Modify: `hooks/post-tool-read.sh`, `hooks/pre-tool-mutate.sh`, `hooks/user-prompt.sh`
- Create: `skills/hashline-edit/SKILL.md`

- [ ] **Step 1: Extend `post-tool-read.sh`**

After skill marking, if `OMG_HASHLINE!=0` and path is under workspace and not `SKILL.md`, read file from disk, build `{line: hash}` map, write to `$GROK_HOME/state/hashline/$session/$(sha256 path).json`.

- [ ] **Step 2: `hooks/lib/hashline.sh`**

- `hashline_validate_pre_tool(stdin_file)` — parse StrReplace `old_string` for `\d+#[ZPMQ...]{2}` refs; compare to cache; `exit 2` + message on mismatch
- `collect_hashline_context()` — list cached files (max 5) with sample line refs

- [ ] **Step 3: Chain in `pre-tool-mutate.sh`**

Order: prometheus deny → hashline validate → skill-gate.

- [ ] **Step 4: Failing test `hooks/test-hashline.sh`**

1. Seed cache for `foo.ts` line 1
2. PreToolUse StrReplace with stale hash → deny
3. Matching hash → allow (with skill loaded or empty catalog)

- [ ] **Step 5: Skill + docs**

`skills/hashline-edit/SKILL.md`; `docs/configuration.md` entries: `OMG_HASHLINE`, `OMG_INTENT_GATE`, `OMG_LSP_ENFORCE`.

- [ ] **Step 6: Full smoke suite**

```bash
export GROK_PLUGIN_ROOT="$(pwd)"
grok plugin validate .
for t in hooks/test-*.sh; do
  case "$t" in *inline*) continue ;; esac
  bash "$t" || exit 1
done
```

- [ ] **Step 7: Commit**

```bash
git add hooks/post-tool-read.sh hooks/lib/hashline.sh hooks/pre-tool-mutate.sh hooks/user-prompt.sh skills/hashline-edit docs/configuration.md hooks/test-hashline.sh
git commit -m "feat(hashline): read cache and PreToolUse stale-edit guard"
```

---

## Phase E — Docs and release prep

### Task 8: Documentation matrix

**Files:**
- Modify: `README.md`, `ROADMAP.md`, `hooks/README.md`, `AGENTS.md`

- [ ] **Step 1: Update `hooks/README.md`**

Add UserPromptSubmit collectors: intent-gate, prometheus, hashline, lsp.

Add Stop chain step 4.5: LSP.

Add PostToolUse: post-tool-lsp.

- [ ] **Step 2: Update `ROADMAP.md`** — move shipped items from Mid term.

- [ ] **Step 3: Update `README.md` feature table** — link to `docs/configuration.md` for `OMG_*` flags.

- [ ] **Step 4: Update `AGENTS.md` decision table** — new libs and test scripts.

- [ ] **Step 5: Commit**

```bash
git add README.md ROADMAP.md hooks/README.md AGENTS.md docs/
git commit -m "docs: omo feature port matrix and hook map"
```

---

## Self-review (spec coverage)

| Requirement | Task |
|-------------|------|
| IntentGate | Task 1 |
| Hash-Anchored Edit | Tasks 6–7 |
| AST-Grep | Task 4 |
| Todo Enforcer | Task 2 |
| Prometheus + subagents | Task 3 |
| LSP | Tasks 4–5 |
| Bundled MCP (user choice) | Task 4 |
| Plugin agents (user choice) | Task 3 |

**Placeholder scan:** All tasks include concrete paths and commands; golden hash in Task 6 requires one-time capture from omo (documented).

**Type consistency:** `intent_gate_extract_prompt` reused by prometheus.sh; `evaluate_*_stop` returns via exit 0 print / exit 1 allow pattern throughout.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-02-omo-features-port.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — Fresh subagent per task (Phase A Task 1 → Task 2 → …), review between tasks.

2. **Inline Execution** — Run phases in this session with executing-plans checkpoints after each phase.

**Which approach?**