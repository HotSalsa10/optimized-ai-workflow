#!/usr/bin/env bash
# Answers "is this change ready to merge?" from the commit, the files on
# disk, main, the run-checks log and the head commit's verdict line, so the
# owner does not have to read test output. The work is done by lib/done.pl.
# Read-only: it writes no file.
#
# Usage: bash scripts/method/done-check.sh --ready
#
# Until CI runs the checks (step 9) and review receipts replace the verdict
# line (step 5), the log and the verdict line are local claims written in
# this session: READY means the local records agree, not proof (RISKS #11).
#
# One line per condition, "done-check: <area>: PASS|FAIL - <detail>", in the
# order a change is finished (files, main, the checks, the review):
#   files          the files on disk are HEAD's commit and nothing untracked
#                  is outside git's ignore rules: run-checks' fingerprint,
#                  the one definition of a clean tree (lib/checks.pl). A CRLF
#                  or an $Id$ that git's checkout writes from the commit's
#                  own .gitattributes is the commit's; one that only this
#                  machine's settings explain is a change (lib/tree.pl).
#   up to date     main's tip is in this branch (M108), as of the last
#                  fetch; done-check never fetches. Main is lib/git.pl's
#                  Git::main_ref; there is no --base. A shallow history that
#                  cannot tell says so instead of "merge main".
#   checks         the newest run-checks log of these files from this place
#                  (CI when CI=true, else local) passed: its last line PASS,
#                  END exit 0, the tree clean at its start, no FAIL, no
#                  SKIPPED other than not-here. A log counts for HEAD when
#                  its commit is HEAD, or has HEAD's files and parents (HEAD
#                  amended to add the verdict line), or has HEAD's files and
#                  is an ancestor (an empty verdict commit on top). A newest
#                  log without END fails. Earlier runs of the same files
#                  that failed are named, and the READY line carries them.
#   elsewhere      every check in checks/*.tsv runs here: a check that runs
#                  only in the other place has no result done-check can read
#                  yet (step 9), so it never counts toward READY (M089)
#   verdict        the head commit ends with a valid verdict line whose value
#                  lets a change merge: verdicts.txt's ready kind (M008,
#                  SPEC R4); the line is typed by the author until receipts
#   verdicts start what the change makes status stop judging: VERDICTS_FROM
#                  in the committed .claude/method.conf on main and at HEAD.
#                  The same value passes; a move passes, naming any commit
#                  on main without a valid verdict line that it accepts
#                  (DECISIONS A30), when the branch is up to date and the
#                  history needed is here.
# Then, when one failed, "done-check: next: <what to do for the first one>",
# and a last line that names HEAD and main by full commit id:
#   done-check: READY - ...            every condition passed
#   done-check: NOT READY - ...        a condition failed, or could not be checked
#   done-check: NOTHING TO MERGE - ... HEAD is main's tip or behind it
# Every condition needs positive evidence (M089): no log, no main, no
# verdict line, or a condition that could not be checked is a FAIL.
#
# Exit codes: 0 ready; 1 not ready; 2 bad usage, not inside a git working
# tree, a working folder git finds elsewhere, perl or Digest::SHA missing,
# or a git or file error (the last line says NOT READY - could not check);
# 3 nothing to merge. Only 0 is ready, for any caller.
#
# Rules it serves:
# - M008: the verdict comes before the merge.
# - M089: "no findings" never counts as a pass on its own.
# - M108: a branch must be up to date with main before it merges.
set -u
# perl reads bytes; these settings would change how it reads and writes
# them, and the library paths would let modules from elsewhere run inside it
unset PERL_UNICODE PERL5OPT PERL5LIB PERLLIB PERL_USE_UNSAFE_INC PERLIO

command -v perl >/dev/null 2>&1 || {
  echo "done-check: NOT READY - could not check: perl is not installed"
  exit 2
}
# only bash, git and perl are needed, so no dirname
case "$0" in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
perl "$here/lib/done.pl" "$@"
st=$?
case $st in
  0 | 1 | 2 | 3) exit "$st" ;;
esac
# perl itself stopped (a file of the method that does not compile, a
# signal), so nothing was checked
echo "done-check: NOT READY - could not check: perl stopped with exit $st"
exit 2
