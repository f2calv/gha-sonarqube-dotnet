#!/usr/bin/env bash
# Fake scanner lifecycle; credentials never enter the command log.
set -euo pipefail
if [[ "${EXPECT_NATIVE_SCANNER_ARGS:-}" == true && "${MSYS2_ARG_CONV_EXCL:-}" != '*' ]]; then
  echo 'Git Bash scanner argument conversion was not disabled.' >&2
  exit 1
fi
{
  printf 'scanner'
  printf ' <%s>' "$@"
  printf '\n'
} >> "$COMMAND_LOG"
if [[ "${FAIL_COMMAND:-}" == "$1" ]]; then
  exit 1
fi
