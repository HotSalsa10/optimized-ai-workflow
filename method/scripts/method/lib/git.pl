#!/usr/bin/env perl
# The method's one git runner (M048: one rule, one implementation). The perl
# helpers load it with require; every git call they make goes through it.
#
# Loading it clears the variables that would point git at another
# repository, index or object store, or change what it shows: GIT_DIR,
# GIT_WORK_TREE, GIT_COMMON_DIR, GIT_INDEX_FILE, GIT_OBJECT_DIRECTORY,
# GIT_ALTERNATE_OBJECT_DIRECTORIES, GIT_NAMESPACE, GIT_DIFF_OPTS,
# GIT_EXTERNAL_DIFF, GIT_REPLACE_REF_BASE and the GIT_*_PATHSPECS settings.
# Replace refs and grafts are turned off. So git finds the repository from
# the current folder, as a reader of the files there does.
#
# Every call gets: --no-optional-locks (git status does not rewrite the
# index), --literal-pathspecs (a path is never pathspec magic),
# core.commitGraph=false (a commit-graph file is a local file that could
# misreport history) and core.fsmonitor=false (a file-system monitor is a
# local program that would run inside the caller and could hide changes).
# A caller adds its own -c options in front of the git command.
#
#   Git::run(ARGS)      (exit status, standard output); stdin and stderr on
#                       the null device, because git's messages can quote
#                       file names raw
#   Git::ok(ARGS)       standard output, or dies "git <command> failed"
#   Git::cat(TYPE, ID)  a stored object's content, checked against its id
#   Git::object_id(TYPE, CONTENT, LIKE)  the id git gives CONTENT
package Git;
use strict;
use warnings;
use Digest::SHA ();
use File::Spec;
use File::Temp qw(tempdir);
use IO::Handle ();
use IPC::Open2 ();

delete @ENV{qw(GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_DIFF_OPTS GIT_EXTERNAL_DIFF GIT_REPLACE_REF_BASE
  GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS)};
$ENV{GIT_NO_REPLACE_OBJECTS} = 1;
$ENV{GIT_GRAFT_FILE} = File::Spec->catfile(tempdir(CLEANUP => 1), 'none');

our @GIT = ('git', '--no-optional-locks', '--literal-pathspecs', '-c', 'core.commitGraph=false',
  '-c', 'core.fsmonitor=false');

# the git command in ARGS, after any -c NAME=VALUE pairs
sub command_name {
  my @a = @_;
  splice @a, 0, 2 while @a >= 2 && $a[0] eq '-c';
  return defined $a[0] ? $a[0] : 'git';
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
# SHA-256 for a 64-digit id).
sub object_id {
  my ($type, $c, $like) = @_;
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
