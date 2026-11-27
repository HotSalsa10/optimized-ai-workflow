#!/usr/bin/env bash
# Tests for the scripts that refuse a bare name found on PATH (step 8.3;
# M163, whose home this file is; docs/plans/step8.md S8; review round 4's
# SEC-D). Started as "bash NAME", bash runs ./NAME when the current folder
# holds one and otherwise the first NAME on PATH, with $0 bare either way;
# a script that then took the current folder for its own would run that
# folder's lib/ (the project it judges could plant one). Every script under
# method/scripts/method/ and scripts/release/sync.sh that locates its own
# folder from $0 (it holds case "$0") is found: the eight plan S8 names,
# each by name, and no fewer than eight. Each is copied, with its real lib/
# beside it, into a folder put on PATH, and then, from a folder whose lib/
# holds a planted copy of every library the script names (each would write
# a mark) and which also holds a file named bash and one named like the
# script with a backslash before it:
# - run as "bash NAME" and "bash --posix NAME" (as macOS sh runs it), found
#   on PATH; sourced ("bash -c '. NAME'", $0 then bash, which is a file
#   there); read from standard input ("bash -s"); and given as "x\NAME" (a
#   name with no / that is a file there, as Git Bash reads a path written
#   with backslashes): each is refused with exit 2 and a line naming NAME,
#   and no planted file runs;
# - run as "bash NAME" from its own folder, and by a relative and a full
#   path: it works as before (its usage line, exit 2, for an option no
#   script takes).
# The checks test what each script does, not its text, so the blocks may
# differ in their refusal form.
# shellcheck disable=SC2016 # 'case "$0" in' and the planted perl are literal text
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: scripts that refuse a bare name"
root=$(repo_root)
work=$(new_sandbox_dir) || abort_sandbox
cd "$root" || abort_sandbox

# --- the finder ---
: >"$work/found.txt"
for f in method/scripts/method/*.sh scripts/release/sync.sh; do
  [ -f "$f" ] || continue
  if grep -q 'case "$0" in' "$f"; then printf '%s\n' "$f" >>"$work/found.txt"; fi
done
found=$(wc -l <"$work/found.txt" | tr -d ' ')
missing=""
for f in method/scripts/method/done-check.sh method/scripts/method/run-checks.sh method/scripts/method/status.sh method/scripts/method/review-packet.sh \
  method/scripts/method/report-check.sh method/scripts/method/mutate-changed.sh method/scripts/method/setup-write.sh scripts/release/sync.sh; do
  grep -q -x -F "$f" "$work/found.txt" || missing="$missing $f"
done
n="the finder finds the eight scripts that locate their folder from \$0"
if [ "$found" -ge 8 ] && [ -z "$missing" ]; then pass "$n ($found)"; else fail "$n" "found $found; not found:$missing"; fi

# --- the copies on PATH, and the folder with planted libraries ---
# (method's scripts with their lib/, and the release's sync.sh two folders
# below a copy of the release, as sync.sh reads the release from there)
mkdir -p "$work/m" "$work/rel/scripts" "$work/evil/lib" || abort_sandbox
if ! { cp -R "$root/method/scripts/method" "$work/m/method" && cp -R "$root/scripts/release" "$work/rel/scripts/release"; }; then
  abort_sandbox
fi
mark="$work/mark.txt"

while read -r f; do
  name=${f##*/}
  case "$f" in
    scripts/release/*) bin="$work/rel/scripts/release" ;;
    *) bin="$work/m/method" ;;
  esac
  # each library the script names, planted in the folder it is run from
  rm -rf "$work/evil/lib" "$work/evil/ci" && mkdir -p "$work/evil/lib" "$work/evil/ci/lib"
  grep -o 'lib/[A-Za-z0-9_-]*\.pl' "$f" | sort -u >"$work/libs.txt"
  while read -r lib; do
    printf 'open my $h, ">>", "%s" or die; print $h "%s ran %s\\n"; exit 0;\n' "$mark" "$name" "$lib" >"$work/evil/$lib"
    cp "$work/evil/$lib" "$work/evil/ci/$lib"
  done <"$work/libs.txt"
  # (a file named bash, as $0 is when the script is sourced or read from
  # standard input, and one named x\NAME)
  : >"$work/evil/bash"
  rm -f "$work/evil/x\\"*
  cp "$bin/$name" "$work/evil/x\\$name"
  rm -f "$mark"
  for how in "bash" "bash --posix" "sourced" "standard input" "backslash" "sourced, \$0 chosen" "standard input, \$0 chosen" "sourced, \$0 with a newline" "sourced from a script elsewhere" "standard input, \$0 with a /"; do
    n="$name started by a bare name found on PATH is refused ($how), and the planted lib never runs"
    wanted "$n" || continue
    # (a $0 the caller chose: the script's own name, with a decoy file of
    # that name in the folder, or a name holding a newline, which must not
    # reach the refusal's one line)
    rm -f "$work/evil/$name"
    # shellcheck disable=SC2086 # $how is the shell and its option, split on purpose
    case "$how" in
      sourced) out=$(cd "$work/evil" && PATH="$bin:$PATH" bash -c ". $name --no-such-option" </dev/null 2>&1) ;;
      "standard input") out=$(cd "$work/evil" && bash -s -- --no-such-option <"$bin/$name" 2>&1) ;;
      backslash) out=$(cd "$work/evil" && bash "x\\$name" --no-such-option </dev/null 2>&1) ;;
      "sourced, \$0 chosen")
        : >"$work/evil/$name"
        out=$(cd "$work/evil" && PATH="$bin:$PATH" bash -c ". $name --no-such-option" "$name" </dev/null 2>&1)
        ;;
      "standard input, \$0 chosen")
        : >"$work/evil/$name"
        out=$(cd "$work/evil" && bash -c "exec -a $name bash -s -- --no-such-option" <"$bin/$name" 2>&1)
        ;;
      "sourced, \$0 with a newline")
        nl_name=$(printf 'x\n%s: a forged last line' "$name")
        out=$(cd "$work/evil" && PATH="$bin:$PATH" bash -c ". $name --no-such-option" "$nl_name" </dev/null 2>&1)
        ;;
      # (a $0 with a /: sourced from a script at ci/run.sh, whose ci/lib/
      # holds the planted copies, or read from standard input as ./x;
      # step 8's review, F20)
      "sourced from a script elsewhere")
        out=$(cd "$work/evil" && PATH="$bin:$PATH" bash -c ". $name --no-such-option" ci/run.sh </dev/null 2>&1)
        ;;
      "standard input, \$0 with a /")
        out=$(cd "$work/evil" && bash -c "exec -a ./x bash -s -- --no-such-option" <"$bin/$name" 2>&1)
        ;;
      *) out=$(cd "$work/evil" && PATH="$bin:$PATH" $how "$name" --no-such-option </dev/null 2>&1) ;;
    esac
    code=$?
    rm -f "$work/evil/$name"
    if [ "$code" -eq 2 ] && [ ! -e "$mark" ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] &&
      case "$out" in *"$name was started by a bare name found on PATH, or not as a file of its own"*"run it by its path, such as bash path/to/$name"*) true ;; *) false ;; esac; then
      pass "$n"
    else
      fail "$n" "exit $code; mark: $(cat "$mark" 2>/dev/null); $(printf '%s\n' "$out" | head -3)"
    fi
    rm -f "$mark"
  done
  # it works as before: from its own folder by its bare name, by a relative
  # path, by a full path (with the bare-name copy on PATH too)
  for at in own relative full; do
    n="$name started from its own folder, a relative path or a full path works as before ($at)"
    wanted "$n" || continue
    case "$at" in
      own) out=$(cd "$bin" && PATH="$bin:$PATH" bash "$name" --no-such-option </dev/null 2>&1) ;;
      relative) out=$(cd "$bin/.." && bash "${bin##*/}/$name" --no-such-option </dev/null 2>&1) ;;
      full) out=$(cd "$work/evil" && bash "$bin/$name" --no-such-option </dev/null 2>&1) ;;
    esac
    code=$?
    if [ "$code" -eq 2 ] && [ ! -e "$mark" ] && case "$out" in *usage*) true ;; *) false ;; esac && case "$out" in *"bare name"*) false ;; *) true ;; esac; then
      pass "$n"
    else
      fail "$n" "exit $code; mark: $(cat "$mark" 2>/dev/null); $(printf '%s\n' "$out" | head -3)"
    fi
    rm -f "$mark"
  done
  # (a shell without arrays, dash, from its own folder: the file still
  # parses, and the start is refused with the one line, not a parse error;
  # step 8's review, F21. By a path too: a shell other than bash cannot
  # tell the file it opened, so a script sourcing this one from ci/run.sh,
  # whose ci/lib/ holds the planted copies, would pass; its fresh check)
  for at in "from its own folder" "by a path, sourced from a script elsewhere"; do
    n="$name started by dash $at is refused with its line, not a parse error"
    wanted "$n" || continue
    if command -v dash >/dev/null 2>&1; then
      case "$at" in
        "from its own folder") out=$(cd "$bin" && dash "$name" --no-such-option </dev/null 2>&1) ;;
        *)
          printf '. %s --no-such-option\n' "$bin/$name" >"$work/evil/ci/run.sh"
          out=$(cd "$work/evil" && dash ci/run.sh </dev/null 2>&1)
          ;;
      esac
      code=$?
      if [ "$code" -eq 2 ] && [ ! -e "$mark" ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && case "$out" in *"$name was started by a bare name found on PATH, or not as a file of its own"*) true ;; *) false ;; esac; then
        pass "$n"
      else
        fail "$n" "exit $code; mark: $(cat "$mark" 2>/dev/null); $(printf '%s\n' "$out" | head -3)"
      fi
      rm -f "$mark"
    else
      skip "$n" "dash is not installed here"
    fi
  done
done <"$work/found.txt"

cd "$here" || true
drop_sandbox "$work" || true
echo "tests: scripts that refuse a bare name: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
