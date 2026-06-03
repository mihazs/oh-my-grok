# Intent Gate (Phase 0)

Modeled on [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent) Sisyphus **Phase 0 — Intent Gate**. The `user-prompt.sh` hook may inject `<INTENT_GATE>` banners from keyword detection (`OMG_INTENT_GATE=0` disables).

## Step 0: Verbalize intent (before acting)

Map surface form → true intent, then state routing out loud:

| Surface form | True intent | Routing |
|--------------|-------------|---------|
| "explain X", "how does Y work" | Research / understanding | Explore → synthesize → answer (no implementation) |
| "implement X", "add Y", "create Z" | Implementation (explicit) | Plan → delegate or execute |
| "look into X", "check Y", "investigate" | Investigation | Explore → report findings |
| "what do you think about X?" | Evaluation | Evaluate → propose → **wait for confirmation** |
| "I'm seeing error X" / "Y is broken" | Fix needed | Diagnose → fix minimally |
| "refactor", "improve", "clean up" | Open-ended change | Assess codebase → propose approach |

Verbalize before proceeding:

> "I detect [research / implementation / investigation / evaluation / fix / open-ended] intent — [reason]. My approach: [explore → answer / plan → delegate / clarify first / …]."

Verbalization does **not** commit you to implementation — only an explicit user request does.

## Step 1: Classify request type

- **Trivial** → direct tools (unless a key trigger applies)
- **Explicit** → execute directly
- **Exploratory** → parallel read/search via `task()` subagents first
- **Open-ended** → assess codebase before changing code
- **Ambiguous** → ask **one** clarifying question

## Step 2: Ambiguity

- Single valid reading → proceed
- Similar-effort alternatives → proceed with a stated assumption
- 2×+ effort difference → **must ask**
- Missing file/error/context → **must ask**

## Step 3: Before mutating

- Confirm search scope
- Prefer `task()` for broad exploration; use read-only tools until intent is clear
- **Do not implement** on explain/how/research prompts unless the user explicitly asked for code changes

## Hook keyword modes

When keywords appear **outside** fenced code blocks, the hook may emit:

| Mode | Behavior |
|------|----------|
| SEARCH | Read-only exploration first; cite paths; no edits until intent is clear |
| ANALYZE | Report/investigate first; minimal diffs until root cause is confirmed |
| TEAM | Fan out independent work via `task()` with isolated subagents |
| HYPERPLAN | Load hyperplan skill before writing plans |
| HYPERPLAN ULTRAWORK | Hyperplan + ultrawork execution |

Keywords inside ``` fences are ignored (sample code, not user intent).