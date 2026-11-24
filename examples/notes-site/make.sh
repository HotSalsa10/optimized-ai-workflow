#!/usr/bin/env bash
# make.sh: builds the notes-site example (step 7.7; docs/plans/step7.md
# S15) in DIR, a new folder outside this repository: a small website of
# plain pages with a perl link check, two commits on main, before the
# method. Its owner, who does not write code, answers /method-setup as in
# answers.txt: profile Balanced, standard, one rule of their own; the start
# page's link check is the smoke row. tests/examples.test.sh installs the
# method into it.
#
# Usage: bash examples/notes-site/make.sh DIR
set -u
unset CDPATH # (cd would print the folder it found through it)
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=examples/lib.sh
. "$here/../lib.sh" || exit 2
example_start "$here" "${1:-}"
example_commit 2026-02-02T09:00:00Z "My notes: the start page and the garden" README.md check-links.pl pages/index.html pages/garden.html pages/style.css || exit 1
example_commit 2026-02-09T09:00:00Z "Notes from the kitchen" || exit 1
echo "make: notes-site built in $(pwd)"
