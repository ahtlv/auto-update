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
