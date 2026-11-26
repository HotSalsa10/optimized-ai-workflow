#!/usr/bin/env bash
# Tests scripts/dev/lint-prompts.sh (step 6.1, M095; step 6.2, M096; step
# 6.3, skill folders): in small throwaway repositories holding only the
# lint and the text it reads (and, for parts two and three, the
# vocabulary, the settings fragment, the method's agent files and the method's
# skill list in protect.pl), each pattern turns it red with its file, line
# and reason, each look-alike stays green, and its own counts are read
# strictly. Part two: each agent-file rule red with the file and the reason,
# a gate with no file red, and what the lint reads missing red, never a
# pass. Part three: each skill-folder rule red with the folder and the
# reason. The lint on this repo's own files is run by validate.sh;
# tests/plants/lint-prompts.sh plants each pattern there.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: lint-prompts"
root=$(repo_root)
work=$(new_sandbox_dir) || abort_sandbox
trap 'drop_sandbox "$work" || true' EXIT
k=0

# mini: makes a new small repository with the lint, a rules file that
# passes, what part two reads (step 6.2): the vocabulary and its reader
# (the gates), the settings fragment (the model) and the method's agent
# files, which pass; and what part three reads (step 6.3): protect.pl with
# the method's skill list, the git.pl it loads, and the method's skill folders
# (since step 6.4), which pass; sets m to its path (not in a
# subshell, so k counts on)
mini() {
  k=$((k + 1))
  m="$work/m$k"
  mkdir -p "$m/scripts/dev/lib" "$m/method/.claude/rules/method" "$m/method/.claude/agents/method" "$m/method/scripts/method/lib" || return 1
  cp "$root/scripts/dev/lint-prompts.sh" "$m/scripts/dev/" &&
    cp "$root/scripts/dev/lib/prompts.pl" "$m/scripts/dev/lib/" &&
    cp "$root/method/scripts/method/verdicts.txt" "$m/method/scripts/method/" &&
    cp "$root/method/scripts/method/lib/verdicts.pl" "$m/method/scripts/method/lib/" &&
    cp "$root/method/scripts/method/lib/protect.pl" "$root/method/scripts/method/lib/git.pl" "$m/method/scripts/method/lib/" &&
    cp "$root/method/settings.fragment.json" "$m/method/" &&
    cp "$root"/method/.claude/agents/method/*.md "$m/method/.claude/agents/method/" &&
    cp -R "$root/method/.claude/skills" "$m/method/.claude/" &&
    printf '# Rules\n\n<!-- M001 -->\nA plain rule.\n' >"$m/method/.claude/rules/method/base.md" &&
    (cd "$m" && git init -q .)
}
# the files a mini repository holds before a case adds one: the rules file,
# the method's agent files and its skill folders' .md files
base_files=$(($(find "$root/method/.claude/agents/method" "$root/method/.claude/skills" -name '*.md' -type f | wc -l) + 1))

# list_skill NAME: puts NAME on the mini repository's skill list
# (protect.pl's @METHOD_SKILLS)
list_skill() {
  # shellcheck disable=SC2016 # perl code, expanded by perl
  N=$1 perl -pi -e 's/^(our \@METHOD_SKILLS = qw\([^)]*)\);$/$1 $ENV{N});/' "$m/method/scripts/method/lib/protect.pl" &&
    grep -q "^our @METHOD_SKILLS = qw(.* $1);\$" "$m/method/scripts/method/lib/protect.pl"
}
# put FILE TEXT: writes TEXT to FILE in the mini repository; a file in a
# skill folder (method/.claude/skills/DIR/...) also puts DIR on its
# skill list, unless NOLIST is set (step 6.3)
put() {
  mkdir -p "$m/$(dirname "$1")" && printf '%s' "$2" >"$m/$1" || return 1
  case "$1" in
    method/.claude/skills/*/*)
      d=${1#method/.claude/skills/}
      [ -n "${NOLIST:-}" ] || list_skill "${d%%/*}"
      ;;
  esac
}

# lint_red NAME FILE TEXT WANT [N]: FILE (under method/.claude/) holding TEXT
# turns the lint red (exit 1) with WANT in its output, and N problems (1)
lint_red() {
  wanted "$1" || return 0
  mini || abort_sandbox
  put "$2" "$3" || abort_sandbox
  out=$(cd "$m" && bash scripts/dev/lint-prompts.sh 2>&1)
  code=$?
  if [ "$code" -eq 1 ] && printf '%s\n' "$out" | grep -F -q -- "$4" && printf '%s\n' "$out" | grep -q "^lint-prompts: FAIL - ${5:-1} problem(s) in $((base_files + 1)) prompt files\$"; then
    pass "$1"
  else
    fail "$1: expected exit 1, ${5:-1} problem(s), and '$4'; got exit $code" "$out"
  fi
}

# lint_green NAME FILE TEXT [SKILL]: FILE holding TEXT leaves the lint
# green; with SKILL, SKILL is also the SKILL.md of FILE's folder
lint_green() {
  wanted "$1" || return 0
  mini || abort_sandbox
  put "$2" "$3" || abort_sandbox
  if [ -n "${4:-}" ]; then put "$(dirname "$2")/SKILL.md" "$4" || abort_sandbox; fi
  out=$(cd "$m" && bash scripts/dev/lint-prompts.sh 2>&1)
  code=$?
  if [ "$code" -eq 0 ] && printf '%s\n' "$out" | grep -q '^lint-prompts: PASS - examined [0-9]* prompt files'; then
    pass "$1"
  else
    fail "$1: expected the lint to stay green; got exit $code" "$out"
  fi
}

R=method/.claude/rules/method/x.md
A=method/.claude/agents/method/method-x.md
S=method/.claude/skills/method-x/SKILL.md
think='a "think carefully" or "think step by step" line (M095)'
format='a fixed-format reasoning request'
shared='a comment not alone on its line'
nl=$'\n'
# a drafting agent's file that passes part two (8 lines: its frontmatter
# and one body line), with the fragment's model (read here, so the ID
# has one home)
model=$(perl -MJSON::PP -0ne 'print JSON::PP->new->decode($_)->{model}' "$root/method/settings.fragment.json")
# fm LINE...: an agent file's frontmatter of those lines, then a body line
fm() {
  printf -- '---\n'
  printf '%s\n' "$@"
  printf -- '---\nA body.\n'
}
hdr=$(fm "name: method-x" "description: x" "model: $model" "effort: xhigh" "tools: Read, Grep, Glob")$nl
# a skill's frontmatter that passes part three (4 lines; the case puts the
# folder on the mini repository's skill list)
shdr=$'---\nname: method-x\ndescription: x\n---\n'

# --- each pattern, red: the file, the line and the reason ---
lint_red "think carefully in a rules file" "$R" $'# Rules\n\nThink carefully before you answer.\n' "lint-prompts: $R:3: $think"
lint_red "think step by step in an agent file" "$A" "${hdr}Let us think step by step.$nl" "lint-prompts: $A:9: $think"
lint_red "think step-by-step, hyphened, in a skill" "$S" "$shdr"$'Always think\tstep-by-step here.\n' "lint-prompts: $S:5: $think"
lint_red "think very carefully" "$R" $'Think very carefully.\n' "lint-prompts: $R:1: $think"
lint_red "a thinking tag" "$R" $'Put your notes in <thinking> tags.\n' "lint-prompts: $R:1: $format"
lint_red "a closing reasoning tag" "$A" "${hdr}Then close with </reasoning>.$nl" "lint-prompts: $A:9: $format"
lint_red "a scratchpad tag with an attribute" "$S" "$shdr"$'Use <scratchpad id="1"> first.\n' "lint-prompts: $S:5: $format"
lint_red "reason in this format" "$R" $'Reason in this format: premise, step, answer.\n' "lint-prompts: $R:1: $format"
lint_red "think using the following structure" "$S" "$shdr"$'Think using the following structure.\n' "lint-prompts: $S:5: $format"
lint_red "a format for your reasoning" "$A" "${hdr}Use this format for your reasoning.$nl" "lint-prompts: $A:9: $format"
lint_red "the emphasis word IMPORTANT" "$R" $'IMPORTANT: read the packet.\n' "lint-prompts: $R:1: the emphasis word IMPORTANT in capitals"
lint_red "the emphasis word MUST" "$R" $'You MUST read the packet.\n' "lint-prompts: $R:1: the emphasis word MUST in capitals"
lint_red "the emphasis word NEVER in bold" "$A" "${hdr}**NEVER** edit files.$nl" "lint-prompts: $A:9: the emphasis word NEVER in capitals"
lint_red "the emphasis word ALWAYS" "$S" "$shdr"$'ALWAYS run the checks.\n' "lint-prompts: $S:5: the emphasis word ALWAYS in capitals"
lint_red "the emphasis word REMEMBER" "$R" $'REMEMBER the stops.\n' "lint-prompts: $R:1: the emphasis word REMEMBER in capitals"
lint_red "the emphasis words DO NOT" "$R" $'DO NOT merge.\n' "lint-prompts: $R:1: the emphasis word DO NOT in capitals"
lint_red "the emphasis words DO NOT across a tab" "$R" $'Please DO\tNOT merge.\n' "lint-prompts: $R:1: the emphasis word DO NOT in capitals"
lint_red "the emphasis word MUST at the end of a line" "$R" $'This you MUST\n' "lint-prompts: $R:1: the emphasis word MUST in capitals"
lint_red "a comment after the text on its line" "$R" $'# Rules\n\nA rule. <!-- M001 -->\n' "lint-prompts: $R:3: $shared"
lint_red "a comment before the text on its line" "$R" $'<!-- M001 --> A rule.\n' "lint-prompts: $R:1: $shared"
lint_red "a comment over two lines" "$R" $'<!-- M001\nM002 -->\nA rule.\n' "lint-prompts: $R:1: $shared" 2
lint_red "two comments on one line" "$R" $'<!-- M001 --><!-- M002 -->\nA rule.\n' "lint-prompts: $R:1: $shared"
lint_red "a comment's end alone after text" "$R" $'A rule. -->\n' "lint-prompts: $R:1: $shared"
lint_red "a rules file in a deeper folder" "method/.claude/rules/method/more/y.md" $'A rule. <!-- M001 -->\n' "lint-prompts: method/.claude/rules/method/more/y.md:1: $shared"

# --- look-alikes, green ---
lint_green "the words in lower or sentence case pass" "$R" $'Never edit files. You must read it. Always run it. Remember the stops. Do not merge. Important: read it. never, must, always, remember, do not.\n'
lint_green "the method's own terms in capitals pass" "$R" $'FULL, LIGHT, CRITICAL, VERIFIED, INFERRED, READY, NOT READY, HIGH_RISK_PATHS, APPROVE, REQUEST CHANGES, REJECT, ESCALATE, VALID, INVALID, INCOMPLETE, TESTS PASS, TESTS FAIL, ROOT CAUSE, END-VERDICT, METHOD-ACTIVE, [EYES], [CHECK], [CREDENTIAL], [AUTHORITY].\n'
lint_green "the words inside a longer word or an identifier pass" "$A" "$hdr"$'MUSTARD, NEVER_SET, ALWAYS-ON, X-MUST, REMEMBERED, IMPORTANTLY, DO NOTHING, DONOT, MUST1.\n'
lint_green "careful wording without the phrases passes" "$S" "$shdr"$'Check carefully. Go step by step. Think it through. The thinking budget. Re-think the plan. Reasoning in plain words.\n'
lint_green "a report form and other tags pass" "$A" "$hdr"$'Use this format for the report: <summary>, then `END-VERDICT <tree>`.\n'
lint_red "a comment with spaces before it (the client keeps it)" "$R" $'# Rules\n\n  <!-- M001 -->\nA rule.\n' "lint-prompts: $R:3: $shared"
lint_red "a comment with a space after it" "$R" $'<!-- M001 --> \nA rule.\n' "lint-prompts: $R:1: $shared"
lint_green "comments alone on their lines pass, an empty one too" "$R" $'# Rules\n\n<!-- M001 M002 -->\nA rule.\n<!---->\nAnother.\n'
lint_green "a comment beside text outside the rules files passes (only rules files are read for it)" "$S" "$shdr"$'A step. <!-- M004 -->\n'
lint_green "a file outside agents, rules and skills is not read" "method/.claude/hooks/method/README.md" $'IMPORTANT: you MUST think carefully. <!-- x --> text\n'
lint_green "a file under skills that is not .md is not read" "method/.claude/skills/method-x/notes.txt" $'You MUST think carefully.\n' "$shdr"

# --- part two (step 6.2, M096): the agent files, red with the file and the
# reason; each case one problem ---
agent_red() {
  lint_red "agent file: $1" "$A" "$2" "lint-prompts: $A: $3" "${4:-1}"
}
agent_red "no frontmatter" $'A body only.\n' "no frontmatter"
agent_red "frontmatter never closed" $'---\nname: method-x\nA body.\n' "no frontmatter"
agent_red "a name other than the file's" "$(fm "name: method-y" "model: $model" "effort: xhigh" "tools: Read")" "the name \"method-y\" is not the file's name, method-x"
agent_red "no name" "$(fm "model: $model" "effort: xhigh" "tools: Read")" "the name \"\" is not the file's name, method-x"
agent_red "no effort" "$(fm "name: method-x" "model: $model" "tools: Read")" "no effort: line"
agent_red "effort high" "$(fm "name: method-x" "model: $model" "effort: high" "tools: Read")" 'the effort is "high", not xhigh'
agent_red "no model" "$(fm "name: method-x" "effort: xhigh" "tools: Read")" "no model: line"
agent_red "a model other than the fragment's" "$(fm "name: method-x" "model: claude-sonnet-5-5" "effort: xhigh" "tools: Read")" "the model \"claude-sonnet-5-5\" is not the settings fragment's model, $model"
agent_red "the model alias in place of the fragment's ID" "$(fm "name: method-x" "model: opus" "effort: xhigh" "tools: Read")" "the model \"opus\" is not the settings fragment's model"
agent_red "no tools" "$(fm "name: method-x" "model: $model" "effort: xhigh")" "no tools: line"
agent_red "an empty tools line" "$(fm "name: method-x" "model: $model" "effort: xhigh" "tools:")" "the tools: line lists no tool"
for t in Agent Task Skill SendMessage; do
  agent_red "$t in tools" "$(fm "name: method-x" "model: $model" "effort: xhigh" "tools: Read, $t")" "the tools: line lists $t, a delegation tool"
done
agent_red "Agent with an argument in tools" "$(fm "name: method-x" "model: $model" "effort: xhigh" "tools: Read, Agent(method-y)")" "the tools: line lists Agent, a delegation tool"
agent_red "Agent in a block list of tools" "$(fm "name: method-x" "model: $model" "effort: xhigh" "tools:" "  - Read" "  - Agent")" "the tools: line lists Agent, a delegation tool"
agent_red "Task in a quoted flow list of tools" "$(fm "name: method-x" "model: $model" "effort: xhigh" 'tools: ["Read", "Task"]')" "the tools: line lists Task, a delegation tool"
# (step 6.6, the review's F15 and F17) the tools as YAML, and so the
# client, reads them: a value continued on an indented line, or starting
# there; the whole value quoted; a " #" comment after it; a block list at
# the key's own indent
agent_red "Agent on a continued tools line" "$(fm "name: method-x" "model: $model" "effort: xhigh" "tools: Read, Grep," "  Glob, Agent")" "the tools: line lists Agent, a delegation tool"
agent_red "Task in a tools value on the next line" "$(fm "name: method-x" "model: $model" "effort: xhigh" "tools:" "  Read, Task")" "the tools: line lists Task, a delegation tool"
agent_red "Agent in a quoted tools list" "$(fm "name: method-x" "model: $model" "effort: xhigh" 'tools: "Read, Grep, Agent"')" "the tools: line lists Agent, a delegation tool"
agent_red "Agent before a comment in tools" "$(fm "name: method-x" "model: $model" "effort: xhigh" "tools: Read, Agent  # to fan out")" "the tools: line lists Agent, a delegation tool"
agent_red "Write in a drafting agent's quoted tools" "$(fm "name: method-x" "model: $model" "effort: xhigh" "tools: 'Read, Write'")" "the tools: line lists Write, but this is not a gate in verdicts.txt"
agent_red "Agent in a block list at the key's indent" "$(fm "name: method-x" "model: $model" "effort: xhigh" "tools:" "- Read" "- Agent  # a comment")" "the tools: line lists Agent, a delegation tool"
for t in Bash PowerShell Monitor Edit Write MultiEdit NotebookEdit; do
  agent_red "$t in a drafting agent's tools" "$(fm "name: method-x" "model: $model" "effort: xhigh" "tools: Read, $t")" "the tools: line lists $t, but this is not a gate in verdicts.txt"
done
for key in memory isolation permissionMode background skills mcpServers; do
  agent_red "the key $key" "$(fm "name: method-x" "model: $model" "effort: xhigh" "tools: Read" "$key: x")" "the key $key: is set"
done
# a gate's name in another folder is not the gate's file: it is held to a
# drafting agent's tools
lint_red "agent file: a gate's name outside agents/method/, with Bash" "method/.claude/agents/other/method-reviewer.md" \
  "$(fm "name: method-reviewer" "model: $model" "effort: xhigh" "tools: Read, Bash")" \
  "lint-prompts: method/.claude/agents/other/method-reviewer.md: the tools: line lists Bash, but this is not a gate in verdicts.txt"

# --- part two, green ---
lint_green "agent file: a drafting agent with web tools, quoted values, a comment line and hooks (left to the guard, G17) passes" "$A" \
  "$(fm 'name: "method-x"' "description: x" "# rules: M001 M002" "model: '$model'" "effort: xhigh" "tools: Read, Grep, Glob, WebFetch, WebSearch" "hooks: x")"
lint_green "agent file: values with comments after them, a quoted tools list continued on the next line and a # inside a word pass" "$A" \
  "$(fm "name: method-x  # its file's name" "model: $model # the fragment's" "effort: xhigh" 'tools: "Read, Grep,' '  Glob" # no Bash' "description: a#b")"
lint_green "agent file: the delegation tools named in the body pass" "$A" "${hdr}Agent, Task, Skill and SendMessage are not yours; memory: none.$nl"
lint_green "agent file: CRLF line ends pass" "$A" "$(fm "name: method-x" "model: $model" "effort: xhigh" "tools: Read" | perl -pe 's/\n/\r\n/')"

# --- part two: the gates' files and what the lint reads ---
# gone NAME FILE WANT: in a mini repository, FILE removed turns the lint red
# (exit 1) with WANT
gone() {
  wanted "$1" || return 0
  mini || abort_sandbox
  rm -f "$m/$2"
  out=$(cd "$m" && bash scripts/dev/lint-prompts.sh 2>&1)
  code=$?
  if [ "$code" -eq 1 ] && printf '%s\n' "$out" | grep -F -q -- "$3"; then pass "$1"; else fail "$1: expected exit 1 and '$3'; got exit $code" "$out"; fi
}
for g in $(cd "$root" && perl method/scripts/method/lib/verdicts.pl words gate-verdict && perl method/scripts/method/lib/verdicts.pl words gate-diagnosis && perl method/scripts/method/lib/verdicts.pl words gate-test-result); do
  gone "a gate in verdicts.txt with no file ($g)" "method/.claude/agents/method/$g.md" "lint-prompts: the gate $g in verdicts.txt has no file method/.claude/agents/method/$g.md"
done
gone "verdicts.txt that cannot be read is a failure, not a pass" method/scripts/method/verdicts.txt "lint-prompts: could not read the gates from method/scripts/method/verdicts.txt"
gone "a settings fragment that cannot be read is a failure, not a pass" method/settings.fragment.json "lint-prompts: could not read the model from method/settings.fragment.json"

# --- part three (step 6.3; S8 and S10): the skill folders, red with the
# folder and the reason; each case one problem ---
SD=method/.claude/skills/method-x/
# sfm LINE...: a skill's SKILL.md of those frontmatter lines, then a body
# line
sfm() {
  printf -- '---\n'
  printf '%s\n' "$@"
  printf -- '---\nA step.\n'
}
skill_red() {
  lint_red "skill folder: $1" "$S" "$2" "lint-prompts: $SD: $3" "${4:-1}"
}
skill_red "context: fork" "$(sfm "name: method-x" "description: x" "context: fork")" "SKILL.md sets context: fork: a forked skill hands its work to an agent"
skill_red "context: fork, quoted" "$(sfm "name: method-x" 'context: "fork"')" "SKILL.md sets context: fork"
skill_red "context: fork before a comment (F17)" "$(sfm "name: method-x" "context: fork  # keeps the main context small")" "SKILL.md sets context: fork"
skill_red "context: fork on the next line (F15)" "$(sfm "name: method-x" "context:" "  fork")" "SKILL.md sets context: fork"
skill_red "agent:" "$(sfm "name: method-x" "agent: method-reviewer")" "SKILL.md sets the key agent:"
skill_red "agent: with context: fork, two problems" "$(sfm "name: method-x" "context: fork" "agent: Explore")" "SKILL.md sets the key agent:" 2
skill_red "a name other than the folder's" "$(sfm "name: method-y")" "the name \"method-y\" in SKILL.md is not the folder's name, method-x"
skill_red "no name" "$(sfm "description: x")" "the name \"\" in SKILL.md is not the folder's name, method-x"
skill_red "no frontmatter" $'A step only.\n' "no frontmatter in SKILL.md"
skill_red "frontmatter never closed" $'---\nname: method-x\nA step.\n' "no frontmatter in SKILL.md"
NOLIST=1 skill_red "a folder not on the method's skill list" "$shdr" "the folder is not on the method's skill list (@METHOD_SKILLS in method/scripts/method/lib/protect.pl)"
lint_red "skill folder: a folder whose name does not start method- (listed)" method/.claude/skills/plan/SKILL.md "$(sfm "name: plan")" \
  "lint-prompts: method/.claude/skills/plan/: the folder's name does not start method-"
NOLIST=1 lint_red "skill folder: a folder whose name does not start method-, not listed: two problems" method/.claude/skills/plan/SKILL.md "$(sfm "name: plan")" \
  "lint-prompts: method/.claude/skills/plan/: the folder is not on the method's skill list" 2
lint_red "skill folder: a folder with no SKILL.md" "${SD}notes.md" $'Notes.\n' "lint-prompts: $SD: no SKILL.md"
if wanted "skill folder: a listed name with no folder"; then
  mini || abort_sandbox
  list_skill method-y || abort_sandbox
  out=$(cd "$m" && bash scripts/dev/lint-prompts.sh 2>&1)
  code=$?
  if [ "$code" -eq 1 ] && printf '%s\n' "$out" | grep -F -q "lint-prompts: the method's skill list (@METHOD_SKILLS in method/scripts/method/lib/protect.pl) names method-y, but method/.claude/skills/method-y/ does not exist" &&
    printf '%s\n' "$out" | grep -q "^lint-prompts: FAIL - 1 problem(s) in $base_files prompt files\$"; then
    pass "skill folder: a listed name with no folder"
  else
    fail "skill folder: a listed name with no folder: expected exit 1 and one problem; got exit $code" "$out"
  fi
fi
gone "the method's skill list that cannot be read is a failure, not a pass" method/scripts/method/lib/protect.pl "lint-prompts: could not read the method's skill list from method/scripts/method/lib/protect.pl"

# --- part three, green ---
lint_green "skill folder: a skill with a description, a comment line, a quoted name, hooks (left to G17) and a ! line (left to M138) passes" "$S" \
  "$(sfm 'name: "method-x"' "description: Plans a task." "# rules: M006 M021" "hooks: x" "argument-hint: id")"$'\nRun !`git status` first.\n'
lint_green "skill folder: context: and agent named only in the body pass" "$S" "${shdr}Do not set context: fork or agent: here.$nl"
lint_green "skill folder: CRLF line ends pass" "$S" "$(sfm "name: method-x" "description: x" | perl -pe 's/\n/\r\n/')"
lint_green "skill folder: a project skill folder outside method/.claude/skills is not read" ".claude/skills/deploy/SKILL.md" $'---\nname: other\n---\n'
# (step 6.5 built the last skill on the list, method-start: no name is
# excepted as not built yet any more)
if wanted "skill folder: every name on the real list has its folder, none excepted"; then
  mini || abort_sandbox
  out=$(cd "$m" && bash scripts/dev/lint-prompts.sh 2>&1)
  code=$?
  if [ "$code" -eq 0 ] && ! printf '%s\n' "$out" | grep -q "not built yet" && [ -f "$m/method/.claude/skills/method-start/SKILL.md" ]; then
    pass "skill folder: every name on the real list has its folder, none excepted"
  else
    fail "skill folder: every name on the real list has its folder, none excepted: exit $code" "$out"
  fi
fi

# --- counts, nothing examined, escaping ---
if wanted "every problem is counted"; then
  mini || abort_sandbox
  printf 'You MUST and NEVER.\nThink carefully. <!-- M1 -->\n' >"$m/$R"
  out=$(cd "$m" && bash scripts/dev/lint-prompts.sh 2>&1)
  code=$?
  if [ "$code" -eq 1 ] && printf '%s\n' "$out" | grep -q "^lint-prompts: FAIL - 4 problem(s) in $((base_files + 1)) prompt files\$"; then pass "every problem is counted"; else fail "every problem is counted: exit $code" "$out"; fi
fi
if wanted "nothing examined is a failure"; then
  mini || abort_sandbox
  rm -rf "$m/method"
  out=$(cd "$m" && bash scripts/dev/lint-prompts.sh 2>&1)
  code=$?
  if [ "$code" -eq 1 ] && printf '%s\n' "$out" | grep -F -q 'examined 0 prompt files under method/.claude/; nothing was checked'; then pass "nothing examined is a failure"; else fail "nothing examined is a failure: exit $code" "$out"; fi
fi
if wanted "a helper's counts that cannot be read are a failure"; then
  mini || abort_sandbox
  printf 'print "EXAMINED 1\\nBAD 0\\nBAD 1\\n";\n' >"$m/scripts/dev/lib/prompts.pl"
  out=$(cd "$m" && bash scripts/dev/lint-prompts.sh 2>&1)
  code=$?
  if [ "$code" -eq 2 ] && printf '%s\n' "$out" | grep -F -q "could not read the check's result"; then pass "a helper's counts that cannot be read are a failure"; else fail "a helper's counts that cannot be read are a failure: exit $code" "$out"; fi
fi
if wanted "a helper that does not run is a failure"; then
  mini || abort_sandbox
  printf 'die "broken\\n";\n' >"$m/scripts/dev/lib/prompts.pl"
  out=$(cd "$m" && bash scripts/dev/lint-prompts.sh 2>&1)
  code=$?
  if [ "$code" -eq 2 ] && printf '%s\n' "$out" | grep -F -q "the check itself did not run"; then pass "a helper that does not run is a failure"; else fail "a helper that does not run is a failure: exit $code" "$out"; fi
fi
if wanted "a file name's control characters and command form are escaped"; then
  mini || abort_sandbox
  esc=$(printf '\033')
  name="method/.claude/rules/method/a${esc}[2K##[error]b.md"
  printf 'You MUST.\n' >"$m/$name"
  out=$(cd "$m" && PERL_UNICODE=SDA bash scripts/dev/lint-prompts.sh 2>&1)
  code=$?
  if [ "$code" -eq 1 ] && printf '%s\n' "$out" | grep -F -q 'a\x1B[2K#\x23[error]b.md:1: the emphasis word MUST' && ! printf '%s\n' "$out" | grep -F -q -e "$esc" -e '##['; then
    pass "a file name's control characters and command form are escaped"
  else
    fail "a file name's control characters and command form are escaped: exit $code" "$(printf '%s\n' "$out" | cat -v)"
  fi
fi
if wanted "outside a git repository the lint fails"; then
  mkdir -p "$work/nogit/scripts/dev/lib"
  cp "$root/scripts/dev/lint-prompts.sh" "$work/nogit/scripts/dev/"
  out=$(cd "$work/nogit" && GIT_CEILING_DIRECTORIES=$work bash scripts/dev/lint-prompts.sh 2>&1)
  code=$?
  if [ "$code" -eq 2 ] && printf '%s\n' "$out" | grep -F -q 'not inside a git repository'; then pass "outside a git repository the lint fails"; else fail "outside a git repository the lint fails: exit $code" "$out"; fi
fi

echo "tests: lint-prompts: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
