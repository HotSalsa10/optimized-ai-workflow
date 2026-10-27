# TASKS

Current phase: Release 1, step 1.

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
- [ ] Security check of step 1 (DECISIONS A7), then the closing commit with the verdict trailer, push
- [ ] CI green on GitHub ([CREDENTIAL], owner: the account's Actions minutes are used up, so GitHub starts no machine; waits for the minutes to renew)
- [ ] Windows and macOS CI run once by hand (needs the item above)

## Follow-ups (not blocking step 1)

- Known misses listed in TESTS.md Known limits, to fix when a step touches those checks.
- The portability lint flags every $( ) that runs onto the next line; narrow it if it gets in the way.

## Next

Step 2 starts only when the owner says so.
