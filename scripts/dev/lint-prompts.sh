#!/usr/bin/env bash
# Checks the method's prompt text: the agents, rules and skills under
# method/.claude/ (M095; docs/plans/step6.md S8). It fails on
# - a "think carefully" or "think step by step" line;
# - a fixed-format reasoning request (a <thinking>-style tag, "reason in
#   this format");
# - an emphasis word in capitals: IMPORTANT, MUST, NEVER, ALWAYS, REMEMBER,
#   DO NOT;
# - in the rules files, an HTML comment that is not a line of its own: the
#   client drops a comment alone on its line and keeps one beside text or
#   spaces, so the rule IDs cost nothing per session only on lines of their
#   own.
# Examining nothing is a failure. The checks live in scripts/dev/lib/prompts.pl.
set -u
# perl reads bytes here; these settings would change how it reads them
unset PERL_UNICODE PERL5OPT

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "lint-prompts: FAIL - not inside a git repository"
  exit 2
}
cd "$root" || exit 2

out=$(perl scripts/dev/lib/prompts.pl . 2>&1) || {
  printf '%s\n' "$out"
  echo "lint-prompts: FAIL - the check itself did not run"
  exit 2
}
examined=$(printf '%s\n' "$out" | sed -n 's/^EXAMINED //p')
bad=$(printf '%s\n' "$out" | sed -n 's/^BAD //p')
printf '%s\n' "$out" | grep -v -e '^EXAMINED ' -e '^BAD '

# Each count must be one plain number. Anything else means the output could
# not be trusted, which is a failure, never a pass.
for n in "$examined" "$bad"; do
  case "$n" in
    '' | *[!0-9]*)
      echo "lint-prompts: FAIL - could not read the check's result"
      exit 2
      ;;
  esac
done

if [ "$bad" -gt 0 ]; then
  echo "lint-prompts: FAIL - $bad problem(s) in $examined prompt files"
  exit 1
fi
if [ "$examined" -eq 0 ]; then
  echo "lint-prompts: FAIL - examined 0 prompt files under method/.claude/; nothing was checked"
  exit 1
fi
echo "lint-prompts: PASS - examined $examined prompt files under method/.claude/ (agents, rules, skills): no think-carefully lines, reasoning formats or emphasis words; every rules comment on a line of its own"
