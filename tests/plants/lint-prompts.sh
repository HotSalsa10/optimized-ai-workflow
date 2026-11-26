#!/usr/bin/env bash
# Plants for scripts/dev/lint-prompts.sh (step 6.1, M095): each pattern
# planted in a throwaway copy of the repo, in the method's real rules
# files or in a new agent or skill file, turns the lint red for its stated
# reason (the file, the line and the pattern); look-alikes planted the same
# way leave it green; a clean copy is green. Part two (step 6.2, M096): each
# agent-file rule broken in one of the method's gate files, a gate added
# to verdicts.txt with no file, a gate's file removed, and the fragment's
# model changed, each red for its reason. Part three (step 6.3): a skill
# folder added (as steps 6.4 and 6.5 will add them) with context: fork,
# with agent:, without method-, with a name other than its folder's, not
# on the method's skill list in protect.pl; a name on the list with no folder; each red
# for its reason, and a well-made listed skill green. Step 6.4: Bash and
# PowerShell in the architect's tools (not a gate), and a built skill's
# folder removed (method-plan; since 6.5 method-start too), each red. Step
# 6.6 (the review's F15, F17): Agent in a quoted tools list, Agent before a
# comment, Bash on a continued tools line, and context: fork before a
# comment, each red as YAML reads the value. Text that
# would trip the lint lives here, outside method/.claude/, which the lint
# does not read.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: lint-prompts"
rules=method/.claude/rules/method/method.md
owner=method/.claude/rules/method/owner.md

sb=$(make_sandbox) || abort_sandbox
expect_green "lint-prompts green on a clean copy" "$sb" bash scripts/dev/lint-prompts.sh
drop_sandbox "$sb"

# plant NAME FILE TEXT REASON: in a fresh copy, TEXT is added as a new line
# after FILE's first line (FILE made if missing, with TEXT as its only
# line); the lint must go red with REASON
plant() {
  sb=$(make_sandbox) || abort_sandbox
  mkdir -p "$sb/$(dirname "$2")"
  if [ -f "$sb/$2" ]; then
    PLANT=$3 perl -pi -e '$_ .= "$ENV{PLANT}\n" if $. == 1' "$sb/$2"
  else
    printf '%s\n' "$3" >"$sb/$2"
  fi
  if expect_landed "$1" grep -q -F -- "$3" "$sb/$2"; then
    expect_red "$1" "$sb" "$4" bash scripts/dev/lint-prompts.sh
  fi
  drop_sandbox "$sb"
}
emph() {
  printf 'the emphasis word %s in capitals' "$1"
}

plant "think carefully in method.md" "$rules" "Think carefully about the plan." "$rules:2: a \"think carefully\" or \"think step by step\" line (M095)"
plant "think step by step in owner.md" "$owner" "Let us think step by step." "$owner:2: a \"think carefully\" or \"think step by step\" line (M095)"
plant "a thinking tag in method.md" "$rules" "Write your notes inside <thinking> tags." "$rules:2: a fixed-format reasoning request"
plant "reason in this format, in a new agent file" "method/.claude/agents/method/method-x.md" "Reason in this format: claim, evidence, answer." "method/.claude/agents/method/method-x.md:1: a fixed-format reasoning request"
for w in IMPORTANT MUST NEVER ALWAYS REMEMBER; do
  plant "$w in method.md" "$rules" "You $w read the packet." "$rules:2: $(emph "$w")"
done
plant "DO NOT in owner.md" "$owner" "DO NOT guess." "$owner:2: $(emph 'DO NOT')"
plant "MUST in a new skill file" "method/.claude/skills/method-x/SKILL.md" "You MUST stop." "method/.claude/skills/method-x/SKILL.md:1: $(emph MUST)"

# an ID comment moved onto its sentence's line
sb=$(make_sandbox) || abort_sandbox
perl -0pi -e 's/<!-- M079 -->\n(A cloud session[^\n]*)/$1 <!-- M079 -->/' "$sb/$rules"
if expect_landed "an ID comment on its sentence's line" grep -q 'repository\. <!-- M079 -->$' "$sb/$rules"; then
  line=$(grep -n 'repository\. <!-- M079 -->$' "$sb/$rules" | cut -d: -f1)
  expect_red "an ID comment on its sentence's line in method.md" "$sb" "$rules:$line: a comment not alone on its line" bash scripts/dev/lint-prompts.sh
fi
drop_sandbox "$sb"

# an ID comment with spaces before it (the client keeps such a line)
sb=$(make_sandbox) || abort_sandbox
perl -pi -e 's/^<!-- M079 -->$/  <!-- M079 -->/' "$sb/$rules"
if expect_landed "an ID comment with spaces before it" grep -q '^  <!-- M079 -->$' "$sb/$rules"; then
  line=$(grep -n '^  <!-- M079 -->$' "$sb/$rules" | cut -d: -f1)
  expect_red "an ID comment with spaces before it in method.md" "$sb" "$rules:$line: a comment not alone on its line" bash scripts/dev/lint-prompts.sh
fi
drop_sandbox "$sb"

# look-alikes, all at once in the real rules file: green
sb=$(make_sandbox) || abort_sandbox
look='Never guess; you must check, always. Do not merge. FULL, LIGHT, CRITICAL, HIGH_RISK_PATHS, REQUEST CHANGES, MUSTARD, NEVER_SET, DO NOTHING. Check carefully, step by step. Use this format for the report: <summary>.'
PLANT=$look perl -pi -e '$_ .= "$ENV{PLANT}\n" if $. == 1' "$sb/$rules"
if expect_landed "look-alikes in method.md" grep -q -F -- "$look" "$sb/$rules"; then
  expect_green "lint-prompts green on look-alikes in method.md: the words in sentence case, the method's terms, longer words, careful wording, a report form" "$sb" bash scripts/dev/lint-prompts.sh
fi
drop_sandbox "$sb"

# part two (step 6.2, M096): the method's own gate files and verdicts.txt.
# change NAME FILE PERL REASON: in a fresh copy, PERL (a perl -0pi script)
# changes FILE, which must then differ from the repo's; the lint must go red
# with REASON
change() {
  sb=$(make_sandbox) || abort_sandbox
  perl -0pi -e "$3" "$sb/$2"
  # shellcheck disable=SC2016 # the $1 and $2 are the inner sh's arguments
  if expect_landed "$1" sh -c '! cmp -s "$1" "$2"' sh "$(repo_root)/$2" "$sb/$2"; then
    expect_red "$1" "$sb" "$4" bash scripts/dev/lint-prompts.sh
  fi
  drop_sandbox "$sb"
}
agents=method/.claude/agents/method
# shellcheck disable=SC2016 # perl code, expanded by perl
{
  change "no tools: line in the reviewer's file" "$agents/method-reviewer.md" 's/^tools:[^\n]*\n//m' "$agents/method-reviewer.md: no tools: line"
  change "Agent in the reviewer's tools" "$agents/method-reviewer.md" 's/^(tools:[^\n]*)$/$1, Agent/m' "$agents/method-reviewer.md: the tools: line lists Agent, a delegation tool"
  change "memory: in the tester's file" "$agents/method-tester.md" 's/^(effort:[^\n]*\n)/${1}memory: project\n/m' "$agents/method-tester.md: the key memory: is set"
  change "effort high in the security checker's file" "$agents/method-security-checker.md" 's/^effort: xhigh$/effort: high/m' "$agents/method-security-checker.md: the effort is \"high\", not xhigh"
  change "a model other than the fragment's in diagnose's file" "$agents/method-diagnose.md" 's/^model: [^\n]*$/model: opus/m' "$agents/method-diagnose.md: the model \"opus\" is not the settings fragment's model"
  change "the reporter's name not its file's" "$agents/method-reporter.md" 's/^name: method-reporter$/name: reporter/m' "$agents/method-reporter.md: the name \"reporter\" is not the file's name, method-reporter"
  change "Bash in the architect's tools (not a gate)" "$agents/method-architect.md" 's/^(tools:[^\n]*)$/$1, Bash/m' "$agents/method-architect.md: the tools: line lists Bash, but this is not a gate in verdicts.txt"
  change "PowerShell in the architect's tools (not a gate)" "$agents/method-architect.md" 's/^(tools:[^\n]*)$/$1, PowerShell/m' "$agents/method-architect.md: the tools: line lists PowerShell, but this is not a gate in verdicts.txt"
  # (step 6.6, the review's F15 and F17: the tools as YAML reads them)
  change "Agent in the reviewer's tools, the whole list quoted" "$agents/method-reviewer.md" 's/^tools: ([^\n]*)$/tools: "$1, Agent"/m' "$agents/method-reviewer.md: the tools: line lists Agent, a delegation tool"
  change "Agent before a comment in the tester's tools" "$agents/method-tester.md" 's/^(tools:[^\n]*)$/$1, Agent  # to fan out/m' "$agents/method-tester.md: the tools: line lists Agent, a delegation tool"
  change "Bash on a continued line of the architect's tools" "$agents/method-architect.md" 's/^(tools:[^\n]*)$/$1,\n  Bash/m' "$agents/method-architect.md: the tools: line lists Bash, but this is not a gate in verdicts.txt"
  change "context: fork before a comment in method-design's SKILL.md" method/.claude/skills/method-design/SKILL.md 's/^(name: method-design\n)/${1}context: fork  # keeps the main context small\n/m' \
    "method/.claude/skills/method-design/: SKILL.md sets context: fork"
  change "a gate in verdicts.txt with no file (a planner added)" method/scripts/method/verdicts.txt 's/(gate-verdict\tmethod-reporter\t[^\n]*\n)/${1}gate-verdict\tmethod-planner\tthe planner; its report opens with a verdict word\n/' \
    "the gate method-planner in verdicts.txt has no file method/.claude/agents/method/method-planner.md"
  change "the fragment's model changed (no agent file names it)" method/settings.fragment.json 's/"model": "[^"]*"/"model": "claude-other-1"/' \
    "the model \"$(perl -MJSON::PP -0ne 'print JSON::PP->new->decode($_)->{model}' "$(repo_root)/method/settings.fragment.json")\" is not the settings fragment's model, claude-other-1"
}
sb=$(make_sandbox) || abort_sandbox
rm -f "$sb/$agents/method-diagnose.md"
if expect_landed "diagnose's file removed" test ! -e "$sb/$agents/method-diagnose.md"; then
  expect_red "a gate in verdicts.txt with no file (diagnose's removed)" "$sb" "the gate method-diagnose in verdicts.txt has no file" bash scripts/dev/lint-prompts.sh
fi
drop_sandbox "$sb"

# part three (step 6.3; S8 and S10): skill folders against the method's skill list
# (protect.pl's @METHOD_SKILLS)
protect=method/scripts/method/lib/protect.pl
# skill NAME LIST DIR SKILL REASON: in a fresh copy, LIST (a name, or
# empty) is put on the method's skill list, and DIR (a folder under
# method/.claude/skills/, or empty) gets SKILL as its SKILL.md; the lint
# must go red with REASON, or stay green when REASON is "green"
skill() {
  sb=$(make_sandbox) || abort_sandbox
  if [ -n "$2" ]; then
    # shellcheck disable=SC2016 # perl code, expanded by perl
    N=$2 perl -pi -e 's/^(our \@METHOD_SKILLS = qw\([^)]*)\);$/$1 $ENV{N});/' "$sb/$protect"
  fi
  if [ -n "$3" ]; then
    mkdir -p "$sb/method/.claude/skills/$3" && printf '%s' "$4" >"$sb/method/.claude/skills/$3/SKILL.md"
  fi
  # shellcheck disable=SC2016 # the $1 to $4 are the inner sh's arguments
  if expect_landed "$1" sh -c '{ [ -z "$1" ] || grep -q "^our @METHOD_SKILLS = qw(.* $1);\$" "$2/$3"; } && { [ -z "$4" ] || [ -f "$2/method/.claude/skills/$4/SKILL.md" ]; }' sh "$2" "$sb" "$protect" "$3"; then
    if [ "$5" = green ]; then
      expect_green "$1" "$sb" bash scripts/dev/lint-prompts.sh
    else
      expect_red "$1" "$sb" "$5" bash scripts/dev/lint-prompts.sh
    fi
  fi
  drop_sandbox "$sb"
}
nl=$'\n'
ok_skill="---${nl}name: method-x${nl}description: A planted skill.${nl}---${nl}A step.${nl}"
skill "a listed skill, well made, stays green" method-x method-x "$ok_skill" green
skill "context: fork in a listed skill" method-x method-x "---${nl}name: method-x${nl}context: fork${nl}---${nl}A step.${nl}" \
  "method/.claude/skills/method-x/: SKILL.md sets context: fork"
skill "agent: in a listed skill" method-x method-x "---${nl}name: method-x${nl}agent: method-reviewer${nl}---${nl}A step.${nl}" \
  "method/.claude/skills/method-x/: SKILL.md sets the key agent:"
skill "a listed skill folder without method-" plan plan "---${nl}name: plan${nl}---${nl}A step.${nl}" \
  "method/.claude/skills/plan/: the folder's name does not start method-"
skill "a skill's name not its folder's" method-x method-x "---${nl}name: method-y${nl}---${nl}A step.${nl}" \
  "method/.claude/skills/method-x/: the name \"method-y\" in SKILL.md is not the folder's name, method-x"
skill "a skill folder missing from the method's skill list" "" method-x "$ok_skill" \
  "method/.claude/skills/method-x/: the folder is not on the method's skill list"
skill "a listed folder that does not exist" method-x "" "" \
  "the method's skill list (@METHOD_SKILLS in method/scripts/method/lib/protect.pl) names method-x, but method/.claude/skills/method-x/ does not exist"
# a built skill's folder removed (step 6.4: method-plan; step 6.5:
# method-start, the last name that was excepted as not built yet)
for s in method-plan method-start; do
  sb=$(make_sandbox) || abort_sandbox
  rm -rf "$sb/method/.claude/skills/$s"
  if expect_landed "$s's folder removed" test ! -e "$sb/method/.claude/skills/$s"; then
    expect_red "a built skill's folder removed ($s)" "$sb" "the method's skill list (@METHOD_SKILLS in method/scripts/method/lib/protect.pl) names $s, but method/.claude/skills/$s/ does not exist" bash scripts/dev/lint-prompts.sh
  fi
  drop_sandbox "$sb"
done

# method-setup dropped from the method's skill list (step 7.5): its folder
# is then a method- skill the list does not name
sb=$(make_sandbox) || abort_sandbox
# shellcheck disable=SC2016 # perl code, expanded by perl
perl -pi -e 's/^(our \@METHOD_SKILLS = qw\(.*) method-setup(.*\);)$/$1$2/' "$sb/$protect"
# shellcheck disable=SC2016 # the $1 is the inner sh's argument
if expect_landed "method-setup dropped from the list" sh -c '! grep -q "^our @METHOD_SKILLS = qw(.*method-setup.*);\$" "$1" && grep -q "^our @METHOD_SKILLS = qw(" "$1"' sh "$sb/$protect"; then
  expect_red "method-setup dropped from the method's skill list" "$sb" "method/.claude/skills/method-setup/: the folder is not on the method's skill list" bash scripts/dev/lint-prompts.sh
fi
drop_sandbox "$sb"

echo "plants: lint-prompts: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
