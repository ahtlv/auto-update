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

check_git_submodule() { # NAME PARENT SUBPATH [FETCH]
  local name="$1" parent type="git-submodule" subpath="$3" fetch="${4:-}"
  parent="$(_expand_tilde "$2")"
  local sub="$parent/$subpath"
  if [ ! -d "$parent/.git" ] && ! git -C "$parent" rev-parse --git-dir >/dev/null 2>&1; then
    _emit SKIP "$name" "$type" "" "" "parent not found: $parent"; return 0
  fi
  if ! git -C "$sub" rev-parse --git-dir >/dev/null 2>&1; then
    _emit SKIP "$name" "$type" "" "" "submodule not initialized: $subpath"; return 0
  fi
  [ "$fetch" = "fetch" ] && git -C "$sub" fetch -q 2>/dev/null
  local remote branch cfg target
  remote="$(git -C "$sub" remote | head -1)"; [ -z "$remote" ] && remote="origin"
  cfg="$(git -C "$parent" config -f "$parent/.gitmodules" "submodule.$name.branch" 2>/dev/null)"
  if [ -z "$cfg" ] || [ "$cfg" = "." ]; then
    target="$(git -C "$sub" symbolic-ref -q "refs/remotes/$remote/HEAD" 2>/dev/null | sed "s|refs/remotes/||")"
    [ -z "$target" ] && target="$remote/main"
  else
    target="$remote/$cfg"
  fi
  local behind head_sha
  head_sha="$(git -C "$sub" rev-parse --short HEAD 2>/dev/null)"
  behind="$(git -C "$sub" rev-list --count "HEAD..refs/remotes/$target" 2>/dev/null)"
  if [ "${behind:-0}" -gt 0 ]; then
    _emit OUTDATED "$name" "$type" "$head_sha" "$target" "behind=$behind on $target"
  else
    _emit OK "$name" "$type" "$head_sha" "$target" "up to date ($target)"
  fi
}

check_claude_plugin() { # NAME MARKETPLACE
  local name="$1" mkt="$2" type="claude-plugin"
  local pdir="${PLUGINS_DIR:-$HOME/.claude/plugins}"
  if ! command -v jq >/dev/null 2>&1; then
    _emit SKIP "$name" "$type" "" "" "jq required for plugin checks (brew install jq)"; return 0
  fi
  local inst="$pdir/installed_plugins.json"
  local mp="$pdir/marketplaces/$mkt/.claude-plugin/marketplace.json"
  local key="$name@$mkt"
  if [ ! -f "$inst" ]; then _emit SKIP "$name" "$type" "" "" "no installed_plugins.json"; return 0; fi
  local inst_ver inst_sha
  inst_ver="$(jq -r --arg k "$key" '.plugins[$k][0].version // ""' "$inst")"
  inst_sha="$(jq -r --arg k "$key" '.plugins[$k][0].gitCommitSha // ""' "$inst")"
  if [ -z "$inst_ver" ] && [ -z "$inst_sha" ]; then
    _emit SKIP "$name" "$type" "" "" "not installed from $mkt"; return 0
  fi
  if [ ! -f "$mp" ]; then _emit INFO "$name" "$type" "${inst_ver:-$inst_sha}" "" "marketplace manifest missing; run with --fetch"; return 0; fi
  local latest_ver latest_sha status installed latest
  latest_ver="$(jq -r --arg n "$name" '.plugins[]|select(.name==$n)|.version // ""' "$mp")"
  latest_sha="$(jq -r --arg n "$name" '.plugins[]|select(.name==$n)|.source.sha // ""' "$mp")"
  if [ -n "$latest_ver" ]; then
    installed="$inst_ver"; latest="$latest_ver"
  else
    installed="$inst_sha"; latest="$latest_sha"
  fi
  status="$(decide_status "$installed" "$latest")"
  _emit "$status" "$name" "$type" "$installed" "$latest" "marketplace=$mkt"
}
