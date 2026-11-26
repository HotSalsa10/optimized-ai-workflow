#!/usr/bin/env bash
# Tests for tests/run.sh, the runner of every test and plant file (DECISIONS
# A70), on a stub tree: a copy of run.sh beside stub test and plant files
# that print their names and what they were given. It must drop a
# TEST_ONLY or PLANT_SHARD from its environment, run only the test files
# or only the plant files when asked, run part K of N as
# tests/plants/shards.txt gives it (since step 7.9), stop before running
# anything when that file misses a plant file, names one twice or one that
# is not there, has a line it cannot read, an empty part or another count
# of parts, and refuse a call it cannot read. The real shards.txt is read
# the same way, on stubs named as the real plant files.
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
# not every Kth file: part 0 holds p1 and p5, part 2 holds p3 and p4
split='# the stub split
0 p1.sh 10
1 p2.sh 20

2 p3.sh 5
2 p4.sh 5
0 p5.sh 7'
printf '%s\n' "$split" >"$stub/tests/plants/shards.txt"

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
t0=$(ran plants 0/3 | tr '\n' ' ')
t1=$(ran plants 1/3 | tr '\n' ' ')
t2=$(ran plants 2/3 | tr '\n' ' ')
if [ "$t0" = "plant p1 plant p5 " ] && [ "$t1" = "plant p2 " ] && [ "$t2" = "plant p3 plant p4 " ]; then
  pass "each part runs the plant files shards.txt gives it, so the parts run every plant file once"
else
  fail "each part runs the plant files shards.txt gives it, so the parts run every plant file once" "0/3: $t0; 1/3: $t1; 2/3: $t2"
fi

# refused SPLIT ARG WANT NAME: with SPLIT as shards.txt, run.sh plants ARG
# exits 1, runs nothing and prints a FAIL line holding WANT
refused() {
  printf '%s\n' "$1" >"$stub/tests/plants/shards.txt"
  out=$(bash "$stub/tests/run.sh" plants "$2" 2>&1)
  code=$?
  if [ "$code" -eq 1 ] && ! printf '%s\n' "$out" | grep -q '^ran ' &&
    printf '%s\n' "$out" | grep -q -F -- "tests: FAIL - tests/plants/shards.txt: $3"; then
    pass "$4"
  else
    fail "$4" "exit $code: $out"
  fi
  printf '%s\n' "$split" >"$stub/tests/plants/shards.txt"
}
refused "$(printf '%s\n' "$split" | grep -v p5)" 0/3 "p5.sh is not named" \
  "a plant file shards.txt does not name stops a shard run"
refused "$(printf '%s\n1 p5.sh 3\n' "$split")" 1/3 "p5.sh is named twice" \
  "a plant file shards.txt names twice stops a shard run"
refused "$(printf '%s\n1 p6.sh 3\n' "$split")" 1/3 "p6.sh is named but is not a plant file" \
  "a name in shards.txt that is not a plant file stops a shard run"
refused "$(printf '%s\n' "$split" | sed 's/^1 p2.sh 20$/1 p2.sh/')" 2/3 "line 3 is not \"K FILE SECONDS\"" \
  "a line of shards.txt it cannot read stops a shard run"
refused "$(printf '%s\n' "$split" | sed 's/^1 p2.sh/3 p2.sh/')" 0/4 "part 1 has no file" \
  "an empty part in shards.txt stops a shard run"
refused "$split" 0/2 "it has 3 parts, not 2" \
  "a count of parts other than shards.txt's stops a shard run"
rm "$stub/tests/plants/shards.txt"
out=$(bash "$stub/tests/run.sh" plants 0/3 2>&1)
code=$?
if [ "$code" -eq 1 ] && printf '%s\n' "$out" | grep -q -F "tests: FAIL - cannot read tests/plants/shards.txt"; then
  pass "a shard run with no shards.txt stops"
else
  fail "a shard run with no shards.txt stops" "exit $code: $out"
fi
printf '%s\n' "$split" >"$stub/tests/plants/shards.txt"

for a in "plants 3/3" "plants 0/0" "plants x" "plants 1/2 x" "tests 0/2" "all x" "other"; do
  # shellcheck disable=SC2086 # the words are meant to split
  out=$(bash "$stub/tests/run.sh" $a 2>&1)
  code=$?
  case "$code:$out" in
    "2:usage: "*) pass "a call it cannot read is refused: run.sh $a" ;;
    *) fail "a call it cannot read is refused: run.sh $a" "exit $code: $out" ;;
  esac
done
drop_sandbox "$stub" || true

# the real split, on stubs named as the real plant files: each of its parts
# runs, and together they run every plant file once
real=$(new_sandbox_dir) || abort_sandbox
mkdir -p "$real/tests/plants"
cp "$here/run.sh" "$real/tests/run.sh" || abort_sandbox
cp "$here/plants/shards.txt" "$real/tests/plants/shards.txt" || abort_sandbox
for f in "$here"/plants/*.sh; do
  n=${f##*/}
  printf 'echo "ran plant %s"\n' "${n%.sh}" >"$real/tests/plants/$n"
done
parts=$(perl -ne 'print "$1\n" if /^([0-9]+) /' "$here/plants/shards.txt" | sort -n | tail -1)
parts=$((${parts:-0} + 1))
got=""
bad=""
k=0
while [ "$k" -lt "$parts" ]; do
  if out=$(bash "$real/tests/run.sh" plants "$k/$parts" 2>&1); then
    got="$got$(printf '%s\n' "$out" | sed -n 's/^ran plant \(.*\)$/\1/p')
"
  else
    bad="$bad$out
"
  fi
  k=$((k + 1))
done
want=$(for f in "$here"/plants/*.sh; do n=${f##*/}; echo "${n%.sh}"; done | sort)
got=$(printf '%s' "$got" | sed '/^$/d' | sort)
if [ -z "$bad" ] && [ "$got" = "$want" ]; then
  pass "the real shards.txt names every plant file once, in $parts parts that each run"
else
  fail "the real shards.txt names every plant file once, in $parts parts that each run" "$bad$(printf '%s\n' "$got" | tr '\n' ' ')"
fi
drop_sandbox "$real" || true

echo "tests: the test runner: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
