#!/usr/bin/env bash
# Plants for scripts/dev/lint-prompts.sh (step 6.1, M095): each pattern
# planted in a throwaway copy of the repo, in the method's real rules
# files or in a new agent or skill file, turns the lint red for its stated
# reason (the file, the line and the pattern); look-alikes planted the same
# way leave it green; a clean copy is green. Part two (step 6.2, M096): each
# agent-file rule broken in one of the method's gate files, a gate added
# to verdicts.txt with no file, a gate's file removed, and the fragment's
# model changed, each red for its reason. Text that would trip the lint
# lives here, outside method/.claude/, which the lint does not read.
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

echo "plants: lint-prompts: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
