# Example projects

Three small projects of different kinds, each shown as it stands before the method, with the answers its owner gives `/method-setup`. All their data is invented.

| Example | What it is | Answers |
|---|---|---|
| `word-game/` | A word game in the terminal, in bash, with a test script | Budget profile, standard, no rules of its own: the floor is the same without a pack |
| `notes-site/` | A small website of notes, plain pages with a perl link check | Balanced profile, standard, one rule; its owner does not write code; the start page's link check is the smoke row |
| `records-keeper/` | A ledger with a history, adopting the method: its own CLAUDE.md and settings, an old export with CRLF line ends, a script that writes "live" rows through the method's live-write helper | Best results, strict (three reviewers on every change), two rules |

Each folder holds `make.sh`, `answers.txt` and `project/`, the project's files. `bash examples/<name>/make.sh DIR` builds the project in DIR, a new folder outside this repository, as a git repository with its history on main. A CLAUDE.md, AGENTS.md or `.claude/` folder an example needs is written there, never here, where it would load into this repository's own sessions.

`tests/examples.test.sh` builds each one, installs the method on a branch as a first install does (the release's sync, with `--keep PostToolUse` for records-keeper's own hook, then `setup-write.sh` with `answers.txt`), and checks the result: the floor holds, status finds nothing to look at, the checks pass, done-check reads the install and a later change, and running sync and setup again changes nothing.

## Taking the method out

`bash scripts/release/sync.sh --to PROJECT --uninstall` (from a clean checkout of a release tag; step 8.2, M162) shows the plan of taking the method back out of a project and writes nothing; with `--write` it writes it, only when the whole plan holds. It runs where the project's hooks are off, as an install does: the guard refuses any sync run with `--write` in a session with the hooks on. It removes only what `scripts/method/method.lock` and the installed settings fragment say the method put there, each unchanged since the lock: the method's files, its keys, deny entries and hook entries in `.claude/settings.json`, and its two blocks in `.gitignore` and `.gitattributes`, the settings first and the lock last. A changed method file or method key is a conflict that names what to do (`--keep PATH` or `--keep KEY` keeps it). When the install was committed, it reads the commit before the install, so what the project held before comes back as it was, byte for byte. What stays is named: the project's own keys and files, `.method/local/` (the method's logs and review receipts), and the files `/method-setup` wrote that still mention the method, which Claude removes or edits with you on the same branch. Its last line says to start a new session.

An uninstall removes the method's reviewers and checks with the rest, so its branch cannot be reviewed by them. Like a first install, it is merged on its plan and check output alone, its pull request carrying `Review-Verdict: not-required - uninstall of the method <tag>` (the owner's exception of 26 November 2026, RISKS #21).
