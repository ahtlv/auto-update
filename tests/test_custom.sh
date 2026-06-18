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
