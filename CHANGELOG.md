# CHANGELOG

Each release has a "What changes for you" section in plain words.

## Unreleased

### What changes for you

Nothing yet. Release 1 is being built.

### Added

- Repo skeleton: records (SPEC, ROADMAP, TASKS, DECISIONS, RISKS, TESTS), MIT licence, pinned line endings, a research summary.
- Rule map with every rule from the original method and the research, and where each one lives.
- Repo checks: line endings, bash 3.2 and BSD portability, secrets and personal data, rule map, workflow hygiene, perl syntax, shellcheck.
- Planted-defect tests: 46 cases, including a 102-line corpus for the portability lint that covers every rule, showing each check goes red for its stated reason and stays green on clean copies and look-alikes.
- CI: Linux on every change; Windows and macOS on release tags and on demand.

### Added (step 2)

- The method's first files, under `method/scripts/method/`: a JSON helper (`lib/json.pl get`), the verdict vocabulary (`verdicts.txt`) with its one reader, and `review-packet.sh`, which builds the one file a reviewer or security checker is given. The packet holds the criteria, the project's incident checklist from the merge base, the check output and the committed diff, never the author's own account. Git settings, file attributes, index flags and hand-changed stored files, folders and commits cannot make it show something other than the commit, and its section markers carry a token no content can copy. The kinds of file it leaves out of the diff are listed by name, with their line counts.
- validate.sh's perl syntax check also covers `method/scripts/`.
- Tests: 3 new test files with 210 test cases, and 1 new plant.

### Added (step 3)

- `run-checks.sh`: runs the method's built-in checks (secrets on every tracked file, fresh-clone, tree-unchanged) and the project's own checks from `checks/*.tsv`. A check passes only when it exited 0 and printed how many things it examined; a check that examined nothing is SKIPPED, never a pass. The whole output goes to a private log under `.method/local/logs/`, masked; the screen shows failures, skips and one last line. Exit codes 0, 1, 2 and 3.
- `status.sh`: one read-only report for any session: work not committed or not pushed (also in linked worktrees and in the other repositories listed in REPOS), commits on main without a valid verdict trailer, the project records, the Claude Code version against the floor, CLAUDE_CODE_EFFORT_LEVEL, perl's modules and CI. It says PASS, LOOK or SKIPPED and exits 1 when something needs a look.
- `.claude/method.conf` settings (PRODUCT_PATHS, LOCAL_ONLY, REPOS, VERDICTS_FROM) with one reader, `lib/conf.pl`, and `REQUIRES` with the Claude Code floor.
- The commit trailer check, `lib/verdicts.pl check-trailer`, used by status.
- Shared helpers `lib/git.pl` (every git call, with the settings that could change what git shows turned off) and `lib/esc.pl` (the one line escaper), taken out of the review packet, whose output is unchanged.
- Tests: 3 new test files and 21 more trailer cases, 276 test cases in all.

### Changed (step 3)

- The secret scan moved into the method (`method/scripts/method/lib/secrets.pl`), lists the tracked files itself, and runs about 7 times faster with the same output.

### Changed (step 1b, from the step 1 security check)

- The checks can no longer be fooled by odd file names: output is escaped, counts are read strictly, and file names never reach a tool as an option.
- Check output never shows a key in full, and a finding shows only its kind and length.
- The secret scan also reads staged copies, files with CR-only line ends and plain text after UTF-16 text. Its allowlist names one text in one file by an id, never the text itself.
- The line-endings check reads files git calls binary because of a lone CR, and handles non-ASCII names.
- The workflow lint treats any YAML form it cannot read as a finding, checks local action files, and wants docker images pinned by digest.
- CI ignores workflow commands in its own output, and manual runs no longer cancel push runs.
- .gitignore keeps local settings and common credential files out of commits in any folder.
- Tests: safe sandbox helpers with their own tests, a .gitignore test, a CI settings test, and 120 test cases in all.
- After the step 1b review: no output line can carry a CI runner command, file names are scanned too, the line-endings check reads staged copies, the workflow lint fails closed on more forms and accepts `permissions: {}`, shellcheck ignores config files, and CI no longer keeps its token on disk.
- After the second step 1b review: the workflow lint accepts only plain YAML and reports every other line, file names are always shown masked, and the test sandboxes refuse every link that could reach outside them.
- After the third step 1b review: a step's time limit no longer counts as its job's; the workflow lint also reports a value continued on the next line and an empty `permissions:`; perl's Unicode settings cannot switch off the escaping; the secret scan reads symlink names and targets; and validate masks a key held in a file name.
