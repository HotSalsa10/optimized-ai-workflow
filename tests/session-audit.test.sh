#!/usr/bin/env bash
# Tests for session-status's user-level audit (step 8.4; M164; docs/plans/
# step8.md S9; lib/session.pl's audit_lines): what the person's own Claude
# Code folder ($CLAUDE_CONFIG_DIR when set, ~/.claude otherwise) adds that
# can hide or replace the method, named by name only, each kind on a line
# of its own that says to tell the owner, names the folder and says what
# they do. The hook runs as tests/session-status.test.sh runs it, in a
# throwaway project laid out as sync lays it out, with the method's skills,
# and a home folder made fresh for each case. Each case runs alone under
# TEST_ONLY, so its plants (tests/plants/session-audit.sh) run only it.
# shellcheck disable=SC2016 # single-quoted perl code is expanded by perl
# shellcheck disable=SC2088 # a ~ in a quoted text is what the hook prints
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: session-status's user-level audit"
root=$(repo_root)
work=$(new_sandbox_dir) || abort_sandbox
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
unset CLAUDE_CONFIG_DIR
mkdir -p "$HOME"

# project NAME: the method laid out as sync lays it out, with three of the
# method's skills, one commit and a bare remote; prints its path
project() {
  p="$work/$1"
  rm -rf "$p" "$work/$1.git"
  mkdir -p "$p/scripts" "$p/.claude/hooks"
  cp -R "$root/method/scripts/method" "$p/scripts/method"
  cp -R "$root/method/.claude/hooks/method" "$p/.claude/hooks/method"
  cp "$root/method/settings.fragment.json" "$p/.claude/settings.json"
  for s in method-start method-plan method-finish; do skill "$p/.claude/skills/$s"; done
  for r in AGENTS.md SPEC.md TASKS.md DECISIONS.md ROADMAP.md RISKS.md CHANGELOG.md TESTS.md; do printf '# %s\n' "$r" >"$p/$r"; done
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
# skill DIR: a skill folder with its SKILL.md, the file the client reads
skill() { mkdir -p "$1" && printf -- '---\nname: x\ndescription: a skill\n---\nText.\n' >"$1/SKILL.md"; }
# hook DIR [VAR=VALUE...]: the hook in DIR as Claude Code runs it at a
# startup; sets out and code
hook() {
  d=$1
  shift
  in=$(printf '{"hook_event_name":"SessionStart","source":"startup","cwd":"%s"}' "$d")
  out=$(cd "$d" && printf '%s' "$in" | env -u CLAUDE_CODE_EXECPATH -u CLAUDE_CODE_EFFORT_LEVEL CLAUDE_PROJECT_DIR="$d" CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1 "$@" bash "$d/.claude/hooks/method/session-status.sh" 2>&1)
  code=$?
}
# home: a fresh, empty Claude Code folder; user JSON: its settings.json
home() { rm -rf "$HOME/.claude" && mkdir -p "$HOME/.claude"; }
user() { printf '%s\n' "$1" >"$HOME/.claude/settings.json"; }
# says TEXT...: one line says to tell the owner and holds each TEXT
says() {
  printf '%s\n' "$out" | grep -F 'session-status: LOOK - tell the owner: ' >"$work/tell.txt"
  s_hit=0
  while read -r l; do
    s_ok=1
    for t in "$@"; do case "$l" in *"$t"*) ;; *) s_ok=0 ;; esac; done
    [ "$s_ok" = 1 ] && s_hit=1
  done <"$work/tell.txt"
  [ "$s_hit" = 1 ] && [ "$code" -eq 0 ]
}
# holds TEXT: the output holds TEXT; quiet: no line says to tell the owner
holds() { printf '%s\n' "$out" | grep -F -q -- "$1"; }
quiet() { ! holds "tell the owner" && [ "$code" -eq 0 ]; }
# fits: every line within 240 bytes, the whole within 10 lines and 1,200
fits() {
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -le 10 ] && [ "$(printf '%s\n' "$out" | wc -c | tr -d ' ')" -le 1200 ] &&
    [ "$(printf '%s\n' "$out" | awk 'length($0) > 240' | wc -l | tr -d ' ')" = 0 ]
}
ok() { pass "$1"; }
no() { fail "$1" "exit $code: $out"; }
GIVE="by hand (Claude cannot): give steps"

pa=$(project audit) || abort_sandbox

n="an empty Claude Code folder gives no audit line"
if wanted "$n"; then
  home
  hook "$pa"
  if quiet; then ok "$n"; else no "$n"; fi
fi

n="a personal skill method-start that shadows the project's is named, with the folder and what to do"
if wanted "$n"; then
  home
  skill "$HOME/.claude/skills/method-start"
  hook "$pa"
  if says "personal skill method-start in ~/.claude/skills runs in place of the project's; they remove or rename it $GIVE"; then ok "$n"; else no "$n"; fi
fi

n="personal skills of other names, a personal command method-start and skills/synced/ give no audit line (F25, F27), and no personal name is shown"
if wanted "$n"; then
  home
  skill "$HOME/.claude/skills/deploy" && skill "$HOME/.claude/skills/method-other" && skill "$HOME/.claude/skills/synced/acme_x/method-start"
  mkdir -p "$HOME/.claude/commands" && printf 'mine\n' >"$HOME/.claude/commands/method-start.md"
  hook "$pa"
  if quiet && ! holds "method-other"; then ok "$n"; else no "$n"; fi
fi

n="a personal method-start folder with no SKILL.md gives no audit line (the client loads nothing from it)"
if wanted "$n"; then
  home
  mkdir -p "$HOME/.claude/skills/method-start" && printf 'notes\n' >"$HOME/.claude/skills/method-start/skill.txt"
  hook "$pa"
  if quiet; then ok "$n"; else no "$n"; fi
fi

n="a personal method- skill with no project counterpart is counted, not named, beside one that shadows"
if wanted "$n"; then
  home
  skill "$HOME/.claude/skills/method-other" && skill "$HOME/.claude/skills/method-plan"
  hook "$pa"
  if says "personal skill method-plan (+1 other personal method-*, not named) in" && ! holds "method-other"; then ok "$n"; else no "$n"; fi
fi

n="user claudeMdExcludes is named on a line that says to tell the owner"
if wanted "$n"; then
  home
  user '{"claudeMdExcludes":["**/x/**"]}'
  hook "$pa"
  if says "claudeMdExcludes in ~/.claude/settings.json keep the method out; they remove it $GIVE"; then ok "$n"; else no "$n"; fi
fi

n="user skillOverrides entries switching method-finish off and method-plan to user-invocable-only are named"
if wanted "$n"; then
  home
  user '{"skillOverrides":{"method-finish":"off","method-plan":"user-invocable-only"}}'
  hook "$pa"
  if says "skillOverrides method-finish, skillOverrides method-plan in ~/.claude/settings.json keep the method out; they remove them"; then ok "$n"; else no "$n"; fi
fi

n="skillOverrides set to on or name-only, or for another skill, gives no audit line"
if wanted "$n"; then
  home
  user '{"skillOverrides":{"method-finish":"on","method-start":"name-only","deploy":"off"}}'
  hook "$pa"
  if quiet; then ok "$n"; else no "$n"; fi
fi

n="a skillOverrides key with a non-ASCII letter, for a project skill of that name, is shown as it is"
if wanted "$n"; then
  home
  skill "$pa/.claude/skills/method-étα"
  user '{"skillOverrides":{"method-étα":"off"}}'
  hook "$pa"
  if says "skillOverrides method-étα in"; then ok "$n"; else no "$n"; fi
  rm -rf "$pa/.claude/skills/method-étα"
fi

n="a skillOverrides entry for a skill the project does not have gives no audit line, and its name is not shown"
if wanted "$n"; then
  home
  user '{"skillOverrides":{"method-mine":"off"}}'
  hook "$pa"
  if quiet && ! holds "method-mine"; then ok "$n"; else no "$n"; fi
fi

n="the agents-md plugin's instructionFiles at managed-only, under the key the client reads, is named"
if wanted "$n"; then
  home
  user '{"pluginConfigs":{"agents-md@builtin":{"options":{"instructionFiles":"managed-only"}}}}'
  hook "$pa"
  if says "agents-md instructionFiles managed-only in ~/.claude/settings.json keep the method out"; then ok "$n"; else no "$n"; fi
fi

n="the plugin's other key, in any letter case after @, and the option's older name at none are named too"
if wanted "$n"; then
  q=0
  for j in '{"pluginConfigs":{"cc-plugin-agents-md@Builtin":{"options":{"projectInstructions":"none"}}}}' \
    '{"pluginConfigs":{"agents-md@builtin":{"options":{"instructionFiles":"claude-md-or-agents-md","projectInstructions":"none"}}}}' \
    '{"pluginConfigs":{"agents-md@builtin":{"options":{"instructionFiles":"no-such-value","projectInstructions":"none"}}}}'; do
    home
    user "$j"
    hook "$pa"
    says "agents-md projectInstructions none in ~/.claude/settings.json keep the method out" || q=1
  done
  if [ "$q" = 0 ]; then ok "$n"; else no "$n"; fi
fi

n="the instruction-files setting gives no audit line under a key the client does not read, at another value, outside options, or when the client reads the other name"
if wanted "$n"; then
  q=0
  for j in '{"pluginConfigs":{"agents-md":{"options":{"instructionFiles":"managed-only"}}}}' \
    '{"pluginConfigs":{"agents-md@builtin":{"options":{"instructionFiles":"claude-md-and-agents-md"}}}}' \
    '{"pluginConfigs":{"agents-md@builtin":{"options":{"instructionFiles":"claude-md","projectInstructions":"none"}}}}' \
    '{"pluginConfigs":{"agents-md@builtin":{"options":{"projectInstructions":"managed-only"}}}}' \
    '{"pluginConfigs":{"agents-md@builtin":{"options":{"instructionFiles":"managed-only"}}}}' \
    '{"pluginConfigs":{"agents-md@builtin":{"instructionFiles":"managed-only"}}}'; do
    home
    user "$j"
    hook "$pa"
    # (the fifth is named: it is the control that this loop can see a line)
    case "$j" in
      *'agents-md@builtin":{"options":{"instructionFiles":"managed-only"}'*) says "agents-md instructionFiles managed-only" || q=1 ;;
      *) quiet || q=1 ;;
    esac
  done
  if [ "$q" = 0 ]; then ok "$n"; else no "$n"; fi
fi

n="a user UserPromptSubmit hook is named on its own line, with what to do, and a Stop hook is not"
if wanted "$n"; then
  home
  user '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"echo hi"}]}],"Stop":[{"hooks":[{"type":"command","command":"x"}]}]}}'
  hook "$pa"
  if says "hooks on UserPromptSubmit (1) in ~/.claude/settings.json run beside the guard or reach every prompt; they remove or keep them $GIVE" && ! holds "Stop ("; then ok "$n"; else no "$n"; fi
fi

n="a user PreToolUse hook is named once, on the audit's line, not again on the user-settings line"
if wanted "$n"; then
  home
  user '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"x"},{"type":"command","command":"y"}]}]}}'
  hook "$pa"
  if says "hooks on PreToolUse (2) in ~/.claude/settings.json" && ! holds "PreToolUse or PermissionRequest hook"; then ok "$n"; else no "$n"; fi
fi

n="hook entries the client drops (not an object, an unknown type, a type without its field) are not counted"
if wanted "$n"; then
  home
  user '{"hooks":{"UserPromptSubmit":[{"hooks":["x",{"type":"nope"},{"command":"y"},{"type":"command"},{"type":"http"},{"type":"prompt","prompt":5},{"type":"mcp_tool","server":"s"}]}]}}'
  hook "$pa"
  if quiet; then ok "$n"; else no "$n"; fi
fi

n="local skillOverrides and claudeMdExcludes are named once, as local settings, and the audit does not name them again"
if wanted "$n"; then
  home
  printf '{"skillOverrides":{"method-finish":"off"},"claudeMdExcludes":["x"]}\n' >"$pa/.claude/settings.local.json"
  hook "$pa"
  if holds ".claude/settings.local.json sets skillOverrides; claudeMdExcludes; it ranks above the method's settings" && quiet; then ok "$n"; else no "$n"; fi
  rm -f "$pa/.claude/settings.local.json"
fi

n="a skill folder's name with a control character comes out escaped"
if wanted "$n"; then
  home
  tab=$(printf '\t')
  skill "$pa/.claude/skills/method-x${tab}y" && skill "$HOME/.claude/skills/method-x${tab}y"
  hook "$pa"
  if says 'personal skill method-x\x09y in' && ! holds "method-x${tab}y"; then ok "$n"; else no "$n"; fi
  rm -rf "$pa/.claude/skills/method-x${tab}y"
fi

n="with CLAUDE_CONFIG_DIR set, the audit reads that folder's skills and settings, not ~/.claude"
if wanted "$n"; then
  home
  rm -rf "$work/cfg" && skill "$work/cfg/skills/method-finish" && skill "$HOME/.claude/skills/method-start"
  printf '{"claudeMdExcludes":["x"],"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"a"}]}]}}\n' >"$work/cfg/settings.json"
  user '{"skillOverrides":{"method-plan":"off"},"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"b"}]}]}}'
  hook "$pa" CLAUDE_CONFIG_DIR="$work/cfg"
  if says "personal skill method-finish in \$CLAUDE_CONFIG_DIR/skills" && says "claudeMdExcludes in \$CLAUDE_CONFIG_DIR/settings.json" &&
    says "hooks on UserPromptSubmit (1) in \$CLAUDE_CONFIG_DIR/settings.json" && ! holds "method-start in" && ! holds "method-plan" && ! holds "SessionStart ("; then
    ok "$n"
  else no "$n"; fi
fi

n="with lib/lock.pl not loading, the audit's own event list still names the UserPromptSubmit hook"
if wanted "$n"; then
  home
  pl=$(project nolock) || abort_sandbox
  printf 'die "planted\\n";\n' >"$pl/scripts/method/lib/lock.pl"
  user '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"echo hi"}]}]}}'
  hook "$pl"
  if says "hooks on UserPromptSubmit (1)"; then ok "$n"; else no "$n"; fi
fi

n="thousands of skillOverrides entries end in time, and a list of 5,000 names is built in time, counting the rest"
if wanted "$n"; then
  home
  perl -e 'print "{\"skillOverrides\":{" . join(",", map { "\"method-$_\":\"off\"" } 1 .. 5000) . "},\"claudeMdExcludes\":[\"x\"]}\n"' >"$HOME/.claude/settings.json"
  start=$(perl -e 'print time')
  hook "$pa"
  took=$(($(perl -e 'print time') - start))
  big=$(LIBDIR="$root/method/scripts/method/lib" perl -e 'require "$ENV{LIBDIR}/session.pl"; my $t = time; my $l = Session::listed("", [map { "method-$_" } 1 .. 5000], " in X keep the method out; they remove them"); print time - $t, "|", length $l, "|$l"')
  big_s=${big%%|*}
  case "$big" in *"more in X keep the method out; they remove them") big_ok=1 ;; *) big_ok=0 ;; esac
  if [ "$took" -le 8 ] && says "claudeMdExcludes in ~/.claude/settings.json" && holds "status: " && fits && [ "$big_s" -le 5 ] && [ "$big_ok" = 1 ]; then ok "$n ($took s, $big_s s)"; else no "$n (took $took s; list: $big)"; fi
fi

n="a long item does not hide the short ones after it, which are named, the long one counted"
if wanted "$n"; then
  out=$(LIBDIR="$root/method/scripts/method/lib" perl -e 'require "$ENV{LIBDIR}/session.pl"; print Session::listed("", ["first", "x" x 300, "maxEffortLevel low", "1 enabled plugin"], "; they change it", "; ")')
  code=0
  if says "first; maxEffortLevel low; 1 enabled plugin and 1 more; they change it" && fits; then ok "$n"; else no "$n"; fi
fi

n="a name cut at 40 bytes never ends in half an escape"
if wanted "$n"; then
  out=$(LIBDIR="$root/method/scripts/method/lib" perl -e 'require "$ENV{LIBDIR}/session.pl"; for my $k (25 .. 40) { print Session::shown_name("method-" . ("a" x $k) . "\t\t\t\tz"), "\n" }')
  if ! printf '%s\n' "$out" | grep -q -E '\\(x[0-9A-F]?)?\.\.\.$' && printf '%s\n' "$out" | grep -q '\.\.\.$'; then ok "$n"; else fail "$n" "$out"; fi
fi

n="a long shadowing name is cut, method-start is named first, and the line keeps what the owner does"
if wanted "$n"; then
  home
  lname="method-$(perl -e 'print "a" x 130')"
  skill "$pa/.claude/skills/$lname" && skill "$HOME/.claude/skills/$lname" && skill "$HOME/.claude/skills/method-start" && skill "$HOME/.claude/skills/method-zz"
  hook "$pa" CLAUDE_CONFIG_DIR="$HOME/.claude"
  if says "personal skills method-start, method-aaa" "they remove or rename them $GIVE" && fits; then ok "$n"; else no "$n"; fi
  rm -rf "$pa/.claude/skills/$lname"
fi

n="the user-settings line keeps what the owner does, however long its list"
if wanted "$n"; then
  home
  long=$(perl -e 'print join ",", map { "\"V" . ("x" x 40) . "_$_\":\"1\"" } 1 .. 12')
  user "{\"env\":{$long},\"enabledPlugins\":{\"p@q\":true},\"maxEffortLevel\":\"medium\"}"
  hook "$pa"
  if says "~/.claude/settings.json adds to every session: env Vxxx" "; they change it $GIVE" && fits; then ok "$n"; else no "$n"; fi
fi

n="the user-settings line names availableModels, a plugin and an effort cap together"
if wanted "$n"; then
  home
  user '{"availableModels":["x"],"enabledPlugins":{"a@b":true},"maxEffortLevel":"low"}'
  hook "$pa"
  if says "availableModels (lists add up); 1 enabled plugin (hooks not read); maxEffortLevel low, below xhigh; they change it $GIVE" && fits; then ok "$n"; else no "$n"; fi
fi

for where in "~/.claude" "\$CLAUDE_CONFIG_DIR"; do
  n="with every item at once ($where), each audit item is named, the user's and the project's own lines still come, all within the caps, the audit's lines first"
  wanted "$n" || continue
  home
  if [ "$where" = "~/.claude" ]; then dir="$HOME/.claude"; set --; else rm -rf "$work/cfg2"; dir="$work/cfg2"; set -- CLAUDE_CONFIG_DIR="$dir"; fi
  for s in method-start method-plan method-finish; do skill "$dir/skills/$s"; done
  printf '{"claudeMdExcludes":["x"],"skillOverrides":{"method-finish":"off"},"pluginConfigs":{"agents-md@builtin":{"options":{"instructionFiles":"managed-only"}}},"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"a"}]}],"PreToolUse":[{"hooks":[{"type":"command","command":"b"}]}]},"env":{"OTEL_A":"1","OTEL_B":"2"},"enabledPlugins":{"p@q":true}}\n' >"$dir/settings.json"
  # (and lines of the project's own: a dirty tree and local settings)
  printf 'x\n' >"$pa/new.txt" && printf '{"effortLevel":"high"}\n' >"$pa/.claude/settings.local.json"
  hook "$pa" "$@"
  rm -f "$pa/new.txt" "$pa/.claude/settings.local.json"
  missing=""
  for t in "method-start, method-finish, method-plan" "agents-md instructionFiles managed-only, claudeMdExcludes, skillOverrides method-finish" "PreToolUse (1), UserPromptSubmit (1)" \
    "adds to every session: env OTEL_A, OTEL_B; 1 enabled plugin" ".claude/settings.local.json sets effortLevel" "work: LOOK - "; do
    holds "$t" || missing="$missing [$t]"
  done
  first3=$(printf '%s\n' "$out" | sed -n 2,4p | grep -c '^session-status: LOOK - tell the owner: ')
  if [ -z "$missing" ] && fits && [ "$first3" = 3 ]; then ok "$n"; else fail "$n" "missing:$missing; $first3 audit lines first: $out"; fi
done

drop_sandbox "$work" || true
echo "tests: session-status's user-level audit: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
