#!/usr/bin/env bash
# Per-type component checkers. Each prints ONE TSV line:
#   status<TAB>name<TAB>type<TAB>installed<TAB>latest<TAB>detail
# Requires lib/compare.sh (decide_status) to be sourced by the caller.

# Expand a leading ~ to $HOME (registry paths use ~).
_expand_tilde() { case "$1" in "~"*) printf '%s\n' "${1/#\~/$HOME}" ;; *) printf '%s\n' "$1" ;; esac; }

_emit() { # status name type installed latest detail
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6"
}

check_git_repo() { # NAME PATH [FETCH]
  local name="$1" path type="git-repo"
  path="$(_expand_tilde "$2")"
  local fetch="${3:-}"
  if [ ! -d "$path/.git" ] && ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    _emit SKIP "$name" "$type" "" "" "path not found: $path"; return 0
  fi
  [ "$fetch" = "fetch" ] && git -C "$path" fetch -q 2>/dev/null
  # Guard upstream: rev-parse @{u} exits non-zero if none / detached.
  if ! git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    local head; head="$(git -C "$path" rev-parse --short HEAD 2>/dev/null)"
    _emit INFO "$name" "$type" "$head" "" "no upstream configured"; return 0
  fi
  local behind head_sha up_sha subj
  behind="$(git -C "$path" rev-list --count 'HEAD..@{u}' 2>/dev/null)"
  head_sha="$(git -C "$path" rev-parse --short HEAD)"
  up_sha="$(git -C "$path" rev-parse --short '@{u}')"
  if [ "${behind:-0}" -gt 0 ]; then
    subj="$(git -C "$path" log --format='%s' -1 '@{u}' 2>/dev/null)"
    _emit OUTDATED "$name" "$type" "$head_sha" "$up_sha" "behind=$behind; latest: $subj"
  else
    _emit OK "$name" "$type" "$head_sha" "$up_sha" "up to date"
  fi
}
