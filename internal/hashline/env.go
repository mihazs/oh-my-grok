package hashline

import "github.com/mihazs/oh-my-grok/internal/config"

// Enabled reports whether hashline guards are active (OMG_HASHLINE, default on).
func Enabled() bool {
	return config.HashlineEnabled()
}