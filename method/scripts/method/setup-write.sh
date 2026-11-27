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
# Rules it serves: M100, M156 (their home is lib/setup.pl).
#
# Exit codes: 0 the card holds (written with --write); 1 refused, nothing
# written (or a write failed: run it again with --write to finish); 2 bad
# usage, perl or one of its modules missing, or started by a bare name not
# from its own folder or not as a file of its own (M163).
set -u
# perl reads bytes; these settings would change how it reads and writes
# them, and the library paths would let modules from elsewhere run inside it
unset PERL_UNICODE PERL5OPT PERL5LIB PERLLIB PERL_USE_UNSAFE_INC PERLIO
if ! command perl -MJSON::PP -MDigest::SHA -e 1 >/dev/null 2>&1; then
  echo "setup: FAIL - perl, or its JSON::PP or Digest::SHA module, is missing"
  exit 2
fi
# only bash and perl are needed, so no dirname; started by a bare name, the
# current folder counts only when $0 and the file bash opened (BASH_SOURCE)
# are both this script's own name and ./setup-write.sh is a file: found on
# PATH (or sourced, or piped), the current folder is not this script's and
# its lib/ could be the project's own, so it refuses (M163; step 8.3,
# docs/plans/step8.md S8)
# (bash's BASH_SOURCE, read through eval only under bash, so a shell
# without arrays still parses this file and is refused below)
self_src=
[ -z "${BASH_VERSION-}" ] || eval 'self_src=${BASH_SOURCE[0]-}'
self_ok=
case "$0" in
  */*)
    # (a $0 with a / counts only when, under bash, it is the file bash
    # opened: sourced from a script elsewhere, $0 is that script's path)
    if [ -z "${BASH_VERSION-}" ] || [ "$self_src" = "$0" ]; then
      here=${0%/*}
      self_ok=1
    fi
    ;;
  *)
    if [ "$0" = setup-write.sh ] && [ "$self_src" = setup-write.sh ] && [ -f ./setup-write.sh ]; then
      here=.
      self_ok=1
    fi
    ;;
esac
if [ -z "$self_ok" ]; then
  printf '%s\n' "setup: FAIL - setup-write.sh was started by a bare name found on PATH, or not as a file of its own; run it by its path, such as bash path/to/setup-write.sh"
  exit 2
fi
exec perl "$here/lib/setup.pl" "$@"
