#!/usr/bin/env bash
# Tests for lib/checks.pl's limited runner (start_limited, wait_limited,
# finish_limited) and the lock it keeps (lib/runstate.pl), step 4b.3a: a
# check runs as the leader of its own process group under a watchdog, with
# a time limit. A small perl driver calls the runner the way mutate-changed
# will, in a throwaway repo. A process the check leaves behind appends to a
# heartbeat file; it counts as stopped once the file stops growing.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: runner"
root=$(repo_root)
lib="$root/method/scripts/method/lib"
work=$(new_sandbox_dir) || abort_sandbox
(cd "$work" && git init -q)
beat_script "$work/beat.pl"
lock="$work/.git/method-run.lock"

# sig.pl: for each stop signal, whether a child of this process dies from it
# (default) or not (ignored); and whether this process holds the lock. (FPE
# is tested from bash: perl ignores it itself when it starts.)
cat >"$work/sig.pl" <<'EOF'
use POSIX ();
for my $s (qw(INT TERM HUP QUIT PIPE)) {
  my $pid = fork;
  if (!$pid) { kill $s, $$; select undef, undef, undef, 0.5; POSIX::_exit(0) }
  waitpid $pid, 0;
  print "$s=", (($? & 127) ? 'default' : 'ignored'), "\n";
}
if (opendir my $d, '/proc/self/fd') {
  my $held = grep { (readlink("/proc/self/fd/$_") || '') =~ /method-run\.lock/ } readdir $d;
  print 'lock=', ($held ? 'held' : 'not held'), "\n";
} else {
  print "lock=skip\n";
}
print "5 ok\n";
EOF

# the driver: drv.pl MODE BEAT
cat >"$work/drv.pl" <<'EOF'
use strict;
use warnings;
use POSIX ();
use Time::HiRes qw(time);
my ($lib, $mode, $beat, $out) = @ARGV;
$| = 1;
require "$lib/checks.pl";
my $t0;
sub took { return sprintf '%.1f', time - $t0 }
if ($mode eq 'exit') {
  my $r = Checks::start_limited(undef, ['bash', '-c', 'echo 3 ok; exit 3'], $out);
  my $how = Checks::wait_limited($r, 10);
  Checks::finish_limited($r);
  print "how=$how code=", $r->{status} >> 8, "\n";
} elsif ($mode eq 'time') {
  my $r = Checks::start_limited(undef, ['perl', $ENV{BEAT_PL}, $beat], $out);
  $t0 = time;
  my $how = Checks::wait_limited($r, 1);
  print "how=$how took=", took(), "\n";
  $t0 = time;
  Checks::finish_limited($r);
  print "finish=", took(), "\n";
} elsif ($mode eq 'note') {
  my $r = Checks::start_limited(undef, ['bash', '-c', 'perl "$1" "$2" note & sleep 0.3; echo 1 ok', 'bash', $ENV{BEAT_PL}, $beat], $out);
  Checks::wait_limited($r, 10);
  Checks::finish_limited($r);
  print "finished\n";
} elsif ($mode eq 'termgroup') {
  my $r = Checks::start_limited(undef, ['perl', $ENV{BEAT_PL}, $beat, 'ignore'], $out);
  print "watchdog $r->{w}\n";
  sleep 60;
} elsif ($mode eq 'leftover') {
  my $r = Checks::start_limited(undef, ['bash', '-c', 'perl "$1" "$2" ignore & sleep 0.3; echo 1 ok', 'bash', $ENV{BEAT_PL}, $beat], $out);
  my $how = Checks::wait_limited($r, 10);
  $t0 = time;
  Checks::finish_limited($r);
  print "how=$how finish=", took(), "\n";
} elsif ($mode eq 'vanish') {
  my $r = Checks::start_limited(undef, ['bash', '-c', 'perl "$1" "$2" ignore & sleep 0.3; echo 1 ok', 'bash', $ENV{BEAT_PL}, $beat], $out);
  my $how = Checks::wait_limited($r, 10);
  print "how=$how\n";
  POSIX::_exit(0);    # gone without finishing, as after kill -9
} elsif ($mode eq 'killed') {
  my ($fh) = RunState::take('exclusive');
  die "no lock\n" unless $fh;
  my $r = Checks::start_limited(undef, ['perl', $ENV{BEAT_PL}, $beat, 'ignore'], $out, $fh);
  print "started\n";
  sleep 60;
} elsif ($mode eq 'fds') {
  # a pipe to a reader that marks EOF: the watchdog must not hold its end
  pipe(my $pr, my $pw) or die;
  my $kid = fork;
  if (!$kid) { close $pw; 1 while sysread $pr, my $b, 64; open my $m, '>', $ENV{MARK}; close $m; POSIX::_exit(0) }
  close $pr;
  my $r = Checks::start_limited(undef, ['bash', '-c', 'perl "$1" "$2" ignore & sleep 0.3; echo 1 ok', 'bash', $ENV{BEAT_PL}, $beat], $out);
  Checks::wait_limited($r, 10);
  POSIX::_exit(0);
} elsif ($mode eq 'forkhold') {
  # a fork of the caller keeps the caller's end of the pipe open after the
  # caller is gone: the watchdog notices its parent changed
  my $r = Checks::start_limited(undef, ['perl', $ENV{BEAT_PL}, $beat, 'ignore'], $out);
  my $kid = fork;
  if (!$kid) { open STDOUT, '>', '/dev/null'; open STDERR, '>&', \*STDOUT; alarm 20; sleep 20; POSIX::_exit(0) }
  print "kid=$kid\n";
  sleep 1;
  POSIX::_exit(0);
} elsif ($mode eq 'stopwd') {
  my $r = Checks::start_limited(undef, ['perl', $ENV{BEAT_PL}, $beat, 'ignore'], $out);
  sleep 1;
  kill 'STOP', $r->{w};
  $t0 = time;
  Checks::finish_limited($r);
  print "finish=", took(), "\n";
} elsif ($mode eq 'wdkilled') {
  my $r = Checks::start_limited(undef, ['perl', $ENV{BEAT_PL}, $beat, 'ignore'], $out);
  sleep 1;
  kill 'KILL', $r->{w};
  Checks::finish_limited($r);
  print "finished\n";
} elsif ($mode eq 'chld') {
  $SIG{CHLD} = sub { 1 while waitpid(-1, POSIX::WNOHANG()) > 0 };
  my $r = Checks::start_limited(undef, ['bash', '-c', 'sleep 0.3; echo 1 ok'], $out);
  my $how = Checks::wait_limited($r, 3);
  Checks::finish_limited($r);
  print "how=$how\n";
} elsif ($mode eq 'fastchild') {
  my $r = Checks::start_limited(undef, ['bash', '-c', 'perl "$1" "$2" ignore; echo done', 'bash', $ENV{BEAT_PL}, $beat], $out);
  sleep 1;
  $t0 = time;
  Checks::finish_limited($r, 1);
  print "finish=", took(), "\n";
} elsif ($mode eq 'signals') {
  my ($fh) = RunState::take('exclusive');
  $SIG{$_} = 'IGNORE' for qw(INT TERM HUP QUIT PIPE FPE);
  my $block = POSIX::SigSet->new(POSIX::SIGTERM());
  POSIX::sigprocmask(POSIX::SIG_BLOCK(), $block);
  my $r = Checks::start_limited(undef, ['bash', '-c', 'ulimit -c 0; bash -c "kill -FPE \$\$; sleep 0.5"; if [ $? -gt 128 ]; then echo FPE=default; else echo FPE=ignored; fi; perl "$1"', 'bash', $ENV{SIG_PL}], $out, $fh);
  my $name = '';
  if (open my $c, '<', "/proc/$r->{w}/cmdline") { local $/; $name = <$c>; $name =~ s/\0/ /g; $name =~ s/ +\z// } else { $name = 'skip' }
  my $how = Checks::wait_limited($r, 10);
  Checks::finish_limited($r);
  print "how=$how watchdog=$name\n";
} elsif ($mode eq 'interrupt') {
  my $r = Checks::start_limited(undef, ['perl', $ENV{BEAT_PL}, $beat, 'ignore'], $out);
  $t0 = time;
  my $how = Checks::wait_limited($r, 30, sub { time - $t0 > 0.3 });
  print "how=$how took=", took(), "\n";
  $t0 = time;
  Checks::finish_limited($r, 1);
  print "finish=", took(), "\n";
} elsif ($mode eq 'interrupt2') {
  my $r = Checks::start_limited(undef, ['perl', $ENV{BEAT_PL}, $beat, 'ignore'], $out);
  sleep 1;
  $t0 = time;
  Checks::finish_limited($r, 0, sub { 1 });
  print "finish=", took(), "\n";
} elsif ($mode eq 'groups') {
  print join(' ', map { Checks::group_ok($_) ? 'yes' : 'no' } undef, 0, 1, getpgrp(), 'x', 4294967295), "\n";
  my $dummy = fork;
  POSIX::_exit(0) unless $dummy;
  Checks::finish_limited({ pgid => getpgrp(), w => $dummy }, 1);
  print "alive\n";
}
EOF

# drive MODE: runs the driver in the work repo; sets out (its screen)
drive() {
  rm -f "$work/beat" "$work/check.out"
  out=$(cd "$work" && BEAT_PL="$work/beat.pl" SIG_PL="$work/sig.pl" perl "$work/drv.pl" "$lib" "$1" "$work/beat" "$work/check.out" 2>&1)
}

# has NAME STRING: the last driver screen holds STRING
has() {
  case "$out" in
    *"$2"*) pass "$1" ;;
    *) fail "$1: missing [$2]" "$out" ;;
  esac
}

# under NAME VALUE LIMIT: VALUE (seconds, one decimal) is below LIMIT
under() {
  if perl -e 'exit !($ARGV[0] < $ARGV[1])' "$2" "$3"; then pass "$1 ($2 s)"; else fail "$1: $2 s, not under $3 s"; fi
}

# a check's exit code comes back, and its output is in its file
drive exit
has "the check's exit code comes back" "how=exit code=3"
if grep -q '^3 ok$' "$work/check.out"; then pass "its output is in its file"; else fail "its output is in its file"; fi

# a check that runs past its limit: how=time at the limit, and finishing
# stops it
drive time
has "a check past its 1 s limit ends as time" "how=time"
under "at the limit" "$(printf '%s\n' "$out" | sed -n 's/.*took=//p')" 2
under "a check that ends on TERM is finished at once (the watchdog reaps it)" "$(printf '%s\n' "$out" | sed -n 's/^finish=//p')" 1
if stopped "$work/beat" 10; then pass "finishing stops it"; else fail "finishing stops it"; fi

# finishing sends TERM first, and gives 2 s before KILL: a leftover that
# handles TERM ends on its own
drive note
has "setup: finished" "finished"
if grep -q '^TERM$' "$work/beat.term" 2>/dev/null; then pass "a leftover gets TERM first"; else fail "a leftover gets TERM first"; fi
if stopped "$work/beat" 10; then pass "and ends"; else fail "and ends"; fi
rm -f "$work/beat.term"

# a check that ends but leaves a process that ignores TERM: finishing stops
# that process too (KILL after 2 s)
drive leftover
has "a check that leaves a process ends normally" "how=exit"
under "finishing waits at most the 2 s grace and the KILL" "$(printf '%s\n' "$out" | sed -n 's/.*finish=//p')" 3.5
if stopped "$work/beat" 10; then pass "the leftover that ignores TERM is stopped"; else fail "the leftover that ignores TERM is stopped"; fi

# the caller vanishes right after the check ended (as kill -9 would leave
# it): the watchdog stops the leftover on its own
t0=$(perl -MTime::HiRes=time -e 'printf "%.1f", time')
drive vanish
took=$(perl -MTime::HiRes=time -e 'printf "%.1f", time - $ARGV[0]' "$t0")
has "setup: the check ended" "how=exit"
under "the watchdog does not keep the caller's output open" "$took" 1.5
if stopped "$work/beat" 10; then pass "the watchdog stops a leftover when its caller is gone"; else fail "the watchdog stops a leftover when its caller is gone"; fi

# TERM, HUP or KILL to the caller's whole process group (a harness stopping
# a job, a lost terminal, timeout -s KILL): the watchdog is in a group of
# its own, ignores TERM and HUP, sees its caller gone, and stops the check
for sig in TERM HUP KILL; do
  rm -f "$work/beat"
  (cd "$work" && BEAT_PL="$work/beat.pl" exec perl -e 'setpgrp(0, 0); exec @ARGV' perl "$work/drv.pl" "$lib" termgroup "$work/beat" "$work/check.out") >"$work/tg.out" 2>&1 &
  tg=$!
  if wait_for "$work/beat" 10; then pass "setup: the check runs"; else fail "setup: the check runs"; fi
  kill "-$sig" -- "-$tg"
  wait "$tg" 2>/dev/null
  if stopped "$work/beat" 10; then pass "$sig to the caller's group: the watchdog outlives it and stops the check"; else fail "$sig to the caller's group: the watchdog outlives it and stops the check"; fi
done

# INT, TERM, HUP and QUIT sent to the watchdog itself are ignored: it still
# stops the check once its caller is gone
rm -f "$work/beat"
(cd "$work" && BEAT_PL="$work/beat.pl" exec perl -e 'setpgrp(0, 0); exec @ARGV' perl "$work/drv.pl" "$lib" termgroup "$work/beat" "$work/check.out") >"$work/tg.out" 2>&1 &
tg=$!
wait_for "$work/beat" 10
wd=$(sed -n 's/^watchdog //p' "$work/tg.out")
for sig in INT TERM HUP QUIT; do kill "-$sig" "$wd" 2>/dev/null; done
perl -e 'select undef, undef, undef, 0.3'
kill -9 "$tg"
wait "$tg" 2>/dev/null
if stopped "$work/beat" 10; then pass "the stop signals sent to the watchdog itself are ignored: it still stops the check"; else fail "the stop signals sent to the watchdog itself are ignored: it still stops the check"; fi

# the watchdog keeps none of the caller's descriptors: not its stdin (a
# pipe from yes ends as soon as the caller does) and not another pipe the
# caller holds (its reader sees the end at once)
t0=$(perl -MTime::HiRes=time -e 'printf "%.1f", time')
(cd "$work" && yes | BEAT_PL="$work/beat.pl" perl "$work/drv.pl" "$lib" vanish "$work/beat" "$work/check.out" >/dev/null 2>&1)
took=$(perl -MTime::HiRes=time -e 'printf "%.1f", time - $ARGV[0]' "$t0")
under "the watchdog does not keep the caller's stdin" "$took" 1.5
stopped "$work/beat" 10 >/dev/null
rm -f "$work/mark"
(cd "$work" && MARK="$work/mark" BEAT_PL="$work/beat.pl" perl "$work/drv.pl" "$lib" fds "$work/beat" "$work/check.out" >/dev/null 2>&1)
if wait_for "$work/mark" 1.5; then pass "the watchdog does not keep the caller's other descriptors"; else fail "the watchdog does not keep the caller's other descriptors"; fi
stopped "$work/beat" 10 >/dev/null

# a fork of the caller that keeps the pipe open does not hide the caller's
# end from the watchdog
drive forkhold
kid=$(printf '%s\n' "$out" | sed -n 's/^kid=//p')
if stopped "$work/beat" 10; then pass "the watchdog notices its parent is gone even while a fork of it holds the pipe"; else fail "the watchdog notices its parent is gone even while a fork of it holds the pipe"; fi
[ -n "$kid" ] && kill "$kid" 2>/dev/null

# a watchdog that is stopped: finishing gives up on it after 3 s and kills
# it and the check; one killed on its own: finishing kills the check's group
drive stopwd
under "a stopped watchdog is given up on after 3 s" "$(printf '%s\n' "$out" | sed -n 's/^finish=//p')" 4
if stopped "$work/beat" 10; then pass "and the check is stopped"; else fail "and the check is stopped"; fi
drive wdkilled
has "setup: finished" "finished"
if stopped "$work/beat" 10; then pass "a watchdog killed on its own: finishing stops the check"; else fail "a watchdog killed on its own: finishing stops the check"; fi

# the caller's own signal handlers do not run in the watchdog: a caller that
# reaps every child still gets the check's result
drive chld
has "a caller's SIGCHLD handler does not take the check's result from the watchdog" "how=exit"

# a fast finish does not wait for a killed check's children to be reaped
drive fastchild
under "a fast finish of a check with a child returns at once" "$(printf '%s\n' "$out" | sed -n 's/^finish=//p')" 1
if stopped "$work/beat" 10; then pass "and the child is stopped"; else fail "and the child is stopped"; fi

# the caller is killed with KILL during a check that ignores TERM: the
# watchdog keeps the lock until it has stopped the check, then lets it go
rm -f "$work/beat"
(cd "$work" && BEAT_PL="$work/beat.pl" exec perl "$work/drv.pl" "$lib" killed "$work/beat" "$work/check.out") >"$work/killed.out" 2>&1 &
drv=$!
if wait_for "$work/beat" 10; then pass "setup: the check runs"; else fail "setup: the check runs"; fi
kill -9 "$drv"
wait "$drv" 2>/dev/null
state=$(lock_state "$lock")
if [ "$state" = "ex=busy sh=busy" ]; then pass "after kill -9 the watchdog still holds the lock"; else fail "after kill -9 the watchdog still holds the lock: $state"; fi
if stopped "$work/beat" 10; then pass "and stops the check that ignores TERM"; else fail "and stops the check that ignores TERM"; fi
if perl -MTime::HiRes=sleep,time -MFcntl=:flock -e 'open my $f, "<", $ARGV[0] or exit 1; my $u = time + 5; until (flock $f, LOCK_EX | LOCK_NB) { exit 1 if time > $u; sleep 0.1 }' "$lock"; then
  pass "then the lock is free"
else
  fail "then the lock is free: $(lock_state "$lock")"
fi

# in the check, the stop signals are back at their defaults though the
# caller ignores them, and the lock is not held; the watchdog has its own name
drive signals
has "the check ends" "how=exit"
for s in INT TERM HUP QUIT PIPE FPE; do
  if grep -q "^$s=default$" "$work/check.out"; then pass "$s is at its default (and not blocked) in the check"; else fail "$s is at its default (and not blocked) in the check" "$(cat "$work/check.out")"; fi
done
if grep -q '^lock=skip$' "$work/check.out"; then
  skip "the check does not hold the lock (no /proc here)"
elif grep -q '^lock=not held$' "$work/check.out"; then
  pass "the check does not hold the lock"
else
  fail "the check does not hold the lock" "$(cat "$work/check.out")"
fi
case "$out" in
  *"watchdog=skip"*) skip "the watchdog's name (no /proc here)" ;;
  *) [ "$(uname -s)" = Linux ] || out="watchdog=skip" ;;
esac
case "$out" in
  *"watchdog=skip"*) skip "the watchdog's name (read through /proc on Linux only)" ;;
  *"watchdog=method check watchdog"*) pass "the watchdog has its own name" ;;
  *) fail "the watchdog has its own name" "$out" ;;
esac

# an interruption ends the wait at once, and a fast finish is quick
drive interrupt
has "an interruption ends the wait" "how=interrupted"
under "soon after it is asked" "$(printf '%s\n' "$out" | sed -n 's/.*took=//p')" 1
under "a fast finish sends KILL at once" "$(printf '%s\n' "$out" | sed -n 's/^finish=//p')" 1
if stopped "$work/beat" 10; then pass "and the check is stopped"; else fail "and the check is stopped"; fi
drive interrupt2
under "an interruption during a finish makes it fast" "$(printf '%s\n' "$out" | sed -n 's/^finish=//p')" 1
if stopped "$work/beat" 10; then pass "and the check is stopped"; else fail "and the check is stopped"; fi

# no signal goes to a group number of 0 or 1, to something that is not a
# number, or to the caller's own group (the driver runs in a group of its
# own, so a KILL to its group would not reach this test file)
out=$(cd "$work" && perl -e 'setpgrp(0, 0); exec @ARGV' perl "$work/drv.pl" "$lib" groups "$work/beat" "$work/check.out" 2>&1)
has "only a group number of 2 or more and below 2^31, not the caller's own, is signalled" "no no no no no no"
has "a finish with the caller's own group sends it nothing" "alive"

drop_sandbox "$work"
echo "tests: runner: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
