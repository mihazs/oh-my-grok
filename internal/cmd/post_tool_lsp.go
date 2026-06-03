package cmd

import (
	"github.com/mihazs/oh-my-grok/internal/hookenv"
	"github.com/mihazs/oh-my-grok/internal/lsp"
	"github.com/spf13/cobra"
)

func postToolLSPCmd() *cobra.Command {
	return &cobra.Command{
		Use: "post-tool-lsp",
		RunE: func(cmd *cobra.Command, args []string) error {
			ev, err := readEvent()
			if err != nil {
				return err
			}
			hookenv.ApplyEvent(ev)
			lsp.UpdateStashFromEvent(ev)
			return nil
		},
	}
}