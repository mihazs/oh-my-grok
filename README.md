# oh-my-grok

**The essential productivity layer for the new Grok Build CLI.**

[![CI](https://github.com/mihazs/oh-my-grok/actions/workflows/ci.yml/badge.svg)](https://github.com/mihazs/oh-my-grok/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/github/license/mihazs/oh-my-grok?style=flat-square)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/mihazs/oh-my-grok?style=flat-square)](https://github.com/mihazs/oh-my-grok/stargazers)
[![Last commit](https://img.shields.io/github/last-commit/mihazs/oh-my-grok?style=flat-square)](https://github.com/mihazs/oh-my-grok/commits/main)
[![Release](https://img.shields.io/github/v/release/mihazs/oh-my-grok?style=flat-square)](https://github.com/mihazs/oh-my-grok/releases)

```bash
grok plugin install github:mihazs/oh-my-grok --trust && grok plugin enable oh-my-grok
```

**Author:** [mihazs](https://github.com/mihazs) · **Repository:** https://github.com/mihazs/oh-my-grok

---

## Why oh-my-grok?

Grok Build CLI is new. The plugin ecosystem is still thin — no mature “oh-my” style productivity layer out of the box.

**oh-my-grok** ports proven patterns from [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent) (Ralph loops, boulder/todos, handoff, skill gate, unified Stop chain) into a **Grok-native plugin**: hooks + skills + rules, workspace state under **`.omg/`**.

It **complements** oh-my-openagent — it does not compete. omo targets OpenCode / Codex and multi-harness orchestration; oh-my-grok targets **Grok Build** only.

---

## Features

- **Agent skill gate** — blocks mutating tools until applicable `SKILL.md` files are Read
- **Ralph loop** — `/ralph-loop` work-until-done with Stop-hook continuations
- **Ultrawork** — `/ulw-loop` / `/ultrawork` with mandatory verifier before exit
- **Todo + boulder** — plan progress and todo mirroring under `.omg/`
- **Handoff** — `/handoff` structured context for new sessions
- **Merged hooks** — single `UserPromptSubmit` payload (no context overwrite)
- **Workspace context** — injects project `AGENTS.md` + plugin rules every prompt
- **Stop chain** — Ralph → boulder → todos → plan fallback (priority documented)

---

## Compatibility

Works with **Grok Build CLI** (early beta).

| Check | Where |
|-------|--------|
| Hook smoke tests | GitHub Actions CI (Ubuntu) |
| `grok plugin validate` | Local only (Grok CLI required) |
| Inline skill-gate E2E | Local: `hooks/test-inline-skill-gate.sh` |

Reload hooks after install: new session or TUI `Ctrl+L` → Hooks.

---

## Comparison

| | Vanilla Grok Build | oh-my-grok | oh-my-openagent |
|--|-------------------|------------|-----------------|
| **Harness** | Grok Build CLI | Grok Build CLI | OpenCode, Codex, others |
| **Install** | Core + optional plugins | `grok plugin install github:mihazs/oh-my-grok` | `bunx oh-my-openagent` / npm |
| **Skill gate** | Optional / manual | Built-in hooks | Yes (omo) |
| **Ralph / ultrawork** | No | `/ralph-loop`, `/ulw-loop` | Yes |
| **Workspace state** | Project-specific | `.omg/` | `.omo/` |
| **Relationship** | Baseline | Grok plugin gap-filler | Upstream inspiration; use both if you use both harnesses |

---

## Quick start

1. Install and enable (command at top).
2. Open a project workspace; optional: add `AGENTS.md` at repo root.
3. Try a slash command:

| Command | Effect |
|---------|--------|
| `/ralph-loop "task"` | Work-until-done loop |
| `/ulw-loop "task"` | Ralph + verification |
| `/cancel-ralph` | Clear loop state |
| `/handoff` | Session handoff summary |
| `/stop-continuation` | Pause auto-continue |
| `/resume-continuation` | Resume auto-continue |

**Docs:** [Installation](docs/installation.md) · [Skills](docs/skills.md) · [Configuration](docs/configuration.md) · [Troubleshooting](docs/troubleshooting.md) · [Examples](docs/examples/README.md) · [Roadmap](ROADMAP.md)

**Hook internals:** [hooks/README.md](hooks/README.md)

---

## Configuration

- Workspace runtime: `.omg/` (boulder, plans, todos, ralph-loop, handoffs) — see [docs/configuration.md](docs/configuration.md)
- Plugin install: `~/.grok/installed-plugins/oh-my-grok-*`
- Do **not** duplicate hooks in `~/.grok/hooks/` — [migrate](docs/installation.md#migrate-from-global-copies) if needed

---

## Custom skills

Project skills live in `.agents/skills/` or `.grok/skills/`. The skill gate uses the full `grok inspect` catalog. See [docs/skills.md](docs/skills.md).

---

## Troubleshooting

Stale install, double hooks, skill-gate blocks, loop won’t stop — [docs/troubleshooting.md](docs/troubleshooting.md).

---

## Skip This README

**Agents:** do not treat this file as the implementation spec. Use:

```
Read AGENTS.md and docs/installation.md for oh-my-grok plugin work:
https://raw.githubusercontent.com/mihazs/oh-my-grok/main/AGENTS.md
https://raw.githubusercontent.com/mihazs/oh-my-grok/main/docs/installation.md
```

Hook and stop-chain details: `hooks/README.md`.

---

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

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Releases

Automated via [release-please](https://github.com/googleapis/release-please): conventional commits on `main` → Release PR → tag `vX.Y.Z`. See [CHANGELOG.md](CHANGELOG.md).

```bash
grok plugin install github:mihazs/oh-my-grok@v0.2.0 --trust   # when tag exists
```

## License

[MIT](LICENSE)