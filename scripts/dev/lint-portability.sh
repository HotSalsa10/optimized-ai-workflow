#!/usr/bin/env bash
# Fails when a tracked shell script uses something that breaks on macOS
# (bash 3.2, BSD tools) or on Git Bash for Windows: bash 4+ features,
# constructs the bash 3.2 parser gets wrong, and GNU-only tool flags.
# The rules live in scripts/dev/lib/portability.pl.
set -u

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "portability: FAIL - not inside a git repository"
  exit 2
}
cd "$root" || exit 2
command -v perl >/dev/null 2>&1 || {
  echo "portability: FAIL - perl is not installed"
  exit 2
}

files=()
while IFS= read -r -d '' f; do
  [ -f "$f" ] && files+=("$f")
done < <(git ls-files -z)
if [ "${#files[@]}" -eq 0 ]; then
  echo "portability: FAIL - found 0 tracked files; nothing was checked"
  exit 1
fi

out=$(perl scripts/dev/lib/portability.pl "${files[@]}") || {
  echo "portability: FAIL - the scan itself did not run"
  exit 2
}
examined=$(printf '%s\n' "$out" | sed -n 's/^EXAMINED //p')
bad=$(printf '%s\n' "$out" | sed -n 's/^BAD //p')
printf '%s\n' "$out" | grep -v -e '^EXAMINED ' -e '^BAD '

if [ "${examined:-0}" -eq 0 ]; then
  echo "portability: FAIL - examined 0 shell scripts; nothing was checked"
  exit 1
fi
if [ "${bad:-0}" -gt 0 ]; then
  echo "portability: FAIL - $bad problem(s) in $examined shell scripts"
  exit 1
fi
echo "portability: PASS - examined $examined shell scripts, no bash 4 features, bash 3.2 parser traps or GNU-only flags"
