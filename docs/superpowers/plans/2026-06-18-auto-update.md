# auto-update Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A distributable Claude Code skill that checks every component of a user's dev environment (plugins, MCP servers, git repos/submodules, brew/pip/CLI tools), reports what's outdated with a short changelog, and updates only what the user picks.

**Architecture:** Hybrid. A dependency-free bash engine (`check.sh` + `lib/*.sh`) does deterministic version comparison and emits TSV; the `SKILL.md` orchestrates 5 phases (CHECK → DISCOVER → RESEARCH → REPORT → APPLY) on top of it. The engine ships in a public repo (`~/Work/auto-update`); each user's component registry lives separately in `~/.claude/auto-update/registry.conf` so engine updates never clobber it. `install.sh` symlinks the skill into `~/.claude/skills/` idempotently.

**Tech Stack:** POSIX/bash 3.2 shell, BSD awk, git, jq (only for the `claude-plugin` type; degrades gracefully if absent). Tests: a homegrown zero-dependency bash test runner.

## Global Constraints

Every task's requirements implicitly include these. Values are verified against the target machine.

- **bash 3.2.57 compatible** — macOS stock `/bin/bash`. NO associative arrays, NO `mapfile`/`readarray`, NO bash-4 features. Use `while IFS=... read` with process substitution `< <(...)` (works in 3.2).
- **BSD awk compatible** — `/usr/bin/awk` is one-true-awk (20200816), NOT gawk. Use only `index()`, `substr()`, `gsub()`, `sub()`, `split()`, `printf`, `[[:space:]]`. Clear arrays with `split("",arr)`.
- **Zero hard dependencies except jq-for-plugins.** Only the `claude-plugin` checker needs `jq`; if `jq` is absent, that checker emits `SKIP` with a note — the rest of the engine must still run.
- **Read-only by default.** `check.sh` never mutates state unless given `--fetch` (which may run `claude plugin marketplace update`, `git fetch`, `brew update`). APPLY is the only place that updates components.
- **Never destroy user data.** `install.sh` never overwrites an existing non-symlink or a symlink pointing elsewhere — it warns. Use `ln -sfn` and compare with `readlink -f`.
- **Shell gotchas (verified):** `npm` is aliased to `pnpm` → always use `command npm`. `agent-browser` is only on PATH under `~/.nvm/versions/node/*/bin` (version hardcoded by nvm) → glob it, never hardcode the node version. `brew outdated` must run with `HOMEBREW_NO_AUTO_UPDATE=1` in CHECK. Under `set -e`, guard `brew outdated <names>` with `|| true` (exits 1 when something is outdated).
- **Registry format:** dependency-free block format — one component per block of `key=value` lines, blocks separated by a blank line, `#` comments allowed, split on the FIRST `=` only. NOT YAML. (Deviation from spec §"Схема registry.yaml" — justified by `yq` being absent; see Task 2.)
- **Component types:** `claude-plugin`, `git-repo`, `git-submodule`, `brew`, `pip-venv`, `custom`. The `custom` type carries optional `latest` (a command that prints the latest version) so a single type covers `agent-browser` (compare installed vs npm) and `claude-cli` (installed only, no remote check).
- **Checker contract:** every `check_<type>` function prints exactly ONE TSV line to stdout: `status<TAB>name<TAB>type<TAB>installed<TAB>latest<TAB>detail`, where `status ∈ {OK, OUTDATED, SKIP, INFO, ERROR}`. This uniform contract is what `check.sh` dispatches to and what tests assert on.

---

## File Structure

```
~/Work/auto-update/                  # public repo (engine), clone target
├── SKILL.md                         # Claude orchestration: 5 phases
├── check.sh                         # entrypoint: parse registry, dispatch, emit TSV
├── discover.sh                      # list candidate components not in the registry
├── install.sh                       # idempotent bootstrap (symlink + registry seed)
├── lib/
│   ├── registry.sh                  # parse_registry(): block format → fixed-column TSV
│   ├── compare.sh                   # decide_status(): version/sha equality → OK/OUTDATED
│   └── checkers.sh                  # check_git_repo / _git_submodule / _claude_plugin / _brew / _pip_venv / _custom
├── registry.example.conf            # template: commented example of every type
├── VERSION                          # semver, e.g. 0.1.0
├── CHANGELOG.md
├── README.md                        # install + usage for students
└── tests/
    ├── lib.sh                       # assert_eq / assert_contains / test_summary
    ├── run.sh                       # sources every tests/test_*.sh, prints summary
    ├── test_registry.sh
    ├── test_compare.sh
    ├── test_git_repo.sh
    ├── test_git_submodule.sh
    ├── test_claude_plugin.sh
    ├── test_brew.sh
    ├── test_pip_venv.sh
    ├── test_custom.sh
    ├── test_check.sh
    └── test_install.sh
```

User-side (created by `install.sh`, never in the repo):
```
~/.claude/auto-update/registry.conf  # personal component list
~/.claude/skills/auto-update         # symlink → ~/Work/auto-update
```

**Responsibilities:** `lib/registry.sh` only parses. `lib/compare.sh` only decides outdated/current from two version-ish strings. `lib/checkers.sh` holds one focused function per component type, each obeying the checker contract. `check.sh` wires registry → dispatch → TSV and owns `--fetch`. `discover.sh` is independent (finds unregistered components). `install.sh` is independent (bootstrap). `SKILL.md` is the human/Claude-facing orchestration that calls these scripts.

---

## Task 1: Project skeleton + zero-dependency test runner

**Files:**
- Create: `~/Work/auto-update/VERSION`
- Create: `~/Work/auto-update/tests/lib.sh`
- Create: `~/Work/auto-update/tests/run.sh`
- Create: `~/Work/auto-update/tests/test_smoke.sh`

**Interfaces:**
- Produces: `assert_eq EXPECTED ACTUAL MSG`, `assert_contains HAYSTACK NEEDLE MSG`, `test_summary` (exit 0 iff no failures). Test files are sourced by `run.sh` into one process; they run asserts at source time and may `source` libs under test. Counters `_T_RUN`/`_T_FAIL` are shared globals.

- [ ] **Step 1: Create the repo directory and VERSION**

```bash
mkdir -p ~/Work/auto-update/lib ~/Work/auto-update/tests
printf '0.1.0\n' > ~/Work/auto-update/VERSION
cd ~/Work/auto-update && git init -q
```

- [ ] **Step 2: Write the test runner library** `tests/lib.sh`

```bash
#!/usr/bin/env bash
# Minimal test helpers — zero deps, bash 3.2 compatible.
_T_RUN=0
_T_FAIL=0

assert_eq() { # expected actual message
  _T_RUN=$((_T_RUN + 1))
  if [ "$1" = "$2" ]; then
    printf 'ok   - %s\n' "$3"
  else
    _T_FAIL=$((_T_FAIL + 1))
    printf 'FAIL - %s\n      expected: [%s]\n      actual:   [%s]\n' "$3" "$1" "$2"
  fi
}

assert_contains() { # haystack needle message
  _T_RUN=$((_T_RUN + 1))
  case "$1" in
    *"$2"*) printf 'ok   - %s\n' "$3" ;;
    *) _T_FAIL=$((_T_FAIL + 1))
       printf 'FAIL - %s\n      [%s]\n      does not contain [%s]\n' "$3" "$1" "$2" ;;
  esac
}

test_summary() {
  printf '\n%d tests, %d failures\n' "$_T_RUN" "$_T_FAIL"
  [ "$_T_FAIL" -eq 0 ]
}
```

- [ ] **Step 3: Write the runner** `tests/run.sh`

```bash
#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
# shellcheck disable=SC1091
source ./lib.sh
for t in test_*.sh; do
  [ -e "$t" ] || continue
  printf '\n## %s\n' "$t"
  # shellcheck disable=SC1090
  source "./$t"
done
test_summary
```

- [ ] **Step 4: Write the failing smoke test** `tests/test_smoke.sh`

```bash
# Proves the runner itself works.
assert_eq "hello" "hello" "runner: equal strings pass"
assert_contains "abcdef" "cde" "runner: substring match"
```

- [ ] **Step 5: Run the tests, verify they pass**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: ends with `2 tests, 0 failures`, exit code 0.

- [ ] **Step 6: Commit**

```bash
cd ~/Work/auto-update
git add VERSION tests/
git commit -m "chore: project skeleton + bash test runner"
```

---

## Task 2: Registry parser (`lib/registry.sh`)

The block format and this awk approach were tested during research (yq absent, BSD awk, bash 3.2).

**Files:**
- Create: `~/Work/auto-update/lib/registry.sh`
- Test: `~/Work/auto-update/tests/test_registry.sh`

**Interfaces:**
- Produces: `parse_registry FILE` → prints one TSV line per component with FIXED 11-column order: `name  type  path  parent  venv  marketplace  post_update  check  latest  update  hosts` (missing fields empty). Splits on first `=`, skips blank lines and `#` comments, strips trailing `\r`. Consumed by `check.sh` via `while IFS=$'\t' read -r ...`.

- [ ] **Step 1: Write the failing test** `tests/test_registry.sh`

```bash
source ../lib/registry.sh

reg="$(mktemp)"
cat > "$reg" <<'EOF'
# a plugin
name=superpowers
type=claude-plugin
marketplace=claude-plugins-official

name=telegram-mcp
type=git-repo
path=~/Work/telegram-mcp
post_update=uv sync

# a custom tool with an = inside the value
name=agent-browser
type=custom
check=ab --version | awk '{print $NF}'
latest=command npm view agent-browser version
update=command npm install -g agent-browser@latest
EOF

out="$(parse_registry "$reg")"

line1="$(printf '%s\n' "$out" | sed -n 1p)"
line2="$(printf '%s\n' "$out" | sed -n 2p)"
line3="$(printf '%s\n' "$out" | sed -n 3p)"

assert_eq "3" "$(printf '%s\n' "$out" | grep -c .)" "registry: 3 components parsed"
assert_eq "superpowers" "$(printf '%s' "$line1" | cut -f1)" "registry: name col"
assert_eq "claude-plugin" "$(printf '%s' "$line1" | cut -f2)" "registry: type col"
assert_eq "claude-plugins-official" "$(printf '%s' "$line1" | cut -f6)" "registry: marketplace col"
assert_eq "uv sync" "$(printf '%s' "$line2" | cut -f7)" "registry: post_update col"
# value containing a pipe and an embedded '=' (in @latest) must survive
assert_contains "$line3" "command npm view agent-browser version" "registry: latest col keeps spaces"
assert_eq "ab --version | awk '{print \$NF}'" "$(printf '%s' "$line3" | cut -f8)" "registry: check col keeps pipe"
rm -f "$reg"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: FAIL lines for `test_registry.sh` (parse_registry not defined / no output).

- [ ] **Step 3: Write the implementation** `lib/registry.sh`

```bash
#!/usr/bin/env bash
# Parse the block-format component registry into fixed-column TSV.
# One component per blank-line-delimited block of key=value lines.

parse_registry() { # FILE
  awk '
    function flush() {
      if (seen) {
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
          f["name"], f["type"], f["path"], f["parent"], f["venv"],
          f["marketplace"], f["post_update"], f["check"], f["latest"],
          f["update"], f["hosts"]
      }
      split("", f); seen = 0
    }
    { sub(/\r$/, "") }                 # CRLF tolerance
    /^[[:space:]]*$/  { flush(); next }# blank line ends a block
    /^[[:space:]]*#/  { next }         # comment
    {
      e = index($0, "=")
      if (e == 0) next                 # not a key=value line
      k = substr($0, 1, e - 1)
      v = substr($0, e + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)   # trim key only
      f[k] = v
      seen = 1
    }
    END { flush() }
  ' "$1"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: all `test_registry.sh` asserts `ok`.

- [ ] **Step 5: Commit**

```bash
cd ~/Work/auto-update
git add lib/registry.sh tests/test_registry.sh
git commit -m "feat: dependency-free block-format registry parser"
```

---

## Task 3: Status decision helper (`lib/compare.sh`)

**Files:**
- Create: `~/Work/auto-update/lib/compare.sh`
- Test: `~/Work/auto-update/tests/test_compare.sh`

**Interfaces:**
- Produces: `decide_status INSTALLED LATEST` → prints `OK` if equal (and both non-empty), `OUTDATED` if both non-empty and differ, `INFO` if `LATEST` is empty (cannot determine). Equality is plain string compare (sufficient for an outdated yes/no — verified in research). Consumed by every checker.

- [ ] **Step 1: Write the failing test** `tests/test_compare.sh`

```bash
source ../lib/compare.sh

assert_eq "OK"       "$(decide_status 6.0.2 6.0.2)" "compare: equal -> OK"
assert_eq "OUTDATED" "$(decide_status 6.0.2 6.1.0)" "compare: differ -> OUTDATED"
assert_eq "OUTDATED" "$(decide_status b62616f abcdef0)" "compare: sha differ -> OUTDATED"
assert_eq "INFO"     "$(decide_status 2.1.139 '')"  "compare: no latest -> INFO"
assert_eq "INFO"     "$(decide_status '' '')"       "compare: nothing -> INFO"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: FAIL (`decide_status` not defined).

- [ ] **Step 3: Write the implementation** `lib/compare.sh`

```bash
#!/usr/bin/env bash
# Decide OK / OUTDATED / INFO from an installed and a latest version-ish string.

decide_status() { # INSTALLED LATEST
  local installed="$1" latest="$2"
  if [ -z "$latest" ]; then
    printf 'INFO\n'
  elif [ "$installed" = "$latest" ]; then
    printf 'OK\n'
  else
    printf 'OUTDATED\n'
  fi
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: all `test_compare.sh` asserts `ok`.

- [ ] **Step 5: Commit**

```bash
cd ~/Work/auto-update
git add lib/compare.sh tests/test_compare.sh
git commit -m "feat: version/sha status decision helper"
```

---

## Task 4: Checker — git-repo (`lib/checkers.sh`)

**Files:**
- Create: `~/Work/auto-update/lib/checkers.sh`
- Test: `~/Work/auto-update/tests/test_git_repo.sh`

**Interfaces:**
- Consumes: `decide_status` from `lib/compare.sh`.
- Produces: `check_git_repo NAME PATH [FETCH]` → one TSV line per the checker contract. Resolves leading `~`. If PATH missing → `SKIP`. Guards `@{u}` (no upstream → `INFO`). `behind=git rev-list --count HEAD..@{u}`; `installed`/`latest` columns carry the short SHAs of HEAD and upstream; `detail` carries `behind=N` plus the first incoming commit subject. If `FETCH=fetch`, runs `git fetch -q` first.

- [ ] **Step 1: Write the failing test** `tests/test_git_repo.sh`

```bash
source ../lib/compare.sh
source ../lib/checkers.sh

# Build a real upstream + clone, then advance upstream so the clone is "behind".
tmp="$(mktemp -d)"
( cd "$tmp" && git init -q up && cd up \
    && git config user.email t@t && git config user.name t \
    && echo a > f && git add f && git commit -qm a )
git clone -q "$tmp/up" "$tmp/clone"
( cd "$tmp/up" && echo b >> f && git commit -qam "second change" )
# clone hasn't fetched yet -> behind 0 against cached ref
line_before="$(check_git_repo demo "$tmp/clone")"
assert_eq "OK" "$(printf '%s' "$line_before" | cut -f1)" "git-repo: stale cache shows OK before fetch"
# with fetch, the new upstream commit is visible -> OUTDATED, behind=1
line_after="$(check_git_repo demo "$tmp/clone" fetch)"
assert_eq "OUTDATED" "$(printf '%s' "$line_after" | cut -f1)" "git-repo: fetch reveals OUTDATED"
assert_contains "$line_after" "behind=1" "git-repo: detail reports behind=1"
assert_contains "$line_after" "second change" "git-repo: detail includes incoming subject"

# Missing path -> SKIP
miss="$(check_git_repo ghost "$tmp/does-not-exist")"
assert_eq "SKIP" "$(printf '%s' "$miss" | cut -f1)" "git-repo: missing path -> SKIP"

# Repo with no upstream -> INFO
( cd "$tmp" && git init -q noup && cd noup && git config user.email t@t \
    && git config user.name t && echo x > y && git add y && git commit -qm x )
noup="$(check_git_repo solo "$tmp/noup")"
assert_eq "INFO" "$(printf '%s' "$noup" | cut -f1)" "git-repo: no upstream -> INFO"
rm -rf "$tmp"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: FAIL (`check_git_repo` not defined).

- [ ] **Step 3: Write the implementation** (start `lib/checkers.sh`)

```bash
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: all `test_git_repo.sh` asserts `ok`.

- [ ] **Step 5: Commit**

```bash
cd ~/Work/auto-update
git add lib/checkers.sh tests/test_git_repo.sh
git commit -m "feat: git-repo checker with upstream guard and --fetch"
```

---

## Task 5: Checker — git-submodule

**Files:**
- Modify: `~/Work/auto-update/lib/checkers.sh` (append `check_git_submodule`)
- Test: `~/Work/auto-update/tests/test_git_submodule.sh`

**Interfaces:**
- Produces: `check_git_submodule NAME PARENT SUBPATH [FETCH]` → checker-contract TSV line. Does NOT use `@{u}` inside the submodule (detached HEAD breaks it — verified). Resolves the tracked branch (`.gitmodules` `branch` key, else `refs/remotes/origin/HEAD`, else `origin/main`), then `behind=git rev-list --count HEAD..refs/remotes/<remote>/<branch>` inside the submodule. `OUTDATED` when behind>0.

- [ ] **Step 1: Write the failing test** `tests/test_git_submodule.sh`

```bash
source ../lib/compare.sh
source ../lib/checkers.sh

tmp="$(mktemp -d)"
export GIT_ALLOW_PROTOCOL=file
# submodule origin with 2 commits
( cd "$tmp" && git init -q suborigin && cd suborigin \
    && git config user.email t@t && git config user.name t \
    && echo 1 > s && git add s && git commit -qm s1 \
    && echo 2 >> s && git commit -qm "sub second" )
# parent that embeds the submodule at its FIRST commit
( cd "$tmp" && git init -q parent && cd parent \
    && git config user.email t@t && git config user.name t \
    && git -c protocol.file.allow=always submodule add -q "$tmp/suborigin" sub \
    && ( cd sub && git checkout -q HEAD~1 ) \
    && git add sub && git commit -qm "pin sub to first commit" )

# The submodule's checked-out HEAD is 1 behind origin/main (or origin/master).
line="$(check_git_submodule mysub "$tmp/parent" sub)"
assert_eq "OUTDATED" "$(printf '%s' "$line" | cut -f1)" "submodule: behind remote -> OUTDATED"
assert_contains "$line" "behind=1" "submodule: detail reports behind=1"

# Missing parent -> SKIP
miss="$(check_git_submodule x "$tmp/nope" sub)"
assert_eq "SKIP" "$(printf '%s' "$miss" | cut -f1)" "submodule: missing parent -> SKIP"
rm -rf "$tmp"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: FAIL (`check_git_submodule` not defined).

- [ ] **Step 3: Append the implementation** to `lib/checkers.sh`

```bash
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: all `test_git_submodule.sh` asserts `ok`.

- [ ] **Step 5: Commit**

```bash
cd ~/Work/auto-update
git add lib/checkers.sh tests/test_git_submodule.sh
git commit -m "feat: git-submodule checker (remote-branch ref compare)"
```

---

## Task 6: Checker — claude-plugin (jq, with graceful skip)

**Files:**
- Modify: `~/Work/auto-update/lib/checkers.sh` (append `check_claude_plugin`)
- Test: `~/Work/auto-update/tests/test_claude_plugin.sh`

**Interfaces:**
- Produces: `check_claude_plugin NAME MARKETPLACE` → checker-contract TSV. Reads `$PLUGINS_DIR` (default `~/.claude/plugins`). Installed from `installed_plugins.json` (`.plugins["NAME@MKT"][0].version` + `.gitCommitSha`); latest from `marketplaces/MKT/.claude-plugin/marketplace.json` (`.plugins[]|select(.name==NAME)` → `.version` else `.source.sha`). If `.version` present → compare versions; else compare gitCommitSha vs source.sha. If `jq` absent → `SKIP`.

- [ ] **Step 1: Write the failing test** `tests/test_claude_plugin.sh`

```bash
source ../lib/compare.sh
source ../lib/checkers.sh

if ! command -v jq >/dev/null 2>&1; then
  echo "ok   - claude-plugin: jq not present, skipping detailed test (engine must SKIP)"
else
  tmp="$(mktemp -d)"
  export PLUGINS_DIR="$tmp"
  mkdir -p "$tmp" "$tmp/marketplaces/mkt-ver/.claude-plugin" "$tmp/marketplaces/mkt-sha/.claude-plugin"

  cat > "$tmp/installed_plugins.json" <<'EOF'
{ "version": 2, "plugins": {
  "vplug@mkt-ver": [{ "scope":"user","version":"1.0.0","gitCommitSha":"" }],
  "splug@mkt-sha": [{ "scope":"user","version":"6.0.2","gitCommitSha":"b62616f" }]
}}
EOF
  # version-pinned marketplace, newer version available
  cat > "$tmp/marketplaces/mkt-ver/.claude-plugin/marketplace.json" <<'EOF'
{ "plugins": [ { "name":"vplug", "version":"1.2.0" } ] }
EOF
  # sha-pinned marketplace, same sha => up to date
  cat > "$tmp/marketplaces/mkt-sha/.claude-plugin/marketplace.json" <<'EOF'
{ "plugins": [ { "name":"splug", "source": { "sha":"b62616f" } } ] }
EOF

  lv="$(check_claude_plugin vplug mkt-ver)"
  assert_eq "OUTDATED" "$(printf '%s' "$lv" | cut -f1)" "plugin: version pin newer -> OUTDATED"
  assert_eq "1.2.0" "$(printf '%s' "$lv" | cut -f5)" "plugin: latest version reported"

  ls_="$(check_claude_plugin splug mkt-sha)"
  assert_eq "OK" "$(printf '%s' "$ls_" | cut -f1)" "plugin: matching sha -> OK"

  miss="$(check_claude_plugin ghost mkt-ver)"
  assert_eq "SKIP" "$(printf '%s' "$miss" | cut -f1)" "plugin: not installed -> SKIP"
  unset PLUGINS_DIR
  rm -rf "$tmp"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: FAIL (`check_claude_plugin` not defined) — or the jq-absent branch logs `ok` (then implement so the `SKIP` path exists).

- [ ] **Step 3: Append the implementation** to `lib/checkers.sh`

```bash
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: all `test_claude_plugin.sh` asserts `ok` (or jq-absent skip line).

- [ ] **Step 5: Commit**

```bash
cd ~/Work/auto-update
git add lib/checkers.sh tests/test_claude_plugin.sh
git commit -m "feat: claude-plugin checker (version+sha pins, jq graceful skip)"
```

---

## Task 7: Checker — brew

**Files:**
- Modify: `~/Work/auto-update/lib/checkers.sh` (append `check_brew`)
- Test: `~/Work/auto-update/tests/test_brew.sh`

**Interfaces:**
- Produces: `check_brew NAME` (NAME = formula) → checker-contract TSV. Runs `HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --formula --verbose NAME` (guarded `|| true`). Parses `name (installed) < latest`. No output for that formula → `OK`. `brew` missing → `SKIP`. Tests stub `brew` on PATH.

- [ ] **Step 1: Write the failing test** `tests/test_brew.sh`

```bash
source ../lib/compare.sh
source ../lib/checkers.sh

stub="$(mktemp -d)"
cat > "$stub/brew" <<'EOF'
#!/usr/bin/env bash
# stub: only knows ffmpeg is outdated
for a in "$@"; do case "$a" in ffmpeg) echo "ffmpeg (8.1.1) < 8.1.2"; exit 1;; esac; done
exit 0
EOF
chmod +x "$stub/brew"
OLDPATH="$PATH"; export PATH="$stub:$PATH"

out="$(check_brew ffmpeg)"
assert_eq "OUTDATED" "$(printf '%s' "$out" | cut -f1)" "brew: outdated formula -> OUTDATED"
assert_eq "8.1.1" "$(printf '%s' "$out" | cut -f4)" "brew: installed version parsed"
assert_eq "8.1.2" "$(printf '%s' "$out" | cut -f5)" "brew: latest version parsed"

cur="$(check_brew uv)"
assert_eq "OK" "$(printf '%s' "$cur" | cut -f1)" "brew: current formula -> OK"

export PATH="$OLDPATH"; rm -rf "$stub"
# brew missing -> SKIP
miss="$(PATH=/usr/bin:/bin check_brew ffmpeg)"
assert_eq "SKIP" "$(printf '%s' "$miss" | cut -f1)" "brew: brew absent -> SKIP"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: FAIL (`check_brew` not defined).

- [ ] **Step 3: Append the implementation** to `lib/checkers.sh`

```bash
check_brew() { # NAME (formula)
  local name="$1" type="brew"
  if ! command -v brew >/dev/null 2>&1; then
    _emit SKIP "$name" "$type" "" "" "brew not installed"; return 0
  fi
  local out
  out="$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --formula --verbose "$name" 2>/dev/null || true)"
  if [ -z "$out" ]; then
    _emit OK "$name" "$type" "" "" "up to date"; return 0
  fi
  # format: "name (installed) < latest"
  local installed latest
  installed="$(printf '%s\n' "$out" | sed -n "s/^$name (\([^)]*\)).*/\1/p" | head -1)"
  latest="$(printf '%s\n' "$out" | sed -n 's/.*< *\([^ ]*\).*/\1/p' | head -1)"
  _emit OUTDATED "$name" "$type" "$installed" "$latest" "brew formula"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: all `test_brew.sh` asserts `ok`.

- [ ] **Step 5: Commit**

```bash
cd ~/Work/auto-update
git add lib/checkers.sh tests/test_brew.sh
git commit -m "feat: brew checker (NO_AUTO_UPDATE, verbose parse)"
```

---

## Task 8: Checker — pip-venv

**Files:**
- Modify: `~/Work/auto-update/lib/checkers.sh` (append `check_pip_venv`)
- Test: `~/Work/auto-update/tests/test_pip_venv.sh`

**Interfaces:**
- Produces: `check_pip_venv NAME VENV` → checker-contract TSV. Runs `<venv>/bin/pip list --outdated` (stderr discarded — pip self-warning). Package present in list → `OUTDATED` with installed/latest from columns; absent → `OK`. `<venv>/bin/pip` missing → `SKIP`. Tests stub the pip path.

- [ ] **Step 1: Write the failing test** `tests/test_pip_venv.sh`

```bash
source ../lib/compare.sh
source ../lib/checkers.sh

venv="$(mktemp -d)"; mkdir -p "$venv/bin"
cat > "$venv/bin/pip" <<'EOF'
#!/usr/bin/env bash
echo "WARNING: old pip" >&2
cat <<TABLE
Package    Version Latest Type
---------- ------- ------ -----
tiktoken   0.12.0  0.13.0 wheel
TABLE
EOF
chmod +x "$venv/bin/pip"

out="$(check_pip_venv tiktoken "$venv")"
assert_eq "OUTDATED" "$(printf '%s' "$out" | cut -f1)" "pip: listed package -> OUTDATED"
assert_eq "0.12.0" "$(printf '%s' "$out" | cut -f4)" "pip: installed parsed"
assert_eq "0.13.0" "$(printf '%s' "$out" | cut -f5)" "pip: latest parsed"

cur="$(check_pip_venv mlx_whisper "$venv")"
assert_eq "OK" "$(printf '%s' "$cur" | cut -f1)" "pip: absent from outdated -> OK"

miss="$(check_pip_venv tiktoken "$venv/nope")"
assert_eq "SKIP" "$(printf '%s' "$miss" | cut -f1)" "pip: missing venv -> SKIP"
rm -rf "$venv"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: FAIL (`check_pip_venv` not defined).

- [ ] **Step 3: Append the implementation** to `lib/checkers.sh`

```bash
check_pip_venv() { # NAME VENV
  local name="$1" type="pip-venv" venv
  venv="$(_expand_tilde "$2")"
  local pip="$venv/bin/pip"
  if [ ! -x "$pip" ]; then
    _emit SKIP "$name" "$type" "" "" "venv pip not found: $pip"; return 0
  fi
  local row
  row="$("$pip" list --outdated 2>/dev/null | awk -v n="$name" '$1==n {print; exit}')"
  if [ -z "$row" ]; then
    _emit OK "$name" "$type" "" "" "up to date"; return 0
  fi
  local installed latest
  installed="$(printf '%s\n' "$row" | awk '{print $2}')"
  latest="$(printf '%s\n' "$row" | awk '{print $3}')"
  _emit OUTDATED "$name" "$type" "$installed" "$latest" "pip in $venv"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: all `test_pip_venv.sh` asserts `ok`.

- [ ] **Step 5: Commit**

```bash
cd ~/Work/auto-update
git add lib/checkers.sh tests/test_pip_venv.sh
git commit -m "feat: pip-venv checker (list --outdated parse)"
```

---

## Task 9: Checker — custom (covers agent-browser & claude-cli)

**Files:**
- Modify: `~/Work/auto-update/lib/checkers.sh` (append `check_custom`)
- Test: `~/Work/auto-update/tests/test_custom.sh`

**Interfaces:**
- Produces: `check_custom NAME CHECKCMD LATESTCMD` → checker-contract TSV. `installed=eval CHECKCMD`. If `LATESTCMD` non-empty → `latest=eval LATESTCMD`, status via `decide_status`. Else → `INFO` (installed only; e.g. claude-cli has no read-only latest check). `CHECKCMD` empty → `SKIP`. (The `update` command is applied only in APPLY, not here.)

- [ ] **Step 1: Write the failing test** `tests/test_custom.sh`

```bash
source ../lib/compare.sh
source ../lib/checkers.sh

out="$(check_custom agent-browser "echo 0.27.0" "echo 0.28.0")"
assert_eq "OUTDATED" "$(printf '%s' "$out" | cut -f1)" "custom: installed<latest -> OUTDATED"
assert_eq "0.27.0" "$(printf '%s' "$out" | cut -f4)" "custom: installed via eval"
assert_eq "0.28.0" "$(printf '%s' "$out" | cut -f5)" "custom: latest via eval"

same="$(check_custom tool "echo 1.0" "echo 1.0")"
assert_eq "OK" "$(printf '%s' "$same" | cut -f1)" "custom: equal -> OK"

info="$(check_custom claude-cli "echo 2.1.139" "")"
assert_eq "INFO" "$(printf '%s' "$info" | cut -f1)" "custom: no latest cmd -> INFO"
assert_eq "2.1.139" "$(printf '%s' "$info" | cut -f4)" "custom: installed reported on INFO"

skip="$(check_custom broken "" "")"
assert_eq "SKIP" "$(printf '%s' "$skip" | cut -f1)" "custom: no check cmd -> SKIP"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: FAIL (`check_custom` not defined).

- [ ] **Step 3: Append the implementation** to `lib/checkers.sh`

```bash
check_custom() { # NAME CHECKCMD LATESTCMD
  local name="$1" type="custom" checkcmd="$2" latestcmd="$3"
  if [ -z "$checkcmd" ]; then
    _emit SKIP "$name" "$type" "" "" "no check command"; return 0
  fi
  local installed latest status
  installed="$(eval "$checkcmd" 2>/dev/null)"
  if [ -z "$latestcmd" ]; then
    _emit INFO "$name" "$type" "$installed" "" "no remote check; update applies blindly"; return 0
  fi
  latest="$(eval "$latestcmd" 2>/dev/null)"
  status="$(decide_status "$installed" "$latest")"
  _emit "$status" "$name" "$type" "$installed" "$latest" "custom"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: all `test_custom.sh` asserts `ok`.

- [ ] **Step 5: Commit**

```bash
cd ~/Work/auto-update
git add lib/checkers.sh tests/test_custom.sh
git commit -m "feat: custom checker with optional latest command"
```

---

## Task 10: Entrypoint `check.sh` (dispatch + TSV + --fetch)

**Files:**
- Create: `~/Work/auto-update/check.sh`
- Test: `~/Work/auto-update/tests/test_check.sh`

**Interfaces:**
- Consumes: `parse_registry`, `decide_status`, all `check_*`.
- Produces: `check.sh [--fetch] [--registry FILE]` → reads the registry (default `~/.claude/auto-update/registry.conf`, override via `--registry` or `$AU_REGISTRY`), dispatches each component to its checker, prints all checker TSV lines to stdout. `--fetch` is forwarded to git checkers and (later) triggers marketplace/brew refresh. Unknown type → `ERROR` line. Used by `SKILL.md`.

- [ ] **Step 1: Write the failing test** `tests/test_check.sh`

```bash
tmp="$(mktemp -d)"
reg="$tmp/registry.conf"
# a git-repo (real, up to date) + a custom (outdated) + an unknown type
( cd "$tmp" && git init -q r && cd r && git config user.email t@t \
    && git config user.name t && echo a>f && git add f && git commit -qm a )
cat > "$reg" <<EOF
name=myrepo
type=git-repo
path=$tmp/r

name=mytool
type=custom
check=echo 1.0
latest=echo 2.0
update=echo updating

name=weird
type=frobnicate
EOF

out="$(AU_REGISTRY="$reg" bash ../check.sh)"
assert_contains "$out" "myrepo" "check: includes git-repo row"
assert_eq "OUTDATED" "$(printf '%s\n' "$out" | awk -F'\t' '$2=="mytool"{print $1}')" "check: custom row OUTDATED"
assert_eq "ERROR" "$(printf '%s\n' "$out" | awk -F'\t' '$2=="weird"{print $1}')" "check: unknown type ERROR"
assert_eq "3" "$(printf '%s\n' "$out" | grep -c .)" "check: one line per component"
rm -rf "$tmp"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: FAIL (`check.sh` missing).

- [ ] **Step 3: Write the implementation** `check.sh`

```bash
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

while IFS=$'\t' read -r name type path parent venv marketplace post_update check latest update hosts; do
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: all `test_check.sh` asserts `ok`.

- [ ] **Step 5: Make executable and commit**

```bash
cd ~/Work/auto-update
chmod +x check.sh
git add check.sh tests/test_check.sh
git commit -m "feat: check.sh entrypoint — dispatch registry to checkers"
```

---

## Task 11: `discover.sh` — find components not in the registry

**Files:**
- Create: `~/Work/auto-update/discover.sh`
- Test: `~/Work/auto-update/tests/test_discover.sh`

**Interfaces:**
- Produces: `discover.sh [--registry FILE]` → prints TSV candidate lines `type<TAB>name<TAB>hint` for things present on the system but NOT named in the registry. Sources: installed plugins (`claude plugin list --json` → ids), git repos directly under `~/Work`, (best-effort) MCP servers from `~/.claude.json`. Already-registered names are filtered out. Consumed by `SKILL.md` DISCOVER phase, which asks the user before appending.

- [ ] **Step 1: Write the failing test** `tests/test_discover.sh`

```bash
tmp="$(mktemp -d)"
reg="$tmp/registry.conf"
printf 'name=known-repo\ntype=git-repo\npath=%s/Work/known-repo\n' "$tmp" > "$reg"
# fake a WORK dir with two repos, one already known
mkdir -p "$tmp/Work/known-repo/.git" "$tmp/Work/fresh-repo/.git"

out="$(AU_REGISTRY="$reg" AU_WORK="$tmp/Work" bash ../discover.sh)"
assert_contains "$out" "fresh-repo" "discover: surfaces unregistered repo"
# known-repo must be filtered out
notknown="$(printf '%s\n' "$out" | awk -F'\t' '$2=="known-repo"' )"
assert_eq "" "$notknown" "discover: hides already-registered repo"
rm -rf "$tmp"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: FAIL (`discover.sh` missing).

- [ ] **Step 3: Write the implementation** `discover.sh`

```bash
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: all `test_discover.sh` asserts `ok`.

- [ ] **Step 5: Make executable and commit**

```bash
cd ~/Work/auto-update
chmod +x discover.sh
git add discover.sh tests/test_discover.sh
git commit -m "feat: discover.sh — surface unregistered components"
```

---

## Task 12: `install.sh` — idempotent bootstrap

**Files:**
- Create: `~/Work/auto-update/install.sh`
- Test: `~/Work/auto-update/tests/test_install.sh`

**Interfaces:**
- Produces: `install.sh` → (1) resolves its own repo dir; (2) symlinks `$HOME/.claude/skills/auto-update` → repo dir with `ln -sfn`, skipping if already correct, WARNING (no mutation) if the path exists as a non-symlink or wrong symlink; (3) if the link lands inside a git work tree, appends the repo-relative path to that repo's `.git/info/exclude` (idempotent `grep -qxF`); (4) creates `$HOME/.claude/auto-update/` and seeds `registry.conf` from `registry.example.conf` ONLY if absent; (5) appends a self-update entry for `auto-update` to the registry if not present. Honors `$HOME` override so tests run in a sandbox.

- [ ] **Step 1: Write the failing test** `tests/test_install.sh`

```bash
sandbox="$(mktemp -d)"
repo="$(cd .. && pwd -P)"     # the auto-update repo under test
# Provide the example registry the installer seeds from (created in Task 13;
# create a stand-in here so this task is independently runnable).
[ -f "$repo/registry.example.conf" ] || printf '# example\n' > "$repo/registry.example.conf"

HOME="$sandbox" bash "$repo/install.sh" >/dev/null 2>&1

link="$sandbox/.claude/skills/auto-update"
assert_eq "yes" "$([ -L "$link" ] && echo yes)" "install: creates symlink"
assert_eq "$(readlink -f "$repo")" "$(readlink -f "$link")" "install: symlink points at repo"
assert_eq "yes" "$([ -f "$sandbox/.claude/auto-update/registry.conf" ] && echo yes)" "install: seeds registry.conf"
assert_contains "$(cat "$sandbox/.claude/auto-update/registry.conf")" "name=auto-update" "install: adds self-update entry"

# idempotent: second run must not error and must not duplicate the self entry
HOME="$sandbox" bash "$repo/install.sh" >/dev/null 2>&1
count="$(grep -c '^name=auto-update$' "$sandbox/.claude/auto-update/registry.conf")"
assert_eq "1" "$count" "install: self entry not duplicated on re-run"
rm -rf "$sandbox"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: FAIL (`install.sh` missing).

- [ ] **Step 3: Write the implementation** `install.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
SKILLS_DIR="$HOME/.claude/skills"
LINK="$SKILLS_DIR/auto-update"
CFG_DIR="$HOME/.claude/auto-update"
REG="$CFG_DIR/registry.conf"

mkdir -p "$SKILLS_DIR"

# 1. Idempotent symlink (never clobber a real dir or a different link).
if [ -L "$LINK" ]; then
  if [ "$(readlink -f "$LINK")" = "$(readlink -f "$REPO_DIR")" ]; then
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: all `test_install.sh` asserts `ok`.

- [ ] **Step 5: Make executable and commit**

```bash
cd ~/Work/auto-update
chmod +x install.sh
git add install.sh tests/test_install.sh
git commit -m "feat: idempotent install.sh (symlink + exclude + registry seed)"
```

---

## Task 13: SKILL.md + example registry + docs

This task has no unit test (it's the Claude-facing orchestration and user docs); its "test" is the manual dry-run in Step 6.

**Files:**
- Create: `~/Work/auto-update/registry.example.conf`
- Create: `~/Work/auto-update/SKILL.md`
- Create: `~/Work/auto-update/README.md`
- Create: `~/Work/auto-update/CHANGELOG.md`

**Interfaces:**
- Consumes: `check.sh`, `discover.sh`, `install.sh`, `VERSION`.
- Produces: the skill Claude Code loads. SKILL.md frontmatter `name: auto-update` + a description that triggers on "запусти автоапдейтер / обнови окружение / auto-update".

- [ ] **Step 1: Write `registry.example.conf`** (template — every type, commented)

```text
# auto-update registry — one component per block, blank line between blocks.
# Format: key=value (split on the FIRST '='). Lines starting with # are comments.
# Fields: name, type, and type-specific keys below. Optional keys may be omitted.
#
# Types: claude-plugin | git-repo | git-submodule | brew | pip-venv | custom

# --- Claude Code plugin (needs jq) ---
# name=superpowers
# type=claude-plugin
# marketplace=claude-plugins-official

# --- git repo (e.g. an MCP server). post_update runs after a successful pull. ---
# name=telegram-mcp
# type=git-repo
# path=~/Work/telegram-mcp
# post_update=uv sync

# --- git submodule (parent repo + path inside it) ---
# name=cybersec-skills
# type=git-submodule
# parent=~/Work/myOS
# path=.claude/skills/cybersec-skills

# --- Homebrew formula ---
# name=ffmpeg
# type=brew

# --- pip package inside a venv ---
# name=mlx_whisper
# type=pip-venv
# venv=~/.venv

# --- custom: check prints installed; latest (optional) prints latest; update applies ---
# name=agent-browser
# type=custom
# check=AB=$(ls ~/.nvm/versions/node/*/bin/agent-browser | tail -1); "$AB" --version | awk '{print $NF}'
# latest=command npm view agent-browser version
# update=command npm install -g agent-browser@latest

# name=claude-cli
# type=custom
# check=claude --version | awk '{print $1}'
# update=claude update
```

- [ ] **Step 2: Write `SKILL.md`**

````markdown
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
````

- [ ] **Step 3: Write `README.md`** (student-facing)

```markdown
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
```

- [ ] **Step 4: Write `CHANGELOG.md`**

```markdown
# Changelog

## 0.1.0 — 2026-06-18
- Initial release: registry-driven environment checker with 6 component types
  (claude-plugin, git-repo, git-submodule, brew, pip-venv, custom), TSV report,
  discover + idempotent install, dependency-free block-format registry.
```

- [ ] **Step 5: Run the full test suite (regression)**

Run: `bash ~/Work/auto-update/tests/run.sh`
Expected: ends `… 0 failures`.

- [ ] **Step 6: Manual end-to-end dry run**

```bash
cd ~/Work/auto-update && ./install.sh
# restart Claude Code, open a new session in ~/Work, then run check.sh directly:
~/Work/auto-update/check.sh --fetch
```
Expected: TSV rows for your real components; `ffmpeg`/`uv`/`yt-dlp`/`agent-browser`
show `OUTDATED`, `mlx_whisper` shows `OK`, `superpowers` shows `OK`.

- [ ] **Step 7: Commit**

```bash
cd ~/Work/auto-update
git add SKILL.md registry.example.conf README.md CHANGELOG.md
git commit -m "feat: SKILL.md orchestration, example registry, docs (v0.1.0)"
git tag v0.1.0
```

---

## Self-Review

**1. Spec coverage** (checked against `2026-06-18-auto-update-skill-design.md`):
- Two-layer engine/registry split → Tasks 10, 12 (registry path separate, never overwritten). ✓
- 5 phases (CHECK/DISCOVER/RESEARCH/REPORT/APPLY) → Task 13 SKILL.md; CHECK→Task 10, DISCOVER→Task 11. ✓
- All component types → Tasks 4–9. ✓
- Report format (collapse OK, number actionable, ⚠️ breaking) → Task 13 Phase 4. ✓
- registry.example + commented types → Task 13 Step 1. ✓
- install.sh (symlink + exclude + seed + self-update) → Task 12. ✓
- Versioning (VERSION, CHANGELOG, tag) + self-update entry → Tasks 1, 12, 13. ✓
- Universality (no hardcoded personal components in the engine; `~` expansion; graceful skip) → checkers `_expand_tilde`, `SKIP` paths; engine ships only `registry.example.conf`. ✓
- Distribution (public repo + install.sh + README) → Task 13. ✓
- Open questions resolved: YAML→block format (Task 2), plugin compare (Task 6), check.sh output = TSV (Task 10), install.sh symlink-into-repo (Task 12), restart note (Task 13). ✓
- `hosts` field: parsed (Task 2 column 11) and carried through but not yet acted on — acceptable for v0.1.0 (per-machine registries make it optional per spec). Documented as parsed-but-unused.

**2. Placeholder scan:** No "TBD"/"handle edge cases"/"similar to Task N". Every code step has complete code; every test step has real assertions. ✓

**3. Type consistency:** Checker contract `status⇥name⇥type⇥installed⇥latest⇥detail` is identical across Tasks 4–9 and consumed unchanged in Task 10. `parse_registry` 11-column order (Task 2) matches the `read` in `check.sh` (Task 10). `decide_status` signature consistent across Tasks 3, 6, 9. Registry field `latest` added in Task 2 is used by `custom` (Task 9) and read in Task 10. ✓

**Note carried to handoff:** the registry switched from YAML (approved spec) to a block `key=value` format because `yq` is absent on the target machine and a hand-rolled YAML parser proved fragile in research. This is the one user-visible deviation from the approved spec and needs Anatoli's explicit sign-off before execution.
