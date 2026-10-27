#!/usr/bin/env bash
# Plants for the repo checks in scripts/dev/. Each check must be green on a
# clean copy and red, for its stated reason, on a copy with the planted defect.
# Strings that would trip the checks are assembled at run time, so this file
# itself stays clean. Each plant first confirms it really landed in the file.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh"

d='$' # a dollar sign, so planted shell text needs no single-quoted $
key="sk-ant""-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef0123456789"
pinned="actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"

# starts_with FILE HEX: the file's first bytes are exactly HEX (portable, no od).
starts_with() {
  perl -e 'open my $f, "<:raw", $ARGV[0] or exit 1; my $want = pack "H*", $ARGV[1]; read $f, my $got, length $want; exit($got eq $want ? 0 : 1)' "$1" "$2"
}

# has_nul FILE: the file holds at least one NUL byte.
has_nul() {
  perl -e 'open my $f, "<:raw", $ARGV[0] or exit 1; local $/; my $b = <$f>; exit(index($b, "\0") >= 0 ? 0 : 1)' "$1"
}

echo "plants: repo checks"

# --- clean copy: every check green ---------------------------------------
sb=$(make_sandbox) || {
  fail "sandbox"
  exit 1
}
expect_green "line-endings green on a clean copy" "$sb" bash scripts/dev/check-line-endings.sh
expect_green "portability green on a clean copy" "$sb" bash scripts/dev/lint-portability.sh
expect_green "secrets green on a clean copy" "$sb" bash scripts/dev/scan-secrets.sh
expect_green "rule-map green on a clean copy" "$sb" bash scripts/dev/check-rule-map.sh
expect_green "workflows green on a clean copy" "$sb" bash scripts/dev/lint-workflows.sh
drop_sandbox "$sb"

# --- line endings ------------------------------------------------------------
# 1. CRLF in the working tree
sb=$(make_sandbox)
printf '#!/usr/bin/env bash\r\necho hi\r\n' >"$sb/planted-crlf.sh"
(cd "$sb" && git -c core.autocrlf=false -c core.safecrlf=false add planted-crlf.sh)
if expect_landed "line-endings plant 1" grep -q "$(printf '\r')" "$sb/planted-crlf.sh"; then
  expect_red "line-endings red on a CRLF file in the working tree" "$sb" "CRLF in planted-crlf.sh" bash scripts/dev/check-line-endings.sh
fi
drop_sandbox "$sb"

# 2. CRLF committed in the index, so a fresh clone gets it
sb=$(make_sandbox)
printf 'planted-crlf-index.sh -text\n' >>"$sb/.gitattributes"
printf '#!/usr/bin/env bash\r\necho hi\r\n' >"$sb/planted-crlf-index.sh"
(cd "$sb" && git add .gitattributes planted-crlf-index.sh && git commit -q -m plant)
if expect_landed "line-endings plant 2" sh -c "cd '$sb' && git ls-files --eol planted-crlf-index.sh | grep -q 'i/crlf'"; then
  expect_red "line-endings red on a CRLF file committed to the index" "$sb" "CRLF in planted-crlf-index.sh (i/crlf" bash scripts/dev/check-line-endings.sh
fi
drop_sandbox "$sb"

# 3. nothing to examine is a failure, not a pass
src_root=$(repo_root)
sb=$(mktemp -d)
(cd "$sb" && git init -q && mkdir -p scripts/dev && cp "$src_root/scripts/dev/check-line-endings.sh" scripts/dev/)
expect_red "line-endings red when it examined nothing" "$sb" "examined 0" bash scripts/dev/check-line-endings.sh
drop_sandbox "$sb"

# --- portability ---------------------------------------------------------------
# 4. associative array (bash 4)
sb=$(make_sandbox)
bash4_text="declare -"'A'
printf '#!/usr/bin/env bash\n%s colours\n' "$bash4_text" >"$sb/planted-bash4.sh"
(cd "$sb" && git add planted-bash4.sh)
if expect_landed "portability plant 1" grep -q -F -- "$bash4_text" "$sb/planted-bash4.sh"; then
  expect_red "portability red on an associative array" "$sb" "planted-bash4.sh:2: associative arrays" bash scripts/dev/lint-portability.sh
fi
drop_sandbox "$sb"

# 5. GNU-only in-place sed, with another flag before it
sb=$(make_sandbox)
sed_text="sed -E -"'i'
printf '#!/usr/bin/env bash\n%s s/a/b/ file.txt\n' "$sed_text" >"$sb/planted-sed.sh"
(cd "$sb" && git add planted-sed.sh)
if expect_landed "portability plant 2" grep -q -F -- "$sed_text" "$sb/planted-sed.sh"; then
  expect_red "portability red on in-place sed after another flag" "$sb" "planted-sed.sh:2: sed -i differs" bash scripts/dev/lint-portability.sh
fi
drop_sandbox "$sb"

# 6. a here-doc inside a command substitution (bash 3.2 parser trap)
sb=$(make_sandbox)
printf '#!/usr/bin/env bash\n%s(cat <<%s\nhello\nEOF\n)\necho "%sx"\n' "x=$d" "'EOF'" "$d" >"$sb/planted-heredoc.sh"
(cd "$sb" && git add planted-heredoc.sh)
if expect_landed "portability plant 3" grep -q -F -- "$d(cat <<" "$sb/planted-heredoc.sh"; then
  expect_red "portability red on a here-doc inside a command substitution" "$sb" "planted-heredoc.sh:2: a here-doc inside" bash scripts/dev/lint-portability.sh
fi
drop_sandbox "$sb"

# 7. a here-string in a $( ) that runs onto the next line is not called a here-doc
sb=$(make_sandbox)
printf '#!/usr/bin/env bash\n%s(wc -l <<<"%sy" |\n  tr -d " ")\n' "x=$d" "$d" >"$sb/planted-herestring.sh"
(cd "$sb" && git add planted-herestring.sh)
if expect_landed "portability plant 4" grep -q -F -- "<<<" "$sb/planted-herestring.sh"; then
  expect_red "portability names a multi-line ${d}( ) with a here-string correctly" "$sb" "planted-herestring.sh:2: a ${d}( ) that continues onto the next line" bash scripts/dev/lint-portability.sh
fi
drop_sandbox "$sb"

# 8. the -v test in single brackets (bash 4.2)
sb=$(make_sandbox)
v_text='[ -''v HOME ]'
printf '#!/usr/bin/env bash\nif %s; then echo set; fi\n' "$v_text" >"$sb/planted-v.sh"
(cd "$sb" && git add planted-v.sh)
if expect_landed "portability plant 5" grep -q -F -- "$v_text" "$sb/planted-v.sh"; then
  expect_red "portability red on the -v test" "$sb" "planted-v.sh:2: the -v test" bash scripts/dev/lint-portability.sh
fi
drop_sandbox "$sb"

# 9. valid bash 3.2 code that looks close to the rules stays green
sb=$(make_sandbox)
cat >"$sb/tricky-valid.sh" <<'EOF'
#!/usr/bin/env bash
x=${HOME:-/tmp}
y=$((1 << 2))
z=${HOME:0:2}
sed -E 's/ -i / /' /dev/null
date -u +%Y-%m-%d
echo "timeout later, then sha256sum by name only"
printf '%s\n' "$x$y$z"
EOF
(cd "$sb" && git add tricky-valid.sh)
if expect_landed "portability plant 6" grep -q "sha256sum by name only" "$sb/tricky-valid.sh"; then
  expect_green "portability green on valid code that looks close to the rules" "$sb" bash scripts/dev/lint-portability.sh
fi
drop_sandbox "$sb"

# 10. the regression corpus: every line marked RED is reported (forms an
#    earlier version of the lint caught or missed), and no other line is
#    (valid look-alikes such as here-strings, arithmetic shifts and the word
#    "case" inside a string)
sb=$(make_sandbox)
corpus="tests/plants/fixtures/portability-corpus.txt"
{
  printf '#!/usr/bin/env bash\n'
  cat "$sb/$corpus"
} >"$sb/planted-corpus.sh"
(cd "$sb" && git add planted-corpus.sh)
if expect_landed "portability plant 7" grep -q "#RED" "$sb/planted-corpus.sh"; then
  out=$(cd "$sb" && bash scripts/dev/lint-portability.sh 2>&1)
  code=$?
  missed=""
  extra=""
  n=1
  while IFS= read -r line; do
    n=$((n + 1))
    if printf '%s\n' "$out" | grep -q "planted-corpus.sh:$n: "; then
      case "$line" in
        *"#RED") ;;
        *) extra="$extra $n" ;;
      esac
    else
      case "$line" in
        *"#RED") missed="$missed $n" ;;
      esac
    fi
  done <"$sb/$corpus"
  if [ "$code" -eq 1 ] && [ -z "$missed$extra" ]; then
    pass "portability reports every corpus line marked RED and no other line"
  else
    fail "portability corpus: exit $code; lines missed:${missed:- none}; lines wrongly reported:${extra:- none}" "$out"
  fi
fi
drop_sandbox "$sb"

# --- secrets and personal data -----------------------------------------------------
# 11. an API key, which must also be masked in the output
sb=$(make_sandbox)
printf 'ANTHROPIC_KEY=%s\n' "$key" >"$sb/planted-key.txt"
(cd "$sb" && git add planted-key.txt)
if expect_landed "secrets plant 1" grep -q "api03" "$sb/planted-key.txt"; then
  expect_red "secrets red on an API key" "$sb" "planted-key.txt:1: Anthropic API key" bash scripts/dev/scan-secrets.sh
  out=$(cd "$sb" && bash scripts/dev/scan-secrets.sh 2>&1)
  if printf '%s\n' "$out" | grep -F -q -- "$key"; then
    fail "secrets output must mask the key, but printed it in full"
  else
    pass "secrets output masks the key"
  fi
fi
drop_sandbox "$sb"

# 12. a credential in a longer variable name
sb=$(make_sandbox)
printf '%s="%s"\n' "DB_PASS""WORD" "Sup3rS3cretValue" >"$sb/planted-cred.py"
(cd "$sb" && git add planted-cred.py)
if expect_landed "secrets plant 2" grep -q "Sup3r" "$sb/planted-cred.py"; then
  expect_red "secrets red on a credential in a longer name" "$sb" "planted-cred.py:1: hard-coded credential" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 13. an env-file style credential without quotes
sb=$(make_sandbox)
printf '%s=%s\n' "API_TO""KEN" "abcd1234efgh5678ijkl" >"$sb/planted.env.example"
(cd "$sb" && git add -f planted.env.example)
if expect_landed "secrets plant 3" grep -q "abcd1234" "$sb/planted.env.example"; then
  expect_red "secrets red on an env-style credential" "$sb" "planted.env.example:1: credential in an env-style assignment" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 14. a personal email address
sb=$(make_sandbox)
printf 'Contact: %s@%s\n' "jane.doe.1987" "gmail.com" >"$sb/planted-email.md"
(cd "$sb" && git add planted-email.md)
if expect_landed "secrets plant 4" grep -q "gmail" "$sb/planted-email.md"; then
  expect_red "secrets red on a personal email" "$sb" "planted-email.md:1: email address" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 15. personal email addresses at domains that end like file names
#     (.md Moldova, .py Paraguay, .rs Serbia, .sh Saint Helena)
sb=$(make_sandbox)
printf '%s@%s\n' "ion.popescu" "mail.md" "juan.perez" "tigo.com.py" "petar.petrovic" "gmail.rs" "ann.smith" "post.sh" >"$sb/planted-emails.md"
(cd "$sb" && git add planted-emails.md)
if expect_landed "secrets plant 5" grep -q "tigo.com.py" "$sb/planted-emails.md"; then
  out=$(cd "$sb" && bash scripts/dev/scan-secrets.sh 2>&1)
  code=$?
  hits=$(printf '%s\n' "$out" | grep -c "planted-emails.md:[1-4]: email address")
  if [ "$code" -eq 1 ] && [ "$hits" -eq 4 ]; then
    pass "secrets red on all 4 emails at domains that end like file names"
  else
    fail "secrets red on all 4 emails at domains that end like file names: exit $code, $hits of 4 found" "$out"
  fi
fi
drop_sandbox "$sb"

# 16. a phone number written in short groups
sb=$(make_sandbox)
printf 'Call %s %s today\n' "+41" "79 123 45 67" >"$sb/planted-phone.md"
(cd "$sb" && git add planted-phone.md)
if expect_landed "secrets plant 6" grep -q "79 123" "$sb/planted-phone.md"; then
  expect_red "secrets red on a phone number in short groups" "$sb" "planted-phone.md:1: phone number" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 17. an IBAN written in groups and followed by more text
sb=$(make_sandbox)
printf 'IBAN: %s %s BIC: %s\n' "DE89" "3704 0044 0532 0130 00" "COBADEFFXXX" >"$sb/planted-iban.md"
(cd "$sb" && git add planted-iban.md)
if expect_landed "secrets plant 7" grep -q "BIC" "$sb/planted-iban.md"; then
  expect_red "secrets red on an IBAN followed by more text" "$sb" "planted-iban.md:1: bank account number" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 18. an API key in a UTF-16LE file with a byte-order mark (Windows PowerShell's default output)
sb=$(make_sandbox)
perl -e 'print "\xFF\xFE", pack("v*", unpack("C*", $ARGV[0]))' "ANTHROPIC_KEY=$key" >"$sb/planted-utf16.txt"
(cd "$sb" && git add planted-utf16.txt)
if expect_landed "secrets plant 8" starts_with "$sb/planted-utf16.txt" fffe; then
  expect_red "secrets red on a key in a UTF-16LE file" "$sb" "planted-utf16.txt:1: Anthropic API key" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 19. an API key in a UTF-16BE file without a byte-order mark
sb=$(make_sandbox)
perl -e 'print pack("n*", unpack("C*", $ARGV[0]))' "ANTHROPIC_KEY=$key" >"$sb/planted-utf16be.txt"
(cd "$sb" && git add planted-utf16be.txt)
if expect_landed "secrets plant 9" starts_with "$sb/planted-utf16be.txt" 0041; then
  expect_red "secrets red on a key in a UTF-16BE file without a byte-order mark" "$sb" "planted-utf16be.txt:1: Anthropic API key" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 20. an API key in a file that one NUL byte makes look binary
sb=$(make_sandbox)
printf 'header\000ANTHROPIC_KEY=%s\n' "$key" >"$sb/planted-blob.bin"
(cd "$sb" && git add planted-blob.bin)
if expect_landed "secrets plant 10" has_nul "$sb/planted-blob.bin"; then
  expect_red "secrets red on a key inside a binary file" "$sb" "planted-blob.bin (binary): Anthropic API key" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 21. an API key after 4 KB of NUL bytes (padding as in a tar file)
sb=$(make_sandbox)
perl -e 'print "\0" x 4096, "ANTHROPIC_KEY=$ARGV[0]\n"' "$key" >"$sb/planted-padded.tar"
(cd "$sb" && git add planted-padded.tar)
if expect_landed "secrets plant 11" starts_with "$sb/planted-padded.tar" 00000000; then
  expect_red "secrets red on a key after many NUL bytes" "$sb" "planted-padded.tar (binary): Anthropic API key" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 22. a binary file without secrets stays green, and the pass line names it
sb=$(make_sandbox)
printf 'GIF89a\000\001\002\003 plain bytes\n' >"$sb/planted-image.gif"
(cd "$sb" && git add planted-image.gif)
if expect_landed "secrets plant 12" has_nul "$sb/planted-image.gif"; then
  out=$(cd "$sb" && bash scripts/dev/scan-secrets.sh 2>&1)
  code=$?
  last=$(printf '%s\n' "$out" | tail -n 1)
  case "$code:$last" in
    "0:secrets: PASS"*planted-image.gif*) pass "secrets green on a clean binary file, and the pass line names it" ;;
    *) fail "secrets green on a clean binary file, and the pass line names it: exit $code" "$out" ;;
  esac
fi
drop_sandbox "$sb"

# 23. ordinary text that looks close to the rules stays green
sb=$(make_sandbox)
cat >"$sb/tricky-clean.md" <<'EOF'
Images: logo@2x.png and icon@3x.webp
Clone: git@gitlab.com:org/repo.git
Package: pkg@1.2.3.tgz
Short number: +12345678
Commits by noreply@anthropic.com and someone@example.com
The score rose by +1.4 points on 2026-10-27, from 0.28 to 0.30.
A score change of +0.123456789 and a map point at +40.7128-074.0060/
The setting is CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1
"apiKeyHelper": "/bin/generate_temp_api_key.sh"
private_key_path = "keys/deploy.pem"
PRIVATE_KEY_FILE=keys/deploy.pem
DB_PASSWORD_FILE=db_password_v2
client_secret: "/run/secrets/client"
api_key: "deploy-key.pem"
A number with a +0 prefix: +0 123 456 7890
An uppercase code that passes the IBAN checksum but has few digits: GB75WESTABCDEFGHIJKLMN
Get-FileHash output:
AE30F5763AC43FB0820A56062566F4CA77527FEF0835B12A4234511F7983574F
EE4395F8B1C766F5D8FA8D3A91CD331C8C2DF570558F2825C19A23DA13CBF483
BE717583B856B62537C980DF1EA10A861A21B9977F51EBE1FCBB02F099ABBE30
EOF
(cd "$sb" && git add tricky-clean.md)
if expect_landed "secrets plant 13" grep -q "apiKeyHelper" "$sb/tricky-clean.md"; then
  expect_green "secrets green on ordinary text that looks close to the rules" "$sb" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# --- rule map ------------------------------------------------------------------------
# 24. a rule marked done whose ID is not in its home
sb=$(make_sandbox)
printf '| M999 | planted rule | test | README.md | done |\n' >>"$sb/docs/rule-map.md"
if expect_landed "rule-map plant 1" grep -q "M999" "$sb/docs/rule-map.md"; then
  expect_red "rule-map red when a done rule is missing from its home" "$sb" "M999 is marked done but 'M999' is not in README.md" bash scripts/dev/check-rule-map.sh
fi
drop_sandbox "$sb"

# 25. a rule marked done whose home does not exist
sb=$(make_sandbox)
printf '| M998 | planted rule | test | no/such/file.md | done |\n' >>"$sb/docs/rule-map.md"
if expect_landed "rule-map plant 2" grep -q "M998" "$sb/docs/rule-map.md"; then
  expect_red "rule-map red when a done rule's home is missing" "$sb" "M998 is marked done but its home no/such/file.md does not exist" bash scripts/dev/check-rule-map.sh
fi
drop_sandbox "$sb"

# 26. a malformed rule ID is an error, not a skipped row
sb=$(make_sandbox)
printf '| MO42 | planted rule | test | no/such/file.md | done |\n' >>"$sb/docs/rule-map.md"
if expect_landed "rule-map plant 3" grep -q "MO42" "$sb/docs/rule-map.md"; then
  expect_red "rule-map red on a malformed rule ID" "$sb" "malformed rule ID 'MO42'" bash scripts/dev/check-rule-map.sh
fi
drop_sandbox "$sb"

# 27. a row that starts with a space is still read, not skipped
sb=$(make_sandbox)
printf ' | MO41 | planted rule | test | no/such/file.md | done |\n' >>"$sb/docs/rule-map.md"
if expect_landed "rule-map plant 4" grep -q "^ | MO41" "$sb/docs/rule-map.md"; then
  expect_red "rule-map red on a bad row that starts with a space" "$sb" "malformed rule ID 'MO41'" bash scripts/dev/check-rule-map.sh
fi
drop_sandbox "$sb"

# 28. the rule map cannot be a rule's home (it contains every ID)
sb=$(make_sandbox)
printf '| M997 | planted rule | test | docs/rule-map.md | done |\n' >>"$sb/docs/rule-map.md"
if expect_landed "rule-map plant 5" grep -q "M997" "$sb/docs/rule-map.md"; then
  expect_red "rule-map red when a rule names the rule map as its home" "$sb" "M997 names the rule map itself as its home" bash scripts/dev/check-rule-map.sh
fi
drop_sandbox "$sb"

# 29. the same, written as ./docs/rule-map.md
sb=$(make_sandbox)
printf '| M996 | planted rule | test | ./docs/rule-map.md | done |\n' >>"$sb/docs/rule-map.md"
if expect_landed "rule-map plant 6" grep -q "M996" "$sb/docs/rule-map.md"; then
  expect_red "rule-map red when the rule map is named with ./ as a home" "$sb" "M996 names the rule map itself as its home" bash scripts/dev/check-rule-map.sh
fi
drop_sandbox "$sb"

# --- workflows --------------------------------------------------------------------------
write_workflow() { # write_workflow FILE INDENT USES PERMISSIONS TIMEOUT(yes|no)
  i=$2
  {
    echo "name: planted"
    echo "on: push"
    [ -n "$4" ] && echo "permissions: $4"
    echo "jobs:"
    echo "${i}build:"
    echo "${i}${i}runs-on: ubuntu-latest"
    [ "$5" = yes ] && echo "${i}${i}timeout-minutes: 5"
    echo "${i}${i}steps:"
    echo "${i}${i}${i}- uses: $3"
  } >"$1"
}

# 30. an action pinned to a tag instead of a commit
sb=$(make_sandbox)
write_workflow "$sb/.github/workflows/planted.yml" "  " "actions/checkout@v7" "read-all" yes
(cd "$sb" && git add .github/workflows/planted.yml)
if expect_landed "workflows plant 1" grep -q "checkout@v7" "$sb/.github/workflows/planted.yml"; then
  expect_red "workflows red on an action pinned by tag" "$sb" "'actions/checkout@v7' is not pinned to a commit SHA" bash scripts/dev/lint-workflows.sh
fi
drop_sandbox "$sb"

# 31. a job without a timeout (2-space indentation)
sb=$(make_sandbox)
write_workflow "$sb/.github/workflows/planted.yml" "  " "$pinned" "read-all" no
(cd "$sb" && git add .github/workflows/planted.yml)
if expect_landed "workflows plant 2" sh -c "! grep -q timeout-minutes '$sb/.github/workflows/planted.yml'"; then
  expect_red "workflows red on a job without a timeout" "$sb" "planted.yml: job 'build' has no timeout-minutes" bash scripts/dev/lint-workflows.sh
fi
drop_sandbox "$sb"

# 32. a job without a timeout (4-space indentation)
sb=$(make_sandbox)
write_workflow "$sb/.github/workflows/planted.yml" "    " "$pinned" "read-all" no
(cd "$sb" && git add .github/workflows/planted.yml)
if expect_landed "workflows plant 3" grep -q "^    build:" "$sb/.github/workflows/planted.yml"; then
  expect_red "workflows red on a 4-space job without a timeout" "$sb" "planted.yml: job 'build' has no timeout-minutes" bash scripts/dev/lint-workflows.sh
fi
drop_sandbox "$sb"

# 33. a job without a timeout whose key line ends in a comment
sb=$(make_sandbox)
cat >"$sb/.github/workflows/planted.yml" <<'EOF'
name: planted
on: push
permissions:
  contents: read
jobs:
  build:   # compile
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
EOF
(cd "$sb" && git add .github/workflows/planted.yml)
if expect_landed "workflows plant 4" grep -q "build:   # compile" "$sb/.github/workflows/planted.yml"; then
  expect_red "workflows red on a commented job key without a timeout" "$sb" "planted.yml: job 'build' has no timeout-minutes" bash scripts/dev/lint-workflows.sh
fi
drop_sandbox "$sb"

# 34. no top-level permissions
sb=$(make_sandbox)
write_workflow "$sb/.github/workflows/planted.yml" "  " "$pinned" "" yes
(cd "$sb" && git add .github/workflows/planted.yml)
if expect_landed "workflows plant 5" sh -c "! grep -q '^permissions' '$sb/.github/workflows/planted.yml'"; then
  expect_red "workflows red without top-level permissions" "$sb" "planted.yml: no top-level permissions" bash scripts/dev/lint-workflows.sh
fi
drop_sandbox "$sb"

# 35. write-all permissions at the top level
sb=$(make_sandbox)
write_workflow "$sb/.github/workflows/planted.yml" "  " "$pinned" "write-all" yes
(cd "$sb" && git add .github/workflows/planted.yml)
if expect_landed "workflows plant 6" grep -q "^permissions: write-all" "$sb/.github/workflows/planted.yml"; then
  expect_red "workflows red on write-all permissions" "$sb" "planted.yml:3: permissions are write-all" bash scripts/dev/lint-workflows.sh
fi
drop_sandbox "$sb"

# 36. write-all permissions in quotes
sb=$(make_sandbox)
write_workflow "$sb/.github/workflows/planted.yml" "  " "$pinned" '"write-all"' yes
(cd "$sb" && git add .github/workflows/planted.yml)
if expect_landed "workflows plant 7" grep -q '^permissions: "write-all"' "$sb/.github/workflows/planted.yml"; then
  expect_red "workflows red on quoted write-all permissions" "$sb" "planted.yml:3: permissions are write-all" bash scripts/dev/lint-workflows.sh
fi
drop_sandbox "$sb"

# 37. write-all permissions on one job
sb=$(make_sandbox)
cat >"$sb/.github/workflows/planted.yml" <<'EOF'
name: planted
on: push
permissions:
  contents: read
jobs:
  build:
    runs-on: ubuntu-latest
    permissions: write-all
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
EOF
(cd "$sb" && git add .github/workflows/planted.yml)
if expect_landed "workflows plant 8" grep -q "^    permissions: write-all" "$sb/.github/workflows/planted.yml"; then
  expect_red "workflows red on job-level write-all permissions" "$sb" "planted.yml:8: permissions are write-all" bash scripts/dev/lint-workflows.sh
fi
drop_sandbox "$sb"

# --- perl syntax (run through validate.sh) -------------------------------------------------
# 38. a perl file that does not compile
sb=$(make_sandbox)
printf 'use strict;\nmy %sx = ;\n' "$d" >"$sb/scripts/dev/lib/planted.pl"
(cd "$sb" && git add scripts/dev/lib/planted.pl)
if expect_landed "perl-syntax plant" grep -q "= ;" "$sb/scripts/dev/lib/planted.pl"; then
  expect_red "perl-syntax red on a file that does not compile" "$sb" "perl-syntax: FAIL - 1 of" bash scripts/dev/validate.sh
fi
drop_sandbox "$sb"

# --- shellcheck (run through validate.sh) --------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  # 39. an unchecked cd
  sb=$(make_sandbox)
  printf '#!/usr/bin/env bash\ncd "%s1"\nrm -f ./tmpfile\n' "$d" >"$sb/planted-cd.sh"
  (cd "$sb" && git add planted-cd.sh)
  if expect_landed "shellcheck plant 1" grep -q -F "cd \"${d}1\"" "$sb/planted-cd.sh"; then
    out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
    if printf '%s\n' "$out" | grep -q "In planted-cd.sh line 2" &&
      printf '%s\n' "$out" | grep -q "SC2164" &&
      printf '%s\n' "$out" | grep -q "validate: FAIL - shellcheck"; then
      pass "shellcheck red on an unchecked cd"
    else
      fail "shellcheck red on an unchecked cd" "$out"
    fi
  fi
  drop_sandbox "$sb"

  # 40. an unquoted variable
  sb=$(make_sandbox)
  printf '#!/usr/bin/env bash\nf=%s1\nrm -f %sf\n' "$d" "$d" >"$sb/planted-unquoted.sh"
  (cd "$sb" && git add planted-unquoted.sh)
  if expect_landed "shellcheck plant 2" grep -q -F "rm -f ${d}f" "$sb/planted-unquoted.sh"; then
    out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
    if printf '%s\n' "$out" | grep -q "In planted-unquoted.sh line 3" &&
      printf '%s\n' "$out" | grep -q "SC2086" &&
      printf '%s\n' "$out" | grep -q "validate: FAIL - shellcheck"; then
      pass "shellcheck red on an unquoted variable"
    else
      fail "shellcheck red on an unquoted variable" "$out"
    fi
  fi
  drop_sandbox "$sb"
elif [ "${REQUIRE_SHELLCHECK:-0}" = "1" ]; then
  fail "shellcheck plants: shellcheck is required here but not installed"
else
  skip "shellcheck plants: shellcheck not installed"
fi

echo "plants: repo checks: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
