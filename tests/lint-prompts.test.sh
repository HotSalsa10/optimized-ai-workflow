#!/usr/bin/env bash
# Tests scripts/dev/lint-prompts.sh (step 6.1, M095): in small throwaway
# repositories holding only the lint and the text it reads, each pattern
# turns it red with its file, line and reason, each look-alike stays green,
# and its own counts are read strictly. The lint on this repo's own files is
# run by validate.sh; tests/plants/lint-prompts.sh plants each pattern there.
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

# mini: makes a new small repository with the lint and a rules file that
# passes, and sets m to its path (not in a subshell, so k counts on)
mini() {
  k=$((k + 1))
  m="$work/m$k"
  mkdir -p "$m/scripts/dev/lib" "$m/method/.claude/rules/method" || return 1
  cp "$root/scripts/dev/lint-prompts.sh" "$m/scripts/dev/" &&
    cp "$root/scripts/dev/lib/prompts.pl" "$m/scripts/dev/lib/" &&
    printf '# Rules\n\n<!-- M001 -->\nA plain rule.\n' >"$m/method/.claude/rules/method/base.md" &&
    (cd "$m" && git init -q .)
}

# lint_red NAME FILE TEXT WANT [N]: FILE (under method/.claude/) holding TEXT
# turns the lint red (exit 1) with WANT in its output, and N problems (1)
lint_red() {
  wanted "$1" || return 0
  mini || abort_sandbox
  mkdir -p "$m/$(dirname "$2")" && printf '%s' "$3" >"$m/$2"
  out=$(cd "$m" && bash scripts/dev/lint-prompts.sh 2>&1)
  code=$?
  if [ "$code" -eq 1 ] && printf '%s\n' "$out" | grep -F -q -- "$4" && printf '%s\n' "$out" | grep -q "^lint-prompts: FAIL - ${5:-1} problem(s) in 2 prompt files\$"; then
    pass "$1"
  else
    fail "$1: expected exit 1, ${5:-1} problem(s), and '$4'; got exit $code" "$out"
  fi
}

# lint_green NAME FILE TEXT: FILE holding TEXT leaves the lint green
lint_green() {
  wanted "$1" || return 0
  mini || abort_sandbox
  mkdir -p "$m/$(dirname "$2")" && printf '%s' "$3" >"$m/$2"
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

# --- each pattern, red: the file, the line and the reason ---
lint_red "think carefully in a rules file" "$R" $'# Rules\n\nThink carefully before you answer.\n' "lint-prompts: $R:3: $think"
lint_red "think step by step in an agent file" "$A" $'---\nname: method-x\n---\nLet us think step by step.\n' "lint-prompts: $A:4: $think"
lint_red "think step-by-step, hyphened, in a skill" "$S" $'Always think\tstep-by-step here.\n' "lint-prompts: $S:1: $think"
lint_red "think very carefully" "$R" $'Think very carefully.\n' "lint-prompts: $R:1: $think"
lint_red "a thinking tag" "$R" $'Put your notes in <thinking> tags.\n' "lint-prompts: $R:1: $format"
lint_red "a closing reasoning tag" "$A" $'Then close with </reasoning>.\n' "lint-prompts: $A:1: $format"
lint_red "a scratchpad tag with an attribute" "$S" $'Use <scratchpad id="1"> first.\n' "lint-prompts: $S:1: $format"
lint_red "reason in this format" "$R" $'Reason in this format: premise, step, answer.\n' "lint-prompts: $R:1: $format"
lint_red "think using the following structure" "$S" $'Think using the following structure.\n' "lint-prompts: $S:1: $format"
lint_red "a format for your reasoning" "$A" $'Use this format for your reasoning.\n' "lint-prompts: $A:1: $format"
lint_red "the emphasis word IMPORTANT" "$R" $'IMPORTANT: read the packet.\n' "lint-prompts: $R:1: the emphasis word IMPORTANT in capitals"
lint_red "the emphasis word MUST" "$R" $'You MUST read the packet.\n' "lint-prompts: $R:1: the emphasis word MUST in capitals"
lint_red "the emphasis word NEVER in bold" "$A" $'**NEVER** edit files.\n' "lint-prompts: $A:1: the emphasis word NEVER in capitals"
lint_red "the emphasis word ALWAYS" "$S" $'ALWAYS run the checks.\n' "lint-prompts: $S:1: the emphasis word ALWAYS in capitals"
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
lint_green "the words inside a longer word or an identifier pass" "$A" $'MUSTARD, NEVER_SET, ALWAYS-ON, X-MUST, REMEMBERED, IMPORTANTLY, DO NOTHING, DONOT, MUST1.\n'
lint_green "careful wording without the phrases passes" "$S" $'Check carefully. Go step by step. Think it through. The thinking budget. Re-think the plan. Reasoning in plain words.\n'
lint_green "a report form and other tags pass" "$A" $'Use this format for the report: <summary>, then `END-VERDICT <tree>`.\n'
lint_red "a comment with spaces before it (the client keeps it)" "$R" $'# Rules\n\n  <!-- M001 -->\nA rule.\n' "lint-prompts: $R:3: $shared"
lint_red "a comment with a space after it" "$R" $'<!-- M001 --> \nA rule.\n' "lint-prompts: $R:1: $shared"
lint_green "comments alone on their lines pass, an empty one too" "$R" $'# Rules\n\n<!-- M001 M002 -->\nA rule.\n<!---->\nAnother.\n'
lint_green "a comment beside text outside the rules files passes (only rules files are read for it)" "$S" $'A step. <!-- M004 -->\n'
lint_green "a file outside agents, rules and skills is not read" "method/.claude/hooks/method/README.md" $'IMPORTANT: you MUST think carefully. <!-- x --> text\n'
lint_green "a file under skills that is not .md is not read" "method/.claude/skills/method-x/notes.txt" $'You MUST think carefully.\n'

# --- counts, nothing examined, escaping ---
if wanted "every problem is counted"; then
  mini || abort_sandbox
  printf 'You MUST and NEVER.\nThink carefully. <!-- M1 -->\n' >"$m/$R"
  out=$(cd "$m" && bash scripts/dev/lint-prompts.sh 2>&1)
  code=$?
  if [ "$code" -eq 1 ] && printf '%s\n' "$out" | grep -q '^lint-prompts: FAIL - 4 problem(s) in 2 prompt files$'; then pass "every problem is counted"; else fail "every problem is counted: exit $code" "$out"; fi
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
