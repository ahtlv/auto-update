---
name: auto-update
description: Use when the user wants to check or update their dev environment — plugins, MCP servers, git repos/submodules, brew/pip/CLI tools. Triggers on "запусти автоапдейтер", "обнови окружение", "проверь обновления", "auto-update", "update my environment". Reports what's outdated with a short changelog, then updates only what the user picks.
---

# auto-update

Hybrid updater: a bash engine does deterministic version checks; you orchestrate
5 phases and do the research/decisions. The engine lives next to this file; the
user's component list is at `~/.claude/auto-update/registry.conf`.

Engine paths (resolve relative to this skill dir):
- `./check.sh [--fetch]` — prints TSV: `status⇥name⇥type⇥installed⇥latest⇥detail`
- `./discover.sh` — prints TSV: `type⇥name⇥hint` for components NOT in the registry

## Phase 1 — CHECK
Run `./check.sh --fetch`. (`--fetch` refreshes marketplace manifests; for a fast
offline pass drop it and tell the user results are only as fresh as the last fetch.)
Statuses: `OK` current · `OUTDATED` update available · `INFO` can't determine
(e.g. claude-cli) · `SKIP` not on this machine / missing dep · `ERROR` bad entry.

## Phase 2 — DISCOVER
Run `./discover.sh`. For each surfaced component, ask the user whether to add it.
On yes, APPEND a block to `~/.claude/auto-update/registry.conf` (blank line +
`key=value` lines). Never rewrite the file — only append.

## Phase 3 — RESEARCH (only for OUTDATED rows, "medium" depth)
For each outdated component, gather a one-line "what changed":
- git-repo/submodule: `git -C <path> log --oneline HEAD..@{u}` (repo) or the
  remote ref (submodule); summarize.
- claude-plugin / brew / pip / custom: use the version delta; if a CHANGELOG or
  release notes are readily available, skim for highlights.
Flag ⚠️ when it looks breaking (major version bump; "breaking"/"removed"/
"migration" in notes).

## Phase 4 — REPORT
Group by category. Collapse `OK` rows. Number the actionable (OUTDATED/INFO) rows.
Show: `name  installed → latest  ✦ what changed  [⚠️ if breaking]`.
Then ask: `Что обновляем? [всё / номера через запятую / только без ⚠️ / ничего]`.

## Phase 5 — APPLY (only the user's selection)
Per type:
- claude-plugin: `claude plugin marketplace update --all` then `claude plugin update <name>@<marketplace>` (note: restart required).
- git-repo: `git -C <path> pull`; then run `post_update` if set.
- git-submodule: `git -C <parent> submodule update --remote <path>`.
- brew: `brew upgrade <name>`.
- pip-venv: `<venv>/bin/pip install -U <name>`.
- custom: run the `update` command from the registry.
After applying, report what changed and note anything needing a Claude restart
(plugins, skills). For the `auto-update` self entry, a pull may change this skill —
tell the user to restart.

## Adding components automatically
Whenever you (in any session) install a new MCP/plugin or clone a skill repo,
append a matching block to `~/.claude/auto-update/registry.conf` so it's tracked.
