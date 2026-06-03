package prometheus

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/mihazs/oh-my-grok/internal/config"
	"github.com/mihazs/oh-my-grok/internal/hookenv"
)

// PlanModeActive reports whether Prometheus plan mode is enabled.
func PlanModeActive(sessionID string) bool {
	if config.PlanModeForced() {
		return true
	}
	if sessionID == "" {
		sessionID = "unknown"
	}
	flag := filepath.Join(hookenv.GrokHome(), "state", "plan-mode", sessionID, "enabled")
	_, err := os.Stat(flag)
	return err == nil
}

var blockedTools = map[string]struct{}{
	"write": {}, "strreplace": {}, "editnotebook": {}, "delete": {},
}

// DenyIfPlanMode returns a deny reason when plan mode blocks the mutation, or "" to allow.
func DenyIfPlanMode(ev hookenv.Event) string {
	if !PlanModeActive(ev.SessionID) {
		return ""
	}
	tool := strings.ToLower(strings.TrimSpace(ev.ToolName))
	if _, blocked := blockedTools[tool]; !blocked {
		return ""
	}
	path := pickPath(ev.ToolInput)
	if path == "" {
		return ""
	}
	rel := normalizeRelPath(path, ev.WorkspaceRoot)
	if strings.HasPrefix(rel, ".omg/") && strings.HasSuffix(rel, ".md") {
		return ""
	}
	return "Prometheus plan mode: only .omg/**/*.md writes allowed; blocked: " + path
}

func pickPath(block map[string]any) string {
	if block == nil {
		return ""
	}
	for _, k := range []string{"path", "file_path", "filePath"} {
		if v, ok := block[k].(string); ok && strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}

func normalizeRelPath(path, workspace string) string {
	rel := strings.ReplaceAll(path, "\\", "/")
	if workspace != "" && strings.HasPrefix(rel, workspace) {
		rel = strings.TrimPrefix(rel, workspace)
		rel = strings.TrimPrefix(rel, "/")
	}
	return rel
}