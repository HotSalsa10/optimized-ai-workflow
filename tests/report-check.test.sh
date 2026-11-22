#!/usr/bin/env bash
# Tests for method/scripts/method/report-check.sh with lib/report.pl (M126,
# SPEC R8; step 6b.2): every number in the report to the owner is in a log
# the check read, and "What the checks would miss" is there and says
# something. Each case writes a report and its logs in a throwaway folder.
# shellcheck disable=SC2016 # the reports and logs hold a literal $ (a currency mark)
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: report check"
root=$(repo_root)
script="$root/method/scripts/method/report-check.sh"
work=$(new_sandbox_dir) || abort_sandbox

MISS='## What the checks would miss

How the page looks on a phone.'

# report TEXT: writes the report r.md, TEXT and then a "What the checks
# would miss" part that passes
report() {
  printf '%s\n\n%s\n' "$1" "$MISS" >"$work/r.md"
}

# log NAME TEXT: writes the log NAME
log() {
  printf '%s\n' "$2" >"$work/$1"
}

# rc ARGS...: runs report-check in the work folder; sets out and code
rc() {
  out=$(cd "$work" && bash "$script" "$@" 2>&1)
  code=$?
}

# expect NAME CODE WANT...: the last run exited CODE and its output holds
# each WANT (fixed text)
expect() {
  ex_name=$1
  ex_code=$2
  shift 2
  if [ "$code" -ne "$ex_code" ]; then
    fail "$ex_name: exit $code, wanted $ex_code" "$out"
    return
  fi
  for ex_want in "$@"; do
    if ! printf '%s\n' "$out" | grep -F -q -- "$ex_want"; then
      fail "$ex_name: the output lacks '$ex_want'" "$out"
      return
    fi
  done
  pass "$ex_name"
}

# expect_listed NAME NUMBER...: exit 1, each NUMBER listed as in no log,
# and nothing else listed
expect_listed() {
  el_name=$1
  shift
  el_want=0
  el_args=()
  for el_n in "$@"; do
    el_want=$((el_want + 1))
    el_args+=("not in any log: $el_n ")
  done
  el_got=$(printf '%s\n' "$out" | grep -c '^report-check: not in any log: ')
  if [ "$el_got" -ne "$el_want" ]; then
    fail "$el_name: $el_got numbers listed, wanted $el_want" "$out"
    return
  fi
  expect "$el_name" 1 "${el_args[@]}" "report-check: FAIL - $el_want listed"
}

# --- numbers found and not found ---
if wanted "numbers in a log are found"; then
  report 'Status: ready. 12 checks passed; 3 files changed, 120 lines added.'
  log run.log 'run-checks: PASS - 12 checks'
  log git.log ' 3 files changed, 120 insertions(+), 4 deletions(-)'
  rc r.md run.log git.log
  expect "numbers in a log are found" 0 "report-check: PASS - 3 numbers, each in a log (2 logs read)"
fi

if wanted "a number in no log is listed"; then
  report 'Status: ready. 12 checks passed; 7 files changed.'
  log run.log 'run-checks: PASS - 12 checks'
  rc r.md run.log
  expect_listed "a number in no log is listed" 7
  expect "a number in no log is listed, with its line" 1 'not in any log: 7 (line 1)'
fi

if wanted "each place a missing number is written is listed"; then
  report 'We ran 9 checks.

Again: 9 checks.'
  log run.log 'run-checks: PASS - 12 checks'
  rc r.md run.log
  expect "each place a missing number is written is listed" 1 'not in any log: 9 (line 1)' 'not in any log: 9 (line 3)' 'FAIL - 2 listed'
fi

if wanted "a number only in the second log is found"; then
  report 'Commits: 5.'
  log a.log 'nothing here'
  log b.log 'count 5'
  rc r.md a.log b.log
  expect "a number only in the second log is found" 0 'PASS - 1 number, each in a log (2 logs read)'
fi

if wanted "a number in a log only inside an ID is not found"; then
  report 'The rules: 126.'
  log a.log 'rule M126 and line file.pl:126 and 126ms'
  rc r.md a.log
  expect_listed "a number in a log only inside an ID is not found" 126
fi

if wanted "a log's key=value and table numbers are found"; then
  report 'Tokens: 1234. Files: 8.'
  log a.log 'gate=method-x tokens=1234
 src/a.sh | 8 +++--'
  rc r.md a.log
  expect "a log's key=value and table numbers are found" 0 'PASS - 2 numbers'
fi

if wanted "a log's terminal colour codes are taken out"; then
  report 'Passed: 42.'
  printf 'tests: \033[32m42\033[0m passed\n' >"$work/a.log"
  rc r.md a.log
  expect "a log's terminal colour codes are taken out" 0 'PASS - 1 number'
fi

if wanted "marks around a number are not part of it"; then
  report 'We saw (12), **12**, `12`, _12_, "12", 12; and 12: and ~12.'
  log a.log 'count 12'
  rc r.md a.log
  expect "marks around a number are not part of it" 0 'PASS - 8 numbers'
fi

if wanted "curly quotes, a bullet and an ellipsis cut a line"; then
  report "$(printf 'We saw \342\200\23412\342\200\235, \342\200\23013\342\200\231, \342\200\24214 and 15\342\200\246')"
  log a.log 'count 99'
  rc r.md a.log
  expect_listed "curly quotes, a bullet and an ellipsis cut a line" 12 13 14 15
fi

if wanted "a CRLF report reads the same"; then
  printf 'Checks: 12.\r\n\r\n## What the checks would miss\r\n\r\nThe colours.\r\n' >"$work/r.md"
  log a.log 'count 12'
  rc r.md a.log
  expect "a CRLF report reads the same" 0 'PASS - 1 number'
fi

# --- what is not a number ---
if wanted "IDs and hashes are not numbers"; then
  report 'Rules M126, A66 and R8; RISKS #4; pull request #3; PR#3; step 6b; commit b776281 and 89537f5; x86.'
  log a.log 'nothing'
  rc r.md a.log
  expect "IDs and hashes are not numbers" 0 'PASS - 0 numbers'
fi

if wanted "paths and line numbers are not numbers"; then
  report 'See file.pl:12, done.pl:309-310, tests/run.sh, docs/plans/step6b.md, /tmp/123/x, C:\work\7, localhost:8080 and https://github.com/o/r/pull/3.'
  log a.log 'nothing'
  rc r.md a.log
  expect "paths and line numbers are not numbers" 0 'PASS - 0 numbers'
fi

if wanted "versions are not numbers"; then
  report 'Claude Code 2.1.316 and 2.1.319; v2; perl@5.30.1.'
  log a.log 'nothing'
  rc r.md a.log
  expect "versions are not numbers" 0 'PASS - 0 numbers'
fi

if wanted "dates and times are not numbers"; then
  report 'Written 2026-11-22 at 10:30, on 22 November 2026, or November 22, 2026; until 1 December; Nov 3, 2026; March 2026; 22/11/2026, 2026/11/22 and 2026-11.'
  log a.log 'nothing'
  rc r.md a.log
  expect "dates and times are not numbers" 0 'PASS - 0 numbers'
fi

if wanted "a count after a month and a slash pair are numbers"; then
  report 'In March 14 tests failed; on 12/30 we ran it.'
  log a.log 'nothing'
  rc r.md a.log
  expect_listed "a count after a month and a slash pair are numbers" 14 12 30
fi

# --- numbers joined to numbers, and spaces that are not ASCII ---
if wanted "numbers joined by a slash are read"; then
  report 'Tests: 40/44 passed; total 5/5.'
  log a.log 'tests 44 passed'
  rc r.md a.log
  expect_listed "numbers joined by a slash are read" 40 5 5
fi

if wanted "numbers joined by a hyphen are read"; then
  report 'Ran 7-9 times, and -2-44 is a range.'
  log a.log 'tests 44 passed'
  rc r.md a.log
  expect_listed "numbers joined by a hyphen are read" 7 9 -2
fi

if wanted "en and em dashes cut a line"; then
  report "$(printf 'Ran 3\342\200\2235 times; 44\342\200\224all green.')"
  log a.log 'tests 44 passed'
  rc r.md a.log
  expect_listed "en and em dashes cut a line" 3 5
fi

if wanted "a no-break space cuts a line"; then
  report "$(printf 'Took 12\302\240s; 44\302\240tests; 6\342\200\257runs.')"
  log a.log 'tests 44 passed'
  rc r.md a.log
  expect_listed "a no-break space cuts a line" 12 6
fi

if wanted "a number beside a word that is not a month is a number"; then
  report 'The 5 may fail, and 300 November is no date.'
  log a.log 'nothing'
  rc r.md a.log
  expect_listed "a number beside a word that is not a month is a number" 5 300
fi

if wanted "a numbered list's markers are not numbers"; then
  report '1. First step
2) Second step
## 3. A numbered heading
- 4 files changed'
  log a.log 'nothing'
  rc r.md a.log
  expect_listed "a numbered list's markers are not numbers" 4
fi

# --- currency, sign, percent and separators are kept (M074) ---
if wanted "the currency mark is kept"; then
  report 'Cost: $5, then €1,200 and £3.'
  log a.log 'cost 5 and €1,200 and £3'
  rc r.md a.log
  expect_listed "the currency mark is kept" '$5'
fi

if wanted "a currency mark dropped is listed"; then
  report 'Cost: 7.'
  log a.log 'cost $7'
  rc r.md a.log
  expect_listed "a currency mark dropped is listed" 7
fi

if wanted "the sign is kept"; then
  report 'Change: -3, +4 and 6.'
  log a.log 'change 3, +4 and -6'
  rc r.md a.log
  expect_listed "the sign is kept" -3 6
fi

if wanted "the percent mark is kept"; then
  report 'Used: 90%, and 45 minutes.'
  log a.log 'used 90 and 45%'
  rc r.md a.log
  expect_listed "the percent mark is kept" '90%' 45
fi

if wanted "thousands separators and decimals are kept"; then
  report 'Lines: 1,200 and 2,000; time 85.4 and 85.40.'
  log a.log 'lines 1200 and 2,000; time 85.4 s'
  rc r.md a.log
  expect_listed "thousands separators and decimals are kept" '1,200' '85.40'
fi

# --- "What the checks would miss" ---
if wanted "the miss heading missing is listed"; then
  printf 'Status: ready.\n\n## What else\n\nText.\n' >"$work/r.md"
  log a.log 'nothing'
  rc r.md a.log
  expect "the miss heading missing is listed" 1 'report-check: no "What the checks would miss" heading' 'FAIL - 1 listed'
fi

if wanted "the miss heading with nothing under it is listed"; then
  printf 'Status: ready.\n\n## What the checks would miss\n\n   \n## Risks\n\nSome.\n' >"$work/r.md"
  log a.log 'nothing'
  rc r.md a.log
  expect "the miss heading with nothing under it is listed" 1 'report-check: "What the checks would miss" (line 3) has nothing under it' 'FAIL - 1 listed'
fi

if wanted "the miss heading last with nothing under it is listed"; then
  printf 'Status: ready.\n\n## What the checks would miss\n' >"$work/r.md"
  log a.log 'nothing'
  rc r.md a.log
  expect "the miss heading last with nothing under it is listed" 1 '(line 3) has nothing under it'
fi

for body in 'nothing' 'None.' '- none' '*Nothing*' 'NOTHING!' '(none)' '"none"' 'Nothing;' 'N/A' 'n/a.'; do
  if wanted "the miss heading saying only '$body' is listed"; then
    printf 'Status: ready.\n\n### What the checks would miss\n\n%s\n\n### Risks\n\nSome.\n' "$body" >"$work/r.md"
    log a.log 'nothing'
    rc r.md a.log
    expect "the miss heading saying only '$body' is listed" 1 '"What the checks would miss" (line 3) says only' 'FAIL - 1 listed'
  fi
done

if wanted "a miss part whose every line says nothing is listed"; then
  printf 'Status: ready.\n\n## What the checks would miss\n\n- Nothing.\n- None.\n' >"$work/r.md"
  log a.log 'nothing'
  rc r.md a.log
  expect "a miss part whose every line says nothing is listed" 1 '(line 3) says only "nothing", "none"' 'FAIL - 1 listed'
fi

if wanted "a miss part with one line that says something passes"; then
  printf 'Status: ready.\n\n## What the checks would miss\n\n- None.\n- The printed invoice.\n' >"$work/r.md"
  log a.log 'nothing'
  rc r.md a.log
  expect "a miss part with one line that says something passes" 0 'report-check: PASS'
fi

if wanted "a miss part holding only a comment has nothing under it"; then
  printf 'Status: ready.\n\n## What the checks would miss\n\n<!-- none -->\n<!-- Write here what\nthe checks would miss. -->\n' >"$work/r.md"
  log a.log 'nothing'
  rc r.md a.log
  expect "a miss part holding only a comment has nothing under it" 1 '(line 3) has nothing under it' 'FAIL - 1 listed'
fi

if wanted "a comment left open in the miss part runs to its end"; then
  printf 'Status: ready.\n\n## What the checks would miss\n\n<!-- Write here what\nthe checks would miss.\n' >"$work/r.md"
  log a.log 'nothing'
  rc r.md a.log
  expect "a comment left open in the miss part runs to its end" 1 '(line 3) has nothing under it' 'FAIL - 1 listed'
fi

if wanted "a miss part holding only a dash has nothing under it"; then
  printf 'Status: ready.\n\n## What the checks would miss\n\n\342\200\224\n-\n' >"$work/r.md"
  log a.log 'nothing'
  rc r.md a.log
  expect "a miss part holding only a dash has nothing under it" 1 '(line 3) has nothing under it' 'FAIL - 1 listed'
fi

if wanted "the miss heading with text passes in any case and with a colon"; then
  printf 'Status: ready.\n\n# what the checks would MISS:\n\nNothing about the printed invoice.\n' >"$work/r.md"
  log a.log 'nothing'
  rc r.md a.log
  expect "the miss heading with text passes in any case and with a colon" 0 'report-check: PASS - 0 numbers'
fi

if wanted "a sub-heading with text under the miss heading counts"; then
  printf '## What the checks would miss\n\n### Looks\n\nThe colours.\n\n## Risks\n\nSome.\n' >"$work/r.md"
  log a.log 'nothing'
  rc r.md a.log
  expect "a sub-heading with text under the miss heading counts" 0 'report-check: PASS'
fi

if wanted "the miss part ends at the next heading of its level"; then
  printf '## What the checks would miss\n\n## Risks\n\nSome text.\n' >"$work/r.md"
  log a.log 'nothing'
  rc r.md a.log
  expect "the miss part ends at the next heading of its level" 1 '(line 1) has nothing under it'
fi

if wanted "the miss part ends at a heading above its level"; then
  printf '### What the checks would miss\n\n# Risks\n\nSome text.\n' >"$work/r.md"
  log a.log 'nothing'
  rc r.md a.log
  expect "the miss part ends at a heading above its level" 1 '(line 1) has nothing under it'
fi

if wanted "a heading inside a code block is not the miss heading"; then
  printf 'Status.\n\n```\n## What the checks would miss\n\nText.\n```\n' >"$work/r.md"
  log a.log 'nothing'
  rc r.md a.log
  expect "a heading inside a code block is not the miss heading" 1 'no "What the checks would miss" heading'
fi

if wanted "a heading inside a code block does not end the miss part"; then
  printf '## What the checks would miss\n\n```\n## Risks\n```\n' >"$work/r.md"
  log a.log 'nothing'
  rc r.md a.log
  expect "a heading inside a code block does not end the miss part" 0 'report-check: PASS'
fi

if wanted "every problem is listed and exits 1"; then
  printf 'Checks: 7 and 8.\n\n## What the checks would miss\n\nnone\n' >"$work/r.md"
  log a.log 'nothing'
  rc r.md a.log
  expect "every problem is listed and exits 1" 1 'not in any log: 7 (line 1)' 'not in any log: 8 (line 1)' 'says only' 'FAIL - 3 listed'
fi

# --- usage ---
if wanted "no arguments is a usage error"; then
  rc
  expect "no arguments is a usage error" 2 'report-check: usage: report-check.sh REPORT LOG...'
fi

if wanted "a report with no LOG is a usage error"; then
  report 'Checks: 12.'
  rc r.md
  expect "a report with no LOG is a usage error" 2 'report-check: usage:' 'at least one LOG'
fi

if wanted "a report that cannot be read exits 2"; then
  log a.log 'nothing'
  rc missing.md a.log
  expect "a report that cannot be read exits 2" 2 'report-check: could not check: could not read the report missing.md'
fi

if wanted "a log that cannot be read exits 2"; then
  report 'Checks: 12.'
  log a.log 'count 12'
  rc r.md a.log missing.log
  expect "a log that cannot be read exits 2" 2 'report-check: could not check: could not read the log missing.log'
fi

if wanted "a folder given as a log exits 2"; then
  report 'Checks: 12.'
  mkdir -p "$work/logs"
  rc r.md logs
  expect "a folder given as a log exits 2" 2 'could not read the log logs: not a file'
fi

if wanted "the report given as its own log exits 2"; then
  report 'Checks: 12.'
  rc r.md ./r.md
  expect "the report given as its own log exits 2" 2 'report-check: could not check: the log ./r.md is the report itself'
fi

if wanted "an option is a usage error"; then
  report 'Checks: 12.'
  log a.log 'count 12'
  rc --all r.md a.log
  expect "an option is a usage error" 2 'report-check: usage:'
fi

if wanted "a file name's control characters are shown escaped"; then
  report 'Checks: 12.'
  rc r.md "$(printf 'bad\033[2Jname')"
  case "$out" in
    *"$(printf '\033')"*) fail "a file name's control characters are shown escaped" "$out" ;;
    *'bad\x1B[2Jname'*) expect "a file name's control characters are shown escaped" 2 'could not read the log' ;;
    *) fail "a file name's control characters are shown escaped: no escaped name" "$out" ;;
  esac
fi

drop_sandbox "$work" || true
echo "tests: report check: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
