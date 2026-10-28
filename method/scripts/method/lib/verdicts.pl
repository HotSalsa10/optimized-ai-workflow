#!/usr/bin/env perl
# The one reader of verdicts.txt (rule M039: one vocabulary file; rule M048:
# one rule, one implementation). Scripts run it; perl helpers load it with
# require and call Verdicts::rows.
#
# Usage:
#   perl verdicts.pl words KIND   prints the words of one kind, one per line
#                                 (KIND: verdict, trailer-key, trailer,
#                                 trailer-reason)
# Exit 2: bad usage, or verdicts.txt is missing or malformed (the message
# names the line).
package Verdicts;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;

my %kinds = map { $_ => 1 } qw(verdict trailer-key trailer trailer-reason);

# rows: the file's entries in order, each [KIND, WORDS, MEANING]. Dies with
# a message when the file is missing or malformed.
sub rows {
  my $path = File::Spec->catfile(dirname(dirname(File::Spec->rel2abs(__FILE__))), 'verdicts.txt');
  open my $fh, '<:raw', $path or die "cannot read verdicts.txt\n";
  my (@rows, %count);
  my $n = 0;
  while (my $line = <$fh>) {
    $n++;
    $line =~ s/\r?\n\z//;    # a copy checked out with CRLF line ends reads the same
    next if $line eq '' || $line =~ /\A#/;
    my @f = split /\t/, $line, -1;
    die "verdicts.txt line $n: expected KIND<TAB>WORDS<TAB>MEANING with a known KIND\n"
      unless @f == 3 && $kinds{ $f[0] } && $f[1] =~ /\A[A-Za-z][A-Za-z -]*[A-Za-z]\z/ && $f[2] =~ /\S/ && $f[2] !~ /[\x00-\x1F\x7F]/;
    $count{ $f[0] }++;
    die "verdicts.txt line $n: $f[0] $f[1] is listed twice\n" if $count{"$f[0]\t$f[1]"}++;
    push @rows, [@f];
  }
  close $fh;
  die "verdicts.txt: expected exactly one trailer-key line\n" unless ($count{'trailer-key'} || 0) == 1;
  die "verdicts.txt: expected at least one verdict line\n" unless $count{verdict};
  return @rows;
}

sub main {
  binmode STDOUT, ':raw';
  binmode STDERR, ':raw';
  my ($cmd, $kind, @rest) = @ARGV;
  unless (defined $cmd && $cmd eq 'words' && defined $kind && $kinds{$kind} && !@rest) {
    print STDERR "verdicts: usage: verdicts.pl words verdict|trailer-key|trailer|trailer-reason\n";
    exit 2;
  }
  my @rows = eval { rows() };
  if (!@rows) { print STDERR "verdicts: $@"; exit 2 }
  print "$_->[1]\n" for grep { $_->[0] eq $kind } @rows;
  close STDOUT or exit 2;
  exit 0;
}

main() unless caller;
1;
