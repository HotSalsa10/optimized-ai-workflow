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
# (and the repo copy plant 12 makes, if a stop comes while it runs)
trap 'h_stop; [ -z "${sb:-}" ] || [ ! -d "$sb" ] || drop_sandbox "$sb" || true; drop_sandbox "$H_WORK" || true' EXIT
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

# 2b. a second fake in the same case: a run that reaches nothing after one
# that reached the first fake reads as reaching nothing (the second fake
# starts with empty logs)
h_case two-fakes
printf '%s\n' "$two" >"$H_DIR/script.json"
if h_fake "$H_DIR/script.json"; then
  # shellcheck disable=SC2086
  h_client 60 -- $D
  if h_reached && h_fake "$H_DIR/script.json"; then
    real_port=$H_PORT
    H_PORT=$(perl -MIO::Socket::INET -e 'my $s = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => 0, Listen => 1) or die; print $s->sockport')
    # shellcheck disable=SC2086
    h_client 60 -- $D
    H_PORT=$real_port
    h_stop
    if h_reached || h_tsv_has 'conv=main'; then fail "a second fake in one case: the reach check answered from the first fake's logs"; else pass "a second fake in one case starts with empty logs, so a run that reached nothing reads as such"; fi
  else
    h_stop
    fail "two-fakes: the first run did not reach the fake, or the second fake did not answer"
  fi
else
  fail "two-fakes: the fake did not answer"
fi

# 2c. settings that are not one JSON object fail the case (the client
# would skip the file, and a "no hook ran" case would pass for that)
h_case bad-settings
out=$( (printf '{"model": "claude-opus-5-5",}\n' | h_settings) 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q "FAIL  h_settings: the case's settings are not one JSON object"; then pass "settings that are not one JSON object fail the case"; else fail "settings that are not one JSON object fail the case" "rc $rc: $out"; fi

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
for extra in HOME=/elsewhere NODE_OPTIONS=--require=x BUN_OPTIONS=--preload=x CLAUDE_CODE_TMPDIR=/x BASH_ENV=/x DISABLE_AUTOUPDATER=0 GIT_CONFIG_GLOBAL=/x LD_PRELOAD=/x MY_TOKEN=x DB_PASSWORD=x MY_KEY_FILE=x GITHUB_PAT=x; do
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

# 14. step 5.9's holds case (h_holds_start): with the hooks' whole command
# form (BASH_ENV= ENV= bash -p) reduced to plain bash, the case goes red.
# (A plant of -p alone, or of "command" before perl, stays green here: on
# Linux the client starts hooks through /bin/sh, and dash drops the
# exported-function variables before bash sees them. bash -p's own effect
# is shown in tests/guard-watch.test.sh, with plain bash as the control;
# A68)
sb=$(make_sandbox) || abort_sandbox
perl -pi -e 's/BASH_ENV= ENV= bash -p /bash /g' "$sb/method/settings.fragment.json"
landed=$(grep -c 'bash -p' "$sb/method/settings.fragment.json")
if [ "$landed" != 0 ]; then
  fail "holds (plain bash plant): the plant did not apply, so the check result would mean nothing"
else
  h_holds_start "$sb"
  h_stop
  if [ -n "$H_HOLD" ]; then pass "holds: with the hooks run as plain bash, the case goes red ($H_HOLD)"; else fail "holds: with the hooks run as plain bash, the case stayed green"; fi
fi
drop_sandbox "$sb" || true

# 15. step 5b.1's and 5b.2's gate cases (h_gates, h_gate_holds): with one
# defect planted in a copy of the method, the gate question it breaks turns
# red, and for that defect's reason (H_WHY holds what the question saw).
# gate_plant MODE FILE PERL QUESTION SEEN TEXT: PERL, a perl -pi script
# that writes the mark HARNESS-PLANT with its change, changes method/FILE
# in a copy of the repository; h_gates runs there in MODE; QUESTION must
# fail with SEEN in its H_WHY
gate_plant() {
  sb=$(make_sandbox) || abort_sandbox
  perl -pi -e "$3" "$sb/method/$2"
  if ! grep -q -F HARNESS-PLANT "$sb/method/$2"; then
    fail "$6: the plant did not apply, so the check result would mean nothing"
  elif ! h_gates "$sb" "$1"; then
    fail "$6: the case could not be made, or the fake did not answer"
  elif h_gate_holds "$4"; then
    fail "$6: the gate question '$4' stayed green"
  else
    case $H_WHY in
      *"$5"*) pass "$6: the gate question '$4' turns red ($H_WHY)" ;;
      *) fail "$6: the gate question '$4' turned red for another reason" "$H_WHY" ;;
    esac
  fi
  h_stop
  drop_sandbox "$sb" || true
}
rp=scripts/method/lib/receipt.pl
# shellcheck disable=SC2016 # perl code, expanded by perl
{
  gate_plant default "$rp" 's/^(\s*)return Hook::json\(\{ hookSpecificOutput => \{ hookEventName => .SubagentStart.*$/$1return 0; # HARNESS-PLANT/' \
    context "the context line is not in gateA's requests" "gates: the start's context line dropped"
  # (the pattern without its ^; JSON has no comments, so the mark is an
  # alternative no agent is named. Measured at 2.1.316 and 2.1.319: a bare
  # list, "method-reviewer|method-tester", is matched name by name and does
  # not take my-method-reviewer; a pattern without ^ does)
  gate_plant default settings.fragment.json 's/"\^\((method-reviewer\|[^"]*)\)\$"/"($1|HARNESS-PLANT)\$"/g' \
    no-hook "gate-receipt ran 2 times during my-method-reviewer's call" "gates: the fragment's gate matchers unanchored at the start"
  gate_plant default "$rp" 's/^(\s*)return \@why \? \$w->\{unchecked\} : \$w->\{good\};/$1return \$w->{unchecked}; # HARNESS-PLANT/' \
    valid "gate A's receipt: INCOMPLETE why=none open=APPROVE" "gates: the receipt never VALID"
  gate_plant default "$rp" 's/^(\s*)log_line\(\$project, \$r, \$in\);/$1# HARNESS-PLANT/' \
    log "gates.log: 0 VALID, 0 INCOMPLETE, 0 lines" "gates: the gates.log line dropped"
  gate_plant default "$rp" 's/^(\s*)return Hook::block\(form_text\(\$gate, \$r->\{tree\}\)\);/$1return 0; # HARNESS-PLANT/' \
    cut-off "gate B's turns: 1;" "gates: the block removed (a report without its lines is let go)"
  gate_plant default "$rp" 's/if \(!\$r->\{blocked\} && !\@why\) \{/if (!\@why) { # HARNESS-PLANT/' \
    never "gate C's receipt: INCOMPLETE why=lines-missing open=none" "gates: the block not once (every stop without the lines is sent back)"
  gate_plant auto "$rp" 's/if \(!\$ok && !\$r->\{denied\}\) \{/if (0) { # HARNESS-PLANT/' \
    deny-once "the refusal is not in gate D's requests" "gates: the denial removed (a handback without its lines is let through)"
  gate_plant auto "$rp" 's/if \(!\$ok && !\$r->\{denied\}\) \{/if (!\$ok) { # HARNESS-PLANT/' \
    twice "gate E's receipt: INCOMPLETE why=no-report" "gates: the denial not once (every handback without its lines is refused)"
  gate_plant auto "$rp" 's/\} elsif \(\$auto\) \{/} elsif (0) { # HARNESS-PLANT/' \
    text-only "gate F's receipt: VALID why=none open=APPROVE" "gates: auto mode's text taken as the report"
  # (step 5b.2's evidence, in the same default run)
  gate_plant default "$rp" 's/^(\s*push \@why, .effort-low. if )(\$floor && .*;)$/${1}0 && $2 # HARNESS-PLANT/' \
    effort "gate G's receipt: VALID why=none open=APPROVE" "gates: the effort check removed (a gate run below its file's effort passes)"
  gate_plant default "$rp" 's/^(\s*push \@why, .instructions-differ. if )(\$same && !\(\$m && trimmed.*;)$/${1}0 && $2 # HARNESS-PLANT/' \
    definition "gate H's receipt: VALID why=none open=APPROVE" "gates: the instructions check removed (a gate run from another definition passes)"
  gate_plant default "$rp" 's/^(\s*\$ev->\{tokens\}\{ \$k->\[0\] \}) \+= (\$v if .*;)$/$1 = $2 # HARNESS-PLANT/' \
    record "gate B's receipt holds models=claude-opus-5-5 efforts=xhigh input=11 output=7 " "gates: the record's tokens not summed (each message's usage replaces the one before)"
  # (step 5b's repair: a run numbered by its prompt id again, at the start
  # and at the handback and stop, as the receipts were named before it)
  gate_plant background "$rp" 's{^(\s*my \$run = )newest\(\$dir, \$part\) \|\| 1;}{${1}hex(substr(sha("prompt", \$in->{prompt_id} // ""), 0, 7)) || 1; # HARNESS-PLANT}; s{^(\s*\$run = )newest\(\$dir, \$part\) \+ 1;}{${1}hex(substr(sha("prompt", \$in->{prompt_id} // ""), 0, 7)) || 1; # HARNESS-PLANT}' \
    background "gate X's receipt: none; 1 running files left" "gates: receipts kept by the prompt id again (a background gate's stop after the owner's next message misses its run)"
}

# 16. step 6.1's case for the method's rules (h_words, h_words_holds):
# with one defect planted in a copy of the method's rules files, the
# questions it breaks turn red, and for that defect's reason.
# words_plant PERL QUESTIONS SEEN TEXT: PERL, a perl -0pi script that
# writes the mark HARNESS-PLANT with its change, changes method.md in a copy
# of the repository; h_words runs there; each of QUESTIONS (space
# separated) must fail with SEEN in its H_WHY
words_plant() {
  local q
  sb=$(make_sandbox) || abort_sandbox
  perl -0pi -e "$1" "$sb/method/.claude/rules/method/method.md"
  if ! grep -q -F HARNESS-PLANT "$sb/method/.claude/rules/method/method.md"; then
    fail "$4: the plant did not apply, so the check result would mean nothing"
  elif ! h_words "$sb"; then
    fail "$4: the case could not be made, or the fake did not answer"
  else
    # shellcheck disable=SC2086 # the questions are words on purpose
    for q in $2; do
      if h_words_holds "$q"; then
        fail "$4: the words question '$q' stayed green"
      else
        case $H_WHY in
          *"$3"*) pass "$4: the words question '$q' turns red ($H_WHY)" ;;
          *) fail "$4: the words question '$q' turned red for another reason" "$H_WHY" ;;
        esac
      fi
    done
  fi
  h_stop
  drop_sandbox "$sb" || true
}
# shellcheck disable=SC2016 # perl code, expanded by perl
{
  words_plant 's/<!-- M079 -->\n(A cloud session[^\n]*)/$1 <!-- M079 HARNESS-PLANT -->/' \
    comments "the comment '<!-- M079 HARNESS-PLANT -->' reached main's requests" "words: an ID comment moved onto its sentence's line"
  # (a rules file with paths: loads only when Claude touches a matching
  # file, so it is missing from the first requests)
  words_plant 's/\A/---\npaths:\n  - "harness-plant\/**" # HARNESS-PLANT\n---\n/' \
    "reach gate" "method.md in" "words: method.md loaded only for some paths"
}

# 17. step 6.2's case for the method's own gate files (h_real_gates,
# h_real_holds): one copy of the repository with four defects, each
# turning one question red for its own gate's reason, in one client run:
# an unknown frontmatter key in the reviewer's file (loads), Agent in the
# security checker's tools (tools), effort high in the reporter's file
# (record), and receipt.pl reading the frontmatter as part of the body, so
# no real body compares equal (valid)
sb=$(make_sandbox) || abort_sandbox
a="$sb/method/.claude/agents/method"
# shellcheck disable=SC2016 # perl code, expanded by perl
{
  perl -0pi -e 's/^(effort: xhigh\n)/${1}bogus-key: 1\n/m' "$a/method-reviewer.md"
  perl -0pi -e 's/^(tools: [^\n]*)/$1, Agent/m' "$a/method-security-checker.md"
  perl -0pi -e 's/^effort: xhigh$/effort: high/m' "$a/method-reporter.md"
  perl -pi -e 's/\? \(\$1, \$2\) : \(\x27\x27, \$text\);/? (\$1, \$text) : (\x27\x27, \$text); # HARNESS-PLANT/' "$sb/method/scripts/method/lib/receipt.pl"
}
if ! grep -q '^bogus-key: 1$' "$a/method-reviewer.md" || ! grep -q '^tools: .*, Agent$' "$a/method-security-checker.md" ||
  ! grep -q '^effort: high$' "$a/method-reporter.md" || ! grep -q -F HARNESS-PLANT "$sb/method/scripts/method/lib/receipt.pl"; then
  fail "real gates: the plants did not apply, so the check results would mean nothing"
elif ! h_real_gates "$sb" default; then
  fail "real gates: the case could not be made, or the fake did not answer"
else
  for qr in "loads|the debug log names method-reviewer: |an unknown frontmatter key in the reviewer's file" \
    "tools|method-security-checker's first request offers Agent, a delegation tool|Agent in the security checker's tools" \
    "record|method-reporter's receipt holds models=$H_MODEL efforts=high |effort high in the reporter's file" \
    "valid|method-tester's receipt: INVALID why=instructions-differ|receipt.pl reading the frontmatter as part of a gate's body"; do
    q=${qr%%|*}
    rest=${qr#*|}
    seen=${rest%%|*}
    text=${rest#*|}
    if h_real_holds "$q"; then
      fail "real gates: $text: the question '$q' stayed green"
    else
      case $H_WHY in
        *"$seen"*) pass "real gates: $text: the question '$q' turns red (${H_WHY%%;*})" ;;
        *) fail "real gates: $text: the question '$q' turned red for another reason" "$H_WHY" ;;
      esac
    fi
  done
fi
h_stop
drop_sandbox "$sb" || true

# 17b. step 6b.1's N1 case (h_real_gates, question refused): with the
# guard taken off the fragment's PreToolUse hook for Bash, a gate's write
# to the project's settings and its push to main are not refused, and the
# question turns red
sb=$(make_sandbox) || abort_sandbox
# shellcheck disable=SC2016 # perl code, expanded by perl
perl -0pi -e 's/"matcher": "Bash\|PowerShell\|/"matcher": "PowerShell|/' "$sb/method/settings.fragment.json"
if ! grep -q '"matcher": "PowerShell|Monitor|' "$sb/method/settings.fragment.json"; then
  fail "real gates (N1): the plant did not apply, so the check result would mean nothing"
elif ! h_real_gates "$sb" default; then
  fail "real gates (N1): the case could not be made, or the fake did not answer"
elif h_real_holds refused; then
  fail "real gates (N1): the guard taken off the fragment's PreToolUse Bash hook: the question 'refused' stayed green"
else
  case $H_WHY in
    *"requests do not carry the guard's G6 refusal"*) pass "real gates (N1): the guard taken off the fragment's PreToolUse Bash hook: the question 'refused' turns red (${H_WHY%%;*})" ;;
    *) fail "real gates (N1): the guard taken off the fragment's PreToolUse Bash hook: the question 'refused' turned red for another reason" "$H_WHY" ;;
  esac
fi
h_stop
drop_sandbox "$sb" || true

# 17c. step 6b.3's Deep review case (h_real_gates MODE deep, question own):
# with receipt.pl naming a receipt by the session alone, not by the session
# and the agent, the three reviewer runs of one message share one run
# number series and each stop lands on the newest run's receipt, so the runs
# do not each leave a VALID receipt of their own
sb=$(make_sandbox) || abort_sandbox
# shellcheck disable=SC2016 # perl code, expanded by perl
perl -pi -e 's/return substr\(sha\(\x27receipt\x27, \$sid, \$aid\), 0, 16\)/return substr(sha(\x27receipt\x27, \$sid), 0, 16) # HARNESS-PLANT/' "$sb/method/scripts/method/lib/receipt.pl"
if ! grep -q -F HARNESS-PLANT "$sb/method/scripts/method/lib/receipt.pl"; then
  fail "real gates (deep): the plant did not apply, so the check result would mean nothing"
elif ! h_real_gates "$sb" deep; then
  fail "real gates (deep): the case could not be made, or the fake did not answer"
elif h_real_holds own; then
  fail "real gates (deep): receipts named by the session alone: the question 'own' stayed green"
else
  case $H_WHY in
    *"method-reviewer-1's receipt: "*) pass "real gates (deep): receipts named by the session alone: the question 'own' turns red (${H_WHY%%;*})" ;;
    *) fail "real gates (deep): receipts named by the session alone: the question 'own' turned red for another reason" "$H_WHY" ;;
  esac
fi
h_stop
drop_sandbox "$sb" || true

# 18. step 6.4's case for planning and design (h_design, h_design_holds).
# design_plant MODE QUESTION|SEEN|TEXT...: with the plants already made in
# the copy $sb, h_design runs there in MODE; each QUESTION must fail with
# SEEN in its H_WHY
design_plant() {
  local mode=$1 qr q rest seen text
  shift
  if ! h_design "$sb" "$mode"; then
    fail "design ($mode): the case could not be made, or the fake did not answer"
    return
  fi
  for qr in "$@"; do
    q=${qr%%|*}
    rest=${qr#*|}
    seen=${rest%%|*}
    text=${rest#*|}
    if h_design_holds "$q"; then
      fail "design: $text: the question '$q' stayed green"
    else
      case $H_WHY in
        *"$seen"*) pass "design: $text: the question '$q' turns red (${H_WHY%%;*})" ;;
        *) fail "design: $text: the question '$q' turned red for another reason" "$H_WHY" ;;
      esac
    fi
  done
}
# one copy with four defects in default mode, each turning one question red
# for its own reason, in one client run: an unknown frontmatter key in the
# architect's file (loads), Bash in its tools (tools), effort high (model),
# and the architect added to the fragment's gate matchers (receipt)
sb=$(make_sandbox) || abort_sandbox
a="$sb/method/.claude/agents/method/method-architect.md"
# shellcheck disable=SC2016 # perl code, expanded by perl
{
  perl -0pi -e 's/^(effort: xhigh\n)/${1}bogus-key: 1\n/m; s/^(tools: [^\n]*)/$1, Bash/m; s/^effort: xhigh$/effort: high/m' "$a"
  perl -pi -e 's/\|method-tester\)\$"/|method-tester|method-architect)\$"/g' "$sb/method/settings.fragment.json"
}
if ! grep -q '^bogus-key: 1$' "$a" || ! grep -q '^tools: .*, Bash$' "$a" || ! grep -q '^effort: high$' "$a" || [ "$(grep -c 'method-tester|method-architect)\$"' "$sb/method/settings.fragment.json")" != 2 ]; then
  fail "design: the plants did not apply, so the check results would mean nothing"
else
  design_plant default "loads|the debug log names method-architect: |an unknown frontmatter key in the architect's file" \
    "tools|the architect's first request offers Bash|Bash in the architect's tools" \
    "model|the architect's requests went out at effort high|effort high in the architect's file" \
    "receipt|gate-receipt ran 2 times during the architect's call, not 0|the architect in the fragment's gate matchers (gate-receipt runs at its start and stop)"
fi
h_stop
drop_sandbox "$sb" || true
# the design skill made one the owner cannot type (expands)
sb=$(make_sandbox) || abort_sandbox
# shellcheck disable=SC2016 # perl code, expanded by perl
perl -0pi -e 's/^(name: method-design\n)/${1}user-invocable: false\n/m' "$sb/method/.claude/skills/method-design/SKILL.md"
if ! grep -q '^user-invocable: false$' "$sb/method/.claude/skills/method-design/SKILL.md"; then
  fail "design: the plant did not apply, so the check result would mean nothing"
else
  design_plant auto "expands|/method-design's body and arguments in main's first request: no request|method-design made a skill only Claude can call"
fi
h_stop
drop_sandbox "$sb" || true
# (step 6.6, the review's F16) gate-receipt refusing every agent's
# handback, the architect's too (ends: it takes more turns, and its design
# never reaches the main session; measured at 2.1.319, the other questions
# stay green)
sb=$(make_sandbox) || abort_sandbox
# shellcheck disable=SC2016 # perl code, expanded by perl
perl -pi -e 's/^(\s*)(return 0 unless defined \$gate && !ref \$gate && exists \$w->\{gate\}\{\$gate\};)$/${1}return Hook::json({ hookSpecificOutput => { hookEventName => "PreToolUse", permissionDecision => "deny", permissionDecisionReason => "refused" } }) if (\$in->{tool_name} \/\/ "") eq "SubagentHandback"; # HARNESS-PLANT\n$1$2/' "$sb/method/scripts/method/lib/receipt.pl"
if ! grep -q -F HARNESS-PLANT "$sb/method/scripts/method/lib/receipt.pl"; then
  fail "design: the plant did not apply, so the check result would mean nothing"
else
  design_plant auto "ends|the handed-back design did not reach the main conversation|gate-receipt refuses every agent's handback, the architect's too"
fi
h_stop
drop_sandbox "$sb" || true

# 19. step 6.5's case for /method-start (h_start, h_start_holds).
# start_plant MODE QUESTION|SEEN|TEXT...: with the plants already made in
# the copy $sb, h_start runs there in MODE; each QUESTION must fail with
# SEEN in its H_WHY
start_plant() {
  local mode=$1 qr q rest seen text
  shift
  if ! h_start "$sb" "$mode"; then
    fail "start ($mode): the case could not be made, or the fake did not answer"
    return
  fi
  for qr in "$@"; do
    q=${qr%%|*}
    rest=${qr#*|}
    seen=${rest%%|*}
    text=${rest#*|}
    if h_start_holds "$q"; then
      fail "start: $text: the question '$q' stayed green"
    else
      case $H_WHY in
        *"$seen"*) pass "start: $text: the question '$q' turns red (${H_WHY%%;*})" ;;
        *) fail "start: $text: the question '$q' turned red for another reason" "$H_WHY" ;;
      esac
    fi
  done
}
# one copy with three defects in default mode, each turning one question
# red for its own reason, in one client run: a variable the client does not
# substitute added to method-start (effort), the guard taken off the
# fragment's PreToolUse hook on Bash (guard), and the start hook taken off its
# SessionStart (active)
sb=$(make_sandbox) || abort_sandbox
s="$sb/method/.claude/skills/method-start/SKILL.md"
# shellcheck disable=SC2016 # the variable is written into the skill as text
printf '\nPlanted: ${CLAUDE_EFFORTS}.\n' >>"$s"
perl -MJSON::PP -e 'my $f = shift; open my $h, "<", $f or die; my $d = JSON::PP->new->decode(do { local $/; <$h> }); close $h;
  delete $d->{hooks}{SessionStart};
  $d->{hooks}{PreToolUse} = [grep { ($_->{matcher} // "") !~ /(?:\A|\|)Bash(?:\||\z)/ } @{ $d->{hooks}{PreToolUse} }];
  open $h, ">", $f or die; print $h JSON::PP->new->canonical->pretty->encode($d); close $h or die' "$sb/method/settings.fragment.json"
# shellcheck disable=SC2016 # the planted variable as written, not expanded here
if ! grep -q -F 'Planted: ${CLAUDE_EFFORTS}.' "$s" || grep -q -F 'session-status.sh' "$sb/method/settings.fragment.json" ||
  ! perl -MJSON::PP -0ne 'my $d = JSON::PP->new->decode($_); my @p = @{ $d->{hooks}{PreToolUse} || [] }; exit(@p && !(grep { ($_->{matcher} // "") =~ /(?:\A|\|)Bash(?:\||\z)/ } @p) ? 0 : 1)' "$sb/method/settings.fragment.json"; then
  fail "start: the plants did not apply, so the check results would mean nothing"
else
  start_plant default "effort|the literal \${CLAUDE_EFFORTS} reached main's requests|a variable the client does not substitute in method-start" \
    "guard|the chained call was not refused by G6|the guard taken off the fragment's PreToolUse hook on Bash" \
    "active|no start hook's METHOD-ACTIVE line reached main's requests|the start hook taken off the fragment"
fi
h_stop
drop_sandbox "$sb" || true
# with no start hook: method-start's lines naming METHOD-ACTIVE removed
# (named), and, in a second copy, method-start made a skill only Claude can
# call (expands)
sb=$(make_sandbox) || abort_sandbox
s="$sb/method/.claude/skills/method-start/SKILL.md"
perl -ni -e 'print unless /METHOD-ACTIVE/' "$s"
if grep -q -F METHOD-ACTIVE "$s"; then
  fail "start: the plant did not apply, so the check result would mean nothing"
else
  start_plant nohook "named|method-start's SKILL.md has no line naming METHOD-ACTIVE|method-start's text naming the METHOD-ACTIVE line removed"
fi
h_stop
drop_sandbox "$sb" || true
sb=$(make_sandbox) || abort_sandbox
s="$sb/method/.claude/skills/method-start/SKILL.md"
# shellcheck disable=SC2016 # perl code, expanded by perl
perl -0pi -e 's/^(name: method-start\n)/${1}user-invocable: false\n/m' "$s"
if ! grep -q '^user-invocable: false$' "$s"; then
  fail "start: the plant did not apply, so the check result would mean nothing"
else
  start_plant nohook "expands|/method-start's body in main's first request: no request|method-start made a skill only Claude can call"
fi
h_stop
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
