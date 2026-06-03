package skillgate

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/mihazs/oh-my-grok/internal/hookenv"
)

var (
	nameRE        = regexp.MustCompile(`(?m)^name:\s*([^\n]+)`)
	descBlockRE   = regexp.MustCompile(`(?m)^description:\s*>\s*\n((?:[ \t]+[^\n]+\n?)+)`)
	descLineRE    = regexp.MustCompile(`(?m)^description:\s*(.+)$`)
)

// ResetSession clears skill-gate session state (session-start).
func ResetSession(sessionID string) {
	dir := SessionDir(sessionID)
	_ = os.MkdirAll(dir, 0o755)
	_ = os.WriteFile(catalogPath(sessionID), []byte("[]\n"), 0o644)
	_ = os.WriteFile(loadedPath(sessionID), nil, 0o644)
}

// CleanupSession removes skill-gate dir (session-end).
func CleanupSession(sessionID string) {
	_ = os.RemoveAll(SessionDir(sessionID))
}

// CleanupStopVerify removes stop-verify state (session-end).
func CleanupStopVerify(sessionID string) {
	dir := filepath.Join(hookenv.GrokHome(), "state", "stop-verify", sessionID)
	_ = os.RemoveAll(dir)
}

func catalogCount(sessionID string) int {
	return len(loadCatalog(sessionID))
}

func grokBin() string {
	if b := os.Getenv("GROK_BIN"); b != "" && filepath.IsAbs(b) {
		if _, err := os.Stat(b); err == nil {
			return b
		}
	}
	candidate := filepath.Join(hookenv.GrokHome(), "bin", "grok")
	if _, err := os.Stat(candidate); err == nil {
		return candidate
	}
	if p, err := exec.LookPath("grok"); err == nil {
		return p
	}
	return ""
}

func runInspect(workspace string) ([]byte, error) {
	cmdPath := grokBin()
	if cmdPath == "" {
		return nil, os.ErrNotExist
	}
	cmd := exec.Command(cmdPath, "inspect", "--json")
	if workspace != "" {
		if info, err := os.Stat(workspace); err == nil && info.IsDir() {
			cmd.Dir = workspace
		}
	}
	cmd.Stderr = nil
	return cmd.Output()
}

// RefreshCatalog fills all-skills.json via grok inspect or on-disk discovery.
func RefreshCatalog(sessionID, workspace string) {
	if catalogCount(sessionID) > 0 {
		return
	}
	if out, err := runInspect(workspace); err == nil && len(out) > 0 {
		if n := writeCatalogFromInspect(sessionID, out); n > 0 {
			return
		}
	}
	_ = discoverSkillsOnDisk(sessionID, workspace)
}

func writeCatalogFromInspect(sessionID string, inspectJSON []byte) int {
	var data struct {
		Skills []struct {
			Name        string `json:"name"`
			Description string `json:"description"`
			Source      struct {
				Path string `json:"path"`
				Type string `json:"type"`
			} `json:"source"`
		} `json:"skills"`
	}
	if json.Unmarshal(inspectJSON, &data) != nil {
		return 0
	}
	var catalog []catalogEntry
	seen := make(map[string]struct{})
	for _, e := range data.Skills {
		if e.Name == "" || e.Source.Path == "" {
			continue
		}
		if _, ok := seen[e.Name]; ok {
			continue
		}
		seen[e.Name] = struct{}{}
		scope := e.Source.Type
		if scope == "" {
			scope = "unknown"
		}
		desc := e.Description
		if len(desc) > 500 {
			desc = desc[:500]
		}
		catalog = append(catalog, catalogEntry{
			ID: e.Name, Path: e.Source.Path, Scope: scope, Description: desc,
		})
	}
	meta := metaSkillPath()
	if meta != "" {
		found := false
		for _, e := range catalog {
			if e.ID == "agent-skill-gate" {
				found = true
				break
			}
		}
		if !found {
			catalog = append([]catalogEntry{{
				ID:          "agent-skill-gate",
				Path:        meta,
				Scope:       "user",
				Description: "Skill gate meta-skill; read before mutating tools when unsure which skills apply.",
			}}, catalog...)
		}
	}
	return writeCatalog(sessionID, catalog)
}

func metaSkillPath() string {
	if root, err := hookenv.PluginRoot(); err == nil {
		p := filepath.Join(root, "skills", "agent-skill-gate", "SKILL.md")
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	plugins := filepath.Join(hookenv.GrokHome(), "installed-plugins")
	entries, err := os.ReadDir(plugins)
	if err != nil {
		return ""
	}
	for _, e := range entries {
		if !e.IsDir() || !strings.HasPrefix(e.Name(), "oh-my-grok") {
			continue
		}
		p := filepath.Join(plugins, e.Name(), "skills", "agent-skill-gate", "SKILL.md")
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return filepath.Join(hookenv.GrokHome(), "skills", "agent-skill-gate", "SKILL.md")
}

func discoverSkillsOnDisk(sessionID, workspace string) error {
	seenPath := make(map[string]struct{})
	seenID := make(map[string]struct{})
	var catalog []catalogEntry

	add := func(path, scope string) {
		path, err := filepath.Abs(path)
		if err != nil {
			return
		}
		if _, ok := seenPath[path]; ok {
			return
		}
		if _, err := os.Stat(path); err != nil {
			return
		}
		parent := filepath.Base(filepath.Dir(path))
		sid := skillIDFromFile(path, parent)
		if sid == "" {
			return
		}
		seenPath[path] = struct{}{}
		if _, ok := seenID[sid]; ok {
			return
		}
		seenID[sid] = struct{}{}
		catalog = append(catalog, catalogEntry{
			ID: sid, Path: path, Scope: scope, Description: skillDescFromFile(path),
		})
	}

	scanRoot := func(root, scope string) {
		if root == "" {
			return
		}
		for _, base := range []string{".agents/skills", ".grok/skills"} {
			skillsRoot := filepath.Join(root, base)
			entries, err := os.ReadDir(skillsRoot)
			if err != nil {
				continue
			}
			for _, name := range sortedNames(entries) {
				add(filepath.Join(skillsRoot, name, "SKILL.md"), scope)
			}
		}
	}

	scanRoot(workspace, "project")
	if root, err := hookenv.PluginRoot(); err == nil {
		scanRoot(root, "plugin")
	}
	scanRoot(hookenv.GrokHome(), "user")

	plugins := filepath.Join(hookenv.GrokHome(), "installed-plugins")
	if entries, err := os.ReadDir(plugins); err == nil {
		for _, e := range entries {
			if !e.IsDir() {
				continue
			}
			skillsRoot := filepath.Join(plugins, e.Name(), "skills")
			for _, name := range sortedNamesFromDir(skillsRoot) {
				add(filepath.Join(skillsRoot, name, "SKILL.md"), "plugin")
			}
		}
	}
	meta := metaSkillPath()
	if meta != "" {
		if _, err := os.Stat(meta); err == nil {
			if _, ok := seenID["agent-skill-gate"]; !ok {
				catalog = append([]catalogEntry{{
					ID: "agent-skill-gate", Path: meta, Scope: "plugin",
					Description: "Skill gate meta-skill; read before mutating tools when unsure which skills apply.",
				}}, catalog...)
			}
		}
	}
	writeCatalog(sessionID, catalog)
	return nil
}

func sortedNames(entries []os.DirEntry) []string {
	var names []string
	for _, e := range entries {
		if e.IsDir() {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	return names
}

func sortedNamesFromDir(dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	return sortedNames(entries)
}

func skillIDFromFile(path, parent string) string {
	head, err := readHead(path, 800)
	if err != nil {
		return parent
	}
	if m := nameRE.FindStringSubmatch(head); len(m) > 1 {
		return strings.Trim(strings.TrimSpace(m[1]), "\"'")
	}
	return parent
}

func skillDescFromFile(path string) string {
	head, err := readHead(path, 1200)
	if err != nil {
		return ""
	}
	if m := descBlockRE.FindStringSubmatch(head); len(m) > 1 {
		var parts []string
		for _, ln := range strings.Split(m[1], "\n") {
			parts = append(parts, strings.TrimSpace(ln))
		}
		desc := strings.Join(parts, " ")
		if len(desc) > 500 {
			return desc[:500]
		}
		return desc
	}
	if m := descLineRE.FindStringSubmatch(head); len(m) > 1 {
		desc := strings.TrimSpace(m[1])
		if len(desc) > 500 {
			return desc[:500]
		}
		return desc
	}
	return ""
}

func readHead(path string, n int) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	if len(b) > n {
		b = b[:n]
	}
	return string(b), nil
}

func writeCatalog(sessionID string, catalog []catalogEntry) int {
	_ = os.MkdirAll(SessionDir(sessionID), 0o755)
	b, _ := json.MarshalIndent(catalog, "", "  ")
	_ = os.WriteFile(catalogPath(sessionID), append(b, '\n'), 0o644)
	return len(catalog)
}

// BuildSessionContextMessage returns SessionStart skill gate banner.
func BuildSessionContextMessage(sessionID string, maxLines int) string {
	if maxLines <= 0 {
		maxLines = 20
	}
	catalog := loadCatalog(sessionID)
	rules := RulesPath()
	catPath := catalogPath(sessionID)
	var lines []string
	lines = append(lines,
		"<AGENT_SKILL_GATE>",
		"Skill gate is active. Before mutating tools (write/edit/delete), Read applicable skills from the catalog.",
		"Full rules: "+rules,
		fmt.Sprintf("Catalog: %s (%d skills)", catPath, len(catalog)),
		"",
	)
	if len(catalog) == 0 {
		meta := metaSkillPath()
		if meta == "" {
			meta = "agent-skill-gate (oh-my-grok plugin)"
		}
		lines = append(lines, "Catalog empty — run `grok inspect` or Read "+meta)
	} else {
		lines = append(lines, "Available skills (use Read on path from inspect):")
		shown := 0
		for _, e := range catalog {
			if shown >= maxLines {
				break
			}
			desc := e.Description
			if len(desc) > 120 {
				desc = desc[:120]
			}
			desc = strings.ReplaceAll(desc, "\n", " ")
			scope := e.Scope
			if scope == "" {
				scope = "?"
			}
			lines = append(lines, fmt.Sprintf("- %s (%s): %s", e.ID, scope, desc))
			shown++
		}
		if len(catalog) > maxLines {
			lines = append(lines, fmt.Sprintf("- ... and %d more in %s", len(catalog)-maxLines, catPath))
		}
	}
	lines = append(lines, "",
		"Minimum: at least one catalog SKILL.md must be Read this session or mutating tools are blocked.",
		"</AGENT_SKILL_GATE>",
	)
	return strings.Join(lines, "\n")
}

// BuildReminder returns per-prompt skill gate reminder.
func BuildReminder(sessionID string) string {
	catalog := loadCatalog(sessionID)
	loaded := loadLoadedIDs(sessionID)
	var unloaded []string
	for _, e := range catalog {
		if e.ID == "" {
			continue
		}
		if _, ok := loaded[e.ID]; !ok {
			unloaded = append(unloaded, e.ID)
		}
	}
	if len(catalog) == 0 {
		return "<AGENT_SKILL_GATE_REMINDER>Catalog empty. Read agent-skill-gate meta-skill before edits.</AGENT_SKILL_GATE_REMINDER>"
	}
	if len(loaded) == 0 {
		sample := strings.Join(truncateList(unloaded, 12), ", ")
		extra := ""
		if len(unloaded) > 12 {
			extra = fmt.Sprintf(" (+%d more)", len(unloaded)-12)
		}
		return fmt.Sprintf(
			"<AGENT_SKILL_GATE_REMINDER>No skills loaded yet. Read applicable skills before tools. Unloaded: %s%s</AGENT_SKILL_GATE_REMINDER>",
			sample, extra,
		)
	}
	if len(unloaded) > 0 {
		sample := strings.Join(truncateList(unloaded, 8), ", ")
		return fmt.Sprintf(
			"<AGENT_SKILL_GATE_REMINDER>Loaded %d skill(s). Still unloaded: %s. Read task-matching skills before domain edits.</AGENT_SKILL_GATE_REMINDER>",
			len(loaded), sample,
		)
	}
	return "<AGENT_SKILL_GATE_REMINDER>All catalog skills loaded this session.</AGENT_SKILL_GATE_REMINDER>"
}

func truncateList(ss []string, n int) []string {
	if len(ss) <= n {
		return ss
	}
	return ss[:n]
}