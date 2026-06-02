# oh-my-grok

Grok plugin: skill gate, merged `UserPromptSubmit`, Ralph/ultrawork loops, todo + boulder continuation, and unified `Stop` chain.

**Author:** mihazs · **Repository:** https://github.com/mihazs/oh-my-grok

Inspired by [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent). Workspace runtime state lives under **`.omg/`** (oh-my-grok; analogous to omo’s `.omo/`).

## Install (plugin only)

Do **not** copy hooks into `~/.grok/hooks/`. Install the plugin once:

```bash
grok plugin install github:mihazs/oh-my-grok --trust
grok plugin enable oh-my-grok
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
  skills/               # agent-skill-gate, ralph-loop, ulw-loop, cancel-ralph
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
```

After editing hooks, run `grok plugin update oh-my-grok` (or reinstall from your path) and start a new session if hooks do not reload.