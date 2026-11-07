#!/usr/bin/env bash
# Checks GitHub Actions workflow files, and every tracked action file
# (action.yml or action.yaml), for these habits:
# - every "uses:" of an action is pinned to a full 40-character commit SHA,
#   and of a docker image to an @sha256 digest (a tag can be moved; these
#   cannot);
# - the workflow sets top-level "permissions:" and does not grant write-all;
# - every job sets "timeout-minutes:" (a stuck job cannot burn minutes).
# YAML forms the check cannot read reliably are findings, not passes.
# The checks live in scripts/dev/lib/workflows.pl.
set -u
# perl reads bytes here; these settings would change how it reads them
unset PERL_UNICODE PERL5OPT

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "workflows: FAIL - not inside a git repository"
  exit 2
}
cd "$root" || exit 2

files=()
while IFS= read -r -d '' f; do
  case "$f" in
    .github/workflows/*.yml | .github/workflows/*.yaml | action.yml | action.yaml | */action.yml | */action.yaml) [ -f "$f" ] && files+=("$f") ;;
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
action_files=$(printf '%s\n' "$out" | sed -n 's/^ACTIONS //p')
bad=$(printf '%s\n' "$out" | sed -n 's/^BAD //p')
printf '%s\n' "$out" | grep -v -e '^EXAMINED ' -e '^ACTIONS ' -e '^BAD '

# Each count must be one plain number. Anything else means the output could
# not be trusted, which is a failure, never a pass.
for n in "$examined" "$action_files" "$bad"; do
  case "$n" in
    '' | *[!0-9]*)
      echo "workflows: FAIL - could not read the check's result"
      exit 2
      ;;
  esac
done

if [ "$bad" -gt 0 ]; then
  echo "workflows: FAIL - $bad problem(s) in $examined workflow files"
  exit 1
fi
if [ "$examined" -eq 0 ]; then
  echo "workflows: FAIL - examined 0 workflow files; nothing was checked"
  exit 1
fi
echo "workflows: PASS - examined $examined workflow files and $action_files action files: actions pinned, permissions set, every job has a timeout"
