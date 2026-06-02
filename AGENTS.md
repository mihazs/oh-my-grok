# oh-my-grok — agent guide

**README.md** is for humans (install, features, links). **This file** is for coding agents editing the plugin or debugging hook behavior. Keep changes aligned with both; do not duplicate the full README here.

Inspired by [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent). Upstream handoff/Ralph/boulder behavior is ported and adapted for **Grok Composer** + `grok plugin`.

---

## What this repository is

| Is | Is not |
|----|--------|
| A **Grok plugin** (`plugin.json`, `hooks/hooks.json`, bundled skills/rules) | A standalone CLI or application users run from this repo |
| Hook shell + Python under `hooks/` | User application code |
| Install target: `grok plugin install github:mihazs/oh-my-grok --trust` | Global copies under `~/.grok/hooks/` (deprecated; plugin-only) |

After install, Grok loads hooks from `GROK_PLUGIN_ROOT` (installed copy under `~/.grok/installed-plugins/oh-my-grok-*`, often symlinked to a local clone).

---

## Architecture (30-second map)

```
plugin.json
hooks/hooks.json          → SessionStart, UserPromptSubmit, Pre/PostToolUse, Stop, SessionEnd
hooks/user-prompt.sh      → single merged additionalContext (do not split into multiple JSON hooks)
hooks/stop-hook.sh        → lib/stop-chain.sh (first block wins)
hooks/lib/
  common.sh               → GROK_HOME, PLUGIN_ROOT, skill catalog, session state
  ralph-loop.sh           → /ralph-loop, /ulw-loop, /cancel-ralph
  handoff.sh              → /handoff
  todo-boulder.sh         → boulder + todo continuation
  omo_state.py            → .omg paths, boulder.json, plan progress
skills/*/SKILL.md         → user-invocable workflows (discovered by grok inspect)
rules/*.md                → injected on every UserPromptSubmit (with workspace AGENTS.md)
```

**superpowers** may also register `SessionStart`; both can run. Do not register duplicate oh-my-grok hooks globally.

---

## Two state namespaces (do not confuse)

| Location | Owner | Examples |
|----------|--------|----------|
| **`~/.grok/`** | Grok harness | `installed-plugins/`, `state/skill-gate/<session>/`, `state/stop-continuation/`, `sessions/` |
| **`.omg/`** (per workspace) | oh-my-grok runtime | `boulder.json`, `plans/`, `todos/`, `ralph-loop.local.md`, `handoffs/` |

Analogous to omo’s **`.omo/`** in OpenCode workspaces. Never store plugin source or session catalogs under `.omg/`.

---

## Bundled skills & slash commands

| Skill | Command | Hook involvement |
|-------|---------|------------------|
| `agent-skill-gate` | (meta; Read before mutating) | `pre-tool-mutate.sh`, `post-tool-read.sh`, `session-start.sh` |
| `ralph-loop` | `/ralph-loop "task"` | `user-prompt.sh`, `stop-hook.sh` |
| `ulw-loop` | `/ulw-loop "task"` | same + Oracle verification pending |
| `cancel-ralph` | `/cancel-ralph` | clears `.omg/ralph-loop.local.md` |
| `handoff` | `/handoff` | `handoff.sh` injects PHASE 0–4 instructions |

User-facing pause/resume: `/stop-continuation`, `/resume-continuation` (see `rules/12-todo-boulder.md`).

Full event map and stop priority: **`hooks/README.md`** (read when touching Stop or UserPromptSubmit).

---

## Where to look (progressive disclosure)

| Task | Read first |
|------|------------|
| Install / publish / repo URL | `README.md`, `docs/installation.md` |
| Hook events, stop chain, `.omg/` layout | `hooks/README.md` |
| Skill-gate behavior | `skills/agent-skill-gate/SKILL.md`, `rules/00-agent-skill-gate.md` |
| Ralph / ultrawork | `skills/ralph-loop/SKILL.md`, `skills/ulw-loop/SKILL.md`, `rules/10-ralph-loop.md` |
| Boulder + todos | `rules/12-todo-boulder.md`, `hooks/lib/omo_state.py` |
| Handoff format | `skills/handoff/SKILL.md`, `rules/11-handoff.md` |
| Remove stale global install | `scripts/remove-global-overlays.sh` |

Do not paste entire skill bodies into this file. Load the path from `grok inspect` when implementing.

---

## Development workflow

1. Clone repo; set `export GROK_PLUGIN_ROOT="$(pwd)"` for local hook tests.
2. Edit `hooks/`, `skills/`, or `rules/` — see decision table below.
3. Run smoke tests (required before claiming done):

```bash
cd oh-my-grok
grok plugin validate .
export GROK_PLUGIN_ROOT="$(pwd)"
bash hooks/test-ralph-loop.sh
bash hooks/test-ulw-loop.sh
bash hooks/test-todo-boulder.sh
bash hooks/test-stop-verify.sh
bash hooks/test-using-superpowers-first-prompt.sh
bash hooks/test-handoff.sh
bash hooks/test-workspace-context.sh
```

4. Refresh install: `grok plugin update oh-my-grok` (or `grok plugin install "$(pwd)" --trust`).
5. **New Grok session** or TUI Hooks reload (`Ctrl+L`) — hooks do not always hot-reload mid-session.

Optional E2E: `bash hooks/test-inline-skill-gate.sh` (needs `grok` CLI + trusted workspace).

---

## What to change when (decision table)

| You need to… | Edit | Avoid |
|--------------|------|--------|
| New slash command or prompt injection | `hooks/lib/*.sh`, wire in `user-prompt.sh` | Extra `UserPromptSubmit` JSON in `hooks.json` (overwrites context) |
| New lifecycle hook event | `hooks/hooks.json` + new script under `hooks/` | Duplicate manifest under `~/.grok/hooks/` |
| Agent-facing workflow / phases | `skills/<name>/SKILL.md` | Long prose only in `rules/` without a skill |
| Always-on Composer rules | `rules/*.md` (keep short) | 30+ “don’t” lines without “do” alternatives |
| Workspace file paths (boulder, todos) | `hooks/lib/omo_state.py` constants + docs | Hardcoded `/home/...` paths anywhere in repo |
| Stop continuation order | `hooks/lib/stop-chain.sh` only | Second Stop hook registration |

Pair every **don’t** with a **do** in rules (e.g. don’t add global `~/.grok/hooks/*.json` → do install via `grok plugin install`).

---

## Plugin editing rules

1. **One JSON context per event** — `user-prompt.sh` merges all `UserPromptSubmit` parts; never add a second manifest entry for the same event.
2. **Stop order** — only change in `hooks/lib/stop-chain.sh`; update `hooks/README.md` + tests.
3. **New slash command** — add `hooks/lib/<feature>.sh`, source from `user-prompt.sh`, add `skills/<name>/SKILL.md` with `user_invocable: true`, add `hooks/test-<feature>.sh`.
4. **Workspace paths** — constants in `hooks/lib/omo_state.py`; never hardcode user home directories in tracked files.
5. **Docs** — human guides in `docs/` and `README.md`; this file stays hook/skill oriented.

Human docs: `docs/installation.md`, `docs/skills.md`, `docs/configuration.md`. Roadmap: `ROADMAP.md`.

### Example: add a prompt hook fragment

1. Create `hooks/lib/my-feature.sh` with `collect_user_prompt_my_feature()` returning context text.
2. In `user-prompt.sh`: `source` the lib, call collector, pass into `emit_user_prompt_context`.
3. Add `hooks/test-my-feature.sh` with `GROK_PLUGIN_ROOT` set and stdin JSON fixture.
4. Document in `hooks/README.md` UserPromptSubmit list.

### Example: add a user-invocable skill

1. Add `skills/my-skill/SKILL.md` with frontmatter `name`, `description`, `user_invocable: true`.
2. If the skill needs prompt injection, wire a collector in `user-prompt.sh` (pattern: `handoff.sh`, `ralph-loop.sh`).
3. Run `grok plugin validate .` and hook smoke tests.

---

## Conventions

- **Shell**: `bash`, `set -euo pipefail`; hook entry via `hooks/run-hook.sh`.
- **Search**: use `rg`, not `grep`, in docs and agent instructions for this repo.
- **Paths in repo**: machine-agnostic (`$(pwd)`, `oh-my-grok/`); author metadata in `plugin.json` / LICENSE is fine; no contributor home directories in source.
- **Hook JSON output**: one `additionalContext` per event per manifest path; `user-prompt.sh` merges parts.
- **Tests**: temp dirs use `.omg/` subdirs; do not depend on a specific user workspace path.
- **Python** in hooks: `omo_state.py` stays compatible with omo boulder schema where possible.

---

## Anti-patterns

- Registering the same hooks in **`~/.grok/hooks/*.json`** and the plugin (double Stop / UserPromptSubmit).
- Adding legacy `user-prompt-*.sh` hooks to `hooks.json` (merged handler exists).
- Changing stop order without updating `hooks/README.md` and tests.
- Documenting only `~/.grok/` for boulder/ralph state — user workspaces use **`.omg/`**.
- Bloating this AGENTS.md past ~150 lines; link to `hooks/README.md` and skills instead.

---

## Verification checklist (before PR / push)

- [ ] CI hook smoke tests pass (same as `.github/workflows/ci.yml`; skip `test-inline-skill-gate.sh`)
- [ ] `grok plugin validate .` passes (local; Grok CLI not in CI)
- [ ] All `hooks/test-*.sh` scripts pass with `GROK_PLUGIN_ROOT` set (except inline E2E)
- [ ] Conventional commit message if the change should appear in the next release
- [ ] Do not bump `plugin.json` version — release-please handles it via Release PR
- [ ] No leaked home-directory paths in tracked files
- [ ] `hooks/hooks.json` uses `${GROK_PLUGIN_ROOT}` for commands
- [ ] New skill has frontmatter `name` + `description` triggers; `user_invocable: true` if slash command

Human install docs: **README.md**. Hook internals: **hooks/README.md**.