#!/usr/bin/env bash
# Fake scanner lifecycle; credentials never enter the command log.
set -euo pipefail
{
  printf 'scanner'
  printf ' <%s>' "$@"
  printf '\n'
} >> "$COMMAND_LOG"
if [[ "${FAIL_COMMAND:-}" == "$1" ]]; then
  exit 1
fi
