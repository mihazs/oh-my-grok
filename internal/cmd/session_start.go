package cmd

import (
	"fmt"
	"os"
	"runtime"

	"github.com/mihazs/oh-my-grok/internal/hookenv"
	"github.com/mihazs/oh-my-grok/internal/hookio"
	"github.com/mihazs/oh-my-grok/internal/skillgate"
	"github.com/mihazs/oh-my-grok/internal/usingpowers"
	"github.com/spf13/cobra"
)

func sessionStartCmd() *cobra.Command {
	return &cobra.Command{
		Use: "session-start",
		RunE: func(cmd *cobra.Command, args []string) error {
			ev, err := readEvent()
			if err != nil {
				return err
			}
			hookenv.ApplyEvent(ev)
			sid := sessionID(ev)
			ws := workspace(ev)

			skillgate.ResetSession(sid)
			usingpowers.ResetSession(sid)
			skillgate.RefreshCatalog(sid, ws)

			if warn := hookBinaryDoctor(); warn != "" {
				fmt.Fprintln(os.Stderr, warn)
			}

			msg := skillgate.BuildSessionContextMessage(sid, 20)
			if msg != "" {
				hookio.EmitAdditionalContext(os.Stdout, msg, "SessionStart")
			}
			return nil
		},
	}
}

func hookBinaryDoctor() string {
	root, err := hookenv.PluginRoot()
	if err != nil {
		return ""
	}
	goos := runtime.GOOS
	goarch := runtime.GOARCH
	switch goarch {
	case "amd64":
	case "arm64":
	default:
		return fmt.Sprintf("omg-hook: unsupported arch %s — rebuild with scripts/build-hook.sh", goarch)
	}
	var name string
	switch goos {
	case "linux":
		name = fmt.Sprintf("omg-hook-linux-%s", goarch)
	case "darwin":
		name = fmt.Sprintf("omg-hook-darwin-%s", goarch)
	case "windows":
		name = "omg-hook-windows-amd64.exe"
	default:
		return fmt.Sprintf("omg-hook: unsupported OS %s", goos)
	}
	path := fmt.Sprintf("%s/bin/%s", root, name)
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Sprintf("omg-hook: missing or unreadable hook binary: %s (run scripts/build-hook.sh)", path)
	}
	if info.Mode()&0o111 == 0 {
		return fmt.Sprintf("omg-hook: hook binary not executable: %s (chmod +x)", path)
	}
	return ""
}