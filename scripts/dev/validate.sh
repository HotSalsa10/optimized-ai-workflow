#!/usr/bin/env bash
# Runs every repo check and prints one line per check plus a count.
# Exit 0 only when nothing failed. A check that cannot run here is reported
# as SKIPPED, which is not a pass. Setting REQUIRE_SHELLCHECK=1 turns a missing
# copy of the shellcheck tool into a failure (CI on Linux does this).
#
# Output from a failing check or tool goes through the secret scan's mask
# filter: keys and credentials a tool quotes are masked, control characters
# are escaped and each line is indented, so no line can start with text taken
# from a file. File names reach tools as ./NAME, so a name that starts with
# "-" is never read as an option. A tracked file name that holds a control
# character fails the "names" check and is kept away from the tools, whose
# output it could split into lines.
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

masked() {
  perl scripts/dev/lib/secrets.pl --mask
}

run_check() {
  name=$1
  shift
  if out=$("$@" 2>&1); then
    passed=$((passed + 1))
    printf '%s\n' "$out" | tail -n 1
  else
    failed=$((failed + 1))
    failed_names="$failed_names $name"
    printf '%s\n' "$out" | masked
  fi
}

# names: no tracked file name may hold a control character (a newline, an
# escape, or a UTF-8 C1 control); such a name could split or steer any tool's
# output. The same byte-level test keeps such names away from the tools below.
control_re='[\x00-\x1F\x7F]|\xC2[\x80-\x9F]'
bad_names=$(git ls-files -z | CONTROL=$control_re perl -0ne 'chomp; next unless /$ENV{CONTROL}/; s/([\x00-\x1F\x7F])/sprintf("\\x%02X", ord $1)/ge; s/\xC2([\x80-\x9F])/sprintf("\\xC2\\x%02X", ord $1)/ge; s/##\[/#\\x23[/g; print "$_\n"')
if [ -n "$bad_names" ]; then
  failed=$((failed + 1))
  failed_names="$failed_names names"
  printf '%s\n' "$bad_names" | sed 's/^/  names: /'
  echo "names: FAIL - tracked file names hold control characters; rename them"
else
  passed=$((passed + 1))
  echo "names: PASS - no tracked file name holds a control character"
fi

# tracked_plain PATTERN: tracked files whose names match the perl PATTERN and
# hold no control character, NUL-separated.
tracked_plain() {
  git ls-files -z | CONTROL=$control_re WANT=$1 perl -0ne 'chomp; print "$_\0" if /$ENV{WANT}/ && !/$ENV{CONTROL}/'
}

run_check line-endings bash scripts/dev/check-line-endings.sh
run_check portability bash scripts/dev/lint-portability.sh
run_check secrets bash scripts/dev/scan-secrets.sh
run_check rule-map bash scripts/dev/check-rule-map.sh
run_check workflows bash scripts/dev/lint-workflows.sh

# perl syntax: every tracked .pl file under scripts/ must compile. perl -c
# runs BEGIN blocks, so it is pointed only at this repo's own helpers.
# Only the file, line and the start of each message are shown.
pl_files=()
while IFS= read -r -d '' f; do
  [ -f "$f" ] && pl_files+=("./$f")
done < <(tracked_plain '^scripts/.*\.pl\z')
if [ "${#pl_files[@]}" -eq 0 ]; then
  failed=$((failed + 1))
  failed_names="$failed_names perl-syntax"
  echo "perl-syntax: FAIL - found 0 perl files; nothing was checked"
else
  pl_bad=0
  for f in "${pl_files[@]}"; do
    if ! msg=$(perl -c "$f" 2>&1); then
      pl_bad=$((pl_bad + 1))
      printf '%s\n' "$msg" | F=$f perl -ne '$n++, print "$2 line $3: $1\n" if /^(.{1,80}?),? at (\S+) line (\d+)/; END { print "$ENV{F}: does not compile\n" unless $n }' | masked
    fi
  done
  if [ "$pl_bad" -gt 0 ]; then
    failed=$((failed + 1))
    failed_names="$failed_names perl-syntax"
    echo "perl-syntax: FAIL - $pl_bad of ${#pl_files[@]} perl files do not compile"
  else
    passed=$((passed + 1))
    echo "perl-syntax: PASS - all ${#pl_files[@]} perl files compile"
  fi
fi

# The shellcheck tool is optional locally, and required where REQUIRE_SHELLCHECK=1.
# It runs at its default severity, so unquoted variables (SC2086) are caught,
# and in its one-line format, which does not quote source lines. It ignores
# .shellcheckrc files (--norc), so a config file cannot switch it off (an
# older version without --norc does not read those files either), and
# SHELLCHECK_OPTS, so the environment cannot either.
unset SHELLCHECK_OPTS
if command -v shellcheck >/dev/null 2>&1; then
  norc=""
  shellcheck --help 2>&1 | grep -q -- --norc && norc="--norc"
  scripts=()
  while IFS= read -r -d '' f; do
    [ -f "$f" ] && scripts+=("./$f")
  done < <(tracked_plain '\.sh\z')
  if [ "${#scripts[@]}" -eq 0 ]; then
    failed=$((failed + 1))
    failed_names="$failed_names shellcheck"
    echo "shellcheck: FAIL - found 0 shell scripts; nothing was checked"
  elif out=$(shellcheck $norc -x -f gcc "${scripts[@]}" 2>&1); then
    passed=$((passed + 1))
    echo "shellcheck: PASS - examined ${#scripts[@]} shell scripts, no findings"
  else
    failed=$((failed + 1))
    failed_names="$failed_names shellcheck"
    printf '%s\n' "$out" | masked
    echo "shellcheck: FAIL - findings in shell scripts"
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
