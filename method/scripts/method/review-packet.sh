#!/usr/bin/env bash
# Builds the review packet: everything a checking agent (reviewer or
# security-checker) is given, in one file. The work is done by
# lib/packet.pl.
#
# Usage: review-packet.sh --base REV [--since REV] [--criteria FILE] [--checks FILE] >PACKET
#   --base REV      the branch the change will merge into, usually main
#   --since REV     a later review round: the last reviewed version
#   --criteria FILE the acceptance criteria the change must meet
#   --checks FILE   the output of the checks run on this version
# Exit codes: 0 the packet was written; 1 refused: the working copy is not
# the committed change; 2 bad usage, a git or file error, or started by a
# bare name not from its own folder or not as a file of its own (M163);
# 3 nothing to review. Nothing is written unless the exit code is 0.
#
# Rules it serves:
# - M038: the packet is the agent's whole input. It holds the criteria, the
#   project's REVIEW.md, the incident checklist, the check output, the
#   changed files and the diff of the committed change. Commit messages and
#   pull request text, the author's account of the change, are never read.
#   A change with nothing to review gives no packet (exit 3).
# - M032: it holds the project's incident checklist,
#   docs/incident-checklist.md, from the merge base, so a change cannot
#   weaken the list it is checked against (DECISIONS A28).
# - M157 (its home is lib/packet.pl, from_base): REVIEW.md from the merge
#   base too.
# - M085: with --since, the diff holds only the changes since the last
#   reviewed version, and FILES still lists the whole change. When that
#   version is not between the merge base and HEAD, the packet says so and
#   shows the whole change.
# - M112: lockfiles, minified files, source maps and files already marked
#   @generated are listed but left out of the diff. Files in a migration
#   folder are always kept, and so is everything when only such files
#   changed.
# - M113: every line inside a section goes through one escaping step, so
#   only the packet's own section markers start with "===", control,
#   format and invisible characters are shown as \xNN or \u{XXXX}, and the
#   CI runner's command form ##[ is shown as #\x23[. The markers also carry
#   a token made from the whole packet, which no line of content can hold.
# The reviewer reads files from disk, so the packet is refused while any
# tracked file on disk differs from the commit, or while git's working copy
# is not the folder it is built from. Stored files, folders and the commits
# after the merge base are checked against their ids as they are read.
# The header names the commit (a line "HEAD: <id>") and, on the next line,
# its top folder ("Tree: <id>", the id git rev-parse HEAD^{tree} gives), so a
# packet can be matched to the files it was built for.
set -u
# perl reads bytes; these settings would change how it reads and writes
# them, and the library paths would let modules from elsewhere run inside
# the builder
unset PERL_UNICODE PERL5OPT PERL5LIB PERLLIB PERL_USE_UNSAFE_INC PERLIO

command -v perl >/dev/null 2>&1 || {
  echo "review-packet: perl is not installed" >&2
  exit 2
}
# only bash, git and perl are needed, so no dirname; started by a bare
# name, the current folder counts only when $0 and the file bash opened
# (BASH_SOURCE) are both this script's own name and ./review-packet.sh is
# a file: found on PATH (or sourced, or piped), the current folder is not
# this script's and its lib/ could be the project's own, so it refuses
# (M163; step 8.3, docs/plans/step8.md S8)
case "$0" in
  */*) here=${0%/*} ;;
  *)
    if [ "$0" = review-packet.sh ] && [ "${BASH_SOURCE[0]-}" = review-packet.sh ] && [ -f ./review-packet.sh ]; then
      here=.
    else
      printf '%s\n' "review-packet: review-packet.sh was started by a bare name found on PATH, or not as a file of its own; run it by its path, such as bash path/to/review-packet.sh" >&2
      exit 2
    fi
    ;;
esac
exec perl "$here/lib/packet.pl" "$@"
