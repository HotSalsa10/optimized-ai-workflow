#!/usr/bin/env bash
# Tests for method/scripts/method/mutate-changed.sh running mutants (rule
# M044, step 4b.3b): the lock, the journal, the write function, recovery,
# --recover, signals and the rounds. Each test builds a small project with
# a local bare remote in a throwaway folder; the code under test is shell
# (src/*.sh, sourced by the check t.sh), so nothing but bash and perl is
# needed. A process a check leaves behind writes a heartbeat file, and
# counts as stopped once the file stops growing.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: mutate run"
root=$(repo_root)
mutate="$root/method/scripts/method/mutate-changed.sh"
lib="$root/method/scripts/method/lib"
work=$(new_sandbox_dir) || abort_sandbox
saved_home=$HOME
mkdir -p "$work/home"
# a clean home and no system settings, so the owner's git settings play no part
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
git config --global user.name "Test"
git config --global user.email "test@example.invalid"
git config --global commit.gpgsign false
git config --global core.autocrlf false
git config --global init.defaultBranch main
git config --global protocol.file.allow always
beat_script "$work/beat.pl"
export BEAT_PL="$work/beat.pl"

# mr DIR ARGS...: runs mutate-changed.sh in DIR, for 300 s at most. Sets out
# and code.
mr() {
  d=$1
  shift
  out=$(cd "$d" && env CI= perl -e 'alarm 300; exec @ARGV' bash "$mutate" "$@" 2>&1)
  code=$?
}

# expect NAME CODE STRING...: the last run exited CODE and holds every STRING
expect() {
  name=$1
  want=$2
  shift 2
  missing=""
  for s in "$@"; do
    case "$out" in
      *"$s"*) ;;
      *) missing="$missing [$s]" ;;
    esac
  done
  if [ "$code" -ne "$want" ]; then
    fail "$name: exit $code, wanted $want" "$out"
  elif [ -n "$missing" ]; then
    fail "$name: missing$missing" "$out"
  else
    pass "$name"
  fi
}

# lacks NAME STRING: the last output does not hold STRING
lacks() {
  case "$out" in
    *"$2"*) fail "$1" "$out" ;;
    *) pass "$1" ;;
  esac
}

# clean NAME DIR: the files in DIR are the commit, there is no journal, and
# the lock is free
clean() {
  st=$(cd "$2" && git status --porcelain --untracked-files=all)
  j=$(cd "$2" && git rev-parse --git-path method-mutate-journal)
  case "$j" in /*) ;; *) j="$2/$j" ;; esac
  l=$(lock_state "$2/.git/method-run.lock")
  if [ -n "$st" ]; then
    fail "$1: the files are not the commit" "$st"
  elif [ -e "$j" ]; then
    fail "$1: a journal is left"
  elif [ "$l" != "ex=free sh=free" ] && [ "$l" != "no lock" ]; then
    fail "$1: the lock is held ($l)"
  else
    pass "$1"
  fi
}

# new_project CHECK: prints a folder holding remote.git (bare) and w. main
# has src/a.sh, src/b.sh and src/c.sh (c.sh executable) setting a variable
# each, t.sh (the check: CHECK, then "echo 1 ok") and the settings
# (MUTATE_PATHS=src, MUTATION_CHECKS=unit). w is on branch feat, which adds
# one function to each file: one mutant per file, '-ge' at src/a.sh:2:18,
# '-gt' at src/b.sh:2:16 and '-le' at src/c.sh:2:18.
new_project() {
  b=$(new_sandbox_dir) || return 1
  printf '%s\n' "$b" >>"$work/repos"    # (new_project runs in $( ): a variable would be lost)
  (
    cd "$b" || exit 1
    git init -q --bare remote.git
    git init -q w
    cd w || exit 1
    mkdir -p checks .claude src
    printf 'unit\tany\t-\t(\\d+) ok\tbash t.sh\n' >checks/project.tsv
    printf 'PRODUCT_PATHS=src\nMUTATE_PATHS=src\nMUTATION_CHECKS=unit\n' >.claude/method.conf
    printf 'min=18\n' >src/a.sh
    printf 'top=99\n' >src/b.sh
    printf 'few=3\n' >src/c.sh
    chmod 755 src/c.sh
    printf '. src/a.sh; . src/b.sh; . src/c.sh\n%s\necho 1 ok\n' "$1" >t.sh
    git add -A
    git commit -q -m "Start"
    git remote add origin ../remote.git
    git push -q -u origin main 2>/dev/null
    git remote set-head origin main
    git checkout -q -b feat
    # shellcheck disable=SC2016 # the code is written, not run
    printf 'adult() { [ "$1" -ge "$min" ]; }\n' >>src/a.sh
    # shellcheck disable=SC2016 # the code is written, not run
    printf 'big() { [ "$1" -gt "$top" ]; }\n' >>src/b.sh
    # shellcheck disable=SC2016 # the code is written, not run
    printf 'small() { [ "$1" -le "$few" ]; }\n' >>src/c.sh
    git add -A
    git commit -q -m "Feat"
  ) || return 1
  printf '%s\n' "$b"
}

# check DIR CHECK: t.sh in DIR runs CHECK (committed on feat)
check() {
  printf '. src/a.sh; . src/b.sh; . src/c.sh\n%s\necho 1 ok\n' "$2" >"$1/t.sh"
  (cd "$1" && git add -A && git commit -q -m "Check")
}

# the demo: only the plain cases are tested, so no boundary mutant is noticed
weak='adult 30 && ! adult 5 && big 200 && ! big 5 && small 1 && ! small 9 || exit 1'
# with the boundary cases
strong='adult 18 && ! adult 17 && big 100 && ! big 99 && small 3 && ! small 4 || exit 1'
# when SLOW is set and src/a.sh holds its mutant (-gt), the check marks it and runs
# a heartbeat that ignores TERM (MODE ignore) or dies on it, for 60 s at most
# shellcheck disable=SC2016 # the check is written, not run
slow='if [ -n "${SLOW:-}" ] && grep -q -- -gt src/a.sh; then touch "$MARK"; perl "$BEAT_PL" "$BEAT" "$SLOW"; fi'

# the checks that remove or change the journal first wait until the round
# has written the check's process group into it, so that write is done
cat >"$work/pgid.pl" <<'EOF'
alarm 10;
for (;;) {
  my $t;
  if (open my $h, '<', '.git/method-mutate-journal') { local $/; $t = <$h> }
  last if defined $t && $t =~ /^pgid [0-9]+$/m;
  select undef, undef, undef, 0.01;
}
EOF

# --- usage ---
p=$(new_project "$weak") || abort_sandbox
w="$p/w"
mr "$w" --minutes 0
expect "--minutes 0 is bad usage (exit 2)" 2 "mutate-changed: usage: mutate-changed.sh [--list | --recover] [--max N] [--minutes N]"
mr "$w" --minutes 601
expect "--minutes 601 is bad usage (exit 2)" 2 "mutate-changed: usage:"
mr "$w" --list --recover
expect "--list and --recover together are bad usage (exit 2)" 2 "mutate-changed: usage:"

# --- the demo: three mutants in three files, none noticed ---
mr "$w"
expect "the demo: three boundary mutants survive (exit 1)" 1 \
  "mutate-changed: run A (no mutant): unit passed in " "limit per mutant: unit 3" \
  "mutate-changed: survived: src/a.sh:2:18: '-ge' becomes '-gt'" \
  "mutate-changed: survived: src/b.sh:2:16: '-gt' becomes '-ge'" \
  "mutate-changed: survived: src/c.sh:2:18: '-le' becomes '-lt'" \
  "mutate-changed: FAIL - 3 changed lines in 3 files: 3 with a mutant" "3 mutants: 0 killed (0 by time limit), 3 survived, 0 not run"
clean "after it, the files are the commit, no journal is left and the lock is free" "$w"
if [ -x "$w/src/c.sh" ] && [ ! -x "$w/src/a.sh" ]; then pass "each file keeps its mode (755 and 644)"; else fail "each file keeps its mode"; fi
check "$w" "$strong"
mr "$w"
expect "with the boundary cases every mutant is killed, which is not a pass yet: SKIPPED kills-unchecked (exit 3)" 3 \
  "3 mutants: 3 killed (0 by time limit), 0 survived, 0 not run" \
  "mutate-changed: SKIPPED - kills-unchecked: " "no repeat or control run checks the kills yet (step 4b.4); this is not a pass"
lacks "and nothing survived" "survived:"
clean "the files are the commit again" "$w"
mr "$w" --max 1
expect "--max 1 runs the first mutant only: SKIPPED max-reached (exit 3)" 3 "1 mutants: 1 killed" "mutate-changed: SKIPPED - max-reached: "
printf 'unit\tany\t-\t(\\d+) ok\tbash t.sh\nunit2\tany\t-\t(\\d+) ok\tbash t.sh\n' >"$w/checks/project.tsv"
printf 'PRODUCT_PATHS=src\nMUTATE_PATHS=src\nMUTATION_CHECKS=unit\nMUTATION_CHECKS=unit2\n' >"$w/.claude/method.conf"
(cd "$w" && git add -A && git commit -q -m "Two checks")
mr "$w" --minutes 1
expect "when a round cannot fit --minutes it is not run: SKIPPED time-reached (exit 3)" 3 "0 killed (0 by time limit), 0 survived, 3 not run" \
  "mutate-changed: SKIPPED - time-reached: "
check "$w" 'if grep -q -- -gt src/a.sh; then echo 0 ok; exit 0; fi; '"$weak"
mr "$w" --max 1
expect "a check that passes but examines nothing on a mutant does not kill it" 1 \
  "mutate-changed: survived: src/a.sh:2:18: '-ge' becomes '-gt' (unit, unit2 examined nothing)"

# --- run A ---
check "$w" 'exit 4'
mr "$w"
expect "run A: a check that fails without any mutant stops the run (exit 2)" 2 \
  "mutate-changed: FAIL - run A: unit did not pass without any mutant (FAIL: exit 4"
check "$w" "touch src/new.txt; $weak"
mr "$w"
expect "run A: a check that changes files stops the run, naming them (exit 2)" 2 "mutate-changed: FAIL - run A: the checks changed 1 files (src/new.txt) without any mutant"
rm -f "$w/src/new.txt"

# --- what a check does during a round ---
check "$w" "$weak"
printf 'PRODUCT_PATHS=src\nMUTATE_PATHS=src\nMUTATION_CHECKS=unit\n' >"$w/.claude/method.conf"
(cd "$w" && git add -A && git commit -q -m "One check")
feat_head=$(cd "$w" && git rev-parse HEAD)
# act DIR WHAT: the check does WHAT when src/a.sh holds a mutant
act() { check "$1" 'if grep -q -- -gt src/a.sh; then '"$2"'; fi; '"$weak"; }
act "$w" 'touch src/new.txt'
mr "$w" --max 1
expect "a check that writes a file during a round stops the run, naming it (exit 2)" 2 \
  "mutate-changed: FAIL - after the mutant at src/a.sh:2:18: the checks changed 1 files (src/new.txt)"
rm -f "$w/src/new.txt"
act "$w" 'git add src/a.sh'
mr "$w" --max 1
expect "a check that stages the mutant: the journal stays, naming the index (exit 2)" 2 \
  "the index holds the mutant of src/a.sh (it was staged)" "the journal stays"
(cd "$w" && git reset -q --hard "$feat_head" && rm -f .git/method-mutate-journal)
act "$w" 'git commit -q -am oops'
mr "$w" --max 1
expect "a check that commits the mutant: the journal stays, naming HEAD (exit 2)" 2 "holds the mutant of src/a.sh: undo that change"
(cd "$w" && git reset -q --hard "$feat_head" && rm -f .git/method-mutate-journal)
act "$w" 'git stash -q'
mr "$w" --max 1
expect "a check that stashes the mutant: the journal stays, naming the stash (exit 2)" 2 "a stash made during the run holds the mutant of src/a.sh"
(cd "$w" && git stash clear && git reset -q --hard "$feat_head" && rm -f .git/method-mutate-journal)
act "$w" 'git add src/a.sh && git show HEAD:src/a.sh >src/a.sh && git stash -q'
mr "$w" --max 1
expect "a check that stashes only the staged mutant: the stash's index part is seen (exit 2)" 2 "a stash made during the run holds the mutant of src/a.sh"
(cd "$w" && git stash clear && git reset -q --hard "$feat_head" && rm -f .git/method-mutate-journal)
# shellcheck disable=SC2016 # the command is run by the check, not here
act "$w" 'c=$(git stash create) && git update-ref refs/stash "$c" && rm -f .git/logs/refs/stash'
mr "$w" --max 1
expect "a stash without a reflog that holds the mutant is seen (exit 2)" 2 "a stash made during the run holds the mutant of src/a.sh"
(cd "$w" && git update-ref -d refs/stash && git reset -q --hard "$feat_head" && rm -f .git/method-mutate-journal)
act "$w" 'rm -f .git/method-mutate-journal; git add src/a.sh'
mr "$w" --max 1
expect "a check that removes the journal and stages the mutant: the index is named (exit 2)" 2 "the index holds the mutant of src/a.sh"
if [ -f "$w/.git/method-mutate-journal" ]; then pass "and the journal is written again"; else fail "and the journal is written again"; fi
(cd "$w" && git reset -q --hard "$feat_head" && rm -f .git/method-mutate-journal)
act "$w" 'git commit -q --allow-empty -m Empty'
mr "$w" --max 1
expect "a check that commits (not the mutant): the run stops, naming it (exit 2)" 2 "after the mutant at src/a.sh:2:18: HEAD moved during the run"
(cd "$w" && git reset -q --hard "$feat_head")
act "$w" 'printf "x\n" >>src/b.sh; git stash push -q -- src/b.sh'
mr "$w" --max 1
expect "a check that makes a stash (not of the mutant): the run stops, naming it (exit 2)" 2 "a stash was made during the run"
(cd "$w" && git stash clear && git reset -q --hard "$feat_head")
# the check leaves a process behind that writes the mutant back once TERM
# comes (its sleeper ends on TERM; the shell around it ignores TERM, so it
# goes on to write): the group is stopped before the file is put back
# shellcheck disable=SC2016 # the check is written, not run
act "$w" 'cp src/a.sh "$MUT"; (trap "" TERM; perl -e "\$SIG{TERM} = sub { exit 0 }; sleep 30"; cat "$MUT" >src/a.sh) & :'
out=$(cd "$w" && env CI= MUT="$work/mut" bash "$mutate" --max 1 2>&1)
code=$?
expect "a leftover that writes the mutant back when stopped: the group is stopped first, then the file put back" 1 "survived: src/a.sh:2:18"
clean "and the files are the commit" "$w"
printf 'unit\tany\t-\t(\\d+) ok\tbash t.sh\nunit2\tany\t-\t(\\d+) ok\tbash t.sh\n' >"$w/checks/project.tsv"
printf 'PRODUCT_PATHS=src\nMUTATE_PATHS=src\nMUTATION_CHECKS=unit\nMUTATION_CHECKS=unit2\n' >"$w/.claude/method.conf"
act "$w" 'mkdir -p .git/method-mutate-journal.tmp'
mr "$w" --max 1
expect "an error in the middle of a round puts the mutant back before it stops (exit 2)" 2 "mutate-changed: FAIL - cannot write the journal" "src/a.sh put back; the run stopped"
rmdir "$w/.git/method-mutate-journal.tmp"
clean "and the files are the commit" "$w"
printf 'unit\tany\t-\t(\\d+) ok\tbash t.sh\n' >"$w/checks/project.tsv"
printf 'PRODUCT_PATHS=src\nMUTATE_PATHS=src\nMUTATION_CHECKS=unit\n' >"$w/.claude/method.conf"
(cd "$w" && git add -A && git commit -q -m "One check again")
feat_head=$(cd "$w" && git rev-parse HEAD)
act "$w" 'git clean -q -fdx'
mr "$w" --max 1
expect "a check that runs git clean -fdx cannot remove the journal: the round ends normally" 1 "survived: src/a.sh:2:18"
clean "and the files are the commit" "$w"
check "$w" "$weak"

# --- a check that starts a merge with autostash, which stops on a conflict:
# the autostash holds the mutant, so the journal stays ---
ap=$(new_project "$weak") || abort_sandbox
aw="$ap/w"
(cd "$aw" && git checkout -q -b side main && printf 'x\n' >other.txt && git add other.txt && git commit -q -m "Side" &&
  git checkout -q feat && printf 'y\n' >other.txt && git add other.txt && git commit -q -m "Mine")
check "$aw" 'if grep -q -- -gt src/a.sh; then git merge -q --autostash side >/dev/null 2>&1; fi; '"$weak"
mr "$aw" --max 1
expect "a merge whose autostash holds the mutant keeps the journal, naming it (exit 2)" 2 \
  "a merge is in progress, and its autostash can hold the mutant of src/a.sh; finish or abort it"
(cd "$aw" && git merge --abort >/dev/null 2>&1)
if grep -q -- -gt "$aw/src/a.sh"; then pass "setup: after the abort the mutant is back on disk"; else fail "setup: after the abort the mutant is back on disk"; fi
mr "$aw" --recover
expect "then --recover puts it back" 0 "RECOVERED - 1 files put back"
clean "and the files are the commit" "$aw"

# --- a build tool that compares file times below the second (make, ninja):
# every write is later than a build made before it, also in the same
# second, so each mutant is rebuilt and the build is current afterwards ---
bp=$(new_project "$weak") || abort_sandbox
bw="$bp/w"
printf 'build/\n' >"$bw/.gitignore"
cat >"$bw/t.sh" <<'EOF'
perl -MTime::HiRes=time,sleep -e 'my $t = time; sleep(1.05 - ($t - int $t))'
mkdir -p build
if perl -MTime::HiRes=stat -e 'my @s = stat "src/a.sh"; my @o = stat "build/a.sh"; exit(!(!@o || $s[9] > $o[9]))'; then cp src/a.sh build/a.sh; fi
. build/a.sh
adult 18 && ! adult 17 || exit 1
echo 1 ok
EOF
(cd "$bw" && git add -A && git commit -q -m "Build")
mr "$bw" --max 1
expect "a mutant written in the same second as a build is still rebuilt and killed" 3 "1 mutants: 1 killed"
if (cd "$bw" && bash t.sh) | grep -q '^1 ok$'; then pass "and afterwards the build is current again"; else fail "and afterwards the build is current again"; fi

# --- an edit made while a run is going is never overwritten: the next
# round's file is edited while its write waits for the clock (the editor,
# started by the first round's check, waits for the journal that names
# src/b.sh, so it does not have to catch the short time between rounds) ---
ep2=$(new_project "$weak") || abort_sandbox
ew2="$ep2/w"
# shellcheck disable=SC2016 # the check is written, not run
check "$ew2" 'if grep -q -- -gt src/a.sh; then perl -MPOSIX -e '\''POSIX::setsid(); alarm 30; my ($j, $f) = @ARGV; my $want = " " . unpack("H*", $f) . " "; for (;;) { my $t; if (open my $h, "<", $j) { local $/; $t = <$h> } last if defined $t && index($t, $want) >= 0; select undef, undef, undef, 0.01 } open my $o, ">>", $f; print $o "# edit\n"; close $o'\'' .git/method-mutate-journal src/b.sh </dev/null >/dev/null 2>&1 & fi; '"$weak"
perl -e 'my $t = time + 10; utime $t, $t, $ARGV[0]' "$ew2/src/b.sh"
mr "$ew2" --max 2
expect "an edit made while the run waits to write a file stops the run, and is kept (exit 2)" 2 \
  "mutate-changed: FAIL - src/b.sh was changed during the run: no mutant was written to it, and the change is kept; the run stopped"
if grep -q '^# edit$' "$ew2/src/b.sh"; then pass "and the edit is still there"; else fail "and the edit is still there" "$(cat "$ew2/src/b.sh")"; fi
if [ -e "$ew2/.git/method-mutate-journal" ]; then fail "and no journal is left (no mutant was written)"; else pass "and no journal is left (no mutant was written)"; fi

# --- an edit made while the round's put-back waits for the clock is kept:
# the put-back's own check sees it. The editor, started by the check on the
# mutant, edits 0.7 s after the check has ended, inside the 1 s the
# put-back waits (it starts about 0.25 s after the check ends); were it early or late, another guard would keep the edit,
# so only exit 2 and the edit are asked ---
pb=$(new_project "$weak") || abort_sandbox
pw="$pb/w"
# shellcheck disable=SC2016 # the check is written, not run
check "$pw" 'if grep -q -- -gt src/a.sh; then rm -f .git/check-ended; perl -MPOSIX -e '\''POSIX::setsid(); alarm 30; my ($m, $f) = @ARGV; select undef, undef, undef, 0.01 until -e $m; select undef, undef, undef, 0.7; open my $o, ">>", $f; print $o "# edit\n"; close $o'\'' .git/check-ended src/a.sh </dev/null >/dev/null 2>&1 & fi; '"$weak"'; touch .git/check-ended'
perl -e 'my $t = time + 10; utime $t, $t, $ARGV[0]' "$pw/src/a.sh"
mr "$pw" --max 1
expect "an edit made while the put-back waits for the clock stops the run (exit 2)" 2 "mutate-changed: FAIL - "
case "$out" in
  *"src/a.sh was changed "*", and it still holds the mutant's change (line 2, column 18: '-ge' becomes '-gt'"*) pass "and the line says where the mutant may still be" ;;
  *"the checks changed 1 files (src/a.sh)"*) pass "and the line says where the mutant may still be (the edit came after the put-back)" ;;
  *) fail "and the line says where the mutant may still be" "$out" ;;
esac
if grep -q '^# edit$' "$pw/src/a.sh"; then pass "and the edit is still there"; else fail "and the edit is still there" "$(cat "$pw/src/a.sh")"; fi

# --- a signal while the next mutant's write waits for the clock: the file
# is put back, and no check runs on that mutant ---
sg=$(new_project "$weak") || abort_sandbox
sw="$sg/w"
# shellcheck disable=SC2016 # the check is written, not run
check "$sw" 'if grep -q -- -ge src/b.sh; then touch "$SAW"; fi; '"$weak"
perl -e 'my $t = time + 10; utime $t, $t, $ARGV[0]' "$sw/src/b.sh"
rm -f "$work/saw"
(cd "$sw" && exec env CI= SAW="$work/saw" perl -e 'alarm 300; setpgrp(0, 0); exec @ARGV' bash "$mutate" --max 2) >"$work/w.out" 2>&1 &
wpid=$!
# (once the journal names src/b.sh, its write waits for the clock)
perl -e 'alarm 60; my ($j, $want) = @ARGV; for (;;) { my $t; if (open my $h, "<", $j) { local $/; $t = <$h> } last if defined $t && index($t, $want) >= 0; select undef, undef, undef, 0.01 }' \
  "$sw/.git/method-mutate-journal" " $(printf 'src/b.sh' | perl -ne 'print unpack "H*", $_') "
kill -INT -- "-$wpid"
wait "$wpid"
code=$?
out=$(cat "$work/w.out")
expect "a signal while the next mutant's write waits for the clock: put back and stopped (exit 2)" 2 "mutate-changed: FAIL - stopped by SIGINT; src/b.sh put back"
if [ -e "$work/saw" ]; then fail "and no check ran on that mutant"; else pass "and no check ran on that mutant"; fi
clean "and the files are the commit" "$sw"

# --- the whole-second cache: a check that reuses its result while the file's
# time in seconds and its size are the same must still run on each mutant ---
cp_=$(new_project "$strong") || abort_sandbox
cw="$cp_/w"
printf 'min=18\nmax=99\n' >"$cw/src/a.sh"
(cd "$cw" && git add -A && git commit -q -m "Two bounds" && git push -q origin feat:main 2>/dev/null && git fetch -q origin)
# two mutants of the same size in one file: the first is tested, the second not
# shellcheck disable=SC2016 # the code is written, not run
printf 'adult() { [ "$1" -ge "$min" ]; }\nlimit() { [ "$1" -le "$max" ]; }\n' >>"$cw/src/a.sh"
# shellcheck disable=SC2016 # the check is written, not run
printf 'key=$(perl -e '\''my @s = stat "src/a.sh"; print "$s[9]-$s[7]"'\'')\nif [ -f "$CACHE/$key" ]; then cat "$CACHE/$key"; exit "$(cat "$CACHE/$key.rc")"; fi\n. src/a.sh\nif adult 18 && ! adult 17; then r=0; echo 1 ok; else r=1; fi\nmkdir -p "$CACHE"; echo "$r" >"$CACHE/$key.rc"; if [ "$r" = 0 ]; then echo 1 ok >"$CACHE/$key"; else : >"$CACHE/$key"; fi\nexit "$r"\n' >"$cw/t.sh"
(cd "$cw" && git add -A && git commit -q -m "Cache")
out=$(cd "$cw" && env CI= CACHE="$work/cache" bash "$mutate" --max 2 2>&1)
code=$?
expect "a cache keyed on the time in seconds and the size never takes a mutant for another: the untested one survives" 1 \
  "survived: src/a.sh:4:18: '-le' becomes '-lt'" "2 mutants: 1 killed"
if (cd "$cw" && CACHE="$work/cache" bash t.sh) | grep -q '^1 ok$'; then pass "and the original passes again afterwards"; else fail "and the original passes again afterwards"; fi
now=$(perl -e 'print time')
ahead=$(perl -e 'my @s = stat $ARGV[0]; print $s[9] - $ARGV[1]' "$cw/src/a.sh" "$now")
if [ "$ahead" -le 3 ]; then pass "after four writes of one file its time runs at most 3 s ahead of the clock ($ahead s)"; else fail "after four writes of one file its time runs at most 3 s ahead of the clock ($ahead s)"; fi
rm -rf "$work/cache"

# --- ten writes of one file in a few seconds: its time runs at most 3 s
# ahead of the clock (the write function waits up to 1 s per write) ---
kp=$(new_project "$weak") || abort_sandbox
kw="$kp/w"
# shellcheck disable=SC2016 # the code is written, not run
printf 'f1() { [ "$1" -ge "$min" ]; }\nf2() { [ "$1" -ge "$min" ]; }\nf3() { [ "$1" -ge "$min" ]; }\nf4() { [ "$1" -ge "$min" ]; }\nf5() { [ "$1" -ge "$min" ]; }\n' >>"$kw/src/a.sh"
(cd "$kw" && git add -A && git commit -q -m "Five more")
mr "$kw" --max 8
expect "setup: five mutants in one file survive" 1 "survived: src/a.sh:7:15"
now=$(perl -e 'print time')
ahead=$(perl -e 'my @s = stat $ARGV[0]; print $s[9] - $ARGV[1]' "$kw/src/a.sh" "$now")
if [ "$ahead" -le 3 ]; then pass "after many writes of one file its time runs at most 3 s ahead of the clock ($ahead s)"; else fail "after many writes of one file its time runs at most 3 s ahead of the clock ($ahead s)"; fi

# --- the environment a check runs in ---
ep=$(new_project "$weak") || abort_sandbox
ew="$ep/w"
cat >"$ew/env.pl" <<'EOF'
use POSIX ();
for my $s (qw(INT TERM HUP QUIT PIPE)) {
  my $pid = fork;
  if (!$pid) { kill $s, $$; select undef, undef, undef, 0.5; POSIX::_exit(0) }
  waitpid $pid, 0;
  exit 3 unless $? & 127;    # ignored in the check
}
if (opendir my $d, '/proc/self/fd') {
  exit 4 if grep { (readlink("/proc/self/fd/$_") || '') =~ /method-run\.lock/ } readdir $d;
}
exit 0;
EOF
# shellcheck disable=SC2016 # the check is written, not run
check "$ew" '[ "$FOO" = bar ] || exit 5; [ "${PERL5LIB:-}" = /nowhere ] || exit 6; ulimit -c 0; perl env.pl || exit $?; perl -MPOSIX -e '\''POSIX::setsid(); open my $f, ">", $ARGV[0]; print $f "$$\n"; close $f; sleep 20'\'' "$LEFT" & sleep 0.2; '"$weak"
out=$(cd "$ew" && env CI= FOO=bar PERL5LIB=/nowhere LEFT="$work/left" bash "$mutate" --max 1 2>&1)
code=$?
expect "a check gets the caller's variables (PERL5LIB too), the stop signals at their defaults and no lock" 1 "survived: src/a.sh:2:18"
if [ "$(lock_state "$ew/.git/method-run.lock")" = "ex=free sh=free" ]; then
  pass "a process that left its group (setsid) does not hold the lock after the run"
else
  fail "a process that left its group (setsid) does not hold the lock after the run"
fi
if [ -f "$work/left" ]; then kill "$(cat "$work/left")" 2>/dev/null; rm -f "$work/left"; fi

# --- a git operation in progress, and a cut-off run's check output ---
(cd "$w" && git bisect start >/dev/null 2>&1)
mr "$w" --max 1
expect "a run does not start during a merge, rebase or bisect (exit 2)" 2 "mutate-changed: FAIL - a bisect is in progress; finish or abort it first"
(cd "$w" && git bisect reset >/dev/null 2>&1)
: >"$w/.git/method-mutate-1-1.out"
: >"$w/.git/method-mutate-journal.tmp"
mr "$w" --recover
expect "a cut-off run's check output and journal temp file are removed" 0 "RECOVERED - nothing to recover"
if [ -e "$w/.git/method-mutate-1-1.out" ] || [ -e "$w/.git/method-mutate-journal.tmp" ]; then fail "and the files are gone"; else pass "and the files are gone"; fi

# a leftover of a cut-off journal write does not stop the next run
: >"$w/.git/method-mutate-journal.tmp"
mr "$w" --max 1
expect "a leftover journal temp file is removed before the journal is written" 1 "survived: src/a.sh:2:18"
clean "and the files are the commit" "$w"

# --- a held lock ---
hold_lock "$w/.git/method-run.lock" 30 "$work/held"
mr "$w"
expect "while another holds the lock it waits 5 s, then stops: busy (exit 2)" 2 \
  "mutate-changed: FAIL - busy: another mutate-changed or a run-checks is running here; wait for it to end"
kill "$holder" 2>/dev/null
wait "$holder" 2>/dev/null

# --- kill -9 during a slow check, then the ways out ---
# (a branch for the rebase case below, made while the files are clean)
(cd "$w" && git checkout -q -b other main && printf 'x\n' >other.txt && git add other.txt && git commit -q -m "Other" && git checkout -q feat)
check "$w" "$slow; $weak"
rm -f "$work/mark" "$work/beat"
(cd "$w" && exec env CI= SLOW=ignore MARK="$work/mark" BEAT="$work/beat" bash "$mutate" --max 1) >"$work/k.out" 2>&1 &
mpid=$!
if wait_for "$work/mark" 20; then pass "setup: the slow check runs on the mutant"; else fail "setup: the slow check runs on the mutant" "$(cat "$work/k.out")"; fi
wait_for "$work/beat" 10
out=$(cd "$w" && bash "$root/method/scripts/method/status.sh" 2>&1)
case "$out" in
  *"work: LOOK - "*"mutate-changed is running: files hold mutants until it ends"*) pass "status names the run while it runs" ;;
  *) fail "status names the run while it runs" "$out" ;;
esac
kill -9 "$mpid"
wait "$mpid" 2>/dev/null
state=$(lock_state "$w/.git/method-run.lock")
if [ "$state" = "ex=busy sh=busy" ]; then pass "after kill -9 the lock stays held while the watchdog stops the check"; else fail "after kill -9 the lock stays held while the watchdog stops the check: $state"; fi
if stopped "$work/beat" 10; then pass "after kill -9 the watchdog stops the check that ignores TERM"; else fail "after kill -9 the watchdog stops the check that ignores TERM"; fi
if grep -q -- -gt "$w/src/a.sh" && [ -f "$w/.git/method-mutate-journal" ]; then
  pass "the mutant is on disk and the journal names it"
else
  fail "the mutant is on disk and the journal names it"
fi
out=$(cd "$w" && bash "$root/method/scripts/method/status.sh" 2>&1)
case "$out" in
  *"work: LOOK - "*"a mutate-changed run was cut off and left its journal: a file may hold a mutant; run mutate-changed.sh --recover"*) pass "status says the run was cut off" ;;
  *) fail "status says the run was cut off" "$out" ;;
esac
out=$(cd "$w" && env CI= bash "$root/method/scripts/method/done-check.sh" --ready 2>&1)
case "$out" in
  *"files: FAIL"*) pass "done-check's files condition fails" ;;
  *) fail "done-check's files condition fails" "$out" ;;
esac
out=$(cd "$w" && env CI= bash "$root/method/scripts/method/run-checks.sh" 2>&1)
case "$out" in
  *"run-checks: FAIL - a mutate-changed run was cut off and left its journal"*) pass "run-checks refuses" ;;
  *) fail "run-checks refuses" "$out" ;;
esac
# the ways out, each in a copy of the project as the kill left it
for k in committed staged edited gone stashed stagededit committededit stashededit movededit conf next rebase; do cp -R "$p" "$work/$k"; done
(cd "$work/committed/w" && git commit -q -am "Oops")
mr "$work/committed/w" --recover
expect "the mutant committed after the kill: refused, naming HEAD (exit 2)" 2 "holds the mutant of src/a.sh: undo that change in a new commit"
(cd "$work/staged/w" && git add src/a.sh)
mr "$work/staged/w" --recover
expect "the mutant staged after the kill: refused (exit 2)" 2 "the index holds the mutant of src/a.sh (it was staged)"
printf '# edited\n' >>"$work/edited/w/src/a.sh"
mr "$work/edited/w" --recover
expect "an edit after the kill: refused, not overwritten, saying where the mutant is (exit 2)" 2 \
  "src/a.sh was changed after its mutant was written, and it still holds the mutant's change (line 2, column 18: '-ge' becomes '-gt'; lines added above it move it): undo that change in the file (git diff " "and its name shows it; if you left the commit the run started on, check it out again first), then run mutate-changed.sh --recover"
case "$out" in
  *"remove "*"by hand"*) fail "and it never says to remove the journal by hand" "$out" ;;
  *) pass "and it never says to remove the journal by hand" ;;
esac
if grep -q '^# edited$' "$work/edited/w/src/a.sh"; then pass "and the edit stays"; else fail "and the edit stays"; fi
# the way out it gives: undo that one change; the edit is kept, the mutant
# is not
(cd "$work/edited/w" && perl -pi -e 's/-gt/-ge/ if $. == 2' src/a.sh)
mr "$work/edited/w" --recover
expect "the advice: once that change is undone, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
if grep -q '^# edited$' "$work/edited/w/src/a.sh" && ! grep -q -- -gt "$work/edited/w/src/a.sh"; then
  pass "the advice: the edit stays, without the mutant"
else
  fail "the advice: the edit stays, without the mutant" "$(cat "$work/edited/w/src/a.sh")"
fi
# a folder on the way removed after the kill: the file is missing, and the
# advice says where else the mutant may be and how to get out
rm -rf "$work/gone/w/src"
mr "$work/gone/w" --recover
expect "a folder removed after the kill: refused as missing, saying a copy may hold the mutant (exit 2)" 2 \
  "src/a.sh is missing; a copy made from it, or the file moved, may hold the mutant's change (line 2, column 18: '-ge' becomes '-gt'; lines added above it move it)"
from=$(printf '%s\n' "$out" | perl -ne 'print $1 if /--source=([0-9a-f]+) --staged --worktree/')
(cd "$work/gone/w" && git restore --source="$from" --staged --worktree -- src/a.sh)
mr "$work/gone/w" --recover
expect "the advice: once the file is back, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
(cd "$work/stashed/w" && git stash -q)
mr "$work/stashed/w" --recover
expect "the mutant stashed after the kill: refused (exit 2)" 2 "a stash made during the run holds the mutant of src/a.sh"
# an edit on top of the mutant, then staged: the file is refused first;
# once the change is undone in it, the index is
sd="$work/stagededit/w"
(cd "$sd" && printf '# edited\n' >>src/a.sh && git add src/a.sh)
mr "$sd" --recover
expect "an edit staged after the kill: the file is refused (exit 2)" 2 "src/a.sh was changed after its mutant was written, and it still holds the mutant's change"
(cd "$sd" && perl -pi -e 's/-gt/-ge/ if $. == 2' src/a.sh)
mr "$sd" --recover
expect "then the index is refused, as it holds the mutant's change with the edit (exit 2)" 2 "the index holds the mutant of src/a.sh (it was staged): unstage that change"
(cd "$sd" && git restore --staged -- src/a.sh)
mr "$sd" --recover
expect "once it is unstaged, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
if grep -q '^# edited$' "$sd/src/a.sh" && ! grep -q -- -gt "$sd/src/a.sh"; then pass "and the edit stays, without the mutant"; else fail "and the edit stays, without the mutant" "$(cat "$sd/src/a.sh")"; fi
# an edit on top of the mutant, then committed: HEAD is refused once the
# file is fixed, until the change is undone in a new commit
cd2="$work/committededit/w"
(cd "$cd2" && printf '# edited\n' >>src/a.sh && git commit -q -am "Edit")
(cd "$cd2" && perl -pi -e 's/-gt/-ge/ if $. == 2' src/a.sh)
mr "$cd2" --recover
expect "an edit committed after the kill: HEAD is refused, as it holds the mutant's change with the edit (exit 2)" 2 \
  "holds the mutant of src/a.sh: undo that change in a new commit"
(cd "$cd2" && git commit -q -am "Undo the mutant's change")
mr "$cd2" --recover
expect "once that is committed, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
# an edit on top of the mutant, then stashed: the stash is refused
se="$work/stashededit/w"
(cd "$se" && printf '# edited\n' >>src/a.sh && git stash -q)
mr "$se" --recover
expect "an edit stashed after the kill: the stash is refused, as it holds the mutant's change with the edit (exit 2)" 2 \
  "a stash made during the run holds the mutant of src/a.sh"
(cd "$se" && git stash pop -q && perl -pi -e 's/-gt/-ge/ if $. == 2' src/a.sh)
mr "$se" --recover
expect "once it is taken back and the change undone, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
if grep -q '^# edited$' "$se/src/a.sh" && ! grep -q -- -gt "$se/src/a.sh"; then pass "and the edit stays, without the mutant"; else fail "and the edit stays, without the mutant" "$(cat "$se/src/a.sh")"; fi
# lines added above the mutant's line: it is still found
mv2="$work/movededit/w"
(cd "$mv2" && perl -pi -e 'print "# added\n# added\n" if $. == 1' src/a.sh)
mr "$mv2" --recover
expect "lines added above the mutant's line after the kill: still found (exit 2)" 2 "and it still holds the mutant's change (line 2, column 18:"
(cd "$mv2" && perl -pi -e 's/-gt/-ge/' src/a.sh)
mr "$mv2" --recover
expect "once that change is undone where it now is, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
printf 'PRODUCT_PATHS=src\nMUTATE_PATHS=src\nMUTATION_CHECKS=nope\n' >"$work/conf/w/.claude/method.conf"
mr "$work/conf/w" --recover
expect "--recover does not read the settings, so broken ones do not keep the mutant on disk" 0 \
  "mutate-changed: recovered: src/a.sh put back (a run was cut off)" "mutate-changed: RECOVERED - 1 files put back; the journal is removed"
mr "$work/next/w" --max 1
expect "the next run puts the mutant back first, then runs" 1 "mutate-changed: recovered: src/a.sh put back (a run was cut off)" "survived: src/a.sh:2:18"
clean "and ends with the files the commit" "$work/next/w"
# a rebase with autostash stopped on a conflict hides the mutant in the autostash
rb="$work/rebase/w"
(cd "$rb" && printf 'y\n' >other.txt && git add other.txt && git commit -q -m "Mine" &&
  git -c rebase.autoStash=true rebase -q other >/dev/null 2>&1)
if [ -d "$rb/.git/rebase-merge" ] || [ -d "$rb/.git/rebase-apply" ]; then pass "setup: the rebase stopped on a conflict"; else fail "setup: the rebase stopped on a conflict"; fi
mr "$rb" --recover
expect "during a rebase, --recover refuses: the autostash holds the mutant (exit 2)" 2 "a rebase is in progress, and its autostash can hold a mutant"
(cd "$rb" && printf 'y\n' >other.txt && git add other.txt && GIT_EDITOR=true git rebase --continue >/dev/null 2>&1)
if grep -q -- -gt "$rb/src/a.sh"; then pass "setup: after the rebase the mutant is back on disk"; else fail "setup: after the rebase the mutant is back on disk"; fi
mr "$rb" --recover
expect "then --recover puts it back" 0 "RECOVERED - 1 files put back"
mr "$w" --recover
expect "--recover puts the mutant back and removes the journal" 0 "mutate-changed: RECOVERED - 1 files put back; the journal is removed"
clean "then the files are the commit" "$w"
mr "$w" --recover
expect "a second --recover has nothing to do" 0 "mutate-changed: RECOVERED - nothing to recover (no journal)"

# --- signals: the mutant is put back and the check stopped at once ---
# run_and DIR SIGNAL MODE [COMMAND]: starts a run whose slow check runs
# heartbeat MODE on the mutant, runs COMMAND in DIR once it does, sends SIGNAL, and KILL 1.5 s later as a
# harness would; sets out and code
run_and() {
  rm -f "$work/mark" "$work/beat" "$work/s.out"
  (cd "$1" && exec env CI= SLOW="$3" MARK="$work/mark" BEAT="$work/beat" perl -e 'setpgrp(0, 0); exec @ARGV' bash "$mutate" --max 1) >"$work/s.out" 2>&1 &
  spid=$!
  wait_for "$work/mark" 20
  wait_for "$work/beat" 10
  # (an optional command, run in the project before the signal)
  if [ -n "${4:-}" ]; then (cd "$1" && eval "$4"); fi
  # (INT to the whole group, as a terminal's Ctrl-C sends it: mutate's git
  # processes get it too)
  if [ "$2" = INT ]; then kill -INT -- "-$spid"; else kill "-$2" "$spid"; fi
  perl -e 'select undef, undef, undef, 1.5'
  kill -9 "$spid" 2>/dev/null
  wait "$spid"
  code=$?
  out=$(cat "$work/s.out")
}
run_and "$w" TERM ignore
expect "TERM, while the check ignores TERM: put back and stopped before the KILL (exit 2)" 2 \
  "mutate-changed: FAIL - stopped by SIGTERM; src/a.sh put back; the run stopped"
if stopped "$work/beat" 10; then pass "and the check is stopped"; else fail "and the check is stopped"; fi
clean "and the files are the commit, with no journal and the lock free" "$w"
if ls "$w/.git"/method-mutate-*.out >/dev/null 2>&1; then fail "and no check output is left in git's folder"; else pass "and no check output is left in git's folder"; fi
for sig in INT HUP QUIT; do
  run_and "$w" "$sig" plain
  expect "$sig: put back and stopped (exit 2)" 2 "mutate-changed: FAIL - stopped by SIG$sig; src/a.sh put back"
  clean "after $sig the files are the commit" "$w"
done

# an edit made while the check runs, then TERM: the put-back is refused,
# and the reason says why (once, with one --recover advice)
run_and "$w" TERM plain 'printf "# edit\n" >>src/a.sh'
expect "TERM after the file was edited during the check: not overwritten, and the reason says why (exit 2)" 2 \
  "mutate-changed: FAIL - stopped by SIGTERM; src/a.sh was changed after its mutant was written" "then run mutate-changed.sh --recover; the journal stays; the run stopped"
case "$out" in
  *--recover*--recover*) fail "and --recover is advised once" "$out" ;;
  *) pass "and --recover is advised once" ;;
esac
if grep -q '^# edit$' "$w/src/a.sh"; then pass "and the edit is still there"; else fail "and the edit is still there"; fi
(cd "$w" && git checkout -q -- src/a.sh)
mr "$w" --recover
expect "once the file is put back as committed, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
clean "and the files are the commit" "$w"

# a check removes the journal, and it cannot be written again: the file is
# put back all the same, and the line does not say a journal stays
act "$w" 'perl "'"$work/pgid.pl"'"; rm -f .git/method-mutate-journal; mkdir -p .git/method-mutate-journal.tmp'
mr "$w" --max 1
expect "a removed journal that cannot be written again: the file is put back all the same (exit 2)" 2 \
  "mutate-changed: FAIL - the journal was removed or changed during the round and could not be written again (cannot write the journal" "src/a.sh put back; the run stopped"
lacks "and it does not say the journal stays" "the journal stays"
rmdir "$w/.git/method-mutate-journal.tmp"
clean "and the files are the commit" "$w"
act "$w" 'perl "'"$work/pgid.pl"'"; rm -f .git/method-mutate-journal; mkdir -p .git/method-mutate-journal.tmp; printf "# edit\n" >>src/a.sh'
mr "$w" --max 1
expect "the same, and the file edited: the put-back is refused, and the line says no journal names it (exit 2)" 2 \
  "src/a.sh was changed after its mutant was written, and it still holds the mutant's change (line 2, column 18:" \
  "; and no journal names it, so --recover cannot find it (the journal was removed or changed during the round and could not be written again" \
  "once that is done, make sure src/a.sh no longer holds the mutant's change (line 2, column 18: '-ge' becomes '-gt')"
lacks "and it does not say the journal stays" "the journal stays"
rmdir "$w/.git/method-mutate-journal.tmp"
(cd "$w" && git checkout -q -- src/a.sh)
clean "and once the file is put back by hand, the files are the commit" "$w"
check "$w" 'if grep -q -- -gt src/a.sh; then perl "'"$work/pgid.pl"'"; rm -f .git/method-mutate-journal; mkdir -p .git/method-mutate-journal.tmp; fi; '"$slow; $weak"
run_and "$w" TERM plain
expect "the same, then TERM: the file is put back all the same (exit 2)" 2 \
  "mutate-changed: FAIL - stopped by SIGTERM; the journal was removed or changed during the round and could not be written again" "src/a.sh put back; the run stopped"
rmdir "$w/.git/method-mutate-journal.tmp"
clean "and the files are the commit" "$w"

act "$w" 'perl "'"$work/pgid.pl"'"; printf "mutate-changed journal 1\n" >.git/method-mutate-journal; git stash -q'
mr "$w" --max 1
expect "a check that cuts the journal short and stashes the mutant: the journal is written again, naming the stash (exit 2)" 2 \
  "a stash made during the run holds the mutant of src/a.sh"
mr "$w" --recover
expect "and --recover trusts it, naming the stash again (exit 2)" 2 "a stash made during the run holds the mutant of src/a.sh"
(cd "$w" && git stash clear)
mr "$w" --recover
expect "once the stash is dropped, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
clean "and the files are the commit" "$w"
# a blob release must read (HEAD holds the mutant's change with an edit)
# that git cannot read: "cannot tell"
# shellcheck disable=SC2016 # the check is written, not run
act "$w" 'printf "# e\n" >>src/a.sh && git commit -q -am Edit && b=$(git rev-parse HEAD:src/a.sh) && git show HEAD^:src/a.sh >src/a.sh && git add src/a.sh && rm -f ".git/objects/$(printf %s "$b" | cut -c1-2)/$(printf %s "$b" | cut -c3-)"'
before=$(cd "$w" && git rev-parse HEAD)
mr "$w" --max 1
expect "a blob release must read cannot be read: the journal stays, saying it cannot tell (exit 2)" 2 \
  "cannot tell whether git holds the mutant of src/a.sh (git cat-file failed)"
(cd "$w" && git reset -q --hard "$before")
mr "$w" --recover
expect "and once HEAD is back, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
clean "and the files are the commit" "$w"
# a refs/stash that names no commit, and a stash reflog left without
# refs/stash: "cannot tell"
# shellcheck disable=SC2016 # the check is written, not run
act "$w" 'git update-ref refs/stash "$(git rev-parse "HEAD^{tree}")"'
mr "$w" --max 1
expect "a refs/stash that names no commit: the journal stays, saying it cannot tell (exit 2)" 2 \
  "cannot tell whether git holds the mutant of src/a.sh (refs/stash names no commit)"
(cd "$w" && git update-ref -d refs/stash)
mr "$w" --recover
expect "and once it is gone, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
clean "and the files are the commit" "$w"
act "$w" 'git stash -q && rm -f .git/refs/stash'
mr "$w" --max 1
expect "a stash reflog left without refs/stash: the journal stays, saying it cannot tell (exit 2)" 2 \
  "cannot tell whether git holds the mutant of src/a.sh (a stash reflog is left without refs/stash)"
rm -f "$w/.git/logs/refs/stash"
mr "$w" --recover
expect "and once it is gone, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
clean "and the files are the commit" "$w"
# a check that makes the journal a folder: the file is put back, the line
# does not say the journal stays, and no journal temp file is left
act "$w" 'perl "'"$work/pgid.pl"'"; rm -f .git/method-mutate-journal; mkdir .git/method-mutate-journal'
mr "$w" --max 1
expect "a check that makes the journal a folder: the file is put back all the same (exit 2)" 2 \
  "the journal was removed or changed during the round and could not be written again" "src/a.sh put back; the run stopped"
lacks "and it does not say the journal stays" "the journal stays"
if [ -e "$w/.git/method-mutate-journal.tmp" ]; then fail "and no journal temp file is left"; else pass "and no journal temp file is left"; fi
rmdir "$w/.git/method-mutate-journal"
clean "and the files are the commit" "$w"
# a check that changes only the journal's process group and blocks its
# rewrite: the journal still names the files, so the round ends as usual
act "$w" 'perl "'"$work/pgid.pl"'"; perl -pi -e "s/^pgid [0-9]+\$/pgid 99999/" .git/method-mutate-journal; mkdir -p .git/method-mutate-journal.tmp'
mr "$w" --max 1
expect "a rewrite that fails over a journal that still names the files: the round ends as usual" 1 "survived: src/a.sh:2:18"
rmdir "$w/.git/method-mutate-journal.tmp"
clean "and the files are the commit" "$w"
# a lost journal, and a put-back that cannot be written (its temp name
# taken by a folder): the line says where the mutant is
# shellcheck disable=SC2016 # the check is written, not run
act "$w" 'perl "'"$work/pgid.pl"'"; tmp=$(perl -ne '\''print pack "H*", $1 if /^temp ([0-9a-f]+)$/'\'' .git/method-mutate-journal); mkdir "src/$tmp"; rm -f .git/method-mutate-journal; mkdir -p .git/method-mutate-journal.tmp'
mr "$w" --max 1
expect "a lost journal and a put-back that cannot be written: the line says where the mutant is (exit 2)" 2 \
  "cannot write next to src/a.sh" "and no journal names it, so --recover cannot find it" \
  "make sure src/a.sh no longer holds the mutant's change (line 2, column 18: '-ge' becomes '-gt')"
rmdir "$w/.git/method-mutate-journal.tmp" "$w"/src/.mutate-*.tmp
(cd "$w" && git checkout -q -- src/a.sh)
clean "and once the file is put back by hand, the files are the commit" "$w"

# --- odd git: a git on PATH that, once the check has seen the mutant and
# made FAKE_ARM (holding how many matching commands to let pass first),
# acts at the next git command holding FAKE_ON: MODE cut sends INT to the
# run's group, as a Ctrl-C would, and the command dies of it; keep sends
# INT, and the command still ends well; fail makes the command fail ---
mkdir -p "$work/fakegit"
cat >"$work/fakegit/git" <<'EOF'
#!/bin/sh
case "$*" in
  *"$FAKE_ON"*)
    if [ -e "$FAKE_ARM" ]; then
      n=$(cat "$FAKE_ARM")
      if [ "${n:-0}" -gt 0 ]; then
        echo $((n - 1)) >"$FAKE_ARM"
      else
        rm -f "$FAKE_ARM"
        case $FAKE_MODE in
          fail) exit 128 ;;
          keep) trap '' INT ;;
        esac
        kill -s INT 0
      fi
    fi ;;
esac
exec "$REAL_GIT" "$@"
EOF
chmod +x "$work/fakegit/git"
# odd_git ON MODE MAX: a run through that git, with --max MAX; sets out and code
odd_git() {
  rm -f "$work/arm"
  (cd "$w" && exec env CI= PATH="$work/fakegit:$PATH" REAL_GIT="$(command -v git)" FAKE_ARM="$work/arm" FAKE_ON="$1" FAKE_MODE="$2" \
    perl -e 'alarm 300; setpgrp(0, 0); exec @ARGV' bash "$mutate" --max "$3") >"$work/g.out" 2>&1
  code=$?
  out=$(cat "$work/g.out")
}
# shellcheck disable=SC2016 # the check is written, not run
act "$w" 'touch "$FAKE_ARM"'
# release's git ls-files is cut off by Ctrl-C: the signal is the reason,
# with what failed after it
odd_git "ls-files -s -z" cut 1
expect "Ctrl-C while mutate runs git: the signal is named first, then what failed (exit 2)" 2 \
  "mutate-changed: FAIL - stopped by SIGINT (then: cannot tell whether git holds the mutant of src/a.sh (git ls-files failed)"
mr "$w" --recover
expect "and --recover then removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
clean "and the files are the commit" "$w"
# a signal while a round's compare runs (its git for-each-ref ends well):
# no next mutant is written, and after the last round the signal is said,
# not lost
odd_git "for-each-ref" keep 2
expect "a signal while the round's compare runs: no next mutant is written (exit 2)" 2 "mutate-changed: FAIL - stopped by SIGINT; the run stopped"
clean "and the files are the commit" "$w"
odd_git "for-each-ref" keep 1
expect "a signal while the last round's compare runs: said, not lost (exit 2)" 2 "mutate-changed: FAIL - stopped by SIGINT; the run stopped"
clean "and the files are the commit" "$w"
# a git command release asks that fails means "cannot tell", never "not
# there": HEAD's git ls-tree, then (with a stash made during the run) the
# stash's, after HEAD's is let pass
odd_git "ls-tree" fail 1
expect "release's git ls-tree of HEAD fails: the journal stays, saying it cannot tell (exit 2)" 2 \
  "cannot tell whether git holds the mutant of src/a.sh (git ls-tree failed); run mutate-changed.sh --recover"
mr "$w" --recover
expect "and --recover then removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
clean "and the files are the commit" "$w"
# shellcheck disable=SC2016 # the check is written, not run
act "$w" 'echo 1 >"$FAKE_ARM"; printf "x\n" >>src/b.sh; git stash push -q -- src/b.sh'
odd_git "ls-tree" fail 1
expect "release's git ls-tree of a stash fails: the journal stays, saying it cannot tell (exit 2)" 2 \
  "cannot tell whether git holds the mutant of src/a.sh (git ls-tree failed); run mutate-changed.sh --recover"
(cd "$w" && git stash clear)
mr "$w" --recover
expect "and once the stash is dropped, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
clean "and the files are the commit" "$w"
# release's other git commands, with a check that stashes the mutant (or
# commits it): a failure, or a Ctrl-C, is "cannot tell" too
# shellcheck disable=SC2016 # the check is written, not run
act "$w" 'touch "$FAKE_ARM"; git stash -q'
for mode in fail cut; do
  odd_git "--verify refs/stash^{commit}" "$mode" 1
  expect "release's git rev-parse of refs/stash ends badly ($mode): the journal stays (exit 2)" 2 \
    "cannot tell whether git holds the mutant of src/a.sh (git rev-parse refs/stash failed); run mutate-changed.sh --recover"
  (cd "$w" && git stash clear)
  mr "$w" --recover
  expect "and once the stash is dropped, --recover removes the journal ($mode)" 0 "RECOVERED - 0 files put back; the journal is removed"
  clean "and the files are the commit ($mode)" "$w"
done
# shellcheck disable=SC2016 # the check is written, not run
act "$w" 'touch "$FAKE_ARM"; git stash -q; printf "x\n" >>src/b.sh; git stash -q'
odd_git "--walk-reflogs" fail 1
expect "release's walk of the stash reflog fails (the mutant in stash@{1}): the journal stays (exit 2)" 2 \
  "cannot tell whether git holds the mutant of src/a.sh (git rev-list --walk-reflogs failed)"
(cd "$w" && git stash clear)
mr "$w" --recover
expect "and once the stashes are dropped, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
clean "and the files are the commit" "$w"
# shellcheck disable=SC2016 # the check is written, not run
act "$w" 'touch "$FAKE_ARM"; git add src/a.sh && git show HEAD:src/a.sh >src/a.sh && git stash -q'
odd_git "^2^{commit}" fail 1
expect "release's look for a stash's index part fails: the journal stays (exit 2)" 2 \
  "cannot tell whether git holds the mutant of src/a.sh (git rev-parse "
(cd "$w" && git stash clear)
mr "$w" --recover
expect "and once the stash is dropped, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
clean "and the files are the commit" "$w"
# shellcheck disable=SC2016 # the check is written, not run
act "$w" 'touch "$FAKE_ARM"; git commit -q -am Mutant && git show HEAD^:src/a.sh >src/a.sh && git add src/a.sh'
before=$(cd "$w" && git rev-parse HEAD)
odd_git "--verify HEAD^{commit}" fail 1
expect "release's git rev-parse of HEAD fails (HEAD holds the mutant): the journal stays (exit 2)" 2 \
  "cannot tell whether git holds the mutant of src/a.sh (git rev-parse HEAD failed)"
(cd "$w" && git reset -q --hard "$before")
mr "$w" --recover
expect "and once HEAD is back, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
clean "and the files are the commit" "$w"
# an autostash a merge left without its merge (MERGE_AUTOSTASH): looked at
# like a stash
# shellcheck disable=SC2016 # the check is written, not run
act "$w" 'c=$(git stash create) && echo "$c" >.git/MERGE_AUTOSTASH && git checkout -- src/a.sh'
mr "$w" --max 1
expect "an autostash a merge left (MERGE_AUTOSTASH) that holds the mutant keeps the journal (exit 2)" 2 \
  "the autostash a merge left (MERGE_AUTOSTASH) holds the mutant of src/a.sh: git merge --quit moves it to the stash list"
rm -f "$w/.git/MERGE_AUTOSTASH"
mr "$w" --recover
expect "and once it is gone, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
clean "and the files are the commit" "$w"
act "$w" 'echo not-an-id >.git/MERGE_AUTOSTASH'
mr "$w" --max 1
expect "a MERGE_AUTOSTASH that names no commit: the journal stays, saying it cannot tell (exit 2)" 2 \
  "cannot tell whether git holds the mutant of src/a.sh (reading MERGE_AUTOSTASH failed)"
rm -f "$w/.git/MERGE_AUTOSTASH"
mr "$w" --recover
expect "and once it is gone, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
clean "and the files are the commit" "$w"
# shellcheck disable=SC2016 # the check is written, not run
act "$w" 'touch "$FAKE_ARM"'
odd_git "--git-path MERGE_AUTOSTASH" fail 1
expect "release's look for MERGE_AUTOSTASH fails: the journal stays (exit 2)" 2 \
  "cannot tell whether git holds the mutant of src/a.sh (git rev-parse --git-path failed)"
mr "$w" --recover
expect "and --recover then removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
clean "and the files are the commit" "$w"
check "$w" "$slow; $weak"

# HUP that came ignored (nohup) stays ignored: the run goes on
rm -f "$work/mark" "$work/beat"
(cd "$w" && trap '' HUP && exec env CI= SLOW=short MARK="$work/mark" BEAT="$work/beat" bash "$mutate" --max 1) >"$work/h.out" 2>&1 &
hpid=$!
wait_for "$work/mark" 20
kill -HUP "$hpid"
wait "$hpid"
code=$?
out=$(cat "$work/h.out")
expect "HUP that came ignored, as under nohup, stays ignored" 1 "survived: src/a.sh:2:18"
clean "and the files are the commit" "$w"

# --- output into a pipe that closes (| head -1) ---
check "$w" "$weak"
rc=$(cd "$w" && env CI= bash "$mutate" --max 1 2>/dev/null | head -1 >/dev/null; echo "${PIPESTATUS[0]}")
if [ "$rc" = 1 ]; then pass "output into a closed pipe does not end the run early (exit 1, not 141)"; else fail "output into a closed pipe does not end the run early (exit $rc)"; fi
clean "and the files are the commit" "$w"

# --- a looping mutant is stopped by its time limit (3 times run A, plus 30 s);
# an unchanged counter ends the loop after about 60 s anyway ---
lp=$(new_project "$weak") || abort_sandbox
lw="$lp/w"
# shellcheck disable=SC2016 # the code is written, not run
printf 'count() { i=0; n=0; while [ "$i" -lt 3 ] && [ "$n" -lt 600 ]; do\n  i=$((i + 2))\n  n=$((n + 1)); sleep 0.1; done; }\n' >"$lw/src/b.sh"
check "$lw" 'count'
(cd "$lw" && git push -q origin feat:main 2>/dev/null && git fetch -q origin)
# shellcheck disable=SC2016 # the code is written, not run
printf 'count() { i=0; n=0; while [ "$i" -lt 3 ] && [ "$n" -lt 600 ]; do\n  i=$((i + 1))\n  n=$((n + 1)); sleep 0.1; done; }\n' >"$lw/src/b.sh"
(cd "$lw" && git add -A && git commit -q -m "Step by one")
mr "$lw"
expect "a mutant that loops is killed by the time limit" 3 "1 mutants: 1 killed (1 by time limit)"
clean "and the files are the commit, with no process left holding the lock" "$lw"

# --- hand-made journals ---
jw="$work/next/w"
jf="$jw/.git/method-mutate-journal"
start=$(cd "$jw" && git rev-parse HEAD)
sb=$(cd "$jw" && git rev-parse HEAD:src/a.sh)
# the ids of the original and of its mutant (-gt), as a run would write them
cat >"$work/ids.pl" <<'EOF'
use Digest::SHA qw(sha1_hex sha256_hex);
local $/;
open my $f, '<', $ARGV[0] or die;
my $t = <$f>;
(my $m = $t) =~ s/-ge/-gt/;
print join(' ', sha1_hex('blob ' . length($m) . "\0$m"), sha256_hex($t), sha256_hex($m));
EOF
ids=$(perl "$work/ids.pl" "$jw/src/a.sh")
# the SHA-256 of the mutant's line (line 2, -gt)
ml=$(perl -MDigest::SHA=sha256_hex -e 'local $/; open my $f, "<", $ARGV[0] or die; my $t = <$f>; $t =~ s/-ge/-gt/; print sha256_hex((split /\n/, $t)[1])' "$jw/src/a.sh")
# and of it with the lines around it (none after it: the file ends there)
mw=$(perl -MDigest::SHA=sha256_hex -e 'local $/; open my $f, "<", $ARGV[0] or die; my $t = <$f>; $t =~ s/-ge/-gt/; my @l = split /\n/, $t, -1; print sha256_hex(join "\n", $l[0], $l[1], $l[2])' "$jw/src/a.sh")
# hex TEXT: TEXT as hex digits
hex() { printf '%s' "$1" | perl -ne 'print unpack "H*", $_'; }
# journal PGID END [PATH [TEMP [IDS]]]: a journal for src/a.sh (or PATH),
# which holds the original on disk, to JF (or the file JF names)
journal() {
  # shellcheck disable=SC2086 # the ids are three words on purpose
  printf 'mutate-changed journal 1\nstart %s\nstash -\ntemp %s\npgid %s\nfile %s %s %s %s %s %s %s %s\n%s' "$start" \
    "$(hex "${4:-.mutate-1.tmp}")" "$1" "$(hex "${3:-src/a.sh}")" "$sb" ${5:-$ids} \
    "$(hex "line 2, column 18: '-ge' becomes '-gt'")" "${ML:-$ml}" "$mw" "$2" >"${JF:-$jf}"
}
journal - ''
mr "$jw" --recover
expect "a journal cut off while written is refused and kept (exit 2)" 2 "cannot be trusted: it has no end line"
if [ -f "$jf" ]; then pass "and it stays"; else fail "and it stays"; fi
journal 1 'end
'
mr "$jw" --recover
expect "a journal whose process group is 1 is refused (exit 2)" 2 "its process group is not a number of 2 or more"
journal - 'end
'
printf 'half\n' >"$jw/src/.mutate-1.tmp"
mr "$jw" --recover
expect "a leftover temp file is removed, and a journal whose file holds the original is released" 0 "RECOVERED - 0 files put back; the journal is removed"
if [ -e "$jw/src/.mutate-1.tmp" ]; then fail "the leftover temp file is gone"; else pass "the leftover temp file is gone"; fi
printf 'mutate-changed journal 1\nstart %s\ntemp %s\npgid -\nend\n' "$start" "$(hex .mutate-1.tmp)" >"$jf"
mr "$jw" --recover
expect "a journal with a line missing is refused (exit 2)" 2 "cannot be trusted: a line is missing"
printf 'mutate-changed journal 1\nstart %s\nstash -\ntemp %s\npgid -\nwhat now\nend\n' "$start" "$(hex .mutate-1.tmp)" >"$jf"
mr "$jw" --recover
expect "a journal with a line that does not parse is refused (exit 2)" 2 "cannot be trusted: a line does not parse"
rm -f "$jf"
mkfifo "$jf" 2>/dev/null
if [ -p "$jf" ]; then
  mr "$jw" --recover
  expect "a FIFO where the journal should be is refused, not read (exit 2)" 2 "cannot be trusted: it is not a regular file"
  rm -f "$jf"
else
  skip "a FIFO where the journal should be: mkfifo is not available here"
fi
journal - 'end
' .git/config
mr "$jw" --recover
expect "a journal naming a file in git's own folder is refused (exit 2)" 2 "a path names the method's or git's own files"
journal - 'end
' .claude/method.conf
mr "$jw" --recover
expect "a journal naming one of the method's own files is refused (exit 2)" 2 "a path names the method's or git's own files"
# (the method copied into the project: its own folder is refused too)
(cd "$jw" && mkdir -p scripts && cp -R "$root/method/scripts/method" scripts/method)
journal - 'end
' scripts/method/lib/esc.pl
out=$(cd "$jw" && env CI= perl -e 'alarm 300; exec @ARGV' bash scripts/method/mutate-changed.sh --recover 2>&1)
code=$?
expect "a journal naming a file in the method's own folder is refused (exit 2)" 2 "a path names the method's or git's own files"
rm -rf "$jw/scripts"
printf 'not a journal\nend\n' >"$jf"
mr "$jw" --recover
expect "a file that is not a journal is refused (exit 2)" 2 "its first line is not a mutate-changed journal"
journal - 'end
' ../outside
mr "$jw" --recover
expect "a journal naming a path outside the working tree is refused (exit 2)" 2 "a path is not a plain path inside the working tree"
journal - 'end
' src/a.sh ../../evil.tmp
mr "$jw" --recover
expect "a journal naming a temp file this tool does not make is refused (exit 2)" 2 "its temp name is not one this tool makes"
mut_ids=$(perl -MDigest::SHA=sha1_hex,sha256_hex -e 'local $/; open my $f, "<", $ARGV[0]; my $t = <$f>; print join(" ", sha1_hex("blob " . length($t) . "\0$t"), "0" x 64, sha256_hex($t))' "$jw/src/a.sh")
journal - 'end
' src/a.sh .mutate-1.tmp "$mut_ids"
mr "$jw" --recover
expect "a journal whose original does not match the stored one is refused (exit 2)" 2 "the stored original of src/a.sh does not match the journal"
# the mutant's line is counted against the original (here a journal whose
# mutant's line is one the original has, min=18): a changed file with that
# line once is not taken for the mutant; with it once more, it is, also
# with CRLF line ends
min18=$(perl -MDigest::SHA=sha256_hex -e 'print sha256_hex("min=18")')
printf '# edited\n' >>"$jw/src/a.sh"
ML=$min18 journal - 'end
'
mr "$jw" --recover
expect "a changed file whose mutant's line is no more often in it than in the original is not refused" 0 "RECOVERED - 0 files put back; the journal is removed"
perl -pi -e 's/\n/\r\n/; $_ .= "min=18\r\n" if $. == 1' "$jw/src/a.sh"
ML=$min18 journal - 'end
'
mr "$jw" --recover
expect "with that line once more, CRLF line ends and all, it is refused (exit 2)" 2 "src/a.sh was changed after its mutant was written, and it still holds the mutant's change"
(cd "$jw" && git checkout -q -- src/a.sh)
rm -f "$jf"
cp -R "$work/next" "$work/link"
(cd "$work/link/w" && mv src real && ln -s real src && perl -pi -e 's/-ge/-gt/' real/a.sh)
: >"$work/link/w/real/.mutate-1.tmp"
JF="$work/link/w/.git/method-mutate-journal" journal - 'end
'
mr "$work/link/w" --recover
expect "a folder on the way that is a link is never written through (exit 2)" 2 "a folder on the way to src/a.sh is a link or not a folder" \
  "and what it leads to holds the mutant (line 2, column 18: '-ge' becomes '-gt'; lines added above it move it): make it the real folder again"
if [ -e "$work/link/w/real/.mutate-1.tmp" ]; then pass "and nothing behind the link is removed"; else fail "and nothing behind the link is removed"; fi
perl -e 'setpgrp(0, 0); open my $f, ">", $ARGV[0]; print $f getpgrp(), "\n"; close $f; alarm 20; sleep 20' "$work/group" &
gpid=$!
wait_for "$work/group" 10
journal "$(cat "$work/group")" 'end
'
mr "$jw" --recover
expect "a journal whose checks still run is refused after 3 s, naming the group (exit 2)" 2 \
  "processes of the cut-off run may still run in process group $(cat "$work/group")"
kill "$gpid" 2>/dev/null
wait "$gpid" 2>/dev/null
rm -f "$jf"

# --- the mutant's line has a twin elsewhere in the original (round 3 of
# 4b.3b). killed DIR WHEN BODY: a run of all mutants in DIR whose check
# (BODY) runs a heartbeat that ignores TERM once WHEN holds on a mutant;
# mutate is killed with -9 then, and its watchdog stops the check ---
killed() {
  rm -f "$work/mark" "$work/beat"
  check "$1" "if $2; then touch \"\$MARK\"; perl \"\$BEAT_PL\" \"\$BEAT\" ignore; fi; $3"
  (cd "$1" && exec env CI= MARK="$work/mark" BEAT="$work/beat" perl -e 'alarm 300; exec @ARGV' bash "$mutate") >"$work/x.out" 2>&1 &
  xpid=$!
  if wait_for "$work/mark" 60 && wait_for "$work/beat" 10; then pass "setup: the check runs on that mutant"; else fail "setup: the check runs on that mutant" "$(cat "$work/x.out")"; fi
  kill -9 "$xpid" 2>/dev/null
  wait "$xpid" 2>/dev/null
  if stopped "$work/beat" 10; then pass "setup: the watchdog stops the check"; else fail "setup: the watchdog stops the check"; fi
}
# the mutant ('-ge' becomes '-gt' in nonneg) makes its line equal to one of
# pos(); an edit that removes pos() does not hide it: its lines around it
# differ
t1=$(new_project "$weak") || abort_sandbox
tw="$t1/w"
# shellcheck disable=SC2016 # the code is written, not run
printf 'min=18\npos() {\n  [ "$1" -gt 0 ] || return 1\n}\nnonneg() {\n  [ "$1" -ge 0 ] || return 1\n}\n' >"$tw/src/a.sh"
(cd "$tw" && git add -A && git commit -q -m "Twin lines")
# shellcheck disable=SC2016 # the check is written, not run
killed "$tw" '[ "$(grep -c -- "-gt 0" src/a.sh)" = 2 ]' 'pos 1 && nonneg 1 || exit 1'
perl -i -ne 'print unless $. >= 2 && $. <= 4' "$tw/src/a.sh"
mr "$tw" --recover
expect "an edit that removes the mutant's twin line: the mutant is still found, by its lines around it (exit 2)" 2 \
  "src/a.sh was changed after its mutant was written, and it still holds the mutant's change (line 6, column"
perl -pi -e 's/-gt 0/-ge 0/' "$tw/src/a.sh"
mr "$tw" --recover
expect "once that change is undone, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
if ! grep -q 'pos()' "$tw/src/a.sh" && grep -q -- '-ge 0' "$tw/src/a.sh"; then pass "and the edit stays, without the mutant"; else fail "and the edit stays, without the mutant" "$(cat "$tw/src/a.sh")"; fi
# the mutant ('0' becomes '1') makes its line, and the lines around it,
# equal to an earlier block: an edit that removes that block leaves it
# unable to tell, so it refuses, and the way out ends at the start
t2=$(new_project "$weak") || abort_sandbox
tw2="$t2/w"
# shellcheck disable=SC2016 # the code is written, not run
printf 'min=18\nif [ -n "${X:-}" ]; then\n  y=1\nfi\nif [ -n "${X:-}" ]; then\n  y=0\nfi\n' >"$tw2/src/a.sh"
(cd "$tw2" && git add -A && git commit -q -m "Twin blocks")
# shellcheck disable=SC2016 # the check is written, not run
killed "$tw2" '[ "$(grep -c "y=1" src/a.sh)" = 2 ]' 'true'
perl -i -ne 'print unless $. >= 2 && $. <= 4' "$tw2/src/a.sh"
mr "$tw2" --recover
expect "an edit that removes a twin of the mutant's lines: it cannot tell, so it refuses (exit 2)" 2 \
  "src/a.sh was changed after its mutant was written, and it cannot tell whether the mutant's change is still in it" \
  "then make your change again, leaving that change out"
from=$(printf '%s\n' "$out" | perl -ne 'print $1 if /--source=([0-9a-f]+) --staged --worktree/')
(cd "$tw2" && git restore --source="$from" --staged --worktree -- src/a.sh)
mr "$tw2" --recover
expect "following its way out, --recover removes the journal" 0 "RECOVERED - 0 files put back; the journal is removed"
clean "and the files are the commit" "$tw2"

# --- a file removed while its mutant's write waits for the clock: no
# mutant was written, and no journal is left ---
rp=$(new_project "$weak") || abort_sandbox
rw="$rp/w"
# shellcheck disable=SC2016 # the check is written, not run
check "$rw" 'if grep -q -- -gt src/a.sh; then perl -MPOSIX -e '\''POSIX::setsid(); alarm 30; my ($j, $f) = @ARGV; my $want = " " . unpack("H*", $f) . " "; for (;;) { my $t; if (open my $h, "<", $j) { local $/; $t = <$h> } last if defined $t && index($t, $want) >= 0; select undef, undef, undef, 0.01 } unlink $f'\'' .git/method-mutate-journal src/b.sh </dev/null >/dev/null 2>&1 & fi; '"$weak"
perl -e 'my $t = time + 10; utime $t, $t, $ARGV[0]' "$rw/src/b.sh"
mr "$rw" --max 2
expect "a file removed while its mutant's write waits: no mutant was written, and the run stops (exit 2)" 2 \
  "src/b.sh was changed during the run: no mutant was written to it, and the change is kept"
if [ -e "$rw/.git/method-mutate-journal" ]; then fail "and no journal is left"; else pass "and no journal is left"; fi

# --- a native Windows perl is refused ---
# shellcheck disable=SC2016 # perl code, not shell
out=$(cd "$w" && env CI= perl -e 'my $f = shift; require $f; $^O = "MSWin32"; Mutate::main()' "$lib/mutate.pl" 2>&1)
code=$?
expect "a native Windows perl is refused (exit 2)" 2 "mutate-changed: FAIL - a native Windows perl cannot run mutants"

if [ -f "$work/repos" ]; then while IFS= read -r d; do drop_sandbox "$d"; done <"$work/repos"; fi
export HOME="$saved_home"
unset GIT_CONFIG_NOSYSTEM
drop_sandbox "$work"
echo "tests: mutate run: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
