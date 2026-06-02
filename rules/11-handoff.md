# Handoff (Grok / oh-my-grok)

Ported from [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent) `/handoff`.

## Trigger

`/handoff` or the **handoff** plugin skill.

## Behavior

- UserPromptSubmit injects execution instructions when the prompt matches `/handoff`
- Agent runs PHASE 0–4 from the handoff skill and emits **HANDOFF CONTEXT**
- Optional artifact: `.omg/handoffs/handoff-<timestamp>.md`

## Gather

- Verbatim user requests from the session
- Todos + `.omg/` state (boulder, plans, ralph-loop, todo mirror)
- `git status` / `git diff --stat` in git repos
- `AGENTS.md` constraints (verbatim only)