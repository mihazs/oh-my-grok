# oh-my-grok

Grok plugin — hooks, skills, and rules for agent skill gate + continuation loops.

## For agents

- Read `README.md` for install and commands.
- Hook architecture: `hooks/README.md`.
- Workspace runtime state: `.omg/` in the project (boulder, ralph-loop, todos).

## Development

Edit under `hooks/`, `skills/`, `rules/`. Run tests from `hooks/` with `GROK_PLUGIN_ROOT` set to repo root (see README). Skills include `handoff` (`/handoff`, ported from omo).