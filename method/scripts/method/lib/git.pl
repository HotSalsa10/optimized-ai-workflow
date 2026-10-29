#!/usr/bin/env perl
# The method's one git runner (M048: one rule, one implementation). The perl
# helpers load it with require; every git call they make goes through it.
#
# Loading it clears the variables that would point git at another
# repository, index, object store or history, or change what it shows:
# GIT_DIR, GIT_WORK_TREE, GIT_COMMON_DIR, GIT_INDEX_FILE,
# GIT_OBJECT_DIRECTORY, GIT_ALTERNATE_OBJECT_DIRECTORIES, GIT_SHALLOW_FILE,
# GIT_IMPLICIT_WORK_TREE, GIT_PREFIX, GIT_INTERNAL_SUPER_PREFIX,
# GIT_NAMESPACE, GIT_DIFF_OPTS, GIT_EXTERNAL_DIFF, GIT_REPLACE_REF_BASE and
# the GIT_*_PATHSPECS settings. Replace refs and grafts are turned off. So
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
#   Git::cat(TYPE, ID)  a stored object's content, checked against its id
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
package Git;
use strict;
use warnings;
use Cwd ();
use File::Basename ();
use File::Spec;
use File::Temp qw(tempdir);
use IO::Handle ();
use IPC::Open2 ();

delete @ENV{qw(GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_SHALLOW_FILE GIT_IMPLICIT_WORK_TREE GIT_PREFIX GIT_INTERNAL_SUPER_PREFIX
  GIT_NAMESPACE GIT_DIFF_OPTS GIT_EXTERNAL_DIFF GIT_REPLACE_REF_BASE
  GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS)};
$ENV{GIT_NO_REPLACE_OBJECTS} = 1;
$ENV{GIT_GRAFT_FILE} = File::Spec->catfile(tempdir(CLEANUP => 1), 'none');

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
  my @o = ('-c', 'core.trustctime=true', '-c', 'core.checkStat=default');
  my ($st, $names) = run(@g, 'config', '--name-only', '-z', '--get-regexp', '^filter\.');
  return @o if $st;
  for my $name (split /\0/, $names) {
    my ($driver) = $name =~ /\Afilter\.(.+)\.[^.]+\z/s or next;
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

# object_id TYPE CONTENT LIKE: in the hash that the id LIKE uses (SHA-1, or
# SHA-256 for a 64-digit id). Digest::SHA is loaded only here, so a perl
# without it can still load this file (status.sh reports it missing).
sub object_id {
  my ($type, $c, $like) = @_;
  require Digest::SHA;
  my $data = "$type " . length($c) . "\0" . $c;
  return length($like) == 64 ? Digest::SHA::sha256_hex($data) : Digest::SHA::sha1_hex($data);
}

# cat TYPE ID: git does not check a stored file, folder or parent commit
# when it reads one, so an object changed by hand could otherwise pass for
# the committed one. Objects are read through one `git cat-file --batch`,
# so reading many of them costs one git process.
my (%cache, $batch_in, $batch_out);
sub cat {
  my ($type, $id) = @_;
  return $cache{$id} if exists $cache{$id};
  if (!$batch_in) {
    open my $saved, '>&', \*STDERR or die "cannot run git\n";
    open STDERR, '>', File::Spec->devnull;    # git's messages can quote names raw
    my $pid = eval { IPC::Open2::open2($batch_out, $batch_in, @GIT, 'cat-file', '--batch') };
    open STDERR, '>&', $saved;
    die "cannot run git cat-file\n" unless $pid;
    binmode $batch_out;
    binmode $batch_in;
    $batch_in->autoflush(1);
  }
  print {$batch_in} "$id\n";
  my $head = <$batch_out>;
  # the id check below also covers the type and the right object: both are
  # part of what the id is made from
  die "cannot read the stored $type $id\n" unless defined $head && $head =~ /\A[0-9a-f]+ [a-z]+ ([0-9]+)\n\z/;
  my ($size, $c) = ($1, '');
  while (length $c < $size) {
    read($batch_out, $c, $size - length $c, length $c) or die "cannot read the stored $type $id\n";
  }
  read($batch_out, my $nl, 1);
  die "cannot read the stored $type $id\n" unless defined $nl && $nl eq "\n";
  die "a stored $type does not match its id ($id); the repository's object store is damaged or was changed by hand\n"
    unless object_id($type, $c, $id) eq $id;
  return $cache{$id} = $c;
}

1;
