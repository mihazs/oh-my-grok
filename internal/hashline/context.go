package hashline

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/mihazs/oh-my-grok/internal/config"
	"github.com/mihazs/oh-my-grok/internal/hookenv"
)

type cachePayload struct {
	RelPath string            `json:"rel_path"`
	Path    string            `json:"path"`
	Lines   map[string]string `json:"lines"`
}

// CollectContext returns hashline cache summary for UserPromptSubmit.
func CollectContext(sessionID string) string {
	if !config.HashlineEnabled() {
		return ""
	}
	if sessionID == "" {
		sessionID = "unknown"
	}
	cacheDir := filepath.Join(hookenv.GrokHome(), "state", "hashline", sessionID)
	entries, err := os.ReadDir(cacheDir)
	if err != nil {
		return ""
	}
	maxFiles := 5
	if v := strings.TrimSpace(os.Getenv("HASHLINE_CONTEXT_MAX_FILES")); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			maxFiles = n
		}
	}

	type item struct {
		mtime   int64
		rel     string
		samples []string
		total   int
	}
	var items []item

	for _, ent := range entries {
		if ent.IsDir() || !strings.HasSuffix(ent.Name(), ".json") {
			continue
		}
		b, err := os.ReadFile(filepath.Join(cacheDir, ent.Name()))
		if err != nil {
			continue
		}
		var data cachePayload
		if json.Unmarshal(b, &data) != nil || len(data.Lines) == 0 {
			continue
		}
		rel := data.RelPath
		if rel == "" {
			rel = data.Path
		}
		if rel == "" {
			rel = ent.Name()
		}
		var lineNos []int
		for k := range data.Lines {
			if n, err := strconv.Atoi(k); err == nil {
				lineNos = append(lineNos, n)
			}
		}
		sort.Ints(lineNos)
		var samples []string
		for _, n := range lineNos {
			samples = append(samples, strconv.Itoa(n)+"#"+data.Lines[strconv.Itoa(n)])
			if len(samples) >= 4 {
				break
			}
		}
		info, _ := ent.Info()
		var mtime int64
		if info != nil {
			mtime = info.ModTime().Unix()
		}
		items = append(items, item{mtime, rel, samples, len(data.Lines)})
	}
	if len(items) == 0 {
		return ""
	}
	sort.Slice(items, func(i, j int) bool { return items[i].mtime > items[j].mtime })
	if len(items) > maxFiles {
		items = items[:maxFiles]
	}

	var out []string
	out = append(out,
		"<HASHLINE_CACHE>",
		"Hash-anchored edits: copy LINE#ID tags from Read output; PreToolUse blocks stale tags.",
		"",
	)
	for _, it := range items {
		sampleText := strings.Join(it.samples, ", ")
		extra := ""
		if it.total > len(it.samples) {
			extra = " (+" + strconv.Itoa(it.total-len(it.samples)) + " more)"
		}
		out = append(out, "- "+it.rel+": "+sampleText+extra)
	}
	out = append(out, "", "Re-read a file before StrReplace if its content changed since cache.", "</HASHLINE_CACHE>")
	return strings.Join(out, "\n")
}