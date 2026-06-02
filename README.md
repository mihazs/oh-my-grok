# oh-my-grok

[![CI](https://github.com/mihazs/oh-my-grok/actions/workflows/ci.yml/badge.svg)](https://github.com/mihazs/oh-my-grok/actions/workflows/ci.yml)

Grok plugin: skill gate, merged `UserPromptSubmit`, Ralph/ultrawork loops, todo + boulder continuation, and unified `Stop` chain.

**Author:** mihazs · **Repository:** https://github.com/mihazs/oh-my-grok

Inspired by [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent). Workspace runtime state lives under **`.omg/`** (oh-my-grok; analogous to omo’s `.omo/`).

## Install (plugin only)

Do **not** copy hooks into `~/.grok/hooks/`. Install the plugin once:

```bash
grok plugin install github:mihazs/oh-my-grok --trust
grok plugin enable oh-my-grok
```

Pinned to a release (see [Releases](https://github.com/mihazs/oh-my-grok/releases)):

```bash
grok plugin install github:mihazs/oh-my-grok@v0.1.0 --trust
```

Local development (from a clone of this repo):

```bash
git clone https://github.com/mihazs/oh-my-grok.git
cd oh-my-grok
grok plugin install "$(pwd)" --trust
grok plugin enable oh-my-grok
```

Reload hooks in the TUI (`Ctrl+L` → Hooks) or start a new session.

### Migrating from global copies

If you previously installed hooks under `~/.grok/hooks/` or duplicated skills/rules globally:

```bash
bash scripts/remove-global-overlays.sh
grok plugin install github:mihazs/oh-my-grok --trust
```

That archives removed files under `~/.grok/archive/removed-global-oh-my-grok-<date>/`.

## Layout

```
oh-my-grok/
  plugin.json
  hooks/hooks.json      # manifest (uses ${GROK_PLUGIN_ROOT})
  hooks/lib/            # ralph, boulder, stop-chain, common
  skills/               # agent-skill-gate, ralph-loop, ulw-loop, cancel-ralph, handoff
  rules/                # injected via skill-gate context
```

See [hooks/README.md](hooks/README.md) for event map and stop priority.

## Commands

| Command | Effect |
|---------|--------|
| `/ralph-loop "task"` | Work-until-done loop |
| `/ulw-loop "task"` | Ralph + Oracle verification |
| `/cancel-ralph` | Clear loop state |
| `/stop-continuation` | Pause auto-continue; clear loop + boulder |
| `/resume-continuation` | Resume auto-continue |
| `/handoff` | Structured HANDOFF CONTEXT for a new session |

## Develop

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

After editing hooks, run `grok plugin update oh-my-grok` (or reinstall from your path) and start a new session if hooks do not reload.

CI runs the same hook tests on every PR (see `.github/workflows/ci.yml`). `grok plugin validate` is local-only.

## Releases

Versions are automated with [release-please](https://github.com/googleapis/release-please):

1. Merge conventional commits to `main` (`feat:`, `fix:`, etc. — see [CONTRIBUTING.md](CONTRIBUTING.md)).
2. A **Release PR** updates `CHANGELOG.md` and `plugin.json`.
3. Merge the Release PR → Git tag `vX.Y.Z` and a [GitHub Release](https://github.com/mihazs/oh-my-grok/releases).

Do not bump `plugin.json` manually on feature branches.