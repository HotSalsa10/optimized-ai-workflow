# TASKS

Current phase: Release 1, step 1b (security fixes). Step 1 is closed except the owner's CI item.

## Step 1: repo skeleton, records, rule map, CI with planted defects

- [x] Records: SPEC, ROADMAP, TASKS, DECISIONS, RISKS, CHANGELOG, TESTS, docs/research/README.md
- [x] README stub, CLAUDE.md, AGENTS.md, LICENSE (MIT)
- [x] .gitattributes (LF pinned), .gitignore, this repo's .claude/settings.json
- [x] docs/rule-map.md with every rule and its home
- [x] Dev checks: line endings, bash 3.2 and BSD portability, secrets and personal data, rule map, workflow hygiene, perl syntax, shellcheck
- [x] Plant suite: each check red for its stated reason on planted defects, green on a clean copy and on look-alikes (46 cases, including a 102-line portability corpus)
- [x] CI: Linux on every change; Windows and macOS on release tags and on demand; actions pinned by commit; Dependabot for actions
- [x] Review round 1: REQUEST CHANGES, 4 blocking findings and 5 notes, all addressed in repair loop 1
- [x] Review round 2: REQUEST CHANGES, 4 blocking findings (portability regressions, a one-line-only $( ) rule, a macOS-only plant failure, missed personal emails) and 5 notes, all addressed in repair loop 2
- [x] Review round 3 (the last under the 3-round cap): ESCALATE. Every round-2 finding fixed; 3 new regressions in the portability lint (commands inside arithmetic, a case inside a one-line $( ), a false alarm on xargs -0 rm -rf). The owner chose one last repair loop.
- [x] Repair loop 3 (the last): the 3 regressions and the nearby false alarms fixed, records corrected. Not reviewed by a fresh reviewer (3-round cap); checked instead by the plant suite, 27 planted breaks of the new guards (all caught), deleting each portability rule in turn (all caught) and 103 third-party scripts (no change in findings)
- [x] Security check (DECISIONS A7): 4 finders, each finding checked by an independent agent that tried to refute it. 23 confirmed (2 medium, 15 low, 6 lowered to info; 2 pairs are the same issue found twice), 2 refuted, 11 ideas. No secret found in the files or in any commit; the only owner details are the GitHub name in LICENSE, the commit author lines and plan details in the records, which is fine while the repo is private. All 3 repair loops were used, so the owner chose: correct the records now, fix the rest in step 1b. Records corrected: TESTS.md (secret-scan coverage, what the scan reads), RISKS.md 3, 4 and 10, ROADMAP.md.
- [ ] CI green on GitHub ([CREDENTIAL], owner: the account's Actions minutes are used up, so GitHub starts no machine; waits for the minutes to renew)
- [ ] Windows and macOS CI run once by hand (needs the item above)

## Step 1b: fixes from the step 1 security check

Each item that changes a check gets a planted defect that turns it red; config-only items get a test. Severity is the one the verifying agent gave.

- [ ] (medium) A file name holding a newline and the text "BAD 0" makes secrets, portability and workflows print PASS and exit 0. Treat a count that is not a plain number as a failure, or use exit codes, and escape file names in all output.
- [ ] (low) File names reach tools as options: validate.sh's perl -c can run code from a file name, and a file name can switch shellcheck off. Pass names after `--` or with a `./` prefix.
- [ ] (low) validate.sh prints a key in full through shellcheck's source lines, perl -c errors and allowlist errors, which the secret scan itself masks. Mask or drop those lines.
- [ ] (low) mask() shows the first 6 characters, which is most of a short password and part of an email. Show less.
- [ ] (low) Control characters, and `::` at the start of a line, in file names or content reach the terminal and the CI log, where the runner reads `::` lines as workflow commands. Escape them.
- [ ] (low) scan-allow.txt: one entry hides that text in every file, the allowlist stores the secret itself, and allowed hits are not reported. Allow by file and hash, and print how many hits were allowed.
- [ ] (low) The secret scan misses keys in a UTF-16 file followed by ASCII text, and in files with CR-only line ends.
- [ ] (low) The secret scan reads the working tree, not the index, so a staged secret passes before commit. Read the index; fix the scan-secrets.sh header wording.
- [ ] (low) .gitignore ignores .claude/settings.local.json only at the root, and no common secret file names.
- [ ] (low) The line-endings check skips a CRLF file that also holds a lone CR or a NUL, and fails correct .bat and .cmd files with non-ASCII names.
- [ ] (low) The workflow lint reads one line at a time, so a quoted `uses` key, a flow mapping, a `uses` value on the next line, a docker:// tag, an unpinned action inside a local composite action, write-all on the line after `permissions:`, and a flow-style job with no timeout all pass. Make it fail closed and scan action.yml files.
- [ ] (low) CI: a manual run and a push run on the same branch share a concurrency group and cancel each other.
- [ ] (info) The plants ignore a failed make_sandbox, and an empty sandbox path would run plant commands in the working tree. Stop when make_sandbox fails; make it fail when a file is not copied.

## Fixed elsewhere

- (medium) The secret scan misses many common credential forms (listed in TESTS.md Known limits): closed, with a second scanner added, before the owner's files are imported (ROADMAP Track 3).
- (low) Nothing checks the Claude Code settings or the agent instruction files: step 5 (settings fragment and hooks).
- (info) Commit messages and session links are never scanned, and nothing scans before a push while CI is down: step 5 hooks.
- (info) The SHA under a version comment is not checked against that version's tag: step 9 (project CI templates).
- (info) The rule map can name itself through other path spellings: TESTS.md Known limits, fix when the rule-map check is next touched.

## Not acted on

- Refuted by the verifying agent: the checkout leaves the read-only CI token on disk; the scans follow tracked symlinks.
- Accepted: CI runs twice when a branch has an open pull request (cost only); crafted lines thousands of characters long slow the perl helpers (CI's 15-minute timeout caps it); anyone who can push can start the Windows and macOS runs with a v* tag (only the owner can push); runner images are not pinned.
- Kept as notes for later steps: owner details in records and history are fine while the repo is private (review before publishing anything); project settings apply only in single-repo sessions without managed settings, and the Opus-only list can turn a fallback re-run into a refusal (both for step 5 and the cloud acceptance test in step 9); the planned method/.claude/ files will load as live skills in this repo's own sessions (step 6 design).

## Follow-ups (not blocking)

- Known misses listed in TESTS.md Known limits, to fix when a step touches those checks.
- The portability lint flags every $( ) that runs onto the next line; narrow it if it gets in the way.

## Next

Step 2 starts only when the owner says so.
