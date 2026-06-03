package cmd

import (
	"strings"

	"github.com/mihazs/oh-my-grok/internal/boulder"
	"github.com/mihazs/oh-my-grok/internal/hookenv"
	"github.com/spf13/cobra"
)

func postToolTodoWriteCmd() *cobra.Command {
	return &cobra.Command{
		Use: "post-tool-todo-write",
		RunE: func(cmd *cobra.Command, args []string) error {
			ev, err := readEvent()
			if err != nil {
				return err
			}
			hookenv.ApplyEvent(ev)
			if !strings.EqualFold(ev.ToolName, "todowrite") {
				return nil
			}
			sid := sessionID(ev)
			ws := workspace(ev)
			if sid == "" || ws == "" {
				return nil
			}
			sessionDir := boulder.FindSessionDir(sid)
			if sessionDir == "" {
				return nil
			}
			todos := boulder.TodosFromResources(sessionDir)
			boulder.MirrorTodos(ws, sid, todos)
			return nil
		},
	}
}