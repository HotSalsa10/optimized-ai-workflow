#!/usr/bin/env bash
# Plants for the live-write helper (step 7.6;
# method/scripts/method/live-write.sh, M063): each planted break turns
# tests/live-write.test.sh red for its stated reason, in a throwaway copy
# of the repo, with only the cases kept for that reason (after they pass on
# the clean copy). The breaks are data: "=== NAME | FILE | REASON", the
# text OLD (in FILE exactly once), "---", the text NEW (tests/lib.sh,
# plant_data). PLANT_SHARD=K/N runs every Nth one from the Kth.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: live-write"
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/plants.txt" <<'PLANTS-END'
=== the reason check removed | method/scripts/method/live-write.sh | no reason: refused, nothing run
  if [ "$have_reason" = 0 ]; then
---
  if false; then
=== the dry-run default inverted | method/scripts/method/live-write.sh | the dry run is the default
  local reason='' have_reason=0 live=0
---
  local reason='' have_reason=0 live=1
=== the reason printed after the command | method/scripts/method/live-write.sh | with --live the write runs
  printf 'live-write: reason: %s\n' "$_method_live_reason"
  if [ "$_method_live_on" != 1 ]; then
---
  if [ "$_method_live_on" != 1 ]; then
    printf 'live-write: reason: %s\n' "$_method_live_reason"
=== the stand-alone run let through | method/scripts/method/live-write.sh | run on its own, it runs nothing
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
---
if false; then
=== -- read as the end of the person's words | method/scripts/method/live-write.sh | a command from the person after --: refused
      --live)
        live=1
        shift
        ;;
---
      --live)
        live=1
        shift
        ;;
      --)
        shift
        break
        ;;
=== method_live_write run without method_live_opts | method/scripts/method/live-write.sh | a write with no method_live_opts call: refused
  if [ "$_method_live_ok" != 1 ]; then
---
  if false; then
=== the reason kept before every word is read | method/scripts/method/live-write.sh | a refused word leaves no reason kept
        reason=$2
        have_reason=1
---
        reason=$2
        have_reason=1
        _method_live_reason=$2 _method_live_ok=1
=== what it keeps not set when sourced | method/scripts/method/live-write.sh | what it keeps never comes from the environment
# in the environment never counts
_method_live_ok=0 _method_live_reason='' _method_live_on=0
---
# in the environment never counts
PLANTS-END
plant_data "$work/plants.txt" tests/live-write.test.sh only
drop_sandbox "$work" || true
echo "plants: live-write: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
