#!/usr/bin/env bash
# allow.sh: a test-only fixture hook for PreToolUse (never shipped). Allows
# the call. At 2.1.319, auto mode's safety check does not run against the
# fake, so the client refuses an Agent call unless a hook allows it; at
# 2.1.316 it only skips the main conversation's check (docs/plans/step5b.md,
# section 6).
cat >/dev/null
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"HARNESS-ALLOW"}}\n'
exit 0
