#!/usr/bin/env bash
# Decide OK / OUTDATED / INFO from an installed and a latest version-ish string.

decide_status() { # INSTALLED LATEST
  local installed="$1" latest="$2"
  if [ -z "$latest" ]; then
    printf 'INFO\n'
  elif [ "$installed" = "$latest" ]; then
    printf 'OK\n'
  else
    printf 'OUTDATED\n'
  fi
}
