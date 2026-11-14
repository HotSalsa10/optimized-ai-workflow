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
# read.pl used DESC HOME GIT: the same receipt's evidence from the agent's
# record (step 5b.2), as "models=M efforts=E input=N output=N
# cache_creation=N cache_read=N" (M and E joined by commas, "none" for
# none), or "none" and exit 1 as above.
# read.pl effort CONV DIR: prints each effort the requests the fake logged
# in DIR for its conversation CONV carried (the request body's
# output_config.effort; "none" for a request without one), once, in the
# order first seen, joined by commas; "none" and exit 1 when there is no
# such request.
# read.pl first CONV TEXT DIR: prints the number of the first request the
# fake logged in DIR for its conversation CONV that holds TEXT in what the
# client sent (as req reads it), or "none" and exit 1.
# read.pl rules CONV SUFFIX FILE DIR (step 6.1): exit 0, printing "same",
# when the first request the fake logged in DIR for its conversation CONV
# holds, after the client's heading for a file whose path ends in SUFFIX
# ("... SUFFIX (project instructions, checked into the codebase):" and a
# blank line), FILE's text without its lines that hold only an HTML comment
# (as tests/budget.test.sh counts it), followed by a line break or the end;
# otherwise exit 1, printing "no request", "missing" (no such heading) or
# "differs at byte N".
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
# the receipt of the agent described DESC (HOME, the git folder GIT), or
# undef when there is not exactly one
sub receipt_of {
  my ($desc, $home, $git) = @_;
  my ($id) = agent_of($desc, $home);
  my @r;
  if (defined $id && opendir my $d, $git) {
    for my $n (sort grep { /\Amethod-receipt-[0-9a-f]+\.json\z/ } readdir $d) {
      open my $h, '<', "$git/$n" or next;
      my $r = eval { local $/; JSON::PP->new->utf8->decode(<$h>) };
      push @r, $r if ref $r eq 'HASH' && ($r->{agent} // '') eq $id;
    }
  }
  return @r == 1 ? $r[0] : undef;
}
# the bodies of the requests the fake logged in DIR for its conversation
# CONV, in the order sent
sub requests_of {
  my ($conv, $dir) = @_;
  my @b;
  opendir my $d, $dir or return ();
  for my $n (sort grep { /\Areq-[0-9]+\.json\z/ } readdir $d) {
    open my $h, '<', "$dir/$n" or next;
    my $r = eval { local $/; JSON::PP->new->utf8->decode(<$h>) } or next;
    next unless ref $r eq 'HASH' && ($r->{info} // '') =~ /\Aconv=\Q$conv\E /;
    push @b, $r->{body} if ref $r->{body} eq 'HASH';
  }
  return @b;
}
if (($what // '') eq 'receipt' && @ARGV == 4) {
  my $r = receipt_of(@ARGV[1 .. 3]);
  if (!$r) { print "none\n"; exit 1 }
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
if (($what // '') eq 'used' && @ARGV == 4) {
  my $r = receipt_of(@ARGV[1 .. 3]);
  if (!$r) { print "none\n"; exit 1 }
  my $list = sub { my @l = ref $_[0] eq 'ARRAY' ? grep { defined && !ref } @{ $_[0] } : (); return @l ? join(',', @l) : 'none' };
  my $t = ref $r->{tokens} eq 'HASH' ? $r->{tokens} : {};
  binmode STDOUT, ':utf8';
  printf "models=%s efforts=%s input=%s output=%s cache_creation=%s cache_read=%s\n", $list->($r->{models}), $list->($r->{efforts}),
    map { $t->{$_} // 'none' } qw(input output cache_creation cache_read);
  exit 0;
}
if (($what // '') eq 'effort' && @ARGV == 3) {
  my @e;
  for my $b (requests_of(@ARGV[1, 2])) {
    my $e = ref $b->{output_config} eq 'HASH' ? $b->{output_config}{effort} : undef;
    $e = 'none' unless defined $e && !ref $e;
    push @e, $e unless grep { $_ eq $e } @e;
  }
  print @e ? join(',', @e) : 'none', "\n";
  exit(@e ? 0 : 1);
}
# what the client sent in a request body: every string of its system text
# and of its messages that are not the assistant's, joined
sub sent {
  my ($b) = @_;
  my $strings;
  $strings = sub {
    my ($v) = @_;
    return ref $v eq 'HASH' ? map { $strings->($_) } @{$v}{ sort keys %$v }
      : ref $v eq 'ARRAY' ? map { $strings->($_) } @$v
      : defined $v && !ref $v ? ($v) : ();
  };
  return join "\n", $strings->([$b->{system}, grep { ref $_ eq 'HASH' && ($_->{role} // '') ne 'assistant' } @{ ref $b->{messages} eq 'ARRAY' ? $b->{messages} : [] }]);
}
if (($what // '') eq 'req' && @ARGV == 4) {
  my ($conv, $text, $dir) = @ARGV[1 .. 3];
  utf8::decode($text);
  for my $b (requests_of($conv, $dir)) {
    exit 0 if index(sent($b), $text) >= 0;
  }
  exit 1;
}
if (($what // '') eq 'first' && @ARGV == 4) {
  my ($conv, $text, $dir) = @ARGV[1 .. 3];
  utf8::decode($text);
  opendir my $d, $dir or do { print "none\n"; exit 1 };
  for my $n (sort grep { /\Areq-[0-9]+\.json\z/ } readdir $d) {
    open my $h, '<', "$dir/$n" or next;
    my $r = eval { local $/; JSON::PP->new->utf8->decode(<$h>) } or next;
    next unless ref $r eq 'HASH' && ($r->{info} // '') =~ /\Aconv=\Q$conv\E / && ref $r->{body} eq 'HASH';
    next unless index(sent($r->{body}), $text) >= 0;
    my ($num) = $n =~ /([0-9]+)/;
    print 0 + $num, "\n";
    exit 0;
  }
  print "none\n";
  exit 1;
}
if (($what // '') eq 'rules' && @ARGV == 5) {
  my ($conv, $suffix, $file, $dir) = @ARGV[1 .. 4];
  my ($b) = requests_of($conv, $dir);
  if (!$b) { print "no request\n"; exit 1 }
  open my $h, '<:raw', $file or do { print "cannot read $file\n"; exit 1 };
  my $want = join '', grep { !/\A<!--(?:(?!-->).)*-->\n?\z/ } <$h>;
  close $h;
  utf8::decode($want);
  utf8::decode($suffix);
  $want =~ s/\n+\z//;
  my $s = sent($b);
  my $key = "$suffix (project instructions, checked into the codebase):\n\n";
  my $at = index($s, $key);
  if ($at < 0) { print "missing\n"; exit 1 }
  my $got = substr($s, $at + length $key, length $want);
  my $next = substr($s, $at + length($key) + length($want), 1);
  if ($got eq $want && ($next eq '' || $next eq "\n")) { print "same\n"; exit 0 }
  my $i = 0;
  $i++ while $i < length $want && substr($got, $i, 1) eq substr($want, $i, 1);
  print "differs at byte $i\n";
  exit 1;
}
die "usage: read.pl init FIELD FILE | read.pl req CONV TEXT DIR | read.pl first CONV TEXT DIR | read.pl rules CONV SUFFIX FILE DIR | read.pl effort CONV DIR | read.pl receipt DESC HOME GIT | read.pl used DESC HOME GIT | read.pl hooks DESC TEXT HOME LOG\n" unless defined $file && $what eq 'init';
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
