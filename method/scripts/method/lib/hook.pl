#!/usr/bin/env perl
# The hooks' input and output (step 5). Loaded with require by each hook's
# perl part; nothing runs when it is loaded. It needs lib/json.pl and
# lib/esc.pl, which it loads from its own folder.
#
# Exit codes: a hook's perl part ends with 0 (go on) or $Hook::BLOCK (3),
# never 2 itself. Its sh wrapper turns 3 into 2, which blocks, and treats
# any other code as a crash. perl exits 2 on its own when it dies after a
# failed file call or cannot load a library, and a SubagentStop hook that
# exits 2 sends the agent back to work, so 2 must never mean "block" by
# accident.
#
#   Hook::read_input([FH, [MAX]]) reads the hook's JSON input once, at most
#     MAX bytes (4 MB): (HASH, undef), or (undef, REASON) when it cannot be
#     read, is empty, is too large, is not UTF-8 or JSON (Json::decode), or
#     is not a JSON object. A hook that cannot read its input decides for
#     itself what that means (the guard refuses).
#   Hook::clean(TEXT) gives TEXT as one safe line, in characters: every
#     control or invisible character escaped (Esc::line), so text taken from
#     the input cannot split a line, move the cursor or reach a terminal as
#     a control code, even after a JSON reader decodes it again; and "No
#     such file" and "No such directory" broken up as "No-such file", since
#     a Stop-type hook that blocks with stderr saying a file is missing is
#     treated as not blocking.
#   Hook::block(TEXT) prints TEXT as one clean line on stderr (the reason
#     Claude Code shows) and returns $Hook::BLOCK.
#   Hook::warning(TEXT) prints {"systemMessage": TEXT} on stdout (shown to the
#     owner) and returns 0.
#   Hook::context(LINE...) prints each LINE, clean, on stdout (added to
#     Claude's context on exit 0) and returns 0.
#   Hook::json(HASH) prints HASH as JSON on stdout (a hook's decision
#     object) and returns 0; its strings are cleaned first.
package Hook;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;

my $here = dirname(File::Spec->rel2abs(__FILE__));
require File::Spec->catfile($here, 'esc.pl');
require File::Spec->catfile($here, 'json.pl');

our $BLOCK = 3;
our $MAX = 4 * 1024 * 1024;

sub read_input {
  my ($fh, $max) = @_;
  $fh = \*STDIN unless defined $fh;
  $max = $MAX unless defined $max;
  binmode $fh, ':raw';
  my $buf = '';
  while (1) {
    my $n = read $fh, $buf, 65536, length $buf;
    return (undef, "cannot read the input ($!)") unless defined $n;
    last if $n == 0;
    return (undef, "the input is over $max bytes") if length $buf > $max;
  }
  return (undef, 'the input is empty') unless length $buf;
  my ($data, $err) = Json::decode($buf);
  return (undef, $err) if defined $err;
  return (undef, 'the input is not a JSON object') unless ref $data eq 'HASH';
  return ($data, undef);
}

sub clean {
  my ($t) = @_;
  $t = '' unless defined $t;
  utf8::encode($t) if utf8::is_utf8($t);
  my $s = Esc::line($t);
  utf8::decode($s);
  $s =~ s/\b(no)\s+(such)\s+(file|directory)/$1-$2 $3/gi;
  return $s;
}

sub bytes {
  my ($s) = @_;
  utf8::encode($s);
  return $s;
}

sub block {
  binmode STDERR, ':raw';
  print STDERR bytes(clean($_[0])), "\n";
  return $BLOCK;
}

sub warning {
  return json({ systemMessage => $_[0] });
}

sub context {
  binmode STDOUT, ':raw';
  print STDOUT bytes(clean($_)), "\n" for @_;
  return 0;
}

# every string in DATA cleaned, keys included
sub cleaned {
  my ($d) = @_;
  return { map { (clean($_) => cleaned($d->{$_})) } keys %$d } if ref $d eq 'HASH';
  return [map { cleaned($_) } @$d] if ref $d eq 'ARRAY';
  return $d if ref $d || !defined $d;
  return $d if $d =~ /\A-?[0-9]+(?:\.[0-9]+)?\z/;    # a number stays a number
  return clean($d);
}

sub json {
  binmode STDOUT, ':raw';
  print STDOUT Json::encode(cleaned($_[0])), "\n";
  return 0;
}

1;
