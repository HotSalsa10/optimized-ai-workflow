#!/usr/bin/env bash
# Plants for the helpers that let a plant run only the cases that can show
# its reason (tests/lib.sh: wanted, wanted_any, plant_control, plant_judge,
# plant_data's "only"; DECISIONS A70), each turning tests/lib.test.sh red
# for its stated reason, and for tests/run.sh, each turning
# tests/suite.test.sh red; in a throwaway copy of the repo. The breaks are
# data: "=== NAME | FILE | REASON", the text OLD (in FILE exactly once),
# "---", the text NEW (tests/lib.sh, plant_data).
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: test helpers"
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/plants.txt" <<'PLANTS-END'
=== wanted keeps every case | tests/lib.sh | wanted skips a case that cannot print the reason
  [ -n "${TEST_ONLY:-}" ] || return 0
---
  return 0
=== wanted skips every case in a whole run | tests/lib.sh | wanted keeps every case when TEST_ONLY is unset or empty
  [ -n "${TEST_ONLY:-}" ] || return 0
---
  [ -n "${TEST_ONLY:-}" ] || return 1
=== wanted reads the reason one way only | tests/lib.sh | wanted keeps a case whose name starts with the reason, and one whose FAIL line would
  case "$TEST_ONLY" in "$1"*) return 0 ;; esac
---
  :
=== wanted_any reads only its first name | tests/lib.sh | wanted_any keeps a group when any of its names is wanted
    wanted "$wa_name" && return 0
  done
---
    wanted "$wa_name" && return 0
    break
  done
=== the clean run's result not read | tests/lib.sh | plant_control fails a plant whose cases fail on the clean copy too
  if pc_got=$(cd "$2" && TEST_ONLY="$4" bash "$3" 2>&1); then
---
  if pc_got=$(cd "$2" && TEST_ONLY="$4" bash "$3" 2>&1) || true; then
=== a clean run taken for a failed one | tests/lib.sh | plant_control lets a plant on when its cases pass on the clean copy
  if pc_got=$(cd "$2" && TEST_ONLY="$4" bash "$3" 2>&1); then
    return 0
---
  if pc_got=$(cd "$2" && TEST_ONLY="$4" bash "$3" 2>&1); then
    return 1
=== the stated reason not read | tests/lib.sh | plant_judge fails a plant that turned the test red for another reason
  elif ! printf '%s\n' "$pj_got" | PJ_LINE="  FAIL  $4" perl -ne 'BEGIN { $miss = 1 } $miss = 0 if index($_, $ENV{PJ_LINE}) == 0; END { exit $miss }'; then
---
  elif false; then
=== a FAIL text anywhere taken for the reason | tests/lib.sh | plant_judge does not take a FAIL text in a detail line for the reason
$miss = 0 if index($_, $ENV{PJ_LINE}) == 0;
---
$miss = 0 if index($_, $ENV{PJ_LINE}) >= 0;
=== a green test taken for a caught plant | tests/lib.sh | plant_judge fails a plant that left the test green
  if [ "$pj_rc" -eq 0 ]; then
---
  if false; then
=== a caught plant not counted | tests/lib.sh | plant_judge passes a plant that turned the test red for its reason
  else
    pass "$1"
  fi
---
  else
    fail "$1"
  fi
=== the reason kept in a whole run | tests/lib.sh | plant_judge without only runs the whole test file
  [ "${5:-}" = only ] && pj_only=$4
---
  pj_only=$4
=== a filtered run that looks whole | tests/lib.sh | a run with TEST_ONLY says so in a SKIP line
if [ -n "${TEST_ONLY:-}" ]; then
  skip
---
if false; then
  skip
=== plant_data's control skipped | tests/lib.sh | plant_data with only refuses a plant whose cases fail on the clean copy
    if [ "$pd_only" = only ] && ! plant_control
---
    if false && ! plant_control
=== plant_data's second pass not applying | tests/lib.sh | plant_data with only applies a good plant and judges it
SB="$pd_sb" PD_APPLY=1 perl
---
SB="$pd_sb" PD_APPLY= perl
PLANTS-END
plant_data "$work/plants.txt" tests/lib.test.sh
cat >"$work/runner.txt" <<'PLANTS-END'
=== TEST_ONLY and PLANT_SHARD let through | tests/run.sh | a TEST_ONLY or PLANT_SHARD in the environment never reaches a file
unset TEST_ONLY PLANT_SHARD
---
:
=== a part runs another part's files | tests/run.sh | each part runs the plant files shards.txt gives it, so the parts run every plant file once
    print "tests/plants/$_\n" for grep { $part{$_} == $k } @files;
---
    print "tests/plants/$_\n" for grep { $part{$_} == ($k + 1) % $n } @files;
=== a plant file not named let through | tests/run.sh | a plant file shards.txt does not name stops a shard run
    push @bad, "$_ is not named" for grep { !exists $part{$_} } @files;
---
    # not checked
=== a plant file named twice let through | tests/run.sh | a plant file shards.txt names twice stops a shard run
        push @bad, "$2 is named twice" if $seen{$2}++ == 1;
---
        $seen{$2}++;
=== a name that is not a plant file let through | tests/run.sh | a name in shards.txt that is not a plant file stops a shard run
    push @bad, "$_ is named but is not a plant file" for grep { !$have{$_} } sort keys %part;
---
    # not checked
=== a line it cannot read skipped | tests/run.sh | a line of shards.txt it cannot read stops a shard run
        push @bad, "line $. is not \"K FILE SECONDS\"";
---
        next;
=== an empty part let through | tests/run.sh | an empty part in shards.txt stops a shard run
      push @bad, "part $p has no file" unless grep { $_ == $p } values %part;
---
      1;
=== the count of parts not checked | tests/run.sh | a count of parts other than shards.txt's stops a shard run
    push @bad, "it has $parts parts, not $n" if $parts != $n;
---
    # not checked
=== a missing shards.txt read as empty | tests/run.sh | a shard run with no shards.txt stops
    open my $h, "<", $list or do { print "tests: FAIL - cannot read $list\n"; exit 1 };
---
    open my $h, "<", $list or exit 0;
=== a split that cannot be read run anyway | tests/run.sh | a plant file shards.txt does not name stops a shard run
      if ! picked=$(shard_files "${shard%/*}" "${shard#*/}"); then
---
      if ! picked=$(shard_files "${shard%/*}" "${shard#*/}") && false; then
=== a part that does not exist let through | tests/run.sh | a call it cannot read is refused: run.sh plants 3/3
      [ "${shard%/*}" -lt "${shard#*/}" ] || usage
---
      :
=== an argument after tests let through | tests/run.sh | a call it cannot read is refused: run.sh tests 0/2
  tests)
    [ $# -le 1 ] || usage
---
  tests)
    :
PLANTS-END
plant_data "$work/runner.txt" tests/suite.test.sh
drop_sandbox "$work" || true
echo "plants: test helpers: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
