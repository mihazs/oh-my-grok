package handoff

import (
	"regexp"
	"strings"
	"time"

	"github.com/mihazs/oh-my-grok/internal/hookenv"
	"github.com/mihazs/oh-my-grok/internal/skillgate"
)

var handoffRE = regexp.MustCompile(`(?i)^/?handoff(?:\s|$)`)

func injectTemplate(sessionID string) string {
	ts := time.Now().UTC().Format(time.RFC3339)
	return strings.TrimSpace(`<HANDOFF_COMMAND>
The user invoked **/handoff** (oh-my-openagent handoff port).

**Read the handoff skill now** if you have not already, then follow it exactly (PHASE 0 → 4).

<session-context>
Session ID: ` + sessionID + `
Timestamp: ` + ts + `
</session-context>

## EXECUTE NOW

PHASE 0: Validate there is meaningful context to hand off.
PHASE 1: Gather todos, .omg/ state, git status/diff, AGENTS.md.
PHASE 2–3: Emit the HANDOFF CONTEXT block (verbatim user requests; max 10 key files).
Save copy to .omg/handoffs/handoff-<timestamp>.md
PHASE 4: Tell the user how to paste into a **new Grok session**.

Do not start unrelated work until the handoff is delivered.
</HANDOFF_COMMAND>`)
}

// Collect returns handoff command context when prompt matches /handoff.
func Collect(ev hookenv.Event) string {
	prompt := strings.TrimSpace(ev.Prompt)
	if prompt == "" || !handoffRE.MatchString(prompt) {
		return ""
	}
	sid := ev.SessionID
	if sid == "" {
		sid = "unknown"
	}
	_ = skillgate.MarkSkillLoaded(sid, "handoff")
	return injectTemplate(sid)
}