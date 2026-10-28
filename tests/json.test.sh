#!/usr/bin/env bash
# Tests for method/scripts/method/lib/json.pl, the method's only JSON helper.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: json helper"
json="$(repo_root)/method/scripts/method/lib/json.pl"
work=$(new_sandbox_dir) || abort_sandbox
doc="$work/doc.json"
# a document with a non-ASCII value (U+00E9 and U+4E2D) and a non-ASCII key (U+00FC)
printf '{"s":"caf\303\251 \344\270\255","\303\274k":"v","b":[1,2.5,true,null,{"z":1,"y":"q"}],"n":"12","t":"true","e":{}}' >"$doc"

# get_is NAME WANT KEY...: get prints exactly WANT (plus its newline) and exits 0.
get_is() {
  name=$1
  want=$2
  shift 2
  got=$(perl "$json" get "$@" <"$doc" 2>&1)
  code=$?
  if [ "$code" -eq 0 ] && [ "$got" = "$want" ]; then
    pass "$name"
  else
    fail "$name: exit $code, got '$got', wanted '$want'"
  fi
}

# exits_with NAME CODE INPUT KEY...: get on INPUT exits with CODE and prints nothing.
exits_with() {
  name=$1
  want=$2
  input=$3
  shift 3
  got=$(printf '%s' "$input" | perl "$json" get "$@" 2>/dev/null)
  code=$?
  if [ "$code" -eq "$want" ] && [ -z "$got" ]; then
    pass "$name"
  else
    fail "$name: exit $code (wanted $want), printed '$got'"
  fi
}

get_is "get prints a string as it is" "$(printf 'caf\303\251 \344\270\255')" s
get_is "get finds a non-ASCII key" "v" "$(printf '\303\274k')"
get_is "get prints a number as JSON text" "2.5" b 1
get_is "get prints true as JSON text" "true" b 2
get_is "get prints null" "null" b 3
get_is "get prints an object as compact JSON with sorted keys" '{"y":"q","z":1}' b 4
get_is "get follows nested keys and indexes" "q" b 4 y
get_is "get keeps a string that looks like a number" "12" n
get_is "get prints an empty object" "{}" e
get_is "get with no KEY prints the whole document, keys sorted" '{"b":[1,2.5,true,null,{"y":"q","z":1}],"e":{},"n":"12","s":"café 中","t":"true","ük":"v"}' 2>/dev/null

# The whole-document case above is only right if non-ASCII text stays UTF-8;
# check those bytes directly.
whole=$(perl "$json" get <"$doc")
case "$whole" in
  *"$(printf 'caf\303\251')"*) pass "get with no KEY keeps non-ASCII text as UTF-8" ;;
  *) fail "get with no KEY keeps non-ASCII text as UTF-8" "$whole" ;;
esac

got=$(printf '"top"' | perl "$json" get 2>&1)
if [ "$got" = "top" ]; then pass "a document that is a single string is read"; else fail "a document that is a single string is read" "$got"; fi
exits_with "a missing key exits 1" 1 '{"a":1}' b
exits_with "an index past the end exits 1" 1 '[1,2]' 2
for bad in abc -1 01 1.9 ' 2' '2 '; do
  exits_with "the array index '$bad' exits 1" 1 '[1,2,3]' "$bad"
done
exits_with "an object key on an array exits 1" 1 '[{"a":1}]' a
exits_with "a KEY on a string exits 1" 1 '{"a":"text"}' a 0
exits_with "a KEY on null exits 1" 1 '{"a":null}' a b
exits_with "input that is not JSON exits 2" 2 '{"a":' a
exits_with "an empty input exits 2" 2 '' a
exits_with "a number out of range exits 2" 2 '{"a":1e400}' a
exits_with "a number out of range anywhere in a printed value exits 2" 2 '{"a":[1,-1e400]}' a
exits_with "a string holding a NUL byte exits 2" 2 '{"a":"x\u0000y"}' a
for cmd in "" check format; do
  printf '{}' | perl "$json" ${cmd:+"$cmd"} >/dev/null 2>&1
  code=$?
  if [ "$code" -eq 2 ]; then pass "the command '$cmd' exits 2 (only get exists)"; else fail "the command '$cmd' exits 2 (only get exists): exit $code"; fi
done

# Bytes that are not UTF-8 as RFC 3629 defines it: a lone byte, an encoded
# surrogate, a code point above U+10FFFF, and UTF-16 (which holds NUL bytes).
for hex in 22ff22 22eda08022 22f490808022 220061002200; do
  printf '%s' "$hex" | perl -ne 'print pack "H*", $_' >"$work/bad.json"
  got=$(perl "$json" get <"$work/bad.json" 2>&1)
  code=$?
  case "$code:$got" in
    2:*"not valid UTF-8"*) pass "input bytes $hex are refused as not valid UTF-8" ;;
    *) fail "input bytes $hex are refused as not valid UTF-8: exit $code" "$got" ;;
  esac
done

# An error message never quotes the input, which may hold a secret.
got=$(printf '{"token" "sk-not-a-real-value"}' | perl "$json" get 2>&1)
case "$got" in
  *sk-not*) fail "an error message does not quote the input" "$got" ;;
  *"not valid JSON"*) pass "an error message does not quote the input" ;;
  *) fail "an error message does not quote the input: unexpected message" "$got" ;;
esac

# The same bytes come out whatever PERL_UNICODE or PERL5OPT ask for.
plain=$(perl "$json" get s <"$doc" | od -An -tx1)
for setting in "PERL_UNICODE=SDA" "PERL_UNICODE=S" "PERL5OPT=-CSDA" "PERL5OPT=-Mbigint" "PERL5OPT=-Minteger"; do
  got=$(env "$setting" perl "$json" get s <"$doc" | od -An -tx1)
  key=$(env "$setting" perl "$json" get "$(printf '\303\274k')" <"$doc")
  if [ "$got" = "$plain" ] && [ "$key" = "v" ]; then
    pass "with $setting the output bytes and key lookup are unchanged"
  else
    fail "with $setting the output bytes and key lookup are unchanged" "got $got (wanted $plain), key '$key'"
  fi
done

# Numbers read the same whatever PERL5OPT loads.
for setting in "PERL5OPT=-Mbigint" "PERL5OPT=-Minteger" "PERL5OPT=-Mbignum"; do
  got=$(env "$setting" perl "$json" get b 1 <"$doc" 2>&1)
  big=$(printf '{"a":1e400}' | env "$setting" perl "$json" get a 2>/dev/null)
  code=$?
  if [ "$got" = "2.5" ] && [ "$code" -eq 2 ] && [ -z "$big" ]; then
    pass "with $setting numbers are read as without it"
  else
    fail "with $setting numbers are read as without it: got '$got', out of range gave exit $code '$big'"
  fi
done

# Deep nesting is valid JSON and gives no warning.
deep=$(perl -e 'print "[" x 400, "1", "]" x 400')
got=$(printf '%s' "$deep" | perl "$json" get 2>&1 >/dev/null)
if [ -z "$got" ]; then pass "deep nesting gives no warning"; else fail "deep nesting gives no warning" "$got"; fi

# A failed write is an error, not a success.
(perl "$json" get s <"$doc" >&-) 2>/dev/null
code=$?
if [ "$code" -eq 2 ]; then pass "a failed write exits 2"; else fail "a failed write exits 2: exit $code"; fi

# Without JSON::PP: one plain sentence and exit 2.
mkdir -p "$work/stub/JSON"
printf 'die "planted: no JSON::PP\\n";\n' >"$work/stub/JSON/PP.pm"
got=$(printf '{}' | PERL5LIB="$work/stub" perl "$json" get 2>&1)
code=$?
case "$code:$got" in
  2:*"JSON::PP module is missing"*) pass "without JSON::PP it says so and exits 2" ;;
  *) fail "without JSON::PP it says so and exits 2: exit $code" "$got" ;;
esac

# Only perl is needed: run with a PATH that holds nothing else.
mkdir -p "$work/bin"
ln -s "$(command -v perl)" "$work/bin/perl"
got=$(PATH="$work/bin" perl "$json" get b 4 y <"$doc" 2>&1)
if [ "$got" = "q" ]; then pass "it runs with only perl on PATH"; else fail "it runs with only perl on PATH" "$got"; fi

drop_sandbox "$work"
echo "tests: json helper: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
