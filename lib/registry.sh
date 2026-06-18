#!/usr/bin/env bash
# Parse the block-format component registry into fixed-column TSV.
# One component per blank-line-delimited block of key=value lines.

parse_registry() { # FILE
  awk '
    function flush() {
      if (seen) {
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
          f["name"], f["type"], f["path"], f["parent"], f["venv"],
          f["marketplace"], f["post_update"], f["check"], f["latest"],
          f["update"], f["hosts"]
      }
      split("", f); seen = 0
    }
    { sub(/\r$/, "") }                 # CRLF tolerance
    /^[[:space:]]*$/  { flush(); next }# blank line ends a block
    /^[[:space:]]*#/  { next }         # comment
    {
      e = index($0, "=")
      if (e == 0) next                 # not a key=value line
      k = substr($0, 1, e - 1)
      v = substr($0, e + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)   # trim key only
      f[k] = v
      seen = 1
    }
    END { flush() }
  ' "$1"
}
