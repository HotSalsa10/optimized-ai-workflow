#!/usr/bin/env bash
# Plants for the release's uninstall (step 8.2; scripts/release/lib/
# uninstall.pl, M162): each planted break turns tests/uninstall.test.sh red
# for its stated reason, in a throwaway copy of the repo. The breaks are
# data: "=== NAME | FILE | REASON", the text OLD (in FILE exactly once),
# "---", the text NEW (tests/lib.sh, plant_data). PLANT_SHARD=K/N runs
# every Nth one from the Kth. The guard's refusal of sync --write has its
# plants in tests/plants/protect.sh.
# shellcheck disable=SC2016 # the plants are literal perl text
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: uninstall"
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/plants.txt" <<'PLANTS-END'
=== uninstall removes a changed file | scripts/release/lib/uninstall.pl | a changed method file is named with its action
    if (defined $have && $have eq $listed{$path}) {
---
    if (1) {
=== it writes before its plan holds (a conflict does not stop the write) | scripts/release/lib/uninstall.pl | a changed method file is named with its action
  if ($count{conflict}) {
---
  if (0) {
=== it drops a project's own deny entry | scripts/release/lib/uninstall.pl | with no before commit, every removed key and deny entry equal to the method's is named
        if (!defined $d || ref $d || !$method{$d}) { push @keep_d, $d; next }
---
        if (!defined $d || ref $d) { push @keep_d, $d; next }
=== it drops a project deny entry equal to a method one that the before commit held | scripts/release/lib/uninstall.pl | an adopted project: install committed, then uninstall, gives the before commit's tree back byte for byte
        if ($bd{$d}) {
---
        if (0) {
=== it drops a project's own hook | scripts/release/lib/uninstall.pl | an adopted project: install committed, then uninstall, gives the before commit's tree back byte for byte
        my @own = grep { !(ref $_ eq 'HASH'
---
        my @own = grep { 0 && !(ref $_ eq 'HASH'
=== it removes a method key the project changed | scripts/release/lib/uninstall.pl | a method key the project changed is named with its action
    if (!same($s->{$key}, $want)) { push @conf,
---
    if (0) { push @conf,
=== it removes an extra file under a method path | scripts/release/lib/uninstall.pl | an extra file under a method path is named with its action
    $conflict->($path, 'not in method.lock: move it out, or keep it with --keep ' . Esc::line($path));
---
    push @removes, $path;
=== it removes an item kept with --keep | scripts/release/lib/uninstall.pl | a changed method file is named with its action, and --keep PATH keeps it
    if ($keep_path{$path}) { push @keeps, [$path, 'changed since
---
    if ($keep_path{$path}) { push @removes, $path; next; push @keeps, [$path, 'changed since
=== it leaves the .gitignore block | scripts/release/lib/uninstall.pl | a new project: install committed, then uninstall, gives the before commit's tree back byte for byte
  for my $file (@BLOCK_FILES) {
---
  for my $file (grep { $_ ne '.gitignore' } @BLOCK_FILES) {
=== it removes the lock first | scripts/release/lib/uninstall.pl | a run cut off after its first stage
  $writing = 1;
---
  $writing = 1;
  unlink abs_path($Lock::LOCK);
=== it removes files before settings | scripts/release/lib/uninstall.pl | a run cut off after its first stage
  if ($set_remove) { unlink abs_path($Lock::SETTINGS) or fail_now("cannot remove $Lock::SETTINGS") }
  elsif (defined $set_bytes) { put($Lock::SETTINGS, $set_bytes) }
  for my $rel (@removes, @last) {
    unlink abs_path($rel) or fail_now('cannot remove ' . Esc::line($rel));
    prune(dirname($rel));
  }
---
  for my $rel (@removes, @last) {
    unlink abs_path($rel) or fail_now('cannot remove ' . Esc::line($rel));
    prune(dirname($rel));
  }
  if ($set_remove) { unlink abs_path($Lock::SETTINGS) or fail_now("cannot remove $Lock::SETTINGS") }
  elsif (defined $set_bytes) { put($Lock::SETTINGS, $set_bytes) }
=== it deletes .method/local/ | scripts/release/lib/uninstall.pl | .method/local/ with a log and a stray file stays, is ignored after, and is named
  if ($local_empty) {
---
  File::Path::rmtree(abs_path($LOCAL)) if do { require File::Path; 1 }; if ($local_empty) {
=== it removes a seeded file | scripts/release/lib/uninstall.pl | after /method-setup, its files stay
  for my $f (setup_files([keys %listed])) { push @keeps,
---
  for my $f (setup_files([keys %listed])) { push @removes, $f if $f eq 'SPEC.md'; push @keeps,
=== the newline sync put before its .gitignore block left in place | scripts/release/lib/uninstall.pl | an adopted project: install committed, then uninstall, gives the before commit's tree back byte for byte
      $new =~ s/\n\z// if $at_end
---
      $new =~ s/\n\z// if 0 && $at_end
=== the before commit's settings bytes not written back | scripts/release/lib/uninstall.pl | an adopted project: install committed, then uninstall, gives the before commit's tree back byte for byte
          } elsif ($bs && same_data($s, $bs)) {
---
          } elsif (0) {
=== a re-run without the fragment refused even when the earlier run took out the rest | scripts/release/lib/uninstall.pl | a run cut off in its third stage
    if (@left || $hooks_left) {
---
    if (1) {
=== what a cut-off write left beside a file it writes not removed | scripts/release/lib/uninstall.pl | a run cut off after its first stage
    for my $e (sort grep { /\A\Q$base$SUFFIX\E[0-9]+\z/ } readdir $dh) {
---
    for my $e (()) {
=== the profiles.tsv and fragment removed among the other files | scripts/release/lib/uninstall.pl | a run cut off in its third stage
      elsif ($kfiles->{$path}) { push @last, $path }
---
      elsif ($kfiles->{$path}) { push @removes, $path }
PLANTS-END
plant_data "$work/plants.txt" tests/uninstall.test.sh only
drop_sandbox "$work" || true
echo "plants: uninstall: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
