#!/usr/bin/env perl
# fake-api.pl: the harness's fake Claude, a small local stand-in for the
# Anthropic Messages API (step 5.2, DECISIONS A49). The real Claude Code
# client talks to it, so the hooks are seen to fire at no cost. Never
# shipped; core perl only (IO::Socket::INET, IO::Select, JSON::PP,
# Getopt::Long, Time::HiRes).
#
# It listens on 127.0.0.1 (a port the system chooses, written to the port
# file), answers POST /v1/messages from a script (streamed or plain JSON,
# whichever the request asks for), answers /v1/messages/count_tokens, logs
# every request, and refuses CONNECT, so it can also sit in HTTPS_PROXY as a
# trap that shows any outside call. GET /harness-alive answers 200, so the
# harness knows it is up before the client starts.
#
# usage: perl fake-api.pl --script S.json --log-dir DIR --port-file F
#                         [--max-requests N] [--max-seconds S]
#
# Script (JSON):
#   { "convs": [ { "name": "main", "match": "<perl regex on the first user message text>",
#                  "turns": [ STEP, STEP, ... ] }, ... ],
#     "fallback": STEP, "usage": {"input_tokens": 0, "output_tokens": 0} }
#   STEP = {"text": "..."} | {"tool": "Bash", "input": {...}}
#        | {"blocks": [ {"type":"text","text":".."}, {"type":"tool_use","name":"..","input":{..}} ]}
#        | {"http_status": 400, "error": "message"}
# The turn index is the number of assistant messages already in the
# request, so a case is a plain list of answers, one per model call of that
# conversation.
#
# Logs, in DIR: requests.tsv (one line per request: number, seconds, method,
# path, model, stream or json, kind, then conv=NAME turn=N and the tool
# results that came back), and req-NNN.json with each whole request, its key
# headers redacted. A request past --max-requests is answered with an error
# and logged as over-cap.
use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;
use JSON::PP;
use Getopt::Long;
use Time::HiRes qw(time);

my ($script_f, $log_dir, $port_file) = ('', '', '');
my ($max_req, $max_sec) = (200, 600);
GetOptions(
  'script=s'       => \$script_f,
  'log-dir=s'      => \$log_dir,
  'port-file=s'    => \$port_file,
  'max-requests=i' => \$max_req,
  'max-seconds=i'  => \$max_sec,
) or die "fake-api: bad arguments\n";
die "fake-api: --script, --log-dir and --port-file are required\n"
  unless $script_f && $log_dir && $port_file;

my $J  = JSON::PP->new->utf8->canonical;
my $JP = JSON::PP->new->utf8->canonical->pretty;
my $JC = JSON::PP->new->canonical;    # character strings, for JSON inside JSON

open my $sfh, '<', $script_f or die "fake-api: cannot read $script_f: $!\n";
my $script = $J->decode(do { local $/; <$sfh> });
close $sfh;
my $usage = $script->{usage} || { input_tokens => 0, output_tokens => 0 };

mkdir $log_dir unless -d $log_dir;
open my $sum, '>>', "$log_dir/requests.tsv" or die "fake-api: log: $!\n";
{ my $o = select $sum; $| = 1; select $o; }

my $srv = IO::Socket::INET->new(
  LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'tcp',
  Listen => 64, ReuseAddr => 1,
) or die "fake-api: cannot listen: $@\n";
my $port = $srv->sockport;
{
  open my $pf, '>', "$port_file.tmp" or die "fake-api: port file: $!\n";
  print $pf "$port\n";
  close $pf;
  rename "$port_file.tmp", $port_file or die "fake-api: rename: $!\n";
}

$SIG{PIPE} = 'IGNORE';
$SIG{TERM} = $SIG{INT} = sub { exit 0 };
my $t0 = time;
my $n  = 0;
my $sel = IO::Select->new($srv);
my %buf;

while (1) {
  if (time - $t0 > $max_sec) {
    print $sum join("\t", 'END', sprintf('%.3f', time - $t0), 'max-seconds reached'), "\n";
    exit 0;
  }
  for my $fh ($sel->can_read(1)) {
    if ($fh == $srv) {
      my $c = $srv->accept or next;
      $c->autoflush(1);
      $sel->add($c);
      $buf{ fileno $c } = '';
      next;
    }
    my $got = sysread($fh, my $chunk, 65536);
    if (!$got) { $sel->remove($fh); delete $buf{ fileno $fh }; close $fh; next; }
    $buf{ fileno $fh } .= $chunk;
    my $req = parse_request(\$buf{ fileno $fh });
    next unless $req;    # not complete yet
    $n++;
    my $resp = handle($req, $n);
    syswrite_all($fh, $resp);
    $sel->remove($fh);
    delete $buf{ fileno $fh };
    close $fh;
  }
}

sub syswrite_all {
  my ($fh, $data) = @_;
  my $off = 0;
  while ($off < length $data) {
    my $w = syswrite($fh, $data, length($data) - $off, $off);
    return unless defined $w;
    $off += $w;
  }
}

# a hash when a whole request is in the buffer, else undef
sub parse_request {
  my ($b) = @_;
  my $end = index($$b, "\r\n\r\n");
  return undef if $end < 0;
  my $head = substr($$b, 0, $end);
  my @lines = split /\r\n/, $head;
  my ($method, $path) = split / /, shift @lines;
  my %h;
  for (@lines) { my ($k, $v) = split /:\s*/, $_, 2; $h{ lc $k } = $v; }
  my $rest = substr($$b, $end + 4);
  my $body;
  if (($h{'transfer-encoding'} || '') =~ /chunked/i) {
    $body = '';
    my $p = 0;
    while (1) {
      my $e = index($rest, "\r\n", $p);
      return undef if $e < 0;
      my $len = hex substr($rest, $p, $e - $p);
      return undef if length($rest) < $e + 2 + $len + 2;
      last if $len == 0;
      $body .= substr($rest, $e + 2, $len);
      $p = $e + 2 + $len + 2;
    }
  } else {
    my $cl = $h{'content-length'} || 0;
    return undef if length($rest) < $cl;
    $body = substr($rest, 0, $cl);
  }
  return { method => $method, path => $path, headers => \%h, body => $body };
}

sub http {
  my ($status, $ctype, $body, $extra) = @_;
  my %txt = (200 => 'OK', 400 => 'Bad Request', 403 => 'Forbidden', 404 => 'Not Found', 500 => 'Internal Server Error', 529 => 'Overloaded');
  return "HTTP/1.1 $status " . ($txt{$status} || 'Status') . "\r\n"
    . "Content-Type: $ctype\r\nContent-Length: " . length($body) . "\r\n"
    . "Connection: close\r\nrequest-id: req_fake_$n\r\n" . ($extra || '') . "\r\n" . $body;
}

sub err_json {
  my ($status, $type, $msg) = @_;
  return http($status, 'application/json', $J->encode({ type => 'error', error => { type => $type, message => $msg } }));
}

sub text_of {
  my ($content) = @_;
  return $content unless ref $content;
  return join "\n", map { ref $_ && ($_->{type} || '') eq 'text' ? $_->{text} : () } @$content;
}

sub handle {
  my ($r, $n) = @_;
  my %h = %{ $r->{headers} };
  for (qw(x-api-key authorization proxy-authorization)) { $h{$_} = '<redacted>' if exists $h{$_}; }
  my $body = eval { $J->decode($r->{body}) };
  my $rec = { n => $n, t => sprintf('%.3f', time - $t0), method => $r->{method}, path => $r->{path},
    headers => \%h, body => (defined $body ? $body : $r->{body}) };
  my ($kind, $resp, $info) = ('other', undef, '');

  if ($r->{method} eq 'CONNECT') {
    $kind = 'CONNECT-REFUSED';
    $info = $r->{path};
    $resp = http(403, 'text/plain', "fake-api: no outside connections\n");
  } elsif ($r->{method} eq 'GET' && $r->{path} eq '/harness-alive') {
    $kind = 'alive';
    $resp = http(200, 'text/plain', "alive\n");
  } elsif ($n > $max_req) {
    $kind = 'over-cap';
    $resp = err_json(400, 'invalid_request_error', "fake-api: request cap $max_req reached");
  } elsif ($r->{method} eq 'POST' && $r->{path} =~ m{^/v1/messages/count_tokens}) {
    $kind = 'count_tokens';
    $resp = http(200, 'application/json', $J->encode({ input_tokens => 42 }));
  } elsif ($r->{method} eq 'POST' && $r->{path} =~ m{^/v1/messages(\?|$)} && ref $body eq 'HASH') {
    ($kind, $resp, $info) = messages($body, $n);
  } else {
    $kind = 'unknown-path';
    $resp = err_json(404, 'not_found_error', "fake-api: no route $r->{method} $r->{path}");
  }
  $rec->{kind} = $kind;
  $rec->{info} = $info;
  if (open my $fh, '>', sprintf('%s/req-%03d.json', $log_dir, $n)) { print $fh $JP->encode($rec); close $fh; }
  my $model = ref $body eq 'HASH' ? ($body->{model} || '') : '';
  my $stream = ref $body eq 'HASH' && $body->{stream} ? 'stream' : 'json';
  print $sum join("\t", $n, $rec->{t}, $r->{method}, $r->{path}, $model, $stream, $kind, $info), "\n";
  return $resp;
}

sub messages {
  my ($b, $n) = @_;
  my $msgs = $b->{messages} || [];
  my ($first) = grep { $_->{role} eq 'user' } @$msgs;
  my $ftext = $first ? text_of($first->{content}) : '';
  my $turn = scalar grep { $_->{role} eq 'assistant' } @$msgs;
  # tool results coming back in the last user message
  my @tr;
  if (@$msgs && $msgs->[-1]{role} eq 'user' && ref $msgs->[-1]{content}) {
    for my $blk (@{ $msgs->[-1]{content} }) {
      next unless ref $blk && ($blk->{type} || '') eq 'tool_result';
      my $c = ref $blk->{content} ? text_of($blk->{content}) : ($blk->{content} // '');
      $c =~ s/\s+/ /g;
      push @tr, ($blk->{is_error} ? 'ERR:' : 'OK:') . substr($c, 0, 160);
    }
  }
  my ($conv) = grep { my $re = $_->{match}; $ftext =~ /$re/m } @{ $script->{convs} || [] };
  my ($name, $step);
  if ($conv) {
    $name = $conv->{name};
    $step = $conv->{turns}[$turn] || { text => "FAKE-END $name turn $turn" };
  } else {
    $name = 'fallback';
    $step = $script->{fallback} || { text => 'FAKE-FALLBACK' };
  }
  my $info = "conv=$name turn=$turn" . (@tr ? ' results=[' . join(' | ', @tr) . ']' : '');
  if ($step->{http_status}) {
    return ("$name:error", err_json($step->{http_status}, 'invalid_request_error', $step->{error} || 'fake error'), $info);
  }
  my @blocks;
  if ($step->{blocks}) { @blocks = @{ $step->{blocks} }; }
  elsif (defined $step->{tool}) { @blocks = ({ type => 'tool_use', name => $step->{tool}, input => $step->{input} || {} }); }
  else { @blocks = ({ type => 'text', text => $step->{text} }); }
  my $i = 0;
  for (@blocks) { $_ = {%$_}; $_->{id} = "toolu_fake_${n}_" . $i++ if $_->{type} eq 'tool_use'; }
  my $stop = (grep { $_->{type} eq 'tool_use' } @blocks) ? 'tool_use' : 'end_turn';
  my $model = $b->{model} || 'fake-model';
  my %u = (input_tokens => $usage->{input_tokens} + 0, output_tokens => $usage->{output_tokens} + 0,
    cache_creation_input_tokens => 0, cache_read_input_tokens => 0);
  my $mid = "msg_fake_$n";
  if (!$b->{stream}) {
    my $m = { id => $mid, type => 'message', role => 'assistant', model => $model,
      content => \@blocks, stop_reason => $stop, stop_sequence => undef, usage => \%u };
    return ("$name", http(200, 'application/json', $J->encode($m)), $info);
  }
  my $sse = '';
  my $ev = sub { my ($t, $d) = @_; $sse .= "event: $t\ndata: " . $J->encode($d) . "\n\n"; };
  $ev->('message_start', { type => 'message_start', message => { id => $mid, type => 'message', role => 'assistant',
    model => $model, content => [], stop_reason => undef, stop_sequence => undef,
    usage => { %u, output_tokens => 1 } } });
  my $idx = 0;
  for my $blk (@blocks) {
    if ($blk->{type} eq 'text') {
      $ev->('content_block_start', { type => 'content_block_start', index => $idx, content_block => { type => 'text', text => '' } });
      $ev->('content_block_delta', { type => 'content_block_delta', index => $idx, delta => { type => 'text_delta', text => $blk->{text} } });
    } else {
      $ev->('content_block_start', { type => 'content_block_start', index => $idx,
        content_block => { type => 'tool_use', id => $blk->{id}, name => $blk->{name}, input => {} } });
      $ev->('content_block_delta', { type => 'content_block_delta', index => $idx,
        delta => { type => 'input_json_delta', partial_json => $JC->encode($blk->{input}) } });
    }
    $ev->('content_block_stop', { type => 'content_block_stop', index => $idx });
    $idx++;
  }
  $ev->('message_delta', { type => 'message_delta', delta => { stop_reason => $stop, stop_sequence => undef },
    usage => { output_tokens => $u{output_tokens} } });
  $ev->('message_stop', { type => 'message_stop' });
  return ("$name", http(200, 'text/event-stream', $sse, "Cache-Control: no-cache\r\n"), $info);
}
