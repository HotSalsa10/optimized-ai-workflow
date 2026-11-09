#!/usr/bin/env bash
# Tests for gate-receipt (step 5b.1; docs/plans/step5b.md): the hook
# .claude/hooks/method/gate-receipt.sh with lib/receipt.pl, run with hook
# inputs shaped as Claude Code 2.1.316 and 2.1.319 send them (measured for
# the plan; personal values removed), in a throwaway project with a home
# folder of its own. A gate's start is recorded and answered with its
# context line; its report is judged by its first and last lines; a report
# without them is sent back once (default mode) or refused once (auto
# mode); the receipt and the gates.log line say what happened; anything
# that goes wrong is exit 0.
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
work=$(new_sandbox_dir) || abort_sandbox
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
unset XDG_CONFIG_HOME CLAUDE_CONFIG_DIR GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
mkdir -p "$HOME"
git config --global user.email test@example.invalid
git config --global user.name Test
git config --global init.defaultBranch main
git config --global commit.gpgsign false
proj="$work/projü"
mkdir -p "$proj"
(cd "$proj" && git init -q && printf 'a\n' >a.txt && git add a.txt && git commit -qm one) || abort_sandbox
tree=$(git -C "$proj" rev-parse 'HEAD^{tree}')
common="$proj/.git"

# mk KEY=VALUE...: a hook input as JSON; a VALUE that starts with "json:" is
# JSON, one that starts with "file:" is a file's text; session_id and cwd
# are filled in unless given
mk() {
  CWD="$proj" perl -MJSON::PP -e '
    my $cwd = $ENV{CWD}; utf8::decode($cwd); my %h = (session_id => "s-1", cwd => $cwd);
    for (@ARGV) {
      my ($k, $v) = /\A([^=]+)=(.*)\z/s or die "bad pair $_\n";
      if ($v =~ s/\Ajson://) { $v = JSON::PP->new->allow_nonref->decode($v) }
      elsif ($v =~ s/\Afile://) { open my $f, "<:raw", $v or die; local $/; $v = <$f>; utf8::decode($v) }
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
# field AGENT PROMPT KEY: a field of that run's receipt (arrays joined by
# commas), or "absent" when there is no receipt
field() {
  COMMON="$common" A="$1" P="$2" K="$3" perl -MJSON::PP -MDigest::SHA=sha256_hex -e '
    my $n = "method-receipt-" . substr(sha256_hex("receipt\0s-1\0$ENV{A}"), 0, 16) . substr(sha256_hex("prompt\0$ENV{P}"), 0, 8) . ".json";
    open my $f, "<", "$ENV{COMMON}/$n" or do { print "absent"; exit };
    local $/; my $r = JSON::PP->new->decode(<$f>); my $v = $r->{$ENV{K}};
    print ref $v eq "ARRAY" ? join(",", @$v) : ref $v eq "HASH" ? "hash" : defined $v ? $v : "null"'
}
is() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got: $2
wanted: $3"; fi
}
report() { printf '%s\n' "$@" >"$work/report.txt"; }
start() { run "$(mk hook_event_name=SubagentStart agent_type="$1" agent_id="$2" prompt_id="$3")"; }
stop() { run "$(mk hook_event_name=SubagentStop agent_type="$1" agent_id="$2" prompt_id="$3" permission_mode="${4:-default}" last_assistant_message="file:$work/report.txt" effort='json:{"level":"xhigh"}' stop_hook_active=json:false background_tasks='json:[]')"; }
handback() { run "$(mk hook_event_name=PreToolUse tool_name=SubagentHandback agent_type="$1" agent_id="$2" prompt_id="$3" permission_mode=auto tool_use_id="toolu_$2" tool_input="json:$(perl -MJSON::PP -e 'local $/; print JSON::PP->new->encode({message => scalar <STDIN>})' <"$work/report.txt")")"; }

# --- the start ---
start method-reviewer a1 p1
is "a gate's start is answered with its context line, the gate and the tree" "$code:$out" "0:{\"hookSpecificOutput\":{\"additionalContext\":\"METHOD-ACTIVE gate=method-reviewer tree=$tree\",\"hookEventName\":\"SubagentStart\"}}"
is "the start writes a receipt in git's folder: not checked, running" "$(field a1 p1 state):$(field a1 p1 why)" "INCOMPLETE:running"
is "the receipt holds the start's tree" "$(field a1 p1 tree)" "$tree"
start my-method-reviewer a9 p9
is "an agent that is not a gate gets nothing and no receipt" "$code:$out:$(field a9 p9 state)" "0::absent"
run "$(mk hook_event_name=SubagentStart agent_type=method-reviewer agent_id='a b' prompt_id=p1)"
is "an agent id that is not a plain id gets nothing" "$code:$out" "0:"

# --- a good report ---
report "APPROVE" "Summary: fine." "END-VERDICT $tree"
stop method-reviewer a1 p1
is "a report with both lines: exit 0, nothing printed" "$code:$out:$err" "0::"
is "its receipt is good, with its opening word" "$(field a1 p1 state):$(field a1 p1 open):$(field a1 p1 why)" "VALID:APPROVE:"
if LC_ALL=C grep -q "	VALID	method-reviewer	$tree	none	xhigh	none\$" "$proj/.method/local/gates.log"; then
  pass "gates.log gets one fixed-field line: the word, the gate, the tree, the model, the effort, the reason"
else
  fail "gates.log gets one fixed-field line" "$(cat "$proj/.method/local/gates.log" 2>&1)"
fi
for first in "REQUEST CHANGES: two findings" "ESCALATE a person must decide" "REJECT"; do
  aid=$(printf '%s' "$first" | tr -c 'A-Za-z' 'x')
  start method-security-checker "$aid" pb
  report "$first" "body" "END-VERDICT $tree"
  stop method-security-checker "$aid" pb
  is "an opening word alone, or followed by a space or a colon, is read: $first" "$(field "$aid" pb state)" "VALID"
done
start method-diagnose d1 pd
report "ROOT CAUSE: the cache" "END-VERDICT $tree"
stop method-diagnose d1 pd
is "diagnose opens with its own words" "$(field d1 pd state):$(field d1 pd open)" "VALID:ROOT CAUSE"
start method-tester t1 pt
report "TESTS NOT RUN" "END-VERDICT $tree"
stop method-tester t1 pt
is "the tester opens with its own words" "$(field t1 pt state):$(field t1 pt open)" "VALID:TESTS NOT RUN"
start method-tester t2 pt
report "APPROVE" "END-VERDICT $tree"
stop method-tester t2 pt
is "another gate's word is not the tester's" "$code" "2"
printf 'APPROVE  \r\n\r\nbody\r\nEND-VERDICT %s \r\n\r\n' "$tree" >"$work/report.txt"
start method-reviewer a2 p2
stop method-reviewer a2 p2
is "trailing spaces, CRs and blank lines around the lines are let be" "$code:$(field a2 p2 state)" "0:VALID"

# --- a report without its lines: sent back once (B6) ---
for bad in "**APPROVE**" "# APPROVE" " APPROVE" "APPROVED" "approve"; do
  aid=$(printf '%s' "$bad" | tr -c 'A-Za-z' 'x')
  start method-reviewer "$aid" p3
  report "$bad" "END-VERDICT $tree"
  stop method-reviewer "$aid" p3
  is "a first line that is not a word is sent back: '$bad'" "$code" "2"
done
start method-reviewer a4 p4
report "APPROVE" "END-VERDICT 0000000"
stop method-reviewer a4 p4
is "an end line with another tree is sent back" "$code" "2"
case "$err" in
  "gate-receipt: your report must open with one of these words on its first line, alone or followed by a space or a colon: APPROVE, REQUEST CHANGES, REJECT, ESCALATE; and its last line must be exactly: END-VERDICT $tree. Send your whole report again in that form.") pass "the block names both exact lines and asks for the whole report again" ;;
  *) fail "the block names both exact lines" "$err" ;;
esac
is "the receipt says it was sent back, before the gate answers again" "$(field a4 p4 blocked):$(field a4 p4 state):$(field a4 p4 why)" "1:INCOMPLETE:lines-missing"
report "APPROVE" "fixed" "END-VERDICT $tree"
stop method-reviewer a4 p4
is "the report sent again with its lines: good" "$code:$(field a4 p4 state):$(field a4 p4 stops)" "0:VALID:2"
start method-reviewer a5 p5
report "nothing useful"
stop method-reviewer a5 p5
report "still nothing"
stop method-reviewer a5 p5
is "still without its lines: let go once, not checked" "$code:$(field a5 p5 state):$(field a5 p5 why)" "0:INCOMPLETE:lines-missing-after-retry"
start method-reviewer a6 p6
run "$(mk hook_event_name=SubagentStop agent_type=method-reviewer agent_id=a6 prompt_id=p6 permission_mode=default)"
is "no report at all: sent back once" "$code:$(field a6 p6 why)" "2:no-report"

# --- auto mode (B7) ---
start method-reviewer h1 ph
report "my findings, no verdict"
handback method-reviewer h1 ph
case "$code:$out" in
  "0:{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"gate-receipt: your report must open with"*) pass "a handback without its lines is refused once, with the exact lines" ;;
  *) fail "a handback without its lines is refused once" "$code:$out" ;;
esac
handback method-reviewer h1 ph
is "the second handback without its lines is let through" "$code:$out" "0:"
run "$(mk hook_event_name=SubagentStop agent_type=method-reviewer agent_id=h1 prompt_id=ph permission_mode=auto)"
is "then the receipt says not checked, and the stop does not block" "$code:$(field h1 ph state):$(field h1 ph why)" "0:INCOMPLETE:lines-missing-after-retry"
start method-reviewer h2 ph
report "REQUEST CHANGES" "one finding" "END-VERDICT $tree"
handback method-reviewer h2 ph
is "a handback with its lines is let through, and noted" "$code:$out:$(field h2 ph handback)" "0::hash"
run "$(mk hook_event_name=SubagentStop agent_type=method-reviewer agent_id=h2 prompt_id=ph permission_mode=auto)"
is "its stop (no last message after a handback) is good" "$code:$(field h2 ph state):$(field h2 ph open)" "0:VALID:REQUEST CHANGES"
start method-reviewer h3 ph
report "APPROVE" "END-VERDICT $tree"
stop method-reviewer h3 ph auto
is "auto mode with no handback: no report was delivered; no block" "$code:$(field h3 ph state):$(field h3 ph why)" "0:INCOMPLETE:no-report"

# --- runs that cannot be judged ---
report "APPROVE" "END-VERDICT $tree"
stop method-reviewer n1 pn
is "a stop with no start: not checked, never blocked" "$code:$(field n1 pn state):$(field n1 pn why)" "0:INCOMPLETE:no-start"
start method-reviewer r1 pr1
stop method-reviewer r1 pr1
is "a background gate's first run is good" "$(field r1 pr1 state)" "VALID"
start method-reviewer r1 pr2
is "resumed under the same agent id, its earlier receipt no longer stands" "$(field r1 pr1 state):$(field r1 pr1 why):$(field r1 pr2 state)" "INCOMPLETE:resumed-after-report:INCOMPLETE"
printf 'not json' >"$work/in.json"
out=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" bash "$hook" <"$work/in.json" 2>&1)
is "input that is not JSON: exit 0, nothing printed" "$?:$out" "0:"
mkdir -p "$work/nogit"
out=$(cd "$work/nogit" && printf '%s' "$(CWD="$work/nogit" mk hook_event_name=SubagentStart agent_type=method-reviewer agent_id=g1 prompt_id=pg cwd="$work/nogit")" | CLAUDE_PROJECT_DIR="$work/nogit" bash "$hook" 2>&1)
is "outside a git repository: tree=none, no receipt" "$?:$out" "0:{\"hookSpecificOutput\":{\"additionalContext\":\"METHOD-ACTIVE gate=method-reviewer tree=none\",\"hookEventName\":\"SubagentStart\"}}"

# --- the wrapper (B11): only a deliberate block exits 2 ---
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

# --- the context line's size (B3), with a SHA-256 repository ---
if git init -q --object-format=sha256 "$work/sha256" 2>/dev/null; then
  (cd "$work/sha256" && printf 'a\n' >a.txt && git add a.txt && git commit -qm one) || abort_sandbox
  t256=$(git -C "$work/sha256" rev-parse 'HEAD^{tree}')
  out=$(cd "$work/sha256" && printf '%s' "$(CWD="$work/sha256" mk hook_event_name=SubagentStart agent_type=method-security-checker agent_id=c1 prompt_id=pc cwd="$work/sha256")" | CLAUDE_PROJECT_DIR="$work/sha256" bash "$hook" 2>&1)
  line="METHOD-ACTIVE gate=method-security-checker tree=$t256"
  case "$out" in *"\"$line\""*) if [ "${#line}" -le 120 ]; then pass "the longest gate name with a SHA-256 tree fits in 120 bytes (${#line})"; else fail "the context line fits in 120 bytes" "${#line}"; fi ;; *) fail "the context line with a SHA-256 tree" "$out" ;; esac
else
  skip "SHA-256 repository: this git cannot make one"
fi

# --- a checkout whose .git links to git's folder elsewhere ---
mkdir -p "$work/store"
mv "$proj/.git" "$work/store/proj.git" && ln -s "$work/store/proj.git" "$proj/.git"
start method-reviewer l1 pl
is "with .git a link, the receipt is written where it points" "$(field l1 pl state):$(field l1 pl why)" "INCOMPLETE:running"

drop_sandbox "$work" || true
echo "tests: gate-receipt: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
