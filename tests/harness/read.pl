#!/usr/bin/env perl
# read.pl init FIELD FILE: prints FIELD of the client's init event in FILE
# (stream-json output, one JSON object per line). A list prints one item per
# line. Exit 1 when there is no init event or no such field.
# read.pl req CONV TEXT DIR: exit 0 when a request the fake logged in DIR
# (req-NNN.json) for its conversation CONV holds TEXT in what the client
# sent: the system text or a message that is not the assistant's (the fake's
# own scripted words come back as assistant messages). TEXT is searched in
# the decoded strings, so non-ASCII text and quotes are found as written.
# read.pl receipt DESC HOME GIT: prints the gate-receipt receipt (step 5b)
# of the agent whose Agent call was described DESC, as "STATE why=W open=O
# stops=N blocked=N denied=N" (W the reasons joined by commas; "none" for
# no reason or no opening word). The agent is found by its description in
# the client's agent-<id>.meta.json under HOME/.claude/projects, the
# receipt by that id among the method-receipt-*.json files in the git
# folder GIT. Prints "none" and exits 1 when either is missing or not one.
# read.pl hooks DESC TEXT HOME LOG: prints how many hook runs whose command
# holds TEXT the client's debug log LOG shows during the Agent call
# described DESC (its "Hooks: ... [COMMAND] finished with status" lines
# between that call's tool_dispatch_start and tool_dispatch_end; a
# foreground agent holds the session for that span). Prints "none" and
# exits 1 when the call or its span is not found.
# Never shipped.
use strict;
use warnings;
use JSON::PP;
my ($what, $field, $file) = @ARGV;
# the agent described DESC: (its id, its Agent call's id), or ()
sub agent_of {
  my ($desc, $home) = @_;
  require File::Find;
  my @found;
  my $top = "$home/.claude/projects";
  return () unless -d $top;
  File::Find::find({ no_chdir => 1, wanted => sub {
    return unless m{/agent-([A-Za-z0-9]+)\.meta\.json\z};
    my $id = $1;
    open my $h, '<', $_ or return;
    my $m = eval { local $/; JSON::PP->new->utf8->decode(<$h>) };
    push @found, [$id, $m->{toolUseId}] if ref $m eq 'HASH' && ($m->{description} // '') eq $desc;
  } }, $top);
  return @found == 1 ? @{ $found[0] } : ();
}
if (($what // '') eq 'receipt' && @ARGV == 4) {
  my ($desc, $home, $git) = @ARGV[1 .. 3];
  my ($id) = agent_of($desc, $home);
  my @r;
  if (defined $id && opendir my $d, $git) {
    for my $n (sort grep { /\Amethod-receipt-[0-9a-f]+\.json\z/ } readdir $d) {
      open my $h, '<', "$git/$n" or next;
      my $r = eval { local $/; JSON::PP->new->utf8->decode(<$h>) };
      push @r, $r if ref $r eq 'HASH' && ($r->{agent} // '') eq $id;
    }
  }
  if (@r != 1) { print "none\n"; exit 1 }
  my $r = $r[0];
  my @why = ref $r->{why} eq 'ARRAY' ? @{ $r->{why} } : ();
  binmode STDOUT, ':utf8';
  printf "%s why=%s open=%s stops=%s blocked=%s denied=%s\n", $r->{state} // 'none', @why ? join(',', @why) : 'none',
    $r->{open} // 'none', map { $r->{$_} // 'none' } qw(stops blocked denied);
  exit 0;
}
if (($what // '') eq 'hooks' && @ARGV == 5) {
  my ($desc, $text, $home, $log) = @ARGV[1 .. 4];
  my (undef, $call) = agent_of($desc, $home);
  my ($in, $n, $done) = (0, 0, 0);
  if (defined $call && open my $f, '<', $log) {
    while (my $l = <$f>) {
      if (index($l, "tool_dispatch_start tool=Agent toolUseId=$call ") >= 0) { $in = 1; next }
      if ($in && index($l, "tool_dispatch_end tool=Agent toolUseId=$call ") >= 0) { $done = 1; last }
      $n++ if $in && $l =~ / Hooks: \S+ \[(.*)\] finished with status / && index($1, $text) >= 0;
    }
  }
  if (!$done) { print "none\n"; exit 1 }
  print "$n\n";
  exit 0;
}
if (($what // '') eq 'req' && @ARGV == 4) {
  my ($conv, $text, $dir) = @ARGV[1 .. 3];
  utf8::decode($text);
  # every string in what the client sent, joined
  my $strings;
  $strings = sub {
    my ($v) = @_;
    return ref $v eq 'HASH' ? map { $strings->($_) } @{$v}{ sort keys %$v }
      : ref $v eq 'ARRAY' ? map { $strings->($_) } @$v
      : defined $v && !ref $v ? ($v) : ();
  };
  opendir my $d, $dir or exit 1;
  for my $n (sort grep { /\Areq-[0-9]+\.json\z/ } readdir $d) {
    open my $h, '<', "$dir/$n" or next;
    my $r = eval { local $/; JSON::PP->new->utf8->decode(<$h>) } or next;
    next unless ref $r eq 'HASH' && ($r->{info} // '') =~ /\Aconv=\Q$conv\E /;
    my $b = $r->{body};
    next unless ref $b eq 'HASH';
    my $sent = join "\n", $strings->([$b->{system}, grep { ref $_ eq 'HASH' && ($_->{role} // '') ne 'assistant' } @{ ref $b->{messages} eq 'ARRAY' ? $b->{messages} : [] }]);
    exit 0 if index($sent, $text) >= 0;
  }
  exit 1;
}
die "usage: read.pl init FIELD FILE | read.pl req CONV TEXT DIR | read.pl receipt DESC HOME GIT | read.pl hooks DESC TEXT HOME LOG\n" unless defined $file && $what eq 'init';
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
