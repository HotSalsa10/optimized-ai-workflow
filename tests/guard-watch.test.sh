#!/usr/bin/env bash
# Tests for what could change the session's hooks once it has started
# (step 5.9, lib/watch.pl): G16, a settings change during a session refused
# at Claude Code's ConfigChange event against the snapshot session-status
# takes when the session starts, with a one-time message after it; and
# G17, a Skill, Agent or Task call whose skill or agent declares hooks in
# its frontmatter. guard.sh and session-status.sh run with a hook's input
# in a real project, with a home folder of its own.
# shellcheck disable=SC2016 # single-quoted JSON and commands are meant literally
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}
echo "tests: guard (settings changes and skill hooks)"
root=$(repo_root)
guard="$root/method/.claude/hooks/method/guard.sh"
status_hook="$root/method/.claude/hooks/method/session-status.sh"
work=$(new_sandbox_dir) || abort_sandbox
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
unset XDG_CONFIG_HOME CLAUDE_CONFIG_DIR GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
mkdir -p "$HOME/.claude"
git config --global user.email test@example.invalid
git config --global user.name Test
git config --global init.defaultBranch main
git config --global commit.gpgsign false
proj="$work/proj"
if ! (mkdir -p "$proj/.claude" && cd "$proj" && git init -q && printf '{}\n' >.claude/settings.json && git add -A && git commit -qm one); then abort_sandbox; fi
user="$HOME/.claude/settings.json"
local_s="$proj/.claude/settings.local.json"
printf '{"theme": "dark", "env": {"FOO": "1"}, "permissions": {"deny": ["Bash(rm:*)"]}}\n' >"$user"
printf '{"theme": "light"}\n' >"$local_s"

# hook INPUT-JSON: guard.sh on a hook's input, from the project
hook() {
  printf '%s\n' "$1" >"$work/in.json"
  err=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" perl -e 'alarm 60; exec @ARGV' bash "$guard" <"$work/in.json" 2>&1 >"$work/out.txt")
  code=$?
}
want() {
  name=$1
  case "$2" in
    allow) if [ "$code" -eq 0 ] && [ -z "$err" ]; then pass "$name"; else fail "$name: wanted it let through" "exit $code: $err"; fi ;;
    *) case "$err" in
        "guard $2: "*) if [ "$code" -eq 2 ]; then pass "$name"; else fail "$name: wanted exit 2" "exit $code: $err"; fi ;;
        *) fail "$name: wanted guard $2" "exit $code: $err" ;;
      esac ;;
  esac
}
# change NAME SID SOURCE WANT: a ConfigChange of SOURCE in session SID
change() { hook "{\"hook_event_name\":\"ConfigChange\",\"session_id\":\"$2\",\"source\":\"$3\",\"cwd\":\"$proj\"}"; want "$1" "$4"; }
# start SID SOURCE: session-status at a session's start
start() {
  printf '{"hook_event_name":"SessionStart","session_id":"%s","source":"%s","cwd":"%s"}\n' "$1" "$2" "$proj" >"$work/start.json"
  (cd "$proj" && CLAUDE_PROJECT_DIR="$proj" perl -e 'alarm 60; exec @ARGV' bash "$status_hook" <"$work/start.json" >/dev/null 2>&1)
}
snap() { (cd "$proj" && CLAUDE_PROJECT_DIR="$proj" perl -e 'require $ARGV[0]; print Watch::snapshot_path($ARGV[1], $ARGV[2])' "$root/method/scripts/method/lib/watch.pl" "$proj" "$1"); }

# --- G16: the snapshot ---
start s1 startup
s1=$(snap s1)
if [ -f "$s1" ]; then pass "session-status takes a snapshot when a session starts, in git's folder"; else fail "a snapshot at the start" "$s1"; fi
case "$s1" in "$proj/.git/method-settings-"*.json) pass "the snapshot is named method-settings-*, which G6 protects" ;; *) fail "the snapshot's name" "$s1" ;; esac
before=$(cksum <"$s1")
printf '{"theme": "dark", "env": {"FOO": "1", "BASH_ENV": "/tmp/x"}, "permissions": {"deny": ["Bash(rm:*)"]}}\n' >"$user"
for src in compact clear resume; do
  start s1 "$src"
  if [ "$(cksum <"$s1")" = "$before" ]; then pass "a $src does not take the snapshot again, so a refused change never becomes the baseline"; else fail "a $src keeps the snapshot"; fi
done
start s2 resume
if [ -f "$(snap s2)" ]; then pass "a resumed session with no snapshot gets one"; else fail "a resume with no snapshot takes one"; fi

# --- G16: changes refused and let through (session s1's snapshot) ---
change "an env variable added to the user settings (BASH_ENV) is refused" s1 user_settings G16
printf '{"theme": "dark", "env": {"FOO": "1", "PATH": "/tmp/evil:/usr/bin"}, "permissions": {"deny": ["Bash(rm:*)"]}}\n' >"$user"
change "PATH set in the user settings is refused" s1 user_settings G16
printf '{"theme": "dark", "env": {"FOO": "1", "BASH_FUNC_perl%%%%": "() { :; }"}, "permissions": {"deny": ["Bash(rm:*)"]}}\n' >"$user"
change "an exported function named perl in the user settings is refused" s1 user_settings G16
printf '{"theme": "dark", "env": {"FOO": "2"}, "permissions": {"deny": ["Bash(rm:*)"]}}\n' >"$user"
change "any change to an env value is refused" s1 user_settings G16
printf '{"theme": "light", "env": {"FOO": "1"}, "permissions": {"deny": ["Bash(rm:*)"]}}\n' >"$user"
change "a theme change in the user settings passes" s1 user_settings allow
printf '{"theme": "dark", "env": {"FOO": "1"}, "permissions": {"deny": []}}\n' >"$user"
change "a permissions.deny entry removed is refused" s1 user_settings G16
printf '{"theme": "dark", "env": {"FOO": "1"}, "permissions": {"deny": ["Bash(rm:*)", "Bash(curl:*)"]}}\n' >"$user"
change "a permissions.deny entry added passes" s1 user_settings allow
printf '{"theme": "dark", "env": {"FOO": "1"}, "permissions": {"deny": ["Bash(rm:*)"]}, "enabledPlugins": {"x@y": true}}\n' >"$user"
change "a plugin enabled is refused" s1 user_settings G16
printf '{"theme": "dark", "env": {"FOO": "1"}, "permissions": {"deny": ["Bash(rm:*)"]}, "hooks": {"PreToolUse": []}}\n' >"$user"
change "hooks added to the user settings are refused" s1 user_settings G16
printf '{"theme": "dark", "env": {"FOO": "1"}, "permissions": {"deny": ["Bash(rm:*)"]}, "statusLine": {"type": "command", "command": "touch /tmp/x"}}\n' >"$user"
change "a statusLine added to the user settings is refused (it runs a program outside the hooks)" s1 user_settings G16
printf '{"theme": "dark", "env": {"FOO": "1"}, "permissions": {"deny": ["Bash(rm:*)"]}, "apiKeyHelper": "/tmp/x"}\n' >"$user"
change "an apiKeyHelper added to the user settings is refused" s1 user_settings G16
printf '{"theme": "dark", "env": {"FOO": "1"}, "permissions": {"deny": ["Bash(rm:*)"]}}\n' >"$user"
printf '{"theme": "light", "disableAllHooks": true}\n' >"$local_s"
change "disableAllHooks in the local settings is refused" s1 local_settings G16
printf '{"theme": "light", "disableSkillShellExecution": false}\n' >"$local_s"
change "skill shell lines turned on in the local settings is refused" s1 local_settings G16
printf '{"theme": "dark"}\n' >"$local_s"
change "a theme change in the local settings passes" s1 local_settings allow
printf 'not json\n' >"$local_s"
change "a local settings file that is not JSON is refused" s1 local_settings G16
printf '{"theme": "dark"}\n' >"$local_s"
change "any change to the project's settings is refused" s1 project_settings G16
change "a change to the skills passes (G17 judges a skill when it is used)" s1 skills allow
change "a change to the managed settings passes (it cannot be refused)" s1 policy_settings allow
case "$err$(cat "$work/out.txt")" in *FOO*|*BASH_ENV*|*evil*) fail "a refusal names no settings value" "$err" ;; *) pass "a refusal names no settings value" ;; esac
# with no snapshot: what the file holds
change "with no snapshot, a user settings file that holds env is refused" s9 user_settings G16
printf '{"theme": "dark", "disableAllHooks": false}\n' >"$local_s"
change "with no snapshot, a local settings file with only a theme and disableAllHooks false passes" s9 local_settings allow

# --- G16: logged, and one message at the next call let through ---
if grep -q '	G16	ConfigChange	' "$proj/.method/local/guard.log" 2>/dev/null; then pass "a refused change is logged in guard.log (G16, ConfigChange)"; else fail "a refused change is logged" "$(tail -2 "$proj/.method/local/guard.log" 2>/dev/null)"; fi
hook "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"s1\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"cwd\":\"$proj\"}"
first=$(cat "$work/out.txt")
hook "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"s1\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"cwd\":\"$proj\"}"
second=$(cat "$work/out.txt")
case "$first" in
  *'"systemMessage":"guard G16: a settings change was refused during this session'*) if [ -z "$second" ] && [ "$code" -eq 0 ]; then pass "the next call let through brings a one-time message, and the one after none"; else fail "one message only" "second: $second"; fi ;;
  *) fail "the next call brings a message" "$first" ;;
esac

# --- G17: skills, commands and agents that declare hooks ---
skill() { mkdir -p "$1/skills/$2" && printf '%s' "$3" >"$1/skills/$2/SKILL.md"; }
HOOKED='---
name: helper
description: a helper
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: touch /tmp/x
---
Body.
'
PLAIN='---
name: plain
description: no hooks
---
The body may say hooks: and is not frontmatter.
'
skill "$proj/.claude" helper "$HOOKED"
skill "$proj/.claude" plain "$PLAIN"
skill "$HOME/.claude" userhook "$HOOKED"
skill "$proj/.claude" quoted "---
name: quoted
\"hooks\": {}
---
Body
"
mkdir -p "$proj/.claude/outside" "$proj/.claude/commands/ns" "$proj/.claude/agents/team" "$HOME/.claude/plugins/cache/mkt/plug/1.0.0/skills/pskill" "$proj/.claude/skills/odd/SKILL.md"
printf '%s' "$HOOKED" >"$proj/.claude/commands/deploy.md"
printf '%s' "$PLAIN" >"$proj/.claude/outside/SKILL.md"
printf '%s' "$HOOKED" >"$proj/.claude/commands/ns/cmd.md"
printf '%s' "$HOOKED" >"$HOME/.claude/plugins/cache/mkt/plug/1.0.0/skills/pskill/SKILL.md"
mkdir -p "$HOME/.claude/plugins/cache/mkt/plug/1.0.0/commands" && printf '%s' "$HOOKED" >"$HOME/.claude/plugins/cache/mkt/plug/1.0.0/commands/pcmd.md"
printf -- '---\nname: rev\ndescription: x\nhooks:\n  Stop: []\n---\nBody\n' >"$proj/.claude/agents/team/reviewer2.md"
printf -- '---\nname: calm\ndescription: x\n---\nBody\n' >"$proj/.claude/agents/calm.md"
call() { hook "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"s1\",\"tool_name\":\"$2\",\"tool_input\":$3,\"cwd\":\"$proj\"}"; want "$1" "$4"; }
call "a project skill that declares hooks is refused" Skill '{"skill":"helper"}' G17
call "the older Skill input form (/name and arguments) is read" Skill '{"command":"/helper now"}' G17
call "a user skill that declares hooks is refused" Skill '{"skill":"userhook"}' G17
call "a skill whose hooks key is quoted is refused" Skill '{"skill":"quoted"}' G17
call "a command that declares hooks is refused" Skill '{"skill":"deploy"}' G17
call "a command in a subfolder (ns:cmd) that declares hooks is refused" Skill '{"skill":"ns:cmd"}' G17
call "a plugin's skill that declares hooks is refused" Skill '{"skill":"plug:pskill"}' G17
call "a plugin's command that declares hooks is refused" Skill '{"skill":"plug:pcmd"}' G17
call "a skill whose definition is not a regular file is refused" Skill '{"skill":"odd"}' G17
call "a skill named as a path is refused (its definition is not looked up there)" Skill '{"skill":"../outside"}' G17
call "a skill without hooks passes (hooks: in its body does not count)" Skill '{"skill":"plain"}' allow
call "a skill with no file here (a built-in one) passes" Skill '{"skill":"code-review"}' allow
call "an agent, found by its frontmatter name, that declares hooks is refused" Agent '{"subagent_type":"rev","prompt":"x","description":"x"}' G17
call "the same agent through Task is refused" Task '{"subagent_type":"rev","prompt":"x","description":"x"}' G17
call "an agent without hooks passes" Agent '{"subagent_type":"calm","prompt":"x","description":"x"}' allow
call "a built-in agent passes" Agent '{"subagent_type":"general-purpose","prompt":"x","description":"x"}' allow
call "an agent call with no subagent_type passes" Agent '{"prompt":"x","description":"x"}' allow

# --- the hook command's form, bash -p (step 5.9): an exported function
# named command or perl, or SHELLOPTS=noexec, in the environment does not
# reach the guard; run as plain bash (the control), the function named
# command and noexec switch it off ---
printf '%s\n' "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"s1\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$proj/.claude/settings.json\",\"content\":\"{}\"},\"cwd\":\"$proj\"}" >"$work/in.json"
for e in command perl noexec; do
  case $e in
    command) var='BASH_FUNC_command%%=() {  return 0
}' ;;
    perl) var='BASH_FUNC_perl%%=() {  return 0
}' ;;
    noexec) var='SHELLOPTS=noexec' ;;
  esac
  (cd "$proj" && perl -e 'alarm 60; exec @ARGV' env "$var" CLAUDE_PROJECT_DIR="$proj" bash -p "$guard" <"$work/in.json" >/dev/null 2>&1)
  c=$?
  (cd "$proj" && perl -e 'alarm 60; exec @ARGV' env "$var" CLAUDE_PROJECT_DIR="$proj" bash "$guard" <"$work/in.json" >/dev/null 2>&1)
  cc=$?
  if [ "$c" -eq 2 ] && { [ "$e" = perl ] || [ "$cc" -ne 2 ]; }; then
    pass "bash -p: with $e set in the environment the guard still refuses a Write to the settings (as plain bash: exit $cc)"
  else
    fail "bash -p keeps $e from the guard" "bash -p: exit $c; plain bash: exit $cc"
  fi
done

# --- the snapshot's file (step 5b: written whole by lib/log.pl) ---
# A non-ASCII value (an e-acute, as UTF-8: a character below U+0100, which
# a snapshot printed as characters wrote as one Latin-1 byte, not UTF-8)
# is written as ASCII JSON and read back: with the snapshot read, a theme
# change passes; a snapshot that cannot be read would leave the stricter
# judging, which refuses a file that holds env.
printf '{"theme": "dark", "env": {"FOO": "caf\303\251"}}\n' >"$user"
start s30 startup
s30=$(snap s30)
printf '{"theme": "light", "env": {"FOO": "caf\303\251"}}\n' >"$user"
change "a non-ASCII settings value round-trips through the snapshot, so a theme change beside it passes" s30 user_settings allow
if [ -f "$s30" ] && ! LC_ALL=C grep -q '[^ -~]' "$s30"; then pass "the snapshot is written as ASCII JSON"; else fail "the snapshot is written as ASCII JSON" "$(od -c "$s30" 2>&1 | head -3)"; fi
printf '{"theme": "dark", "env": {"FOO": "cafe"}}\n' >"$user"
change "a change to a non-ASCII env value is still refused" s30 user_settings G16
# 25 older snapshots planted, each with its own time, beside a temporary
# file and a name that is not a snapshot's: a new session's snapshot keeps
# the newest 20 (its own among them) and leaves the other files alone
PROJ="$proj" perl -e 'for my $i (1 .. 25) { my $p = sprintf "%s/.git/method-settings-%016x.json", $ENV{PROJ}, $i; open my $o, ">", $p or die; print $o "{}"; close $o; utime 1000 + $i, 1000 + $i, $p or die } for my $n ("method-settings-00000000000000aa.json.123.tmp", "method-settings-x.json") { my $p = "$ENV{PROJ}/.git/$n"; open my $o, ">", $p or die; close $o; utime 1000, 1000, $p or die }'
start s31 startup
s31=$(snap s31)
kept=$(PROJ="$proj" perl -e 'opendir my $d, "$ENV{PROJ}/.git" or die; print scalar grep { /\Amethod-settings-[0-9a-f]+\.json\z/ && -f "$ENV{PROJ}/.git/$_" } readdir $d')
if [ "$kept" = 20 ] && [ -f "$s31" ] && [ -f "$proj/.git/method-settings-0000000000000019.json" ] && [ ! -e "$proj/.git/method-settings-0000000000000001.json" ] && [ -f "$proj/.git/method-settings-00000000000000aa.json.123.tmp" ] && [ -f "$proj/.git/method-settings-x.json" ]; then
  pass "the snapshots are pruned to the newest 20, the new one kept, other files left alone"
else
  fail "the snapshots are pruned to the newest 20, the new one kept, other files left alone" "$kept snapshots kept; temporary file there: $([ -f "$proj/.git/method-settings-00000000000000aa.json.123.tmp" ] && echo yes || echo no); other name there: $([ -f "$proj/.git/method-settings-x.json" ] && echo yes || echo no)"
fi
# the new session's snapshot is kept even when 20 others carry later times
# (a clock moved back, files restored from a backup)
PROJ="$proj" perl -e 'my $t = time + 3600; for my $i (100 .. 121) { my $p = sprintf "%s/.git/method-settings-%016x.json", $ENV{PROJ}, $i; open my $o, ">", $p or die; print $o "{}"; close $o; utime $t, $t, $p or die }'
start s32 startup
if [ -f "$(snap s32)" ]; then pass "a new session's snapshot is kept even when 20 others carry later times"; else fail "a new session's snapshot is kept even when 20 others carry later times" "it was pruned at once"; fi
# a checkout whose .git is a link to git's folder elsewhere: the snapshot
# is written in the folder the link names, and read back
mkdir -p "$work/store"
mv "$proj/.git" "$work/store/proj.git" && ln -s "$work/store/proj.git" "$proj/.git"
printf '{"theme": "dark", "env": {"FOO": "1"}}\n' >"$user"
start s33 startup
printf '{"theme": "light", "env": {"FOO": "1"}}\n' >"$user"
change "with .git a link, the snapshot is written where it points, so a theme change passes" s33 user_settings allow

drop_sandbox "$work" || true
echo "tests: guard (settings changes and skill hooks): $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
