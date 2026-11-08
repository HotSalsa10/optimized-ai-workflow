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
sig=$(perl -e 'my $pid = fork; if (!$pid) { setpgrp(0, 0); exec "bash", "-c", q{perl "$0" 60 sleep 30; echo HARNESS-WENT-ON}, $ARGV[0] } sleep 1; kill "INT", -$pid; waitpid $pid, 0; print $? & 127' "$HARNESS/bound.pl")
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
  if [ -n "${METHOD_HARNESS_VERSION:-}" ]; then
    if [ "$version" = "$METHOD_HARNESS_VERSION" ]; then pass "startup: the client is the version asked for ($METHOD_HARNESS_VERSION)"; else fail "startup: the client reports '$version', not the version asked for ($METHOD_HARNESS_VERSION)"; fi
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
  if h_reached && ! h_req_has '"effort" : "xhigh"' && [ ! -e "$H_PROJ/.harness/env.txt" ]; then
    pass "rejected-shape: one value of the wrong type makes the client skip the whole file, hooks included (effort is not xhigh; the hook did not run), so settings.test.sh checks every value's type"
  else
    fail "rejected-shape: one value of the wrong type makes the client skip the whole file: effort xhigh still applied, so the client now keeps the rest; settings.test.sh's note is out of date"
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
  if h_req_has 'METHOD-ACTIVE vunreleased' && { h_req_has 'status: nothing needs a look' || h_req_has ' areas need a look ('; }; then pass "session-status: METHOD-ACTIVE and status's summary reach the first request"; else fail "session-status: METHOD-ACTIVE and status's summary reach the first request" "$(LC_ALL=C grep -h -o 'METHOD-ACTIVE[^"]*' "$H_DIR"/fake/req-*.json | head -3)"; fi
  rm -f "$H_DIR"/fake/req-*.json
  # the resumed request also holds the first session's text, and the client
  # does not add output identical to what it already has: so the tree is
  # changed first, and the resume's own tag and new line are required
  printf 'x\n' >"$H_PROJ/changed-before-resume.txt"
  # shellcheck disable=SC2086
  H_PROMPT=again h_client 60 -- $D --resume "$sid"
  h_stop
  if h_req_has 'SessionStart:resume hook success: METHOD-ACTIVE vunreleased' && h_req_has 'work: LOOK - 1 uncommitted'; then pass "session-status: a resumed session gets METHOD-ACTIVE and its own status again"; else fail "session-status: a resumed session gets METHOD-ACTIVE and its own status again" "$(LC_ALL=C grep -h -o 'SessionStart:[a-z]* hook success: [^"]\{0,80\}' "$H_DIR"/fake/req-*.json | sort -u | head -4)"; fi
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
  if h_req_has 'METHOD-ACTIVE vunreleased' && h_req_has 'work: LOOK - ' && h_req_has 'status: 1 areas need a look (work)'; then pass "session-status: with a dirty tree (status exits 1) the line and the LOOK still reach Claude"; else fail "session-status: with a dirty tree the line and the LOOK still reach Claude"; fi
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
  if h_req_has 'METHOD-ACTIVE vunreleased' && h_req_has 'perl or its JSON::PP module is missing'; then pass "session-status: without perl on PATH, METHOD-ACTIVE and a LOOK saying so still reach Claude"; else fail "session-status: without perl on PATH, METHOD-ACTIVE and a LOOK saying so still reach Claude" "$(tail -3 "$H_DIR/err.txt")"; fi
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
  if h_req_has 'METHOD-ACTIVE vunreleased (nested: status skipped)'; then pass "session-status: a nested run (METHOD_NESTED=1) gets the one short line"; else fail "session-status: a nested run gets the one short line"; fi
  h_safe session-status-nested
else
  fail "session-status-nested: the fake did not answer; the client was not started"
fi

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

echo "harness: ${H_RUNS:-0} client runs took ${H_TOTAL_SECS:-0} s"
finish
