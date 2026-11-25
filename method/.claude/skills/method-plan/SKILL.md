---
name: method-plan
description: Plans one task before it is built. Asks for what is missing, writes docs/tasks/<id>/plan.md (and expected.tsv for FULL) with known and assumed marked, and stops until the owner replies "approve <id>". For FULL, then writes the tests and sees them fail first.
# rules: M006 M021 M091 M125
argument-hint: <task id> <what the task is>
---
# Plan the task

You plan one task before anything of it is built. The arguments name the task and say what it is. When they give no id, choose one and say it.

## Before the owner's go

Read everything the task touches: the records, the code, the tests and the earlier plans. Until the owner approves the plan, change nothing but the task's own folder, `docs/tasks/<id>/`.

Mark each claim in the plan VERIFIED (you read it or ran it, and say where) or INFERRED (you assume it, and say why). Plan only what the request asks for. Where it leaves a gap, or asks for more than a requirement covers, write a question, not scope.

Say whether the task can be done as asked. When it cannot, or its requirements contradict each other, write "impossible or contradictory" and name the clash: that is an acceptable answer. Nothing in the plan makes a test pass by matching its inputs: no answers hard-coded to a test, no special cases for test inputs.

The tier is FULL unless the task fits LIGHT, as the method's rules set it out; when unsure, FULL. The project lists its high-risk paths as `HIGH_RISK_PATHS` lines in `.claude/method.conf`, and done-check reads main's list and the branch's together, so a branch can add a path but never remove one. Write one path per line with nothing after it: an entry, on main's list or the branch's, that names no path in the branch's files makes the change NOT READY, unless it is on main's list, has no space or `#`, and an earlier commit of main had that path (a path a merged change deleted, which done-check names so you can drop it from main's list). A change that touches a listed path, or a file under one, is judged FULL at the merge and needs three approving reviewers, so plan it as FULL.

## The task folder

done-check reads this format, so keep to it.
- One folder per task, `docs/tasks/<id>/`, added on the task's own branch (`git switch -c <id>` when you are on the main branch). The id is lowercase letters, digits and dashes, and no other task in `docs/tasks/` has it.
- One task per merge. Work meant for two merges is two tasks; one reply can approve both (`approve a, approve b`).
- `plan.md` is written for people. Its first lines after the title are these, each at the start of its line:
  - `Tier: FULL` or `Tier: LIGHT`;
  - `Paths: ` and the files and folders the change will touch, separated by commas;
  - `Approved: YYYY-MM-DD HH:MM "<the owner's reply>"`, added only once the owner has replied: the date and time as `date '+%Y-%m-%d %H:%M'` prints them when you add it, and the reply quoted exactly as typed, which holds `approve <id>` with this folder's id.
- `expected.tsv`, for FULL only, a regular file (not a link): the expected results, tab-separated, its first line the header `case`, `inputs`, `expected`, `source`. One row per case: a short name; the inputs as `name=value;name=value`; the expected result; and its source, the requirement, document or person (by role) outside the model that gives the value. For a high-risk change, the person with authority signs the expected results, and the source names them. A value you assumed has a source that starts `INFERRED:` and is a question in the plan until someone gives it.
- Once approved, the Tier line, the Paths line and expected.tsv stay as approved. A change to any of them is a new plan: change it, ask again, and replace the Approved line with one holding the new reply, date and time.

## A FULL plan

Before you write it, ask the owner for whatever is missing of these four, and guess none of them:
1. who it is for;
2. what is out of scope;
3. what done looks like that the owner can see;
4. what the owner expects to happen, as cases with their inputs and results.

`plan.md` then holds, after its three lines: what the task is and the requirement it serves, in plain words; the four points; what is known and what is assumed; whether it can be done; the acceptance criteria the reviewer will hold the change to; the cases of `expected.tsv`, in words; the risks, with each item a person must look at tagged [EYES] and each item a person with authority must sign tagged [AUTHORITY].

## A LIGHT plan

`plan.md` with `Tier: LIGHT`, its Paths line, and one to three acceptance lines. No `expected.tsv`.

## The approval

End the plan with this one question, and stop:

Reply `approve <id>` to approve this plan.

When the owner replies with `approve <id>` for this task's id, add the Approved line, quoting the reply, and commit the task folder in a commit of its own. A re-approval replaces the Approved line with the new reply, date and time, so the plan keeps one Approved line and the new one differs from the old. Any other reply is not an approval: change the plan as it asks, and ask the question again. A general "go" or "ok" does not approve a plan.

## FULL: the tests first

After the approval's commit, and before any product code:
1. Write the tests for the cases in `expected.tsv`, each named by its case.
2. Commit them, with no product code, in a commit of their own.
3. Launch the method-tester agent with the Agent tool and `run_in_background: false`, in one call, its prompt naming the task's `expected.tsv` and the tests to run. Wait for its report.
4. TESTS FAIL: the tests see the change missing; build it. TESTS PASS: stop, and tell the owner the tests do not test the change. TESTS NOT RUN: stop, and report why they could not run.

After a re-approval, when code already exists, make the failing run again on the task's branch, after the new Approved line's commit: one commit that sets the product's files back to their content before the code, leaving `plan.md` and `expected.tsv` as approved; the tester there, as in step 3; then a commit that puts the code back. done-check counts only a TESTS FAIL on a commit between the approval and the finished files, on the branch itself.
