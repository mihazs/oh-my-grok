package lsp

import (
	"encoding/json"
	"os"
	"sort"
	"strings"

)

// CollectContext returns LSP diagnostic reminder for UserPromptSubmit.
func CollectContext(sessionID string) string {
	path := StashPath(sessionID)
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	var stash stashFile
	if json.Unmarshal(b, &stash) != nil || len(stash.Files) == 0 {
		return ""
	}
	var filePaths []string
	for p, e := range stash.Files {
		if e.HasErrors {
			filePaths = append(filePaths, p)
		}
	}
	if len(filePaths) == 0 {
		return ""
	}
	sort.Strings(filePaths)
	var blocks []string
	for _, filePath := range filePaths {
		entry := stash.Files[filePath]
		lines := []string{"LSP diagnostics for " + filePath + ":"}
		diag := strings.TrimSpace(entry.Diagnostics)
		if diag != "" {
			for _, chunk := range strings.Split(strings.ReplaceAll(diag, "\r\n", "\n"), "\n") {
				chunk = strings.TrimSpace(chunk)
				if chunk == "" {
					continue
				}
				if errorPattern.MatchString(chunk) {
					lines = append(lines, "- "+chunk)
				} else {
					lines = append(lines, chunk)
				}
			}
		} else {
			lines = append(lines, "(empty)")
		}
		blocks = append(blocks, strings.Join(lines, "\n"))
	}
	body := strings.Join(blocks, "\n\n")
	return strings.TrimSpace(
		"<LSP_DIAGNOSTICS>\n" +
			"Unresolved LSP errors remain from recent edits. Fix these before stopping.\n\n" +
			body + "\n" +
			"</LSP_DIAGNOSTICS>",
	)
}