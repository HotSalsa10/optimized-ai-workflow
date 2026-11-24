#!/usr/bin/env bash
# Plants for the release's sync (step 7.3; scripts/release/lib/sync.pl,
# M155): each planted break turns tests/sync.test.sh red for its stated
# reason, in a throwaway copy of the repo. The breaks are data: "=== NAME |
# FILE | REASON", the text OLD (in FILE exactly once), "---", the text NEW
# (tests/lib.sh, plant_data). PLANT_SHARD=K/N runs every Nth one from the
# Kth.
# shellcheck disable=SC2016 # the plants are literal perl text
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: sync"
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/plants.txt" <<'PLANTS-END'
=== sync overwrites an edited file | scripts/release/lib/sync.pl | an edited method file is refused and named, nothing written
  if (defined $old{$path} && $have eq $old{$path}) { push @plan, ['update', $path];
---
  if (defined $old{$path}) { push @plan, ['update', $path];
=== it writes before its plan is complete (a conflict does not stop the write) | scripts/release/lib/sync.pl | a conflicting floor key is refused on first install, nothing written
if ($count{conflict}) {
---
if (0) {
=== the merge drops a project hook | scripts/release/lib/sync.pl | a project hook, allow rule, own deny rule and own key survive
      push @groups, { %$g, hooks => \@own };
---
      1;
=== sync keeps a PreToolUse hook without --keep | scripts/release/lib/sync.pl | a project's PreToolUse is refused on first install
    if ($keep{$key}) {
---
    if (1) {
=== a project's PostToolUse hook kept without --keep | method/scripts/method/lib/lock.pl | a project's PostToolUse is refused on first install
our @KEEP_EVENTS = qw(PreToolUse PermissionRequest ConfigChange SessionStart SubagentStart SubagentStop UserPromptSubmit PostToolUse PostToolUseFailure PostToolBatch);
---
our @KEEP_EVENTS = qw(PreToolUse PermissionRequest ConfigChange SessionStart SubagentStart SubagentStop UserPromptSubmit PostToolUseFailure PostToolBatch);
=== an update without --profile resets to Best | scripts/release/lib/sync.pl | a Budget project updated without --profile stays Budget
my $profile = defined $profile_arg ? $profile_arg : $first ? 'best' : $lock->{profile};
---
my $profile = defined $profile_arg ? $profile_arg : 'best';
=== a method key the project set is overridden on first install | scripts/release/lib/sync.pl | a conflicting floor key is refused on first install
      if exists $cur->{$key} && Json::encode([$cur->{$key}]) ne Json::encode([$k->{keys}{$key}]);
---
      if 0;
=== method keys changed by hand are put back on an update | scripts/release/lib/sync.pl | method keys changed by hand are refused on an update
    if (@w && Lock::compare($k, $cur)) {
---
    if (0) {
=== an extra file under the method's paths is left alone | scripts/release/lib/sync.pl | an extra file under the method's paths is refused
  push @plan, ['conflict', $path, defined $old{$path} ? 'changed since method.lock and gone from the release; sync never removes it'
---
  next; push @plan, ['conflict', $path, defined $old{$path} ? 'changed since method.lock and gone from the release; sync never removes it'
=== a changed file the release removes is removed | scripts/release/lib/sync.pl | a changed file the release removes is refused
  if (defined $old{$path} && defined $have && $have eq $old{$path}) { push @plan, ['remove', $path];
---
  if (defined $old{$path}) { push @plan, ['remove', $path];
=== a file equal to the release counted as changed | scripts/release/lib/sync.pl | an interrupted run is finished by a re-run
  if ($have eq $want) { push @plan, ['unchanged', $path]; next }
---
  if (0) { }
=== an untagged source accepted | scripts/release/lib/sync.pl | an untagged source is refused
refuse_now('the release checkout is not at a v* tag (git describe --exact-match); sync installs only a tagged release') if $tst || $tag eq '';
---
$tag = 'v0.0.0' if $tst || $tag eq '';
=== a dirty source accepted | scripts/release/lib/sync.pl | a dirty source is refused
sync installs only a clean checkout of a tag') if $dirty ne '';
---
sync installs only a clean checkout of a tag') if 0;
=== the settings written after the method files | scripts/release/lib/sync.pl | a run cut off while writing the settings is finished by a re-run
put($settings_rel, $new_settings, 0644) if defined $new_settings && (!defined $cur_bytes || $cur_bytes ne $new_settings);
put($_, $rel{$_}[0], $rel{$_}[1]) for @writes;
---
put($_, $rel{$_}[0], $rel{$_}[1]) for @writes;
put($settings_rel, $new_settings, 0644) if defined $new_settings && (!defined $cur_bytes || $cur_bytes ne $new_settings);
=== a cut-off write's copy beside the settings left behind | scripts/release/lib/sync.pl | a run cut off while writing the settings is finished by a re-run, which removes what it left
if (defined $marker_tag) {
  for my $t ($Lock::SETTINGS, $MARKER, sort keys %BLOCKS) {
---
if (0) {
  for my $t ($Lock::SETTINGS, $MARKER, sort keys %BLOCKS) {
=== a cut-off write's copy under the method's paths counted as an extra file | scripts/release/lib/sync.pl | a run cut off while writing a method file is finished by a re-run
  return 0 unless defined $marker_tag;
---
  return 0;
=== the marker without the profile | scripts/release/lib/sync.pl | a run cut off while writing a method file is finished by a re-run with its --profile, which the re-run names
put($MARKER, "$tag\n$profile\n", 0644);
---
put($MARKER, "$tag\n", 0644);
=== a key the release drops kept | scripts/release/lib/sync.pl | a method key and deny entry the release drops are removed on an update
      delete $s->{$key} if !exists $k->{keys}{$key}
---
      1 if !exists $k->{keys}{$key}
=== a deny entry the release drops kept | scripts/release/lib/sync.pl | a method key and deny entry the release drops are removed on an update
    my %gone = $old ? map
---
    my %gone = 0 ? map
=== a byte-order mark read as part of the JSON | scripts/release/lib/sync.pl | a settings.json that starts with a byte-order mark is read
  (my $tj = defined $t ? $t : '') =~ s/\A\xEF\xBB\xBF//;
---
  my $tj = defined $t ? $t : '';
=== the project's settings read with perl's own numbers | scripts/release/lib/sync.pl | the project's own numbers keep their value
  my ($d, $de) = defined $t ? Json::decode($tj) : (undef, $te);
---
  my ($d, $de) = defined $t ? Json::decode($tj, 'plain') : (undef, $te);
=== a hook event's shape not checked | scripts/release/lib/sync.pl | hooks in a shape other than lists of groups are refused, nothing written
  } sort keys %{ $cur->{hooks} };
---
  } ();
=== a relative --to read from the release checkout | scripts/release/lib/sync.pl | a relative --to names the folder sync is run from
my $proj = Cwd::realpath($to);
---
my $proj = Cwd::realpath(File::Spec->rel2abs($to, $src_arg));
=== the .gitattributes block added at the end, over the project's own line-end rules | scripts/release/lib/sync.pl | a new .gitattributes block goes at the top, so the project's own line-end rules still win
    $new = $file eq '.gitattributes' ? $block . $t : $t
---
    $new = 0 ? $block . $t : $t
=== a folder that cannot be made ends the run without a FAIL line | scripts/release/lib/sync.pl | a folder sync cannot make gives its FAIL line and exit 1
  eval { File::Path::make_path(dirname($p)); 1 } or fail_now('cannot make the folder for ' . $rel);
---
  File::Path::make_path(dirname($p));
=== a method key conflict names no way out | scripts/release/lib/sync.pl | a conflicting floor key is refused on first install
      . ((grep { $_ eq $key } @Lock::PROFILE_KEYS) ? 'remove it from the file, or choose the --profile whose row sets it (method/scripts/method/profiles.tsv in the release)' : 'remove it from the file')]
---
      . '']
=== the WROTE line counts only the method files | scripts/release/lib/sync.pl | a relative --to names the folder sync is run from
my @also = ((defined
---
my @also = (); my @x = ((defined
=== CDPATH left set | scripts/release/sync.sh | an exported CDPATH does not change the folder sync.sh finds itself in
unset CDPATH
---
:
PLANTS-END
plant_data "$work/plants.txt" tests/sync.test.sh only
drop_sandbox "$work" || true
echo "plants: sync: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
