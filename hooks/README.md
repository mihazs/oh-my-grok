# Grok hooks layout

Plugin manifest: **`hooks/hooks.json`** (loaded via `GROK_PLUGIN_ROOT`). **Do not** add parallel `~/.grok/hooks/*.json` for this stack — use `grok plugin install github:mihazs/oh-my-grok --trust` (or `$(pwd)` from a local clone).

## Event map

| Event | Script | Role |
|-------|--------|------|
| `SessionStart` | `session-start.sh` | Skill catalog + skill-gate rules |
| `UserPromptSubmit` | **`user-prompt.sh`** | **One** merged `additionalContext` (see below) |
| `PreToolUse` | `pre-tool-mutate.sh` | Block writes until a skill is Read |
| `PostToolUse` (Read) | `post-tool-read.sh` | Mark skill loaded when `SKILL.md` is Read |
| `PostToolUse` (TodoWrite) | `post-tool-todo-write.sh` | Mirror todos → `.omg/todos/<session>.json` |
| `Stop` | `stop-hook.sh` | Continuation chain (`lib/stop-chain.sh`) |
| `SessionEnd` | `session-end.sh` | Reset session state |

## UserPromptSubmit (merged)

**`user-prompt.sh`** collects and emits a single JSON payload:

1. `using-superpowers` (first prompt only)
2. Workspace `AGENTS.md` + plugin `rules/*.md` (every prompt; size-capped)
3. Ralph / ultrawork commands (`/ralph-loop`, `/cancel-ralph`, …)
4. `/handoff` — session handoff summary (handoff skill; omo port)
5. `/stop-continuation`, `/resume-continuation`
6. Boulder context (`.omg/boulder.json`)
7. Skill-gate reminder

## Stop (priority chain)

`lib/stop-chain.sh` — **first block wins**:

1. **Ralph / ultrawork** — not affected by `/stop-continuation` (but `/stop-continuation` clears loop state)
2. **Boulder** — `.omg/plans/*.md` progress
3. **Todo continuation** — incomplete `TodoWrite` items
4. **plan.md** — root/session unchecked boxes (fallback)

After `/stop-continuation`, steps 2–4 are skipped until `/resume-continuation` or `SessionEnd`.

## Workspace state (`.omg/`)

| Path | Purpose |
|------|---------|
| `.omg/boulder.json` | Active plan work (omo-compatible schema) |
| `.omg/plans/*.md` | Prometheus-style plans |
| `.omg/todos/<session>.json` | Todo mirror |
| `.omg/run-continuation/<session>.json` | Pause marker (with `~/.grok/state/stop-continuation/`) |
| `.omg/ralph-loop.local.md` | Ralph / ultrawork loop |
| `.omg/handoffs/*.md` | Saved handoff summaries |

Session hook state (skill catalog, stop-verify) stays under **`~/.grok/state/`** (Grok home).

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
```