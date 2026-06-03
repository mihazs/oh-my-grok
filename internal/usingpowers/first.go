package usingpowers

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/mihazs/oh-my-grok/internal/hookenv"
	"github.com/mihazs/oh-my-grok/internal/skillgate"
)

func stateDir(sessionID string) string {
	if sessionID == "" {
		sessionID = "unknown"
	}
	return filepath.Join(hookenv.GrokHome(), "state", "using-superpowers", sessionID)
}

func doneFile(sessionID string) string {
	return filepath.Join(stateDir(sessionID), "first_prompt_done")
}

// ResetSession clears first-prompt state for a session (session-start).
func ResetSession(sessionID string) {
	_ = os.RemoveAll(stateDir(sessionID))
}

// CleanupSession removes using-superpowers state (session-end).
func CleanupSession(sessionID string) {
	ResetSession(sessionID)
}

func resolveSkillPath() string {
	if p := os.Getenv("USING_SUPERPOWERS_SKILL"); p != "" {
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
		if !e.IsDir() {
			continue
		}
		candidate := filepath.Join(plugins, e.Name(), "skills", "using-superpowers", "SKILL.md")
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	return ""
}

func buildContext(skillPath string) string {
	body, err := os.ReadFile(skillPath)
	if err != nil {
		body = []byte(fmt.Sprintf("(using-superpowers skill unavailable: %v)", err))
	}
	return strings.TrimSpace(fmt.Sprintf(
		"<USING_SUPERPOWERS_FIRST_PROMPT>\n"+
			"MANDATORY: You are starting this session's first user turn. "+
			"Treat this as invoking `/using-superpowers` — follow the skill below before "+
			"any response, tool use, or clarifying question (subagents: skip per skill).\n\n"+
			"**Full content of superpowers:using-superpowers:**\n\n%s\n"+
			"</USING_SUPERPOWERS_FIRST_PROMPT>",
		string(body),
	))
}

// Collect returns first-prompt using-superpowers context or "".
func Collect(sessionID string) string {
	if _, err := os.Stat(doneFile(sessionID)); err == nil {
		return ""
	}
	skillPath := resolveSkillPath()
	if skillPath == "" {
		return ""
	}
	_ = os.MkdirAll(stateDir(sessionID), 0o755)
	_ = os.WriteFile(doneFile(sessionID), []byte{}, 0o644)
	_ = skillgate.MarkSkillLoaded(sessionID, "using-superpowers")
	return buildContext(skillPath)
}