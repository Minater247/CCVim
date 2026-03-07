#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if ! command -v lua >/dev/null 2>&1; then
  echo "lua is not available in PATH"
  exit 127
fi

cd "$WORKSPACE_DIR" || exit 1
exec lua vim/tests/new/run.lua
