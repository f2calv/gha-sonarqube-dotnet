#!/usr/bin/env bash
# Fake dotnet tool installation, builds and tests without network access.
set -euo pipefail
{
  printf 'dotnet'
  printf ' <%s>' "$@"
  printf '\n'
} >> "$COMMAND_LOG"
if [[ "${FAIL_COMMAND:-}" == "$1" ]]; then
  exit 1
fi
if [[ "$1" == tool ]]; then
  while [[ "$1" != --tool-path ]]; do shift; done
  cp "$FAKE_SCANNER" "$2/dotnet-sonarscanner"
  chmod +x "$2/dotnet-sonarscanner"
fi
