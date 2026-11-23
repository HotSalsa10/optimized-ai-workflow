#!/usr/bin/env bash
# setup-write.sh: writes a project's setup from the owner's answers (step
# 7.4; docs/plans/step7.md S9, S10; DECISIONS A78 (9), (10)). The
# /method-setup skill writes the answers to .claude/setup-answers.txt and
# runs this: first without --write, which prints the card (what the
# answers change) and the files it would write, and writes nothing; then,
# once the owner agrees with the card, with --write.
#
# Usage: bash scripts/method/setup-write.sh [--write]
#
# It works on the project this script is installed in (two folders up). It
# writes only the seeded files when they are absent, its own method-setup
# blocks, the pack's working.md and project.md blocks, and the profile's
# three keys in .claude/settings.json with method.lock's profile and
# settings lines; it refuses, naming the answer, file or key, before
# anything is written. lib/setup.pl does the work and says what each
# refusal means.
#
# Rules it serves:
# - M100: setup answers never lower the floor.
# - M156: setup writes only through setup-write from an answers file and
#   never overwrites a project file outside its block.
#
# Exit codes: 0 the card holds (written with --write); 1 refused, nothing
# written (or a write failed: run it again with --write to finish); 2 bad
# usage, or perl or one of its modules is missing.
set -u
# perl reads bytes; these settings would change how it reads and writes
# them, and the library paths would let modules from elsewhere run inside it
unset PERL_UNICODE PERL5OPT PERL5LIB PERLLIB PERL_USE_UNSAFE_INC PERLIO
if ! command perl -MJSON::PP -MDigest::SHA -e 1 >/dev/null 2>&1; then
  echo "setup: FAIL - perl, or its JSON::PP or Digest::SHA module, is missing"
  exit 2
fi
# only bash and perl are needed, so no dirname
case "$0" in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
exec perl "$here/lib/setup.pl" "$@"
