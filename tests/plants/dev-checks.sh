#!/usr/bin/env bash
# Plants for the repo checks in scripts/dev/. Each check must be green on a
# clean copy and red, for its stated reason, on a copy with the planted defect.
# Strings that would trip the checks are assembled at run time, so this file
# itself stays clean.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh"

echo "plants: repo checks"

# --- clean copy: every check green ---------------------------------------
sb=$(make_sandbox) || { fail "sandbox"; exit 1; }
expect_green "line-endings green on a clean copy" "$sb" bash scripts/dev/check-line-endings.sh
expect_green "portability green on a clean copy" "$sb" bash scripts/dev/lint-portability.sh
expect_green "secrets green on a clean copy" "$sb" bash scripts/dev/scan-secrets.sh
expect_green "rule-map green on a clean copy" "$sb" bash scripts/dev/check-rule-map.sh
expect_green "workflows green on a clean copy" "$sb" bash scripts/dev/lint-workflows.sh
drop_sandbox "$sb"

# --- line endings: a script committed with CRLF ----------------------------
sb=$(make_sandbox)
printf '#!/usr/bin/env bash\r\necho hi\r\n' >"$sb/planted-crlf.sh"
(cd "$sb" && git -c core.autocrlf=false -c core.safecrlf=false add planted-crlf.sh)
if expect_landed "line-endings plant" grep -q "$(printf '\r')" "$sb/planted-crlf.sh"; then
  expect_red "line-endings red on a CRLF script" "$sb" "CRLF in planted-crlf.sh" bash scripts/dev/check-line-endings.sh
fi
drop_sandbox "$sb"

# --- line endings: nothing to examine is a failure, not a pass --------------
src_root=$(repo_root)
sb=$(mktemp -d)
(cd "$sb" && git init -q && mkdir -p scripts/dev && cp "$src_root/scripts/dev/check-line-endings.sh" scripts/dev/)
expect_red "line-endings red when it examined nothing" "$sb" "examined 0" bash scripts/dev/check-line-endings.sh
drop_sandbox "$sb"

# --- portability: associative array (bash 4) --------------------------------
sb=$(make_sandbox)
bash4_text="declare -"'A'
printf '#!/usr/bin/env bash\n%s colours\n' "$bash4_text" >"$sb/planted-bash4.sh"
(cd "$sb" && git add planted-bash4.sh)
if expect_landed "portability plant 1" grep -q -F -- "$bash4_text" "$sb/planted-bash4.sh"; then
  expect_red "portability red on an associative array" "$sb" "planted-bash4.sh:2: associative arrays" bash scripts/dev/lint-portability.sh
fi
drop_sandbox "$sb"

# --- portability: GNU-only in-place sed ------------------------------------
sb=$(make_sandbox)
sed_text="sed -"'i'
printf '#!/usr/bin/env bash\n%s s/a/b/ file.txt\n' "$sed_text" >"$sb/planted-sed.sh"
(cd "$sb" && git add planted-sed.sh)
if expect_landed "portability plant 2" grep -q -F -- "$sed_text" "$sb/planted-sed.sh"; then
  expect_red "portability red on in-place sed" "$sb" "planted-sed.sh:2: $sed_text differs" bash scripts/dev/lint-portability.sh
fi
drop_sandbox "$sb"

# --- secrets: an API key ------------------------------------------------------
sb=$(make_sandbox)
key="sk-ant""-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef0123456789"
printf 'ANTHROPIC_KEY=%s\n' "$key" >"$sb/planted-key.txt"
(cd "$sb" && git add planted-key.txt)
if expect_landed "secrets plant 1" grep -q "api03" "$sb/planted-key.txt"; then
  expect_red "secrets red on an API key" "$sb" "planted-key.txt:1: Anthropic API key" bash scripts/dev/scan-secrets.sh
  out=$(cd "$sb" && bash scripts/dev/scan-secrets.sh 2>&1)
  if printf '%s\n' "$out" | grep -F -q "$key"; then
    fail "secrets output must mask the key, but printed it in full"
  else
    pass "secrets output masks the key"
  fi
fi
drop_sandbox "$sb"

# --- secrets: a personal email address ---------------------------------------
sb=$(make_sandbox)
printf 'Contact: %s@%s\n' "jane.doe.1987" "gmail.com" >"$sb/planted-email.md"
(cd "$sb" && git add planted-email.md)
if expect_landed "secrets plant 2" grep -q "gmail" "$sb/planted-email.md"; then
  expect_red "secrets red on a personal email" "$sb" "planted-email.md:1: email address" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# --- secrets: a bank account number (IBAN with a valid checksum) --------------
sb=$(make_sandbox)
printf 'Pay to %s%s%s\n' "GB82" "WEST" "12345698765432" >"$sb/planted-iban.md"
(cd "$sb" && git add planted-iban.md)
if expect_landed "secrets plant 3" grep -q "WEST" "$sb/planted-iban.md"; then
  expect_red "secrets red on an IBAN" "$sb" "planted-iban.md:1: bank account number" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# --- rule map: a rule marked done whose ID is not in its home ------------------
sb=$(make_sandbox)
printf '| M999 | planted rule | test | README.md | done |\n' >>"$sb/docs/rule-map.md"
if expect_landed "rule-map plant 1" grep -q "M999" "$sb/docs/rule-map.md"; then
  expect_red "rule-map red when a done rule is missing from its home" "$sb" "M999 is marked done but 'M999' is not in README.md" bash scripts/dev/check-rule-map.sh
fi
drop_sandbox "$sb"

# --- rule map: a rule marked done whose home file does not exist ----------------
sb=$(make_sandbox)
printf '| M998 | planted rule | test | no/such/file.md | done |\n' >>"$sb/docs/rule-map.md"
if expect_landed "rule-map plant 2" grep -q "M998" "$sb/docs/rule-map.md"; then
  expect_red "rule-map red when a done rule's home is missing" "$sb" "M998 is marked done but its home no/such/file.md does not exist" bash scripts/dev/check-rule-map.sh
fi
drop_sandbox "$sb"

# --- workflows: an action pinned to a tag instead of a commit -------------------
sb=$(make_sandbox)
wf="$sb/.github/workflows/ci.yml"
if [ -f "$wf" ]; then
  perl -pi -e 'if (!$done && s/uses: actions\/checkout\@[0-9a-f]{40}/uses: actions\/checkout\@v7/) { $done = 1 }' "$wf"
  if expect_landed "workflows plant 1" grep -q "checkout@v7" "$wf"; then
    expect_red "workflows red on an action pinned by tag" "$sb" "'actions/checkout@v7' is not pinned to a commit SHA" bash scripts/dev/lint-workflows.sh
  fi
else
  fail "workflows plant 1: .github/workflows/ci.yml not found"
fi
drop_sandbox "$sb"

# --- workflows: a job without a timeout ---------------------------------------
sb=$(make_sandbox)
wf="$sb/.github/workflows/ci.yml"
perl -ni -e 'print unless /^    timeout-minutes:/ && !$done++' "$wf"
if expect_landed "workflows plant 2" perl -e 'my $c = () = do { local $/; open my $f, "<", $ARGV[0]; <$f> } =~ /^    timeout-minutes:/mg; my $j = () = do { local $/; open my $f, "<", $ARGV[0]; <$f> } =~ /^  [A-Za-z0-9_-]+:\s*$/mg; exit($c < $j ? 0 : 1)' "$wf"; then
  expect_red "workflows red on a job without timeout-minutes" "$sb" "has no timeout-minutes" bash scripts/dev/lint-workflows.sh
fi
drop_sandbox "$sb"

# --- shellcheck: an unchecked cd ----------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  sb=$(make_sandbox)
  printf '#!/usr/bin/env bash\ncd "$1"\nrm -f ./tmpfile\n' >"$sb/planted-cd.sh"
  (cd "$sb" && git add planted-cd.sh)
  out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
  if printf '%s\n' "$out" | grep -q "In planted-cd.sh line 2" &&
    printf '%s\n' "$out" | grep -q "SC2164" &&
    printf '%s\n' "$out" | grep -q "validate: FAIL - shellcheck"; then
    pass "shellcheck red on an unchecked cd"
  else
    fail "shellcheck red on an unchecked cd" "$out"
  fi
  drop_sandbox "$sb"
elif [ "${REQUIRE_SHELLCHECK:-0}" = "1" ]; then
  fail "shellcheck plant: shellcheck is required here but not installed"
else
  skip "shellcheck plant: shellcheck not installed"
fi

echo "plants: repo checks: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
