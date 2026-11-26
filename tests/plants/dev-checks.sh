#!/usr/bin/env bash
# Plants for the repo checks in scripts/dev/. Each check must be green on a
# clean copy and red, for its stated reason, on a copy with the planted defect.
# Strings that would trip the checks are assembled at run time, so this file
# itself stays clean. Each plant first confirms it really landed in the file.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

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

# crlf_in_index DIR FILE: git has FILE with CRLF line endings in its index.
crlf_in_index() {
  (cd "$1" && git ls-files --eol -- "$2" | grep -q i/crlf)
}

# lacks TEXT FILE: no line of FILE matches TEXT.
lacks() {
  ! grep -q -- "$1" "$2"
}

# lacks_lf FILE: the file holds no LF byte.
lacks_lf() {
  perl -e 'open my $f, "<:raw", $ARGV[0] or exit 2; local $/; my $b = <$f>; exit(index($b, "\n") < 0 ? 0 : 1)' "$1"
}

# staged_has DIR FILE TEXT: the staged copy of FILE contains TEXT.
staged_has() {
  (cd "$1" && git show ":$2" | grep -q -- "$3")
}

# git_warns DIR: git diff in DIR prints a warning.
git_warns() {
  (cd "$1" && git diff --name-only 2>&1 >/dev/null | grep -q "^warning:")
}

# eol_is DIR FILE EOL: git reports EOL (such as i/-text) for FILE's index copy.
eol_is() {
  (cd "$1" && git ls-files --eol -- "$2" | grep -q -- "$3")
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
sb=$(make_sandbox) || abort_sandbox
printf '#!/usr/bin/env bash\r\necho hi\r\n' >"$sb/planted-crlf.sh"
(cd "$sb" && git -c core.autocrlf=false -c core.safecrlf=false add planted-crlf.sh)
if expect_landed "line-endings plant 1" grep -q "$(printf '\r')" "$sb/planted-crlf.sh"; then
  expect_red "line-endings red on a CRLF file in the working tree" "$sb" "CRLF in planted-crlf.sh" bash scripts/dev/check-line-endings.sh
fi
drop_sandbox "$sb"

# 2. CRLF committed in the index, so a fresh clone gets it
sb=$(make_sandbox) || abort_sandbox
printf '#!/usr/bin/env bash\r\necho hi\r\n' >"$sb/planted-crlf-index.sh"
# hash-object --no-filters stores the bytes as they are, so the index gets CRLF
(cd "$sb" && oid=$(git hash-object -w --no-filters planted-crlf-index.sh) && git update-index --add --cacheinfo "100644,$oid,planted-crlf-index.sh" && git commit -q -m plant)
# the working copy goes back to LF, so only the index holds CRLF
printf '#!/usr/bin/env bash\necho hi\n' >"$sb/planted-crlf-index.sh"
if expect_landed "line-endings plant 2" crlf_in_index "$sb" planted-crlf-index.sh; then
  expect_red "line-endings red on a CRLF file committed to the index" "$sb" "CRLF in planted-crlf-index.sh (i/crlf w/lf)" bash scripts/dev/check-line-endings.sh
fi
drop_sandbox "$sb"

# 3. nothing to examine is a failure, not a pass
src_root=$(repo_root)
sb=$(new_sandbox_dir) || abort_sandbox
(cd "$sb" && git init -q && mkdir -p scripts/dev && cp "$src_root/scripts/dev/check-line-endings.sh" scripts/dev/)
expect_red "line-endings red when it examined nothing" "$sb" "examined 0" bash scripts/dev/check-line-endings.sh
drop_sandbox "$sb"

# --- portability ---------------------------------------------------------------
# 4. associative array (bash 4)
sb=$(make_sandbox) || abort_sandbox
bash4_text="declare -"'A'
printf '#!/usr/bin/env bash\n%s colours\n' "$bash4_text" >"$sb/planted-bash4.sh"
(cd "$sb" && git add planted-bash4.sh)
if expect_landed "portability plant 1" grep -q -F -- "$bash4_text" "$sb/planted-bash4.sh"; then
  expect_red "portability red on an associative array" "$sb" "planted-bash4.sh:2: associative arrays" bash scripts/dev/lint-portability.sh
fi
drop_sandbox "$sb"

# 4b. the same in an example's script: the lint covers examples/ (step 7.7)
sb=$(make_sandbox) || abort_sandbox
printf '%s colours\n' "$bash4_text" >>"$sb/examples/word-game/project/game.sh"
ex_line=$(wc -l <"$sb/examples/word-game/project/game.sh" | tr -d ' ')
if expect_landed "portability plant 1b" grep -q -F -- "$bash4_text" "$sb/examples/word-game/project/game.sh"; then
  expect_red "portability red on an associative array in an example's script" "$sb" "examples/word-game/project/game.sh:$ex_line: associative arrays" bash scripts/dev/lint-portability.sh
fi
drop_sandbox "$sb"

# 5. GNU-only in-place sed, with another flag before it
sb=$(make_sandbox) || abort_sandbox
sed_text="sed -E -"'i'
printf '#!/usr/bin/env bash\n%s s/a/b/ file.txt\n' "$sed_text" >"$sb/planted-sed.sh"
(cd "$sb" && git add planted-sed.sh)
if expect_landed "portability plant 2" grep -q -F -- "$sed_text" "$sb/planted-sed.sh"; then
  expect_red "portability red on in-place sed after another flag" "$sb" "planted-sed.sh:2: sed -i differs" bash scripts/dev/lint-portability.sh
fi
drop_sandbox "$sb"

# 6. a here-doc inside a command substitution (bash 3.2 parser trap)
sb=$(make_sandbox) || abort_sandbox
printf '#!/usr/bin/env bash\n%s(cat <<%s\nhello\nEOF\n)\necho "%sx"\n' "x=$d" "'EOF'" "$d" >"$sb/planted-heredoc.sh"
(cd "$sb" && git add planted-heredoc.sh)
if expect_landed "portability plant 3" grep -q -F -- "$d(cat <<" "$sb/planted-heredoc.sh"; then
  expect_red "portability red on a here-doc inside a command substitution" "$sb" "planted-heredoc.sh:2: a here-doc inside" bash scripts/dev/lint-portability.sh
fi
drop_sandbox "$sb"

# 7. a here-string in a $( ) that runs onto the next line is not called a here-doc
sb=$(make_sandbox) || abort_sandbox
printf '#!/usr/bin/env bash\n%s(wc -l <<<"%sy" |\n  tr -d " ")\n' "x=$d" "$d" >"$sb/planted-herestring.sh"
(cd "$sb" && git add planted-herestring.sh)
if expect_landed "portability plant 4" grep -q -F -- "<<<" "$sb/planted-herestring.sh"; then
  expect_red "portability names a multi-line ${d}( ) with a here-string correctly" "$sb" "planted-herestring.sh:2: a ${d}( ) that continues onto the next line" bash scripts/dev/lint-portability.sh
fi
drop_sandbox "$sb"

# 8. the -v test in single brackets (bash 4.2)
sb=$(make_sandbox) || abort_sandbox
v_text='[ -''v HOME ]'
printf '#!/usr/bin/env bash\nif %s; then echo set; fi\n' "$v_text" >"$sb/planted-v.sh"
(cd "$sb" && git add planted-v.sh)
if expect_landed "portability plant 5" grep -q -F -- "$v_text" "$sb/planted-v.sh"; then
  expect_red "portability red on the -v test" "$sb" "planted-v.sh:2: the -v test" bash scripts/dev/lint-portability.sh
fi
drop_sandbox "$sb"

# 9. valid bash 3.2 code that looks close to the rules stays green
sb=$(make_sandbox) || abort_sandbox
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
sb=$(make_sandbox) || abort_sandbox
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
sb=$(make_sandbox) || abort_sandbox
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
sb=$(make_sandbox) || abort_sandbox
printf '%s="%s"\n' "DB_PASS""WORD" "Sup3rS3cretValue" >"$sb/planted-cred.py"
(cd "$sb" && git add planted-cred.py)
if expect_landed "secrets plant 2" grep -q "Sup3r" "$sb/planted-cred.py"; then
  expect_red "secrets red on a credential in a longer name" "$sb" "planted-cred.py:1: hard-coded credential" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 13. an env-file style credential without quotes
sb=$(make_sandbox) || abort_sandbox
printf '%s=%s\n' "API_TO""KEN" "abcd1234efgh5678ijkl" >"$sb/planted.env.example"
(cd "$sb" && git add -f planted.env.example)
if expect_landed "secrets plant 3" grep -q "abcd1234" "$sb/planted.env.example"; then
  expect_red "secrets red on an env-style credential" "$sb" "planted.env.example:1: credential in an env-style assignment" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 14. a personal email address
sb=$(make_sandbox) || abort_sandbox
printf 'Contact: %s@%s\n' "jane.doe.1987" "gmail.com" >"$sb/planted-email.md"
(cd "$sb" && git add planted-email.md)
if expect_landed "secrets plant 4" grep -q "gmail" "$sb/planted-email.md"; then
  expect_red "secrets red on a personal email" "$sb" "planted-email.md:1: email address" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 15. personal email addresses at domains that end like file names
#     (.md Moldova, .py Paraguay, .rs Serbia, .sh Saint Helena)
sb=$(make_sandbox) || abort_sandbox
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
sb=$(make_sandbox) || abort_sandbox
printf 'Call %s %s today\n' "+41" "79 123 45 67" >"$sb/planted-phone.md"
(cd "$sb" && git add planted-phone.md)
if expect_landed "secrets plant 6" grep -q "79 123" "$sb/planted-phone.md"; then
  expect_red "secrets red on a phone number in short groups" "$sb" "planted-phone.md:1: phone number" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 17. an IBAN written in groups and followed by more text
sb=$(make_sandbox) || abort_sandbox
printf 'IBAN: %s %s BIC: %s\n' "DE89" "3704 0044 0532 0130 00" "COBADEFFXXX" >"$sb/planted-iban.md"
(cd "$sb" && git add planted-iban.md)
if expect_landed "secrets plant 7" grep -q "BIC" "$sb/planted-iban.md"; then
  expect_red "secrets red on an IBAN followed by more text" "$sb" "planted-iban.md:1: bank account number" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 18. an API key in a UTF-16LE file with a byte-order mark (Windows PowerShell's default output)
sb=$(make_sandbox) || abort_sandbox
perl -e 'print "\xFF\xFE", pack("v*", unpack("C*", $ARGV[0]))' "ANTHROPIC_KEY=$key" >"$sb/planted-utf16.txt"
(cd "$sb" && git add planted-utf16.txt)
if expect_landed "secrets plant 8" starts_with "$sb/planted-utf16.txt" fffe; then
  expect_red "secrets red on a key in a UTF-16LE file" "$sb" "planted-utf16.txt:1: Anthropic API key" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 19. an API key in a UTF-16BE file without a byte-order mark
sb=$(make_sandbox) || abort_sandbox
perl -e 'print pack("n*", unpack("C*", $ARGV[0]))' "ANTHROPIC_KEY=$key" >"$sb/planted-utf16be.txt"
(cd "$sb" && git add planted-utf16be.txt)
if expect_landed "secrets plant 9" starts_with "$sb/planted-utf16be.txt" 0041; then
  expect_red "secrets red on a key in a UTF-16BE file without a byte-order mark" "$sb" "planted-utf16be.txt:1: Anthropic API key" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 20. an API key in a file that one NUL byte makes look binary
sb=$(make_sandbox) || abort_sandbox
printf 'header\000ANTHROPIC_KEY=%s\n' "$key" >"$sb/planted-blob.bin"
(cd "$sb" && git add planted-blob.bin)
if expect_landed "secrets plant 10" has_nul "$sb/planted-blob.bin"; then
  expect_red "secrets red on a key inside a binary file" "$sb" "planted-blob.bin (binary): Anthropic API key" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 21. an API key after 4 KB of NUL bytes (padding as in a tar file)
sb=$(make_sandbox) || abort_sandbox
perl -e 'print "\0" x 4096, "ANTHROPIC_KEY=$ARGV[0]\n"' "$key" >"$sb/planted-padded.tar"
(cd "$sb" && git add planted-padded.tar)
if expect_landed "secrets plant 11" starts_with "$sb/planted-padded.tar" 00000000; then
  expect_red "secrets red on a key after many NUL bytes" "$sb" "planted-padded.tar (raw bytes): Anthropic API key" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 22. a binary file without secrets stays green, and the pass line names it
sb=$(make_sandbox) || abort_sandbox
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
sb=$(make_sandbox) || abort_sandbox
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
sb=$(make_sandbox) || abort_sandbox
printf '| M999 | planted rule | test | README.md | done |\n' >>"$sb/docs/rule-map.md"
if expect_landed "rule-map plant 1" grep -q "M999" "$sb/docs/rule-map.md"; then
  expect_red "rule-map red when a done rule is missing from its home" "$sb" "M999 is marked done but 'M999' is not in README.md" bash scripts/dev/check-rule-map.sh
fi
drop_sandbox "$sb"

# 25. a rule marked done whose home does not exist
sb=$(make_sandbox) || abort_sandbox
printf '| M998 | planted rule | test | no/such/file.md | done |\n' >>"$sb/docs/rule-map.md"
if expect_landed "rule-map plant 2" grep -q "M998" "$sb/docs/rule-map.md"; then
  expect_red "rule-map red when a done rule's home is missing" "$sb" "M998 is marked done but its home no/such/file.md does not exist" bash scripts/dev/check-rule-map.sh
fi
drop_sandbox "$sb"

# 26. a malformed rule ID is an error, not a skipped row
sb=$(make_sandbox) || abort_sandbox
printf '| MO42 | planted rule | test | no/such/file.md | done |\n' >>"$sb/docs/rule-map.md"
if expect_landed "rule-map plant 3" grep -q "MO42" "$sb/docs/rule-map.md"; then
  expect_red "rule-map red on a malformed rule ID" "$sb" "malformed rule ID 'MO42'" bash scripts/dev/check-rule-map.sh
fi
drop_sandbox "$sb"

# 27. a row that starts with a space is still read, not skipped
sb=$(make_sandbox) || abort_sandbox
printf ' | MO41 | planted rule | test | no/such/file.md | done |\n' >>"$sb/docs/rule-map.md"
if expect_landed "rule-map plant 4" grep -q "^ | MO41" "$sb/docs/rule-map.md"; then
  expect_red "rule-map red on a bad row that starts with a space" "$sb" "malformed rule ID 'MO41'" bash scripts/dev/check-rule-map.sh
fi
drop_sandbox "$sb"

# 28. the rule map cannot be a rule's home (it contains every ID)
sb=$(make_sandbox) || abort_sandbox
printf '| M997 | planted rule | test | docs/rule-map.md | done |\n' >>"$sb/docs/rule-map.md"
if expect_landed "rule-map plant 5" grep -q "M997" "$sb/docs/rule-map.md"; then
  expect_red "rule-map red when a rule names the rule map as its home" "$sb" "M997 names the rule map itself as its home" bash scripts/dev/check-rule-map.sh
fi
drop_sandbox "$sb"

# 29. the same, written as ./docs/rule-map.md
sb=$(make_sandbox) || abort_sandbox
printf '| M996 | planted rule | test | ./docs/rule-map.md | done |\n' >>"$sb/docs/rule-map.md"
if expect_landed "rule-map plant 6" grep -q "M996" "$sb/docs/rule-map.md"; then
  expect_red "rule-map red when the rule map is named with ./ as a home" "$sb" "M996 names the rule map itself as its home" bash scripts/dev/check-rule-map.sh
fi
drop_sandbox "$sb"

# 29b. a status that names no step is an error (a step may carry one letter, as 4b)
sb=$(make_sandbox) || abort_sandbox
printf '| M995 | planted rule | test | README.md | step 4bc |\n' >>"$sb/docs/rule-map.md"
if expect_landed "rule-map plant 7" grep -q "M995" "$sb/docs/rule-map.md"; then
  expect_red "rule-map red on a status that names no step" "$sb" "M995 has unknown status 'step 4bc'" bash scripts/dev/check-rule-map.sh
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
sb=$(make_sandbox) || abort_sandbox
write_workflow "$sb/.github/workflows/planted.yml" "  " "actions/checkout@v7" "read-all" yes
(cd "$sb" && git add .github/workflows/planted.yml)
if expect_landed "workflows plant 1" grep -q "checkout@v7" "$sb/.github/workflows/planted.yml"; then
  expect_red "workflows red on an action pinned by tag" "$sb" "'actions/checkout@v7' is not pinned to a commit SHA" bash scripts/dev/lint-workflows.sh
fi
drop_sandbox "$sb"

# 31. a job without a timeout (2-space indentation)
sb=$(make_sandbox) || abort_sandbox
write_workflow "$sb/.github/workflows/planted.yml" "  " "$pinned" "read-all" no
(cd "$sb" && git add .github/workflows/planted.yml)
if expect_landed "workflows plant 2" lacks timeout-minutes "$sb/.github/workflows/planted.yml"; then
  expect_red "workflows red on a job without a timeout" "$sb" "planted.yml: job 'build' has no timeout-minutes" bash scripts/dev/lint-workflows.sh
fi
drop_sandbox "$sb"

# 32. a job without a timeout (4-space indentation)
sb=$(make_sandbox) || abort_sandbox
write_workflow "$sb/.github/workflows/planted.yml" "    " "$pinned" "read-all" no
(cd "$sb" && git add .github/workflows/planted.yml)
if expect_landed "workflows plant 3" grep -q "^    build:" "$sb/.github/workflows/planted.yml"; then
  expect_red "workflows red on a 4-space job without a timeout" "$sb" "planted.yml: job 'build' has no timeout-minutes" bash scripts/dev/lint-workflows.sh
fi
drop_sandbox "$sb"

# 33. a job without a timeout whose key line ends in a comment
sb=$(make_sandbox) || abort_sandbox
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
sb=$(make_sandbox) || abort_sandbox
write_workflow "$sb/.github/workflows/planted.yml" "  " "$pinned" "" yes
(cd "$sb" && git add .github/workflows/planted.yml)
if expect_landed "workflows plant 5" lacks "^permissions" "$sb/.github/workflows/planted.yml"; then
  expect_red "workflows red without top-level permissions" "$sb" "planted.yml: no top-level permissions" bash scripts/dev/lint-workflows.sh
fi
drop_sandbox "$sb"

# 35. write-all permissions at the top level
sb=$(make_sandbox) || abort_sandbox
write_workflow "$sb/.github/workflows/planted.yml" "  " "$pinned" "write-all" yes
(cd "$sb" && git add .github/workflows/planted.yml)
if expect_landed "workflows plant 6" grep -q "^permissions: write-all" "$sb/.github/workflows/planted.yml"; then
  expect_red "workflows red on write-all permissions" "$sb" "planted.yml:3: permissions are write-all" bash scripts/dev/lint-workflows.sh
fi
drop_sandbox "$sb"

# 36. write-all permissions in quotes
sb=$(make_sandbox) || abort_sandbox
write_workflow "$sb/.github/workflows/planted.yml" "  " "$pinned" '"write-all"' yes
(cd "$sb" && git add .github/workflows/planted.yml)
if expect_landed "workflows plant 7" grep -q '^permissions: "write-all"' "$sb/.github/workflows/planted.yml"; then
  expect_red "workflows red on quoted write-all permissions" "$sb" "planted.yml:3: permissions are write-all" bash scripts/dev/lint-workflows.sh
fi
drop_sandbox "$sb"

# 37. write-all permissions on one job
sb=$(make_sandbox) || abort_sandbox
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

# --- hostile names and content (step 1b) -----------------------------------------------
# can_create DIR NAME: this file system allows a file called NAME. Windows does
# not allow a newline or a colon in a name, so those plants are skipped there.
can_create() {
  : >"$1/$2" 2>/dev/null && rm -f "$1/$2"
}
esc_char=$(printf '\033')

# 38. a file name holding a newline and "BAD 0" cannot turn the secret scan's FAIL into a PASS
sb=$(make_sandbox) || abort_sandbox
nl_name=$(printf 'logo\nBAD 0\n.gif')
if can_create "$sb" "$nl_name"; then
  printf 'ANTHROPIC_KEY=%s\n' "$key" >"$sb/planted-key.txt"
  printf 'GIF89a\000plain\n' >"$sb/$nl_name"
  (cd "$sb" && git add planted-key.txt "$nl_name")
  if expect_landed "hostile-name plant 1" has_nul "$sb/$nl_name"; then
    expect_red "secrets red despite a file name holding a newline and BAD 0" "$sb" "planted-key.txt:1: Anthropic API key" bash scripts/dev/scan-secrets.sh
    expect_red "secrets shows that file name escaped, on one line" "$sb" 'logo\x0ABAD 0\x0A.gif' bash scripts/dev/scan-secrets.sh
  fi
else
  skip "secrets with a newline in a file name: this file system does not allow one"
fi
drop_sandbox "$sb"

# 39. the same for the portability lint
sb=$(make_sandbox) || abort_sandbox
nl_name=$(printf 'p\nBAD 0\n.sh')
if can_create "$sb" "$nl_name"; then
  printf '#!/usr/bin/env bash\n%s colours\n' "declare -""A" >"$sb/$nl_name"
  (cd "$sb" && git add "$nl_name")
  if expect_landed "hostile-name plant 2" grep -q "declare" "$sb/$nl_name"; then
    expect_red "portability red despite a file name holding a newline and BAD 0" "$sb" 'p\x0ABAD 0\x0A.sh:2: associative arrays' bash scripts/dev/lint-portability.sh
  fi
else
  skip "portability with a newline in a file name: this file system does not allow one"
fi
drop_sandbox "$sb"

# 40. the same for the workflow lint
sb=$(make_sandbox) || abort_sandbox
nl_name=$(printf '.github/workflows/w\nBAD 0\n.yml')
if can_create "$sb" "$nl_name"; then
  write_workflow "$sb/$nl_name" "  " "actions/checkout@v7" "read-all" yes
  (cd "$sb" && git add "$nl_name")
  if expect_landed "hostile-name plant 3" grep -q "checkout@v7" "$sb/$nl_name"; then
    expect_red "workflows red despite a file name holding a newline and BAD 0" "$sb" "'actions/checkout@v7' is not pinned to a commit SHA" bash scripts/dev/lint-workflows.sh
  fi
else
  skip "workflows with a newline in a file name: this file system does not allow one"
fi
drop_sandbox "$sb"

# 41. control characters in content are escaped, never printed raw
sb=$(make_sandbox) || abort_sandbox
write_workflow "$sb/.github/workflows/planted.yml" "  " "actions/checkout@v1${esc_char}[2K" "read-all" yes
(cd "$sb" && git add .github/workflows/planted.yml)
if expect_landed "hostile-content plant 1" grep -q "$esc_char" "$sb/.github/workflows/planted.yml"; then
  expect_red "workflows show a control character in a value escaped" "$sb" 'checkout@v1\x1B[2K' bash scripts/dev/lint-workflows.sh
  out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
  if printf '%s\n' "$out" | grep -q "$esc_char"; then
    fail "validate printed a raw control character from a file" "$out"
  else
    pass "validate prints no raw control character from a file"
  fi
fi
drop_sandbox "$sb"

# 42. a file name that starts with "-" is never read as a perl option (it would run code)
sb=$(make_sandbox) || abort_sandbox
inj_name='-eBEGIN{mkdir(q(INJECTED))}#.pl'
printf '1;\n' >"$sb/$inj_name"
printf 'BEGIN { mkdir "RAN" }\n1;\n' >"$sb/planted-begin.pl"
(cd "$sb" && git add -- "$inj_name" planted-begin.pl)
if expect_landed "option-name plant 1" test -f "$sb/$inj_name"; then
  (cd "$sb" && bash scripts/dev/validate.sh >/dev/null 2>&1)
  if [ -e "$sb/INJECTED" ]; then
    fail "validate ran perl code taken from a file name"
  else
    pass "validate does not run perl code taken from a file name"
  fi
  if [ -e "$sb/RAN" ]; then
    fail "validate ran a BEGIN block of a perl file outside scripts/"
  else
    pass "validate does not run BEGIN blocks of perl files outside scripts/"
  fi
fi
drop_sandbox "$sb"

# 43. validate never prints a key in full: perl -c errors and allowlist errors quote it
sb=$(make_sandbox) || abort_sandbox
printf 'my %sk = "x" "%s";\n' "$d" "$key" >"$sb/scripts/dev/lib/planted-leak.pl"
printf '%s\n' "$key" >>"$sb/scripts/dev/scan-allow.txt"
(cd "$sb" && git add scripts/dev/lib/planted-leak.pl scripts/dev/scan-allow.txt)
if expect_landed "leak plant 1" grep -q "api03" "$sb/scripts/dev/lib/planted-leak.pl"; then
  out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
  code=$?
  if printf '%s\n' "$out" | grep -F -q -- "$key"; then
    fail "validate printed a key in full from a perl error or an allowlist error" "$out"
  elif [ "$code" -eq 1 ] && printf '%s\n' "$out" | grep -q "perl-syntax: FAIL" && printf '%s\n' "$out" | grep -q "scan-allow.txt line"; then
    pass "validate reports the perl error and the allowlist error without printing the key"
    out=$(cd "$sb" && bash scripts/dev/scan-secrets.sh 2>&1)
    if printf '%s\n' "$out" | grep -F -q -- "$key"; then
      fail "scan-secrets printed a key in full from an allowlist error" "$out"
    else
      pass "scan-secrets names the bad allowlist line without printing it"
    fi
  else
    fail "validate reports the perl error and the allowlist error without printing the key: exit $code" "$out"
  fi
fi
drop_sandbox "$sb"

# 44. validate masks a key that a check quotes back (here a "uses:" value)
sb=$(make_sandbox) || abort_sandbox
write_workflow "$sb/.github/workflows/planted.yml" "  " "someone/action@$key" "read-all" yes
(cd "$sb" && git add .github/workflows/planted.yml)
if expect_landed "leak plant 2" grep -q "api03" "$sb/.github/workflows/planted.yml"; then
  out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
  if printf '%s\n' "$out" | grep -F -q -- "$key"; then
    fail "validate printed a key in full that the workflow lint quoted" "$out"
  elif printf '%s\n' "$out" | grep -q "is not pinned to a commit SHA"; then
    pass "validate masks a key that the workflow lint quotes"
  else
    fail "validate masks a key that the workflow lint quotes: the lint did not report the action" "$out"
  fi
fi
drop_sandbox "$sb"

# 45. a short password is shown by its length only
sb=$(make_sandbox) || abort_sandbox
printf '%s="%s"\n' "DB_PASS""WORD" "Xy7pQ2rLm9" >"$sb/planted-short.py"
(cd "$sb" && git add planted-short.py)
if expect_landed "mask plant 1" grep -q "Xy7pQ2rLm9" "$sb/planted-short.py"; then
  expect_red "secrets shows a short password by its length only" "$sb" "planted-short.py:1: hard-coded credential: ***(10 chars)" bash scripts/dev/scan-secrets.sh
  out=$(cd "$sb" && bash scripts/dev/scan-secrets.sh 2>&1)
  if printf '%s\n' "$out" | grep -q "Xy7"; then
    fail "secrets printed the start of a short password" "$out"
  else
    pass "secrets prints no part of a short password"
  fi
fi
drop_sandbox "$sb"

# 46. an allowlist entry covers one text in one file, and the pass line counts it
sb=$(make_sandbox) || abort_sandbox
printf 'Contact: %s@%s\n' "jane.doe.1987" "gmail.com" >"$sb/planted-a.md"
cp "$sb/planted-a.md" "$sb/planted-b.md"
(cd "$sb" && git add planted-a.md planted-b.md)
id=$(cd "$sb" && bash scripts/dev/scan-secrets.sh --ids 2>&1 | sed -n 's/^secrets: planted-a\.md:1: .*\[id \([0-9a-f]\{12\}\)\]$/\1/p')
if expect_landed "allowlist plant 1" test -n "$id"; then
  printf 'planted-a.md\t%s\ttest fixture\n' "$id" >>"$sb/scripts/dev/scan-allow.txt"
  (cd "$sb" && git add scripts/dev/scan-allow.txt)
  expect_red "secrets: an allowlist entry for one file does not hide the same text in another" "$sb" "planted-b.md:1: email address" bash scripts/dev/scan-secrets.sh
  rm "$sb/planted-b.md"
  (cd "$sb" && git rm -q --cached planted-b.md)
  out=$(cd "$sb" && bash scripts/dev/scan-secrets.sh 2>&1)
  code=$?
  case "$code:$(printf '%s\n' "$out" | tail -n 1)" in
    "0:secrets: PASS"*"(1 allowed by scan-allow.txt)"*) pass "secrets: the allowed text passes, and the pass line counts it" ;;
    *) fail "secrets: the allowed text passes, and the pass line counts it: exit $code" "$out" ;;
  esac
fi
drop_sandbox "$sb"

# 47. a key in plain text added after UTF-16 text
sb=$(make_sandbox) || abort_sandbox
perl -e 'print "\xFF\xFE", pack("v*", unpack("C*", "hello\n")), "ANTHROPIC_KEY=$ARGV[0]\n"' "$key" >"$sb/planted-mixed.txt"
(cd "$sb" && git add planted-mixed.txt)
if expect_landed "utf16-tail plant 1" starts_with "$sb/planted-mixed.txt" fffe; then
  expect_red "secrets red on a key in plain text after UTF-16 text" "$sb" "planted-mixed.txt (raw bytes): Anthropic API key" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 48. a credential in a file whose lines end in a lone CR
sb=$(make_sandbox) || abort_sandbox
printf 'x=1\r%s=%s\r' "DB_PASS""WORD" "Xy7pQ2rLm9Kq" >"$sb/planted-cr.txt"
(cd "$sb" && git -c core.autocrlf=false -c core.safecrlf=false add planted-cr.txt)
if expect_landed "cr-only plant 1" lacks_lf "$sb/planted-cr.txt"; then
  expect_red "secrets red on a credential in a file with CR-only line ends" "$sb" "planted-cr.txt:2: credential in an env-style assignment" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 49. a key that is staged but no longer in the working copy
sb=$(make_sandbox) || abort_sandbox
printf 'clean\n' >"$sb/planted-staged.txt"
(cd "$sb" && git add planted-staged.txt && git commit -q -m clean)
printf 'ANTHROPIC_KEY=%s\n' "$key" >"$sb/planted-staged.txt"
(cd "$sb" && git add planted-staged.txt)
printf 'clean\n' >"$sb/planted-staged.txt"
if expect_landed "staged plant 1" staged_has "$sb" planted-staged.txt api03; then
  expect_red "secrets red on a key that is staged but not in the working copy" "$sb" "planted-staged.txt (staged):1: Anthropic API key" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 50. the mask filter that validate sends other tools' output through
out=$(printf 'tool said %s\n::warning::spoof\nan escape %s[2K here ##[error]x\ncall %s today\na C1 control \302\233 here\n%s="Xy7p\\x41Q2rLm9Kq"\n\302\240::error::nbsp\n' "$key" "$esc_char" "+41"" 79 123 45 67" "DB_PASS""WORD" | perl "$(repo_root)/method/scripts/method/lib/secrets.pl" --mask)
if printf '%s\n' "$out" | grep -F -q -e "$key" -e "79 123 45 67" -e "Q2rLm9Kq"; then
  fail "the mask filter printed a key, a phone number or a credential holding an escape in full" "$out"
elif printf '%s\n' "$out" | grep -q '^[[:space:]]*::' || printf '%s\n' "$out" | grep -F -q -e '##[' -e "$esc_char" -e "$(printf '\302\233')" -e "$(printf '\302\240::')"; then
  fail "the mask filter let a :: line, a ##[ command or a raw control character through" "$out"
elif printf '%s\n' "$out" | grep -F -q 'sk-a...(' && printf '%s\n' "$out" | grep -F -q -e '\x1B[2K' && printf '%s\n' "$out" | grep -F -q '\xC2\x9B'; then
  pass "the mask filter masks keys and phone numbers, escapes control characters and indents every line"
else
  fail "the mask filter masks keys and phone numbers, escapes control characters and indents every line" "$out"
fi

# 51. a helper whose result cannot be read is a failure, never a pass
for pair in "scan-secrets.sh method/scripts/method/lib/secrets.pl" "lint-portability.sh scripts/dev/lib/portability.pl" \
  "lint-workflows.sh scripts/dev/lib/workflows.pl" "check-rule-map.sh scripts/dev/lib/rule-map.pl"; do
  wrapper=${pair% *}
  helper=${pair#* }
  sb=$(make_sandbox) || abort_sandbox
  printf 'print "EXAMINED 1\\nSTAGED 0\\nACTIONS 0\\nROWS 1\\nBAD 0\\nBAD 1\\nALLOWED 0\\nSKIPPED 0\\nSKIPPED_NAMES\\nSUMMARY x\\n";\n' >"$sb/$helper"
  (cd "$sb" && git add "$helper")
  if expect_landed "count plant $wrapper" grep -q "BAD 1" "$sb/$helper"; then
    out=$(cd "$sb" && bash "scripts/dev/$wrapper" 2>&1)
    code=$?
    case "$code:$out" in
      2:*"could not read the"*) pass "$wrapper fails when its helper's counts cannot be read" ;;
      *) fail "$wrapper fails when its helper's counts cannot be read: exit $code" "$out" ;;
    esac
  fi
  drop_sandbox "$sb"
done

# 52. CRLF lines plus one lone CR, which makes git call the file binary
sb=$(make_sandbox) || abort_sandbox
printf '#!/usr/bin/env bash\r\necho "a\rb"\r\n' >"$sb/planted-crcr.sh"
(cd "$sb" && git -c core.autocrlf=false -c core.safecrlf=false add planted-crcr.sh)
if expect_landed "line-endings plant 3" eol_is "$sb" planted-crcr.sh "i/-text"; then
  expect_red "line-endings red on CRLF lines that git calls binary because of a lone CR" "$sb" "CR in planted-crcr.sh" bash scripts/dev/check-line-endings.sh
fi
drop_sandbox "$sb"

# 53. a CRLF batch file with a non-ASCII name stays green
sb=$(make_sandbox) || abort_sandbox
bat_name=$(printf 'r\303\251sum\303\251.bat')
if can_create "$sb" "$bat_name"; then
  printf '@echo off\r\necho hi\r\n' >"$sb/$bat_name"
  (cd "$sb" && git -c core.autocrlf=false -c core.safecrlf=false add "$bat_name")
  if expect_landed "line-endings plant 4" grep -q "echo hi" "$sb/$bat_name"; then
    expect_green "line-endings green on a CRLF batch file with a non-ASCII name" "$sb" bash scripts/dev/check-line-endings.sh
  fi
else
  skip "a batch file with a non-ASCII name: this file system does not allow one"
fi
drop_sandbox "$sb"

# 54. workflow forms a line reader cannot follow are findings, and valid look-alikes are not
sb=$(make_sandbox) || abort_sandbox
wf=$sb/.github/workflows
wf_head() { printf 'name: t\non: push\npermissions:\n  contents: read\njobs:\n  b:\n    runs-on: ubuntu-latest\n    timeout-minutes: 5\n    steps:\n'; }
{
  wf_head
  echo '      - uses: docker://alpine:latest'
} >"$wf/f-docker.yml"
{
  wf_head
  echo '      - "uses": actions/cache@main'
} >"$wf/f-quoted.yml"
{
  wf_head
  echo '      - { name: x, uses: actions/setup-node@v4 }'
} >"$wf/f-flow.yml"
{
  wf_head
  printf '      - uses:\n          actions/cache@main\n'
} >"$wf/f-nextline.yml"
printf 'name: t\non: push\npermissions:\n  write-all\njobs:\n  b:\n    runs-on: ubuntu-latest\n    timeout-minutes: 5\n    steps:\n      - run: true\n' >"$wf/f-wa-next.yml"
printf 'name: t\non: push\npermissions: !!str write-all\njobs:\n  b:\n    runs-on: ubuntu-latest\n    timeout-minutes: 5\n    steps:\n      - run: true\n' >"$wf/f-tag.yml"
printf 'name: t\non: push\npermissions:\n  contents: read\njobs:\n  a: {runs-on: ubuntu-latest, steps: [{run: true}]}\n' >"$wf/f-flowjob.yml"
{
  wf_head
  printf '      - ? uses\n        : actions/cache@v4\n'
} >"$wf/f-explicit.yml"
{
  wf_head
  printf '      - "u\\x73es": actions/cache@v4\n'
} >"$wf/f-escaped.yml"
printf 'name: t\non: push\npermissions: >-\n  write-all\njobs:\n  b:\n    runs-on: ubuntu-latest\n    timeout-minutes: 5\n    steps:\n      - run: true\n' >"$wf/f-blockperm.yml"
{
  wf_head
  printf '      - if: |\n          github.ref == 1\n        uses: evil/action@main\n'
} >"$wf/f-dashblock.yml"
printf '\357\273\277jobs:\n  b:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\nname: t\non: push\npermissions:\n  contents: read\n' >"$wf/f-bom.yml"
{
  wf_head
  printf '      - run: true\n    other: [ "uses":actions/cache@v4 ]\n'
} >"$wf/f-flowseq.yml"
{
  wf_head
  printf '      - name: x\n        &a uses: actions/cache@v4\n'
} >"$wf/f-anchor.yml"
{
  wf_head
  printf '      - name: x\n        !!str uses: actions/cache@v4\n'
} >"$wf/f-tagkey.yml"
{
  wf_head
  printf '      - name: "a\n          b"\n        uses: actions/cache@v4\n'
} >"$wf/f-multiquote.yml"
{
  wf_head
  printf '      - name: x\342\200\250        uses: evil/a@main\n'
} >"$wf/f-linesep.yml"
printf 'name: t\non: push\npermissions:\n  contents: read\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n    - timeout-minutes: 1\n      run: echo quick\n    - name: long\n      run: sleep 21000\n' >"$wf/f-indentless.yml"
printf 'name: t\non: push\npermissions:\n  contents: read\njobs:\n  b:\n    runs-on: ubuntu-latest\n    timeout-minutes: ~\n    steps:\n      - run: true\n' >"$wf/f-tilde.yml"
printf 'name: t\non: push\npermissions:\njobs:\n  b:\n    runs-on: ubuntu-latest\n    timeout-minutes: 5\n    steps:\n      - run: true\n' >"$wf/f-emptyperm.yml"
{
  wf_head
  printf '      - run: echo hi\n          - uses: evil/x@main\n'
} >"$wf/f-cont.yml"
{
  wf_head
  printf '      - run: true\n    other: [uses: evil/x@main]\n'
} >"$wf/f-flowmap.yml"
printf 'name: t\non: push\npermissions: &p write-all\njobs:\n  b:\n    runs-on: ubuntu-latest\n    timeout-minutes: 5\n    steps:\n      - run: true\n' >"$wf/f-anchorval.yml"
printf 'name: t\non: push\npermissions: "write\\x2dall"\njobs:\n  b:\n    runs-on: ubuntu-latest\n    timeout-minutes: 5\n    steps:\n      - run: true\n' >"$wf/f-escval.yml"
{
  wf_head
  printf '      - run: echo #\302\205      - uses: evil/a@main\n'
} >"$wf/f-nel.yml"
{
  wf_head
  printf '      - run: echo #\342\200\251      - uses: evil/a@main\n'
} >"$wf/f-ps.yml"
{
  wf_head
  printf '      - run: echo #\r      - uses: evil/a@main\n'
} >"$wf/f-cr.yml"
printf 'name: t  \non: push\npermissions:   \n  contents: read  \njobs:\n  build:  \n    runs-on: ubuntu-latest \n    timeout-minutes: %s\n    steps:\n      - uses: %s # v7  \n        with:\n          persist-credentials: false\n      - run: |\n          a\n          b\n' "${d}{{ fromJSON(vars.T) }}" "$pinned" >"$wf/g-trailing.yml"
mkdir -p "$sb/act"
printf 'runs:\n  using: composite\n  steps:\n    - uses: actions/setup-python@main\n' >"$sb/act/action.yml"
{
  wf_head
  printf '      - uses: docker://alpine@sha256:%s\n' "0000000000000000000000000000000000000000000000000000000000000000"
  printf '      - uses: %s # v7\n' "$pinned"
  printf '      - run: |\n          echo "{x}" uses: foo@main\n          { echo; }\n          uses: foo@main\n          ? x\n      - name: "**"\n        run: echo "{x}" && find . -exec true {} \\;\n'
  printf '    env:\n      A: "a: b"\n      B: '"'"'it'"'"''"'"'s'"'"'\n      C: ["a: b", x]\n    if: startsWith(github.ref, '"'"'refs/tags/v'"'"') || github.event_name == '"'"'push'"'"'\n'
  printf '    permissions: {}\n    services:\n      db:\n        image: postgres\n        ports: ["5432:5432"]\n'
  printf '    strategy:\n      matrix:\n        os: [windows-latest, macos-latest]\n'
} >"$wf/g-lookalikes.yml"
(cd "$sb" && git -c core.autocrlf=false -c core.safecrlf=false add .github/workflows act)
if expect_landed "workflows plant 9" grep -q "setup-python@main" "$sb/act/action.yml"; then
  out=$(cd "$sb" && bash scripts/dev/lint-workflows.sh 2>&1)
  code=$?
  missing=""
  plain_msg="this line is not plain YAML"
  for want in "f-docker.yml:10: 'docker://alpine:latest' is not pinned to an @sha256 digest" \
    "f-quoted.yml:10: $plain_msg" \
    "f-flow.yml:10: $plain_msg" \
    "f-nextline.yml:10: a \"uses:\" without a value" \
    "f-wa-next.yml:4: $plain_msg" \
    "f-tag.yml:3: $plain_msg" \
    "f-flowjob.yml:6: $plain_msg" \
    "act/action.yml:4: 'actions/setup-python@main' is not pinned" \
    "f-explicit.yml:10: $plain_msg" \
    "f-escaped.yml:10: $plain_msg" \
    "f-blockperm.yml:3: a block scalar as the value of permissions" \
    "f-dashblock.yml:12: 'evil/action@main' is not pinned" \
    "f-bom.yml: job 'b' has no timeout-minutes" \
    "f-flowseq.yml:11: $plain_msg" \
    "f-anchor.yml:11: $plain_msg" \
    "f-tagkey.yml:11: $plain_msg" \
    "f-multiquote.yml:10: $plain_msg" \
    "f-linesep.yml:10: a line break other than LF" \
    "f-indentless.yml: job 'build' has no timeout-minutes" \
    "f-tilde.yml: job 'b' has no timeout-minutes" \
    "f-emptyperm.yml:3: \"permissions:\" has no value" \
    "f-cont.yml:11: this line continues the value" \
    "f-flowmap.yml:11: $plain_msg" \
    "f-anchorval.yml:3: $plain_msg" \
    "f-escval.yml:3: $plain_msg" \
    "f-nel.yml:10: a line break other than LF" \
    "f-ps.yml:10: a line break other than LF" \
    "f-cr.yml:10: a line break other than LF"; do
    printf '%s\n' "$out" | grep -F -q -- "$want" || missing="$missing [$want]"
  done
  if [ "$code" -eq 1 ] && [ -z "$missing" ] && ! printf '%s\n' "$out" | grep -q -e "g-lookalikes.yml" -e "g-trailing.yml"; then
    pass "workflows flag 28 forms a line reader cannot follow, and not the valid look-alikes"
  else
    fail "workflows flag 28 forms a line reader cannot follow, and not the valid look-alikes: exit $code; missing:${missing:- none}" "$out"
  fi
fi
drop_sandbox "$sb"

# --- step 1b, review round 1 -----------------------------------------------------------
# 55. a key in a file that starts with a UTF-16 byte-order mark but holds no NUL byte
sb=$(make_sandbox) || abort_sandbox
perl -e 'print "\xFF\xFEANTHROPIC_KEY=$ARGV[0]\n"' "$key" >"$sb/planted-bom-only.txt"
(cd "$sb" && git add planted-bom-only.txt)
if expect_landed "bom plant 1" starts_with "$sb/planted-bom-only.txt" fffe; then
  expect_red "secrets red on a key after a byte-order mark with no NUL byte" "$sb" "planted-bom-only.txt (raw bytes): Anthropic API key" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 56. a key used as a file name
sb=$(make_sandbox) || abort_sandbox
printf 'GIF89a\000plain\n' >"$sb/$key.gif"
(cd "$sb" && git add -- "$key.gif")
if expect_landed "name plant 1" has_nul "$sb/$key.gif"; then
  expect_red "secrets red on a key used as a file name" "$sb" "a tracked file name (sk-a...(" bash scripts/dev/scan-secrets.sh
  out=$( (cd "$sb" && bash scripts/dev/scan-secrets.sh; bash scripts/dev/validate.sh) 2>&1)
  if printf '%s\n' "$out" | grep -F -q -- "$key"; then
    fail "scan-secrets or validate printed a key in full that was used as a file name" "$out"
  else
    pass "neither scan-secrets nor validate prints a key used as a file name"
  fi
fi
drop_sandbox "$sb"

# 57. validate's names check masks a key held in a file name
sb=$(make_sandbox) || abort_sandbox
tab_name="notes-$key$(printf '\t').txt"
if can_create "$sb" "$tab_name"; then
  printf 'hello\n' >"$sb/$tab_name"
  (cd "$sb" && git add -- "$tab_name")
  out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
  if printf '%s\n' "$out" | grep -F -q -- "$key"; then
    fail "validate printed a key in full from a file name" "$out"
  elif printf '%s\n' "$out" | grep -q "names: FAIL"; then
    pass "validate's names check masks a key held in a file name"
  else
    fail "validate's names check masks a key held in a file name: the name was not reported" "$out"
  fi
else
  skip "a tab in a file name: this file system does not allow one"
fi
drop_sandbox "$sb"

# 58. the names and stored targets of symlinks are scanned
sb=$(make_sandbox) || abort_sandbox
ln -s "missing-$key" "$sb/planted-link-target" 2>/dev/null
ln -s nowhere "$sb/link-$key" 2>/dev/null
if [ -L "$sb/planted-link-target" ] && [ -L "$sb/link-$key" ]; then
  (cd "$sb" && git add -- planted-link-target "link-$key")
  expect_red "secrets red on a key in a symlink's stored target" "$sb" "planted-link-target (link target):1: Anthropic API key" bash scripts/dev/scan-secrets.sh
  expect_red "secrets red on a key in the name of a dangling symlink" "$sb" "a tracked file name (link-sk-a...(" bash scripts/dev/scan-secrets.sh
else
  skip "symlink names and targets: this system cannot make symlinks"
fi
drop_sandbox "$sb"

# 59. the name of a staged file that is gone from the working tree is scanned too
sb=$(make_sandbox) || abort_sandbox
printf 'hello\n' >"$sb/notes-$key.md"
(cd "$sb" && git add -- "notes-$key.md")
rm -f "$sb/notes-$key.md"
if expect_landed "name plant 2" staged_has "$sb" "notes-$key.md" hello; then
  expect_red "secrets red on a key in the name of a staged file gone from the working tree" "$sb" "a tracked file name (notes-sk-a...(" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 60. a staged key in a file git was told to treat as unchanged
sb=$(make_sandbox) || abort_sandbox
printf 'clean\n' >"$sb/planted-hidden.txt"
(cd "$sb" && git add planted-hidden.txt && git commit -q -m clean)
printf 'ANTHROPIC_KEY=%s\n' "$key" >"$sb/planted-hidden.txt"
(cd "$sb" && git add planted-hidden.txt && git update-index --assume-unchanged planted-hidden.txt)
printf 'clean\n' >"$sb/planted-hidden.txt"
if expect_landed "staged plant 2" staged_has "$sb" planted-hidden.txt api03; then
  expect_red "secrets red on a staged key in a file marked assume-unchanged" "$sb" "planted-hidden.txt (staged):1: Anthropic API key" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 61. validate masks a key after a tab, and an IBAN that perl quotes
sb=$(make_sandbox) || abort_sandbox
gh_key="ghp_""ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef0123456789"
iban="DE89""370400440532013000"
write_workflow "$sb/.github/workflows/planted.yml" "  " "someone/action@$(printf '\t')$gh_key" "read-all" yes
printf 'use strict;\nmy %sx = %s;\n' "$d" "$iban" >"$sb/scripts/dev/lib/planted-iban.pl"
(cd "$sb" && git add .github/workflows/planted.yml scripts/dev/lib/planted-iban.pl)
if expect_landed "leak plant 3" grep -q "ghp_" "$sb/.github/workflows/planted.yml"; then
  out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
  if printf '%s\n' "$out" | grep -F -q -e "$gh_key" -e "$iban"; then
    fail "validate printed a key after a tab, or an IBAN from a perl error, in full" "$out"
  elif printf '%s\n' "$out" | grep -q "is not pinned" && printf '%s\n' "$out" | grep -q "perl-syntax: FAIL"; then
    pass "validate masks a key after a tab and an IBAN in a perl error"
  else
    fail "validate masks a key after a tab and an IBAN in a perl error: a planted problem was not reported" "$out"
  fi
fi
drop_sandbox "$sb"

# 62. the runner's ##[ command form in a file name never reaches the output whole
sb=$(make_sandbox) || abort_sandbox
cmd_gif='assets ##[error]Secret scan bypassed.gif'
printf 'GIF89a\000plain\n' >"$sb/$cmd_gif"
(cd "$sb" && git add -- "$cmd_gif")
if expect_landed "command-name plant 1" has_nul "$sb/$cmd_gif"; then
  out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
  if printf '%s\n' "$out" | grep -F -q '##['; then
    fail "validate printed the runner's ##[ command form from a file name" "$out"
  else
    pass "validate breaks up the runner's ##[ command form in a file name"
  fi
fi
drop_sandbox "$sb"

# 63. the runner's ##[ form and C1 control characters are broken up in every check's output,
#     also when PERL_UNICODE asks perl to read text (and file names) as characters
c1=$(printf '\302\233')
sb=$(make_sandbox) || abort_sandbox
write_workflow "$sb/.github/workflows/planted.yml" "  " "someone/action@v1##[error]x${c1}2J" "read-all" yes
printf '| M##[warning]x%s1 | planted rule | test | README.md | done |\n' "$c1" >>"$sb/docs/rule-map.md"
c1_name="p##[error]x${c1}.sh"
named=0
if can_create "$sb" "$c1_name"; then
  printf '#!/usr/bin/env bash\r\n%s colours\r\n# %s\r\n' "declare -""A" "$key" >"$sb/$c1_name"
  write_workflow "$sb/.github/workflows/p##[error]x${c1}.yml" "  " "someone/action" "read-all" yes
  named=1
fi
(cd "$sb" && git -c core.autocrlf=false -c core.safecrlf=false add -A)
if expect_landed "command-form plant 2" grep -q "##\[error\]" "$sb/.github/workflows/planted.yml"; then
  bad_out=""
  for check in lint-workflows.sh check-rule-map.sh lint-portability.sh check-line-endings.sh scan-secrets.sh; do
    case "$check" in
      lint-portability.sh | check-line-endings.sh | scan-secrets.sh) [ "$named" -eq 0 ] && continue ;;
    esac
    out=$(cd "$sb" && PERL_UNICODE=SDA bash "scripts/dev/$check" 2>&1)
    if printf '%s\n' "$out" | grep -F -q -e '##[' -e "$c1"; then
      bad_out="$bad_out
$out"
    elif ! printf '%s\n' "$out" | grep -F -q -e '#\x23[' -e '\xC2\x9B'; then
      bad_out="$bad_out
$check did not report the planted text: $out"
    fi
  done
  if [ -z "$bad_out" ]; then
    pass "workflows, rule-map, portability, line-endings and secrets break up ##[ and C1 control characters"
  else
    fail "workflows, rule-map, portability, line-endings and secrets break up ##[ and C1 control characters" "$bad_out"
  fi
fi
drop_sandbox "$sb"

# 64. a file name holding a newline fails validate's names check
sb=$(make_sandbox) || abort_sandbox
nl_name=$(printf 'notes\nx.txt')
if can_create "$sb" "$nl_name"; then
  printf 'hello\n' >"$sb/$nl_name"
  (cd "$sb" && git add -- "$nl_name")
  expect_red "validate fails a tracked file name that holds a newline" "$sb" 'names: notes\x0Ax.txt' bash scripts/dev/validate.sh
else
  skip "validate's names check: this file system does not allow a newline in a name"
fi
drop_sandbox "$sb"

# 65. a CRLF+CR file that is staged while the working copy is clean, and the reverse
sb=$(make_sandbox) || abort_sandbox
printf 'echo a\n' >"$sb/planted-stagedcr.sh"
(cd "$sb" && git add planted-stagedcr.sh && git commit -q -m clean)
printf '#!/usr/bin/env bash\r\necho "a\rb"\r\n' >"$sb/planted-stagedcr.sh"
(cd "$sb" && git -c core.autocrlf=false -c core.safecrlf=false add planted-stagedcr.sh)
printf 'echo a\n' >"$sb/planted-stagedcr.sh"
printf 'echo b\n' >"$sb/planted-worktreecr.sh"
(cd "$sb" && git add planted-worktreecr.sh)
printf '#!/usr/bin/env bash\r\necho "a\rb"\r\n' >"$sb/planted-worktreecr.sh"
if expect_landed "line-endings plant 5" eol_is "$sb" planted-stagedcr.sh "i/-text"; then
  expect_red "line-endings red on a staged copy with a lone CR" "$sb" "CR in planted-stagedcr.sh (the staged copy" bash scripts/dev/check-line-endings.sh
  expect_red "line-endings red on a working copy with a lone CR" "$sb" "CR in planted-worktreecr.sh (the working copy" bash scripts/dev/check-line-endings.sh
fi
drop_sandbox "$sb"

# 66. a file marked binary in .gitattributes may hold a CR
sb=$(make_sandbox) || abort_sandbox
printf '%%PDF-1.0\r1 0 obj\r<< >>\rendobj\r' >"$sb/planted-doc.pdf"
(cd "$sb" && git add planted-doc.pdf)
if expect_landed "line-endings plant 6" lacks_lf "$sb/planted-doc.pdf"; then
  expect_green "line-endings green on a CR-only file marked binary in .gitattributes" "$sb" bash scripts/dev/check-line-endings.sh
fi
drop_sandbox "$sb"

# 67. a CRLF file whose name holds an escape character is shown escaped
sb=$(make_sandbox) || abort_sandbox
esc_name="crlf${esc_char}[2K.sh"
if can_create "$sb" "$esc_name"; then
  printf '#!/usr/bin/env bash\r\necho hi\r\n' >"$sb/$esc_name"
  (cd "$sb" && git -c core.autocrlf=false -c core.safecrlf=false add -- "$esc_name")
  expect_red "line-endings shows a file name's escape character escaped" "$sb" 'CRLF in crlf\x1B[2K.sh' bash scripts/dev/check-line-endings.sh
else
  skip "line-endings with an escape character in a name: this file system does not allow one"
fi
drop_sandbox "$sb"

# 68. a rule-map cell holding an escape character is shown escaped
sb=$(make_sandbox) || abort_sandbox
printf '| M%s[31m1 | planted rule | test | README.md | done |\n' "$esc_char" >>"$sb/docs/rule-map.md"
if expect_landed "rule-map plant 7" grep -q "$esc_char" "$sb/docs/rule-map.md"; then
  expect_red "rule-map shows an escape character in a cell escaped" "$sb" "malformed rule ID 'M\\x1B[31m1'" bash scripts/dev/check-rule-map.sh
  out=$(cd "$sb" && bash scripts/dev/check-rule-map.sh 2>&1)
  if printf '%s\n' "$out" | grep -q "$esc_char"; then
    fail "rule-map printed a raw escape character" "$out"
  else
    pass "rule-map prints no raw escape character"
  fi
fi
drop_sandbox "$sb"

# 69. a workflow with permissions only on its job still needs top-level permissions
sb=$(make_sandbox) || abort_sandbox
printf 'name: t\non: push\njobs:\n  b:\n    runs-on: ubuntu-latest\n    permissions:\n      contents: read\n    timeout-minutes: 5\n    steps:\n      - run: true\n' >"$sb/.github/workflows/planted.yml"
(cd "$sb" && git add .github/workflows/planted.yml)
if expect_landed "workflows plant 10" lacks "^permissions" "$sb/.github/workflows/planted.yml"; then
  expect_red "workflows red when only a job sets permissions" "$sb" "planted.yml: no top-level permissions" bash scripts/dev/lint-workflows.sh
fi
drop_sandbox "$sb"

# --- step 1b, review round 2 -----------------------------------------------------------
# 70. a CRLF working copy over a staged copy that holds a NUL byte
sb=$(make_sandbox) || abort_sandbox
printf 'a\000b\n' >"$sb/planted-was-binary.md"
(cd "$sb" && git add planted-was-binary.md && git commit -q -m binary)
printf 'line one\r\nline two\r\n' >"$sb/planted-was-binary.md"
if expect_landed "line-endings plant 7" eol_is "$sb" planted-was-binary.md "i/-text"; then
  expect_red "line-endings red on a CRLF working copy over a binary staged copy" "$sb" "CRLF in planted-was-binary.md (i/-text w/crlf)" bash scripts/dev/check-line-endings.sh
fi
drop_sandbox "$sb"

# 71. a CRLF file marked binary in .gitattributes stays green
sb=$(make_sandbox) || abort_sandbox
printf '%%PDF-1.0\r\n1 0 obj\r\nendobj\r\n' >"$sb/planted-crlf-doc.pdf"
(cd "$sb" && git add planted-crlf-doc.pdf)
if expect_landed "line-endings plant 8" grep -q "endobj" "$sb/planted-crlf-doc.pdf"; then
  expect_green "line-endings green on a CRLF file marked binary in .gitattributes" "$sb" bash scripts/dev/check-line-endings.sh
fi
drop_sandbox "$sb"

# 72. the staged-copy check is not blinded by the caller's pathspec settings
sb=$(make_sandbox) || abort_sandbox
printf 'echo a\n' >"$sb/planted-pathspec.sh"
(cd "$sb" && git add planted-pathspec.sh && git commit -q -m clean)
printf '#!/usr/bin/env bash\r\necho "a\rb"\r\n' >"$sb/planted-pathspec.sh"
(cd "$sb" && git -c core.autocrlf=false -c core.safecrlf=false add planted-pathspec.sh)
printf 'echo a\n' >"$sb/planted-pathspec.sh"
if expect_landed "line-endings plant 9" eol_is "$sb" planted-pathspec.sh "i/-text"; then
  expect_red "line-endings red on a staged lone CR with GIT_LITERAL_PATHSPECS=1" "$sb" "CR in planted-pathspec.sh (the staged copy" env GIT_LITERAL_PATHSPECS=1 bash scripts/dev/check-line-endings.sh
fi
drop_sandbox "$sb"

# 73. a script or perl file whose name holds a UTF-8 C1 control fails validate,
#     and is kept away from perl (the planted perl file does not compile)
sb=$(make_sandbox) || abort_sandbox
c1_sh="tool$(printf '\302\233')x.sh"
if can_create "$sb" "$c1_sh"; then
  printf '#!/usr/bin/env bash\nrm -f %s1\n' "$d" >"$sb/$c1_sh"
  printf 'my %sx = ;\n' "$d" >"$sb/scripts/dev/lib/bad$(printf '\302\233').pl"
  (cd "$sb" && git add -A)
  out=$(cd "$sb" && PERL_UNICODE=SDA bash scripts/dev/validate.sh 2>&1)
  code=$?
  if [ "$code" -eq 1 ] && printf '%s\n' "$out" | grep -F -q 'names: tool\xC2\x9Bx.sh' && printf '%s\n' "$out" | grep -F -q 'names: scripts/dev/lib/bad\xC2\x9B.pl' && printf '%s\n' "$out" | grep -q '^perl-syntax: PASS'; then
    pass "validate fails script and perl file names that hold a C1 control, and keeps them from perl"
  else
    fail "validate fails script and perl file names that hold a C1 control, and keeps them from perl: exit $code" "$out"
  fi
else
  skip "a C1 control in a file name: this file system does not allow one"
fi
drop_sandbox "$sb"

# 74. the names check breaks up ##[ in a name it reports
sb=$(make_sandbox) || abort_sandbox
nl_cmd_name=$(printf 'w\nx ##[error]fake.txt')
if can_create "$sb" "$nl_cmd_name"; then
  printf 'hello\n' >"$sb/$nl_cmd_name"
  (cd "$sb" && git add -- "$nl_cmd_name")
  out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
  if printf '%s\n' "$out" | grep -F -q '##['; then
    fail "the names check printed the runner's ##[ command form" "$out"
  elif printf '%s\n' "$out" | grep -q "names: FAIL"; then
    pass "the names check breaks up ##[ in a name it reports"
  else
    fail "the names check breaks up ##[ in a name it reports: the name was not reported" "$out"
  fi
else
  skip "##[ in a reported name: this file system does not allow a newline in a name"
fi
drop_sandbox "$sb"

# 75. a key shorter than 20 characters is shown by its length only
sb=$(make_sandbox) || abort_sandbox
slack="xoxb-""1234567890"
printf 'SLACK_HOOK=%s\n' "$slack" >"$sb/planted-slack.txt"
(cd "$sb" && git add planted-slack.txt)
if expect_landed "mask plant 2" grep -q "1234567890" "$sb/planted-slack.txt"; then
  expect_red "secrets shows a 15-character token by its length only" "$sb" "planted-slack.txt:1: Slack token: ***(15 chars)" bash scripts/dev/scan-secrets.sh
fi
drop_sandbox "$sb"

# 76. git's own warnings never reach the secret scan's output
sb=$(make_sandbox) || abort_sandbox
printf 'a\nb\n' >"$sb/planted-warn.txt"
(cd "$sb" && git add planted-warn.txt && git commit -q -m lf)
printf 'a\r\nb\r\n' >"$sb/planted-warn.txt"
if expect_landed "git-warning plant 1" git_warns "$sb"; then
  out=$(cd "$sb" && bash scripts/dev/scan-secrets.sh 2>&1)
  if printf '%s\n' "$out" | grep -q "^warning:"; then
    fail "scan-secrets printed one of git's warnings" "$out"
  else
    pass "scan-secrets discards git's warnings"
  fi
fi
drop_sandbox "$sb"

# --- perl syntax (run through validate.sh) -------------------------------------------------
# 77. a perl file that does not compile
sb=$(make_sandbox) || abort_sandbox
printf 'use strict;\nmy %sx = ;\n' "$d" >"$sb/scripts/dev/lib/planted.pl"
(cd "$sb" && git add scripts/dev/lib/planted.pl)
if expect_landed "perl-syntax plant" grep -q "= ;" "$sb/scripts/dev/lib/planted.pl"; then
  expect_red "perl-syntax red on a file that does not compile" "$sb" "perl-syntax: FAIL - 1 of" bash scripts/dev/validate.sh
fi
drop_sandbox "$sb"

# 77b. a perl file under method/scripts/ that does not compile
sb=$(make_sandbox) || abort_sandbox
mkdir -p "$sb/method/scripts/method/lib"
printf 'use strict;\nmy %sx = ;\n' "$d" >"$sb/method/scripts/method/lib/planted.pl"
(cd "$sb" && git add method/scripts/method/lib/planted.pl)
if expect_landed "perl-syntax plant 2" grep -q "= ;" "$sb/method/scripts/method/lib/planted.pl"; then
  expect_red "perl-syntax red on a method file that does not compile" "$sb" "./method/scripts/method/lib/planted.pl line 2" bash scripts/dev/validate.sh
fi
drop_sandbox "$sb"

# --- shellcheck (run through validate.sh) --------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  # 78. an unchecked cd
  sb=$(make_sandbox) || abort_sandbox
  printf '#!/usr/bin/env bash\ncd "%s1"\nrm -f ./tmpfile\n' "$d" >"$sb/planted-cd.sh"
  (cd "$sb" && git add planted-cd.sh)
  if expect_landed "shellcheck plant 1" grep -q -F "cd \"${d}1\"" "$sb/planted-cd.sh"; then
    out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
    if printf '%s\n' "$out" | grep -q "\./planted-cd\.sh:2:" &&
      printf '%s\n' "$out" | grep -q "SC2164" &&
      printf '%s\n' "$out" | grep -q "validate: FAIL - shellcheck"; then
      pass "shellcheck red on an unchecked cd"
    else
      fail "shellcheck red on an unchecked cd" "$out"
    fi
  fi
  drop_sandbox "$sb"

  # 79. an unquoted variable
  sb=$(make_sandbox) || abort_sandbox
  printf '#!/usr/bin/env bash\nf=%s1\nrm -f %sf\n' "$d" "$d" >"$sb/planted-unquoted.sh"
  (cd "$sb" && git add planted-unquoted.sh)
  if expect_landed "shellcheck plant 2" grep -q -F "rm -f ${d}f" "$sb/planted-unquoted.sh"; then
    out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
    if printf '%s\n' "$out" | grep -q "\./planted-unquoted\.sh:3:" &&
      printf '%s\n' "$out" | grep -q "SC2086" &&
      printf '%s\n' "$out" | grep -q "validate: FAIL - shellcheck"; then
      pass "shellcheck red on an unquoted variable"
    else
      fail "shellcheck red on an unquoted variable" "$out"
    fi
  fi
  drop_sandbox "$sb"

  # 80. SHELLCHECK_OPTS in the environment cannot switch shellcheck off
  sb=$(make_sandbox) || abort_sandbox
  printf '#!/usr/bin/env bash\nf=%s1\nrm -f %sf\n' "$d" "$d" >"$sb/planted-unquoted4.sh"
  (cd "$sb" && git add planted-unquoted4.sh)
  if expect_landed "shellcheck plant 7" grep -q "rm -f" "$sb/planted-unquoted4.sh"; then
    expect_red "shellcheck is not switched off by SHELLCHECK_OPTS" "$sb" "./planted-unquoted4.sh:3:" env SHELLCHECK_OPTS="-e SC2086" bash scripts/dev/validate.sh
  fi
  drop_sandbox "$sb"

  # 81. a tracked .shellcheckrc cannot switch shellcheck off
  sb=$(make_sandbox) || abort_sandbox
  printf 'disable=all\n' >"$sb/.shellcheckrc"
  printf '#!/usr/bin/env bash\nf=%s1\nrm -f %sf\n' "$d" "$d" >"$sb/planted-unquoted3.sh"
  (cd "$sb" && git add .shellcheckrc planted-unquoted3.sh)
  if expect_landed "shellcheck plant 6" grep -q "disable=all" "$sb/.shellcheckrc"; then
    expect_red "shellcheck is not switched off by a tracked .shellcheckrc" "$sb" "./planted-unquoted3.sh:3:" bash scripts/dev/validate.sh
  fi
  drop_sandbox "$sb"

  # 82. a file named like a shellcheck option is linted as a file, not read as one
  sb=$(make_sandbox) || abort_sandbox
  printf '#!/usr/bin/env bash\ntrue\n' >"$sb/--rcfile=sc.sh"
  printf '# disable=all\ndisable=all\n' >"$sb/sc.sh"
  printf '#!/usr/bin/env bash\nf=%s1\nrm -f %sf\n' "$d" "$d" >"$sb/planted-unquoted2.sh"
  (cd "$sb" && git add -- --rcfile=sc.sh sc.sh planted-unquoted2.sh)
  if expect_landed "shellcheck plant 3" test -f "$sb/--rcfile=sc.sh"; then
    expect_red "shellcheck is not switched off by a file named --rcfile=sc.sh" "$sb" "./planted-unquoted2.sh:3:" bash scripts/dev/validate.sh
  fi
  drop_sandbox "$sb"

  # 83. a key on a line shellcheck flags is not printed in full
  sb=$(make_sandbox) || abort_sandbox
  printf '#!/usr/bin/env bash\necho %s1 "%s"\n' "$d" "$key" >"$sb/planted-leak.sh"
  (cd "$sb" && git add planted-leak.sh)
  if expect_landed "shellcheck plant 4" grep -q "api03" "$sb/planted-leak.sh"; then
    out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
    if printf '%s\n' "$out" | grep -F -q -- "$key"; then
      fail "validate printed a key in full from shellcheck's output" "$out"
    elif printf '%s\n' "$out" | grep -q "planted-leak.sh:2:.*SC2086"; then
      pass "shellcheck findings show no key in full"
    else
      fail "shellcheck findings show no key in full: SC2086 was not reported" "$out"
    fi
  fi
  drop_sandbox "$sb"

  # 84. no output line starts with "::", which the CI runner would read as a command
  sb=$(make_sandbox) || abort_sandbox
  cmd_name='::warning title=Spoof::x.sh'
  if can_create "$sb" "$cmd_name"; then
    printf '#!/usr/bin/env bash\nrm -f %s1\n' "$d" >"$sb/$cmd_name"
    (cd "$sb" && git add -- "./$cmd_name")
    if expect_landed "shellcheck plant 5" test -f "$sb/$cmd_name"; then
      out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
      if printf '%s\n' "$out" | grep -q '^[[:space:]]*::'; then
        fail "validate printed a line that starts with :: (after any spaces)" "$out"
      elif printf '%s\n' "$out" | grep -q "SC2086"; then
        pass "validate prints no line that starts with ::, even for a file named ::warning"
      else
        fail "validate prints no line that starts with ::: the planted SC2086 was not reported" "$out"
      fi
    fi
  else
    skip "a file named ::warning: this file system does not allow a colon"
  fi
  drop_sandbox "$sb"
elif [ "${REQUIRE_SHELLCHECK:-0}" = "1" ]; then
  fail "shellcheck plants: shellcheck is required here but not installed"
else
  skip "shellcheck plants: shellcheck not installed"
fi

# --- self-install (run through validate.sh; step 8.1, DECISIONS A82) ----------------------
# root_verify_empty DIR: the root copy's own lib/lock.pl, loaded from DIR,
# says the root copy matches its lock (no findings)
root_verify_empty() {
  (cd "$1" && perl -e 'require "./scripts/method/lib/lock.pl"; my $v = Lock::verify("."); exit(@{ $v->{findings} } ? 1 : 0)')
}

# 85. the root copy of the method is green on a clean copy
sb=$(make_sandbox) || abort_sandbox
out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
if printf '%s\n' "$out" | grep -q '^self-install: PASS - the root copy of the method matches scripts/method/method.lock (v'; then
  pass "self-install green on a clean copy"
else
  fail "self-install green on a clean copy" "$out"
fi
drop_sandbox "$sb"

# 86. a root method file changed
sb=$(make_sandbox) || abort_sandbox
printf '# planted\n' >>"$sb/.claude/hooks/method/guard.sh"
if expect_landed "self-install plant 1" grep -q '^# planted$' "$sb/.claude/hooks/method/guard.sh"; then
  expect_red "self-install red on a root method file changed since the release" "$sb" "self-install: changed since the release: .claude/hooks/method/guard.sh" bash scripts/dev/validate.sh
fi
drop_sandbox "$sb"

# 87. the claudeMdExcludes pattern that keeps the method's rules out removed
sb=$(make_sandbox) || abort_sandbox
perl -MJSON::PP -0777 -i -pe 'my $j = JSON::PP->new->canonical->pretty; my $s = $j->decode($_); delete $s->{claudeMdExcludes}; $_ = $j->encode($s)' "$sb/.claude/settings.json"
if expect_landed "self-install plant 2" lacks 'rules/method' "$sb/.claude/settings.json"; then
  expect_red "self-install red on the root settings without the rules pattern" "$sb" "self-install: FAIL - .claude/settings.json does not list claudeMdExcludes **/.claude/rules/method/**" bash scripts/dev/validate.sh
fi
drop_sandbox "$sb"

# 88. the root lib/lock.pl changed so its own verify finds nothing: the
#     check, which loads method/'s copy, still sees the change
sb=$(make_sandbox) || abort_sandbox
perl -0pi -e 's/(sub verify \{\n  my \(\$root\) = \@_;\n)/$1  return { examined => 1, findings => [], version => "v0.7.0" }; # planted\n/' "$sb/scripts/method/lib/lock.pl"
if expect_landed "self-install plant 3" grep -q '# planted$' "$sb/scripts/method/lib/lock.pl" &&
  expect_landed "self-install plant 3 (the root verify finds nothing)" root_verify_empty "$sb"; then
  expect_red "self-install red on a root lock.pl whose verify finds nothing" "$sb" "self-install: changed since the release: scripts/method/lib/lock.pl" bash scripts/dev/validate.sh
fi
drop_sandbox "$sb"

echo "plants: repo checks: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
