---
name: cancel-ralph
description: >
  Cancel an active Ralph or Ultrawork loop. Use when the user says /cancel-ralph,
  cancel ralph, cancel ultrawork, or wants to stop the autonomous work-until-done loop.
user_invocable: true
---

# Cancel Ralph / Ultrawork Loop

Clears `.omg/ralph-loop.local.md` (covers both `ralph-loop` and `ulw-loop`) and stops Stop-hook continuations.

For todo + boulder auto-continue too, use `/stop-continuation` instead.

Tell the user to run:

```text
/cancel-ralph
```

Or send that command yourself if you are canceling on their behalf.