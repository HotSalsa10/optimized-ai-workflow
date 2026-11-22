# What enforces the method

The method's rules are text, and Claude can fail to follow one. This page says honestly which rules a hook or a script enforces, which are only partly checked, and which are only written down (M067). Each row names its rule IDs; the rule map in the method's own repository, not in this project, gives each rule's reason and its one home.

## Your part

- A person is accountable for every change that ships (M109). Claude never merges: your merge on GitHub is the approval for the exact version merged, and the only lock outside the session.
- People who read code add a review layer; they never replace the reviewer agents (M088). Look at intent, business rules, design and risky paths first, and at the agents' findings after: people shown an AI review mostly check what it flagged.
- Give the whole task in one message, with the finish line and the stops (M119). Claude then keeps going without asking, unless it needs input or a step is destructive; its half of the rule is in `.claude/rules/method/method.md`.

## Enforced by a hook

The hooks run in local sessions and in cloud sessions with one repository. Where they do not run, the session's first message has no `METHOD-ACTIVE` line (`.claude/hooks/method/README.md`, "Where the hooks do not run").

| Rule | What it stops | Where |
|---|---|---|
| G0 cannot-tell, G1 perl-missing (M128) | A command the guard cannot read that names something it watches; input it cannot parse; every call when perl is missing | guard.sh |
| G2 powershell (M129) | Every PowerShell call | guard.sh |
| G3 git-shapes (M130) | A git command not on the list of allowed shapes, such as a push to main | guard.sh, `git-shapes.txt` |
| G4 outside (M131) | gh, MCP tools, curl or wget to GitHub, another Claude, SendMessage and remote agents, unless on a list | guard.sh, `gh-shapes.txt`, `mcp-tools.txt` |
| G6 protected (M132) | A write to the method's files, its settings, or git's config and hooks | guard.sh |
| G8 mutant-commit (M133) | A commit while a mutation run, or what one left behind, is in the repository | guard.sh |
| G12 effort (M134) | Nothing: a warning at the first call of a session below xhigh | guard.sh |
| G16 settings-change (M136) | A settings change mid-session that switches off or weakens the hooks | guard.sh |
| G17 skill-and-agent-hooks (M137) | A skill or agent that declares its own hooks | guard.sh |
| The start line | Nothing: a notice. `METHOD-ACTIVE` and status's LOOK lines show the method's state at every start where the hooks run; whether Claude then stops is not checked (below) | session-status.sh |
| Receipts (M053, M078, M106, M116) | A review that does not count being taken for one: a checking agent's report cut off, made on files that changed, run below its effort, off the allowed models or from another definition gets an INVALID or INCOMPLETE receipt, which done-check does not count. Each receipt also records the base of the review packet its agent read | gate-receipt.sh |
| Settings (M076, M104, M138, M139) | The advisor, auto memory and skill shell lines are off; merge tools and tools that start other sessions are denied, also with the hooks off | `.claude/settings.json` |

## Enforced by a script

| Rule | What it checks | Where |
|---|---|---|
| M001, M003, M077 | Where things stand: uncommitted and unpushed work, commits missing a verdict, records, versions, effort | `scripts/method/status.sh` |
| M002, M050, M051, M066 | Every check runs and examines something; a fresh clone works; no secrets; the log is kept | `scripts/method/run-checks.sh` |
| M032, M038, M085, M112, M113 | The review packet is the reviewer's whole input, without the author's account or noise | `scripts/method/review-packet.sh` |
| M008, M089, M108 | Ready to merge: the files are the commit, main is merged in, the checks passed, and the verdict line is the one the receipts give | `scripts/method/done-check.sh` |
| M044 | Mutation testing breaks the changed code on purpose | `scripts/method/mutate-changed.sh` |
| M039 | Every script reads the verdict words from one file | `scripts/method/verdicts.txt` |
| M072 | No hook log grows forever or stores secrets: each is cut to its newest lines, and its lines hold only fields of a fixed shape, never a command, a path or a message | `scripts/method/lib/log.pl` |
| M009, M144, M146 | The task's plan with its approval; VALID approving receipts of the reviewer and the security checker for the exact files, reviewed from the merge base or chained back to it; no other word from either on those files; at most three review rounds since the approval; every gate's word on the branch listed | `scripts/method/done-check.sh` |
| M145, M146, M147 (step 6b) | The locked expected results and tier, a test run seen failing first and passing at the end, the reporter, three approving reviewers on high-risk paths | `scripts/method/done-check.sh` |
| M126 (step 6b) | Every number in a report is in a log; "What the checks would miss" is not missing or empty | `scripts/method/report-check.sh` |
| CI | The project's checks run on every change, outside the session | the project's CI (step 9) |

## Partly enforced

| Rule | What is checked | What is not |
|---|---|---|
| M140, the start line | The hook adds `METHOD-ACTIVE` at every start | Whether Claude stops when it is missing |
| Receipts | A gate's report has its first and last lines and was made the right way on the right files | Whether the verdict is right; a review cut off before its first word neither blocks nor counts, so its gate is run again |
| The plan's approval (M144) | The Approved line's form, and that it quotes `approve <task>` for its own task | That you typed it |
| The tier (M147, step 6b) | A change on a high-risk path is judged FULL | Whether a change off those paths is really LIGHT |
| Seen failing first (M145, step 6b) | A tester run said TESTS FAIL after the approval and before the code | Which tests failed, or why: the reviewer checks the tests (M090) |
| The report check (M126, step 6b) | The reporter refuses a report whose check did not pass | A LIGHT change without a reporter: then only the skill runs the check |
| Predictions before a FULL merge (M124) | Nothing: done-check cannot see that you predicted | All of it |
| High-risk work: Deep review | Three approving reviewers (step 6b) | The rest of Deep review: sign-off of expected results, a test copy, an undo plan, a human expert |
| LIGHT's reporter for [EYES] or [CHECK] items | `/method-finish` runs it then (step 6b) | done-check does not require it |
| M075 | `/code-review` is kept to you by the settings | That nothing else is treated as a gate |

## Written down only

These rules are text the model reads. A review can notice a broken one; nothing stops it.

| Where | Rules |
|---|---|
| `.claude/rules/method/method.md`, loaded in every session | M079, M016, M033, M057, M082, M034, M119, M093, M064, M013; M020, M058, M107, M047, M048, M049, M059, M121, M042, M043, M052, M056, M143, M035, M036; M060, M061, M098, M065, M062, M054, M055, M028; for checking agents M022, M023, M115, M026, M025, M027, M117, M114 |
| `.claude/rules/method/owner.md`, loaded in every session | M012, M037, M123, M074, M068, M071, M105 |
| `.claude/hooks/method/README.md` | M073: each hook documented with what it stops, what it costs and how it was seen to fire |
| The checking agents, `.claude/agents/method/` (step 6) | reviewer M024, M083, M084, M086, M090, M102; security checker M030; tester M029; diagnose M142; reporter M031, M046, M069, M092, M124 |
| The architect (step 6) | M141 |
| The skills you type (step 6 and 6b) | `/method-start` M004, M005, M127; `/method-plan` M006, M021, M091, M125; `/method-design` M099; `/method-finish` M007, M011, M070, M087 |
