#!/usr/bin/env bash
# Plants for tests/settings.test.sh (step 5.3): each planted defect in the
# settings fragment, or in this repo's own settings, must turn the test red
# for its stated reason, and a clean copy must stay green. Each plant runs
# in a throwaway copy of the repo.
# shellcheck disable=SC2016 # the plants are perl code: perl expands them
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: settings"

# plant NAME FILE REASON CODE: in a fresh copy, CODE (perl, on $d, the
# decoded FILE) changes FILE; the settings test must then fail, and its
# output must hold REASON.
plant() {
  name=$1
  file=$2
  reason=$3
  code=$4
  sb=$(make_sandbox) || abort_sandbox
  if ! (cd "$sb" && perl -MJSON::PP -e 'my ($f, $c) = @ARGV; open my $h, "<", $f or die; my $d = JSON::PP->new->decode(do { local $/; <$h> }); close $h; eval "$c; 1" or die $@; open $h, ">", $f or die; print $h JSON::PP->new->canonical->pretty->encode($d); close $h' "$file" "$code"); then
    fail "$name: the plant did not apply, so the check result would mean nothing"
  else
    out=$(cd "$sb" && bash tests/settings.test.sh 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then
      fail "$name: the settings test stayed green" "$out"
    elif ! printf '%s\n' "$out" | grep -F -q -- "$reason"; then
      fail "$name: went red, but not for the stated reason ('$reason')" "$(printf '%s\n' "$out" | grep FAIL)"
    else
      pass "$name"
    fi
  fi
  drop_sandbox "$sb" || true
}

frag=method/settings.fragment.json
sb=$(make_sandbox) || abort_sandbox
expect_green "settings green on a clean copy" "$sb" bash tests/settings.test.sh
drop_sandbox "$sb" || true

plant "another model" "$frag" 'model is "claude-sonnet-5-5", not "claude-opus-5-5"' '$d->{model} = "claude-sonnet-5-5"'
plant "a model allowlist written as a string" "$frag" "availableModels is not a list" '$d->{availableModels} = "claude-opus-5-5"'
plant "enforceAvailableModels as the string true" "$frag" "enforceAvailableModels is not true or false (a JSON boolean)" '$d->{enforceAvailableModels} = "true"'
plant "effort high" "$frag" 'effortLevel is "high", not "xhigh"' '$d->{effortLevel} = "high"'
plant "attribution without sessionUrl" "$frag" "attribution.sessionUrl is missing" 'delete $d->{attribution}{sessionUrl}'
plant "attribution with a commit trailer" "$frag" 'attribution.commit is "Co-Authored-By: x", not ""' '$d->{attribution}{commit} = "Co-Authored-By: x"'
plant "auto memory on" "$frag" "autoMemoryEnabled is true, not false" '$d->{autoMemoryEnabled} = JSON::PP::true()'
plant "skill shell lines on" "$frag" "disableSkillShellExecution is false, not true" '$d->{disableSkillShellExecution} = JSON::PP::false()'
plant "code-review visible to Claude" "$frag" 'skillOverrides.code-review is "on", not "user-invocable-only"' '$d->{skillOverrides}{"code-review"} = "on"'
plant "hooks switched off" "$frag" "disableAllHooks is true, not false" '$d->{disableAllHooks} = JSON::PP::true()'
plant "a minimum version that is not the floor" "$frag" 'minimumVersion is "2.1.295"' '$d->{minimumVersion} = "2.1.295"'
plant "the advisor not switched off" "$frag" 'env.CLAUDE_CODE_DISABLE_ADVISOR_TOOL is "0", not "1"' '$d->{env}{CLAUDE_CODE_DISABLE_ADVISOR_TOOL} = "0"'
plant "the advisor variable as a number" "$frag" "env.CLAUDE_CODE_DISABLE_ADVISOR_TOOL is not a string" '$d->{env}{CLAUDE_CODE_DISABLE_ADVISOR_TOOL} = 1'
plant "the PowerShell tool variable missing" "$frag" "env.CLAUDE_CODE_USE_POWERSHELL_TOOL is missing" 'delete $d->{env}{CLAUDE_CODE_USE_POWERSHELL_TOOL}'
plant "model missing" "$frag" "model is missing" 'delete $d->{model}'
plant "a key the plan does not name" "$frag" "unknown keys: outputStyle" '$d->{outputStyle} = "x"'
plant "the effort variable set" "$frag" "it sets env.CLAUDE_CODE_EFFORT_LEVEL" '$d->{env}{CLAUDE_CODE_EFFORT_LEVEL} = "max"'
plant "auto-continue set" "$frag" "it sets autoContinueAtUsageLimit" '$d->{autoContinueAtUsageLimit} = JSON::PP::true()'
plant "bypassPermissions as the default mode" "$frag" "it sets permissions.defaultMode bypassPermissions" '$d->{permissions} = {defaultMode => "bypassPermissions"}'
plant "workflows switched on" "$frag" "it sets enableWorkflows" '$d->{enableWorkflows} = JSON::PP::true()'
plant "subprocess scrubbing set" "$frag" "it sets env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB" '$d->{env}{CLAUDE_CODE_SUBPROCESS_ENV_SCRUB} = "1"'
plant "the remote variable set" "$frag" "it sets env.CLAUDE_CODE_REMOTE" '$d->{env}{CLAUDE_CODE_REMOTE} = "1"'
plant "workflows switched off by its key" "$frag" "it sets disableWorkflows" '$d->{disableWorkflows} = JSON::PP::true()'
plant "auto as the default mode" .claude/settings.json "it sets permissions.defaultMode auto" '$d->{permissions} = {defaultMode => "auto"}'
plant "permissions as a string (the client skips the whole file)" "$frag" "permissions is not an object" '$d->{permissions} = "x"'
plant "a deny list as a string" "$frag" "permissions.deny is not a list" '$d->{permissions}{deny} = "mcp__*__merge_pull_request"'
plant "an allow list (permissions hold the deny list only)" "$frag" "permissions has keys the plan does not set: allow" '$d->{permissions}{allow} = ["Bash(*)"]'
# each deny entry dropped (5.8, M139), and the merge entry for one server only
for t in merge_pull_request enable_pr_auto_merge create_session send_message create_trigger fire_trigger update_trigger unarchive_session; do
  plant "the deny entry for $t dropped" "$frag" "permissions.deny is not exactly" "\$d->{permissions}{deny} = [grep { \$_ ne 'mcp__*__$t' } @{ \$d->{permissions}{deny} }]"
done
plant "the merge tool denied on one server name only" "$frag" "permissions.deny is not exactly" '$_ = "mcp__github__merge_pull_request" for grep { $_ eq "mcp__*__merge_pull_request" } @{ $d->{permissions}{deny} }'
plant "an env variable the plan does not set" "$frag" "env has keys the plan does not set: EXTRA_X" '$d->{env}{EXTRA_X} = "1"'
plant "a second model allowed" "$frag" "availableModels is not exactly" '$d->{availableModels} = ["claude-opus-5-5", "claude-sonnet-5-5"]'
plant "this repo's settings turn auto memory on" .claude/settings.json "they differ on: autoMemoryEnabled" '$d->{autoMemoryEnabled} = JSON::PP::true()'
plant "this repo's PowerShell variable differs" .claude/settings.json "they differ on: env.CLAUDE_CODE_USE_POWERSHELL_TOOL" '$d->{env}{CLAUDE_CODE_USE_POWERSHELL_TOOL} = "1"'
plant "this repo's settings set the effort variable" .claude/settings.json "it sets env.CLAUDE_CODE_EFFORT_LEVEL" '$d->{env}{CLAUDE_CODE_EFFORT_LEVEL} = "max"'
plant "this repo's effort differs from the fragment's" .claude/settings.json "they differ on: effortLevel" '$d->{effortLevel} = "high"'
plant "session-status on startup only" "$frag" "it is not registered so" '$d->{hooks}{SessionStart}[0]{matcher} = "startup"'
plant "no hooks at all" "$frag" "it has no hooks key" 'delete $d->{hooks}'
ok_hook='BASH_ENV= ENV= bash -p "$CLAUDE_PROJECT_DIR/.claude/hooks/method/guard.sh"'
export OK_HOOK="$ok_hook"
plant "a fourth hook script" "$frag" "PreToolUse: BASH_ENV= ENV= bash" '$d->{hooks}{PreToolUse} = [{matcher => "Bash", hooks => [{type => "command", command => q{BASH_ENV= ENV= bash -p "$CLAUDE_PROJECT_DIR/.claude/hooks/method/extra.sh"}, onFailure => "block"}]}]'
plant "a hook path not in quotes" "$frag" 'PreToolUse: BASH_ENV= ENV= bash -p $CLAUDE_PROJECT_DIR' '$d->{hooks}{PreToolUse} = [{matcher => "Bash", hooks => [{type => "command", command => q{BASH_ENV= ENV= bash -p $CLAUDE_PROJECT_DIR/.claude/hooks/method/guard.sh}, onFailure => "block"}]}]'
plant "a hook without the BASH_ENV= ENV= prefix" "$frag" 'PreToolUse: bash -p "$CLAUDE_PROJECT_DIR' '$d->{hooks}{PreToolUse} = [{matcher => "Bash", hooks => [{type => "command", command => q{bash -p "$CLAUDE_PROJECT_DIR/.claude/hooks/method/guard.sh"}, onFailure => "block"}]}]'
plant "a hook without bash -p" "$frag" 'PreToolUse: BASH_ENV= ENV= bash "$CLAUDE_PROJECT_DIR' '$d->{hooks}{PreToolUse} = [{matcher => "Bash", hooks => [{type => "command", command => q{BASH_ENV= ENV= bash "$CLAUDE_PROJECT_DIR/.claude/hooks/method/guard.sh"}, onFailure => "block"}]}]'
plant "onFailure on SubagentStop" "$frag" "onFailure on SubagentStop" '$d->{hooks}{SubagentStop} = [{matcher => "reviewer", hooks => [{type => "command", command => $ENV{OK_HOOK}, onFailure => "block"}]}]'
plant "onFailure on SessionStart" "$frag" "onFailure on SessionStart" '$d->{hooks}{SessionStart}[0]{hooks}[0]{onFailure} = "block"'
plant "session-status with a 1 s time limit" "$frag" "its timeout is 1" '$d->{hooks}{SessionStart}[0]{hooks}[0]{timeout} = 1'
plant "session-status with no time limit" "$frag" "its timeout is not set" 'delete $d->{hooks}{SessionStart}[0]{hooks}[0]{timeout}'
plant "session-status's time limit written as a string (the client drops the hook: METHOD-ACTIVE never arrives)" "$frag" 'its timeout is "30"' '$d->{hooks}{SessionStart}[0]{hooks}[0]{timeout} = "30"'
plant "the guard on outside tools with a 600 s time limit" "$frag" "FAIL  guard.sh on PreToolUse for ^mcp__ has a 30 s time limit" '$d->{hooks}{PreToolUse}[1]{hooks}[0]{timeout} = 600'
plant "the guard on the built-in tools with no time limit" "$frag" "Task has a 30 s time limit" 'delete $d->{hooks}{PreToolUse}[0]{hooks}[0]{timeout}'
plant "the guard without onFailure block" "$frag" 'no onFailure "block" on PreToolUse' '$d->{hooks}{PreToolUse} = [{matcher => "Bash", hooks => [{type => "command", command => $ENV{OK_HOOK}}]}]'
plant "a stray .sh in the hooks folder" method/settings.fragment.json "also extra.sh" 'open my $x, ">", "method/.claude/hooks/method/extra.sh" or die'

# two plants outside a JSON file: the floor raised with the fragment left
# as it was, and a committed settings.local.json
sb=$(make_sandbox) || abort_sandbox
sed 's/^claude_code_min=.*/claude_code_min=2.1.999/' "$sb/method/scripts/method/REQUIRES" >"$sb/req.tmp" && mv "$sb/req.tmp" "$sb/method/scripts/method/REQUIRES"
out=$(cd "$sb" && bash tests/settings.test.sh 2>&1)
case "$out" in *'minimumVersion is "2.1.316", not "2.1.999"'*) pass "the floor raised in REQUIRES with the fragment left as it was" ;; *) fail "the floor raised in REQUIRES: the settings test did not go red for it" "$(printf '%s\n' "$out" | grep FAIL | head -3)" ;; esac
drop_sandbox "$sb" || true
sb=$(make_sandbox) || abort_sandbox
printf '{"model":"claude-opus-5-5"}\n' >"$sb/.claude/settings.local.json"
(cd "$sb" && git add -f .claude/settings.local.json 2>/dev/null)
out=$(cd "$sb" && bash tests/settings.test.sh 2>&1)
case "$out" in *"committed: .claude/settings.local.json"*) pass "a committed settings.local.json" ;; *) fail "a committed settings.local.json: the settings test did not go red for it" "$(printf '%s\n' "$out" | grep FAIL | head -3)" ;; esac
drop_sandbox "$sb" || true
# four more outside a JSON file (review round 2): settings behind a
# committed link, in another letter case, in a nested folder, and an env
# name in lower case
# file_plant NAME REASON SETUP: SETUP (sh, in a fresh copy) commits
# something; the settings test must then go red with REASON
file_plant() {
  sb=$(make_sandbox) || abort_sandbox
  if ! (cd "$sb" && sh -c "$3" >/dev/null 2>&1); then
    fail "$1: the plant did not apply"
  else
    out=$(cd "$sb" && bash tests/settings.test.sh 2>&1)
    case "$out" in *"$2"*) pass "$1" ;; *) fail "$1: the settings test did not go red for it" "$(printf '%s\n' "$out" | grep FAIL | head -3)" ;; esac
  fi
  drop_sandbox "$sb" || true
}
file_plant "a committed link named .claude" "committed links: sub/.claude" 'mkdir -p sub conf && printf "{}\n" >conf/settings.json && ln -s ../conf sub/.claude && git add conf sub/.claude'
file_plant "a committed settings.local.json in another letter case" "committed: .Claude/Settings.Local.JSON" 'mkdir -p .Claude && printf "{}\n" >.Claude/Settings.Local.JSON && git add -f .Claude/Settings.Local.JSON'
file_plant "a never-set key in a nested folder's committed settings" "sub/.claude/settings.json sets nothing on the never-set list" 'mkdir -p sub/.claude && printf "{\"autoContinueAtUsageLimit\":true}\n" >sub/.claude/settings.json && git add -f sub/.claude/settings.json'
file_plant "a never-set env variable in lower case in this repo's settings" "it sets env.claude_code_effort_level" 'perl -MJSON::PP -i -0pe "my \$d = decode_json(\$_); \$d->{env}{claude_code_effort_level} = q(low); \$_ = JSON::PP->new->canonical->pretty->encode(\$d)" .claude/settings.json && git add .claude/settings.json'

echo "plants: settings: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
