#!/usr/bin/env bash
# Plants for tests/verdicts.test.sh's order checks (step 6.2; docs/plans/
# step6.md S4): the lines of verdicts.txt that scripts read by their place
# (Verdicts::roles), put out of the order DECISIONS A10 and A71 give, turn
# the test red for its stated reason, in a throwaway copy of the repo. A
# clean copy is green.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: verdicts"
vfile=method/scripts/method/verdicts.txt

sb=$(make_sandbox) || abort_sandbox
expect_green "verdicts test green on a clean copy" "$sb" bash tests/verdicts.test.sh
drop_sandbox "$sb"

# plant NAME PERL LANDED REASON...: in a fresh copy, PERL (a perl -0pi
# script) changes verdicts.txt, which then matches the perl regular
# expression LANDED; the test must go red with each REASON
plant() {
  p_name=$1
  script=$2
  landed=$3
  shift 3
  sb=$(make_sandbox) || abort_sandbox
  perl -0pi -e "$script" "$sb/$vfile"
  # shellcheck disable=SC2016 # perl code, expanded by perl
  if expect_landed "$p_name" env LANDED="$landed" perl -0ne 'exit(/$ENV{LANDED}/m ? 0 : 1)' "$sb/$vfile"; then
    for reason in "$@"; do
      expect_red "$p_name: red for '$reason'" "$sb" "FAIL  $reason" bash tests/verdicts.test.sh
    done
  fi
  drop_sandbox "$sb"
}

# shellcheck disable=SC2016 # perl code, expanded by perl
{
  plant "the reporter's line before the reviewer's" 's/(gate-verdict\tmethod-reviewer\t[^\n]*\n)((?:[^\n]*\n)*?)(gate-verdict\tmethod-reporter\t[^\n]*\n)/$3$1$2/' \
    '^gate-verdict\tmethod-reporter\t[^\n]*\ngate-verdict\tmethod-reviewer\t' \
    "the gate-verdict words match the records" "Verdicts::roles reads each role by its place"
  plant "the fail word before the pass word" 's/(test-result\tTESTS PASS\t[^\n]*\n)(test-result\tTESTS FAIL\t[^\n]*\n)/$2$1/' \
    '^test-result\tTESTS FAIL\t[^\n]*\ntest-result\tTESTS PASS\t' \
    "the test-result words match the records" "Verdicts::roles reads each role by its place"
}

echo "plants: verdicts: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
