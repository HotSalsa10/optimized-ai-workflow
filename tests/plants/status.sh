#!/usr/bin/env bash
# Plants for status's context area (step 7.5, M152: the project's own
# always-loaded text, at most 8,000 bytes) and for the verdicts area's line
# naming a first install merged without a review (step 7's whole-step
# check; step7.md S16): each planted break turns
# tests/status.test.sh red for its stated reason, in a throwaway copy of
# the repo. The breaks are data: "=== NAME | FILE | REASON", the text OLD
# (in FILE exactly once), "---", the text NEW (tests/lib.sh, plant_data).
# PLANT_SHARD=K/N runs every Nth one from the Kth.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: status"
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/plants.txt" <<'PLANTS-END'
=== 7.5 the LOOK off by one | method/scripts/method/lib/status.pl | context: the project's own text at 8,000 bytes is a PASS
  if ($total > $CONTEXT_MAX) {
---
  if ($total >= $CONTEXT_MAX) {
=== 7.5 rules with a paths: line counted | method/scripts/method/lib/status.pl | context: rules with a paths: line are not counted
        push @files, [$p, $bytes] unless scoped($p);
---
        push @files, [$p, $bytes];
=== 7.5 the method's own rules counted | method/scripts/method/lib/status.pl | context: .claude/rules/method/ is not counted
  if (my @m = stat '.claude/rules/method') { $seen{"$m[0]:$m[1]"} = 1 }
---

=== 7.5 the method's folder left out by its name alone | method/scripts/method/lib/status.pl | context: a link into .claude/rules/method/ from another rules folder is not counted
  if (my @m = stat '.claude/rules/method') { $seen{"$m[0]:$m[1]"} = 1 }
  my $walk;
  $walk = sub {
    my ($dir) = @_;
---
  my $walk;
  $walk = sub {
    my ($dir) = @_;
    return if $dir eq '.claude/rules/method';
=== 7.5 .claude/CLAUDE.md not counted | method/scripts/method/lib/status.pl | context: .claude/CLAUDE.md, which Claude Code loads as project memory, is counted
  for my $f (qw(CLAUDE.md .claude/CLAUDE.md AGENTS.md)) { push @files, [$f, -s _] if -f $f }
---
  for my $f (qw(CLAUDE.md AGENTS.md)) { push @files, [$f, -s _] if -f $f }
=== a first install merged without a review not named | method/scripts/method/lib/status.pl | a first install merged without a review is named on a line of its own
  my @also = !@first ? () :
---
  my @also = 1 ? () :
=== a second first install not a LOOK | method/scripts/method/lib/status.pl | a second first install merged without a review is a LOOK naming both
  my @also = !@first ? () : ['verdicts', @first > 1 ? 'LOOK' : 'PASS',
---
  my @also = !@first ? () : ['verdicts', 'PASS',
PLANTS-END
# where links cannot be made (Git Bash may make a copy instead of a link),
# the test skips its case on a link into .claude/rules/method/, so that
# case's plant is dropped, and said so
if ! { ln -s target "$work/link-probe" 2>/dev/null && [ -L "$work/link-probe" ]; }; then
  perl -0pi -e 's/^=== 7\.5 the method.s folder left out by its name alone \|.*?(?=^=== |\z)//msg' "$work/plants.txt"
  skip "the plant on the method's folder left out by its name alone (this system cannot make links)"
fi
rm -f "$work/link-probe"
plant_data "$work/plants.txt" tests/status.test.sh
drop_sandbox "$work" || true
echo "plants: status: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
