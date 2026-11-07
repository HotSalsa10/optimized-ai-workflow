#!/usr/bin/env bash
# Runs every test file (tests/*.test.sh) and every plant file (tests/plants/*.sh)
# and prints how many files passed and failed. Each file prints its own detail.
set -u
here=$(cd "$(dirname "$0")" && pwd)
cd "$here/.." || exit 2

files_pass=0
files_fail=0
found=0
for f in tests/*.test.sh tests/plants/*.sh; do
  [ -f "$f" ] || continue
  found=$((found + 1))
  if bash "$f"; then
    files_pass=$((files_pass + 1))
  else
    files_fail=$((files_fail + 1))
    echo "tests: FAILED in $f"
  fi
done

if [ "$found" -eq 0 ]; then
  echo "tests: FAIL - found 0 test files; nothing was run"
  exit 1
fi
echo "tests: $files_pass of $found files passed, $files_fail failed"
[ "$files_fail" -eq 0 ]
