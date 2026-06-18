# auto-update

One command to check your whole Claude Code dev environment — plugins, MCP
servers, git repos & submodules, brew/pip/CLI tools — and update only what you pick.

## Install

```bash
git clone https://github.com/ahtlv/auto-update ~/Work/auto-update
cd ~/Work/auto-update && ./install.sh
```

Restart Claude Code, then say **"запусти автоапдейтер"** (or "update my environment").

## How it works

- Engine: `check.sh` + `lib/` (dependency-free bash; `jq` only for plugin checks).
- Your component list: `~/.claude/auto-update/registry.conf` (yours; never
  overwritten by updates). First run auto-discovers what's on your machine.
- Update the tool itself: `git -C ~/Work/auto-update pull` (or let auto-update do it).

## Add a component manually

Append a block to `~/.claude/auto-update/registry.conf` — see
`registry.example.conf` for every supported type.

## Requirements

bash, git. Optional: `jq` (plugin version checks), Homebrew/pip as needed.
