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
