#!/usr/bin/env perl
# read.pl init FIELD FILE: prints FIELD of the client's init event in FILE
# (stream-json output, one JSON object per line). A list prints one item per
# line. Exit 1 when there is no init event or no such field.
# read.pl req CONV TEXT DIR: exit 0 when a request the fake logged in DIR
# (req-NNN.json) for its conversation CONV holds TEXT in what the client
# sent: the system text or a message that is not the assistant's (the fake's
# own scripted words come back as assistant messages). Never shipped.
use strict;
use warnings;
use JSON::PP;
my ($what, $field, $file) = @ARGV;
if (($what // '') eq 'req' && @ARGV == 4) {
  my ($conv, $text, $dir) = @ARGV[1 .. 3];
  opendir my $d, $dir or exit 1;
  for my $n (sort grep { /\Areq-[0-9]+\.json\z/ } readdir $d) {
    open my $h, '<', "$dir/$n" or next;
    my $r = eval { local $/; JSON::PP->new->utf8->decode(<$h>) } or next;
    next unless ref $r eq 'HASH' && ($r->{info} // '') =~ /\Aconv=\Q$conv\E /;
    my $b = $r->{body};
    next unless ref $b eq 'HASH';
    my $sent = JSON::PP->new->canonical->encode([$b->{system}, grep { ref $_ eq 'HASH' && ($_->{role} // '') ne 'assistant' } @{ $b->{messages} || [] }]);
    exit 0 if index($sent, $text) >= 0;
  }
  exit 1;
}
die "usage: read.pl init FIELD FILE | read.pl req CONV TEXT DIR\n" unless defined $file && $what eq 'init';
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
