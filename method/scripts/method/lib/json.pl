#!/usr/bin/env perl
# The method's only JSON helper. Core perl modules only (JSON::PP).
#
# Usage, with JSON on standard input:
#   perl json.pl get [KEY...]
# prints the value at KEY... Each KEY is an object key, or, on an array, an
# index (0, 1, 2 ... below the array's length). With no KEY it prints the
# whole input. A string is printed as it is, then one newline. A number,
# true, false or null is printed as JSON text, and an object or an array as
# compact JSON with sorted keys.
#
# Exit codes: 0 done; 1 the path does not exist; 2 bad usage, input that is
# not valid UTF-8 or not valid JSON, a string holding a NUL byte (a shell
# variable cannot hold one), a number out of range, or JSON::PP missing.
#
# Known limits: duplicate keys keep the last value, as JavaScript's
# JSON.parse does. The string "true" and the value true print the same, and
# $( ) drops a string's trailing newlines. On old perl, integers of more than
# about 18 digits come back as strings.
use strict;
use warnings;

# Raw handles, whatever PERL_UNICODE or PERL5OPT asked for, so the bytes in
# are the bytes JSON::PP sees and the bytes out are UTF-8.
binmode STDIN, ':raw';
binmode STDOUT, ':raw';
binmode STDERR, ':raw';

sub fail {
  my ($code, $msg) = @_;
  print STDERR "json: $msg\n";
  exit $code;
}

eval { require JSON::PP; 1 }
  or fail(2, "perl's JSON::PP module is missing; install it (on Linux, for example, the perl-JSON-PP or libjson-pp-perl package)");

my $cmd = shift @ARGV;
fail(2, 'usage: json.pl get [KEY...]') unless defined $cmd && $cmd eq 'get';

# KEYs as characters, to match the decoded keys. They arrive as bytes, or
# already as characters when PERL_UNICODE includes A.
my @keys = @ARGV;
for (@keys) {
  next if utf8::is_utf8($_);
  utf8::decode($_) or fail(2, 'a KEY is not valid UTF-8');
}

my $text = do { local $/; <STDIN> };
$text = '' unless defined $text;

# UTF-8 as RFC 3629 defines it, checked before JSON::PP sees the input:
# JSON::PP's own check differs between versions, and a NUL byte would make
# it guess UTF-16.
my $chars = $text;
fail(2, 'the input is not valid UTF-8 (or holds a NUL byte)')
  if index($text, "\0") >= 0 || !utf8::decode($chars) || $chars =~ /[\x{D800}-\x{DFFF}]|[^\x{0}-\x{10FFFF}]/;

my $json = JSON::PP->new->utf8->allow_nonref->canonical;
my $data = eval { $json->decode($text) };
if (!defined $data && $@) {
  my $err = $@;
  $err =~ s/,? \(before .*//s;    # it quotes the input, which may hold a secret
  $err =~ s/ at \S+ line \d+\.?\n?\z//;
  $err =~ s/[\x00-\x1F\x7F]/ /g;
  fail(2, 'not valid JSON: ' . substr($err, 0, 200));
}

my $node = $data;
for my $key (@keys) {
  if (ref $node eq 'HASH') {
    exit 1 unless exists $node->{$key};
    $node = $node->{$key};
  } elsif (ref $node eq 'ARRAY') {
    exit 1 unless $key =~ /\A(?:0|[1-9][0-9]*)\z/ && $key < @$node;
    $node = $node->[$key];
  } else {
    exit 1;    # a KEY on a string, number, true, false or null
  }
}

# finite: false for a number that is Inf or NaN anywhere in the value
sub finite {
  my ($v) = @_;
  return !grep { !finite($_) } values %$v if ref $v eq 'HASH';
  return !grep { !finite($_) } @$v if ref $v eq 'ARRAY';
  return 1 if !defined $v || ref $v;
  require B;
  my $flags = B::svref_2object(\$v)->FLAGS;
  return 1 if $flags & B::SVf_POK() || !($flags & (B::SVf_IOK() | B::SVf_NOK()));
  return $v * 0 == 0;
}
fail(2, 'a number is out of range') unless finite($node);

my $out;
if (ref $node || !defined $node) {
  $out = $json->encode($node);    # object, array, true, false, null
} else {
  my $enc = $json->encode($node);
  if ($enc =~ /\A"/) {
    $out = $node;
    utf8::encode($out);    # characters back to UTF-8 bytes
    fail(2, 'the value holds a NUL byte, which a shell variable cannot hold') if index($out, "\0") >= 0;
  } else {
    $out = $enc;           # a number
  }
}
print $out, "\n" or fail(2, 'cannot write the output');
close STDOUT or fail(2, 'cannot write the output');
exit 0;
