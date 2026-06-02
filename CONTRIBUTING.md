# Contributing

Thank you for helping improve oh-my-grok.

## Relationship to oh-my-openagent

[oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent) (omo) is the upstream inspiration for Ralph loops, boulder/todos, handoff, and skill-gate patterns.

**oh-my-grok complements omo — it does not replace it.**

| | oh-my-grok | oh-my-openagent |
|--|------------|-----------------|
| Harness | Grok Build CLI | OpenCode, Codex, multi-harness |
| Workspace state | `.omg/` | `.omo/` |
| Install | `grok plugin install github:mihazs/oh-my-grok` | npm / bun installers |

When porting behavior from omo, adapt paths and hooks for Grok’s plugin model. Do not copy OpenCode-specific assumptions into this repo.

See [ROADMAP.md](ROADMAP.md) for planned work.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/) so release-please can pick the semver bump:

| Prefix | Version bump |
|--------|----------------|
| `fix:` | patch |
| `feat:` | minor |
| `feat!:` / `fix!:` / footer `BREAKING CHANGE:` | major |
| `chore:`, `docs:`, `test:`, `ci:` | no release (unless noted in PR) |

Examples:

```
feat: add workspace rules injection on UserPromptSubmit
fix: stop-chain skips boulder when continuation paused
docs: document release workflow in README
```

## Pull requests

1. Branch from `main`.
2. Run hook tests locally (CI runs the same set):

```bash
export GROK_PLUGIN_ROOT="$(pwd)"
for t in hooks/test-*.sh; do
  case "$(basename "$t")" in test-inline-skill-gate.sh) continue ;; esac
  bash "$t"
done
```

3. Optional: `grok plugin validate .` (requires Grok CLI; not run in CI).
4. Use the PR template checklist.

Do **not** bump `plugin.json` version on feature PRs — release-please updates it in the Release PR.

## Releases

On merge to `main`, [release-please](https://github.com/googleapis/release-please) opens or updates a **Release PR** with `CHANGELOG.md` and `plugin.json` changes. Merging that PR creates the `v*` tag and GitHub Release.

See [README.md](README.md#releases).

## Maintainers (repo metadata)

GitHub description and topics are not stored in git. After major positioning changes, update via:

```bash
gh repo edit mihazs/oh-my-grok \
  --description "oh-my-grok: Essential productivity plugin for Grok Build CLI — skill gate, Ralph & Ultrawork loops, todo/boulder continuation, handoff, unified Stop chain (oh-my-openagent inspired)" \
  --homepage "https://github.com/mihazs/oh-my-grok"
# Topics: grok-build grok-plugin oh-my-grok grok-cli ralph-loop agentic-workflow ai-coding productivity multi-agent xai
```

## Agent contributors

Implementation work: read [AGENTS.md](AGENTS.md) and [docs/installation.md](docs/installation.md), not the marketing README alone.