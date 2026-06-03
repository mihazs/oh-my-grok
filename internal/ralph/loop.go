package ralph

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/mihazs/oh-my-grok/internal/hookenv"
)

const stateRelPath = ".omg/ralph-loop.local.md"

// StatePath returns the ralph loop state file for a workspace.
func StatePath(workspace string) string {
	return filepath.Join(workspace, stateRelPath)
}

type state struct {
	Active                   bool
	Iteration                int
	MaxIterations            int
	CompletionPromise        string
	InitialCompletionPromise string
	SessionID                string
	Strategy                 string
	StartedAt                string
	Prompt                   string
	Ultrawork                bool
	VerificationPending      bool
}

func defaultMaxIterations(ultrawork bool) int {
	if ultrawork {
		if v := os.Getenv("ULW_DEFAULT_MAX_ITERATIONS"); v != "" {
			if n, err := strconv.Atoi(v); err == nil {
				return n
			}
		}
		return 500
	}
	if v := os.Getenv("RALPH_DEFAULT_MAX_ITERATIONS"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return 100
}

func oracleSubagent() string {
	if v := os.Getenv("RALPH_ORACLE_SUBAGENT"); v != "" {
		return v
	}
	return "code-reviewer"
}

func ulwVerificationPromise() string {
	if v := os.Getenv("ULW_VERIFICATION_PROMISE"); v != "" {
		return v
	}
	return "VERIFIED"
}

func parseFrontmatter(text string) (map[string]string, string) {
	if !strings.HasPrefix(text, "---\n") {
		return nil, text
	}
	end := strings.Index(text[4:], "\n---\n")
	if end < 0 {
		return nil, text
	}
	header := text[4 : 4+end]
	body := text[4+end+5:]
	data := make(map[string]string)
	for _, line := range strings.Split(header, "\n") {
		if !strings.Contains(line, ":") {
			continue
		}
		parts := strings.SplitN(line, ":", 2)
		key := strings.TrimSpace(parts[0])
		val := strings.TrimSpace(parts[1])
		val = strings.Trim(val, "\"'")
		data[key] = val
	}
	return data, body
}

func readState(path string) *state {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	fm, body := parseFrontmatter(string(b))
	active := fm["active"] == "true" || fm["active"] == "True"
	if !active {
		return nil
	}
	iter, _ := strconv.Atoi(fm["iteration"])
	ultrawork := fm["ultrawork"] == "true" || fm["ultrawork"] == "True"
	maxIt := defaultMaxIterations(ultrawork)
	if fm["max_iterations"] != "" {
		if n, err := strconv.Atoi(fm["max_iterations"]); err == nil {
			maxIt = n
		}
	}
	cp := fm["completion_promise"]
	if cp == "" {
		cp = "DONE"
	}
	icp := fm["initial_completion_promise"]
	if icp == "" {
		icp = cp
	}
	return &state{
		Active:                   true,
		Iteration:                iter,
		MaxIterations:            maxIt,
		CompletionPromise:        cp,
		InitialCompletionPromise: icp,
		SessionID:                fm["session_id"],
		Strategy:                 fm["strategy"],
		StartedAt:                fm["started_at"],
		Prompt:                   strings.TrimSpace(body),
		Ultrawork:                ultrawork,
		VerificationPending:      fm["verification_pending"] == "true" || fm["verification_pending"] == "True",
	}
}

func writeState(path string, st *state) error {
	_ = os.MkdirAll(filepath.Dir(path), 0o755)
	var lines []string
	lines = append(lines, "---",
		fmt.Sprintf("active: %t", st.Active),
		fmt.Sprintf("iteration: %d", st.Iteration),
		fmt.Sprintf("max_iterations: %d", st.MaxIterations),
		fmt.Sprintf(`completion_promise: "%s"`, st.CompletionPromise),
	)
	if st.InitialCompletionPromise != "" {
		lines = append(lines, fmt.Sprintf(`initial_completion_promise: "%s"`, st.InitialCompletionPromise))
	}
	if st.SessionID != "" {
		lines = append(lines, fmt.Sprintf(`session_id: "%s"`, st.SessionID))
	}
	if st.Strategy != "" {
		lines = append(lines, fmt.Sprintf(`strategy: "%s"`, st.Strategy))
	}
	lines = append(lines, fmt.Sprintf("ultrawork: %t", st.Ultrawork))
	lines = append(lines, fmt.Sprintf("verification_pending: %t", st.VerificationPending))
	if st.StartedAt != "" {
		lines = append(lines, fmt.Sprintf(`started_at: "%s"`, st.StartedAt))
	} else {
		lines = append(lines, fmt.Sprintf(`started_at: "%s"`, time.Now().UTC().Format(time.RFC3339)))
	}
	lines = append(lines, "---", strings.TrimSpace(st.Prompt), "")
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o644)
}

func clearState(path string) {
	_ = os.Remove(path)
}

// ClearState removes the ralph loop state file.
func ClearState(path string) {
	clearState(path)
}

func hasPromise(text, promise string) bool {
	if text == "" || promise == "" {
		return false
	}
	pat := regexp.MustCompile(`(?i)<promise>\s*` + regexp.QuoteMeta(promise) + `\s*</promise>`)
	return pat.MatchString(text)
}

func isOracleVerified(text string) bool {
	if text == "" {
		return false
	}
	agentRE := regexp.MustCompile(`(?im)^Agent:\s*(\S+)\s*$`)
	m := agentRE.FindStringSubmatch(text)
	if len(m) < 2 || strings.ToLower(m[1]) != "oracle" {
		return false
	}
	return hasPromise(text, ulwVerificationPromise())
}

func buildRalphContinuation(st *state) string {
	return fmt.Sprintf(
		"[RALPH LOOP %d/%d]\nContinue. Output <promise>%s</promise> when fully done.\n\nOriginal task:\n%s",
		st.Iteration, st.MaxIterations, st.CompletionPromise, st.Prompt,
	)
}

func buildULWVerification(st *state) string {
	oracle := oracleSubagent()
	initial := st.InitialCompletionPromise
	if initial == "" {
		initial = st.CompletionPromise
	}
	return fmt.Sprintf(
		"[ULTRAWORK LOOP VERIFICATION %d/%d]\n"+
			"You already emitted <promise>%s</promise>. That does NOT finish the loop.\n\n"+
			"REQUIRED NOW:\n"+
			"- Call task(subagent_type=\"%s\", load_skills=[], run_in_background=false, ...)\n"+
			"- Ask the verifier to confirm the original task is actually complete\n"+
			"- Tell them to review skeptically and look for gaps, regressions, or missing tests\n"+
			"- The verifier must end with: Agent: oracle\\n<promise>VERIFIED</promise>\n"+
			"- Do not claim final completion until you see <promise>VERIFIED</promise>\n\n"+
			"Original task:\n%s",
		st.Iteration, st.MaxIterations, initial, oracle, st.Prompt,
	)
}

func buildULWVerificationFailed(st *state) string {
	return fmt.Sprintf(
		"[ULTRAWORK LOOP VERIFICATION FAILED %d/%d]\n"+
			"Oracle did not emit <promise>VERIFIED</promise>. Fix remaining issues, then request verification again.\n"+
			"When ready for another review, output <promise>%s</promise> again.\n\nOriginal task:\n%s",
		st.Iteration, st.MaxIterations, st.CompletionPromise, st.Prompt,
	)
}

func buildContinuation(st *state) string {
	if st.VerificationPending {
		return buildULWVerificationFailed(st)
	}
	if st.Ultrawork {
		return fmt.Sprintf(
			"[ULTRAWORK LOOP %d/%d]\nContinue. Output <promise>%s</promise> when done (verification follows).\n\nOriginal task:\n%s",
			st.Iteration, st.MaxIterations, st.CompletionPromise, st.Prompt,
		)
	}
	return buildRalphContinuation(st)
}

func shouldAllowRalphStop(ev hookenv.Event) bool {
	sr := strings.ToLower(strings.TrimSpace(ev.StopReason))
	if sr != "" && sr != "end_turn" && sr != "endturn" {
		return true
	}
	active := map[string]struct{}{
		"running": {}, "pending": {}, "in_progress": {}, "active": {},
	}
	for _, t := range ev.BackgroundTasks {
		st, _ := t["status"].(string)
		if _, ok := active[strings.ToLower(st)]; ok {
			return true
		}
	}
	return false
}

// EvaluateStop implements ralph/ultrawork stop continuation (first in stop chain).
func EvaluateStop(ev hookenv.Event) (bool, string) {
	ws := ev.WorkspaceRoot
	if ws == "" {
		return false, ""
	}
	if shouldAllowRalphStop(ev) {
		return false, ""
	}
	path := StatePath(ws)
	st := readState(path)
	if st == nil {
		return false, ""
	}
	sid := ev.SessionID
	if st.SessionID != "" && sid != "" && st.SessionID != sid {
		return false, ""
	}
	lastMsg := ev.LastAssistantMessage

	if st.Ultrawork && st.VerificationPending {
		if isOracleVerified(lastMsg) {
			clearState(path)
			return false, ""
		}
		if hasPromise(lastMsg, st.CompletionPromise) {
			return true, buildULWVerification(st)
		}
		return true, buildULWVerificationFailed(st)
	}

	if st.Ultrawork && hasPromise(lastMsg, st.CompletionPromise) {
		st.VerificationPending = true
		if st.InitialCompletionPromise == "" {
			st.InitialCompletionPromise = st.CompletionPromise
		}
		_ = writeState(path, st)
		return true, buildULWVerification(st)
	}

	if !st.Ultrawork && hasPromise(lastMsg, st.CompletionPromise) {
		clearState(path)
		return false, ""
	}

	if st.Iteration >= st.MaxIterations {
		clearState(path)
		return false, ""
	}

	st.Iteration++
	_ = writeState(path, st)
	if st.Iteration > st.MaxIterations {
		clearState(path)
		return false, ""
	}
	return true, buildContinuation(st)
}

// WriteStateJSON writes state from JSON (tests / future user-prompt port).
func WriteStateJSON(workspace string, stateJSON []byte) error {
	var raw map[string]any
	if err := json.Unmarshal(stateJSON, &raw); err != nil {
		return err
	}
	st := &state{Active: true, Iteration: 1, CompletionPromise: "DONE", InitialCompletionPromise: "DONE"}
	if v, ok := raw["iteration"].(float64); ok {
		st.Iteration = int(v)
	}
	if v, ok := raw["max_iterations"].(float64); ok {
		st.MaxIterations = int(v)
	}
	if v, ok := raw["completion_promise"].(string); ok {
		st.CompletionPromise = v
		st.InitialCompletionPromise = v
	}
	if v, ok := raw["initial_completion_promise"].(string); ok {
		st.InitialCompletionPromise = v
	}
	if v, ok := raw["session_id"].(string); ok {
		st.SessionID = v
	}
	if v, ok := raw["prompt"].(string); ok {
		st.Prompt = v
	}
	if v, ok := raw["ultrawork"].(bool); ok {
		st.Ultrawork = v
		if st.MaxIterations == 0 {
			st.MaxIterations = defaultMaxIterations(v)
		}
	}
	if st.MaxIterations == 0 {
		st.MaxIterations = defaultMaxIterations(st.Ultrawork)
	}
	if v, ok := raw["started_at"].(string); ok {
		st.StartedAt = v
	}
	return writeState(StatePath(workspace), st)
}