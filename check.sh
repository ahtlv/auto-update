#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
# shellcheck disable=SC1091
source "$HERE/lib/registry.sh"
source "$HERE/lib/compare.sh"
source "$HERE/lib/checkers.sh"

FETCH=""
REGISTRY="${AU_REGISTRY:-$HOME/.claude/auto-update/registry.conf}"
while [ $# -gt 0 ]; do
  case "$1" in
    --fetch) FETCH="fetch" ;;
    --registry) shift; REGISTRY="$1" ;;
    *) printf 'unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

if [ ! -f "$REGISTRY" ]; then
  printf 'ERROR\t(registry)\t-\t\t\tnot found: %s\n' "$REGISTRY"
  exit 0
fi

# --fetch: refresh marketplace manifests once up front (state change, opt-in).
if [ "$FETCH" = "fetch" ] && command -v claude >/dev/null 2>&1; then
  claude plugin marketplace update --all >/dev/null 2>&1 || true
fi

# NOTE: bash 3.2 collapses consecutive IFS-whitespace (including tab) when
# splitting with 'read'. To preserve empty TAB-separated fields, extract each
# column individually with 'cut' instead of relying on IFS=$'\t' read -r.
while IFS= read -r _line; do
  [ -z "$_line" ] && continue
  name="$(        printf '%s' "$_line" | cut -f1)"
  type="$(        printf '%s' "$_line" | cut -f2)"
  path="$(        printf '%s' "$_line" | cut -f3)"
  parent="$(      printf '%s' "$_line" | cut -f4)"
  venv="$(        printf '%s' "$_line" | cut -f5)"
  marketplace="$( printf '%s' "$_line" | cut -f6)"
  post_update="$( printf '%s' "$_line" | cut -f7)"
  check="$(       printf '%s' "$_line" | cut -f8)"
  latest="$(      printf '%s' "$_line" | cut -f9)"
  update="$(      printf '%s' "$_line" | cut -f10)"
  [ -z "$name" ] && continue
  case "$type" in
    git-repo)       check_git_repo "$name" "$path" "$FETCH" ;;
    git-submodule)  check_git_submodule "$name" "$parent" "$path" "$FETCH" ;;
    claude-plugin)  check_claude_plugin "$name" "$marketplace" ;;
    brew)           check_brew "$name" ;;
    pip-venv)       check_pip_venv "$name" "$venv" ;;
    custom)         check_custom "$name" "$check" "$latest" ;;
    *)              printf 'ERROR\t%s\t%s\t\t\tunknown type\n' "$name" "$type" ;;
  esac
done < <(parse_registry "$REGISTRY")
