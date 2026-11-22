#!/usr/bin/env bash
# Answers "is this change ready to merge?" from the commit, the files on
# disk, main, the run-checks log, the task's plan, the gates' receipts and
# the head commit's verdict line, so the owner does not have to read test
# output. The work is done by lib/done.pl. Read-only: it writes no file.
#
# Usage: bash scripts/method/done-check.sh --ready
#
# Until CI runs the checks (step 9), the log and the receipts are local
# records written in this clone: READY means the local records agree, not
# proof (RISKS #11). A program Claude writes and runs could forge a receipt
# or the plan's Approved line (RISKS #2); the owner's merge stays the lock.
#
# One line per condition, "done-check: <area>: PASS|FAIL - <detail>", in the
# order a change is finished (files, main, the checks, the plan, the review):
#   files          the files on disk are HEAD's commit and nothing untracked
#                  is outside git's ignore rules: run-checks' fingerprint,
#                  the one definition of a clean tree (lib/checks.pl). A CRLF
#                  or an $Id$ that git's checkout writes from the commit's
#                  own .gitattributes is the commit's; one that only this
#                  machine's settings explain is a change (lib/tree.pl).
#   up to date     main's tip is in this branch (M108), as of the last
#                  fetch; done-check never fetches. Main is lib/git.pl's
#                  Git::main_ref (origin's, or the only remote's with a URL,
#                  at a ref git fetch moves; a local main only when there
#                  is no remote and no remote-tracking branch); no --base. A shallow history that
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
#   plan           the branch adds exactly one task plan,
#                  docs/tasks/<id>/plan.md (not on main at the merge base),
#                  a regular file in a plain folder (a symbolic link or a
#                  submodule there fails),
#                  whose Tier line is Tier: FULL or Tier: LIGHT and whose one
#                  Approved line is Approved: <YYYY-MM-DD> "<the owner's
#                  reply>", the reply holding the ready word and the task's
#                  id (M144). The anchor is the first commit on the branch
#                  whose plan carries that exact line; every Approved line
#                  the branch has had is named.
#   reviewer       the reviewer gate's receipts for HEAD's tree (lib/
#   security checker  receipt-read.pl; the gates by role, verdicts.txt):
#                  one is valid, opened with the approving word, and one of
#                  its bases (the review packets it read) is the merge base
#                  with main, or a commit between the merge base and HEAD
#                  whose tree has a valid receipt of the same gate whose
#                  base chains back the same way (a packet built with
#                  --since). Any receipt of the gate for HEAD's tree that
#                  opened with another word fails it, whatever its state; a
#                  receipt with no word neither fails nor counts (M146).
#   rounds         at most three trees have a valid reviewer receipt since
#                  the plan's approval: the trees of the commits from the
#                  anchor on, and any other reviewed tree whose plan holds
#                  the same Approved line, so a squash or a rebase keeps the
#                  rounds; a fourth means plan again (M009). A reviewed tree
#                  this clone cannot read is not counted, and is named
#   verdict        the head commit ends with a valid verdict line, and its
#                  value is the one the receipts give: verdicts.txt's ready
#                  word when the plan, both reviews and the rounds passed;
#                  otherwise no value lets the change merge (M008, SPEC R4).
#                  When the receipts give it and the line is missing or
#                  other, next: names the exact line to add.
#   verdicts start what the change makes status stop judging: VERDICTS_FROM
#                  in the committed .claude/method.conf on main and at HEAD,
#                  which must equal the file on disk that status reads.
#                  The same value passes; a move passes, naming any commit
#                  on main without a valid verdict line that it accepts
#                  (DECISIONS A30), when the branch is up to date and the
#                  history needed is here.
# Then "done-check: history - ..." lists every gate's word on the branch's
# versions, in commit order (each version's receipts by the time they
# stopped; one with no stop time is left out); then, when a condition
# failed, "done-check: next: <what to do for the first one>", and a last
# line that names HEAD and main by full commit id:
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
# - M009: after three review rounds, plan again.
# - M089: "no findings" never counts as a pass on its own.
# - M108: a branch must be up to date with main before it merges.
# - M144: a change is ready only when its task's plan carries a quoted
#   approval naming the task.
# - M146 (in part; the tester, the reporter and the high-risk reviews come
#   with step 6b.3): approving receipts for the exact files, reviewed from
#   the merge base; no other word from those gates on those files; the
#   verdict line says what they say.
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
if [ ! -f "$here/lib/done.pl" ]; then
  echo "done-check: NOT READY - could not check: lib/done.pl is not next to done-check.sh"
  exit 2
fi
perl "$here/lib/done.pl" "$@"
st=$?
case $st in
  0 | 1 | 2 | 3) exit "$st" ;;
esac
# perl itself stopped (a file of the method that does not compile, a
# signal), so nothing was checked
echo "done-check: NOT READY - could not check: perl stopped with exit $st"
exit 2
