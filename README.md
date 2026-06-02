# oh-my-grok

<p align="center">
  <img src=".github/oh-my-grok.svg" alt="oh-my-grok" width="100" />
</p>

**The missing productivity layer for the new Grok Build CLI.**

Makes Grok significantly more effective at long-running tasks with proven loops and state management.

[![CI](https://github.com/mihazs/oh-my-grok/actions/workflows/ci.yml/badge.svg)](https://github.com/mihazs/oh-my-grok/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/github/license/mihazs/oh-my-grok?style=flat-square)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/mihazs/oh-my-grok?style=flat-square)](https://github.com/mihazs/oh-my-grok/stargazers)
[![Release](https://img.shields.io/github/v/release/mihazs/oh-my-grok?style=flat-square)](https://github.com/mihazs/oh-my-grok/releases)
[![Grok Build](https://img.shields.io/badge/Grok%20Build-0.1.x%2B-111827?style=flat-square)](docs/installation.md)

```bash
grok plugin install github:mihazs/oh-my-grok --trust && grok plugin enable oh-my-grok
```

Pinned release:

```bash
grok plugin install github:mihazs/oh-my-grok@v0.1.0 --trust
```

**Author:** [mihazs](https://github.com/mihazs) · **Repository:** https://github.com/mihazs/oh-my-grok

---

## Why oh-my-grok?

Grok Build CLI launched with a thin plugin ecosystem — no mature “oh-my” productivity layer for long-running agentic work.

**oh-my-grok** fills that gap: skill gate, Ralph and Ultrawork loops, todo/boulder continuation, handoff, and a unified Stop chain — ported from proven [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent) patterns into a **Grok-native** plugin (hooks + skills + rules, workspace state in **`.omg/`**).

It **complements** oh-my-openagent; it does **not** replace it. Use omo for OpenCode/Codex/multi-harness; use oh-my-grok when you work in **Grok Build** only.

---

## Features

- 🛡️ **Skill gate** — blocks mutating tools until matching `SKILL.md` files are Read
- 🔁 **Ralph loop** — `/ralph-loop` work-until-done via Stop-hook continuations
- ⚡ **Ultrawork** — `/ulw-loop` / `/ultrawork` with mandatory verifier before exit
- 🪨 **Todo + boulder** — plan progress and todo mirroring under `.omg/`
- 📋 **Handoff** — `/handoff` structured context for new sessions
- 🔗 **Merged hooks** — one `UserPromptSubmit` payload (no context overwrite)
- 📄 **Workspace context** — project `AGENTS.md` + plugin rules every prompt
- 🛑 **Stop chain** — Ralph → boulder → todos → plan (documented priority)

---

## Demo

Visual demos (TUI with plugin enabled, `/ralph-loop` in action) coming soon.

---

## Compatibility

Requires **Grok Build CLI 0.1.x or newer** (tested with **0.2.x**).

| Check | Where |
|-------|--------|
| `grok plugin validate .` | After install (local Grok CLI) |
| Hook smoke tests | GitHub Actions CI when billing active |
| Inline skill-gate E2E | Local: `hooks/test-inline-skill-gate.sh` |

Reload hooks after install: new session or TUI `Ctrl+L` → Hooks.

---

## Comparison

| | Vanilla Grok Build | oh-my-grok |
|--|-------------------|------------|
| **Productivity plugin** | Bring your own / none | Batteries-included oh-my patterns |
| **Skill gate** | Manual | Hook-enforced catalog Read |
| **Long-running loops** | No | `/ralph-loop`, `/ulw-loop` |
| **Workspace state** | Ad hoc | `.omg/` (boulder, todos, handoff, ralph) |
| **Stop continuation** | Session ends | Unified Stop chain with pause/resume |

Upstream inspiration for loop/boulder/handoff patterns: [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent) (different harness).

---

## Quick start

1. Install and enable (commands above).
2. Open a project; optional: add `AGENTS.md` at repo root.
3. Run a slash command:

| Command | Effect | Example |
|---------|--------|---------|
| `/ralph-loop "task"` | Work-until-done loop | `/ralph-loop "fix failing hook tests"` |
| `/ulw-loop "task"` | Ralph + verification | `/ultrawork "ship docs polish"` |
| `/cancel-ralph` | Clear loop state | `/cancel-ralph` |
| `/handoff` | Session handoff summary | `/handoff` |
| `/stop-continuation` | Pause auto-continue | `/stop-continuation` |
| `/resume-continuation` | Resume auto-continue | `/resume-continuation` |

**Docs:** [Installation](docs/installation.md) · [Skills](docs/skills.md) · [Configuration](docs/configuration.md) · [Troubleshooting](docs/troubleshooting.md) · [Examples](docs/examples/README.md) · [Roadmap](ROADMAP.md)

**Hook internals:** [hooks/README.md](hooks/README.md)

---

## Configuration

See [docs/configuration.md](docs/configuration.md) — `.omg/` workspace state, `~/.grok/installed-plugins/`, no duplicate `~/.grok/hooks/`.

---

## Custom skills

Project skills: `.agents/skills/` or `.grok/skills/`. Full catalog via `grok inspect`. Details: [docs/skills.md](docs/skills.md).

---

## Troubleshooting

[docs/troubleshooting.md](docs/troubleshooting.md) — stale install, double hooks, skill-gate blocks, loops that won’t stop.

---

## Skip This README

**Agents:** use implementation docs, not this marketing page:

```
https://raw.githubusercontent.com/mihazs/oh-my-grok/main/AGENTS.md
https://raw.githubusercontent.com/mihazs/oh-my-grok/main/docs/installation.md
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — conventional commits, hook tests, complements oh-my-openagent.

[Open an issue](https://github.com/mihazs/oh-my-grok/issues/new/choose) for bugs or feature requests.

## Support

- **Issues:** [GitHub Issues](https://github.com/mihazs/oh-my-grok/issues) (bug / feature templates)
- **Roadmap:** [ROADMAP.md](ROADMAP.md)
- **Releases:** [CHANGELOG.md](CHANGELOG.md) via [release-please](https://github.com/googleapis/release-please)

## Develop

```bash
cd oh-my-grok
grok plugin validate .
export GROK_PLUGIN_ROOT="$(pwd)"
for t in hooks/test-*.sh; do
  case "$(basename "$t")" in test-inline-skill-gate.sh) continue ;; esac
  bash "$t"
done
```

## License

[MIT](LICENSE)