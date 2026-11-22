#!/usr/bin/env perl
# report-check's work (M126, SPEC R8), started by report-check.sh, which
# documents the output and the exit codes. Read-only.
#
# Report::numbers(TEXT) is the one reading of what a number is, used for
# the report and for every log alike (M048): a list of [LINE, NUMBER], the
# number exactly as written. Each line is cut into pieces at spaces and at
# the marks ( ) [ ] { } < > " ` * = | ; then the marks ' _ ~ that open a
# piece and ' _ . , : ! ? that close it are dropped. A piece is a number
# only when all of it is one ($NUMBER), so a digit inside an ID, a hash, a
# path, a version or a date is never one. A one- or two-digit day or a
# four-digit year beside a month's name is a date; the first number of a
# line that opens with a list or heading marker (1. or 2) after any # or >)
# is that marker.
#
# Report::miss_problems(TEXT): what is wrong with the "What the checks
# would miss" part, one plain line each; none when it is there and says
# something.
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
my %SAYS_NOTHING = map { $_ => 1 } qw(nothing none);

# the marks a number may carry, as UTF-8 bytes
my $SIGN = qr/(?:[+-]|\xE2\x88\x92)/;                   # + - U+2212
my $CUR = qr/(?:\$|\xE2\x82\xAC|\xC2\xA3|\xC2\xA5)/;    # $ EUR GBP JPY signs
our $NUMBER = qr/\A$SIGN?$CUR?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?(?:%|$CUR)?\z/;
my $MONTH = qr/\A(?:January|February|March|April|May|June|July|August|September|October|November|December
  |Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\z/x;
my $DATE_PART = qr/\A(?:\d{1,2}|\d{4})\z/;
my $CUT = qr/[ \t\r\f\x0B()\[\]{}<>"`*=|;]+/;
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

sub numbers {
  my ($text) = @_;
  my @out;
  my $n = 0;
  for my $line (split /\n/, Esc::plain($text), -1) {
    $n++;
    my @p = grep { length } map {
      my $x = $_;
      $x =~ s/\A['_~]+//;
      $x =~ s/['_.,:!?]+\z//;
      $x
    } split $CUT, $line;
    my $marker = $line =~ $LIST_MARK;
    for my $i (0 .. $#p) {
      next unless $p[$i] =~ $NUMBER;
      if ($marker) {    # the line's first number is its marker
        $marker = 0;
        next;
      }
      next if $p[$i] =~ $DATE_PART
        && (($i > 0 && $p[$i - 1] =~ $MONTH)
        || ($i < $#p && $p[$i + 1] =~ $MONTH)
        || ($i > 1 && $p[$i - 2] =~ $MONTH && $p[$i - 1] =~ $DATE_PART));
      push @out, [$n, $p[$i]];
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
    my $say = join ' ', map {
      my $x = $_;
      $x =~ s/\A[ \t]*(?:[-*+]|\d+[.)])[ \t]+//;
      $x
    } @body;
    $say =~ s/[*_`>#~]+//g;
    $say =~ s/\s+/ /g;
    $say =~ s/\A | \z//g;
    $say =~ s/[.!]+\z//;
    my $where = '"What the checks would miss" (line ' . ($i + 1) . ')';
    if ($say eq '') {
      push @problems, "$where has nothing under it";
    } elsif ($SAYS_NOTHING{lc $say}) {
      push @problems, "$where says only \"" . lc($say) . '"';
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
