# Installation

## Requirements

- [Grok Build CLI](https://github.com/xai-org/grok) with plugin support (`grok plugin install`, `grok plugin enable`)
- Network access to GitHub for `github:mihazs/oh-my-grok`

Hooks ship as prebuilt **`bin/omg-hook-*`** binaries (no Python required). Optional: **`grok`** for skill catalog refresh (`grok inspect --json`); **`node`** for LSP post-edit diagnostics when using the bundled LSP MCP.

## Install from GitHub

```bash
grok plugin install github:mihazs/oh-my-grok --trust
grok plugin enable oh-my-grok
```

Pinned to a release (see [Releases](https://github.com/mihazs/oh-my-grok/releases)):

```bash
grok plugin install github:mihazs/oh-my-grok@v0.1.0 --trust
grok plugin enable oh-my-grok
```

## Local development

```bash
git clone https://github.com/mihazs/oh-my-grok.git
cd oh-my-grok
grok plugin install "$(pwd)" --trust
grok plugin enable oh-my-grok
```

After hook or skill changes:

```bash
bash scripts/build-hook.sh   # maintainers: refresh bin/omg-hook-*
grok plugin update oh-my-grok
# or: grok plugin install "$(pwd)" --trust
```

Start a **new Grok session** or reload hooks in the TUI (`Ctrl+L` → Hooks). Hooks do not always hot-reload mid-session.

## Migrate from global copies

If you previously copied hooks or skills into `~/.grok/hooks/` or `~/.grok/rules/`:

```bash
bash scripts/remove-global-overlays.sh
grok plugin install github:mihazs/oh-my-grok --trust
grok plugin enable oh-my-grok
```

Removed files are archived under `~/.grok/archive/removed-global-oh-my-grok-<date>/`.

## Verify install

```bash
grok plugin validate .
grok inspect   # should list oh-my-grok skills
```

Hook smoke tests (from a clone):

```bash
export GROK_PLUGIN_ROOT="$(pwd)"
for t in hooks/test-*.sh; do
  case "$(basename "$t")" in test-inline-skill-gate.sh|test-support.sh) continue ;; esac
  bash "$t"
done
```