#!/usr/bin/env bash
# Fails when a tracked file contains something that looks like a secret or
# personal data: API keys and tokens, private keys, credentials assigned in
# code or env files, personal email addresses, phone numbers in international
# format, and bank account numbers (IBANs that pass their checksum).
# Matches are shown masked, never in full. Binary files are named, and only
# searched for keys and tokens.
# Known limit: only the current commit is scanned, not history.
# Known false positives go in scripts/dev/scan-allow.txt, one per line:
#   <exact text><TAB><reason>
# The rules live in scripts/dev/lib/secrets.pl.
set -u

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "secrets: FAIL - not inside a git repository"
  exit 2
}
cd "$root" || exit 2
command -v perl >/dev/null 2>&1 || {
  echo "secrets: FAIL - perl is not installed"
  exit 2
}

files=()
while IFS= read -r -d '' f; do
  [ -f "$f" ] && files+=("$f")
done < <(git ls-files -z)
if [ "${#files[@]}" -eq 0 ]; then
  echo "secrets: FAIL - found 0 tracked files; nothing was checked"
  exit 1
fi

out=$(perl scripts/dev/lib/secrets.pl scripts/dev/scan-allow.txt "${files[@]}" 2>&1) || {
  printf '%s\n' "$out"
  echo "secrets: FAIL - the scan itself did not run"
  exit 2
}
examined=$(printf '%s\n' "$out" | sed -n 's/^EXAMINED //p')
bad=$(printf '%s\n' "$out" | sed -n 's/^BAD //p')
skipped=$(printf '%s\n' "$out" | sed -n 's/^SKIPPED //p')
skipped_names=$(printf '%s\n' "$out" | sed -n 's/^SKIPPED_NAMES //p')
printf '%s\n' "$out" | grep -v -e '^EXAMINED ' -e '^BAD ' -e '^SKIPPED ' -e '^SKIPPED_NAMES ' | sed 's/^NOTE /secrets: note - /'

if [ "${examined:-0}" -eq 0 ]; then
  echo "secrets: FAIL - examined 0 tracked text files; nothing was checked"
  exit 1
fi
if [ "${bad:-0}" -gt 0 ]; then
  echo "secrets: FAIL - $bad finding(s) in $examined tracked text files"
  exit 1
fi
if [ "${skipped:-0}" -gt 0 ]; then
  skip_note=" (skipped $skipped binary, searched for keys only: $skipped_names)"
else
  skip_note=""
fi
echo "secrets: PASS - examined $examined tracked text files$skip_note, no secrets or personal data found"
