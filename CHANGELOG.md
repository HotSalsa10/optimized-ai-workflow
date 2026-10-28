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

- The method's first files, under `method/scripts/method/`: a JSON helper (`lib/json.pl get`), the verdict vocabulary (`verdicts.txt`) with its one reader, and `review-packet.sh`, which builds the one file a reviewer or security checker is given. The packet holds the criteria, the project's incident checklist from the merge base, the check output and the committed diff, never the author's own account, and a change cannot hide part of itself from it.
- validate.sh's perl syntax check also covers `method/scripts/`.
- Tests: 3 new test files with 128 test cases, and 1 new plant.

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
