source ../lib/compare.sh
source ../lib/checkers.sh

tmp="$(mktemp -d)"
export GIT_ALLOW_PROTOCOL=file
# submodule origin with 2 commits
( cd "$tmp" && git init -q suborigin && cd suborigin \
    && git config user.email t@t && git config user.name t \
    && echo 1 > s && git add s && git commit -qm s1 \
    && echo 2 >> s && git commit -qam "sub second" )
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
