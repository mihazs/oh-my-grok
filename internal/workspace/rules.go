package workspace

import (
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/mihazs/oh-my-grok/internal/hookenv"
)

func maxBytes(name string, fallback int) int {
	v := strings.TrimSpace(os.Getenv(name))
	if v == "" {
		return fallback
	}
	var n int
	for _, c := range v {
		if c < '0' || c > '9' {
			return fallback
		}
		n = n*10 + int(c-'0')
	}
	if n <= 0 {
		return fallback
	}
	return n
}

func readCapped(path string, limit int) (string, bool) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", false
	}
	truncated := len(b) > limit
	if truncated {
		b = b[:limit]
	}
	return strings.TrimRight(string(b), " \t\r\n"), truncated
}

// Collect returns workspace AGENTS.md + plugin rules context or "".
func Collect(workspace string) string {
	if workspace == "" {
		workspace = os.Getenv("GROK_WORKSPACE_ROOT")
	}
	if workspace == "" {
		return ""
	}
	agentsMax := maxBytes("WORKSPACE_AGENTS_MAX_BYTES", 16384)
	ruleMax := maxBytes("PLUGIN_RULE_MAX_BYTES", 8192)
	totalMax := maxBytes("WORKSPACE_CONTEXT_MAX_BYTES", 32768)

	var parts []string
	used := 0

	agentsPath := filepath.Join(workspace, "AGENTS.md")
	if body, trunc := readCapped(agentsPath, min(agentsMax, totalMax-used)); body != "" {
		rel, _ := filepath.Rel(workspace, agentsPath)
		if rel == "" {
			rel = "AGENTS.md"
		}
		rel = strings.ReplaceAll(rel, "\\", "/")
		tag := fmtWorkspaceAgents(rel, trunc)
		block := tag + "\n" + body + "\n</WORKSPACE_AGENTS>"
		parts = append(parts, block)
		used += len(block)
	}

	pluginRoot, _ := hookenv.PluginRoot()
	if pluginRoot != "" {
		rulesDir := filepath.Join(pluginRoot, "rules")
		entries, err := os.ReadDir(rulesDir)
		if err == nil {
			var names []string
			for _, e := range entries {
				if e.IsDir() || !strings.HasSuffix(e.Name(), ".md") {
					continue
				}
				names = append(names, e.Name())
			}
			sort.Strings(names)
			for _, name := range names {
				if used >= totalMax {
					break
				}
				cap := min(ruleMax, totalMax-used)
				if cap <= 0 {
					break
				}
				path := filepath.Join(rulesDir, name)
				body, trunc := readCapped(path, cap)
				if body == "" {
					continue
				}
				tag := fmtPluginRule(name, trunc)
				block := tag + "\n" + body + "\n</OMG_PLUGIN_RULE>"
				parts = append(parts, block)
				used += len(block)
			}
		}
	}

	if len(parts) == 0 {
		return ""
	}
	return strings.Join(parts, "\n\n")
}

func fmtWorkspaceAgents(rel string, trunc bool) string {
	if trunc {
		return `<WORKSPACE_AGENTS path="` + rel + `" truncated="true">`
	}
	return `<WORKSPACE_AGENTS path="` + rel + `">`
}

func fmtPluginRule(name string, trunc bool) string {
	if trunc {
		return `<OMG_PLUGIN_RULE file="rules/` + name + `" truncated="true">`
	}
	return `<OMG_PLUGIN_RULE file="rules/` + name + `">`
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}