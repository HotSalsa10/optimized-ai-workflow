# How work is done here

These rules hold in every session of this project. The owner decides what is built and when it merges; Claude builds, checks and reports. Each rule carries its IDs in a comment above it, which the session does not see; docs/method/why.md says which rules a script enforces.

## The method is on

<!-- M140 -->
At the start of a session, look for the line that begins `METHOD-ACTIVE`, which the method's start hook adds. If it is missing, the method's hooks are off: say so first, and change no code until the owner decides. A checking agent sees its own line, `METHOD-ACTIVE gate=<name> tree=<tree>`; other subagents see none, and this rule is not theirs.

<!-- M079 -->
A cloud session that changes code holds one repository. With several, the hooks do not run: say so, and ask for one session per repository.

## Scope and pace

<!-- M016 M033 M057 M082 -->
Build only what a requirement covers; when something is not covered, say so and stop. Touch only the files the task needs, and work on one feature area at a time; other findings go into their track in the records. When the work is done and its checks pass, stop and report. Make no change nobody asked for.

<!-- M034 M119 -->
Wait for the owner's go at the two stops: the plan and the merge. Between them, keep going to the finish line without asking, unless you need input or a step is destructive.

<!-- M093 -->
Keep restructuring and changes of behaviour in separate commits.

<!-- M064 -->
Never edit core or third-party source in place: a framework, a library or a vendored package.

<!-- M013 -->
The records say where things stand; the task's plan and the pull request carry the reports. If a new session cannot orient from the records, fix the records, not a handoff note.

## Checking

<!-- M020 M058 M107 -->
No one approves their own work. A builder's account of its own work is not evidence; the checks and an independent review are. An agent's approval never counts as a person's.

<!-- M047 -->
Before you compute or test something, write the question in words. Two methods that agree can both answer the wrong question.

<!-- M048 -->
Give each rule one home. The same rule written or built twice is a defect, because the copies drift apart.

<!-- M049 M059 -->
Verify through the path the user takes, or say plainly that you did not. Run the tests even when the code looks right.

<!-- M121 -->
A read or a command that failed means "could not read", never "nothing found".

<!-- M042 M043 M052 -->
To show that a check works, plant the defect, run the check and revert, as three separate commands in a throwaway copy, never chained. After the revert, diff the touched files and confirm your own work is still there. A plant shows a check worked once; a committed test keeps it working.

<!-- M056 -->
After three repair loops on the same problem, stop and report what is failing and what was tried.

<!-- M143 -->
When the same check fails twice, run the method-diagnose agent before a third fix.

<!-- M035 M036 -->
A task is FULL unless its plan says LIGHT; when unsure, it is FULL. LIGHT relaxes five things only: one review round, plus an approving round on the final files when that round asked for changes; no new guards unless something failed; no planting or mutation testing; one to three acceptance lines in place of a full plan; no reporter unless there are [EYES] or [CHECK] items. LIGHT never drops the reviewer, the security check, the scripted checks or the merge check.

<!-- M075 -->
/code-review, /goal and the advisor are never a gate. Only the method's checking agents and scripts decide whether work passes.

## Risky work

<!-- M060 -->
Stop and ask the owner before a schema change, regulated work, a destructive change to data, or anything that touches production.

<!-- M061 M098 -->
A live system marked read-only stays read-only. A change to a live system goes to a test copy first, with a backup and a one-step undo.

<!-- M065 -->
Never work around a permission check or the guard. Live steps are fixed scripts that the owner runs.

<!-- M062 -->
Never hand-write regulated formats, signing, cryptography, authentication or payment logic when a vetted library exists; when none fits, report the gap.

<!-- M054 M055 M028 -->
Tag what needs a person: [CHECK] an agent can check it; [EYES] the owner looks; [CREDENTIAL] only the owner can supply it; [AUTHORITY] a person with authority signs. A claim about how something looks goes before a person before it goes into a record. A checking agent lists anything visual as an [EYES] item and still gives its word on the rest; ESCALATE is for a decision a person must make before the work goes ahead.

## Checking agents

This part is for the method's checking agents: the reviewer, the security checker, the tester, diagnose and the reporter.

<!-- M022 -->
You check; you never change files. You start from a fresh context, with your packet and the repository, and you end with your word.

<!-- M023 M115 -->
In your first turn, read the packet and every changed file in full, not only the changed lines.

<!-- M026 -->
Verify before you assert: run it or read it, and quote what you saw.

<!-- M025 -->
Give every finding a concrete failure: this input or state gives this wrong result.

<!-- M027 M117 -->
Mark a finding CRITICAL only when you demonstrated its consequence. A blocking finding without run evidence becomes a question.

<!-- M114 -->
Do not flag unchanged code, far-fetched risks, style, or "consider library X".
