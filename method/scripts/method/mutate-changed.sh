#!/usr/bin/env bash
# Breaks the code under test on purpose (M044): each changed line gets a
# small text change (a mutant), the project's fast checks run against it,
# and the line is put back. A mutant the checks do not notice survives: the
# tests would not notice that mistake either. The work is done by
# lib/mutate.pl. Step 4b.2 builds the plan only; running mutants comes in
# step 4b.3.
#
# Usage: bash scripts/method/mutate-changed.sh --list [--max N]
#   --list   print the plan: one line per mutant, nothing written, no check
#            run
#   --max N  at most N mutants (default 100)
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
#                    mutant: the fast tests. Unset: SKIPPED not-configured;
#                    never all checks. An unknown id: exit 2. None runs here
#                    (runs_in, needs): SKIPPED not-here.
# Never mutated: the folder this script runs from, .claude/, checks/,
# .method/, and .gitattributes, .gitignore and .gitmodules anywhere, in any
# case of letters.
#
# A mutant runs with your rights, so a file or line that names one of these
# words gets none: rm, rmdir, unlink, mv, dd, chmod, chown, shred, truncate,
# rimraf, $(RM) and ${RM}; find with -delete, rsync with --delete, make with
# clean or distclean, and git (also as $(GIT), ${GIT} or $GIT) with clean,
# reset, push, checkout, restore, rm, branch, stash or worktree later on
# the line, whatever options come first; os.remove, .unlink, .rmdir,
# .removedirs, .rename, .replace, .RemoveAll, .Remove and .Rename;
# shutil.rmtree and .move; fs.rm, .rmSync, .unlink, .unlinkSync, .rmdir,
# .rmdirSync, .rename and .renameSync; FileUtils.rm*, .remove* and .mv;
# File.Delete and .Move (also delete and move); Directory.Delete and .Move;
# Files.delete* and .move; fs::remove* and fs::rename; Remove-Item and
# Move-Item; and del, erase or rd followed by a space. In a .bat, .cmd or
# .ps1 file, del, erase, rd, rmdir, move, ren, rename, remove-item and
# move-item in any letter case, and robocopy with /mir, /purge or /move,
# count too. A shell script, make file or batch file (.sh, .bash, .zsh,
# .ksh, .bats, .fish, .command, .mk, .mak, .make, .bat, .cmd, .ps1,
# Makefile and its kin, .envrc, .bashrc, .bash_profile, .profile, .zshrc,
# or a first line naming sh, bash, dash, ksh, zsh, fish, make or pwsh) with
# such a line anywhere is skipped whole, since its guard can sit on another
# line; in any other file, only that line gets no mutant. The list is
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
# Screen: one line per planned mutant,
#   mutate-changed: planned: FILE:LINE:COLUMN: 'OP' becomes 'OP'
# (the column in bytes; never the line's text, which can hold a key: a
# number other than 0 and 1 is shown as "a N-digit number becomes that
# number + 1"), the checks it would run, then one line that starts with
# mutate-changed: PLAN, SKIPPED or FAIL. File names are escaped.
#
# Exit codes: 0 a plan with mutants; 2 bad usage (the usage line), bad
# settings, files on disk that are not the commit, no main, two merge
# bases, no shared history, or a git error
# or a damaged stored file (the last line says FAIL and why); 3 SKIPPED
# (not-configured, not-here, nothing-to-mutate), never a pass.
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
case "$0" in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
if [ ! -f "$here/lib/mutate.pl" ]; then
  echo "mutate-changed: FAIL - lib/mutate.pl is not next to mutate-changed.sh; the run stopped"
  exit 2
fi
exec perl "$here/lib/mutate.pl" "$@"
