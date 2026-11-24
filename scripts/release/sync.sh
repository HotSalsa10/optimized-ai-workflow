#!/usr/bin/env bash
# sync.sh: installs or updates the method in a project, from the release
# this checkout holds (step 7.3; docs/plans/step7.md S2, S3, S6; DECISIONS
# A78). Rule M155: sync replaces nothing changed since the lock and writes
# nothing until its whole plan holds.
#
# Usage: bash scripts/release/sync.sh --to PROJECT [--profile best|balanced|budget]
#          [--keep KEY]... [--write] [--source CHECKOUT]
#
# It runs from a clean checkout of the method's repository at an exact v*
# tag, so a new release always runs its own sync; --source, when given,
# must name that same checkout. It never fetches. Without --write it prints
# the plan, each file as install, update, unchanged, remove or conflict,
# and writes nothing; with --write it writes only when the whole plan
# holds: a marker under .method/local/ first, method.lock last. The layout:
# method/X goes to X, except method/settings.fragment.json, which is
# installed as scripts/method/settings.method.json and merged into
# .claude/settings.json. The work is done by lib/sync.pl, which says what
# each refusal means.
#
# Exit codes: 0 the plan holds (written with --write); 1 refused, nothing
# written (or, after writing, the installed files do not match the lock);
# 2 bad usage, or perl is missing.
set -u
# (an exported CDPATH would make cd print the folder it found, so here
# would hold two lines)
unset CDPATH
case "$0" in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
here=$(cd "$here" && pwd) || {
  echo "sync: FAIL - cannot find the folder this script is in"
  exit 2
}
# PERL* variables could change what perl runs or reads
for _sync_name in $(compgen -e); do
  case $_sync_name in
    PERL*) unset "$_sync_name" ;;
  esac
done
unset _sync_name
if ! command perl -MJSON::PP -MDigest::SHA -e 1 >/dev/null 2>&1; then
  echo "sync: FAIL - perl, or its JSON::PP or Digest::SHA module, is missing"
  exit 2
fi
exec perl "$here/lib/sync.pl" "$here/../.." "$@"
