package boulder

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/mihazs/oh-my-grok/internal/hookenv"
)

const (
	todoEnforcerDir          = "todo-enforcer"
	continuationCooldownMs   = 5000
	maxConsecutiveFailures   = 5
	abortWindowMs            = 3000
	todoMirrorDir            = ".omg/todos"
)

var incompleteStatuses = map[string]struct{}{
	"pending": {}, "in_progress": {}, "in-progress": {},
}

// ShouldAllowStop returns true when stop should not be blocked by boulder/todo logic.
func ShouldAllowStop(stopReason string, stopHookActive bool, backgroundTasks []map[string]any) bool {
	sr := strings.ToLower(strings.TrimSpace(stopReason))
	if sr != "" && sr != "end_turn" && sr != "endturn" {
		return true
	}
	if stopHookActive {
		return true
	}
	active := map[string]struct{}{
		"running": {}, "pending": {}, "in_progress": {},
		"in-progress": {}, "active": {},
	}
	for _, t := range backgroundTasks {
		st, _ := t["status"].(string)
		if _, ok := active[strings.ToLower(st)]; ok {
			return true
		}
	}
	return false
}

// FindSessionDir locates the Grok session resources directory.
func FindSessionDir(sessionID string) string {
	return findSessionDir(sessionID)
}

func findSessionDir(sessionID string) string {
	root := filepath.Join(hookenv.GrokHome(), "sessions")
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

// TodosFromResources reads todos from resources_state.json.
func TodosFromResources(sessionDir string) []map[string]any {
	return todosFromResources(sessionDir)
}

func todosFromResources(sessionDir string) []map[string]any {
	b, err := os.ReadFile(filepath.Join(sessionDir, "resources_state.json"))
	if err != nil {
		return nil
	}
	var state map[string]any
	if json.Unmarshal(b, &state) != nil {
		return nil
	}
	var todos []map[string]any
	for key, entry := range state {
		em, ok := entry.(map[string]any)
		if !ok {
			continue
		}
		if !strings.Contains(key, "TodoState") && !strings.Contains(key, "todo_write") {
			continue
		}
		raw := em["state"]
		var todoData map[string]any
		switch v := raw.(type) {
		case string:
			if json.Unmarshal([]byte(v), &todoData) != nil {
				continue
			}
		case map[string]any:
			todoData = v
		default:
			continue
		}
		items, _ := todoData["todos"].([]any)
		for _, it := range items {
			if m, ok := it.(map[string]any); ok {
				todos = append(todos, m)
			}
		}
	}
	return todos
}

func incompleteTodos(todos []map[string]any) []map[string]any {
	var out []map[string]any
	done := map[string]struct{}{
		"completed": {}, "cancelled": {}, "blocked": {}, "deleted": {},
	}
	for _, t := range todos {
		status := strings.ToLower(strings.TrimSpace(stringField(t, "status")))
		if _, ok := incompleteStatuses[status]; ok {
			out = append(out, t)
			continue
		}
		if _, ok := done[status]; !ok {
			out = append(out, t)
		}
	}
	return out
}

func stringField(m map[string]any, key string) string {
	if v, ok := m[key].(string); ok {
		return v
	}
	return ""
}

func enforcerStatePath(sessionID string) string {
	return filepath.Join(hookenv.GrokHome(), "state", todoEnforcerDir, sessionID, "state.json")
}

func readEnforcerState(sessionID string) map[string]any {
	b, err := os.ReadFile(enforcerStatePath(sessionID))
	if err != nil {
		return map[string]any{}
	}
	var state map[string]any
	if json.Unmarshal(b, &state) != nil {
		return map[string]any{}
	}
	return state
}

func writeEnforcerState(sessionID string, state map[string]any) {
	state["updated_at"] = nowISO()
	path := enforcerStatePath(sessionID)
	_ = os.MkdirAll(filepath.Dir(path), 0o755)
	b, _ := json.MarshalIndent(state, "", "  ")
	_ = os.WriteFile(path, append(b, '\n'), 0o644)
}

// ShouldSkipTodoContinuation returns a skip reason or "" if continuation is allowed.
func ShouldSkipTodoContinuation(sessionID, stopReason string) string {
	state := readEnforcerState(sessionID)
	nowMs := time.Now().UTC().UnixMilli()
	if v, ok := state["cooldown_until_ms"].(float64); ok && nowMs < int64(v) {
		return "cooldown"
	}
	if v, ok := state["abort_detected_at_ms"].(float64); ok && nowMs-int64(v) < abortWindowMs {
		return "abort_window"
	}
	failures := 0
	if v, ok := state["failure_count"].(float64); ok {
		failures = int(v)
	}
	if failures >= maxConsecutiveFailures {
		return "failure_backoff"
	}
	sr := strings.ToLower(strings.TrimSpace(stopReason))
	if sr != "" && sr != "end_turn" && sr != "endturn" {
		state["abort_detected_at_ms"] = float64(nowMs)
		writeEnforcerState(sessionID, state)
	}
	return ""
}

func recordTodoContinuationFire(sessionID string) {
	state := readEnforcerState(sessionID)
	nowMs := time.Now().UTC().UnixMilli()
	state["last_fire_ms"] = float64(nowMs)
	state["cooldown_until_ms"] = float64(nowMs + continuationCooldownMs)
	if v, ok := state["fire_count"].(float64); ok {
		state["fire_count"] = v + 1
	} else {
		state["fire_count"] = float64(1)
	}
	writeEnforcerState(sessionID, state)
}

// MirrorTodos writes .omg/todos/<session>.json.
func MirrorTodos(workspace, sessionID string, todos []map[string]any) {
	if workspace == "" {
		return
	}
	dest := filepath.Join(workspace, todoMirrorDir, sessionID+".json")
	_ = os.MkdirAll(filepath.Dir(dest), 0o755)
	payload := map[string]any{
		"session_id": sessionID,
		"updated_at": nowISO(),
		"todos":      todos,
	}
	b, _ := json.MarshalIndent(payload, "", "  ")
	_ = os.WriteFile(dest, append(b, '\n'), 0o644)
}