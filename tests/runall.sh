#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v lua >/dev/null 2>&1; then
  echo "lua is not available in PATH"
  exit 127
fi

exec lua "$SCRIPT_DIR/new/run.lua" "$@"
