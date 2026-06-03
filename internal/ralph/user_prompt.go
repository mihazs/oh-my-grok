package ralph

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/mihazs/oh-my-grok/internal/hookenv"
	"github.com/mihazs/oh-my-grok/internal/skillgate"
)

var cancelRE = regexp.MustCompile(`(?i)^/?cancel-ralph\b`)

// CollectUserPrompt handles ralph/ultrawork slash commands on UserPromptSubmit.
func CollectUserPrompt(ev hookenv.Event) string {
	ws := ev.WorkspaceRoot
	if ws == "" {
		return ""
	}
	prompt := strings.TrimSpace(ev.Prompt)
	if prompt == "" {
		return ""
	}
	path := StatePath(ws)
	sid := ev.SessionID

	if cancelRE.MatchString(prompt) {
		clearState(path)
		return "<RALPH_LOOP>Canceled active loop (ralph or ultrawork). Cleared " + stateRelPath + ".</RALPH_LOOP>"
	}

	args := parseLoopArgs(prompt)
	if args == nil || args.Task == "" {
		if matchedLoopCommand(prompt) {
			return `<RALPH_LOOP>Provide a task. Examples:
/ralph-loop "fix bug"
/ulw-loop "fix bug" --max-iterations=200
ultrawork refactor auth module</RALPH_LOOP>`
		}
		return ""
	}

	st := &state{
		Active:                   true,
		Iteration:                1,
		MaxIterations:            args.MaxIterations,
		CompletionPromise:        args.CompletionPromise,
		InitialCompletionPromise: args.CompletionPromise,
		SessionID:                sid,
		Strategy:                 args.Strategy,
		StartedAt:                time.Now().UTC().Format(time.RFC3339),
		Prompt:                   args.Task,
		Ultrawork:                args.Ultrawork,
	}
	if err := writeState(path, st); err != nil {
		return ""
	}
	if args.Ultrawork {
		_ = skillgate.MarkSkillLoaded(sid, "ulw-loop")
	} else {
		_ = skillgate.MarkSkillLoaded(sid, "ralph-loop")
	}
	tmpl := ralphLoopTemplate(st.MaxIterations, st.CompletionPromise)
	if args.Ultrawork {
		tmpl = ulwLoopTemplate(st.MaxIterations, st.CompletionPromise, oracleSubagent())
	}
	return strings.TrimSpace(tmpl + "\n" + args.Task)
}

type loopArgs struct {
	Task               string
	CompletionPromise  string
	MaxIterations      int
	Strategy           string
	Ultrawork          bool
}

func matchedLoopCommand(prompt string) bool {
	re := regexp.MustCompile(`(?i)^/?(?:ralph-loop|ulw-loop|ultrawork)\b`)
	return re.MatchString(prompt)
}

func parseLoopArgs(text string) *loopArgs {
	text = strings.TrimSpace(text)
	ultrawork := false
	rest := ""

	m := regexp.MustCompile(`(?is)^/?(?:ralph-loop)(?:\s+|$)(.*)$`).FindStringSubmatch(text)
	if m != nil {
		rest = strings.TrimSpace(m[1])
	} else {
		m2 := regexp.MustCompile(`(?is)^/?(?:ulw-loop|ultrawork)(?:\s+|$)(.*)$`).FindStringSubmatch(text)
		if m2 != nil {
			ultrawork = true
			rest = strings.TrimSpace(m2[1])
		} else {
			m3 := regexp.MustCompile(`(?is)^ultrawork\s+(.+)$`).FindStringSubmatch(text)
			if m3 == nil {
				return nil
			}
			ultrawork = true
			rest = strings.TrimSpace(m3[1])
		}
	}

	cp := os.Getenv("RALPH_DEFAULT_COMPLETION_PROMISE")
	if cp == "" {
		cp = "DONE"
	}
	maxIt := defaultMaxIterations(ultrawork)
	strategy := "continue"

	cpRE := regexp.MustCompile(`(?i)--completion-promise=(\S+)`)
	maxRE := regexp.MustCompile(`(?i)--max-iterations=(\d+)`)
	stratRE := regexp.MustCompile(`(?i)--strategy=(reset|continue)`)
	if fm := cpRE.FindStringSubmatch(rest); len(fm) > 1 {
		cp = fm[1]
		rest = cpRE.ReplaceAllString(rest, "")
	}
	if fm := maxRE.FindStringSubmatch(rest); len(fm) > 1 {
		if n, err := strconv.Atoi(fm[1]); err == nil {
			maxIt = n
		}
		rest = maxRE.ReplaceAllString(rest, "")
	}
	if fm := stratRE.FindStringSubmatch(rest); len(fm) > 1 {
		strategy = strings.ToLower(fm[1])
		rest = stratRE.ReplaceAllString(rest, "")
	}
	rest = strings.TrimSpace(rest)

	task := rest
	if len(rest) > 0 && (rest[0] == '"' || rest[0] == '\'') {
		q := rest[0]
		if end := strings.Index(rest[1:], string(q)); end >= 0 {
			task = rest[1 : 1+end]
		} else {
			task = strings.Trim(rest, string(q))
		}
	}

	return &loopArgs{
		Task:              task,
		CompletionPromise: cp,
		MaxIterations:     maxIt,
		Strategy:          strategy,
		Ultrawork:         ultrawork,
	}
}

func ralphLoopTemplate(maxIt int, promise string) string {
	return fmt.Sprintf(`You are in a **Ralph Loop** — a self-referential development loop that runs until the task is complete.

## How it works

1. Work on the task continuously until it is **fully** done.
2. When complete, output exactly: <promise>%s</promise>
3. If you stop without that tag, the Stop hook injects a continuation prompt.
4. Maximum iterations: %d.

## Rules

- Finish the whole task, not a partial slice.
- Do not emit the completion promise until the work is truly complete.
- Use todos to track multi-step work.

## Cancel

/cancel-ralph

## Your task

`, promise, maxIt)
}

func ulwLoopTemplate(maxIt int, promise, oracle string) string {
	verified := ulwVerificationPromise()
	return fmt.Sprintf(`You are in an **ULTRAWORK Loop** — Ralph loop with mandatory verification before exit.

## How it works

1. Work continuously until the task is **fully** complete.
2. When done, output: <promise>%s</promise> — this does **not** end the loop.
3. The Stop hook will require **Oracle verification** via task(subagent_type="%s", ...).
4. The loop ends only after verification emits <promise>%s</promise> (Agent: oracle in the verification report).
5. Maximum iterations: %d.

## Rules

- Do not treat <promise>%s</promise> as final completion until Oracle verifies.
- After emitting DONE, run the verification subagent when the hook instructs you.
- Ask Oracle to review skeptically; include the original task and evidence of what changed.
- Use todos for multi-step work.

## Cancel

/cancel-ralph

## Your task

`, promise, oracle, verified, maxIt, promise)
}