#!/usr/bin/env bash
# guard.sh: the method's guard (steps 5.5 to 5.10; R7; docs/plans/step5.md,
# section 6.2; README.md beside it). Claude Code runs it before each
# command, edit and outside tool (PreToolUse), as
#   BASH_ENV= ENV= bash "$CLAUDE_PROJECT_DIR/.claude/hooks/method/guard.sh"
# with onFailure "block", so a guard that cannot start or times out blocks.
# The rules are in lib/guard.pl. This wrapper turns its answers into exit
# codes Claude Code reads: 0 lets the call through (with perl's stdout, a
# warning), 2 refuses it (perl's one stderr line is the reason). perl's
# private block code 3 becomes 2; anything else perl ends with is a crash,
# and a crash refuses (G0) with this wrapper's own line only: what perl
# wrote while crashing is dropped, so it can neither split the reason nor
# show text from the call. Without perl nothing can be checked, so every
# call is refused (G1).
# Rules done here (docs/rule-map.md): M128 (G0, G1), M129 (G2).
case "$0" in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
lib="$here/../../../scripts/method/lib"
way_out="if the guard is wrong, see .claude/hooks/method/README.md, \"When the guard blocks something it should not\""
if ! command -v perl >/dev/null 2>&1; then
  echo "guard G1: perl is missing, so this call cannot be checked and is refused; install perl ($way_out)" >&2
  exit 2
fi
if [ ! -f "$lib/hook-env.sh" ] || [ ! -f "$lib/guard.pl" ]; then
  echo "guard G0: the method's scripts are missing ($lib), so this call cannot be checked and is refused; run the method's sync ($way_out)" >&2
  exit 2
fi
# shellcheck source=method/scripts/method/lib/hook-env.sh
. "$lib/hook-env.sh"
# stderr is kept aside, stdout goes through (fd 3)
{ err=$(command perl "$lib/guard.pl" 2>&1 1>&3 3>&-); code=$?; } 3>&1
case $code in
  0) exit 0 ;;
  3)
    # (the last line that is a refusal; perl's warnings never stand in for it)
    # shellcheck disable=SC2016 # a sed program, not a shell expression
    line=$(printf '%s\n' "$err" | sed -n '/^guard G[0-9]/h; ${x;p;}')
    case $line in
      "guard G"*) printf '%s\n' "$line" >&2 ;;
      *) echo "guard G0: the guard gave no reason (code 3), so this call is refused ($way_out)" >&2 ;;
    esac
    exit 2
    ;;
esac
echo "guard G0: the guard stopped without an answer (code $code), so this call is refused ($way_out)" >&2
exit 2
