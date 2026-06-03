package lsp

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/mihazs/oh-my-grok/internal/hookenv"
)

var (
	patchPrefixes = []string{"*** Add File: ", "*** Update File: ", "*** Move to: "}
	mutationTools = map[string]struct{}{
		"apply_patch": {}, "write": {}, "strreplace": {}, "str_replace": {},
		"edit": {}, "multiedit": {}, "multi_edit": {}, "editnotebook": {},
	}
)

// UpdateStashFromEvent runs diagnostics for mutated paths in a PostToolUse event.
func UpdateStashFromEvent(ev hookenv.Event) {
	paths := extractMutatedPaths(ev)
	if len(paths) == 0 {
		return
	}
	ws := ev.WorkspaceRoot
	if ws == "" {
		ws = os.Getenv("GROK_WORKSPACE_ROOT")
	}
	sid := ev.SessionID
	if sid == "" {
		sid = "unknown"
	}
	stashPath := StashPath(sid)
	_ = os.MkdirAll(filepath.Dir(stashPath), 0o755)
	for _, rel := range paths {
		abs := rel
		if !filepath.IsAbs(abs) && ws != "" {
			abs = filepath.Join(ws, strings.TrimPrefix(rel, "./"))
		}
		if _, err := os.Stat(abs); err != nil {
			continue
		}
		diag, err := runDiagnostics(abs)
		if err != nil {
			continue
		}
		mergeDiagnostics(stashPath, abs, diag)
	}
}

func extractMutatedPaths(ev hookenv.Event) []string {
	name := strings.ToLower(strings.TrimSpace(ev.ToolName))
	if name != "" && !isMutationTool(name) {
		return nil
	}
	if isFailedResponse(ev) {
		return nil
	}
	block := ev.ToolInput
	if block == nil {
		return nil
	}
	set := make(map[string]struct{})
	for _, k := range []string{"path", "filePath", "file_path", "target_file", "targetFile"} {
		if v, ok := block[k].(string); ok && v != "" {
			set[v] = struct{}{}
		}
	}
	for _, k := range []string{"paths", "filePaths", "file_paths"} {
		if arr, ok := block[k].([]any); ok {
			for _, it := range arr {
				if s, ok := it.(string); ok && s != "" {
					set[s] = struct{}{}
				}
			}
		}
	}
	for _, k := range []string{"input", "patch", "command"} {
		if v, ok := block[k].(string); ok {
			addPatchPaths(set, v)
		}
	}
	for _, k := range []string{"files", "changes"} {
		if arr, ok := block[k].([]any); ok {
			for _, it := range arr {
				m, ok := it.(map[string]any)
				if !ok {
					continue
				}
				for _, pk := range []string{"path", "filePath", "file_path", "movePath", "move_path"} {
					if v, ok := m[pk].(string); ok && v != "" {
						set[v] = struct{}{}
					}
				}
			}
		}
	}
	var out []string
	for p := range set {
		out = append(out, p)
	}
	return out
}

func isMutationTool(name string) bool {
	_, ok := mutationTools[strings.ToLower(name)]
	return ok
}

func isFailedResponse(ev hookenv.Event) bool {
	// PostTool events may include response in raw map — not on Event struct; skip.
	return false
}

func addPatchPaths(set map[string]struct{}, payload string) {
	for _, line := range strings.Split(payload, "\n") {
		for _, prefix := range patchPrefixes {
			if strings.HasPrefix(line, prefix) {
				set[strings.TrimSpace(line[len(prefix):])] = struct{}{}
			}
		}
	}
}

func toolsModule() string {
	root, err := hookenv.PluginRoot()
	if err != nil {
		return ""
	}
	mod := filepath.Join(root, "vendor", "lsp-tools-mcp", "dist", "tools.js")
	if _, err := os.Stat(mod); err != nil {
		return ""
	}
	return mod
}

func runDiagnostics(absPath string) (string, error) {
	if mock := os.Getenv("OMG_LSP_MOCK_DIAG"); mock != "" {
		return mock, nil
	}
	mod := toolsModule()
	if mod == "" {
		return "", os.ErrNotExist
	}
	if _, err := exec.LookPath("node"); err != nil {
		return "", err
	}
	script := `
import { pathToFileURL } from "node:url";
import { executeLspDiagnostics } from pathToFileURL(process.argv[2]).href;
const filePath = process.argv[3];
try {
  const result = await executeLspDiagnostics({ filePath, severity: "error" });
  const text = result.content.map((block) => block.text).join("\n").trim();
  process.stdout.write(text);
} catch (error) {
  const message = error instanceof Error ? (error.message || String(error)) : String(error);
  process.stderr.write(message);
  process.exit(1);
}
`
	cmd := exec.Command("node", "--input-type=module", "-e", script, mod, absPath)
	cmd.Stderr = nil
	out, err := cmd.Output()
	return string(out), err
}

const cleanText = "No diagnostics found"
const unsupportedPrefix = "No LSP server configured for extension:"

func isUnavailable(text string) bool {
	normalized := strings.TrimSpace(text)
	if normalized == "" {
		return false
	}
	markers := []string{
		"LSP request timeout (method: initialize)",
		"LSP server is still initializing",
		"NOT INSTALLED",
		"Command not found:",
	}
	for _, m := range markers {
		if strings.Contains(normalized, m) {
			return true
		}
	}
	return false
}

func hasErrors(text string) bool {
	normalized := strings.TrimSpace(text)
	if normalized == "" {
		return false
	}
	if normalized == cleanText {
		return false
	}
	if strings.HasPrefix(normalized, unsupportedPrefix) {
		return false
	}
	if isUnavailable(normalized) {
		return false
	}
	if errorPattern.MatchString(normalized) {
		return true
	}
	lower := strings.ToLower(normalized)
	return strings.HasPrefix(lower, "error") || strings.Contains(lower, "error[")
}

func mergeDiagnostics(stashPath, filePath, diagnostics string) {
	var stash stashFile
	b, err := os.ReadFile(stashPath)
	if err == nil {
		_ = json.Unmarshal(b, &stash)
	}
	if stash.Files == nil {
		stash.Files = make(map[string]stashFileEntry)
	}
	if stash.Version == 0 {
		stash.Version = 1
	}
	entry := stashFileEntry{
		Diagnostics: diagnostics,
		HasErrors:   hasErrors(diagnostics),
	}
	if entry.HasErrors {
		stash.Files[filePath] = entry
	} else {
		delete(stash.Files, filePath)
	}
	out, _ := json.MarshalIndent(stash, "", "  ")
	_ = os.WriteFile(stashPath, append(out, '\n'), 0o644)
}

// CleanupSession removes LSP stash for session-end.
func CleanupSession(sessionID string) {
	_ = os.Remove(StashPath(sessionID))
}