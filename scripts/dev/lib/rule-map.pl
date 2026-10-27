#!/usr/bin/env perl
# Checks docs/rule-map.md. Called by scripts/dev/check-rule-map.sh.
# Usage: perl rule-map.pl MAP_FILE
# Prints one line per problem, then "ROWS n", "BAD n" and "SUMMARY ...".
use strict;
use warnings;

my $map = shift @ARGV;
open my $fh, '<', $map or die "cannot read $map\n";
my (%seen, %by_status);
my ($rows, $bad, $n) = (0, 0, 0);
while (my $line = <$fh>) {
  $n++;
  next unless $line =~ /^\|/;
  next if $line =~ /^\|\s*ID\s*\|/;          # header row
  next if $line =~ /^\|[\s:|-]+\|\s*$/;      # separator row
  $rows++;
  my @c = map { my $x = $_; $x =~ s/^\s+|\s+$//g; $x } split /\|/, $line;
  shift @c;
  my ($id, $rule, $source, $home, $status) = @c;
  if (!defined $status || $status eq '' || !defined $home || $home eq '') {
    print "rule-map: line $n has missing columns\n"; $bad++; next;
  }
  if ($id !~ /^M\d{3}$/) { print "rule-map: line $n has a malformed rule ID '$id'\n"; $bad++; next; }
  if ($seen{$id}++) { print "rule-map: $id appears more than once\n"; $bad++; }
  if ($status !~ /^(?:done|step \d+|R2|later)$/) { print "rule-map: $id has unknown status '$status'\n"; $bad++; next; }
  my $key = $status =~ /^step/ ? 'planned for a later step' : $status;
  $by_status{$key}++;
  next unless $status eq 'done';
  my ($file, $token) = split /\s+@/, $home, 2;
  $token = $id unless defined $token && length $token;
  if ($file eq $map) { print "rule-map: $id names the rule map itself as its home; a rule needs a real home\n"; $bad++; next; }
  if (!-f $file) { print "rule-map: $id is marked done but its home $file does not exist\n"; $bad++; next; }
  open my $h, '<', $file or do { print "rule-map: cannot read $file\n"; $bad++; next };
  local $/;
  my $text = <$h>;
  close $h;
  if (index($text, $token) < 0) { print "rule-map: $id is marked done but '$token' is not in $file\n"; $bad++; }
}
close $fh;
my $summary = join ', ', map { "$by_status{$_} $_" } sort keys %by_status;
print "ROWS $rows\nBAD $bad\nSUMMARY $summary\n";
