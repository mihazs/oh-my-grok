# Changelog

All notable changes to this project are documented in this file.

Releases are normally automated via [release-please](https://github.com/googleapis/release-please) when GitHub Actions billing is active. While Actions is disabled, use [`scripts/manual-release.sh`](scripts/manual-release.sh).

## [0.1.0](https://github.com/mihazs/oh-my-grok/releases/tag/v0.1.0) (2026-06-02)

### Features

* Initial oh-my-grok Grok plugin: skill gate, Ralph/ultrawork loops, todo + boulder continuation, unified Stop chain
* Workspace runtime state under `.omg/` (boulder, plans, todos, ralph-loop, handoffs)
* Handoff skill (`/handoff`) ported from oh-my-openagent
* Per-prompt injection of workspace `AGENTS.md` and bundled plugin `rules/*.md`
* Merged `UserPromptSubmit` hook; Stop priority chain in `hooks/lib/stop-chain.sh`
* First-prompt `using-superpowers` injection when superpowers is installed

### Documentation

* Marketing README, `docs/` guides, `ROADMAP.md`, GitHub issue/PR templates
* Agent-focused `AGENTS.md` with skill-gate flow and plugin editing rules
* SVG logo (`.github/oh-my-grok.svg`)

### CI

* GitHub Actions hook smoke tests (`.github/workflows/ci.yml`)
* release-please workflow (`.github/workflows/release.yml`) — requires Actions billing to run