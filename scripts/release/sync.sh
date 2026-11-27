#!/usr/bin/env bash
# sync.sh: installs or updates the method in a project, from the release
# this checkout holds (step 7.3; docs/plans/step7.md S2, S3, S6; DECISIONS
# A78). Rule M155: sync replaces nothing changed since the lock and writes
# nothing until its whole plan holds.
#
# Usage: bash scripts/release/sync.sh --to PROJECT [--profile best|balanced|budget]
#          [--keep KEY]... [--write] [--source CHECKOUT]
#        bash scripts/release/sync.sh --to PROJECT --uninstall
#          [--keep KEY|PATH]... [--write] [--source CHECKOUT]
#
# With --uninstall (step 8.2; docs/plans/step8.md S7; M162) it takes the
# method back out of the project instead, by lib/uninstall.pl: the plan
# first, and with --write only when the whole plan holds, the settings
# before the files and method.lock last; what stays is named. Like an
# install, it runs where the project's hooks are off (the guard refuses a
# sync run with --write); --profile with it is bad usage.
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
# written (an error sync did not foresee too), or, after writing, the
# installed files do not match the lock or the run failed; 2 bad usage,
# perl missing, or started by a bare name not from its own folder or not
# as a file of its own (M163).
set -u
# (an exported CDPATH would make cd print the folder it found, so here
# would hold two lines)
unset CDPATH
# started by a bare name, the current folder counts only when $0 and the
# file bash opened (BASH_SOURCE) are both this script's own name and
# ./sync.sh is a file: found on PATH (or sourced, or piped), the current
# folder is not this script's and its lib/ could be the project's own, so
# it refuses (M163; step 8.3, docs/plans/step8.md S8)
# (bash's BASH_SOURCE, read through eval only under bash, so a shell
# without arrays still parses this file and is refused below)
self_src=
[ -z "${BASH_VERSION-}" ] || eval 'self_src=${BASH_SOURCE[0]-}'
self_ok=
case "$0" in
  */*)
    # (a $0 with a / counts only under bash, when it is the file bash opened:
    # sourced from a script elsewhere, $0 is that script's path; another
    # shell cannot tell, so it is refused)
    if [ -n "${BASH_VERSION-}" ] && [ "$self_src" = "$0" ]; then
      here=${0%/*}
      self_ok=1
    fi
    ;;
  *)
    if [ "$0" = sync.sh ] && [ "$self_src" = sync.sh ] && [ -f ./sync.sh ]; then
      here=.
      self_ok=1
    fi
    ;;
esac
if [ -z "$self_ok" ]; then
  printf '%s\n' "sync: FAIL - sync.sh was started by a bare name found on PATH, or not as a file of its own; run it by its path, such as bash path/to/sync.sh"
  exit 2
fi
# (-- so a folder whose name starts with - is not read as an option)
here=$(cd -- "$here" && pwd) || {
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
