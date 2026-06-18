#!/usr/bin/env bash
# Minimal test helpers — zero deps, bash 3.2 compatible.
_T_RUN=0
_T_FAIL=0

assert_eq() { # expected actual message
  _T_RUN=$((_T_RUN + 1))
  if [ "$1" = "$2" ]; then
    printf 'ok   - %s\n' "$3"
  else
    _T_FAIL=$((_T_FAIL + 1))
    printf 'FAIL - %s\n      expected: [%s]\n      actual:   [%s]\n' "$3" "$1" "$2"
  fi
}

assert_contains() { # haystack needle message
  _T_RUN=$((_T_RUN + 1))
  case "$1" in
    *"$2"*) printf 'ok   - %s\n' "$3" ;;
    *) _T_FAIL=$((_T_FAIL + 1))
       printf 'FAIL - %s\n      [%s]\n      does not contain [%s]\n' "$3" "$1" "$2" ;;
  esac
}

test_summary() {
  printf '\n%d tests, %d failures\n' "$_T_RUN" "$_T_FAIL"
  [ "$_T_FAIL" -eq 0 ]
}
