#!/usr/bin/env bash
# block-once.sh: a test-only fixture hook for SubagentStop. Blocks the stop
# once (exit 2) when the agent's last message has no END-VERDICT line; never
# blocks a second time.
in=$(cat)
case $in in *'"stop_hook_active":true'*) exit 0 ;; esac
case $in in *END-VERDICT*) exit 0 ;; esac
printf 'block-once\tfired\n' >>"$CLAUDE_PROJECT_DIR/.harness/events.tsv"
echo "HARNESS-BLOCK-ONCE: end with your verdict line" >&2
exit 2
