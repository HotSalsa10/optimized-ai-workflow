#!/usr/bin/env perl
# read.pl init FIELD FILE: prints FIELD of the client's init event in FILE
# (stream-json output, one JSON object per line). A list prints one item per
# line. Exit 1 when there is no init event or no such field. Never shipped.
use strict;
use warnings;
use JSON::PP;
my ($what, $field, $file) = @ARGV;
die "usage: read.pl init FIELD FILE\n" unless defined $file && $what eq 'init';
open my $f, '<', $file or exit 1;
while (my $l = <$f>) {
  my $o = eval { JSON::PP->new->utf8->decode($l) } or next;
  next unless ref $o eq 'HASH' && ($o->{type} || '') eq 'system' && ($o->{subtype} || '') eq 'init';
  exit 1 unless exists $o->{$field};
  my $v = $o->{$field};
  binmode STDOUT, ':utf8';
  print ref $v eq 'ARRAY' ? join('', map { "$_\n" } @$v) : (ref $v ? encode_json($v) : "$v\n");
  exit 0;
}
exit 1;
