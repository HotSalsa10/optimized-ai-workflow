#!/usr/bin/env bash
# Tests for the session-status hook (step 5.4): .claude/hooks/method/
# session-status.sh and lib/session.pl, run directly with a hook's JSON
# input in throwaway projects laid out as sync will lay them out. The
# harness shows the real client running it.
# shellcheck disable=SC2016 # single-quoted perl code is expanded by perl
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: session-status"
root=$(repo_root)
work=$(new_sandbox_dir) || abort_sandbox
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"

# project NAME: a project with the method laid out as sync will (scripts/
# method/, .claude/hooks/method/, the fragment as .claude/settings.json),
# one commit, a bare remote holding it; prints its path
project() {
  p="$work/$1"
  rm -rf "$p" "$work/$1.git"
  mkdir -p "$p/scripts" "$p/.claude/hooks"
  cp -R "$root/method/scripts/method" "$p/scripts/method"
  cp -R "$root/method/.claude/hooks/method" "$p/.claude/hooks/method"
  cp "$root/method/settings.fragment.json" "$p/.claude/settings.json"
  for r in CLAUDE.md AGENTS.md SPEC.md TASKS.md DECISIONS.md ROADMAP.md RISKS.md CHANGELOG.md TESTS.md; do printf '# %s\n' "$r" >"$p/$r"; done
  printf '@AGENTS.md\n' >"$p/CLAUDE.md"
  (
    cd "$p" || exit 1
    git init -q . && git symbolic-ref HEAD refs/heads/main &&
      git config user.name T && git config user.email t@example.invalid && git config commit.gpgsign false &&
      git add -A && git commit -q -m init &&
      git init -q --bare "$work/$1.git" && git remote add origin "$work/$1.git" && git push -q origin main 2>/dev/null
  ) || return 1
  printf '%s\n' "$p"
}

# hook DIR [JSON] [VAR=VALUE...]: runs the hook in DIR as Claude Code would
# (CLAUDE_PROJECT_DIR set, no CLAUDE_CODE_EXECPATH), with the input JSON
# (default: a startup at DIR), the advisor variable set unless a VAR says
# otherwise; sets out and code. HOOK_MEM_KB, when set, caps the hook's
# memory where ulimit -v works (a planted break that reads /dev/zero would
# otherwise fill the machine's memory before the hook's deadline)
hook() {
  d=$1
  in=${2:-}
  shift
  [ $# -gt 0 ] && shift
  [ -n "$in" ] || in=$(printf '{"hook_event_name":"SessionStart","source":"startup","cwd":"%s"}' "$d")
  out=$(cd "$d" && { [ -z "${HOOK_MEM_KB:-}" ] || ulimit -v "$HOOK_MEM_KB" 2>/dev/null || true; } && printf '%s' "$in" | env -u CLAUDE_CODE_EXECPATH -u CLAUDE_CODE_EFFORT_LEVEL CLAUDE_PROJECT_DIR="$d" CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1 "$@" bash "$d/.claude/hooks/method/session-status.sh" 2>&1)
  code=$?
}

# has NAME TEXT...: the output holds each TEXT
has() {
  name=$1
  shift
  missing=""
  for t in "$@"; do printf '%s\n' "$out" | grep -F -q -- "$t" || missing="$missing [$t]"; done
  if [ -z "$missing" ] && [ "$code" -eq 0 ]; then pass "$name"; else fail "$name: exit $code, missing:$missing" "$out"; fi
}
# lacks NAME TEXT: the output does not hold TEXT
lacks() {
  if ! printf '%s\n' "$out" | grep -F -q -- "$2"; then pass "$1"; else fail "$1" "$out"; fi
}

p=$(project clean) || abort_sandbox
hook "$p"
first=$(printf '%s\n' "$out" | sed -n 1p)
if [ "$first" = "METHOD-ACTIVE vunreleased" ] && [ "$code" -eq 0 ]; then pass "the first line is METHOD-ACTIVE vunreleased, and it exits 0"; else fail "the first line is METHOD-ACTIVE vunreleased, and it exits 0" "exit $code: $out"; fi
has "a clean project gets status's summary, with the client's version and CI left to /start" "status: nothing needs a look" "claude-code" "ci)"

# the version from the lock's first line (step 7.2): read before perl
# starts; vunknown when that line is not a version line; vunreleased with
# no lock (above)
lp=$(project locked) || abort_sandbox
printf 'version\tv0.7.0\nsource\t%s\nprofile\tbest\nsettings\t%s\n' "$(printf '%040d' 0)" "$(printf '%064d' 0)" >"$lp/scripts/method/method.lock"
hook "$lp"
first=$(printf '%s\n' "$out" | sed -n 1p)
if [ "$first" = "METHOD-ACTIVE v0.7.0" ] && [ "$code" -eq 0 ]; then pass "the first line names the lock's version (METHOD-ACTIVE v0.7.0)"; else fail "the first line names the lock's version (METHOD-ACTIVE v0.7.0)" "exit $code: $out"; fi
hook "$lp" "" METHOD_NESTED=1
if [ "$out" = "METHOD-ACTIVE v0.7.0 (nested: status skipped)" ]; then pass "the first line names the lock's version in a nested run too"; else fail "the first line names the lock's version in a nested run too" "$out"; fi
for bad in 'version\tv0.7.0 ; rm -rf ~' 'version\tv0.7.0\r' 'version\tlatest' 'Version\tv0.7.0' 'version\tv0.7.0.0.0.0.0.0.0.0.0.0.0' ''; do
  # shellcheck disable=SC2059 # the line's \t and \r are printf's to read
  printf "$bad\n" >"$lp/scripts/method/method.lock"
  hook "$lp"
  first=$(printf '%s\n' "$out" | sed -n 1p)
  if [ "$first" = "METHOD-ACTIVE vunknown" ]; then pass "a lock whose first line is not a version line gives vunknown: $bad"; else fail "a lock whose first line is not a version line gives vunknown: $bad" "$first"; fi
done
rm -f "$lp/scripts/method/method.lock"
mkdir "$lp/scripts/method/method.lock"
hook "$lp"
first=$(printf '%s\n' "$out" | sed -n 1p)
if [ "$first" = "METHOD-ACTIVE vunreleased" ] && [ "$code" -eq 0 ]; then pass "a lock that is a folder is not read (vunreleased)"; else fail "a lock that is a folder is not read (vunreleased)" "exit $code: $out"; fi
lacks "status's PASS lines stay out of the context" "records: PASS"

# the gates' receipts for the files at HEAD (step 5b.2): one LOOK line with
# how many do not say VALID, and how many say each other word; receipts
# for another tree, and VALID ones, are not counted
ptree=$(git -C "$p" rev-parse 'HEAD^{tree}')
n=0
for r in "$ptree INVALID" "$ptree INCOMPLETE" "$ptree INCOMPLETE" "$ptree VALID" "0123456789abcdef0123456789abcdef01234567 INVALID"; do
  n=$((n + 1))
  printf '{"gate":"method-reviewer","state":"%s","tree":"%s","v":1,"why":["x"]}' "${r#* }" "${r% *}" >"$p/.git/method-receipt-$(printf '%024d' "$n").json"
done
hook "$p"
has "gate receipts for the files at HEAD that do not say VALID are named in one LOOK line, by word" "session-status: LOOK - 3 gate receipts for the files at HEAD do not say VALID: 1 INVALID, 2 INCOMPLETE (.method/local/gates.log says why)"
rm -f "$p"/.git/method-receipt-*.json
hook "$p"
lacks "with no such receipts there is no receipts line" "gate receipt"

printf 'x\n' >"$p/new.txt"
hook "$p"
has "a dirty project still gets METHOD-ACTIVE, the work LOOK line and status's summary, and exits 0 (status exited 1)" "METHOD-ACTIVE vunreleased" "work: LOOK - " "status: 1 areas need a look (work)"
rm -f "$p/new.txt"

hook "$p" "" CLAUDE_CODE_DISABLE_ADVISOR_TOOL=0
has "the advisor not switched off is a LOOK" "session-status: LOOK - the advisor is not switched off"
hook "$p" "" CLAUDE_CODE_DISABLE_AUTO_MEMORY=0
has "auto memory switched on by its variable is a LOOK" "auto memory is switched on by CLAUDE_CODE_DISABLE_AUTO_MEMORY=0"
hook "$p" "$(printf '{"source":"startup","cwd":"%s","model":"claude-sonnet-5-5"}' "$p")"
has "a session on another model is a LOOK" "this session runs claude-sonnet-5-5, not claude-opus-5-5"
hook "$p" "$(printf '{"source":"startup","cwd":"%s","model":"claude-opus-5-5"}' "$p")"
lacks "a session on claude-opus-5-5 is not" "this session runs"
hook "$p" "" CLAUDE_CODE_EFFORT_LEVEL=low
has "CLAUDE_CODE_EFFORT_LEVEL set is status's effort LOOK, also inside a hook" "effort: LOOK - CLAUDE_CODE_EFFORT_LEVEL is set"

key="sk-ant""-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef0123456789"
cat >"$p/.claude/settings.local.json" <<EOF
{"effortLevel":"low","disableAllHooks":true,"env":{"MY_TOKEN":"$key"},
 "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash rewrite.sh"},{"type":"command","command":"BASH_ENV= ENV= bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/method/guard.sh\""}]}]},
 "enabledPlugins":{"a@b":true,"c@d":false}}
EOF
hook "$p"
# (the second hook is a copy of the method's own command: in local settings
# it would replace the project's entry with its own fields, so it counts)
has "local settings that weaken the method are named, key by key, a copy of the method's hook included" ".claude/settings.local.json sets effortLevel; disableAllHooks; env MY_TOKEN; 2 PreToolUse or PermissionRequest hooks (the method's are in the project's settings only); 1 enabled plugin (their hooks were not read)"
lacks "a value from the settings is never printed, only names" "$key"
printf '{"effortLevel":' >"$p/.claude/settings.local.json"
hook "$p"
has "local settings that are not JSON are a LOOK" ".claude/settings.local.json is not JSON, so what it changes is not known"
rm -f "$p/.claude/settings.local.json"
mkdir -p "$HOME/.claude"
printf '{"maxEffortLevel":"high","disableSkillShellExecution":false}\n' >"$HOME/.claude/settings.json"
hook "$p"
# shellcheck disable=SC2088 # the ~ is the text the hook prints, not a path
has "user settings that cap effort below xhigh are named; what the project's settings override is not" "~/.claude/settings.json adds to every session: maxEffortLevel high, below xhigh"
lacks "user settings' skill shell setting is not named (the project's wins)" "disableSkillShellExecution"
printf '{"modelSettings":{"claude-opus-5-5":{"maxEffortLevel":"low"}}}\n' >"$HOME/.claude/settings.json"
hook "$p"
# shellcheck disable=SC2088 # the ~ is the text the hook prints, not a path
has "a per-model effort cap in user settings is named" "~/.claude/settings.json adds to every session: a maxEffortLevel below xhigh for 1 model (modelSettings)"
printf '{"maxEffortLevel":"high"}\n' >"$p/.claude/settings.local.json"
hook "$p"
has "an effort cap in local settings is named too" ".claude/settings.local.json sets maxEffortLevel high, below xhigh; it ranks above the method's settings"
rm -f "$p/.claude/settings.local.json"
mkdir -p "$work/cfg"
printf '{"env":{"CFG_ONLY":"1"}}\n' >"$work/cfg/settings.json"
hook "$p" "" CLAUDE_CONFIG_DIR="$work/cfg"
has "with CLAUDE_CONFIG_DIR set, the user settings there are read, as Claude Code reads them" "\$CLAUDE_CONFIG_DIR/settings.json adds to every session: env CFG_ONLY"
# shellcheck disable=SC2088 # the ~ is the text the hook prints, not a path
lacks "and ~/.claude/settings.json is not" "~/.claude/settings.json"
if mkfifo "$p/.claude/settings.local.json" 2>/dev/null; then
  start=$(perl -e 'print time')
  # (under a 20 s bound: a hook that waits on the FIFO is ended and the
  # case goes red, instead of the test file waiting forever)
  hook "$p" "" perl "$root/tests/harness/bound.pl" 20
  took=$(($(perl -e 'print time') - start))
  if [ "$code" -ne 124 ] && [ "$took" -le 10 ]; then has "a settings file that is a FIFO is a LOOK, and the hook does not wait on it (${took} s)" ".claude/settings.local.json is not a regular file"; else fail "a settings file that is a FIFO does not hold the hook" "exit $code after $took s"; fi
  rm -f "$p/.claude/settings.local.json"
else
  skip "a settings file that is a FIFO: FIFOs cannot be made here"
fi
printf '{"modelSettings":{"claude-opus-5-5":{"effortLevel":"low"}}}\n' >"$p/.claude/settings.local.json"
hook "$p"
has "an effortLevel below xhigh for one model in local settings is a LOOK" "an effortLevel below xhigh for 1 model (modelSettings)"
rm -f "$p/.claude/settings.local.json"
printf '{"availableModels":["claude-sonnet-5-5"]}\n' >"$HOME/.claude/settings.json"
hook "$p"
has "availableModels in user settings is a LOOK, as lists add up across settings files" "availableModels (lists add up across settings files)"
rm -f "$HOME/.claude/settings.json"
printf '{"env":{"METHOD_NESTED":"1"}}\n' >"$p/.claude/settings.local.json"
hook "$p" "" METHOD_NESTED=1
has "a nested run still checks the settings, so METHOD_NESTED set in them is named" "METHOD-ACTIVE vunreleased (nested: status skipped)" "env METHOD_NESTED"
rm -f "$p/.claude/settings.local.json"
perl -e 'print "{\"env\":{\"A\":\"" . ("x" x (1024 * 1024)) . "\"}}\n"' >"$p/.claude/settings.local.json"
hook "$p"
has "a settings file over 1 MB is named, not read, so reading it cannot take the hook past its time" ".claude/settings.local.json is over 1 MB"
rm -f "$p/.claude/settings.local.json"
printf '\357\273\277{"env":{"BOM_ONLY":"1"}}\n' >"$p/.claude/settings.local.json"
hook "$p"
has "a settings file that starts with a byte-order mark is read, as Claude Code reads it" "env BOM_ONLY"
printf '{"disableSkillShellExecution":false}\n' >"$p/.claude/settings.local.json"
hook "$p"
n=$(printf '%s\n' "$out" | grep -o 'disableSkillShellExecution' | wc -l | tr -d ' ')
if [ "$n" = 1 ]; then pass "skill shell lines switched on in local settings are named once"; else fail "skill shell lines switched on in local settings are named once" "$out"; fi
rm -f "$p/.claude/settings.local.json"
mkdir -p "$p/sub"
printf '{"maxEffortLevel":"low"}\n' >"$p/.claude/settings.local.json"
hook "$p" "$(printf '{"hook_event_name":"SessionStart","source":"compact","cwd":"%s/sub"}' "$p")"
has "local settings are read from the project, also when the input's folder is a subfolder" ".claude/settings.local.json sets maxEffortLevel low, below xhigh"
rm -f "$p/.claude/settings.local.json"
hook "$p" "$(printf '{"hook_event_name":"SessionStart","source":"startup","cwd":"%s","model":"us.custom.arn:aws:bedrock:eu:123456789012:x"}' "$p")"
has "a model id not in Anthropic's own shape is not shown, only that it differs" "this session runs a model, not claude-opus-5-5"
lacks "and the id itself is not printed" "123456789012"
hook "$p" "not json"
has "input that cannot be read is a LOOK" "the hook's input could not be read (not valid JSON"
rm -f "$HOME/.claude/settings.json"

mkdir -p "$p/.claude/method-local"
printf '# the owner keeps work aside\nstash :: kept aside\n\nstash pop :: back\n' >"$p/.claude/method-local/git-shapes.txt"
hook "$p"
has "git shapes the owner added in .claude/method-local are counted (comments and blank lines are not)" "2 git shapes added in .claude/method-local/git-shapes.txt; the guard lets them through (G3)"
printf 'pr merge -* ARG... :: I merge here\n' >"$p/.claude/method-local/gh-shapes.txt"
printf 'request_copilot_review :: I want it\nrun_secret_scanning :: and this\n' >"$p/.claude/method-local/mcp-tools.txt"
hook "$p"
has "gh shapes and MCP tool lines the owner added are counted too" "1 gh shape added in .claude/method-local/gh-shapes.txt; the guard lets them through (G4)" "2 MCP tool lines added in .claude/method-local/mcp-tools.txt; the guard lets them through (G4)"
rm -f "$p/.claude/method-local/git-shapes.txt" "$p/.claude/method-local/gh-shapes.txt" "$p/.claude/method-local/mcp-tools.txt"
# a list that is a link to /dev/zero is never read (it would never end),
# and one over 1 MB is not read either; the hook ends at once
ln -s /dev/zero "$p/.claude/method-local/git-shapes.txt"
perl -e 'print "x :: y\n" x 200000' >"$p/.claude/method-local/gh-shapes.txt"
start=$(perl -e 'print time')
HOOK_MEM_KB=1048576 hook "$p"
took=$(($(perl -e 'print time') - start))
if [ "$took" -le 5 ]; then has "a list that is not a regular file, or is over 1 MB, is a LOOK and is not read (in ${took} s)" ".claude/method-local/git-shapes.txt is not a regular file, so what it adds is not known" ".claude/method-local/gh-shapes.txt is over 1 MB, so what it adds is not known"; else fail "a list that is not a regular file is not read" "took $took s: $out"; fi
rm -rf "$p/.claude/method-local"

hook "$p" "" METHOD_NESTED=1
if [ "$out" = "METHOD-ACTIVE vunreleased (nested: status skipped)" ] && [ "$code" -eq 0 ]; then pass "a nested run gets one line"; else fail "a nested run gets one line" "$out"; fi

# a fake gh on PATH: the ci area must not run it (origin on github.com, so
# the ci area would call gh if it ran)
mkdir -p "$work/bin"
printf '#!/bin/sh\ntouch "%s/gh-ran"\nexit 1\n' "$work" >"$work/bin/gh"
chmod +x "$work/bin/gh"
real_origin=$(git -C "$p" remote get-url origin)
git -C "$p" remote set-url origin https://github.com/example/example.git
hook "$p" "" PATH="$work/bin:$PATH"
git -C "$p" remote set-url origin "$real_origin"
if [ ! -e "$work/gh-ran" ]; then pass "the ci area is not run at session start (a gh on PATH is not called, with origin on github.com)"; else fail "the ci area is not run at session start (a gh on PATH is not called)"; fi

# many LOOK lines: the caps
# long lines: a local settings file naming many long variables
printf '{"effortLevel":"low"}\n' >"$p/.claude/settings.local.json"
long=$(perl -e 'print "V" . "x" x 60 . "_$_," for 1 .. 40')
printf '{"env":{%s"Z":"1"}}\n' "$(printf '%s' "$long" | sed 's/\([A-Za-z0-9_x]*\),/"\1":"1",/g')" >"$HOME/.claude/settings.json"
hook "$p" "$(printf '{"source":"startup","cwd":"%s","model":"m"}' "$p")" CLAUDE_CODE_DISABLE_ADVISOR_TOOL=0 CLAUDE_CODE_DISABLE_AUTO_MEMORY=0
lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
bytes=$(printf '%s\n' "$out" | wc -c | tr -d ' ')
long_line=$(printf '%s\n' "$out" | awk 'length($0) > 240' | wc -l | tr -d ' ')
if [ "$lines" -le 10 ] && [ "$bytes" -le 1200 ] && [ "$long_line" -eq 0 ]; then pass "the output keeps to 10 lines, 1,200 bytes and 240 bytes a line ($lines lines, $bytes bytes)"; else fail "the output keeps to 10 lines, 1,200 bytes and 240 bytes a line" "$lines lines, $bytes bytes, $long_line long: $out"; fi
cut_line=$(printf '%s\n' "$out" | grep '^session-status: LOOK - ~/.claude/settings.json adds to every session: env Vxxx' || true)
case "$cut_line" in
  *' ...') if [ "$(printf '%s' "$cut_line" | wc -c | tr -d ' ')" -le 240 ]; then pass "a line that is too long is cut to 240 bytes and marked, not dropped"; else fail "a line that is too long is cut to 240 bytes" "$cut_line"; fi ;;
  *) fail "a line that is too long is cut to 240 bytes and marked, not dropped" "$out" ;;
esac
rm -f "$HOME/.claude/settings.json" "$p/.claude/settings.local.json"
# more than 1,200 bytes in fewer than 10 lines: the byte cap ends it
# (session.pl's own lines, through capped(): the hook's other lines can no
# longer be made long enough, as a model id is shown only in its own shape)
out=$(LIBDIR="$root/method/scripts/method/lib" perl -e 'require "$ENV{LIBDIR}/session.pl"; print "$_\n" for Session::capped(map { "line $_: " . ("b" x 200) } 1 .. 8)')
lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
bytes=$(printf '%s\n' "$out" | wc -c | tr -d ' ')
last=$(printf '%s\n' "$out" | tail -1)
case "$last" in
  "... "*" more: run bash scripts/method/status.sh") if [ "$bytes" -le 1160 ] && [ "$lines" -lt 9 ]; then pass "over its 1,160 bytes in fewer than 9 lines, the byte cap ends session.pl's output and counts the rest ($lines lines, $bytes bytes)"; else fail "the byte cap ends the output" "$lines lines, $bytes bytes: $out"; fi ;;
  *) fail "over its 1,160 bytes in fewer than 9 lines, the byte cap ends session.pl's output and counts the rest" "$lines lines, $bytes bytes: $out" ;;
esac
# the PowerShell warning, on the systems where the tool exists (perl's $^O
# set as Git Bash's perl sets it)
out=$(LIBDIR="$root/method/scripts/method/lib" CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1 perl -e 'require "$ENV{LIBDIR}/session.pl"; delete $ENV{CLAUDE_CODE_USE_POWERSHELL_TOOL}; my @w; { local $^O = "msys"; @w = Session::warnings_for({ model => "claude-opus-5-5" }, $ARGV[0]) } my @l = Session::warnings_for({ model => "claude-opus-5-5" }, $ARGV[0]); $ENV{CLAUDE_CODE_USE_POWERSHELL_TOOL} = "0"; my @o; { local $^O = "msys"; @o = Session::warnings_for({ model => "claude-opus-5-5" }, $ARGV[0]) } print join("|", scalar(grep { /PowerShell tool is not switched off/ } @w), scalar(grep { /PowerShell/ } @l), scalar(grep { /PowerShell/ } @o))' "$p")
if [ "$out" = "1|0|0" ]; then pass "on Git Bash the PowerShell tool not switched off is a LOOK, and not elsewhere or when it is off"; else fail "the PowerShell warning on Git Bash only" "$out"; fi
# run_limited stops what a timed-out command left behind that ignores TERM
# (a grandchild that would write a mark after 2 s)
rm -f "$work/left-behind"
LIBDIR="$root/method/scripts/method/lib" MARK="$work/left-behind" perl -e 'require "$ENV{LIBDIR}/status.pl"; Status::run_limited(Time::HiRes::time() + 0.5, undef, "sh", "-c", "(trap \"\" TERM; sleep 2; touch \"\$MARK\") & sleep 30")' >/dev/null 2>&1
perl -e 'select undef, undef, undef, 3'
if [ ! -e "$work/left-behind" ]; then pass "a command run under a time limit leaves nothing running that ignored TERM"; else fail "a command run under a time limit leaves nothing running that ignored TERM" "the grandchild wrote its mark"; fi
# another repository status reports on (REPOS), named with capitals and an
# underscore, and not clean: its LOOK line is kept
git init -q "$work/Site_B" && printf 'x\n' >"$work/Site_B/new.txt"
printf 'REPOS=../Site_B\n' >"$p/.claude/method.conf"
hook "$p"
has "a LOOK line of another repository status reports on is kept, whatever its name's letters" "repo ../Site_B: LOOK"
rm -rf "$p/.claude/method.conf" "$work/Site_B"
# more lines than fit: the last line says how many more
cat >"$p/.claude/settings.local.json" <<'EOF'
{"model":"m","env":{"A":"1"}}
EOF
printf '{"env":{"B":"1"},"maxEffortLevel":"low"}\n' >"$HOME/.claude/settings.json"
hook "$p" "$(printf '{"source":"startup","cwd":"%s","model":"m"}' "$p")" CLAUDE_CODE_DISABLE_ADVISOR_TOOL=0 CLAUDE_CODE_DISABLE_AUTO_MEMORY=0 CLAUDE_CODE_EFFORT_LEVEL=low
lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
bytes=$(printf '%s\n' "$out" | wc -c | tr -d ' ')
if [ "$lines" -le 10 ] && [ "$bytes" -le 1200 ]; then pass "with every warning at once it still keeps to the caps ($lines lines, $bytes bytes)"; else fail "with every warning at once it still keeps to the caps" "$lines lines, $bytes bytes: $out"; fi
rm -f "$HOME/.claude/settings.json" "$p/.claude/settings.local.json"
p2=$(project capped) || abort_sandbox
perl -0pi -e 's/our \$MAX_LINES = 9;/our \$MAX_LINES = 3;/' "$p2/scripts/method/lib/session.pl"
hook "$p2" "" CLAUDE_CODE_DISABLE_ADVISOR_TOOL=0 CLAUDE_CODE_DISABLE_AUTO_MEMORY=0 CLAUDE_CODE_EFFORT_LEVEL=low
last=$(printf '%s\n' "$out" | tail -1)
lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
case "$last" in
  "... "*" more: run bash scripts/method/status.sh") if [ "$lines" -le 4 ]; then pass "lines that do not fit are counted on the last line, which points to status.sh"; else fail "lines that do not fit are counted on the last line" "$out"; fi ;;
  *) fail "lines that do not fit are counted on the last line, which points to status.sh" "$out" ;;
esac

# the library, status and perl going wrong
p3=$(project broken) || abort_sandbox
printf '#!/usr/bin/env bash\nexit 7\n' >"$p3/scripts/method/status.sh"
hook "$p3"
has "status that gives no summary is a LOOK, and the hook still exits 0" "METHOD-ACTIVE vunreleased" "status gave no summary line"
printf '#!/usr/bin/env bash\nsleep 20\n' >"$p3/scripts/method/status.sh"
start=$(perl -e 'print time')
hook "$p3"
took=$(($(perl -e 'print time') - start))
if [ "$took" -le 12 ]; then has "status that does not finish within 5 s is a LOOK, and the hook ends (in ${took} s)" "status did not finish within 5 s"; else fail "status that does not finish within 5 s ends the wait" "took $took s: $out"; fi
cp "$p3/scripts/method/lib/status.pl" "$work/status.pl.keep"
printf 'die "planted\\n";\n' >"$p3/scripts/method/lib/status.pl"
mkdir -p "$p3/.claude" && printf '{"maxEffortLevel":"low"}\n' >"$p3/.claude/settings.local.json"
hook "$p3"
has "when status cannot be loaded, the settings checks still come, with a LOOK saying so" "status could not be loaded" ".claude/settings.local.json sets maxEffortLevel low"
cp "$work/status.pl.keep" "$p3/scripts/method/lib/status.pl"
rm -f "$p3/.claude/settings.local.json"
printf 'die "planted\\n";\n' >"$p3/scripts/method/lib/session.pl"
hook "$p3"
if [ "$code" -eq 0 ] && [ "$out" = "$(printf 'METHOD-ACTIVE vunreleased\nsession-status: LOOK - its perl part failed (exit 255), so status and the settings checks are missing; run bash scripts/method/status.sh')" ]; then pass "a session.pl that crashes still leaves METHOD-ACTIVE and says it failed, and the hook exits 0"; else fail "a session.pl that crashes still leaves METHOD-ACTIVE and says it failed" "exit $code: $out"; fi
rm -f "$p3/scripts/method/lib/session.pl"
hook "$p3"
# a status that takes too long is cut off at the deadline, with a line
# saying so (the deadline lowered to 1 s, status made to take 5 s)
dl=$(cd "$p" && printf '{"hook_event_name":"SessionStart","source":"startup"}' | LIBDIR="$root/method/scripts/method/lib" CLAUDE_PROJECT_DIR="$p" perl -e 'require "$ENV{LIBDIR}/session.pl"; no warnings "redefine"; *Session::status_lines = sub { sleep 5; () }; $Session::DEADLINE = 1; my $t = time; Session::main(); print STDERR "took ", time - $t, "\n"' 2>&1)
case "$dl" in
  *"ran out of time (1 s)"*) case "$dl" in *"took "[12]*) pass "the perl part ends at its deadline, with a line saying part of its checks is missing" ;; *) fail "the perl part ends at its deadline" "$dl" ;; esac ;;
  *) fail "the perl part ends at its deadline" "$dl" ;;
esac
# the deadline holds when it fires inside a step whose own eval catches it
# (a settings read: Json::decode, here made to take 3 s inside its eval)
mkdir -p "$p/.claude" && printf '{"maxEffortLevel":"low"}\n' >"$p/.claude/settings.local.json"
dl=$(cd "$p" && printf '{"hook_event_name":"SessionStart","source":"startup"}' | LIBDIR="$root/method/scripts/method/lib" CLAUDE_PROJECT_DIR="$p" perl -e 'require "$ENV{LIBDIR}/session.pl"; no warnings "redefine"; *Session::status_lines = sub { () }; my $real = \&Json::decode; *Json::decode = sub { return $real->(@_) if $_[0] =~ /hook_event_name/; my $ok = eval { sleep 3; 1 }; return (undef, "stopped") }; $Session::DEADLINE = 1; my $t = time; Session::main(); print STDERR "took ", time - $t, "\n"' 2>&1)
case "$dl" in
  *"is not JSON"*) fail "a deadline caught inside a settings read still ends the perl part, and says so" "$dl" ;;
  *"ran out of time (1 s)"*) case "$dl" in *"took "[12]*) pass "a deadline caught inside a settings read still ends the perl part, and says so (the file is not called not JSON)" ;; *) fail "a deadline caught inside a settings read ends the perl part in time" "$dl" ;; esac ;;
  *) fail "a deadline caught inside a settings read still ends the perl part, and says so" "$dl" ;;
esac
rm -f "$p/.claude/settings.local.json"
# G16's snapshot runs inside the deadline too: one that hangs (a git call
# that blocks) cannot hold the hook (final review of step 5)
dl=$(cd "$p" && printf '{"hook_event_name":"SessionStart","source":"startup","session_id":"s1"}' | LIBDIR="$root/method/scripts/method/lib" CLAUDE_PROJECT_DIR="$p" perl -e 'require "$ENV{LIBDIR}/session.pl"; require "$ENV{LIBDIR}/watch.pl"; no warnings "redefine"; *Session::status_lines = sub { () }; *Watch::snapshot = sub { sleep 5; 1 }; $Session::DEADLINE = 1; my $t = time; Session::main(); print STDERR "took ", time - $t, "\n"' 2>&1)
case "$dl" in
  *"ran out of time (1 s)"*) case "$dl" in *"took "[12]*) pass "a snapshot that hangs is cut off at the deadline, with a line saying so" ;; *) fail "a snapshot that hangs is cut off at the deadline" "$dl" ;; esac ;;
  *) fail "a snapshot that hangs is cut off at the deadline" "$dl" ;;
esac
has "missing scripts still leave METHOD-ACTIVE and say so, in a line that holds no path" "METHOD-ACTIVE vunreleased" "the method's scripts are missing (scripts/method/lib); run the method's sync"
# a lone surrogate escape, which Claude Code reads, is read too: the env
# name is shown, not "is not JSON"
mkdir -p "$p/.claude" && printf '{"env":{"SOME_SETTING":"\\ud800"}}\n' >"$p/.claude/settings.local.json"
hook "$p"
has "a settings file with a lone surrogate escape is read, as Claude Code reads it" ".claude/settings.local.json sets env SOME_SETTING"
rm -f "$p/.claude/settings.local.json"
mkdir -p "$work/noperl"
for t in bash sh env sed cat git dirname; do
  w=$(command -v "$t") && ln -s "$w" "$work/noperl/$t"
done
hook "$p" "" PATH="$work/noperl"
has "without perl, METHOD-ACTIVE and a LOOK saying so" "METHOD-ACTIVE vunreleased" "perl or its JSON::PP module is missing"
hook "$p" "" PERL5OPT=-Mplanted::module PERL5LIB="$work/nowhere"
has "PERL5OPT and PERL5LIB set by a settings file do not reach the hook's perl" "status: nothing needs a look"

drop_sandbox "$work" || true
echo "tests: session-status: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
