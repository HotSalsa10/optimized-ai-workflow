# TASKS

Current phase: Release 1, step 1.

## Step 1: repo skeleton, records, rule map, CI with planted defects

- [x] Records: SPEC, ROADMAP, TASKS, DECISIONS, RISKS, CHANGELOG, TESTS
- [x] README stub, CLAUDE.md, AGENTS.md, LICENSE (MIT)
- [x] .gitattributes (LF pinned), .gitignore, this repo's .claude/settings.json
- [x] docs/rule-map.md with every rule and its home
- [x] Dev checks: line endings, bash 3.2 and BSD portability, secret and personal-data scan, rule map, shellcheck
- [x] Plant suite: each check goes red for its stated reason on a planted defect, and stays green on a clean copy
- [x] CI: Linux on every change; Windows and macOS on release tags and on demand; actions pinned by commit; Dependabot for actions
- [ ] Fresh-context review, five-part report, commit, push

## Next

Step 2: JSON helper, verdict vocabulary, review packet.
