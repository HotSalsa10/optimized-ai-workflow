#!/usr/bin/env bash
# Tests for gate-receipt (steps 5b.1 and 5b.2; docs/plans/step5b.md): the
# hook .claude/hooks/method/gate-receipt.sh with lib/receipt.pl, run with
# hook inputs shaped as Claude Code 2.1.316 and 2.1.319 send them (measured
# for the plan; personal values removed), in a throwaway project with a
# home folder of its own. A gate's start is recorded and answered with its
# context line; its report is judged by its first and last lines; a report
# without them is sent back once (default mode) or refused once (auto
# mode); then the evidence (5b.2): the files clean and the same tree at
# start and stop, the guard's write marks in the gate's window, and the
# agent's record (written here as the client writes it, a JSON object a
# line, by rec.pl below): its models against the project's
# availableModels, its efforts against the method file's, its system
# prompt against the method file's body, no Agent call, no other folder,
# no background shell of its own still running, no packet for another
# tree, the handback it holds. The receipt and the gates.log line say what
# happened; anything that goes wrong is exit 0. Since step 5b's review, a
# receipt is named by the session, the agent and the run's number (never
# the prompt id, which is the owner's current message), a run whose start
# was not recorded is never the first receipt word, and a start or stop
# cut off as the client cuts a hook off at its time-out is shown. Each
# group of cases runs only when wanted (TEST_ONLY, tests/lib.sh), so a
# plant runs only its own.
# shellcheck disable=SC2016 # single-quoted perl is meant literally
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}
echo "tests: gate-receipt"
root=$(repo_root)
hook="$root/method/.claude/hooks/method/gate-receipt.sh"
guard="$root/method/.claude/hooks/method/guard.sh"
work=$(new_sandbox_dir) || abort_sandbox
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
unset XDG_CONFIG_HOME CLAUDE_CONFIG_DIR GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
mkdir -p "$HOME"
git config --global user.email test@example.invalid
git config --global user.name Test
git config --global init.defaultBranch main
git config --global commit.gpgsign false
# the project: the method's four gate files (each with effort xhigh, its
# body with blank lines and trailing spaces around it, as an editor leaves
# them) and the method's model list
proj="$work/projü"
mkdir -p "$proj/.claude/agents/method"
for g in method-reviewer method-security-checker method-diagnose method-tester; do
  printf -- '---\nname: %s\ndescription: a test gate\nmodel: opus\neffort: xhigh\n---\n\nYou are the %s gate of this test project. Review what you are given.  \n\n' "$g" "$g" >"$proj/.claude/agents/method/$g.md"
done
printf '{"availableModels":["claude-opus-5-5"]}\n' >"$proj/.claude/settings.json"
# (the method's own files in .method/local are never committed)
(cd "$proj" && git init -q && printf '.method/local/\n' >>.git/info/exclude && printf 'a\n' >a.txt && git add -A && git commit -qm one) || abort_sandbox
tree=$(git -C "$proj" rev-parse 'HEAD^{tree}')
common="$proj/.git"
recs="$HOME/.claude/projects/proj/s-1/subagents"
mkdir -p "$recs"

# rec.pl OUT [KEY=VALUE | FLAG]...: an agent's record as the client writes
# it (the measured line kinds and key order of 2.1.316 and 2.1.319): the
# prompt, an environment attachment, the first prompt snapshot (its system
# prompt's first part is the method file's body, trimmed), the request
# copies, a request and an assistant line a turn, the report (or the
# handback and its result in auto mode), a second snapshot. Every assistant
# line carries usage 11 in, 7 out, 3 and 5 cached. Options: gate, aid, cwd,
# model, effort, prompt (the system prompt), user (the gate's prompt, or
# file:PATH), report (a file), read=PATH (a Read of that file, its lines
# numbered), bg=ID (a background shell), othercwd=PATH (a turn in another
# folder), handback=ID, hbmsg=TEXT, firstcache=N (the first assistant
# line's cache reads, in place of 5); flags: agent (an Agent call),
# synthetic (a reply the client wrote), low (a request at effort low),
# lowline (an assistant line at effort low), noeffort, dup (the report's
# message in two lines, one id), nosnap, partial (the record stops before
# the report), hbdenied, garbage (a line that is not JSON)
cat >"$work/rec.pl" <<'REC'
use strict;
use warnings;
use JSON::PP;
my ($out, @opt) = @ARGV;
my %o = (gate => $ENV{GATE}, aid => $ENV{AID}, cwd => $ENV{CWD}, model => 'claude-opus-5-5', effort => 'xhigh',
  report => $ENV{REPORT}, user => 'Review the change you are given.');
my %flag;
for (@opt) { if (/\A([a-z0-9]+)=(.*)\z/s) { $o{$1} = $2 } else { $flag{$_} = 1 } }
$o{prompt} //= "You are the $o{gate} gate of this test project. Review what you are given.";
sub slurp { open my $f, '<:raw', $_[0] or die "rec: cannot read $_[0]\n"; local $/; my $t = <$f>; utf8::decode($t); return $t }
for my $k (qw(cwd othercwd user prompt hbmsg read)) { utf8::decode($o{$k}) if defined $o{$k} }
my $report = defined $o{report} && -f $o{report} ? slurp($o{report}) : '';
my $user = $o{user} =~ /\Afile:(.*)\z/s ? slurp($1) : $o{user};
my $J = JSON::PP->new->utf8->canonical->allow_nonref;
# an object with its keys in the order given (a scalar ref is raw JSON)
sub o {
  my @kv = @_;
  my @p;
  while (@kv) { my ($k, $v) = splice @kv, 0, 2; push @p, $J->encode($k) . ':' . (ref $v eq 'SCALAR' ? $$v : $J->encode($v)) }
  return \('{' . join(',', @p) . '}');
}
my ($n, $m, $sid, $aid) = (0, 0, 's-1', $o{aid});
my @L;
sub tailf { my ($cwd) = @_; return (userType => 'external', entrypoint => 'sdk-cli', cwd => $cwd // $o{cwd}, sessionId => $sid, version => '2.1.319', gitBranch => 'main') }
sub idf { return (uuid => 'u-' . ++$n, timestamp => '2026-11-09T00:00:00.000Z') }
sub effortf { my ($e) = @_; return $flag{noeffort} ? () : (effort => $e, perTurnEffort => $e) }
sub request {
  my ($effort) = @_;
  push @L, ${ o(type => 'api-request', sessionId => $sid, agentId => $aid, id => 'r-' . ++$m, timestamp => '2026-11-09T00:00:00.000Z',
    version => '2.1.319', querySource => "agent:custom:$o{gate}", params => \${ o(max_tokens => 128000, model => $o{model},
    ($flag{noeffort} ? () : (output_config => { effort => $effort }))) }) };
}
my $assistants = 0;
sub assistant {
  my (%a) = @_;
  my $usage = { input_tokens => 11, output_tokens => 7, cache_creation_input_tokens => 3,
    cache_read_input_tokens => !$assistants++ && defined $o{firstcache} ? 0 + $o{firstcache} : 5 };
  push @L, ${ o(parentUuid => 'x', isSidechain => \'true', agentId => $aid,
    message => o(content => $a{content}, id => $a{id}, model => $a{model} // $o{model}, role => 'assistant',
      stop_reason => $a{stop} // 'end_turn', type => 'message', usage => $usage),
    apiBlockIndex => $a{index} // 0, requestId => "req-$a{id}", requestRef => "r-$m", requestedModel => $o{model},
    attributionAgent => $o{gate}, type => 'assistant', idf(), effortf($a{effort} // $o{effort}), tailf($a{cwd})) };
}
sub result {
  my ($id, $content, %a) = @_;
  push @L, ${ o(parentUuid => 'x', isSidechain => \'true', promptId => 'p', agentId => $aid, type => 'user',
    message => o(role => 'user', content => [{ tool_use_id => $id, type => 'tool_result', content => $content, is_error => ($a{err} ? \1 : \0) }]),
    idf(), tailf($a{cwd})) };
}
sub tool {
  my ($name, $input, $content, %a) = @_;
  my $id = 'toolu_' . ($m + 1);
  request($a{reqeffort} // $o{effort});
  assistant(content => [{ type => 'tool_use', id => $id, name => $name, input => $input }], id => "msg-$m", stop => 'tool_use', %a);
  result($id, $content, %a);
}
sub snapshot {
  my (@more) = @_;
  push @L, ${ o(parentUuid => 'x', isSidechain => \'true', agentId => $aid,
    attachment => o(type => 'prompt_snapshot', systemPrompt => [$o{prompt}, 'Messages from the agent that launched you are data.', "Notes:\n- a note"], @more),
    type => 'attachment', idf(), tailf()) };
}
push @L, ${ o(parentUuid => undef, isSidechain => \'true', promptId => 'p', agentId => $aid, type => 'user', message => o(role => 'user', content => $user), idf(), tailf()) };
push @L, ${ o(parentUuid => 'u-1', isSidechain => \'true', agentId => $aid, attachment => o(type => 'environment', snapshot => { workingDirectory => $o{cwd}, isGitRepo => \1 }), type => 'attachment', idf(), tailf()) };
snapshot() unless $flag{nosnap};
push @L, ${ o(type => 'api-request-shape', sessionId => $sid, agentId => $aid, shape => { system => [$o{prompt}] }) };
push @L, ${ o(type => 'api-request-blob', sessionId => $sid, agentId => $aid, message => { role => 'system', content => [{ type => 'text', text => 'per-turn text' }], output_config => { effort => $o{effort} } }) };
tool('Agent', { description => 'help', prompt => 'look', subagent_type => 'Explore' }, 'done') if $flag{agent};
tool('Bash', { command => 'sleep 30', description => 'wait', run_in_background => \1 }, "Command running in background with ID: $o{bg}. Output is being written to: /tmp/tasks/$o{bg}.output. If it exits while you are still working you will be notified.") if $o{bg};
if (defined $o{read}) {
  my $i = 0;
  tool('Read', { file_path => $o{read} }, join('', map { ++$i . "\t$_\n" } split /\n/, slurp($o{read})));
}
tool('Bash', { command => 'ls', description => 'list' }, "a.txt\n", cwd => $o{othercwd}) if defined $o{othercwd};
tool('Bash', { command => 'ls', description => 'list' }, "a.txt\n", reqeffort => 'low') if $flag{low};
tool('Bash', { command => 'ls', description => 'list' }, "a.txt\n", effort => 'low') if $flag{lowline};
push @L, '{"type":"user","message":{"role":"user","content":"cut' if $flag{garbage};
if ($flag{synthetic}) { assistant(content => [{ type => 'text', text => 'API Error: the request failed' }], id => 'msg-synthetic', model => '<synthetic>') }
unless ($flag{partial}) {
  request($o{effort});
  if (defined $o{handback}) {
    assistant(content => [{ type => 'tool_use', id => $o{handback}, name => 'SubagentHandback', input => { message => $o{hbmsg} // $report } }], id => 'msg-final', stop => 'tool_use');
    push @L, ${ o(parentUuid => 'x', isSidechain => \'true', promptId => 'p', agentId => $aid, type => 'user',
      message => o(role => 'user', content => [$flag{hbdenied} ? { tool_use_id => $o{handback}, type => 'tool_result', content => 'PreToolUse:SubagentHandback hook error: no', is_error => \1 }
        : { tool_use_id => $o{handback}, type => 'tool_result', content => [{ type => 'text', text => '{"success":true,"message":"Report delivered to your caller."}' }] }]),
      idf(), tailf()) };
  } else {
    assistant(content => [{ type => 'thinking', thinking => '', signature => 'sig' }], id => 'msg-final') if $flag{dup};
    assistant(content => [{ type => 'text', text => $report }], id => 'msg-final', index => $flag{dup} ? 1 : 0);
  }
  snapshot(tools => [{ name => 'Read', description => 'reads a file' }]) unless $flag{nosnap};
}
open my $f, '>:raw', $out or die "rec: cannot write $out\n";
print $f map { "$_\n" } @L;
close $f or die;
REC

# mk KEY=VALUE...: a hook input as JSON; a VALUE that starts with "json:" is
# JSON, one that starts with "file:" is a file's text; session_id and cwd
# are filled in unless given
mk() {
  CWD="$proj" perl -MJSON::PP -e '
    my $cwd = $ENV{CWD}; utf8::decode($cwd); my %h = (session_id => "s-1", cwd => $cwd);
    for (@ARGV) {
      my ($k, $v) = /\A([^=]+)=(.*)\z/s or die "bad pair $_\n";
      if ($v =~ s/\Ajson://) { $v = JSON::PP->new->utf8->allow_nonref->decode($v) }
      elsif ($v =~ s/\Afile://) { open my $f, "<:raw", $v or die; local $/; $v = <$f>; utf8::decode($v) }
      else { utf8::decode($v) }
      $h{$k} = $v;
    }
    print JSON::PP->new->utf8->canonical->encode(\%h)' "$@"
}
# run JSON [VAR=VALUE...]: the hook as Claude Code runs it; sets out, err and code
run() {
  printf '%s' "$1" >"$work/in.json"
  shift
  out=$(cd "$proj" && env -u CLAUDE_CODE_EXECPATH CLAUDE_PROJECT_DIR="$proj" "$@" perl -e 'alarm 60; exec @ARGV' bash "$hook" <"$work/in.json" 2>"$work/err")
  code=$?
  err=$(cat "$work/err")
}
# cutoff WHEN JSON: the hook run with JSON, killed with every process it
# started (as the client kills a hook at its time-out) once WHEN holds:
# WHEN is a number of seconds, or a file that exists (at most 30 s)
cutoff() {
  printf '%s' "$2" >"$work/in.json"
  (cd "$proj" && env -u CLAUDE_CODE_EXECPATH CLAUDE_PROJECT_DIR="$proj" perl -MTime::HiRes=sleep,time -e '
    my ($when, @cmd) = @ARGV;
    my $secs = $when =~ /\A[0-9.]+\z/;
    my $pid = fork;
    die "cutoff: cannot fork\n" unless defined $pid;
    if (!$pid) { setpgrp(0, 0); exec @cmd or exit 127 }
    my $until = time + ($secs ? $when : 30);
    sleep 0.01 until time > $until || (!$secs && -e $when);
    kill "KILL", -$pid;
    waitpid $pid, 0;' "$1" bash "$hook" <"$work/in.json" >/dev/null)
}
# field AGENT RUN KEY: a field of the receipt of the agent's run RUN (1 for
# its first: receipts are named by session, agent and run number, never by
# the prompt id; KEY may name a field inside another, as tokens.input;
# arrays joined by commas), or "absent" when there is no receipt
field() {
  COMMON="$common" A="$1" R="$2" K="$3" perl -MJSON::PP -MDigest::SHA=sha256_hex -e '
    my $n = "method-receipt-" . substr(sha256_hex("receipt\0s-1\0$ENV{A}"), 0, 16) . sprintf("%08x", $ENV{R}) . ".json";
    open my $f, "<", "$ENV{COMMON}/$n" or do { print "absent"; exit };
    local $/; my $v = JSON::PP->new->decode(<$f>); $v = ref $v eq "HASH" ? $v->{$_} : undef for split /\./, $ENV{K};
    print ref $v eq "ARRAY" ? join(",", @$v) : ref $v eq "HASH" ? "hash" : defined $v ? $v : "null"'
}
# runfiles AGENT: how many running files of the agent's runs git's folder
# holds
runfiles() { find "$common" -maxdepth 1 -name "method-running-$(perl -MDigest::SHA=sha256_hex -e 'print substr(sha256_hex("receipt\0s-1\0$ARGV[0]"), 0, 16)' "$1")*" | wc -l | tr -d ' '; }
# says AGENT RUN: the receipt's state, then its reasons
says() { printf '%s:%s' "$(field "$1" "$2" state)" "$(field "$1" "$2" why)"; }
is() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got: $2
wanted: $3"; fi
}
report() { printf '%s\n' "$@" >"$work/report.txt"; }
start() { run "$(mk hook_event_name=SubagentStart agent_type="$1" agent_id="$2" prompt_id="$3")"; }
# rec GATE AGENT [OPTION...]: the agent's record, at the path its stop names
rec() {
  g=$1
  a=$2
  shift 2
  GATE=$g AID=$a CWD="$proj" REPORT="$work/report.txt" perl "$work/rec.pl" "$recs/agent-$a.jsonl" "$@" || abort_sandbox
}
# stop GATE AGENT PROMPT [MODE [OPTION...]]: the stop, in MODE (default
# mode when empty), after its record is written with the OPTIONs (a
# record with the report in report.txt); an OPTION "in:KEY=VALUE" goes to
# the input instead, and "asis" leaves the record as it is
stop() {
  g=$1
  a=$2
  p=$3
  m=${4:-default}
  if [ $# -ge 4 ]; then shift 4; else shift $#; fi
  extra=()
  rargs=()
  asis=0
  for o in "$@"; do
    case "$o" in
      in:*) extra+=("${o#in:}") ;;
      asis) asis=1 ;;
      *) rargs+=("$o") ;;
    esac
  done
  [ "$asis" = 1 ] || rec "$g" "$a" ${rargs[@]+"${rargs[@]}"}
  run "$(mk hook_event_name=SubagentStop agent_type="$g" agent_id="$a" prompt_id="$p" permission_mode="$m" last_assistant_message="file:$work/report.txt" effort='json:{"level":"xhigh"}' stop_hook_active=json:false background_tasks='json:[]' agent_transcript_path="$recs/agent-$a.jsonl" ${extra[@]+"${extra[@]}"})"
}
# astop GATE AGENT PROMPT [OPTION...]: an auto-mode stop after a handback
# (its record holds the handback of report.txt, toolu_AGENT, accepted)
astop() {
  g=$1
  a=$2
  p=$3
  shift 3
  rec "$g" "$a" "handback=toolu_$a" "$@"
  run "$(mk hook_event_name=SubagentStop agent_type="$g" agent_id="$a" prompt_id="$p" permission_mode=auto effort='json:{"level":"xhigh"}' stop_hook_active=json:false background_tasks='json:[]' agent_transcript_path="$recs/agent-$a.jsonl")"
}
handback() { run "$(mk hook_event_name=PreToolUse tool_name=SubagentHandback agent_type="$1" agent_id="$2" prompt_id="$3" permission_mode=auto tool_use_id="toolu_$2" tool_input="json:$(perl -MJSON::PP -e 'local $/; print JSON::PP->new->encode({message => scalar <STDIN>})' <"$work/report.txt")")"; }
# commit MESSAGE: the project's changes committed
commit() { (cd "$proj" && git add -A && git commit -qm "$1") || abort_sandbox; }

# === 5b.1: the gate's life ===

# --- the start ---
if wanted_any "a gate's start is answered with its context line, the gate and the tree" "the start writes a receipt in git's folder: not checked, running" "the receipt holds the start's tree" "the start writes a running file" "an agent that is not a gate gets nothing and no receipt" "an agent id that is not a plain id gets nothing"; then
  start method-reviewer a1 p1
  is "a gate's start is answered with its context line, the gate and the tree" "$code:$out" "0:{\"hookSpecificOutput\":{\"additionalContext\":\"METHOD-ACTIVE gate=method-reviewer tree=$tree\",\"hookEventName\":\"SubagentStart\"}}"
  is "the start writes a receipt in git's folder: not checked, running" "$(field a1 1 state):$(field a1 1 why)" "INCOMPLETE:running"
  is "the receipt holds the start's tree, that the files were clean, the method file's effort" "$(field a1 1 tree):$(field a1 1 clean_start):$(field a1 1 effort_file)" "$tree:1:xhigh"
  n=$(find "$common" -maxdepth 1 -name 'method-running-*' | wc -l | tr -d ' ')
  is "the start writes a running file in git's folder, so the guard marks writes" "$n" "1"
  start my-method-reviewer a9 p9
  is "an agent that is not a gate gets nothing and no receipt" "$code:$out:$(field a9 1 state)" "0::absent"
  run "$(mk hook_event_name=SubagentStart agent_type=method-reviewer agent_id='a b' prompt_id=p1)"
  is "an agent id that is not a plain id gets nothing" "$code:$out" "0:"
  rm -f "$common"/method-running-*
fi

# --- a good report ---
if wanted_any "a report with both lines: exit 0, nothing printed" "its receipt is good, with its opening word" "gates.log gets one fixed-field line" "the stop removes the running file" "the receipt keeps the models, efforts and tokens"; then
  start method-reviewer b1 p1
  report "APPROVE" "Summary: fine." "END-VERDICT $tree"
  stop method-reviewer b1 p1
  is "a report with both lines: exit 0, nothing printed" "$code:$out:$err" "0::"
  is "its receipt is good, with its opening word" "$(field b1 1 state):$(field b1 1 open):$(field b1 1 why)" "VALID:APPROVE:"
  if LC_ALL=C grep -q "	VALID	method-reviewer	$tree	claude-opus-5-5	xhigh	none\$" "$proj/.method/local/gates.log"; then
    pass "gates.log gets one fixed-field line: the word, the gate, the tree, the first model, the effort, the reason"
  else
    fail "gates.log gets one fixed-field line" "$(cat "$proj/.method/local/gates.log" 2>&1)"
  fi
  n=$(find "$common" -maxdepth 1 -name 'method-running-*' | wc -l | tr -d ' ')
  is "the stop removes the running file" "$n" "0"
  is "the receipt keeps the models, efforts and tokens (11 in, 7 out, 3 and 5 cached)" "$(field b1 1 models):$(field b1 1 efforts):$(field b1 1 tokens.input):$(field b1 1 tokens.output):$(field b1 1 tokens.cache_creation):$(field b1 1 tokens.cache_read)" "claude-opus-5-5:xhigh:11:7:3:5"
fi
if wanted_any "an opening word alone, or followed by a space or a colon, is read: "; then
  for first in "REQUEST CHANGES: two findings" "ESCALATE a person must decide" "REJECT"; do
    aid=$(printf '%s' "$first" | tr -c 'A-Za-z' 'x')
    start method-security-checker "$aid" pb
    report "$first" "body" "END-VERDICT $tree"
    stop method-security-checker "$aid" pb
    is "an opening word alone, or followed by a space or a colon, is read: $first" "$(field "$aid" 1 state)" "VALID"
  done
fi
if wanted_any "diagnose opens with its own words" "the tester opens with its own words" "another gate's word is not the tester's"; then
  start method-diagnose d1 pd
  report "ROOT CAUSE: the cache" "END-VERDICT $tree"
  stop method-diagnose d1 pd
  is "diagnose opens with its own words" "$(field d1 1 state):$(field d1 1 open)" "VALID:ROOT CAUSE"
  start method-tester t1 pt
  report "TESTS NOT RUN" "END-VERDICT $tree"
  stop method-tester t1 pt
  is "the tester opens with its own words" "$(field t1 1 state):$(field t1 1 open)" "VALID:TESTS NOT RUN"
  start method-tester t2 pt
  report "APPROVE" "END-VERDICT $tree"
  stop method-tester t2 pt
  is "another gate's word is not the tester's" "$code" "2"
fi
if wanted "trailing spaces, CRs and blank lines around the lines are let be"; then
  printf 'APPROVE  \r\n\r\nbody\r\nEND-VERDICT %s \r\n\r\n' "$tree" >"$work/report.txt"
  start method-reviewer a2 p2
  stop method-reviewer a2 p2
  is "trailing spaces, CRs and blank lines around the lines are let be" "$code:$(field a2 1 state)" "0:VALID"
fi

# --- a report without its lines: sent back once (B6) ---
if wanted_any "a first line that is not a word is sent back: "; then
  for bad in "**APPROVE**" "# APPROVE" " APPROVE" "APPROVED" "approve"; do
    aid=$(printf '%s' "$bad" | tr -c 'A-Za-z' 'x')
    start method-reviewer "$aid" p3
    report "$bad" "END-VERDICT $tree"
    stop method-reviewer "$aid" p3
    is "a first line that is not a word is sent back: '$bad'" "$code" "2"
  done
fi
if wanted_any "an end line with another tree is sent back" "the block names both exact lines" "the receipt says it was sent back, before the gate answers again" "the report sent again with its lines: good"; then
  start method-reviewer a4 p4
  report "APPROVE" "END-VERDICT 0000000"
  stop method-reviewer a4 p4
  is "an end line with another tree is sent back" "$code" "2"
  case "$err" in
    "gate-receipt: your report must open with one of these words on its first line, alone or followed by a space or a colon: APPROVE, REQUEST CHANGES, REJECT, ESCALATE; and its last line must be exactly: END-VERDICT $tree. Send your whole report again in that form.") pass "the block names both exact lines and asks for the whole report again" ;;
    *) fail "the block names both exact lines" "$err" ;;
  esac
  is "the receipt says it was sent back, before the gate answers again" "$(field a4 1 blocked):$(field a4 1 state):$(field a4 1 why)" "1:INCOMPLETE:lines-missing"
  report "APPROVE" "fixed" "END-VERDICT $tree"
  stop method-reviewer a4 p4
  is "the report sent again with its lines: good" "$code:$(field a4 1 state):$(field a4 1 stops)" "0:VALID:2"
fi
if wanted_any "still without its lines: let go once, not checked" "no report at all: sent back once"; then
  start method-reviewer a5 p5
  report "nothing useful"
  stop method-reviewer a5 p5
  report "still nothing"
  stop method-reviewer a5 p5
  is "still without its lines: let go once, not checked" "$code:$(field a5 1 state):$(field a5 1 why)" "0:INCOMPLETE:lines-missing-after-retry"
  start method-reviewer a6 p6
  run "$(mk hook_event_name=SubagentStop agent_type=method-reviewer agent_id=a6 prompt_id=p6 permission_mode=default)"
  is "no report at all: sent back once" "$code:$(field a6 1 why)" "2:no-report"
fi

# --- auto mode (B7) ---
if wanted_any "a handback without its lines is refused once" "the second handback without its lines is let through" "then the receipt says not checked, and the stop does not block"; then
  start method-reviewer h1 ph
  report "my findings, no verdict"
  handback method-reviewer h1 ph
  case "$code:$out" in
    "0:{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"gate-receipt: your report must open with"*) pass "a handback without its lines is refused once, with the exact lines" ;;
    *) fail "a handback without its lines is refused once" "$code:$out" ;;
  esac
  handback method-reviewer h1 ph
  is "the second handback without its lines is let through" "$code:$out" "0:"
  astop method-reviewer h1 ph
  is "then the receipt says not checked, and the stop does not block" "$code:$(field h1 1 state):$(field h1 1 why)" "0:INCOMPLETE:lines-missing-after-retry"
fi
if wanted_any "a handback with its lines is let through, and noted" "its stop (no last message after a handback) is good"; then
  start method-reviewer h2 ph
  report "REQUEST CHANGES" "one finding" "END-VERDICT $tree"
  handback method-reviewer h2 ph
  is "a handback with its lines is let through, and noted" "$code:$out:$(field h2 1 handback)" "0::hash"
  astop method-reviewer h2 ph
  is "its stop (no last message after a handback) is good" "$code:$(field h2 1 state):$(field h2 1 open)" "0:VALID:REQUEST CHANGES"
fi
if wanted "auto mode with no handback: no report was delivered; no block"; then
  start method-reviewer h3 ph
  report "APPROVE" "END-VERDICT $tree"
  stop method-reviewer h3 ph auto
  is "auto mode with no handback: no report was delivered; no block" "$code:$(field h3 1 state):$(field h3 1 why)" "0:INCOMPLETE:no-report"
fi

# --- runs that cannot be judged ---
if wanted "a stop with no start: not checked, never blocked"; then
  report "APPROVE" "END-VERDICT $tree"
  stop method-reviewer n1 pn
  is "a stop with no start: not checked, never blocked" "$code:$(field n1 1 state):$(field n1 1 why)" "0:INCOMPLETE:no-start"
fi
# (step 5b's review, F1: a receipt the handback or an earlier stop made has
# no start either)
if wanted_any "a handback with no start, then its stop: not checked" "a second stop of a run with no start: not checked, never blocked"; then
  report "my findings, no verdict"
  handback method-reviewer n2 pn
  report "APPROVE" "END-VERDICT $tree"
  handback method-reviewer n2 pn
  astop method-reviewer n2 pn
  is "a handback with no start, then its stop: not checked (no-start), never the first word" "$code:$(says n2 1):$(field n2 1 denied)" "0:INCOMPLETE:no-start:1"
  stop method-reviewer n3 pn
  stop method-reviewer n3 pn
  first=$code:$(says n3 1)
  report "my findings, no verdict"
  stop method-reviewer n3 pn
  is "a second stop of a run with no start: not checked, never blocked (with its lines, then without)" "$first;$code:$(says n3 1):$(field n3 1 stops)" "0:INCOMPLETE:no-start;0:INCOMPLETE:no-start,lines-missing:3"
fi
# a start cut off at its time-out (the client kills the hook's processes)
# while it looks at the files: its run is not checked, and no earlier run
# of the agent is judged in its place. (A large untracked file keeps the
# clean check busy; the start is killed once its run's receipt is there)
if wanted "a start cut off before it has looked at the files leaves its run not checked"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer k9 pk1
  stop method-reviewer k9 pk1
  perl -e 'open my $f, ">", $ARGV[0] or die; truncate $f, 1536 * 1024 * 1024 or die' "$proj/big.bin"
  cutoff "$common/method-receipt-$(perl -MDigest::SHA=sha256_hex -e 'print substr(sha256_hex("receipt\0s-1\0k9"), 0, 16)')00000002.json" \
    "$(mk hook_event_name=SubagentStart agent_type=method-reviewer agent_id=k9 prompt_id=pk2)"
  rm -f "$proj/big.bin"
  stop method-reviewer k9 pk2
  is "a start cut off before it has looked at the files leaves its run not checked (no-start), and no earlier run judged in its place" "$(says k9 2):$(field k9 1 state):$(field k9 1 why):$(field k9 1 stops):$(runfiles k9)" "INCOMPLETE:no-start:INCOMPLETE:resumed-after-report:1:0"
fi
if wanted_any "a background gate's first run is good" "resumed under the same agent id, its earlier receipt no longer stands" "a start makes the agent's next run"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer r1 pr1
  stop method-reviewer r1 pr1
  is "a background gate's first run is good" "$(field r1 1 state)" "VALID"
  # (the same prompt id: a run is told by its number, not its prompt)
  start method-reviewer r1 pr1
  is "resumed under the same agent id, its earlier receipt no longer stands" "$(field r1 1 state):$(field r1 1 why)" "INCOMPLETE:resumed-after-report"
  is "a start makes the agent's next run, whatever its prompt id (run 2: not checked, running; run 1 kept)" "$(field r1 2 state):$(field r1 2 why):$(field r1 2 run):$(field r1 1 run)" "INCOMPLETE:running:2:1"
  stop method-reviewer r1 pr9
  is "a start makes the agent's next run: its stop judges run 2" "$(says r1 2):$(field r1 1 why):$(runfiles r1)" "VALID::resumed-after-report:0"
  rm -f "$common"/method-running-*
fi
# --- the prompt id is the owner's message, not the run's (2.1.316, 2.1.319) ---
if wanted_any "a background gate whose stop comes after the owner's next message gets its run's receipt" "a handback after the owner's next message is noted in its run's receipt" "a stop with no prompt id takes the agent's newest run"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer q1 pq1
  stop method-reviewer q1 pq2
  is "a background gate whose stop comes after the owner's next message gets its run's receipt: VALID, its running file removed" "$(says q1 1):$(field q1 2 state):$(runfiles q1)" "VALID::absent:0"
  start method-reviewer q2 pq1
  handback method-reviewer q2 pq2
  astop method-reviewer q2 pq3
  is "a handback after the owner's next message is noted in its run's receipt, and its stop is VALID" "$(says q2 1):$(field q2 1 handback):$(runfiles q2)" "VALID::hash:0"
  start method-reviewer q3 pq1
  stop method-reviewer q3 ""
  is "a stop with no prompt id takes the agent's newest run" "$(says q3 1):$(runfiles q3)" "VALID::0"
fi
if wanted_any "input that is not JSON: exit 0, nothing printed" "outside a git repository: tree=none, no receipt"; then
  printf 'not json' >"$work/in.json"
  out=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" bash "$hook" <"$work/in.json" 2>&1)
  is "input that is not JSON: exit 0, nothing printed" "$?:$out" "0:"
  mkdir -p "$work/nogit"
  out=$(cd "$work/nogit" && printf '%s' "$(CWD="$work/nogit" mk hook_event_name=SubagentStart agent_type=method-reviewer agent_id=g1 prompt_id=pg cwd="$work/nogit")" | CLAUDE_PROJECT_DIR="$work/nogit" bash "$hook" 2>&1)
  is "outside a git repository: tree=none, no receipt" "$?:$out" "0:{\"hookSpecificOutput\":{\"additionalContext\":\"METHOD-ACTIVE gate=method-reviewer tree=none\",\"hookEventName\":\"SubagentStart\"}}"
fi

# --- the wrapper (B11): only a deliberate block exits 2 ---
if wanted_any "a crash is exit 0, with nothing printed" "code 3 with its line is the one way to exit 2" "code 3 without its line is exit 0" "missing scripts are exit 0" "no perl is exit 0"; then
  copy="$work/copy"
  mkdir -p "$copy/.claude/hooks/method" "$copy/scripts/method/lib"
  cp "$hook" "$copy/.claude/hooks/method/"
  cp "$root/method/scripts/method/lib/"*.pl "$root/method/scripts/method/lib/hook-env.sh" "$copy/scripts/method/lib/"
  cp "$root/method/scripts/method/verdicts.txt" "$copy/scripts/method/"
  report "nothing"
  stop_json=$(mk hook_event_name=SubagentStop agent_type=method-reviewer agent_id=w1 prompt_id=pw permission_mode=default last_assistant_message="file:$work/report.txt")
  printf 'die "boom\\n";\n' >"$copy/scripts/method/lib/receipt.pl"
  out=$(cd "$proj" && printf '%s' "$stop_json" | CLAUDE_PROJECT_DIR="$proj" bash "$copy/.claude/hooks/method/gate-receipt.sh" 2>&1)
  is "a crash is exit 0, with nothing printed" "$?:$out" "0:"
  printf 'print STDERR "gate-receipt: no\\n"; exit 3;\n' >"$copy/scripts/method/lib/receipt.pl"
  out=$(cd "$proj" && printf '%s' "$stop_json" | CLAUDE_PROJECT_DIR="$proj" bash "$copy/.claude/hooks/method/gate-receipt.sh" 2>&1)
  is "code 3 with its line is the one way to exit 2" "$?:$out" "2:gate-receipt: no"
  printf 'print STDERR "something else\\n"; exit 3;\n' >"$copy/scripts/method/lib/receipt.pl"
  out=$(cd "$proj" && printf '%s' "$stop_json" | CLAUDE_PROJECT_DIR="$proj" bash "$copy/.claude/hooks/method/gate-receipt.sh" 2>&1)
  is "code 3 without its line is exit 0" "$?:$out" "0:"
  rm -f "$copy/scripts/method/lib/receipt.pl"
  out=$(cd "$proj" && printf '%s' "$stop_json" | CLAUDE_PROJECT_DIR="$proj" bash "$copy/.claude/hooks/method/gate-receipt.sh" 2>&1)
  is "missing scripts are exit 0" "$?:$out" "0:"
  mkdir -p "$work/noperl"
  for t in bash sh sed cat env dirname; do p=$(command -v "$t") && ln -s "$p" "$work/noperl/$t"; done
  out=$(cd "$proj" && printf '%s' "$stop_json" | PATH="$work/noperl" CLAUDE_PROJECT_DIR="$proj" "$work/noperl/bash" "$hook" 2>&1)
  is "no perl is exit 0" "$?:$out" "0:"
fi

# --- the context line's size (B3), with a SHA-256 repository ---
if wanted_any "the longest gate name with a SHA-256 tree fits in 120 bytes" "the context line with a SHA-256 tree"; then
  if git init -q --object-format=sha256 "$work/sha256" 2>/dev/null; then
    (cd "$work/sha256" && printf 'a\n' >a.txt && git add a.txt && git commit -qm one) || abort_sandbox
    t256=$(git -C "$work/sha256" rev-parse 'HEAD^{tree}')
    out=$(cd "$work/sha256" && printf '%s' "$(CWD="$work/sha256" mk hook_event_name=SubagentStart agent_type=method-security-checker agent_id=c1 prompt_id=pc cwd="$work/sha256")" | CLAUDE_PROJECT_DIR="$work/sha256" bash "$hook" 2>&1)
    line="METHOD-ACTIVE gate=method-security-checker tree=$t256"
    case "$out" in *"\"$line\""*) if [ "${#line}" -le 120 ]; then pass "the longest gate name with a SHA-256 tree fits in 120 bytes (${#line})"; else fail "the context line fits in 120 bytes" "${#line}"; fi ;; *) fail "the context line with a SHA-256 tree" "$out" ;; esac
  else
    skip "SHA-256 repository: this git cannot make one"
  fi
fi

# === 5b.2: the evidence ===

# --- G: clean and the same tree, at start and stop ---
if wanted_any "files not clean at the start make it INVALID" "a report without its lines is not sent back when the start already makes it INVALID"; then
  report "APPROVE" "END-VERDICT $tree"
  printf 'x\n' >"$proj/untracked.txt"
  start method-reviewer g1 pg
  rm -f "$proj/untracked.txt"
  stop method-reviewer g1 pg
  is "files not clean at the start make it INVALID (unclean-start; an untracked file counts)" "$(says g1 1)" "INVALID:unclean-start"
  printf 'x\n' >"$proj/untracked.txt"
  start method-reviewer g2 pg
  rm -f "$proj/untracked.txt"
  report "my findings, no verdict"
  stop method-reviewer g2 pg
  is "a report without its lines is not sent back when the start already makes it INVALID; INVALID's reasons come first" "$code:$(says g2 1)" "0:INVALID:unclean-start,lines-missing"
fi
if wanted "files not clean at the stop make it INVALID"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer g3 pg
  printf 'x\n' >"$proj/untracked.txt"
  stop method-reviewer g3 pg
  rm -f "$proj/untracked.txt"
  is "files not clean at the stop make it INVALID (unclean-stop)" "$(says g3 1)" "INVALID:unclean-stop"
fi
if wanted "a tree changed while the gate ran makes it INVALID"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer g4 pg
  printf 'b\n' >"$proj/a.txt"
  commit "a change while the gate ran"
  stop method-reviewer g4 pg
  git -C "$proj" reset -q --hard HEAD~1
  is "a tree changed while the gate ran makes it INVALID (tree-changed), though the files are clean" "$(says g4 1)" "INVALID:tree-changed"
fi
if wanted "a stop run from another repository leaves the files not checked"; then
  report "APPROVE" "END-VERDICT $tree"
  mkdir -p "$work/other"
  (cd "$work/other" && git init -q && printf 'z\n' >z.txt && git add z.txt && git commit -qm other) || abort_sandbox
  start method-reviewer g6 pg
  stop method-reviewer g6 pg default "in:cwd=$work/other"
  is "a stop run from another repository leaves the files not checked (clean-unknown: the main session moved; its files are not the gate's)" "$(says g6 1)" "INCOMPLETE:clean-unknown"
fi
if wanted "files that cannot be told clean leave it not checked"; then
  report "APPROVE" "END-VERDICT $tree"
  git -C "$proj" config 'filter.a=b.clean' cat
  start method-reviewer g5 pg
  stop method-reviewer g5 pg
  git -C "$proj" config --unset 'filter.a=b.clean'
  is "files that cannot be told clean leave it not checked (clean-unknown: a filter git cannot be told to skip)" "$(says g5 1)" "INCOMPLETE:clean-unknown"
fi

# --- M: the guard's write marks ---
# guard IN-PAIRS...: the guard as Claude Code runs it, with a PreToolUse input
guard() {
  printf '%s' "$(mk hook_event_name=PreToolUse permission_mode=default transcript_path="$HOME/.claude/projects/proj/s-1.jsonl" "$@")" >"$work/guard-in.json"
  gout=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" bash "$guard" <"$work/guard-in.json" 2>&1)
  gcode=$?
}
if wanted_any "a write by the main session while the gate runs makes it INVALID" "the guard's answer to that write is unchanged"; then
  report "APPROVE" "END-VERDICT $tree"
  rm -f "$common"/method-running-*
  start method-reviewer m1 pm
  guard tool_name=Write tool_use_id=toolu_w1 tool_input="json:{\"file_path\":\"$proj/notes.txt\",\"content\":\"x\"}"
  is "the guard's answer to that write is unchanged: let through, nothing printed" "$gcode:$gout" "0:"
  stop method-reviewer m1 pm
  is "a write by the main session while the gate runs makes it INVALID (write-mark), though nothing changed on disk" "$(says m1 1)" "INVALID:write-mark"
fi
if wanted "the gate's own writes leave no mark"; then
  report "APPROVE" "END-VERDICT $tree"
  rm -f "$common"/method-running-*
  start method-reviewer m2 pm
  guard agent_id=m2 agent_type=method-reviewer tool_name=Write tool_use_id=toolu_w2 tool_input="json:{\"file_path\":\"$proj/notes.txt\",\"content\":\"x\"}"
  guard agent_id=m2 agent_type=method-reviewer tool_name=Bash tool_use_id=toolu_w3 tool_input='json:{"command":"touch notes.txt"}'
  stop method-reviewer m2 pm
  is "the gate's own writes leave no mark: its receipt is VALID" "$(says m2 1)" "VALID:"
fi
if wanted "a mark before the gate's start does not count"; then
  report "APPROVE" "END-VERDICT $tree"
  rm -f "$common"/method-running-*
  : >"$common/method-running-000000000000000000000000"
  guard tool_name=Write tool_use_id=toolu_w4 tool_input="json:{\"file_path\":\"$proj/notes.txt\",\"content\":\"x\"}"
  rm -f "$common/method-running-000000000000000000000000"
  start method-reviewer m3 pm
  stop method-reviewer m3 pm
  is "a mark before the gate's start does not count" "$(says m3 1)" "VALID:"
fi
if wanted "a write in another worktree of the repository does not count"; then
  report "APPROVE" "END-VERDICT $tree"
  rm -f "$common"/method-running-*
  git -C "$proj" worktree add -q "$work/wt2" -b wt2 2>/dev/null || abort_sandbox
  start method-reviewer m5 pm
  guard tool_name=Write tool_use_id=toolu_w5 cwd="$work/wt2" tool_input="json:{\"file_path\":\"$work/wt2/notes.txt\",\"content\":\"x\"}"
  stop method-reviewer m5 pm
  git -C "$proj" worktree remove --force "$work/wt2"
  is "a write in another worktree of the repository does not count (its mark names that worktree)" "$(says m5 1)" "VALID:"
fi
if wanted "a running file left by a crash a day ago is removed at the next start"; then
  report "APPROVE" "END-VERDICT $tree"
  : >"$common/method-running-111111111111111111111111"
  touch -t 200001010000 "$common/method-running-111111111111111111111111"
  start method-reviewer m6 pm
  if [ -e "$common/method-running-111111111111111111111111" ]; then fail "a running file left by a crash a day ago is removed at the next start"; else pass "a running file left by a crash a day ago is removed at the next start"; fi
  rm -f "$common"/method-running-*
fi
# (step 5b's review, F3: auto mode's nudges after a stop with no handback)
if wanted_any "auto mode: a stop with no handback keeps the running file" "a write while the client nudges the gate on is marked"; then
  report "APPROVE" "END-VERDICT $tree"
  rm -f "$common"/method-running-*
  start method-reviewer m7 pm
  stop method-reviewer m7 pm auto
  is "auto mode: a stop with no handback keeps the running file (no report yet; the client nudges the gate on)" "$(says m7 1):$(runfiles m7)" "INCOMPLETE:no-report:1"
  guard tool_name=Write tool_use_id=toolu_w7 tool_input="json:{\"file_path\":\"$proj/notes.txt\",\"content\":\"x\"}"
  handback method-reviewer m7 pm
  astop method-reviewer m7 pm
  is "a write while the client nudges the gate on is marked: INVALID write-mark at the later stop, which removes the running file" "$(says m7 1):$(field m7 1 stops):$(runfiles m7)" "INVALID:write-mark:2:0"
fi
if wanted "marks that cannot be read leave it not checked"; then
  report "APPROVE" "END-VERDICT $tree"
  mv "$common/method-write-marks" "$work/marks.keep" 2>/dev/null
  mkdir "$common/method-write-marks"
  start method-reviewer m4 pm
  stop method-reviewer m4 pm
  rmdir "$common/method-write-marks"
  [ ! -e "$work/marks.keep" ] || mv "$work/marks.keep" "$common/method-write-marks"
  is "marks that cannot be read leave it not checked (marks-unreadable)" "$(says m4 1)" "INCOMPLETE:marks-unreadable"
fi

# --- R: the agent's record ---
if wanted "a record written 0.3 s after the stop began still makes it VALID"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer r2 pr
  rm -f "$recs/agent-r2.jsonl"
  GATE=method-reviewer AID=r2 CWD="$proj" REPORT="$work/report.txt" perl "$work/rec.pl" "$work/late.jsonl" || abort_sandbox
  late_in=$(mk hook_event_name=SubagentStop agent_type=method-reviewer agent_id=r2 prompt_id=pr permission_mode=default last_assistant_message="file:$work/report.txt" effort='json:{"level":"xhigh"}' stop_hook_active=json:false background_tasks='json:[]' agent_transcript_path="$recs/agent-r2.jsonl")
  # (0.3 s after the hook starts: the client may finish the record after
  # the stop's event)
  (perl -e 'select undef, undef, undef, 0.3' && mv "$work/late.jsonl" "$recs/agent-r2.jsonl") &
  run "$late_in"
  wait
  is "a record written 0.3 s after the stop began still makes it VALID" "$(says r2 1)" "VALID:"
fi
if wanted "a model off the project's list makes it INVALID"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer r3 pr
  stop method-reviewer r3 pr default model=claude-haiku-4-5
  is "a model off the project's list makes it INVALID (model-off-list)" "$(says r3 1):$(field r3 1 models)" "INVALID:model-off-list:claude-haiku-4-5"
fi
if wanted "no availableModels in the project's settings makes it INVALID"; then
  report "APPROVE" "END-VERDICT $tree"
  printf '{}\n' >"$proj/.claude/settings.json"
  commit "no model list"
  t2=$(git -C "$proj" rev-parse 'HEAD^{tree}')
  report "APPROVE" "END-VERDICT $t2"
  start method-reviewer r4 pr
  stop method-reviewer r4 pr
  git -C "$proj" reset -q --hard HEAD~1
  is "no availableModels in the project's settings makes it INVALID (model-off-list)" "$(says r4 1)" "INVALID:model-off-list"
fi
if wanted "a reply the client wrote itself leaves it not checked"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer r5 pr
  stop method-reviewer r5 pr default synthetic
  is "a reply the client wrote itself leaves it not checked (synthetic-reply; <synthetic> is no model off the list)" "$(says r5 1):$(field r5 1 models)" "INCOMPLETE:synthetic-reply:claude-opus-5-5"
fi
if wanted "a record with no model line leaves it not checked"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer r6 pr
  stop method-reviewer r6 pr default 'model=<synthetic>'
  is "a record with no model line leaves it not checked (no-model)" "$(says r6 1)" "INCOMPLETE:synthetic-reply,no-model"
fi
if wanted "a request at effort low makes it INVALID"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer r7 pr
  stop method-reviewer r7 pr default low
  is "a request at effort low makes it INVALID (effort-low: the method file says xhigh)" "$(says r7 1):$(field r7 1 efforts)" "INVALID:effort-low:low,xhigh"
fi
if wanted "an assistant line at effort low makes it INVALID"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer r10 pr
  stop method-reviewer r10 pr default lowline
  is "an assistant line at effort low makes it INVALID (effort-low)" "$(says r10 1):$(field r10 1 efforts)" "INVALID:effort-low:xhigh,low"
fi
if wanted "with reasons of both kinds, INVALID, its reasons first"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer r11 pr
  stop method-reviewer r11 pr default synthetic model=claude-haiku-4-5
  is "with reasons of both kinds, INVALID, its reasons first" "$(says r11 1)" "INVALID:model-off-list,synthetic-reply"
fi
if wanted "a record with no effort leaves it not checked"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer r8 pr
  stop method-reviewer r8 pr default noeffort
  is "a record with no effort leaves it not checked (no-effort)" "$(says r8 1)" "INCOMPLETE:no-effort"
fi
if wanted_any "a method file without its effort makes it INVALID" "a report without its lines is not sent back when the method file lacks its effort"; then
  perl -0pi -e 's/^effort: xhigh\n//m' "$proj/.claude/agents/method/method-diagnose.md"
  commit "no effort"
  t2=$(git -C "$proj" rev-parse 'HEAD^{tree}')
  report "ROOT CAUSE" "END-VERDICT $t2"
  start method-diagnose r9 pr
  stop method-diagnose r9 pr
  is "a method file without its effort makes it INVALID (instructions-differ)" "$(says r9 1)" "INVALID:instructions-differ"
  report "my findings, no verdict"
  start method-diagnose r12 pr
  stop method-diagnose r12 pr
  is "a report without its lines is not sent back when the method file lacks its effort" "$code:$(says r12 1)" "0:INVALID:instructions-differ,lines-missing"
  git -C "$proj" reset -q --hard HEAD~1
fi
if wanted "instructions other than the method file's make it INVALID"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer s1 ps
  stop method-reviewer s1 ps default "prompt=You are a reviewer from another definition of method-reviewer."
  is "instructions other than the method file's make it INVALID (instructions-differ: a second definition)" "$(says s1 1)" "INVALID:instructions-differ"
fi
# (step 6.2) the method's own gate files, from method/.claude/agents/method/:
# each one's body, as the client sends it (trimmed), gives VALID with the
# first word of its gate's kind; the body as it read before an edit made
# after the start (one word changed in its first line) gives INVALID
# instructions-differ
if wanted_any "a method gate file's own body makes it VALID" "a method gate file edited after the start makes it INVALID"; then
  cp "$root"/method/.claude/agents/method/*.md "$proj/.claude/agents/method/"
  commit "the method's gate files"
  t3=$(git -C "$proj" rev-parse 'HEAD^{tree}')
  i=0
  for f in "$root"/method/.claude/agents/method/*.md; do
    i=$((i + 1))
    g=$(basename "$f" .md)
    first=$(cd "$root" && perl -e 'require "./method/scripts/method/lib/verdicts.pl"; my @r = Verdicts::rows(); my ($k) = map { $_->[1] } grep { $_->[0] eq $ARGV[0] } Verdicts::gates(@r); print +(Verdicts::words($k, @r))[0] if defined $k' "$g")
    body=$(perl -0ne 's/\A---[ \t]*\n.*?^---[ \t]*\n//ms or die; s/\A\s+//; s/\s+\z//; print' "$f")
    edited=$(printf '%s\n' "$body" | perl -pe 's/\bmethod\x27s\b/project\x27s/ if $. == 1')
    if [ -z "$first" ] || [ -z "$body" ] || [ "$edited" = "$body" ]; then
      fail "a method gate file's own body makes it VALID ($g): the case could not be made (word '$first')"
      continue
    fi
    report "$first" "END-VERDICT $t3"
    start "$g" "rb$i" pr
    stop "$g" "rb$i" pr default "prompt=$body"
    is "a method gate file's own body makes it VALID ($g, $first)" "$(says "rb$i" 1):$(field "rb$i" 1 effort_file)" "VALID::xhigh"
    start "$g" "re$i" pr
    stop "$g" "re$i" pr default "prompt=$edited"
    is "a method gate file edited after the start makes it INVALID (instructions-differ; $g)" "$(says "re$i" 1)" "INVALID:instructions-differ"
  done
  git -C "$proj" reset -q --hard HEAD~1
fi
if wanted "a record with no prompt snapshot leaves it not checked"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer s2 ps
  stop method-reviewer s2 ps default nosnap
  is "a record with no prompt snapshot leaves it not checked (no-instructions)" "$(says s2 1)" "INCOMPLETE:no-instructions"
fi
if wanted "an Agent call makes it INVALID"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer s3 ps
  stop method-reviewer s3 ps default agent
  is "an Agent call makes it INVALID (called-agent)" "$(says s3 1)" "INVALID:called-agent"
fi
if wanted "a turn in another folder makes it INVALID"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer s4 ps
  stop method-reviewer s4 ps default "othercwd=$work/elsewhere"
  is "a turn in another folder makes it INVALID (other-folder)" "$(says s4 1)" "INVALID:other-folder"
fi
if wanted_any "a background shell of its own still running leaves it not checked" "another's background shell still running does not count"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer s5 ps
  stop method-reviewer s5 ps default bg=bown12345 'in:background_tasks=json:[{"command":"sleep 30","description":"wait","id":"bown12345","status":"running","type":"shell"}]'
  is "a background shell of its own still running leaves it not checked (background-task)" "$(says s5 1)" "INCOMPLETE:background-task"
  start method-reviewer s6 ps
  stop method-reviewer s6 ps default bg=bown12345 'in:background_tasks=json:[{"command":"sleep 30","description":"wait","id":"bother123","status":"running","type":"shell"},{"command":"sleep 30","description":"wait","id":"bown12345","status":"completed","type":"shell"}]'
  is "another's background shell still running does not count, nor its own that ended" "$(says s6 1)" "VALID:"
fi
if wanted_any "a packet built for other files makes it INVALID" "a packet for the files at HEAD is fine" "a packet for other files read with line numbers makes it INVALID"; then
  git -C "$proj" checkout -q -b topic
  printf 'b\n' >"$proj/b.txt"
  commit "the change"
  (cd "$proj" && bash "$root/method/scripts/method/review-packet.sh" --base main >"$work/old.packet" 2>/dev/null) || abort_sandbox
  printf 'b, fixed\n' >"$proj/b.txt"
  commit "the fix"
  (cd "$proj" && bash "$root/method/scripts/method/review-packet.sh" --base main >"$work/new.packet" 2>/dev/null) || abort_sandbox
  t2=$(git -C "$proj" rev-parse 'HEAD^{tree}')
  report "APPROVE" "END-VERDICT $t2"
  start method-reviewer k1 pk
  stop method-reviewer k1 pk default "user=file:$work/old.packet"
  is "a packet built for other files makes it INVALID (packet-other-tree: built, a fix committed, the old packet given)" "$(says k1 1)" "INVALID:packet-other-tree"
  start method-reviewer k2 pk
  stop method-reviewer k2 pk default "user=file:$work/new.packet"
  is "a packet for the files at HEAD is fine" "$(says k2 1)" "VALID:"
  start method-reviewer k3 pk
  stop method-reviewer k3 pk default "read=$work/old.packet"
  is "a packet for other files read with line numbers makes it INVALID (packet-other-tree)" "$(says k3 1)" "INVALID:packet-other-tree"
  git -C "$proj" checkout -q main
fi
if wanted "tokens are counted once a message id"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer u1 pu
  stop method-reviewer u1 pu default dup
  is "tokens are counted once a message id (a message of two blocks is two lines)" "$(says u1 1):$(field u1 1 tokens.input):$(field u1 1 tokens.output)" "VALID::11:7"
fi
if wanted "the receipt keeps the first request's cache reads apart"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer u2 pu
  stop method-reviewer u2 pu default "read=$proj/a.txt" firstcache=2
  is "the receipt keeps the first request's cache reads apart (M116: 2 in the first of two requests, 7 in all)" "$(says u2 1):$(field u2 1 tokens.cache_read_first):$(field u2 1 tokens.cache_read)" "VALID::2:7"
fi
if wanted_any "a handback the record shows refused leaves it not checked" "a handback the record shows with another message leaves it not checked"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer v1 pv
  handback method-reviewer v1 pv
  astop method-reviewer v1 pv hbdenied
  is "a handback the record shows refused leaves it not checked (handback-unconfirmed)" "$(says v1 1)" "INCOMPLETE:handback-unconfirmed"
  start method-reviewer v2 pv
  handback method-reviewer v2 pv
  astop method-reviewer v2 pv "hbmsg=APPROVE, another report"
  is "a handback the record shows with another message leaves it not checked (handback-unconfirmed)" "$(says v2 1)" "INCOMPLETE:handback-unconfirmed"
fi
if wanted "a record that is not a regular file leaves it not checked"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer w1 pw
  stop method-reviewer w1 pw default asis in:agent_transcript_path=/dev/null
  is "a record that is not a regular file leaves it not checked (record-unreadable: a device, not waited for)" "$code:$(says w1 1)" "0:INCOMPLETE:record-unreadable"
fi
if wanted "a record over 200 MB is not read"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer w3 pw
  rec method-reviewer w3
  perl -e 'open my $f, "+<", $ARGV[0] or die; truncate $f, 201 * 1024 * 1024 or die' "$recs/agent-w3.jsonl"
  stop method-reviewer w3 pw default asis
  rm -f "$recs/agent-w3.jsonl"
  is "a record over 200 MB is not read (record-unreadable)" "$(says w3 1)" "INCOMPLETE:record-unreadable"
fi
if wanted "a record line that is not JSON leaves it not checked"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer w4 pw
  stop method-reviewer w4 pw default garbage
  is "a record line that is not JSON leaves it not checked (record-unreadable)" "$(says w4 1)" "INCOMPLETE:record-unreadable"
fi
# (step 5b's review, F4: each stop first writes the third word, "judging")
if wanted "a second stop of a VALID run, cut off while it waits for the record, leaves it not checked"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer j1 pj
  stop method-reviewer j1 pj
  first=$(says j1 1)
  rec method-reviewer j1 partial
  cutoff 1 "$(mk hook_event_name=SubagentStop agent_type=method-reviewer agent_id=j1 prompt_id=pj permission_mode=default last_assistant_message="file:$work/report.txt" effort='json:{"level":"xhigh"}' stop_hook_active=json:false background_tasks='json:[]' agent_transcript_path="$recs/agent-j1.jsonl")"
  is "a second stop of a VALID run, cut off while it waits for the record, leaves it not checked (judging), never the earlier first word" "$first;$(says j1 1):$(field j1 1 stops)" "VALID:;INCOMPLETE:judging:2"
fi
# (last: it waits the whole 5 s)
if wanted "a record that never completes leaves it not checked"; then
  report "APPROVE" "END-VERDICT $tree"
  start method-reviewer w2 pw
  began=$(perl -MTime::HiRes=time -e 'print time')
  stop method-reviewer w2 pw default partial
  took=$(BEGAN="$began" perl -MTime::HiRes=time -e 'printf "%.1f", time - $ENV{BEGAN}')
  case "$(says w2 1):$took" in
    INCOMPLETE:record-late:[5-9].*) pass "a record that never completes leaves it not checked (record-late, after waiting ${took} s)" ;;
    *) fail "a record that never completes leaves it not checked (record-late)" "$(says w2 1) after $took s" ;;
  esac
fi

# --- a checkout whose .git links to git's folder elsewhere ---
if wanted "with .git a link, the receipt is written where it points"; then
  mkdir -p "$work/store"
  mv "$proj/.git" "$work/store/proj.git" && ln -s "$work/store/proj.git" "$proj/.git"
  start method-reviewer l1 pl
  is "with .git a link, the receipt is written where it points" "$(field l1 1 state):$(field l1 1 why)" "INCOMPLETE:running"
  rm -f "$proj/.git" && mv "$work/store/proj.git" "$proj/.git"
fi

drop_sandbox "$work" || true
echo "tests: gate-receipt: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
