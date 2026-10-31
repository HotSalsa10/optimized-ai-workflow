#!/usr/bin/env bash
# Says where things stand, read-only, for a person or a session starting
# work. The work is done by lib/status.pl.
#
# Usage: bash scripts/method/status.sh   (no arguments)
#
# One line per area, "<area>: PASS|LOOK|SKIPPED - <detail>". LOOK means a
# person should look; status never says FAIL and never blocks anything.
#   config       problems in .claude/method.conf (only when there are any)
#   work         uncommitted changes, files git is told not to compare (also
#                ones gone from disk, and inside submodules), submodule
#                folders whose changes git cannot see, a merge, rebase,
#                cherry-pick, revert or bisect in progress, stashes and
#                commits not pushed (as of the last fetch), in this
#                repository and each of its linked worktrees; and in this
#                working tree, a mutate-changed run that is running (files
#                hold mutants until it ends) or was cut off (run
#                mutate-changed.sh --recover)
#   verdicts     every commit on main's first-parent history since the first
#                one with a Review-Verdict line (or after VERDICTS_FROM)
#                ends with a valid trailer (lib/verdicts.pl check-trailer)
#   records      the project records exist, CLAUDE.md imports AGENTS.md,
#                checks/*.tsv reads cleanly and TESTS.md names each check
#   claude-code  the running Claude Code is not older than REQUIRES says
#   effort       CLAUDE_CODE_EFFORT_LEVEL is not set
#   perl         JSON::PP and Digest::SHA load
#   ci           the newest CI run of each workflow for HEAD and main's tip
#                (gh, at most 15 seconds; only for a github.com origin)
#   repo <path>  the work checks for each REPOS entry in .claude/method.conf
# The last line counts the areas that need a look and the SKIPPED ones.
#
# Exit codes: 0 nothing needs a look; 1 something does; 2 bad usage, not
# inside a git working tree, or perl missing.
#
# Rules it serves:
# - M001: one read-only command orients any session: work not committed or
#   not pushed in every repository, commits missing a verdict, record
#   consistency and health.
# - M003: it exits 1 when something needs a look; it reports, it does not
#   block.
# - M077: CLAUDE_CODE_EFFORT_LEVEL is never set (DECISIONS A4).
# It writes no file and runs no program from the repository: git runs with
# --no-optional-locks, without a file-system monitor and with every filter
# program turned off (lib/git.pl), so even the index is left as it is (git
# may still freshen the time stamp of a split index's shared file). git and
# perl are found on PATH, which the session controls; gh only in absolute
# PATH folders.
set -u
# perl reads bytes; these settings would change how it reads and writes
# them, and the library paths would let modules from elsewhere run inside it
unset PERL_UNICODE PERL5OPT PERL5LIB PERLLIB PERL_USE_UNSAFE_INC PERLIO

command -v perl >/dev/null 2>&1 || {
  echo "status: perl is not installed"
  exit 2
}
# only bash, git and perl are needed, so no dirname
case "$0" in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
exec perl "$here/lib/status.pl" "$@"
