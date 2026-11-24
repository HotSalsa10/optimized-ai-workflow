#!/usr/bin/env bash
# Tests for method/scripts/method/live-write.sh, the helper a project's own
# script sources before it writes to live records (M063; step 7.6). A
# stand-in project script sources it, hands method_live_opts its own
# arguments and method_live_write its fixed command; that command writes a
# marker file, so each case can tell whether the write ran.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: live-write"
root=$(repo_root)
helper="$root/method/scripts/method/live-write.sh"
work=$(new_sandbox_dir) || abort_sandbox
# the project's script: sources the helper, passes on its arguments, then
# names its own command. LW_FORM gives the forms a careless script takes:
# noopts (method_live_opts never called), ignored (its status not read),
# nocmd (no command named).
cat >"$work/post.sh" <<'EOS'
#!/usr/bin/env bash
. "$LW_HELPER" || exit 2
case ${LW_FORM:-} in
  noopts) ;;
  ignored) method_live_opts "$@" ;;
  *) method_live_opts "$@" || exit 2 ;;
esac
if [ "${LW_FORM:-}" = nocmd ]; then
  method_live_write
else
  method_live_write bash "$LW_WRITE" "rows file.csv"
fi
EOS
# the write it guards: records its arguments and the reason it was given
cat >"$work/write.sh" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$LW_MARK"
printf 'reason=%s\n' "${METHOD_LIVE_REASON-unset}" >>"$LW_MARK"
exit "${LW_STATUS:-0}"
EOS
mark="$work/written"
W="$work/write.sh"

# lw ARGS...: runs the project's script with ARGS, in the form $form (empty
# for the careful one). Sets out (stdout), err (stderr) and code, and
# removes the marker first.
form=
lw() {
  rm -f "$mark"
  out=$(LW_HELPER="$helper" LW_MARK="$mark" LW_WRITE="$W" LW_FORM="$form" bash "$work/post.sh" "$@" 2>"$work/err")
  code=$?
  err=$(cat "$work/err")
}

# refused NAME WHY ARGS...: the script with ARGS returns 2, writes nothing,
# prints nothing on stdout and says WHY on stderr
refused() {
  r_name=$1
  r_why=$2
  shift 2
  wanted "$r_name" || return 0
  lw "$@"
  if [ "$code" -ne 2 ]; then
    fail "$r_name: exit $code, wanted 2" "$out$err"
  elif [ -e "$mark" ]; then
    fail "$r_name: the write ran" "$out$err"
  elif [ -n "$out" ]; then
    fail "$r_name: printed on stdout" "$out"
  else
    case "$err" in
      "live-write: REFUSED - $r_why"*"; nothing was run") pass "$r_name" ;;
      *) fail "$r_name: the refusal does not say why ($r_why)" "$err" ;;
    esac
  fi
}

refused "no reason: refused, nothing run" "no reason given: a write to live records needs one" --live
refused "no reason and no --live: refused too" "no reason given"
refused "an empty reason: refused" "the reason is empty" --reason "" --live
refused "a reason of spaces only: refused" "the reason is empty" --reason "   " --live
refused "a reason over two lines: refused" "the reason holds a control character" --reason "monthly
close" --live
refused "a reason with a tab: refused" "the reason holds a control character" --reason "$(printf 'month\tclose')" --live
refused "--reason with no text after it: refused" "--reason needs its text" --live --reason
refused "--reason given twice: refused" "--reason is given twice" --reason one --reason two --live
refused "an option it does not know: refused" "the word --reason=close is not known here" --reason=close --live
refused "a command from the person after --: refused" "the word -- is not known here" --reason close --live -- sh -c "echo injected"
refused "a command from the person with no --: refused" "the word sh is not known here" --reason close --live sh -c "echo injected"
form=nocmd
refused "no command named by the script: refused" "no command: the script names the command that writes" --reason close --live
form=noopts
refused "a write with no method_live_opts call: refused" "no reason given: a write to live records needs one, given as --reason \"why this write is made\" and read by method_live_opts" --reason close --live
form=ignored
refused "a refused word leaves no reason kept, though the script ignores the refusal" "the word -- is not known here" --reason close --live --
form=noopts
if wanted "what it keeps never comes from the environment"; then
  rm -f "$mark"
  out=$(_method_live_ok=1 _method_live_on=1 _method_live_reason=x LW_HELPER="$helper" LW_MARK="$mark" LW_WRITE="$W" LW_FORM=noopts bash "$work/post.sh" 2>&1)
  code=$?
  if [ "$code" -eq 2 ] && [ ! -e "$mark" ]; then pass "what it keeps never comes from the environment (exit 2, nothing run)"; else fail "what it keeps never comes from the environment: exit $code" "$out"; fi
fi
form=

if wanted "the dry run is the default"; then
  lw --reason "monthly close, ticket 12"
  line1=$(printf '%s\n' "$out" | sed -n 1p)
  line2=$(printf '%s\n' "$out" | sed -n 2p)
  if [ "$code" -ne 0 ]; then
    fail "the dry run is the default: exit $code, wanted 0" "$out$err"
  elif [ -e "$mark" ]; then
    fail "the dry run is the default: the write ran without --live" "$out"
  elif [ "$line1" != "live-write: reason: monthly close, ticket 12" ]; then
    fail "the dry run is the default: the reason is not the first line" "$out"
  else
    case "$line2" in
      "live-write: dry run, nothing written; add --live to write. It would run: bash "*"/write.sh rows\\ file.csv") pass "the dry run is the default: the reason first, the command named, nothing run" ;;
      *) fail "the dry run is the default: the second line does not name the command" "$out" ;;
    esac
  fi
fi

if wanted "with --live the write runs"; then
  lw --live --reason "monthly close, ticket 12"
  line1=$(printf '%s\n' "$out" | sed -n 1p)
  got=$(cat "$mark" 2>/dev/null)
  if [ "$code" -ne 0 ]; then
    fail "with --live the write runs: exit $code, wanted 0" "$out$err"
  elif [ "$line1" != "live-write: reason: monthly close, ticket 12" ]; then
    fail "with --live the write runs: the reason is not the first line" "$out"
  elif [ "$got" != "rows file.csv
reason=monthly close, ticket 12" ]; then
    fail "with --live the write runs: its arguments or METHOD_LIVE_REASON are not as given" "$got"
  else
    case "$out" in
      *"live-write: live, running: bash "*) pass "with --live the write runs, the reason first, with its arguments and METHOD_LIVE_REASON" ;;
      *) fail "with --live the write runs: the command is not named" "$out" ;;
    esac
  fi
fi

if wanted "with --live the command's status is returned"; then
  rm -f "$mark"
  out=$(LW_HELPER="$helper" LW_MARK="$mark" LW_WRITE="$W" LW_STATUS=3 bash "$work/post.sh" --reason close --live 2>&1)
  code=$?
  if [ "$code" -eq 3 ] && [ -e "$mark" ]; then pass "with --live the command's status is returned (3)"; else fail "with --live the command's status is returned: exit $code" "$out"; fi
fi

if wanted "run on its own, it runs nothing"; then
  rm -f "$mark"
  out=$(LW_MARK="$mark" bash "$helper" --reason close --live -- bash "$W" 2>&1)
  code=$?
  if [ "$code" -eq 2 ] && [ ! -e "$mark" ] && printf '%s\n' "$out" | grep -q '^live-write: FAIL - this file runs nothing on its own'; then
    pass "run on its own, it runs nothing (exit 2)"
  else
    fail "run on its own, it runs nothing: exit $code" "$out"
  fi
fi

if wanted "sourcing it changes no shell option"; then
  # shellcheck disable=SC2016 # the script's text, expanded by the inner bash
  got=$(LW_HELPER="$helper" bash -c 'set -eu; before=$-; . "$LW_HELPER" || exit 9; [ "$-" = "$before" ] && echo same' 2>&1)
  if [ "$got" = same ]; then pass "sourcing it changes no shell option"; else fail "sourcing it changes no shell option" "$got"; fi
fi

if wanted "sourced by a shell that is not bash"; then
  nb=""
  for s in dash posh ksh; do
    if command -v "$s" >/dev/null 2>&1; then
      nb=$s
      break
    fi
  done
  if [ -z "$nb" ]; then
    skip "sourced by a shell that is not bash, it refuses (no dash, posh or ksh here)"
  else
    # shellcheck disable=SC2016 # the script's text, expanded by the inner shell
    got=$(LW_HELPER="$helper" "$nb" -c '. "$LW_HELPER"; echo "status $?"' 2>&1)
    case "$got" in
      *"live-write: FAIL - source this file from a bash script"*"status 2") pass "sourced by a shell that is not bash ($nb), it refuses (status 2)" ;;
      *) fail "sourced by a shell that is not bash ($nb), it refuses" "$got" ;;
    esac
  fi
fi

drop_sandbox "$work" || true
echo "tests: live-write: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
