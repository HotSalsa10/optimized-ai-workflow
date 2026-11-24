# Example projects

Three small projects of different kinds, each shown as it stands before the method, with the answers its owner gives `/method-setup`. All their data is invented.

| Example | What it is | Answers |
|---|---|---|
| `word-game/` | A word game in the terminal, in bash, with a test script | Budget profile, standard, no rules of its own: the floor is the same without a pack |
| `notes-site/` | A small website of notes, plain pages with a perl link check | Balanced profile, standard, one rule; its owner does not write code; the start page's link check is the smoke row |
| `records-keeper/` | A ledger with a history, adopting the method: its own CLAUDE.md and settings, an old export with CRLF line ends, a script that writes "live" rows through the method's live-write helper | Best results, strict (three reviewers on every change), two rules |

Each folder holds `make.sh`, `answers.txt` and `project/`, the project's files. `bash examples/<name>/make.sh DIR` builds the project in DIR, a new folder outside this repository, as a git repository with its history on main. A CLAUDE.md, AGENTS.md or `.claude/` folder an example needs is written there, never here, where it would load into this repository's own sessions.

`tests/examples.test.sh` builds each one, installs the method on a branch as a first install does (the release's sync, then `setup-write.sh` with `answers.txt`), and checks the result: the floor holds, status finds nothing to look at, the checks pass, done-check reads the install and a later change, and running sync and setup again changes nothing.
