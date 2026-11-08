#!/usr/bin/env bash
# session-status.sh: the method's SessionStart hook (step 5.4; R1, M073;
# docs/plans/step5.md, section 6.1; README.md beside it). Claude Code runs it
# at every session start, resume, /clear, compaction and fork, as
#   BASH_ENV= ENV= bash "$CLAUDE_PROJECT_DIR/.claude/hooks/method/session-status.sh"
# Its plain output, at most 10 lines and 1,200 bytes, is added to Claude's
# context. It always exits 0: SessionStart cannot block, and text printed
# with any other exit code does not reach Claude (measured).
#
# The first line, METHOD-ACTIVE, is printed here, before perl starts, so it
# is there even when perl or the method's libraries are missing; a session
# without it is a session where the method is off. The rest comes from
# lib/session.pl: status.sh --quick's LOOK lines and summary, and warnings
# about settings that weaken the method.
#
# perl starts without any PERL* variable (they can change what perl runs or
# reads), through "command perl", so a shell function named perl cannot
# stand in for it.
version=unreleased    # step 7's method.lock gives the version
case "$0" in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
lib="$here/../../../scripts/method/lib"
if [ "${METHOD_NESTED:-}" = 1 ]; then
  echo "METHOD-ACTIVE v$version (nested: status skipped)"
  exit 0
fi
echo "METHOD-ACTIVE v$version"
for name in $(env | sed -n 's/^\(PERL[A-Za-z0-9_]*\)=.*/\1/p'); do
  unset "$name"
done
if ! command perl -MJSON::PP -e 1 >/dev/null 2>&1; then
  echo "session-status: LOOK - perl or its JSON::PP module is missing, so the method's hooks cannot run; install perl"
  exit 0
fi
if [ ! -f "$lib/session.pl" ]; then
  echo "session-status: LOOK - the method's scripts are missing ($lib); run the method's sync"
  exit 0
fi
command perl "$lib/session.pl" 2>/dev/null
exit 0
