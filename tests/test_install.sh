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
