## Summary

<!-- What does this PR change? -->

## Type

- [ ] `feat:` — minor release bump (release-please)
- [ ] `fix:` — patch release bump
- [ ] `docs:` / `chore:` / `ci:` — no version bump (unless release noted)
- [ ] Breaking change (`feat!:` / `fix!:` / BREAKING CHANGE footer)

## Checklist

- [ ] Hook smoke tests pass (`export GROK_PLUGIN_ROOT="$(pwd)"`; skip `test-inline-skill-gate.sh`)
- [ ] `hooks/hooks.json` unchanged or still uses `${GROK_PLUGIN_ROOT}` only
- [ ] **Did not** bump `plugin.json` version (release-please Release PR handles it)
- [ ] Stop chain / `hooks/README.md` updated if Stop order changed
- [ ] Complements [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent) — not a fork; Grok Build scope only

## Notes

<!-- Optional: migration, follow-ups -->