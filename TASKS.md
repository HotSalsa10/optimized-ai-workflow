# TASKS

Current phase: Release 1, step 1.

## Step 1: repo skeleton, records, rule map, CI with planted defects

- [x] Records: SPEC, ROADMAP, TASKS, DECISIONS, RISKS, CHANGELOG, TESTS, docs/research/README.md
- [x] README stub, CLAUDE.md, AGENTS.md, LICENSE (MIT)
- [x] .gitattributes (LF pinned), .gitignore, this repo's .claude/settings.json
- [x] docs/rule-map.md with every rule and its home
- [x] Dev checks: line endings, bash 3.2 and BSD portability, secrets and personal data, rule map, workflow hygiene, perl syntax, shellcheck
- [x] Plant suite: each check red for its stated reason on planted defects, green on a clean copy and on look-alikes (34 cases)
- [x] CI: Linux on every change; Windows and macOS on release tags and on demand; actions pinned by commit; Dependabot for actions
- [x] Review round 1: REQUEST CHANGES, 4 blocking findings and 5 notes, all addressed in repair loop 1
- [ ] Review round 2 on the changes since round 1, commit with the verdict trailer, push
- [ ] CI green on GitHub ([CREDENTIAL], owner: GitHub Actions did not start a machine for the first run; the owner checks the repo's Actions settings and the account's billing)
- [ ] Windows and macOS CI run once by hand (needs the item above)

## Next

Step 2 starts only when the owner says so.
