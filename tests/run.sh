#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
# shellcheck disable=SC1091
source ./lib.sh
for t in test_*.sh; do
  [ -e "$t" ] || continue
  printf '\n## %s\n' "$t"
  # shellcheck disable=SC1090
  source "./$t"
done
test_summary
