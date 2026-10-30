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
# A caller adds its own -c options in front of the git command.
#
#   Git::run(ARGS)      (exit status, standard output); stdin and stderr on
#                       the null device, because git's messages can quote
#                       file names raw
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
#                       there is none: origin/HEAD (unless it names HEAD's
#                       own branch), then @Git::MAIN_REFS; Git::no_main()
#                       says where it looked
#   Git::merge_base(A, B)  ('ok', ids), ('none', what to do) or ('error')
#   Git::message(ID)    a commit's message, checked against its id
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

sub run {
  my @cmd = (@GIT, @_);
  my $pid = open(my $fh, '-|');
  die "cannot run git\n" unless defined $pid;
  if (!$pid) {
    open STDERR, '>', File::Spec->devnull;
    open STDIN, '<', File::Spec->devnull;
    exec { $cmd[0] } @cmd or exit 127;
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

# own_branch REF: REF is HEAD's own branch or its namesake on origin; git
# remote set-head, or a clone of a working copy on that branch, can point
# origin/HEAD there, and then it is not main. (A branch's upstream is no
# reason: `git checkout -b feat origin/develop` makes the default branch the
# upstream.)
sub own_branch {
  my ($ref) = @_;
  my ($st, $b) = run('symbolic-ref', '-q', 'HEAD');
  return 0 if $st;
  chomp $b;
  return 1 if $ref eq $b;
  my ($name) = $b =~ m{\Arefs/heads/(.+)\z}s or return 0;
  return $ref eq "refs/remotes/origin/$name" ? 1 : 0;
}

# the refs main_ref tries after origin/HEAD, in order
our @MAIN_REFS = qw(refs/remotes/origin/main refs/heads/main refs/remotes/origin/master refs/heads/master);

# main_ref: (the full name of main, its commit), or () when there is none
# (origin/HEAD is not taken when it names HEAD's own branch, see own_branch)
sub main_ref {
  my ($st, $t) = run('symbolic-ref', '-q', 'refs/remotes/origin/HEAD');
  $t =~ s/\n\z//;
  if (!$st && $t =~ m{\Arefs/remotes/origin/\S+\z} && !own_branch($t)) {
    my $id = exact($t);
    return ($t, $id) if defined $id;
  }
  for my $ref (@MAIN_REFS) {
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

# no_main: where main_ref looked, and how to fetch main when it is missing
sub no_main {
  return 'looked for origin/HEAD, ' . join(', ', @MAIN_REFS)
    . '; in a single-branch or shallow clone, fetch it: git fetch origin main:refs/remotes/origin/main';
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

1;
