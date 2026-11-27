#!/usr/bin/env bash
# Plants for tests/ci-template.test.sh (step 9.3, M166): each break, made in
# a throwaway copy of the repo, must turn the test red for its stated
# reason. Two more are judged by the tests that read the seeded file
# elsewhere: tests/examples.test.sh (the run step in each example) and
# tests/uninstall.test.sh (uninstall names the file as setup's).
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: CI template"
test_file=tests/ci-template.test.sh
t=method/scripts/method/templates/method-checks.yml.tmpl

# plant NAME REASON CHANGE LANDED [TEST [only]]: in a new sandbox, the shell
# code CHANGE (run in it) makes the break and LANDED (run in it) confirms
# it; then TEST (the CI template test unless named) must go red with a
# FAIL line that starts with REASON
plant() {
  sb=$(make_sandbox) || abort_sandbox
  pl_test=${5:-$test_file}
  if [ "${6:-}" = only ] && ! plant_control "$1" "$sb" "$pl_test" "$2"; then
    drop_sandbox "$sb"
    return
  fi
  if (cd "$sb" && eval "$3") && expect_landed "$1" sh -c "cd \"\$1\" && $4" sh "$sb"; then
    plant_judge "$1" "$sb" "$pl_test" "$2" "${6:-}"
  fi
  drop_sandbox "$sb"
}

sb=$(make_sandbox) || abort_sandbox
if out=$(cd "$sb" && bash "$test_file" 2>&1); then
  pass "the CI template test is green on a clean copy"
else
  fail "the CI template test is green on a clean copy" "$(printf '%s\n' "$out" | grep FAIL)"
fi
drop_sandbox "$sb"

plant "a pull_request trigger" \
  "its triggers are exactly push, on every branch, and workflow_dispatch" \
  "perl -pi -e 's/^  workflow_dispatch:\$/  workflow_dispatch:\n  pull_request:/' $t" "grep -q -x '  pull_request:' $t"

plant "a pull_request_target trigger" \
  "its triggers are exactly push, on every branch, and workflow_dispatch" \
  "perl -pi -e 's/^  workflow_dispatch:\$/  workflow_dispatch:\n  pull_request_target:/' $t" "grep -q -x '  pull_request_target:' $t"

plant "push limited to main" \
  "its triggers are exactly push, on every branch, and workflow_dispatch" \
  "perl -pi -e 's/^    branches: \[\"\*\*\"\]\$/    branches: [main]/' $t" "grep -q -x '    branches: \[main\]' $t"

plant "a secrets. reference in the run step's environment" \
  "outside comments it names no secret and no token" \
  "perl -pi -e 's/^      - name: Run the checks\$/      - name: Run the checks\n        env:\n          KEY: \\\${{ secrets.KEY }}/' $t" "grep -q 'secrets.KEY' $t"

plant "the token handed to a step" \
  "outside comments it names no secret and no token" \
  "perl -pi -e 's/^      - name: Run the checks\$/      - name: Run the checks\n        env:\n          GH: \\\${{ github.token }}/' $t" "grep -q 'github.token' $t"

plant "checkout pinned by tag" \
  "the workflow lint finds nothing" \
  "perl -pi -e 's/actions\/checkout\@[0-9a-f]{40}/actions\/checkout\@v7/' $t" "grep -q 'actions/checkout@v7 ' $t"

plant "persist-credentials dropped" \
  "it checks out with ci.yml's pinned checkout commit" \
  "perl -ni -e 'print unless /^ *(?:with:|persist-credentials: false)\$/' $t" "! grep -q persist-credentials $t"

plant "a checkout commit other than ci.yml's" \
  "it checks out with ci.yml's pinned checkout commit" \
  "perl -pi -e 's/actions\/checkout\@[0-9a-f]{40}/actions\/checkout\@1111111111111111111111111111111111111111/' $t" "grep -q 'checkout@1111111111' $t"

plant "permissions widened to contents: write" \
  "its permissions are contents: read alone" \
  "perl -pi -e 's/^  contents: read\$/  contents: write/' $t" "grep -q -x '  contents: write' $t"

plant "the stop-commands line dropped from the run step" \
  "every run starts with the stop-commands line" \
  "perl -ni -e 'print unless /^          echo \"::stop-commands::/' $t" "! grep -q '^          echo \"::stop-commands::' $t"

plant "the run step without CI=true" \
  "every run starts with the stop-commands line, and the last runs CI=true" \
  "perl -pi -e 's/^          CI=true bash /          bash /' $t" "grep -q -x '          bash scripts/method/run-checks.sh' $t"

plant "the run step swallowing run-checks' exit code" \
  "in a project whose check rows are all off, the seeded run step gives exit 3" \
  "perl -pi -e 's/^(          CI=true bash scripts\/method\/run-checks\.sh)\$/\$1 || true/' $t" "grep -q 'run-checks.sh || true' $t"

plant "the template not seeded where setup puts the workflow" \
  "setup seeds it byte for byte" \
  "perl -ni -e 'print unless /^  return \\\$CI if /' method/scripts/method/lib/setup.pl" "! grep -q 'return \$CI if' method/scripts/method/lib/setup.pl"

plant "the run step without CI=true, seen in an example" \
  "word-game: the seeded CI workflow's run step, run as GitHub's runner runs it, exits 0 with CI=true" \
  "perl -pi -e 's/^          CI=true bash /          bash /' $t" "grep -q -x '          bash scripts/method/run-checks.sh' $t" \
  tests/examples.test.sh only

plant "uninstall not naming the CI workflow as setup's" \
  "after /method-setup, its files stay and the output lists exactly the files that mention the method" \
  "perl -pi -e 's/\\\$t eq .method-checks\.yml. \? .\.github\/workflows\/method-checks\.yml. : //' scripts/release/lib/uninstall.pl" "! grep -q 'method-checks' scripts/release/lib/uninstall.pl" \
  tests/uninstall.test.sh only

echo "plants: CI template: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
