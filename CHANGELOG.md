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
- `status.sh`: one read-only report for any session: work not committed or not pushed (also in linked worktrees, inside submodules and in the other repositories listed in REPOS), commits on main without a valid verdict trailer, the project records, the Claude Code version against the floor, CLAUDE_CODE_EFFORT_LEVEL, perl's modules and CI. It says PASS, LOOK or SKIPPED and exits 1 when something needs a look.
- `.claude/method.conf` settings (PRODUCT_PATHS, LOCAL_ONLY, REPOS, VERDICTS_FROM) with one reader, `lib/conf.pl`, and `REQUIRES` with the Claude Code floor.
- The commit trailer check, `lib/verdicts.pl check-trailer`, used by status.
- Shared helpers `lib/git.pl` (every git call, with the settings that could change what git shows turned off) and `lib/esc.pl` (the one line escaper), taken out of the review packet with its output unchanged. Later in the step the escaper also learned to show the CI runner's command form `##[` as `#\x23[`, so the packet shows it that way too and says so in its header, and every git call refuses to use a folder laid out like a repository.
- Tests: 3 new test files and 25 more trailer cases, 364 test cases in all.

### Added (step 4)

- `done-check.sh --ready`: says whether a change is ready to merge, from the commit, the files on disk, main, the run-checks log and the head commit's verdict line, so nobody has to read test output. Six conditions each need positive evidence: the files are the commit; the branch has main's tip; the newest run of these files passed; no check is left that runs only in the other place; the verdict line approves; and any move of VERDICTS_FROM names the commits it accepts. READY names what it rests on (a local log and a typed verdict line, until steps 5 and 9); NOT READY says what to do next.
- `lib/tree.pl`, taken out of the review packet with its output unchanged: one rule for "the files on disk are the commit", now used by the packet, run-checks and done-check.
- The verdict vocabulary gains a `ready` kind: only `approve` makes a change ready (DECISIONS A33).
- Tests: 1 new test file and new cases in four others, 890 test cases in all.

### Added (step 4b)

- `mutate-changed.sh --list`: plans the mutants for the lines this branch adds (step 4b.2; running them comes in 4b.3): which changed lines get which small text change, in an order that reaches every changed file first, with the reasons files are skipped. It writes nothing and runs no check, and nothing that deletes or moves files gets a mutant. New settings MUTATE_PATHS and MUTATION_CHECKS (DECISIONS A40).
- `Tree::added_lines`: the lines a file adds, from the same fixed diff the review packet uses; `Esc::utf8_ok`: the escaper's UTF-8 rule, shared.
- Tests: 1 new test file (mutate plan), 3 config cases and 1 packet case; 939 test cases in all.

### Changed (step 4b)

- The review packet finds moved files up to git's default limit whatever a local diff.renameLimit says (a low one turned moves into deletes and adds).
- run-checks' way of running one project check is split into parts (whether it applies here, and how its end is judged) that mutate-changed.sh will share; internal, with run-checks' output byte for byte the same.

### Changed (step 4)

- run-checks compares the bytes of every tracked file with the commit at its start and in tree-unchanged, so a CR that core.autocrlf hides from git status is a change; a CRLF or $Id$ that the commit's own .gitattributes asks for is not, on Linux too (DECISIONS A36).
- Main is no longer taken from an origin/HEAD that names the task branch itself. It is read from origin, or from the only remote (one with a URL) when none is named origin; a local main or master counts only when there is no remote and no remote-tracking branch at all, since git fetch never moves it (status too). done-check also needs the remote's fetch settings to name main's ref. git never fetches a missing object while the method reads (git 2.44 and later).
- The review packet now accepts a CRLF or $Id$ that the commit's own .gitattributes asks for (on Linux too), and refuses four cases it accepted before: Git LFS content whose path the commit does not mark for LFS, a committed symlink written as a plain file (core.symlinks=false), a file over 64 MB that differs only by CRs, and a file missing a CR that the commit's eol=crlf rule asks for once it is added (git status then shows nothing; the packet names it and how to fix it).
- status turns off a filter set only inside a submodule (also one whose .git points at another folder), as run-checks and done-check do.
- Where the working tree's file system tells case apart, every git call made through Git::run pins core.ignoreCase=false, so a setting copied from a Mac or Windows cannot hide an untracked file whose name differs from a tracked one only by case; where the file system folds case, git's own setting stays.
- The mutation wrapper is split out of step 4 into step 4b, and rule M044's second half becomes M122 (DECISIONS A39).

### Changed (step 3)

- The secret scan moved into the method (`method/scripts/method/lib/secrets.pl`), lists the tracked files itself, and runs about 7 times faster with the same findings. Its mask (`--mask`) now covers the whole of a phone number or IBAN that starts like a shorter one (it used to leave the last digits), and a key, phone number or IBAN right after a terminal colour code, or right after an escape written as text, as a test runner prints a string (`\x1b[1m`, `\u001b[31m`, `\n`). A key or token is masked also when it is glued to a word. The scan also finds a key after such an escape in a file, and an armored PGP private key. It reads the staged copy of a file whenever its content is not the file on disk (it used to ask git, which trusts its stat cache), reports a find in both copies once, and never writes the index. Its `--staged FILE...` mode, which nothing used, is gone.
- The review packet names in its header every tracked file that differs from the commit only by CRs before line ends (a checkout that writes CRLF, or an edit that only adds CRs, which turns `set -e` off in a shell script).

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
