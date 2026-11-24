#!/usr/bin/env bash
# Plants for setup-write (step 7.4; method/scripts/method/lib/setup.pl,
# M100, M156) and for the answers method-setup's SKILL.md asks for (step
# 7.5): each planted break turns tests/setup.test.sh red for its
# stated reason, in a throwaway copy of the repo. The breaks are data: "===
# NAME | FILE | REASON", the text OLD (in FILE exactly once), "---", the
# text NEW (tests/lib.sh, plant_data). PLANT_SHARD=K/N runs every Nth one
# from the Kth.
# shellcheck disable=SC2016 # the plants are literal perl text
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: setup"
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/plants.txt" <<'PLANTS-END'
=== Budget drops a deny rule | method/scripts/method/lib/setup.pl | every combination: the method keys, deny list and hooks as released
  $s->{$_} = $kn->{keys}{$_} for @Lock::PROFILE_KEYS;
---
  $s->{$_} = $kn->{keys}{$_} for @Lock::PROFILE_KEYS;
  shift @{ $s->{permissions}{deny} } if $a->{PROFILE} eq 'budget';
=== an answer removes a HIGH_RISK_PATHS entry | method/scripts/method/lib/setup.pl | every combination: HIGH_RISK_PATHS keeps every entry it had
    my @all = (@n, @old);
---
    my @all = $k eq 'HIGH_RISK_PATHS' ? (@n) : (@n, @old);
=== setup overwrites an existing AGENTS.md | method/scripts/method/lib/setup.pl | every combination: no pre-existing file changed outside a managed block
    if (!defined $cur) {
      my $new = '';
---
    if (!defined $cur || $target eq 'AGENTS.md') {
      my $new = '';
=== a second run reorders a block | method/scripts/method/lib/setup.pl | every combination: a second run gives the same bytes
    my @all = (@n, @old);
---
    my @all = %$old_v ? (reverse(@n), @old) : (@n, @old);
=== a key written both inside and outside the block accepted | method/scripts/method/lib/setup.pl | a key setup writes that is also set outside its block is refused and named
      . ' the block or remove it (through a reviewed change), then run setup again' if exists $ov_v->{$k};
---
      . ' the block or remove it (through a reviewed change), then run setup again' if 0;
=== setup-write rehashes a weakened deny list | method/scripts/method/lib/setup.pl | a method deny entry removed by hand: --write is refused naming it
    Lock::compare(\%kk, $s);
---
    ();
=== a missing named path written to HIGH_RISK_PATHS | method/scripts/method/lib/setup.pl | every combination: no HIGH_RISK_PATHS entry names no path
  my @risk = grep { $exists->($_) } @{ $a->{RISK_PATH} };
---
  my @risk = @{ $a->{RISK_PATH} };
=== the shape check dropped (a TAB or CR in a value) | method/scripts/method/lib/setup.pl | shape refusals name the key or line and write nothing
    if ($v =~ /[\x00-\x1F\x7F]/) {
---
    if (0) {
=== the secret scan skipped | method/scripts/method/lib/setup.pl | a token-shaped answer is refused, named by its key, and its value appears nowhere
    if (my @s = Secrets::scan_bytes($v)) {
---
    if (my @s = ()) {
=== the template hash comparison dropped | method/scripts/method/lib/setup.pl | a method input changed by hand (a template, method.lock's settings line)
    if (!defined $hash{$rel} || !defined $h || $h ne $hash{$rel}) {
---
    if (!defined $hash{$rel} || !defined $h) {
=== a stale settings line in method.lock taken over | method/scripts/method/lib/setup.pl | a method input changed by hand (a template, method.lock's settings line)
  if (Lock::k_hash($kc) ne $lock->{settings}) {
---
  if (0) {
=== VERDICTS_FROM moved to main's tip after main holds the method | method/scripts/method/lib/setup.pl | VERDICTS_FROM is main's tip only while main does not hold the method
      $tip = $det->{main_has_method} ? undef : $det->{main_tip};
---
      $tip = $det->{main_tip};
=== a re-run turns the smoke row off again | method/scripts/method/lib/setup.pl | a smoke row turned on stays on in a re-run with the same command
        if ($on_now{$on}) { push @l, $on; $smoke = 'on' }
---
        if (0) { push @l, $on; $smoke = 'on' }
=== a second fast-tests row id accepted | method/scripts/method/lib/setup.pl | a row id setup turns on that checks/pack.tsv already uses is refused
        . ($answer_of{$id} || 'its answer') . ' empty, then run setup again' if $ids{$id};
---
        . ($answer_of{$id} || 'its answer') . ' empty, then run setup again' if 0;
=== a path setup writes itself counted as missing | method/scripts/method/lib/setup.pl | a named path setup writes itself (checks, REVIEW.md) counts as there
    return 1 if grep { $_ eq $rel || index($_, "$rel/") == 0 } (grep { defined $ov->{$_} } keys %$ov), keys %tmpl_text, $WORKING, $PROJECT;
---
    return 1 if grep { $_ eq $rel || index($_, "$rel/") == 0 } (grep { defined $ov->{$_} } keys %$ov);
=== settings.json rewritten for its layout alone | method/scripts/method/lib/setup.pl | settings.json laid out otherwise, with the profile unchanged, is left as it is
  if (Json::encode($s) ne $s_was) {
---
  if ($new_settings ne $st) {
=== a key of the project's own inside the block dropped on a re-run | method/scripts/method/lib/setup.pl | a key of the project's own inside setup's method.conf block is refused on a re-run
  for my $k (sort grep { !$ours{$_} } keys %$old_v) {
---
  for my $k (()) {
=== a cut-off write's copy left beside the file | method/scripts/method/lib/setup.pl | a copy left by a cut-off write (method.lock.setup-<pid>) is removed
    unlink map { File::Spec->catfile($dir, $_) } grep { /\A\Q$base\E\.setup-[0-9]+\z/ } readdir $dh;
---
    ();
=== 7.5 an empty list answer kept | method/scripts/method/lib/setup.pl | a list answer left empty (RULE, PRODUCT_PATH, RISK_PATH) adds nothing
      next if $v eq '' && $k ne 'TOUCHES';
---
=== 7.5 the skill asks for a value setup does not take | method/.claude/skills/method-setup/SKILL.md | method-setup's SKILL.md asks for exactly the answer keys and values setup takes
(PACE larger)
---
(PACE large)
=== 7.5 the skill asks for a key setup does not know | method/.claude/skills/method-setup/SKILL.md | method-setup's SKILL.md asks for exactly the answer keys and values setup takes
(STRICT strict)
---
(STRICTNESS strict)
=== 7.5 the skill leaves out a profile | method/.claude/skills/method-setup/SKILL.md | method-setup's SKILL.md asks for exactly the answer keys and values setup takes
; Balanced, cheaper and slower to catch subtle bugs (PROFILE balanced)
---

PLANTS-END
plant_data "$work/plants.txt" tests/setup.test.sh only
drop_sandbox "$work" || true
echo "plants: setup: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
