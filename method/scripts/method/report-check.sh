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
#                 currency mark before or after ($, EUR, GBP, JPY signs),
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
#                 code block or an HTML comment do not count. HTML
#                 comments are not text. A part whose every line says
#                 only "nothing", "none" or "n/a" (round, square and
#                 curly brackets, straight and curly quotes and closing
#                 marks aside), or holds no word at all, is listed.
# Then "report-check: PASS - ..." when nothing was listed, or
# "report-check: FAIL - N listed".
#
# Exit codes: 0 nothing listed; 1 anything listed; 2 bad usage (no LOG
# among them), a report or log that could not be read, a log that is the
# report itself, or perl missing (the last line says could not check).
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
# and JPY (5 INR written with its sign, for one).
set -u
# perl reads bytes; these settings would change how it reads and writes
# them, and the library paths would let modules from elsewhere run inside it
unset PERL_UNICODE PERL5OPT PERL5LIB PERLLIB PERL_USE_UNSAFE_INC PERLIO

command -v perl >/dev/null 2>&1 || {
  echo "report-check: FAIL - could not check: perl is not installed"
  exit 2
}
# only bash and perl are needed, so no dirname
case "$0" in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
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
