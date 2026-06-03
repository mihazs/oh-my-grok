package cmd

import (
	"os"

	"github.com/mihazs/oh-my-grok/internal/boulder"
	"github.com/mihazs/oh-my-grok/internal/hookenv"
	"github.com/mihazs/oh-my-grok/internal/hookio"
	"github.com/mihazs/oh-my-grok/internal/lsp"
	"github.com/mihazs/oh-my-grok/internal/ralph"
	"github.com/mihazs/oh-my-grok/internal/stoppending"
	"github.com/spf13/cobra"
)

func stopCmd() *cobra.Command {
	return &cobra.Command{
		Use: "stop",
		RunE: func(cmd *cobra.Command, args []string) error {
			ev, err := readEvent()
			if err != nil {
				return err
			}
			hookenv.ApplyEvent(ev)
			w := os.Stdout

			if block, msg := ralph.EvaluateStop(ev); block {
				hookio.EmitStopBlock(w, msg)
				os.Exit(0)
			}

			ws := workspace(ev)
			sid := sessionID(ev)
			if !boulder.AutoContinuePaused(ws, sid) {
				if block, msg := boulder.EvaluateBoulderStop(ev); block {
					hookio.EmitStopBlock(w, msg)
					os.Exit(0)
				}
				if block, msg := boulder.EvaluateTodoStop(ev); block {
					hookio.EmitStopBlock(w, msg)
					os.Exit(0)
				}
				if block, msg := lsp.EvaluateStop(sid); block {
					hookio.EmitStopBlock(w, msg)
					os.Exit(0)
				}
				if block, msg := stoppending.EvaluateStop(ev); block {
					hookio.EmitStopBlock(w, msg)
					os.Exit(0)
				}
			}

			hookio.EmitStopAllow(w)
			os.Exit(0)
			return nil
		},
	}
}