---
name: ulw-loop
description: >
  Start an ULTRAWORK loop — Ralph loop plus mandatory Oracle verification before exit.
  Use for /ulw-loop, /ultrawork, or "ultrawork <task>". Ends only after
  <promise>VERIFIED</promise> from the verifier subagent. Cancel with /cancel-ralph.
user_invocable: true
---

# ULTRAWORK Loop

## Start

```text
/ulw-loop "task description" [--completion-promise=DONE] [--max-iterations=500]
/ultrawork "task description"
ultrawork refactor the payment module
```

Default max iterations: **500** (vs 100 for `/ralph-loop`).

## Flow

1. Work until fully done → output `<promise>DONE</promise>` (not final).
2. Stop hook enters **verification** — you must run a verifier subagent (default: `code-reviewer`).
3. Verifier must end with:
   ```text
   Agent: oracle
   <promise>VERIFIED</promise>
   ```
4. Only then does the loop clear and the session may stop.

## If verification fails

Fix issues, emit `<promise>DONE</promise>` again, and re-run verification.

## Cancel

`/cancel-ralph` (same as Ralph loop — one state file).

## State

`.omg/ralph-loop.local.md` with `ultrawork: true` and `verification_pending` when awaiting verification.