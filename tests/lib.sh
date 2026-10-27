# shellcheck shell=bash
# Shared helpers for tests. Source this file; do not run it.
#
# Plants never touch the working tree. Each plant runs in a sandbox: a fresh
# git repo built from a copy of the current tracked and untracked (not ignored)
# files. Removing the sandbox is the revert, so a plant can never be left
# behind and no real work can be lost.

tests_pass=0
tests_fail=0
tests_skip=0

repo_root() {
  git rev-parse --show-toplevel
}

# make_sandbox: prints the path of a new sandbox repo.
make_sandbox() {
  src=$(repo_root) || return 1
  dir=$(mktemp -d 2>/dev/null || mktemp -d -t sandbox) || return 1
  (
    cd "$src" || exit 1
    git ls-files -z -co --exclude-standard | while IFS= read -r -d '' f; do
      [ -f "$f" ] || continue
      mkdir -p "$dir/$(dirname "$f")"
      cp -p "$f" "$dir/$f"
    done
  ) || return 1
  (
    cd "$dir" || exit 1
    git init -q
    git config core.autocrlf false
    git config user.name "Test"
    git config user.email "test@example.invalid"
    git config commit.gpgsign false
    git add -A
    git commit -q -m "sandbox base"
  ) || return 1
  printf '%s\n' "$dir"
}

drop_sandbox() {
  case "$1" in
    "" | /) return 1 ;;
  esac
  rm -rf "$1"
}

pass() {
  tests_pass=$((tests_pass + 1))
  echo "  PASS  $1"
}

fail() {
  tests_fail=$((tests_fail + 1))
  echo "  FAIL  $1"
  if [ -n "${2:-}" ]; then
    printf '%s\n' "$2" | sed 's/^/        /'
  fi
}

skip() {
  tests_skip=$((tests_skip + 1))
  echo "  SKIP  $1 (not a pass)"
}

# expect_green NAME DIR COMMAND...: the check must pass in DIR.
expect_green() {
  name=$1
  dir=$2
  shift 2
  if out=$(cd "$dir" && "$@" 2>&1); then
    pass "$name"
  else
    fail "$name: expected the check to pass on a clean copy" "$out"
  fi
}

# expect_red NAME DIR REASON COMMAND...: the check must fail in DIR with exit
# code 1 (a real finding, not a crash) and its output must contain REASON.
expect_red() {
  name=$1
  dir=$2
  reason=$3
  shift 3
  out=$(cd "$dir" && "$@" 2>&1)
  code=$?
  if [ "$code" -ne 1 ]; then
    fail "$name: expected exit 1 (finding), got $code" "$out"
  elif ! printf '%s\n' "$out" | grep -F -q -- "$reason"; then
    fail "$name: went red, but not for the stated reason ('$reason')" "$out"
  else
    pass "$name"
  fi
}

# expect_landed NAME COMMAND...: confirms a plant really applied, checked in
# the artifact itself, before the check is run.
expect_landed() {
  name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    return 0
  fi
  fail "$name: the plant did not apply, so the check result would mean nothing"
  return 1
}
