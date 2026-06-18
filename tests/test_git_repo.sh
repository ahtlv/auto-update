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
