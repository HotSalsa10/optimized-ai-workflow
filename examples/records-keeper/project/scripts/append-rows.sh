#!/usr/bin/env bash
# append-rows.sh FROM TO: adds the rows of the ledger FROM, without its
# header, to the end of TO, skipping each row TO already holds, so a row is
# never posted twice. post-rows.sh runs it through the method's live-write
# helper; it is not meant to be run on its own.
set -u
# shellcheck disable=SC2016 # perl code, expanded by perl
perl -e '
  my ($from, $to) = @ARGV;
  my %have;
  if (open my $t, "<", $to) {
    while (my $l = <$t>) { $l =~ s/\r?\n\z//; $have{$l} = 1 }
    close $t;
  }
  open my $f, "<", $from or die "append-rows: cannot read $from\n";
  my $head = <$f>;
  my ($rows, @new) = (0);
  while (my $l = <$f>) { $l =~ s/\r?\n\z//; $rows++; push @new, $l unless $have{$l}++ }
  close $f;
  open my $o, ">>", $to or die "append-rows: cannot write $to\n";
  print $o "$_\n" for @new;
  close $o or die "append-rows: cannot write $to\n";
  print "append-rows: added " . scalar(@new) . " of $rows rows; the rest were there already\n";' "$1" "$2"
