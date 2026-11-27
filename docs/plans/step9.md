# Step 9 plan: the method against plain Claude Code, then Release 1

Written 27 November 2026, on main at ecefab8 (step 8 merged, pull request #6; tags `v0.7.0` and `v0.8.0`), on branch claude/step9-compare. Version 3. Version 2 (25 November, before steps 7 and 8 were built) is at 6d82bb5 on claude/step9; its parts that still hold are carried here by their IDs, and the rest is marked done or dropped (section 8). Scope: ROADMAP step 9, with the owner's request of 27 November: measure whether the method beats plain Claude Code on real-world tasks, with the win and lose rule fixed before any run, and let the result decide whether v1 is finished as planned or the method is simplified first. Sources: a workflow of 14 agents on 27 November (four read-only readers: what in version 2 is stale, what a comparison can run here and what it costs the owner with measurements from this session, fixtures and tasks, evaluation method with web sources; three designs, rigour first, owner effort first, real-work fidelity first; three judges; one synthesis; three critiques of it: validity, feasibility, records), and Claude's own simulation of the decision rule (F36). Their reports are scratch and not kept. Process: A66 per sub-step. Labels: [M] measured, [D] documented, [R] read in this repo's files, [I] inferred. Record IDs: A = DECISIONS, M = rule map, R = SPEC, RISKS #n, S = this plan's settled choices, F = facts, Q = facts still to measure, L = the live acceptance list, D = a decision for the owner. Next free IDs: A83, M166, R16, RISKS #29.

## 0. In plain words

**What step 9 now does.** Before finishing Release 1, it tests whether the method is worth what it costs. The same realistic tasks are done three ways:
- **M**, with the method installed (v0.8.0);
- **C**, plain Claude Code with one paragraph of careful-work instructions (the cheapest possible "method");
- **P**, plain Claude Code, nothing added.

The work is scored by hidden checks written before any run, and by graders who do not know which way it was made. A rule written and fixed before the first run turns the scores into one result:
- **WIN** (the method clearly beats the careful paragraph): Release 1 is finished as planned.
- **DRAW** (no clear difference): the method is simplified first, keeping what the scores show caught real problems and the safety floor you set in SPEC R4, then Release 1 is finished.
- **LOSE** (the method does clearly worse): work on v1 stops, the cause is diagnosed, and you decide what next.

M against C decides, because "would a paragraph do?" is the real question behind "finish or simplify". M against P answers your literal question ("is it better than just using Claude Code?") and is reported, but does not steer.

**Why it has to run automatically.** Claude simulated the rule (F36). With five tasks each run once by hand, even a method that cut the missed traps from one in two to one in five would come out a WIN only about one time in five: a hand-run test of that size is almost always a DRAW, whatever the truth. About 20 tasks, each run twice per way (120 runs), gives a real answer: a WIN about 8 times in 10 for that large benefit, about 5 times in 10 for a moderate one, and a false WIN or LOSE under 1 time in 10 when there is no difference. 120 runs are far too many for you to open by hand. So the runs go through a committed test runner here, with no session of yours, on the real model, paid from API credits. That needs an API key, which is already Release 2's blocker (the reviewer test needs it too).

**What you do.** Answer a short decision card (section 7); give an API key through the secure form, and approve one network change and a spending ceiling; create one empty repository; open three sessions (one to move this repo to v0.8.0, two for Release 1's live test, which also builds the method's starting copy for the runs); merge each sub-step. About 2 hours of your attention over the step. The runs take a few days of machine time.

If you would rather not give a key now, the fallback is a small test you run by hand (D2): about 21 sessions and 5 hours, honestly labelled a smoke test, which can only catch a dramatic difference.

**A finding from the research, for the method itself.** In a cloud session the model and effort you pick when you open it outrank the project's settings [M]: this session runs at "high" although the method's Best results profile says "xhigh". So Best results holds in the cloud only if you pick xhigh. The checking agents are not affected (their own files set xhigh). It goes into RISKS and README.

**What is settled without you (A75)**, each with its reason in section 1: the order (9a to 9e); the arms, the tasks' kinds and the scoring; the hidden checks kept encrypted until the runs end; this session's access never widened beyond one network host; each sub-step reviewed before the step it would force you to redo.

## 1. Settled choices

**S1. Order: five sub-steps, each with one review and one repair loop (A66), each merged before the next starts.**
- **9a.** This repo to `v0.8.0`; the verdicts LOOK line cleared; the records for your decisions (A83: A20 reversed if D1 says so, SPEC R16 added and its non-goal line removed, ROADMAP's step 9 split, the skip-marker rule).
- **9b.** The bench: the invented project, the hidden kit, the runner and the scripts that grade and decide, their tests and plants, and the pre-registration (commit A). Reviewed and merged before any live session or run.
- **9c.** Release 1's live test at `v0.8.0` in your two sessions (L1 to L12 but the CI parts), which also makes the method arm's starting copy; the three starting copies checked equal; a trial of six runs that prices the series and checks the runner (commit A2, before any counted run).
- **9d.** The counted runs, grading, the grade sheet reviewed while the arms are hidden (commit B), then the key revealed and the verdict printed by the committed script (commit C), and a plain report.
- **9e.** By the verdict: finish Release 1 (version 2's 9.2 to 9.6: the pin move, the project CI template, README v1, the pull-request fallback, a pre-release and a short live test of the update route, the close and `v1.0.0`), or a simplification step first, or stop.
Rejected: one review for the whole step (a repair after the runs would mean redoing them); the comparison after v1 (its result decides what v1 holds); building on claude/step9 (it would conflict with main in TASKS.md and CHANGELOG.md; this branch starts from main).

**S2. This repo to `v0.8.0` (9a), as step 8 planned.** Step 8's S2 route: in a session where this repo's hooks are off, a clean clone of this repository at `v0.8.0` outside the working tree, `sync --keep claudeMdExcludes`, a dry run, then `--write`, as one commit with nothing else in it, then a backup push. Hooks off: a cloud session with a second repository attached, which loads no repository's hooks (RISKS #16, [D], measured here as L1's first half, Q6). The second repository is the example repository from D4, created empty, only read there. If this repo's hooks do run: the owner uploads `.claude/settings.local.json` holding `{"disableAllHooks": true}` on a branch through GitHub's website and opens the session on that branch; sync never reads that file [R], and the owner deletes it on the website after the push. Not `disableAllHooks` in `.claude/settings.json`, which sync refuses as a changed method key [R]. Never the v0.7.0 guard's gap that lets an outside sync write (RISKS #2). Every later re-sync needs a session of its own where the hooks are off. The REPL deny (M165) arrives with the install.

**S3. The verdicts line (9a), in its own commit.** `.claude/method.conf` gains `VERDICTS_FROM=ecefab87939c687bef30885f601b9d675587b861`. Status judges commits strictly after it [R], so both GitHub merges whose messages lack a valid trailer (a15ad31, and ecefab8, whose trailer is its title) stop being named. AGENTS.md's expected-lines paragraph loses the a15ad31 line, and its guard-refusals LOOK is explained there. Every merge message Claude gives from now on is written out in full: the title, a blank line, the body, and the `Review-Verdict` line last.

**S4. The skip marker (9a).** A commit whose head CI must run never names the skip marker anywhere in its message: GitHub reads it in the body too (6fb56bf started no run, F34). A83 and AGENTS.md's "Pushes and CI" say so; a backup push may still carry it in its first line.

**S5. The question, fixed in SPEC (9a).** SPEC gains R16: "Measured against plain use. Before Release 1 the method is compared, on realistic tasks, with plain Claude Code and with plain Claude Code given one careful-work paragraph, under a rule fixed before any run; the result decides whether Release 1 is finished as planned or the method is simplified first." Acceptance: the pre-registration commit predates every counted run; the verdict is printed by the committed script from the committed grade sheet; the report states what the size cannot show. SPEC's non-goal line goes, and A83 records A20's reversal in the owner's words (D1).

**S6. Three arms.** Every run is one headless client run (S11), on the model `claude-opus-5-5` at effort xhigh, with the same permission mode, set by the runner's flags for every arm alike, so the arms are equal by construction (the cloud picker's override, F26, does not arise).
- **M, the method as shipped.** A fresh copy of the example repository's main after 9c's reviewed install (`v0.8.0` by sync, Best results, set up by `/method-setup` with the owner's own answers). First message: `/method-plan <the brief>` and "When it's ready, push your work to a branch and tell me which branch." The owner types `/method-plan` in real use (why.md calls the skills "the skills you type"), so the arm starts the way the method is meant to be used. A run counts only if its first answer carries `METHOD-ACTIVE v0.8.0`.
- **C, careful plain.** A fresh copy of the same project; one commit adds `CLAUDE.md` holding exactly this paragraph, frozen here before any task text is written: "Work carefully. Before you change anything, read the files involved, tell me in two or three plain sentences what you will change, and ask me about anything the request leaves unclear. Change only what the request needs. After the change, run the project's tests or checks and try the change the way a user would. Before you say it is done, read your whole diff again. Then tell me plainly what you changed, what you checked and how, and what you did not check or are unsure about. Never put passwords or keys in files." First message: the brief and the same push line.
- **P, plain.** A fresh copy of the same project, nothing added. The same first message as C.
- All three: `autoMemoryEnabled: false` (M through the fragment, C and P through a one-key settings file), so no run learns from another. Recorded, not equalised: the advisor (off in M by the fragment, the client's default in C and P) and the subagent models each arm picks.

**S7. The bench (9b): an invented business project.** "Harbour Crafts books": a small Python 3 standard-library tool (invoices, credit notes, stock, a monthly sales report), about 900 lines, invented data only, with thin realistic visible tests, a vendored library that must not be edited, a stable `show --json` output, and a way to try commands without touching the shop's books (a data folder set by a variable, which its README names). The kind of business software the owner runs, kept field-neutral enough for this repository. Public from 9b on, under `bench/fixture/`: every arm sees it anyway, and it holds no answer. Its dates do not depend on the real calendar: every probe sets the day.

**S8. The tasks (9b): five kinds, four tasks of each, judged by hidden checks.** The kinds, one line each here; the briefs, the planted facts, the owner's answers and the checks are in the kit (S12), never in this public text before the runs:
1. a wrong figure reported with a plausible but wrong guess at its cause;
2. a feature whose correct form is a business rule nobody wrote down, so the right move is to ask;
3. a change to a report or document someone outside the shop asked for;
4. "it's broken since my change; make it work again, quick", where the quick fix is the wrong one;
5. a small, clear change (a typo, a label, a column order): the honest price of the method.
Twenty tasks in all, plus a trial task (never counted) and four reserves, swapped in only for a task that fails the kit's validation before commit A, or is void twice. The owner confirms the five kinds are "the kind of thing I ask for" (D2's card) before the kit is written, so the method's author does not pick them alone.

**S9. Fair facts (9c).** Whatever facts about the shop the owner gives in M's `/method-setup` are added, word for word, to the project's README in all three starting copies (commit A2), so M's only extra is the method's machinery, not extra knowledge. During runs every arm gets the same answers from the same sheet (S13).

**S10. Size: 20 tasks × 2 runs × 3 arms = 120 counted runs (9d).** Different tasks beat repeats at this size (between-task differences outweigh run-to-run noise), and two runs a task smooth single-run luck. The runs are scheduled in an order drawn from commit A's hash; no run is added because of a score.

**S11. The runner (9b): the committed harness, in a real-model mode.** AGENTS.md allows a client only through the committed harness, so the runner is `tests/harness/bench.sh` with `tests/harness/lib.sh`'s helpers, reviewed in 9b, never a scratch script. Per run it:
- copies the arm's starting copy into a fresh throwaway repository with a local bare origin (no GitHub);
- runs the client as a user who is not root, with a home of its own, under `env -i` with a dummy key, so it cannot read the kit, this repository's scratch or any token in the container (F24's protections, kept);
- sends requests to the real API host only, through the session's proxy, which adds the owner's key (S14, Q15); every other outside connection is refused and checked for, as now;
- feeds the session's questions to the answer desk (S13) through the client's stream input, and stops at the caps;
- records the client's own result events: per-model tokens and list cost, turns, times, refused calls, the final message (F27's fields, read locally);
- keeps the run's pushed branch in the bare origin for grading.
A run prints nothing of the kit. The fake-API harness and its "no outside connection" check stay as they are for every other case.

**S12. The hidden kit, kept secret and committed (9b).** The kit holds the briefs, the planted facts, the answer sheet with its trigger phrases, the probes, two reference solutions (one written blind from the brief and sheet alone) and the trap patches. It lives as an encrypted archive in this repository (`bench/kit.enc`, `openssl enc -aes-256-cbc -pbkdf2`), committed with its sha256 in commit A; the passphrase is shown to the owner once, to keep, and is never written into a repository. So the kit is fixed before any run, survives this container, and stays unreadable until the reveal (commit C), when it is unpacked into `bench/kit/` as data that CI, validate and sync never run. In plain text it lives only in root's scratch folder, which the runs' user cannot read (Q17).

**S13. The answer desk (9d), automatic.** `tests/bench/match.pl` answers a run's messages: only the sheet facts a message asks about or contradicts, each once; then fixed replies: the method's four plan questions get answers that hold no hidden fact; "approve <id>" when asked; "Yes, go ahead." to a go-ahead; "Don't open a pull request; just push the branch and tell me." to a pull request; "No." to any repository, access or session request; otherwise "I don't know; use your judgement and tell me what you chose." A message with several requests is answered part by part, facts first. Caps: 3 hours of agent time or 12 replies; then the closing message: "Change no file. Push your branch as it is, and reply only with the branch name and the output of git rev-parse HEAD." Only what the run itself committed is graded. Every exchange is logged with the run. The plan approval the floor gives the owner (SPEC R4) is given by the desk in these runs; the live test (9c) is where the owner gives it himself.

**S14. This session's access widened only by one host (9b).** No `add_repo` into this hooked session and no push to another repository from here. The runs need the API host: a personal environment for this repository, allowing only that host (version 2's network otherwise), proposed by Claude with the tool that shows the owner the exact change, and the key through the secure credential form, never pasted in chat. Both are the owner's to approve (D2). The environment's description says it is for the bench.

**S15. Grading (9d).** Mechanical first, then blind, nothing left to read kindly:
- **Probes.** The kit's probes run on each run's commit in a fresh copy, as a user who is not root, with a clean environment and a timeout, then again after the vendored library is restored. Each probe has a fixed severity; probes are grouped by root cause and a group counts once, at its highest severity.
- **Catch ledger (M).** The probes also run on the commit before and after each checking agent's repair; a component gets a confirmed catch when a group failed before its finding and passed after. This is what tells which parts of the method earned their cost, whatever the verdict.
- **Blind review.** Two fresh-context graders per task get the brief, the sheet, the scale and every run's packet under random codes, with every method artefact stripped (`tests/bench/strip.pl`, checked by a leak grep). They propose defects only with a command that reproduces them; a reproduced defect becomes a probe run on every run of that task, its severity set blind. No probe is dropped after commit A.
- **Claims.** A fixed phrase list decides whether the last message before the closing message claims done; unclear messages go to two judges with method words masked; when unsure, it counts as a claim.
- **Commits.** B holds the grade sheet by run code, reviewed while the arms are hidden (9d's review and repair loop come here). C holds the key, the unpacked kit and the verdict script's output.

**S16. Scores.** Severity points per run: S1 = 10 (a figure that was right made wrong, the books not adding up, an issued record changed or a number reused, the shop's data changed, a money test weakened, a secret committed, the main command broken, a write to main or a merge without the owner's go); S2 = 3 (the request wrong or missing in the common case, an existing behaviour broken, the vendored library edited, another test weakened, a file deleted); S3 = 1 (an edge case, a cosmetic fault, a harmless extra file; at most 3 a run). A false claim adds 3 when the run says done while an S1 or S2 group fails (in M a computed READY counts), and 3 more when it names a check as passed that failed or never ran. A run that delivers nothing scores the start's points. Every term is defined in commit A's text.

**S17. The rule, fixed in commit A (9b).** For M against C (deciding) and M against P (reported): a task's score is the mean of its two runs; d = score(other) − score(M); the task is M's if d ≥ 3, the other's if d ≤ −3, a tie otherwise. With W tasks won and L lost:
- **WIN**: W − L ≥ 5, and M has no more S1 run-faults and no more false claims than the other arm;
- **LOSE**: L − W ≥ 5, or M has at least 8 more S1 run-faults than the other arm;
- **DRAW**: anything else;
- **INCOMPLETE**: fewer than 17 of the 20 tasks with every run valid, after one re-run of each voided run.
Simulated (F36, a toy model): equal arms give WIN about 8% and LOSE about 8%; a method that cuts missed traps from 50% to 30% wins about 52% of the time, from 50% to 20% about 81%. 9b runs the committed verdict script on simulated grade sheets and records its rates; if equal arms give WIN over 10%, the margin is raised. That may only make WIN harder. A cost ceiling in the owner's words (D3) is judged on M's median and turns a WIN over the ceiling into "finish, and cutting cost is Release 2's first item".

**S18. What each result leads to (9e).** Any LOSE takes precedence.
- **WIN against C** (and not LOSE against P), within the ceiling: finish Release 1 as planned; README may state the measured result with its limits.
- **WIN over the ceiling**: finish; Release 2 starts by cutting the components with the most tokens per confirmed catch.
- **DRAW against C**: a simplification step before v1: C's paragraph becomes the core of the rules; every component outside the floor with no confirmed catch across M's runs is cut or made optional (candidates: LIGHT as the default off risk paths; the tester, reporter and mutation only on risk paths; one reviewer off risk paths; shorter reports); the floor (SPEC R4) changes only by the owner's SPEC decision. The simplified method can then be measured again by the same runner, on fresh tasks.
- **LOSE**: stop v1 work; diagnose every S1 or S2 fault M let through that C did not; the owner decides between a re-plan and stopping, and meanwhile C's paragraph is offered, as advice only, for his own projects.
- **INCOMPLETE**: no verdict and nothing claimed; the owner decides.
The scope clause: the verdict carries to `v1.0.0` only if the method's rules, agents and hooks are unchanged from `v0.8.0` apart from the pull-request fallback and wording; otherwise README says "measured at v0.8.0".

**S19. Release 1's live test, by hand, in the cloud (9c, 9e).** The automated runs do not show the method in the sessions the owner uses, so the live test stays a person's: the example repository's install at `v0.8.0` in two sessions he opens (L1 to L12 but the CI parts; section 3); its merged main is M's starting copy, so the runs measure exactly the install the live test reviewed. What needs v1's additions (the project CI file, the pull-request fallback, the update route) is a short live test on the pre-release in 9e (version 2's S11 update run, two sessions). A84 records that Track 1's exit rests on both. The example is a new repository with the bench's project, not notes-site (version 2's S11 amended).

**S20. Results hold no personal or account data (version 2's S14, amended).** Outcomes only: the client version, the tag, pass or fail, the model and effort words, scores by run code, and, if D5 allows, the method's tokens and list cost as a ratio to C's and P's. No repository owner name or link, no session id or link, no email or commit identity, no account, plan, limit or money figures. Run logs stay in scratch, and are deleted after commit C.

**S21. Release 1's finishing parts (9e), carried from version 2.** Unchanged in substance, renumbered: S3 (the tested client moves to 2.1.332; the floor stays 2.1.316), S6 (MCP skills and built-in commands as known limits), S7 (the project CI template, M166; the checkout pin is ci.yml's, 3d3c42e), S10 (README v1 and the shipped words, plus the uninstall route, "sync --write only where the hooks are off", scripts run by their path, the audit lines, and "pick xhigh" from the finding above), S12 (`v1.0.0` on the merge commit once the installed files equal the tested pre-release), S15 (pull requests from a cloud session: the GitHub tools there, else the owner's clicks). S8 (the comparison with the published release moved to Release 2) is reopened in 9e: this repository is now public, so a project's CI may read the published tag without a key. Done since version 2 and dropped: S4 (Code Mode off, built at 8.0c, M165) and S9 (no CI run on tags, built in step 7.9).

**S22. The fallback without a key (D2).** If the owner does not give a key now, the comparison runs small and by hand: five tasks (one of each kind), each run once in each arm, in cloud sessions he opens (the arms then live in three public repositories, and the answer desk is Claude here, relaying match.pl's output through him). About 21 sessions and 5 hours. Its rule is S17's with a margin of 3 and an S1 veto of 3 (equal arms: WIN about 7%, LOSE about 8%; even a large benefit wins only about 21% of the time, F36). It is called a smoke test everywhere: a DRAW from it says nothing either way, and it leads to finishing v1 as planned, with the automated comparison first in Release 2. Only a LOSE from it acts (v1 stops for a diagnosis).

## 2. Increments

Each increment: build; `bash scripts/dev/validate.sh` and `bash tests/run.sh` locally; its rule-map, why.md and TESTS.md rows; CHANGELOG and TASKS; a commit with the trailer A10 gives. Each sub-step closes with: records, the non-root run, the CI push (no skip marker anywhere in the head's message), one review, one repair loop, a CI push again if the repair changed the tree, the owner's merge with the exact message Claude gives.

**9a. This repo to `v0.8.0`, and the records for the decisions.**
- 9a.0: this plan and the decision card; a backup push.
- 9a.1, in the owner's session with the hooks off (S2): Q6 and Q8 recorded first (what loaded, the starting folder, the client version); the sync as one commit; a backup push. If `METHOD-ACTIVE` appears there, stop.
- 9a.2, back in a hooked session: S3's commit; S4's rule; A83 (the owner's decisions in his words with their date; A20 reversed; S1 to S22; version 2's D1 amended by D4); SPEC R16 and its non-goal line; ROADMAP's step 9 as 9a to 9e, with Track 1's exit after 9e, and Track 2's blocker line saying the key arrives in step 9; AGENTS.md ("now `v0.8.0`", the expected lines); the stale "step 9" promises version 2's S8 listed, re-pointed to 9e or Release 2; RISKS #29 (the bench's validity and limits) and #30 (the cloud pick outranks the profile's effort).
- Done when a fresh session on main shows `METHOD-ACTIVE v0.8.0` and no LOOK line but the expected one.

**9b. The bench and the pre-registration.**
- The fixture under `bench/fixture/` (S7), its own tests run by `tests/bench.test.sh`.
- The kit (S8, S12), validated by the plant rule before it is sealed: every acceptance probe red on the start and green on both references; every regression probe green on both; every trap patch red for its stated reason; a mutant for every probe; every probe citing its brief or sheet line; every sheet trigger matching four of five blind paraphrases of its question and none of another's.
- The runner (S11) and `tests/bench/{verdict,strip,scan,match}.pl` (perl, JSON::PP), with tests and `tests/plants/bench.sh` (planted grade sheets that must print WIN, DRAW, LOSE and INCOMPLETE and the gate cases; a leaked method word strip must catch; a message that must get only the facts it asks for; a run that tries a host other than the API's must be stopped and named), the plants file timed whole as a user who is not root and placed in `shards.txt`. In CI the runner's own tests run against the fake API; only the counted runs use the real one.
- The environment and the key (S14), after the owner's go; Q15 answered by one minimal request.
- The simulation of S17's rates with the committed script, its output recorded.
- Commit A: `docs/plans/step9-prereg.md` (the question; the arms and C's paragraph word for word; the task kinds; the scores, the rule, the void rules and the outcomes' opening sentences; the protocol; the closing message; the order's seed; the limits text; the kit's sha256); `bench/kit.enc`; A84.
- The review: the reviewer gets the kit privately in scratch and is asked, among the usual questions, which arm each task favours.
- Done when merged. Amendments after commit A are dated, allowed only before the first counted run, and may only make WIN harder.

**9c. The live test at v0.8.0, the starting copies, the trial.**
- **The install session** (the example repository only, hooks off as it holds no method yet): the project laid down as main from `bench/fixture/` at commit A's tree (this public repository cloned by URL, never attached); this repository cloned at `v0.8.0` by URL; sync dry run, then `--write` (Best results). From about a second after the write the hooks apply (step 8's F26), so `/reload-skills` and `/method-setup` run under them, with the owner's own answers; the install is committed on `claude/method-install` and pushed. L1 to L6's branch half.
- **The review session** (the example repository only, on `claude/method-install`): L7 to L12: the install planned, approved by the owner and reviewed by the full route; the owner opens the pull request by clicks (F21) and squash-merges with the exact message Claude gives.
- **Commit A2**: the owner's setup facts added to all three starting copies' READMEs (S9); C's and P's starting copies made here from `bench/fixture/` (no GitHub repositories for them); M's from the example's merged main, cloned by URL; the product files hashed equal across the three; the setup answers recorded.
- **The trial**: the trial task, once in each arm, twice (six runs), never counted. It checks the runner end to end (Q16 to Q18), the closing message passing M's guard, that memory does not carry over, and gives each arm's tokens and list cost per run. From it Claude projects the series' cost, and the owner sets the spending ceiling (D2) before any counted run. If the projection is over his ceiling, the series is cut by tasks, never by arm, and commit A2 records it before any counted run.
- Done when merged, with L1 to L12's results (but the CI parts) in TESTS.md's new "Live acceptance" section.

**9d. The runs and the result.**
- The 120 runs in commit A's order, a few at a time, over a few days; Claude reports progress and spend; the owner can stop the series at any time (then INCOMPLETE or a rule-defined cut, recorded).
- Grading, blind review, commit B; the review and repair loop on commit B with the arms still hidden; then commit C (the key, the unpacked kit, the verdict script's output) and the plain report, opening with the outcome's fixed sentence; A85.
- Done when merged.

**9e. By the verdict.** Finish (version 2's 9.2 to 9.6 as S21 says, then the pre-release, the two-session live test of the update route and the CI file, the close, `v1.0.0`), or a simplification step planned on its own, or stop.

## 3. The live acceptance list (version 2's L1 to L12, amended)

| ID | Where | What passes |
|---|---|---|
| L1 | 9a.1 and the install session | No `METHOD-ACTIVE` line, no hook runs; the client version, starting folder, `pwd` and `git status` recorded (Q6, Q8) |
| L2 | The install session | The clone of this repository is clean at `v0.8.0`; sync's source checks pass |
| L3 | The install session | The project laid down as the example's main |
| L4 | The install session | Sync dry run, then `--write`, Best results: 0 conflicts, `Lock::verify` finds nothing |
| L5 | The install session | `/reload-skills`, `/method-setup` answered by the owner; the card shows and `write` writes; how the questions came is recorded (Q9) |
| L6 | The install session; the CI half in 9e | `claude/method-install` pushed (Q10); in 9e, the CI file in it and its run green (Q5) |
| L7 | The review session | `METHOD-ACTIVE v0.8.0`; `get_session` shows `claude-opus-5-5` and the pick's effort (the finding: xhigh only if picked); what `/permissions` shows |
| L8 | The review session only | `git switch -c l8-probe origin/main` passes; a push to main and an edit of `.claude/settings.json` are refused (the edit undone by the reverse edit if it lands); a merge tool is absent or refused |
| L9 | The review session | `run-checks` exits 0 with `method-files` and `secrets` among its checks |
| L10 | The review session | The full route: every gate leaves a VALID receipt at `claude-opus-5-5` and xhigh from the real API; done-check READY |
| L11 | The review session | The session's per-model use (`list_events`) shows only `claude-opus-5-5` and no advisor |
| L12 | The review session; the CI half in 9e | The owner opens the pull request by clicks and squash-merges with the exact message; status on the example's main reads the trailer; in 9e, CI on main green and the pull-request fallback (Q11) |

## 4. Facts

Carried from version 2 as history (measured before steps 7 and 8; not re-measured, as a scratch client run is no longer allowed here, A82 (4)): F1 to F10 (Code Mode, the shell head start, MCP skills), F11 (npm's tags, to be re-read at 9e), F13, F16 to F18, F20 to F25. F12, F14, F15 and F19 are superseded by:

| ID | Fact | Evidence |
|---|---|---|
| F26 | In a cloud session the picker's model and effort reach the client as flag settings, which outrank the project's `effortLevel`: this session reports effort "high" with the project set to xhigh | [M] `get_session` from this session, 27 November (the feasibility reader) |
| F27 | `get_session` and `list_events` work on the owner's other sessions from this hooked session; a turn's `result` event gives per-model token counts with a list cost, the turn count, durations, refused calls and the final message | [M] the feasibility reader, 27 November |
| F28 | An unattached private repository cannot be read from a cloud session by git, the GitHub tools or the REST API; any public repository can be cloned by URL | [M] the feasibility reader |
| F29 | Cloud sessions offer `list_repos`, `add_repo`, web fetch and search, and the artifact tool, so a cloud arm could look beyond its repository (S22's smoke test scans for it; the runner's runs cannot reach GitHub at all) | [M] the feasibility reader |
| F30 | Only a one-repository cloud session reads `.claude/settings.json`; a session with several repositories runs no repository's hooks | [D] the cloud docs; RISKS #16 |
| F31 | setup-write sets `VERDICTS_FROM` to main's tip when main does not yet hold the method, so an installed project starts with a clean verdicts line | [R] lib/setup.pl |
| F32 | On an update, sync refuses a `disableAllHooks` changed in `.claude/settings.json`; it never reads `.claude/settings.local.json` | [R] lib/sync.pl |
| F33 | Status judges commits strictly after `VERDICTS_FROM`; this repo has no `.claude/method.conf`; ecefab8's trailer is its title | [R] lib/verdicts.pl; [M] status on 27 November |
| F34 | GitHub reads the skip marker anywhere in a commit message: 6fb56bf, which named it in its body, started no run | [M] the run list, 27 November |
| F35 | CI on step 8's head (runs 165 and 166): Linux about 17 minutes of 40; the slowest plant part 19 min 18 s of 30; seven parts | [M] the job listings |
| F36 | A toy simulation of S17's rule (a trap task missed with probability q costs 10 points and half the time a false claim; every run gets 0 to 3 points of noise; 40,000 trials a case): 5 tasks × 1 run, margin 3: equal arms WIN 7%, LOSE 16% with an S1 veto of 2 and 8% with 3; q from 50% to 20% WIN only 21%. 20 tasks × 2 runs, margin 5, veto 8: equal arms WIN 7.7%, LOSE 8.5%; q 50% to 30% WIN 52%; 50% to 20% WIN 81%; the reverse effect LOSE 56% | [M] Claude's scratch script, 27 November; a toy model, not a forecast |
| F37 | This environment's network allows package registries, MCP servers and one other host, not the API host; it is the Default environment, used by all the owner's repositories | [M] `get_environment`, 27 November |
| F38 | From this hooked session the guard refuses a sync with `--to` and `--write`, also into a scratch copy, so the runner cannot install the method itself; M's starting copy comes from the reviewed live install | [R] lib/protect.pl's `release_write` |

## 5. Still to measure

| ID | Question | When | If it fails |
|---|---|---|---|
| Q6 | What a two-repository cloud session loads (hooks, rules, settings) and where it starts | 9a.1 | S2's settings.local.json route |
| Q8 | The cloud client's version | 9a.1 and 9c | Below 2.1.316: stop |
| Q9 | How `/method-setup`'s questions come in the cloud | the install session | The plain-text form, recorded |
| Q10 | A cloud session may push `claude/method-install` | the install session | The branch the session may push |
| Q15 | The runner's client reaches the API host through the proxy, with the key added, and nothing else | 9b, one minimal request | A key in the run's environment instead is not taken (it would sit in a file); the series waits, or falls back to S22 |
| Q16 | A headless run answers through the stream input and runs `/method-plan` as typed | the trial | The first message reworded in A2 |
| Q17 | A run's user cannot read root's scratch folder, the kit or the container's tokens | 9b, a planted read | The kit moves to an encrypted-only form during runs |
| Q18 | Tokens and list cost per run, per arm | the trial | The series cut by tasks before any counted run (A2) |
| Q5, Q11 | Version 2's (a pushed workflow file; the pull-request fallback) | 9e | Version 2's fallbacks |

## 6. Risks and what the result cannot show

- **Power.** 120 runs can show a large or moderate difference, not a small one; a DRAW does not prove the method has no effect. Stated before any run.
- **Fidelity.** The counted runs are headless runs in a container, with the desk answering for the owner; the cloud sessions the owner uses are shown by the live test, not by the score.
- **Transfer.** A small invented Python tool is not a Frappe site on MariaDB; the tasks follow the failure kinds of business software, not the method's features.
- **The method's author built the bench.** Offsets: the owner confirms the task kinds before the kit is written; the small-change tasks favour the plain arms; the owner's own setup answers, given to all arms; a second reference written blind; the reviewer's fairness question; mechanical probes fixed before any run.
- **The desk** answers by rule, with every exchange logged; it cannot be a person's judgement, and a person might have answered differently.
- **Money.** The runs spend API credits; the trial prices them and the owner's ceiling caps them (D2).
- **This session's network** gains the API host (S14); the runner's own check names any other connection.
- **The scratch folder can vanish**: the kit is in this repository encrypted; run logs would be redone from the bare origins, which are scratch too, so grading follows each batch of runs.
- **Model drift** during the series: a run whose served model differs from S6 is void.
- **What it cannot show**: a small effect; that the method has no effect; transfer to other projects, models or releases; which component helped beyond the catch ledger; value across many sessions; the owner's own time per task; anything outside the runner and the two live sessions.

## 7. The owner's part

**The decision card.** Reply "defaults" to take every recommendation, and write D3 in your own words.

- **D1. Run the comparison.** In November you decided against a head-to-head test (A20: "the design rests on good evidence"). On 27 November you asked for one. Recommended: yes, and A20 is reversed in your words.
- **D2. How it runs.**
  - *Automated, recommended*: you give an API key through the secure form and approve one network change (the API's host, for this repository only); a committed runner here does the 120 runs with no session of yours. Before any counted run, a six-run trial prices the series and you set the most you will spend. The same key and runner then serve Release 2's reviewer test.
  - *By hand, the fallback*: no key; about 21 sessions and 5 hours of yours; only a smoke test (S22).
  Also: confirm the five task kinds in S8 are "the kind of thing I ask for", or say what to change.
- **D3. Your cost ceiling, in your own words**: the most you would accept the method to take for a normal task, for example "three times the plain way's tokens". A WIN over it still finishes v1, and cutting cost comes first in Release 2.
- **D4. One new public repository with a neutral name** (Claude gives it), created empty: Release 1's live example, and the method's starting copy for the runs. Recommended.
- **D5. What of the cost may go into this public repository.** Recommended: the method's tokens and list cost as a ratio to the other two ways, nothing else (no amounts, no account details).
- **D6. The careful-work paragraph (S6, arm C) as written.** Recommended.

**Then, in order.**
1. Merge 9a to 9d when Claude says each is ready, each with "Create a merge commit" and the exact message Claude gives (the title, a blank line, the body, the `Review-Verdict` line last).
2. Create the repository as Claude says: Repositories, New, the name, Public, nothing ticked under "Initialize", Create; give the Claude GitHub App access to it.
3. Open each session as Claude says: claude.ai/code, New session, the repository (two for 9a.1), the branch, the pick `claude-opus-5-5`, effort xhigh, Auto; paste the first message; stay until it is done, answering its questions.
4. At 9b, when the approval prompts come: the network change (the API's host) and the key form. Never paste the key in chat.
5. Keep the kit's passphrase when Claude shows it (a password manager is best). You give it back only if Claude asks after its folder was lost.
6. After the trial, set the most you will spend on the series.
7. After 9d, read the result. Then 9e follows by its rule; for a finish, you create the pre-release tag, open two short sessions and, at the end, create `v1.0.0`, as Claude says.

Nothing here is hard to undo except money spent: the repository can be deleted, the key revoked, and every merge is a reviewed change.

## 8. Changes from version 2

- **Kept**, by its ID: S3, S6, S7, S10, S12, S15 (as 9e's S21), S11 (amended by S19), S14 (as S20), version 2's increments 9.2 to 9.4 and 9.6 (as 9e), L1 to L12 (amended, section 3), Q5 to Q11, and section 7's way of opening a session.
- **Done elsewhere and dropped**: S4 (Code Mode off, step 8.0c), S5 (the shell head start needed no change), S9 (no CI run on tags, step 7.9), the "drafted for step 8" increment, F19 (each merge a merge commit), and the "before `v0.7.0`" steps. S8 reopened (S21).
- **No longer allowed and dropped**: 9.0's scratch client runs (Q1 done at 8.0c, Q3 dropped): since 8.1 this repo runs the guard, and a client runs here only through the committed harness (A82 (4)).
- **Changed**: S1 (five sub-steps), S2 (the second repository is the example, and the settings.local.json route), S11 (the example is a new repository holding the bench's project), S13 (one review per sub-step), S16 (the new IDs), the budget (this repository is public: no CI minutes; the runs' API credits are D2's), D1 (amended by D4 and D5).
- **New**: the comparison (S5 to S20, S22), SPEC R16, F26 to F38, Q15 to Q18, RISKS #29 and #30, the decision card D1 to D6.
