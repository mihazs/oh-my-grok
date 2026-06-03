package cmd

import (
	"github.com/mihazs/oh-my-grok/internal/boulder"
	"github.com/mihazs/oh-my-grok/internal/hookenv"
	"github.com/mihazs/oh-my-grok/internal/lsp"
	"github.com/mihazs/oh-my-grok/internal/skillgate"
	"github.com/mihazs/oh-my-grok/internal/usingpowers"
	"github.com/spf13/cobra"
)

func sessionEndCmd() *cobra.Command {
	return &cobra.Command{
		Use: "session-end",
		RunE: func(cmd *cobra.Command, args []string) error {
			ev, err := readEvent()
			if err != nil {
				return err
			}
			hookenv.ApplyEvent(ev)
			sid := sessionID(ev)
			ws := workspace(ev)

			skillgate.CleanupSession(sid)
			skillgate.CleanupStopVerify(sid)
			usingpowers.CleanupSession(sid)
			boulder.CleanupOMOSession(ws, sid)
			lsp.CleanupSession(sid)
			return nil
		},
	}
}