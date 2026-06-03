package lsp

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/mihazs/oh-my-grok/internal/config"
	"github.com/mihazs/oh-my-grok/internal/hookenv"
)

var errorPattern = regexp.MustCompile(`(?m)^(?:error|warning|information|hint)\[[^\]\r\n]+\] \(\d+:\d+:`)

// StashPath returns ~/.grok/state/lsp-diagnostics/<session>.json
func StashPath(sessionID string) string {
	if sessionID == "" {
		sessionID = "unknown"
	}
	return filepath.Join(hookenv.GrokHome(), "state", "lsp-diagnostics", sessionID+".json")
}

// EnforceEnabled reports whether LSP stop enforcement is on (OMG_LSP_ENFORCE, default on).
func EnforceEnabled() bool {
	return config.LSPEnforceEnabled()
}

type stashFile struct {
	Version int                       `json:"version"`
	Files   map[string]stashFileEntry `json:"files"`
}

type stashFileEntry struct {
	Diagnostics string `json:"diagnostics"`
	HasErrors   bool   `json:"has_errors"`
}

// EvaluateStop blocks when the LSP stash has unresolved errors.
func EvaluateStop(sessionID string) (bool, string) {
	if !EnforceEnabled() {
		return false, ""
	}
	path := StashPath(sessionID)
	b, err := os.ReadFile(path)
	if err != nil {
		return false, ""
	}
	var stash stashFile
	if json.Unmarshal(b, &stash) != nil || len(stash.Files) == 0 {
		return false, ""
	}
	var filePaths []string
	for p, e := range stash.Files {
		if e.HasErrors {
			filePaths = append(filePaths, p)
		}
	}
	if len(filePaths) == 0 {
		return false, ""
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
	msg := "Stop blocked: LSP errors remain in files you edited this session.\n" +
		"Run diagnostics on each file and fix errors before stopping.\n\n" + body
	return true, strings.TrimSpace(msg)
}