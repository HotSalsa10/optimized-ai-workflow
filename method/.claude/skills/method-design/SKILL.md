---
name: method-design
description: Starts a new project or a big feature with a design. The method-architect agent drafts it from the owner's brief, the main session writes it into a LIGHT task folder, method-reviewer checks it against the brief, and the owner sees the card and the verdict. The walking skeleton comes first.
# rules: M099
argument-hint: <task id> <the brief>
---
# Design first

A new project or a big feature starts here, before any plan to build it. The arguments name the task and give the brief: what is wanted, for whom, and the limits that hold, such as time, cost and what has to keep working. When the brief lacks one of these, ask the owner for it first. Work on the task's own branch (`git switch -c <id>` when you are on the main branch).

Five steps, in order:

1. **The architect drafts.** Launch the method-architect agent with the Agent tool and `run_in_background: false`. Its prompt gives the project's context, then the brief as the owner wrote it, last. It returns a design with a card for the owner, and writes nothing.
2. **Write it and commit.** Write the design, as it came back, to `docs/tasks/<id>/design.md`. Write the task's `docs/tasks/<id>/plan.md` in the form "The task folder" in `.claude/skills/method-plan/SKILL.md` sets out: its first lines after the title, each at the start of its line, are `Tier: LIGHT` and `Paths: docs/tasks/<id>/`, and the brief follows as its acceptance lines. Commit both in one commit.
3. **The review.** Make the folder with `mkdir -p .method/local`, then build the review packet with `bash scripts/method/review-packet.sh --base origin/main --criteria docs/tasks/<id>/plan.md > .method/local/packet.txt`, each in a Bash call of its own (use the branch the change will merge into, if it is not main). Launch the method-reviewer agent with the Agent tool and `run_in_background: false`, its prompt naming the packet and saying that the brief is the criteria. When it asks for changes, fix the design (asking the architect again when the approach has to change), commit, build the packet again as above (a packet names the tree it was built for, and a review of an old one does not count), and review again; after three rounds, stop and report.
4. **The owner sees it.** Show the owner the card and the reviewer's word with its findings, then end with this one question, and stop:

   Reply `approve <id>` to approve this plan.

   On that reply, add the Approved line to `plan.md`, after the Paths line: `Approved: <date> "<the owner's reply>"`, the date as YYYY-MM-DD and the reply quoted exactly as typed. Then commit. /method-finish then takes the task to the merge.
5. **The walking skeleton comes first.** Once the design is merged, the first task is its walking skeleton: plan it with /method-plan, build it, and let the tasks after it grow it.
