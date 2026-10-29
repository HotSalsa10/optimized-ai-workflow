#!/usr/bin/env bash
# Runs every check of the project, built-in and its own, from the top of
# the repository, and keeps the whole output in a log. The work is done by
# lib/checks.pl.
#
# Usage: bash scripts/method/run-checks.sh   (no arguments)
#
# The project's checks are listed in checks/*.tsv, read in name order. Each
# line has five fields separated by TAB; # lines and blank lines are skipped:
#   id       lower-case letters, digits and -; not a built-in check's name
#   runs_in  any, ci or local; here is CI when CI=true
#   needs    -, or a comma list of cmd:NAME (on PATH), env:NAME (set, not
#            empty) or file:PATH (exists); an unmet need skips the check
#   count    a perl pattern with one capture group, matched on each output
#            line; the last match is the number of things the check examined
#   command  run with bash -o pipefail from the top of the repository. Join
#            steps with &&. Do not trim output with | tail or | head: the
#            log keeps it all and a failure shows its last 10 lines.
# Settings come from .claude/method.conf (lib/conf.pl explains each key).
#
# Results, each with a kind:
#   PASS     pass: the check ran, exited 0 and examined 1 or more things
#   FAIL     exit (non-zero exit or killed by a signal), or finding (a
#            built-in check found something)
#   SKIPPED  not-here (runs_in rules it out here), needs (a need is unmet),
#            examined-nothing (a count of 0), no-count (no line matched the
#            count, or it caught something that is not a number), or
#            not-configured (a built-in check has nothing to work on)
# Built-in checks, always run:
#   secrets         lib/secrets.pl --repo on every tracked file, with
#                   checks/scan-allow.txt for accepted false positives
#   fresh-clone     files under PRODUCT_PATHS that git ignores are here but
#                   not in a clone; LOCAL_ONLY names the ones a clone is
#                   meant to lack
#   project-checks  SKIPPED when checks/*.tsv lists no checks
#   tree-unchanged  last: the checks left HEAD and the files on disk as
#                   they found them
#
# Screen: the log's path first; each FAIL with its last 10 output lines,
# masked; up to 10 SKIPPED lines; the passed ids; then one line that starts
# with run-checks: PASS, FAIL or SKIPPED, says where it ran (CI or local)
# and whether the files had uncommitted changes.
# Log: .method/local/logs/run-checks-<UTC time>-<pid>.log, readable only by
# its owner. Per check "=== CHECK <id> ===", its output masked, and
# RESULT<TAB>id<TAB>result<TAB>kind<TAB>runs_in<TAB>examined<TAB>detail; at
# the end the screen's last line and END<TAB>exit N. A log without END is
# from a run that was cut off. The newest 20 logs are kept. Logs and the
# screen are written by the code being checked: they are local claims, not
# evidence.
#
# Exit codes: 0 every check that applies here ran, examined something and
# passed; 1 something failed; 2 bad usage or a bad config file, and no check
# ran; 3 nothing failed, but a check that applies here was SKIPPED, or no
# project check runs here. A SKIPPED is never a pass.
#
# Rules it serves:
# - M002: a check that examined nothing is SKIPPED, never a pass; a check
#   must print how many things it examined.
# - M050: fresh-clone fails on files that are here but not in a clone, and
#   CI's clean checkout runs the same checks (DECISIONS A31).
# - M051: the whole output goes to a log where the run happens; the screen
#   stays short.
# - M066: the secrets check runs on every tracked file, every time.
set -u
# Perl reads bytes; these settings would change how the method's perl reads
# them, and the library paths would let modules from elsewhere run inside
# it. The project's checks get the caller's values back (lib/checks.pl).
unset METHOD_CALLER_PERL_UNICODE METHOD_CALLER_PERL5OPT METHOD_CALLER_PERL5LIB METHOD_CALLER_PERLLIB
if [ "${PERL_UNICODE+set}" = set ]; then export METHOD_CALLER_PERL_UNICODE="$PERL_UNICODE"; fi
if [ "${PERL5OPT+set}" = set ]; then export METHOD_CALLER_PERL5OPT="$PERL5OPT"; fi
if [ "${PERL5LIB+set}" = set ]; then export METHOD_CALLER_PERL5LIB="$PERL5LIB"; fi
if [ "${PERLLIB+set}" = set ]; then export METHOD_CALLER_PERLLIB="$PERLLIB"; fi
unset PERL_UNICODE PERL5OPT PERL5LIB PERLLIB

command -v perl >/dev/null 2>&1 || {
  echo "run-checks: FAIL - perl is not installed; the run stopped"
  exit 2
}
# only bash, git and perl are needed, so no dirname
case "$0" in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
exec perl "$here/lib/checks.pl" "$@"
