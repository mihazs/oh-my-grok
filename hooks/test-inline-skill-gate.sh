#!/usr/bin/env bash
# End-to-end skill-gate test via inline Grok (headless single-turn).
set -euo pipefail

GROK="${GROK_BIN:-${HOME}/.grok/bin/grok}"
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-support.sh
source "${HOOKS_DIR}/test-support.sh"
META_SKILL="${META_SKILL_PATH:-${HOOKS_DIR}/../skills/agent-skill-gate/SKILL.md}"
WORKSPACE="${1:-${GROK_WORKSPACE_ROOT:-$(pwd)}}"
TEST_FILE="${TMPDIR:-/tmp}/grok-skill-gate-inline-test-$$.txt"
STATE_ROOT="${HOME}/.grok/state/skill-gate"
LOG="${TMPDIR:-/tmp}/grok-skill-gate-inline-$$.log"

rm -f "$TEST_FILE"
: >"$LOG"

echo "== grok inspect (hooks) ==" | tee -a "$LOG"
(cd "$WORKSPACE" && "$GROK" inspect --json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
hooks = d.get('hooks', [])
targets = [h.get('target', '') for h in hooks]
if any('pre-tool-use' in t for t in targets):
    print('OK: PreToolUse skill-gate hook registered (%d hooks)' % len(hooks))
else:
    print('FAIL: pre-tool-use not in inspect hooks')
    for h in hooks:
        print(' -', h.get('event'), h.get('target'))
    sys.exit(1)
" | tee -a "$LOG")

PROMPT=$(cat <<'EOF'
You are running an automated hook test. Follow exactly:
1) Read the file META_SKILL_PATH (required).
2) Write a one-line file at TEST_FILE_PATH with the exact content: ok
3) Reply with a single line: INLINE_GATE_OK
Do not skip step 1. Do not use any other tools.
EOF
)
PROMPT="${PROMPT//TEST_FILE_PATH/$TEST_FILE}"
PROMPT="${PROMPT//META_SKILL_PATH/$META_SKILL}"

echo "== inline grok run (--no-alt-screen) ==" | tee -a "$LOG"
set +e
(cd "$WORKSPACE" && "$GROK" --no-alt-screen --always-approve --max-turns 8 \
  --disallowed-tools "Task,WebSearch,WebFetch,GenerateImage,SwitchMode,AskQuestion,CallMcpTool,ListMcpResources,FetchMcpResource,EditNotebook" \
  -p "$PROMPT" 2>&1 | tee -a "$LOG")
GROK_RC=$?
set -e
echo "grok exit=$GROK_RC" | tee -a "$LOG"

echo "== assertions ==" | tee -a "$LOG"
FAIL=0

if rg -q 'denied: skill catalog empty' "$LOG"; then
  echo "FAIL: still saw 'skill catalog empty'" | tee -a "$LOG"
  FAIL=1
else
  echo "OK: no 'skill catalog empty' in output" | tee -a "$LOG"
fi

if rg -qi 'INLINE_GATE_OK' "$LOG"; then
  echo "OK: agent reported INLINE_GATE_OK" | tee -a "$LOG"
else
  echo "WARN: INLINE_GATE_OK not in output (may still have written file)" | tee -a "$LOG"
fi

if [ -f "$TEST_FILE" ] && [ "$(cat "$TEST_FILE")" = "ok" ]; then
  echo "OK: Write succeeded -> $TEST_FILE" | tee -a "$LOG"
else
  echo "FAIL: Write did not produce $TEST_FILE with content ok" | tee -a "$LOG"
  FAIL=1
fi

# Latest skill-gate state for this workspace session
LATEST="$(find "$STATE_ROOT" -name all-skills.json -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
if [ -n "$LATEST" ]; then
  python3 - "$LATEST" <<'PY' | tee -a "$LOG"
import json, sys
path = sys.argv[1]
with open(path) as f:
    skills = json.load(f)
dirpath = path.rsplit("/", 1)[0]
loaded = []
lp = dirpath + "/skills.loaded"
try:
    with open(lp) as f:
        loaded = [ln.strip() for ln in f if ln.strip()]
except OSError:
    pass
print(f"state_dir={dirpath}")
print(f"catalog_count={len(skills)}")
print(f"loaded_count={len(loaded)} loaded={loaded[:5]}")
if len(skills) == 0:
    raise SystemExit(1)
PY
else
  echo "WARN: no skill-gate state dir found under $STATE_ROOT" | tee -a "$LOG"
fi

rm -f "$TEST_FILE"
echo "log: $LOG"
exit "$FAIL"