#!/usr/bin/env bash
# Tests for tests/run.sh, the runner of every test and plant file (DECISIONS
# A70), on a stub tree: a copy of run.sh beside stub test and plant files
# that print their names and what they were given. It must drop a
# TEST_ONLY or PLANT_SHARD from its environment, run only the test files
# or only the plant files when asked, split the plant files into halves
# that together run each file once, and refuse what it cannot read.
# shellcheck disable=SC2016 # the stub files are literal shell text
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: the test runner"
stub=$(new_sandbox_dir) || abort_sandbox
mkdir -p "$stub/tests/plants"
cp "$here/run.sh" "$stub/tests/run.sh" || abort_sandbox
for n in a b; do
  printf 'echo "ran test %s TEST_ONLY=${TEST_ONLY-none} PLANT_SHARD=${PLANT_SHARD-none}"\n' "$n" >"$stub/tests/$n.test.sh"
done
for n in p1 p2 p3 p4 p5; do
  printf 'echo "ran plant %s TEST_ONLY=${TEST_ONLY-none} PLANT_SHARD=${PLANT_SHARD-none}"\n' "$n" >"$stub/tests/plants/$n.sh"
done

# ran ARGS...: the names run.sh ran, sorted, one line each
ran() {
  bash "$stub/tests/run.sh" "$@" 2>&1 | sed -n 's/^ran \([a-z]*\) \([a-z0-9]*\) .*/\1 \2/p' | sort
}

out=$(TEST_ONLY='left over' PLANT_SHARD=0/4 bash "$stub/tests/run.sh" 2>&1)
if [ "$(printf '%s\n' "$out" | grep -c '^ran .* TEST_ONLY=none PLANT_SHARD=none$')" -eq 7 ]; then
  pass "a TEST_ONLY or PLANT_SHARD in the environment never reaches a file"
else
  fail "a TEST_ONLY or PLANT_SHARD in the environment never reaches a file" "$out"
fi
if [ "$(ran tests | tr '\n' ' ')" = "test a test b " ]; then pass "tests runs the test files only"; else fail "tests runs the test files only" "$(ran tests)"; fi
if [ "$(ran plants | tr '\n' ' ')" = "plant p1 plant p2 plant p3 plant p4 plant p5 " ]; then pass "plants runs the plant files only"; else fail "plants runs the plant files only" "$(ran plants)"; fi
h0=$(ran plants 0/2)
h1=$(ran plants 1/2)
both=$(printf '%s\n%s\n' "$h0" "$h1" | sort)
if [ "$both" = "$(ran plants)" ] && [ -n "$h0" ] && [ -n "$h1" ]; then
  pass "the two halves run every plant file once"
else
  fail "the two halves run every plant file once" "0/2: $h0; 1/2: $h1"
fi
t0=$(ran plants 0/3)
t1=$(ran plants 1/3)
t2=$(ran plants 2/3)
all3=$(printf '%s\n%s\n%s\n' "$t0" "$t1" "$t2" | sort)
if [ "$all3" = "$(ran plants)" ] && [ -n "$t0" ] && [ -n "$t1" ] && [ -n "$t2" ]; then
  pass "the three parts CI runs cover every plant file once"
else
  fail "the three parts CI runs cover every plant file once" "0/3: $t0; 1/3: $t1; 2/3: $t2"
fi
for a in "plants 2/2" "plants 0/0" "plants x" "plants 1/2 x" "tests 0/2" "all x" "other"; do
  # shellcheck disable=SC2086 # the words are meant to split
  out=$(bash "$stub/tests/run.sh" $a 2>&1)
  code=$?
  case "$code:$out" in
    "2:usage: "*) pass "a call it cannot read is refused: run.sh $a" ;;
    *) fail "a call it cannot read is refused: run.sh $a" "exit $code: $out" ;;
  esac
done

drop_sandbox "$stub" || true
echo "tests: the test runner: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
