#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
SKILLS_DIR="$HOME/.claude/skills"
LINK="$SKILLS_DIR/auto-update"
CFG_DIR="$HOME/.claude/auto-update"
REG="$CFG_DIR/registry.conf"

# Resolve a path to its physical absolute form. Prefer `readlink -f`, but fall
# back to `cd -P` for macOS < Ventura whose stock readlink has no -f flag.
_realpath() {
  if readlink -f / >/dev/null 2>&1; then
    readlink -f "$1"
  elif [ -d "$1" ]; then
    (cd "$1" 2>/dev/null && pwd -P)
  else
    local d
    d="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)"
    printf '%s/%s\n' "$d" "$(basename "$1")"
  fi
}

mkdir -p "$SKILLS_DIR"

# 1. Idempotent symlink (never clobber a real dir or a different link).
if [ -L "$LINK" ]; then
  if [ "$(_realpath "$LINK")" = "$(_realpath "$REPO_DIR")" ]; then
    echo "OK: skill already linked"
  else
    echo "WARN: $LINK points elsewhere ($(readlink "$LINK")); leaving it untouched"
  fi
elif [ -e "$LINK" ]; then
  echo "WARN: $LINK exists and is not a symlink; leaving it untouched"
else
  ln -sfn "$REPO_DIR" "$LINK"
  echo "linked $LINK -> $REPO_DIR"
fi

# 2. If the link sits inside a git work tree, ignore it via .git/info/exclude.
GITROOT="$(git -C "$SKILLS_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$GITROOT" ]; then
  EXC="$GITROOT/.git/info/exclude"
  REL="${LINK#"$GITROOT"/}"
  if [ -d "$GITROOT/.git" ]; then
    grep -qxF "$REL" "$EXC" 2>/dev/null || printf '%s\n' "$REL" >> "$EXC"
    echo "ensured '$REL' in .git/info/exclude"
  fi
fi

# 3. Seed the personal registry from the template (only if absent).
mkdir -p "$CFG_DIR"
if [ ! -f "$REG" ]; then
  cp "$REPO_DIR/registry.example.conf" "$REG"
  echo "seeded $REG"
fi

# 4. Register auto-update itself for self-update (idempotent).
if ! grep -qxF 'name=auto-update' "$REG"; then
  printf '\nname=auto-update\ntype=git-repo\npath=%s\n' "$REPO_DIR" >> "$REG"
  echo "added self-update entry"
fi

echo "Done. Restart Claude Code, then say: запусти автоапдейтер"
