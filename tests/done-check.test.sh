#!/usr/bin/env bash
# Tests for method/scripts/method/done-check.sh (rules M008, M089, M108).
# Each test builds a small project with a local bare remote in a throwaway
# folder, runs the checks with run-checks.sh and reads done-check's report.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: done-check"
root=$(repo_root)
done_check="$root/method/scripts/method/done-check.sh"
run_checks="$root/method/scripts/method/run-checks.sh"
work=$(new_sandbox_dir) || abort_sandbox
repos=""
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
git config --global advice.detachedHead false

OPEN='Review-Verdict: request-changes-open - not reviewed yet'
OK='Review-Verdict: approve'

# msg DIR ARGS...: commits in DIR with the message from printf ARGS (a
# subject, a blank line, the verdict line), allowing an empty commit
msg() {
  d=$1
  shift
  # shellcheck disable=SC2059 # the message is a printf format on purpose
  printf "$@" >"$work/msg"
  (cd "$d" && git commit -q --allow-empty --cleanup=verbatim -F "$work/msg")
}

# amend DIR LINE: the head commit's message becomes "Change" and LINE; its
# files and parents stay as they are
amend() {
  printf 'Change\n\n%s\n' "$2" >"$work/msg"
  (cd "$1" && git commit -q --amend --allow-empty --cleanup=verbatim -F "$work/msg")
}

# rc DIR [VAR=VALUE...]: runs run-checks in DIR (not in CI unless a VAR says
# so). Sets rc_out and rc_code.
rc() {
  d=$1
  shift
  rc_out=$(cd "$d" && env CI= "$@" bash "$run_checks" 2>&1)
  rc_code=$?
}

# dc DIR [VAR=VALUE...]: runs done-check --ready in DIR. Sets out and code.
dc() {
  d=$1
  shift
  out=$(cd "$d" && env CI= "$@" bash "$done_check" --ready 2>&1)
  code=$?
}

# expect NAME CODE STRING...: the last report exited CODE and holds every STRING
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

# lacks NAME STRING: the last report does not hold STRING
lacks() {
  case "$out" in
    *"$2"*) fail "$1" "$out" ;;
    *) pass "$1" ;;
  esac
}

# rc_ok NAME: the last run-checks passed (a test's setup)
rc_ok() {
  if [ "$rc_code" -eq 0 ]; then pass "$1"; else fail "$1: run-checks exit $rc_code" "$rc_out"; fi
}

# newest_log DIR: the path of DIR's newest run-checks log
newest_log() {
  (cd "$1" && for l in .method/local/logs/run-checks-*.log; do printf '%s\n' "$l"; done | LC_ALL=C sort | tail -n 1)
}

# new_project: prints a folder holding remote.git (bare) and w: main with one
# commit, pushed, origin/HEAD set; then w on branch feat with a project check
# (unit: fails while flaky.marker exists), .claude/method.conf
# (PRODUCT_PATHS=src) and src/a.txt, committed with an open verdict line
new_project() {
  b=$(new_sandbox_dir) || return 1
  repos="$repos $b"
  (
    cd "$b" || exit 1
    git init -q --bare remote.git
    git init -q w
    cd w || exit 1
    printf '*.marker\n' >.gitignore
    printf 'hello\n' >README
    git add -A
    git commit -q -m "Start" -m "Review-Verdict: not-required - the first commit"
    git remote add origin ../remote.git
    git push -q -u origin main 2>/dev/null
    git remote set-head origin main
    git checkout -q -b feat
    mkdir -p checks .claude src
    printf 'unit\tany\t-\t(\\d+) ok\ttest ! -e flaky.marker && echo 3 ok\n' >checks/project.tsv
    printf 'PRODUCT_PATHS=src\n' >.claude/method.conf
    printf 'x = 1\n' >src/a.txt
    git add -A
    git commit -q -m "Add the feature" -m "$OPEN"
  ) || return 1
  printf '%s\n' "$b"
}

# manifest DIR: every file under DIR with its SHA-256 and change time
manifest() { (cd "$1" && find . -type f | LC_ALL=C sort | perl -MDigest::SHA -ne 'chomp; my @s = stat; print "$_ ", Digest::SHA->new(256)->addfile($_)->hexdigest, " $s[9]\n"'); }

# --- READY ---
p=$(new_project) || abort_sandbox
w="$p/w"
rc "$w"
rc_ok "setup: run-checks passes on the feature"
amend "$w" "$OK"
head=$(cd "$w" && git rev-parse HEAD)
h7=$(cd "$w" && git rev-parse --short=7 HEAD)
main=$(cd "$w" && git rev-parse origin/main)
before=$(manifest "$w")
dc "$w"
after=$(manifest "$w")
expect "READY after run-checks and an amend that only adds the verdict line, with no new run (exit 0)" 0 \
  "done-check: files: PASS - the tracked files on disk are commit $h7, byte for byte; nothing untracked outside git's ignore rules" \
  "done-check: up to date: PASS - main is refs/remotes/origin/main ${main%"${main#???????}"} as of the last fetch; done-check does not fetch" \
  "done-check: checks: PASS - local run-checks log of " "the same files as HEAD; a local claim (RISKS #11)" \
  "done-check: elsewhere: PASS - every check in checks/*.tsv runs here (1)" \
  "done-check: verdict: PASS - approve, as typed in commit $h7; not yet backed by a review receipt (step 5)" \
  "done-check: verdicts start: PASS - VERDICTS_FROM is unset both on main and in this change" \
  "done-check: READY - $head is up to date with refs/remotes/origin/main $main; verdict approve as typed in the commit"
lacks "READY has no next: line" "done-check: next:"
if [ "$before" = "$after" ]; then pass "done-check changes no file, .git and the index included"; else fail "done-check changes no file" "$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after"))"; fi
if [ "$(printf '%s\n' "$out" | sed -n '$p')" = "$(printf '%s\n' "$out" | grep '^done-check: READY')" ]; then pass "READY is the last line"; else fail "READY is the last line" "$out"; fi

printf 'x = 2\n' >"$w/src/a.txt"
(cd "$w" && git add -A)
msg "$w" 'More\n\n%s\n' "$OPEN"
rc "$w"
msg "$w" 'Verdict\n\n%s\n' "$OK"
dc "$w"
expect "READY with an empty verdict commit on top of the run's commit" 0 "the same files as HEAD" "done-check: READY - "

# --- files ---
echo more >>"$w/src/a.txt"
dc "$w"
expect "an edit fails files, with the next step (exit 1)" 1 \
  "done-check: files: FAIL - 1 paths are not commit" "changed or staged (git status lists them): src/a.txt" \
  "done-check: next: commit, restore or remove them" "done-check: NOT READY - 1 conditions failed (files); $(cd "$w" && git rev-parse HEAD) against refs/remotes/origin/main"
(cd "$w" && git checkout -q -- src/a.txt)
: >"$w/src/new.txt"
dc "$w"
expect "an untracked file fails files" 1 "untracked, and not ignored by git: src/new.txt"
rm -f "$w/src/new.txt"
: >"$w/flaky2.marker"
dc "$w"
expect "a file git ignores does not fail files" 0 "done-check: READY - "
rm -f "$w/flaky2.marker"

# a project with a committed line-end rule and a script
printf '*.sh text eol=lf\n' >"$w/.gitattributes"
printf '#!/bin/sh\nset -e\nfalse\necho reached\n' >"$w/t.sh"
printf '@echo off\necho hi\n' >"$w/run.bat"
(cd "$w" && git add -A)
msg "$w" 'Scripts\n\n%s\n' "$OK"
rc "$w"
rc_ok "setup: run-checks passes with a committed eol=lf rule"
dc "$w"
expect "a committed line-end rule is READY" 0 "done-check: READY - "
perl -pi -e 's/\n/\r\n/ if $. == 2' "$w/t.sh"
dc "$w"
expect "one CR added to one line under eol=lf fails files, though git status sees nothing" 1 \
  "with CRs before line ends that the commit's .gitattributes does not ask for" "t.sh"
rm -f "$w/t.sh" && (cd "$w" && git checkout -q -- t.sh)
printf 'run.bat text eol=crlf\n' >"$w/.git/info/attributes"
rm -f "$w/run.bat" && (cd "$w" && git checkout -q -- run.bat)
dc "$w"
expect "a CRLF that only .git/info/attributes asks for fails files, and says why" 1 \
  "with CRs before line ends that the commit's .gitattributes does not ask for" "run.bat" \
  ".git/info/attributes holds rules, so a conversion cannot be told from an edit"
rm -f "$w/.git/info/attributes" "$w/run.bat" && (cd "$w" && git checkout -q -- run.bat)
(cd "$w" && git config core.autocrlf true)
perl -pi -e 's/\n/\r\n/' "$w/t.sh"
(cd "$w" && git add t.sh 2>/dev/null)
st_short=$(cd "$w" && git status --porcelain)
dc "$w"
if [ -z "$st_short" ]; then pass "setup: core.autocrlf hides a CRLF set -e script from git status"; else fail "setup: core.autocrlf hides the CRLF" "$st_short"; fi
expect "a set -e script made CRLF under a local core.autocrlf and added fails files" 1 \
  "with CRs before line ends that the commit's .gitattributes does not ask for" "t.sh"
(cd "$w" && git config --unset core.autocrlf)
rm -f "$w/t.sh" && (cd "$w" && git checkout -q -- t.sh && git reset -q)
dc "$w"
expect "setup: back to READY" 0 "done-check: READY - "

# a committed eol=crlf file and an ident file, in a fresh clone on Linux
printf '*.sh text eol=lf\n*.bat text eol=crlf\nid.txt ident\n' >"$w/.gitattributes"
# shellcheck disable=SC2016 # $Id$ is meant literally
printf 'version $Id$\n' >"$w/id.txt"
(cd "$w" && git add -A 2>/dev/null)
msg "$w" 'Line ends\n\n%s\n' "$OK"
(cd "$w" && git push -q origin feat 2>/dev/null)
(cd "$p" && git clone -q -b feat remote.git fresh 2>/dev/null)
f="$p/fresh"
if grep -q "$(printf '\r')" "$f/run.bat" && grep -q 'Id: ' "$f/id.txt"; then pass "setup: the fresh clone has CRLF in run.bat and an expanded \$Id\$"; else fail "setup: the clone's checkout converted"; fi
rc "$f"
rc_ok "run-checks passes in a fresh clone with committed CRLF and ident files"
if grep -q '^tree at start clean$' "$f/$(newest_log "$f")"; then pass "its log says the tree was clean at the start"; else fail "its log says the tree was clean at the start" "$(cat "$f/$(newest_log "$f")")"; fi
rc "$f" CI=true
rc_ok "the same with CI=true"
if grep -q '^tree at start clean$' "$f/$(newest_log "$f")" && grep -q '^where CI$' "$f/$(newest_log "$f")"; then pass "the CI log says clean too"; else fail "the CI log says clean too" "$(cat "$f/$(newest_log "$f")")"; fi
dc "$f"
expect "a fresh clone with files the commit's .gitattributes converts is READY" 0 \
  "done-check: files: PASS - the tracked files on disk are commit" "2 of them as the commit's .gitattributes asks" "done-check: READY - "
dc "$f" CI=true
expect "and READY in CI from the CI log" 0 "done-check: checks: PASS - CI run-checks log of " "done-check: READY - "

# a submodule moved after the run
s="$p/sub"
(git init -q "$s" && cd "$s" && echo one >s.txt && git add -A && git commit -q -m one && echo two >s.txt && git commit -q -am two)
(cd "$w" && git submodule add -q "$s" sub 2>/dev/null)
(cd "$w" && git add -A)
msg "$w" 'Submodule\n\n%s\n' "$OK"
rc "$w"
dc "$w"
expect "setup: READY with a submodule" 0 "done-check: READY - "
(cd "$w/sub" && git checkout -q HEAD~1)
dc "$w"
expect "a submodule moved after the run fails files" 1 "done-check: files: FAIL" "sub"
(cd "$w/sub" && git checkout -q -)

# --- up to date (M108) ---
(cd "$p" && git clone -q remote.git other 2>/dev/null && cd other && echo later >>README && git commit -q -am "Later" -m "$OK" && git push -q origin main 2>/dev/null)
(cd "$w" && git fetch -q origin)
dc "$w"
expect "main moved on: up to date fails, with the whole next step" 1 \
  "done-check: up to date: FAIL - refs/remotes/origin/main has 1 commits this branch does not (as of the last fetch)" \
  "done-check: next: merge refs/remotes/origin/main into this branch, run the checks, have the merged version reviewed, and end the merge commit with its own verdict line"
(cd "$w" && git merge -q --no-edit origin/main 2>/dev/null)
rc "$w"
dc "$w"
expect "a merge of main with no verdict line fails the verdict, saying why" 1 "done-check: up to date: PASS" \
  "done-check: verdict: FAIL - the head commit merges" "so the merged version needs its own"
amend "$w" "$OK"
dc "$w"
expect "the same merge with an approving line is READY" 0 "done-check: READY - "
(cd "$w" && git push -q origin feat 2>/dev/null)
(cd "$p" && git clone -q --depth 1 --no-single-branch -b feat "file://$p/remote.git" shallow1 2>/dev/null)
dc "$p/shallow1"
expect "a shallow clone that cannot tell says so" 1 "done-check: up to date: FAIL - the history here is shallow, so whether refs/remotes/origin/main is merged cannot be told" \
  "fetch the whole history (git fetch --unshallow origin)"
lacks "and does not say to merge main" "commits this branch does not"
(cd "$p" && git clone -q --depth 3 --no-single-branch -b feat "file://$p/remote.git" shallow3 2>/dev/null)
dc "$p/shallow3"
expect "a shallow clone that holds main's tip passes up to date" 1 "done-check: up to date: PASS - main is refs/remotes/origin/main"
(cd "$p" && git clone -q --depth 1 -b feat "file://$p/remote.git" single 2>/dev/null)
(cd "$p/single" && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/feat)
dc "$p/single"
expect "origin/HEAD that names the task branch is not main; no main says how to fetch it" 1 \
  "done-check: up to date: FAIL - no main branch here (looked for origin/HEAD" "git fetch origin main:refs/remotes/origin/main"

# --- checks (M089) ---
q=$(new_project) || abort_sandbox
v="$q/w"
amend "$v" "$OK"
dc "$v"
expect "no log fails checks, saying to run them" 1 "done-check: checks: FAIL - no run-checks log of these files" \
  "done-check: next: run the checks: bash scripts/method/run-checks.sh"
rc "$v"
dc "$v"
expect "setup: READY after the run" 0 "done-check: READY - "
echo changed >"$v/src/a.txt"
(cd "$v" && git add -A)
amend "$v" "$OK"
dc "$v"
expect "a log of other files does not count" 1 "done-check: checks: FAIL - no run-checks log of these files"
rc "$v"
x=$(cd "$v" && git rev-parse HEAD)
e=$(cd "$v" && git commit-tree "$(git rev-parse "origin/main^{tree}")" -p origin/main -m "Other")
printf 'Change\n\n%s\n' "$OK" >"$work/msg"
n=$(cd "$v" && git commit-tree "$x^{tree}" -p "$e" -F "$work/msg")
(cd "$v" && git reset -q --hard "$n")
dc "$v"
expect "a log of the same files with other parents does not count" 1 "done-check: up to date: PASS" "done-check: checks: FAIL - no run-checks log of these files"
(cd "$v" && git reset -q --hard "$x")
printf 'Change, amended\n\n%s\n' "$OK" >"$work/msg"
(cd "$v" && git commit -q --amend --allow-empty --cleanup=verbatim -F "$work/msg")
(cd "$v" && git reflog expire --expire=now --all && git gc -q --prune=now 2>/dev/null)
if (cd "$v" && git cat-file -e "$x" 2>/dev/null); then fail "setup: the run's commit is pruned"; else pass "setup: the run's commit is pruned"; fi
dc "$v"
expect "a log whose commit was pruned does not count, and is named" 1 "logs name commits that are no longer in this repository"
rc "$v"
: >"$v/flaky.marker"
rc "$v"
dc "$v"
expect "a failing run fails checks, naming the check" 1 "done-check: checks: FAIL - the last run of these files (" ") failed: unit" \
  "done-check: next: fix them, then run the checks"
rm -f "$v/flaky.marker"
rc "$v"
dc "$v"
expect "a fail then a pass of the same files is READY, naming the failure" 0 \
  "runs of these files failed: unit; a check that fails sometimes is a finding for the review" "done-check: READY - " \
  "; 1 of 3 runs of these files failed: unit"
newest=$(newest_log "$v")
sed '$d' "$v/$newest" | sed '$d' >"$v/.method/local/logs/run-checks-29991231T235959Z-0000000001.log"
dc "$v"
expect "a newest log without END fails checks" 1 "did not finish (stopped, or a check hung)"
printf 'junk\n' >"$v/.method/local/logs/run-checks-29991231T235959Z-0000000001.log"
dc "$v"
expect "a newer log that cannot be read fails checks" 1 "a run-checks log newer than the last one of these files cannot be read"
rm -f "$v/.method/local/logs/run-checks-29991231T235959Z-0000000001.log"
echo again >"$v/src/a.txt"
(cd "$v" && git add -A)
amend "$v" "$OK"
echo dirty >>"$v/src/a.txt"
: >"$v/flaky.marker"
rc "$v"
(cd "$v" && git checkout -q -- src/a.txt)
rm -f "$v/flaky.marker"
rc "$v"
dc "$v"
expect "a failed run that started on uncommitted changes is not named" 0 "done-check: READY - "
lacks "(no earlier failure named)" "runs of these files failed"
: >"$v/flaky.marker"
rc "$v" CI=true
rm -f "$v/flaky.marker"
dc "$v"
expect "a failed CI run does not count for a local done-check" 0 "done-check: READY - "
lacks "(not named either)" "runs of these files failed"
echo dirty >>"$v/src/a.txt"
rc "$v"
(cd "$v" && git checkout -q -- src/a.txt)
dc "$v"
expect "a newest run that started on uncommitted changes fails checks" 1 "started on uncommitted changes" "done-check: next: commit first"

# --- elsewhere (M089) ---
rc "$v"
printf 'integ\tci\t-\t(\\d+) ok\techo 0 ok; exit 1\n' >>"$v/checks/project.tsv"
(cd "$v" && git add -A)
amend "$v" "$OK"
rc "$v"
rc_ok "setup: a CI-only check is not for here, so run-checks passes locally"
dc "$v"
expect "a CI-only check has no result here, so it is not READY" 1 "done-check: checks: PASS" \
  "done-check: elsewhere: FAIL - 1 checks run only in CI and done-check reads no CI result yet (step 9): integ"
printf 'unit\tany\t-\t(\\d+) ok\ttest ! -e flaky.marker && echo 3 ok\npriv\tlocal\t-\t(\\d+) ok\techo 0 ok; exit 1\n' >"$v/checks/project.tsv"
(cd "$v" && git add -A)
amend "$v" "$OK"
rc "$v" CI=true
rc_ok "setup: with CI=true, a local-only check is not for here"
dc "$v" CI=true
expect "CI=true for both: a local-only check has no result, so it is not READY" 1 \
  "done-check: elsewhere: FAIL - 1 checks run only locally, and no record of a local run is read yet: priv"
printf 'unit\tany\t-\t(\\d+) ok\ttest ! -e flaky.marker && echo 3 ok\n' >"$v/checks/project.tsv"
(cd "$v" && git add -A)
amend "$v" "$OK"
rc "$v"

# --- verdict (M008) ---
amend "$v" 'Review-Verdict: request-changes-open - round 3 fixes checked by tests, planted breaks and two checks of the fixes, not re-reviewed (3-round cap); CI waits on Actions minutes'
dc "$v"
expect "an open verdict line is not READY, and names the owner's way forward" 1 \
  "done-check: verdict: FAIL - the verdict line says request-changes-open (changes are still open; the reason names them): no review approved this version (SPEC R4)" \
  "re-plan or the owner decides (DECISIONS A7, A10)" "done-check: NOT READY - 1 conditions failed (verdict)"
amend "$v" 'Review-Verdict: request-changes-resolved'
dc "$v"
expect "a resolved verdict line is not READY: no review approved the fixes" 1 "the verdict line says request-changes-resolved"
amend "$v" 'Review-Verdict: not-required - a typo'
dc "$v"
expect "a not-required verdict line is not READY" 1 "the verdict line says not-required"
amend "$v" 'No verdict here'
dc "$v"
expect "no verdict line is not READY" 1 "done-check: verdict: FAIL - the head commit's verdict line: no line starts with Review-Verdict:"
amend "$v" 'Review-Verdict: fine'
dc "$v"
expect "an unknown verdict value is not READY" 1 "unknown value"
amend "$v" "$OK"

# --- verdicts start ---
# main: r0 (no line), r1 (sets up the project), r2 (VERDICTS_FROM=r1), r3
vs=$(new_sandbox_dir) || abort_sandbox
repos="$repos $vs"
(
  cd "$vs" || exit 1
  git init -q --bare remote.git
  git init -q w
  cd w || exit 1
  printf '*.marker\n' >.gitignore
  git add -A
  git commit -q -m "Root"
  mkdir -p checks .claude src
  printf 'unit\tany\t-\t(\\d+) ok\techo 3 ok\n' >checks/project.tsv
  printf 'PRODUCT_PATHS=src\n' >.claude/method.conf
  printf 'x = 1\n' >src/a.txt
  git add -A
  git commit -q -m "Project" -m "Review-Verdict: approve"
  printf 'PRODUCT_PATHS=src\nVERDICTS_FROM=%s\n' "$(git rev-parse HEAD)" >.claude/method.conf
  git commit -q -am "Start the verdicts" -m "Review-Verdict: approve"
  git commit -q --allow-empty -m "More" -m "Review-Verdict: approve"
  git remote add origin ../remote.git
  git push -q -u origin main 2>/dev/null
  git remote set-head origin main
  git checkout -q -b feat
) || abort_sandbox
y="$vs/w"
r0=$(cd "$y" && git rev-parse HEAD~3)
r1=$(cd "$y" && git rev-parse HEAD~2)
r2=$(cd "$y" && git rev-parse HEAD~1)
setvf() { # setvf DIR VALUE: commits VERDICTS_FROM=VALUE (or none) with an approving line
  if [ -n "$2" ]; then printf 'PRODUCT_PATHS=src\nVERDICTS_FROM=%s\n' "$2" >"$1/.claude/method.conf"; else printf 'PRODUCT_PATHS=src\n' >"$1/.claude/method.conf"; fi
  (cd "$1" && git add -A)
  msg "$1" 'Move VERDICTS_FROM\n\n%s\n' "$OK"
}
setvf "$y" "$r0"
rc "$y"
dc "$y"
expect "moving VERDICTS_FROM to an older commit accepts nothing (READY)" 0 \
  "done-check: verdicts start: PASS - this change moves VERDICTS_FROM from ${r1%"${r1#???????}"} to ${r0%"${r0#???????}"}; it accepts no commit without a valid verdict line"
(cd "$y" && git reset -q --hard origin/main)
setvf "$y" "$r2"
rc "$y"
dc "$y"
expect "moving it forward over commits with valid lines accepts nothing (READY)" 0 \
  "from ${r1%"${r1#???????}"} to ${r2%"${r2#???????}"}; it accepts no commit without a valid verdict line"
(cd "$y" && git reset -q --hard origin/main)
side=$(cd "$y" && git commit-tree "$(git rev-parse "HEAD^{tree}")" -p "$r1" -m "Side")
setvf "$y" "$side"
rc "$y"
dc "$y"
expect "a VERDICTS_FROM that is not on main fails" 1 "which is not on refs/remotes/origin/main's first-parent history, so status would report LOOK after the merge"

# main: b0 (no line, the project), b1 (no line), b2 (VERDICTS_FROM=b0)
vb=$(new_sandbox_dir) || abort_sandbox
repos="$repos $vb"
(
  cd "$vb" || exit 1
  git init -q --bare remote.git
  git init -q w
  cd w || exit 1
  mkdir -p checks .claude src
  printf 'unit\tany\t-\t(\\d+) ok\techo 3 ok\n' >checks/project.tsv
  printf 'PRODUCT_PATHS=src\n' >.claude/method.conf
  printf 'x = 1\n' >src/a.txt
  git add -A
  git commit -q -m "Project"
  git commit -q --allow-empty -m "Oops"
  printf 'PRODUCT_PATHS=src\nVERDICTS_FROM=%s\n' "$(git rev-parse HEAD~1)" >.claude/method.conf
  git commit -q -am "Start the verdicts" -m "Review-Verdict: approve"
  git remote add origin ../remote.git
  git push -q -u origin main 2>/dev/null
  git remote set-head origin main
  git checkout -q -b feat
) || abort_sandbox
z="$vb/w"
b0=$(cd "$z" && git rev-parse HEAD~2)
b1=$(cd "$z" && git rev-parse HEAD~1)
setvf "$z" "$b1"
rc "$z"
dc "$z"
expect "a move over a commit with no verdict line passes, naming it on the READY line (A30)" 0 \
  "done-check: verdicts start: PASS - this change moves VERDICTS_FROM from ${b0%"${b0#???????}"} to ${b1%"${b1#???????}"}; it accepts 1 commits on main without a valid verdict line: ${b1%"${b1#???????}"}" \
  "; accepts 1 commits on main without a valid verdict line: ${b1%"${b1#???????}"}"
(cd "$z" && git push -q origin feat 2>/dev/null)
(cd "$vb" && git clone -q --depth 2 -b feat "file://$vb/remote.git" shallow 2>/dev/null)
(cd "$vb/shallow" && git fetch -q --depth 1 origin main:refs/remotes/origin/main 2>/dev/null)
dc "$vb/shallow"
expect "a changed value in a shallow clone could not be checked" 1 "done-check: up to date: PASS" "which is not in this shallow history of refs/remotes/origin/main; could not check"
(cd "$z" && git reset -q --hard origin/main)
setvf "$z" ""
rc "$z"
dc "$z"
expect "removing it so a commit with no line leaves the range names that commit" 0 \
  "from ${b0%"${b0#???????}"} to unset; it accepts 1 commits on main without a valid verdict line: ${b1%"${b1#???????}"}"

# adoption: main has no verdict line yet; the change sets VERDICTS_FROM
va=$(new_sandbox_dir) || abort_sandbox
repos="$repos $va"
(
  cd "$va" || exit 1
  git init -q --bare remote.git
  git init -q w
  cd w || exit 1
  mkdir -p checks .claude src
  printf 'unit\tany\t-\t(\\d+) ok\techo 3 ok\n' >checks/project.tsv
  printf 'PRODUCT_PATHS=src\n' >.claude/method.conf
  printf 'x = 1\n' >src/a.txt
  git add -A
  git commit -q -m "Before the method"
  git remote add origin ../remote.git
  git push -q -u origin main 2>/dev/null
  git remote set-head origin main
  git checkout -q -b feat
) || abort_sandbox
u="$va/w"
c0=$(cd "$u" && git rev-parse HEAD)
setvf "$u" "$c0"
rc "$u"
dc "$u"
expect "adopting the method (VERDICTS_FROM set on a main with no verdict line) is READY" 0 \
  "this change moves VERDICTS_FROM from unset to ${c0%"${c0#???????}"}; it accepts no commit without a valid verdict line" "done-check: READY - "

# --- exit codes ---
(cd "$u" && git checkout -q main)
dc "$u"
expect "HEAD at main's tip: nothing to merge (exit 3)" 3 "done-check: NOTHING TO MERGE - $c0 is refs/remotes/origin/main's tip or behind it"
out=$(cd "$u" && bash "$done_check" 2>&1)
code=$?
expect "no argument is bad usage (exit 2)" 2 "done-check: usage: done-check.sh --ready"
out=$(cd "$u" && bash "$done_check" --ready extra 2>&1)
code=$?
expect "an extra argument is bad usage" 2 "done-check: usage: done-check.sh --ready"
mkdir -p "$work/plain"
out=$(cd "$work/plain" && GIT_CEILING_DIRECTORIES=$work bash "$done_check" --ready 2>&1)
code=$?
expect "outside a git working tree it cannot check (exit 2)" 2 "done-check: NOT READY - could not check: not inside a git working tree"
(cd "$q" && git clone -q remote.git elsewhere 2>/dev/null)
(cd "$v" && git config core.worktree "$q/elsewhere")
dc "$v"
expect "a core.worktree setting that points git elsewhere cannot be checked" 2 "a core.worktree setting points git elsewhere"
(cd "$v" && git config --unset core.worktree)

for d in $repos; do drop_sandbox "$d"; done
export HOME="$saved_home"
unset GIT_CONFIG_NOSYSTEM
drop_sandbox "$work"
echo "tests: done-check: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
