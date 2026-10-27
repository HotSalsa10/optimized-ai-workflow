#!/usr/bin/env bash
# Checks docs/rule-map.md, the list of every rule of the method and its home.
# - Every table row has an ID like M001, a rule, a source, a home and a status.
# - IDs are unique; a malformed row is an error, never skipped.
# - Status is one of: done, step N, R2, later.
# - A rule marked done names a real home file (not the rule map itself) that
#   contains the rule's ID, or the token written after "@" in the home column.
# Each rule has one reason and one home (M111): the same rule in two places
# is a defect. The checks live in scripts/dev/lib/rule-map.pl.
set -u

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "rule-map: FAIL - not inside a git repository"
  exit 2
}
cd "$root" || exit 2
map="docs/rule-map.md"
[ -f "$map" ] || {
  echo "rule-map: FAIL - $map is missing"
  exit 1
}

out=$(perl scripts/dev/lib/rule-map.pl "$map" 2>&1) || {
  printf '%s\n' "$out"
  echo "rule-map: FAIL - the check itself did not run"
  exit 2
}
rows=$(printf '%s\n' "$out" | sed -n 's/^ROWS //p')
bad=$(printf '%s\n' "$out" | sed -n 's/^BAD //p')
summary=$(printf '%s\n' "$out" | sed -n 's/^SUMMARY //p')
printf '%s\n' "$out" | grep -v -e '^ROWS ' -e '^BAD ' -e '^SUMMARY '

if [ "${rows:-0}" -eq 0 ]; then
  echo "rule-map: FAIL - found 0 rules in $map; nothing was checked"
  exit 1
fi
if [ "${bad:-0}" -gt 0 ]; then
  echo "rule-map: FAIL - $bad problem(s) in $rows rules"
  exit 1
fi
echo "rule-map: PASS - $rows rules ($summary); every rule marked done was found in its home"
