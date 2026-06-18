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
