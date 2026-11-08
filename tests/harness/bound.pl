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
alarm $secs;
waitpid $pid, 0;
my $st = $?;
alarm 0;
kill 'KILL', -$pid;   # leftovers in the group, if any
exit 124 if $timed_out;
exit($st & 127 ? 128 + ($st & 127) : $st >> 8);
