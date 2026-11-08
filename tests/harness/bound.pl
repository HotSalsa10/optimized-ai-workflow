#!/usr/bin/env perl
# bound.pl SECONDS cmd args...: runs cmd in its own process group; on
# timeout kills the whole group (TERM, then KILL) and exits 124. Core perl,
# no GNU timeout (BSD and Git Bash have none). Never shipped.
use strict; use warnings; use POSIX ();
my $secs = shift @ARGV;
my $pid = fork;
die "fork: $!\n" unless defined $pid;
if (!$pid) { setpgrp(0, 0); exec @ARGV or do { print STDERR "exec: $!\n"; POSIX::_exit(127) }; }
my $timed_out = 0;
local $SIG{ALRM} = sub { $timed_out = 1; kill 'TERM', -$pid; sleep 2; kill 'KILL', -$pid; };
# Ctrl-C or a TERM ends the group too: it is in a group of its own, so the
# terminal's signal never reaches it. Then bound.pl dies by the same signal,
# so the shell that ran it stops as well, instead of going on to the next
# case.
for my $sig (qw(INT TERM HUP)) {
  $SIG{$sig} = sub {
    kill 'TERM', -$pid; sleep 2; kill 'KILL', -$pid;
    $SIG{$sig} = 'DEFAULT';
    kill $sig, $$;
    exit 128 + (POSIX->can("SIG$sig") ? POSIX->can("SIG$sig")->() : 15);
  };
}
alarm $secs;
waitpid $pid, 0;
my $st = $?;
alarm 0;
kill 'KILL', -$pid;   # leftovers in the group, if any
exit 124 if $timed_out;
exit($st & 127 ? 128 + ($st & 127) : $st >> 8);
