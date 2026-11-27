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
  # --- the write ---
  $writing = 1;
---
  # --- the write ---
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
  if ($local_empty || $made_local) {
---
  File::Path::rmtree(abs_path($LOCAL)); if ($local_empty || $made_local) {
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
=== what a cut-off write left beside a file it writes not removed | scripts/release/lib/uninstall.pl | a run cut off after its first stage
    for my $e (sort grep { /\A\Q$base$SUFFIX\E[0-9]+\z/ } readdir $dh) {
---
    for my $e (()) {
=== the copies of the keys' files not saved before the first write | scripts/release/lib/uninstall.pl | a run cut off after its third stage with --keep PATH is finished by a re-run
    put($SAVED{$_}, $ktext{$_}) for sort keys %SAVED;
---
    1;
=== a missing settings file with no saved copy let through | scripts/release/lib/uninstall.pl | the method's settings files removed by hand, with no copy saved by an earlier run, are refused
        $conflict->($path, "it is missing, so the method's keys in $Lock::SETTINGS cannot be told: put back the release's copy");
        next;
---
        next;
=== what of the project's own stays not named | scripts/release/lib/uninstall.pl | what of the project's own stays in its settings is named, by kind
        push @keeps, [$Lock::SETTINGS, "the project's own: " . join('; ', @{ $r->{own} })] if @{ $r->{own} } && !$set_remove;
---
        1;
=== a changed installed fragment not refused as the keys' source | scripts/release/lib/uninstall.pl | a changed installed settings.method.json is refused, as uninstall reads the method's keys from it
    if ($kfiles->{$path}) { $conflict->($path, 'changed since method.lock; uninstall reads
---
    if (0) { $conflict->($path, 'changed since method.lock; uninstall reads
=== the lock's settings line not checked | scripts/release/lib/uninstall.pl | a lock whose settings line does not match the installed fragment and profile is refused
    elsif (Lock::k_hash($kk) ne $lock->{settings}) {
---
    elsif (0) {
=== a lock that cannot be read taken as not installed | scripts/release/lib/uninstall.pl | a lock that cannot be read is refused
    refuse_now('method.lock cannot be read, so what the method put there cannot be told');
---
    1;
=== a cut-off sync run not refused | scripts/release/lib/uninstall.pl | a sync run that was cut off is refused until sync finishes it
    if -e abs_path($SYNC_MARKER) || -l abs_path($SYNC_MARKER);
---
    if 0;
=== --keep not checked against what the uninstall would remove | scripts/release/lib/uninstall.pl | --keep of a key that is not the method's is bad usage
  if ($k) {
    my %onpath
---
  if (0) {
    my %onpath
=== the guard's own lists not named | scripts/release/lib/uninstall.pl | the guard's own lists in .claude/method-local/ stay and are named
    if -d abs_path($LOCAL_OWN) && !-l abs_path($LOCAL_OWN);
---
    if 0;
=== a block file's conflict without its action | scripts/release/lib/uninstall.pl | a .gitignore that is a folder is a conflict with its action
    if ($te) { $conflict->($file, "$te: replace it with a plain file or remove it"); next }
---
    if ($te) { $conflict->($file, $te); next }
=== git's common folder not read from a linked worktree | scripts/release/lib/uninstall.pl | from a linked worktree, the run state in git's common folder is named
  for my $q (['--absolute-git-dir'], ['--git-common-dir']) {
---
  for my $q (['--absolute-git-dir']) {
=== a local settings file left unignored without a word | scripts/release/lib/uninstall.pl | a local settings file git no longer ignores once the .gitignore block goes is named
      push @keeps, ['.claude/settings.local.json', 'git may no longer ignore it
---
      0 && push @keeps, ['.claude/settings.local.json', 'git may no longer ignore it
=== the rule git ignores the local settings file by not asked for | scripts/release/lib/uninstall.pl | a local settings file a nested .gitignore still ignores brings no note
      $still = $r && @$r && $r->[0][1] !~ /\A\.gitignore line /;
---
      $still = 0;
=== a run cut off after the lock went left as not installed | scripts/release/lib/uninstall.pl | a run cut off after the lock went, before its saved copies, is finished by a re-run
    if (@left) {
---
    if (0) {
=== a file where .method/local belongs not named in the plan | scripts/release/lib/uninstall.pl | a file where .method/local belongs is a conflict with its action
  elsif (-e abs_path($LOCAL)) { $conflict->($LOCAL, 'a file where the method\'s folder belongs: move it out of the way') }
---
  elsif (0) { }
=== a key's name escaped as characters, not as UTF-8 bytes | scripts/release/lib/uninstall.pl | a key's name in the project's own line is shown as written
    utf8::encode($n) if utf8::is_utf8($n);
---
    1;
=== a key's name holding a ; not put in quotes | scripts/release/lib/uninstall.pl | a key's name in the project's own line is shown as written
    return $e =~ /;|\A\s|\s\z|\A\z/ ? qq("$e") : $e;
---
    return $e;
=== the profiles.tsv and fragment removed among the other files | scripts/release/lib/uninstall.pl | a run cut off late in its third stage still has profiles.tsv and the fragment
      elsif ($kfiles->{$path}) { push @last, $path }
---
      elsif ($kfiles->{$path}) { push @removes, $path }
PLANTS-END
plant_data "$work/plants.txt" tests/uninstall.test.sh only
drop_sandbox "$work" || true
echo "plants: uninstall: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
