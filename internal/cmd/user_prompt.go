package cmd

import (
	"os"
	"strings"

	"github.com/mihazs/oh-my-grok/internal/boulder"
	"github.com/mihazs/oh-my-grok/internal/handoff"
	"github.com/mihazs/oh-my-grok/internal/hashline"
	"github.com/mihazs/oh-my-grok/internal/hookenv"
	"github.com/mihazs/oh-my-grok/internal/hookio"
	"github.com/mihazs/oh-my-grok/internal/intentgate"
	"github.com/mihazs/oh-my-grok/internal/lsp"
	"github.com/mihazs/oh-my-grok/internal/prometheus"
	"github.com/mihazs/oh-my-grok/internal/ralph"
	"github.com/mihazs/oh-my-grok/internal/skillgate"
	"github.com/mihazs/oh-my-grok/internal/usingpowers"
	wsrules "github.com/mihazs/oh-my-grok/internal/workspace"
	"github.com/spf13/cobra"
)

func userPromptCmd() *cobra.Command {
	return &cobra.Command{
		Use: "user-prompt",
		RunE: func(cmd *cobra.Command, args []string) error {
			ev, err := readEvent()
			if err != nil {
				return err
			}
			hookenv.ApplyEvent(ev)
			sid := sessionID(ev)
			ws := workspace(ev)

			parts := []string{
				usingpowers.Collect(sid),
				wsrules.Collect(ws),
				ralph.CollectUserPrompt(ev),
				intentgate.Collect(ev),
				prometheus.CollectUserPrompt(ev),
				handoff.Collect(ev),
				boulder.CollectStopContinuation(ev),
				boulder.CollectPromptContext(ws, sid),
				lsp.CollectContext(sid),
				hashline.CollectContext(sid),
				skillgate.BuildReminder(sid),
			}
			merged := mergeNonEmpty(parts...)
			if merged == "" {
				return nil
			}
			hookio.EmitAdditionalContext(os.Stdout, merged, "UserPromptSubmit")
			return nil
		},
	}
}

func mergeNonEmpty(parts ...string) string {
	var merged string
	for _, part := range parts {
		part = strings.ReplaceAll(part, "\r", "")
		if strings.TrimSpace(part) == "" {
			continue
		}
		if merged != "" {
			merged += "\n\n" + part
		} else {
			merged = part
		}
	}
	return merged
}