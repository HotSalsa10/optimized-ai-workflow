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

drop_sandbox "$src_repo"
echo "tests: sandbox helpers: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
