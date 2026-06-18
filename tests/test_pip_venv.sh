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
