package cmd

import (
	"io"
	"os"

	"github.com/mihazs/oh-my-grok/internal/hookenv"
	"github.com/mihazs/oh-my-grok/internal/hookio"
	"github.com/spf13/cobra"
)

// NewRoot returns the omg-hook cobra root command.
func NewRoot() *cobra.Command {
	root := &cobra.Command{Use: "omg-hook"}
	root.AddCommand(
		sessionStartCmd(),
		sessionEndCmd(),
		userPromptCmd(),
		preToolUseCmd(),
		postToolReadCmd(),
		postToolTodoWriteCmd(),
		postToolLSPCmd(),
		stopCmd(),
	)
	return root
}

// Execute runs the root command; exits 1 on error.
func Execute() {
	if err := NewRoot().Execute(); err != nil {
		os.Exit(1)
	}
}

func readEvent() (hookenv.Event, error) {
	return hookenv.ReadEvent(os.Stdin)
}

func sessionID(ev hookenv.Event) string {
	if ev.SessionID != "" {
		return ev.SessionID
	}
	if s := os.Getenv("GROK_SESSION_ID"); s != "" {
		return s
	}
	return "unknown"
}

func workspace(ev hookenv.Event) string {
	if ev.WorkspaceRoot != "" {
		return ev.WorkspaceRoot
	}
	return os.Getenv("GROK_WORKSPACE_ROOT")
}

func denyPreTool(w io.Writer, reason, fallback string) {
	if reason == "" {
		reason = fallback
	}
	os.Exit(hookio.EmitDeny(w, reason))
}

func allowPreTool(w io.Writer) {
	hookio.EmitAllow(w)
	os.Exit(0)
}