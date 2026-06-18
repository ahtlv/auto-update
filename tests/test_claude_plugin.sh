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
