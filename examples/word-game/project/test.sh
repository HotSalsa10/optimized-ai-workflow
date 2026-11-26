#!/usr/bin/env bash
# test.sh: the game's tests. Prints "tests: N passed" and exits 0 only
# when every test passed.
# shellcheck source-path=SCRIPTDIR
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=score.sh
. "$here/score.sh"

passed=0
failed=0
check() {
  if [ "$2" = "$3" ]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    echo "FAIL: $1: got '$2', expected '$3'"
  fi
}

check "a right guess scores 10" "$(score_guess meadow meadow)" 10
check "a wrong guess scores 0" "$(score_guess meadow meadows)" 0
check "each hint costs a point" "$(HINTS=3 score_guess meadow meadow)" 7
check "a right guess scores at least 1" "$(HINTS=20 score_guess meadow meadow)" 1
check "scramble reverses the letters" "$(scramble pebble)" elbbep
check "a round starts and stops" "$(bash "$here/game.sh" --once | tail -1)" "game: started, 1 round shown"

if [ "$failed" -gt 0 ]; then
  echo "tests: $failed failed, $passed passed"
  exit 1
fi
echo "tests: $passed passed"
