# What enforces the method

The method's rules are text, and Claude can fail to follow one. This page says honestly which rules a hook or a script enforces, which are only partly checked, and which are only written down (M067). Each row names its rule IDs; the rule map in the method's own repository, not in this project, gives each rule's reason and its one home.

## Your part

- A person is accountable for every change that ships (M109). Claude never merges: your merge on GitHub is the approval for the exact version merged, and the only lock outside the session.
- People who read code add a review layer; they never replace the reviewer agents (M088). Look at intent, business rules, design and risky paths first, and at the agents' findings after: people shown an AI review mostly check what it flagged.
- If Claude Code asks whether to turn on hot reloading for mods, answer "Not now". A mod runs inside Claude Code, outside the method's checks, and method work uses none (M105). The guard keeps Claude from writing one; one you install or load yourself (/plugin, --plugin-dir) it cannot stop.
- Give the whole task in one message, with the finish line and the stops (M119). Claude then keeps going without asking, unless it needs input or a step is destructive; its half of the rule is in `.claude/rules/method/method.md`.

## Enforced by a hook

The hooks run in local sessions and in cloud sessions with one repository. Where they do not run, the session's first message has no `METHOD-ACTIVE` line (`.claude/hooks/method/README.md`, "Where the hooks do not run").

| Rule | What it stops | Where |
|---|---|---|
| G0 cannot-tell, G1 perl-missing (M128) | A command the guard cannot read that names something it watches; input it cannot parse; every call when perl is missing | guard.sh |
| G2 powershell (M129) | Every PowerShell call | guard.sh |
| G3 git-shapes (M130) | A git command not on the list of allowed shapes, such as a push to main | guard.sh, `git-shapes.txt` |
| G4 outside (M131) | gh, MCP tools, curl or wget to GitHub, another Claude, SendMessage and remote agents, unless on a list | guard.sh, `gh-shapes.txt`, `mcp-tools.txt` |
| G6 protected (M132) | A write to the method's files and skills (any skill named `method-`), its settings, git's config and hooks, or the folders Claude Code loads mods and plugins from (`~/.claude/dev-mods/`, `~/.claude/plugins/`) | guard.sh |
| G8 mutant-commit (M133) | A commit while a mutation run, or what one left behind, is in the repository | guard.sh |
| G12 effort (M134) | Nothing: a warning at the first call of a session below the effort your profile sets (xhigh for Best results, medium for Balanced and Budget; xhigh with no lock) | guard.sh |
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
| M010 | The method changes only through its release's sync: the built-in `method-files` check fails when a file under the method's folders is changed, missing or not in `scripts/method/method.lock`, or when the method's settings in `.claude/settings.json` (its keys, hooks and deny entries) are not the release's; your own deny entries, hooks, other keys and skills are left alone. The method's keys are compared whole, `env` and `skillOverrides` among them, so an env variable or skill override of your own in `.claude/settings.json` turns the check red; one in `.claude/settings.local.json` is not compared, and session-status names it | `scripts/method/run-checks.sh` |
| M155 | The method is installed and updated only by its release's sync, which replaces no method file changed since `method.lock`, removes no file you added to a method folder, and writes nothing until its whole plan holds; on a first install it refuses a method key your settings set to another value and, unless you name each with `--keep`, a hook of your own before each tool call, on permission requests, on settings changes or at the start, `claudeMdExcludes`, enabled plugins and the settings that run a program | the release's `scripts/release/sync.sh`, run from the method's repository; it is not copied into the project |
| M100, M156 | Setup keeps the floor: `/method-setup` writes your answers to `.claude/setup-answers.txt`, and only `scripts/method/setup-write.sh` writes files from them, first as a card of what they change and then, when you agree, for real. No answer reaches a method file, the method's hooks, deny entries or built-in checks; the profile changes only the main session's model, effort and model list, and the checking agents stay on Opus 5.5 at xhigh. A record or other seeded file is written only when it is absent; after that only setup's own block in it changes (between `>>> method-setup` and `<<< method-setup`), and an entry setup wrote is never removed. It refuses before writing anything when an answer has the wrong shape or looks like a key, a password or personal data (named by the answer, never shown), or when the method's settings were changed by hand, so a weakened deny list stays red in `method-files`. The same answers give the same files; a test tries every combination of the closed answers | `scripts/method/setup-write.sh` |
| M032, M038, M085, M112, M113 | The review packet is the reviewer's whole input, without the author's account or noise | `scripts/method/review-packet.sh` |
| M008, M089, M108 | Ready to merge: the files are the commit, main is merged in, the checks passed, and the verdict line is the one the receipts give | `scripts/method/done-check.sh` |
| M044 | Mutation testing breaks the changed code on purpose | `scripts/method/mutate-changed.sh` |
| M039 | Every script reads the verdict words from one file | `scripts/method/verdicts.txt` |
| M072 | No hook log grows forever or stores secrets: each is cut to its newest lines, and its lines hold only fields of a fixed shape, never a command, a path or a message | `scripts/method/lib/log.pl` |
| M009, M144, M146 | The task's plan with its approval; VALID approving receipts of the reviewer and the security checker for the exact files, reviewed from the merge base or chained back to it; no other word from either on those files; at most three review rounds since the approval, also when the branch's history is rewritten; every gate's word on the branch listed | `scripts/method/done-check.sh` |
| M147 | The tier: a change that touches a path in `HIGH_RISK_PATHS` (main's list and the branch's together, so a branch can add a path but never remove one; a moved file counts at its old path too) is judged FULL, and a plan that says LIGHT is NOT READY. A broken setting on either side (a misspelt key, a spaced `=`, a bad value, a file stored through Git LFS or a filter, and an entry on either list that names no path in the branch's files, such as a misspelt path or a comment on the line) makes it NOT READY, never a shorter list. One exception: an entry on main's list that is a plain path (no space, no `#`) which an earlier commit of main had is a path a merged change deleted; it fails nothing, and the tier line tells you to drop it from main's list | `scripts/method/done-check.sh` |
| M153 | The files that steer the method are high-risk whatever `HIGH_RISK_PATHS` says: a change to `.claude/method.conf`, `checks/`, your pack (`.claude/rules/pack/`, `.claude/skills/pack-*`), `.github/workflows/`, `docs/incident-checklist.md`, `REVIEW.md`, `CLAUDE.md`, `.claude/CLAUDE.md` or `AGENTS.md`, in any letter case, is judged FULL and needs Deep review, so a quiet change to what is checked or to what steers Claude takes three approving reviewers. A project without some of these files has no problem from it. The method's own files and `.claude/settings.json` are not on the list: G6 and `method-files` keep them. Known limit: the list does not reach a file CLAUDE.md or AGENTS.md imports with `@path`, a CLAUDE.md in a subfolder, `CLAUDE.local.md`, rules under `.claude/rules/` outside `pack/`, the project's other skills, commands and agents, `.mcp.json` or `.github/` outside `workflows/`, and a pack folder that is a link changes with its target unseen; a change to these takes the tier its plan gives, and the review reads it | `scripts/method/done-check.sh`, its list in `scripts/method/lib/conf.pl` |
| M145 | The lock: the plan's Tier and Paths lines and `expected.tsv` as they were at the approval; for FULL, `expected.tsv` there at the approval, a tester run that said TESTS FAIL on a commit after the approval and before the finished files, on the branch's own history, with the Tier and Paths lines and `expected.tsv` there as approved, and the tester's newest word on the finished files TESTS PASS | `scripts/method/done-check.sh` |
| M146 | For FULL, the reporter's newest word on the finished files is APPROVE; on a high-risk path, Deep review: three VALID approving reviewer receipts for the exact files, each reviewed from the merge base or chained back to it, and no other word from the reviewer | `scripts/method/done-check.sh` |
| M126 | Every number in the report to you is in a log the check read, exactly as written, with its sign, currency mark and percent, including numbers joined by a slash or a dash (40/44, 3-5); "What the checks would miss" is there and says more than "nothing", "none" or "n/a", in one line or in every line of a list | `scripts/method/report-check.sh` |
| CI | The project's checks run on every change, outside the session | the project's CI (step 9) |

## Partly enforced

| Rule | What is checked | What is not |
|---|---|---|
| M140, the start line | The hook adds `METHOD-ACTIVE` at every start | Whether Claude stops when it is missing |
| Receipts | A gate's report has its first and last lines and was made the right way on the right files | Whether the verdict is right; a review cut off before its first word neither blocks nor counts, so its gate is run again |
| The plan's approval (M144) | The Approved line's form, and that it quotes `approve <task>` for its own task | That you typed it, or what the rest of the reply says: a quote that holds `approve <task>` passes even when it refuses ("no, do not approve <task> yet") |
| The tier (M147) | A change on a high-risk path is judged FULL | Whether a change off those paths is really LIGHT, and whether the list names every risky path |
| Seen failing first (M145) | A tester run said TESTS FAIL after the approval and before the finished files | Which tests failed, or why: the reviewer checks the tests (M090) |
| The report check (M126) | Every number written in digits is in a log, and the reporter refuses a report whose check did not pass | A LIGHT change without a reporter: then only the skill runs the check. A number written in words or with a unit or word stuck to it ("three", "5ms", "44-all", "40/s"), a count read as a date beside a month's name ("14 March tests"), month names in other languages, and whether a number means in the report what it means in its log |
| Predictions before a FULL merge (M124) | Nothing: done-check cannot see that you predicted | All of it |
| Deep review (M087, M146): three independent method-reviewer runs, launched in one message, all approving; every finding of any of them gets a disposition in the report | Three VALID approving receipts of the reviewer for the exact files | That the three were launched together and worked apart, and that every finding got a disposition |
| High-risk work beyond Deep review | Nothing | The person with authority signing the expected results (the `source` column names them), a test copy, an undo plan, a human expert: convention, in the plan's [AUTHORITY] items and the review |
| M075 | `/code-review` is kept to you by the settings | That nothing else is treated as a gate |
| M010, the method's files | Every method file and the method's settings against `method.lock`, whenever the checks run | That the lock is the real release's: a sync run from a doctored copy writes a lock that matches it (CI's comparison with the published release comes in step 9) |
| Profiles (M134) | Each profile in `scripts/method/profiles.tsv` changes only the main session's model, effort and model list; claude-opus-5-5 stays on every list, so the checking agents keep Opus 5.5 at xhigh in every profile; the start warning and G12 measure against the profile | How much a cheaper profile misses in the main session's own work; a hook, `claudeMdExcludes` or a setting that runs a program added to `.claude/settings.json` after the install is named by session-status at each start, not refused |
| M094, a scanner that is not AI | The built-in `secrets` check reads every tracked file whenever the checks run | Known security problems in the libraries the project uses: `checks/project.tsv` offers rows for four common scanners (Python, Node, Go, Rust), each off until you install its tool and turn its row on |
| M063, writes to live records | A script that sources `scripts/method/live-write.sh`, hands `method_live_opts` the person's words (only `--reason` and `--live`) and `method_live_write` its own command refuses to run without `--reason "<why>"`, prints the reason first, and does a dry run, running nothing, unless `--live` is given | A script that writes to live records without the helper: the review reads it |
| Your pack (M152) | status's `context` line says when the project's own text that loads in every session (`CLAUDE.md`, `.claude/CLAUDE.md`, `AGENTS.md` and the rules under `.claude/rules/` without a `paths:` line; the method's own rules apart) passes 8,000 bytes, naming the biggest files: long instructions are followed less well, and the method holds its own rules to the same 8,000 | What a pack rule says: a rule that would weaken the method loses to the method rule (M151), and only the review reads it (`docs/method/packs.md`) |
| The records (M014, M019) | status says when a record is missing, when CLAUDE.md does not load AGENTS.md, and when TESTS.md does not name a check listed in `checks/*.tsv` | Whether the records are up to date, and whether TESTS.md names the built-in checks |

## Written down only

These rules are text the model reads. A review can notice a broken one; nothing stops it.

| Where | Rules |
|---|---|
| `.claude/rules/method/method.md`, loaded in every session | M079, M151, M016, M033, M057, M082, M034, M119, M093, M064, M013; M020, M058, M107, M047, M048, M049, M059, M121, M154, M042, M043, M052, M056, M143, M035, M036; M060, M061, M098, M065, M063 (its helper above), M062, M054, M055, M028; for checking agents M022, M023, M115, M026, M025, M027, M117, M114 |
| `.claude/rules/method/owner.md`, loaded in every session | M012, M037, M123, M074, M068, M071, M105 |
| `.claude/hooks/method/README.md` | M073: each hook documented with what it stops, what it costs and how it was seen to fire |
| The checking agents, `.claude/agents/method/` (step 6) | reviewer M024, M083, M084, M086, M090, M102; security checker M030; tester M029; diagnose M142; reporter M031, M046, M069, M092, M124 |
| The architect (step 6) | M141 |
| The skills you type (step 6 and 6b) | `/method-start` M004, M005, M127; `/method-plan` M006, M021, M091, M125; `/method-design` M099; `/method-finish` M007, M011, M070, M087, M148, M149, M150, and its reporter for a LIGHT task with [EYES] or [CHECK] items (a convention, which done-check does not require); `/method-setup` asks the questions (with a plain-text fallback where the question tool is missing) and leaves every write to setup-write (M100, M156, above) |
| The records, REVIEW.md and the pull request text as setup first writes them, from `scripts/method/templates/` | SPEC M015, ROADMAP M017, DECISIONS M018, REVIEW.md M101, the pull request text M097 |
