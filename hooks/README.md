# Grok hooks layout

Plugin manifest: **`hooks/hooks.json`** (loaded via `GROK_PLUGIN_ROOT`). **Do not** add parallel `~/.grok/hooks/*.json` for this stack — use `grok plugin install github:mihazs/oh-my-grok --trust` (or `$(pwd)` from a local clone).

## Runtime

Hooks run as a **single Go binary** per OS/arch: `bin/omg-hook-<platform>`. [`run-hook.sh`](run-hook.sh) selects the binary and passes a subcommand (`session-start`, `user-prompt`, `pre-tool-use`, …). Rebuild with `scripts/build-hook.sh` (requires Go 1.22+). End users need **no** Python or Go installed.

Optional: **`grok`** CLI for `grok inspect` (skill catalog on SessionStart); **`node`** for LSP diagnostics post-edit (bundled MCP under `vendor/`).

## Event map

| Event | Subcommand | Role |
|-------|------------|------|
| `SessionStart` | `session-start` | Reset session state, refresh skill catalog, skill-gate banner |
| `UserPromptSubmit` | **`user-prompt`** | **One** merged `additionalContext` (see below) |
| `PreToolUse` | `pre-tool-use` | Prometheus plan-mode → hashline → skill gate |
| `PostToolUse` (Read) | `post-tool-read` | Hashline cache + mark SKILL.md loaded |
| `PostToolUse` (TodoWrite) | `post-tool-todo-write` | Mirror todos → `.omg/todos/<session>.json` |
| `PostToolUse` (Write\|StrReplace) | `post-tool-lsp` | LSP diagnostics → `~/.grok/state/lsp-diagnostics/<session>.json` |
| `Stop` | `stop` | Continuation chain (ralph → boulder → todo → lsp → plan.md) |
| `SessionEnd` | `session-end` | Reset session state |

## UserPromptSubmit (merged)

**`user-prompt`** collects and emits a single JSON payload:

1. `using-superpowers` (first prompt only)
2. Workspace `AGENTS.md` + plugin `rules/*.md` (every prompt; size-capped)
3. Ralph / ultrawork
4. **IntentGate** — search / analyze / team / hyperplan banners (`OMG_INTENT_GATE`)
5. **Prometheus** — `/plan`, `/start-work`, plan-mode state
6. `/handoff`, `/stop-continuation`, `/resume-continuation`
7. Boulder context (`.omg/boulder.json`)
8. **LSP** — `<LSP_DIAGNOSTICS>` from session stash
9. **Hashline** — `<HASHLINE_CACHE>` for recently read files
10. Skill-gate reminder

## Stop (priority chain)

**First block wins** (see `internal/cmd/stop.go`):

1. **Ralph / ultrawork** — not affected by `/stop-continuation` (but `/stop-continuation` clears loop state)
2. **Boulder** — `.omg/plans/*.md` progress
3. **Todo continuation** — incomplete `TodoWrite` items (**todo enforcer**: 5s cooldown, 3s abort window on non-`end_turn` stops; state in `~/.grok/state/todo-enforcer/<session>/state.json`)
4. **LSP** — error diagnostics in stash (skip when `OMG_LSP_ENFORCE=0`)
5. **plan.md** — root/session unchecked boxes (fallback)

Grok fires **`Stop`** (not Claude Code’s `session.idle`).

After `/stop-continuation`, steps 2–5 are skipped until `/resume-continuation` or `SessionEnd`.

**PreToolUse** (`pre-tool-use`): prometheus plan-mode deny → hashline stale `LINE#ID` deny → skill gate.

## Workspace state (`.omg/`)

| Path | Purpose |
|------|---------|
| `.omg/boulder.json` | Active plan work (omo-compatible schema) |
| `.omg/plans/*.md` | Prometheus-style plans |
| `.omg/todos/<session>.json` | Todo mirror |
| `.omg/run-continuation/<session>.json` | Pause marker (with `~/.grok/state/stop-continuation/`) |
| `.omg/ralph-loop.local.md` | Ralph / ultrawork loop |
| `.omg/handoffs/*.md` | Saved handoff summaries |

Session hook state under **`~/.grok/state/`**: skill-gate, stop-continuation, **hashline** (`state/hashline/<session>/`), **lsp-diagnostics** (`state/lsp-diagnostics/<session>.json`), **todo-enforcer**.

Bundled MCP (optional): `.mcp.json` — `ast_grep`, `lsp` under `vendor/` (see `skills/ast-grep`, `skills/lsp`).

## Plugin overlap

**superpowers** also registers `SessionStart`. Both may run; expect skill-gate + superpowers bootstrap on startup.

## Tests

From repo root with `GROK_PLUGIN_ROOT` set (see main README):

```bash
export GROK_PLUGIN_ROOT="$(pwd)"
bash hooks/test-stop-verify.sh
bash hooks/test-ralph-loop.sh
bash hooks/test-ulw-loop.sh
bash hooks/test-todo-boulder.sh
bash hooks/test-using-superpowers-first-prompt.sh
bash hooks/test-handoff.sh
bash hooks/test-intent-gate.sh
bash hooks/test-prometheus.sh
bash hooks/test-hashline.sh
bash hooks/test-lsp.sh
```

`OMG_*` toggles: [docs/configuration.md](../docs/configuration.md).