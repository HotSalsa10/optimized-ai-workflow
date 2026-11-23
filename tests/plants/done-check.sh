#!/usr/bin/env bash
# Plants for done-check's reading of the plan and the receipts (step 6b.1;
# docs/plans/step6b.md, section 1, item 16) and of the SPEC R6 set (step
# 6b.3: the tier and the high-risk paths, the lock, the failing and passing
# runs, the reporter, Deep review): each planted break in
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
  return grep { defined $_->{open} && $_->{open} ne $yes } @r;
---
  return grep { $_->{state} eq Receipt::words()->{good} && defined $_->{open} && $_->{open} ne $yes } @r;
=== the other-word filter by state instead of the word | method/scripts/method/lib/done.pl | floor: a receipt with no word beside an APPROVE neither blocks nor counts
  return grep { defined $_->{open} && $_->{open} ne $yes } @r;
---
  return grep { $_->{state} ne Receipt::words()->{good} } @r;
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
  return grep { $_->{gate} eq $gate && $_->{tree} eq $T{tree} } @{ $T{receipts} };
---
  return grep { $_->{gate} eq $gate && ($_->{head} // '') eq $T{head} } @{ $T{receipts} };
=== the newest by file name instead of the stop time | method/scripts/method/lib/receipt-read.pl | floor: two receipts whose name order and stopped order disagree
  return sort { $a->{stopped} <=> $b->{stopped} || $a->{name} cmp $b->{name} } grep { defined $_->{stopped} } @_;
---
  return sort { $a->{name} cmp $b->{name} } grep { defined $_->{stopped} } @_;
=== the hook library loaded with the receipts | method/scripts/method/lib/done.pl | floor: NOTHING TO MERGE still exits 3
qw(git.pl esc.pl conf.pl tree.pl verdicts.pl checks.pl receipt-read.pl)
---
qw(git.pl esc.pl conf.pl tree.pl verdicts.pl checks.pl receipt.pl)
=== the tier condition removed | method/scripts/method/lib/done.pl | R6: a LIGHT plan on a high-risk path is judged FULL
  tier_condition($ref, $tip);

---

=== the lock condition removed | method/scripts/method/lib/done.pl | R6: the lock: the Tier line changed after the approval is NOT READY
  lock_condition();

---

=== the failing run condition removed | method/scripts/method/lib/done.pl | R6: no failing run after the approval is NOT READY
  failing_condition();

---

=== the passing run condition removed | method/scripts/method/lib/done.pl | R6: no passing run at HEAD is NOT READY
  newest_condition('passing run', 'tester', 'pass', '');

---

=== the reporter condition removed | method/scripts/method/lib/done.pl | R6: no reporter on FULL is NOT READY
  newest_condition('reporter', 'reporter', 'approving', '; a FULL change needs the reporter\'s word on its report');

---

=== the deep review condition removed | method/scripts/method/lib/done.pl | R6: two reviewers on a high-risk path are NOT READY
  deep_condition();

---

=== a LIGHT tier on a high-risk path accepted | method/scripts/method/lib/done.pl | R6: a LIGHT plan on a high-risk path is judged FULL
'plan again as FULL (Tier: FULL, with expected.tsv), and ask the owner for their go again') if $T{tier} eq 'LIGHT' && @high;
---
'plan again as FULL (Tier: FULL, with expected.tsv), and ask the owner for their go again') if 0;
=== HIGH_RISK_PATHS shrunk in the same change judged LIGHT | method/scripts/method/lib/done.pl | R6: a branch that drops a high-risk path main lists
  my @list = grep { !$seen{$_}++ } @$main, @$mine;
---
  my @list = grep { !$seen{$_}++ } @$mine;
=== the lock compared with HEAD instead of the anchor | method/scripts/method/lib/done.pl | R6: the lock: expected.tsv changed after the approval is NOT READY
  my ($then, $now) = (locked($at), locked($T{head}));
---
  my ($then, $now) = (locked($T{head}), locked($T{head}));
=== a HIGH_RISK_PATHS-tagged problem ignored | method/scripts/method/lib/done.pl | R6: HIGH_RISK_PATHS: HIGH_RISK_PATHS=../src on the main side is NOT READY
  my @bad = map { $problems->[$_] } grep { !defined $tags->[$_] || $tags->[$_] eq 'HIGH_RISK_PATHS' } 0 .. $#$problems;
---
  my @bad = map { $problems->[$_] } grep { !defined $tags->[$_] } 0 .. $#$problems;
=== an untagged problem ignored | method/scripts/method/lib/done.pl | R6: HIGH_RISK_PATHS: HIGH_RISK_PATH=src on the main side is NOT READY
  my @bad = map { $problems->[$_] } grep { !defined $tags->[$_] || $tags->[$_] eq 'HIGH_RISK_PATHS' } 0 .. $#$problems;
---
  my @bad = map { $problems->[$_] } grep { defined $tags->[$_] && $tags->[$_] eq 'HIGH_RISK_PATHS' } 0 .. $#$problems;
=== a method.conf stored as a Git LFS pointer read as text | method/scripts/method/lib/done.pl | R6: HIGH_RISK_PATHS: an unreadable method.conf (main side, a Git LFS pointer) is NOT READY
  return (undef, "$label: $why") if defined $why;
---
  return (undef, "$label: $why") if 0;
=== the old path of a rename not matched | method/scripts/method/lib/done.pl | R6: a rename out of a high-risk path is high-risk
    $p{ $f->{old} } = 1 if $f->{st} eq 'R' || $f->{st} eq 'C';
---
    $p{ $f->{old} } = 1 if 0;
=== a failing run on HEAD's files counted | method/scripts/method/lib/done.pl | R6: a failing run on HEAD's files at an earlier commit (an empty commit on top) is NOT READY
    if ($r->{tree} eq $T{tree}) { $not{here}++; next }
---
    if (0) { $not{here}++; next }
=== a failing run off the branch's history counted | method/scripts/method/lib/done.pl | R6: a failing run on a side branch does not count: NOT READY
    if (!ancestor($at, $h) || $h eq $T{head} || !ancestor($h, $T{head})) { $not{off}++; next }
---
    if (!ancestor($at, $h) || $h eq $T{head}) { $not{off}++; next }
=== a failing run before the plan's approval counted | method/scripts/method/lib/done.pl | R6: a re-approval moves the anchor: the lock holds, and the failing run before it does not count
    if (!ancestor($at, $h) || $h eq $T{head} || !ancestor($h, $T{head})) { $not{off}++; next }
---
    if ($h eq $T{head} || !ancestor($h, $T{head})) { $not{off}++; next }
=== any passing word on the files taken instead of the newest | method/scripts/method/lib/done.pl | R6: the tester's newest word decides: TESTS PASS, then TESTS FAIL on one tree is NOT READY
    unless $n->{state} eq $good && defined $n->{open} && $n->{open} eq $word;
---
    unless grep { $_->{state} eq $good && defined $_->{open} && $_->{open} eq $word } @r;
=== Deep review satisfied by two reviewers | method/scripts/method/lib/done.pl | R6: two reviewers on a high-risk path are NOT READY
  if (@yes >= 3 && !@other) {
---
  if (@yes >= 2 && !@other) {
=== Deep review blind to another word | method/scripts/method/lib/done.pl | R6: three reviewers, one asking for changes, are NOT READY
  if (@yes >= 3 && !@other) {
---
  if (@yes >= 3) {
=== Deep review counting an approval that does not chain | method/scripts/method/lib/done.pl | R6: Deep review: a reviewer's approval with no base is not one of the three
    && grep { chains($gate, $_, {}) } @{ $r->{bases} } } @on;
---
    } @on;
=== a FULL plan's expected.tsv not required | method/scripts/method/lib/done.pl | R6: a FULL plan with no expected.tsv when it was approved is NOT READY
    if $T{full} && !defined $then->{'expected.tsv'};
---
    if 0;
=== a failing run on values changed and changed back counted | method/scripts/method/lib/done.pl | R6: a failing run on an expected value changed and changed back does not count: NOT READY
    if (lock_moved($then, $l)) { $not{moved}++; next }
---
    if (0) { $not{moved}++; next }
=== a HIGH_RISK_PATHS entry that names no path read as a path | method/scripts/method/lib/done.pl | R6: HIGH_RISK_PATHS: an entry that names no path (scr) is NOT READY
  my @none = grep { my $e = $_; !$on_main{$e} && $e ne '.' && !Tree::lookup($T{head}, $e) && !grep { Conf::under($_, [$e]) } @touched }
    @{ $mine || [] };
---
  my @none = ();
=== an entry whose files the change deletes read as naming nothing | method/scripts/method/lib/done.pl | R6: HIGH_RISK_PATHS: an entry whose files this change deletes is read
&& !Tree::lookup($T{head}, $e) && !grep { Conf::under($_, [$e]) } @touched }
---
&& !Tree::lookup($T{head}, $e) }
=== an entry main lists checked for a path again | method/scripts/method/lib/done.pl | R6: HIGH_RISK_PATHS: an entry main lists whose path a merged change deleted blocks no other branch
  my @none = grep { my $e = $_; !$on_main{$e} && $e ne '.'
---
  my @none = grep { my $e = $_; $e ne '.'
=== expected.tsv that is not a regular file read as locked | method/scripts/method/lib/done.pl | R6: the lock: expected.tsv as a submodule when the plan was approved is NOT READY
      . " again (replace the Approved line with their new reply, with today's date and the time)") if defined $l->{odd};
---
      . " again (replace the Approved line with their new reply, with today's date and the time)") if 0;
=== a failing run where expected.tsv is not a regular file counted | method/scripts/method/lib/done.pl | R6: the failing run: expected.tsv as a submodule at the anchor does not count
    if (defined $then->{odd} || defined $l->{odd}) { $not{odd}++; next }
---
    if (0) { $not{odd}++; next }
=== the time after the date not read | method/scripts/method/lib/done.pl | floor: a same-day re-approval with a time moves the anchor
(?: ((?:[01][0-9]|2[0-3]):[0-5][0-9]))? "(.*)"\z/;
---
(?: ((?!)))? "(.*)"\z/;
=== a malformed time read as a time | method/scripts/method/lib/done.pl | floor: an Approved line with a malformed time (25:00) is NOT READY
(?: ((?:[01][0-9]|2[0-3]):[0-5][0-9]))? "(.*)"\z/;
---
(?: ([0-9]{1,2}:[0-9]{2}))? "(.*)"\z/;
=== two Tier lines read as one | method/scripts/method/lib/done.pl | floor: a plan with two Tier lines is NOT READY
"keep one Tier line in $path, and ask the owner again")
    if @tier > 1;
---
"keep one Tier line in $path, and ask the owner again")
    if 0;
=== two Approved lines read as one | method/scripts/method/lib/done.pl | floor: a plan with two Approved lines is NOT READY
    'keep only the newest Approved line') if @app > 1;
---
    'keep only the newest Approved line') if 0;
=== a task folder name that is not an id accepted | method/scripts/method/lib/done.pl | floor: a task folder whose name is not an id (T_1) is NOT READY
    'rename the folder, and ask the owner again') unless $id =~ /\A[a-z0-9][a-z0-9-]*\z/;
---
    'rename the folder, and ask the owner again') unless 1;
=== a task folder stored as a submodule passed over | method/scripts/method/lib/done.pl | floor: a second task folder stored as a submodule (a gitlink) is NOT READY
    if ($m eq '120000' || $m eq '160000') { push @p, ["docs/tasks/$n", $KIND{$m}]; next }
---
    if ($m eq '120000') { push @p, ["docs/tasks/$n", $KIND{$m}]; next }
=== the quote's leading word bound removed | method/scripts/method/lib/done.pl | floor: an Approved line whose quote only ends in the ready word
    unless $quote =~ /(?<![A-Za-z0-9-])(?i:\Q$ready\E)[ \t]+\Q$id\E(?![A-Za-z0-9-])/;
---
    unless $quote =~ /(?i:\Q$ready\E)[ \t]+\Q$id\E(?![A-Za-z0-9-])/;
=== the rounds since the anchor taken by place in the list | method/scripts/method/lib/done.pl | floor: a side line reviewed before the approval and merged after it
    my %since = map { ($_ => 1) } $at, split /\n/, Git::ok('rev-list', '--ancestry-path', "$at..$T{head}", '--');
    $on{ $_->[1] } = 1 for grep { $since{ $_->[0] } } @{ $T{branch} };
---
    $on{ $_->[1] } = 1 for @{ $T{branch} }[ $T{anchor} .. $#{ $T{branch} } ];
=== a later step promised in the elsewhere line | method/scripts/method/lib/done.pl | floor: done-check's lines name no record of the method's own repository
' only in CI, and done-check does not read CI results: '
---
' only in CI and done-check reads no CI result yet (step 9): '
=== a .claude that is not a folder read as no list | method/scripts/method/lib/done.pl | R6: HIGH_RISK_PATHS: main's method.conf unreadable (file) is NOT READY
  return (undef, "$label: .claude is " . ($d->[0] eq '160000' ? 'a submodule' : 'not a folder')) if $d->[0] ne '40000';
---
  return (undef, "$label: .claude is a submodule") if $d->[0] eq '160000';
=== a method.conf that is not a regular file read as text | method/scripts/method/lib/done.pl | R6: HIGH_RISK_PATHS: main's method.conf unreadable (link) is NOT READY
  return (undef, "$label: not a regular file in the commit") unless $e->[0] =~ /\A100(?:644|755)\z/;
---
  return (undef, "$label: not a regular file in the commit") if 0;
=== the verdict blind to the R6 set | method/scripts/method/lib/done.pl | R6: no failing run after the approval is NOT READY
  my %need = map { ($_ => 1) } 'plan', 'reviewer', 'security checker', 'rounds', @{ $T{need} };
---
  my %need = map { ($_ => 1) } 'plan', 'reviewer', 'security checker', 'rounds';
PLANTS-END
plant_data "$work/plants.txt" tests/done-check.test.sh only
# the reader of method.conf: its HIGH_RISK_PATHS, its tags and under (step
# 6b.3), each turning tests/conf.test.sh red (a fast file, run whole)
cat >"$work/conf-plants.txt" <<'PLANTS-END'
=== under matching a path that only starts like a listed one | method/scripts/method/lib/conf.pl | under: a path that only starts like a listed one is not under it
  return scalar grep { $_ eq '.' || $p eq $_ || index($p, "$_/") == 0 } @$list;
---
  return scalar grep { $_ eq '.' || $p eq $_ || index($p, $_) == 0 } @$list;
=== under not reading . as every path | method/scripts/method/lib/conf.pl | under: . holds every path
  return scalar grep { $_ eq '.' || $p eq $_ || index($p, "$_/") == 0 } @$list;
---
  return scalar grep { $p eq $_ || index($p, "$_/") == 0 } @$list;
=== problems not tagged with their key | method/scripts/method/lib/conf.pl | a bad HIGH_RISK_PATHS value is a problem tagged HIGH_RISK_PATHS
    my $problem = sub { push @problems, "$label line $n: $_[0]"; push @tags, $_[1] };
---
    my $problem = sub { push @problems, "$label line $n: $_[0]"; push @tags, undef };
=== an unknown key tagged as a key | method/scripts/method/lib/conf.pl | a misspelt key (HIGH_RISK_PATH=src) is a problem with no tag
    if (!$kind) { $problem->("unknown key $k (a typo, or a key from a newer method version)"); next }
---
    if (!$kind) { $problem->("unknown key $k (a typo, or a key from a newer method version)", $k); next }
=== HIGH_RISK_PATHS not read in PRODUCT_PATHS' syntax | method/scripts/method/lib/conf.pl | HIGH_RISK_PATHS is a list in PRODUCT_PATHS' syntax
  if ($k eq 'PRODUCT_PATHS' || $k eq 'MUTATE_PATHS' || $k eq 'HIGH_RISK_PATHS') { return check_path($val, 1) }
---
  if ($k eq 'PRODUCT_PATHS' || $k eq 'MUTATE_PATHS') { return check_path($val, 1) }
PLANTS-END
plant_data "$work/conf-plants.txt" tests/conf.test.sh
drop_sandbox "$work" || true
echo "plants: done-check: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
