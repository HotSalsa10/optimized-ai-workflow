#!/usr/bin/env bash
# make.sh: builds the word-game example (step 7.7; docs/plans/step7.md
# S15) in DIR, a new folder outside this repository: a small terminal game
# in bash with its test script, one commit on main, before the method. Its
# owner's answers to /method-setup are in answers.txt: profile Budget,
# standard, no rules of its own, so the method's floor is seen to be the
# same without a pack. tests/examples.test.sh installs the method into it.
#
# Usage: bash examples/word-game/make.sh DIR
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=examples/lib.sh
. "$here/../lib.sh" || exit 2
example_start "$here" "${1:-}"
example_commit 2026-01-05T10:00:00Z "A word game in the terminal" || exit 1
echo "make: word-game built in $(pwd)"
