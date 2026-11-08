#!/usr/bin/env perl
# The hooks' input and output (step 5). Loaded with require by each hook's
# perl part; nothing runs when it is loaded. It needs lib/json.pl and
# lib/esc.pl, which it loads from its own folder (once, also when another
# helper already loaded them by another spelling of the path).
#
# Exit codes: a hook's perl part ends with 0 (go on) or $Hook::BLOCK (3),
# never 2 itself. Its sh wrapper turns 3 into 2, which blocks, and treats
# any other code as a crash. perl exits 2 on its own when it dies after a
# failed file call or cannot load a library, and a SubagentStop hook that
# exits 2 sends the agent back to work, so 2 must never mean "block" by
# accident. perl can also exit 3 on its own (a die after a failed kill, or
# after a child that exited 3), so an END block turns any exit 3 that
# Hook::block did not ask for into 70, a crash; and an exit 0 after
# Hook::block into 3, so a refusal whose code was dropped still refuses.
#
# The sh wrapper (step 5.4) must start perl without the variables that
# change what perl runs or reads (every PERL* variable, among them
# PERL5OPT, PERL5LIB, PERLLIB, PERL5DB and PERLIO), with "command perl".
#
#   Hook::read_input([FH, [MAX]]) reads the hook's JSON input once, at most
#     MAX bytes (4 MB): (HASH, undef), or (undef, REASON) when it cannot be
#     read, is empty, is too large, is not UTF-8 or JSON (Json::decode), or
#     is not a JSON object. Numbers come back as perl's own ("plain"). A
#     hook that cannot read its input decides for itself what that means
#     (the guard refuses).
#   Hook::clean(TEXT) gives TEXT as one safe line, in characters: every
#     control or invisible character but TAB escaped (Esc::line), so text
#     taken from the input cannot split a line, move the cursor or reach a
#     terminal as a control code, even after a JSON reader decodes it again.
#     The words a Stop-type hook's stderr must not hold are broken up
#     wherever they stand ("No such file" as "No- such file", "can't open"
#     as "can-t open"): Claude Code 2.1.319 treats an exit 2 from such a
#     hook as not blocking when its stderr matches /no such file|can't open/i.
#   Hook::block(TEXT...) prints its texts, joined by a space, as one clean
#     line on stderr (the reason Claude Code shows) and returns
#     $Hook::BLOCK.
#   A hook answers on stdout once per run, with one of these (a second one
#     dies, as two JSON objects would be read as neither):
#   Hook::warning(TEXT...) prints {"systemMessage": TEXT} (shown to the
#     owner), several texts joined by "; ", and returns 0.
#   Hook::context(LINE...) prints each LINE, clean, as plain text and
#     returns 0. Claude Code adds plain stdout to Claude's context on exit 0
#     for SessionStart, UserPromptSubmit, UserPromptExpansion and
#     PostModelSwitch only; SubagentStart takes it through Hook::json, as
#     hookSpecificOutput's additionalContext. Claude Code trims the whole
#     output (JavaScript's trim) and reads it as the hook's JSON answer when
#     it then opens with "{", so that first "{" is written as \x7B, also
#     after blank lines.
#   Hook::json(HASH) prints HASH as JSON (a hook's decision object) and
#     returns 0. Its keys and strings are cleaned first; its numbers and
#     JSON true and false keep their type (a number perl has ever used as
#     text, by printing or comparing it with eq, is a string: pass 0+$n).
package Hook;
use strict;
use warnings;
use B ();
use File::Basename qw(dirname);
use File::Spec;

# set before the helpers load, so the END block has them when a load fails
our ($BLOCK, $BLOCKED);
BEGIN { $BLOCK = 3; $BLOCKED = 0 }    # $BLOCKED: Hook::block was called in this run

my $here = dirname(File::Spec->rel2abs(__FILE__));
require File::Spec->catfile($here, 'esc.pl') unless defined &Esc::line;
require File::Spec->catfile($here, 'json.pl') unless defined &Json::decode;

our $MAX = 4 * 1024 * 1024;
our $SAID = 0;       # an answer went to stdout in this run

# an exit 3 that Hook::block did not ask for is a crash; an exit 0 after a
# refusal still refuses
END {
  $? = 70 if $? == $BLOCK && !$BLOCKED;
  $? = $BLOCK if $? == 0 && $BLOCKED;
}

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
  my ($data, $err) = Json::decode($buf, 'plain');
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
  $s =~ s/(no)(\s+such\s+(?:file|director))/$1-$2/gi;
  $s =~ s/(can)'(t\s+open)/$1-$2/gi;
  return $s;
}

sub bytes {
  my ($s) = @_;
  utf8::encode($s);
  return $s;
}

sub block {
  $BLOCKED = 1;
  binmode STDERR, ':raw';
  print STDERR bytes(clean(join ' ', map { defined $_ ? $_ : '' } @_)), "\n";
  return $BLOCK;
}

sub say_once {
  die "Hook: a hook answers on stdout once per run\n" if $SAID++;
  binmode STDOUT, ':raw';
}

sub warning {
  return json({ systemMessage => join('; ', @_) });
}

sub context {
  say_once();
  my @l = map { clean($_) } @_;
  return 0 unless @l;
  my $out = join "\n", @l;
  # JavaScript's trim: white space (Unicode's Zs among it) and line ends
  $out =~ s/\A([\t\n\r \x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}]*)\{/$1\\x7B/;
  print STDOUT bytes($out), "\n";
  return 0;
}

# a number perl holds as a number, never turned into text: JSON::PP writes
# it as a number. A value that ever held text is a string. The test reads
# perl's flags, so it does not turn the number into text itself (a match
# would, and old JSON::PP versions read that as a string).
sub is_number {
  my $f = B::svref_2object(\$_[0])->FLAGS;
  return ($f & (B::SVp_IOK() | B::SVp_NOK())) && !($f & B::SVp_POK());
}

# every string in DATA cleaned, keys included
sub cleaned {
  my ($d) = @_;
  return { map { (clean($_) => cleaned($d->{$_})) } keys %$d } if ref $d eq 'HASH';
  return [map { cleaned($_) } @$d] if ref $d eq 'ARRAY';
  return $d if ref $d || !defined $d || is_number($d);
  return clean($d);
}

sub json {
  my $out = Json::encode(cleaned($_[0]));
  say_once();
  print STDOUT $out, "\n";
  return 0;
}

1;
