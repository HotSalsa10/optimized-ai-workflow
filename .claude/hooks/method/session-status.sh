#!/usr/bin/env bash
# session-status.sh: the method's SessionStart hook (step 5.4; R1, M073;
# docs/plans/step5.md, section 6.1; README.md beside it). Claude Code runs it
# at every session start, resume, /clear, compaction and fork, as
#   BASH_ENV= ENV= bash -p "$CLAUDE_PROJECT_DIR/.claude/hooks/method/session-status.sh"
# Its plain output, at most 10 lines and 1,200 bytes, is added to Claude's
# context. It always exits 0: SessionStart cannot block, and text printed
# with any other exit code does not reach Claude (measured).
#
# The first line, METHOD-ACTIVE, is printed here, before perl starts, so it
# is there even when perl or the method's libraries are missing (with a
# LOOK line saying so, also when perl fails); a session without it is a
# session where the method is off. The rest comes from
# lib/session.pl: status.sh --quick's LOOK lines and summary, and warnings
# about settings that weaken the method.
#
# perl starts without any PERL* variable (they can change what perl runs or
# reads; lib/hook-env.sh), through "command perl", so a shell function named
# perl cannot stand in for it.
case "$0" in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
# the version: the first line of scripts/method/method.lock (lib/lock.pl
# writes it), read with the shell's read, before perl starts; vunreleased
# with no lock, vunknown when its first line is not a version line
version=vunreleased
lock="$here/../../../scripts/method/method.lock"
if [ -f "$lock" ]; then
  version=vunknown
  line=
  IFS= read -r line <"$lock" 2>/dev/null
  tab=$(printf '\t')
  case "$line" in
    "version${tab}v"[0-9]*)
      v=${line#version"$tab"}
      case "$v" in
        *[!0-9A-Za-z.+-]* | ????????????????????????*) ;;
        *) version=$v ;;
      esac
      ;;
  esac
fi
# (as the shell sees it: under Git Bash a C:/ path becomes /c/..., which
# perl reads as absolute)
lib=$(cd "$here/../../../scripts/method/lib" 2>/dev/null && pwd) || lib="$here/../../../scripts/method/lib"
# a nested run (claude -p inside a session) skips status, not the settings
# checks: METHOD_NESTED set in a settings file then shows among them
if [ "${METHOD_NESTED:-}" = 1 ]; then
  echo "METHOD-ACTIVE $version (nested: status skipped)"
else
  echo "METHOD-ACTIVE $version"
fi
if [ ! -f "$lib/session.pl" ] || [ ! -f "$lib/hook-env.sh" ]; then
  echo "session-status: LOOK - the method's scripts are missing (scripts/method/lib); run the method's sync"
  exit 0
fi
# shellcheck source=method/scripts/method/lib/hook-env.sh
. "$lib/hook-env.sh"
if ! command perl -MJSON::PP -e 1 >/dev/null 2>&1; then
  echo "session-status: LOOK - perl or its JSON::PP module is missing, so the method's hooks cannot run; install perl"
  exit 0
fi
command perl "$lib/session.pl" 2>/dev/null
code=$?
# a crash leaves METHOD-ACTIVE, and says so (session.pl prints only at its
# end, so nothing of it came out)
if [ "$code" -ne 0 ]; then
  echo "session-status: LOOK - its perl part failed (exit $code), so status and the settings checks are missing; run bash scripts/method/status.sh"
fi
exit 0
