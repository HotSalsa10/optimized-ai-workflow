#!/usr/bin/env perl
# The release's uninstall (step 8.2; docs/plans/step8.md S7; DECISIONS A82;
# M162): it takes the method back out of a project. Run by
# scripts/release/sync.sh --to PROJECT --uninstall [--keep KEY|PATH]...
# [--write]; lib/sync.pl loads this file with require once sync's own
# source checks hold (a clean checkout at an exact v* tag, perl, JSON::PP)
# and calls Uninstall::run. That checkout's tag may differ from the
# project's: uninstall reads only the project's own method.lock, its
# installed settings.method.json and its profiles.tsv, and first checks all
# three against the lock, through the checkout's lib/lock.pl.
#
# M162: uninstall removes only what method.lock and the installed fragment
# say the method put there, each unchanged since the lock, settings before
# files and the lock last, and writes nothing until its whole plan holds;
# what the project held before the install, its own files and keys, kept
# items, setup's files and .method/local/ stay and are named.
#
# The before commit: the first parent of the newest commit that added
# scripts/method/method.lock (git log --diff-filter=A -1), read with git
# cat-file, never through a working tree, attributes or text conversion.
# It says whether a method key or deny entry held that value before the
# install (it stays); whether .gitignore, .gitattributes and
# .claude/settings.json existed and whether their last line ended in a
# newline (a file the uninstall leaves empty, or holding only $schema, is
# removed only when the before commit lacks it, and the newline sync added
# before its .gitignore block goes again); and, when the project's settings
# without the method's items equal the before commit's as data (the deny
# list as a set), its exact bytes are written back. With no before commit
# (the install not committed, a shallow clone, no git, the project not the
# top folder of its repository) the plan says so, names every removed key
# and deny entry that equals the method's, keeps an emptied file, and keeps
# the final newline.
#
# The plan, written in this order, each file written as a new file beside
# it renamed into place (TARGET.uninstall-<digits>):
#   1. .method/local/.gitignore holding *, when the folder holds something
#      and has no such file (never over one), so the folder stays ignored
#      once the .gitignore block goes;
#   2. .claude/settings.json: the method's hook entries (those naming
#      .claude/hooks/method/; a group or an event left empty goes), the
#      fragment's and the profile's keys while each holds the method's
#      value, and the method's deny entries; a container the removal
#      empties (hooks, permissions, deny) goes unless the before commit
#      holds it;
#   3. every file the lock lists, while it matches the lock's hash (the
#      installed profiles.tsv and settings.method.json last: a re-run reads
#      the method's keys from the copies saved under .method/local/ before
#      the first write, and these two stay as a fallback while they can),
#      then each folder left empty;
#   4. the two "# >>> method" blocks;
#   5. the lock, last; then the saved copies, the folders left empty, and
#      .method/local/ when it is empty.
# Settings go before files, so no cut-off run leaves a hook entry naming a
# missing script. A re-run finishes a cut-off run: a listed file, a method
# key, deny entry or hook entry, or a block that is already absent counts
# as removed, and a TARGET.uninstall-<digits> file a cut write left is
# removed. With no lock it says "not installed" and exits 1, unless the
# saved copies are still there: then a run was cut off at its very end,
# and this one removes them (step 8's fresh check).
#
# Conflicts (nothing is written), each naming its one action: a changed
# method file (keep it with --keep PATH, or put back the method's copy); a
# method key the project changed (keep it with --keep KEY); a file under a
# method path the lock does not list (a file the system made: delete it;
# else move it out, or keep it with --keep PATH); a link on a path it would
# touch (replace the link with a plain file or remove it); a broken method
# block (put back both marker lines or remove the block by hand).
#
# What stays, each named: the project's own keys, hooks and deny entries,
# and method-valued ones the before commit held; items kept with --keep;
# $schema unless the before commit lacked it; .method/local/ when it holds
# something; the method's run state in git's own folder; and the files
# /method-setup wrote that mention the method (its seeded files, the
# answers, method.conf, checks/, the pack, and the always-loaded CLAUDE.md,
# .claude/CLAUDE.md, AGENTS.md and .claude/rules/), which are the
# project's words now: Claude removes or edits them with the owner on the
# same branch.
package Uninstall;
use strict;
use warnings;
use Cwd ();
use Fcntl qw(O_WRONLY O_CREAT O_EXCL);
use File::Basename qw(dirname basename);
use File::Path ();
use File::Spec;

our ($OPEN, $CLOSE) = ('# >>> method', '# <<< method');
our @BLOCK_FILES = ('.gitattributes', '.gitignore');
our $LOCAL = '.method/local';
our $SYNC_MARKER = '.method/local/sync-in-progress';
# copies of the two files the method's keys are read from, written before
# the first write and removed after the lock, so a re-run of a cut-off run
# can still tell the method's keys once the installed ones are gone, and a
# missing installed file with no copy is a removal by hand (step 8.5's
# repair, review F1 and F2)
our %SAVED = ($Lock::FRAGMENT => '.method/local/uninstall-settings.method.json', $Lock::PROFILES => '.method/local/uninstall-profiles.tsv');
our $LOCAL_OWN = '.claude/method-local';
# files a system makes in any folder it shows (macOS, Windows)
our %SYSTEM_FILES = map { ($_ => 1) } qw(.DS_Store Thumbs.db desktop.ini);
# what marks a file that mentions the method
our $MENTIONS = qr{scripts/method/|\.claude/rules/method/|/method-|>>> method-setup};
# the files /method-setup writes besides its seeded ones, and the files
# Claude Code always loads
our @SETUP_FILES = ('.claude/setup-answers.txt', '.claude/method.conf', 'CLAUDE.md', '.claude/CLAUDE.md', 'AGENTS.md');
our @SETUP_DIRS = ('checks', '.claude/rules');
our $SUFFIX = '.uninstall-';

my ($proj, $writing);
sub say_line { print 'uninstall: ', Esc::line(join '', @_), "\n" }
sub refuse_now { say_line("REFUSED - $_[0]; nothing was written"); exit 1 }
sub fail_now {
  say_line("FAIL - $_[0] (the run was cut off; run the same uninstall again to finish it)");
  exit 1;
}
sub abs_path { return File::Spec->catfile($proj, split m{/}, $_[0]) }
sub same { return Json::encode([$_[0]]) eq Json::encode([$_[1]]) }

# link_on_way PATH: the first part of PATH that is a link, or a file where a
# folder belongs, or undef
sub link_on_way {
  my ($rel) = @_;
  my @parts = split m{/}, $rel;
  for my $i (0 .. $#parts) {
    my $u = join '/', @parts[0 .. $i];
    my $p = abs_path($u);
    return $u if -l $p;
    return $u if $i < $#parts && -e $p && !-d _;
  }
  return undef;
}

# run {proj, tag, commit, keep => [...], write}: the whole uninstall; exits
sub run {
  my ($opt) = @_;
  $proj = $opt->{proj};
  my (%keep_key, %keep_path);
  for my $k (@{ $opt->{keep} }) {
    if (index($k, '/') >= 0) {
      if (!Lock::good_path($k) || !Lock::method_path($k)) {
        say_line('usage - --keep with --uninstall names a method key (such as model or effortLevel) or a file under the method\'s paths; ' . Esc::line($k) . ' is neither');
        exit 2;
      }
      $keep_path{$k} = 1;
    } elsif ($k =~ /\A(?:permissions\.)?[A-Za-z_\$][A-Za-z0-9_.-]*\z/) {
      $keep_key{$k} = 1;
    } else {
      say_line('usage - --keep with --uninstall names a method key or a file under the method\'s paths; ' . Esc::line($k) . ' is neither');
      exit 2;
    }
  }
  local $SIG{__DIE__} = sub {
    return if $^S;
    (my $e = $_[0]) =~ s/\n\z//;
    $writing ? fail_now("uninstall stopped on an error: $e") : refuse_now("uninstall stopped on an error: $e");
  };
  chdir $proj or refuse_now('the project folder cannot be entered');

  # --- the lock ---
  if (defined(my $l = link_on_way($Lock::LOCK))) { refuse_now('a link, or a file where a folder belongs, is on the path of method.lock (' . Esc::line($l) . '); replace the link with a plain file or remove it') }
  my ($lock, $lp) = Lock::load($proj);
  if (@$lp) {
    say_line("conflict  $Lock::LOCK: $_") for @$lp;
    refuse_now('method.lock cannot be read, so what the method put there cannot be told');
  }
  if (!$lock) {
    # (a run cut off after the lock went and before its saved copies did:
    # they are its last files, so this run finishes it; the fresh check)
    my @left = grep { -f abs_path($_) && !-l abs_path($_) && !defined link_on_way($_) } sort values %SAVED;
    if (@left) {
      say_line("remove    $_ (left by an uninstall cut off at its end)") for @left;
      if (!$opt->{write}) { say_line('dry run - nothing written; run it again with --write, where the project\'s hooks are off, to finish the earlier uninstall'); exit 0 }
      $writing = 1;
      for my $c (@left) { unlink abs_path($c) or fail_now('cannot remove ' . Esc::line($c)) }
      opendir my $dh, abs_path($LOCAL);
      my @in = $dh ? grep { $_ ne '.' && $_ ne '..' } readdir $dh : ('?');
      closedir $dh if $dh;
      rmdir abs_path($LOCAL) and prune(dirname($LOCAL)) if !@in;
      say_line('WROTE - finished an earlier uninstall that was cut off at its end');
      exit 0;
    }
    say_line('not installed - this project has no ' . $Lock::LOCK . ', so there is nothing of the method to take out (a run that already finished leaves none)');
    exit 1;
  }
  refuse_now("a sync run was cut off here ($SYNC_MARKER is there); finish it with the same sync first, then uninstall")
    if -e abs_path($SYNC_MARKER) || -l abs_path($SYNC_MARKER);
  my %listed = map { ($_->[1] => $_->[0]) } @{ $lock->{files} };

  # --- the before commit ---
  my ($before, $none) = before_commit();
  my $before_file = sub {
    my ($path) = @_;
    return (0) unless defined $before;
    my ($st, $out) = Git::run('ls-tree', '-r', '-z', $before, '--', $path);
    die "git cannot read the before commit\n" if $st;
    for my $rec (split /\0/, $out) {
      my ($meta, $p) = split /\t/, $rec, 2;
      next unless defined $p && $p eq $path;
      my ($mode, $type, $id) = split / /, $meta;
      return (0) unless $type eq 'blob';
      return (1, Git::cat('blob', $id, 1));
    }
    return (0);
  };

  # each stage's lines, [word, path, note]; @keeps: [path, note]
  my (@s1, @s2, @s4, @left, @conflicts, @notes, @keeps);
  my $conflict = sub { push @conflicts, ['conflict', @_] };

  # --- the method's files ---
  my ($disk, $fp, $blocked) = Lock::files($proj);
  for my $e (@$fp) {
    my ($kind, $text) = @$e;
    $conflict->("the method's paths", $kind eq 'link' ? "$text: replace the link with a plain file or remove it" : "$text: move it out, or remove it");
  }
  my %on = map { ($_ => 1) } @$disk;
  my $kfiles = { $Lock::FRAGMENT => 1, $Lock::PROFILES => 1 };
  my (@removes, @last);
  for my $path (sort keys %listed) {
    next unless $on{$path};
    my $have = Lock::sha_file(abs_path($path));
    if (defined $have && $have eq $listed{$path}) {
      if ($keep_path{$path} && !$kfiles->{$path}) { push @keeps, [$path, 'kept as --keep asked; it is the project\'s now'] }
      elsif ($kfiles->{$path}) { push @last, $path }
      else { push @removes, $path }
      next;
    }
    if ($kfiles->{$path}) { $conflict->($path, 'changed since method.lock; uninstall reads the method\'s keys from it, so it cannot be kept: put back the method\'s copy'); next }
    if ($keep_path{$path}) { push @keeps, [$path, 'changed since method.lock, kept as --keep asked; it is the project\'s now']; next }
    $conflict->($path, 'changed since method.lock: keep it with --keep ' . Esc::line($path) . ', or put back the method\'s copy');
  }
  for my $path (@$disk) {
    next if exists $listed{$path};
    if ($keep_path{$path}) { push @keeps, [$path, 'not in method.lock, kept as --keep asked; it is the project\'s now']; next }
    if ($SYSTEM_FILES{ basename($path) }) { $conflict->($path, 'not in method.lock: delete it (a file your system made)'); next }
    $conflict->($path, 'not in method.lock: move it out, or keep it with --keep ' . Esc::line($path));
  }
  # (profiles.tsv, then the fragment: the last files to go)
  my %lastset = map { ($_ => 1) } @last;
  @last = grep { $lastset{$_} } $Lock::PROFILES, $Lock::FRAGMENT;

  # --- the method's keys: from the installed fragment and profile, or from
  # the copies an earlier run of this uninstall saved, each checked against
  # the lock's hash, and their keys against its settings line ---
  my ($k, $frag, %ktext);
  my $saved_used;
  for my $path (sort keys %$kfiles) {
    next if grep { $_->[1] eq $path } @conflicts;
    my $src = $on{$path} ? $path : $SAVED{$path};
    if (!$on{$path}) {
      my $c = abs_path($SAVED{$path});
      if (-l $c || !-f $c || (Lock::sha_file($c) // '') ne ($listed{$path} // '')) {
        $conflict->($path, "it is missing, so the method's keys in $Lock::SETTINGS cannot be told: put back the release's copy");
        next;
      }
      $saved_used = 1;
    }
    my ($t, $te) = Lock::read_text(abs_path($src), $src);
    if ($te) { $conflict->($path, "$te: put back the release's copy"); next }
    $ktext{$path} = $t;
  }
  if (keys %ktext == 2) {
    my ($f, $fe) = Json::decode($ktext{$Lock::FRAGMENT}, 'plain');
    my ($kk, $ke) = defined $fe || ref $f ne 'HASH' ? (undef, "$Lock::FRAGMENT is not a JSON object") : Lock::expected_from($f, $ktext{$Lock::PROFILES}, $lock->{profile});
    if ($ke) { $conflict->($Lock::FRAGMENT, "the method's keys cannot be worked out: $ke; put back the release's copy") }
    elsif (Lock::k_hash($kk) ne $lock->{settings}) { $conflict->($Lock::LOCK, "its settings line does not match $Lock::FRAGMENT and the profile $lock->{profile}; put back the method's copies") }
    else { ($k, $frag) = ($kk, $f) }
  }
  push @notes, "an earlier uninstall was cut off after the method's settings files went; this run finishes it, from the copies it saved in $LOCAL" if $saved_used;
  # (--keep names only what the uninstall would otherwise remove: a method
  # key, or a file under the method's paths other than the lock and the two
  # files its keys are read from)
  if ($k) {
    my %onpath = map { ($_ => 1) } @$disk;
    for my $key (sort keys %keep_key) {
      (my $pk = $key) =~ s/\Apermissions\.//;
      next if $key =~ /\Apermissions\./ ? exists $k->{permissions}{$pk} : exists $k->{keys}{$key};
      say_line('usage - --keep ' . Esc::line($key) . ' is not one of the method\'s keys, so there is nothing to keep (' . join(' ', sort(keys %{ $k->{keys} }), map {"permissions.$_"} sort keys %{ $k->{permissions} }) . ')');
      exit 2;
    }
    for my $path (sort keys %keep_path) {
      next if !$kfiles->{$path} && $path ne $Lock::LOCK && (exists $listed{$path} || $onpath{$path});
      say_line('usage - --keep ' . Esc::line($path) . ($kfiles->{$path} || $path eq $Lock::LOCK ? ' cannot be kept: uninstall reads the method\'s keys and files from it' : ' names no file of the method\'s in this project'));
      exit 2;
    }
  }

  # --- stage 1: .method/local/ ---
  my ($write_local, $local_empty);
  my $lp_link = link_on_way($LOCAL);
  if (defined $lp_link) { $conflict->($LOCAL, 'a link on its path (' . Esc::line($lp_link) . '): replace the link with a plain file or remove it') }
  elsif (-d abs_path($LOCAL)) {
    opendir my $dh, abs_path($LOCAL) or refuse_now("cannot read the folder $LOCAL");
    my %ours = map { (basename($_) => 1) } values %SAVED;
    my @in = grep { $_ ne '.' && $_ ne '..' && !$ours{$_} && !/\Q$SUFFIX\E[0-9]+\z/ } readdir $dh;
    closedir $dh;
    if (!@in) { $local_empty = 1 }
    else {
      my $gi = "$LOCAL/.gitignore";
      $write_local = 1 unless -e abs_path($gi) || -l abs_path($gi);
      push @s1, ['write', $gi, 'a * line, so git still ignores the folder once the .gitignore block goes'] if $write_local;
      push @keeps, ["$LOCAL/", "the method's logs and review receipts, which git does not keep; delete the folder when you no longer need them"];
    }
  }
  # (a file where the method's folder belongs: the write first saves the
  # keys' files there, so it could not start; the fresh check)
  elsif (-e abs_path($LOCAL)) { $conflict->($LOCAL, 'a file where the method\'s folder belongs: move it out of the way') }

  # --- stage 2: the settings ---
  my ($set_bytes, $set_remove);
  if ($k) {
    my $sp = link_on_way($Lock::SETTINGS);
    if (defined $sp) { $conflict->($Lock::SETTINGS, 'a link on its path (' . Esc::line($sp) . '): replace the link with a plain file or remove it') }
    elsif (-e abs_path($Lock::SETTINGS)) {
      my ($t, $te) = Lock::read_text(abs_path($Lock::SETTINGS), $Lock::SETTINGS);
      (my $tj = defined $t ? $t : '') =~ s/\A\xEF\xBB\xBF//;
      my ($cur, $de) = defined $t ? Json::decode($tj) : (undef, $te);
      my $bad = $te || (defined $de || ref $cur ne 'HASH' ? 'it is not a JSON object' : undef);
      if (!$bad) {
        $bad ||= "its $_ is not a JSON object" for grep { exists $cur->{$_} && ref $cur->{$_} ne 'HASH' } qw(hooks permissions);
        $bad ||= 'its permissions.deny is not a list' if ref $cur->{permissions} eq 'HASH' && exists $cur->{permissions}{deny} && ref $cur->{permissions}{deny} ne 'ARRAY';
      }
      if ($bad) { $conflict->($Lock::SETTINGS, "$bad, so the method's keys cannot be taken out: fix it, then run uninstall again") }
      else {
        my ($bhas, $bbytes) = $before_file->($Lock::SETTINGS);
        my $bs;
        if ($bhas) {
          (my $bj = $bbytes) =~ s/\A\xEF\xBB\xBF//;
          my ($d, $e) = Json::decode($bj);
          $bs = $d if !defined $e && ref $d eq 'HASH';
        }
        my $r = take_out($cur, $k, $frag, $bs, $bhas, defined $before, \%keep_key);
        push @conflicts, map { ['conflict', $Lock::SETTINGS, $_] } @{ $r->{conflicts} };
        push @keeps, map { [$Lock::SETTINGS, $_] } @{ $r->{kept} };
        push @notes, map {"$Lock::SETTINGS: $_"} @{ $r->{named} };
        if ($r->{changed}) {
          my $s = $r->{settings};
          my $empty = !grep { $_ ne '$schema' } keys %$s;
          if ($empty && defined $before && !$bhas) {
            $set_remove = 1;
            push @s2, ['remove', $Lock::SETTINGS, 'nothing of the project\'s own is left in it, and the before commit lacks it'];
          } elsif ($bs && same_data($s, $bs)) {
            $set_bytes = $bbytes;
            push @s2, ['update', $Lock::SETTINGS, 'the method\'s keys, deny entries and hooks taken out; its bytes as the before commit holds them'];
          } else {
            $set_bytes = Lock::settings_json($s);
            push @s2, ['update', $Lock::SETTINGS, 'the method\'s keys, deny entries and hooks taken out'];
            push @notes, "$Lock::SETTINGS is kept, holding only " . ($empty && %$s ? '$schema' : 'nothing') . ': with no before commit, whether the project had it cannot be told' if $empty && !defined $before;
          }
        }
        push @keeps, [$Lock::SETTINGS, "the project's own: " . join('; ', @{ $r->{own} })] if @{ $r->{own} } && !$set_remove;
      }
    }
  }

  # --- stage 4: the blocks ---
  my %block_out;    # file => bytes, or undef to remove it
  for my $file (@BLOCK_FILES) {
    if (defined(my $l = link_on_way($file))) { $conflict->($file, 'a link on its path (' . Esc::line($l) . '): replace the link with a plain file or remove it'); next }
    my $p = abs_path($file);
    next unless -e $p;
    my ($t, $te) = Lock::read_text($p, $file);
    if ($te) { $conflict->($file, "$te: replace it with a plain file or remove it"); next }
    my $bom = $t =~ s/\A\xEF\xBB\xBF// ? "\xEF\xBB\xBF" : '';
    my @lines = split /(?<=\n)/, $t;
    my @open = grep { $lines[$_] =~ /\A\Q$OPEN\E\r?\n?\z/ } 0 .. $#lines;
    my @close = grep { $lines[$_] =~ /\A\Q$CLOSE\E\r?\n?\z/ } 0 .. $#lines;
    next if !@open && !@close;
    if (!(@open == 1 && @close == 1 && $close[0] > $open[0])) {
      $conflict->($file, "its method block is broken: put back both marker lines (\"$OPEN\" and \"$CLOSE\", in that order) or remove the block by hand");
      next;
    }
    my $at_end = $close[0] == $#lines;
    my $new = join('', @lines[0 .. $open[0] - 1]) . join('', @lines[$close[0] + 1 .. $#lines]);
    my ($bhas, $btext) = $before_file->($file);
    if ($bhas) {
      (my $bt = $btext) =~ s/\A\xEF\xBB\xBF//;
      # (the newline sync put before a block it added at the end)
      $new =~ s/\n\z// if $at_end && $bt ne '' && $bt !~ /\n\z/ && $new =~ /\n\z/;
    }
    # (the .gitignore block ignores .claude/settings.local.json; once it goes,
    # a local settings file that is there may be committed: say so, as it
    # may hold tokens or a hooks-off switch; review F14)
    # (by the common forms of a line that ignores it in what stays of the
    # root .gitignore, or by git itself when the rule that ignores it now is
    # not in the root .gitignore: a nested .gitignore, .git/info/exclude or
    # core.excludesFile; another form in the root file only brings this
    # note when it is not needed, so it says "may"; the fresh check)
    my $still = grep { /\A\s*\/?(?:\.claude\/)?(?:settings\.local\.json|\*\.local\.json|\*\.json)\s*\z|\A\s*\/?\.claude\/?\**\s*\z/ } split /\n/, $new;
    if ($file eq '.gitignore' && -e abs_path('.claude/settings.local.json') && !$still) {
      my $r = Git::ignored($proj, '.claude/settings.local.json');
      $still = $r && @$r && $r->[0][1] !~ /\A\.gitignore line /;
    }
    if ($file eq '.gitignore' && -e abs_path('.claude/settings.local.json') && !$still) {
      push @keeps, ['.claude/settings.local.json', 'git may no longer ignore it once the method\'s .gitignore block goes: delete it, or add it to .gitignore, before a commit picks it up'];
    }
    if ($new eq '' && defined $before && !$bhas) {
      $block_out{$file} = undef;
      push @s4, ['remove', $file, 'the method block was all it held, and the before commit lacks it'];
    } else {
      $block_out{$file} = $bom . $new;
      push @s4, ['update', $file, 'the method block taken out'];
      push @notes, "$file is kept, now empty: with no before commit, whether the project had it cannot be told" if $new eq '' && !defined $before;
    }
  }

  # --- what a cut-off run left: TARGET.uninstall-<digits> ---
  my @leftovers;
  for my $t ($Lock::SETTINGS, "$LOCAL/.gitignore", @BLOCK_FILES, values %SAVED) {
    my ($dir, $base) = $t =~ m{\A(?:(.*)/)?([^/]+)\z};
    next if defined link_on_way($t);
    opendir my $dh, abs_path(defined $dir ? $dir : '.') or next;
    for my $e (sort grep { /\A\Q$base$SUFFIX\E[0-9]+\z/ } readdir $dh) {
      my $r = defined $dir ? "$dir/$e" : $e;
      next if -l abs_path($r) || !-f _;
      push @leftovers, $r;
      push @left, ['remove', $r, 'left by an uninstall that was cut off'];
    }
    closedir $dh;
  }

  # --- what stays: setup's files, the run state in git's folder ---
  for my $f (setup_files([keys %listed])) { push @keeps, [$f, 'it mentions the method: remove or edit it with Claude on the same branch'] }
  # (in git's own folder and, from a linked worktree, its common one, where
  # the receipts and snapshots are; review F11)
  my %gm;
  for my $q (['--absolute-git-dir'], ['--git-common-dir']) {
    my ($gst, $gdir) = Git::run('rev-parse', @$q);
    next if $gst || $gdir !~ s/\n\z//;
    $gdir = File::Spec->rel2abs($gdir, $proj);
    opendir my $gh, $gdir or next;
    $gm{$_} = 1 for grep { /\Amethod-/ } readdir $gh;
    closedir $gh;
  }
  my @m = sort keys %gm;
  push @keeps, ['git\'s own folder', 'the method\'s run state there (' . join(', ', map { Esc::line($_) } @m) . '), inert without the scripts'] if @m;
  # (the project's own lines for the guard's lists; review F12)
  push @keeps, ["$LOCAL_OWN/", 'the project\'s own lines for the guard\'s lists, which do nothing once the guard is gone; delete the folder when you no longer need it']
    if -d abs_path($LOCAL_OWN) && !-l abs_path($LOCAL_OWN);

  # --- the plan, and the refusal or the write ---
  my @files_plan = map { ['remove', $_] } @removes, @last;
  say_line("$opt->{tag} ($opt->{commit}) takes out the method $lock->{version}, profile $lock->{profile}");
  say_line(defined $before ? "the before commit: $before (the first parent of the newest commit that added $Lock::LOCK)"
    : "no before commit: $none; settings come back equal as data, apart from the keys named below, and an emptied file is kept");
  say_line("note      $_") for @notes;
  my @order = (@s1, @s2, @files_plan, @s4, @left, @conflicts);
  for my $e (@order) {
    my ($word, $path, $note) = @$e;
    say_line(sprintf('%-9s %s', $word, $path) . (defined $note ? " ($note)" : ''));
  }
  say_line(sprintf('%-9s %s', 'remove', $Lock::LOCK) . ' (last)');
  say_line(sprintf('%-9s %s', 'keep', $_->[0]) . " ($_->[1])") for @keeps;
  my %count;
  $count{ $_->[0] }++ for @order;
  $count{remove}++;
  $count{keep} = scalar @keeps;
  say_line('plan: ' . join(', ', map { ($count{$_} || 0) . " $_" } qw(remove update write keep conflict)));
  if ($count{conflict}) {
    say_line('REFUSED - ' . $count{conflict} . ' conflict' . ($count{conflict} == 1 ? '' : 's') . '; nothing was written. Do what each conflict line says, then run the uninstall again');
    exit 1;
  }
  if (!$opt->{write}) {
    say_line('dry run - nothing written; run it again with --write, where the project\'s hooks are off, to write this plan');
    exit 0;
  }

  # --- the write ---
  $writing = 1;
  # (first, the copies of the files the method's keys are read from, unless
  # this run already reads them from copies an earlier run saved)
  my $made_local = !-d abs_path($LOCAL);
  if (!$saved_used) {
    eval { File::Path::make_path(abs_path($LOCAL)); 1 } or fail_now("cannot make the folder $LOCAL");
    put($SAVED{$_}, $ktext{$_}) for sort keys %SAVED;
  }
  put("$LOCAL/.gitignore", "*\n") if $write_local;
  if ($set_remove) { unlink abs_path($Lock::SETTINGS) or fail_now("cannot remove $Lock::SETTINGS") }
  elsif (defined $set_bytes) { put($Lock::SETTINGS, $set_bytes) }
  for my $rel (@removes, @last) {
    unlink abs_path($rel) or fail_now('cannot remove ' . Esc::line($rel));
    prune(dirname($rel));
  }
  for my $file (sort keys %block_out) {
    if (defined $block_out{$file}) { put($file, $block_out{$file}) }
    else { unlink abs_path($file) or fail_now("cannot remove $file") }
  }
  for my $r (@leftovers) { unlink abs_path($r) or fail_now('cannot remove ' . Esc::line($r)) }
  unlink abs_path($Lock::LOCK) or fail_now("cannot remove $Lock::LOCK");
  prune(dirname($Lock::LOCK));
  prune(dirname($Lock::SETTINGS));
  # (the copies go after the lock: until then a re-run needs them)
  for my $c (sort values %SAVED) { unlink abs_path($c) if -f abs_path($c) && !-l abs_path($c) }
  if ($local_empty || $made_local) { rmdir abs_path($LOCAL) and prune(dirname($LOCAL)) }
  say_line('WROTE - the method ' . $lock->{version} . ' taken out: ' . (@removes + @last) . ' method file' . (@removes + @last == 1 ? '' : 's')
    . ' removed, then method.lock; what stays is named above. Review the change before it is merged: its pull request carries'
    . " \"Review-Verdict: not-required - uninstall of the method $lock->{version}\", merged on its plan and this output (RISKS #21)");
  say_line('start a new Claude Code session in this project before any other work: a session open now still runs the method\'s hooks and rules as they were when it started');
  exit 0;
}

# put PATH CONTENT: a new file beside PATH, renamed into place
sub put {
  my ($rel, $content) = @_;
  my $p = abs_path($rel);
  my $tmp = "$p$SUFFIX$$";
  unlink $tmp;
  my $mode = -e $p ? (stat _)[2] & 07777 : 0644;
  sysopen my $fh, $tmp, O_WRONLY | O_CREAT | O_EXCL, 0600 or fail_now('cannot write ' . Esc::line($rel));
  binmode $fh;
  my $ok = print {$fh} $content;
  $ok = close($fh) && $ok;
  $ok = chmod($mode, $tmp) && $ok;
  if (!$ok || !rename $tmp, $p) { unlink $tmp; fail_now('cannot write ' . Esc::line($rel)) }
}

# prune DIR: DIR and each folder above it, while each is empty, up to the
# project's own folder
sub prune {
  my ($d) = @_;
  while ($d ne '.' && $d ne '' && rmdir abs_path($d)) { $d = dirname($d) }
}

# before_commit: (COMMIT, undef) or (undef, WHY there is none)
sub before_commit {
  my ($st, $top) = Git::run('rev-parse', '--show-toplevel');
  return (undef, 'the project is not in a git repository') if $st || $top !~ s/\n\z//;
  my $rt = Cwd::realpath($top);
  return (undef, 'the project is not the top folder of its git repository') unless defined $rt && $rt eq $proj;
  my ($hs) = Git::run('cat-file', '-e', "HEAD:$Lock::LOCK");
  return (undef, "the install is not committed (HEAD has no $Lock::LOCK)") if $hs;
  my ($ls, $c) = Git::run('log', '--diff-filter=A', '-1', '--format=%H', 'HEAD', '--', $Lock::LOCK);
  $c =~ s/\n\z// if defined $c;
  return (undef, "git cannot find the commit that added $Lock::LOCK") if $ls || !defined $c || $c !~ /\A[0-9a-f]{40,64}\z/;
  my ($ps, $p) = Git::run('rev-parse', '--verify', '-q', "$c^1^{commit}");
  $p =~ s/\n\z// if defined $p;
  return (undef, "the commit that added $Lock::LOCK has no parent here (the first commit, or a shallow clone)") if $ps || !defined $p || $p !~ /\A[0-9a-f]{40,64}\z/;
  return ($p, undef);
}

# take_out CURRENT K FRAGMENT BEFORE BEFORE-HAS-FILE HAS-BEFORE KEEP: the
# settings without the method's items: {settings, changed, conflicts,
# kept, named}
sub take_out {
  my ($cur, $k, $frag, $bs, $bhas, $has_before, $keep) = @_;
  my $s = (Json::decode(Json::encode($cur)))[0];    # a copy, numbers exact
  my (@conf, @kept, @named);
  for my $key (sort keys %{ $k->{keys} }) {
    next unless exists $s->{$key};
    my $want = $k->{keys}{$key};
    if ($keep->{$key}) { push @kept, "the key $key, kept as --keep asked; it is the project's now"; next }
    if (!same($s->{$key}, $want)) { push @conf, "the project changed the method key $key: keep it with --keep $key"; next }
    if ($bs && exists $bs->{$key} && same($bs->{$key}, $want)) { push @kept, "the key $key, which the before commit held with this value"; next }
    delete $s->{$key};
    push @named, "the key $key is removed: it equals the method's, and with no before commit whether the project set it so itself cannot be told" unless $has_before;
  }
  my $perm = ref $s->{permissions} eq 'HASH' ? $s->{permissions} : undef;
  my $bp = $bs && ref $bs->{permissions} eq 'HASH' ? $bs->{permissions} : {};
  if ($perm) {
    for my $key (sort keys %{ $k->{permissions} }) {
      next unless exists $perm->{$key};
      my $want = $k->{permissions}{$key};
      my $name = "permissions.$key";
      if ($keep->{$name}) { push @kept, "the key $name, kept as --keep asked; it is the project's now"; next }
      if (!same($perm->{$key}, $want)) { push @conf, "the project changed the method key $name: keep it with --keep $name"; next }
      if (exists $bp->{$key} && same($bp->{$key}, $want)) { push @kept, "the key $name, which the before commit held with this value"; next }
      delete $perm->{$key};
      push @named, "the key $name is removed: it equals the method's, and with no before commit whether the project set it so itself cannot be told" unless $has_before;
    }
    if (ref $perm->{deny} eq 'ARRAY') {
      my %bd = map { ($_ => 1) } grep { defined && !ref } (ref $bp->{deny} eq 'ARRAY' ? @{ $bp->{deny} } : ());
      my %method = map { ($_ => 1) } @{ $k->{deny} };
      my (@keep_d, %said);
      for my $d (@{ $perm->{deny} }) {
        if (!defined $d || ref $d || !$method{$d}) { push @keep_d, $d; next }
        if ($bd{$d}) { push @keep_d, $d; push @kept, 'the deny entry ' . Esc::line($d) . ', which the before commit held' unless $said{$d}++; next }
        push @named, 'the deny entry ' . Esc::line($d) . ' is removed: it equals one of the method\'s, and with no before commit whether the project had it too cannot be told'
          unless $has_before || $said{$d}++;
      }
      if (@keep_d) { $perm->{deny} = \@keep_d }
      elsif (@{ $perm->{deny} } && !exists $bp->{deny}) { delete $perm->{deny} }
      else { $perm->{deny} = [] }
    }
    delete $s->{permissions} if !%$perm && %{ $cur->{permissions} } && !($bs && exists $bs->{permissions});
  }
  if (ref $s->{hooks} eq 'HASH') {
    my $hooks = $s->{hooks};
    my $had = %$hooks;
    for my $ev (sort keys %$hooks) {
      next unless ref $hooks->{$ev} eq 'ARRAY';
      my ($groups, $cut) = ([], 0);
      for my $g (@{ $hooks->{$ev} }) {
        if (ref $g ne 'HASH' || ref $g->{hooks} ne 'ARRAY') { push @$groups, $g; next }
        my @own = grep { !(ref $_ eq 'HASH' && defined $_->{command} && !ref $_->{command} && index($_->{command}, $Lock::HOOK_MARK) >= 0) } @{ $g->{hooks} };
        if (@own == @{ $g->{hooks} }) { push @$groups, $g; next }
        $cut = 1;
        push @$groups, { %$g, hooks => \@own } if @own;
      }
      next unless $cut;
      if (@$groups) { $hooks->{$ev} = $groups } else { delete $hooks->{$ev} }
    }
    delete $s->{hooks} if $had && !%$hooks && !($bs && exists $bs->{hooks});
  }
  if (exists $s->{'$schema'} && $has_before && !($bs && exists $bs->{'$schema'}) && ref $frag eq 'HASH' && exists $frag->{'$schema'} && same($s->{'$schema'}, $frag->{'$schema'})) {
    delete $s->{'$schema'};
  }
  my $changed = Json::encode($s) ne Json::encode($cur);
  # what of the project's own stays, by kind (S7: each kind named): its own
  # keys and permissions keys by name, its hook entries and deny entries by
  # number, and $schema (review F3)
  # (a key's name as UTF-8 bytes, as Esc::line reads them, and in quotes
  # when it holds a ; or starts or ends with a space, so one name cannot
  # read as two; the fresh check)
  my $key_name = sub {
    my ($n) = @_;
    utf8::encode($n) if utf8::is_utf8($n);
    my $e = Esc::line($n);
    return $e =~ /;|\A\s|\s\z|\A\z/ ? qq("$e") : $e;
  };
  my (@own, %mkey);
  %mkey = map { ($_ => 1) } keys %{ $k->{keys} };
  push @own, map { $key_name->($_) } grep { !$mkey{$_} && $_ ne '$schema' && $_ ne 'hooks' && $_ ne 'permissions' } sort keys %$s;
  if (ref $s->{permissions} eq 'HASH') {
    my %mperm = map { ($_ => 1) } keys %{ $k->{permissions} };
    push @own, map { 'permissions.' . $key_name->($_) } grep { $_ ne 'deny' && !$mperm{$_} } sort keys %{ $s->{permissions} };
    my %method = map { ($_ => 1) } @{ $k->{deny} };
    my $nd = ref $s->{permissions}{deny} eq 'ARRAY' ? grep { !defined || ref || !$method{$_} } @{ $s->{permissions}{deny} } : 0;
    push @own, "$nd deny entr" . ($nd == 1 ? 'y' : 'ies') if $nd;
  }
  if (ref $s->{hooks} eq 'HASH') {
    my $nh = 0;
    for my $ev (values %{ $s->{hooks} }) {
      next unless ref $ev eq 'ARRAY';
      $nh += ref $_ eq 'HASH' && ref $_->{hooks} eq 'ARRAY' ? scalar @{ $_->{hooks} } : 0 for @$ev;
    }
    push @own, "$nh hook" . ($nh == 1 ? '' : 's') if $nh;
  }
  push @own, '$schema' if exists $s->{'$schema'};
  return { settings => $s, changed => $changed, conflicts => \@conf, kept => \@kept, named => $changed ? \@named : [], own => \@own };
}

# same_data A B: equal as data, each permissions.deny compared as a set
sub same_data {
  my ($x, $y) = @_;
  my $norm = sub {
    my $c = (Json::decode(Json::encode($_[0])))[0];
    if (ref $c->{permissions} eq 'HASH' && ref $c->{permissions}{deny} eq 'ARRAY') {
      $c->{permissions}{deny} = [sort { Json::encode([$a]) cmp Json::encode([$b]) } @{ $c->{permissions}{deny} }];
    }
    return Json::encode($c);
  };
  return $norm->($x) eq $norm->($y);
}

# setup_files LISTED: the files /method-setup writes (from the installed
# templates the lock lists, the answers, method.conf, checks/, the pack) and
# the always-loaded files, that mention the method, sorted
sub setup_files {
  my ($listed) = @_;
  my %cand = map { ($_ => 1) } @SETUP_FILES;
  for my $p (@$listed) {
    next unless $p =~ m{\Ascripts/method/templates/(.+)\.tmpl\z};
    my $t = $1;
    $cand{ $t eq 'method.conf' ? '.claude/method.conf' : $t eq 'pull_request_template.md' ? '.github/pull_request_template.md'
      : $t eq 'method-checks.yml' ? '.github/workflows/method-checks.yml' : $t } = 1;
  }
  my $walk;
  $walk = sub {
    my ($rel) = @_;
    return if Lock::method_path($rel);
    my $p = abs_path($rel);
    return if -l $p;
    if (-f _) { $cand{$rel} = 1; return }
    return unless -d _;
    opendir my $d, $p or return;
    my @e = sort grep { $_ ne '.' && $_ ne '..' } readdir $d;
    closedir $d;
    $walk->("$rel/$_") for @e;
  };
  $walk->($_) for @SETUP_DIRS;
  if (opendir my $d, abs_path($Lock::SKILLS)) {
    $walk->("$Lock::SKILLS/$_") for sort grep { /\Apack-/ } readdir $d;
    closedir $d;
  }
  my @out;
  for my $rel (sort keys %cand) {
    next if Lock::method_path($rel) || defined link_on_way($rel);
    my ($t) = Lock::read_text(abs_path($rel), $rel);
    push @out, $rel if defined $t && $t =~ $MENTIONS;
  }
  return @out;
}

1;
