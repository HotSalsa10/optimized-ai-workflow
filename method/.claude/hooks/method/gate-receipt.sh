#!/usr/bin/env bash
# gate-receipt.sh: the method's third hook (step 5b; docs/plans/step5b.md;
# README.md beside it). Claude Code runs it when one of the method's
# checking agents (a gate) starts and stops (SubagentStart, SubagentStop,
# matched by the gates' names) and when a gate hands its report back in
# auto mode (PreToolUse of SubagentHandback), as
#   BASH_ENV= ENV= bash -p "$CLAUDE_PROJECT_DIR/.claude/hooks/method/gate-receipt.sh"
# with no onFailure. lib/receipt.pl writes the gate's receipt. Only a
# deliberate block refuses: perl's private block code 3, with its one
# "gate-receipt: " line, becomes exit 2 (the gate is sent back once to
# finish its report). Anything else is exit 0, a missing perl, a missing
# script and a crash included: at SubagentStop an exit 2 would send the
# gate back to work, so a hook that cannot judge stays out of the way and
# the receipt says "not checked".
case "$0" in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
# (as the shell sees it: under Git Bash a C:/ path becomes /c/..., which
# perl reads as absolute)
lib=$(cd "$here/../../../scripts/method/lib" 2>/dev/null && pwd) || lib="$here/../../../scripts/method/lib"
# (without its scripts, or without perl, the run below fails and the last
# line makes it exit 0)
if [ ! -f "$lib/receipt.pl" ] || [ ! -f "$lib/hook-env.sh" ]; then
  exit 0
fi
# shellcheck source=method/scripts/method/lib/hook-env.sh
. "$lib/hook-env.sh"
# perl's stdout (the start's context, the handback's refusal) goes out as
# it is; its stderr is kept aside for the block's line
{ err=$(command perl "$lib/receipt.pl" 2>&1 1>&3 3>&-); code=$?; } 3>&1
if [ "$code" -eq 3 ]; then
  # shellcheck disable=SC2016 # a sed script, not shell
  line=$(printf '%s\n' "$err" | sed -n '/^gate-receipt: /h; ${x;p;}')
  if [ -n "$line" ]; then
    printf '%s\n' "$line" >&2
    exit 2
  fi
fi
exit 0
