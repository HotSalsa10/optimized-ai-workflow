#!/usr/bin/env bash
# Plants for lib/log.pl's writers of step 5b (gates.log's fields, the
# guard's write marks' fields (5b.2), a file written whole, the newest
# files kept) and for the settings snapshot that
# lib/watch.pl now writes with them: each planted break turns
# tests/hook-lib.test.sh (only the cases kept for its reason, after they
# pass on the clean copy) or tests/guard-watch.test.sh red for its stated
# reason, in a throwaway copy of the repo. The breaks are data: "=== NAME
# | FILE | REASON", the text OLD (in FILE exactly once), "---", the text
# NEW (tests/lib.sh, plant_data). PLANT_SHARD=K/N runs every Nth one from
# the Kth.
# shellcheck disable=SC2016 # the plants are literal perl text
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: log writers and the snapshot's file"
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/lib.txt" <<'PLANTS-END'
=== gates.log's field set dropped | method/scripts/method/lib/log.pl | append writes a gates.log line: the time, then the word, gate, tree, model, effort and reason, tab-separated
my @SETS = ([qw(rule tool hash)], [qw(word gate tree model effort why)], [qw(at top)]);
---
my @SETS = ([qw(rule tool hash)], [qw(at top)]);
=== the write marks' field set dropped | method/scripts/method/lib/log.pl | append writes a write mark line: the time, then the mark's time and the worktree's top, tab-separated
my @SETS = ([qw(rule tool hash)], [qw(word gate tree model effort why)], [qw(at top)]);
---
my @SETS = ([qw(rule tool hash)], [qw(word gate tree model effort why)]);
=== a mark's time of any shape | method/scripts/method/lib/log.pl | write marks refuse a mark's time in words
  at => qr/\A[0-9]{9,11}\.[0-9]{1,6}\z/,
---
  at => qr/\A[0-9a-z.]+\z/,
=== a mark's top of any shape | method/scripts/method/lib/log.pl | write marks refuse a mark's top as a path
  top => qr/\A[0-9]{1,20}-[0-9]{1,20}\z/,
---
  top => qr/\A\S+\z/,
=== lines reads the default set whatever it is asked for | method/scripts/method/lib/log.pl | lines reads the gates form when given its fields, and a line of the other form as another line
  my $set = $SETS[0];
  if (defined $fields) {
---
  my $set = $SETS[0];
  if (0) {
=== lines reads a line with more fields as one of its set | method/scripts/method/lib/log.pl | lines reads the gates form when given its fields, and a line of the other form as another line
if (@f == 1 + @$set && $f[0] =~ $STAMP
---
if (@f >= 1 + @$set && $f[0] =~ $STAMP
=== a receipt word in any case | method/scripts/method/lib/log.pl | gates.log refuses a receipt word in lower case
  word => qr/\A[A-Z][A-Z -]{0,30}[A-Z]\z/,
---
  word => qr/\A[A-Za-z][A-Za-z -]{0,30}[A-Za-z]\z/,
=== a gate name with spaces | method/scripts/method/lib/log.pl | gates.log refuses a gate name holding a space
  gate => qr/\A[a-z][a-z0-9-]{0,63}\z/,
---
  gate => qr/\A[a-z][a-z0-9 -]{0,63}\z/,
=== a tree id of any length | method/scripts/method/lib/log.pl | gates.log refuses a tree of 6 hex digits
  tree => qr/\A(?:[0-9a-f]{7,64}|none)\z/,
---
  tree => qr/\A(?:[0-9a-f]{1,64}|none)\z/,
=== a model id with spaces | method/scripts/method/lib/log.pl | gates.log refuses a model holding a space
  model => qr/\A[A-Za-z0-9._\[\]-]{1,64}\z/,
---
  model => qr/\A[A-Za-z0-9._\[\] -]{1,64}\z/,
=== any word as the effort | method/scripts/method/lib/log.pl | gates.log refuses an effort that is not a level
  effort => qr/\A(?:low|medium|high|xhigh|max|none)\z/,
---
  effort => qr/\A[a-z]+\z/,
=== a reason as free text | method/scripts/method/lib/log.pl | gates.log refuses a reason that is text
  why => qr/\A[a-z][a-z0-9-]{0,47}\z/,
---
  why => qr/\A[a-z][a-z0-9 -]{0,47}\z/,
=== only the fields given are checked | method/scripts/method/lib/log.pl | gates.log refuses a line without one of its fields
  for my $k (@$set) {
---
  for my $k (keys %f) {
=== a set taken when it holds any key given | method/scripts/method/lib/log.pl | fields of both sets on one line are refused, and nothing is written
    return $set unless grep { !$in{$_} } @keys;
---
    return $set if grep { $in{$_} } @keys;
=== any fields to read taken as the default set | method/scripts/method/lib/log.pl | lines refuses fields to read that are not one set, in its order
    die "log: the fields to read must be one field set, in its order\n" unless $set;
---
    $set ||= $SETS[0];
=== only the start of the bytes written | method/scripts/method/lib/log.pl | write_whole writes the whole file over the old one, and leaves no temporary file
  my $ok = print {$out} @bytes;
---
  my $ok = print {$out} substr(join('', @bytes), 0, 4096);
=== 0644 when no mode is given | method/scripts/method/lib/log.pl | write_whole makes the file with the mode given, 0600 when none is
  $mode = 0600 unless defined $mode;
---
  $mode = 0644 unless defined $mode;
=== a relative folder taken | method/scripts/method/lib/log.pl | write_whole refuses a relative folder, and a file given as the folder
  die "log: the folder must be an absolute path\n" unless defined $dir && !ref $dir && $dir ne '' && File::Spec->file_name_is_absolute($dir);
---
  die "log: the folder must be an absolute path\n" unless defined $dir && !ref $dir && $dir ne '';
=== any file name taken | method/scripts/method/lib/log.pl | write_whole refuses a file name with a slash, .. or nothing, and writes nothing
  my $ok = defined $s && !ref $s && $s =~ ($empty ? qr/\A[A-Za-z0-9._-]*\z/ : qr/\A[A-Za-z0-9._-]+\z/);
---
  my $ok = defined $s && !ref $s;
=== characters written as they come | method/scripts/method/lib/log.pl | write_whole refuses characters, and writes bytes as they are
 && (!utf8::is_utf8($data) || $data !~ /[^\x00-\x7F]/);
---
;
=== characters below U+0100 taken for bytes | method/scripts/method/lib/log.pl | write_whole refuses characters, and writes bytes as they are
(!utf8::is_utf8($data) || $data !~ /[^\x00-\x7F]/)
---
utf8::downgrade(my $copy = $data, 1)
=== no other temporary name tried | method/scripts/method/lib/log.pl | write_whole tries another temporary name when one cannot be removed (a folder there)
    die "log: cannot make $tmp ($!)\n" unless $!{EEXIST} && $n ne '9';
---
    die "log: cannot make $tmp ($!)\n";
=== the temporary file kept when the rename fails | method/scripts/method/lib/log.pl | write_whole removes its temporary file when the rename fails (a folder at the name)
  rename $tmp, $path or do { my $e = $!; unlink $tmp; die
---
  rename $tmp, $path or do { my $e = $!; die
=== a folder that is a link taken | method/scripts/method/lib/log.pl | write_whole and keep_newest refuse a folder that is a link
  die "log: the folder $dir is missing or a link\n" unless -d $dir && !-l $dir;
---
  die "log: the folder $dir is missing or a link\n" unless -d $dir;
=== times in whole seconds | method/scripts/method/lib/log.pl | keep_newest keeps the newest by their time to the fraction of a second, and says how many it removed
    my @st = Time::HiRes::stat($p);
---
    my @st = stat($p);
=== the file named counted as any other | method/scripts/method/lib/log.pl | keep_newest never removes the file named, which counts as one of those kept
    if (defined $kept && $n eq $kept) { $has_kept = 1; next }
---
    if (0) { }
=== names matched anywhere | method/scripts/method/lib/log.pl | keep_newest leaves other names and temporary files alone
  my @names = grep { /\A\Q$prefix\E[0-9a-f]+\Q$suffix\E\z/ } readdir $d;
---
  my @names = grep { /\Q$prefix\E[0-9a-f]+\Q$suffix\E/ } readdir $d;
=== links followed | method/scripts/method/lib/log.pl | keep_newest leaves links and folders alone
    next unless lstat $p;
---
    next unless stat $p;
=== a keep of 0 taken | method/scripts/method/lib/log.pl | keep_newest refuses a keep of 0 or one that is not a whole number, and removes nothing
 && $keep =~ /\A[1-9][0-9]{0,8}\z/;
---
 && $keep =~ /\A-?[0-9]+\z/;
=== an empty prefix taken | method/scripts/method/lib/log.pl | keep_newest refuses an empty prefix, which would take other files
  one_part('prefix', $prefix);
---
  one_part('prefix', $prefix, 1);
PLANTS-END
cat >"$work/watch.txt" <<'PLANTS-END'
=== the snapshot written as characters | method/scripts/method/lib/watch.pl | a non-ASCII settings value round-trips through the snapshot
  eval { Log::write_whole($dir, $name, Json::encode(\%snap), 0600) } or return;
---
  eval { Log::write_whole($dir, $name, canon(\%snap), 0600) } or return;
=== the snapshot written as UTF-8 | method/scripts/method/lib/watch.pl | the snapshot is written as ASCII JSON
  eval { Log::write_whole($dir, $name, Json::encode(\%snap), 0600) } or return;
---
  eval { my $t = canon(\%snap); utf8::encode($t); Log::write_whole($dir, $name, $t, 0600) } or return;
=== env not compared with the snapshot | method/scripts/method/lib/watch.pl | a change to a non-ASCII env value is still refused
    for my $k (qw(env hooks disableAllHooks enabledPlugins), @RUNS) {
---
    for my $k (qw(hooks disableAllHooks enabledPlugins), @RUNS) {
=== the snapshots never pruned | method/scripts/method/lib/watch.pl | the snapshots are pruned to the newest 20
  eval { Log::keep_newest($dir, 'method-settings-', '.json', $KEEP, $name) };
---

=== the new snapshot not kept by its name | method/scripts/method/lib/watch.pl | a new session's snapshot is kept even when 20 others carry later times
  eval { Log::keep_newest($dir, 'method-settings-', '.json', $KEEP, $name) };
---
  eval { Log::keep_newest($dir, 'method-settings-', '.json', $KEEP) };
=== the snapshot folder taken through its link | method/scripts/method/lib/watch.pl | with .git a link, the snapshot is written where it points, so a theme change passes
  $c = $real if defined $real;
---

PLANTS-END
# Git Bash keeps neither file modes nor links: the cases these plants
# break pass or skip there, so the plants are skipped, and said so
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    perl -0pi -e 's/^=== (?:0644 when no mode is given|a folder that is a link taken|links followed|the snapshot folder taken through its link) \|.*?(?=^=== |\z)//msg' "$work/lib.txt" "$work/watch.txt"
    skip "the plants on file modes and links (Git Bash keeps neither)"
    ;;
esac
plant_data "$work/lib.txt" tests/hook-lib.test.sh only
plant_data "$work/watch.txt" tests/guard-watch.test.sh
drop_sandbox "$work" || true
echo "plants: log writers and the snapshot's file: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
