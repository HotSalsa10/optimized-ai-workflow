#!/usr/bin/env bash
# Plants for done-check's reading of the plan and the receipts (step 6b.1;
# docs/plans/step6b.md, section 1, item 16): each planted break in
# lib/done.pl or lib/receipt-read.pl turns tests/done-check.test.sh red for
# its stated reason, in a throwaway copy of the repo, with only the cases
# kept for that reason (after they pass on the clean copy). The floor's
# missing elements are input cases in the test file; these are defects in
# the code. The breaks are data: "=== NAME | FILE | REASON", the text OLD
# (in FILE exactly once), "---", the text NEW (tests/lib.sh, plant_data).
# PLANT_SHARD=K/N runs every Nth one from the Kth. The two breaks of the
# receipt's base, which lib/receipt.pl records, are in
# tests/plants/gate-receipt.sh.
# shellcheck disable=SC2016 # the plants are literal perl text
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: done-check"
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/plants.txt" <<'PLANTS-END'
=== the chain check removed | method/scripts/method/lib/done.pl | floor: a first review built with --since that does not chain
  my ($ok) = grep { my $r = $_; grep { chains($gate, $_, {}) } @{ $r->{bases} } } @based;
---
  my ($ok) = @based;
=== the other-word filter limited to VALID | method/scripts/method/lib/done.pl | floor: a REQUEST CHANGES beside an APPROVE on one tree is NOT READY, whatever its state (INVALID)
  my @other = grep { defined $_->{open} && $_->{open} ne $yes } @on;
---
  my @other = grep { $_->{state} eq $good && defined $_->{open} && $_->{open} ne $yes } @on;
=== the other-word filter by state instead of the word | method/scripts/method/lib/done.pl | floor: a receipt with no word beside an APPROVE neither blocks nor counts
  my @other = grep { defined $_->{open} && $_->{open} ne $yes } @on;
---
  my @other = grep { $_->{state} ne $good } @on;
=== the round limit off by one | method/scripts/method/lib/done.pl | floor: a fourth round since the anchor
  if ($n > $MAX_ROUNDS) {
---
  if ($n > $MAX_ROUNDS + 1) {
=== the anchor taken as the last commit with the line | method/scripts/method/lib/done.pl | floor: an Approved line removed and added again does not move the anchor
      $anchor = $i if !defined $anchor && $l eq $app[0];
---
      $anchor = $i if $l eq $app[0];
=== the rounds counted from the branch's commits only | method/scripts/method/lib/done.pl | floor: rounds survive a squash
    for my $t (grep { !$on{$_} } sort keys %reviewed) {
---
    for my $t () {
=== a reviewed version that cannot be read passed over in silence | method/scripts/method/lib/done.pl | floor: a reviewed version this clone cannot read is not counted, and the line says so
      if (!defined $has) { $unread++; next }
---
      next unless defined $has;
=== a task plan that is not a regular file passed over | method/scripts/method/lib/done.pl | floor: a second task plan that is a symbolic link
  my @added = grep { !Tree::lookup($T{mb}, $_->[0]) } plan_paths($head);
---
  my @added = grep { !Tree::lookup($T{mb}, $_->[0]) && $_->[1] eq '' } plan_paths($head);
=== diagnose left out of the history | method/scripts/method/lib/done.pl | floor: a diagnose receipt shows in the history
grep { $_->{tree} eq $c->[1] && exists $w->{gate}{ $_->{gate} } }
---
grep { $_->{tree} eq $c->[1] && exists $w->{gate}{ $_->{gate} } && $w->{gate}{ $_->{gate} } ne 'diagnosis' }
=== the quote check takes any approval word | method/scripts/method/lib/done.pl | floor: an Approved line that names another task is NOT READY
    unless $quote =~ /(?<![A-Za-z0-9-])(?i:\Q$ready\E)[ \t]+\Q$id\E(?![A-Za-z0-9-])/;
---
    unless $quote =~ /(?i:\Q$ready\E)/;
=== the receipts matched by head instead of tree | method/scripts/method/lib/done.pl | floor: approving receipts at the parent, HEAD an empty trailer commit
  my @on = grep { $_->{gate} eq $gate && $_->{tree} eq $T{tree} } @{ $T{receipts} };
---
  my @on = grep { $_->{gate} eq $gate && ($_->{head} // '') eq $T{head} } @{ $T{receipts} };
=== the newest by file name instead of the stop time | method/scripts/method/lib/receipt-read.pl | floor: two receipts whose name order and stopped order disagree
  return sort { $a->{stopped} <=> $b->{stopped} || $a->{name} cmp $b->{name} } grep { defined $_->{stopped} } @_;
---
  return sort { $a->{name} cmp $b->{name} } grep { defined $_->{stopped} } @_;
=== the hook library loaded with the receipts | method/scripts/method/lib/done.pl | floor: NOTHING TO MERGE still exits 3
qw(git.pl esc.pl conf.pl tree.pl verdicts.pl checks.pl receipt-read.pl)
---
qw(git.pl esc.pl conf.pl tree.pl verdicts.pl checks.pl receipt.pl)
PLANTS-END
plant_data "$work/plants.txt" tests/done-check.test.sh only
drop_sandbox "$work" || true
echo "plants: done-check: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
