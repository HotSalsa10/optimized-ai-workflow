#!/usr/bin/env bash
# Fails when a tracked file contains something that looks like a secret or
# personal data: API keys and tokens, private keys, credentials assigned in
# code or env files, personal email addresses, phone numbers in international
# format, and bank account numbers (IBANs that pass their checksum).
# Matches are shown masked, never in full. Binary files are named, and only
# searched for keys and tokens.
# It reads the working-tree copy of every tracked file, plus the staged copy
# of any file whose staged copy differs. It does not read git history.
# Known false positives go in scripts/dev/scan-allow.txt, one per line:
#   <path><TAB><id><TAB><reason>
# Run "bash scripts/dev/scan-secrets.sh --ids" to see each finding's id.
# The rules live in method/scripts/method/lib/secrets.pl.
set -u
# perl reads bytes here; these settings would change how it reads them, and
# the library paths would let modules from elsewhere run inside the scan
unset PERL_UNICODE PERL5OPT PERL5LIB PERLLIB

ids=""
case "${1:-}" in
  --ids) ids="--ids" ;;
  "") ;;
  *)
    echo "secrets: FAIL - unknown option (only --ids is accepted)"
    exit 2
    ;;
esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "secrets: FAIL - not inside a git repository"
  exit 2
}
cd "$root" || exit 2
command -v perl >/dev/null 2>&1 || {
  echo "secrets: FAIL - perl is not installed"
  exit 2
}

# the scan lists the tracked files itself, so no file name goes on a command line
out=$(perl method/scripts/method/lib/secrets.pl --repo $ids scripts/dev/scan-allow.txt 2>&1) || {
  printf '%s\n' "$out"
  echo "secrets: FAIL - the scan itself did not run"
  exit 2
}
examined=$(printf '%s\n' "$out" | sed -n 's/^EXAMINED //p')
staged_copies=$(printf '%s\n' "$out" | sed -n 's/^STAGED //p')
bad=$(printf '%s\n' "$out" | sed -n 's/^BAD //p')
allowed=$(printf '%s\n' "$out" | sed -n 's/^ALLOWED //p')
skipped=$(printf '%s\n' "$out" | sed -n 's/^SKIPPED //p')
skipped_names=$(printf '%s\n' "$out" | sed -n 's/^SKIPPED_NAMES //p')
printf '%s\n' "$out" | grep -v -e '^EXAMINED ' -e '^STAGED ' -e '^BAD ' -e '^ALLOWED ' -e '^SKIPPED ' -e '^SKIPPED_NAMES ' -e '^RESULT ' | sed 's/^NOTE /secrets: note - /'

# Each count must be one plain number. Anything else means the output could
# not be trusted, which is a failure, never a pass.
for n in "$examined" "$staged_copies" "$bad" "$allowed" "$skipped"; do
  case "$n" in
    '' | *[!0-9]*)
      echo "secrets: FAIL - could not read the scan's result"
      exit 2
      ;;
  esac
done

if [ "$examined" -eq 0 ]; then
  echo "secrets: FAIL - examined 0 tracked text files; nothing was checked"
  exit 1
fi
if [ "$bad" -gt 0 ]; then
  echo "secrets: FAIL - $bad finding(s) in $examined tracked text files"
  exit 1
fi
notes=""
if [ "$staged_copies" -gt 0 ]; then
  notes="$notes (and $staged_copies staged copies and link targets)"
fi
if [ "$skipped" -gt 0 ]; then
  notes="$notes (skipped $skipped binary, searched for keys only: $skipped_names)"
fi
if [ "$allowed" -gt 0 ]; then
  notes="$notes ($allowed allowed by scan-allow.txt)"
fi
echo "secrets: PASS - examined $examined tracked text files$notes, no secrets or personal data found"
