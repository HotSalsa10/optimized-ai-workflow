#!/usr/bin/env perl
# The release's sync, run by scripts/release/sync.sh (step 7.3; docs/plans/
# step7.md S2, S3, S6; DECISIONS A78; M155). Usage, from sync.sh:
#   perl sync.pl SOURCE --to PROJECT [--profile NAME] [--keep KEY]... [--write] [--source DIR]
#
# SOURCE is the checkout sync.sh sits in. It must be a clean checkout at an
# exact v* tag; the tag is the version, HEAD the source commit. The
# release's files are read from git's stored objects at HEAD (never the
# working copies, which a line-end setting could change), and lib/lock.pl
# is loaded from the source, so a release always runs its own rules.
#
# The plan (every refusal, a conflict, stops the whole run before a byte is
# written, and names the file or key):
# - method files (class M): each file under the release's method/ goes to
#   the same path without method/; settings.fragment.json goes to
#   scripts/method/settings.method.json. A file is installed when absent,
#   updated when it equals the hash method.lock gives it, unchanged when it
#   equals the release; anything else is a conflict (changed since the
#   lock, or there before the method with other content). A file under the
#   method's paths that the release does not hold is removed when it equals
#   the lock's hash, else a conflict (an extra file). A link on a target
#   path or on the way to it, a link or odd entry under the method's
#   paths, and a release file outside them are conflicts.
# - the method keys in .claude/settings.json (class K): what the release's
#   fragment and the profile's row give (Lock::expected_from). On an update
#   the current keys must equal those the installed release and the lock's
#   profile give, or those the new release gives (a run that was cut off);
#   on a first install a method key the project sets to another value, or
#   a hook naming .claude/hooks/method/ that is not the release's, is a
#   conflict, and so is each item Lock::refused names unless --keep names
#   it. The merge (S6): the method's keys and the profile's win, the deny
#   list is the method's entries in the release's order and then the
#   project's own, the method's hook entries are replaced and the
#   project's kept; the file is written by JSON::PP, sorted and indented,
#   so a second run gives the same bytes.
# - the managed blocks (class B): the "# >>> method" block in .gitignore
#   and .gitattributes is replaced where it stands, or added: at the end of
#   .gitignore, so the method's ignore wins, and at the top of
#   .gitattributes, so the project's own later line-end rules win (git
#   takes the last line that matches); text outside it is never touched;
#   two openings, or one without its end, are a conflict.
# - method.lock, written last (Lock::make, Lock::save); then Lock::verify
#   must find nothing. .method/local/sync-in-progress holds the tag and the
#   profile while the files are written; .claude/settings.json is written
#   before the method files, so a run cut off between them leaves the
#   installed fragment the old release's, from which a re-run works out the
#   old keys. A re-run that finds the marker removes what a write that was
#   cut off left, a <target>.sync-<digits> file beside a path sync writes;
#   it needs the cut-off run's --profile and --keep, which the marker's
#   line names.
# Without --profile an update keeps the lock's profile; a first install
# takes best. On an update a key or deny entry the installed release set
# and the new one drops goes (when it still holds the old release's value).
use strict;
use warnings;
no warnings q(once);    # the libraries are loaded at run time, from the release
use Cwd ();
use Digest::SHA ();
use Fcntl qw(O_WRONLY O_CREAT O_EXCL);
use File::Basename qw(dirname);
use File::Path ();
use File::Spec;
use JSON::PP ();

my $FRAG_SRC = 'method/settings.fragment.json';
my $MARKER = '.method/local/sync-in-progress';
my ($OPEN, $CLOSE) = ('# >>> method', '# <<< method');
my %BLOCKS = (
  '.gitignore' => [".method/local/"],
  '.gitattributes' => ['* text=auto eol=lf', '*.cmd text eol=crlf', '*.bat text eol=crlf', '*.ps1 text eol=crlf'],
);

sub say_line { print 'sync: ', Esc::line(join '', @_), "\n" }
sub usage {
  print "sync: usage: bash scripts/release/sync.sh --to PROJECT [--profile NAME] [--keep KEY]... [--write] [--source CHECKOUT]\n";
  exit 2;
}
sub refuse_now {
  say_line("REFUSED - $_[0]; nothing was written");
  exit 1;
}
# after the first write: say what failed, and that a second run finishes it
sub fail_now {
  say_line("FAIL - $_[0] (the run was cut off; run sync again with the same options to finish it)");
  exit 1;
}

my $src_arg = shift @ARGV;
usage() unless defined $src_arg;
my ($to, $profile_arg, $write, $source_opt, @keep);
while (@ARGV) {
  my $a = shift @ARGV;
  if ($a eq '--to' && @ARGV) { $to = shift @ARGV }
  elsif ($a eq '--profile' && @ARGV) { $profile_arg = shift @ARGV }
  elsif ($a eq '--keep' && @ARGV) { push @keep, shift @ARGV }
  elsif ($a eq '--source' && @ARGV) { $source_opt = shift @ARGV }
  elsif ($a eq '--write') { $write = 1 }
  else { usage() }
}
usage() unless defined $to;
# (read before the chdir into the release below, so a relative --to is the
# folder sync was run from)
my $proj = Cwd::realpath($to);

my $src = Cwd::realpath($src_arg);
refuse_now('the release checkout cannot be found') unless defined $src && -d $src;
require File::Spec->catfile($src, 'method/scripts/method/lib', $_) for qw(esc.pl json.pl git.pl lock.pl);
if (defined $source_opt) {
  my $s = Cwd::realpath($source_opt);
  refuse_now('--source names another checkout than the one this sync.sh is in; run the sync.sh of the release you install')
    unless defined $s && $s eq $src;
}
my %keepable = map { ($_ => 1) } @Lock::KEEP_EVENTS, @Lock::KEEP_KEYS, do { require File::Spec->catfile($src, 'method/scripts/method/lib/watch.pl'); no warnings 'once'; @Watch::RUNS };
for my $k (@keep) {
  next if $keepable{$k};
  say_line('usage - --keep names one of: ' . join(' ', sort keys %keepable));
  exit 2;
}
my %keep = map { ($_ => 1) } @keep;

# --- the source: a clean checkout at an exact v* tag ---
chdir $src or refuse_now('the release checkout cannot be entered');
my ($st, $top) = Git::run('rev-parse', '--show-toplevel');
$top =~ s/\n\z// if defined $top;
refuse_now('the release is not a git checkout') if $st || !defined Cwd::realpath($top) || Cwd::realpath($top) ne $src;
my ($dst, $dirty) = Git::run(Git::status_options(), 'status', '--porcelain', '--untracked-files=all');
refuse_now('git cannot read the release checkout') if $dst;
refuse_now('the release checkout has changes or untracked files (git status is not empty); sync installs only a clean checkout of a tag') if $dirty ne '';
my ($tst, $tag) = Git::run('describe', '--exact-match', '--tags', '--match', 'v*', 'HEAD');
$tag =~ s/\n\z// if defined $tag;
refuse_now('the release checkout is not at a v* tag (git describe --exact-match); sync installs only a tagged release') if $tst || $tag eq '';
refuse_now('the tag ' . Esc::line($tag) . ' is not a version such as v0.7.0') unless $tag =~ $Lock::VERSION_RE;
my $commit = Git::ok('rev-parse', '--verify', 'HEAD^{commit}');
$commit =~ s/\n\z//;

# the release's files, from git's stored objects at HEAD
my (%rel, @conf);    # %rel: target path => [content, mode]
for my $rec (split /\0/, Git::ok('ls-tree', '-r', '-z', '--full-tree', 'HEAD', '--', 'method')) {
  my ($meta, $path) = split /\t/, $rec, 2;
  my ($mode, $type, $id) = split / /, $meta;
  next unless defined $path;
  my $target = $path eq $FRAG_SRC ? $Lock::FRAGMENT : substr($path, length 'method/');
  if ($type ne 'blob' || ($mode ne '100644' && $mode ne '100755')) { push @conf, [$path, 'the release holds it as a link or a submodule, which sync never installs']; next }
  if (!Lock::good_path($target) || !Lock::method_path($target) || $target eq $Lock::LOCK) { push @conf, [$path, "the release holds it outside the method's paths"]; next }
  $rel{$target} = [Git::cat('blob', $id, 1), $mode eq '100755' ? 0755 : 0644];
}
push @conf, [$FRAG_SRC, 'the release has no settings fragment'] unless $rel{$Lock::FRAGMENT};
push @conf, ["method/$Lock::PROFILES", 'the release has no profiles.tsv'] unless $rel{$Lock::PROFILES};
if (@conf) {
  say_line("conflict  $_->[0]: $_->[1]") for @conf;
  refuse_now('the release itself is not one sync can install');
}
my ($frag, $fe) = Json::decode($rel{$Lock::FRAGMENT}[0], 'plain');
refuse_now("the release's settings fragment is not a JSON object") if defined $fe || ref $frag ne 'HASH';

# --- the project ---
refuse_now('the project folder ' . Esc::line($to) . ' does not exist') unless defined $proj && -d $proj;
refuse_now('the project is the release checkout itself, or inside it') if $proj eq $src || index($proj, "$src/") == 0;
my $abs = sub { File::Spec->catfile($proj, split m{/}, $_[0]) };

# a link on a path sync would write, or on the way to it
my %link_seen;
my $link_on_way = sub {
  my ($rel) = @_;
  my @parts = split m{/}, $rel;
  for my $i (0 .. $#parts) {
    my $u = join '/', @parts[0 .. $i];
    next if $link_seen{$u};
    my $p = $abs->($u);
    if (-l $p) { $link_seen{$u} = 1; return $u }
    if ($i < $#parts && -e $p && !-d _) { $link_seen{$u} = 1; return $u }
  }
  return undef;
};

my ($lock, $lp) = Lock::load($proj);
if (@$lp) {
  say_line("conflict  $Lock::LOCK: $_") for @$lp;
  refuse_now('method.lock cannot be read, so what the project changed cannot be told');
}
my $first = !$lock;
my $profile = defined $profile_arg ? $profile_arg : $first ? 'best' : $lock->{profile};
my ($k, $ke) = Lock::expected_from($frag, $rel{$Lock::PROFILES}[0], $profile);
refuse_now($ke) if $ke;
my ($marker_tag, $marker_profile);
if (-f $abs->($MARKER) && !-l $abs->($MARKER) && open my $mh, '<', $abs->($MARKER)) {
  ($marker_tag, $marker_profile) = (scalar <$mh>, scalar <$mh>);
  close $mh;
  $marker_tag = '' unless defined $marker_tag;
  chomp $marker_tag;
  $marker_profile = '' unless defined $marker_profile;
  chomp $marker_profile;
}
# a write the cut-off run left: TARGET.sync-<digits> beside a path sync writes
my $leftover = sub {
  my ($path) = @_;
  return 0 unless defined $marker_tag;
  my ($base) = $path =~ /\A(.+)\.sync-[0-9]+\z/ or return 0;
  return $rel{$base} || $base eq $Lock::LOCK || $base eq $Lock::SETTINGS || $base eq $MARKER || $BLOCKS{$base} ? 1 : 0;
};

my (@plan, @writes, @removes);    # @plan: [word, path, note]
my %old = $first ? () : map { ($_->[1] => $_->[0]) } @{ $lock->{files} };
for my $path (sort keys %rel) {
  my $want = Digest::SHA::sha256_hex($rel{$path}[0]);
  if (defined(my $l = $link_on_way->($path))) { push @plan, ['conflict', $path, 'a link, or a file where a folder belongs, on its path (' . Esc::line($l) . ')']; next }
  my $p = $abs->($path);
  if (!-e $p) { push @plan, ['install', $path]; push @writes, $path; next }
  if (!-f $p) { push @plan, ['conflict', $path, 'not a regular file']; next }
  my $have = Lock::sha_file($p);
  if (!defined $have) { push @plan, ['conflict', $path, 'cannot be read']; next }
  if ($have eq $want) { push @plan, ['unchanged', $path]; next }
  if (defined $old{$path} && $have eq $old{$path}) { push @plan, ['update', $path]; push @writes, $path; next }
  push @plan, ['conflict', $path, defined $old{$path} ? 'changed since method.lock; sync never replaces it'
    : 'there before the method, with other content; sync never replaces it'];
}
# what is under the method's paths now and not in the release
my ($disk, $fp, $blocked) = Lock::files($proj);
push @plan, map { ['conflict', "the method's paths", $_->[1]] } @$fp;
if (defined(my $l = $link_on_way->($MARKER))) { push @plan, ['conflict', $MARKER, 'a link, or a file where a folder belongs, on its path (' . Esc::line($l) . ')'] }
for my $path (@$disk) {
  next if $rel{$path};
  if ($leftover->($path)) { push @plan, ['remove', $path, 'left by the run that was cut off']; push @removes, $path; next }
  my $have = Lock::sha_file($abs->($path));
  if (defined $old{$path} && defined $have && $have eq $old{$path}) { push @plan, ['remove', $path]; push @removes, $path; next }
  push @plan, ['conflict', $path, defined $old{$path} ? 'changed since method.lock and gone from the release; sync never removes it'
    : 'not in method.lock (an extra file under the method\'s paths); remove it, or move it out of the method\'s folders'];
}
# (and those beside the paths sync writes outside them)
if (defined $marker_tag) {
  for my $t ($Lock::SETTINGS, $MARKER, sort keys %BLOCKS) {
    my ($dir, $base) = $t =~ m{\A(?:(.*)/)?([^/]+)\z};
    next if defined $link_on_way->($t);
    opendir my $dh, $abs->(defined $dir ? $dir : '.') or next;
    for my $e (sort grep { /\A\Q$base\E\.sync-[0-9]+\z/ } readdir $dh) {
      my $r = defined $dir ? "$dir/$e" : $e;
      next if -l $abs->($r) || !-f _;
      push @plan, ['remove', $r, 'left by the run that was cut off'];
      push @removes, $r;
    }
    closedir $dh;
  }
}

# --- the settings ---
my @set_notes;
my $settings_rel = $Lock::SETTINGS;
my ($cur, $cur_bytes) = ({}, undef);
if (defined(my $l = $link_on_way->($settings_rel))) {
  push @plan, ['conflict', $settings_rel, 'a link on its path (' . Esc::line($l) . ')'];
  $cur = undef;
} elsif (-e $abs->($settings_rel)) {
  my ($t, $te) = Lock::read_text($abs->($settings_rel), $settings_rel);
  # (a byte-order mark at the start, as some Windows editors write, is read
  # past, as Claude Code does; numbers are read exactly, so the project's
  # own come back as they were)
  (my $tj = defined $t ? $t : '') =~ s/\A\xEF\xBB\xBF//;
  my ($d, $de) = defined $t ? Json::decode($tj) : (undef, $te);
  if ($te || defined $de || ref $d ne 'HASH') {
    push @plan, ['conflict', $settings_rel, $te || 'not a JSON object'];
    $cur = undef;
  } else {
    ($cur, $cur_bytes) = ($d, $t);
  }
}
if ($cur) {
  for my $key (qw(hooks permissions)) {
    next unless exists $cur->{$key} && ref $cur->{$key} ne 'HASH';
    push @plan, ['conflict', $settings_rel, "its $key is not a JSON object"];
    $cur = undef;
    last;
  }
}
if ($cur && $cur->{permissions} && exists $cur->{permissions}{deny} && ref $cur->{permissions}{deny} ne 'ARRAY') {
  push @plan, ['conflict', $settings_rel, 'its permissions.deny is not a list'];
  $cur = undef;
}
if ($cur && $cur->{hooks}) {
  # each event a list of groups, each group an object with a list of hooks
  my @bad = grep {
    my $v = $cur->{hooks}{$_};
    ref $v ne 'ARRAY' || grep { ref $_ ne 'HASH' || ref $_->{hooks} ne 'ARRAY' } @$v
  } sort keys %{ $cur->{hooks} };
  push @plan, map { ['conflict', $settings_rel, 'its hooks.' . Esc::line($_) . ' is not a list of hook groups, each an object with a list of hooks'] } @bad;
  $cur = undef if @bad;
}
my %new_hooks = map { ($_ => 1) } @{ $k->{hooks} };
my $old_k;
if ($cur && $first) {
  # a first install never overrides a method key the project set itself
  for my $key (sort keys %{ $k->{keys} }) {
    push @plan, ['conflict', $settings_rel, "the project sets the method key $key to another value than the release's; "
      . ((grep { $_ eq $key } @Lock::PROFILE_KEYS) ? 'remove it from the file, or choose the --profile whose row sets it (method/scripts/method/profiles.tsv in the release)' : 'remove it from the file')]
      if exists $cur->{$key} && Json::encode([$cur->{$key}]) ne Json::encode([$k->{keys}{$key}]);
  }
  my $cp = $cur->{permissions} || {};
  for my $key (sort keys %{ $k->{permissions} }) {
    push @plan, ['conflict', $settings_rel, "the project sets the method key permissions.$key to another value than the release's; remove it from the file"]
      if exists $cp->{$key} && Json::encode([$cp->{$key}]) ne Json::encode([$k->{permissions}{$key}]);
  }
  for my $h (@{ Lock::method_hooks($cur) }) {
    next if $new_hooks{$h};
    my ($ev) = @{ (Json::decode($h, 'plain'))[0] };
    push @plan, ['conflict', $settings_rel, 'a hook on ' . Esc::line($ev) . " names $Lock::HOOK_MARK but is not one of the release's"];
  }
  for my $r (Lock::refused($cur)) {
    my ($key, $text) = @$r;
    if ($keep{$key}) { push @set_notes, ['kept', "$text, kept as --keep $key asked (it runs or loads beside the method)"] }
    else { push @plan, ['conflict', $settings_rel, "$text: a first install refuses it unless you name it with --keep $key"] }
  }
} elsif ($cur) {
  # an update: the keys must be those the installed release and the lock's
  # profile give, or already the new release's (a run that was cut off)
  (my $ok, my $oe) = Lock::expected($proj, $lock->{profile});
  $old_k = $ok;
  if ($oe) {
    push @plan, ['conflict', $settings_rel, "the installed release's method keys cannot be worked out: $oe"];
  } else {
    my @w = Lock::compare($old_k, $cur);
    if (@w && Lock::compare($k, $cur)) {
      push @plan, ['conflict', $settings_rel, $_] for @w;
    } elsif (!@w && Lock::k_hash($old_k) ne $lock->{settings} && Lock::compare($k, $cur)) {
      push @plan, ['conflict', $settings_rel, "method.lock's settings line does not match the installed release and profile"];
    }
  }
}
my $new_settings;
if ($cur) {
  my $merged = merge($cur, $frag, $k, $old_k);
  $new_settings = Lock::settings_json($merged);
  my @w = Lock::compare($k, (Json::decode($new_settings, 'plain'))[0]);
  refuse_now("the merged settings would not hold the method keys (@w); this is a defect in sync") if @w;
  if (!defined $cur_bytes) { push @plan, ['install', $settings_rel, "the method keys for the profile $profile"] }
  elsif ($cur_bytes eq $new_settings) { push @plan, ['unchanged', $settings_rel] }
  else {
    push @plan, ['update', $settings_rel, "the method keys for the profile $profile"];
    push @set_notes, ['note', "$settings_rel is written in one layout (sorted keys, two-space indent), once; its own keys are kept"] if $first;
  }
}

# --- the managed blocks ---
my %block_text;
for my $file (sort keys %BLOCKS) {
  if (defined(my $l = $link_on_way->($file))) { push @plan, ['conflict', $file, 'a link on its path (' . Esc::line($l) . ')']; next }
  my $p = $abs->($file);
  my $t = '';
  if (-e $p) {
    my ($tt, $te) = Lock::read_text($p, $file);
    if ($te) { push @plan, ['conflict', $file, $te]; next }
    $t = $tt;
  }
  my $block = join '', "$OPEN\n", (map {"$_\n"} @{ $BLOCKS{$file} }), "$CLOSE\n";
  my @lines = split /(?<=\n)/, $t;
  my @open = grep { $lines[$_] =~ /\A\Q$OPEN\E\r?\n?\z/ } 0 .. $#lines;
  my @close = grep { $lines[$_] =~ /\A\Q$CLOSE\E\r?\n?\z/ } 0 .. $#lines;
  my $new;
  if (!@open && !@close) {
    # (.gitattributes: at the top, so the project's own later rules win)
    $new = $file eq '.gitattributes' ? $block . $t : $t . ($t eq '' || $t =~ /\n\z/ ? '' : "\n") . $block;
  } elsif (@open == 1 && @close == 1 && $close[0] > $open[0]) {
    $new = join('', @lines[0 .. $open[0] - 1]) . $block . join('', @lines[$close[0] + 1 .. $#lines]);
  } else {
    push @plan, ['conflict', $file, "its method block is broken (\"$OPEN\" and \"$CLOSE\" must each be there once, in that order)"];
    next;
  }
  if ($new eq $t) { push @plan, ['unchanged', $file, 'the method block'] }
  else { push @plan, [(-e $p ? 'update' : 'install'), $file, 'the method block']; $block_text{$file} = $new }
}

# --- the plan, and the refusal or the write ---
my $from = $first ? 'a first install' : "an update from $lock->{version}";
say_line("$tag ($commit), profile $profile, $from");
say_line('an earlier run of ' . ($marker_tag =~ $Lock::VERSION_RE ? $marker_tag : 'sync')
  . ($marker_profile =~ $Lock::PROFILE_RE ? " with --profile $marker_profile" : '')
  . ' was cut off; this run finishes it when given the same --profile and --keep as that run') if defined $marker_tag;
for my $e (@plan) {
  my ($word, $path, $note) = @$e;
  say_line(sprintf('%-9s %s', $word, $path) . (defined $note ? " ($note)" : ''));
}
say_line(sprintf('%-9s %s', $_->[0], $_->[1])) for @set_notes;
say_line("lock      $Lock::LOCK (written last)");
my %count;
$count{ $_->[0] }++ for @plan;
say_line('plan: ' . join(', ', map { ($count{$_} || 0) . " $_" } qw(install update unchanged remove conflict)));
if ($count{conflict}) {
  say_line('REFUSED - ' . $count{conflict} . ' conflict' . ($count{conflict} == 1 ? '' : 's') . '; nothing was written. '
    . 'Put each method file back as its release has it (or remove the extra one), take out each method key the project set, or name a kept setting with --keep KEY, as each conflict line says, then run sync again');
  exit 1;
}
if (!$write) {
  say_line('dry run - nothing written; run again with --write to write this plan');
  exit 0;
}

# write FILE CONTENT MODE: a new file beside it, renamed into place
sub put {
  my ($rel, $content, $mode) = @_;
  my $p = $abs->($rel);
  eval { File::Path::make_path(dirname($p)); 1 } or fail_now('cannot make the folder for ' . $rel);
  my $tmp = "$p.sync-$$";
  unlink $tmp;
  sysopen my $fh, $tmp, O_WRONLY | O_CREAT | O_EXCL, 0600 or fail_now('cannot write ' . $rel);
  binmode $fh;
  my $ok = print {$fh} $content;
  $ok = close($fh) && $ok;
  $ok = chmod($mode, $tmp) && $ok;
  if (!$ok || !rename $tmp, $p) { unlink $tmp; fail_now('cannot write ' . $rel) }
}
put($MARKER, "$tag\n$profile\n", 0644);
# (the settings before the method files: see the top of this file)
put($settings_rel, $new_settings, 0644) if defined $new_settings && (!defined $cur_bytes || $cur_bytes ne $new_settings);
put($_, $rel{$_}[0], $rel{$_}[1]) for @writes;
for my $rel (@removes) {
  unlink $abs->($rel) or fail_now('cannot remove ' . $rel);
  # (a folder the removal left empty goes too, up to the method's own)
  my $d = dirname($rel);
  my %stop = map { ($_ => 1) } @Lock::DIRS, $Lock::SKILLS, '.';
  while (!$stop{$d} && rmdir $abs->($d)) { $d = dirname($d) }
}
put($_, $block_text{$_}, 0644) for sort keys %block_text;
my ($text, $me) = Lock::make($proj, $tag, $commit, $profile);
fail_now("method.lock cannot be made: $me") if $me;
my $se = Lock::save($proj, $text);
fail_now($se) if $se;
my $v = Lock::verify($proj);
if (@{ $v->{findings} }) {
  say_line("FAIL - after writing, the method's files do not match method.lock: $_->[1]") for @{ $v->{findings} };
  exit 1;
}
unlink $abs->($MARKER);
my @also = ((defined $new_settings && (!defined $cur_bytes || $cur_bytes ne $new_settings) ? $settings_rel : ()), map {"the $_ block"} sort keys %block_text);
say_line("WROTE $tag, profile $profile: " . scalar(@writes) . ' method file' . (@writes == 1 ? '' : 's') . ' written, '
  . scalar(@removes) . ' removed, ' . (@also ? join(', ', @also) . ' written, ' : '') . 'method.lock written last; review the change like any other before it is merged');
exit 0;

# merge CURRENT FRAGMENT K [OLD_K]: the project's settings with the method
# keys K (the fragment's keys with the profile's row) put in, step7.md S6;
# on an update, the keys and deny entries of OLD_K (the installed
# release's) that K no longer has are taken out
sub merge {
  my ($c, $f, $k, $old) = @_;
  my $s = (Json::decode(Json::encode($c)))[0];    # a copy, numbers exact
  my $same = sub { Json::encode([$_[0]]) eq Json::encode([$_[1]]) };
  if ($old) {
    for my $key (keys %{ $old->{keys} }) {
      delete $s->{$key} if !exists $k->{keys}{$key} && exists $s->{$key} && $same->($s->{$key}, $old->{keys}{$key});
    }
    if (ref $s->{permissions} eq 'HASH') {
      for my $key (keys %{ $old->{permissions} }) {
        delete $s->{permissions}{$key}
          if !exists $k->{permissions}{$key} && exists $s->{permissions}{$key} && $same->($s->{permissions}{$key}, $old->{permissions}{$key});
      }
    }
  }
  $s->{'$schema'} = $f->{'$schema'} if !exists $s->{'$schema'} && exists $f->{'$schema'};
  $s->{$_} = $k->{keys}{$_} for keys %{ $k->{keys} };
  my $perm = ref $s->{permissions} eq 'HASH' ? $s->{permissions} : ($s->{permissions} = {});
  $perm->{$_} = $k->{permissions}{$_} for keys %{ $k->{permissions} };
  my @method_deny = ref $f->{permissions} eq 'HASH' && ref $f->{permissions}{deny} eq 'ARRAY' ? @{ $f->{permissions}{deny} } : ();
  if (@method_deny || exists $perm->{deny}) {
    # (a deny entry only the installed release had goes)
    my %gone = $old ? map { (Json::encode([$_]) => 1) } @{ $old->{deny} } : ();
    my %seen;
    $perm->{deny} = [grep { !$seen{ Json::encode([$_]) }++ } @method_deny, grep { !$gone{ Json::encode([$_]) } } @{ $perm->{deny} || [] }];
  }
  delete $s->{permissions} unless %$perm;
  # the method's hook entries go; the project's stay; the release's are
  # added after them, event by event
  my $hooks = ref $s->{hooks} eq 'HASH' ? $s->{hooks} : {};
  for my $ev (keys %$hooks) {
    next unless ref $hooks->{$ev} eq 'ARRAY';
    my @groups;
    for my $g (@{ $hooks->{$ev} }) {
      if (ref $g ne 'HASH' || ref $g->{hooks} ne 'ARRAY') { push @groups, $g; next }
      my @own = grep { !(ref $_ eq 'HASH' && defined $_->{command} && !ref $_->{command} && index($_->{command}, $Lock::HOOK_MARK) >= 0) } @{ $g->{hooks} };
      next unless @own;
      push @groups, { %$g, hooks => \@own };
    }
    $hooks->{$ev} = \@groups;
  }
  my $fh = ref $f->{hooks} eq 'HASH' ? $f->{hooks} : {};
  for my $ev (sort keys %$fh) {
    next unless ref $fh->{$ev} eq 'ARRAY';
    push @{ $hooks->{$ev} }, @{ (Json::decode(Json::encode($fh->{$ev}), 'plain'))[0] };
  }
  delete $hooks->{$_} for grep { ref $hooks->{$_} eq 'ARRAY' && !@{ $hooks->{$_} } } keys %$hooks;
  if (%$hooks) { $s->{hooks} = $hooks } else { delete $s->{hooks} }
  return $s;
}
