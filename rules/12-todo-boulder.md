# Todo + Boulder tracking (Grok / omo)

## Todo continuation

Stop hook blocks with omo-style `[TODO CONTINUATION]` when `TodoWrite` todos are pending/in_progress.

- Mirror: `.omg/todos/<sessionId>.json` (updated on each `TodoWrite`)
- Pause: `/stop-continuation`
- Resume: `/resume-continuation`

## Boulder (`boulder.json`)

Active work tracked at `.omg/boulder.json` (schema v2, omo-compatible fields).

- Plans: `.omg/plans/*.md` (structured `## TODOs` / `## Final Verification Wave` checkboxes)
- Stop hook: `[BOULDER CONTINUATION]` while plan incomplete; `BOULDER COMPLETE` nudge when all checked
- Context injected each prompt when a session is registered in boulder state
- `/stop-continuation` also clears boulder + Ralph loop

## Stop hook order

See oh-my-grok `hooks/README.md`. Chain in `stop-hook.sh`:

1. Ralph / ultrawork  
2. Boulder plan (skipped when `/stop-continuation`)  
3. Todo list  
4. Root `plan.md` checkboxes (fallback)