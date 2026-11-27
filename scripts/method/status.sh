#!/usr/bin/env bash
# Says where things stand, read-only, for a person or a session starting
# work. The work is done by lib/status.pl.
#
# Usage: bash scripts/method/status.sh [--quick]
#   --quick skips the ci area (SKIPPED), which waits on the network: the
#   method's session-status hook runs it at every session start (step 5.4).
#
# One line per area (verdicts may add a second), "<area>: PASS|LOOK|SKIPPED -
# <detail>". LOOK means a person should look; status never says FAIL and
# never blocks anything.
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
#                ends with a valid trailer (lib/verdicts.pl check-trailer);
#                a second line names each commit merged without a review
#                as the first install of the method (its trailer's reason
#                starts "first install of the method"): PASS for one, LOOK
#                for more, as the exception is allowed once per project
#   records      the project records exist, CLAUDE.md imports AGENTS.md,
#                checks/*.tsv reads cleanly and TESTS.md names each check
#   context      the project's own text that loads in every session
#                (CLAUDE.md, .claude/CLAUDE.md, AGENTS.md and the .md files
#                under .claude/rules/ without a paths: line,
#                .claude/rules/method/ left out, also through a link) is at
#                most 8,000 bytes; LOOK over it, naming the biggest files
#   claude-code  the running Claude Code is not older than REQUIRES says
#                (SKIPPED inside a hook, which cannot see the client)
#   effort       CLAUDE_CODE_EFFORT_LEVEL is not set (also checked inside a
#                hook: CLAUDE_PROJECT_DIR set, CLAUDE_CODE_EXECPATH not)
#   perl         JSON::PP and Digest::SHA load
#   guard        the refusals in the guard's log (.method/local/guard.log):
#                LOOK with their count and rules, else PASS
#   ci           the newest CI run of each workflow for HEAD and main's tip
#                (gh, at most 15 seconds; only for a github.com origin)
#   repo <path>  the work checks for each REPOS entry in .claude/method.conf
# The last line counts the areas that need a look and the SKIPPED ones.
#
# Exit codes: 0 nothing needs a look; 1 something does; 2 bad usage, not
# inside a git working tree, perl missing, or started by a bare name not
# from its own folder or not as a file of its own (M163).
#
# Rules it serves:
# - M001: one read-only command orients any session: work not committed or
#   not pushed in every repository, commits missing a verdict, record
#   consistency and health.
# - M152 (its home is lib/status.pl): the context area.
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
# only bash, git and perl are needed, so no dirname; started by a bare
# name, the current folder counts only when $0 and the file bash opened
# (BASH_SOURCE) are both this script's own name and ./status.sh is a file:
# found on PATH (or sourced, or piped), the current folder is not this
# script's and its lib/ could be the project's own, so it refuses (M163;
# step 8.3, docs/plans/step8.md S8)
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
    if [ "$0" = status.sh ] && [ "$self_src" = status.sh ] && [ -f ./status.sh ]; then
      here=.
      self_ok=1
    fi
    ;;
esac
if [ -z "$self_ok" ]; then
  printf '%s\n' "status: status.sh was started by a bare name found on PATH, or not as a file of its own; run it by its path, such as bash path/to/status.sh"
  exit 2
fi
exec perl "$here/lib/status.pl" "$@"
