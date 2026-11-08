#!/usr/bin/env bash
# context.sh EVENT TEXT: a test-only fixture hook. Answers with TEXT as
# additionalContext for EVENT (SubagentStart adds it to the subagent's
# first request).
cat >/dev/null
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$2"
exit 0
