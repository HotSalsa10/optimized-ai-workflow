#!/usr/bin/env perl
# Checks docs/rule-map.md. Called by scripts/dev/check-rule-map.sh.
# Usage: perl rule-map.pl MAP_FILE
# Prints one line per problem, then "ROWS n", "BAD n" and "SUMMARY ...".
use strict;
use warnings;

# Prints one line of output. Control characters taken from file names or
# content (also UTF-8 C1 controls) are shown as \xNN, and the CI runner's
# old command form (## [) is broken up, so text from a file cannot start a
# new line of output, move the cursor or reach the CI runner as a command.
# (Every line starts with this check's name, so it never starts with "::".)
sub say_line {
  my ($s) = @_;
  $s =~ s/([\x00-\x1F\x7F])/sprintf('\\x%02X', ord $1)/ge;
  $s =~ s/\xC2([\x80-\x9F])/sprintf('\\xC2\\x%02X', ord $1)/ge;
  $s =~ s/##\[/#\\x23[/g;
  print "$s\n";
}

my $map = shift @ARGV;
open my $fh, '<', $map or die "cannot read $map\n";
my (%seen, %by_status);
my ($rows, $bad, $n) = (0, 0, 0);
while (my $line = <$fh>) {
  $n++;
  next unless $line =~ /^\s*\|/;           # a table row, even if indented
  $line =~ s/^\s+//;
  next if $line =~ /^\|\s*ID\s*\|/;          # header row
  next if $line =~ /^\|[\s:|-]+\|\s*$/;      # separator row
  $rows++;
  my @c = map { my $x = $_; $x =~ s/^\s+|\s+$//g; $x } split /\|/, $line;
  shift @c;
  my ($id, $rule, $source, $home, $status) = @c;
  if (!defined $status || $status eq '' || !defined $home || $home eq '') {
    say_line("rule-map: line $n has missing columns"); $bad++; next;
  }
  if ($id !~ /^M\d{3}$/) { say_line("rule-map: line $n has a malformed rule ID '$id'"); $bad++; next; }
  if ($seen{$id}++) { say_line("rule-map: $id appears more than once"); $bad++; }
  if ($status !~ /^(?:done|step \d+|R2|later)$/) { say_line("rule-map: $id has unknown status '$status'"); $bad++; next; }
  my $key = $status =~ /^step/ ? 'planned for a later step' : $status;
  $by_status{$key}++;
  next unless $status eq 'done';
  my ($file, $token) = split /\s+@/, $home, 2;
  $token = $id unless defined $token && length $token;
  1 while $file =~ s{(^|/)\./}{$1};    # ./docs/x.md and docs/./x.md name docs/x.md
  if ($file eq $map) { say_line("rule-map: $id names the rule map itself as its home; a rule needs a real home"); $bad++; next; }
  if (!-f $file) { say_line("rule-map: $id is marked done but its home $file does not exist"); $bad++; next; }
  open my $h, '<', $file or do { say_line("rule-map: cannot read $file"); $bad++; next };
  local $/;
  my $text = <$h>;
  close $h;
  if (index($text, $token) < 0) { say_line("rule-map: $id is marked done but '$token' is not in $file"); $bad++; }
}
close $fh;
my $summary = join ', ', map { "$by_status{$_} $_" } sort keys %by_status;
print "ROWS $rows\nBAD $bad\nSUMMARY $summary\n";
