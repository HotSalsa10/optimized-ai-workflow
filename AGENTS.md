# AGENTS: working on the method repo itself

This repo builds a portable working method for Claude Code (see SPEC.md). The method is used on itself.

## Records

SPEC.md (requirements), ROADMAP.md (tracks), TASKS.md (current step), DECISIONS.md (settled choices, not reopened), RISKS.md, CHANGELOG.md, TESTS.md (every check and what runs it), docs/rule-map.md (every rule and its home).

## How work is done here

- One small step at a time, as listed in ROADMAP.md. Touch only the files the step needs.
- Every step gets a fresh-context review that returns APPROVE, REQUEST CHANGES, REJECT or ESCALATE, and a five-part report: summary, change summary, actual check output, risks, verdict.
- Update the records before review, so one review covers one change.
- Commit messages end with one line as the last paragraph: `Review-Verdict: <value>` (values in DECISIONS.md A10). No Co-Authored-By or session-link lines.
- Stop after 3 repair loops and report what is failing and what was tried.

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
