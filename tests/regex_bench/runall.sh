#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKSPACE_DIR="$(cd "$REPO_DIR/.." && pwd)"

if ! command -v lua >/dev/null 2>&1; then
  echo "lua is not available in PATH"
  exit 127
fi

total=0
passed=0
failed=0

for test in "$SCRIPT_DIR"/test_*.lua; do
  [ -e "$test" ] || continue
  total=$((total + 1))
  rel="vim/tests/regex_bench/$(basename "$test")"
  echo "Running $rel"
  if (cd "$WORKSPACE_DIR" && lua "$rel"); then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
  fi
done

if [ "$total" -eq 0 ]; then
  echo "No tests found in $SCRIPT_DIR"
  exit 1
fi

echo
echo "Results: $passed/$total passed, $failed failed"

if [ "$failed" -eq 0 ]; then
  exit 0
fi
exit 1
