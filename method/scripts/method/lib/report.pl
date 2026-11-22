#!/usr/bin/env perl
# report-check's work (M126, SPEC R8), started by report-check.sh, which
# documents the output and the exit codes. Read-only.
#
# Report::numbers(TEXT) is the one reading of what a number is, used for
# the report and for every log alike (M048): a list of [LINE, NUMBER], the
# number exactly as written. Each line is cut into pieces at spaces and at
# the marks ( ) [ ] { } < > " ` * = | ; and at the no-break, thin and
# other wide spaces, the en and em dashes, curly quotes, the bullet and
# the ellipsis; then the marks ' _ ~ that
# open a piece and ' _ . , : ! ? that close it are dropped. A piece is a
# number only when all of it is one ($NUMBER), so a digit inside an ID, a
# hash, a path, a version or a date is never one. A piece made only of
# numbers joined by / or - (40/44, 3-5) is those numbers, unless it is a
# date written so: a four-digit year first or last (2026-11-22, 22/11/2026,
# 2026-11); 12/30 is two numbers. Beside a month's name, a date is a day
# (1 to 31) before it (22 November), a day after it followed by a comma or
# a year (November 22, 2026), or a year after it or after its day (March
# 2026, 22 November 2026); so "March 14 tests" is a number. The first
# number of a line that opens with a list or heading marker (1. or 2)
# after any # or >) is that marker.
#
# Report::miss_problems(TEXT): what is wrong with the "What the checks
# would miss" part, one plain line each; none when it is there and says
# something. HTML comments are not text; a part whose every line says
# only "nothing", "none" or "n/a" (brackets, quotes, emphasis, list marks
# and closing . ! ; , : dropped) says nothing.
package Report;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;
use Cwd qw(abs_path);

my $lib = dirname(File::Spec->rel2abs(__FILE__));
if (!eval { require File::Spec->catfile($lib, 'esc.pl'); 1 }) {
  (my $e = $@) =~ s/[^\x20-\x7e]+/ /g;
  print "report-check: FAIL - could not check: a library of the method did not load: $e\n";
  exit 2;
}

my $HEADING = 'what the checks would miss';
my %SAYS_NOTHING = map { $_ => 1 } qw(nothing none n/a);

# the marks a number may carry, as UTF-8 bytes
my $SIGN = qr/(?:[+-]|\xE2\x88\x92)/;                   # + - U+2212
my $CUR = qr/(?:\$|\xE2\x82\xAC|\xC2\xA3|\xC2\xA5)/;    # $ EUR GBP JPY signs
our $NUMBER = qr/\A$SIGN?$CUR?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?(?:%|$CUR)?\z/;
my $MONTH = qr/\A(?:January|February|March|April|May|June|July|August|September|October|November|December
  |Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\z/x;
my $DAY = qr/\A(?:0?[1-9]|[12]\d|3[01])\z/;
my $YEAR = qr/\A(?:19|20)\d\d\z/;
# what joins numbers into one piece, and a date written with it
my $JOIN = qr{[/-]};
my $JOINED_DATE = qr{\A(?:\d{4}([/-])\d{1,2}(?:\1\d{1,2})?|\d{1,2}([/-])\d{1,2}\2\d{4})\z};
# where a line is cut: spaces and marks; U+00A0, U+2000 to U+200A and
# U+202F (spaces); U+2012 to U+2015 (dashes); U+2018 to U+201F, U+2022 and
# U+2026 (quotes, the bullet, the ellipsis)
my $CUT = qr/(?:[ \t\r\f\x0B()\[\]{}<>"`*=|;]|\xC2\xA0|\xE2\x80[\x80-\x8A\xAF]|\xE2\x80[\x92-\x95]|\xE2\x80[\x98-\x9F\xA2\xA6])+/;
# dashes and spaces that are no word in the miss part
my $NO_WORD = qr/(?:\xC2\xA0|\xE2\x80[\x80-\x8A\xAF\x92-\x95])+/;
my $LIST_MARK = qr/\A[ \t]*(?:(?:#{1,6}|>)[ \t]+)*\d+[.)][ \t]/;

sub say_line { print Esc::line("report-check: $_[0]"), "\n" }

sub stop {
  say_line("could not check: $_[0]");
  say_line('FAIL - could not check');
  exit 2;
}

sub usage {
  say_line("usage: report-check.sh REPORT LOG...$_[0]");
  exit 2;
}

# joined PIECE: the numbers of a piece made only of numbers joined by / or
# - (40/44 is 40 and 44, -2-44 is -2 and 44); none for any other piece and
# for a date written so
sub joined {
  my ($x) = @_;
  my $sign = $x =~ s/\A($SIGN)// ? $1 : '';
  return () unless $x =~ $JOIN;
  my @parts = split $JOIN, $x, -1;
  return () if grep { $_ !~ $NUMBER } @parts;
  return () if $x =~ $JOINED_DATE;
  $parts[0] = $sign . $parts[0];
  return @parts;
}

# date PIECES I COMMA: the number at I is part of a date beside a month's
# name; COMMA: a comma closed it
sub date {
  my ($p, $i, $comma) = @_;
  my ($x, $before, $after) = ($p->[$i], $i > 0 ? $p->[$i - 1] : '', $i < $#$p ? $p->[$i + 1] : '');
  return 1 if $x =~ $DAY && $after =~ $MONTH;
  return 1 if $x =~ $DAY && $before =~ $MONTH && ($comma || $after =~ $YEAR);
  return 1 if $x =~ $YEAR && $before =~ $MONTH;
  return 1 if $x =~ $YEAR && $i > 1 && $p->[$i - 2] =~ $MONTH && $before =~ $DAY;
  return 0;
}

sub numbers {
  my ($text) = @_;
  my @out;
  my $n = 0;
  for my $line (split /\n/, Esc::plain($text), -1) {
    $n++;
    my (@p, @comma);
    for (split $CUT, $line) {
      my $x = $_;
      $x =~ s/\A['_~]+//;
      my $close = $x =~ s/(['_.,:!?]+)\z// ? $1 : '';
      next unless length $x;
      push @p, $x;
      push @comma, index($close, ',') >= 0;
    }
    my $marker = $line =~ $LIST_MARK;
    for my $i (0 .. $#p) {
      my @nums = $p[$i] =~ $NUMBER ? ($p[$i]) : joined($p[$i]);
      next unless @nums;
      if ($marker) {    # the line's first number is its marker
        $marker = 0;
        next;
      }
      next if @nums == 1 && $nums[0] eq $p[$i] && date(\@p, $i, $comma[$i]);
      push @out, map { [$n, $_] } @nums;
    }
  }
  return @out;
}

# heading LINE: (LEVEL, TEXT) of a markdown heading, else ()
sub heading {
  my ($l) = @_;
  return () unless $l =~ /\A {0,3}(#{1,6})(?:[ \t]+(.*?))?[ \t]*\z/;
  my ($level, $t) = (length $1, defined $2 ? $2 : '');
  $t =~ s/(?:\A|[ \t]+)#+\z//;
  return ($level, $t);
}

sub miss_problems {
  my ($text) = @_;
  my @lines = split /\n/, $text, -1;
  s/\r\z// for @lines;
  # which lines are inside a code block
  my (@code, $fence);
  for my $i (0 .. $#lines) {
    if (defined $fence) {
      $code[$i] = 1;
      undef $fence if $lines[$i] =~ /\A {0,3}(`{3,}|~{3,})[ \t]*\z/ && substr($1, 0, 1) eq substr($fence, 0, 1) && length $1 >= length $fence;
    } elsif ($lines[$i] =~ /\A {0,3}(`{3,}|~{3,})/) {
      $fence = $1;
      $code[$i] = 1;
    }
  }
  my (@problems, $found);
  for my $i (0 .. $#lines) {
    next if $code[$i];
    my ($level, $t) = heading($lines[$i]);
    next unless defined $level;
    $t =~ s/\A[*_ \t]+|[*_ \t]+\z//g;
    $t =~ s/[ \t]*:\z//;
    $t =~ s/[ \t]+/ /g;
    next unless lc $t eq $HEADING;
    $found = 1;
    my @body;
    for my $j ($i + 1 .. $#lines) {
      my ($l) = $code[$j] ? () : heading($lines[$j]);
      last if defined $l && $l <= $level;
      push @body, $lines[$j];
    }
    my $body = join "\n", @body;
    $body =~ s/<!--.*?-->//gs;
    $body =~ s/<!--(?:(?!-->).)*\z//s;    # a comment left open runs to the end
    my @said;
    for my $x (split /\n/, $body) {
      $x =~ s/\A[ \t]*(?:[-*+]|\d+[.)])[ \t]+//;
      $x =~ s/[*_`>#~()"']+//g;
      $x =~ s/$NO_WORD/ /g;
      $x =~ s/\s+/ /g;
      $x =~ s/\A | \z//g;
      $x =~ s/[.!;,:]+\z//;
      push @said, lc $x if $x =~ /[A-Za-z0-9\x80-\xff]/;
    }
    my $where = '"What the checks would miss" (line ' . ($i + 1) . ')';
    if (!@said) {
      push @problems, "$where has nothing under it";
    } elsif (!grep { !$SAYS_NOTHING{$_} } @said) {
      my %seen;
      push @problems, "$where says only \"" . join('", "', grep { !$seen{$_}++ } @said) . '"';
    }
  }
  push @problems, 'no "What the checks would miss" heading' unless $found;
  return @problems;
}

# read_file PATH WHAT: its bytes, or a stop naming WHAT
sub read_file {
  my ($p, $what) = @_;
  stop("could not read $what $p: not a file") if -e $p && !-f $p;
  open my $f, '<', $p or stop("could not read $what $p: $!");
  binmode $f;
  local $/;
  my $t = <$f>;
  close $f;
  stop("could not read $what $p") unless defined $t;
  return $t;
}

# same PATH PATH: the two name one file
sub same {
  my ($x, $y) = @_;
  my @sa = stat $x;
  my @sb = stat $y;
  return 1 if @sa && @sb && $sa[1] && $sa[0] == $sb[0] && $sa[1] == $sb[1];
  my ($ra, $rb) = (abs_path($x), abs_path($y));
  return defined $ra && defined $rb && $ra eq $rb;
}

sub main {
  usage('') unless @ARGV;
  for (@ARGV) { usage(': it takes no options') if /\A-/ }
  my ($report, @logs) = @ARGV;
  usage(': give at least one LOG, the logs the numbers come from') unless @logs;
  my $text = read_file($report, 'the report');
  my %have;
  for my $l (@logs) {
    stop("the log $l is the report itself") if same($report, $l);
    $have{$_->[1]} = 1 for numbers(read_file($l, 'the log'));
  }
  my @nums = numbers($text);
  my @listed;
  for (@nums) {
    push @listed, "not in any log: $_->[1] (line $_->[0])" unless $have{$_->[1]};
  }
  push @listed, miss_problems($text);
  say_line($_) for @listed;
  if (@listed) {
    say_line('FAIL - ' . scalar(@listed) . ' listed');
    exit 1;
  }
  say_line('PASS - ' . scalar(@nums) . (@nums == 1 ? ' number' : ' numbers') . ', each in a log ('
      . scalar(@logs) . (@logs == 1 ? ' log' : ' logs') . ' read); "What the checks would miss" says something');
  exit 0;
}

main() unless caller;
1;
