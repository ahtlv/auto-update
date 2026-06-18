#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
# shellcheck disable=SC1091
source "$HERE/lib/registry.sh"

REGISTRY="${AU_REGISTRY:-$HOME/.claude/auto-update/registry.conf}"
WORK="${AU_WORK:-$HOME/Work}"
while [ $# -gt 0 ]; do case "$1" in --registry) shift; REGISTRY="$1";; esac; shift; done

# Names already registered (column 1 of the parsed TSV).
known=""
[ -f "$REGISTRY" ] && known="$(parse_registry "$REGISTRY" | cut -f1)"
_is_known() { printf '%s\n' "$known" | grep -qxF "$1"; }

# git repos directly under WORK
if [ -d "$WORK" ]; then
  for d in "$WORK"/*/; do
    [ -d "$d/.git" ] || continue
    nm="$(basename "$d")"
    _is_known "$nm" || printf 'git-repo\t%s\t%s\n' "$nm" "$d"
  done
fi

# installed plugins (best-effort; needs claude + jq)
if command -v claude >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  claude plugin list --json 2>/dev/null \
    | jq -r '.[].id' 2>/dev/null \
    | while IFS= read -r id; do
        nm="${id%@*}"
        _is_known "$nm" || printf 'claude-plugin\t%s\t%s\n' "$nm" "$id"
      done
fi
