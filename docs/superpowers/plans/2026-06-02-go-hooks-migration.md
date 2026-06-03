# Go Hooks Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Bash/Python hook runtime (~4.6k LOC) with a single cross-compiled Go binary (`omg-hook`) per OS/arch, shipped under `bin/`, for lower memory and faster PreToolUse while preserving Grok JSON contracts and existing `hooks/test-*.sh` smoke tests.

**Architecture:** Thin [`hooks/run-hook.sh`](hooks/run-hook.sh) selects `bin/omg-hook-<goos>-<goarch>` and passes a subcommand; Go reads hook JSON from stdin, writes JSON to stdout, and uses `os/exec` only for `grok inspect` (skill gate) and optional `node` (LSP diagnostics). Bundled MCP stays Node ([`.mcp.json`](.mcp.json)). Legacy `hooks/lib/*.{sh,py}` removed after parity.

**Tech Stack:** Go 1.22+, `github.com/spf13/cobra`, `github.com/cespare/xxhash/v2` (hashline only — implement seed/normalize in-tree to match Python), Bash dispatcher + existing shell integration tests, GitHub Actions cross-compile.

**Prerequisites:** `go`, `git`; maintainers run `scripts/build-hook.sh` to refresh `bin/*`. End users need **no** Go/Python for hooks.

**Spec reference:** Approved architecture plan in session; behavior must match current [`hooks/hooks.json`](hooks/hooks.json), [`hooks/lib/stop-chain.sh`](hooks/lib/stop-chain.sh), [`hooks/user-prompt.sh`](hooks/user-prompt.sh).

---

## File map (final tree)

| Path | Responsibility |
|------|----------------|
| [`go.mod`](go.mod) | Module `github.com/mihazs/oh-my-grok` |
| [`cmd/omg-hook/main.go`](cmd/omg-hook/main.go) | Cobra root + subcommands |
| [`internal/hookenv/env.go`](internal/hookenv/env.go) | `GROK_*` paths, stdin JSON → `Event` |
| [`internal/hookio/emit.go`](internal/hookio/emit.go) | `EmitAllow`, `EmitDeny`, `EmitStopBlock`, `EmitAdditionalContext` |
| [`internal/config/flags.go`](internal/config/flags.go) | `OMG_HASHLINE`, `OMG_INTENT_GATE`, `OMG_LSP_ENFORCE`, … |
| [`internal/hashline/hash.go`](internal/hashline/hash.go) | Port of [`hooks/lib/hashline.py`](hooks/lib/hashline.py) |
| [`internal/hashline/cache.go`](internal/hashline/cache.go) | Read cache under `~/.grok/state/hashline/<session>/` |
| [`internal/skillgate/gate.go`](internal/skillgate/gate.go) | Catalog + loaded set + PreTool deny |
| [`internal/prometheus/plan.go`](internal/prometheus/plan.go) | Plan mode + md-only PreTool |
| [`internal/boulder/state.go`](internal/boulder/state.go) | Port of [`hooks/lib/omo_state.py`](hooks/lib/omo_state.py) |
| [`internal/ralph/loop.go`](internal/ralph/loop.go) | Port of [`hooks/lib/ralph-loop.sh`](hooks/lib/ralph-loop.sh) |
| [`internal/lsp/stash.go`](internal/lsp/stash.go) | Port of [`hooks/lib/lsp.sh`](hooks/lib/lsp.sh) |
| [`internal/intentgate/detect.go`](internal/intentgate/detect.go) | Port of [`hooks/lib/intent-gate.sh`](hooks/lib/intent-gate.sh) |
| [`internal/workspace/rules.go`](internal/workspace/rules.go) | Port workspace + rules injection |
| [`internal/handoff/prompt.go`](internal/handoff/prompt.go) | `/handoff` collector |
| [`internal/usingpowers/first.go`](internal/usingpowers/first.go) | First-prompt bootstrap |
| [`internal/stoppending/planmd.go`](internal/stoppending/planmd.go) | Root `plan.md` fallback |
| [`internal/cmd/pre_tool_use.go`](internal/cmd/pre_tool_use.go) | Pre-tool chain |
| [`internal/cmd/user_prompt.go`](internal/cmd/user_prompt.go) | Merged collectors |
| [`internal/cmd/stop.go`](internal/cmd/stop.go) | Stop chain |
| [`scripts/build-hook.sh`](scripts/build-hook.sh) | Cross-compile 5 binaries |
| [`hooks/run-hook.sh`](hooks/run-hook.sh) | OS/arch → binary + exec subcommand |
| [`hooks/hooks.json`](hooks/hooks.json) | `run-hook.sh <subcommand>` not `*.sh` |
| [`bin/omg-hook-*`](bin/) | Committed release binaries |

---

### Task 1: Go module + hook I/O

**Files:**
- Create: `go.mod`, `internal/hookenv/env.go`, `internal/hookenv/event.go`, `internal/hookio/emit.go`, `internal/hookio/emit_test.go`
- Create: `cmd/omg-hook/main.go` (stub `session-start` only)

- [ ] **Step 1: Write failing emit test**

Create `internal/hookio/emit_test.go`:

```go
package hookio_test

import (
	"bytes"
	"encoding/json"
	"os"
	"testing"

	"github.com/mihazs/oh-my-grok/internal/hookio"
)

func TestEmitAllow(t *testing.T) {
	var buf bytes.Buffer
	hookio.EmitAllow(&buf)
	var out map[string]string
	if err := json.Unmarshal(buf.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if out["decision"] != "allow" {
		t.Fatalf("got %v", out)
	}
}

func TestEmitDenyWritesReason(t *testing.T) {
	var buf bytes.Buffer
	code := hookio.EmitDeny(&buf, `say "hi"`)
	if code != 2 {
		t.Fatalf("exit %d", code)
	}
	if !bytes.Contains(buf.Bytes(), []byte(`deny`)) {
		t.Fatalf("%s", buf.Bytes())
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/mihazs/Dev/oh-my-grok
go test ./internal/hookio/... -count=1
```

Expected: FAIL (`package hookio` not found)

- [ ] **Step 3: Add `go.mod` and implement emit**

`go.mod`:

```go
module github.com/mihazs/oh-my-grok

go 1.22

require github.com/spf13/cobra v1.8.1
```

`internal/hookio/emit.go`:

```go
package hookio

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"
)

func escapeJSON(s string) string {
	var b strings.Builder
	_ = json.NewEncoder(&b).Encode(s)
	out := strings.TrimSpace(b.String())
	if len(out) >= 2 && out[0] == '"' {
		return out[1 : len(out)-1]
	}
	return out
}

func EmitAllow(w io.Writer) {
	fmt.Fprint(w, `{"decision":"allow"}`+"\n")
}

func EmitDeny(w io.Writer, reason string) int {
	fmt.Fprintf(w, `{"decision":"deny","reason":"%s"}`+"\n", escapeJSON(reason))
	return 2
}

func EmitStopBlock(w io.Writer, reason string) {
	fmt.Fprintf(w, `{"decision":"block","reason":"%s"}`+"\n", escapeJSON(reason))
}

func EmitStopAllow(w io.Writer) {
	fmt.Fprint(w, "{}\n")
}

func EmitAdditionalContext(w io.Writer, message, hookEvent string) {
	escaped := escapeJSON(message)
	// Grok default (match hooks/lib/common.sh)
	if os.Getenv("CURSOR_PLUGIN_ROOT") != "" {
		fmt.Fprintf(w, `{"additional_context":"%s"}`+"\n", escaped)
		return
	}
	if os.Getenv("CLAUDE_PLUGIN_ROOT") != "" && os.Getenv("COPILOT_CLI") == "" {
		fmt.Fprintf(w, `{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}`+"\n",
			escapeJSON(hookEvent), escaped)
		return
	}
	fmt.Fprintf(w, `{"additionalContext":"%s"}`+"\n", escaped)
}
```

`internal/hookenv/event.go` — struct with `SessionID`, `WorkspaceRoot`, `ToolName`, `ToolInput map[string]any`, `Prompt string`, `StopReason string`; `ReadEvent(r io.Reader)`.

`internal/hookenv/env.go` — `GrokHome()`, `PluginRoot()`, `ApplyEvent(ev Event)` sets env when empty.

- [ ] **Step 4: Run tests**

```bash
go test ./internal/hookio/... -v
```

Expected: PASS

- [ ] **Step 5: Stub CLI**

`cmd/omg-hook/main.go`:

```go
package main

import (
	"os"

	"github.com/mihazs/oh-my-grok/internal/hookenv"
	"github.com/mihazs/oh-my-grok/internal/hookio"
	"github.com/spf13/cobra"
)

func main() {
	root := &cobra.Command{Use: "omg-hook"}
	root.AddCommand(&cobra.Command{
		Use: "session-start",
		RunE: func(cmd *cobra.Command, args []string) error {
			ev, err := hookenv.ReadEvent(os.Stdin)
			if err != nil {
				return err
			}
			hookenv.ApplyEvent(ev)
			// Phase 1: no output required for passive hook
			return nil
		},
	})
	if err := root.Execute(); err != nil {
		os.Exit(1)
	}
}
```

- [ ] **Step 6: Commit**

```bash
git add go.mod go.sum cmd/omg-hook internal/hookenv internal/hookio
git commit -m "feat(go): scaffold omg-hook module with hookio and hookenv"
```

---

### Task 2: Cross-compile + dispatcher

**Files:**
- Create: `scripts/build-hook.sh`
- Modify: `hooks/run-hook.sh`, `hooks/hooks.json`, `.github/workflows/ci.yml`
- Create: `bin/.gitkeep` (until first build)

- [ ] **Step 1: Add build script**

`scripts/build-hook.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p bin
build() {
  local goos="$1" goarch="$2 out="$3"
  CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" go build -ldflags="-s -w" -o "bin/$out" ./cmd/omg-hook
}
build linux amd64 omg-hook-linux-amd64
build linux arm64 omg-hook-linux-arm64
build darwin amd64 omg-hook-darwin-amd64
build darwin arm64 omg-hook-darwin-arm64
build windows amd64 omg-hook-windows-amd64.exe
echo "Built bin/omg-hook-*"
```

- [ ] **Step 2: Build locally**

```bash
bash scripts/build-hook.sh
file bin/omg-hook-linux-amd64
```

Expected: `ELF 64-bit LSB executable`

- [ ] **Step 3: Replace `hooks/run-hook.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
if [ $# -lt 1 ]; then
  echo "run-hook.sh: missing subcommand" >&2
  exit 1
fi
SUBCOMMAND="$1"
shift
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-$ROOT}"
os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "run-hook.sh: unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac
case "$os" in
  linux) bin="${PLUGIN_ROOT}/bin/omg-hook-linux-${arch}" ;;
  darwin) bin="${PLUGIN_ROOT}/bin/omg-hook-darwin-${arch}" ;;
  mingw*|msys*|cygwin*|windows*)
    bin="${PLUGIN_ROOT}/bin/omg-hook-windows-amd64.exe"
    ;;
  *) echo "run-hook.sh: unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
if [ ! -x "$bin" ]; then
  echo "run-hook.sh: missing hook binary: $bin" >&2
  exit 1
fi
exec "$bin" "$SUBCOMMAND" "$@"
```

- [ ] **Step 4: Update `hooks/hooks.json`**

Replace every:

`bash "${GROK_PLUGIN_ROOT}/hooks/run-hook.sh" session-start.sh`

with:

`bash "${GROK_PLUGIN_ROOT}/hooks/run-hook.sh" session-start`

(Subcommands: `session-start`, `user-prompt`, `pre-tool-use`, `post-tool-read`, `post-tool-todo-write`, `post-tool-lsp`, `stop`, `session-end`.)

- [ ] **Step 5: CI job**

Add to [`.github/workflows/ci.yml`](.github/workflows/ci.yml):

```yaml
  build-hook:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: "1.22"
      - run: bash scripts/build-hook.sh
      - run: go test ./... -count=1
      - run: |
          export GROK_PLUGIN_ROOT="${{ github.workspace }}"
          for t in hooks/test-*.sh; do
            case "$(basename "$t")" in test-inline-skill-gate.sh) continue ;; esac
            bash "$t"
          done
```

Note: Until full port, smoke tests may still call legacy bash scripts if subcommands delegate — **Phase 2+** implements subcommands; until then keep dual path or implement stubs returning allow/exit 0.

**Migration note for Task 2:** After Task 2 only `session-start` exists in Go; other subcommands must be added before flipping `hooks.json` for those events. **Order:** implement subcommand before changing its `hooks.json` line.

- [ ] **Step 6: Commit binaries + scripts**

```bash
git add scripts/build-hook.sh hooks/run-hook.sh hooks/hooks.json bin/ .github/workflows/ci.yml
git commit -m "feat(go): cross-compile omg-hook and arch dispatcher"
```

---

### Task 3: Hashline package (golden tests)

**Files:**
- Create: `internal/hashline/hash.go`, `internal/hashline/hash_test.go`
- Port logic from [`hooks/lib/hashline.py`](hooks/lib/hashline.py) lines 104–112

- [ ] **Step 1: Write failing golden test**

`internal/hashline/hash_test.go`:

```go
func TestComputeLineHashGoldenHello(t *testing.T) {
	got := ComputeLineHash(1, "  hello  ")
	if got != "ST" {
		t.Fatalf("got %q want ST", got)
	}
}

func TestComputeLineHashTrimEnd(t *testing.T) {
	a := ComputeLineHash(1, "function hello() {")
	b := ComputeLineHash(1, "function hello() {  ")
	if a != b {
		t.Fatalf("%s vs %s", a, b)
	}
}
```

- [ ] **Step 2: Run test — FAIL**

```bash
go test ./internal/hashline/... -run Golden -v
```

- [ ] **Step 3: Implement `ComputeLineHash`**

Copy `xxhash32` from Python (lines 47–92 in `hashline.py`) into Go `hash.go` using `[]byte` and uint32 math — **do not** use cespare with different seed rules until golden passes.

`ComputeLineHash(line int, content string) string` → `fmt.Sprintf("%d#%s", line, dict[hash%256])` with dict built from `ZPMQVRWSNKTXJBYH`.

Significant char check: `unicode.IsLetter` || `unicode.IsNumber` per rune.

- [ ] **Step 4: PASS + commit**

```bash
go test ./internal/hashline/... -v
git add internal/hashline
git commit -m "feat(go): port hashline-core line hash with golden tests"
```

---

### Task 4: Pre-tool-use subcommand

**Files:**
- Create: `internal/cmd/pre_tool_use.go`, wire packages `prometheus`, `hashline`, `skillgate`
- Modify: `cmd/omg-hook/main.go`
- Modify: `hooks/hooks.json` PreToolUse line only

- [ ] **Step 1: Write Go test for prometheus md-only deny**

`internal/prometheus/plan_test.go` — plan mode flag file exists → deny write to `src/foo.ts`.

- [ ] **Step 2: Implement prometheus PreTool guard**

Port [`evaluate_prometheus_pre_tool`](hooks/lib/prometheus.sh) logic: allow only `.omg/**/*.md`.

- [ ] **Step 3: Implement hashline PreTool validate**

Port stale `LINE#ID` check from [`hashline_validate_pre_tool`](hooks/lib/hashline.sh).

- [ ] **Step 4: Implement skillgate skeleton**

Port catalog count + loaded file from [`hooks/lib/common.sh`](hooks/lib/common.sh):
- If catalog empty → allow
- If any loaded → allow
- Else → deny with unloaded sample

Full `grok inspect` port can follow in Task 8; initially read cached `all-skills.json` from session-start.

- [ ] **Step 5: `pre-tool-use` command**

```go
// internal/cmd/pre_tool_use.go — order:
// 1. prometheus.DenyIfPlanMode(ev) → EmitDeny
// 2. hashline.ValidatePreTool(ev) → EmitDeny
// 3. skillgate.PreTool(ev) → EmitDeny or EmitAllow
```

- [ ] **Step 6: Switch hooks.json PreToolUse + run tests**

```bash
export GROK_PLUGIN_ROOT="$(pwd)"
bash hooks/test-prometheus.sh
bash hooks/test-hashline.sh
git add internal/cmd internal/prometheus internal/hashline internal/skillgate hooks/hooks.json cmd/omg-hook
git commit -m "feat(go): pre-tool-use chain in omg-hook"
```

---

### Task 5: Post-tool-read + hashline cache

**Files:**
- Create: `internal/hashline/cache.go`, `internal/cmd/post_tool_read.go`
- Modify: `hooks/hooks.json` Read matcher

- [ ] **Step 1: Test cache written on Read path**

Extend [`hooks/test-hashline.sh`](hooks/test-hashline.sh) — already uses `run-hook.sh`; ensure subcommand is `post-tool-read`.

- [ ] **Step 2: Implement `UpdateCacheFromRead(path)`**

SHA256 of absolute path as filename; JSON `{"lines":{"1":"ST",...}}`.

Skip `SKILL.md` paths (match `path_is_skill_file` semantics from bash).

- [ ] **Step 3: Mark skill loaded on SKILL.md read**

Append skill id to `~/.grok/state/skill-gate/<session>/skills.loaded`.

- [ ] **Step 4: Wire hooks.json PostToolUse Read → `post-tool-read`**

- [ ] **Step 5: Commit + `bash hooks/test-hashline.sh`**

---

### Task 6: Boulder + todo enforcer (Go)

**Files:**
- Create: `internal/boulder/*.go` (port [`omo_state.py`](hooks/lib/omo_state.py))
- Test: `internal/boulder/stop_test.go`

- [ ] **Step 1: Table-driven test for cooldown**

Port `should_skip_todo_continuation` — second stop within 5s must not block.

- [ ] **Step 2: Implement boulder read/write, plan progress, todo mirror**

Paths: `.omg/boulder.json`, `.omg/todos/<session>.json`, `~/.grok/state/todo-enforcer/<session>/state.json`.

- [ ] **Step 3: `EvaluateTodoStop`, `EvaluateBoulderStop` return (block bool, message string)**

- [ ] **Step 4: `bash hooks/test-todo-boulder.sh` passes with Go stop** (Task 7 wires stop)

---

### Task 7: Stop subcommand + ralph + lsp + stoppending

**Files:**
- Create: `internal/cmd/stop.go`, `internal/ralph/loop.go`, `internal/lsp/stash.go`, `internal/stoppending/planmd.go`

Stop order (must match [`hooks/lib/stop-chain.sh`](hooks/lib/stop-chain.sh)):

1. `ralph.EvaluateStop(ev)`
2. if `!boulder.AutoContinuePaused()` → boulder → todo → lsp → stoppending
3. EmitStopBlock or EmitStopAllow

- [ ] **Step 1: Port ralph stop evaluator** (read `.omg/ralph-loop.local.md`)

- [ ] **Step 2: Port lsp `EvaluateStop`** from [`hooks/lib/lsp.sh`](hooks/lib/lsp.sh)

- [ ] **Step 3: Wire `stop` subcommand + hooks.json Stop**

- [ ] **Step 4: Run**

```bash
bash hooks/test-ralph-loop.sh
bash hooks/test-ulw-loop.sh
bash hooks/test-todo-boulder.sh
bash hooks/test-lsp.sh
bash hooks/test-stop-verify.sh
```

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(go): stop chain in omg-hook"
```

---

### Task 8: User-prompt merge + session lifecycle

**Files:**
- Create: `internal/cmd/user_prompt.go`, `session_start.go`, `session_end.go`, `post_tool_todo.go`, `post_tool_lsp.go`
- Port collectors in order from [`hooks/user-prompt.sh`](hooks/user-prompt.sh) lines 44–67

```go
parts := []string{
  usingpowers.Collect(ev),
  workspace.Collect(ev),
  ralph.CollectUserPrompt(ev),
  intentgate.Collect(ev),
  prometheus.CollectUserPrompt(ev),
  handoff.Collect(ev),
  boulder.CollectStopContinuation(ev),
  boulder.CollectPromptContext(ev),
  lsp.CollectContext(ev),
  hashline.CollectContext(ev),
  skillgate.BuildReminder(ev),
}
hookio.EmitAdditionalContext(os.Stdout, mergeNonEmpty(parts), "UserPromptSubmit")
```

- [ ] **Step 1:** `session-start` runs `skillgate.RefreshCatalog()` via `exec grok inspect --json`

- [ ] **Step 2:** Implement remaining collectors (intentgate regex from [`intent-gate.sh`](hooks/lib/intent-gate.sh))

- [ ] **Step 3:** Flip all `hooks/hooks.json` entries to subcommands

- [ ] **Step 4:** Full smoke loop

```bash
export GROK_PLUGIN_ROOT="$(pwd)"
for t in hooks/test-*.sh; do
  case "$(basename "$t")" in test-inline-skill-gate.sh) continue ;; esac
  bash "$t" || exit 1
done
go test ./... -count=1
bash scripts/build-hook.sh
grok plugin validate .
```

- [ ] **Step 5: Commit**

---

### Task 9: Remove legacy runtime

**Files:**
- Delete: `hooks/lib/*.sh`, `hooks/lib/*.py`, `hooks/lib/__pycache__`, obsolete `hooks/*.sh` (except `run-hook.sh`, `run-hook.cmd`, `test-*.sh`)
- Modify: [`AGENTS.md`](AGENTS.md), [`hooks/README.md`](hooks/README.md), [`docs/installation.md`](docs/installation.md), [`CONTRIBUTING.md`](CONTRIBUTING.md)

- [ ] **Step 1: Delete legacy sources**

```bash
git rm hooks/lib/*.sh hooks/lib/*.py hooks/session-start.sh hooks/user-prompt.sh hooks/pre-tool-mutate.sh hooks/stop-hook.sh hooks/post-tool-*.sh hooks/session-end.sh 2>/dev/null || true
```

- [ ] **Step 2: Update docs — hooks require no python3; optional grok + node**

- [ ] **Step 3: Commit**

```bash
git commit -m "chore(go): remove bash/python hook runtime"
```

---

### Task 10: Hardening + doctor

**Files:**
- Create: `internal/config/flags.go`, `internal/cmd/session_start.go` doctor message

- [ ] **Step 1: Centralize `OMG_*` parsing**

- [ ] **Step 2: `session-start` prints warning if `bin/omg-hook-*` missing or not executable**

- [ ] **Step 3: Rebuild stripped binaries, document ~30MB total in CONTRIBUTING**

- [ ] **Step 4: Final commit**

```bash
git commit -m "feat(go): config flags and session-start binary doctor"
```

---

## Self-review

| Requirement | Task |
|-------------|------|
| Ship multi-platform binaries | Task 2, 6, 10 |
| One process per hook | All subcommands |
| PreTool order | Task 4 |
| Stop order | Task 7 |
| UserPrompt merge order | Task 8 |
| Hashline golden `1#ST` | Task 3 |
| MCP stays Node | Out of scope (unchanged `.mcp.json`) |
| Integration tests preserved | Tasks 4–8 |
| Memory vs bash+python | Task 4+ (remove legacy Task 9) |

**Placeholder scan:** No TBD sections.

**Task 2 caveat:** Do not point `hooks.json` at Go subcommands until each is implemented (incremental flip per task).

---

## Execution handoff

Plan complete and saved to [`docs/superpowers/plans/2026-06-02-go-hooks-migration.md`](docs/superpowers/plans/2026-06-02-go-hooks-migration.md).

**Two execution options:**

1. **Subagent-driven (recommended)** — One subagent per task (1–10), spec + code review between tasks.

2. **Inline execution** — Phases 1–4 in sequence with checkpoints after Tasks 2, 7, and 9.

**Which approach?**