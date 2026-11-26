#!/usr/bin/env bash
# shellcheck disable=SC2016 # single-quoted perl code and hook commands are expanded later, by perl or by Claude Code
# The $0 harness (step 5.2, DECISIONS A49): the real Claude Code client runs
# against the local fake Claude (tests/harness/fake-api.pl) with test-only
# fixture hooks, and each case looks at what the client did: the requests
# the fake got, the files written, the fake MCP server's log. It proves that
# hooks fire and what their exit codes and output do in the real client.
#
# It needs a client: METHOD_HARNESS_CLIENT names the binary (CI's harness
# job fetches the pinned versions with tests/harness/get-client.sh). Without
# it the file says SKIPPED, which is never a pass. With it set to something
# that is not a program, the file fails. METHOD_HARNESS_VERSION, when set,
# is the version the client must report (CI sets it).
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: harness (the real client against the fake)"
finish() {
  echo "tests: harness: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
  [ "$tests_fail" -eq 0 ]
  exit
}
client=${METHOD_HARNESS_CLIENT:-}
# a relative name would not be found once a case changes folder
case $client in '' | /*) ;; *) client=$PWD/$client ;; esac
if [ -z "$client" ]; then
  skip "harness: no client given; set METHOD_HARNESS_CLIENT to a Claude Code binary to run it"
  finish
fi
if [ ! -f "$client" ] || [ ! -x "$client" ]; then
  fail "harness: METHOD_HARNESS_CLIENT is set, but it names no program: $client"
  finish
fi

HARNESS="$here/harness"
H_CLIENT=$client
H_WORK=$(new_sandbox_dir) || abort_sandbox
# shellcheck source=tests/harness/lib.sh
. "$HARNESS/lib.sh"
# the case folders, the fake's logs among them, go on any exit (a TERM too)
trap 'h_stop; drop_sandbox "$H_WORK" || true' EXIT
root=$(repo_root)
D="--permission-mode default --allowedTools Bash"
F='bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/fixture'

# the request reader finds text as written: non-ASCII, quotes and line
# breaks, in the system text and the user's messages, not the assistant's
mkdir -p "$H_WORK/rq"
perl -MJSON::PP -e 'print JSON::PP->new->utf8->encode({info => "conv=x turn=0", body => {system => [{type => "text", text => "Gr\x{fc}\x{df}e \"quoted\" HARNESS-MARK"}], messages => [{role => "assistant", content => "HARNESS-ASSISTANT"}, {role => "user", content => [{type => "text", text => "two\nlines"}]}]}})' >"$H_WORK/rq/req-001.json"
if perl "$HARNESS/read.pl" req x 'Grüße "quoted" HARNESS-MARK' "$H_WORK/rq" && perl "$HARNESS/read.pl" req x "two
lines" "$H_WORK/rq" && ! perl "$HARNESS/read.pl" req x HARNESS-ASSISTANT "$H_WORK/rq" && ! perl "$HARNESS/read.pl" req y HARNESS-MARK "$H_WORK/rq"; then
  pass "read.pl req finds non-ASCII text, quotes and line breaks as written, in the conversation asked for, and not in the assistant's own words"
else
  fail "read.pl req finds text as written"
fi
# Ctrl-C during a bounded run (INT to the shell's whole process group, as a
# terminal sends it) stops the shell too, not just the run
# (the child takes INT's default action even when the harness was started
# as a background job, which ignores INT)
sig=$(perl -e 'my $pid = fork; if (!$pid) { $SIG{INT} = "DEFAULT"; setpgrp(0, 0); exec "bash", "-c", q{perl "$0" 60 sleep 30; echo HARNESS-WENT-ON}, $ARGV[0] } sleep 1; kill "INT", -$pid; waitpid $pid, 0; print $? & 127' "$HARNESS/bound.pl")
if [ "$sig" = 2 ]; then pass "Ctrl-C during a bounded run stops the harness shell too (bound.pl dies by the same signal)"; else fail "Ctrl-C during a bounded run stops the harness shell too" "the shell ended by signal '$sig'"; fi

# --- 1. startup: version, tools, SessionStart context, a PreToolUse refusal ---
h_case startup
h_fixtures
h_settings <<EOF
{"model":"claude-opus-5-5",
 "hooks":{
  "SessionStart":[{"hooks":[{"type":"command","command":"$F/say.sh\" HARNESS-SESSION-CONTEXT"},
                            {"type":"command","command":"$F/log.sh\" SessionStart"}]}],
  "PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"$F/deny.sh\" HARNESS-REFUSE-ME"}]}]}}
EOF
cat >"$H_DIR/script.json" <<'EOF'
{"convs":[{"name":"main","match":"^go$","turns":[
  {"tool":"Bash","input":{"command":"touch allowed.txt","description":"An allowed command"}},
  {"tool":"Bash","input":{"command":"touch refused-ran.txt # HARNESS-REFUSE-ME","description":"A refused command"}},
  {"text":"MAIN-DONE"}]}],
 "fallback":{"text":"FAKE-FALLBACK"}}
EOF
if h_fake "$H_DIR/script.json"; then
  # shellcheck disable=SC2086 # D holds several arguments on purpose
  h_client 60 -- $D
  h_stop
  version=$(h_init claude_code_version)
  floor=$(sed -n 's/^claude_code_min=//p' "$root/method/scripts/method/REQUIRES")
  if [ -n "$version" ] && perl -e 'my @a = split /\./, $ARGV[0]; my @b = split /\./, $ARGV[1]; for (0 .. 2) { exit 0 if $a[$_] > $b[$_]; exit 1 if $a[$_] < $b[$_] } exit 0' "$version" "$floor"; then
    pass "startup: the client reports $version, at or above the floor $floor (REQUIRES)"
  else
    fail "startup: the client's version '$version' is not at or above the floor $floor" "$(tail -3 "$H_DIR/err.txt")"
  fi
  # (step 6b's review, R20) the case is always counted: with no version
  # asked for it says SKIPPED, so a run without METHOD_HARNESS_VERSION
  # shows the same number of cases as CI's
  if [ -z "${METHOD_HARNESS_VERSION:-}" ]; then
    skip "startup: no version asked for (METHOD_HARNESS_VERSION is not set), so the client's version is not compared with one"
  elif [ "$version" = "$METHOD_HARNESS_VERSION" ]; then
    pass "startup: the client is the version asked for ($METHOD_HARNESS_VERSION)"
  else
    fail "startup: the client reports '$version', not the version asked for ($METHOD_HARNESS_VERSION)"
  fi
  tools=$(h_init tools)
  missing=""
  for t in $tools; do
    LC_ALL=C grep -q "^$t	" "$HARNESS/tools.txt" || missing="$missing $t"
  done
  if [ -n "$tools" ] && [ -z "$missing" ]; then
    pass "startup: every tool the client offers is in tests/harness/tools.txt, marked guarded or not"
  else
    fail "startup: tools the client offers that tests/harness/tools.txt does not list:${missing:- (no tool list)}"
  fi
  if h_req_has HARNESS-SESSION-CONTEXT; then pass "startup: SessionStart text printed with exit 0 reaches the model's request"; else fail "startup: SessionStart text printed with exit 0 reaches the model's request"; fi
  if h_ran allowed.txt; then pass "startup: a command the PreToolUse hook lets through runs"; else fail "startup: a command the PreToolUse hook lets through runs" "$(tail -3 "$H_DIR/err.txt")"; fi
  if ! h_ran refused-ran.txt && h_tsv_has "ERR:PreToolUse:Bash hook error: " && h_tsv_has "HARNESS-DENY"; then
    pass "startup: a PreToolUse exit 2 stops the command, and its reason reaches the model as an error"
  else
    fail "startup: a PreToolUse exit 2 stops the command, and its reason reaches the model as an error" "$(cut -f7- "$H_DIR/fake/requests.tsv")"
  fi
  h_safe startup
else
  fail "startup: the fake did not answer; the client was not started"
fi

# --- 2. a SessionStart hook that exits 1: its text is not added ---
h_case session-exit1
h_fixtures
h_settings <<EOF
{"model":"claude-opus-5-5",
 "hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"$F/say.sh\" HARNESS-EXIT1-CONTEXT 1"},{"type":"command","command":"$F/log.sh\" SessionStart"}]}]}}
EOF
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"text":"MAIN-DONE"}]}]}' >"$H_DIR/script.json"
if h_fake "$H_DIR/script.json"; then
  # shellcheck disable=SC2086
  h_client 60 -- $D
  h_stop
  # (the hooks ran: log.sh, beside say.sh on the same event, wrote its line)
  if ! LC_ALL=C grep -q "^SessionStart	" "$H_PROJ/.harness/events.tsv" 2>/dev/null; then
    fail "session-exit1: SessionStart text printed with exit 1 does not reach the model" "the SessionStart hooks did not run (log.sh wrote no line), so the case shows nothing"
  elif h_req_has HARNESS-EXIT1-CONTEXT; then
    fail "session-exit1: SessionStart text printed with exit 1 does not reach the model" "it reached the model: the client now passes it on, so session-status's exit 0 rule can be revisited"
  elif h_reached; then
    pass "session-exit1: SessionStart text printed with exit 1 does not reach the model (so session-status must exit 0)"
  else
    fail "session-exit1: SessionStart text printed with exit 1 does not reach the model" "no request reached the fake"
  fi
  h_safe session-exit1
else
  fail "session-exit1: the fake did not answer; the client was not started"
fi

# --- 3. a subagent: SubagentStart context, a SubagentStop block ---
h_case subagent
h_fixtures
h_settings <<EOF
{"model":"claude-opus-5-5",
 "hooks":{
  "SubagentStart":[{"matcher":"reviewer","hooks":[{"type":"command","command":"$F/context.sh\" SubagentStart HARNESS-SUBAGENT-CONTEXT"}]}],
  "SubagentStop":[{"matcher":"reviewer","hooks":[{"type":"command","command":"$F/block-once.sh\""}]}]}}
EOF
cat >"$H_DIR/script.json" <<'EOF'
{"convs":[
  {"name":"sub","match":"HARNESS-SUBAGENT-TASK","turns":[{"text":"partial review, no verdict yet"},{"text":"APPROVE\nEND-VERDICT harness"}]},
  {"name":"main","match":"^go$","turns":[
    {"tool":"Agent","input":{"description":"harness review","prompt":"HARNESS-SUBAGENT-TASK: review the change","subagent_type":"reviewer","run_in_background":false}},
    {"text":"MAIN-DONE"}]}],
 "fallback":{"text":"FAKE-FALLBACK"}}
EOF
mkdir -p "$H_PROJ/.harness"
if h_fake "$H_DIR/script.json"; then
  # shellcheck disable=SC2086
  h_client 90 -- $D
  h_stop
  if h_req_in sub HARNESS-SUBAGENT-CONTEXT && ! h_req_in main HARNESS-SUBAGENT-CONTEXT; then pass "subagent: SubagentStart additionalContext reaches the subagent's request, and only the subagent's"; else fail "subagent: SubagentStart additionalContext reaches the subagent's request, and only the subagent's" "$(cut -f7- "$H_DIR/fake/requests.tsv")"; fi
  if LC_ALL=C grep -q "^block-once	fired" "$H_PROJ/.harness/events.tsv" 2>/dev/null && h_tsv_has "conv=sub turn=1"; then
    pass "subagent: a SubagentStop exit 2 sends the subagent back for one more turn"
  else
    fail "subagent: a SubagentStop exit 2 sends the subagent back for one more turn" "$(cut -f7- "$H_DIR/fake/requests.tsv")"
  fi
  h_safe subagent
else
  fail "subagent: the fake did not answer; the client was not started"
fi

# --- 3b. after a subagent's tool call: PostToolUse, PostToolUseFailure and
# PostToolBatch context reach the subagent's request (A80) ---
h_case subagent-post
h_fixtures
h_settings <<EOF
{"model":"claude-opus-5-5",
 "hooks":{
  "PostToolUse":[{"matcher":"Read","hooks":[{"type":"command","command":"$F/context.sh\" PostToolUse HARNESS-POST-CONTEXT"}]}],
  "PostToolUseFailure":[{"matcher":"Read","hooks":[{"type":"command","command":"$F/context.sh\" PostToolUseFailure HARNESS-FAILURE-CONTEXT"}]}],
  "PostToolBatch":[{"hooks":[{"type":"command","command":"$F/context.sh\" PostToolBatch HARNESS-BATCH-CONTEXT"}]}]}}
EOF
printf 'hello\n' >"$H_PROJ/readme.txt"
cat >"$H_DIR/script.json" <<EOF
{"convs":[
  {"name":"sub","match":"HARNESS-SUBAGENT-TASK","turns":[
    {"tool":"Read","input":{"file_path":"$H_PROJ/readme.txt"}},
    {"tool":"Read","input":{"file_path":"$H_PROJ/no-such-file.txt"}},
    {"text":"APPROVE\nEND-VERDICT harness"}]},
  {"name":"main","match":"^go$","turns":[
    {"tool":"Agent","input":{"description":"harness review","prompt":"HARNESS-SUBAGENT-TASK: review the change","subagent_type":"reviewer","run_in_background":false}},
    {"text":"MAIN-DONE"}]}],
 "fallback":{"text":"FAKE-FALLBACK"}}
EOF
if h_fake "$H_DIR/script.json"; then
  # shellcheck disable=SC2086
  h_client 90 -- $D
  h_stop
  if h_req_in sub HARNESS-POST-CONTEXT && h_req_in sub HARNESS-FAILURE-CONTEXT && h_req_in sub HARNESS-BATCH-CONTEXT; then
    pass "subagent-post: PostToolUse, PostToolUseFailure and PostToolBatch additionalContext reach the subagent's request"
  else
    fail "subagent-post: PostToolUse, PostToolUseFailure and PostToolBatch additionalContext reach the subagent's request" "$(cut -f7- "$H_DIR/fake/requests.tsv")"
  fi
  h_safe subagent-post
else
  fail "subagent-post: the fake did not answer; the client was not started"
fi

# --- 4. onFailure: a hook that cannot start blocks only with "block" ---
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"tool":"Bash","input":{"command":"touch ran.txt","description":"Write a marker"}},{"text":"MAIN-DONE"}]}]}' >"$H_WORK/onfail.json"
for mode in block unset; do
  h_case "onfailure-$mode"
  h_fixtures
  if [ "$mode" = block ]; then on=',"onFailure":"block"'; else on=""; fi
  h_settings <<EOF
{"model":"claude-opus-5-5",
 "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"$F/no-such-hook.sh\""$on}]}]}}
EOF
  if h_fake "$H_WORK/onfail.json"; then
    # shellcheck disable=SC2086
    h_client 60 -- $D
    h_stop
    if [ "$mode" = block ]; then
      if ! h_ran ran.txt && h_tsv_has "ERR:"; then pass "onfailure: with onFailure \"block\", a hook that cannot start blocks the call"; else fail "onfailure: with onFailure \"block\", a hook that cannot start blocks the call" "$(cut -f7- "$H_DIR/fake/requests.tsv")"; fi
    else
      if h_ran ran.txt; then pass "onfailure: without it, a hook that cannot start lets the call through (why the guard sets it)"; else fail "onfailure: without it, a hook that cannot start lets the call through"; fi
    fi
    h_safe "onfailure-$mode"
  else
    fail "onfailure-$mode: the fake did not answer; the client was not started"
  fi
done

# --- 5. MCP: a ^mcp__ PreToolUse refusal stops the tool ---
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"tool":"mcp__fake__merge_pull_request","input":{"pull_number":1}},{"text":"MAIN-DONE"}]}]}' >"$H_WORK/mcp.json"
for mode in refused control; do
  h_case "mcp-$mode"
  h_fixtures
  if [ "$mode" = refused ]; then
    h_settings <<EOF
{"model":"claude-opus-5-5",
 "hooks":{"PreToolUse":[{"matcher":"^mcp__","hooks":[{"type":"command","command":"$F/deny.sh\" pull_number"}]}]}}
EOF
  else
    printf '%s\n' '{"model":"claude-opus-5-5"}' | h_settings
  fi
  perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({mcpServers => {fake => {type => "stdio", command => "perl", args => [$ARGV[0], $ARGV[1]]}}})' \
    "$HARNESS/fake-mcp.pl" "$H_DIR/mcp.log" >"$H_DIR/mcp.json"
  if h_fake "$H_WORK/mcp.json"; then
    # shellcheck disable=SC2086
    h_client 60 -- $D mcp__fake__merge_pull_request --mcp-config "$H_DIR/mcp.json" --strict-mcp-config
    h_stop
    if [ "$mode" = refused ]; then
      if [ -s "$H_DIR/mcp.log" ] && ! LC_ALL=C grep -q '^CALLED' "$H_DIR/mcp.log" && h_tsv_has HARNESS-DENY; then pass "mcp: a ^mcp__ PreToolUse refusal stops the MCP tool before it is called"; else fail "mcp: a ^mcp__ PreToolUse refusal stops the MCP tool before it is called" "$(cut -f7- "$H_DIR/fake/requests.tsv")"; fi
    else
      if LC_ALL=C grep -q '^CALLED' "$H_DIR/mcp.log" 2>/dev/null; then pass "mcp: without the hook the same MCP tool is called (the case can tell)"; else fail "mcp: without the hook the same MCP tool is called" "$(cut -f7- "$H_DIR/fake/requests.tsv")"; fi
    fi
    h_safe "mcp-$mode"
  else
    fail "mcp-$mode: the fake did not answer; the client was not started"
  fi
done
# a .mcp.json the harness did not write (here in the case folder, above
# the project, with the project's settings approving it) starts no server:
# every run is given --strict-mcp-config
h_case mcp-stray
printf '%s\n' '{"model":"claude-opus-5-5","enableAllProjectMcpServers":true}' | h_settings
perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({mcpServers => {stray => {type => "stdio", command => "perl", args => [$ARGV[0], $ARGV[1]]}}})' \
  "$HARNESS/fake-mcp.pl" "$H_DIR/stray.log" >"$H_DIR/.mcp.json"
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"text":"MAIN-DONE"}]}]}' >"$H_DIR/script.json"
if h_fake "$H_DIR/script.json"; then
  # shellcheck disable=SC2086
  h_client 60 -- $D
  h_stop
  if h_reached && [ ! -e "$H_DIR/stray.log" ]; then pass "mcp-stray: a .mcp.json above the project, approved by its settings, starts no server in a harness run"; else fail "mcp-stray: a .mcp.json above the project started its server" "$(head -c 300 "$H_DIR/stray.log" 2>/dev/null)"; fi
  h_safe mcp-stray
else
  fail "mcp-stray: the fake did not answer; the client was not started"
fi

# --- 6. started in a subfolder: no project hook runs (RISKS #16) ---
h_case subfolder
h_fixtures
mkdir -p "$H_PROJ/sub"
h_settings <<EOF
{"model":"claude-opus-5-5",
 "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"$F/deny.sh\" HARNESS-REFUSE-ME"},{"type":"command","command":"CLAUDE_PROJECT_DIR=\"$H_PROJ\" bash \"$H_PROJ/.claude/hooks/fixture/log.sh\" PreToolUse-absolute"}]}]}}
EOF
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"tool":"Bash","input":{"command":"touch refused-ran.txt # HARNESS-REFUSE-ME","description":"A command the hook would refuse"}},{"text":"MAIN-DONE"}]}]}' >"$H_DIR/script.json"
if h_fake "$H_DIR/script.json"; then
  # shellcheck disable=SC2086
  H_CWD="$H_PROJ/sub" h_client 60 -- $D
  h_stop
  # (a hook with an absolute path, which needs no CLAUDE_PROJECT_DIR, did
  # not run either: the hooks were not loaded at all)
  if h_ran sub/refused-ran.txt && ! LC_ALL=C grep -q "PreToolUse-absolute" "$H_PROJ/.harness/events.tsv" 2>/dev/null; then
    pass "subfolder: a client started in a subfolder of the project runs no project hook (known limit, RISKS #16)"
  else
    fail "subfolder: a client started in a subfolder of the project runs no project hook: the hook ran, so RISKS #16 and the plan's note are out of date"
  fi
  h_safe subfolder
else
  fail "subfolder: the fake did not answer; the client was not started"
fi

# --- 7. a resumed session: SessionStart fires with source "resume" ---
h_case resume
h_fixtures
h_settings <<EOF
{"model":"claude-opus-5-5",
 "hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"$F/log.sh\" SessionStart"}]}]}}
EOF
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"text":"FIRST-DONE"},{"text":"SECOND-DONE"}]}]}' >"$H_DIR/script.json"
if h_fake "$H_DIR/script.json"; then
  # shellcheck disable=SC2086
  h_client 60 -- $D
  sid=$(h_init session_id)
  # shellcheck disable=SC2086
  H_PROMPT=again h_client 60 -- $D --resume "$sid"
  h_stop
  if [ -n "$sid" ] && LC_ALL=C grep -l '"source":"resume"' "$H_PROJ"/.harness/SessionStart-*.json >/dev/null 2>&1; then
    pass "resume: a resumed session fires SessionStart with source resume"
  else
    fail "resume: a resumed session fires SessionStart with source resume" "session '$sid'; $(cat "$H_PROJ"/.harness/SessionStart-*.json 2>/dev/null | cut -c1-200)"
  fi
  h_safe resume
else
  fail "resume: the fake did not answer; the client was not started"
fi

# --- 8. the settings fragment loads (step 5.3) ---
# with_fragment PERL: prints the fragment as the project settings, after
# PERL (on $d) changes it
with_fragment() {
  perl -MJSON::PP -e 'open my $h, "<", $ARGV[0] or die; my $d = JSON::PP->new->decode(do { local $/; <$h> }); eval "$ARGV[1]; 1" or die $@; print JSON::PP->new->canonical->encode($d)' "$root/method/settings.fragment.json" "$1"
}
h_case fragment
h_fixtures
with_fragment '$d->{hooks} = {SessionStart => [{hooks => [{type => "command", command => q{bash "$CLAUDE_PROJECT_DIR/.claude/hooks/fixture/env.sh" CLAUDE_CODE_DISABLE_ADVISOR_TOOL CLAUDE_CODE_USE_POWERSHELL_TOOL}}]}]}' | h_settings
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"text":"MAIN-DONE"}]}]}' >"$H_DIR/script.json"
if h_fake "$H_DIR/script.json"; then
  # (asked for another model: the fragment's allowlist must keep opus;
  # opus is also the client's default, so without --model this would pass
  # with no settings at all)
  # shellcheck disable=SC2086
  h_client 60 -- $D --model claude-sonnet-5-5
  h_stop
  if [ "$(h_init model)" = claude-opus-5-5 ]; then pass "fragment: the session runs claude-opus-5-5, also when asked for another model"; else fail "fragment: the session runs claude-opus-5-5, also when asked for another model" "$(h_init model)"; fi
  if h_req_has '"effort" : "xhigh"' && ! h_req_has '"effort" : "medium"'; then pass "fragment: every request carries effort xhigh"; else fail "fragment: every request carries effort xhigh" "$(LC_ALL=C grep -h -o '"effort" : "[a-z]*"' "$H_DIR"/fake/req-*.json | sort | uniq -c)"; fi
  if LC_ALL=C grep -q '^CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1$' "$H_PROJ/.harness/env.txt" 2>/dev/null && LC_ALL=C grep -q '^CLAUDE_CODE_USE_POWERSHELL_TOOL=0$' "$H_PROJ/.harness/env.txt"; then
    pass "fragment: its env (the advisor off, the PowerShell tool off) reaches the hooks"
  else
    fail "fragment: its env reaches the hooks" "$(cat "$H_PROJ/.harness/env.txt" 2>/dev/null)"
  fi
  h_safe fragment
else
  fail "fragment: the fake did not answer; the client was not started"
fi
# the control: without the fragment the same request runs the model asked for
h_case fragment-control
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"text":"MAIN-DONE"}]}]}' >"$H_DIR/script.json"
if h_fake "$H_DIR/script.json"; then
  # shellcheck disable=SC2086
  h_client 60 -- $D --model claude-sonnet-5-5
  h_stop
  if [ "$(h_init model)" = claude-sonnet-5-5 ]; then pass "fragment-control: without the fragment the model asked for runs (so the case above can tell)"; else fail "fragment-control: without the fragment the model asked for runs" "$(h_init model)"; fi
  h_safe fragment-control
else
  fail "fragment-control: the fake did not answer; the client was not started"
fi

# --- 9. skill shell lines off (D9, A51) ---
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"tool":"Skill","input":{"skill":"run-x"}},{"text":"MAIN-DONE"}]}]}' >"$H_WORK/skill.json"
for mode in off on; do
  h_case "skill-shell-$mode"
  mkdir -p "$H_PROJ/.claude/skills/run-x"
  printf '%s\n' '---' 'name: run-x' 'description: A harness skill with a shell line.' 'allowed-tools: Bash(touch *)' '---' 'Shipped: !`touch skill-ran.txt && echo HARNESS-SKILL-RAN`' >"$H_PROJ/.claude/skills/run-x/SKILL.md"
  if [ "$mode" = off ]; then with_fragment 'delete $d->{hooks}' | h_settings; else with_fragment 'delete $d->{hooks}; delete $d->{disableSkillShellExecution}' | h_settings; fi
  if h_fake "$H_WORK/skill.json"; then
    # shellcheck disable=SC2086
    h_client 60 -- --permission-mode default --allowedTools Skill
    h_stop
    if [ "$mode" = off ]; then
      if ! h_ran skill-ran.txt && h_req_has 'shell command execution disabled by policy'; then pass "skill-shell: with the fragment, a skill's shell line does not run and Claude sees the placeholder"; else fail "skill-shell: with the fragment, a skill's shell line does not run" "$(cut -f7- "$H_DIR/fake/requests.tsv")"; fi
    else
      if h_ran skill-ran.txt; then pass "skill-shell: without that setting the same line runs (the case can tell)"; else fail "skill-shell: without that setting the same line runs" "$(cut -f7- "$H_DIR/fake/requests.tsv")"; fi
    fi
    h_safe "skill-shell-$mode"
  else
    fail "skill-shell-$mode: the fake did not answer; the client was not started"
  fi
done

# --- 10. one value of the wrong type turns the whole file off ---
h_case rejected-shape
h_fixtures
with_fragment '$d->{availableModels} = "claude-opus-5-5"; $d->{hooks} = {SessionStart => [{hooks => [{type => "command", command => q{bash "$CLAUDE_PROJECT_DIR/.claude/hooks/fixture/env.sh" CLAUDE_CODE_DISABLE_ADVISOR_TOOL}}]}]}' | h_settings
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"text":"MAIN-DONE"}]}]}' >"$H_DIR/script.json"
if h_fake "$H_DIR/script.json"; then
  # shellcheck disable=SC2086
  h_client 60 -- $D
  h_stop
  why=""
  h_reached || why="$why no request reached the fake;"
  ! h_req_has '"effort" : "xhigh"' || why="$why effort xhigh still applied;"
  [ ! -e "$H_PROJ/.harness/env.txt" ] || why="$why the file's hook ran;"
  if [ -z "$why" ]; then
    pass "rejected-shape: one value of the wrong type makes the client skip the whole file, hooks included (effort is not xhigh; the hook did not run), so settings.test.sh checks every value's type"
  else
    fail "rejected-shape: one value of the wrong type makes the client skip the whole file:$why if the client now keeps the rest, settings.test.sh's note is out of date"
  fi
  h_safe rejected-shape
else
  fail "rejected-shape: the fake did not answer; the client was not started"
fi

# --- 11. session-status (step 5.4): METHOD-ACTIVE reaches Claude ---
printf '%s\n' '{"convs":[{"name":"main","match":"^(go|again)$","turns":[{"text":"FIRST-DONE"},{"text":"SECOND-DONE"}]}]}' >"$H_WORK/ss.json"
h_case session-status
h_method "$root"
if h_fake "$H_WORK/ss.json"; then
  # shellcheck disable=SC2086
  h_client 60 -- $D
  sid=$(h_init session_id)
  if h_req_has "METHOD-ACTIVE $H_TAG" && { h_req_has 'status: nothing needs a look' || h_req_has ' areas need a look ('; }; then pass "session-status: METHOD-ACTIVE, naming the release sync installed (method.lock), and status's summary reach the first request"; else fail "session-status: METHOD-ACTIVE and status's summary reach the first request" "$(LC_ALL=C grep -h -o 'METHOD-ACTIVE[^"]*' "$H_DIR"/fake/req-*.json | head -3)"; fi
  rm -f "$H_DIR"/fake/req-*.json
  # the resumed request also holds the first session's text, and the client
  # does not add output identical to what it already has: so the tree is
  # changed first, and the resume's own tag and new line are required
  printf 'x\n' >"$H_PROJ/changed-before-resume.txt"
  # shellcheck disable=SC2086
  H_PROMPT=again h_client 60 -- $D --resume "$sid"
  h_stop
  if h_req_has "SessionStart:resume hook success: METHOD-ACTIVE $H_TAG" && h_req_has 'work: LOOK - 1 uncommitted'; then pass "session-status: a resumed session gets METHOD-ACTIVE and its own status again"; else fail "session-status: a resumed session gets METHOD-ACTIVE and its own status again" "$(LC_ALL=C grep -h -o 'SessionStart:[a-z]* hook success: [^"]\{0,80\}' "$H_DIR"/fake/req-*.json | sort -u | head -4)"; fi
  h_safe session-status
else
  fail "session-status: the fake did not answer; the client was not started"
fi
h_case session-status-dirty
h_method "$root"
printf 'x\n' >"$H_PROJ/uncommitted.txt"
if h_fake "$H_WORK/ss.json"; then
  # shellcheck disable=SC2086
  h_client 60 -- $D
  h_stop
  if h_req_has "METHOD-ACTIVE $H_TAG" && h_req_has 'work: LOOK - ' && h_req_has 'status: 1 areas need a look (work)'; then pass "session-status: with a dirty tree (status exits 1) the line and the LOOK still reach Claude"; else fail "session-status: with a dirty tree the line and the LOOK still reach Claude"; fi
  h_safe session-status-dirty
else
  fail "session-status-dirty: the fake did not answer; the client was not started"
fi
h_case session-status-noperl
h_method "$root"
mkdir -p "$H_DIR/bin"
for t in bash sh env sed cat git dirname; do
  w=$(command -v "$t") && ln -s "$w" "$H_DIR/bin/$t"
done
if h_fake "$H_WORK/ss.json"; then
  # shellcheck disable=SC2086
  h_client 60 PATH="$H_DIR/bin" -- $D
  h_stop
  if h_req_has "METHOD-ACTIVE $H_TAG" && h_req_has 'perl or its JSON::PP module is missing'; then pass "session-status: without perl on PATH, METHOD-ACTIVE and a LOOK saying so still reach Claude"; else fail "session-status: without perl on PATH, METHOD-ACTIVE and a LOOK saying so still reach Claude" "$(tail -3 "$H_DIR/err.txt")"; fi
  h_safe session-status-noperl
else
  fail "session-status-noperl: the fake did not answer; the client was not started"
fi
h_case session-status-nested
h_method "$root"
if h_fake "$H_WORK/ss.json"; then
  # shellcheck disable=SC2086
  h_client 60 METHOD_NESTED=1 -- $D
  h_stop
  if h_req_has "METHOD-ACTIVE $H_TAG (nested: status skipped)"; then pass "session-status: a nested run (METHOD_NESTED=1) gets METHOD-ACTIVE without status"; else fail "session-status: a nested run gets the one short line"; fi
  h_safe session-status-nested
else
  fail "session-status-nested: the fake did not answer; the client was not started"
fi
# (step 8.4, M164) the user-level audit: a home with a personal skill named
# like the project's method-start and a user claudeMdExcludes; the first
# request carries the audit's two lines, each saying to tell the owner
h_case session-status-audit
h_method "$root"
mkdir -p "$H_PROJ/.claude/skills" "$H_DIR/home/.claude/skills/method-start"
cp -R "$root/method/.claude/skills/method-start" "$H_PROJ/.claude/skills/method-start"
printf -- '---\nname: method-start\ndescription: a personal copy\n---\nPersonal text.\n' >"$H_DIR/home/.claude/skills/method-start/SKILL.md"
printf '{"claudeMdExcludes":["**/nothing-here/**"]}\n' >"$H_DIR/home/.claude/settings.json"
if h_fake "$H_WORK/ss.json"; then
  # shellcheck disable=SC2086
  h_client 60 -- $D
  h_stop
  # shellcheck disable=SC2088 # the ~ is the text the hook prints, not a path
  if h_req_has "METHOD-ACTIVE $H_TAG" && h_req_has "LOOK - tell the owner: personal skill method-start in ~/.claude/skills runs in place of the project's" &&
    h_req_has "LOOK - tell the owner: claudeMdExcludes in ~/.claude/settings.json keep the method out"; then
    pass "session-status: the user-level audit's lines, a personal method-start and a user claudeMdExcludes, each saying to tell the owner, reach the first request"
  else
    fail "session-status: the user-level audit's lines reach the first request" "$(LC_ALL=C grep -h -o 'LOOK - tell the owner[^"]\{0,120\}' "$H_DIR"/fake/req-*.json | sort -u | head -4)"
  fi
  h_safe session-status-audit
else
  fail "session-status-audit: the fake did not answer; the client was not started"
fi
# (step 8.4) where and how the agents-md plugin's option is read: a user
# setting that resolves to managed-only, under a @builtin key, keeps the
# project's CLAUDE.md out of the first request, and the audit names it;
# under a bare id, or at a value that does not resolve to managed-only,
# CLAUDE.md arrives and the audit is silent. Each form: ID:AT:OPTION:VALUE:
# out or in (the keys and values read from the client's strings, pinned
# here; the older option's none is its managed-only)
n_if=0
for form in agents-md:builtin:instructionFiles:managed-only:out cc-plugin-agents-md:builtin:instructionFiles:managed-only:out \
  agents-md::instructionFiles:managed-only:in cc-plugin-agents-md::instructionFiles:managed-only:in \
  agents-md:builtin:projectInstructions:none:out agents-md:builtin:projectInstructions:managed-only:in; do
  n_if=$((n_if + 1))
  # (the key is ID@AT, or the bare ID; put together here)
  rest=$form
  key=${rest%%:*} && rest=${rest#*:}
  at=${rest%%:*} && rest=${rest#*:}
  opt=${rest%%:*} && rest=${rest#*:}
  val=${rest%%:*} && want=${rest#*:}
  [ -z "$at" ] || key="$key@$at"
  what="$opt $val under pluginConfigs $key"
  h_case "instruction-files-$n_if"
  h_method "$root"
  printf '%s\n' 'INSTRUCTION-MARK-84 from the project CLAUDE.md' '@AGENTS.md' >"$H_PROJ/CLAUDE.md"
  mkdir -p "$H_DIR/home/.claude"
  printf '{"pluginConfigs":{"%s":{"options":{"%s":"%s"}}}}\n' "$key" "$opt" "$val" >"$H_DIR/home/.claude/settings.json"
  if h_fake "$H_WORK/ss.json"; then
    # shellcheck disable=SC2086
    h_client 60 -- $D
    h_stop
    seen=$(LC_ALL=C grep -h -o 'INSTRUCTION-MARK-84\|tell the owner: agents-md[^"]\{0,40\}' "$H_DIR"/fake/req-*.json | sort -u | head -3)
    if [ "$want" = out ]; then
      if h_req_has "METHOD-ACTIVE $H_TAG" && ! h_req_has 'INSTRUCTION-MARK-84' && h_req_has "tell the owner: agents-md $opt $val"; then
        pass "instruction files: $what keeps the project's CLAUDE.md out, and the audit names it"
      else
        fail "instruction files: $what keeps the project's CLAUDE.md out, and the audit names it" "$seen"
      fi
    elif h_req_has "METHOD-ACTIVE $H_TAG" && h_req_has 'INSTRUCTION-MARK-84' && ! h_req_has 'tell the owner: agents-md'; then
      pass "instruction files: with $what the client drops nothing, CLAUDE.md arrives, and the audit is silent"
    else
      fail "instruction files: with $what the client drops nothing, CLAUDE.md arrives, and the audit is silent" "$seen"
    fi
    h_safe "instruction-files-$n_if"
  else
    fail "instruction-files-$n_if: the fake did not answer; the client was not started"
  fi
done

# --- 12. the guard (step 5.5) ---
g0='echo $(git rev-parse HEAD) > refused-ran.txt'
GUARD_SCRIPT=$(CMD="$g0" perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({convs => [{name => "main", match => "^go\$", turns => [{tool => "Bash", input => {command => "git status > allowed.txt", description => "a plain command"}}, {tool => "Bash", input => {command => $ENV{CMD}, description => "an unreadable one"}}, {text => "MAIN-DONE"}]}]})')
printf '%s\n' "$GUARD_SCRIPT" >"$H_WORK/guard.json"
for mode in default acceptEdits; do
  h_case "guard-$mode"
  h_method "$root"
  if h_fake "$H_WORK/guard.json"; then
    h_client 60 -- --permission-mode "$mode" --allowedTools Bash
    h_stop
    if h_ran allowed.txt && ! h_ran refused-ran.txt && h_tsv_has "ERR:PreToolUse:Bash hook error: " && h_tsv_has "guard G0: this command holds command substitution"; then
      pass "guard ($mode mode): a plain command runs; an unreadable one next to git is refused (G0) and its reason reaches Claude"
    else
      fail "guard ($mode mode): a plain command runs; an unreadable one next to git is refused (G0)" "$(cut -f7- "$H_DIR/fake/requests.tsv")"
    fi
    if LC_ALL=C grep -q "	G0	Bash	" "$H_PROJ/.method/local/guard.log" 2>/dev/null; then pass "guard ($mode mode): the refusal is in .method/local/guard.log"; else fail "guard ($mode mode): the refusal is in .method/local/guard.log"; fi
    h_safe "guard-$mode"
  else
    fail "guard-$mode: the fake did not answer; the client was not started"
  fi
done
h_case guard-monitor
h_method "$root"
CMD="$g0" perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({convs => [{name => "main", match => "^go\$", turns => [{tool => "Monitor", input => {command => $ENV{CMD}, description => "watch"}}, {text => "MAIN-DONE"}]}]})' >"$H_DIR/script.json"
if h_fake "$H_DIR/script.json"; then
  h_client 60 -- --permission-mode default --allowedTools Bash Monitor
  h_stop
  if ! h_ran refused-ran.txt && h_tsv_has "guard G0"; then pass "guard: a Monitor command is checked as a Bash one, and refused"; else fail "guard: a Monitor command is checked as a Bash one, and refused" "$(cut -f7- "$H_DIR/fake/requests.tsv")"; fi
  h_safe guard-monitor
else
  fail "guard-monitor: the fake did not answer; the client was not started"
fi
h_case guard-missing
h_method "$root"
rm -f "$H_PROJ/.claude/hooks/method/guard.sh"
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"tool":"Bash","input":{"command":"touch ran.txt","description":"a plain command"}},{"text":"MAIN-DONE"}]}]}' >"$H_DIR/script.json"
if h_fake "$H_DIR/script.json"; then
  # shellcheck disable=SC2086
  h_client 60 -- $D
  h_stop
  if ! h_ran ran.txt && h_tsv_has "ERR:"; then pass "guard: with guard.sh missing, even a plain command is blocked (onFailure block)"; else fail "guard: with guard.sh missing, even a plain command is blocked" "$(cut -f7- "$H_DIR/fake/requests.tsv")"; fi
  h_safe guard-missing
else
  fail "guard-missing: the fake did not answer; the client was not started"
fi
h_case guard-noperl
h_method "$root"
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"tool":"Bash","input":{"command":"touch ran.txt","description":"a plain command"}},{"text":"MAIN-DONE"}]}]}' >"$H_DIR/script.json"
mkdir -p "$H_DIR/bin"
for t in bash sh env sed cat git dirname; do
  w=$(command -v "$t") && ln -s "$w" "$H_DIR/bin/$t"
done
if h_fake "$H_DIR/script.json"; then
  # shellcheck disable=SC2086
  h_client 60 PATH="$H_DIR/bin" -- $D
  h_stop
  if ! h_ran ran.txt && h_tsv_has "guard G1: perl is missing"; then pass "guard: without perl on PATH every call is refused (G1), with the way out"; else fail "guard: without perl on PATH every call is refused (G1)" "$(cut -f7- "$H_DIR/fake/requests.tsv")"; fi
  h_safe guard-noperl
else
  fail "guard-noperl: the fake did not answer; the client was not started"
fi
# --- 13. the git list (step 5.6): a push to main is refused with its
# reason, and a task branch's push runs ---
h_case git-list
h_method "$root"
git init -q --bare "$H_DIR/origin.git"
hg() { HOME="$H_DIR/home" GIT_CONFIG_NOSYSTEM=1 git -C "$H_PROJ" "$@"; }
{ hg remote add origin "$H_DIR/origin.git" && hg push -q origin main && hg switch -q -c task; } || fail "git-list: the case's origin could not be made"
main_before=$(git -C "$H_DIR/origin.git" rev-parse refs/heads/main)
GIT_LIST_SCRIPT=$(perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({convs => [{name => "main", match => "^go\$", turns => [{tool => "Bash", input => {command => "git push origin HEAD:main", description => "a push to main"}}, {tool => "Bash", input => {command => "git push -q -u origin HEAD", description => "a push of the task branch"}}, {text => "MAIN-DONE"}]}]})')
printf '%s\n' "$GIT_LIST_SCRIPT" >"$H_DIR/git-list.json"
if h_fake "$H_DIR/git-list.json"; then
  h_client 60 -- --permission-mode default --allowedTools Bash
  h_stop
  if h_tsv_has "guard G3: pushing to main is refused" && [ "$(git -C "$H_DIR/origin.git" rev-parse refs/heads/main)" = "$main_before" ] && git -C "$H_DIR/origin.git" rev-parse -q --verify refs/heads/task >/dev/null; then
    pass "git list: a push to main is refused with its reason, and the task branch's push runs"
  else
    fail "git list: a push to main is refused with its reason, and the task branch's push runs" "$(cut -f7- "$H_DIR/fake/requests.tsv")"
  fi
  h_safe git-list
else
  fail "git-list: the fake did not answer; the client was not started"
fi

# --- 14. protected files (step 5.7): a write to the settings is refused
# with its reason and the file is unchanged, a read of them runs; at effort
# low the first call brings one G12 warning ---
h_case protect
h_method "$root"
PROTECT_SCRIPT=$(perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({convs => [{name => "main", match => "^go\$", turns => [{tool => "Write", input => {file_path => $ARGV[0], content => "{}\n"}}, {tool => "Bash", input => {command => "cat .claude/settings.json > seen.txt", description => "a read"}}, {text => "MAIN-DONE"}]}]})' "$H_PROJ/.claude/settings.json")
printf '%s\n' "$PROTECT_SCRIPT" >"$H_DIR/protect.json"
before=$(cksum <"$H_PROJ/.claude/settings.json")
if h_fake "$H_DIR/protect.json"; then
  h_client 60 CLAUDE_CODE_EFFORT_LEVEL=low -- --permission-mode acceptEdits --allowedTools Bash Write
  h_stop
  if h_tsv_has "guard G6: the project's settings (.claude/settings.json) may not be changed by Claude" && [ "$(cksum <"$H_PROJ/.claude/settings.json")" = "$before" ] && h_ran seen.txt; then
    pass "protected files: a Write to the project's settings is refused with its reason and the file is unchanged; a read of them runs"
  else
    fail "protected files: a Write to the project's settings is refused with its reason; a read of them runs" "$(cut -f7- "$H_DIR/fake/requests.tsv")"
  fi
  n=$(LC_ALL=C grep -c 'guard G12: this session runs at effort low' "$H_DIR/out.jsonl" 2>/dev/null)
  if [ "${n:-0}" -ge 1 ] && [ "$(wc -l <"$H_PROJ/.method/local/effort-warned" 2>/dev/null | tr -d ' ')" = 1 ]; then
    pass "G12: at effort low the first call brings one warning (in the client's output) and the session is noted once"
  else
    fail "G12: at effort low the first call brings one warning" "$(LC_ALL=C grep -o '.\{0,80\}G12.\{0,80\}' "$H_DIR/out.jsonl" | head -3)"
  fi
  h_safe protect
else
  fail "protect: the fake did not answer; the client was not started"
fi

# --- 15. the outside (step 5.8): gh by its list (a stand-in gh only
# notes that it ran), MCP tools by theirs, and the settings' deny entries,
# which take the merge tool away under any server name, hooks on or off ---
# outside_case NAME SETTINGS-PERL [VAR=VALUE...]: a method project whose
# origin names a GitHub repository (never contacted), on branch task, with
# the fake MCP server under two names (github and plugin_github_github,
# each with its own log); SETTINGS-PERL changes the settings ($d) first
outside_case() {
  h_case "$1"
  h_method "$root"
  OUT_PERL=$2 perl -MJSON::PP -e 'my $f = $ARGV[0]; open my $h, "<", $f or die; my $d = decode_json(do { local $/; <$h> }); close $h; eval "$ENV{OUT_PERL}; 1" or die $@; open $h, ">", $f or die; print $h JSON::PP->new->canonical->pretty->encode($d)' "$H_PROJ/.claude/settings.json" || fail "$1: the settings could not be changed"
  { hg remote add origin https://github.com/example-owner/example-repo.git && hg switch -q -c task; } || fail "$1: the case's origin could not be set"
  mkdir -p "$H_DIR/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>gh-ran.txt\n' >"$H_DIR/bin/gh" && chmod +x "$H_DIR/bin/gh"
  perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({mcpServers => {map { $_ => {type => "stdio", command => "perl", args => [$ARGV[0], "$ARGV[1]/$_.log", qw(merge_pull_request create_pull_request)]} } qw(github plugin_github_github)}})' \
    "$HARNESS/fake-mcp.pl" "$H_DIR" >"$H_DIR/mcp.json"
}
# deny_loaded: the client's debug log says the ten deny rules (REPL the
# tenth since step 8.0c) loaded from the project's settings, and that no
# rule was found invalid (a rule the client rejects prints nothing on stderr
# or in the stream)
deny_loaded() {
  LC_ALL=C grep -q "Adding 10 deny rule(s) to destination 'projectSettings'" "$H_DIR/debug.log" 2>/dev/null && ! LC_ALL=C grep -q 'Invalid permission rule\|Invalid setting' "$H_DIR/debug.log"
}
# called LOG [TEXT]: the fake MCP server under that name was called (with
# TEXT in the call)
called() {
  LC_ALL=C grep "^CALLED" "$H_DIR/$1.log" 2>/dev/null | LC_ALL=C grep -q -- "${2:-}"
}
OUT_SCRIPT='{"convs":[{"match":"^go$","name":"main","turns":[{"input":{"command":"gh pr merge 1","description":"a merge"},"tool":"Bash"},{"input":{"command":"gh pr create --head task --title t --body b","description":"a pull request"},"tool":"Bash"},{"input":{"owner":"example-owner","pullNumber":1,"repo":"example-repo"},"tool":"mcp__github__merge_pull_request"},{"input":{"owner":"example-owner","pullNumber":1,"repo":"example-repo"},"tool":"mcp__plugin_github_github__merge_pull_request"},{"input":{"base":"main","head":"task","owner":"someone-else","repo":"other","title":"OTHER-REPO"},"tool":"mcp__github__create_pull_request"},{"input":{"base":"main","head":"task","owner":"example-owner","repo":"example-repo","title":"THIS-REPO"},"tool":"mcp__github__create_pull_request"},{"text":"MAIN-DONE"}]}]}'
printf '%s\n' "$OUT_SCRIPT" >"$H_WORK/outside.json"
MERGE_ONLY='{"convs":[{"match":"^go$","name":"main","turns":[{"input":{"owner":"example-owner","pullNumber":1,"repo":"example-repo"},"tool":"mcp__github__merge_pull_request"},{"input":{"owner":"example-owner","pullNumber":1,"repo":"example-repo"},"tool":"mcp__plugin_github_github__merge_pull_request"},{"text":"MAIN-DONE"}]}]}'
printf '%s\n' "$MERGE_ONLY" >"$H_WORK/outside-merge.json"
OUT_ARGS="--permission-mode default --allowedTools Bash mcp__github__create_pull_request mcp__github__merge_pull_request mcp__plugin_github_github__merge_pull_request"

outside_case outside ''
if h_fake "$H_WORK/outside.json"; then
  # shellcheck disable=SC2086
  h_client 60 PATH="$H_DIR/bin:/usr/bin:/bin" -- $OUT_ARGS --mcp-config "$H_DIR/mcp.json" --debug-file "$H_DIR/debug.log"
  h_stop
  if h_req_in main '"gh pr merge" in this form is not on the method' && LC_ALL=C grep -q '^pr create --head task' "$H_PROJ/gh-ran.txt" 2>/dev/null && ! LC_ALL=C grep -q 'merge' "$H_PROJ/gh-ran.txt"; then
    pass "outside: gh pr merge is refused (G4) with its reason; gh pr create from the task branch runs"
  else
    fail "outside: gh pr merge is refused (G4); gh pr create from the task branch runs" "$(cut -f7- "$H_DIR/fake/requests.tsv")"
  fi
  if h_req_in main 'No such tool available: mcp__github__merge_pull_request' && h_req_in main 'No such tool available: mcp__plugin_github_github__merge_pull_request' && ! called github merge && ! called plugin_github_github merge; then
    pass "outside: the MCP merge tool is taken away under both server names by the settings' deny entries, and never called"
  else
    fail "outside: the MCP merge tool is taken away under both server names" "$(cut -f7- "$H_DIR/fake/requests.tsv")"
  fi
  # (read from every message: the client can add a reminder after a tool
  # result, and the fake's log sums up the last message only)
  if h_req_in main 'guard G4: the MCP tool create_pull_request may write only to this repository' && ! called github OTHER-REPO && called github THIS-REPO; then
    pass "outside: an MCP pull request on another repository is refused (G4); one from this repository's task branch is made"
  else
    fail "outside: an MCP pull request on another repository is refused (G4); one from the task branch is made" "$(cut -f7- "$H_DIR/fake/requests.tsv")"
  fi
  if deny_loaded; then pass "outside: the client's debug log shows the ten deny rules loaded from the project's settings, none invalid"; else fail "outside: the ten deny rules loaded, none invalid" "$(LC_ALL=C grep -i 'deny rule\|invalid' "$H_DIR/debug.log" 2>/dev/null | head -3)"; fi
  if LC_ALL=C grep -q '	G4	mcp__github	' "$H_PROJ/.method/local/guard.log" 2>/dev/null && ! LC_ALL=C grep -q 'create_pull_request' "$H_PROJ/.method/local/guard.log"; then
    pass "outside: the MCP refusal is in guard.log under the tool's server only"
  else
    fail "outside: the MCP refusal is in guard.log under the tool's server only" "$(cut -f2-3 "$H_PROJ/.method/local/guard.log" 2>&1 | head -5)"
  fi
  h_safe outside
else
  fail "outside: the fake did not answer; the client was not started"
fi
# the controls: the same rules under allow are found invalid (so the debug
# log check can tell), and without the deny entries the merge tool is
# there, and only the guard (G4) stops it
outside_case outside-nodeny '$d->{permissions} = {allow => $d->{permissions}{deny}}'
if h_fake "$H_WORK/outside-merge.json"; then
  # shellcheck disable=SC2086
  h_client 60 -- $OUT_ARGS --mcp-config "$H_DIR/mcp.json" --debug-file "$H_DIR/debug.log"
  h_stop
  if ! deny_loaded && h_req_in main 'guard G4: the MCP tool merge_pull_request is not on' && ! h_req_has 'No such tool available' && ! called github && ! called plugin_github_github; then
    pass "outside (control): the rules under allow are found invalid, and without the deny entries the merge tool is there and only the guard stops it"
  else
    fail "outside (control): without the deny entries the merge tool is there and only the guard stops it" "$(cut -f7- "$H_DIR/fake/requests.tsv")"
  fi
  h_safe outside-nodeny
else
  fail "outside-nodeny: the fake did not answer; the client was not started"
fi
# with the hooks switched off (the owner's way out), the deny entries still
# hold (M139); without them, the merge is called (the case can tell)
for deny in yes no; do
  if [ "$deny" = yes ]; then outside_case outside-hooksoff ''; else outside_case outside-hooksoff-nodeny 'delete $d->{permissions}'; fi
  printf '{"disableAllHooks": true}\n' >"$H_PROJ/.claude/settings.local.json"
  if h_fake "$H_WORK/outside-merge.json"; then
    # shellcheck disable=SC2086
    h_client 60 -- $OUT_ARGS --mcp-config "$H_DIR/mcp.json"
    h_stop
    if [ "$deny" = yes ]; then
      if h_req_in main 'No such tool available: mcp__github__merge_pull_request' && h_req_in main 'No such tool available: mcp__plugin_github_github__merge_pull_request' && ! called github && ! called plugin_github_github && [ ! -e "$H_PROJ/.method/local/guard.log" ]; then
        pass "outside: with the hooks off, the deny entries still take the merge tool away under both server names (M139)"
      else
        fail "outside: with the hooks off, the deny entries still take the merge tool away" "$(cut -f7- "$H_DIR/fake/requests.tsv")"
      fi
      h_safe outside-hooksoff
    else
      if called github && called plugin_github_github; then pass "outside (control): with the hooks off and no deny entries, the merge tool is called on both servers"; else fail "outside (control): with the hooks off and no deny entries, the merge tool is called" "$(cut -f7- "$H_DIR/fake/requests.tsv")"; fi
      h_safe outside-hooksoff-nodeny
    fi
  else
    fail "outside-hooksoff ($deny): the fake did not answer; the client was not started"
  fi
done

# the owner's way out (README, "When the guard blocks something it should not")
for way in local flag; do
  h_case "way-out-$way"
  h_method "$root"
  if [ "$way" = local ]; then printf '{"disableAllHooks": true}\n' >"$H_PROJ/.claude/settings.local.json"; fi
  if h_fake "$H_WORK/guard.json"; then
    if [ "$way" = flag ]; then
      h_client 60 -- --permission-mode default --allowedTools Bash --settings '{"disableAllHooks": true}'
    else
      h_client 60 -- --permission-mode default --allowedTools Bash
    fi
    h_stop
    if h_ran refused-ran.txt && ! h_req_has 'METHOD-ACTIVE'; then
      pass "way out ($way): with hooks switched off before the session, the guard does not run, and the missing METHOD-ACTIVE line shows it"
    else
      fail "way out ($way): with hooks switched off before the session, the guard does not run" "$(cut -f7- "$H_DIR/fake/requests.tsv")"
    fi
    h_safe "way-out-$way"
  else
    fail "way-out-$way: the fake did not answer; the client was not started"
  fi
done

# --- 16. settings changes and skill hooks (step 5.9): the "holds" cases
# that rest on the client itself (the other rules' bypasses are proven
# through guard.sh with a real hook input: guard*.test.sh; A68) ---
# a. the hook prefix and command perl hold at a session's start: with
# BASH_ENV and an exported function named perl in the user's settings env,
# the guard runs and refuses a Write to the project's settings
h_holds_start "$root"
if [ -z "$H_HOLD" ]; then pass "holds: with BASH_ENV and functions named perl and command in the user's env at start, the hooks run none of them, and the guard refuses a Write to the settings"; else fail "holds: the hook prefix and command perl" "$H_HOLD $(cut -f7- "$H_DIR/fake/requests.tsv" 2>/dev/null)"; fi
h_safe holds-start
# b. mid-session, while the client waits for an answer, disableAllHooks is
# written to the local settings: refused at ConfigChange (logged), the
# guard still refuses the next write, and the next call it lets through
# brings G16's one-time message. Without the ConfigChange entry (the
# control) the same change switches the guard off, so the case can tell.
# (The client notices a changed file within a few seconds: the fake waits
# 8 s before it answers.)
nocc() { perl -MJSON::PP -e 'local $/; my $d = JSON::PP->new->decode(<STDIN>); delete $d->{hooks}{ConfigChange}; print JSON::PP->new->canonical->encode($d)' <"$H_PROJ/.claude/settings.json" >"$H_DIR/s.json" && cp "$H_DIR/s.json" "$H_PROJ/.claude/settings.json"; }
for mode in guard control; do
  h_case "g16-local-$mode"
  h_method "$root"
  [ "$mode" = guard ] || nocc
  printf '{}\n' >"$H_PROJ/.claude/settings.local.json"
  perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({convs => [{name => "main", match => "^go\$", turns => [{write => {path => $ARGV[0], text => "{\"disableAllHooks\": true}\n"}, pause => 8, tool => "Bash", input => {command => "echo x > .claude/settings.json", description => "a write"}}, {tool => "Bash", input => {command => "echo ok > seen.txt", description => "a plain write"}}, {text => "MAIN-DONE"}]}]})' "$H_PROJ/.claude/settings.local.json" >"$H_DIR/g16.json"
  before=$(cksum <"$H_PROJ/.claude/settings.json")
  if h_fake "$H_DIR/g16.json"; then
    h_client 90 -- --permission-mode default --allowedTools Bash
    h_stop
    if [ "$mode" = guard ]; then
      if h_tsv_has 'guard G6: ' && [ "$(cksum <"$H_PROJ/.claude/settings.json")" = "$before" ] && LC_ALL=C grep -q '	G16	ConfigChange	' "$H_PROJ/.method/local/guard.log" 2>/dev/null; then
        pass "G16: disableAllHooks written to the local settings mid-session is refused (and logged); the guard still refuses the next write"
      else
        fail "G16: disableAllHooks written mid-session is refused" "$(cut -f7- "$H_DIR/fake/requests.tsv"; cat "$H_PROJ/.method/local/guard.log" 2>/dev/null)"
      fi
      if h_ran seen.txt && LC_ALL=C grep -q 'guard G16: a settings change was refused during this session' "$H_DIR/out.jsonl"; then
        pass "G16: the next call the guard lets through brings the one-time message"
      else
        fail "G16: the next call brings the one-time message" "$(LC_ALL=C grep -o '.\{0,80\}G16.\{0,80\}' "$H_DIR/out.jsonl" | head -3)"
      fi
    else
      if h_tsv_has 'turn=1' && ! h_tsv_has 'guard G6: ' && [ ! -e "$H_PROJ/.method/local/guard.log" ]; then pass "G16 (control): without the ConfigChange entry the same change switches the guard off mid-session (the case can tell)"; else fail "G16 (control): without the ConfigChange entry the change switches the guard off" "$(cut -f7- "$H_DIR/fake/requests.tsv")"; fi
    fi
    h_safe "g16-local-$mode"
  else
    fail "g16-local-$mode: the fake did not answer; the client was not started"
  fi
done
# c. mid-session, an env variable is added to the user's settings: refused,
# so the next command's shell does not see it; without the ConfigChange
# entry (the control) it does (G16 refuses any env change: BASH_ENV, PATH
# and the like reach later commands this way)
for mode in guard control; do
  h_case "g16-env-$mode"
  h_method "$root"
  [ "$mode" = guard ] || nocc
  mkdir -p "$H_DIR/home/.claude"
  printf '{}\n' >"$H_DIR/home/.claude/settings.json"
  perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({convs => [{name => "main", match => "^go\$", turns => [{write => {path => $ARGV[0], text => "{\"env\": {\"HARNESS_ADDED\": \"yes\"}}\n"}, pause => 8, tool => "Bash", input => {command => "printf \"%s\" \"\$HARNESS_ADDED\" > seen.txt", description => "a plain write"}}, {text => "MAIN-DONE"}]}]})' "$H_DIR/home/.claude/settings.json" >"$H_DIR/g16env.json"
  if h_fake "$H_DIR/g16env.json"; then
    h_client 90 -- --permission-mode default --allowedTools Bash
    h_stop
    got=$(cat "$H_PROJ/seen.txt" 2>/dev/null)
    if [ "$mode" = guard ]; then
      if h_ran seen.txt && [ -z "$got" ] && LC_ALL=C grep -q '	G16	ConfigChange	' "$H_PROJ/.method/local/guard.log" 2>/dev/null; then pass "G16: an env variable added to the user's settings mid-session is refused; the next command's shell does not see it"; else fail "G16: an env variable added mid-session is refused" "seen: '$got'; $(cut -f7- "$H_DIR/fake/requests.tsv")"; fi
    else
      if [ "$got" = yes ]; then pass "G16 (control): without the ConfigChange entry the next command's shell sees it (the case can tell)"; else fail "G16 (control): without the ConfigChange entry the next command sees the variable" "seen: '$got'"; fi
    fi
    h_safe "g16-env-$mode"
  else
    fail "g16-env-$mode: the fake did not answer; the client was not started"
  fi
done
# d. G17: a project skill whose frontmatter declares a hook is refused,
# and its hook never runs
h_case g17
h_method "$root"
mkdir -p "$H_PROJ/.claude/skills/helper"
printf '%s\n' '---' 'name: helper' 'description: A harness skill with a hook.' 'hooks:' '  PreToolUse:' '    - matcher: Bash' '      hooks:' '        - type: command' '          command: touch "$CLAUDE_PROJECT_DIR/skill-hook-ran.txt"' '---' 'Say HARNESS-HELPER.' >"$H_PROJ/.claude/skills/helper/SKILL.md"
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"tool":"Skill","input":{"skill":"helper"}},{"tool":"Bash","input":{"command":"echo ok > seen.txt","description":"a plain write"}},{"text":"MAIN-DONE"}]}]}' >"$H_DIR/g17.json"
if h_fake "$H_DIR/g17.json"; then
  h_client 60 -- --permission-mode default --allowedTools Skill Bash
  h_stop
  if h_tsv_has 'guard G17: the skill "helper" declares hooks in its frontmatter' && h_ran seen.txt && ! h_ran skill-hook-ran.txt; then
    pass "G17: a skill whose frontmatter declares a hook is refused, and its hook never runs"
  else
    fail "G17: a skill whose frontmatter declares a hook is refused" "$(cut -f7- "$H_DIR/fake/requests.tsv")"
  fi
  h_safe g17
else
  fail "g17: the fake did not answer; the client was not started"
fi

# --- 17. gate-receipt (step 5b.1): a gate's life in the real client, with
# the method's fragment and the harness's stand-in reviewer gate, one run
# in default mode and one in auto mode (h_gates, h_gate_holds); step
# 5b.2's evidence (an effort override, a second definition, the record's
# models and tokens) in the same default run ---
# gate_q QUESTION TEXT: passes TEXT (with what the question noted, if
# anything) when the gate question holds
gate_q() {
  if h_gate_holds "$1"; then pass "$2${H_NOTE:+ ($H_NOTE)}"; else fail "$2" "$H_WHY"; fi
}
if h_gates "$root" default; then
  gate_q context "gates: the start's context line (METHOD-ACTIVE gate=method-reviewer tree=<the tree>) reaches each gate's requests, and neither the main conversation's nor my-method-reviewer's"
  gate_q no-hook "gates: an agent named my-method-reviewer (a longer name holding a gate's) gets no gate-receipt hook at all and no receipt (the client's debug log: no run during its call, two during a gate's)"
  gate_q valid "gates (default mode): a report with both lines gets a VALID receipt in the project's git folder, with its opening word, in one turn"
  gate_q log "gates (default mode): .method/local/gates.log gets one line a gate run: the word, the gate, the tree, the model read from the gate's record and the effort the client gave"
  gate_q cut-off "gates (default mode): a report cut off is sent back once, gate-receipt's reason reaching the gate's next request; completed, it is VALID"
  gate_q never "gates (default mode): a report never completed gets one more turn only, then INCOMPLETE (lines-missing-after-retry)"
  gate_q effort "gates (default mode): a gate whose Agent call asks for effort low, below its file's xhigh, runs at low and is INVALID (effort-low), its gates.log line saying low"
  gate_q definition "gates (default mode): a gate run from another definition of its name is INVALID (instructions-differ): one given with --agents, which the client takes over the project's files; with a second project file of the name outside .claude/agents/method/, the receipt follows the file the client ran (INVALID for the other, VALID for the method's)"
  gate_q record "gates (default mode): a receipt's models, efforts and tokens are what the client wrote in the gate's record: claude-opus-5-5, the effort the gate ran at, and the fake's tokens summed over the gate's turns"
  h_safe gates-default
else
  fail "gates-default: the case could not be made, or the fake did not answer; the client was not started"
fi
if h_gates "$root" auto; then
  gate_q deny-once "gates (auto mode): a handback without its lines is refused once, the refusal reaching the gate's next request; handed back with them, VALID"
  gate_q twice "gates (auto mode): a second handback without its lines is let through (no loop), and the receipt is INCOMPLETE (lines-missing-after-retry)"
  gate_q text-only "gates (auto mode): a complete report given as text, never handed back, is INCOMPLETE (no-report), never refused or sent back"
  h_safe gates-auto
else
  fail "gates-auto: the case could not be made, or the fake did not answer; the client was not started"
fi
# (step 5b's repair: the client's prompt_id is the owner's current message,
# so receipts are kept by session, agent and run number)
if h_gates "$root" background; then
  gate_q background "gates (background): a background gate whose run outlives the owner's next message gets one receipt, VALID, and leaves no running file"
  h_safe gates-background
else
  fail "gates-background: the case could not be made, or the fake did not answer; the client was not started"
fi

# --- 18. the method's rules (step 6.1): the real rules files, laid out as
# sync will (h_method_words), reach the main session's first request and a
# gate's, exactly as tests/budget.test.sh counts them, and their rule ID
# comments reach no request (h_words, h_words_holds) ---
words_q() {
  if h_words_holds "$1"; then pass "$2"; else fail "$2" "$H_WHY"; fi
}
if h_words "$root"; then
  words_q reach "words: the method's rules files reach the main session's first request exactly as the budget counts them (each line holding only a comment dropped, every other byte kept)"
  words_q gate "words: the method's rules files reach a gate's first request the same way"
  words_q comments "words: no rule ID comment from the rules files reaches any request of the main session or the gate"
  h_safe words
else
  fail "words: the case could not be made, or the fake did not answer; the client was not started"
fi

# --- 19. the gates (step 6.2): the method's own gate files, laid out as
# sync will, each called by the main session in one message in the
# foreground, once in default mode and once in auto mode (h_real_gates,
# h_real_holds); since step 6b.1 each reads the review packet first, and in
# default mode one gate's calls meet the guard (N1) ---
real_q() {
  if h_real_holds "$1"; then pass "$2"; else fail "$2" "$H_WHY"; fi
}
if h_real_gates "$root" default; then
  real_q loads "real gates: each gate file in verdicts.txt loads (in the init event's agents), with no unknown-key, parse or not-loaded line in the client's debug log"
  real_q valid "real gates (default mode): each gate's receipt is VALID with its word, its real body compared with what the client sent (B10)"
  real_q record "real gates (default mode): each receipt took the fragment's model and effort xhigh from the gate's record"
  real_q tools "real gates (default mode): each gate is offered its tools, Read and Bash among them, and no Agent, Task, Skill or SendMessage"
  real_q base "real gates (default mode): each gate reads the review packet first, and its VALID receipt records the packet's base, the merge base"
  real_q refused "real gates (default mode, N1): inside a gate the guard still refuses a write to the project's settings (G6) and a push to main (G3); nothing changed, and the receipt stays VALID"
  h_safe real-gates-default
else
  fail "real-gates-default: the case could not be made, or the fake did not answer; the client was not started"
fi
if h_real_gates "$root" auto; then
  real_q handback "real gates (auto mode): with tools: set, each gate is still offered SubagentHandback"
  real_q valid "real gates (auto mode): each gate's handback gets a VALID receipt with its word"
  real_q tools "real gates (auto mode): each gate is offered no Agent, Task, Skill or SendMessage"
  real_q base "real gates (auto mode): each gate reads the review packet first, and its VALID receipt records the packet's base, the merge base"
  h_safe real-gates-auto
else
  fail "real-gates-auto: the case could not be made, or the fake did not answer; the client was not started"
fi
# Deep review (step 6b.3, F12, item 31): three runs of the reviewer in one
# message, each with its own match string, each leaving its own VALID receipt
if h_real_gates "$root" deep; then
  real_q own "real gates (deep): three method-reviewer runs launched in one message each leave a VALID receipt of their own, three for the tree"
  real_q base "real gates (deep): each of the three runs reads the review packet first, and its receipt records the merge base"
  real_q record "real gates (deep): each of the three runs took the fragment's model and effort xhigh"
  h_safe real-gates-deep
else
  fail "real-gates-deep: the case could not be made, or the fake did not answer; the client was not started"
fi

# --- 20. planning and design (step 6.4): the method's skills typed as the
# owner's message (-p "/method-plan ..." and "/method-design ...", F6), and
# the method's architect called by the main session in the foreground, once
# in default mode and once in auto mode (h_design, h_design_holds) ---
design_q() {
  if h_design_holds "$1"; then pass "$2"; else fail "$2" "$H_WHY"; fi
}
if h_design "$root" default; then
  design_q expands "design (default mode): -p \"/method-plan ...\" sends method-plan's SKILL.md body as written, with the typed arguments; its '# rules:' line reaches no request; every method skill is in init's slash_commands"
  design_q loads "design: method-architect loads (in the init event's agents), with no unknown-key, parse or not-loaded line in the client's debug log"
  design_q model "design (default mode): the architect's requests go out at the fragment's model and effort xhigh"
  design_q tools "design (default mode): the architect is offered Read and WebFetch, and no Agent, Task, Skill, SendMessage, Bash, PowerShell, Monitor, Edit, Write, MultiEdit or NotebookEdit"
  design_q receipt "design (default mode): the architect makes no receipt (gate-receipt does not run during its call; no receipt, no gates.log line, no METHOD-ACTIVE line for it)"
  h_safe design-default
else
  fail "design-default: the case could not be made, or the fake did not answer; the client was not started"
fi
if h_design "$root" auto; then
  design_q expands "design (auto mode): -p \"/method-design ...\" sends method-design's SKILL.md body as written, with the typed arguments"
  design_q ends "design (auto mode): the architect is offered SubagentHandback, hands its design back in one turn, and the main session gets it"
  design_q model "design (auto mode): the architect's requests go out at the fragment's model and effort xhigh"
  design_q tools "design (auto mode): the architect is offered Read and WebFetch, and no delegation, command or writing tool"
  design_q receipt "design (auto mode): the architect makes no receipt (gate-receipt runs once, on its handback, and lets it through)"
  h_safe design-auto
else
  fail "design-auto: the case could not be made, or the fake did not answer; the client was not started"
fi

# --- 21. /method-start (step 6.5): the skill typed as the owner's message
# (-p "/method-start", F6), with the method's fragment, once with the start
# hook and the main session's two Bash calls, once without the start hook
# (h_start, h_start_holds) ---
start_q() {
  if h_start_holds "$1"; then pass "$2"; else fail "$2" "$H_WHY"; fi
}
if h_start "$root" default; then
  start_q expands "start: -p \"/method-start\" sends method-start's SKILL.md body, with no ARGUMENTS line; its '# rules:' line reaches no request; it is in init's slash_commands"
  start_q effort "start: \${CLAUDE_EFFORT} in method-start is substituted with the session's effort (the fragment's effortLevel, which the main session's requests carry), and no \${...} reaches a request as written (F6)"
  start_q guard "start: the skill's Bash calls reach the guard: status.sh in a call of its own passes and runs; status.sh && git commit is refused (G6) and commits nothing"
  start_q active "start: with the start hook, its METHOD-ACTIVE line reaches the main session's first request"
  start_q merged "start (6b.4): the skill's text naming its merged pull request read (gh pr list --state merged), which compares HEAD with the merged head (git merge-base --is-ancestor) and counts from the one merged last (mergedAt, --not <its headRefOid> origin/<main>), reaches the main session (the text only)"
  h_safe start-default
else
  fail "start-default: the case could not be made, or the fake did not answer; the client was not started"
fi
if h_start "$root" nohook; then
  start_q expands "start (no start hook): -p \"/method-start\" still sends method-start's SKILL.md body"
  start_q named "start (no start hook): no METHOD-ACTIVE line comes, and the skill's text that names the missing METHOD-ACTIVE line reaches the main session (the text only; acting on it is convention)"
  h_safe start-nohook
else
  fail "start-nohook: the case could not be made, or the fake did not answer; the client was not started"
fi

# --- 22. /method-finish (step 6b.4): the skill typed as the owner's
# message (-p "/method-finish", F6), with the method's fragment and its start
# hook; the main session only answers (h_start finish, h_start_holds) ---
if h_start "$root" finish; then
  start_q expands "finish: -p \"/method-finish\" sends method-finish's SKILL.md body, with no ARGUMENTS line; its '# rules:' line reaches no request; it is in init's slash_commands"
  start_q steps "finish: method-finish's thirteen numbered steps reach the main session, and its text names run-checks, the packet, done-check --ready, report-check, the files log with --no-renames, the push and gh pr create"
  h_safe finish
else
  fail "finish: the case could not be made, or the fake did not answer; the client was not started"
fi

# --- 23. /method-setup (step 7.5): the skill typed as the owner's message
# (-p "/method-setup", F6), with the method's fragment and its start hook;
# the main session only answers (h_start setup, h_start_holds). A plain -p run
# offers no AskUserQuestion (step 7.0, F5), so it is the plain-text
# fallback the skill names that such a run takes ---
if h_start "$root" setup; then
  start_q expands "setup: -p \"/method-setup\" sends method-setup's SKILL.md body, with no ARGUMENTS line; its '# rules:' line reaches no request; it is in init's slash_commands"
  start_q setup "setup: method-setup sets disable-model-invocation, its six numbered steps reach the main session, they name the answers file, setup-write.sh without and with --write, AskUserQuestion with its plain-text fallback, /reload-skills and the owner's reply, and its description reaches no request"
  h_safe setup
else
  fail "setup: the case could not be made, or the fake did not answer; the client was not started"
fi
# F2 (step 7.0), kept as a case: setup-write --write run by the main
# session in a session with the method's hooks, with answers that change
# the profile (best to budget). The guard lets the call through (G6's
# method scripts), settings.json and method.lock hold the bytes the same
# run gives outside a session, and G16 refuses applying the settings
# change mid-session: logged, and the next call the guard lets through
# brings its one-time message, which names no file, so the card's own
# first line names .claude/settings.json (S10) (h_setup_f2,
# h_setup_f2_holds)
f2_q() {
  if h_setup_f2_holds "$1"; then pass "$2"; else fail "$2" "$H_WHY"; fi
}
if h_setup_f2 "$root"; then
  f2_q bytes "F2: setup-write --write in a hooked session passes the guard, and settings.json and method.lock hold the bytes the same run gives outside a session"
  f2_q g16 "F2: G16 refuses applying the settings setup-write wrote mid-session (logged), and the next call brings its one-time message"
  f2_q card "F2: the card's first line, which reaches the main session, names .claude/settings.json; G16's one-time message names no file"
  h_safe setup-f2
else
  fail "setup-f2: the case could not be made, or the fake did not answer; the client was not started"
fi

echo "harness: ${H_RUNS:-0} client runs took ${H_TOTAL_SECS:-0} s"
finish
