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
# otherwise; sets out and code
hook() {
  d=$1
  in=${2:-}
  shift
  [ $# -gt 0 ] && shift
  [ -n "$in" ] || in=$(printf '{"hook_event_name":"SessionStart","source":"startup","cwd":"%s"}' "$d")
  out=$(cd "$d" && printf '%s' "$in" | env -u CLAUDE_CODE_EXECPATH -u CLAUDE_CODE_EFFORT_LEVEL CLAUDE_PROJECT_DIR="$d" CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1 "$@" bash "$d/.claude/hooks/method/session-status.sh" 2>&1)
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
lacks "status's PASS lines stay out of the context" "records: PASS"

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
has "local settings that weaken the method are named, key by key" ".claude/settings.local.json sets effortLevel; disableAllHooks; env MY_TOKEN; 1 PreToolUse or PermissionRequest hook that are not the method's; 1 enabled plugin (their hooks were not read)"
lacks "a value from the settings is never printed, only names" "$key"
printf '{"effortLevel":' >"$p/.claude/settings.local.json"
hook "$p"
has "local settings that are not JSON are a LOOK" ".claude/settings.local.json is not JSON, so what it changes is not known"
rm -f "$p/.claude/settings.local.json"
mkdir -p "$HOME/.claude"
printf '{"maxEffortLevel":"high","disableSkillShellExecution":false}\n' >"$HOME/.claude/settings.json"
hook "$p"
# shellcheck disable=SC2088 # the ~ is the text the hook prints, not a path
has "user settings that cap effort below xhigh or turn skill shell lines on are named" "~/.claude/settings.json sets disableSkillShellExecution; disableSkillShellExecution false; maxEffortLevel high, below xhigh"
rm -f "$HOME/.claude/settings.json"

hook "$p" "" METHOD_NESTED=1
if [ "$out" = "METHOD-ACTIVE vunreleased (nested: status skipped)" ] && [ "$code" -eq 0 ]; then pass "a nested run gets one line"; else fail "a nested run gets one line" "$out"; fi

# a fake gh on PATH: the ci area must not run it
mkdir -p "$work/bin"
printf '#!/bin/sh\ntouch "%s/gh-ran"\nexit 1\n' "$work" >"$work/bin/gh"
chmod +x "$work/bin/gh"
hook "$p" "" PATH="$work/bin:$PATH"
if [ ! -e "$work/gh-ran" ]; then pass "the ci area is not run at session start (a gh on PATH is not called)"; else fail "the ci area is not run at session start (a gh on PATH is not called)"; fi

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
cut_line=$(printf '%s\n' "$out" | grep '^session-status: LOOK - ~/.claude/settings.json sets env Vxxx' || true)
case "$cut_line" in
  *' ...') if [ "$(printf '%s' "$cut_line" | wc -c | tr -d ' ')" -le 240 ]; then pass "a line that is too long is cut to 240 bytes and marked, not dropped"; else fail "a line that is too long is cut to 240 bytes" "$cut_line"; fi ;;
  *) fail "a line that is too long is cut to 240 bytes and marked, not dropped" "$out" ;;
esac
rm -f "$HOME/.claude/settings.json" "$p/.claude/settings.local.json"
# more than 1,200 bytes in fewer than 10 lines: the byte cap ends it
name=$(perl -e 'print "W" x 100')
printf '{"env":{"%s_1":"1","%s_2":"1","%s_3":"1"}}\n' "$name" "$name" "$name" >"$p/.claude/settings.local.json"
printf '{"env":{"%s_4":"1","%s_5":"1","%s_6":"1"}}\n' "$name" "$name" "$name" >"$HOME/.claude/settings.json"
printf 'x\n' >"$p/dirty-$(perl -e 'print "d" x 120')"
hook "$p" "$(printf '{"source":"startup","cwd":"%s","model":"%s"}' "$p" "$(perl -e 'print "m" x 180')")" CLAUDE_CODE_DISABLE_ADVISOR_TOOL=0 CLAUDE_CODE_DISABLE_AUTO_MEMORY=0 CLAUDE_CODE_EFFORT_LEVEL=low
lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
bytes=$(printf '%s\n' "$out" | wc -c | tr -d ' ')
last=$(printf '%s\n' "$out" | tail -1)
case "$last" in
  "... "*" more: run bash scripts/method/status.sh") if [ "$bytes" -le 1200 ] && [ "$lines" -lt 10 ]; then pass "over 1,200 bytes in fewer than 10 lines, the byte cap ends the output and counts the rest ($lines lines, $bytes bytes)"; else fail "the byte cap ends the output" "$lines lines, $bytes bytes: $out"; fi ;;
  *) fail "over 1,200 bytes in fewer than 10 lines, the byte cap ends the output and counts the rest" "$lines lines, $bytes bytes: $out" ;;
esac
rm -f "$HOME/.claude/settings.json" "$p/.claude/settings.local.json" "$p"/dirty-*
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
printf 'die "planted\\n";\n' >"$p3/scripts/method/lib/session.pl"
hook "$p3"
if [ "$code" -eq 0 ] && [ "$out" = "METHOD-ACTIVE vunreleased" ]; then pass "a session.pl that crashes still leaves METHOD-ACTIVE, and the hook exits 0"; else fail "a session.pl that crashes still leaves METHOD-ACTIVE, and the hook exits 0" "exit $code: $out"; fi
rm -f "$p3/scripts/method/lib/session.pl"
hook "$p3"
has "missing scripts still leave METHOD-ACTIVE and say so" "METHOD-ACTIVE vunreleased" "the method's scripts are missing"
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
