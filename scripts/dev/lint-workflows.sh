#!/usr/bin/env bash
# Checks GitHub Actions workflow files for three habits:
# - every "uses:" of an action is pinned to a full 40-character commit SHA
#   (a tag can be moved; a commit cannot);
# - the workflow sets top-level "permissions:" and does not grant write-all;
# - every job sets "timeout-minutes:" (a stuck job cannot burn minutes).
# The checks live in scripts/dev/lib/workflows.pl.
set -u

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "workflows: FAIL - not inside a git repository"
  exit 2
}
cd "$root" || exit 2

files=()
while IFS= read -r -d '' f; do
  case "$f" in
    .github/workflows/*.yml | .github/workflows/*.yaml) [ -f "$f" ] && files+=("$f") ;;
  esac
done < <(git ls-files -z)

if [ "${#files[@]}" -eq 0 ]; then
  echo "workflows: FAIL - found 0 tracked workflow files; nothing was checked"
  exit 1
fi

out=$(perl scripts/dev/lib/workflows.pl "${files[@]}" 2>&1) || {
  printf '%s\n' "$out"
  echo "workflows: FAIL - the check itself did not run"
  exit 2
}
examined=$(printf '%s\n' "$out" | sed -n 's/^EXAMINED //p')
bad=$(printf '%s\n' "$out" | sed -n 's/^BAD //p')
printf '%s\n' "$out" | grep -v -e '^EXAMINED ' -e '^BAD '

if [ "${bad:-0}" -gt 0 ]; then
  echo "workflows: FAIL - $bad problem(s) in $examined workflow files"
  exit 1
fi
echo "workflows: PASS - examined $examined workflow files: actions pinned by commit, permissions set, every job has a timeout"
