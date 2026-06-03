package stoppending

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/mihazs/oh-my-grok/internal/hookenv"
)

const maxBlocks = 8

func findSessionDir(grokHome, sessionID string) string {
	root := filepath.Join(grokHome, "sessions")
	entries, err := os.ReadDir(root)
	if err != nil {
		return ""
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		candidate := filepath.Join(root, e.Name(), sessionID)
		if _, err := os.Stat(filepath.Join(candidate, "resources_state.json")); err == nil {
			return candidate
		}
	}
	return ""
}

func pendingPlanCheckboxes(sessionDir, workspace string) []string {
	uncheckedPat := regexp.MustCompile(`^\s*-\s*\[\s*\]\s+(.+)$`)
	var candidates []string
	if workspace != "" {
		candidates = append(candidates, filepath.Join(workspace, "plan.md"))
	}
	if sessionDir != "" {
		candidates = append(candidates, filepath.Join(sessionDir, "plan.md"))
	}
	for _, plan := range candidates {
		b, err := os.ReadFile(plan)
		if err != nil {
			continue
		}
		var items []string
		for _, line := range strings.Split(string(b), "\n") {
			if m := uncheckedPat.FindStringSubmatch(line); m != nil {
				item := strings.TrimSpace(m[1])
				if len(item) > 120 {
					item = item[:120]
				}
				items = append(items, item)
			}
		}
		if len(items) > 0 {
			return items
		}
	}
	return nil
}

func shouldAllow(ev hookenv.Event) bool {
	sr := strings.ToLower(strings.TrimSpace(ev.StopReason))
	if sr != "" && sr != "end_turn" && sr != "endturn" {
		return true
	}
	if ev.StopHookActive {
		return true
	}
	active := map[string]struct{}{
		"running": {}, "pending": {}, "in_progress": {}, "in-progress": {}, "active": {},
	}
	for _, t := range ev.BackgroundTasks {
		st, _ := t["status"].(string)
		if _, ok := active[strings.ToLower(st)]; ok {
			return true
		}
	}
	return false
}

// EvaluateStop blocks when plan.md has unchecked items (stop-verify pending work).
func EvaluateStop(ev hookenv.Event) (bool, string) {
	if shouldAllow(ev) {
		return false, ""
	}
	sid := ev.SessionID
	if sid == "" {
		return false, ""
	}
	grokHome := hookenv.GrokHome()
	stateDir := filepath.Join(grokHome, "state", "stop-verify", sid)
	_ = os.MkdirAll(stateDir, 0o755)
	blocksFile := filepath.Join(stateDir, "blocks.json")
	blocks := 0
	if b, err := os.ReadFile(blocksFile); err == nil {
		var data struct {
			Count int `json:"count"`
		}
		_ = json.Unmarshal(b, &data)
		blocks = data.Count
	}
	if blocks >= maxBlocks {
		return false, ""
	}
	ws := ev.WorkspaceRoot
	if ws == "" {
		ws = os.Getenv("GROK_WORKSPACE_ROOT")
	}
	sessionDir := findSessionDir(grokHome, sid)
	planItems := pendingPlanCheckboxes(sessionDir, ws)
	if len(planItems) == 0 {
		return false, ""
	}
	blocks++
	_ = os.WriteFile(blocksFile, mustJSON(map[string]int{"count": blocks}), 0o644)
	sample := strings.Join(planItems[:min(5, len(planItems))], "; ")
	extra := ""
	if len(planItems) > 5 {
		extra = " (+" + itoa(len(planItems)-5) + " more)"
	}
	msg := "Stop hook: unfinished work detected. Continue until complete, then summarize. " +
		"plan.md has " + itoa(len(planItems)) + " unchecked step(s): " + sample + extra
	if blocks >= maxBlocks {
		msg += " (block " + itoa(blocks) + "/" + itoa(maxBlocks) + "; this is the final allowed block)"
	}
	return true, strings.TrimSpace(msg)
}

func mustJSON(v any) []byte {
	b, _ := json.MarshalIndent(v, "", "  ")
	return append(b, '\n')
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var d []byte
	neg := n < 0
	if neg {
		n = -n
	}
	for n > 0 {
		d = append([]byte{byte('0' + n%10)}, d...)
		n /= 10
	}
	if neg {
		return "-" + string(d)
	}
	return string(d)
}