#!/usr/bin/env bash
# deny.sh WORD: a test-only fixture hook for PreToolUse. Refuses (exit 2,
# the reason on stderr) a call whose input holds WORD; lets others through.
in=$(cat)
case $in in
  *"$1"*)
    echo "HARNESS-DENY: a call holding '$1' is refused" >&2
    exit 2
    ;;
esac
exit 0
