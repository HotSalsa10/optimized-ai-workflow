#!/usr/bin/env bash
# make.sh: builds the records-keeper example (step 7.7; docs/plans/step7.md
# S15) in DIR, a new folder outside this repository: a project with a
# history that adopts the method. A ledger of invented items, a script
# that posts its rows to a "live" ledger (a local file) through the
# method's live-write helper, an old export with CRLF line ends, a
# requirements.txt with no package in it yet, a CLAUDE.md of its own
# without @AGENTS.md, and a .claude/settings.json with its own PostToolUse
# hook, allow rules and deny rule, in three commits on main. Its owner's
# answers to /method-setup are in answers.txt: profile Best results,
# strict, with rules of its own. tests/examples.test.sh installs the
# method into it.
#
# The CRLF file, CLAUDE.md and .claude/ are written here, in the new
# folder, never under this repository: its line-ends rule is LF, and a
# CLAUDE.md or .claude/ under its tree would load into its sessions.
#
# Usage: bash examples/records-keeper/make.sh DIR
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=examples/lib.sh
. "$here/../lib.sh" || exit 2
example_start "$here" "${1:-}"
example_commit 2025-09-01T08:00:00Z "The ledger and its check" README.md ledger.csv requirements.txt scripts/check-ledger.sh || exit 1
perl -pi -e 's/\n/\r\n/' exports/2025-export.csv || exit 1
example_commit 2025-10-01T08:00:00Z "An export from the spreadsheet program, as it wrote it" exports || exit 1
mkdir -p .claude || exit 1
cat >CLAUDE.md <<'TEXT'
# Notes for Claude

Amounts in ledger.csv are whole cents.
Never run scripts/post-rows.sh with --live; the owner does.
TEXT
cat >.claude/settings.json <<'TEXT'
{
  "permissions": {
    "allow": [
      "Bash(bash scripts/check-ledger.sh)",
      "Bash(bash scripts/post-rows.sh --reason *)"
    ],
    "deny": [
      "Bash(bash scripts/post-rows.sh *--live*)"
    ]
  },
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash scripts/check-ledger.sh"
          }
        ]
      }
    ]
  }
}
TEXT
example_commit 2025-11-03T08:00:00Z "Post the rows to the live ledger; notes and settings for Claude" || exit 1
echo "make: records-keeper built in $(pwd)"
