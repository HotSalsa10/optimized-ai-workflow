#!/usr/bin/env bash
# Plants for tests/ci-config.test.sh (step 6b's review, R17): in a throwaway
# copy of the repo, the real .github/workflows/ci.yml gets its on: block in
# flow form on one line, with a quoted " #" before a pull_request trigger.
# YAML reads the # as text and the trigger as a trigger, so the test's
# check of the real file must go red for its stated reason. The test's own
# cases plant each other setting in a copy of ci.yml (its cases 2 to 7).
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: CI settings"
real="ci.yml: every run step stops workflow commands, groups split by event, checkout keeps no token, no pull_request trigger"

sb=$(make_sandbox) || abort_sandbox
if got=$(cd "$sb" && bash tests/ci-config.test.sh 2>&1); then
  pass "the CI settings test is green on a clean copy"
else
  fail "the CI settings test is green on a clean copy" "$(printf '%s\n' "$got" | grep FAIL)"
fi
drop_sandbox "$sb"

sb=$(make_sandbox) || abort_sandbox
ci=$sb/.github/workflows/ci.yml
perl -0pi -e 's/^on:\n  push:\n    branches: \["\*\*"\]\n    tags: \["v\*"\]\n  workflow_dispatch:\n/on: {push: {branches: ["**", "skip #"], tags: ["v*"]}, pull_request: {}, workflow_dispatch: {}}\n/m' "$ci"
if expect_landed "a one-line flow-form on: with a quoted \" #\" before pull_request" grep -q -F 'on: {push: {branches: ["**", "skip #"], tags: ["v*"]}, pull_request: {}' "$ci"; then
  plant_judge "a pull_request trigger after a quoted \" #\" in a one-line flow-form on: (R17)" "$sb" tests/ci-config.test.sh "$real"
fi
drop_sandbox "$sb"

echo "plants: CI settings: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
