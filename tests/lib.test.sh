#!/usr/bin/env bash
# Tests for the sandbox helpers in tests/lib.sh. Plants rely on them never
# touching the real working tree, so each safety rule is checked here.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: sandbox helpers"
tmp_base=${TMPDIR:-/tmp}
case "$tmp_base" in
  /*) ;;
  *) tmp_base=/tmp ;;
esac

# A small source repo with awkward names: a leading dash and a space.
src_repo=$(new_sandbox_dir) || abort_sandbox
(
  cd "$src_repo" || exit 1
  git init -q
  git config user.name "Test"
  git config user.email "test@example.invalid"
  git config commit.gpgsign false
  mkdir -p "sub dir"
  printf 'dash\n' >./-dash.txt
  printf 'nested\n' >"sub dir/a.txt"
  git add -A
  git commit -q -m base
) || abort_sandbox

# 1. every file is copied, also one whose name starts with "-"
sb=$(cd "$src_repo" && make_sandbox) || abort_sandbox
if cmp -s "$src_repo/-dash.txt" "$sb/-dash.txt" && cmp -s "$src_repo/sub dir/a.txt" "$sb/sub dir/a.txt"; then
  pass "make_sandbox copies a file named with a leading dash and a nested file"
else
  fail "make_sandbox copies a file named with a leading dash and a nested file" "$(ls -la "$sb" 2>&1)"
fi
drop_sandbox "$sb"

# 2. a failed copy fails the whole sandbox and leaves nothing behind (in a
#    temp folder of its own, so other test runs cannot change what is there)
private_tmp=$(mktemp -d "${tmp_base%/}/privtmp.XXXXXX") || abort_sandbox
# make_sandbox_failing_cp: make_sandbox from the source repo while every cp fails.
make_sandbox_failing_cp() {
  cd "$src_repo" || return 1
  cp() { return 1; }
  make_sandbox
}
out=$(TMPDIR=$private_tmp make_sandbox_failing_cp)
code=$?
left=$(ls -A "$private_tmp")
if [ "$code" -ne 0 ] && [ -z "$out" ] && [ -z "$left" ]; then
  pass "make_sandbox fails, and leaves no folder, when a file cannot be copied"
else
  fail "make_sandbox fails, and leaves no folder, when a file cannot be copied: exit $code, printed '$out', left behind: $left"
fi
rm -rf "$private_tmp"

# 3. drop_sandbox refuses a folder it did not make
other=$(mktemp -d "${tmp_base%/}/notsandbox.XXXXXX") || abort_sandbox
mkdir "$other/repo"
if ! drop_sandbox "$other/repo" && ! drop_sandbox "" && ! drop_sandbox / && [ -d "$other/repo" ]; then
  pass "drop_sandbox refuses an empty path, / and a folder without the sandbox marker"
else
  fail "drop_sandbox refuses an empty path, / and a folder without the sandbox marker"
fi
rm -rf "$other"

# 4. a relative TMPDIR never puts the sandbox inside the repo
sb=$(cd "$src_repo" && TMPDIR=. make_sandbox) || abort_sandbox
case "$sb" in
  "$src_repo"/* | [!/]*) fail "make_sandbox with a relative TMPDIR made $sb inside the repo or with a relative path" ;;
  *) pass "make_sandbox with a relative TMPDIR still makes an absolute path outside the repo" ;;
esac
drop_sandbox "$sb"

# 5. a TMPDIR inside the repo, or a link to a folder inside it, is refused
mkdir -p "$src_repo/tmp-inside"
out=$(cd "$src_repo" && TMPDIR="$src_repo/tmp-inside" make_sandbox)
code=$?
left=$(ls -A "$src_repo/tmp-inside")
if [ "$code" -ne 0 ] && [ -z "$out" ] && [ -z "$left" ]; then
  pass "make_sandbox refuses a TMPDIR inside the repo"
else
  fail "make_sandbox refuses a TMPDIR inside the repo: exit $code, made '$out', left behind: $left"
fi
link_parent=$(mktemp -d "${tmp_base%/}/linktmp.XXXXXX") || abort_sandbox
ln -s "$src_repo/tmp-inside" "$link_parent/tmp" 2>/dev/null
if [ -L "$link_parent/tmp" ]; then
  out=$(cd "$src_repo" && TMPDIR="$link_parent/tmp" make_sandbox)
  code=$?
  left=$(ls -A "$src_repo/tmp-inside")
  if [ "$code" -ne 0 ] && [ -z "$out" ] && [ -z "$left" ]; then
    pass "make_sandbox refuses a TMPDIR that is a link into the repo"
  else
    fail "make_sandbox refuses a TMPDIR that is a link into the repo: exit $code, made '$out', left behind: $left"
  fi
else
  skip "a TMPDIR that is a link: this system cannot make symlinks"
fi
rm -rf "$link_parent" "$src_repo/tmp-inside"

# 6. a symlink that points outside the repo, or whose target ln would read as
#    an option, fails the sandbox, so no plant can write through it. The
#    targets do not exist, so a system that copies instead of linking (Git
#    Bash) copies nothing and the test is skipped.
ln -s /nonexistent-sandbox-test/x "$src_repo/abs-link" 2>/dev/null
ln -s ../outside "$src_repo/up-link" 2>/dev/null
if [ -L "$src_repo/abs-link" ] && [ -L "$src_repo/up-link" ]; then
  out=$(cd "$src_repo" && make_sandbox)
  code=$?
  if [ "$code" -ne 0 ] && [ -z "$out" ]; then
    pass "make_sandbox fails on a symlink that points outside the repo"
  else
    fail "make_sandbox fails on a symlink that points outside the repo: exit $code, made '$out'"
    [ -n "$out" ] && drop_sandbox "$out"
  fi
  rm -f "$src_repo/abs-link"
  out=$(cd "$src_repo" && make_sandbox)
  code=$?
  if [ "$code" -ne 0 ] && [ -z "$out" ]; then
    pass "make_sandbox fails on a symlink that climbs out with .."
  else
    fail "make_sandbox fails on a symlink that climbs out with ..: exit $code, made '$out'"
    [ -n "$out" ] && drop_sandbox "$out"
  fi
  rm -f "$src_repo/up-link"
  # "-toutdir" names a folder that exists, so GNU ln, if it read the target
  # as its -t option, would write a link into it
  mkdir "$src_repo/outdir"
  ln -s -- -toutdir "$src_repo/dash-link"
  out=$(cd "$src_repo" && make_sandbox)
  code=$?
  if [ "$code" -ne 0 ] && [ -z "$out" ] && [ -z "$(ls -A "$src_repo/outdir")" ]; then
    pass "make_sandbox fails on a symlink whose target starts with -, and writes nothing"
  else
    fail "make_sandbox fails on a symlink whose target starts with -, and writes nothing: exit $code, made '$out', in outdir: $(ls -A "$src_repo/outdir")"
    [ -n "$out" ] && drop_sandbox "$out"
  fi
  rm -rf "$src_repo/dash-link" "$src_repo/outdir"
  for target in '..\outside' 'C:/outside'; do
    ln -s -- "$target" "$src_repo/win-link"
    out=$(cd "$src_repo" && make_sandbox)
    code=$?
    if [ "$code" -ne 0 ] && [ -z "$out" ]; then
      pass "make_sandbox fails on a symlink to the Windows path $target"
    else
      fail "make_sandbox fails on a symlink to the Windows path $target: exit $code, made '$out'"
      [ -n "$out" ] && drop_sandbox "$out"
    fi
    rm -f "$src_repo/win-link"
  done
else
  skip "symlinks that point outside: this system cannot make symlinks"
fi
rm -f "$src_repo/abs-link" "$src_repo/up-link"

# 7. a plant runs only the cases that can show its reason (TEST_ONLY), after
# the same cases passed on the clean copy (DECISIONS A70)
if (unset TEST_ONLY; wanted "any case") && TEST_ONLY="" wanted "any case"; then
  pass "wanted keeps every case when TEST_ONLY is unset or empty"
else
  fail "wanted keeps every case when TEST_ONLY is unset or empty"
fi
if TEST_ONLY="a write is refused" wanted "a write is refused: rm x" && TEST_ONLY="a write is refused: rm x: wanted guard G6" wanted "a write is refused: rm x"; then
  pass "wanted keeps a case whose name starts with the reason, and one whose FAIL line would"
else
  fail "wanted keeps a case whose name starts with the reason, and one whose FAIL line would"
fi
if ! TEST_ONLY="a write is refused" wanted "a read passes" && ! TEST_ONLY="a write is refused: rm x" wanted "a write is refused: rm y"; then
  pass "wanted skips a case that cannot print the reason"
else
  fail "wanted skips a case that cannot print the reason"
fi
if TEST_ONLY="case two" wanted_any "case one" "case two" && ! TEST_ONLY="case three" wanted_any "case one" "case two"; then
  pass "wanted_any keeps a group when any of its names is wanted"
else
  fail "wanted_any keeps a group when any of its names is wanted"
fi
fake=$(new_sandbox_dir) || abort_sandbox
cat >"$fake/fake.test.sh" <<FAKE
. "$here/lib.sh"
if wanted "case one"; then if [ -f detail ]; then fail "case one: other" "FAIL  case one: in detail"; elif [ -f broken ]; then fail "case one: broke"; else pass "case one"; fi; fi
if wanted "case two"; then if [ -f needs ]; then pass "case two"; else fail "case two: needs a file the clean copy lacks"; fi; fi
[ "\$tests_fail" -eq 0 ]
FAKE
out=$(plant_control "p1" "$fake" fake.test.sh "case one")
code=$?
if [ "$code" -eq 0 ] && [ -z "$out" ]; then pass "plant_control lets a plant on when its cases pass on the clean copy"; else fail "plant_control lets a plant on when its cases pass on the clean copy" "exit $code: $out"; fi
out=$(plant_control "p2" "$fake" fake.test.sh "case two")
code=$?
case "$code:$out" in
  "1:  FAIL  p2: the cases kept for its reason fail without the plant too"*) pass "plant_control fails a plant whose cases fail on the clean copy too" ;;
  *) fail "plant_control fails a plant whose cases fail on the clean copy too" "exit $code: $out" ;;
esac
out=$(plant_judge "p3" "$fake" fake.test.sh "case one" only)
case "$out" in "  FAIL  p3: the test stayed green"*) pass "plant_judge fails a plant that left the test green" ;; *) fail "plant_judge fails a plant that left the test green" "$out" ;; esac
out=$(plant_judge "p6" "$fake" fake.test.sh "case one")
case "$out" in "  FAIL  p6: went red, but not for the stated reason"*) pass "plant_judge without only runs the whole test file" ;; *) fail "plant_judge without only runs the whole test file" "$out" ;; esac
out=$(cd "$fake" && TEST_ONLY="case one" bash fake.test.sh 2>&1)
case "$out" in *"  SKIP  every case that cannot show 'case one'"*) pass "a run with TEST_ONLY says so in a SKIP line" ;; *) fail "a run with TEST_ONLY says so in a SKIP line" "$out" ;; esac
: >"$fake/broken"
out=$(plant_judge "p4" "$fake" fake.test.sh "case one" only)
case "$out" in "  PASS  p4") pass "plant_judge passes a plant that turned the test red for its reason" ;; *) fail "plant_judge passes a plant that turned the test red for its reason" "$out" ;; esac
out=$(plant_judge "p5" "$fake" fake.test.sh "case one: another reason" only)
case "$out" in "  FAIL  p5: went red, but not for the stated reason"*) pass "plant_judge fails a plant that turned the test red for another reason" ;; *) fail "plant_judge fails a plant that turned the test red for another reason" "$out" ;; esac
: >"$fake/detail"
out=$(plant_judge "p7" "$fake" fake.test.sh "case one: in detail" only)
case "$out" in "  FAIL  p7: went red, but not for the stated reason"*) pass "plant_judge does not take a FAIL text in a detail line for the reason" ;; *) fail "plant_judge does not take a FAIL text in a detail line for the reason" "$out" ;; esac
drop_sandbox "$fake"

# plant_data with "only": the control runs before the plant is applied, and
# a good plant is applied and judged
pdrepo=$(new_sandbox_dir) || abort_sandbox
(
  cd "$pdrepo" || exit 1
  git init -q
  printf 'ok\n' >target.txt
  cat >fake.test.sh <<FAKE
. "$here/lib.sh"
if wanted "case one"; then if grep -q broken target.txt; then fail "case one: broke"; else pass "case one"; fi; fi
if wanted "case two"; then fail "case two: fails on every copy"; fi
[ "\$tests_fail" -eq 0 ]
FAKE
) || abort_sandbox
pddata=$(new_sandbox_dir) || abort_sandbox
printf '=== good | target.txt | case one\nok\n---\nbroken\n=== bad | target.txt | case two\nok\n---\nbroken\n' >"$pddata/plants.txt"
out=$(cd "$pdrepo" && plant_data "$pddata/plants.txt" fake.test.sh only 2>&1)
case "$out" in *"  PASS  good"*) pass "plant_data with only applies a good plant and judges it" ;; *) fail "plant_data with only applies a good plant and judges it" "$out" ;; esac
case "$out" in *"  FAIL  bad: the cases kept for its reason fail without the plant too"*) pass "plant_data with only refuses a plant whose cases fail on the clean copy" ;; *) fail "plant_data with only refuses a plant whose cases fail on the clean copy" "$out" ;; esac
drop_sandbox "$pdrepo"
drop_sandbox "$pddata"

drop_sandbox "$src_repo"
echo "tests: sandbox helpers: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
