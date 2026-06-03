package skillgate

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/mihazs/oh-my-grok/internal/hookenv"
)

type catalogEntry struct {
	ID          string `json:"id"`
	Path        string `json:"path"`
	Scope       string `json:"scope,omitempty"`
	Description string `json:"description,omitempty"`
}

// SessionDir returns ~/.grok/state/skill-gate/<session>.
func SessionDir(sessionID string) string {
	if sessionID == "" {
		sessionID = "unknown"
	}
	return filepath.Join(hookenv.GrokHome(), "state", "skill-gate", sessionID)
}

func catalogPath(sessionID string) string {
	return filepath.Join(SessionDir(sessionID), "all-skills.json")
}

func loadedPath(sessionID string) string {
	return filepath.Join(SessionDir(sessionID), "skills.loaded")
}

// RulesPath returns the agent-skill-gate rules markdown path.
func RulesPath() string {
	if root, err := hookenv.PluginRoot(); err == nil {
		p := filepath.Join(root, "rules", "00-agent-skill-gate.md")
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return filepath.Join(hookenv.GrokHome(), "rules", "00-agent-skill-gate.md")
}

func loadCatalog(sessionID string) []catalogEntry {
	b, err := os.ReadFile(catalogPath(sessionID))
	if err != nil {
		return nil
	}
	var raw []catalogEntry
	if err := json.Unmarshal(b, &raw); err != nil {
		return nil
	}
	return raw
}

func loadLoadedIDs(sessionID string) map[string]struct{} {
	b, err := os.ReadFile(loadedPath(sessionID))
	if err != nil {
		return map[string]struct{}{}
	}
	out := make(map[string]struct{})
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			out[line] = struct{}{}
		}
	}
	return out
}

func listUnloaded(catalog []catalogEntry, loaded map[string]struct{}, limit int) []string {
	var ids []string
	for _, e := range catalog {
		if e.ID == "" {
			continue
		}
		if _, ok := loaded[e.ID]; !ok {
			ids = append(ids, e.ID)
			if limit > 0 && len(ids) >= limit {
				break
			}
		}
	}
	return ids
}

// PreTool returns allow=true or a deny reason for skill-gate.
func PreTool(sessionID string) (allow bool, reason string) {
	catalog := loadCatalog(sessionID)
	loaded := loadLoadedIDs(sessionID)
	if len(loaded) > 0 {
		return true, ""
	}
	if len(catalog) == 0 {
		return true, ""
	}
	unloaded := listUnloaded(catalog, loaded, 15)
	sample := strings.Join(unloaded, ", ")
	return false, fmt.Sprintf(
		"Read at least one applicable skill from the grok inspect catalog before mutating files. Rules: %s. Unloaded examples: %s",
		RulesPath(), sample,
	)
}

// MarkSkillLoaded appends a skill id to skills.loaded if not present.
func MarkSkillLoaded(sessionID, skillID string) error {
	if skillID == "" {
		return nil
	}
	dir := SessionDir(sessionID)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	path := loadedPath(sessionID)
	existing := loadLoadedIDs(sessionID)
	if _, ok := existing[skillID]; ok {
		return nil
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = fmt.Fprintf(f, "%s\n", skillID)
	return err
}

// SkillIDForPath resolves catalog id or conventional SKILL.md layout.
func SkillIDForPath(sessionID, path string) string {
	abs, err := filepath.Abs(path)
	if err != nil {
		abs = path
	}
	for _, e := range loadCatalog(sessionID) {
		if e.Path == "" {
			continue
		}
		ep, err := filepath.Abs(e.Path)
		if err == nil && ep == abs {
			return e.ID
		}
	}
	p := strings.ReplaceAll(abs, "\\", "/")
	for _, part := range []string{".agents/skills/", ".grok/skills/"} {
		if idx := strings.Index(p, part); idx >= 0 && strings.HasSuffix(p, "/SKILL.md") {
			seg := p[idx+len(part):]
			if i := strings.Index(seg, "/"); i >= 0 {
				return seg[:i]
			}
		}
	}
	homeSkills := filepath.Join(hookenv.GrokHome(), "skills")
	if strings.HasPrefix(abs, homeSkills) && strings.HasSuffix(p, "/SKILL.md") {
		rel := strings.TrimPrefix(p, strings.ReplaceAll(homeSkills, "\\", "/")+"/")
		if i := strings.Index(rel, "/"); i >= 0 {
			return rel[:i]
		}
	}
	if idx := strings.Index(p, "/installed-plugins/"); idx >= 0 {
		if sk := strings.Index(p, "/skills/"); sk >= 0 && strings.HasSuffix(p, "/SKILL.md") {
			seg := p[sk+len("/skills/"):]
			if i := strings.Index(seg, "/"); i >= 0 {
				return seg[:i]
			}
		}
	}
	return ""
}

// ReadPathFromEvent extracts the Read tool path from hook stdin.
func ReadPathFromEvent(ev hookenv.Event) string {
	if ev.ToolInput != nil {
		for _, k := range []string{"path", "file_path", "filePath", "target_file", "targetFile"} {
			if v, ok := ev.ToolInput[k].(string); ok && strings.TrimSpace(v) != "" {
				return v
			}
		}
	}
	return ""
}