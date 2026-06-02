---
name: ralph-loop
description: >
  Start a Ralph Loop — autonomous work-until-done via Stop-hook continuations.
  Use when the user says ralph loop, /ralph-loop, or wants the agent to keep going
  until it emits a completion promise tag. Pair with cancel-ralph to stop.
user_invocable: true
---

# Ralph Loop

## Start

User runs:

```text
/ralph-loop "your task description" [--completion-promise=DONE] [--max-iterations=100] [--strategy=continue|reset]
```

Or invoke this skill and state the task in the same message.

## Behavior (Grok hooks)

1. `UserPromptSubmit` writes `.omg/ralph-loop.local.md` in the workspace and injects loop instructions.
2. You work until the task is **fully** complete.
3. When done, output: `<promise>DONE</promise>` (or your custom `--completion-promise` text).
4. If you stop without that tag, the **Stop** hook blocks exit and injects a continuation prompt (up to `max-iterations`, default 100).
5. Pending todos can still block stop when no Ralph loop is active (`stop-verify-pending`).

## Rules

- Do not emit the completion promise early.
- Use todos for multi-step work.
- Each iteration must make real progress.

## Ultrawork variant

For verified completion (Oracle subagent required), use **`ulw-loop`** instead:

```text
/ulw-loop "same task" [--max-iterations=500]
```

See the oh-my-grok `ulw-loop` skill (`grok inspect` for path).

## Cancel

```text
/cancel-ralph
```

Or use the `cancel-ralph` skill. Also cancels an active ultrawork loop.

## State file

Workspace-relative: `.omg/ralph-loop.local.md` (oh-my-grok; omo uses `.omo/`).