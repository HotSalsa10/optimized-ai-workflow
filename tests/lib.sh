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

# new_sandbox_dir: makes an empty, marked folder outside the repo and prints
# the path of the "repo" folder inside it. The marker sits next to "repo", so
# drop_sandbox can tell a sandbox from any other folder.
new_sandbox_dir() {
  src=$(repo_root) || return 1
  base=${TMPDIR:-/tmp}
  case "$base" in
    /*) ;;
    *) base=/tmp ;; # a relative TMPDIR would put the sandbox inside the repo
  esac
  parent=$(mktemp -d "${base%/}/sandbox.XXXXXX") || return 1
  # compare real paths, so a TMPDIR that is a link into the repo is caught too
  src_real=$(cd -P "$src" && pwd -P) || return 1
  parent_real=$(cd -P "$parent" && pwd -P) || return 1
  case "$parent_real/" in
    "$src_real"/*)
      rm -rf "$parent"
      return 1
      ;;
  esac
  if ! { : >"$parent/.sandbox-marker" && mkdir "$parent/repo"; }; then
    rm -rf "$parent"
    return 1
  fi
  printf '%s\n' "$parent/repo"
}

# make_sandbox: prints the path of a new sandbox repo holding a copy of every
# tracked and untracked (not ignored) file. Fails, and leaves nothing behind,
# if any file could not be copied. Files deleted from the working tree are
# left out, as they would be from a commit. A symlink is copied as a link
# only when its target is relative and does not climb out with "..";
# otherwise the sandbox fails, so no plant can write through a link to a
# place outside the sandbox.
make_sandbox() {
  src=$(repo_root) || return 1
  dir=$(new_sandbox_dir) || return 1
  copy_failed=0
  while IFS= read -r -d '' f; do
    case "$f" in
      */*) to="$dir/${f%/*}" ;;
      *) to=$dir ;;
    esac
    if [ -L "$src/$f" ]; then
      target=$(readlink "$src/$f")
      case "$target" in
        /* | .. | ../* | */.. | */../*) copy_failed=1 ;;
        *) mkdir -p "$to" && ln -s "$target" "$dir/$f" || copy_failed=1 ;;
      esac
    elif [ -f "$src/$f" ]; then
      mkdir -p "$to" && cp -p "$src/$f" "$dir/$f" || copy_failed=1
    fi
  done < <(cd "$src" && git ls-files -z -co --exclude-standard)
  if [ "$copy_failed" -ne 0 ]; then
    drop_sandbox "$dir"
    return 1
  fi
  (
    cd "$dir" || exit 1
    git init -q
    git config core.autocrlf false
    git config user.name "Test"
    git config user.email "test@example.invalid"
    git config commit.gpgsign false
    git add -A
    git commit -q -m "sandbox base"
  ) || {
    drop_sandbox "$dir"
    return 1
  }
  printf '%s\n' "$dir"
}

# drop_sandbox DIR: removes a sandbox made above, and refuses anything else.
drop_sandbox() {
  case "$1" in
    /*/repo) ;;
    *) return 1 ;;
  esac
  parent=${1%/repo}
  [ -f "$parent/.sandbox-marker" ] || return 1
  rm -rf "$parent"
}

# abort_sandbox: a plant could not get a sandbox. Stop the whole file, so no
# plant command runs in the real working tree instead.
abort_sandbox() {
  fail "could not make a sandbox; stopping here"
  exit 1
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
