#!/usr/bin/env bash
# Tests for method/scripts/method/run-checks.sh (rules M002, M050, M051,
# M066). Each test builds a small repo in a throwaway folder and runs the
# checks there.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: run-checks"
root=$(repo_root)
rc="$root/method/scripts/method/run-checks.sh"
work=$(new_sandbox_dir) || abort_sandbox
T=$(printf '\t')
ESC=$(printf '\033')
repos=""

# new_repo: prints the path of a new repo on main holding src/a.txt and
# .claude/method.conf with PRODUCT_PATHS=src, committed.
new_repo() {
  r=$(new_sandbox_dir) || return 1
  repos="$repos $r"
  (
    cd "$r" || exit 1
    git init -q
    git symbolic-ref HEAD refs/heads/main
    git config user.name "Test"
    git config user.email "test@example.invalid"
    git config commit.gpgsign false
    git config core.autocrlf false
    mkdir -p src .claude checks
    printf 'hello\n' >src/a.txt
    printf 'PRODUCT_PATHS=src\n' >.claude/method.conf
    git add -A
    git commit -q -m base
  ) || return 1
  printf '%s\n' "$r"
}

# ck ID COMMAND: a checks line that runs anywhere, needs nothing and counts
# "N passed"; <T> stands for a TAB
ck() { printf '%s<T>any<T>-<T>^([0-9]+) passed<T>%s' "$1" "$2"; }

# tsv DIR LINE...: checks/main.tsv in DIR holds the LINEs (<T> becomes a
# TAB), committed
tsv() {
  d=$1
  shift
  printf '%s\n' "$@" | perl -pe 's/<T>/\t/g' >"$d/checks/main.tsv"
  (cd "$d" && git add -A && git commit -q -m checks)
}

# run DIR [VAR=VALUE...]: runs run-checks in DIR, with CI unset and the
# variables set. Sets out, code, last (the last line) and logf (the log).
run() {
  d=$1
  shift
  (cd "$d" && unset CI && env "$@" bash "$rc") >"$work/out" 2>&1
  code=$?
  out=$(cat "$work/out")
  last=$(printf '%s\n' "$out" | tail -n 1)
  logf=$(printf '%s\n' "$out" | sed -n '1s/^run-checks: log //p')
  if [ -n "$logf" ]; then logf="$d/$logf"; fi
}

# expect NAME CODE STRING...: the last run exited CODE and printed every STRING
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

# in_log NAME STRING...: the last run's log holds every STRING
in_log() {
  name=$1
  shift
  if [ -z "$logf" ] || [ ! -f "$logf" ]; then
    fail "$name: no log" "$out"
    return
  fi
  missing=""
  for s in "$@"; do
    grep -F -q -- "$s" "$logf" || missing="$missing [$s]"
  done
  if [ -n "$missing" ]; then fail "$name: the log lacks$missing" "$(cat "$logf")"; else pass "$name"; fi
}

# result ID: the RESULT line of check ID in the last log, without "RESULT<TAB>ID<TAB>"
result() { sed -n "s/^RESULT${T}$1${T}//p" "$logf"; }

P='^([0-9]+) passed'

# 1. results and exit codes
r=$(new_repo) || abort_sandbox
tsv "$r" "$(ck unit 'echo "3 passed"')"
run "$r"
expect "a passing run exits 0" 0 "run-checks: PASS - 4 passed; where local"
lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
if [ "$lines" -eq 3 ] && printf '%s\n' "$out" | sed -n 1p | grep -q '^run-checks: log \.method/local/logs/run-checks-[0-9]\{8\}T[0-9]\{6\}Z-[0-9]\{10\}\.log$' \
  && printf '%s\n' "$out" | sed -n 2p | grep -q '^passed: secrets fresh-clone unit tree-unchanged$'; then
  pass "a passing run prints the log, the passed ids and the last line only"
else
  fail "a passing run prints the log, the passed ids and the last line only" "$out"
fi
head_id=$(cd "$r" && git rev-parse HEAD)
in_log "the log starts with its header" "run-checks log" "started 20" "commit $head_id" "tree at start clean" "where local" "system "
if [ "$(result unit)" = "PASS${T}pass${T}any${T}3${T}examined 3 (checks/main.tsv line 1)" ] \
  && [ "$(grep -c '^RESULT' "$logf")" -eq 4 ] && [ "$(grep -c '^=== CHECK ' "$logf")" -eq 4 ]; then
  pass "the log holds a header and a RESULT line per check, with the count"
else
  fail "the log holds a header and a RESULT line per check, with the count" "$(cat "$logf")"
fi
if [ "$(tail -n 1 "$logf")" = "END${T}exit 0" ] && [ "$(tail -n 2 "$logf" | sed -n 1p)" = "$last" ]; then
  pass "the log ends with the screen's last line and END with the exit code"
else
  fail "the log ends with the screen's last line and END with the exit code" "$(tail -n 3 "$logf")"
fi
modes=$(perl -e 'printf "%o %o", (stat $ARGV[0])[2] & 0777, (stat $ARGV[1])[2] & 0777' "$logf" "$r/.method/local/logs")
if [ "$modes" = "600 700" ]; then pass "the log is readable only by its owner, in a private folder"; else fail "the log is readable only by its owner: modes $modes"; fi

tsv "$r" "$(ck unit 'echo "5 passed"; echo boom >&2; exit 4')"
run "$r"
expect "a non-zero exit is a FAIL with its last output lines" 1 "unit: FAIL - exit 4 (checks/main.tsv line 1)" "  5 passed" "  boom" \
  "run-checks: FAIL - 1 failed (unit), 3 passed, 0 skipped; where local"
if [ "$(tail -n 1 "$logf")" = "END${T}exit 1" ]; then pass "a failing run's log ends with exit 1"; else fail "a failing run's log ends with exit 1" "$(tail -n 2 "$logf")"; fi
tsv "$r" "$(ck unit 'echo "5 passed"; kill -9 $$')"
run "$r"
expect "a check killed by a signal after printing a count is a FAIL" 1 "unit: FAIL - killed by signal 9" "  5 passed"
tsv "$r" "$(ck unit '(echo "3 passed"; exit 1) | tail -n 5')"
run "$r"
expect "a failure hidden behind | tail is caught by pipefail" 1 "unit: FAIL - exit 1"

tsv "$r" "$(ck unit 'echo "3 passed"')" "bench<T>ci<T>-<T>$P<T>echo '2 passed'"
run "$r"
expect "a CI-only check is SKIPPED locally and the rest still passes" 0 "bench: SKIPPED - runs in CI only (checks/main.tsv line 2)" \
  "run-checks: PASS - 4 passed, 1 not for here; where local"
run "$r" CI=true
expect "in CI the CI-only check runs" 0 "run-checks: PASS - 5 passed; where CI"
tsv "$r" "priv<T>local<T>-<T>$P<T>echo '2 passed'" "$(ck unit 'echo "3 passed"')"
run "$r" CI=true
expect "a local-only check is SKIPPED in CI" 0 "priv: SKIPPED - runs locally only" "1 not for here; where CI"
tsv "$r" "bench<T>ci<T>-<T>$P<T>echo '2 passed'"
run "$r"
expect "when no project check runs here, the run is SKIPPED (exit 3)" 3 "run-checks: SKIPPED - " "no project check runs here"

tsv "$r" "a<T>any<T>cmd:no-such-command-zz<T>$P<T>echo '1 passed'" \
  "b<T>any<T>env:RC_TEST_UNSET<T>$P<T>echo '1 passed'" \
  "c<T>any<T>env:RC_TEST_EMPTY<T>$P<T>echo '1 passed'" \
  "d<T>any<T>file:src/missing.txt<T>$P<T>echo '1 passed'" \
  "e<T>any<T>cmd:bash,env:RC_TEST_SET,file:src/a.txt<T>$P<T>echo '1 passed'"
run "$r" RC_TEST_EMPTY= RC_TEST_SET=x
expect "an unmet need skips the check and names the need (exit 3)" 3 \
  "a: SKIPPED - needs cmd:no-such-command-zz, which is not on PATH" "b: SKIPPED - needs env:RC_TEST_UNSET, which is not set" \
  "c: SKIPPED - needs env:RC_TEST_EMPTY, which is not set" "d: SKIPPED - needs file:src/missing.txt, which does not exist" \
  "passed: secrets fresh-clone e tree-unchanged"

tsv "$r" "$(ck zero "printf '12 passed\\n0 passed\\n'")" "$(ck zeros 'echo "000 passed"')" "$(ck seven 'echo "007 passed"')"
run "$r"
expect "a last count of 0 is SKIPPED examined-nothing, not a pass" 3 "zero: SKIPPED - it passed, but its count is 0" "zeros: SKIPPED - it passed, but its count is 0"
if [ "$(result zero)" = "SKIPPED${T}examined-nothing${T}any${T}0${T}it passed, but its count is 0, so it examined nothing (checks/main.tsv line 1)" ] \
  && [ "$(result seven | cut -f 1,4)" = "PASS${T}7" ]; then
  pass "the last matching line gives the count"
else
  fail "the last matching line gives the count" "$(grep '^RESULT' "$logf")"
fi
tsv "$r" "$(ck quiet 'echo all good')" "word<T>any<T>-<T>^result: (\\S+)<T>echo 'result: many'" "alt<T>any<T>-<T>([0-9]+) passed|failed<T>echo failed"
run "$r"
expect "a pass with no count, or a count that is not a number, is SKIPPED no-count" 3 \
  "quiet: SKIPPED - it passed, but no output line matched its count pattern" \
  "word: SKIPPED - it passed, but its count pattern caught something that is not a number" \
  "alt: SKIPPED - it passed, but its count pattern caught something that is not a number"

tsv "$r" "# no checks yet"
run "$r"
expect "an empty checks file is SKIPPED: the project's own tests were not run" 3 \
  "project-checks: SKIPPED - checks/*.tsv lists no checks, so the project's own tests were not run"
in_log "project-checks has a RESULT line" "RESULT${T}project-checks${T}SKIPPED${T}not-configured${T}-${T}-${T}"

# 2. how the count is read
# shellcheck disable=SC2016 # the check's own shell expands it
tsv "$r" "$(ck crlf "printf '4 passed\\r\\n'")" "$(ck lonecr "printf 'x\\r5 passed\\rdone\\n'")" \
  "$(ck colour "printf '\\033[1;32m6\\033[0m passed\\n'")" \
  "$(ck cionly 'if [ "${CI:-}" = true ]; then printf "\\033[32m7 passed\\033[0m\\n"; else echo "1 passed"; fi')"
run "$r" CI=true
counts=$(for id in crlf lonecr colour cionly; do result "$id" | cut -f 1,4; done | tr '\n' ' ')
if [ "$code" -eq 0 ] && [ "$counts" = "PASS${T}4 PASS${T}5 PASS${T}6 PASS${T}7 " ]; then
  pass "counts are read across CRLF, lone CR and colour codes"
else
  fail "counts are read across CRLF, lone CR and colour codes: $counts" "$out
$(grep '^RESULT' "$logf")"
fi

# 3. a bad checks file stops the run before anything runs
good="$(ck ok 'touch ran.marker; echo "1 passed"')"
tsv_bad() {
  name=$1
  reason=$2
  shift 2
  rm -rf "$r/.method" "$r/ran.marker"
  tsv "$r" "$good" "$@"
  run "$r"
  if [ "$code" -ne 2 ]; then
    fail "a checks file with $name exits 2: exit $code" "$out"
  elif [ -e "$r/ran.marker" ] || [ -e "$r/.method" ]; then
    fail "a checks file with $name runs nothing and writes no log" "$out"
  elif ! printf '%s\n' "$out" | grep -F -- "checks/main.tsv line 2: " | grep -F -q -- "$reason"; then
    fail "a checks file with $name names line 2 and '$reason'" "$out"
  elif [ "$last" != "run-checks: FAIL - checks/*.tsv has problems (above); no check was run; the run stopped" ]; then
    fail "a checks file with $name ends with the stop line" "$out"
  else
    pass "a checks file with $name exits 2, names the line and runs nothing"
  fi
}
tsv_bad "four fields" "expected 5 TAB-separated fields (id, runs_in, needs, count, command), found 4" "x<T>any<T>-<T>$P"
tsv_bad "six fields" "found 6" "x<T>any<T>-<T>$P<T>echo<T>more"
tsv_bad "spaces for TABs" "this line has none" "x any - (\\d+) echo"
tsv_bad "an id in capitals" "the id must be lower-case" "$(ck Unit 'echo')"
tsv_bad "a built-in check's id" "the id secrets is the name of a built-in check" "$(ck secrets 'echo')"
tsv_bad "an id used twice" "the id ok is already used at checks/main.tsv line 1" "$(ck ok 'echo')"
tsv_bad "an unknown runs_in" "runs_in must be any, ci or local" "x<T>always<T>-<T>$P<T>echo"
tsv_bad "an unknown need" "each need must be" "x<T>any<T>pkg:x<T>$P<T>echo"
tsv_bad "a bad command need" "a cmd: need names one command" "x<T>any<T>cmd:a;b<T>$P<T>echo"
tsv_bad "a bad variable need" "an env: need names one variable" "x<T>any<T>env:1X<T>$P<T>echo"
tsv_bad "a file need outside the repo" "a file: need is a relative path" "x<T>any<T>file:../x<T>$P<T>echo"
tsv_bad "a pattern that does not compile" "the count pattern does not compile" "x<T>any<T>-<T>(<T>echo"
tsv_bad "a pattern with code in it" "the count pattern does not compile" "x<T>any<T>-<T>(?{1})([0-9]+)<T>echo"
tsv_bad "a pattern without a capture group" "exactly one capture group" "x<T>any<T>-<T>passed<T>echo"
tsv_bad "a pattern with two capture groups" "exactly one capture group" "x<T>any<T>-<T>([0-9]+) ([0-9]+)<T>echo"
tsv_bad "a pattern that matches an empty line" "the count pattern matches an empty line" "x<T>any<T>-<T>([0-9]*)<T>echo"
tsv_bad "an empty command" "the command is empty" "x<T>any<T>-<T>$P<T> "
tsv_bad "a control character" "holds a control character" "$(ck x "echo $(printf '\001')")"

tsv "$r" "$(ck unit 'echo "3 passed"')" "bench<T>ci<T>cmd:bash<T>$P<T>echo '2 passed'"
run "$r"
lf_results=$(grep '^RESULT' "$logf")
printf 'unit\tany\t-\t%s\techo "3 passed"\r\nbench\tci\tcmd:bash\t%s\techo '"'"'2 passed'"'"'\r\n' "$P" "$P" >"$r/checks/main.tsv"
(cd "$r" && git add -A && git commit -q -m crlf)
run "$r"
if [ "$code" -eq 0 ] && [ "$(grep '^RESULT' "$logf")" = "$lf_results" ]; then
  pass "a checks file with CRLF line ends gives the same results"
else
  fail "a checks file with CRLF line ends gives the same results" "$out"
fi

# 4. config files a clone would lack, and bad settings
i=$(new_repo) || abort_sandbox
printf 'checks/extra.tsv\n' >"$i/.gitignore"
(cd "$i" && git add .gitignore && git commit -q -m ignore)
printf '%s\n' "$(ck extra 'echo "1 passed"')" | perl -pe 's/<T>/\t/g' >"$i/checks/extra.tsv"
run "$i"
expect "an ignored checks file stops the run" 2 "run-checks: checks/extra.tsv is ignored by git, so a clone would not have it; track it with git add -f"
rm -f "$i/checks/extra.tsv"
printf '.claude/method.conf\n' >"$i/.gitignore"
(cd "$i" && git rm -q --cached .claude/method.conf && git add .gitignore && git commit -q -m untrack)
run "$i"
expect "an ignored method.conf stops the run" 2 "run-checks: .claude/method.conf is ignored by git"
if [ ! -e "$i/.method" ]; then pass "a stopped run writes no log"; else fail "a stopped run writes no log"; fi
printf '' >"$i/.gitignore"
printf 'PRODUCT_PATHS=src\nPRODUCT_PATH=zq\n' >"$i/.claude/method.conf"
run "$i"
expect "a bad method.conf stops the run and names the line, not the value" 2 \
  "run-checks: .claude/method.conf line 2: unknown key PRODUCT_PATH" "run-checks: FAIL - .claude/method.conf has problems (above); fix them first; the run stopped"
case "$out" in *zq*) fail "the config problem quotes the value" "$out" ;; esac
printf 'PRODUCT_PATHS=src\n' >"$i/.claude/method.conf"
run "$i"
expect "with the problems fixed the run goes on" 3 "project-checks: SKIPPED"
(cd "$i" && bash "$rc" extra) >"$work/out" 2>&1
code=$?
out=$(cat "$work/out")
expect "any argument is bad usage" 2 "run-checks: usage: run-checks.sh (it takes no arguments)"
mkdir -p "$work/plain"
(cd "$work/plain" && GIT_CEILING_DIRECTORIES=$work bash "$rc") >"$work/out" 2>&1
code=$?
out=$(cat "$work/out")
expect "outside a git working tree the run stops" 2 "run-checks: FAIL - not inside a git working tree; the run stopped"
rm -rf "$i/.method"
mkdir -p "$work/elsewhere" "$i/.method"
ln -s "$work/elsewhere" "$i/.method/local"
run "$i"
if [ "$code" -eq 2 ] && [ -z "$(ls -A "$work/elsewhere")" ]; then
  pass "a .method/local that is a symbolic link stops the run and nothing is written through it"
else
  fail "a .method/local that is a symbolic link stops the run: exit $code" "$out"
fi
rm -rf "$i/.method"

# 5. the secrets check
sec=$(new_repo) || abort_sandbox
fake="sk-ant""-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef0123456789"
printf 'the key is %s here\n' "$fake" >"$sec/src/key.txt"
(cd "$sec" && git add -A && git commit -q -m key)
tsv "$sec" "$(ck unit 'echo "1 passed"')"
run "$sec"
expect "secrets fails on a planted key and shows its id and the way to accept it" 1 "secrets: FAIL - 1 finding(s) in " \
  "secrets: src/key.txt:1: Anthropic API key: sk-a...(" "[id " \
  "  to accept a false positive, add PATH<TAB>ID<TAB>a real reason to checks/scan-allow.txt"
if grep -F -q -- "$fake" "$logf" || printf '%s\n' "$out" | grep -F -q -- "$fake"; then
  fail "the key is never shown in full" "$out"
else
  pass "the key is never shown in full, on screen or in the log"
fi
id=$(printf '%s\n' "$out" | sed -n 's/.*\[id \([0-9a-f]\{12\}\)\].*/\1/p' | head -n 1)
printf 'src/key.txt\t%s\ta test fixture, not a real key\n' "$id" >"$sec/checks/scan-allow.txt"
(cd "$sec" && git add -A && git commit -q -m allow)
run "$sec"
expect "with its id in checks/scan-allow.txt the key is accepted" 0 "run-checks: PASS - 4 passed"
in_log "the accepted key is counted" "RESULT${T}secrets${T}PASS${T}pass${T}-${T}" "1 allowed"

# 6. fresh-clone
f=$(new_repo) || abort_sandbox
tsv "$f" "$(ck unit 'echo "1 passed"')"
printf '*.local\n__pycache__/\n*.cache\n.claude/settings.local.json\nCLAUDE.local.md\n' >"$f/.gitignore"
(cd "$f" && git add -A && git commit -q -m ignores)
printf 'x\n' >"$f/src/x.local"
printf 'x\n' >"$f/notes.local"
run "$f"
expect "fresh-clone fails on an ignored file under PRODUCT_PATHS" 1 \
  "fresh-clone: FAIL - 1 ignored files under PRODUCT_PATHS are here but not in a clone" "ignored by git, so not in a clone: src/x.local" \
  "add the name or path to LOCAL_ONLY in .claude/method.conf"
case "$out" in *notes.local*) fail "fresh-clone looks only under PRODUCT_PATHS" "$out" ;; *) pass "fresh-clone looks only under PRODUCT_PATHS" ;; esac
rm -f "$f/src/x.local"
mkdir -p "$f/src/p1/__pycache__" "$f/src/p2/__pycache__"
: >"$f/src/p1/__pycache__/a.pyc"
: >"$f/src/p2/__pycache__/b.pyc"
printf 'PRODUCT_PATHS=src\nLOCAL_ONLY=__pycache__\n' >"$f/.claude/method.conf"
(cd "$f" && git add -A && git commit -q -m local-only)
run "$f"
expect "a bare LOCAL_ONLY name sets aside the caches of two packages" 0 "run-checks: PASS - 4 passed"
in_log "fresh-clone says how many files LOCAL_ONLY set aside" "2 ignored files set aside by LOCAL_ONLY"
: >"$f/src/build.cache"
run "$f"
expect "a cache LOCAL_ONLY does not cover fails again" 1 "ignored by git, so not in a clone: src/build.cache"
rm -f "$f/src/build.cache"
mkdir -p "$f/sub/.claude"
: >"$f/.claude/settings.local.json"
: >"$f/sub/.claude/settings.local.json"
: >"$f/CLAUDE.local.md"
printf 'PRODUCT_PATHS=.\nLOCAL_ONLY=__pycache__\nLOCAL_ONLY=notes.local\n' >"$f/.claude/method.conf"
(cd "$f" && git add -A && git commit -q -m whole)
run "$f"
expect "with PRODUCT_PATHS=. old logs and Claude Code's per-machine files are not counted" 0 "run-checks: PASS - 4 passed"
printf 'PRODUCT_PATHS=src\nPRODUCT_PATHS=srcc\n' >"$f/.claude/method.conf"
run "$f"
expect "a PRODUCT_PATHS entry that matches no tracked file fails" 1 "1 PRODUCT_PATHS entries match no tracked file" \
  "a PRODUCT_PATHS entry that matches no tracked file: srcc"
printf '# nothing set\n' >"$f/.claude/method.conf"
run "$f"
expect "without PRODUCT_PATHS fresh-clone is SKIPPED (exit 3)" 3 "fresh-clone: SKIPPED - PRODUCT_PATHS is not set in .claude/method.conf"
(cd "$f" && git checkout -q .claude/method.conf)

# 7. tree-unchanged
t=$(new_repo) || abort_sandbox
tsv "$t" "$(ck edit 'echo more >>src/a.txt; echo "1 passed"')"
run "$t"
expect "a check that edits a tracked file fails tree-unchanged" 1 "tree-unchanged: FAIL - the checks changed 1 files" "changed during the run: src/a.txt"
(cd "$t" && git checkout -q src/a.txt)
tsv "$t" "$(ck commit 'git commit -q --allow-empty -m moved && echo "1 passed"')"
run "$t"
expect "a check that commits fails tree-unchanged" 1 "tree-unchanged: FAIL - HEAD moved during the run"
(cd "$t" && git reset -q --hard HEAD~1)
tsv "$t" "$(ck new 'echo hi >made.txt; echo "1 passed"')"
run "$t"
expect "a check that leaves a new file fails tree-unchanged" 1 "changed during the run: made.txt"
rm -f "$t/made.txt"
tsv "$t" "$(ck edit 'echo more >>src/a.txt; echo "1 passed"')"
echo dirty >>"$t/src/a.txt"
run "$t"
expect "a check that edits an already changed file fails tree-unchanged" 1 "changed during the run: src/a.txt" "on uncommitted changes"
(cd "$t" && git checkout -q src/a.txt)
tsv "$t" "$(ck unit 'echo "1 passed"')"
echo dirty >>"$t/src/a.txt"
run "$t"
expect "a run on uncommitted changes says so" 0 "run-checks: PASS - 4 passed; where local; on uncommitted changes"
in_log "the log says the tree had uncommitted changes" "tree at start uncommitted changes"
(cd "$t" && git checkout -q src/a.txt)

# 8. what a check leaves running, and the caller's perl settings
tsv "$t" "$(ck bg 'sleep 20 & echo "1 passed"')"
start=$(date +%s)
run "$t"
took=$(($(date +%s) - start))
if [ "$code" -eq 0 ] && [ "$took" -lt 10 ]; then
  pass "a process a check leaves running does not hold the run up (${took}s)"
else
  fail "a process a check leaves running does not hold the run up: exit $code after ${took}s" "$out"
fi
mkdir -p "$work/plib/Digest"
printf 'die "a module from PERL5LIB was loaded\\n";\n1;\n' >"$work/plib/Digest/SHA.pm"
tsv "$t" "$(ck perl5lib "[ \"\$PERL5LIB\" = '$work/plib' ] && echo '1 passed'")"
run "$t" PERL5LIB="$work/plib"
expect "the caller's PERL5LIB reaches a check but not the method's own perl" 0 "run-checks: PASS - 4 passed"

# 9. the log folder
g=$(new_repo) || abort_sandbox
tsv "$g" "$(ck unit 'echo "1 passed"')"
run "$g"
first_log=$logf # newer than the 25 planted below, so kept
if [ "$(cat "$g/.method/local/.gitignore")" = "*" ] && [ -z "$(cd "$g" && git status --porcelain)" ]; then
  pass "run-checks makes git ignore .method/local"
else
  fail "run-checks makes git ignore .method/local" "$(cd "$g" && git status --porcelain)"
fi
in_log "the log says it wrote the .gitignore" "note wrote .method/local/.gitignore"
printf '*\n# kept\n' >"$g/.method/local/.gitignore"
run "$g"
if [ "$(cat "$g/.method/local/.gitignore")" = "*
# kept" ] && ! grep -q '^note' "$logf"; then
  pass "an existing .gitignore that does the job is left alone"
else
  fail "an existing .gitignore that does the job is left alone" "$(cat "$logf")"
fi
h=$(new_repo) || abort_sandbox
mkdir -p "$h/.method/local"
printf '# mine\n' >"$h/.method/local/.gitignore"
run "$h"
if [ "$(cat "$h/.method/local/.gitignore")" = "# mine" ]; then pass "a .gitignore that does not ignore the folder is never overwritten"; else fail "a .gitignore is never overwritten"; fi
in_log "the log says the .gitignore was left as it is" "note .method/local/.gitignore exists but does not make git ignore the folder"
logs="$g/.method/local/logs"
n=1
while [ "$n" -le 25 ]; do
  : >"$logs/$(printf 'run-checks-20200101T0000%02dZ-%010d.log' "$n" "$n")"
  n=$((n + 1))
done
: >"$logs/run-checks-old.log"
: >"$logs/run-checks-20190101T000000Z-0000000001.log"
(cd "$g" && git add -f .method/local/logs/run-checks-20190101T000000Z-0000000001.log && git commit -q -m tracked-log)
run "$g"
left=0
for l in "$logs"/run-checks-[0-9]*Z-[0-9]*.log; do
  case "${l##*/}" in
    run-checks-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].log) left=$((left + 1)) ;;
  esac
done
if [ "$left" -eq 21 ] && [ -f "$logf" ] && [ -f "$logs/run-checks-old.log" ] && [ -f "$logs/run-checks-20190101T000000Z-0000000001.log" ] \
  && [ ! -f "$logs/run-checks-20200101T000001Z-0000000001.log" ] && [ -f "$first_log" ]; then
  pass "the newest 20 logs are kept; look-alikes and tracked files are never deleted"
else
  fail "the newest 20 logs are kept; look-alikes and tracked files are never deleted: $left left" "$(ls "$logs")"
fi

# 10. the screen
many=""
n=1
while [ "$n" -le 30 ]; do
  many="$many$(ck "check-number-$n-with-a-rather-long-name" 'echo "1 passed"')
"
  n=$((n + 1))
done
# shellcheck disable=SC2086 # one line per check
(IFS='
'
  tsv "$g" $many)
run "$g"
passed_lines=$(printf '%s\n' "$out" | grep -c -e '^passed:' -e '^       ')
longest=$(printf '%s\n' "$out" | awk '{ if (length($0) > m) m = length($0) } END { print m }')
if [ "$code" -eq 0 ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -le 15 ] && [ "$passed_lines" -le 3 ] && [ "$longest" -le 100 ] \
  && printf '%s\n' "$out" | grep -q ' more$'; then
  pass "a passing run of 30 checks prints a few short lines"
else
  fail "a passing run of 30 checks prints a few short lines" "$out"
fi
tsv "$g" "$(ck progress "perl -e '\$|=1; print \"step \$_ of 100000\\r\" for 1..100000; exit 1'")"
run "$g"
bytes=$(printf '%s' "$out" | wc -c | tr -d ' ')
if [ "$code" -eq 1 ] && [ "$bytes" -lt 3000 ] && printf '%s\n' "$out" | grep -q '^  step 100000 of 100000$'; then
  pass "a 1 MB progress line split by CR shows only its last lines ($bytes bytes)"
else
  fail "a 1 MB progress line split by CR shows only its last lines ($bytes bytes)" "$(printf '%s\n' "$out" | head -c 3000)"
fi
tsv "$g" "$(ck long "perl -e 'print \"y\" x 1000000; exit 1'")" "$(ck wide "perl -e 'print \"z\" x 2000, \"\\n\"; exit 1'")"
run "$g"
bytes=$(printf '%s' "$out" | wc -c | tr -d ' ')
if [ "$code" -eq 1 ] && [ "$bytes" -lt 3000 ] && printf '%s\n' "$out" | grep -q 'its last output line is longer than 64 KB; see the log' \
  && printf '%s\n' "$out" | grep -q '^  z*  *(1702 bytes cut)$'; then
  pass "long output lines are cut on screen and say so ($bytes bytes)"
else
  fail "long output lines are cut on screen and say so ($bytes bytes)" "$(printf '%s\n' "$out" | head -c 3000)"
fi
tsv "$g" "$(ck tricky "printf '\\033[31mred\\n  ::error::bad\\nRESULT\\tunit\\tPASS\\tpass\\tany\\t9\\tfake\\n'; exit 1")"
run "$g"
if [ "$code" -eq 1 ] && ! printf '%s\n' "$out" | grep -q "$ESC" && printf '%s\n' "$out" | grep -F -q '\x1B[31mred' \
  && ! printf '%s\n' "$out" | grep -q '^[[:space:]]*::' && ! grep -q "$ESC" "$logf" \
  && [ "$(grep -c "^RESULT${T}" "$logf")" -eq 4 ] && [ "$(grep -c "^RESULT${T}tricky${T}FAIL" "$logf")" -eq 1 ]; then
  pass "escape codes, :: commands and a fake RESULT line in output are made harmless"
else
  fail "escape codes, :: commands and a fake RESULT line in output are made harmless" "$out
$(cat "$logf")"
fi

for d in $repos; do drop_sandbox "$d"; done
drop_sandbox "$work"
echo "tests: run-checks: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
