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
