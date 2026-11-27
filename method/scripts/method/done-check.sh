#!/usr/bin/env bash
# Answers "is this change ready to merge?" from the commit, the files on
# disk, main, the run-checks log, the task's plan, the gates' receipts and
# the head commit's verdict line, so the owner does not have to read test
# output. The work is done by lib/done.pl. Read-only: it writes no file.
#
# Usage: bash scripts/method/done-check.sh --ready
#
# done-check reads no CI result, so the log and the receipts are local
# records written in this clone: READY means the local records agree, not
# proof (RISKS #11). A program Claude writes and runs could forge a receipt
# or the plan's Approved line (RISKS #2); the owner's merge stays the lock.
#
# One line per condition, "done-check: <area>: PASS|FAIL - <detail>", in the
# order a change is finished (files, main, the checks, the plan, the tests,
# the review, the report):
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
#                  only in the other place has no result done-check reads,
#                  so it never counts toward READY (M089)
#   plan           the branch adds exactly one task plan,
#                  docs/tasks/<id>/plan.md (not on main at the merge base),
#                  a regular file in a plain folder (a symbolic link or a
#                  submodule there fails),
#                  whose Tier line is Tier: FULL or Tier: LIGHT and whose one
#                  Approved line is Approved: <YYYY-MM-DD> <HH:MM> "<the
#                  owner's reply>" (the time, on a 24-hour clock, may be
#                  left out), the reply holding the ready word and the
#                  task's id (M144). The anchor is the first commit on the
#                  branch whose plan carries that exact line (the same line
#                  removed and added back keeps it; a new approval with its
#                  time is a new line); every Approved line the branch has
#                  had is named.
#   tier           the high-risk list is HIGH_RISK_PATHS in the committed
#                  .claude/method.conf on main's tip and at HEAD together (a
#                  branch can add a path, never remove one); a file that
#                  cannot be read as stored (a submodule, Git LFS, a filter)
#                  or a problem of that key or of a line tied to no key (a
#                  misspelt key, a spaced =) fails it, on either side, so a
#                  broken setting never reads as a shorter list. A path the
#                  change touches from the merge base (a moved file at its
#                  old path too) that is a listed path or under one makes
#                  the change high-risk; a plan that says LIGHT is then
#                  judged FULL and fails (M147). An entry, on main's list or
#                  the change's, that names no path in its files or among
#                  the paths it touches (a misspelt or deleted path, a
#                  comment on the line) fails it, unless it is on main's
#                  list, is a plain path (no space, no #) and an earlier
#                  commit of main had it: that path a merged change deleted
#                  fails nothing, and the tier line says to drop it from
#                  main's list. A touched path on the built-in list of the
#                  files that steer the method (Conf::steers in lib/conf.pl,
#                  M153) is high-risk too; that list is added after the
#                  check above, so a path on it that is absent is no
#                  problem.
#   lock           HEAD's Tier and Paths lines and expected.tsv (next to the
#                  plan) are the anchor's; a FULL task had expected.tsv at
#                  the anchor; expected.tsv, where it is, is a regular file
#                  at the anchor and at HEAD (a symbolic link, a submodule
#                  or a folder there fails) (M145)
#   failing run    (FULL) a valid receipt of the tester that opened with the
#                  fail word, on a commit the anchor is an ancestor of and
#                  that is a strict ancestor of HEAD, with a tree other than
#                  HEAD's, and the lock's lines and a regular expected.tsv
#                  there as at the anchor (M145)
#   passing run    (FULL) the newest receipt of the tester for HEAD's tree,
#                  by its stop time, is valid with the pass word (M145)
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
#   deep review    (a high-risk change) three valid receipts of the reviewer
#                  for HEAD's tree opened with the approving word, each with
#                  a base that chains as above, and none with another word
#                  (M146, Deep review)
#   rounds         at most three trees have a valid reviewer receipt since
#                  the plan's approval: the trees of the anchor and of the
#                  branch's commits it is an ancestor of (by git ancestry,
#                  so a side line made before the approval and merged after
#                  it is not counted), and any other reviewed tree whose
#                  plan holds the same Approved line, so a squash or a
#                  rebase keeps the rounds; a fourth means plan again
#                  (M009). A reviewed tree this clone cannot read is not
#                  counted, and is named
#   reporter       (FULL) the newest receipt of the reporter for HEAD's
#                  tree, by its stop time, is valid with the approving word
#                  (M146)
#   verdict        the head commit ends with a valid verdict line, and its
#                  value is the one the receipts give: verdicts.txt's ready
#                  word when the plan, both reviews, the rounds and every
#                  condition of the SPEC R6 set that applies (tier, lock,
#                  failing run, passing run, deep review, reporter) passed;
#                  otherwise no value lets the change merge (M008). Files,
#                  up to date, checks and elsewhere fail on their own lines
#                  and do not change it.
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
# a git or file error, or started by a bare name not from its own folder
# or not as a file of its own (M163) (the last line says NOT READY - could
# not check);
# 3 nothing to merge. Only 0 is ready, for any caller.
#
# Rules it serves:
# - M008: the verdict comes before the merge.
# - M009: after three review rounds, plan again.
# - M089: "no findings" never counts as a pass on its own.
# - M108: a branch must be up to date with main before it merges.
# - M144: a change is ready only when its task's plan carries a quoted
#   approval naming the task.
# - M145: expected results, tier and paths are locked at the plan's
#   approval; a test run is seen failing after approval and before the
#   code, and passing at the end.
# - M146: approving receipts for the exact files, reviewed from the merge
#   base: the reviewer and the security checker always, the tester and the
#   reporter for FULL, three reviewers on high-risk paths; no other word
#   from the reviewer or the security checker on those files, and the
#   newest word of the tester and the reporter; the verdict line says what
#   they say.
# - M147: LIGHT only when the plan says so and the change touches no
#   high-risk path, as main or the branch lists them.
# - M153 (its list in lib/conf.pl): the files that steer the method are
#   high-risk whatever HIGH_RISK_PATHS says.
set -u
# perl reads bytes; these settings would change how it reads and writes
# them, and the library paths would let modules from elsewhere run inside it
unset PERL_UNICODE PERL5OPT PERL5LIB PERLLIB PERL_USE_UNSAFE_INC PERLIO

command -v perl >/dev/null 2>&1 || {
  echo "done-check: NOT READY - could not check: perl is not installed"
  exit 2
}
# only bash, git and perl are needed, so no dirname. Started by a bare
# name (bash done-check.sh), bash runs ./done-check.sh when there is one and
# otherwise the first one on PATH, $0 bare either way. Found on PATH, the
# current folder is not this script's, and its lib/ could be the judged
# project's own; so the current folder counts only when $0 and the file
# bash opened (BASH_SOURCE, a full path when bash found it on PATH) are
# both this script's own name and ./done-check.sh is a file. Any other $0
# with no / (a name found on PATH, a sourced or piped script, a $0 the
# caller chose, a path written with backslashes) is refused, and the line
# does not repeat $0 (M163; step 8.3, docs/plans/step8.md S8)
# (bash's BASH_SOURCE, read through eval only under bash, so a shell
# without arrays still parses this file and is refused below)
self_src=
[ -z "${BASH_VERSION-}" ] || eval 'self_src=${BASH_SOURCE[0]-}'
self_ok=
case "$0" in
  */*)
    # (a $0 with a / counts only under bash, when it is the file bash opened:
    # sourced from a script elsewhere, $0 is that script's path; another
    # shell cannot tell, so it is refused)
    if [ -n "${BASH_VERSION-}" ] && [ "$self_src" = "$0" ]; then
      here=${0%/*}
      self_ok=1
    fi
    ;;
  *)
    if [ "$0" = done-check.sh ] && [ "$self_src" = done-check.sh ] && [ -f ./done-check.sh ]; then
      here=.
      self_ok=1
    fi
    ;;
esac
if [ -z "$self_ok" ]; then
  printf '%s\n' "done-check: NOT READY - could not check: done-check.sh was started by a bare name found on PATH, or not as a file of its own; run it by its path, such as bash path/to/done-check.sh"
  exit 2
fi
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
