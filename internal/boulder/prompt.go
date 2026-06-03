package boulder

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/mihazs/oh-my-grok/internal/hookenv"
	"github.com/mihazs/oh-my-grok/internal/ralph"
)

var (
	stopContRE    = regexp.MustCompile(`(?i)^/?stop-continuation\b`)
	resumeContRE  = regexp.MustCompile(`(?i)^/?resume-continuation\b`)
)

func markerPath(workspace, sessionID string) string {
	return filepath.Join(workspace, continuationMarkerDir, sessionID+".json")
}

// SetContinuationStopped marks auto-continue paused for this session.
func SetContinuationStopped(workspace, sessionID string) {
	if sessionID == "" {
		return
	}
	dir := filepath.Join(hookenv.GrokHome(), "state", "stop-continuation", sessionID)
	_ = os.MkdirAll(dir, 0o755)
	_ = os.WriteFile(filepath.Join(dir, "stopped"), []byte(nowISO()+"\n"), 0o644)
	if workspace == "" {
		return
	}
	mp := markerPath(workspace, sessionID)
	_ = os.MkdirAll(filepath.Dir(mp), 0o755)
	existing := map[string]any{}
	if b, err := os.ReadFile(mp); err == nil {
		_ = json.Unmarshal(b, &existing)
	}
	sources, _ := existing["sources"].(map[string]any)
	if sources == nil {
		sources = map[string]any{}
	}
	sources["stop"] = map[string]any{
		"state":     "stopped",
		"reason":    "Continuation stopped via /stop-continuation",
		"updatedAt": nowISO(),
	}
	existing["sessionID"] = sessionID
	existing["updatedAt"] = nowISO()
	existing["sources"] = sources
	b, _ := json.MarshalIndent(existing, "", "  ")
	_ = os.WriteFile(mp, append(b, '\n'), 0o644)
}

// ClearContinuationStopped resumes auto-continue.
func ClearContinuationStopped(workspace, sessionID string) {
	flag := filepath.Join(hookenv.GrokHome(), "state", "stop-continuation", sessionID, "stopped")
	_ = os.Remove(flag)
	if workspace == "" {
		return
	}
	mp := markerPath(workspace, sessionID)
	b, err := os.ReadFile(mp)
	if err != nil {
		return
	}
	var data map[string]any
	if json.Unmarshal(b, &data) != nil {
		return
	}
	sources, _ := data["sources"].(map[string]any)
	if sources == nil {
		return
	}
	sources["stop"] = map[string]any{"state": "idle", "updatedAt": nowISO()}
	data["sources"] = sources
	data["updatedAt"] = nowISO()
	out, _ := json.MarshalIndent(data, "", "  ")
	_ = os.WriteFile(mp, append(out, '\n'), 0o644)
}

// ClearBoulder removes .omg/boulder.json in workspace.
func ClearBoulder(workspace string) {
	if workspace == "" {
		return
	}
	_ = os.Remove(boulderPath(workspace))
}

// CollectStopContinuation handles /stop-continuation and /resume-continuation.
func CollectStopContinuation(ev hookenv.Event) string {
	prompt := strings.TrimSpace(ev.Prompt)
	if prompt == "" {
		return ""
	}
	ws := ev.WorkspaceRoot
	sid := ev.SessionID

	if stopContRE.MatchString(prompt) {
		SetContinuationStopped(ws, sid)
		if ws != "" {
			ralph.ClearState(ralph.StatePath(ws))
		}
		ClearBoulder(ws)
		return "<STOP_CONTINUATION>Stopped: todo continuation, Ralph/ultrawork loop, and boulder.json cleared. Auto-continue resumes on SessionEnd or /resume-continuation.</STOP_CONTINUATION>"
	}
	if resumeContRE.MatchString(prompt) {
		ClearContinuationStopped(ws, sid)
		return "<STOP_CONTINUATION>Auto-continuation resumed for this session.</STOP_CONTINUATION>"
	}
	return ""
}

// CollectPromptContext returns active boulder state summary.
func CollectPromptContext(workspace, sessionID string) string {
	return BuildBoulderContext(workspace, sessionID)
}

// BuildBoulderContext mirrors omo_state build_boulder_context.
func BuildBoulderContext(workspace, sessionID string) string {
	state := readBoulder(workspace)
	if state == nil {
		return ""
	}
	work := getWorkForSession(state, sessionID)
	ids := stringSlice(state["session_ids"])
	if work == nil && !containsStr(ids, sessionID) {
		return ""
	}
	subject := state
	if work != nil {
		subject = work
	}
	status, _ := subject["status"].(string)
	if status == "paused" || status == "abandoned" {
		return ""
	}
	planPath := resolvePlanPath(workspace, state, work)
	planName, _ := subject["plan_name"].(string)
	if planName == "" {
		planName = "plan"
	}
	progress := getPlanProgress(planPath)
	remaining := progress.Total - progress.Completed
	activePlan, _ := subject["active_plan"].(string)
	if activePlan == "" {
		if ap, ok := state["active_plan"].(string); ok {
			activePlan = ap
		}
	}
	var lines []string
	lines = append(lines,
		"<BOULDER_STATE>",
		"Active plan: "+planName,
		"Plan file: "+activePlan,
		fmt.Sprintf("Progress: %d/%d tasks", progress.Completed, progress.Total),
		"Status: "+orDefault(status, "active"),
	)
	if wt, ok := subject["worktree_path"].(string); ok && wt != "" {
		lines = append(lines, "Worktree: "+wt)
	}
	if remaining > 0 {
		lines = append(lines, fmt.Sprintf("%d task(s) remaining — read the plan and continue.", remaining))
	}
	lines = append(lines, "</BOULDER_STATE>")
	return strings.Join(lines, "\n")
}

func orDefault(s, def string) string {
	if s == "" {
		return def
	}
	return s
}

// CleanupOMOSession clears continuation + nudge state on session-end.
func CleanupOMOSession(workspace, sessionID string) {
	if sessionID == "" {
		return
	}
	ClearContinuationStopped(workspace, sessionID)
	nudge := filepath.Join(hookenv.GrokHome(), "state", "boulder-nudge", sessionID)
	_ = os.RemoveAll(nudge)
}

