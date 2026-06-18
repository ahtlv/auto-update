# Changelog

## 0.1.0 — 2026-06-18
- Initial release: registry-driven environment checker with 6 component types
  (claude-plugin, git-repo, git-submodule, brew, pip-venv, custom), TSV report,
  discover + idempotent install, dependency-free block-format registry.
- install.sh: harden symlink resolution with a `readlink -f` fallback for
  macOS < Ventura (`_realpath` via `cd -P`).
- Add MIT LICENSE and .gitignore (ignores personal registry.conf, logs, secrets).
