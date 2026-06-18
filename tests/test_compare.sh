source ../lib/compare.sh

assert_eq "OK"       "$(decide_status 6.0.2 6.0.2)" "compare: equal -> OK"
assert_eq "OUTDATED" "$(decide_status 6.0.2 6.1.0)" "compare: differ -> OUTDATED"
assert_eq "OUTDATED" "$(decide_status b62616f abcdef0)" "compare: sha differ -> OUTDATED"
assert_eq "INFO"     "$(decide_status 2.1.139 '')"  "compare: no latest -> INFO"
assert_eq "INFO"     "$(decide_status '' '')"       "compare: nothing -> INFO"
