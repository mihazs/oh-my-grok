package prometheus

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/mihazs/oh-my-grok/internal/hookenv"
)

var (
	planRE       = regexp.MustCompile(`(?i)^/?(?:plan|prometheus)\b`)
	startWorkRE  = regexp.MustCompile(`(?i)^/?start-work\b`)
	cancelPlanRE = regexp.MustCompile(`(?i)^/?cancel-plan\b`)
	startWorkArg = regexp.MustCompile(`(?is)^/?start-work(?:\s+(.+))?$`)
)

func planModeFlag(sessionID string) string {
	if sessionID == "" {
		sessionID = "unknown"
	}
	return filepath.Join(hookenv.GrokHome(), "state", "plan-mode", sessionID, "enabled")
}

func planModeOn(sessionID string) {
	f := planModeFlag(sessionID)
	_ = os.MkdirAll(filepath.Dir(f), 0o755)
	_ = os.WriteFile(f, []byte(time.Now().UTC().Format(time.RFC3339)+"\n"), 0o644)
}

func planModeOff(sessionID string) {
	_ = os.Remove(planModeFlag(sessionID))
}

const planModeBanner = "<PROMETHEUS_PLAN_MODE>\n" +
	"You are in planning mode. ONLY create or edit files under `.omg/` (plans, drafts).\n" +
	`Interview the user, then Task(subagent_type="metis-consultant") for gaps, write plan to ` + "`.omg/plans/<name>.md`" + `, optional Task(subagent_type="momus-reviewer").` + "\n" +
	"Implementation starts only after `/start-work <plan-file>`.\n" +
	"</PROMETHEUS_PLAN_MODE>"

// CollectUserPrompt handles /plan, /start-work, /cancel-plan on UserPromptSubmit.
func CollectUserPrompt(ev hookenv.Event) string {
	prompt := strings.TrimSpace(ev.Prompt)
	if prompt == "" {
		return ""
	}
	sid := ev.SessionID
	ws := ev.WorkspaceRoot

	if planRE.MatchString(prompt) {
		planModeOn(sid)
		return planModeBanner
	}
	if startWorkRE.MatchString(prompt) {
		return handleStartWork(ws, sid, prompt)
	}
	if cancelPlanRE.MatchString(prompt) {
		planModeOff(sid)
		return "<PROMETHEUS_PLAN_MODE>Plan mode cancelled.</PROMETHEUS_PLAN_MODE>"
	}
	return ""
}

func handleStartWork(workspace, sessionID, prompt string) string {
	planModeOff(sessionID)
	if workspace == "" || sessionID == "" {
		return "<PROMETHEUS_PLAN_MODE>Start-work failed: missing workspace or session.</PROMETHEUS_PLAN_MODE>"
	}
	m := startWorkArg.FindStringSubmatch(strings.TrimSpace(prompt))
	raw := ""
	if len(m) > 1 {
		raw = strings.Trim(strings.TrimSpace(m[1]), "\"'")
	}
	if raw == "" {
		return "<PROMETHEUS_PLAN_MODE>Start-work failed: provide plan path, e.g. /start-work .omg/plans/auth.md</PROMETHEUS_PLAN_MODE>"
	}

	base := workspace
	planPath := raw
	if !filepath.IsAbs(planPath) {
		planPath = filepath.Join(base, raw)
	}
	if _, err := os.Stat(planPath); err != nil {
		alt := filepath.Join(base, ".omg", "plans", filepath.Base(raw))
		if _, err2 := os.Stat(alt); err2 == nil {
			planPath = alt
		} else {
			return "<PROMETHEUS_PLAN_MODE>Start-work failed: plan not found: " + raw + "</PROMETHEUS_PLAN_MODE>"
		}
	}

	absBase, _ := filepath.Abs(base)
	absPlan, _ := filepath.Abs(planPath)
	rel, err := filepath.Rel(absBase, absPlan)
	activePlan := rel
	if err != nil {
		activePlan = planPath
	}
	activePlan = strings.ReplaceAll(activePlan, "\\", "/")
	if !strings.HasPrefix(activePlan, ".omg/") || !strings.HasSuffix(activePlan, ".md") {
		return "<PROMETHEUS_PLAN_MODE>Start-work failed: plan must be under .omg/ and end with .md</PROMETHEUS_PLAN_MODE>"
	}

	planName := strings.TrimSuffix(filepath.Base(activePlan), filepath.Ext(activePlan))
	workID := planName + "-work"
	now := time.Now().UTC().Format("2006-01-02T15:04:05+00:00")

	state := map[string]any{
		"schema_version": 2,
		"active_work_id": workID,
		"active_plan":    activePlan,
		"plan_name":      planName,
		"status":         "active",
		"started_at":     now,
		"updated_at":     now,
		"session_ids":    []any{sessionID},
		"works": map[string]any{
			workID: map[string]any{
				"work_id":        workID,
				"active_plan":    activePlan,
				"plan_name":      planName,
				"status":         "active",
				"started_at":     now,
				"updated_at":     now,
				"session_ids":    []any{sessionID},
				"task_sessions":  map[string]any{},
			},
		},
	}
	boulderFile := filepath.Join(base, ".omg", "boulder.json")
	_ = os.MkdirAll(filepath.Dir(boulderFile), 0o755)
	b, _ := json.MarshalIndent(state, "", "  ")
	_ = os.WriteFile(boulderFile, append(b, '\n'), 0o644)

	return "<PROMETHEUS_PLAN_MODE>Start-work: boulder.json activated. Execute the plan.</PROMETHEUS_PLAN_MODE>"
}