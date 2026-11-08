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
plant "this repo's settings set the effort variable" .claude/settings.json "it sets env.CLAUDE_CODE_EFFORT_LEVEL" '$d->{env}{CLAUDE_CODE_EFFORT_LEVEL} = "max"'
plant "this repo's effort differs from the fragment's" .claude/settings.json "they differ on: effortLevel" '$d->{effortLevel} = "high"'
ok_hook='BASH_ENV= ENV= bash "$CLAUDE_PROJECT_DIR/.claude/hooks/method/guard.sh"'
export OK_HOOK="$ok_hook"
plant "a fourth hook script" "$frag" "PreToolUse: BASH_ENV= ENV= bash" '$d->{hooks} = {PreToolUse => [{matcher => "Bash", hooks => [{type => "command", command => q{BASH_ENV= ENV= bash "$CLAUDE_PROJECT_DIR/.claude/hooks/method/extra.sh"}, onFailure => "block"}]}]}'
plant "a hook path not in quotes" "$frag" 'PreToolUse: BASH_ENV= ENV= bash $CLAUDE_PROJECT_DIR' '$d->{hooks} = {PreToolUse => [{matcher => "Bash", hooks => [{type => "command", command => q{BASH_ENV= ENV= bash $CLAUDE_PROJECT_DIR/.claude/hooks/method/guard.sh}, onFailure => "block"}]}]}'
plant "a hook without the BASH_ENV= ENV= prefix" "$frag" 'PreToolUse: bash "$CLAUDE_PROJECT_DIR' '$d->{hooks} = {PreToolUse => [{matcher => "Bash", hooks => [{type => "command", command => q{bash "$CLAUDE_PROJECT_DIR/.claude/hooks/method/guard.sh"}, onFailure => "block"}]}]}'
plant "onFailure on SubagentStop" "$frag" "onFailure on SubagentStop" '$d->{hooks} = {SubagentStop => [{matcher => "reviewer", hooks => [{type => "command", command => $ENV{OK_HOOK}, onFailure => "block"}]}]}'
plant "the guard without onFailure block" "$frag" 'no onFailure "block" on PreToolUse' '$d->{hooks} = {PreToolUse => [{matcher => "Bash", hooks => [{type => "command", command => $ENV{OK_HOOK}}]}]}'

echo "plants: settings: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
