#!/usr/bin/env bash
# check-ledger.sh: checks ledger.csv. Every row after the header has three
# fields: an item, an amount in whole cents and a date (YYYY-MM-DD).
# Prints "ledger: N rows checked" and exits 0 only when every row is right.
set -u
here=$(cd "$(dirname "$0")" && pwd)
ledger=${1:-$here/../ledger.csv}
# shellcheck disable=SC2016 # perl code, expanded by perl
perl -e '
  my ($rows, $bad) = (0, 0);
  my $head = <STDIN>;
  while (my $l = <STDIN>) {
    $l =~ s/\r?\n\z//;
    $rows++;
    my @f = split /,/, $l, -1;
    next if @f == 3 && length $f[0] && $f[1] =~ /\A\d+\z/ && $f[2] =~ /\A\d{4}-\d\d-\d\d\z/;
    $bad++;
    print "check-ledger: row $rows is not item,cents,date: $l\n";
  }
  print "ledger: $rows rows checked\n";
  exit($bad ? 1 : 0);' <"$ledger"
