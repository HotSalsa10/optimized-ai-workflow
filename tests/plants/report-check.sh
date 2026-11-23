#!/usr/bin/env bash
# Plants for report-check (step 6b.2, M126): each planted break in
# lib/report.pl or report-check.sh turns tests/report-check.test.sh red for
# its stated reason, in a throwaway copy of the repo, with only the cases
# kept for that reason (after they pass on the clean copy). One plant per
# rule the check holds. The breaks are data: "=== NAME | FILE | REASON",
# the text OLD (in FILE exactly once), "---", the text NEW (tests/lib.sh,
# plant_data). PLANT_SHARD=K/N runs every Nth one from the Kth.
# shellcheck disable=SC2016 # the plants are literal perl and shell text
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: report-check"
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/plants.txt" <<'PLANTS-END'
=== a number in no log not listed | method/scripts/method/lib/report.pl | a number in no log is listed
(line $_->[0])" unless $have{$_->[1]};
---
(line $_->[0])" unless 1;
=== each missing number listed once only | method/scripts/method/lib/report.pl | each place a missing number is written is listed
(line $_->[0])" unless $have{$_->[1]};
---
(line $_->[0])" unless $have{$_->[1]}++;
=== only the first log read | method/scripts/method/lib/report.pl | a number only in the second log is found
  for my $l (@logs) {
---
  for my $l ($logs[0]) {
=== a digit inside a piece taken for a number | method/scripts/method/lib/report.pl | IDs and hashes are not numbers
our $NUMBER = qr/\A$SIGN?
---
our $NUMBER = qr/$SIGN?
=== paths cut at colons and slashes | method/scripts/method/lib/report.pl | paths and line numbers are not numbers
my $CUT = qr/(?:[ \t\r
---
my $CUT = qr/(?:[:\/ \t\r
=== a version read as a decimal | method/scripts/method/lib/report.pl | versions are not numbers
(?:\.\d+)?|\.\d+)
---
(?:\.\d+)*|\.\d+)
=== a decimal with no leading digit not read | method/scripts/method/lib/report.pl | a decimal with no leading digit is read
|\.\d+)(?:%
---
)(?:%
=== no day before a month | method/scripts/method/lib/report.pl | dates and times are not numbers
  return 1 if $x =~ $DAY && $after =~ $MONTH;
---

=== no day after a month | method/scripts/method/lib/report.pl | dates and times are not numbers
  return 1 if $x =~ $DAY && $before =~ $MONTH && ($comma || $after =~ $YEAR);
---

=== a day after a month with no comma or year taken for a date | method/scripts/method/lib/report.pl | a count after a month and a slash pair are numbers
$before =~ $MONTH && ($comma || $after =~ $YEAR);
---
$before =~ $MONTH;
=== no year after a month | method/scripts/method/lib/report.pl | dates and times are not numbers
  return 1 if $x =~ $YEAR && $before =~ $MONTH;
---

=== no year after a month's day | method/scripts/method/lib/report.pl | dates and times are not numbers
  return 1 if $x =~ $YEAR && $i > 1
---
  return 0 if $x =~ $YEAR && $i > 1
=== a joined date read as numbers | method/scripts/method/lib/report.pl | dates and times are not numbers
  return () if $x =~ $JOINED_DATE;
---

=== a slash pair taken for a date | method/scripts/method/lib/report.pl | a count after a month and a slash pair are numbers
$M($JOIN)$D\3$Y)\z};
---
$M($JOIN)$D(?:\3$Y)?)\z};
=== any four digits taken for a joined date's year | method/scripts/method/lib/report.pl | a joined pair without a year from 1900 to 2099 is numbers
my $Y = qr/(?:19|20)\d\d/;
---
my $Y = qr/\d{4}/;
=== any two digits taken for a joined date's month | method/scripts/method/lib/report.pl | a joined piece whose month or day is out of range is numbers
my $M = qr/(?:0?[1-9]|1[0-2])/;
---
my $M = qr/\d{1,2}/;
=== any two digits taken for a joined date's day | method/scripts/method/lib/report.pl | a joined piece whose month or day is out of range is numbers
my $D = qr/(?:0?[1-9]|[12]\d|3[01])/;
---
my $D = qr/\d{1,2}/;
=== a month and a year joined read as numbers | method/scripts/method/lib/report.pl | a year last after a month, or after a month and a day, is a date
|$M$JOIN$Y
---

=== a month, a day and a year joined read as numbers | method/scripts/method/lib/report.pl | a year last after a month, or after a month and a day, is a date
|$M($JOIN)$D\3$Y)
---
)
=== joined numbers not read | method/scripts/method/lib/report.pl | numbers joined by a slash are read
my @nums = $p[$i] =~ $NUMBER ? ($p[$i]) : joined($p[$i]);
---
my @nums = $p[$i] =~ $NUMBER ? ($p[$i]) : ();
=== only a slash joins numbers | method/scripts/method/lib/report.pl | numbers joined by a hyphen are read
my $JOIN = qr{(?:[/-]|
---
my $JOIN = qr{(?:/|
=== the hyphens U+2010 and U+2011 not a join | method/scripts/method/lib/report.pl | the hyphens U+2010 and U+2011 join numbers
|\xE2\x80[\x90\x91])};
---
)};
=== a sign after a join taken for a join | method/scripts/method/lib/report.pl | a sign after a join is read with its part
(?<![/-])(?<!\xE2\x80[\x90\x91])$JOIN
---
$JOIN
=== the sign of a later joined part dropped | method/scripts/method/lib/report.pl | a sign after a join must be in a log as written
  my @parts = split $JOIN_AT, $x, -1;
---
  my @parts = map { (my $p = $_) =~ s/\A$SIGN//; $p } split $JOIN_AT, $x, -1;
=== the sign of joined numbers dropped | method/scripts/method/lib/report.pl | numbers joined by a hyphen are read
  $parts[0] = $sign . $parts[0];
---

=== wide spaces not a cut | method/scripts/method/lib/report.pl | a no-break space cuts a line
|\xC2\xA0|\xE2\x80[\x80-\x8A\xAF]|
---
|
=== dashes not a cut | method/scripts/method/lib/report.pl | en and em dashes cut a line
|\xE2\x80[\x92-\x95]|
---
|
=== curly quotes not a cut | method/scripts/method/lib/report.pl | curly quotes, a bullet and an ellipsis cut a line
|\xE2\x80[\x98-\x9F\xA2\xA6]|
---
|
=== the ideographic and medium mathematical spaces not a cut | method/scripts/method/lib/report.pl | an ideographic and a medium mathematical space cut a line
|\xE3\x80\x80|\xE2\x81\x9F|
---
|
=== guillemets not a cut | method/scripts/method/lib/report.pl | guillemets cut a line
|\xC2[\xAB\xBB]|\xE2\x80[\xB9\xBA]
---

=== a month's name in any case | method/scripts/method/lib/report.pl | a number beside a word that is not a month is a number
  |Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\z/x;
---
  |Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\z/xi;
=== any number beside a month a date | method/scripts/method/lib/report.pl | a number beside a word that is not a month is a number
my $DAY = qr/\A(?:0?[1-9]|[12]\d|3[01])\z/;
---
my $DAY = qr/\A\d+\z/;
=== a list marker taken for a number | method/scripts/method/lib/report.pl | a numbered list's markers are not numbers
      if ($marker) {
---
      if (0) {
=== the currency mark not read | method/scripts/method/lib/report.pl | the currency mark is kept
qr/\A$SIGN?$CUR?(?:
---
qr/\A$SIGN?(?:
=== the sign not read | method/scripts/method/lib/report.pl | the sign is kept
our $NUMBER = qr/\A$SIGN?$CUR?
---
our $NUMBER = qr/\A$CUR?
=== the percent mark not read | method/scripts/method/lib/report.pl | the percent mark is kept
|\.\d+)(?:%|$CUR)?\z/;
---
|\.\d+)(?:$CUR)?\z/;
=== thousands separators not read | method/scripts/method/lib/report.pl | thousands separators and decimals are kept
(?:\d{1,3}(?:,\d{3})+|\d+)
---
(?:\d+)
=== the closing marks kept on a number | method/scripts/method/lib/report.pl | marks around a number are not part of it
      my $close = $x =~ s/(['_.,:!?+~]+)\z// ? $1 : '';
---
      my $close = '';
=== a closing plus kept on a number | method/scripts/method/lib/report.pl | a closing plus is dropped
s/(['_.,:!?+~]+)\z//
---
s/(['_.,:!?~]+)\z//
=== a closing tilde kept on a number | method/scripts/method/lib/report.pl | a struck-through number is read
s/(['_.,:!?+~]+)\z//
---
s/(['_.,:!?+]+)\z//
=== a CR kept on a number | method/scripts/method/lib/report.pl | a CRLF report reads the same
my $CUT = qr/(?:[ \t\r\f
---
my $CUT = qr/(?:[ \t\f
=== an equals sign not a cut | method/scripts/method/lib/report.pl | a log's key=value and table numbers are found
<>"`*=|;]|
---
<>"`*|;]|
=== terminal codes left in | method/scripts/method/lib/report.pl | a log's terminal colour codes are taken out
split /\n/, Esc::plain($text), -1) {
---
split /\n/, $text, -1) {
=== a missing miss heading not listed | method/scripts/method/lib/report.pl | the miss heading missing is listed
  push @problems, 'no "What the checks would miss" heading' unless $found;
---
  push @problems, 'no "What the checks would miss" heading' unless 1;
=== an empty miss part not listed | method/scripts/method/lib/report.pl | the miss heading with nothing under it is listed
    if (!@said) {
---
    if (0) {
=== a miss part saying "none" let through | method/scripts/method/lib/report.pl | the miss heading saying only 'None.' is listed
my %SAYS_NOTHING = map { $_ => 1 } qw(nothing none n/a);
---
my %SAYS_NOTHING = map { $_ => 1 } qw(nothing n/a);
=== a miss part saying "nothing" let through | method/scripts/method/lib/report.pl | the miss heading saying only 'nothing' is listed
my %SAYS_NOTHING = map { $_ => 1 } qw(nothing none n/a);
---
my %SAYS_NOTHING = map { $_ => 1 } qw(none n/a);
=== a miss part saying "n/a" let through | method/scripts/method/lib/report.pl | the miss heading saying only 'N/A' is listed
my %SAYS_NOTHING = map { $_ => 1 } qw(nothing none n/a);
---
my %SAYS_NOTHING = map { $_ => 1 } qw(nothing none);
=== brackets and quotes kept in the miss part | method/scripts/method/lib/report.pl | the miss heading saying only '(none)' is listed
      $x =~ s/[*_`>#~()\[\]{}"']+//g;
---
      $x =~ s/[*_`>#~\[\]{}]+//g;
=== square and curly brackets kept in the miss part | method/scripts/method/lib/report.pl | the miss heading saying only '[none]' is listed
()\[\]{}"']+//g;
---
()"']+//g;
=== curly quotes kept in the miss part | method/scripts/method/lib/report.pl | a miss part saying only curly-quoted words is listed
      $x =~ s/\xE2\x80[\x98-\x9F]//g;    # curly quotes
---

=== a closing semicolon kept in the miss part | method/scripts/method/lib/report.pl | the miss heading saying only 'Nothing;' is listed
      $x =~ s/[.!;,:]+\z//;
---
      $x =~ s/[.!]+\z//;
=== a miss part judged whole, not line by line | method/scripts/method/lib/report.pl | a miss part whose every line says nothing is listed
    } elsif (!grep { !$SAYS_NOTHING{$_} } @said) {
---
    } elsif (@said == 1 && $SAYS_NOTHING{$said[0]}) {
=== HTML comments read as text | method/scripts/method/lib/report.pl | a miss part holding only a comment has nothing under it
    $body =~ s/<!--.*?-->//gs;
---

=== a comment left open read as text | method/scripts/method/lib/report.pl | a comment left open in the miss part runs to its end
    $body =~ s/<!--(?:(?!-->).)*\z//s;    # a comment left open runs to the end
---

=== dashes and wide spaces read as a word | method/scripts/method/lib/report.pl | a miss part holding only a dash has nothing under it
      $x =~ s/$NO_WORD/ /g;
---

=== a line of marks only read as a word | method/scripts/method/lib/report.pl | a miss part holding only a dash has nothing under it
      push @said, lc $x if $x =~ /[A-Za-z0-9\x80-\xff]/;
---
      push @said, lc $x if length $x;
=== the miss heading's case kept | method/scripts/method/lib/report.pl | the miss heading with text passes in any case and with a colon
    next unless lc $t eq $HEADING;
---
    next unless $t eq $HEADING;
=== the miss heading's colon kept | method/scripts/method/lib/report.pl | the miss heading with text passes in any case and with a colon
    $t =~ s/[ \t]*:\z//;
---

=== the miss part cut at any heading | method/scripts/method/lib/report.pl | a sub-heading with text under the miss heading counts
      last if defined $l && $l <= $level;
---
      last if defined $l;
=== the miss part not cut at a heading of its level | method/scripts/method/lib/report.pl | the miss part ends at the next heading of its level
      last if defined $l && $l <= $level;
---
      last if defined $l && $l < $level;
=== a heading in a code block taken | method/scripts/method/lib/report.pl | a heading inside a code block is not the miss heading
    next if $code[$i];
---

=== a code block's heading ends the miss part | method/scripts/method/lib/report.pl | a heading inside a code block does not end the miss part
      my ($l) = $code[$j] ? () : heading($lines[$j]);
---
      my ($l) = heading($lines[$j]);
=== a heading in an HTML comment taken | method/scripts/method/lib/report.pl | a heading inside an HTML comment is not the miss heading
    next if $comment[$i];
---

=== an HTML comment's heading ends the miss part | method/scripts/method/lib/report.pl | a heading inside an HTML comment does not end the miss part
      ($l) = () if $comment[$j];    # a heading inside a comment
---

=== a report with no LOG accepted | method/scripts/method/lib/report.pl | a report with no LOG is a usage error
the numbers come from') unless @logs;
---
the numbers come from') unless 1;
=== an unreadable log skipped | method/scripts/method/lib/report.pl | a log that cannot be read exits 2
  open my $f, '<', $p or stop("could not read $what $p: $!");
---
  open my $f, '<', $p or return '';
=== a folder read as a log | method/scripts/method/lib/report.pl | a folder given as a log exits 2
  stop("could not read $what $p: not a file") if -e $p && !-f $p;
---

=== the report taken as its own log | method/scripts/method/lib/report.pl | the report given as its own log exits 2
    stop("the log $l is the report itself") if same($report, $l);
---

=== an option taken for the report | method/scripts/method/lib/report.pl | an option is a usage error
  for (@ARGV) { usage(': it takes no options') if /\A-/ }
---

=== the output not escaped | method/scripts/method/lib/report.pl | a file name's control characters are shown escaped
sub say_line { print Esc::line("report-check: $_[0]"), "\n" }
---
sub say_line { print "report-check: $_[0]\n" }
=== a listed report exits 0 | method/scripts/method/lib/report.pl | every problem is listed and exits 1
    exit 1;
  }
---
    exit 0;
  }
=== the wrapper turns exit 1 into 2 | method/scripts/method/report-check.sh | a number in no log is listed
  0 | 1 | 2) exit "$st" ;;
---
  0 | 2) exit "$st" ;;
PLANTS-END
plant_data "$work/plants.txt" tests/report-check.test.sh only
drop_sandbox "$work" || true
echo "plants: report-check: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
