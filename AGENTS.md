# AGENTS: working on the method repo itself

This repo builds a portable working method for Claude Code (see SPEC.md). The method is used on itself.

## Records

SPEC.md (requirements), ROADMAP.md (tracks), TASKS.md (current step), DECISIONS.md (settled choices, not reopened), RISKS.md, CHANGELOG.md, TESTS.md (every check and what runs it), docs/rule-map.md (every rule and its home).

## How work is done here

- One small step at a time, as listed in ROADMAP.md. Touch only the files the step needs.
- Every step gets a fresh-context review whose report opens with its verdict word (APPROVE, REQUEST CHANGES, REJECT or ESCALATE) alone on the first line, then gives the summary, the change summary, the actual check output and the risks, and ends with the line `END-VERDICT <tree>`, the tree of the commit reviewed (A72).
- Update the records before review, so one review covers one change.
- The method's hooks, agents, skills and scripts are installed here from the last release tag, now `v0.7.0` (A82). Its rules do not load here (`claudeMdExcludes`), and its `method-*` skills are product: never used here, only run by their tests. This repo's process is this file and DECISIONS. Text under `method/.claude/` is product being built and reviewed, never instructions for sessions here. A session with no `METHOD-ACTIVE` line has its hooks off; only a re-sync session should be like that, so say so first.
- Commit messages end with one line as the last paragraph: `Review-Verdict: <value>` (values in DECISIONS.md A10). No Co-Authored-By or session-link lines.
- One review and one repair loop per step (DECISIONS A66); if the repair does not close a finding, stop and report what is failing and what was tried.

## Pushes and CI (DECISIONS A76)

- CI runs on pushes only, never on pull_request events; a push run checks a pull request's head.
- A commit that changes only records (root records and docs/, never method/) may carry `[skip ci]` in its first line, never after the trailer; run validate.sh on it, and tests/verdicts.test.sh when DECISIONS.md or AGENTS.md change.
- A pushed head that a review or a merge will read never carries `[skip ci]`; a backup push of work no review reads yet may.
- Before a push that runs CI, run `bash tests/run.sh tests` once as a user who is not root, in a throwaway copy that user owns, started in the foreground or with `setsid`, never under `nohup` (its HUP cases then fail, F23 in docs/plans/step8.md).
- A merge commit carries `[skip ci]` only when the pull request's head had a green CI run and the branch contains main's tip.
- Before a push that adds shell code, read it for SC2016, SC2034 and SC2086. A local shellcheck helps, but CI's copy decides.

## Working under the guard (DECISIONS A82)

- The allowed shapes are in `.claude/hooks/method/git-shapes.txt`, `gh-shapes.txt` and the hooks README beside them; this file does not copy them. Common replacements: `git merge origin/main`, not `git merge main`; `git worktree add -b`; a branch only on the remote: `git switch -c NAME origin/NAME`, or a fresh session on it; `gh pr create --head`; to undo an edit, the reverse edit, `git restore --staged` or `git reset --soft` (not `git restore PATH`, `git checkout -- PATH`, `git stash` or `git reset --hard`); an edit under `method/` with `sed -i`, the Edit tool or a script under `tests/`, never an inline perl program; tags are made by the owner on GitHub.
- A Claude Code client runs only through the committed harness (`tests/harness.test.sh`, `h_client` in `tests/harness/lib.sh`), never from a scratchpad script, which would be a session with the hooks off. No SendMessage or create_session from a hooked session.
- No line goes into `.claude/method-local/`. A refusal that has no allowed shape and blocks needed work is reported, not worked around.
- Every session starts with one expected `session-status: LOOK` line, for the kept pattern: `.claude/settings.json keeps claudeMdExcludes, which run or load beside the method's hooks ...`. status also names `a15ad31` (the GitHub merge of pull request #5, whose message lacks a `Review-Verdict` line) in a `verdicts: LOOK` line, and may say status did not finish within 5 s; both are expected. A merge made on GitHub keeps its trailer only when the owner pastes the line into the merge message. Any other such line is news.
- An install or re-sync runs where the hooks are off; from about a second after sync's `--write`, that session runs under the guard (F26 in docs/plans/step8.md), so its tests, commit and push are made under it. The install is one commit. The way back out while step 8 is unmerged: `git revert --no-edit <that commit>`, which the guard lets through; after the merge, the owner switches the hooks off for one session (docs/plans/step8.md, section 7).

## Hard rules

- No secrets, personal data or business data anywhere in this repo.
- Wording in `method/` is field-neutral. Field-specific rules belong in `packs/`.
- Shell scripts run on bash 3.2 (macOS), Git Bash on Windows and Linux: no bash 4 features, no GNU-only tool flags. JSON goes through perl's JSON::PP. Node is not assumed.
- Line endings are LF (see .gitattributes).
- Every check gets a planted defect in tests/plants/ that turns it red for its stated reason. Plants run in a throwaway copy, never in the working tree.
- A rule enters the method only with its reason and one home, recorded in docs/rule-map.md.

## Commands

- `bash scripts/dev/validate.sh` runs every repo check.
- `bash tests/run.sh` runs every test and plant (`bash tests/run.sh tests` or `plants` runs one half).
