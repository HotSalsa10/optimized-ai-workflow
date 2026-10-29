#!/usr/bin/env perl
# The one reader of verdicts.txt (rule M039: one vocabulary file; rule M048:
# one rule, one implementation). Scripts run it; perl helpers load it with
# require and call Verdicts::rows.
#
# Usage:
#   perl verdicts.pl words KIND   prints the words of one kind, one per line
#                                 (KIND: verdict, trailer-key, trailer,
#                                 trailer-reason)
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
# - <text>" where the text holds a letter or digit and no control
# character (trailing spaces and tabs are dropped); and no other line
# starts with "<trailer-key>:".
package Verdicts;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;

my %kinds = map { $_ => 1 } qw(verdict trailer-key trailer trailer-reason);

# rows: the file's entries in order, each [KIND, WORDS, MEANING]. Dies with
# a message when the file is missing or malformed. Read once per process.
my @rows_read;
sub rows {
  return @rows_read if @rows_read;
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
  return @rows_read = @rows;
}

# words KIND ROWS: the words of one kind
sub words {
  my ($kind, @rows) = @_;
  return map { $_->[1] } grep { $_->[0] eq $kind } @rows;
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
  my @lines = split /\n/, $msg, -1;
  shift @lines while @lines && $lines[0] =~ /\A[ \t]*\z/;
  pop @lines while @lines && $lines[-1] =~ /\A[ \t]*\z/;
  return "the message is empty; it needs a subject and a last line $key: <value>" unless @lines;
  my (@paras, $open);
  for my $l (@lines) {
    if ($l =~ /\A[ \t]*\z/) { $open = 0; next }
    push @paras, [] unless $open;
    $open = 1;
    push @{ $paras[-1] }, $l;
  }
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
    print STDERR "verdicts: usage: verdicts.pl words verdict|trailer-key|trailer|trailer-reason, or verdicts.pl check-trailer <MESSAGE\n";
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
1;
