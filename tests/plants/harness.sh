#!/usr/bin/env bash
# Plants for the harness's own checks (step 5.2): each must turn red for its
# stated reason, so a harness that passes is known to look. Like the
# harness, it needs a client: METHOD_HARNESS_CLIENT names one; without it
# this file says SKIPPED, which is never a pass. Runs in throwaway folders
# and copies only.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: harness"
finish() {
  echo "plants: harness: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
  [ "$tests_fail" -eq 0 ]
  exit
}
client=${METHOD_HARNESS_CLIENT:-}
case $client in '' | /*) ;; *) client=$PWD/$client ;; esac
if [ -z "$client" ]; then
  skip "harness plants: no client given; set METHOD_HARNESS_CLIENT to a Claude Code binary to run them"
  finish
fi

root=$(repo_root)
HARNESS="$root/tests/harness"
H_CLIENT=$client
H_WORK=$(new_sandbox_dir) || abort_sandbox
# shellcheck source=tests/harness/lib.sh
. "$HARNESS/lib.sh"
# the case folders, the fake's logs among them, go on any exit (a TERM too)
trap 'h_stop; drop_sandbox "$H_WORK" || true' EXIT
# shellcheck disable=SC2329 # called through expect_landed
lacks_line() {
  ! grep -q -- "$1" "$2"
}
D="--permission-mode default --allowedTools Bash WebFetch"
two='{"convs":[{"name":"main","match":"^go$","turns":[{"tool":"Bash","input":{"command":"touch one.txt","description":"one"}},{"text":"MAIN-DONE"}]}]}'

# 1. a fake that never answers: the case stops before the client starts
cat >"$H_WORK/silent.pl" <<'EOF'
use IO::Socket::INET; my %a = @ARGV; my $s = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => 0, Listen => 5, ReuseAddr => 1) or die;
open my $p, '>', "$a{'--port-file'}.tmp" or die; print $p $s->sockport, "\n"; close $p; rename "$a{'--port-file'}.tmp", $a{'--port-file'};
alarm 60; my @held; while (my $c = $s->accept) { push @held, $c }
EOF
h_case silent
printf '%s\n' "$two" >"$H_DIR/script.json"
start=$(perl -e 'print time')
if H_FAKE_API="$H_WORK/silent.pl" h_fake "$H_DIR/script.json"; then
  h_stop
  fail "a fake that never answers stops the case before the client starts: it was taken as up"
else
  took=$(($(perl -e 'print time') - start))
  if [ "$took" -le 15 ] && [ ! -e "$H_DIR/out.jsonl" ]; then pass "a fake that never answers stops the case before the client starts (in ${took} s)"; else fail "a fake that never answers stops the case before the client starts" "took ${took} s"; fi
fi

# 2. a client pointed at a dead port: "no request reached the fake"
h_case dead-port
printf '%s\n' "$two" >"$H_DIR/script.json"
if h_fake "$H_DIR/script.json"; then
  real_port=$H_PORT
  H_PORT=$(perl -MIO::Socket::INET -e 'my $s = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => 0, Listen => 1) or die; print $s->sockport')
  # shellcheck disable=SC2086 # D holds several arguments on purpose
  h_client 60 -- $D
  H_PORT=$real_port
  h_stop
  # (the client did start: it wrote its init event, then could not connect)
  if h_reached; then fail "a client pointed at a dead port: the reach check said a request arrived"
  elif [ -z "$(h_init session_id 2>/dev/null)" ]; then fail "a client pointed at a dead port: the client never started, so the plant shows nothing" "$(tail -3 "$H_DIR/err.txt")"
  else pass "a client pointed at a dead port: the reach check sees that no request reached the fake (in $H_SECS s)"; fi
else
  fail "dead-port: the fake did not answer"
fi

# 3. a request cap of 1: the cap check goes red
h_case cap-one
printf '%s\n' "$two" >"$H_DIR/script.json"
if h_fake "$H_DIR/script.json" 1; then
  # shellcheck disable=SC2086
  h_client 60 -- $D
  h_stop
  if h_no_overcap; then fail "a request cap of 1: the cap check did not see the cap reached"; else pass "a request cap of 1: the cap check sees the cap reached"; fi
else
  fail "cap-one: the fake did not answer"
fi

# 4. an outside call through the trap: the connection check goes red
h_case trap
printf '%s\n' '{"model":"claude-opus-5-5","skipWebFetchPreflight":true}' | h_settings
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"tool":"WebFetch","input":{"url":"https://example.invalid/","prompt":"summarize"}},{"text":"MAIN-DONE"}]}]}' >"$H_DIR/script.json"
if h_fake "$H_DIR/script.json"; then
  # shellcheck disable=SC2086
  h_client 60 -- $D
  h_stop
  if h_no_connect; then fail "an outside call through the trap: the connection check did not see it" "$(cut -f7- "$H_DIR/fake/requests.tsv")"; else pass "an outside call through the trap: the connection check sees it (CONNECT refused and logged)"; fi
else
  fail "trap: the fake did not answer"
fi

# 5. a plain-http call through the proxy (no CONNECT): it counts too
h_case trap-http
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"tool":"Bash","input":{"command":"curl -s -m 5 http://example.invalid/harness-plain-http >/dev/null; true","description":"a plain-http call"}},{"text":"MAIN-DONE"}]}]}' >"$H_DIR/script.json"
if h_fake "$H_DIR/script.json"; then
  # shellcheck disable=SC2086
  h_client 60 -- $D
  h_stop
  if h_no_connect; then fail "a plain-http call through the proxy: the connection check did not see it" "$(cut -f3-7 "$H_DIR/fake/requests.tsv")"; else pass "a plain-http call through the proxy: the connection check sees it (a request for a whole URL)"; fi
else
  fail "trap-http: the fake did not answer"
fi

# 6. an extra variable that would replace one of the case's own settings,
# or carry a key, is refused, and nothing runs
h_case extras
for extra in HOME=/elsewhere NODE_OPTIONS=--require=x DISABLE_AUTOUPDATER=0 GIT_CONFIG_GLOBAL=/x LD_PRELOAD=/x MY_TOKEN=x DB_PASSWORD=x; do
  rm -f "$H_DIR/out.jsonl"
  if h_client 5 "$extra" -- --version 2>"$H_DIR/refused.txt"; then fail "an extra $extra for the client was let through"
  elif [ "${H_RC:-}" = 2 ] && [ ! -e "$H_DIR/out.jsonl" ] && LC_ALL=C grep -q "refusing to pass ${extra%%=*}=" "$H_DIR/refused.txt"; then pass "an extra $extra for the client is refused by name, and the client is not started"
  else fail "an extra $extra for the client is refused" "rc ${H_RC:-?}: $(cat "$H_DIR/refused.txt")"; fi
done

# 7. no refusing hook: the command the case expects refused runs
h_case no-guard
h_fixtures
printf '%s\n' '{"model":"claude-opus-5-5"}' | h_settings
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"tool":"Bash","input":{"command":"touch refused-ran.txt # HARNESS-REFUSE-ME","description":"A refused command"}},{"text":"MAIN-DONE"}]}]}' >"$H_DIR/script.json"
if h_fake "$H_DIR/script.json"; then
  # shellcheck disable=SC2086
  h_client 60 -- $D
  h_stop
  if h_ran refused-ran.txt; then pass "with no refusing hook, the command a case expects refused runs, so the refusal check can tell"; else fail "with no refusing hook, the command a case expects refused runs"; fi
else
  fail "no-guard: the fake did not answer"
fi

# 8. a client that writes its temporary files outside the case: the check
# for them goes red (here the "outside" folder is in the case, so nothing
# is left in /tmp: the client's own naming is what is checked)
h_case tmp-outside
printf '%s\n' "$two" >"$H_DIR/script.json"
if h_fake "$H_DIR/script.json"; then
  mkdir -p "$H_DIR/outside"
  # shellcheck disable=SC2086
  H_TMPDIR="$H_DIR/outside" h_client 60 -- $D
  h_stop
  if H_TMP_ROOT="$H_DIR/outside/claude-$(id -u)" h_tmp_clean; then fail "a client that writes its temporary files outside the case: the check did not see them" "$(ls "$H_DIR/outside" 2>&1)"; else pass "a client that writes its temporary files outside the case: the check sees them (by this run's own word in their names)"; fi
  if h_tmp_used; then fail "a client that does not use the case's TMPDIR: the check did not see it" "$(ls "$H_DIR/tmp" 2>&1)"; else pass "a client that does not use the case's TMPDIR: the check sees it (no claude-$(id -u) folder in the case's own)"; fi
else
  fail "tmp-outside: the fake did not answer"
fi

# 9. a request with a key other than the dummy one (here from an
# apiKeyHelper in the project's settings): the key check goes red
h_case key-helper
printf '%s\n' '{"model":"claude-opus-5-5","apiKeyHelper":"echo not-the-dummy-key"}' | h_settings
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"text":"MAIN-DONE"}]}]}' >"$H_DIR/script.json"
if h_fake "$H_DIR/script.json"; then
  # shellcheck disable=SC2086
  h_client 60 -- $D
  h_stop
  if h_keys_ok; then fail "a request with a key other than the dummy one: the check did not see it" "$(cut -f9 "$H_DIR/fake/requests.tsv")"; else pass "a request with a key other than the dummy one: the check sees it (the fake logs each key's kind, never the key)"; fi
  if LC_ALL=C grep -r -q not-the-dummy-key "$H_DIR/fake"; then fail "the fake keeps no key: the planted key is in its logs"; else pass "the fake keeps no key: the planted key is in none of its logs"; fi
else
  fail "key-helper: the fake did not answer"
fi

# 10. a run without --strict-mcp-config: a .mcp.json above the project
# starts its server, so the harness's mcp-stray case can tell
h_case mcp-stray
printf '%s\n' '{"model":"claude-opus-5-5","enableAllProjectMcpServers":true}' | h_settings
perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({mcpServers => {stray => {type => "stdio", command => "perl", args => [$ARGV[0], $ARGV[1]]}}})' \
  "$HARNESS/fake-mcp.pl" "$H_DIR/stray.log" >"$H_DIR/.mcp.json"
printf '%s\n' '{"convs":[{"name":"main","match":"^go$","turns":[{"text":"MAIN-DONE"}]}]}' >"$H_DIR/script.json"
if lacks_line ' --strict-mcp-config ' "$HARNESS/lib.sh"; then
  fail "h_client no longer gives --strict-mcp-config, so this plant cannot remove it"
elif h_fake "$H_DIR/script.json"; then
  (
    eval "$(declare -f h_client | sed 's/ --strict-mcp-config / /')"
    # shellcheck disable=SC2086
    h_client 60 -- $D
  )
  h_stop
  if [ -e "$H_DIR/stray.log" ]; then pass "without --strict-mcp-config, a .mcp.json above the project starts its server (the mcp-stray case can tell)"; else fail "without --strict-mcp-config, a .mcp.json above the project starts its server"; fi
else
  fail "mcp-stray: the fake did not answer"
fi

# 11. SubagentStart's text reaching the main conversation only: the
# subagent question goes red
h_case subagent-main
h_fixtures
h_settings <<EOF
{"model":"claude-opus-5-5",
 "hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/fixture/say.sh\" HARNESS-SUBAGENT-CONTEXT"}]}]}}
EOF
cat >"$H_DIR/script.json" <<'EOF'
{"convs":[
  {"name":"sub","match":"HARNESS-SUBAGENT-TASK","turns":[{"text":"APPROVE\nEND-VERDICT harness"}]},
  {"name":"main","match":"^go$","turns":[
    {"tool":"Agent","input":{"description":"harness review","prompt":"HARNESS-SUBAGENT-TASK: review the change","subagent_type":"reviewer","run_in_background":false}},
    {"text":"MAIN-DONE"}]}],
 "fallback":{"text":"FAKE-FALLBACK"}}
EOF
if h_fake "$H_DIR/script.json"; then
  # shellcheck disable=SC2086
  h_client 90 -- $D
  h_stop
  if h_req_in sub HARNESS-SUBAGENT-CONTEXT; then fail "SubagentStart text in the main conversation only: the subagent question still says yes"
  elif ! h_req_in main HARNESS-SUBAGENT-CONTEXT; then fail "SubagentStart text in the main conversation only: the text reached no request, so the plant shows nothing"
  else pass "SubagentStart text in the main conversation only: the subagent question says no"; fi
else
  fail "subagent-main: the fake did not answer"
fi

# 12. the harness file itself, in a copy: a tool missing from tools.txt, a
# wrong version asked for, a client that is not there
sb=$(make_sandbox) || abort_sandbox
grep -v '^Bash	' "$sb/tests/harness/tools.txt" >"$sb/tools.tmp" && mv "$sb/tools.tmp" "$sb/tests/harness/tools.txt"
if expect_landed "tools.txt without Bash" lacks_line '^Bash	' "$sb/tests/harness/tools.txt"; then
  out=$(cd "$sb" && METHOD_HARNESS_CLIENT="$client" bash tests/harness.test.sh 2>&1)
  if printf '%s\n' "$out" | grep -q "FAIL  startup: tools the client offers that tests/harness/tools.txt does not list:.* Bash"; then pass "a tool missing from tools.txt turns the harness red, naming it"; else fail "a tool missing from tools.txt turns the harness red, naming it" "$(printf '%s\n' "$out" | grep -v '^  PASS' | head -5)"; fi
fi
out=$(cd "$sb" && METHOD_HARNESS_CLIENT="$client" METHOD_HARNESS_VERSION=0.0.1 bash tests/harness.test.sh 2>&1)
if printf '%s\n' "$out" | grep -q "FAIL  startup: the client reports '[0-9][^']*', not the version asked for (0.0.1)"; then pass "a client that is not the version asked for turns the harness red"; else fail "a client that is not the version asked for turns the harness red" "$(printf '%s\n' "$out" | grep -v '^  PASS' | head -5)"; fi
out=$(cd "$sb" && METHOD_HARNESS_CLIENT="$sb/no-such-client" bash tests/harness.test.sh 2>&1)
code=$?
if [ "$code" -ne 0 ] && printf '%s\n' "$out" | grep -q "FAIL  harness: METHOD_HARNESS_CLIENT is set, but it names no program"; then pass "a client that is named but not there fails the harness (exit $code)"; else fail "a client that is named but not there fails the harness" "exit $code: $out"; fi
out=$(cd "$sb" && METHOD_HARNESS_CLIENT='' bash tests/harness.test.sh 2>&1)
code=$?
if [ "$code" -eq 0 ] && printf '%s\n' "$out" | grep -q "SKIP  harness: no client given" && printf '%s\n' "$out" | grep -q "0 passed, 0 failed, 1 skipped"; then pass "with no client named, the harness says SKIPPED and passes nothing"; else fail "with no client named, the harness says SKIPPED and passes nothing" "exit $code: $out"; fi
drop_sandbox "$sb" || true

# 13. get-client: a download that does not match the pinned checksum is refused
reg="$H_WORK/registry/@anthropic-ai/claude-code-linux-x64/-"
mkdir -p "$reg" "$H_WORK/pkg/package"
printf '#!/bin/sh\necho planted\n' >"$H_WORK/pkg/package/claude"
tested=$(sed -n 's/^tested	//p' "$HARNESS/VERSIONS")
(cd "$H_WORK/pkg" && tar -czf "$reg/claude-code-linux-x64-$tested.tgz" package)
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64)
    out=$(METHOD_HARNESS_REGISTRY="file://$H_WORK/registry" bash "$HARNESS/get-client.sh" tested "$H_WORK/got" 2>&1)
    code=$?
    if [ "$code" -eq 1 ] && printf '%s\n' "$out" | grep -q "does not match VERSIONS" && [ ! -e "$H_WORK/got/claude" ]; then pass "get-client refuses a download that does not match the pinned checksum, and installs nothing"; else fail "get-client refuses a download that does not match the pinned checksum" "exit $code: $out"; fi
    ;;
  *) skip "get-client's checksum plant: get-client pins Linux x64 only" ;;
esac

finish
