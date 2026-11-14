#!/usr/bin/env perl
# The one reader of verdicts.txt (rule M039: one vocabulary file; rule M048:
# one rule, one implementation). Scripts run it; perl helpers load it with
# require and call Verdicts::rows.
#
# Usage:
#   perl verdicts.pl words KIND   prints the words of one kind, one per line
#                                 (KIND: verdict, trailer-key, trailer,
#                                 trailer-reason, ready, gate-verdict,
#                                 gate-diagnosis, gate-test-result,
#                                 diagnosis, test-result, receipt, end-key)
#   perl verdicts.pl check-trailer
#                                 reads one commit message on standard input;
#                                 exit 0 when it ends with a valid trailer,
#                                 else exit 1 and the reason
# Exit 2: bad usage, or verdicts.txt is missing or malformed (the message
# names the line).
#
# Verdicts::trailer_problem(MESSAGE) is the one judge of a commit trailer
# (DECISIONS A10): undef for a valid message, else a plain reason. A valid
# message, read with CRLF as LF, has no other CR; blank lines (only spaces
# and tabs) split it into paragraphs, leading and trailing ones dropped; it
# has at least two paragraphs; the last paragraph is one line,
# "<trailer-key>: <trailer word>" or "<trailer-key>: <trailer-reason word>
# - <text>" where the text is UTF-8 and holds a letter or digit and no
# control, format or invisible character (trailing spaces and tabs are
# dropped); and no other line starts with "<trailer-key>:".
#
# Verdicts::gates(ROWS) is the one reading of the gate lines (DECISIONS
# A71): the gates, the checking agents gate-receipt watches, in file order,
# each [NAME, OPENING KIND], where the opening kind is the gate line's kind
# without "gate-": the kind of word the gate's report opens with. The
# receipt words are read by their place: the first means valid, the second
# invalid, the third incomplete; the file holds exactly three, and exactly
# one end-key word. No kind starts with "trailer" but the trailer kinds,
# which done-check finds by that prefix.
#
# Verdicts::judged(TIP, FROM) is the one rule for which commits on main's
# first-parent history carry a verdict that counts (DECISIONS A30); status
# and done-check use it. Callers load lib/git.pl first.
package Verdicts;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;

my @kinds = qw(verdict trailer-key trailer trailer-reason ready gate-verdict gate-diagnosis gate-test-result diagnosis test-result receipt end-key);
my %kinds = map { $_ => 1 } @kinds;

# rows: the file's entries in order, each [KIND, WORDS, MEANING]. Dies with
# a message when the file is missing or malformed. Read once per process.
my @rows_read;
sub rows {
  return @rows_read if @rows_read;
  my $path = File::Spec->catfile(dirname(dirname(File::Spec->rel2abs(__FILE__))), 'verdicts.txt');
  open my $fh, '<:raw', $path or die "cannot read verdicts.txt\n";
  local $/ = "\n";    # whatever the caller set
  my (@rows, %count);
  my $n = 0;
  while (my $line = <$fh>) {
    $n++;
    $line =~ s/\r?\n\z//;    # a copy checked out with CRLF line ends reads the same
    next if $line eq '' || $line =~ /\A#/;
    my @f = split /\t/, $line, -1;
    die "verdicts.txt line $n: expected KIND<TAB>WORDS<TAB>MEANING with a known KIND\n"
      unless @f == 3 && $kinds{ $f[0] } && $f[1] =~ /\A[A-Za-z][A-Za-z -]*[A-Za-z]\z/ && $f[2] =~ /\S/ && $f[2] !~ /[\x00-\x1F\x7F]/;
    die "verdicts.txt line $n: the gate name $f[1] must be lower-case letters and hyphens, as an agent's name is\n"
      if $f[0] =~ /\Agate-/ && $f[1] !~ /\A[a-z]+(?:-[a-z]+)*\z/;
    $count{ $f[0] }++;
    die "verdicts.txt line $n: $f[0] $f[1] is listed twice\n" if $count{"$f[0]\t$f[1]"}++;
    push @rows, [@f];
  }
  close $fh;
  die "verdicts.txt: expected exactly one trailer-key line\n" unless ($count{'trailer-key'} || 0) == 1;
  die "verdicts.txt: expected at least one verdict line\n" unless $count{verdict};
  my %alone = map { ($_->[1] => 1) } grep { $_->[0] eq 'trailer' } @rows;
  for my $r (grep { $_->[0] eq 'ready' } @rows) {
    die "verdicts.txt: the ready word $r->[1] is not a trailer word (a ready word stands alone)\n" unless $alone{ $r->[1] };
  }
  my @gates = gates(@rows);
  die "verdicts.txt: expected at least one gate line (gate-verdict, gate-diagnosis or gate-test-result)\n" unless @gates;
  my %gate;
  for my $g (@gates) {
    die "verdicts.txt: the gate $g->[0] stands under two gate kinds; a gate opens with one kind of word\n" if $gate{ $g->[0] }++;
    die "verdicts.txt: the gate $g->[0] opens with a $g->[1] word, but there is no $g->[1] line\n" unless $count{ $g->[1] };
  }
  die "verdicts.txt: expected exactly one end-key line\n" unless ($count{'end-key'} || 0) == 1;
  die "verdicts.txt: expected exactly three receipt lines (valid, invalid, incomplete, in this order)\n" unless ($count{receipt} || 0) == 3;
  return @rows_read = @rows;
}

# words KIND ROWS: the words of one kind
sub words {
  my ($kind, @rows) = @_;
  return map { $_->[1] } grep { $_->[0] eq $kind } @rows;
}

# gates ROWS: the gates in file order, each [NAME, OPENING KIND]; the
# opening kind is the gate line's kind without "gate-"
sub gates {
  my (@rows) = @_;
  return map { [ $_->[1], substr($_->[0], length 'gate-') ] } grep { $_->[0] =~ /\Agate-/ } @rows;
}

# trailer_word MESSAGE: the word of a valid message's trailer value, its
# reason dropped, or undef when trailer_problem finds a problem
sub trailer_word {
  my ($msg) = @_;
  return undef if defined trailer_problem($msg);
  my @rows = rows();
  my ($key) = words('trailer-key', @rows);
  my %alone = map { $_ => 1 } words('trailer', @rows);
  (my $m = $msg) =~ s/\r\n/\n/g;
  my ($line) = grep { index($_, "$key:") == 0 } split /\n/, $m;
  $line =~ s/[ \t]+\z//;
  my ($value) = $line =~ /\A\Q$key\E: (.*)\z/s;
  return $value if $alone{$value};
  my ($word) = $value =~ /\A(\S+) -/s;
  return $word;
}

sub trailer_problem {
  my ($msg) = @_;
  my @rows = rows();
  my ($key) = words('trailer-key', @rows);
  my %alone = map { $_ => 1 } words('trailer', @rows);
  my %reason = map { $_ => 1 } words('trailer-reason', @rows);
  my $values = join(', ', words('trailer', @rows), map {"$_ - <reason>"} words('trailer-reason', @rows));
  $msg =~ s/\r\n/\n/g;
  return 'the message holds a carriage return (CR) that is not part of a line end' if $msg =~ /\r/;
  # paragraphs are runs of lines that are not blank, so blank lines at the
  # start and the end count for nothing
  my @lines = split /\n/, $msg, -1;
  my (@paras, $open);
  for my $l (@lines) {
    if ($l =~ /\A[ \t]*\z/) { $open = 0; next }
    push @paras, [] unless $open;
    $open = 1;
    push @{ $paras[-1] }, $l;
  }
  return "the message is empty; it needs a subject and a last line $key: <value>" unless @paras;
  my @key_lines = grep { index($_, "$key:") == 0 } @lines;
  return "no line starts with $key:; the last line must be $key: <value>" unless @key_lines;
  my $last = $paras[-1];
  if (!grep { index($_, "$key:") == 0 } @$last) {
    return "the $key line is followed by GitHub's ---------/Co-authored-by block, which a squash merge adds when"
      . " commit authors differ from the pull request's author; the $key line must be the last paragraph"
      if grep { /\A-{3,}[ \t]*\z/ || /\ACo-authored-by:/i } @$last;
    return "the last paragraph is not the $key line; the $key line must be the last paragraph, after a blank line";
  }
  return "the last paragraph must be the $key line alone; it has " . scalar(@$last) . ' lines' if @$last > 1;
  return "the message is only the $key line; it needs a subject and a blank line before it" if @paras < 2;
  return "another line also starts with $key:; only the last line may" if @key_lines > 1;
  (my $line = $last->[0]) =~ s/[ \t]+\z//;
  my ($value) = $line =~ /\A\Q$key\E: (.*)\z/s;
  return "the $key line must be $key: <value> with one space after the colon" unless defined $value && $value ne '';
  return undef if $alone{$value};
  return "$value needs a reason: $key: $value - <what is open or why>" if $reason{$value};
  my ($word, $text) = $value =~ /\A(\S+) -(?: (.*))?\z/s;
  if (defined $word && $reason{$word}) {
    return "$word needs a reason: $key: $word - <what is open or why>" unless defined $text;
    return "the reason after $word holds a control character" if $text =~ /[\x00-\x1F\x7F]/;
    my $chars = $text;
    return "the reason after $word is not valid UTF-8" unless utf8::decode($chars);
    return "the reason after $word holds a control, format or invisible character"
      if $chars =~ /[\p{Cc}\p{Cf}\p{Default_Ignorable_Code_Point}\p{Zl}\p{Zp}]/;
    return "the reason after $word must say something (a letter or a digit)" unless $text =~ /[A-Za-z0-9]/;
    return undef;
  }
  return "$word takes no reason; write $key: $word" if defined $word && $alone{$word};
  return "unknown value; the values are: $values";
}

sub main {
  binmode STDIN, ':raw';
  binmode STDOUT, ':raw';
  binmode STDERR, ':raw';
  my ($cmd, $kind, @rest) = @ARGV;
  my $words = defined $cmd && $cmd eq 'words' && defined $kind && $kinds{$kind} && !@rest;
  my $check = defined $cmd && $cmd eq 'check-trailer' && !defined $kind;
  unless ($words || $check) {
    print STDERR "verdicts: usage: verdicts.pl words " . join('|', @kinds) . ", or verdicts.pl check-trailer <MESSAGE\n";
    exit 2;
  }
  my @rows = eval { rows() };
  if (!@rows) { print STDERR "verdicts: $@"; exit 2 }
  if ($check) {
    my $msg = do { local $/; <STDIN> };
    my $problem = trailer_problem(defined $msg ? $msg : '');
    print "verdicts: $problem\n" if defined $problem;
    close STDOUT or exit 2;
    exit(defined $problem ? 1 : 0);
  }
  print "$_\n" for words($kind, @rows);
  close STDOUT or exit 2;
  exit 0;
}

main() unless caller;

# judged TIP FROM: the commits status judges, newest first: those on TIP's
# first-parent history after FROM, or, when FROM is undef, from the oldest
# one whose message has a line starting with the trailer key (none such: an
# empty list). Returns {ids => [...], start => FROM or the oldest judged,
# shallow => 1 when the history here is cut and older commits were not
# read}, or {problem => 'not here', shallow => ...} when FROM is not on that
# history (in a shallow one it may lie beyond the cut). Needs lib/git.pl.
sub judged {
  my ($tip, $from) = @_;
  my ($key) = words('trailer-key', rows());
  my @ids = split /\n/, Git::ok('rev-list', '--first-parent', $tip);
  my ($sh) = Git::ok('rev-parse', '--is-shallow-repository') =~ /\A(\w+)/;
  my $shallow = defined $sh && $sh eq 'true' ? 1 : 0;
  if (defined $from) {
    my ($at) = grep { $ids[$_] eq $from } 0 .. $#ids;
    return { problem => 'not here', shallow => $shallow } unless defined $at;
    return { ids => [@ids[0 .. $at - 1]], start => $from, shallow => 0 };    # all of it is here
  }
  for my $i (reverse 0 .. $#ids) {
    return { ids => [@ids[0 .. $i]], start => $ids[$i], shallow => $shallow }
      if grep { index($_, "$key:") == 0 } split /\r?\n/, Git::message($ids[$i]);
  }
  return { ids => [], shallow => $shallow };
}

1;
