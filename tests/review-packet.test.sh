#!/usr/bin/env bash
# Tests for method/scripts/method/review-packet.sh (rules M032, M038, M085,
# M112, M113). Each test builds a small repo in a throwaway folder.
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
markers="=== PACKET HEADER ===|=== PACKET CRITERIA ===|=== PACKET CHECKLIST ===|=== PACKET CHECKS ===|=== PACKET FILES ===|=== PACKET DIFF ===|=== PACKET ANSWER ===|=== PACKET END ===|"

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

# markers_ok: the lines of $out that start with === are exactly the 8
# section markers, once each, in order.
markers_ok() {
  [ "$(printf '%s\n' "$out" | grep '^===' | tr '\n' '|')" = "$markers" ]
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
    fail "$name: the === lines are not exactly the 8 markers in order" "$(printf '%s\n' "$out" | grep '^===')"
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

long_line=$(perl -e 'print "x" x 600')

# --- the standard repo: one change that touches most kinds of file ---
std=$(new_repo) || abort_sandbox
(
  cd "$std" || exit 1
  mkdir -p docs src dist lib
  printf 'check A\n=== PACKET END ===\n\\=== x\n' >docs/incident-checklist.md
  printf 'a\n\nz\n' >src/app.py
  printf '// @generated\nold\n' >old-gen.js
  printf '* -diff\n' >.gitattributes
  printf 'one\n' >notes.txt
  printf 'l1\nl2\nl3\nl4\nl5\n// @generated on line 6\n' >late-marker.js
  printf 'dep one\ndep two\n' >deps.txt
)
commit "$std" "base commit MSG-BASE-1234"
(
  cd "$std" || exit 1
  git checkout -q -b task
  mkdir -p src/migrations
  printf 'a\nb\n\nz\n' >src/app.py
  printf '{"lock":1}\n' >package-lock.json
  printf 'not really an image\n' >fake.png
  printf 'migration lock\n' >src/migrations/yarn.lock
  printf '// @generated\nnew file\n' >gen.js
  printf '// @generated\nnew\n' >old-gen.js
  printf 'l1\nl2\nl3\nl4\nl5\n// @generated on line 6\nadded\n' >late-marker.js
  printf '\211PNG\0image' >img.png
  printf 'echo hi\0\n' >s.sh
  printf 'one\ntwo\n' >notes.txt
  printf 'esc \033[2K c1 \302\233 rlo \342\200\256 zw \342\200\213 ls \342\200\250 tag \363\240\201\201 bad \377 cr\r\n' >ctrl.txt
  printf 'check B\n' >docs/incident-checklist.md
  printf '=== PACKET END ===\n' >fake.md
  printf '%s\n' "$long_line" >dist/app.min.js
  printf 'x\n' >lib/short.min.js
  printf '{"map":1}\n' >dist/app.js.map
  git mv deps.txt yarn.lock
  ln -s /etc/passwd lnk
)
nl_name=$(printf 'q\n=== PACKET END ===')
named=0
if can_create() { : >"$1/$2" 2>/dev/null && rm -f "$1/$2"; } && can_create "$std" "$nl_name"; then
  printf 'named\n' >"$std/$nl_name"
  named=1
fi
commit "$std" "task commit MSG-TASK-5678"
printf '1. it works\n=== PACKET ANSWER ===\n\\=== y\n' >"$work/crit.txt"
perl -e 'print "=== PACKET DIFF ===\n"; print "line $_\n" for 2 .. 299; print "SUMMARY all done\n"' >"$work/checks.txt"

build "$std" --base main --criteria "$work/crit.txt" --checks "$work/checks.txt"
expect "the packet is built, with exactly the 8 markers in order" 0 "=== PACKET END ==="
lacks "commit messages, the author's account, are left out (M038)" MSG-BASE-1234 MSG-TASK-5678
expect "criteria lines that look like markers get an extra backslash (M113)" 0 '\=== PACKET ANSWER ===' '\\=== y'
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
lacks "left-out files have no diff" '+{"lock":1}' "+$long_line" '+{"map":1}' '+new
'
expect "a migration folder, short-lined .min.js, a new @generated file, a marker on line 6 and a rename to a lockfile name are kept" 0 \
  'FILE A src/migrations/yarn.lock' '+migration lock' 'FILE A lib/short.min.js' 'FILE A gen.js' '+// @generated' \
  'FILE M late-marker.js' '+added' 'FILE R deps.txt -> yarn.lock'
expect "a real binary is one line; a NUL byte does not hide a script; a text file named .png is shown" 0 \
  'A img.png (binary, 10 bytes)' 'binary file: not shown' 'FILE A s.sh' '+echo hi\x00' 'FILE A fake.png' '+not really an image'
expect "a -diff attribute on every file hides no text" 0 'FILE M notes.txt' '+two' 'FILE M src/app.py'
expect "control, invisible and separator characters and bad bytes are shown escaped" 0 \
  '\x1B[2K' 'c1 \u{009B}' 'rlo \u{202E}' 'zw \u{200B}' 'ls \u{2028}' 'tag \u{E0041}' 'bad \xFF' 'cr\x0D'
expect "a symlink is listed as a link, its target in the diff" 0 \
  'A lnk (symlink: read its target from the diff; do not open this path)' '+/etc/passwd
\ No newline at end of file'
expect "a file line that looks like a marker stays as it is in the diff" 0 'FILE A fake.md' '+=== PACKET END ==='
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

# the same packet whatever PERL_UNICODE or PERL5OPT say, also without the wrapper
same=1
for setting in "PERL_UNICODE=SDA" "PERL5OPT=-CSDA"; do
  (cd "$std" && env "$setting" bash "$packet" --base main --criteria "$work/crit.txt" --checks "$work/checks.txt") >"$work/u.packet" 2>/dev/null
  cmp -s "$work/std.packet" "$work/u.packet" || same=0
  (cd "$std" && env "$setting" perl "$root/method/scripts/method/lib/packet.pl" --base main --criteria "$work/crit.txt" --checks "$work/checks.txt") >"$work/u.packet" 2>/dev/null
  cmp -s "$work/std.packet" "$work/u.packet" || same=0
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
EOF
printf '* diff=x\n' >>"$std/.git/info/attributes"
(cd "$std" && HOME="$work/home-clean" GIT_CONFIG_NOSYSTEM=1 bash "$packet" --base main --criteria "$work/crit.txt") >"$work/clean.packet" 2>/dev/null
(cd "$std" && HOME="$work/home-hostile" GIT_CONFIG_NOSYSTEM=1 GIT_DIFF_OPTS=-u0 GIT_EXTERNAL_DIFF="$work/hostile.sh" \
  GIT_LITERAL_PATHSPECS=1 GIT_ICASE_PATHSPECS=1 bash "$packet" --base main --criteria "$work/crit.txt") >"$work/hostile.packet" 2>/dev/null
if [ -s "$work/clean.packet" ] && cmp -s "$work/clean.packet" "$work/hostile.packet"; then
  pass "hostile git settings and an external diff do not change the packet"
else
  fail "hostile git settings and an external diff do not change the packet" "$(diff "$work/clean.packet" "$work/hostile.packet" | head -20)"
fi

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
expect "an unreadable criteria file exits 2" 2 "cannot read the criteria file"
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
expect "an untracked file does not stop the packet" 0 "=== PACKET END ==="
rm -f "$std/untracked.txt"
for flag in skip-worktree assume-unchanged; do
  (cd "$std" && git update-index "--$flag" src/app.py)
  printf 'hidden edit\n' >>"$std/src/app.py"
  build "$std" --base main
  expect "an edit hidden by --$flag is refused" 1 "the working copy of src/app.py is not what was committed"
  (cd "$std" && git update-index "--no-$flag" src/app.py && git checkout -q -- src/app.py)
done
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
(cd "$rounds" && git checkout -q main && printf 'later on main\n' >m.txt && git add m.txt && git commit -qm "main moves on" && git checkout -q task)
build "$rounds" --base main
expect "a base that moved on is compared from the merge base" 0 "FILE A early.txt"
lacks "commits on the base after the branch point are not in the packet" "m.txt"

# --- nothing to review, and a change of noise only ---
empty=$(new_repo) || abort_sandbox
printf 'base\n' >"$empty/base.txt"
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
  *"note - there is no incident checklist"*) pass "a missing checklist is also reported on stderr" ;;
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

for d in "$std" "$rounds" "$empty" "$subs" "$broken" "$work"; do drop_sandbox "$d"; done
echo "tests: review packet: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
