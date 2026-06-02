# Contributing

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

Do **not** bump `plugin.json` version on feature PRs — release-please updates it in the Release PR.

## Releases

On merge to `main`, [release-please](https://github.com/googleapis/release-please) opens or updates a **Release PR** with `CHANGELOG.md` and `plugin.json` changes. Merging that PR creates the `v*` tag and GitHub Release.

See [README.md](README.md#releases) for install by tag.