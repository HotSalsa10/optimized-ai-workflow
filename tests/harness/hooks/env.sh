#!/usr/bin/env bash
# env.sh NAME...: a test-only fixture hook. Writes NAME=VALUE (or
# NAME=<unset>) for each NAME into the project's .harness/env.txt, so a case
# can see which settings variables reach a hook.
cat >/dev/null
d="$CLAUDE_PROJECT_DIR/.harness"
mkdir -p "$d"
for n in "$@"; do
  if v=$(printenv "$n"); then printf '%s=%s\n' "$n" "$v"; else printf '%s=<unset>\n' "$n"; fi
done >>"$d/env.txt"
exit 0
