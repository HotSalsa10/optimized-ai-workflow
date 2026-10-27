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

- [x] (medium) A file name holding a newline and the text "BAD 0" makes secrets, portability and workflows print PASS and exit 0. Treat a count that is not a plain number as a failure, or use exit codes, and escape file names in all output.
- [x] (low) File names reach tools as options: validate.sh's perl -c can run code from a file name, and a file name can switch shellcheck off. Pass names after `--` or with a `./` prefix.
- [x] (low) validate.sh prints a key in full through shellcheck's source lines, perl -c errors and allowlist errors, which the secret scan itself masks. Mask or drop those lines.
- [x] (low) mask() shows the first 6 characters, which is most of a short password and part of an email. Show less.
- [x] (low) Control characters, and `::` at the start of a line, in file names or content reach the terminal and the CI log, where the runner reads `::` lines as workflow commands. Escape them.
- [x] (low) scan-allow.txt: one entry hides that text in every file, the allowlist stores the secret itself, and allowed hits are not reported. Allow by file and hash, and print how many hits were allowed.
- [x] (low) The secret scan misses keys in a UTF-16 file followed by ASCII text, and in files with CR-only line ends.
- [x] (low) The secret scan reads the working tree, not the index, so a staged secret passes before commit. Read the index; fix the scan-secrets.sh header wording.
- [x] (low) .gitignore ignores .claude/settings.local.json only at the root, and no common secret file names.
- [x] (low) The line-endings check skips a CRLF file that also holds a lone CR or a NUL, and fails correct .bat and .cmd files with non-ASCII names.
- [x] (low) The workflow lint reads one line at a time, so a quoted `uses` key, a flow mapping, a `uses` value on the next line, a docker:// tag, an unpinned action inside a local composite action, write-all on the line after `permissions:`, and a flow-style job with no timeout all pass. Make it fail closed and scan action.yml files.
- [x] (low) CI: a manual run and a push run on the same branch share a concurrency group and cancel each other.
- [x] (info) The plants ignore a failed make_sandbox, and an empty sandbox path would run plant commands in the working tree. Stop when make_sandbox fails; make it fail when a file is not copied.
- [x] Checked (first pass): 81 test cases in 3 files passed.
- [x] Records updated: TESTS.md, CHANGELOG.md, this file.
- [x] Found while working: the first draft of tests/lib.test.sh loaded its helpers from a wrong path, kept running, and ran its setup in the real repo (a local commit and a test git identity; nothing pushed). Undone at once. Every test file now stops if tests/lib.sh does not load, and new tests run in a throwaway copy first.
- [x] Review round 1 (blind reviewer and security checker in parallel; each blocking or medium finding re-checked by an independent agent that tried to refute it): REQUEST CHANGES. 7 confirmed: a block scalar on a step's dash line hid an unpinned action (medium); a byte-order mark with no NUL byte hid a file from the secret scan; the line-endings check read lone-CR files from the working tree only; a NUL-free file marked binary failed it; the workflow lint passed explicit and escaped keys; it failed `permissions: {}` and quoted port lists; and the planted-break claim was false (5 removals went unnoticed). 20 notes.
- [x] Repair loop 1 (of 3): all 7 fixed, plus these notes: `::` after spaces and `##[` broken up in all output, UTF-8 C1 controls escaped, file names scanned as text, the mask filter masks phone numbers and IBANs and is not fooled by an escaped character, git's warnings discarded, assume-unchanged and skip-worktree files read, a names check in validate.sh, shellcheck ignores `.shellcheckrc`, sandboxes refuse outward symlinks and compare real paths, CI checkout keeps no token, more credential files ignored, a test for the CI settings. Checked: 105 test cases in 4 files pass; the planted-break runs are summed up in TESTS.md (71 removals, 64 caught, 7 explained one by one).
- [x] Found while working: two planted-break batches were first "caught" by the wrong test (a sandbox count that other parallel runs changed; a phone number left as plain text in a plant). Both causes fixed and both batches re-run; the checks now run before every batch.
- [x] Review round 2 (same set-up): REQUEST CHANGES. 10 confirmed. 3 medium: a symlink target starting with "-" let a sandbox plant write outside the sandbox; a list holding `"uses":x` and YAML line breaks other than LF hid lines from the workflow lint. 7 low: tags and anchors on keys, a C1 name dropped from shellcheck without a message, a CRLF working copy over a binary staged copy, two .gitignore entries that worked only at the root, and an overstated planted-break record. 13 notes.
- [x] Repair loop 2 (of 3): all 10 fixed, and the workflow lint rewritten to accept only plain YAML line shapes and report every other line, which closes that whole class instead of adding forms one by one. Also: file names always shown masked, names of staged-only files scanned, the mask filter masks the whole line before the pieces, `::` after Unicode spaces broken up, git's warnings tested by a plant, the index and working copy judged separately for line endings and files marked binary skipped, pathspec and SHELLCHECK_OPTS settings ignored, and escaping layers that could never fire removed. Checked: 115 test cases in 4 files pass; 87 planted breaks for step 1b, 82 caught and 5 that cannot be caught, each named in TESTS.md.
- [ ] Review round 3 (the last under the cap) on the changes since round 2; closing commit with the verdict trailer, push

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
