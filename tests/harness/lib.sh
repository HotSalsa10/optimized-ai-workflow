# shellcheck shell=bash
# The harness's helpers (step 5.2, DECISIONS A49): the real Claude Code
# client, run against the local fake Claude (fake-api.pl), in a throwaway
# project, at no cost. Source this file after tests/lib.sh; do not run it.
#
# The caller sets:
#   HARNESS  this folder
#   H_CLIENT the client binary to run
#   H_WORK   a throwaway folder (tests/lib.sh's new_sandbox_dir)
#
# A case:
#   h_case NAME          makes the case's folders and a project (git, one
#                        commit, branch main). Every case folder name holds
#                        a space, an apostrophe and a non-ASCII letter, so
#                        each hook command is seen to quote its paths.
#   h_settings           writes standard input as the project's
#                        .claude/settings.json
#   h_fixtures           copies the fixture hooks and agents into the project
#   h_fake SCRIPT [CAP]  starts the fake (fake-api.pl, or H_FAKE_API for a
#                        plant) with a script (fake-api.pl's format)
#                        and a request cap (default 40); fails when it does
#                        not answer within 5 s, and the case must stop there
#   h_client SECS [VAR=VALUE...] -- ARGS...
#                        runs the client once in the project, "-p go" with
#                        stream-json output, bounded by SECS, with an
#                        environment built from a fixed list (no key but the
#                        dummy one, the fake as every proxy, HOME and TMPDIR
#                        inside the case, no retries) and SendMessage
#                        switched off (H_SEND_MESSAGE=1 keeps it, for a case
#                        that addresses a stand-in inside the case);
#                        with H_FEED (a steps file, feed.pl's format) the
#                        owner's messages come as stream-json from feed.pl,
#                        which waits between them for what the case needs,
#                        in place of "go";
#                        every run is given --strict-mcp-config, so a case
#                        that wants an MCP server passes --mcp-config.
#                        VAR=VALUE adds to it; a name that could replace
#                        one of the case's own settings (HOME, TMPDIR, a
#                        proxy, CLAUDE_CONFIG_DIR, ANTHROPIC_*, a program
#                        the client or its shell loads) or carry a key
#                        (KEY, TOKEN, SECRET, PASSWORD, CREDENTIAL anywhere
#                        in the name) is refused
#   h_stop               stops the fake
# A case may start more than one fake: h_fake stops the one before and
# empties the fake's logs, so every question below is about the fake that
# ran last.
# Questions about the case's results, each 0 (yes) or 1 (no), printing
# nothing: h_reached, h_no_connect, h_no_overcap, h_tmp_clean, h_tmp_used,
# h_keys_ok, h_req_has TEXT (any request, in the JSON as sent, escapes
# and all), h_req_in CONV TEXT (the requests of the fake's conversation
# CONV only, in the decoded text the client sent: system text and
# non-assistant messages), h_tsv_has TEXT (the fake's one-line summary of
# each request, which holds the last message's results only), h_ran FILE.
# h_safe NAME passes or fails the six safety questions (the first six) as
# one line. h_init FIELD prints a field of the client's init event.
# Step 5b.1's gate cases: h_gates ROOT MODE runs them (below);
# h_receipt LETTER and h_hook_runs LETTER TEXT read one gate run's receipt
# and the hook runs during its call; h_used LETTER (step 5b.2) the models,
# efforts and tokens its receipt took from the agent's record, and
# h_req_effort CONV the efforts the requests of one conversation carried.
# Step 6.1's case: h_method_words ROOT lays the method's agents, rules and
# skills out; h_words ROOT runs the case and h_words_holds QUESTION judges
# it (below).
# req-001 is h_fake's own alive probe.

# settings a caller's environment must not carry into every case
unset H_CWD H_PROMPT H_FEED H_TMPDIR H_TMP_ROOT H_FAKE_API H_SEND_MESSAGE H_FAKE_PID H_PORT H_RUNS H_TOTAL_SECS

h_case() {
  H_DIR="$H_WORK/it's a case ü/$1"
  # this run's folder as the client names it (each character that is not
  # a letter or a digit a dash): unique to the run, and in every name the
  # client makes from a case's path
  H_TOKEN=$(perl -e 'my $s = shift; utf8::decode($s); $s =~ s/[^A-Za-z0-9]/-/g; print $s' "$H_WORK")
  H_PROJ="$H_DIR/project"
  rm -rf "$H_DIR"
  mkdir -p "$H_DIR/home" "$H_DIR/tmp" "$H_DIR/fake" "$H_PROJ" || return 1
  (
    cd "$H_PROJ" || exit 1
    export HOME="$H_DIR/home" GIT_CONFIG_NOSYSTEM=1
    git init -q . &&
      git symbolic-ref HEAD refs/heads/main &&
      git config user.name Harness &&
      git config user.email harness@example.invalid &&
      git config commit.gpgsign false &&
      git commit -q --allow-empty -m init &&
      mkdir -p .claude &&
      printf '.harness/\n' >>.git/info/exclude
  ) || return 1
}

# (one JSON object, or the case fails: the client would skip a file it
# cannot read, and a "no hook ran" case would pass for the wrong reason)
h_settings() {
  cat >"$H_PROJ/.claude/settings.json" || return 1
  if ! perl -MJSON::PP -e 'local $/; my $d = eval { JSON::PP->new->decode(<STDIN>) }; exit(ref $d eq "HASH" ? 0 : 1)' <"$H_PROJ/.claude/settings.json"; then
    fail "h_settings: the case's settings are not one JSON object"
    return 1
  fi
}

# h_method ROOT: lays the method out in the project as sync will (scripts/
# method/, .claude/hooks/method/, the fragment as .claude/settings.json,
# the project records), from the repository at ROOT, and commits it all
h_method() {
  mkdir -p "$H_PROJ/scripts" "$H_PROJ/.claude/hooks" &&
    cp -R "$1/method/scripts/method" "$H_PROJ/scripts/method" &&
    cp -R "$1/method/.claude/hooks/method" "$H_PROJ/.claude/hooks/method" &&
    cp "$1/method/settings.fragment.json" "$H_PROJ/.claude/settings.json" || return 1
  for r in AGENTS.md SPEC.md TASKS.md DECISIONS.md ROADMAP.md RISKS.md CHANGELOG.md TESTS.md; do printf '# %s\n' "$r" >"$H_PROJ/$r"; done
  printf '@AGENTS.md\n' >"$H_PROJ/CLAUDE.md"
  (cd "$H_PROJ" && HOME="$H_DIR/home" GIT_CONFIG_NOSYSTEM=1 git add -A && HOME="$H_DIR/home" GIT_CONFIG_NOSYSTEM=1 git commit -q -m "the method")
}

# h_holds_start ROOT: step 5.9's case for the hook prefix and command perl,
# with the method from the repository at ROOT (a planted copy in
# tests/plants/harness.sh): BASH_ENV and exported functions named perl and
# command in the user's settings env at the session's start (each leaves a mark
# only when a method hook runs it), and a Write to the project's settings.
# H_HOLD says what went wrong, or is empty
h_holds_start() {
  local before
  H_HOLD=""
  if ! { h_case holds-start && h_method "$1"; }; then H_HOLD="the case could not be made;"; return 0; fi
  mkdir -p "$H_DIR/home/.claude"
  # shellcheck disable=SC2016 # $0 is for the BASH_ENV script, read when it runs
  printf 'case "$0" in *hooks/method/*) touch "%s/bashenv-ran.txt" ;; esac\n' "$H_PROJ" >"$H_DIR/bashenv.sh"
  perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({env => {BASH_ENV => $ARGV[0], "BASH_FUNC_perl%%" => "() {  touch \"$ARGV[1]/perlfunc-ran.txt\"; return 0\n}", "BASH_FUNC_command%%" => "() {  touch \"$ARGV[1]/commandfunc-ran.txt\"; return 0\n}"}})' "$H_DIR/bashenv.sh" "$H_PROJ" >"$H_DIR/home/.claude/settings.json"
  perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({convs => [{name => "main", match => "^go\$", turns => [{tool => "Write", input => {file_path => $ARGV[0], content => "{}\n"}}, {text => "MAIN-DONE"}]}]})' "$H_PROJ/.claude/settings.json" >"$H_DIR/holds.json"
  before=$(cksum <"$H_PROJ/.claude/settings.json")
  h_fake "$H_DIR/holds.json" || { H_HOLD="the fake did not answer;"; return 0; }
  h_client 60 -- --permission-mode acceptEdits --allowedTools Write
  h_stop
  h_tsv_has "guard G6: the project's settings" || H_HOLD="$H_HOLD the Write was not refused by the guard;"
  [ "$(cksum <"$H_PROJ/.claude/settings.json")" = "$before" ] || H_HOLD="$H_HOLD the settings changed;"
  [ ! -e "$H_PROJ/bashenv-ran.txt" ] || H_HOLD="$H_HOLD a method hook's bash ran BASH_ENV;"
  [ ! -e "$H_PROJ/perlfunc-ran.txt" ] || H_HOLD="$H_HOLD a method hook ran the function named perl;"
  [ ! -e "$H_PROJ/commandfunc-ran.txt" ] || H_HOLD="$H_HOLD a method hook ran the function named command;"
  return 0
}

# h_gates ROOT MODE: step 5b.1's gate cases (gate-receipt), with the
# method from the repository at ROOT (a planted copy in
# tests/plants/harness.sh) and its fragment as the project's settings. The
# harness's stand-in reviewer gate (agents/method/method-reviewer.md) is
# committed into the project before the tree is taken, so the END-VERDICT
# line the fake writes names the tree the gate starts on (H_TREE). Each
# gate is called by the main session in the foreground, one after another,
# and told apart by its Agent call's description ("harness gate A" ...).
# MODE default: first my-method-reviewer (a copy of the gate under a longer
# name holding the gate's: not a gate), then gate A (a report with both
# lines), gate B (cut off, then complete), gate C (never complete), and
# step 5b.2's three, each with a report with both lines: gate G (the
# reviewer, its Agent call asking for effort low, below its file's xhigh;
# measured at 2.1.316 and 2.1.319: the call's effort takes, while the
# settings' effortLevel and --effort do not reach a gate whose file sets
# one), gate H (method-security-checker: its file in the method's folder,
# and a second definition of its name with other instructions given with
# --agents, which the client takes over the project's files, measured at
# both versions) and gate I (method-tester: its file in the method's
# folder, and a second project file of its name outside it with other
# instructions; measured at both versions, the client runs the one its
# file listing (ripgrep's) gives last, which on ext4 follows the file
# system's name hashing, so either may run on another machine). MODE
# auto, with the test-only allow hook on Agent (2.1.319 refuses the call
# against the fake without it; at 2.1.316 it only skips the main
# conversation's check): gate D (a handback without its lines, then one
# with them), gate E (twice without), gate F (a complete report as text,
# never handed back). MODE background (step 5b's repair): the owner's
# messages come as stream-json (H_FEED): "go1", whose turn calls gate X
# in the background (its first turn a Bash sleep of 4 s, then a report with
# both lines), then, once the gate has started and the first turn has
# ended, "go2", while the gate still runs; the input closes a second after
# gates.log has its line, or at 60 s. The client's prompt_id is the
# session's id for the owner's current message (measured at 2.1.316 and
# 2.1.319), so the gate's stop comes under go2's. The client's debug log
# goes to $H_DIR/debug.log (not in MODE background). Returns 1 when the
# case could not be made or the fake did not answer (the client was then
# not started)
h_gates() {
  local mode=$2 agents g
  H_TREE=""
  { h_case "gates-$mode" && h_method "$1"; } || return 1
  mkdir -p "$H_PROJ/.claude/agents/method" && cp "$HARNESS/agents/method/method-reviewer.md" "$H_PROJ/.claude/agents/method/" || return 1
  if [ "$mode" = background ]; then
    :
  elif [ "$mode" = auto ]; then
    mkdir -p "$H_PROJ/.claude/hooks/fixture" && cp "$HARNESS/hooks/allow.sh" "$H_PROJ/.claude/hooks/fixture/" || return 1
    perl -MJSON::PP -e 'my $f = shift; open my $h, "<", $f or die; my $d = JSON::PP->new->decode(do { local $/; <$h> }); close $h;
      push @{ $d->{hooks}{PreToolUse} }, {matcher => "Agent|Task", hooks => [{type => "command", command => q{bash "$CLAUDE_PROJECT_DIR/.claude/hooks/fixture/allow.sh"}, timeout => 30}]};
      open $h, ">", $f or die; print $h JSON::PP->new->canonical->pretty->encode($d); close $h or die' "$H_PROJ/.claude/settings.json" || return 1
  else
    sed 's/^name: method-reviewer$/name: my-method-reviewer/' "$HARNESS/agents/method/method-reviewer.md" >"$H_PROJ/.claude/agents/my-method-reviewer.md" || return 1
    for g in method-security-checker method-tester; do
      sed "s/^name: method-reviewer\$/name: $g/" "$HARNESS/agents/method/method-reviewer.md" >"$H_PROJ/.claude/agents/method/$g.md" || return 1
    done
    # (the second definitions: the same model and effort as the method's
    # file, other instructions, which the gate's requests show)
    printf '%s\n' '---' 'name: method-tester' 'description: A second project file named method-tester (test-only). Use when asked for a harness gate review.' \
      'model: opus' 'effort: xhigh' '---' 'You are HARNESS-OTHER-DEFINITION, a second project file named method-tester (test-only).' >"$H_PROJ/.claude/agents/method-tester.md" || return 1
    agents='{"method-security-checker":{"description":"A second definition of method-security-checker, on the command line (test-only).","prompt":"You are HARNESS-OTHER-DEFINITION, a second definition of method-security-checker given on the command line (test-only).","model":"opus","effort":"xhigh"}}'
  fi
  (cd "$H_PROJ" && HOME="$H_DIR/home" GIT_CONFIG_NOSYSTEM=1 git add -A && HOME="$H_DIR/home" GIT_CONFIG_NOSYSTEM=1 git commit -q -m "the gates") || return 1
  H_TREE=$(HOME="$H_DIR/home" GIT_CONFIG_NOSYSTEM=1 git -C "$H_PROJ" rev-parse 'HEAD^{tree}') || return 1
  perl -MJSON::PP -e '
    my ($mode, $t) = @ARGV;
    my $good = "APPROVE\nSummary: the change is fine.\nEND-VERDICT $t";
    my $agent = sub { my ($g, $type, $effort, $bg) = @_; return {tool => "Agent", input => {description => "harness gate $g", prompt => "HARNESS-GATE-$g: review the change",
      subagent_type => $type // "method-reviewer", run_in_background => $bg ? JSON::PP::true : JSON::PP::false, defined $effort ? (effort => $effort) : ()}} };
    my $hand = sub { return {tool => "SubagentHandback", input => {message => $_[0]}} };
    my (@convs, @calls);
    my $go = "go";
    if ($mode eq "background") {
      push @convs, {name => "gateX", match => "HARNESS-GATE-X", turns => [{tool => "Bash", input => {command => "sleep 4", description => "wait"}}, {text => $good}]};
      @calls = ($agent->("X", undef, undef, 1));
      $go = "go1";
    } elsif ($mode eq "auto") {
      # (the check auto mode runs, matched by its first message: the
      # transcript, or the CLAUDE.md of the project once there is one)
      push @convs, {name => "classifier", match => "(?:^<transcript>|<user_claude_md>)", turns => [{text => "<block>no</block>"}]},
        {name => "gateD", match => "HARNESS-GATE-D", turns => [$hand->("my findings, no verdict yet"), $hand->($good)]},
        {name => "gateE", match => "HARNESS-GATE-E", turns => [$hand->("my findings, no verdict yet"), $hand->("still no verdict")]},
        # (the client nudges a gate that ends without a handback three times)
        {name => "gateF", match => "HARNESS-GATE-F", turns => [map { {text => $good} } 1 .. 4]};
      @calls = map { $agent->($_) } qw(D E F);
    } else {
      push @convs, {name => "mine", match => "HARNESS-GATE-mine", turns => [{text => $good}]},
        {name => "gateA", match => "HARNESS-GATE-A", turns => [{text => $good}]},
        {name => "gateB", match => "HARNESS-GATE-B", turns => [{text => "partial review, no verdict yet"}, {text => "REQUEST CHANGES: one finding\nEND-VERDICT $t"}]},
        {name => "gateC", match => "HARNESS-GATE-C", turns => [{text => "partial review"}, {text => "still partial"}]},
        {name => "gateG", match => "HARNESS-GATE-G", turns => [{text => $good}]},
        {name => "gateH", match => "HARNESS-GATE-H", turns => [{text => $good}]},
        {name => "gateI", match => "HARNESS-GATE-I", turns => [{text => "TESTS PASS\nSummary: the tests ran.\nEND-VERDICT $t"}]};
      @calls = ($agent->("mine", "my-method-reviewer"), (map { $agent->($_) } qw(A B C)), $agent->("G", undef, "low"),
        $agent->("H", "method-security-checker"), $agent->("I", "method-tester"));
    }
    push @convs, {name => "main", match => "^$go\$", turns => [@calls, map { {text => "MAIN-DONE-$_"} } 1 .. 4]};
    print JSON::PP->new->canonical->encode({convs => \@convs, fallback => {text => "FAKE-FALLBACK"}, usage => {input_tokens => 11, output_tokens => 7}})' "$mode" "$H_TREE" >"$H_DIR/gates.json" || return 1
  h_fake "$H_DIR/gates.json" || return 1
  if [ "$mode" = background ]; then
    printf 'say\tgo1\nfile\t%s\tmethod-running-\nholds\t%s\t"type":"result"\nsay\tgo2 while the gate runs\nholds\t%s\tmethod-reviewer\nsleep\t1\n' \
      "$H_PROJ/.git" "$H_DIR/out.jsonl" "$H_PROJ/.method/local/gates.log" >"$H_DIR/feed.txt" || return 1
    H_FEED="$H_DIR/feed.txt" h_client 60 -- --permission-mode default --allowedTools Bash
  elif [ "$mode" = auto ]; then
    h_client 90 -- --permission-mode auto --debug-file "$H_DIR/debug.log"
  else
    h_client 90 -- --permission-mode default --allowedTools Bash --agents "$agents" --debug-file "$H_DIR/debug.log"
  fi
  h_stop
}
# h_receipt LETTER: the receipt of gate LETTER's run (read.pl receipt), or
# "none"
h_receipt() {
  perl "$HARNESS/read.pl" receipt "harness gate $1" "$H_DIR/home" "$H_PROJ/.git"
}
# h_hook_runs LETTER TEXT: how many hook runs whose command holds TEXT the
# client's debug log shows during gate LETTER's Agent call, or "none"
h_hook_runs() {
  perl "$HARNESS/read.pl" hooks "harness gate $1" "$2" "$H_DIR/home" "$H_DIR/debug.log"
}
# h_used LETTER: the models, efforts and tokens gate LETTER's receipt took
# from the agent's record (read.pl used), or "none"
h_used() {
  perl "$HARNESS/read.pl" used "harness gate $1" "$H_DIR/home" "$H_PROJ/.git"
}
# h_req_effort CONV: the efforts the requests of the fake's conversation
# CONV carried, joined by commas, or "none"
h_req_effort() {
  perl "$HARNESS/read.pl" effort "$1" "$H_DIR/fake"
}
# h_turns CONV: how many requests the fake got for its conversation CONV
h_turns() {
  LC_ALL=C grep -c "	conv=$1 turn=" "$H_DIR/fake/requests.tsv" 2>/dev/null
}
# h_gate_holds QUESTION: 0 when QUESTION holds for the gate case h_gates
# ran last; else 1, with H_WHY saying what was seen. The questions:
#   context    the start's context line, with the tree, reached the requests
#              of gates A, B and C, and neither the main conversation's nor
#              my-method-reviewer's
#   no-hook    gate-receipt ran no time during my-method-reviewer's call,
#              which has no receipt, and twice during gate A's (its start
#              and its stop: so the debug log can tell)
#   valid      gate A (both lines): VALID with its opening word, one turn
#   log        .method/local/gates.log: one line a gate run (six), VALID
#              for A and B, INCOMPLETE lines-missing-after-retry for C,
#              each with the gate, the tree, the model read from the gate's
#              record (claude-opus-5-5, the fragment's only model) and the
#              effort the client gave (xhigh)
#   cut-off    gate B: one more turn, whose request carries gate-receipt's
#              reason; then VALID (two stops, sent back once)
#   never      gate C: one more turn only; INCOMPLETE
#              lines-missing-after-retry
#   effort     gate G: its requests went out at effort low (so the case can
#              tell), and its receipt is INVALID effort-low, its gates.log
#              line giving effort low
#   definition gate H: the command line's instructions reached its
#              requests (so the case can tell), and its receipt is INVALID
#              instructions-differ; gate I: its receipt follows the
#              definition the client used, INVALID instructions-differ for
#              the second project file, VALID for the method's (H_NOTE
#              says which ran)
#   record     the receipts' models, efforts and tokens are what the
#              client wrote in each gate's record from the fake's answers
#              (11 input and 7 output tokens a turn): gate A
#              claude-opus-5-5, xhigh, 11 and 7; gate B (two turns), 22
#              and 14; gate G, effort low
#   deny-once  gate D: its first handback refused, the refusal in its next
#              request; the second let through; VALID
#   twice      gate E: two handbacks, the second let through; INCOMPLETE
#              lines-missing-after-retry
#   text-only  gate F (no handback; the client nudges it three times):
#              INCOMPLETE no-report, never refused or sent back
#   background gate X (MODE background): the owner's second message
#              reached the fake before the gate's last request (so the
#              gate's stop came under it, and the case can tell); the gate
#              has one receipt, VALID, and no running file is left
h_gate_holds() {
  local got c n v i want
  H_WHY=""
  H_NOTE=""
  case $1 in
    context)
      for c in gateA gateB gateC; do
        h_req_in "$c" "METHOD-ACTIVE gate=method-reviewer tree=$H_TREE" || H_WHY="$H_WHY the context line is not in $c's requests;"
      done
      for c in main mine; do
        ! h_req_in "$c" 'METHOD-ACTIVE gate=' || H_WHY="$H_WHY a context line is in $c's requests;"
      done
      ;;
    no-hook)
      got=$(h_hook_runs mine gate-receipt.sh)
      [ "$got" = 0 ] || H_WHY="$H_WHY gate-receipt ran $got times during my-method-reviewer's call;"
      got=$(h_receipt mine)
      [ "$got" = none ] || H_WHY="$H_WHY my-method-reviewer has a receipt: $got;"
      got=$(h_hook_runs A gate-receipt.sh)
      [ "$got" = 2 ] || H_WHY="$H_WHY gate-receipt ran $got times during gate A's call, not 2 (the debug log cannot tell);"
      ;;
    valid)
      got=$(h_receipt A)
      [ "$got" = "VALID why=none open=APPROVE stops=1 blocked=0 denied=0" ] || H_WHY="$H_WHY gate A's receipt: $got;"
      n=$(h_turns gateA)
      [ "$n" = 1 ] || H_WHY="$H_WHY gate A's turns: $n;"
      ;;
    log)
      v=$(LC_ALL=C grep -c "	VALID	method-reviewer	$H_TREE	claude-opus-5-5	xhigh	none\$" "$H_PROJ/.method/local/gates.log" 2>/dev/null)
      i=$(LC_ALL=C grep -c "	INCOMPLETE	method-reviewer	$H_TREE	claude-opus-5-5	xhigh	lines-missing-after-retry\$" "$H_PROJ/.method/local/gates.log" 2>/dev/null)
      n=0
      [ ! -f "$H_PROJ/.method/local/gates.log" ] || n=$(wc -l <"$H_PROJ/.method/local/gates.log" | tr -d ' ')
      [ "${v:-0}/${i:-0}/${n:-0}" = 2/1/6 ] || H_WHY="$H_WHY gates.log: ${v:-0} VALID, ${i:-0} INCOMPLETE, ${n:-0} lines;"
      ;;
    cut-off)
      n=$(h_turns gateB)
      [ "$n" = 2 ] || H_WHY="$H_WHY gate B's turns: $n;"
      h_req_in gateB "gate-receipt: your report must open with one of these words on its first line" || H_WHY="$H_WHY gate-receipt's reason is not in gate B's requests;"
      got=$(h_receipt B)
      [ "$got" = "VALID why=none open=REQUEST CHANGES stops=2 blocked=1 denied=0" ] || H_WHY="$H_WHY gate B's receipt: $got;"
      ;;
    never)
      n=$(h_turns gateC)
      [ "$n" = 2 ] || H_WHY="$H_WHY gate C's turns: $n;"
      got=$(h_receipt C)
      [ "$got" = "INCOMPLETE why=lines-missing-after-retry open=none stops=2 blocked=1 denied=0" ] || H_WHY="$H_WHY gate C's receipt: $got;"
      ;;
    effort)
      got=$(h_req_effort gateG)
      [ "$got" = low ] || H_WHY="$H_WHY gate G's requests went out at effort $got, not low (the Agent call's effort did not take, so the case cannot tell);"
      got=$(h_receipt G)
      [ "$got" = "INVALID why=effort-low open=APPROVE stops=1 blocked=0 denied=0" ] || H_WHY="$H_WHY gate G's receipt: $got;"
      n=$(LC_ALL=C grep -c "	INVALID	method-reviewer	$H_TREE	claude-opus-5-5	low	effort-low\$" "$H_PROJ/.method/local/gates.log" 2>/dev/null)
      [ "${n:-0}" = 1 ] || H_WHY="$H_WHY gates.log: ${n:-0} INVALID effort-low lines at effort low, not 1;"
      ;;
    definition)
      h_req_in gateH HARNESS-OTHER-DEFINITION || H_WHY="$H_WHY the command line's definition did not reach gate H's requests (the client used another, so the case cannot tell);"
      got=$(h_receipt H)
      [ "$got" = "INVALID why=instructions-differ open=APPROVE stops=1 blocked=0 denied=0" ] || H_WHY="$H_WHY gate H's receipt: $got;"
      if h_req_in gateI HARNESS-OTHER-DEFINITION; then
        H_NOTE="the client ran gate I from the second project file"
        want="INVALID why=instructions-differ open=TESTS PASS stops=1 blocked=0 denied=0"
      else
        H_NOTE="the client ran gate I from the method's file"
        want="VALID why=none open=TESTS PASS stops=1 blocked=0 denied=0"
      fi
      got=$(h_receipt I)
      [ "$got" = "$want" ] || H_WHY="$H_WHY gate I's receipt: $got ($H_NOTE);"
      ;;
    record)
      got=$(h_used A)
      [ "$got" = "models=claude-opus-5-5 efforts=xhigh input=11 output=7 cache_creation=0 cache_read=0" ] || H_WHY="$H_WHY gate A's receipt holds $got;"
      got=$(h_used B)
      [ "$got" = "models=claude-opus-5-5 efforts=xhigh input=22 output=14 cache_creation=0 cache_read=0" ] || H_WHY="$H_WHY gate B's receipt holds $got;"
      got=$(h_used G)
      case $got in "models=claude-opus-5-5 efforts=low input=11 output=7 "*) ;; *) H_WHY="$H_WHY gate G's receipt holds $got;" ;; esac
      ;;
    deny-once)
      n=$(h_turns gateD)
      [ "$n" = 2 ] || H_WHY="$H_WHY gate D's turns: $n;"
      h_req_in gateD "PreToolUse:SubagentHandback hook error: gate-receipt: your report must open with one of these words" || H_WHY="$H_WHY the refusal is not in gate D's requests;"
      got=$(h_receipt D)
      [ "$got" = "VALID why=none open=APPROVE stops=1 blocked=0 denied=1" ] || H_WHY="$H_WHY gate D's receipt: $got;"
      ;;
    twice)
      n=$(h_turns gateE)
      [ "$n" = 2 ] || H_WHY="$H_WHY gate E's turns: $n;"
      got=$(h_receipt E)
      [ "$got" = "INCOMPLETE why=lines-missing-after-retry open=none stops=1 blocked=0 denied=1" ] || H_WHY="$H_WHY gate E's receipt: $got;"
      ;;
    text-only)
      got=$(h_receipt F)
      case $got in "INCOMPLETE why=no-report open=none stops="*" blocked=0 denied=0") ;; *) H_WHY="$H_WHY gate F's receipt: $got;" ;; esac
      ! h_req_in gateF 'gate-receipt: ' || H_WHY="$H_WHY gate-receipt's reason reached gate F;"
      ;;
    background)
      v=$(perl "$HARNESS/read.pl" first main "go2 while the gate runs" "$H_DIR/fake")
      i=$(perl "$HARNESS/read.pl" first gateX tool_result "$H_DIR/fake")
      case "$v:$i" in
        *none*) H_WHY="$H_WHY the owner's second message (request $v) or the gate's last request ($i) did not reach the fake;" ;;
        *) [ "$v" -lt "$i" ] || H_WHY="$H_WHY the owner's second message (request $v) came after the gate's last request ($i), so the case cannot tell;" ;;
      esac
      got=$(h_receipt X)
      [ "$got" = "VALID why=none open=APPROVE stops=1 blocked=0 denied=0" ] || H_WHY="$H_WHY gate X's receipt: $got;"
      n=$(find "$H_PROJ/.git" -maxdepth 1 -name 'method-running-*' | wc -l | tr -d ' ')
      [ "$n" = 0 ] || H_WHY="$H_WHY $n running files left in git's folder;"
      ;;
    *) H_WHY="no such gate question: $1" ;;
  esac
  [ -z "$H_WHY" ]
}

# h_method_words ROOT (step 6.1): lays the method's own words out in the
# project as sync will, from the repository at ROOT: method/.claude/agents/
# method/, rules/method/ and every skills/method-*/ that exists, into the
# project's .claude/; then commits. h_method is not changed, so the hook
# cases keep the harness's stand-in gate.
h_method_words() {
  local d
  for d in agents/method rules/method; do
    if [ -d "$1/method/.claude/$d" ]; then
      mkdir -p "$H_PROJ/.claude/$d" && cp -R "$1/method/.claude/$d/." "$H_PROJ/.claude/$d/" || return 1
    fi
  done
  for d in "$1"/method/.claude/skills/method-*; do
    [ -d "$d" ] || continue
    mkdir -p "$H_PROJ/.claude/skills/${d##*/}" && cp -R "$d/." "$H_PROJ/.claude/skills/${d##*/}/" || return 1
  done
  (cd "$H_PROJ" && HOME="$H_DIR/home" GIT_CONFIG_NOSYSTEM=1 git add -A && HOME="$H_DIR/home" GIT_CONFIG_NOSYSTEM=1 git commit -q --allow-empty -m "the method's words")
}

# h_words ROOT (step 6.1): the case for the method's rules files, with the
# method (h_method) and its words (h_method_words) from the repository at
# ROOT (a planted copy in tests/plants/harness.sh), and the harness's
# stand-in reviewer while the method has no reviewer file of its own (step
# 6.2 brings it). The main session calls the reviewer once, in the
# foreground (conversation "gate"), then ends. Returns 1 when the case
# could not be made or the fake did not answer.
h_words() {
  local t
  { h_case words && h_method "$1" && h_method_words "$1"; } || return 1
  if [ ! -f "$H_PROJ/.claude/agents/method/method-reviewer.md" ]; then
    mkdir -p "$H_PROJ/.claude/agents/method" && cp "$HARNESS/agents/method/method-reviewer.md" "$H_PROJ/.claude/agents/method/" &&
      (cd "$H_PROJ" && HOME="$H_DIR/home" GIT_CONFIG_NOSYSTEM=1 git add -A && HOME="$H_DIR/home" GIT_CONFIG_NOSYSTEM=1 git commit -q -m "the stand-in gate") || return 1
  fi
  t=$(HOME="$H_DIR/home" GIT_CONFIG_NOSYSTEM=1 git -C "$H_PROJ" rev-parse 'HEAD^{tree}') || return 1
  perl -MJSON::PP -e 'my $t = shift; print JSON::PP->new->canonical->encode({convs => [
      {name => "gate", match => "HARNESS-GATE-W", turns => [{text => "APPROVE\nSummary: the change is fine.\nEND-VERDICT $t"}]},
      {name => "main", match => "^go\$", turns => [{tool => "Agent", input => {description => "harness gate W", prompt => "HARNESS-GATE-W: review the change",
        subagent_type => "method-reviewer", run_in_background => JSON::PP::false}}, map { {text => "MAIN-DONE-$_"} } 1 .. 3]}],
    fallback => {text => "FAKE-FALLBACK"}})' "$t" >"$H_DIR/words.json" || return 1
  h_fake "$H_DIR/words.json" || return 1
  h_client 90 -- --permission-mode default --allowedTools Bash
  h_stop
}
# h_words_holds QUESTION: 0 when QUESTION holds for the case h_words ran
# last; else 1, with H_WHY saying what was seen. The rules files are the
# project's .claude/rules/**/*.md (at least one, or the case cannot tell).
#   reach    each reaches the main conversation's first request exactly as
#            tests/budget.test.sh counts it: its lines holding only a comment
#            dropped, every other byte kept (read.pl rules)
#   gate     the same, in the gate's first request
#   comments no HTML comment from a rules file, alone on its line or not,
#            reaches any request of the main conversation or the gate (and
#            the files hold at least one, or the case cannot tell)
h_words_holds() {
  local f rel c n got line
  H_WHY=""
  find "$H_PROJ/.claude/rules" -type f -name '*.md' 2>/dev/null | sort >"$H_DIR/words-files.txt"
  if [ ! -s "$H_DIR/words-files.txt" ]; then
    H_WHY="no rules file in the project, so the case cannot tell"
    return 1
  fi
  case $1 in
    reach | gate)
      c=main
      [ "$1" = gate ] && c=gate
      while IFS= read -r f; do
        rel=${f#"$H_PROJ/"}
        got=$(perl "$HARNESS/read.pl" rules "$c" "$rel" "$f" "$H_DIR/fake")
        [ "$got" = same ] || H_WHY="$H_WHY $rel in $c's first request: $got;"
      done <"$H_DIR/words-files.txt"
      ;;
    comments)
      # shellcheck disable=SC2016 # perl code, expanded by perl
      while IFS= read -r f; do perl -ne 'print "$1\n" while /(<!--(?:(?!-->).)*-->)/g' "$f"; done <"$H_DIR/words-files.txt" >"$H_DIR/words-comments.txt"
      n=0
      while IFS= read -r line; do
        n=$((n + 1))
        for c in main gate; do
          ! perl "$HARNESS/read.pl" req "$c" "$line" "$H_DIR/fake" || H_WHY="$H_WHY the comment '$line' reached $c's requests;"
        done
      done <"$H_DIR/words-comments.txt"
      [ "$n" -gt 0 ] || H_WHY="$H_WHY the rules files hold no comment, so the case cannot tell;"
      ;;
    *) H_WHY="no such words question: $1" ;;
  esac
  [ -z "$H_WHY" ]
}

h_fixtures() {
  mkdir -p "$H_PROJ/.claude/hooks/fixture" "$H_PROJ/.claude/agents" &&
    cp "$HARNESS"/hooks/*.sh "$H_PROJ/.claude/hooks/fixture/" &&
    cp "$HARNESS"/agents/*.md "$H_PROJ/.claude/agents/"
}

h_fake() {
  h_stop
  rm -rf "$H_DIR/fake" && mkdir -p "$H_DIR/fake" || return 1
  perl "${H_FAKE_API:-$HARNESS/fake-api.pl}" --script "$1" --log-dir "$H_DIR/fake" --port-file "$H_DIR/fake/port" \
    --max-requests "${2:-40}" --max-seconds 300 >"$H_DIR/fake/stdout" 2>&1 &
  H_FAKE_PID=$!
  perl -MTime::HiRes=sleep,time -e 'my $u = time + 5; until (-s $ARGV[0]) { exit 1 if time > $u; sleep 0.05 }' "$H_DIR/fake/port" || {
    h_stop
    return 1
  }
  H_PORT=$(cat "$H_DIR/fake/port")
  # the fake must answer before the client starts; the whole exchange is
  # under an alarm, so a listener that never answers cannot hang the case
  perl -MIO::Socket::INET -e '
    $SIG{ALRM} = sub { exit 1 }; alarm 5;
    my $s = IO::Socket::INET->new(PeerAddr => "127.0.0.1", PeerPort => $ARGV[0], Timeout => 3) or exit 1;
    print $s "GET /harness-alive HTTP/1.1\r\nHost: x\r\n\r\n";
    my $l = <$s>; exit(defined $l && $l =~ m{\AHTTP/1\.1 200 } ? 0 : 1)' "$H_PORT" || {
    h_stop
    return 1
  }
}

h_client() {
  local secs start end
  secs=$1
  shift
  h_env=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    case "$1" in
      [A-Za-z_]*=*) ;;
      *)
        echo "harness: h_client takes VAR=VALUE before --, not $1" >&2
        H_RC=2
        return 2
        ;;
    esac
    # (judged by the name: a name that would replace one of the case's own
    # settings, or that can carry a key, is refused; PATH may be given)
    case "${1%%=*}=" in
      *OAUTH*= | *AUTH_TOKEN*= | *BEDROCK*= | *VERTEX*= | ANTHROPIC_*= | CLAUDE_CODE_USE_*= | HOME= | TMPDIR= | *_PROXY= | *_proxy= | CLAUDE_CONFIG_DIR= | CLAUDE_CODE_MAX_RETRIES= | \
        DISABLE_AUTOUPDATER= | CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC= | GIT_CONFIG*= | LD_*= | DYLD_*= | NODE_OPTIONS= | BUN_OPTIONS= | XDG_*= | \
        CLAUDE_CODE_TMPDIR= | CLAUDE_ENV_FILE= | CLAUDE_CODE_SHELL_PREFIX= | BASH_ENV= | ENV= | *TOKEN*= | *SECRET*= | *KEY*= | *PASSWORD*= | *CREDENTIAL*= | *CREDS*= | *_PAT=)
        echo "harness: refusing to pass $1 to the client: only the dummy key, the case's own folders and the fake may reach it" >&2
        rm -f "$H_DIR/out.jsonl" "$H_DIR/err.txt"
        H_RC=2
        return 2
        ;;
    esac
    h_env+=("$1")
    shift
  done
  [ "${1:-}" = "--" ] && shift
  h_no_send=(--disallowedTools SendMessage)
  [ "${H_SEND_MESSAGE:-0}" = 1 ] && h_no_send=()
  # (the owner's messages: "go" on the command line, or, with H_FEED,
  # stream-json from feed.pl on standard input)
  if [ -n "${H_FEED:-}" ]; then
    h_prompt=(-p --input-format stream-json)
    exec 9< <(perl "$HARNESS/feed.pl" "$H_FEED" "$secs")
  else
    h_prompt=(-p "${H_PROMPT:-go}")
    exec 9</dev/null
  fi
  # (so h_tmp_used asks about this run, not an earlier one in the case)
  [ -n "${H_TMPDIR:-}" ] || rm -rf "$H_DIR/tmp/claude-$(id -u)"
  start=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  # (H_TMPDIR is for the plant that shows the /tmp check going red)
  perl "$HARNESS/bound.pl" "$secs" env -i \
    HOME="$H_DIR/home" PATH=/usr/bin:/bin TMPDIR="${H_TMPDIR:-$H_DIR/tmp}" \
    ANTHROPIC_BASE_URL="http://127.0.0.1:$H_PORT" ANTHROPIC_API_KEY=dummy \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_AUTOUPDATER=1 CLAUDE_CODE_MAX_RETRIES=0 \
    HTTPS_PROXY="http://127.0.0.1:$H_PORT" HTTP_PROXY="http://127.0.0.1:$H_PORT" ALL_PROXY="http://127.0.0.1:$H_PORT" NO_PROXY=127.0.0.1 \
    https_proxy="http://127.0.0.1:$H_PORT" http_proxy="http://127.0.0.1:$H_PORT" all_proxy="http://127.0.0.1:$H_PORT" no_proxy=127.0.0.1 \
    GIT_CONFIG_NOSYSTEM=1 ${h_env[@]+"${h_env[@]}"} \
    /bin/sh -c 'cd "$1" && shift && exec "$@"' sh "${H_CWD:-$H_PROJ}" \
    "$H_CLIENT" "${h_prompt[@]}" --output-format stream-json --verbose --strict-mcp-config ${h_no_send[@]+"${h_no_send[@]}"} "$@" \
    <&9 >"$H_DIR/out.jsonl" 2>"$H_DIR/err.txt"
  H_RC=$?
  exec 9<&-
  end=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  H_SECS=$(perl -e 'printf "%.1f", $ARGV[1] - $ARGV[0]' "$start" "$end")
  H_TOTAL_SECS=$(perl -e 'printf "%.1f", $ARGV[0] + $ARGV[1]' "${H_TOTAL_SECS:-0}" "$H_SECS")
  H_RUNS=$((${H_RUNS:-0} + 1))
}

h_stop() {
  if [ -n "${H_FAKE_PID:-}" ]; then
    kill "$H_FAKE_PID" 2>/dev/null
    wait "$H_FAKE_PID" 2>/dev/null
    H_FAKE_PID=""
  fi
  return 0
}

# --- questions ---

# a scripted answer to a messages request (not a token count, not over the cap)
h_reached() {
  perl -e 'open my $f, "<", $ARGV[0] or exit 1; while (<$f>) { chomp; my @c = split /\t/; exit 0 if @c > 6 && $c[2] eq "POST" && $c[3] =~ m{\A/v1/messages(?:\?|\z)} && $c[6] !~ /\A(?:over-cap|other|unknown-path)\z/ } exit 1' "$H_DIR/fake/requests.tsv"
}
# no CONNECT, and no request for another host through the proxy (its path
# is then a whole URL)
h_no_connect() {
  ! perl -e 'open my $f, "<", $ARGV[0] or exit 1; while (<$f>) { my @c = split /\t/; exit 0 if /CONNECT-REFUSED/ || (@c > 3 && $c[3] =~ m{\A[A-Za-z][A-Za-z0-9+.-]*://}) } exit 1' "$H_DIR/fake/requests.tsv"
}
h_no_overcap() {
  ! LC_ALL=C grep -q "	over-cap	" "$H_DIR/fake/requests.tsv" 2>/dev/null
}
# the client's own temporary folder for this user, outside the case
# (H_TMP_ROOT: another folder, for the plant that shows this check red)
h_tmp_list() {
  perl -e 'opendir my $d, $ARGV[0] or exit 0; print "$_\n" for sort readdir $d' "${H_TMP_ROOT:-/tmp/claude-$(id -u)}"
}
# nothing in it that names this run's cases
h_tmp_clean() {
  ! h_tmp_list | LC_ALL=C grep -F -q -- "$H_TOKEN"
}
# the client used the case's own temporary folder (it makes claude-<uid>
# there on every run seen), which a client that ignored TMPDIR would not
h_tmp_used() {
  [ -d "${H_TMPDIR:-$H_DIR/tmp}/claude-$(id -u)" ]
}
# every request carried the dummy key or none: no other key or token
h_keys_ok() {
  ! LC_ALL=C grep -q '	[^	]*other-[^	]*$' "$H_DIR/fake/requests.tsv" 2>/dev/null
}
h_req_has() {
  LC_ALL=C grep -F -q -- "$1" "$H_DIR"/fake/req-*.json 2>/dev/null
}
h_req_in() {
  perl "$HARNESS/read.pl" req "$1" "$2" "$H_DIR/fake"
}
h_tsv_has() {
  LC_ALL=C grep -F -q -- "$1" "$H_DIR/fake/requests.tsv" 2>/dev/null
}
h_ran() {
  [ -e "$H_PROJ/$1" ]
}
h_init() {
  perl "$HARNESS/read.pl" init "$1" "$H_DIR/out.jsonl"
}

h_safe() {
  local why
  why=""
  h_reached || why="$why no request reached the fake;"
  h_no_connect || why="$why an outside connection was tried;"
  h_no_overcap || why="$why the request cap was reached;"
  h_tmp_clean || why="$why the client left files in /tmp/claude-$(id -u);"
  h_tmp_used || why="$why the client did not use the case's TMPDIR;"
  h_keys_ok || why="$why a request carried a key or token other than the dummy one;"
  if [ -z "$why" ]; then
    pass "$1: reached the fake, no outside connection, under the cap, no files outside the case, the case's TMPDIR used, no key but the dummy one"
  else
    fail "$1: unsafe or empty run:$why" "client exit ${H_RC:-?}; $(tail -5 "$H_DIR/err.txt" 2>/dev/null)"
  fi
}
