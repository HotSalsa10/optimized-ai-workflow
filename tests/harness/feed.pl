#!/usr/bin/env perl
# feed.pl STEPS SECONDS: the owner's side of a client run that reads its
# input as stream-json (h_client with H_FEED, step 5b's repair): prints one
# user message a "say" step, waiting between them for what the case needs,
# then ends, which closes the client's input. STEPS is a file, one step a
# line, its fields tab-separated:
#   say TEXT          one user message holding TEXT
#   file DIR PREFIX   wait until DIR holds a file whose name starts PREFIX
#   holds FILE TEXT   wait until FILE holds TEXT
#   sleep SECONDS     wait that long
# Every wait ends at SECONDS from the start (then the steps left are
# skipped, and the input closes). Never shipped.
use strict;
use warnings;
use JSON::PP;
use Time::HiRes qw(sleep time);
my ($steps, $secs) = @ARGV;
die "usage: feed.pl STEPS SECONDS\n" unless defined $secs && $secs =~ /\A[0-9]+\z/;
$SIG{PIPE} = 'IGNORE';
$| = 1;
my $until = time + $secs;
open my $f, '<', $steps or die "feed.pl: cannot read $steps\n";
my @steps = map { chomp; [split /\t/] } grep { /\S/ } <$f>;
close $f;
# wait until CODE says yes, or the time is up: 1 or 0
sub wait_for {
  my ($code) = @_;
  until ($code->()) {
    return 0 if time > $until;
    sleep 0.05;
  }
  return 1;
}
sub holds {
  my ($file, $text) = @_;
  open my $h, '<', $file or return 0;
  local $/;
  my $t = <$h>;
  close $h;
  return defined $t && index($t, $text) >= 0;
}
sub has_file {
  my ($dir, $prefix) = @_;
  opendir my $d, $dir or return 0;
  my $n = grep { index($_, $prefix) == 0 } readdir $d;
  closedir $d;
  return $n;
}
for my $s (@steps) {
  my ($kind, @a) = @$s;
  if ($kind eq 'say') {
    print JSON::PP->new->canonical->encode({ type => 'user', message => { role => 'user', content => $a[0] } }), "\n";
  } elsif ($kind eq 'file') {
    wait_for(sub { has_file(@a) }) or last;
  } elsif ($kind eq 'holds') {
    wait_for(sub { holds(@a) }) or last;
  } elsif ($kind eq 'sleep') {
    my $end = time + $a[0];
    wait_for(sub { time >= $end });
  } else {
    die "feed.pl: no such step: $kind\n";
  }
}
exit 0;
