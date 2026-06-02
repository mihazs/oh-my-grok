# Ralph + Ultrawork Loops (Grok)

Modeled on [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent) `ralph-loop` and `ulw-loop`.

## Commands

| Command | Effect |
|---------|--------|
| `/ralph-loop "task" [--max-iterations=100]` | Work-until-done; exit on `<promise>DONE</promise>` |
| `/ulw-loop` / `/ultrawork` / `ultrawork <task>` | Same + mandatory verifier; exit on `<promise>VERIFIED</promise>` |
| `/cancel-ralph` | Clear `.omg/ralph-loop.local.md` |

## Ultrawork verification

After `<promise>DONE</promise>`, run `task(subagent_type="code-reviewer", ...)` (override via `RALPH_ORACLE_SUBAGENT`). Verifier output must include `Agent: oracle` and `<promise>VERIFIED</promise>`.

## Hooks

- `user-prompt.sh` — start/cancel (merged UserPromptSubmit)
- `stop-hook.sh` — continuation chain (`lib/stop-chain.sh`; Ralph first)

Skills: `ralph-loop`, `ulw-loop`, `cancel-ralph` (oh-my-grok plugin; see `grok inspect`).