# Troubleshooting

## Hooks do not run after install

1. Confirm plugin is enabled: `grok plugin enable oh-my-grok`
2. Reload hooks (`Ctrl+L` → Hooks) or start a new session
3. Reinstall: `grok plugin install github:mihazs/oh-my-grok --trust`
4. Check for duplicate manifests in `~/.grok/hooks/*.json` — remove or run `scripts/remove-global-overlays.sh`

## Stale plugin copy

`grok plugin update` may not refresh a broken snapshot. Reinstall from path or GitHub:

```bash
grok plugin install /path/to/oh-my-grok --trust
# or
grok plugin install github:mihazs/oh-my-grok --trust
```

## Mutating tools blocked (skill gate)

Hooks deny `Write` / `StrReplace` / `Delete` until at least one catalog `SKILL.md` was `Read` this session.

- Run `grok inspect` and Read a skill whose description matches the task
- Or Read `agent-skill-gate` from the oh-my-grok plugin path in inspect

## Ralph / ultrawork loop will not stop

- Emit the completion promise tag required by the active loop (see `skills/ralph-loop/SKILL.md` or `skills/ulw-loop/SKILL.md`)
- Or run `/cancel-ralph`
- Or `/stop-continuation` to pause continuation (also clears loop + boulder)

## Boulder or todos out of sync

State lives under `.omg/` in the **workspace**, not `~/.grok/`. Check `.omg/boulder.json` and `.omg/todos/<session>.json`.

## Migrated from old `.grok/` workspace folders

Earlier builds used `.grok/` under the project for boulder/ralph state. Current releases use **`.omg/`**. Move any remaining files manually; do not commit `.omg/` to git.

## CI vs local

GitHub Actions runs hook smoke tests only. `grok plugin validate` and `hooks/test-inline-skill-gate.sh` require the Grok CLI locally.