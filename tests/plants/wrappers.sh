#!/usr/bin/env bash
# Plants for the scripts that refuse a bare name found on PATH (step 8.3;
# M163): each planted break turns tests/wrappers.test.sh red for its stated
# reason, in a throwaway copy of the repo. The breaks are data: "=== NAME |
# FILE | REASON", the text OLD (in FILE exactly once), "---", the text NEW
# (tests/lib.sh, plant_data). PLANT_SHARD=K/N runs every Nth one from the
# Kth.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: scripts that refuse a bare name"
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/plants.txt" <<'PLANTS-END'
=== done-check's block back to here=. | method/scripts/method/done-check.sh | done-check.sh started by a bare name found on PATH is refused (bash)
    if [ "$0" = done-check.sh ] && [ "$self_src" = done-check.sh ] && [ -f ./done-check.sh ]; then
---
    if true; then
=== sync.sh's block back to here=. | scripts/release/sync.sh | sync.sh started by a bare name found on PATH is refused (bash)
    if [ "$0" = sync.sh ] && [ "$self_src" = sync.sh ] && [ -f ./sync.sh ]; then
---
    if true; then
=== report-check's checks back to ./$0 alone (as first built), so a sourced script counts | method/scripts/method/report-check.sh | report-check.sh started by a bare name found on PATH is refused (sourced)
    if [ "$0" = report-check.sh ] && [ "$self_src" = report-check.sh ] && [ -f ./report-check.sh ]; then
---
    if [ -f "./$0" ]; then
=== status.sh's checks back to ./$0 alone, so a name with a backslash counts | method/scripts/method/status.sh | status.sh started by a bare name found on PATH is refused (backslash)
    if [ "$0" = status.sh ] && [ "$self_src" = status.sh ] && [ -f ./status.sh ]; then
---
    if [ -f "./$0" ]; then
=== run-checks' BASH_SOURCE check dropped, so a $0 the caller chose counts | method/scripts/method/run-checks.sh | run-checks.sh started by a bare name found on PATH is refused (sourced, $0 chosen)
    if [ "$0" = run-checks.sh ] && [ "$self_src" = run-checks.sh ] && [ -f ./run-checks.sh ]; then
---
    if [ "$0" = run-checks.sh ] && [ -f ./run-checks.sh ]; then
=== done-check's refusal repeats $0, so a newline in it forges a last line | method/scripts/method/done-check.sh | done-check.sh started by a bare name found on PATH is refused (sourced, $0 with a newline)
or not as a file of its own; run it by its path, such as bash path/to/done-check.sh"
---
or not as a file of its own (it was given as $0); run it by its path, such as bash path/to/done-check.sh"
=== mutate-changed's refusal ends with exit 0 | method/scripts/method/mutate-changed.sh | mutate-changed.sh started by a bare name found on PATH is refused (bash --posix)
such as bash path/to/mutate-changed.sh; the run stopped"
  exit 2
---
such as bash path/to/mutate-changed.sh; the run stopped"
  exit 0
=== review-packet's block written in a form the finder misses | method/scripts/method/review-packet.sh | the finder finds the eight scripts that locate their folder from $0
case "$0" in
---
case $0 in
=== a refusal that does not name the script | method/scripts/method/setup-write.sh | setup-write.sh started by a bare name found on PATH is refused (bash)
  printf '%s\n' "setup: FAIL - setup-write.sh was started by a bare name found on PATH, or not as a file of its own; run it by its path, such as bash path/to/setup-write.sh"
---
  printf '%s\n' "setup: FAIL - this script was started by a bare name found on PATH"
=== the refusal on every bare name, its own folder's too | method/scripts/method/review-packet.sh | review-packet.sh started from its own folder, a relative path or a full path works as before (own)
    if [ "$0" = review-packet.sh ] && [ "$self_src" = review-packet.sh ] && [ -f ./review-packet.sh ]; then
---
    if false; then
=== done-check's $0 with a / taken as it is (as first built), so a script that sources it from elsewhere counts | method/scripts/method/done-check.sh | done-check.sh started by a bare name found on PATH is refused (sourced from a script elsewhere)
    if [ -n "${BASH_VERSION-}" ] && [ "$self_src" = "$0" ]; then
---
    if true; then
=== sync.sh takes an empty BASH_SOURCE for its own file, so standard input with a $0 holding a / counts | scripts/release/sync.sh | sync.sh started by a bare name found on PATH is refused (standard input, $0 with a /)
    if [ -n "${BASH_VERSION-}" ] && [ "$self_src" = "$0" ]; then
---
    if [ -n "${BASH_VERSION-}" ] && { [ "$self_src" = "$0" ] || [ -z "$self_src" ]; }; then
PLANTS-END
# (the plants that only dash can show: where it is not installed, such as
# Git Bash, their cases skip, so the plants would stay green for no fault
# of their own; step 8's fresh check)
if command -v dash >/dev/null 2>&1; then
  cat >>"$work/plants.txt" <<'PLANTS-END'
=== BASH_SOURCE read without the eval, so dash cannot parse the file | method/scripts/method/status.sh | status.sh started by dash from its own folder is refused with its line, not a parse error
[ -z "${BASH_VERSION-}" ] || eval 'self_src=${BASH_SOURCE[0]-}'
---
self_src=${BASH_SOURCE[0]-}
=== status.sh trusts a $0 with a / under a shell other than bash | method/scripts/method/status.sh | status.sh started by dash by a path, sourced from a script elsewhere is refused
    if [ -n "${BASH_VERSION-}" ] && [ "$self_src" = "$0" ]; then
---
    if [ -z "${BASH_VERSION-}" ] || [ "$self_src" = "$0" ]; then
PLANTS-END
else
  skip "the plants for a start by dash" "dash is not installed here"
fi
plant_data "$work/plants.txt" tests/wrappers.test.sh only
drop_sandbox "$work" || true
echo "plants: scripts that refuse a bare name: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
