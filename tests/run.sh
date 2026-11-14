#!/usr/bin/env bash
# Runs every test file (tests/*.test.sh) and every plant file (tests/plants/*.sh)
# and prints how many files passed and failed. Each file prints its own detail.
# "run.sh tests" runs only the test files and "run.sh plants" only the plant
# files, so CI can run them side by side; "run.sh plants K/N" runs every Nth
# plant file from the Kth (0-based). A TEST_ONLY or PLANT_SHARD left in the
# caller's environment is dropped: a run of whole files never keeps only
# some cases or some plants. (Tested in tests/suite.test.sh.)
set -u
unset TEST_ONLY PLANT_SHARD
here=$(cd "$(dirname "$0")" && pwd)
cd "$here/.." || exit 2

usage() {
  echo "usage: tests/run.sh [tests | plants [K/N]]"
  exit 2
}
shard=0/1
case "${1:-all}" in
  all)
    [ $# -le 1 ] || usage
    set -- tests/*.test.sh tests/plants/*.sh
    ;;
  tests)
    [ $# -le 1 ] || usage
    set -- tests/*.test.sh
    ;;
  plants)
    [ $# -le 2 ] || usage
    case "${2:-0/1}" in
      [0-9]/[1-9]) shard=${2:-0/1} ;;
      *) usage ;;
    esac
    [ "${shard%/*}" -lt "${shard#*/}" ] || usage
    set -- tests/plants/*.sh
    ;;
  *) usage ;;
esac
k=0

files_pass=0
files_fail=0
found=0
for f in "$@"; do
  [ -f "$f" ] || continue
  k=$((k + 1))
  [ $(((k - 1) % ${shard#*/})) -eq "${shard%/*}" ] || continue
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
