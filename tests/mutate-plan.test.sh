#!/usr/bin/env bash
# Tests for method/scripts/method/mutate-changed.sh --list (rule M044, step
# 4b.2: the plan only). Each test builds a small project with a local bare
# remote in a throwaway folder and reads the plan; nothing is run.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: mutate plan"
root=$(repo_root)
mutate="$root/method/scripts/method/mutate-changed.sh"
work=$(new_sandbox_dir) || abort_sandbox
repos=""
saved_home=$HOME
mkdir -p "$work/home"
# a clean home and no system settings, so the owner's git settings play no part
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
git config --global user.name "Test"
git config --global user.email "test@example.invalid"
git config --global commit.gpgsign false
git config --global core.autocrlf false
git config --global init.defaultBranch main
git config --global protocol.file.allow always

# mp DIR ARGS...: runs mutate-changed.sh in DIR (the method's own copy unless
# MP is set). Sets out and code.
mp() {
  d=$1
  shift
  out=$(cd "$d" && env CI= bash "${MP:-$mutate}" "$@" 2>&1)
  code=$?
}

# expect NAME CODE STRING...: the last run exited CODE and holds every STRING
expect() {
  name=$1
  want=$2
  shift 2
  missing=""
  for s in "$@"; do
    case "$out" in
      *"$s"*) ;;
      *) missing="$missing [$s]" ;;
    esac
  done
  if [ "$code" -ne "$want" ]; then
    fail "$name: exit $code, wanted $want" "$out"
  elif [ -n "$missing" ]; then
    fail "$name: missing$missing" "$out"
  else
    pass "$name"
  fi
}

# lacks NAME STRING: the last output does not hold STRING
lacks() {
  case "$out" in
    *"$2"*) fail "$1" "$out" ;;
    *) pass "$1" ;;
  esac
}

# planned: the planned lines of the last output, without the prefix
planned() { printf '%s\n' "$out" | sed -n 's/^mutate-changed: planned: //p'; }

# new_project: prints a folder holding remote.git (bare) and w: main with
# checks/project.tsv (unit, any), .claude/method.conf (MUTATE_PATHS=src,
# MUTATION_CHECKS=unit) and src/base.py, pushed, origin/HEAD set; w is on
# branch feat
new_project() {
  b=$(new_sandbox_dir) || return 1
  repos="$repos $b"
  (
    cd "$b" || exit 1
    git init -q --bare remote.git
    git init -q w
    cd w || exit 1
    mkdir -p checks .claude src
    printf 'unit\tany\t-\t(\\d+) ok\techo 3 ok\nci-only\tci\t-\t(\\d+) ok\techo 3 ok\n' >checks/project.tsv
    printf 'PRODUCT_PATHS=src\nMUTATE_PATHS=src\nMUTATION_CHECKS=unit\n' >.claude/method.conf
    printf 'def base(x):\n    return x == 1\n' >src/base.py
    git add -A
    git commit -q -m "Start"
    git remote add origin ../remote.git
    git push -q -u origin main 2>/dev/null
    git remote set-head origin main
    git checkout -q -b feat
  ) || return 1
  printf '%s\n' "$b"
}

# feat DIR MESSAGE: commits everything in DIR on its branch
feat() { (cd "$1" && git add -A 2>/dev/null && git commit -q -m "$2"); }

# --- usage and settings ---
p=$(new_project) || abort_sandbox
w="$p/w"
mp "$w"
expect "without --list it stops: running mutants comes later (exit 2)" 2 \
  "mutate-changed: FAIL - running mutants comes in step 4b.3; for now mutate-changed.sh plans them with --list"
mp "$w" --list --max 0
expect "--max 0 is bad usage (exit 2)" 2 "mutate-changed: usage: mutate-changed.sh --list [--max N]"
mp "$w" --list --bogus
expect "an unknown argument is bad usage (exit 2)" 2 "mutate-changed: usage:"
mp "$w" --list
expect "HEAD at main's tip has nothing to mutate (exit 3, never a pass)" 3 \
  "mutate-changed: SKIPPED - nothing-to-mutate: 0 changed lines in 0 files" "this is not a pass"
printf 'PRODUCT_PATHS=src\nMUTATION_CHECKS=unit\n' >"$w/.claude/method.conf"
feat "$w" "No MUTATE_PATHS"
mp "$w" --list
expect "MUTATE_PATHS unset: SKIPPED not-configured (exit 3)" 3 \
  "mutate-changed: SKIPPED - not-configured: MUTATE_PATHS is not set in .claude/method.conf"
printf 'PRODUCT_PATHS=src\nMUTATE_PATHS=src\n' >"$w/.claude/method.conf"
feat "$w" "No MUTATION_CHECKS"
mp "$w" --list
expect "MUTATION_CHECKS unset: SKIPPED not-configured, never all checks (exit 3)" 3 \
  "mutate-changed: SKIPPED - not-configured: MUTATION_CHECKS is not set"
printf 'PRODUCT_PATHS=src\nMUTATE_PATHS=src\nMUTATION_CHECKS=nope\n' >"$w/.claude/method.conf"
feat "$w" "An unknown check"
mp "$w" --list
expect "a MUTATION_CHECKS id that checks/*.tsv lacks stops it (exit 2)" 2 \
  "mutate-changed: FAIL - MUTATION_CHECKS names checks that checks/*.tsv does not have: nope"
printf 'PRODUCT_PATHS=src\nMUTATE_PATHS=src\nMUTATION_CHECKS=Unit\n' >"$w/.claude/method.conf"
feat "$w" "A bad id"
mp "$w" --list
expect "a MUTATION_CHECKS value that is not a check id is a settings problem (exit 2)" 2 \
  "MUTATION_CHECKS: a check id from checks/*.tsv" "mutate-changed: FAIL - .claude/method.conf has problems"
printf 'PRODUCT_PATHS=src\nMUTATE_PATHS=src\nMUTATION_CHECKS=ci-only\n' >"$w/.claude/method.conf"
printf 'y = 2\n' >"$w/src/new.py"
feat "$w" "Only a CI check"
mp "$w" --list
expect "MUTATION_CHECKS that run only in CI: SKIPPED not-here, naming them (exit 3)" 3 \
  "mutate-changed: SKIPPED - not-here: none of MUTATION_CHECKS runs here: ci-only (runs in CI only"
printf 'PRODUCT_PATHS=src\nMUTATE_PATHS=src\nMUTATION_CHECKS=unit\nMUTATION_CHECKS=ci-only\n' >"$w/.claude/method.conf"
feat "$w" "Both checks"
mp "$w" --list
expect "a plan names the checks it would run and the ones not run here" 0 \
  "mutate-changed: planned: src/new.py:1:5: '2' becomes '3'" "mutate-changed: checks: unit; not run here: ci-only"
echo 'z = 3' >>"$w/src/new.py"
mp "$w" --list
expect "files on disk that are not the commit stop it (exit 2)" 2 "mutate-changed: FAIL - the files on disk are not the commit"
(cd "$w" && git checkout -q -- src/new.py)

# --- the operators ---
cat >"$w/src/ops.js" <<'EOF'
a === b
a !== b
a == b
a != b
a <= b
a >= b
[ "$a" -lt "$b" ]
[ "$a" -le "$b" ]
[ "$a" -gt "$b" ]
[ "$a" -ge "$b" ]
[ "$a" -eq "$b" ]
[ "$a" -ne "$b" ]
a && b
a || b
a and b
a or b
x = true
x = False
x = TRUE
x = 41
x = 1
x = 0
x = 99
a <=> b
a << b; a >> b
a => b
a ||= b; a &&= b
a <<= b; a >>= b
x = 007
x = 1.5
v2 = abc_3
echo $1 \1
a < b; a > b
a+b
android oregon untrue
=====
v = café1
echo ${1}
ls -lt x
# x == 1
// x == 1
-- x == 1
/* x == 1
 * x == 1
; x == 1
% x == 1
<!-- x == 1
EOF
mkdir -p "$w/lib"
printf 'x == 1\n' >"$w/lib/out.py"
feat "$w" "Operators"
mp "$w" --list --max 1000
lacks "a changed file outside MUTATE_PATHS is not planned" "lib/out.py"
cat >"$work/ops.want" <<'EOF'
src/new.py:1:5: '2' becomes '3'
src/ops.js:1:3: '===' becomes '!=='
src/ops.js:2:3: '!==' becomes '==='
src/ops.js:3:3: '==' becomes '!='
src/ops.js:4:3: '!=' becomes '=='
src/ops.js:5:3: '<=' becomes '<'
src/ops.js:6:3: '>=' becomes '>'
src/ops.js:7:8: '-lt' becomes '-le'
src/ops.js:8:8: '-le' becomes '-lt'
src/ops.js:9:8: '-gt' becomes '-ge'
src/ops.js:10:8: '-ge' becomes '-gt'
src/ops.js:11:8: '-eq' becomes '-ne'
src/ops.js:12:8: '-ne' becomes '-eq'
src/ops.js:13:3: '&&' becomes '||'
src/ops.js:14:3: '||' becomes '&&'
src/ops.js:15:3: 'and' becomes 'or'
src/ops.js:16:3: 'or' becomes 'and'
src/ops.js:17:5: 'true' becomes 'false'
src/ops.js:18:5: 'False' becomes 'True'
src/ops.js:19:5: 'TRUE' becomes 'FALSE'
src/ops.js:20:5: '41' becomes '42'
src/ops.js:21:5: '1' becomes '0'
src/ops.js:22:5: '0' becomes '1'
src/ops.js:23:5: '99' becomes '100'
EOF
if [ "$(planned | LC_ALL=C sort -t: -k1,1 -k2,2n)" = "$(cat "$work/ops.want")" ]; then
  pass "each operator gets its mutant, and the look-alikes get none"
else
  fail "each operator gets its mutant, and the look-alikes get none" "$(planned | LC_ALL=C sort -t: -k1,1 -k2,2n | diff "$work/ops.want" - | head -20)"
fi
expect "comment-like lines are counted, not mutated" 0 \
  "48 changed lines in 2 files: 24 with a mutant, 8 comment-like, 0 that delete or move files, 16 with nothing to mutate"

# --- order and the cap ---
p2=$(new_project) || abort_sandbox
w2="$p2/w"
i=1
while [ "$i" -le 30 ]; do
  printf '  "k%d": %d,\n' "$i" "$i" >>"$w2/src/a.json"
  i=$((i + 1))
done
printf 'if x >= 1 and y:\n    pass\n' >"$w2/src/z.py"
feat "$w2" "A long data file before the code"
mp "$w2" --list --max 2
expect "the cap reaches every changed file: one from each in turn (Frappe-like: a .json sorted before its .py)" 0 \
  "mutate-changed: PLAN - 2 mutants of 33 (--max 2)"
if [ "$(planned | tr '\n' '|')" = "src/a.json:1:9: '1' becomes '0'|src/z.py:1:6: '>=' becomes '>'|" ]; then
  pass "and the first two are the first line of each file"
else
  fail "and the first two are the first line of each file" "$out"
fi
mp "$w2" --list --max 1000
if [ "$(planned | tail -n 2 | tr '\n' '|')" = "src/z.py:1:9: '1' becomes '0'|src/z.py:1:11: 'and' becomes 'or'|" ]; then
  pass "a line's second and third mutants come after one mutant from every changed line"
else
  fail "a line's second and third mutants come after one mutant from every changed line" "$(planned | tail -n 5)"
fi

# --- which lines and files ---
p3=$(new_project) || abort_sandbox
w3="$p3/w"
printf 'def base(x):\n    y = 2\n    return x == 1\n' >"$w3/src/base.py"
feat "$w3" "One line added in the middle"
mp "$w3" --list
expect "only the added line is mutated, at its new line number" 0 "mutate-changed: planned: src/base.py:2:9: '2' becomes '3'" \
  "1 changed lines in 1 files"
lacks "and the unchanged line is not" "src/base.py:3"
(cd "$p3" && git clone -q remote.git m1 2>/dev/null && cd m1 && git checkout -q -b feat && git mv src/base.py src/moved.py &&
  git commit -q -m "A pure move")
mp "$p3/m1" --list
expect "a pure move adds no line to mutate" 3 "SKIPPED - nothing-to-mutate"
(cd "$p3" && git clone -q remote.git m2 2>/dev/null && cd m2 && mkdir lib && printf 'if a >= b: pass\n' >lib/c.py &&
  git add -A && git commit -q -m lib && git push -q origin main 2>/dev/null && git checkout -q -b feat && mkdir -p src &&
  git mv lib/c.py src/c.py && git commit -q -m "Move in")
mp "$p3/m2" --list
expect "a move in from outside MUTATE_PATHS adds no line to mutate" 3 "SKIPPED - nothing-to-mutate"

# nothing that deletes or moves files gets a mutant: a shell script or make
# file that runs such a command anywhere is skipped whole (its guard can sit
# on another line), and in any other file the line itself gets none
# shellcheck disable=SC2016 # the scripts are written, not run
printf '#!/bin/sh\n[ -n "$D" ] || exit 1\nrm -rf "$D"/*\n' >"$w3/src/t.sh"
# shellcheck disable=SC2016 # the scripts are written, not run
printf '#!/usr/bin/env bash\n[ "$n" -ge 2 ] || exit 1\necho ok\n' >"$w3/src/run"
printf 'clean:\n\t[ -d build ] && rm -rf build\n' >"$w3/src/Makefile"
# shellcheck disable=SC2016 # the scripts are written, not run
printf 'ok = d != "" and rm(d)\nx = [ "$D" != "" ] && git -C "$D" clean -fdx\ny = test -n "$D" || git --git-dir=g reset --hard\nflag = 1\n' >"$w3/src/t.py"
feat "$w3" "Shell"
mp "$w3" --list --max 1000
lacks "a shell script whose guard is on the line before its rm gets no mutant at all" "src/t.sh:"
lacks "nor does a make file that runs rm" "src/Makefile:"
expect "and both are counted" 0 "files skipped: 2 a shell script or make file that deletes or moves files"
lacks "in another file, a line that runs rm gets no mutant, != included" "src/t.py:1:"
lacks "nor one that runs git -C DIR clean" "src/t.py:2:"
lacks "nor one that runs git --git-dir=... reset" "src/t.py:3:"
expect "but a shell script that deletes nothing gets its mutants, and so does another file's harmless line" 0 \
  "mutate-changed: planned: src/run:2:8: '-ge' becomes '-gt'" "mutate-changed: planned: src/run:2:16: '||' becomes '&&'" \
  "mutate-changed: planned: src/t.py:4:8: '1' becomes '0'" "3 that delete or move files"

# files that are skipped, and why
p4=$(new_project) || abort_sandbox
w4="$p4/w"
printf 'x == 1\n' >"$w4/src/target.py"
ln -s target.py "$w4/src/link.py"
printf 'x == 1\0\n' >"$w4/src/nul.py"
printf 'x == 1 \351\n' >"$w4/src/latin1.py"
perl -e 'print "x == 1\n" x 200000' >"$w4/src/big.py"
printf '*.bat text eol=crlf\ndata.txt filter=lfs\n' >"$w4/src/.gitattributes"
# a stand-in for git-lfs's clean filter: the pointer names the content's hash
cat >"$w4/.git/lfs-clean.sh" <<'EOS'
#!/bin/sh
exec perl -MDigest::SHA -e 'binmode STDIN; local $/; my $c = <STDIN>; $c = "" unless defined $c; printf "version https://git-lfs.github.com/spec/v1\noid sha256:%s\nsize %d\n", Digest::SHA::sha256_hex($c), length $c'
EOS
(cd "$w4" && git config filter.lfs.clean "sh .git/lfs-clean.sh" && git config filter.lfs.smudge cat)
printf 'x == 1\n' >"$w4/src/data.txt"
printf 'if %%x%% == 1 echo y\n' >"$w4/src/run.bat"
printf 'version https://git-lfs.github.com/spec/v1\noid sha256:%s\nsize 3\n' "$(printf '64%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32)" >"$w4/src/fake.txt"
# a file the commit puts in Git LFS whose disk copy is the stored blob (no
# smudge): committed plain first, its LFS rule added after
printf 'x == 1\n' >"$w4/src/ptr.txt"
(cd "$w4" && git add src/ptr.txt && git commit -q -m "A plain file first" && touch -t 202001010000 src/ptr.txt &&
  git update-index -q --refresh && printf 'ptr.txt filter=lfs\n' >>src/.gitattributes)
feat "$w4" "Files to skip"
rm -f "$w4/src/run.bat" && (cd "$w4" && git checkout -q -- src/run.bat)
touch -t 202001010000 "$w4/src/data.txt"
(cd "$w4" && git update-index -q --refresh)
if (cd "$w4" && git cat-file blob HEAD:src/data.txt | grep -q '^version https://git-lfs'); then pass "setup: data.txt is stored as an LFS pointer"; else fail "setup: data.txt is stored as an LFS pointer"; fi
if (cd "$w4" && od -c src/run.bat | grep -q '\\r'); then pass "setup: run.bat is CRLF on disk"; else fail "setup: run.bat is CRLF on disk"; fi
mp "$w4" --list
expect "a link, a NUL file, a file that is not UTF-8, one over 1 MB and one git converts are skipped and counted" 0 \
  "mutate-changed: planned: src/target.py:1:3: '==' becomes '!='" \
  "files skipped: 4 converted by .gitattributes or in Git LFS, 1 larger than 1 MB, 1 left out (the method's or git's own files), 2 not UTF-8 text, 1 not a regular file"
for f in link.py nul.py latin1.py big.py run.bat data.txt ptr.txt fake.txt; do lacks "nothing planned in $f" "src/$f:"; done

# the method's own files, and git's, are never mutated, even with MUTATE_PATHS=.
p5=$(new_project) || abort_sandbox
w5="$p5/w"
(cd "$w5" && git checkout -q main && mkdir -p scripts && cp -R "$root/method/scripts/method" scripts/method &&
  printf 'PRODUCT_PATHS=src\nMUTATE_PATHS=.\nMUTATION_CHECKS=unit\n' >.claude/method.conf && git add -A &&
  git commit -q -m "The method" && git push -q origin main 2>/dev/null && git checkout -q feat && git merge -q main 2>/dev/null)
printf 'x == 1\n' >"$w5/scripts/method/extra.sh"
printf 'unit\tany\t-\t(\\d+) ok\techo 3 ok\nb\tany\t-\t(\\d+) ok\ttest 1 -eq 1 && echo 1 ok\n' >"$w5/checks/project.tsv"
printf 'PRODUCT_PATHS=src\nMUTATE_PATHS=.\nMUTATION_CHECKS=unit\n# x == 1\n' >"$w5/.claude/method.conf"
printf '*.log\n' >"$w5/src/.gitignore"
printf 'top = 1\n' >"$w5/top.py"
mkdir -p "$w5/.Claude" "$w5/Checks"
printf 'x == 1\n' >"$w5/.Claude/x.py"
printf 'x == 1\n' >"$w5/Checks/x.py"
printf 'x == 1\n' >"$w5/src/.GitAttributes"
feat "$w5" "Method files and a top file"
MP="$w5/scripts/method/mutate-changed.sh" mp "$w5" --list
expect "with MUTATE_PATHS=. the method's files, checks/, .claude/ and .gitignore are left out, and the rest is mutated" 0 \
  "mutate-changed: planned: top.py:1:7: '1' becomes '0'" "7 left out (the method's or git's own files)"
lacks "nothing in the method's folder" "scripts/method/"
lacks "nothing in checks/" "checks/project.tsv:"
lacks "nor in .Claude/ (any case: a file system that folds case opens .claude/)" ".Claude/"
lacks "nor in Checks/" "Checks/"
lacks "nor in .GitAttributes" ".GitAttributes"

# git settings and attribute files on this machine change nothing, and run
# nothing: a text conversion, diff settings, a non-ASCII name
p6=$(new_project) || abort_sandbox
w6="$p6/w"
printf 'a = 1\nb = 2\n' >"$w6/src/base.py"
printf 'if a >= 1:\n    b = true\n' >"$w6/src/caf$(printf '\303\251').py"
feat "$w6" "Settings"
mp "$w6" --list
clean=$out
printf '* diff=x\n' >"$w6/.git/info/attributes"
(cd "$w6" && git config diff.x.textconv "touch $work/textconv-ran; cat" && git config diff.noprefix true &&
  git config diff.algorithm patience && git config diff.interHunkContext 10 && git config diff.context 0 &&
  git config core.quotepath true)
mp "$w6" --list
if [ "$out" = "$clean" ]; then pass "local diff settings and a text conversion give the same plan"; else fail "local diff settings and a text conversion give the same plan" "$(printf '%s\n%s\n' "$clean" "$out")"; fi
if [ -e "$work/textconv-ran" ]; then fail "and the conversion program never runs"; else pass "and the conversion program never runs"; fi
expect "a non-ASCII file name is shown as it is" 0 "src/caf$(printf '\303\251').py:1:6: '>=' becomes '>'"

# the screen never shows a line's text, and escapes file names
printf 'key = "sk-ant-api03-%s" if n == 2 else 0\n' "$(perl -e 'print "A" x 95')AA" >"$w6/src/keys.py"
printf 'x == 1\n' >"$w6/src/a$(printf '\033')[31m.py"
feat "$w6" "A key and an escape"
mp "$w6" --list --max 1000
expect "a mutant on a line with a key is planned" 0 "src/keys.py:1:"
lacks "and the key is never on the screen" "sk-ant"
expect "a file name with an escape character is escaped" 0 "src/a\\x1B[31m.py:1:3: '==' becomes '!='"
case "$out" in
  *"$(printf '\033')"*) fail "and no raw escape reaches the screen" "$out" ;;
  *) pass "and no raw escape reaches the screen" ;;
esac

# a number of more than two digits never reaches the screen
printf 'card = 4111111111111111\nparts = "4111-1111-1111-1111"\n' >"$w6/src/card.py"
feat "$w6" "Numbers"
mp "$w6" --list --max 1000
expect "a number of more than two digits is shown by its length only" 0 \
  "mutate-changed: planned: src/card.py:1:8: a 16-digit number becomes that number + 1" \
  "mutate-changed: planned: src/card.py:2:10: a 4-digit number becomes that number + 1"
lacks "and its digits never reach the screen" "4111"

# --list writes nothing and runs nothing: no project check, filter, text
# conversion, external diff, file-system monitor or hook, whatever this
# machine's settings say
p8=$(new_project) || abort_sandbox
w8="$p8/w"
printf '#!/bin/sh\ntouch %s/ran\ncat\n' "$work" >"$work/mark.sh"
chmod +x "$work/mark.sh"
printf 'unit\tany\tcmd:bash\t(\\d+) ok\ttouch %s/check-ran; echo 1 ok\n' "$work" >"$w8/checks/project.tsv"
printf 'x == 1\n' >"$w8/src/a.py"
printf '*.py diff=x filter=y\n' >"$w8/.gitattributes"
feat "$w8" "Hostile settings"
mkdir -p "$work/hooks"
for h in post-checkout post-index-change reference-transaction pre-commit fsmonitor-watchman; do cp "$work/mark.sh" "$work/hooks/$h"; done
(cd "$w8" && git config diff.x.textconv "$work/mark.sh" && git config diff.x.command "$work/mark.sh" &&
  git config diff.external "$work/mark.sh" && git config filter.y.clean "$work/mark.sh" && git config filter.y.smudge "$work/mark.sh" &&
  git config filter.y.process "$work/mark.sh" && git config core.fsmonitor "$work/mark.sh" && git config core.hooksPath "$work/hooks")
before=$(cd "$p8" && find w -type f | LC_ALL=C sort | while read -r f; do cksum "$f"; done)
rm -f "$work/ran" "$work/check-ran"
mp "$w8" --list
expect "setup: a plan under hostile settings" 0 "mutate-changed: planned: src/a.py:1:3: '==' becomes '!='"
after=$(cd "$p8" && find w -type f | LC_ALL=C sort | while read -r f; do cksum "$f"; done)
if [ "$before" = "$after" ]; then pass "no file in the project, .git included, is written or changed"; else fail "no file in the project, .git included, is written or changed" "$(printf '%s\n' "$before" >"$work/b"; printf '%s\n' "$after" | diff "$work/b" - | head -10)"; fi
if [ -e "$work/check-ran" ]; then fail "the project check never runs"; else pass "the project check never runs"; fi
if [ -e "$work/ran" ]; then fail "no filter, conversion, external diff, monitor or hook runs"; else pass "no filter, conversion, external diff, monitor or hook runs"; fi

# errors: a stored file git cannot read, or one changed by hand, stop it
# with a FAIL line (exit 2), never a bare git error
p9=$(new_project) || abort_sandbox
w9="$p9/w"
printf 'def base(x):\n    return x == 2\n' >"$w9/src/base.py"
feat "$w9" "Change"
ob=$(cd "$w9" && git rev-parse main:src/base.py)
nb=$(cd "$w9" && git rev-parse HEAD:src/base.py)
obj="$w9/.git/objects/$(printf '%s' "$ob" | cut -c1-2)/$(printf '%s' "$ob" | cut -c3-)"
src="$w9/.git/objects/$(printf '%s' "$nb" | cut -c1-2)/$(printf '%s' "$nb" | cut -c3-)"
if [ -f "$obj" ] && [ -f "$src" ]; then
  mv "$obj" "$work/obj.saved"
  mp "$w9" --list
  expect "a stored file git cannot read stops it with a FAIL line (exit 2)" 2 "mutate-changed: FAIL - cannot read the stored blob"
  cp "$src" "$obj"
  mp "$w9" --list
  expect "a stored file changed by hand stops it too, before its lines could hide" 2 "mutate-changed: FAIL - " "does not match its id"
  chmod u+w "$obj" && mv "$work/obj.saved" "$obj"
else
  fail "setup: the objects are loose files"
fi
mp "$w9" --list
expect "setup: the plan works again" 0 "mutate-changed: planned: src/base.py:2:17: '2' becomes '3'"

# a deleted file is neither counted nor skipped
(cd "$w9" && printf 'y = 2\n' >src/new.py && git rm -q src/base.py)
feat "$w9" "Delete one, add one"
mp "$w9" --list
expect "a deleted file is neither counted nor skipped" 0 "1 changed lines in 1 files"
lacks "and it is not called a file that is not regular" "not a regular file"

# settings: duplicate check ids count once; a MUTATE_PATHS entry that names
# no tracked file is named
printf 'PRODUCT_PATHS=src\nMUTATE_PATHS=src\nMUTATE_PATHS=srcc\nMUTATION_CHECKS=unit\nMUTATION_CHECKS=unit\n' >"$w9/.claude/method.conf"
feat "$w9" "Settings with a typo"
mp "$w9" --list
expect "a MUTATE_PATHS entry that names no tracked file is named" 0 "MUTATE_PATHS entries that name no tracked file: srcc"
lacks "and a check id given twice counts once" "checks: unit unit"

# the method run from the top folder refuses: every file would be its own
p10=$(new_project) || abort_sandbox
w10="$p10/w"
(cd "$w10" && cp -R "$root/method/scripts/method/lib" lib && cp "$root/method/scripts/method/mutate-changed.sh" . && printf 'y = 2\n' >src/new.py)
feat "$w10" "The method at the top"
MP="$w10/mutate-changed.sh" mp "$w10" --list
expect "a copy run from the top folder refuses (exit 2)" 2 "mutate-changed: FAIL - mutate-changed.sh runs from the top folder"
# a settings file git ignores stops it
(cd "$w10" && git rm -q --cached .claude/method.conf && printf '.claude/method.conf\n' >>.git/info/exclude && git commit -q -m "Untrack the settings")
mp "$w10" --list
expect "a settings file git ignores stops it (exit 2)" 2 ".claude/method.conf is ignored by git" "mutate-changed: FAIL - a config file is ignored by git"

# a link that becomes a file: every line is new, even one equal to the link's target
p11=$(new_project) || abort_sandbox
w11="$p11/w"
(cd "$w11" && git checkout -q main && perl -e 'symlink "a = 1\n", "src/l.py" or die' && git add -A && git commit -q -m link &&
  git push -q origin main 2>/dev/null && git checkout -q feat && git merge -q main 2>/dev/null && rm src/l.py &&
  printf 'a = 1\nb = 2\n' >src/l.py && git add -A && git commit -q -m "Link to file")
mp "$w11" --list
expect "a link that becomes a file has every line planned" 0 "src/l.py:1:5: '1' becomes '0'" "src/l.py:2:5: '2' becomes '3'"
# a branch with no history in common with main stops it
(cd "$w11" && git checkout -q --orphan lone && git commit -q -m lone)
mp "$w11" --list
expect "a branch with no history in common with main stops it (exit 2)" 2 "share no history here"

# no main
p7=$(new_project) || abort_sandbox
(cd "$p7/w" && git remote remove origin)
(cd "$p7/w" && git branch -q -m main trunk)
mp "$p7/w" --list
expect "no main branch stops it with what to do (exit 2)" 2 "mutate-changed: FAIL - no main branch here" "make a branch named main"

for d in $repos; do drop_sandbox "$d"; done
export HOME="$saved_home"
unset GIT_CONFIG_NOSYSTEM
drop_sandbox "$work"
echo "tests: mutate plan: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
