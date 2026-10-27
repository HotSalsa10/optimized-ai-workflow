#!/usr/bin/env bash
# Runs every repo check and prints one line per check plus a count.
# Exit 0 only when nothing failed. A check that cannot run here is reported
# as SKIPPED, which is not a pass. Setting REQUIRE_SHELLCHECK=1 turns a missing
# copy of the shellcheck tool into a failure (CI on Linux does this).
set -u

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "validate: FAIL - not inside a git repository"
  exit 2
}
cd "$root" || exit 2

passed=0
failed=0
skipped=0
failed_names=""

run_check() {
  name=$1
  shift
  if out=$("$@" 2>&1); then
    passed=$((passed + 1))
    printf '%s\n' "$out" | tail -n 1
  else
    failed=$((failed + 1))
    failed_names="$failed_names $name"
    printf '%s\n' "$out"
  fi
}

run_check line-endings bash scripts/dev/check-line-endings.sh
run_check portability bash scripts/dev/lint-portability.sh
run_check secrets bash scripts/dev/scan-secrets.sh
run_check rule-map bash scripts/dev/check-rule-map.sh
run_check workflows bash scripts/dev/lint-workflows.sh

# The shellcheck tool is optional locally, and required where REQUIRE_SHELLCHECK=1.
if command -v shellcheck >/dev/null 2>&1; then
  scripts=()
  while IFS= read -r -d '' f; do
    [ -f "$f" ] && scripts+=("$f")
  done < <(git ls-files -z -- '*.sh')
  if [ "${#scripts[@]}" -eq 0 ]; then
    failed=$((failed + 1))
    failed_names="$failed_names shellcheck"
    echo "shellcheck: FAIL - found 0 shell scripts; nothing was checked"
  elif out=$(shellcheck -x -S warning "${scripts[@]}" 2>&1); then
    passed=$((passed + 1))
    echo "shellcheck: PASS - examined ${#scripts[@]} shell scripts, no warnings"
  else
    failed=$((failed + 1))
    failed_names="$failed_names shellcheck"
    printf '%s\n' "$out"
    echo "shellcheck: FAIL - warnings in shell scripts"
  fi
elif [ "${REQUIRE_SHELLCHECK:-0}" = "1" ]; then
  failed=$((failed + 1))
  failed_names="$failed_names shellcheck"
  echo "shellcheck: FAIL - required here but not installed"
else
  skipped=$((skipped + 1))
  echo "shellcheck: SKIPPED - not installed here; this is not a pass (CI on Linux runs it)"
fi

echo "validate: $passed passed, $failed failed, $skipped skipped"
if [ "$failed" -gt 0 ]; then
  echo "validate: FAIL -$failed_names"
  exit 1
fi
