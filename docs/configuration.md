# Configuration

## Two state locations

| Path | Owner | Contents |
|------|--------|----------|
| `~/.grok/` | Grok harness | `installed-plugins/`, `state/skill-gate/<session>/`, `state/stop-continuation/` |
| `.omg/` (per workspace) | oh-my-grok | `boulder.json`, `plans/`, `todos/`, `ralph-loop.local.md`, `handoffs/` |

Do not store plugin source or session catalogs under `.omg/`. `.omg/` is gitignored in this repo.

## Workspace AGENTS.md and rules

On every user prompt, oh-my-grok injects:

1. Workspace root `AGENTS.md` (if present), size-capped
2. Plugin `rules/*.md` from the install directory

Keep workspace `AGENTS.md` focused on project constraints; use `docs/` in this plugin repo for human guides.

## Environment variables (hooks)

| Variable | Role |
|----------|------|
| `GROK_PLUGIN_ROOT` | Plugin install path (set by harness or local tests) |
| `GROK_HOME` | Defaults to `~/.grok` |
| `GROK_WORKSPACE_ROOT` | Active workspace for `.omg/` and `AGENTS.md` |
| `GROK_SESSION_ID` | Session key for hook state |

Local hook tests: `export GROK_PLUGIN_ROOT="$(pwd)"`.

## superpowers plugin

The [superpowers](https://github.com/obra/superpowers) plugin may also register `SessionStart`. Both can run; avoid duplicating oh-my-grok hooks under `~/.grok/hooks/*.json`.

## Stop continuation priority

See [hooks/README.md](../hooks/README.md). First block wins:

1. Ralph / ultrawork loop
2. Boulder (`.omg/plans/`)
3. Todo continuation
4. Root `plan.md` fallback

`/stop-continuation` pauses steps 2–4 until `/resume-continuation` or session end.