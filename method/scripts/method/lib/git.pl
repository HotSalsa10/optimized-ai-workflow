#!/usr/bin/env perl
# The method's one git runner (M048: one rule, one implementation). The perl
# helpers load it with require; every git call they make goes through it.
#
# Loading it clears the variables that would point git at another
# repository, index, object store, history or settings file, or change what
# it shows: GIT_DIR, GIT_WORK_TREE, GIT_COMMON_DIR, GIT_INDEX_FILE, GIT_CONFIG,
# GIT_OBJECT_DIRECTORY, GIT_ALTERNATE_OBJECT_DIRECTORIES, GIT_SHALLOW_FILE,
# GIT_IMPLICIT_WORK_TREE, GIT_PREFIX, GIT_INTERNAL_SUPER_PREFIX,
# GIT_NAMESPACE, GIT_DIFF_OPTS, GIT_EXTERNAL_DIFF, GIT_REPLACE_REF_BASE and
# the GIT_*_PATHSPECS settings. Replace refs and grafts are turned off. A
# partial clone does not fetch a missing object (GIT_NO_LAZY_FETCH, git 2.44
# and later; older git still may), so reading stays local. So
# git finds the repository from the current folder, as a reader of the
# files there does.
#
# Every call gets: --no-optional-locks (git status does not rewrite the
# index), --literal-pathspecs (a path is never pathspec magic),
# core.commitGraph=false (a commit-graph file is a local file that could
# misreport history), core.fsmonitor=false (a file-system monitor is a
# local program that would run inside the caller and could hide changes)
# and safe.bareRepository=explicit (a folder laid out like a repository,
# committed inside another one, is never used as one; git 2.38 or later).
# Git::run also adds core.ignoreCase=false where the working tree's file
# system tells case apart (Git::case_pin): there a true value would hide an
# untracked file whose name differs from a tracked one only by case. Where it
# folds case, git's own setting stays, so ignore and attribute patterns match
# as git matches them. (Git::cat and secrets.pl use @GIT directly: their
# commands do not read core.ignoreCase.)
# A caller adds its own -c options in front of the git command.
#
#   Git::run(ARGS)      (exit status, standard output); stdin and stderr on
#                       the null device, because git's messages can quote
#                       file names raw
#   Git::run_input(INPUT, ARGS)  the same, with INPUT on git's standard input
#   Git::ok(ARGS)       standard output, or dies "git <command> failed"
#   Git::cat(TYPE, ID, ONCE, MAX)  a stored object's content, checked against
#                       its id; ONCE: not kept for a later read; MAX: undef
#                       when it is larger than MAX bytes (read and dropped)
#   Git::object_id(TYPE, CONTENT, LIKE)  the id git gives CONTENT
#   Git::top()          (TOP, PROBLEM): the top folder of the working tree
#                       git finds from the current folder; PROBLEM is undef,
#                       'none' (not inside a working tree) or 'elsewhere'
#                       (git's working tree is not the first folder at or
#                       above this one that holds a .git entry, where git
#                       itself looks: a core.worktree setting points it at
#                       another copy)
#   Git::status_options(GIT...)  -c options for `git status` in the
#                       repository GIT points at, so it runs no program and
#                       trusts no stat shortcut: every filter driver set in
#                       its settings is turned off (a clean filter is a local
#                       program that could hide an edit, like a file-system
#                       monitor), and core.trustctime and core.checkStat are
#                       set to git's defaults
#   Git::status_options_all(DIR, SUBS)  the same for DIR and every checked-out
#                       submodule, so no submodule's own filter runs either
#   Git::exact(REF)     the commit id of a full ref name, or undef
#   Git::main_ref()     (main's full ref name, its commit id), or () when
#                       there is none: from origin, or the only remote when
#                       there is no origin, its HEAD (unless it names HEAD's
#                       own branch), then its main and master; local main and
#                       master only when there is no remote (Git::main_refs);
#                       Git::no_main() says where it looked, and
#                       Git::no_main_action() what to do
#   Git::main_remote()  (that remote's name), (undef) with no remote, or
#                       ('', WHY) when it cannot be told
#   Git::hint_name(NAME, PLACEHOLDER)  NAME when it is safe in a command to
#                       copy and paste, else PLACEHOLDER (<remote>)
#   Git::fetched(REMOTE, REF)  1 when REMOTE's fetch settings write REF, so
#                       git fetch moves it
#   Git::merge_base(A, B)  ('ok', ids), ('none', what to do) or ('error')
#   Git::message(ID)    a commit's message, checked against its id
#   Git::ignored(DIR, PATH...)  [[PATH, WHY], ...]: each PATH (relative to
#                       the folder DIR) that git ignores and does not track,
#                       so a commit would leave it out; WHY names the ignore
#                       file, its line and its pattern. [] when no .git is
#                       found at or above DIR; undef when git cannot tell
#                       (one is there, but git refuses the repository, for
#                       one owned by another user, or fails)
package Git;
use strict;
use warnings;
use Cwd ();
use File::Basename ();
use File::Spec;
use IO::Handle ();
use IPC::Open2 ();

delete @ENV{qw(GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_CONFIG GIT_OBJECT_DIRECTORY
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_SHALLOW_FILE GIT_IMPLICIT_WORK_TREE GIT_PREFIX GIT_INTERNAL_SUPER_PREFIX
  GIT_NAMESPACE GIT_DIFF_OPTS GIT_EXTERNAL_DIFF GIT_REPLACE_REF_BASE
  GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS)};
# git's trace settings would make it write files where the session says
delete @ENV{ grep {/\AGIT_TRACE/} keys %ENV };
@ENV{qw(GIT_TRACE2 GIT_TRACE2_EVENT GIT_TRACE2_PERF)} = (0, 0, 0);    # (also over trace2.* settings)
$ENV{GIT_NO_REPLACE_OBJECTS} = 1;
$ENV{GIT_NO_LAZY_FETCH} = 1;    # a partial clone never fetches a missing object (git 2.44 and later)
$ENV{GIT_GRAFT_FILE} = File::Spec->catfile(File::Spec->devnull, 'none');    # a grafts file that cannot exist, so none is read and nothing is written

our @GIT = ('git', '--no-optional-locks', '--literal-pathspecs', '-c', 'core.commitGraph=false',
  '-c', 'core.fsmonitor=false', '-c', 'safe.bareRepository=explicit');

# the git command in ARGS, after any -c NAME=VALUE and -C FOLDER pairs
sub command_name {
  my @a = @_;
  splice @a, 0, 2 while @a >= 2 && ($a[0] eq '-c' || $a[0] eq '-C');
  return defined $a[0] ? $a[0] : 'git';
}

sub top {
  my ($st, $top) = run('rev-parse', '--show-toplevel');
  return (undef, 'none') if $st || $top !~ /\A(.+)\n\z/;
  $top = $1;
  my $home = Cwd::getcwd();
  return (undef, 'none') unless defined $home;
  until (-e File::Spec->catfile($home, '.git')) {
    my $up = File::Basename::dirname($home);
    return (undef, 'none') if $up eq $home;
    $home = $up;
  }
  my @home_id = stat $home;
  my @top_id = stat $top;
  return ($top, 'elsewhere') unless @home_id && @top_id && $home_id[0] == $top_id[0] && $home_id[1] == $top_id[1];
  return ($top, undef);
}

sub status_options {
  my @g = @_;
  # (also passed to the git status git runs inside each submodule, where a
  # status.showUntrackedFiles=no of its own would hide its untracked files)
  my @o = ('-c', 'core.trustctime=true', '-c', 'core.checkStat=default', '-c', 'status.showUntrackedFiles=normal');
  my ($st, $names) = run(@g, 'config', '--name-only', '-z', '--get-regexp', '^filter\.');
  return @o if $st;
  for my $name (split /\0/, $names) {
    # a driver may have an empty name ([filter ""]), which filter= selects
    my ($driver) = $name =~ /\Afilter\.(.*)\.[^.]+\z/s or next;
    die "a filter driver has a name git cannot be told to skip\n" if $driver =~ /[=\n]/;
    push @o, map { ('-c', "filter.$driver.$_") } 'clean=', 'smudge=', 'process=', 'required=false';
  }
  return @o;
}

# case_pin: (-c core.ignoreCase=false), or () where the working tree's file
# system folds case: there the top folder and the same name with its case
# flipped, in the folder above, are one folder. (The working tree decides: a
# case twin can sit there only where it tells case apart, and where it folds,
# git's own setting matches patterns as checkout does.) Found once, with the
# first git call; when it cannot be told (a name with no letters), the pin
# stays.
my $case_pin;
sub case_pin {
  return @$case_pin if $case_pin;
  $case_pin = [];    # (the probe's own git call runs without it)
  my ($st, $top) = run('rev-parse', '--show-toplevel');
  my $folds;
  if (!$st && $top =~ s/\n\z//) {
    my ($vol, $dirs, $name) = File::Spec->splitpath($top);
    (my $flipped = $name) =~ tr/a-zA-Z/A-Za-z/;
    if ($flipped ne $name) {
      my @a = stat $top;
      my @b = stat File::Spec->catpath($vol, $dirs, $flipped);
      $folds = @a && @b && $a[0] == $b[0] && $a[1] == $b[1];
    }
  }
  $case_pin = $folds ? [] : ['-c', 'core.ignoreCase=false'];
  return @$case_pin;
}

sub run { return run_input(undef, @_) }

# run_input INPUT ARGS: INPUT (undef: none) is written to git's standard
# input by a process of its own, so a git that writes before it has read
# all of it cannot stall the run
sub run_input {
  my ($input, @args) = @_;
  my @cmd = (@GIT, case_pin(), @args);
  my $pid = open(my $fh, '-|');
  die "cannot run git\n" unless defined $pid;
  if (!$pid) {
    # the child leaves with POSIX::_exit, so no END block or destructor of
    # the caller runs here and writes into git's pipe
    require POSIX;
    open STDERR, '>', File::Spec->devnull;
    if (defined $input) {
      pipe(my $r, my $w) or POSIX::_exit(127);
      my $wpid = fork;
      POSIX::_exit(127) unless defined $wpid;
      if (!$wpid) {
        close $r;
        close STDOUT;    # (so the caller's read ends when git's does)
        binmode $w;
        print {$w} $input;
        close $w;
        POSIX::_exit(0);
      }
      close $w;
      open STDIN, '<&', $r or POSIX::_exit(127);
    } else {
      open STDIN, '<', File::Spec->devnull;
    }
    exec { $cmd[0] } @cmd or POSIX::_exit(127);
  }
  binmode $fh;
  my $out = do { local $/; <$fh> };
  close $fh;
  return ($?, defined $out ? $out : '');
}

sub ok {
  my ($st, $out) = run(@_);
  die 'git ' . command_name(@_) . " failed\n" if $st;
  return $out;
}

# submodules DIR: [path relative to DIR, folder, problem] for every
# submodule folder that holds anything in the repository whose working tree
# has its top at DIR, nested ones too (up to 8 deep). PROBLEM is undef for
# a submodule that is checked out; otherwise it says why git cannot see a
# change in the folder (git's own status then reports nothing for it). Only
# checked-out submodules are walked into.
sub submodules {
  my ($dir, $prefix, $depth) = @_;
  ($prefix, $depth) = ('', 0) unless defined $prefix;
  my (@s, %seen);
  for my $rec (split /\0/, ok('-C', $dir, 'ls-files', '-s', '-z')) {
    my ($meta, $path) = split /\t/, $rec, 2;
    # a merge conflict lists a path up to three times
    next unless defined $path && $meta =~ /\A160000 / && !$seen{$path}++;
    my $sub = "$dir/$path";
    my $problem;
    if (!-e "$sub/.git") {
      opendir my $dh, $sub or next;
      next unless grep { $_ ne '.' && $_ ne '..' } readdir $dh;    # empty: not checked out
      $problem = 'holds files but no .git, so git cannot see a change in it';
    } else {
      my ($st, $top) = run('-C', $sub, 'rev-parse', '--show-toplevel');
      my @here = stat $sub;
      my @there = !$st && $top =~ /\A(.+)\n\z/ ? stat $1 : ();
      $problem = 'its .git points git at another working folder (or git cannot read it), so git cannot see a change in it'
        unless @here && @there && $here[0] == $there[0] && $here[1] == $there[1];
    }
    push @s, ["$prefix$path", $sub, $problem];
    push @s, submodules($sub, "$prefix$path/", $depth + 1) if !defined $problem && $depth < 7;
  }
  return @s;
}

# flagged DIR: [path, tag] for every index entry marked so git does not
# compare it with the file on disk (assume-unchanged: a lower-case tag;
# skip-worktree: S), in the repository whose working tree has its top at
# DIR and in every submodule checked out in it (SUBS: submodules(DIR), when
# the caller has it already): git's own status of a submodule obeys the
# submodule's flags. Paths are relative to DIR. No program from the
# repository runs.
sub flagged {
  my ($dir, $subs) = @_;
  $subs = [submodules($dir)] unless $subs;
  my @f;
  for my $r (['', $dir], map { ["$_->[0]/", $_->[1]] } grep { !defined $_->[2] } @$subs) {
    my ($prefix, $d) = @$r;
    for my $rec (split /\0/, ok('-C', $d, 'ls-files', '-v', '-z')) {
      my ($tag, $path) = split / /, $rec, 2;
      push @f, ["$prefix$path", $tag] if defined $path && ($tag =~ /\A[a-z]\z/ || $tag eq 'S');
    }
  }
  return @f;
}

# object_id TYPE CONTENT LIKE: in the hash that the id LIKE uses (SHA-1, or
# SHA-256 for a 64-digit id). Digest::SHA is loaded only here, so a perl
# without it can still load this file (status.sh reports it missing).
sub object_id {
  my ($type, $c, $like) = @_;
  require Digest::SHA;
  # (added in two parts, so a large file is not copied)
  return Digest::SHA->new(length($like) == 64 ? 256 : 1)->add("$type " . length($c) . "\0")->add($c)->hexdigest;
}

# cat TYPE ID [ONCE]: git does not check a stored file, folder or parent commit
# when it reads one, so an object changed by hand could otherwise pass for
# the committed one. Objects are read through one `git cat-file --batch`,
# so reading many of them costs one git process.
my (%cache, %batch);    # one batch process per repository folder (submodules have their own)
sub cat {
  my ($type, $id, $once, $max) = @_;    # ONCE: not kept for a later read
  return $cache{$id} if exists $cache{$id};
  my $here = Cwd::getcwd();
  if (!$batch{$here}) {
    my ($o, $i);
    open my $saved, '>&', \*STDERR or die "cannot run git\n";
    open STDERR, '>', File::Spec->devnull;    # git's messages can quote names raw
    my $pid = eval { IPC::Open2::open2($o, $i, @GIT, 'cat-file', '--batch') };
    open STDERR, '>&', $saved;
    die "cannot run git cat-file\n" unless $pid;
    binmode $o;
    binmode $i;
    $i->autoflush(1);
    $batch{$here} = [$o, $i];
  }
  my ($batch_out, $batch_in) = @{ $batch{$here} };
  print {$batch_in} "$id\n";
  my $head = <$batch_out>;
  # the id check below also covers the type and the right object: both are
  # part of what the id is made from
  die "cannot read the stored $type $id\n" unless defined $head && $head =~ /\A[0-9a-f]+ [a-z]+ ([0-9]+)\n\z/;
  my ($size, $c) = ($1, '');
  if (defined $max && $size > $max) {
    my $left = $size + 1;    # and the newline after it
    while ($left > 0) {
      my $n = read($batch_out, my $buf, $left < 65536 ? $left : 65536) or die "cannot read the stored $type $id\n";
      $left -= $n;
    }
    return undef;
  }
  while (length $c < $size) {
    read($batch_out, $c, $size - length $c, length $c) or die "cannot read the stored $type $id\n";
  }
  read($batch_out, my $nl, 1);
  die "cannot read the stored $type $id\n" unless defined $nl && $nl eq "\n";
  die "a stored $type does not match its id ($id); the repository's object store is damaged or was changed by hand\n"
    unless object_id($type, $c, $id) eq $id;
  return $c if $once;
  return $cache{$id} = $c;
}


# exact REF: the commit id of the full ref name REF (a branch or tag with the
# same short name cannot stand in for it), or undef
sub exact {
  my ($ref) = @_;
  my ($st, $id) = run('show-ref', '--verify', '--hash', $ref);
  return undef if $st || $id !~ /\A([0-9a-f]+)\n\z/;
  my ($cst, $c) = run('rev-parse', '-q', '--verify', "$1^{commit}");
  return $cst || $c !~ /\A([0-9a-f]+)\n\z/ ? undef : $1;
}

# own_branch REF REMOTE: REF is HEAD's own branch or its namesake on REMOTE;
# git remote set-head, or a clone of a working copy on that branch, can
# point REMOTE/HEAD there, and then it is not main. (A branch's upstream is
# no reason: `git checkout -b feat origin/develop` makes the default branch
# the upstream.)
sub own_branch {
  my ($ref, $remote) = @_;
  my ($st, $b) = run('symbolic-ref', '-q', 'HEAD');
  return 0 if $st;
  chomp $b;
  return 1 if $ref eq $b;
  my ($name) = $b =~ m{\Arefs/heads/(.+)\z}s or return 0;
  return $ref eq "refs/remotes/$remote/$name" ? 1 : 0;
}

# main_remote: (the remote main is read from: origin, or the only remote when
# none is named origin); (undef) when there is no remote at all; ('', WHY)
# when which one cannot be told: several remotes and none is origin
# (several), remote-tracking branches with no remote set up, as a fetch by
# URL leaves (refs), or git failed (error). A remote counts only with a URL:
# a remote.NAME.* setting alone, such as remote.origin.prune in a personal
# settings file, is not one.
sub main_remote {
  my ($st, $out) = run('config', '-z', '--get-regexp', '^remote\..*\.url$');
  return ('', 'error') if $st && $st >> 8 != 1;    # (1: no such setting)
  my %r;
  for my $e (split /\0/, $out) { $r{$1} = 1 if $e =~ /\Aremote\.([^\n]+)\.url\n/ }
  my @r = sort keys %r;
  if (!@r) {
    my ($rst, $refs) = run('for-each-ref', '--count=1', '--format=%(refname)', 'refs/remotes/');
    return ('', 'error') if $rst;
    return $refs eq '' ? (undef) : ('', 'refs');
  }
  return ('origin') if $r{origin};
  return @r == 1 ? ($r[0]) : ('', 'several');
}

# hint_name NAME [PLACEHOLDER]: NAME when it is safe in a command the owner
# copies and pastes, else PLACEHOLDER (<remote>; git allows ; $ and | in a
# remote's or a branch's name)
sub hint_name {
  my ($n, $ph) = @_;
  return $n =~ m{\A[A-Za-z0-9_][A-Za-z0-9._-]*(?:/[A-Za-z0-9._-]+)*\z} ? $n : defined $ph ? $ph : '<remote>';
}

# fetched REMOTE REF: 1 when one of REMOTE's fetch settings (remote.NAME.fetch)
# writes REF, so that git fetch moves it; a ref fetched by hand into place (git
# fetch origin main:refs/remotes/origin/main in a single-branch clone) is
# never moved again
sub fetched {
  my ($remote, $ref) = @_;
  my ($st, $out) = run('config', '-z', '--get-all', "remote.$remote.fetch");
  return 0 if $st;
  for my $spec (split /\0/, $out) {
    next if $spec =~ /\A\^/;    # (a negative refspec writes nothing)
    $spec =~ s/\A\+//;
    my (undef, $dst) = split /:/, $spec, 2;
    next unless defined $dst && $dst ne '';
    return 1 if $dst eq $ref;
    my ($pre, $suf) = $dst =~ /\A([^*]*)\*([^*]*)\z/ or next;
    return 1 if length($ref) > length($pre) + length($suf) && substr($ref, 0, length $pre) eq $pre
      && substr($ref, length($ref) - length $suf) eq $suf;
  }
  return 0;
}

# main_refs: (the remote, why it cannot be told, the refs main_ref tries
# after REMOTE/HEAD, in order). With a remote, only its branches: a local
# main is never moved by git fetch, so it can be behind the main that was
# fetched. Local branches count only when there is no remote at all.
sub main_refs {
  my ($r, $why) = main_remote();
  return (undef, undef, qw(refs/heads/main refs/heads/master)) unless defined $r;
  return ('', $why) if $r eq '';
  return ($r, undef, "refs/remotes/$r/main", "refs/remotes/$r/master");
}

# main_ref: (the full name of main, its commit), or () when there is none
# (REMOTE/HEAD is not taken when it names HEAD's own branch, see own_branch)
sub main_ref {
  my ($r, undef, @refs) = main_refs();
  if (defined $r && $r ne '') {
    my ($st, $t) = run('symbolic-ref', '-q', "refs/remotes/$r/HEAD");
    $t =~ s/\n\z//;
    if (!$st && $t =~ m{\Arefs/remotes/\Q$r\E/\S+\z} && !own_branch($t, $r)) {
      my $id = exact($t);
      return ($t, $id) if defined $id;
    }
  }
  for my $ref (@refs) {
    my $id = exact($ref);
    return ($ref, $id) if defined $id;
  }
  return;
}

# status_options_all DIR SUBS: status_options for DIR and for every
# checked-out submodule in SUBS (Git::submodules), so a filter set only
# inside a submodule is off too when git status reads it (the -c options
# reach the git status git runs there)
sub status_options_all {
  my ($dir, $subs) = @_;
  my (@o, %seen);
  # (a submodule with a problem too: git status still reads it, and git -C
  # reads its own settings even when its .git points elsewhere)
  for my $g (['-C', $dir], map { ['-C', $_->[1]] } grep { -e "$_->[1]/.git" } @$subs) {
    my @x = status_options(@$g);
    while (my ($c, $v) = splice @x, 0, 2) { push @o, $c, $v unless $seen{$v}++ }
  }
  return @o;
}

# no_main: where main_ref looked, and why main is missing
my %CANNOT_TELL = (
  several => 'this repository has several remotes and none is named origin, so which one holds main cannot be told',
  refs => 'this repository has remote-tracking branches but no remote set up (fetched by URL?), so which one holds'
    . ' main cannot be told',
  error => 'git could not list the remotes',
);
sub no_main {
  my ($r, $why, @refs) = main_refs();
  return 'looked for ' . join(', ', @refs) . '; this repository has no remote' unless defined $r;
  return $CANNOT_TELL{$why} if $r eq '';
  my $h = hint_name($r);
  return "looked for $r/HEAD, " . join(', ', @refs) . "; in a single-branch or shallow clone, fetch it and keep it"
    . " fetched: git remote set-branches --add $h main && git fetch $h (or push main to $r first, if it does not have it"
    . ' yet)';
}

# no_main_action: what to do when main is missing
sub no_main_action {
  my ($r, $why) = main_refs();
  return 'make a branch named main (or rename the default branch: git branch -m NAME main)' unless defined $r;
  return 'name the remote that holds main origin (git remote rename NAME origin)' if $r eq '' && $why eq 'several';
  return 'set up the remote that holds main (git remote add origin URL, or git remote set-url origin URL when origin is'
    . ' there without one) and fetch it' if $r eq '' && $why eq 'refs';
  return 'check the repository\'s git settings' if $r eq '';
  return 'fetch main';
}

# merge_base A B: ('ok', every merge base, the one git picks first);
# ('none', WHAT TO DO) when A and B share no history here (in a shallow
# clone, more history may be needed); ('error') when git failed
my $NO_HISTORY_HINT = 'in a shallow clone, fetch more history (git fetch --deepen=N or git fetch --unshallow)';
sub merge_base {
  my ($st, $out) = run('merge-base', '--all', @_);
  return ('none', $NO_HISTORY_HINT) if $st == 1 << 8;
  return ('error') if $st || $out !~ /\A(?:[0-9a-f]+\n)+\z/;
  return ('ok', split /\n/, $out);
}

# message ID: a commit's message, read raw and checked against its id
sub message {
  my $c = cat('commit', $_[0]);
  my $i = index $c, "\n\n";
  return $i < 0 ? '' : substr($c, $i + 2);
}

# ignored DIR PATH...: see the top of this file (a tracked file is never
# reported: git's ignore rules do not apply to it)
sub ignored {
  my ($dir, @paths) = @_;
  return [] unless @paths;
  my ($st, $in) = run('-C', $dir, 'rev-parse', '--is-inside-work-tree');
  if ($st || $in ne "true\n") {
    # (git refusing a repository, one owned by another user say, fails as
    # it does outside one: only a .git at or above DIR tells them apart)
    my $up = Cwd::abs_path($dir);
    return undef unless defined $up;
    until (-e File::Spec->catfile($up, '.git')) {
      my $next = File::Basename::dirname($up);
      return [] if $next eq $up;
      $up = $next;
    }
    return undef;
  }
  # (check-ignore refuses pathspec magic, --literal-pathspecs too; it reads
  # each PATH as a path, never as a pattern. With -z its fields come
  # NUL-separated and unquoted, so a name holding ':12:' or a non-ASCII
  # letter is read whole; -z needs --stdin)
  local @GIT = grep { $_ ne '--literal-pathspecs' } @GIT;
  return undef if grep {/\0/} @paths;
  my ($ist, $out) = run_input(join('', map {"$_\0"} @paths), '-C', $dir, 'check-ignore', '-v', '-z', '--stdin');
  return undef if $ist && $ist != 1 << 8;    # (exit 1: none is ignored)
  return [] if $out eq '';
  my @f = split /\0/, $out, -1;
  return undef unless pop(@f) eq '' && @f % 4 == 0;
  my @r;
  while (my ($src, $n, $pat, $path) = splice @f, 0, 4) {
    return undef unless $n =~ /\A[0-9]+\z/;
    next if $pat =~ /\A!/;    # (a negated pattern matched: not ignored)
    push @r, [$path, "$src line $n: $pat"];
  }
  return \@r;
}

1;
