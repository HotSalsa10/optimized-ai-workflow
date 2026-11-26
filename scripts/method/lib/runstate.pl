#!/usr/bin/env perl
# The lock that run-checks and mutate-changed share, and where a mutate run
# keeps its journal (M048: one home for both). They live in git's own folder
# for this working tree (git rev-parse --git-path), so git clean never
# touches them and nothing is written into the working tree. run-checks
# holds the lock shared for its whole run, mutate-changed exclusively, so
# neither runs while the other does: a run-checks run between two mutants
# could otherwise log a clean pass over a mutant that was put back before it
# ended. Loaded after lib/git.pl; nothing runs when it is loaded.
package RunState;
use strict;
use warnings;
use Fcntl qw(:flock O_RDONLY O_RDWR O_CREAT O_NONBLOCK);
use File::Spec;
use Time::HiRes ();

my $NOFOLLOW = eval { Fcntl::O_NOFOLLOW() } || 0;
my $WAIT = 5;    # seconds take keeps trying

# paths [DIR]: (the lock, the journal) of the working tree at DIR (default
# this folder)
sub paths {
  my ($dir) = @_;
  $dir = '.' unless defined $dir;
  my @p = split /\n/, Git::ok('-C', $dir, 'rev-parse', '--git-path', 'method-run.lock', '--git-path', 'method-mutate-journal');
  die "git rev-parse --git-path did not give the lock's and the journal's paths\n" unless @p == 2;
  return map { File::Spec->rel2abs($_, $dir) } @p;
}

# operations DIR: the git operations in progress in the working tree at DIR,
# as words ("a merge", "a rebase", ...). status reports them; mutate-changed
# does not recover or run during one, as a rebase's or a merge's autostash
# can hold a mutant that comes back when the operation ends.
sub operations {
  my ($dir) = @_;
  my @what = (['MERGE_HEAD', 'a merge'], ['rebase-merge', 'a rebase'], ['rebase-apply', 'a rebase or am'],
    ['CHERRY_PICK_HEAD', 'a cherry-pick'], ['REVERT_HEAD', 'a revert'], ['BISECT_LOG', 'a bisect']);
  my @paths = split /\n/, Git::ok('-C', $dir, 'rev-parse', map { ('--git-path', $_->[0]) } @what);
  my @on;
  for my $k (0 .. $#what) {
    next unless defined $paths[$k];
    push @on, $what[$k][1] if -e File::Spec->rel2abs($paths[$k], $dir);
  }
  return @on;
}

# probe [DIR]: what a report may say without writing anything: {journal (1
# when a journal exists), mutate (1 when someone holds the lock
# exclusively: a mutate run, or the watchdog of a cut-off run while it stops
# its checks), unknown (why that cannot be told, or undef)}. The lock is opened read only
# and never created; a FIFO or a link there is not opened.
sub probe {
  my ($lock, $journal) = paths($_[0]);
  my %r = (journal => (-e $journal || -l $journal) ? 1 : 0, mutate => 0, unknown => undef);
  return \%r unless -e $lock || -l $lock;
  my $fh;
  if (-l $lock || !-f _) {
    $r{unknown} = 'the lock is not a regular file';
  } elsif (!sysopen $fh, $lock, O_RDONLY | O_NONBLOCK | $NOFOLLOW) {
    $r{unknown} = "cannot open the lock ($!)";
  } elsif (!-f $fh) {
    $r{unknown} = 'the lock is not a regular file';
  } elsif (flock $fh, LOCK_SH | LOCK_NB) {
    flock $fh, LOCK_UN;
  } elsif ($!{EWOULDBLOCK} || $!{EAGAIN}) {
    $r{mutate} = 1;
  } else {
    $r{unknown} = "cannot test the lock ($!)";
  }
  close $fh if $fh;
  return \%r;
}

# take MODE: the lock, held 'shared' (run-checks) or 'exclusive'
# (mutate-changed), as (HANDLE), or (undef, 'busy' or 'error', REASON). It
# keeps trying for 5 s, so a report's brief shared hold, or the watchdog of
# a cut-off run while it stops its checks, does not read as busy. The handle
# is close-on-exec (perl's default above descriptor 2), so no check inherits
# it; the lock is held while the handle is open.
sub take {
  my ($mode) = @_;
  my ($lock) = paths();
  # (without O_NOFOLLOW, O_CREAT would follow a link and make its target)
  return (undef, 'error', "the lock $lock is a link") if !$NOFOLLOW && -l $lock;
  my $fh;
  sysopen $fh, $lock, O_RDWR | O_CREAT | O_NONBLOCK | $NOFOLLOW, 0600
    or return (undef, 'error', "cannot open the lock $lock ($!)");
  return (undef, 'error', "the lock $lock is not a regular file") unless -f $fh;
  my $how = $mode eq 'exclusive' ? LOCK_EX : LOCK_SH;
  my $until = Time::HiRes::time() + $WAIT;
  while (1) {
    return ($fh) if flock $fh, $how | LOCK_NB;
    return (undef, 'error', "cannot lock $lock ($!): does this file system support locks?")
      unless $!{EWOULDBLOCK} || $!{EAGAIN};
    return (undef, 'busy', "$lock is held") if Time::HiRes::time() >= $until;
    Time::HiRes::sleep(0.1);
  }
}

1;
