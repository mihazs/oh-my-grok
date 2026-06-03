package intentgate

import (
	"regexp"
	"strings"

	"github.com/mihazs/oh-my-grok/internal/config"
	"github.com/mihazs/oh-my-grok/internal/hookenv"
)

var (
	searchRE    = regexp.MustCompile(`(?i)\b(search|find|locate|lookup|explore|discover|scan|grep|query)\b|where\s+is|show\s+me`)
	analyzeRE   = regexp.MustCompile(`(?i)\b(analyze|analyse|investigate|audit|review|assess|evaluate|diagnose|debug|root\s+cause)\b`)
	teamRE      = regexp.MustCompile(`(?i)\b(team\s+mode|team\s+up|parallel\s+agents?)\b`)
	hyperplanRE = regexp.MustCompile(`(?i)\b(hpp|hyperplan)\b`)
	hyperULWRE  = regexp.MustCompile(`(?i)\b(?:hpp|hyperplan)\s+(?:ulw|ultrawork)\b|\b(?:ulw|ultrawork)\s+(?:hpp|hyperplan)\b`)
	ralphSkipRE = regexp.MustCompile(`(?i)^/?(ralph-loop|ulw-loop|cancel-ralph)\b`)
	fenceRE     = regexp.MustCompile("(?s)```[\\s\\S]*?```")
	inlineRE    = regexp.MustCompile("`[^`]+`")
)

type mode struct {
	tag string
	msg string
}

// Collect returns intent-gate context for the user prompt or "".
func Collect(ev hookenv.Event) string {
	if !config.IntentGateEnabled() {
		return ""
	}
	prompt := strings.TrimSpace(ev.Prompt)
	if prompt == "" {
		return ""
	}
	if ralphSkipRE.MatchString(prompt) {
		return ""
	}
	return detect(prompt)
}

func stripCode(text string) string {
	text = fenceRE.ReplaceAllString(text, "")
	text = inlineRE.ReplaceAllString(text, "")
	return text
}

func detect(text string) string {
	text = stripCode(text)
	var modes []mode
	if hyperULWRE.MatchString(text) {
		modes = append(modes, mode{"hyperplan-ultrawork", "HYPERPLAN ULTRAWORK MODE: load hyperplan skill; apply ultrawork execution."})
	} else if hyperplanRE.MatchString(text) {
		modes = append(modes, mode{"hyperplan", "HYPERPLAN MODE: adversarial planning — load hyperplan skill before writing plans."})
	}
	if searchRE.MatchString(text) {
		modes = append(modes, mode{"search", "SEARCH MODE: read-only exploration first; cite file paths; do not mutate until intent is clear."})
	}
	if analyzeRE.MatchString(text) {
		modes = append(modes, mode{"analyze", "ANALYZE MODE: investigation/report first; minimal diffs until root cause is confirmed."})
	}
	if teamRE.MatchString(text) {
		modes = append(modes, mode{"team", "TEAM MODE: fan out independent work via Task tool with isolated subagents."})
	}
	if len(modes) == 0 {
		return ""
	}
	var lines []string
	lines = append(lines, "<INTENT_GATE>", "Classified intent from this message (turn-local; not conversation momentum):")
	for _, m := range modes {
		lines = append(lines, "- "+m.msg)
	}
	lines = append(lines, "</INTENT_GATE>")
	return strings.Join(lines, "\n")
}