#!/usr/bin/env perl
# fake-mcp.pl LOGFILE [TOOL...]: the harness's fake MCP server (stdio,
# newline-delimited JSON-RPC) with the tools named (merge_pull_request when
# none is), each of which only logs that it was called. Never shipped; core
# perl.
use strict; use warnings; use JSON::PP;
my $log = shift or die "usage: fake-mcp.pl LOGFILE [TOOL...]\n";
my @tools = @ARGV ? @ARGV : ('merge_pull_request');
my $J = JSON::PP->new->utf8->canonical;
$| = 1;
open my $L, '>>', $log or die "log: $!\n";
{ my $o = select $L; $| = 1; select $o; }
while (my $line = <STDIN>) {
    next unless $line =~ /\S/;
    my $m = eval { $J->decode($line) } or next;
    print $L "IN ", $J->encode($m), "\n";
    next unless defined $m->{id};
    my $meth = $m->{method} || '';
    my $res;
    if ($meth eq 'initialize') {
        $res = { protocolVersion => ($m->{params}{protocolVersion} || '2025-06-18'),
                 capabilities => { tools => {} }, serverInfo => { name => 'fake', version => '0.0.1' } };
    } elsif ($meth eq 'tools/list') {
        $res = { tools => [ map { { name => $_, description => "$_ (fake, logs only).",
                 inputSchema => { type => 'object', properties => { pull_number => { type => 'number' } }, additionalProperties => JSON::PP::true } } } @tools ] };
    } elsif ($meth eq 'tools/call') {
        print $L "CALLED ", $J->encode($m->{params}), "\n";
        $res = { content => [ { type => 'text', text => 'FAKE-MERGED' } ] };
    } else {
        print STDOUT $J->encode({ jsonrpc => '2.0', id => $m->{id}, error => { code => -32601, message => "no method $meth" } }), "\n";
        next;
    }
    print STDOUT $J->encode({ jsonrpc => '2.0', id => $m->{id}, result => $res }), "\n";
}
