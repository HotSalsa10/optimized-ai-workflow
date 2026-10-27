#!/usr/bin/env bash
# Checks docs/rule-map.md, the list of every rule of the method and its home.
# - Every row has an ID like M001, a rule, a source, a home and a status.
# - IDs are unique.
# - Status is one of: done, step N, R2, later.
# - A rule marked done names a home file that exists and contains the rule's
#   ID (or the token written after "@" in the home column).
# A rule that lives in two places is a defect (M048), so each rule has one home.
set -u

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "rule-map: FAIL - not inside a git repository"
  exit 2
}
cd "$root" || exit 2
map="docs/rule-map.md"
[ -f "$map" ] || {
  echo "rule-map: FAIL - $map is missing"
  exit 1
}

prog=$(cat <<'PERL'
use strict;
use warnings;
my $map = shift @ARGV;
open my $fh, '<', $map or die "cannot read $map\n";
my (%seen, %by_status);
my ($rows, $bad) = (0, 0);
while (my $line = <$fh>) {
  next unless $line =~ /^\|\s*M\d/;
  $rows++;
  my @c = map { s/^\s+|\s+$//gr } split /\|/, $line;
  shift @c;
  my ($id, $rule, $source, $home, $status) = @c;
  if (!defined $status || $status eq '') { print "rule-map: row $rows has missing columns\n"; $bad++; next; }
  if ($id !~ /^M\d{3}$/) { print "rule-map: bad ID '$id'\n"; $bad++; next; }
  if ($seen{$id}++) { print "rule-map: $id appears more than once\n"; $bad++; }
  if ($status !~ /^(?:done|step \d+|R2|later)$/) { print "rule-map: $id has unknown status '$status'\n"; $bad++; next; }
  my $key = $status =~ /^step/ ? 'planned for a later step' : $status;
  $by_status{$key}++;
  next unless $status eq 'done';
  my ($file, $token) = split /\s+@/, $home, 2;
  $token = $id unless defined $token && length $token;
  if (!-f $file) { print "rule-map: $id is marked done but its home $file does not exist\n"; $bad++; next; }
  open my $h, '<', $file or do { print "rule-map: cannot read $file\n"; $bad++; next };
  local $/; my $text = <$h>; close $h;
  if (index($text, $token) < 0) { print "rule-map: $id is marked done but '$token' is not in $file\n"; $bad++; }
}
my $summary = join ', ', map { "$by_status{$_} $_" } sort keys %by_status;
print "ROWS $rows\nBAD $bad\nSUMMARY $summary\n";
PERL
)

out=$(perl -e "$prog" "$map") || {
  echo "rule-map: FAIL - the check itself did not run"
  exit 2
}
rows=$(printf '%s\n' "$out" | sed -n 's/^ROWS //p')
bad=$(printf '%s\n' "$out" | sed -n 's/^BAD //p')
summary=$(printf '%s\n' "$out" | sed -n 's/^SUMMARY //p')
printf '%s\n' "$out" | grep -v -e '^ROWS ' -e '^BAD ' -e '^SUMMARY '

if [ "${rows:-0}" -eq 0 ]; then
  echo "rule-map: FAIL - found 0 rules in $map; nothing was checked"
  exit 1
fi
if [ "${bad:-0}" -gt 0 ]; then
  echo "rule-map: FAIL - $bad problem(s) in $rows rules"
  exit 1
fi
echo "rule-map: PASS - $rows rules ($summary); every rule marked done was found in its home"
