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
2. Rebuild hook binaries after Go changes:

```bash
bash scripts/build-hook.sh
GOFLAGS=-mod=mod go test ./... -count=1
```

3. Run hook smoke tests locally (CI runs the same set):

```bash
export GROK_PLUGIN_ROOT="$(pwd)"
for t in hooks/test-*.sh; do
  case "$(basename "$t")" in test-inline-skill-gate.sh|test-support.sh) continue ;; esac
  bash "$t"
done
```

Committed `bin/omg-hook-*` total ~30MB across five platforms (linux/darwin amd64+arm64, windows amd64).

4. Optional: `grok plugin validate .` (requires Grok CLI; not run in CI).
5. Use the PR template checklist.

Do **not** bump `plugin.json` version on feature PRs — release-please updates it in the Release PR.

## Releases

**When GitHub Actions billing is active:** [release-please](https://github.com/googleapis/release-please) opens a **Release PR** on merge to `main`. Merging it creates the `v*` tag and GitHub Release.

**When Actions is locked:** release manually (no CI required):

```bash
# 1. Update CHANGELOG.md with ## [X.Y.Z] section
# 2. Commit to main, then:
./scripts/manual-release.sh X.Y.Z
```

The script tags `HEAD`, pushes the tag, and creates/updates the GitHub Release from the CHANGELOG section.

Current release: [v0.1.0](https://github.com/mihazs/oh-my-grok/releases/tag/v0.1.0).

See [README.md](README.md).

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