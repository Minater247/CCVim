#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CALLER_CWD="$(pwd)"

if ! command -v lua >/dev/null 2>&1; then
  echo "lua is not available in PATH"
  exit 127
fi

ARGS=()
for arg in "$@"; do
  case "$arg" in
    --backend=*)
      ARGS+=("$arg")
      ;;
    /*)
      ARGS+=("$arg")
      ;;
    *)
      ARGS+=("$CALLER_CWD/$arg")
      ;;
  esac
done

cd "$REPO_ROOT" || exit 1
if [ "${#ARGS[@]}" -eq 0 ]; then
  exec lua "$SCRIPT_DIR/run.lua"
fi
exec lua "$SCRIPT_DIR/run.lua" "${ARGS[@]}"
