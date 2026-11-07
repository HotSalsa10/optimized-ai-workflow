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
# variable cannot hold one), a printed number that cannot print exactly or
# in full, JSON::PP missing, or perl's taint mode switched on through
# PERL5OPT.
#
# Numbers print exactly or not at all. Numbers with a fraction or an
# exponent print with all their digits (as exact decimals, so 1e3 prints as
# 1000). A number with an exponent beyond 10000 either way, or an integer
# that JSON::PP can only read as a floating-point number (one of 20
# characters, minus sign included, outside -9223372036854775808 to
# 18446744073709551615 on a 64-bit perl), exits 2.
#
# Run it as "perl json.pl": switches given to perl itself (-M, -C) are the
# caller's choice and are not undone. A module loaded through PERL5OPT (such
# as -MO=Deparse) runs before the first line here, so a caller that cannot
# trust its environment unsets PERL5OPT first, as review-packet.sh does.
#
# Known limits: duplicate keys keep the last value, as JavaScript's
# JSON.parse does. A string that reads like another value ("true", "null",
# "12") prints the same as that value, and $( ) drops a string's trailing
# newlines.
use strict;
use warnings;

# PERL5OPT and PERL_UNICODE change how perl reads and computes (-C, -Mbigint,
# -Minteger), and PERL5LIB and PERLLIB could put another JSON::PP in place,
# so the helper starts again without them.
if (grep { defined $ENV{$_} } qw(PERL5OPT PERL_UNICODE PERL5LIB PERLLIB)) {
  if (${^TAINT} == 1) {    # taint mode (-T) forbids starting perl again
    print STDERR "json: perl's taint mode (-T) is on through PERL5OPT; run json.pl without it\n";
    exit 2;
  }
  delete @ENV{qw(PERL5OPT PERL_UNICODE PERL5LIB PERLLIB)};
  exec { $^X } $^X, $0, @ARGV or do {
    print STDERR "json: cannot start perl again\n";
    exit 2;
  };
}

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

my $json = JSON::PP->new->utf8->allow_nonref->canonical->allow_bignum;
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

# Every number in the printed value prints exactly and in full: JSON::PP
# reads a short integer outside the 64-bit range as a floating-point
# number, which prints rounded in exponent form, and a large exponent would
# print as millions of digits.
my @todo = ($node);
while (@todo) {
  my $v = shift @todo;
  if (ref $v eq 'HASH') {
    push @todo, values %$v;
  } elsif (ref $v eq 'ARRAY') {
    push @todo, @$v;
  } elsif (ref $v eq 'Math::BigFloat') {
    fail(2, 'a number has an exponent beyond 10000, too long to print in full') if abs($v->exponent) > 10000;
  } elsif (defined $v && !ref $v && $v =~ /[eE]/ && $json->encode($v) =~ /\A-?[0-9]/) {
    fail(2, 'an integer outside the 64-bit range cannot be printed exactly');
  }
}

my $out;
if (ref $node || !defined $node) {
  $out = $json->encode($node);    # object, array, true, false, null, exact number
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
print $out, "\n";
close STDOUT or fail(2, 'cannot write the output');    # also catches a failed print
exit 0;
