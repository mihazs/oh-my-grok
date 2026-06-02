# Skills and slash commands

oh-my-grok bundles user-invocable skills under `skills/`. Grok discovers them via `grok inspect`.

| Skill | Slash / trigger | Purpose |
|-------|-----------------|--------|
| `agent-skill-gate` | (meta) | Read before mutating tools; hooks block writes until a catalog skill was Read |
| `ralph-loop` | `/ralph-loop "task"` | Work-until-done via Stop-hook continuations |
| `ulw-loop` | `/ulw-loop`, `/ultrawork` | Ralph loop + mandatory verifier before exit |
| `cancel-ralph` | `/cancel-ralph` | Clear active Ralph / ultrawork state |
| `handoff` | `/handoff` | Structured HANDOFF CONTEXT for a new session |

## Related prompts (hooks, not separate skills)

| Prompt | Effect |
|--------|--------|
| `/stop-continuation` | Pause auto-continue; clears loop + boulder |
| `/resume-continuation` | Resume auto-continue |

## Custom skills in your project

Add project skills under `.agents/skills/<name>/SKILL.md` or `.grok/skills/<name>/SKILL.md`. The skill gate uses the full `grok inspect` catalog — oh-my-grok skills are not hardcoded.

When delegating subagents, paste skill **paths** from inspect into the subagent prompt (Grok has no `load_skills` API).

## Source files

- `skills/agent-skill-gate/SKILL.md`
- `skills/ralph-loop/SKILL.md`
- `skills/ulw-loop/SKILL.md`
- `skills/cancel-ralph/SKILL.md`
- `skills/handoff/SKILL.md`

Bundled rules in `rules/*.md` are injected on every `UserPromptSubmit` together with workspace `AGENTS.md` when present.