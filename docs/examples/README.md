# Examples

## Ralph loop — work until done

```text
/ralph-loop "fix all failing hook tests and update hooks/README if stop order changes"
```

The hook writes `.omg/ralph-loop.local.md`. If you try to stop without the completion promise, the Stop hook injects a continuation prompt (up to `max-iterations`, default 100).

Cancel: `/cancel-ralph`

## Ultrawork — Ralph + verification

```text
/ulw-loop "implement docs/ and README discoverability overhaul"
ultrawork add GitHub issue templates
```

Same loop file as Ralph, but Stop requires a verifier subagent to emit `<promise>VERIFIED</promise>` before the loop clears. Default max iterations: 500.

## Handoff — continue in a new session

```text
/handoff
```

Produces a structured HANDOFF CONTEXT block and saves a copy under `.omg/handoffs/handoff-<timestamp>.md`. In the next session:

```text
Continue from handoff .omg/handoffs/handoff-YYYYMMDD-HHMMSS.md
```

## Boulder + todos

When boulder state is active (`.omg/boulder.json`), prompts include plan progress and Stop may block until plan/todo work advances. `TodoWrite` is mirrored to `.omg/todos/<session>.json`.

Pause auto-continue without deleting workspace state: `/stop-continuation`  
Resume: `/resume-continuation`