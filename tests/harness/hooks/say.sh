#!/usr/bin/env bash
# say.sh TEXT [CODE]: a test-only fixture hook. Prints TEXT on stdout and
# exits CODE (0 by default). On SessionStart, text printed with exit 0 is
# added to Claude's context.
cat >/dev/null
printf '%s\n' "$1"
exit "${2:-0}"
