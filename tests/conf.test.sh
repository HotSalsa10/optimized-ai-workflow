#!/usr/bin/env bash
# Tests for method/scripts/method/lib/conf.pl, the one reader of
# .claude/method.conf and REQUIRES (M048). Each test writes a config file
# in a throwaway folder and reads it through Conf::read or Conf::requires.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: config reader"
root=$(repo_root)
conf_pl="$root/method/scripts/method/lib/conf.pl"
work=$(new_sandbox_dir) || abort_sandbox
mkdir -p "$work/.claude"
cfile="$work/.claude/method.conf"

# read_conf: reads $cfile; prints "V KEY=VALUE" per value and "P PROBLEM"
# per problem, into $got
# shellcheck disable=SC2016 # perl code: perl expands it
read_pl='
  my ($v, $p) = $ARGV[0] eq "requires" ? Conf::requires($ARGV[1]) : Conf::read($ARGV[1]);
  for my $k (sort keys %$v) { my $x = $v->{$k}; print "V $k=$_\n" for ref $x ? @$x : $x }
  print "P $_\n" for @$p;
'
read_conf() {
  got=$(perl -e "require \$ARGV[0]; shift; $read_pl" "$conf_pl" read "$work" 2>&1)
}

# conf_is NAME CONTENT WANTED: the file holding CONTENT (printf format) reads as WANTED
conf_is() {
  # shellcheck disable=SC2059 # the content is a printf format on purpose
  printf "$2" >"$cfile"
  read_conf
  if [ "$got" = "$3" ]; then pass "$1"; else fail "$1" "got:
$got
wanted:
$3"; fi
}

# conf_bad NAME CONTENT LINE REASON: the file holding CONTENT gives one
# problem naming LINE and REASON, and neither sets nor quotes the bad value
# (every bad value below holds "zq")
conf_bad() {
  # shellcheck disable=SC2059
  printf "$2" >"$cfile"
  read_conf
  problems=$(printf '%s\n' "$got" | grep -c '^P ')
  case "$got" in
    *zq*) fail "$1: the problem quotes the value" "$got" ;;
    *"P .claude/method.conf line $3: "*"$4"*)
      if [ "$problems" -eq 1 ]; then pass "$1"; else fail "$1: expected exactly one problem" "$got"; fi
      ;;
    *) fail "$1: expected a problem naming line $3 and '$4'" "$got" ;;
  esac
}

# 1. what a good file gives
rm -f "$cfile"
read_conf
if [ -z "$got" ]; then pass "a missing file sets nothing and is no problem"; else fail "a missing file sets nothing and is no problem" "$got"; fi
conf_is "comments, blank lines and list keys are read" \
  '# the product\n\nPRODUCT_PATHS=src\nPRODUCT_PATHS=Client Letters\n   # indented comment\nLOCAL_ONLY=__pycache__\nLOCAL_ONLY=*.pyc\nLOCAL_ONLY=src/data/private\nREPOS=../website\nREPOS=../../other/site\nVERDICTS_FROM=0123456789abcdef0123456789abcdef01234567\n' \
  'V LOCAL_ONLY=__pycache__
V LOCAL_ONLY=*.pyc
V LOCAL_ONLY=src/data/private
V PRODUCT_PATHS=src
V PRODUCT_PATHS=Client Letters
V REPOS=../website
V REPOS=../../other/site
V VERDICTS_FROM=0123456789abcdef0123456789abcdef01234567'
conf_is "CRLF line ends read the same as LF" 'PRODUCT_PATHS=src\r\nLOCAL_ONLY=__pycache__\r\n' 'V LOCAL_ONLY=__pycache__
V PRODUCT_PATHS=src'
conf_is "a value keeps its inner spaces and apostrophes" "PRODUCT_PATHS=Owner's Files/2024 plan\n" "V PRODUCT_PATHS=Owner's Files/2024 plan"
conf_is "a trailing / is dropped" 'PRODUCT_PATHS=src/\nREPOS=../site/\n' 'V PRODUCT_PATHS=src
V REPOS=../site'
conf_is "PRODUCT_PATHS may be the whole repo, with a LOCAL_ONLY path anywhere" 'PRODUCT_PATHS=.\nLOCAL_ONLY=data/private\n' 'V LOCAL_ONLY=data/private
V PRODUCT_PATHS=.'
conf_is "a 64-digit VERDICTS_FROM is accepted" 'VERDICTS_FROM=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n' \
  'V VERDICTS_FROM=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
conf_is "a bad line leaves the other lines read" 'PRODUCT_PATHS=src\nNOPE=zq\nLOCAL_ONLY=__pycache__\n' 'V LOCAL_ONLY=__pycache__
V PRODUCT_PATHS=src
P .claude/method.conf line 2: unknown key NOPE (a typo, or a key from a newer method version)'

# 2. every rule turns a line into a problem that names the line, not the value
conf_bad "a lone CR" 'PRODUCT_PATHS=zq\rsrc\n' 1 "control character"
conf_bad "a control character" 'PRODUCT_PATHS=zq\001src\n' 1 "control character"
conf_bad "an escape character" '# x\nPRODUCT_PATHS=zq\033[31m\n' 2 "control character"
conf_bad "double quotes" 'PRODUCT_PATHS="zq"\n' 1 "no quotes"
conf_bad "single quotes around the value" "PRODUCT_PATHS='zq'\n" 1 "no quotes"
conf_bad "a leading space" 'PRODUCT_PATHS= zq\n' 1 "starts or ends with a space"
conf_bad "a trailing space" 'PRODUCT_PATHS=zq \n' 1 "starts or ends with a space"
conf_bad "a tab" 'PRODUCT_PATHS=zq\t\n' 1 "control character"
conf_bad "an empty value" '\nPRODUCT_PATHS=\n' 2 "has no value"
conf_bad "a line without =" 'PRODUCT_PATHS zq\n' 1 "is not KEY=VALUE"
conf_bad "a space before =" 'PRODUCT_PATHS =zq\n' 1 "is not KEY=VALUE"
conf_bad "an unknown key" 'PRODUCT_PATH=zq\n' 1 "unknown key PRODUCT_PATH"
conf_bad "a key in lower case" 'product_paths=zq\n' 1 "unknown key product_paths"
conf_bad "a PROFILE key (not in this version)" 'PROFILE=zq\n' 1 "unknown key PROFILE"
conf_bad "an unknown key name with digits (a pasted value ending in =?) is not shown" 'Ab3dEf9hKk2=zq\n' 1 "an unknown key, not shown"
case "$got" in *Ab3dEf9hKk2*) fail "an unknown key name with digits is not quoted" "$got" ;; *) pass "an unknown key name with digits is not quoted" ;; esac
conf_bad "an unknown key name in mixed case (a pasted value ending in =?) is not shown" 'AbcdEfghIjkl=zq\n' 1 "an unknown key, not shown"
conf_bad "an unknown key name of 31 letters is not shown" 'ABCDEFGHIJKLMNOPQRSTUVWXYZABCDE=zq\n' 1 "an unknown key, not shown"
conf_bad "an unknown key name shaped like an AWS key id, all letters, is not shown" 'AKIA''ABCDEFGHIJKLMNOP=zq\n' 1 "an unknown key, not shown"
printf 'VERDICTS_FROM=0123456789abcdef0123456789abcdef01234567\nVERDICTS_FROM=1123456789abcdef0123456789abcdef01234567\n' >"$cfile"
read_conf
case "$got" in
  *"V VERDICTS_FROM=0123456789abcdef0123456789abcdef01234567"*"P .claude/method.conf line 2: VERDICTS_FROM is given twice"*) pass "a single-value key given twice is a problem on the second line" ;;
  *) fail "a single-value key given twice is a problem on the second line" "$got" ;;
esac
for bad in /zq 'C:/zq' 'zq/../src' '../zq' 'zq/./src' './zq' 'zq//src' .zq/.. :zq -zq 'zq*' 'zq?' 'zq[1]' 'zq\\x'; do
  conf_bad "PRODUCT_PATHS refuses $bad" "PRODUCT_PATHS=$bad\n" 1 "a relative path"
done
for bad in '/zq' 'zq/../x' '..' '../zq/..' 'zq\\x'; do
  conf_bad "REPOS refuses $bad" "REPOS=$bad\n" 1 "a relative path"
done
for bad in '*' '**' '?' '*?' '-zq' ':zq' 'zq[1]' '..'; do
  conf_bad "LOCAL_ONLY refuses the bare name $bad" "LOCAL_ONLY=$bad\n" 1 "a name like"
done
conf_bad "a LOCAL_ONLY path outside PRODUCT_PATHS" 'PRODUCT_PATHS=src\nLOCAL_ONLY=zq/private\n' 2 "must lie under a PRODUCT_PATHS entry"
conf_bad "a LOCAL_ONLY path that only starts like a PRODUCT_PATHS entry" 'PRODUCT_PATHS=src\nLOCAL_ONLY=srczq/private\n' 2 "must lie under"
conf_bad "a LOCAL_ONLY path with no PRODUCT_PATHS" 'LOCAL_ONLY=zq/private\n' 1 "must lie under"
conf_bad "a LOCAL_ONLY path breaking the path rules" 'PRODUCT_PATHS=.\nLOCAL_ONLY=zq/../x\n' 2 "a name like"
for bad in zq0123 0123456789abcdef0123456789abcdef0123456 0123456789ABCDEF0123456789ABCDEF01234567 0123456789abcdef0123456789abcdef01234567zq; do
  conf_bad "VERDICTS_FROM refuses $bad" "VERDICTS_FROM=$bad\n" 1 "a full commit id"
done
rm -f "$cfile"
mkdir "$cfile"
read_conf
case "$got" in
  "P .claude/method.conf: not a regular file") pass "a folder in the file's place is a problem" ;;
  *) fail "a folder in the file's place is a problem" "$got" ;;
esac
rmdir "$cfile"
conf_is "a byte-order mark at the start is dropped" '\357\273\277PRODUCT_PATHS=src\n' 'V PRODUCT_PATHS=src'
printf 'PRODUCT_PATHS=src\n' >"$work/other.conf"
rm -f "$cfile"
ln -s "$work/other.conf" "$cfile"
read_conf
case "$got" in
  "P .claude/method.conf: .claude or the file is a link; settings must be in the repository itself") pass "a method.conf that is a link is a problem" ;;
  *) fail "a method.conf that is a link is a problem" "$got" ;;
esac
rm -f "$cfile"
mv "$work/.claude" "$work/real-claude"
ln -s "$work/real-claude" "$work/.claude"
read_conf
case "$got" in
  "P .claude/method.conf: .claude or the file is a link"*) pass "a .claude folder that is a link is a problem" ;;
  *) fail "a .claude folder that is a link is a problem" "$got" ;;
esac
rm -f "$work/.claude"
mv "$work/real-claude" "$work/.claude"

# 3. REQUIRES: read by the same parser, and the same floor as SPEC.md
req=$(perl -e "require \$ARGV[0]; shift; $read_pl" "$conf_pl" requires "$root/method/scripts/method" 2>&1)
spec_floor=$(sed -n 's/^| Claude Code | \([0-9][0-9.]*\) or later |.*/\1/p' "$root/SPEC.md")
if [ -n "$spec_floor" ] && [ "$req" = "V claude_code_min=$spec_floor" ]; then
  pass "REQUIRES holds only the Claude Code floor of SPEC.md ($spec_floor)"
else
  fail "REQUIRES holds only the Claude Code floor of SPEC.md" "REQUIRES: $req
SPEC.md: $spec_floor"
fi
mkdir -p "$work/req"
printf 'claude_code_min=2.1\nPRODUCT_PATHS=src\n' >"$work/req/REQUIRES"
req=$(perl -e "require \$ARGV[0]; shift; $read_pl" "$conf_pl" requires "$work/req" 2>&1)
case "$req" in
  "P REQUIRES line 1: claude_code_min: a version like 2.1.295
P REQUIRES line 2: unknown key PRODUCT_PATHS"*) pass "REQUIRES refuses a short version and the project's keys" ;;
  *) fail "REQUIRES refuses a short version and the project's keys" "$req" ;;
esac

# 4. ignored_inputs: the project's config files that git ignores
ign=$(new_sandbox_dir) || abort_sandbox
(
  cd "$ign" || exit 1
  git init -q
  mkdir -p .claude checks
  printf '.claude/method.conf\nchecks/*\n!checks/kept.tsv\n' >.gitignore
  : >.claude/method.conf
  : >checks/unit.tsv
  : >checks/kept.tsv
  : >checks/.hidden.tsv
  : >checks/scan-allow.txt
  : >checks/notes.txt
  : >checks/forced.tsv
  git add -f checks/forced.tsv
) || fail "could not build the ignored-files repo"
got=$(cd "$ign" && perl -e 'require $_ for @ARGV; print "$_\n" for Conf::ignored_inputs(".")' "$root/method/scripts/method/lib/git.pl" "$conf_pl" 2>&1)
want='.claude/method.conf
checks/scan-allow.txt
checks/unit.tsv'
if [ "$got" = "$want" ]; then pass "ignored_inputs names the ignored config files, not tracked or other files"; else fail "ignored_inputs names the ignored config files" "got:
$got
wanted:
$want"; fi

drop_sandbox "$ign"
drop_sandbox "$work"
echo "tests: config reader: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
