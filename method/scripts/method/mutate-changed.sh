#!/usr/bin/env bash
# Breaks the code under test on purpose (M044): each changed line gets a
# small text change (a mutant), the project's fast checks run against it,
# and the line is put back. A mutant the checks do not notice survives: the
# tests would not notice that mistake either. The work is done by
# lib/mutate.pl. A kill counts only when the checks pass twice without a
# mutant (runs A and B: one that fails stops the run, exit 2, and one
# SKIPPED in run A is not used), pass when only a line end is added at the
# end of the files that get a mutant (the control run: one that does not is
# not used), and still pass after the last mutant (run C: else exit 2). The
# control run writes through the same write function and journal as a
# mutant, naming each file in the journal just before it writes it, so a
# file it did not write is never put back; an edit made on top of its line
# end is left as it is, and the line says that line end may still be there.
#
# Usage: bash scripts/method/mutate-changed.sh [--list | --recover] [--max N] [--minutes N]
#   (none)       run: runs A and B (each check twice, with no mutant), the
#                control run, one mutant at a time, then run C
#   --list       print the plan: one line per mutant, nothing written, no
#                check run
#   --recover    put back what a run that was cut off left on disk, and
#                nothing else
#   --max N      at most N mutants (default 100)
#   --minutes N  stop starting mutants once one more, and run C after it,
#                might not end within N minutes of the start (default 8; 1
#                to 600); runs B and C and the control run must fit before
#                the first, so with the checks' time limits, less than 3
#                never runs one (the line says how long they can take). A
#                foreground tool call allows 10 minutes: for longer runs,
#                raise its limit or run in the background.
#
# A run writes into the working tree with your rights. It holds the lock it
# shares with run-checks.sh (lib/runstate.pl, in git's own folder), so the
# two never run at once: while another holds it, it waits 5 s, then stops
# with "FAIL - busy: ..." (exit 2). Each mutant goes in through one write
# function (a temp file next to the file, synced, given the file's mode, and
# renamed over it, only while the file still holds what this run last left
# there: an edit made during the run stops it, exit 2, and is kept; when
# that stops a mutant's write, nothing was written, and no journal is left;
# its time is the next whole second, or one past the file's own, so it is
# later than anything written before, also at the sub-second times make
# compares, and a cache keyed on the time in seconds and the size never
# takes one version for another; a file can be up to about 3 s ahead of the
# clock, which make may warn about), with a journal in git's own folder that
# names it, and where it is (line, column and change), until it is put back.
# Do not edit files while a run is going. Each check runs in its own process
# group under a watchdog that stops the group when the run ends in any way,
# kill -9 included, and within a time limit of 3 times its run A time plus
# 30 s; a check that runs out of time has killed the mutant. After each
# mutant: the check's group is stopped, the file put back, and the journal
# removed once the mutant is nowhere git keeps it (HEAD, the index, a stash
# made during the run and its index part, an autostash a merge left: each is
# looked at for the mutant's line, alone and with the lines around it, so an
# edit made on top of it does not hide it, and where that cannot tell (a
# copy of the line whose lines around it are not the original's), the
# journal stays; the journal keeps their SHA-256s, never their text) and no
# merge, rebase or other git operation is in progress (its autostash can
# hold it, also when a check started it); a git command that fails there, or
# ends on a signal, keeps the journal too. A journal a check removed or
# changed is written again first; when it cannot be, the files are put back
# all the same, and the line says no journal names them and where the
# mutant may be. Every file a journal names is tried, here and in recovery:
# one that cannot be put back does not keep the others from it (the line
# names 10 refusals, then how many more). Then the files, HEAD, the
# branches and tags, and the stash must be
# as at the start (else exit 2, naming what changed). On INT, TERM, HUP
# (unless it came ignored, as under nohup) or QUIT, the check's group is
# killed and the file put back at once (exit 2, naming the signal). After
# kill -9, the next run or --recover puts the file back (it never reads the
# settings first), and refuses, keeping the journal, by the same rules; it
# goes on only while HEAD is the commit the run started on, one after it, or
# one with those files as they were then (a rebase), and otherwise says to
# check that commit out first. A file changed on top of its mutant is left
# as it is once the mutant's line is gone from it; while it is there, the
# refusal says where (line, column and change; lines added above move it):
# undo that one change, then --recover; where it cannot tell (a copy of the
# line whose lines around it are not the original's), put the file back as
# it was at the start, --recover, and make the change again without the
# mutant's. A missing file, or a copy of it, may hold it: the refusal says
# to undo it there and put the file back as it was at the start (git restore
# --source=START --staged --worktree). Files put back are newer than any
# build, so a build is redone, and a "build is current" check fails until a
# rebuild.
#
# What changed: the lines this branch adds since its merge base with main
# (lib/git.pl's Git::main_ref; there is no --base). Two merge bases (after
# criss-cross merges) stop it: merge main into the branch first. Only files
# that are exactly their stored bytes on disk are mutated: a file git's
# checkout converts (eol, ident, working-tree-encoding), Git LFS content
# and an LFS pointer, a file that is not UTF-8 text as RFC 3629 defines it
# (or holds a NUL byte), one larger than 1 MB (or whose old version is) and
# one that is not a regular file are skipped and counted. The files on disk must be the commit (run-checks' fingerprint is
# empty).
#
# Settings, in .claude/method.conf (lib/conf.pl):
#   MUTATE_PATHS     what is mutated, as PRODUCT_PATHS ("." is all). Unset:
#                    SKIPPED not-configured. An entry that names no tracked
#                    file is named on the last line.
#   MUTATION_CHECKS  the ids of the checks in checks/*.tsv run against each
#                    mutant: the fast tests (not a coverage threshold or a
#                    lint, which fail on a mutant for other reasons). Unset:
#                    SKIPPED not-configured; never all checks. An unknown
#                    id: exit 2. None runs here (runs_in, needs): SKIPPED
#                    not-here.
# Never mutated: the folder this script runs from, .claude/, checks/,
# .method/, and .gitattributes, .gitignore and .gitmodules anywhere, in any
# case of letters where the file system folds case (lib/git.pl's
# Git::case_pin); where it keeps case, a file named like them in another
# case is not theirs, and is named as not mutated (so the run is not a
# pass).
#
# A mutant runs with your rights, so a file or line that names one of these
# words gets none: rm, rmdir, unlink, mv, dd, chmod, chown, shred, truncate,
# rimraf, $(RM), ${RM} and $RM; find with -delete, rsync with --delete, make
# (also as $(MAKE), ${MAKE} or $MAKE) with clean, distclean, mostlyclean or
# maintainer-clean, and git (also as $(GIT), ${GIT} or $GIT) with clean,
# reset, push, checkout, restore, rm, branch, stash or worktree later on the
# line, whatever options come first, each as a word of its own: the
# character before it is not a letter, digit, _ or -, so ["git", "clean"]
# and repo.git.clean count too; os.remove, .unlink, .rmdir, .removedirs,
# .rename, .replace, .RemoveAll, .Remove and .Rename; shutil.rmtree and
# .move; fs.rm, .rmSync, .unlink, .unlinkSync, .rmdir, .rmdirSync, .rename
# and .renameSync; FileUtils.rm*, .remove* and .mv; File.Delete and .Move
# (also delete and move, and PowerShell's [IO.File]::Delete and ::Move);
# Directory.Delete and .Move (also with ::); Files.delete* and .move;
# fs::remove* and fs::rename; Remove-Item and Move-Item; and del, erase or
# rd followed by a space or tab. In a .bat, .cmd or .ps1 file, or a script
# whose first line names pwsh, del, erase, rd, rmdir, move, ren, rename,
# remove-item and move-item in any letter case, and robocopy with /mir,
# /purge, /move or /mov later on the line, count too. In every file, a line
# that ends in a backslash (in those files also ^ or `) is read with the
# next. A shell script, make file or batch file (.sh, .bash, .zsh, .ksh,
# .bats, .fish, .command, .mk, .mak, .make, .bat, .cmd, .ps1, Makefile and
# its kin, .envrc, .bashrc, .bash_profile, .profile, .zshrc, or a first
# line naming sh, bash, dash, ksh, zsh, fish, make or pwsh) with such a line
# anywhere is skipped whole, since its guard can sit on another line; in
# any other file, only that line, with the lines a backslash joins it to,
# gets no mutant, so a guard on another line gets mutants. The list is
# words, not a parser (RISKS #13): a delete, move or overwrite written any
# other way gets mutants, even on its own line.
#
# Mutants, one position each: === and !== swapped, == and != swapped; <= to
# <, >= to >; after a [ or test on the line, the shell tests -lt -le -gt
# -ge -eq -ne as whole words with a space on both sides (-ge and -gt, -le
# and -lt, -eq and -ne swapped); && and || swapped, and the words and and
# or; true and false (also True, TRUE) swapped; a whole decimal integer N
# to N+1 (1 to 0), not one with a leading zero, a fraction or a letter
# (also a non-ASCII one) next to it, nor one after $, ${, ${#, %, \ (a
# variable or a back-reference) or >& and <&, nor one before > or < (a
# file descriptor). A run of =, and ==>, <=<, >=> and the like, are not
# operators. A line whose first
# text opens a comment (#, //, --, /*, *, ;, %, <!--) is skipped and
# counted.
# Order: the files in path order, one mutant per changed line from each
# file in turn, then the rest the same way, so a cap reaches every file.
#
# Screen: --list prints one line per planned mutant,
#   mutate-changed: planned: FILE:LINE:COLUMN: 'OP' becomes 'OP'
# (the column in bytes; never the line's text, which can hold a key: a
# number other than 0 and 1 is shown as "a N-digit number becomes that
# number + 1"), the checks it would run, then one line that starts with
# mutate-changed: PLAN, SKIPPED or FAIL. A run prints what it put back
# from a cut-off run, the checks, run A's times and the limits, an estimate
# ("about N mutants x S s, about M min with runs B and C and the control
# run"), the checks not used and why ("not used: ID (...)": SKIPPED in run
# A, or not passing the control run), one line per mutant that survived
# ("survived: FILE:LINE:COLUMN: ...", naming a check that passed but
# examined nothing), then the last line: the counts, then "N mutants: K
# killed (ID n, ...; T by time limit), S survived, R not run", each kill
# counted for the check that made it. File names are escaped.
#
# Exit codes: 0 a plan with mutants (--list), --recover done, or PASS:
# every mutant ran and was killed, and nothing the branch changed under
# MUTATE_PATHS was left out but the method's or git's own files; 1 a mutant
# survived (FAIL); 2 bad usage (the usage line), bad settings, files on
# disk that are not the commit, no main, two merge bases, no shared
# history, a git error or a damaged stored file, busy, run A failing, run
# B or C not passing (results that do not repeat cannot be trusted), a
# check that changed something, a signal, started by a bare name not from
# its own folder or not as a file of its own (M163), or a refusal to put a
# file back
# (the last line says FAIL and why); 3 SKIPPED (not-configured, not-here,
# nothing-to-mutate, no-usable-check: no check is left once those SKIPPED
# in run A and those that do not pass the control run are not used;
# time-reached: --minutes ran out; max-reached: the plan had more than
# --max; not-all-mutated: every mutant was killed, but changed lines kept
# out by the delete words or changed files skipped are named), never a
# pass. A pass is a run's last line "mutate-changed: PASS - ...": exit 0
# alone is also --list and --recover.
set -u
unset METHOD_CALLER_PERL_UNICODE METHOD_CALLER_PERL5OPT METHOD_CALLER_PERL5LIB METHOD_CALLER_PERLLIB
unset METHOD_CALLER_PERL_USE_UNSAFE_INC METHOD_CALLER_PERLIO
if [ "${PERL_UNICODE+set}" = set ]; then export METHOD_CALLER_PERL_UNICODE="$PERL_UNICODE"; fi
if [ "${PERL5OPT+set}" = set ]; then export METHOD_CALLER_PERL5OPT="$PERL5OPT"; fi
if [ "${PERL5LIB+set}" = set ]; then export METHOD_CALLER_PERL5LIB="$PERL5LIB"; fi
if [ "${PERLLIB+set}" = set ]; then export METHOD_CALLER_PERLLIB="$PERLLIB"; fi
if [ "${PERL_USE_UNSAFE_INC+set}" = set ]; then export METHOD_CALLER_PERL_USE_UNSAFE_INC="$PERL_USE_UNSAFE_INC"; fi
if [ "${PERLIO+set}" = set ]; then export METHOD_CALLER_PERLIO="$PERLIO"; fi
unset PERL_UNICODE PERL5OPT PERL5LIB PERLLIB PERL_USE_UNSAFE_INC PERLIO

command -v perl >/dev/null 2>&1 || {
  echo "mutate-changed: FAIL - perl is not installed; the run stopped"
  exit 2
}
# started by a bare name, the current folder counts only when $0 and the
# file bash opened (BASH_SOURCE) are both this script's own name and
# ./mutate-changed.sh is a file: found on PATH (or sourced, or piped), the
# current folder is not this script's and its lib/ could be the project's
# own, so it refuses (M163; step 8.3, docs/plans/step8.md S8)
case "$0" in
  */*) here=${0%/*} ;;
  *)
    if [ "$0" = mutate-changed.sh ] && [ "${BASH_SOURCE[0]-}" = mutate-changed.sh ] && [ -f ./mutate-changed.sh ]; then
      here=.
    else
      printf '%s\n' "mutate-changed: FAIL - mutate-changed.sh was started by a bare name found on PATH, or not as a file of its own; run it by its path, such as bash path/to/mutate-changed.sh; the run stopped"
      exit 2
    fi
    ;;
esac
if [ ! -f "$here/lib/mutate.pl" ]; then
  echo "mutate-changed: FAIL - lib/mutate.pl is not next to mutate-changed.sh; the run stopped"
  exit 2
fi
exec perl "$here/lib/mutate.pl" "$@"
