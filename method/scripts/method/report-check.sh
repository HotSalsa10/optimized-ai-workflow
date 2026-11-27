#!/usr/bin/env bash
# Checks the report written for the owner against the logs the numbers in
# it came from, before the reporter reads it. The work is done by
# lib/report.pl. Read-only: it writes no file.
#
# Usage: bash scripts/method/report-check.sh REPORT LOG...
#   REPORT  the report, usually .method/local/report.md
#   LOG     each log the report's numbers come from (at least one): the
#           run-checks log of HEAD, git's counts, done-check's output and
#           .method/local/gates.log, as /method-finish writes them. The
#           folder of logs is not read whole: it holds runs of other
#           versions and branches.
#
# It lists, one line each:
#   report-check: not in any log: NUMBER (line N)
#                 a number in the report that no LOG holds. A number is a
#                 run of digits with an optional sign (+, -, U+2212), a
#                 currency mark before or after ($, EUR, GBP, JPY signs;
#                 a sign before or after a mark in front: -$5, $-5),
#                 thousands separators (1,200), a decimal part (.45 too)
#                 and a percent mark, standing alone between spaces or
#                 marks such as ( ) * ` " = | ; the no-break, ideographic
#                 and other wide spaces, the en and em dashes, curly
#                 quotes, guillemets, and closing punctuation (a closing +
#                 or ~ too: 45+ and ~~45~~ are 45). Numbers joined by /,
#                 - or the hyphens U+2010 and U+2011 are each read, each
#                 with its own sign (40/44, 3-5, 12/30, +120/-4). It must
#                 be in a log exactly as written: 1,200 is not 1200, -3
#                 is not 3, $5 is not 5, 90% is not 90 (M074). Not
#                 numbers: IDs and hashes (M126, A66, #4, b776281, 6b),
#                 paths and line numbers (file.pl:12, a/7), versions
#                 (2.1.316), dates and times (10:30, 22 November 2026,
#                 November 22, 2026, March 2026; but "March 14 tests" is
#                 a number), a date joined by one of the marks above,
#                 with a year from 1900 to 2099, a month from 1 to 12 and
#                 a day from 1 to 31 (2026-11, 2026-11-22, 11/2026,
#                 22/11/2026, 11/22/2026; but 1024/12 and 2026/13 are
#                 numbers), and a numbered list's or heading's marker (1.
#                 or 2) at the start of a line). The logs are read the
#                 same way, after terminal colour codes are taken out.
#   report-check: no "What the checks would miss" heading
#   report-check: "What the checks would miss" (line N) has nothing under it
#   report-check: "What the checks would miss" (line N) says only "none"
#                 the heading is a markdown heading (#, ##, ...) with that
#                 text in any case, a colon allowed; its part runs to the
#                 next heading of its level or higher; headings inside a
#                 code block or an HTML comment do not count. Such a
#                 comment starts at a line that opens with up to 3
#                 spaces and <!-- and ends at the first line holding -->
#                 (<!--> alone opens and closes one), or runs to the end;
#                 a <!-- later in a line starts none, and there only a
#                 whole <!-- ... --> is a comment. HTML comments are not
#                 text. A part whose every line says only "nothing",
#                 "none" or "n/a" (round, square, curly and angle
#                 brackets, guillemets, U+3008 to U+3011, U+3014 to U+301B, the fullwidth ( ) [ ] { },
#                 straight and curly quotes and closing marks aside), or
#                 holds no word at all, is listed.
# Then "report-check: PASS - ..." when nothing was listed, or
# "report-check: FAIL - N listed".
#
# Exit codes: 0 nothing listed; 1 anything listed; 2 bad usage (no LOG
# among them), a report or log that could not be read, a log that is the
# report itself, perl missing, or started by a bare name not from its own
# folder or not as a file of its own (M163) (the last line says could not
# check).
#
# Rules it serves:
# - M126: the report check lists every number that appears in no log, and
#   refuses a report whose "What the checks would miss" part is missing,
#   empty, "nothing" or "none" (SPEC R8).
# Who makes it count: /method-finish runs it, and the reporter answers that
# changes are needed when it did not exit 0. Not read as numbers, so not
# checked: a number written in words, or with a unit or word stuck to it
# (5ms, 44-all, 40/s); a decimal comma (3,4 or 9,5%; 1.200,50); grouping
# other than 1,200 (Indian 1,00,000, or 1'200); digits other than ASCII
# 0 to 9 (fullwidth digits); and a currency sign other than $, EUR, GBP
# and JPY (5 INR written with its sign, for one). A month and a year
# joined (3/2000) is taken for a date, so "Passed 3/2000" is not checked;
# and a span of years written short (2025-26) is read as the numbers 2025
# and 26, so it is listed unless a log holds them. A sign after a currency
# mark in a piece joined by / or - ($-5/$-3) is not read, so such a piece
# is not checked. In the miss part, a line <!--> or <!---> is taken for a
# comment left open, so the text after it is not read; and text from a
# <!-- to a later --> is taken for a comment even inside code spans.
set -u
# perl reads bytes; these settings would change how it reads and writes
# them, and the library paths would let modules from elsewhere run inside it
unset PERL_UNICODE PERL5OPT PERL5LIB PERLLIB PERL_USE_UNSAFE_INC PERLIO

command -v perl >/dev/null 2>&1 || {
  echo "report-check: FAIL - could not check: perl is not installed"
  exit 2
}
# only bash and perl are needed, so no dirname; started by a bare name, the
# current folder counts only when $0 and the file bash opened (BASH_SOURCE)
# are both this script's own name and ./report-check.sh is a file: found on
# PATH (or sourced, or piped), the current folder is not this script's and
# its lib/ could be the project's own, so it refuses (M163; step 8.3,
# docs/plans/step8.md S8)
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
    if [ "$0" = report-check.sh ] && [ "$self_src" = report-check.sh ] && [ -f ./report-check.sh ]; then
      here=.
      self_ok=1
    fi
    ;;
esac
if [ -z "$self_ok" ]; then
  printf '%s\n' "report-check: FAIL - could not check: report-check.sh was started by a bare name found on PATH, or not as a file of its own; run it by its path, such as bash path/to/report-check.sh"
  exit 2
fi
if [ ! -f "$here/lib/report.pl" ]; then
  echo "report-check: FAIL - could not check: lib/report.pl is not next to report-check.sh"
  exit 2
fi
perl "$here/lib/report.pl" "$@"
st=$?
case $st in
  0 | 1 | 2) exit "$st" ;;
esac
# perl itself stopped (a file of the method that does not compile, a
# signal), so nothing was checked
echo "report-check: FAIL - could not check: perl stopped with exit $st"
exit 2
