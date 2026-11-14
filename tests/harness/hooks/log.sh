#!/usr/bin/env bash
# log.sh EVENT: a test-only fixture hook (never shipped). Saves the hook's
# input under the project's .harness/ folder and adds a line to
# .harness/events.tsv, so a case can see that EVENT fired and what it got.
ev=${1:-unknown}
d="$CLAUDE_PROJECT_DIR/.harness"
mkdir -p "$d"
in=$(cat)
printf '%s\n' "$in" >"$d/$ev-$$.json"
printf '%s\t%s\n' "$ev" "$ev-$$.json" >>"$d/events.tsv"
exit 0
