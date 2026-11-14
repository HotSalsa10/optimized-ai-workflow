# Step 6 plan: method rules, agents and skills; then 6b, a computed "Ready to merge"

**Version 2, approved** by the owner on 14 November 2026, who left the choices to me ("think carefully then choose whats best"). Approved: step 6 as planned, with the two judgment calls as recommended (no planner agent, its rules in /method-plan; a high-risk change needs three reviewers who all approve, in place of M087's vote). Step 6b is approved in direction; its design is checked again against what step 6 built before 6b's build starts, and the owner is told of any change. M045's twelve questions are not available: M045 is later and /method-checks is not built (S18). Version 1 was critiqued for feasibility and for scope, value and safety; section 7 lists every finding and what changed. Drawn from three read-only maps made for this plan (the requirements and deferred items, the client's behaviour at 2.1.316 and 2.1.319, and what the built code requires). Step 6's first draft and its critiques were lost with the planning session's scratch space (TASKS.md:358), and `plan-v3-full.md` is in neither the repo nor its history, so nothing here rests on them. Process: A66 (one review and one repair loop per step; fix what a careless agent could plausibly hit, record the exotic as known limits). Labels: [M] measured (by the harness, a decision or the platform map), [D] documented, [I] inferred, [C] read in the client's bundled code. Record IDs: A = DECISIONS, M = rule map, R = SPEC, RISKS #n, S = this plan's decisions, V1/V2 = the two critiques' findings (section 7).

## 0. In plain words

**First, before this plan.**
- Steps 5 and 5b are finished and wait for your merge: 36 commits, 93 files, not yet on main (origin/main is still dd860c3). M127 says that merge is the one next thing. I recommend you merge them before step 6's build starts, so step 6 is reviewed on its own.
- Before that merge, one setting on GitHub [EYES]: Settings, General, Pull Requests, "Allow squash merging", default message "Pull request title and description". Otherwise GitHub's squash message puts its own lines after the `Review-Verdict:` line, and status judges main's commit bad (A30). Claude cannot set this (G4 allows `gh api` reads only).

**What it adds.**
- Step 6: the method's own words, as files Claude Code loads.
  - Two rules files that load in every session: how Claude works (scope, stops, checking, risky work), and how reports to you are written.
  - Six agents. Five are checking agents ("gates") whose reports get receipts: reviewer, security checker, tester, diagnose, reporter. One drafts and never checks: the architect.
  - Three skills you type: `/method-start`, `/method-plan`, `/method-design`. A fourth, `/method-checks`, only if you give me M045's twelve questions (S18).
  - Checks that keep the words honest: a size budget, and a lint against emphasis words and "think carefully" lines. The guard also starts protecting the method's skills.
  - `why.md`, one page that ships with the method: what a script enforces, what is only partly checked, and what is only written down.
- Step 6b: "Ready to merge" computed from receipts, not from a typed line.
  - done-check reads the gates' receipts for the exact files, the plan's approval line and the locked expected results.
  - A report check lists every number not found in a log; the reporter refuses a report that fails it.
  - `/method-finish` drives it all and opens the pull request with the report.

**What it stops.** Each item says what is checked, no more.
- (6) An agent file that lists delegation tools, or a drafting agent with tools that write. A method skill edited mid-session. The always-loaded text growing past its budget unseen. A gate that writes files gets an INVALID receipt (loud, not prevented).
- (6b) A merge called ready when:
  - the reviewer's or security checker's approval is missing, cut off, for other files, or reviewed only a slice that does not chain back to a full review;
  - any reviewer or security run on those files said something other than approve;
  - more than three review rounds were needed (then: plan again, M009);
  - the change has no plan with an approval line naming the task;
  - a FULL change's expected results, tier or paths changed after approval; no test run failed after approval and before the code; or the tests do not pass at the end;
  - a FULL change has no approving reporter;
  - a change touching a high-risk path does not have three approving reviewers.
  A typed "approve" that the receipts do not back.

**What it does not stop.**
- Rules are text. Claude can still fail to follow one; why.md says which rules a script enforces and which are only written down (M067).
- Whether a review is right (that is Release 2's reviewer test, R10).
- That you typed the approval: done-check checks the line's form and task name, not who wrote it.
- Which tests failed before the code: done-check sees only that the tester's run said TESTS FAIL; the reviewer checks the tests themselves (M090).
- A receipt or approval line forged by a program Claude writes and runs (RISKS #2).
- Your merge on GitHub stays the real lock. Claude still never merges (S12).
- Sessions where the hooks do not run: several repositories in one cloud session, or a Projects thread (RISKS #16).

**What you will see.**
- `/method-start`: where things stand, what is blocked and on whom, how much finished work waits for your merge, whether GitHub's squash setting is right, and the one next thing.
- Before a FULL task, Claude asks for whatever is missing of the four points below, then ends the plan with one question: reply `approve <task-id>`.
- Before a FULL merge, three cases to predict, then the real results copied from the test log.
- A pull request whose text opens with status and next step, then anything you must look at ([EYES]) or someone with authority must sign ([AUTHORITY]), then every gate's word on every version reviewed, and what the checks would miss. Every number in it is in a log the report check read.

**What it costs.**
- Each session: at most 8,000 bytes of rules plus 3,000 bytes of skill and agent descriptions, about 2,800 tokens [I]. These are the budgets in S7.
- Each change, in Opus runs at xhigh per review round [I]:
  - LIGHT: 2 (reviewer, security checker);
  - FULL: 5 (tester twice, reviewer, security checker, reporter);
  - a high-risk change: 2 more reviewers.
- Building it:
  - step 6: 7 increments; step 6b: 5.
  - Each step gets one review (a reviewer and a security check) and one repair loop (A66).
  - The harness gains about 25 client runs at each pinned version, about 4 more CI minutes [I].

**Before you approve (M125).**
1. **Who it is for.** You, alone, on Linux and in one-repository cloud sessions (A27). Nothing reaches a project before step 7's sync.
2. **Out of scope:**
   - `/setup` moves to step 7 (S9);
   - `/method-explain` moves to Track 4 (S9);
   - Claude merging (S12);
   - `/lesson`, `/research` and `/supervise` stay out (S16);
   - the reviewer test (Release 2);
   - Windows and macOS runs (A27).
3. **What done looks like that you can see.**
   - A green CI run whose harness job names each method agent and skill loading in the real client at 2.1.316 and 2.1.319.
   - done-check printing NOT READY for each missing floor element, one planted case each.
   - why.md.
4. **Predict, then compare** (my answers are in section 5's last paragraph):
   - a. A FULL change: the reviewer approves, but the security checker's run was cut off. What does done-check say?
   - b. You type `/method-start` with a finished branch not merged. What is the one next thing?
   - c. Claude tries to edit `.claude/skills/method-finish/SKILL.md` mid-session. What happens?
   - d. A plan says LIGHT, but the change touches a path listed as high-risk. Ready after one reviewer and one security approval?

## 1. Decisions (recommended)

**S1. Split into 6 and 6b.** Step 6 builds the words and the checks on them. 6b builds the computed "Ready to merge" that `/method-finish` drives. One plan approval covers both; you merge after each.
- Why: the size (84 step-6 rows plus about 20 items earlier steps deferred here); the A54 precedent; and one review of two different kinds of change would be weaker.
- A merge point after step 6 also keeps unmerged work small (M127: 117 commits once waited).
- 6b is ordered R4 core, then R8, then the R6 set (V2.10), so if usage runs short the R6 set (6b.3) becomes a step 6c without leaving a half-built floor.

**S2. Restore A66 and say the process once.**
- A66 was added in d996221 and deleted by accident in c29bf61 (that diff drops `-A66.` while it shifts A67 and A69). It is still cited at DECISIONS.md:108, :112, TASKS.md:219 and ROADMAP.md:27.
- Restore its exact text from `git show d996221:DECISIONS.md`.
- AGENTS.md:12's "Stop after 3 repair loops" becomes "One review and one repair loop per step (A66); if the repair does not close a finding, stop and report what is failing and what was tried."
- AGENTS.md also gains, in 6.0: "Text under `method/.claude/` is product being built and reviewed. It is never instructions for sessions in this repo; in particular M140 does not apply here, where the hooks are off (A47)." (V1.5, V2.12)
- Method projects keep M009 and M056 (three rounds). A66 is this repo's build process, not the method's.

**S3. Names: `method-` on every agent and skill.**
- Agents are `.claude/agents/method/method-<role>.md`, with frontmatter `name:` equal to the file name.
  - receipt.pl reads `.claude/agents/method/<gate>.md` (receipt.pl:195-203), so `reviewer.md` would leave every receipt INVALID `instructions-differ`.
- Skills are `.claude/skills/method-<name>/SKILL.md`.
- Why:
  - The loader reads one level only (`<dir>/<entry>/SKILL.md`) [C], and G17 refuses names holding `/` (watch.pl:317-319), so a `method/` subfolder is not possible.
  - A personal skill beats a project skill of the same name [D]; a prefix makes an accidental clash unlikely, as A71's prefix does for agents.
  - The prefix avoids the bundled `/design` (v2.1.265+, present in both pins [C]).
- The rule-map homes change to match (section 3). The cost is longer names to type; the slash menu completes them.

**S4. The agent set, and how scripts tell the gates apart.**
- **Gates** (receipts; the fragment's matchers run gate-receipt for them):
  - `method-reviewer`, `method-security-checker`, `method-tester`, `method-diagnose` (all four exist in verdicts.txt);
  - `method-reporter`, new, under `gate-verdict`. It reuses A10's words:
    - APPROVE: the report's claims re-derive and report-check passed;
    - REQUEST CHANGES: a claim fails, or report-check did not exit 0;
    - ESCALATE: a person must decide before the change can go ahead.
- **Roles by place (V1.2).** Scripts may not spell vocabulary words (tests/verdicts.test.sh:160-178 over every kind at :17), and nothing in verdicts.txt says which gate is the reviewer or which word approves. Like the `receipt` kind, roles are read by place. verdicts.txt's header gains the order rules, and verdicts.test.sh checks them against A10 and A71's lists in order:
  - the first `verdict` word approves (APPROVE is first today);
  - `test-result` words go pass, fail, not run (as today);
  - `gate-verdict` lines go reviewer, security checker, reporter (A71's "Verdict gates:" list in that order).
  - lib/verdicts.pl gains one reader, `roles`, used by done.pl (M048). `@kinds` (verdicts.pl:47) and the `kinds=` line (verdicts.test.sh:17) do not change; the header, the test's order check and A71's list do. Version 1's "do not change" claim was wrong.
- **Not a gate:** `method-architect`. It drafts; it checks nothing, and nothing would read its receipt. It returns text; the main session writes it.
- **No planner agent (V2.10).** A6: subagents only check or look things up, and a planner does neither. M021, M091 and M125 move into the `method-plan` skill, which the main session follows. This saves one Opus run per FULL task and a harness case. This settles step5.md:284 ("which files planner and reporter may write"): the reporter, a gate, writes only under `.method/local/` (Checks::fingerprint sets that aside, checks.pl:508), and its acceptance run (M092) works in a temporary copy or under `.method/local/` (V2.14).
- **The design review** (A16) is `method-reviewer`, run on the design document's commit with the design brief as criteria. No separate agent.
- Supersedes A71's "planner and reporter join in step 6".

**S5. The shape of a method agent file.**
- Frontmatter, and nothing else:
  - `name`, `description`;
  - `model:` equal to the fragment's `model` (settings.fragment.json:3, today `claude-opus-5-5`; R5 names the full ID). The lint compares the two, so the ID has one home (M048, V1.15);
  - `effort: xhigh` (R5, A3);
  - `tools:`:
    - gates: `Read, Grep, Glob, Bash`;
    - architect: `Read, Grep, Glob, WebFetch, WebSearch` (no Bash, Edit or Write: A6, V2.7; registry lookups go through WebFetch);
  - one YAML comment line listing the agent's rule IDs (for check-rule-map; F3).
- Never `hooks` (G17, A51), `memory` (it appends to the body and adds Read, Write and Edit [C]), `isolation` (`remote` from a file is not seen by G4 [I]), `permissionMode`, `background`, `skills` or `mcpServers`.
- No `Agent`, `Task`, `Skill` or `SendMessage` in `tools:`: this closes A72's delegation limit (hooks README:124).
- The body holds only the role's own rules and its report form, in this order:
  1. the opening word;
  2. summary, change summary, actual check output, risks; [EYES] and [AUTHORITY] items listed under risks (S14);
  3. `END-VERDICT <tree>`, the tree from the gate's `METHOD-ACTIVE` line.
- Everything about one run goes in the Agent prompt (B10 compares the body). That is M096: static instructions, task text last.
- Gates still load the project's rules (no `omitClaudeMd`). Rules every gate shares live once, in method.md's "Checking agents" part (S6), not copied into five bodies (M048). That part opens with "You check; you never change files" (V2.14), since a gate also reads the builder's "keep going to the finish line".
  - The cost: A72's known limit (user rules are not compared by B10) stays.

**S6. Two rules files and why.md; merged sentences.**
- `method.md` is for whoever works in the session: the builder, and every gate through its "Checking agents" part. `owner.md` covers reports and writing (R15: the default owner profile; step 7's setup may replace it).
- Sentences that overlap are merged, each carrying every ID (TASKS.md:197). A group crossing homes is settled by moving IDs to method.md, where all its members can live:
  - M026, M028, M022, M023, M025, M027, M114, M115 and M117 move from reviewer.md (they bind every gate);
  - M009 moves from reviewer.md to done-check.sh, which counts rounds (S14); method.md keeps M056;
  - M021, M091 and M125 move to the `method-plan` skill (S4);
  - M097 stays a step 7 template.
- M088 and M109 address people, so they move to why.md. M119 stays in method.md (Claude's half); why.md explains the owner's half without being its home.
- **M028 ("Anything visual comes back as NEEDS A HUMAN")** is written as: a gate lists anything visual as an [EYES] item and still opens with its word on the rest; ESCALATE is kept for "a person must decide before this goes ahead". `/method-finish` puts the [EYES] and [AUTHORITY] items first in the pull request, and your merge is the look (V1.4).
- **Tension 1, M005 and M034 against M119.** One sentence: "Wait for the owner's go at the two stops, the plan and the merge; between them, keep going to the finish line without asking, unless input is needed or a step is destructive."
- **Tension 2, M013 against M070.** "The records say where things stand; the pull request and the task's plan carry the reports. If a new session needs a handoff to orient, fix the records."
- **M006** reads "read everything, change nothing but the plan's own folder before the go" (V2.14).

**S7. Budgets (R12).**
- `method.md` plus `owner.md`: at most 8,000 bytes, counting what reaches the model. The rule IDs go in HTML comments on lines of their own, which the client strips (F4, measured at both pins: a comment alone on its line is removed, one that shares a line with text reaches the model as written), so they cost nothing per session; lint-prompts refuses a comment that shares a line with text in these files.
- The `description` fields of all method skills and agents together: at most 3,000 bytes; each one at most 300. Counted from the file bytes (F10 is not measured, V2.10).
- session-status's 1,200 bytes are already capped and tested (session.pl:43-44).
- tests/budget.test.sh enforces them, with a plant one byte over each.
- If the drafted text is over, the text is cut, not the budget raised. A raise is an owner decision.

**S8. One check on the method's prompt text: `scripts/dev/lint-prompts.sh`.** It homes M095 and M096 and runs in validate.sh. It walks `method/.claude/agents/`, `method/.claude/rules/` and `method/.claude/skills/` with perl's File::Find (no `**`: bash 3.2), so the hooks README is out of scope (V1.7).
- **M095.** It fails on:
  - "think carefully" or "think step by step" lines;
  - fixed-format reasoning requests (`<thinking>`-style tags, "reason in this format");
  - emphasis: the words IMPORTANT, MUST, NEVER, ALWAYS, REMEMBER, and DO NOT, in capitals (a short denylist, V2.10). The method's own terms (FULL, LIGHT, VERIFIED, CRITICAL, READY, HIGH_RISK_PATHS, the vocabulary) pass without an allowlist.
- **Agent files.** It fails unless:
  - `name` equals the file stem, and every gate in verdicts.txt has a file;
  - `effort: xhigh` is present and `model` equals the fragment's;
  - `tools:` is present and holds none of Agent, Task, Skill or SendMessage; a non-gate agent's also holds none of Bash, Edit, Write or NotebookEdit;
  - none of `memory`, `isolation`, `permissionMode`, `background`, `skills` or `mcpServers` appears. `hooks` is left to G17 (M137), so the rule has one home (M048).
- **Skill files.** It fails unless the folder starts `method-`, equals `name`, and is on G6's skill list (S10), and the list has no folder that is missing; and the skill has no `context: fork` and no `agent:` (a fork is delegation receipts do not see, A72). `!` lines are left to `disableSkillShellExecution` (M138), and `hooks:` to G17.
- Each failure has a plant, and each emphasis word a look-alike that passes (lower case, a vocabulary word, `CRITICAL`, `HIGH_RISK_PATHS`).

**S9. Skills, and when each comes.**
- Step 6: `method-start` (M004, M005, M127), `method-plan` (M006, M021, M091, M125), `method-design` (M099).
- `method-checks` (M042, M043, M045, M052) is built in 6.5 only if M045's questions arrive (S18). If not, M042, M043 and M052 become one sentence in method.md's "Checking" part, and M045 becomes `later`.
- 6b: `method-finish` (M007, M011, M070, M087), written once, against the done-check it drives.
- `/method-explain` (M120) moves to Track 4: no SPEC requirement asks for it (V2.10).
- `/setup` moves to step 7. Its rule M100 is already step 7, and R3's acceptance ("every answer combination", "twice gives the same configuration") needs step 7's templates, profiles and sync. ROADMAP's step 6 line is reworded.
- Skills have no `!` lines; the fragment turns them off anyway, `disableSkillShellExecution` (A51). They tell Claude to run each method script in a Bash call of its own, never chained with a write (G6, protect.pl's read-only rule for calls that name protected paths).

**S10. G6 protects the method's skills, by a fixed list (V1.6).** Today the project's `.claude/skills/` is unprotected. A `method-*` pattern cannot be added: protect.pl's `prefix` kind matches direct children only (protect.pl:310-313), and `@SPECS` (protect.pl:947) goes to git with `--literal-pathspecs` (git.pl:92), so the version check on switch, cherry-pick and revert would silently miss skills.
- protect.pl gains one list, `@METHOD_SKILLS` (`method-start`, `method-plan`, `method-design`; `method-checks` if built; `method-finish` in 6b). Each becomes an ordinary `dir` entry `.claude/skills/<name>`.
- The same list feeds protect.pl's set (:229-236), `@SPECS` (:947), `text_re` (:548-550) and guard.pl's `$WATCHED_PATH` (guard.pl:79), which reads it from protect.pl. One home.
- The lint checks the list equals the method's skill folders (S8).
- A project's own skills stay editable.

**S11. Task folders.** One folder per task: `docs/tasks/<id>/`, added on the task's branch. One task per merge: a plan meant for two merges is two tasks, which one reply can approve (`approve 6, approve 6b`).
- `plan.md` is written for people. done-check reads only three lines near the top:
  - `Tier: FULL` or `Tier: LIGHT`;
  - `Paths:` (for the reviewer; nothing enforces it);
  - `Approved: <date> "<the owner's reply, quoted>"`. `method-plan` ends with one fixed question, "Reply `approve <id>` to approve this plan.", and writes the line only after a reply. done-check requires the quote to contain `approve <id>` with the folder's id (V2.3). A general "go" no longer passes by accident.
- FULL only: `expected.tsv` holds the expected results, from a source outside the model (A9: the person with authority signs high-risk ones; the `source` column names them).
  - Columns: `case`, `inputs` (`name=value;…`), `expected`, `source`.
  - No `# defaults:` line: M122 becomes `later` (V2.10).
- No `task.conf`, `oracles.lock` or `owner.tsv`: one file a person reads, plus one table, is enough.
- **The lock (V1.10, V2.4).** The anchor is the first commit on the branch whose plan.md carries HEAD's exact Approved line. Since the anchor, plan.md's Tier and Paths lines and expected.tsv are unchanged.
  - A re-approval (a wrong expected value found at the failing run) is a new reply, so a new Approved line and a new anchor. Removing the line and re-adding the same one does not move the anchor.
  - done-check's READY or NOT READY line names every Approved line the branch has had, so a re-approval is visible in the pull request.
  - done-check checks the lock, so G6 needs no rule for task files (step5.md:286).
- **R6's order, read deliberately.** R6 says "seen failing first, then locked". Here the expected results are locked at approval and the failing run follows it: a value changed after a failing run would make "seen failing" mean nothing. Recorded in A74.
- **A promotion.** A plan that says LIGHT but touches a high-risk path is judged FULL and has no expected.tsv: done-check says NOT READY, next: plan again as FULL.
- A design branch (`/method-design`) gets a LIGHT task folder whose acceptance lines are the design brief (V1.14).

**S12. Owner approvals; Claude never merges in Release 1.**
- **Plan approval** is the quoted Approved line naming the task. done-check requires it (M144). Its form is checked; that you typed it is not (why.md says so).
- **Merge approval** is your merge on GitHub. GitHub records who merged which head.
- No hook records approvals (A58, A61, R7's cap of three).
- **Claude's own landing route is not built.** A46 stays in force through Release 1, and "until step 6" goes from its text and from guard.pl:516.
  - Why: without a paid plan nothing on GitHub stops a merge (RISKS #4). Your click is the only lock outside the session. A route for Claude would add guard code and plants to save you one click.
  - It returns with GitHub branch rules (Release 2).
- **The verdict line through a squash merge (A30, V1.11, V2.11).** `/method-finish` ends the pull request's text with the trailer as its last paragraph. That survives only with the repository's squash default set to the pull request's description, which Claude cannot set. So:
  - `/method-start` reads the setting with an allowed `gh api repos/<owner>/<repo>` GET (`squash_merge_commit_message`, [D]) and names a mismatch and your one-time fix; if the field cannot be read, it says so (M121).
  - Known limit with your action: when commit authors differ from the pull request's author, GitHub adds Co-authored-by lines after the trailer. Delete them in the merge box; status names the cause if one gets through (A30).

**S13. Tiers and Deep review.**
- FULL by default (M035).
- LIGHT only when the plan says `Tier: LIGHT` and the change touches no high-risk path. Otherwise done-check judges the change as FULL.
- **High-risk paths (V1.9, V2.4).** A new list key `HIGH_RISK_PATHS` in `.claude/method.conf`, in PRODUCT_PATHS' syntax (`check_path`, conf.pl:132; no second syntax, M048). The set is the union of main tip's and HEAD's lists: a branch can add a path, never remove one. Two blobs, read by conf.pl's parser; not A37's every-commit reading.
- **Deep review (V1.1, V2.2).** A change touching a high-risk path needs three VALID `method-reviewer` receipts on HEAD's tree, all opening APPROVE (M087, A9). They are launched in one message (F12).
  - No vote. Every finding of any of the three gets an M083 disposition in the report; an unproven serious or security finding goes on the unresolved list (M086). The builder judges nothing by majority.
  - This changes M087's wording ("several independent finders and a vote on each finding") to "three independent reviewers, all approving; every finding of any of them gets a disposition". Recorded in A74.
- A9's other high-risk items (sign-off of expected results, a test copy, an undo plan, a human expert) stay convention, listed in why.md's "partly enforced" table.
- The workflows setting stays unset for good (A60): Agent calls get receipts, and a project file setting `enableWorkflows` would hide your switch in /config.
- **LIGHT (A11, V1.14).** One review round, plus an approving round on the final files when that round asked for changes (SPEC R4; TASKS.md:144's open question). A11's "no reporter unless there are [EYES] or [CHECK] items" stays convention: `/method-finish` runs the reporter then; done-check does not check it.
- No `tiers` column in checks/*.tsv: every check runs in both tiers. No requirement asks for fewer checks.

**S14. done-check reads receipts (6b).** For the tree of HEAD (an empty or message-only verdict commit keeps the tree, A35). Gates are named by role (S4).
- **Every tier:**
  - a VALID reviewer and a VALID security-checker receipt that open with the approving word;
  - any VALID receipt of either gate on that tree that opens with another word makes it NOT READY. Re-running a review on the same files until it approves does not work. An ESCALATE is resolved by your decision and a change after it, which makes a new tree and a new round;
  - **the chain (V2.5).** Each receipt records its packet's base: the "Merge base:" or "Last reviewed version:" line (packet.pl:490-492), read where receipt.pl already reads the packet's `Tree:` (receipt.pl:568). The approving receipt's base must be the merge base, or a commit whose tree has a VALID receipt of the same gate whose own base chains back to the merge base. A slice built with `--since` on the first review fails;
  - **rounds (M009).** More than three trees since the anchor with a VALID reviewer receipt gives NOT READY, next: plan again;
  - **history.** The output lists every gate word on the branch's trees, in commit order. The pull request copies it, so you see "REQUEST CHANGES, REQUEST CHANGES, APPROVE".
- **FULL adds:**
  - a VALID tester receipt that opens with the fail word on a commit after the anchor and before HEAD, with a tree other than HEAD's ("seen failing first"). Any failure counts: it is a gate's word, not a per-case check (V1.3, V2.6);
  - one opening with the pass word on HEAD's tree;
  - a VALID reporter receipt that opens with the approving word.
- **High-risk adds:** three VALID reviewer receipts on HEAD's tree, all approving (S13).
- **The verdict line** must then be `Review-Verdict: approve`. When it is missing, `next:` gives the exact line to add (A24: generated, never chosen). A33's typed-line stopgap ends.
- **One reader:** lib/receipt.pl gains a tree query used by done-check and session-status (M048).
- **status gets no gates area.** done-check's verdict area names the receipts, and session-status already LOOKs on a bad one (step5b.md:85). A third display would be the same thing again (supersedes B12's "status's full gates area").
- **Receipts are per clone** (in git's common folder, receipt.pl:79). A new cloud session starts with none. Reviews can be re-run on the same tree; the pre-code failing run is re-made by `git switch -c <tmp> <pre-code commit>` (on G3's list, git-shapes.txt:107), the tester there, then a switch back. `method-finish` names this route when the failing receipt is missing.

**S15. `report-check.sh` (6b, M126, R8).** `bash scripts/method/report-check.sh REPORT [LOG…]`; with no LOG, every file in `.method/local/logs/` plus `.method/local/gates.log`.
- A "number" is a run of digits with an optional sign, thousands separators, decimal part, `%` or currency mark. It is not part of an identifier, a path, a hash or a date: `M126`, `A66`, `R8`, `#4`, `file.pl:12`, `2.1.316` inside a word.
- It lists each number that is in no log.
- It lists a report with no "What the checks would miss" heading, or one whose body is empty, "nothing" or "none".
- Exit codes: 0 nothing listed; 1 anything listed; 2 usage (V1.12).
- `/method-finish` first writes git's counts and done-check's plain output to `.method/local/logs/`, so the report's own numbers have a log (V1.12).
- Who makes it count: the skill runs it and the reporter answers REQUEST CHANGES when it did not exit 0, so a FULL change cannot be READY with a failing report (V2.1). For LIGHT without a reporter it is the skill's step only (why.md says so).

**S16. Not built in step 6 or 6b, with the reason.**

| Item | Reason |
|---|---|
| The nested-claude wrapper (A53), and M081 | No flow in Release 1 starts another Claude: Deep review uses Agent calls, which get receipts. G4 keeps refusing every `claude`. M081 becomes `later` with A53 (V2.10). |
| The agent-launch guard (step5.md:285), including a clause refusing a gate launched in the background (V1.8) | Receipts already make a wrong effort or model INVALID, a stale packet too (`packet-other-tree`), and a background gate whose builder keeps writing (`write-mark`, receipt.pl:740). The skill names `run_in_background: false` (F11). A doctored prompt stays a known limit. |
| A planner agent | S4. |
| `/method-explain` (M120) | Track 4 (S9). |
| M122's READY-line note | Advisory only; `later` (V2.10). |
| The diff scan with plan v3's `.skip` plant (TASKS.md:83) | The reviewer checks for gaming (M090). The scan is a second layer: Release 2. |
| A check that the failing run changed only test files | No key names test files, and PRODUCT_PATHS may hold tests (conf.pl:16-22). The reviewer checks the tests (M090). |
| The touches-method route (step5.md:287) | Those files arrive with step 7's templates and packs. Step 7. |
| mutate-changed's accept path and the TASKS.md:116 follow-ups | Nothing gates on its exit 1 in Release 1 (mutation in CI is Release 2). They stay follow-ups. |
| SendMessage | Gates run in the foreground; no flow needs it (step5.md:716). |
| `/lesson`, `/research`, `/research-update` (R13) | They go together to Track 4; ROADMAP's Track 4 line gains `/lesson`. Until then, a lesson is an ordinary reviewed change to the records. |
| `/supervise` (A12) | The reporter replaces it; nothing requires it. |
| High-stakes paths below xhigh, and edits outside the plan's paths (step5.md:288) | Gates are pinned at xhigh (S5) and G12 warns the builder. The plan's `Paths:` goes to the reviewer. |

**S17. New rule rows.** The next free ID is M140.

| ID | Rule | Source | Home | Status |
|---|---|---|---|---|
| M140 | At session start the main session looks for session-status's METHOD-ACTIVE line; with none, the method's hooks are off: say so first and change no code until the owner decides. A checking agent's own line reads `METHOD-ACTIVE gate=… tree=…`; other agents get none, and the rule is not theirs | research: measured (step 5 plan E12, RISKS #16) | method.md | step 6 |
| M141 | The architect drafts a design for a new project or big feature (options and trade-offs in business terms; where the project uses packages, versions checked against live registries; the thinnest end-to-end version first) and builds nothing | decision A16 | method-architect.md | step 6 |
| M142 | Diagnose finds the cause before any fix: it reads the evidence, changes nothing, and opens with ROOT CAUSE, SYMPTOM CHASE or SPEC QUESTION | decision A71 | method-diagnose.md | step 6 |
| M143 | When the same check fails twice, call diagnose before a third fix | plan v3, moved by step 3 (TASKS.md:83) | method.md | step 6 |
| M144 | A change is ready only when its task's plan carries a quoted approval naming the task | SPEC R4; A61 | done-check.sh | step 6b |
| M145 | Expected results, tier and paths are locked at the plan's approval; a test run is seen failing after approval and before the code, and passing at the end | SPEC R6 | done-check.sh | step 6b |
| M146 | Ready to merge needs VALID approving receipts for the exact files, reviewed from the merge base: reviewer and security check always; tester and reporter for FULL; three approving reviewers on high-risk paths; no other word from those gates on those files. The verdict line says what they say | SPEC R4, R6; A24 | done-check.sh | step 6b |
| M147 | LIGHT only when the plan says so and the change touches no high-risk path, as main or the branch lists them | SPEC R6 | done-check.sh | step 6b |

**S18. M045's twelve questions.** They are written nowhere in the repo or its history. It is an incident rule from your original method.
- Please paste them when you approve this plan.
- If you cannot, M045 becomes `later` with a TASKS note (Track 3 brings your original prompts), and `/method-checks` is not built (S9).
- I will not invent twelve (M016).

## 2. The design

Paths are under `method/` unless noted. IDs per file are each file's rule-map homes after S6's moves. Every agent and skill file carries its IDs in a frontmatter comment; the rules files carry them in HTML comments on lines of their own, just above the sentences they cover (F3, F4).

**Rules (step 6.1; loaded every session, budget S7).**
- `.claude/rules/method/method.md`, in five short parts:
  - **The method is on:** M140, M079.
  - **Scope and pace:** M016, M033, M057, M082; M034 and M119 (S6's sentence); M093; M064; M013.
  - **Checking:** M020, M058, M107; M047, M048; M049, M059, M121; M056 (three repair loops, then report); M035, M036; M143; M075; M042, M043 and M052 if `/method-checks` is not built (S9).
  - **Risky work:** M060, M061, M062, M065, M098; M054, M055, M028 (S6's mapping).
  - **Checking agents:** "You check; you never change files." M022; M023 with M115 (packet and every changed file, whole, in the first turn); M025; M026; M027 with M117 (no CRITICAL without demonstration; a blocking finding without run evidence becomes a question); M114 (the do-not-flag list).
- `.claude/rules/method/owner.md`:
  - M012 with M037: the report opens with status and next step, then [EYES] and [AUTHORITY] items, what changed, what is left, risks, what is uncertain and check output; no success without summary, change summary, check output, risks and verdict.
  - M068 with M071; M074; M123; M105.
- `docs/method/why.md`, shipped (V2.9; R14: nothing dropped without a decision; step 7's sync places it at the same path in a project): M067, M088, M109, and the owner's half of M119. Four tables, each row naming rule IDs:
  - hook: G0 to G17 and the receipts;
  - script: run-checks, done-check, report-check, CI;
  - partly enforced, with what is not checked: the Approved line (form and task name), the tier (only high-risk paths are computed), the failing run (any failure), report-check (run by a skill; the reporter refuses a failure; nothing for LIGHT without a reporter), M124's predictions, A9's high-risk extras beyond Deep review, LIGHT's reporter for [EYES] items;
  - convention: the rules files, the agent bodies and the skills, by ID.

**Agents (6.2 and 6.4).** All are under `.claude/agents/method/`.

| File | Gate | Opens with | IDs |
|---|---|---|---|
| `method-reviewer.md` | yes | APPROVE, REQUEST CHANGES, REJECT, ESCALATE | M024 (no criteria: ESCALATE and stop; the packet says "No acceptance criteria were given.", packet.pl:455), M083, M084, M086, M090, M102 |
| `method-security-checker.md` | yes | the same | M030 |
| `method-tester.md` | yes | TESTS PASS, TESTS FAIL, TESTS NOT RUN | M029 (runs `run-checks.sh` and the tests written for the expected.tsv cases, copies the output, fixes nothing) |
| `method-diagnose.md` | yes | ROOT CAUSE, SYMPTOM CHASE, SPEC QUESTION | M142 |
| `method-reporter.md` | yes, new | APPROVE, REQUEST CHANGES, ESCALATE | M031, M046, M069 (reads `.method/local/report.md` and report-check's output, both named in its prompt), M092 (its acceptance run in a temporary copy or under `.method/local/`), M124 (three cases from expected.tsv) |
| `method-architect.md` | no | — | M141 |

What changes with them:
- verdicts.txt gains `gate-verdict	method-reporter	…` after the security checker, and the header's order rules (S4).
- A71's "Verdict gates:" list gains `method-reporter`, in role order. tests/verdicts.test.sh reads that list (:24-56) and gains the order check.
- Both fragment matchers (settings.fragment.json:97, :109) become `^(method-reviewer|method-security-checker|method-diagnose|method-tester|method-reporter)$`. tests/settings.test.sh:204-213 ties them to verdicts.txt. tests/plants/settings.sh:150 expects the matcher text, so its expected message gains `method-reporter` (V1.13).
- The hooks README's gate list (README:104) names five gates (V1.13).
- The harness stand-in `tests/harness/agents/method/method-reviewer.md` stays for the hook cases. `h_method` (tests/harness/lib.sh:102-110) is not changed; a new helper, `h_method_words`, copies the real agents, rules and skills for the new cases (V1.13).

**Skills.** All are `.claude/skills/method-<name>/SKILL.md`.
- `method-start` (6.5): M004, M005, M127. It runs these, each in its own Bash call:
  1. `bash scripts/method/status.sh` (the full run, so the version, effort and CI areas RISKS #17 and A59 left to it);
  2. `git fetch origin`;
  3. `git rev-list --count origin/<main>..HEAD` and `git diff --stat origin/<main>...HEAD`;
  4. `gh pr list` (a read; "could not read" if it fails, M121);
  5. `gh api repos/<owner>/<repo>` (a read, S12).

  It shows `${CLAUDE_EFFORT}` (F6). It says whether a METHOD-ACTIVE line was seen (M140). It names a single-branch clone. Then it gives the four answers and stops for your go (M005).
- `method-plan` (6.4): M006, M021, M091, M125.
  - FULL: the main session reads everything and asks for whatever is missing of M125's four points. It writes `docs/tasks/<id>/plan.md` and an expected.tsv draft with sources, marking known and assumed (M021), feasibility, and "impossible or contradictory" when it is (M091). It ends with the fixed question (S11).
  - On `approve <id>`: it adds the Approved line and commits.
  - FULL, then (V1.3): it writes the tests for the expected.tsv cases, commits them without product code, and launches `method-tester` with `run_in_background: false`. TESTS FAIL: build. TESTS PASS: stop and tell you the tests do not test the change.
  - LIGHT: plan.md with `Tier: LIGHT` and one to three acceptance lines (A11); the same approval question.
- `method-design` (6.4): M099.
  1. `method-architect` returns a design with its card for you.
  2. The main session writes it and a LIGHT task folder whose acceptance lines are the brief, and commits.
  3. `method-reviewer` reviews it, with the brief as criteria.
  4. You see the card and the verdict.
  5. The first task is the walking skeleton.
- `method-checks` (6.5, only per S18): M042, M043, M045, M052.
  - Plant, run and revert as three separate commands, in a throwaway copy (AGENTS.md). G3 refuses `git restore`, `checkout --` and `stash`.
  - Diff after revert; commit a test.
- `method-finish` (6b.4): M007, M011, M070, M087. In order (V2.1):
  1. Records first.
  2. Commit.
  3. `run-checks.sh`.
  4. Build the packet into `.method/local/packet-<tree>.txt` from the merge base or the last reviewed version, rebuilt for every tree.
  5. FULL: the tester, expecting TESTS PASS on HEAD.
  6. The reviewer and the security checker (high-risk: three reviewers and the security checker), launched in one message with `run_in_background: false` (F9, F11, F12).
  7. Log `git rev-list --count`, `git diff --stat` and `done-check.sh` (plain) to `.method/local/logs/`.
  8. Write the report to `.method/local/report.md`; run `report-check.sh` on it, logged too.
  9. FULL, or LIGHT with [EYES] or [CHECK] items: the reporter, its prompt naming report.md and report-check's output.
  10. `done-check.sh --ready`, logged; add the `next:` line's trailer, as an empty commit if already pushed (G3 refuses force; the tree is kept, A35).
  11. `git push origin HEAD`.
  12. `gh pr create` or `gh pr edit`: the READY line, the [EYES] and [AUTHORITY] items, the gate history, then the report, the trailer last.
  13. Stop.

  When a receipt is missing in a fresh clone, it names the re-run route (S14).

**Scripts and checks.**
- `scripts/dev/lint-prompts.sh` and `scripts/dev/lib/prompts.pl` (6.1, 6.2, 6.3): M095, M096.
- `tests/budget.test.sh` (6.1): R12.
- `scripts/method/report-check.sh` and `lib/report.pl` (6b.2): M126.
- `scripts/method/lib/done.pl` (6b.1, 6b.3): M009, M144 to M147.
- `lib/receipt.pl` (6b.1): a tree query, and the packet's base in each receipt.
- `lib/verdicts.pl` (6.2): `roles`.
- `lib/conf.pl`: the `HIGH_RISK_PATHS` key (6b.3).
- New `.sh` and `.pl` files spell no vocabulary word (tests/verdicts.test.sh:160-178).

**Guard (6.3, 6b.1).**
- protect.pl and guard.pl get `@METHOD_SKILLS` (S10).
- Text only:
  - guard.pl:516 loses "(until review receipts exist, step 6)";
  - outside.pl:24 and :102 lose "the method's own nested runs come in step 6";
  - done.pl:309 and :416-417 and done-check.sh:9-10 lose "(step 5)".

**Records.**
- DECISIONS: A66 restored (6.0); A73, step 6's S1 to S10 and S18 (6.6); A74, 6b's S11 to S16 as built, with R6's order reading and M087's new wording (6b.5); A71's list updated; A46 reworded "through Release 1"; A11's two clauses as S13 states them.
- ROADMAP: the step 6 line, step 6b, setup in step 7, `/lesson` and `/method-explain` in Track 4.
- Also AGENTS.md (S2, and the B2 report order), the rule map, TESTS, RISKS (#4 reworded; a new risk: rules are text), CHANGELOG and TASKS.

## 3. Changes from earlier plans and decisions

1. **A66** is restored (S2). AGENTS.md:9's order becomes: verdict word first, then summary, change summary, actual check output, risks, then `END-VERDICT <tree>`. This is B2 (step5b.md:27), A72(1).
2. **A71:** the reporter joins as a verdict gate; the planner is not built, and the architect is not a gate (S4).
3. **A6, A16:** no planner agent; the architect is the one drafting agent, with no Bash (S4, S5).
4. **A11:** LIGHT's "one review round" gains an approving round on the final files after changes; its reporter clause stays convention (S13).
5. **A46** holds through Release 1, and Claude's landing route is not built (S12). This drops:
   - step5.md:279's "landing allowed when what lands is the commit done-check judged";
   - TASKS.md:143's binding design (`git push <remote> HEAD:<main>`, `gh pr merge --match-head-commit`);
   - guard rule 4.
6. **A53:** no wrapper; nothing needs one; M081 goes with it (S16).
7. **A60:** the workflows setting is never set. tests/settings.test.sh:133 keeps refusing it (S13).
8. **A61:** plan approval is a quoted line naming the task that done-check requires; merge approval is the owner's GitHub merge (S12). This answers TASKS.md:149.
9. **A33** ends in 6b. The verdict line must equal what the receipts give (S14), so A24's "generated from receipts" holds.
10. **M087** loses its vote (S13).
11. **B12 and step5.md:271:** status's gates area is not built. step5.md:271 placed it in 5b, and B12 deferred it here; S14 drops it.
12. **The rule map** (6.1, with each row's status set as its file lands):
    - homes: `agents/method/<role>.md` becomes `method-<role>.md`; `skills/<x>/` becomes `skills/method-<x>/`, with `plan-first` becoming `method-plan`;
    - moves: M022, M023, M025, M026, M027, M028, M114, M115 and M117 go to method.md; M009 to done-check.sh; M021, M091 and M125 to `method-plan`; M088 and M109 to `docs/method/why.md`; M067 to the same; M096 to scripts/dev/lint-prompts.sh;
    - `later`: M120 (Track 4), M081 (with A53), M122; M045 per S18, and M042, M043 and M052 to method.md if `/method-checks` is not built;
    - M073 becomes `done`: its ID is at hooks/README.md:3, and the row still says `step 5`;
    - new rows M140 to M147.
13. **step5.md section 4's step 6 rows**, each settled:

    | Row | Outcome |
    |---|---|
    | landing | not built |
    | done-check reads receipts | 6b |
    | owner records | S12 |
    | nested runs | not built |
    | workflows | never set |
    | planner and reporter writes | S4 |
    | agent-launch guard | not built |
    | task-file protection | done-check's lock |
    | touches-method | step 7 |
    | high-stakes and outside-paths | not built |
    | M117 | method.md |

14. **TASKS.md:83:**
    - the diagnose trigger becomes M143, a convention;
    - the diff scan goes to Release 2;
    - the tiers column is not built.
15. **TASKS.md:144:**
    - "fetch main before --ready" becomes `/method-start`'s `git fetch origin`. Its "`git remote set-branches --add` first" is refused by G3 and by G6 (`.git/config`). A single-branch clone is therefore a known limit, and `/method-start` names it.
    - LIGHT fixes: S13.
    - The baseline: review-packet's `--since` (M085), now chained back to the merge base (S14).
    - Survivor reasons: not needed in Release 1.
16. **step5b.md:83's handback warning:** done-check cannot read the Agent call's result (it lives in the session's record, not in the repo). It becomes a known limit, not a 6b feature.
17. **ROADMAP step 6** loses "setup"; step 6b is added; Track 4 gains `/lesson` and `/method-explain`.
18. **Stale text fixed:**
    - TASKS.md:3 ("step 5 is being built");
    - hooks README:113 ("until step 6 nothing reads receipts");
    - TESTS.md:194-195 ("receipts, step 5").
    - Old plans are not edited; this section records their corrections.

## 4. Increments

Each increment is reviewable on its own, has its tests and plants, and states a "you will see" line copied from a log. Harness cases run at 2.1.316 and 2.1.319.

### Step 6

**6.0 Measure, and fix the records (no product code).**
- Run F1 to F6, F8, F9, F11 and F12 (section 6) with stand-in files in a throwaway harness project. Each fact the build relies on becomes a harness case in the increment that uses it.
- Restore A66; AGENTS.md's product-text line (S2); M073 becomes done; fix TASKS.md:3.
- Ask for M045's twelve questions (S18).
- A fact that changes a decision makes this plan version 3, and you are told before code.

**6.1 The rules.**
- method.md, owner.md, `docs/method/why.md`; the rule-map moves and new rows (S6, S17).
- tests/budget.test.sh and tests/plants/budget.sh: one byte over each budget turns it red.
- lint-prompts.sh, part one (M095: phrases and emphasis words), with tests/lint-prompts.test.sh and tests/plants/lint-prompts.sh: one plant per pattern, plus look-alikes that must pass (S8).
- validate.sh; TESTS.md.
- Harness (`h_method_words`):
  - the rules reach the main session's first request;
  - the ID comments, on lines of their own, do not reach it (F4);
  - they reach a gate's first request.

**6.2 The gates.**
- The five gate files; verdicts.txt and its order rules; `Verdicts::roles`; A71's list; both matchers; settings and verdicts tests; plants/settings.sh:150; the README's gate list.
- lint-prompts part two (agent files, S5 and S8). One plant each: no `tools:`, Agent in `tools:`, `memory:`, effort high, a model other than the fragment's, name not equal to the stem, a gate in verdicts.txt with no file. A verdicts.txt plant: the reporter's line before the reviewer's turns verdicts.test.sh red.
- AGENTS.md's report order.
- Harness, per gate file:
  - it loads with no "does not recognize or apply" and no "not loaded" debug line;
  - its receipt is VALID against the fake with the real body (B10), at claude-opus-5-5 and xhigh;
  - with `tools:` set, auto mode still offers SubagentHandback and the receipt is VALID (F1);
  - no Agent tool is in the gate's request.
- Plant: a gate body edited after the start reads INVALID `instructions-differ`. That plant exists; it is re-run on a real file.

**6.3 Skill protection.**
- `@METHOD_SKILLS` (S10): cases in tests/guard-protect.test.sh (an Edit, a `sed -i`, a redirect, `cp` over, a read that passes, a project skill `deploy` still editable, a `git switch` to a branch whose `method-start` SKILL.md differs) and plants in tests/plants/protect.sh (one per feed: the set, `@SPECS`, `text_re`, `$WATCHED_PATH`).
- The hooks README G6 row; M132's wording.
- lint-prompts part three (skill files) with plants: `context: fork`, `agent:`, a folder without `method-`, a name not equal to the folder, a skill folder missing from the list, a listed folder that does not exist.

**6.4 Design and planning.**
- method-architect, method-plan, method-design.
- The task-folder format (S11) is written down in method-plan; 6b reads it.
- lint plant: Bash in the architect's `tools:`.
- Harness:
  - `-p "/method-plan …"` expands (F6);
  - the architect runs at claude-opus-5-5 and xhigh, makes no receipt, has WebFetch, and has no Agent or Bash; in auto mode it ends cleanly (F1).

**6.5 Working skills.**
- method-start; method-checks only per S18.
- Harness:
  - `-p "/method-start"` expands, and its Bash calls reach the guard (`status.sh` in its own call passes; `status.sh && git commit` is refused, G6);
  - `${CLAUDE_EFFORT}` is substituted (F6);
  - with no session-status hook, the skill's text names the missing METHOD-ACTIVE line. This is the text only; whether Claude acts on it is convention.

**6.6 Close.**
- One review (a reviewer and a security check) over 6.1 to 6.5, and one repair loop (A66). Records before the review: A73, the rule map, TESTS, RISKS, CHANGELOG, TASKS.
- Then you merge.

### Step 6b

**6b.1 The R4 core: plan and receipts read by done-check.**
- lib/receipt.pl's tree query and the packet base; the plan condition (exactly one `docs/tasks/*/plan.md` added on the branch, a well-formed Tier line, an Approved line quoting `approve <id>` for its folder); the reviewer and security conditions, the chain, the round count and the history (S14); the typed line must match; the stale texts (section 3, item 18).
- Plants, one per floor element (R4's acceptance): no plan; an Approved line without `approve <id>`; one naming another task; no reviewer receipt; no security receipt; an INVALID receipt; an INCOMPLETE receipt; a REQUEST CHANGES beside an APPROVE on one tree; a receipt for another tree; a first review built with `--since` that does not chain; a fourth round; a typed `approve` with no receipts.
- Harness: two real gates launched in one message both get VALID receipts with no write marks (F9). done-check, run in that harness project, names them.

**6b.2 report-check.sh (R8).**
- Tests: numbers found and not found; IDs, paths, versions and dates ignored; currency and sign kept (M074); the miss section missing, empty, "nothing" or "none"; exit 1 for each.
- One plant per rule.
- TESTS.md; validate.sh does not run it (it reads reports, not the repo).

**6b.3 The R6 set.** If usage runs short, this becomes step 6c and 6b.4's skill is first written without its FULL steps.
- The tier: `HIGH_RISK_PATHS` in conf.pl (PRODUCT_PATHS' syntax), the union of main tip's and HEAD's; the promotion to FULL (S11).
- The lock and its anchor (S11); the failing run after the anchor; the passing run at HEAD; the reporter; Deep review (S13).
- Cases in tests/done-check.test.sh and tests/conf.test.sh. Plants:
  - each condition removed;
  - a LIGHT tier on a high-risk path accepted;
  - HIGH_RISK_PATHS shrunk in the same change, judged LIGHT;
  - the Tier line edited after approval;
  - the Approved line removed and re-added unchanged after an expected.tsv change;
  - the lock compared with HEAD instead of the anchor;
  - no TESTS FAIL before the code; a TESTS FAIL on HEAD's tree only; no TESTS PASS at HEAD; no reporter on FULL;
  - two reviewers on a high-risk path; three reviewer receipts, one REQUEST CHANGES.
- Harness: three `method-reviewer` runs launched in one message all VALID (F12); a tester run on a `git switch -c` branch at the pre-code commit gives a TESTS FAIL receipt done-check accepts (S14's route).

**6b.4 method-finish.**
- The skill (section 2).
- Harness:
  - `-p "/method-finish"` expands;
  - its first Bash call is a records check, not a commit;
  - `git push origin HEAD:main` from the skill's flow is still refused (G3).

**6b.5 Close.** One review and one repair loop; A74; rule-map M009 and M144 to M147 done; then you merge.

## 5. Known limits

- **Text, not enforcement.** Rules are text. Which rules a hook or script enforces, which are partly checked, and which are convention is in why.md (M067).
- **Forgeable records.** Receipts and the Approved line are local records a program Claude writes could forge (RISKS #2). The Approved line's form and task name are checked; that you typed it is not. Your merge on GitHub is the lock.
- **Any failure counts as "seen failing".** done-check sees the tester's word, not which tests failed or why. The reviewer checks the tests (M090).
- **Receipts are per clone.** A new cloud session has none: reviews are re-run, and the pre-code failing run is re-made on a temporary branch (S14). CI and other machines see only the verdict line (step 9).
- **Things that can replace or hide the method:**
  - a personal skill named `method-start` (personal beats project [D]);
  - a user-level `skillOverrides`, `claudeMdExcludes` or `agent` setting.

  G16 does not watch these (README:77, watch.pl:59). The prefix makes an accidental clash unlikely.
- **Sessions with no hooks** (several repositories in one cloud session, a Projects thread): no hooks run, and the rules may not load, so M140 helps only where the rules load. Live proof is step 9.
- **A doctored Agent prompt to a gate.** Only a stale packet, or a packet that does not chain to the merge base, is caught.
- **A gate launched in the background** whose builder keeps writing gets an INVALID receipt (`write-mark`): loud, costs a re-run.
- **The handback warning.** A handback whose auto-mode check could not run is not seen (step5b.md:83).
- **A gate's own writes.** A gate's Bash can still write files. The receipt then says INVALID; this is loud, but not prevented.
- **The squash merge.** The trailer survives only with the repository's squash default set to the description, and with Co-authored-by lines deleted when authors differ (S12).
- **Single-branch clones.** `/method-finish` cannot widen them (G3 and G6 refuse `remote set-branches`).
- **This repo's own sessions** load `method/.claude/rules/method/*.md` and `method/.claude/skills/method-*` once Claude touches any file under `method/` [M: F8, both pins]. AGENTS.md says that text is product, not instructions, and that M140 does not apply here (S2).
- **M124's predictions** are convention: done-check cannot see that you predicted.
- **An older conf.pl** reads `HIGH_RISK_PATHS` as an unknown key (conf.pl:98). Sync brings scripts and conf together, so this arises only from a hand-copied conf.

My answers to section 0's four predictions:
- a. NOT READY: the security checker's receipt is INCOMPLETE for these files.
- b. Your merge, with its commit and file counts.
- c. Refused by the guard; the skill is unchanged.
- d. No. done-check judges it FULL, and a plan that said LIGHT has no expected.tsv: NOT READY, next: plan again as FULL. Then it needs the failing and passing tester runs, the reporter, and three approving reviewers.

## 6. Facts to measure before code (6.0, both pins, the method's fragment)

Measured on 14 November 2026, before any product code, with the repo's $0 harness: the real client at 2.1.316 and 2.1.319 (tests/harness/get-client.sh, sha512 checked) against the local fake, the method's fragment and hooks laid out as sync will (`h_method`), and S5-shaped stand-in agent, rule and skill files committed in throwaway projects. Eight cases a pin, 18 client runs in the final pass, 29.6 s of client time; no outside connection, no key but the dummy one. Every fact gave the same result at both pins. No result changes a decision, so this plan stays version 2; the one "If it fails" change applied is F4's (S7 and 6.1).

| # | Fact | If it fails | Measured at 2.1.316 and 2.1.319 |
|---|---|---|---|
| F1 | A gate with `tools: Read, Grep, Glob, Bash`, and the architect with `tools: Read, Grep, Glob, WebFetch, WebSearch`, resolve to non-empty sets without Agent or Task, in default and auto mode, foreground and background. Auto mode still offers SubagentHandback, or the agent ends cleanly. A gate's receipt is VALID. | Add `SubagentHandback` to `tools:` and measure again; if that is refused, use `disallowedTools: Agent, Task, Skill, SendMessage` (plus Bash, Edit, Write for the architect) instead of an allowlist. | **Holds at both.** A gate's requests carry `Bash, Read`: the client drops Glob and Grep from any set holding Bash (the main session gets none either; search goes through Bash). The architect's carry `Glob, Grep, Read, WebFetch, WebSearch`. Neither holds Agent, Task, Skill or SendMessage. Auto mode adds `SubagentHandback` to both, though `tools:` does not list it; gates and the architect hand back in one turn. Gate receipts `VALID why=none open=APPROVE` in default and auto mode, foreground and background. |
| F2 | `model: claude-opus-5-5` in agent frontmatter runs as claude-opus-5-5 under availableModels. | Use `model: opus` (measured, step5b.md:81), and change R5's wording in A73. | **Holds at both.** With the fragment, every gate and architect request carries `claude-opus-5-5`, and the receipts are VALID (no `model-off-list`). The control, without the fragment and with `--model claude-sonnet-5-5`: the main session's requests carry sonnet at effort medium, the gate's and the architect's `claude-opus-5-5` at xhigh, so the field takes. |
| F3 | A YAML `#` comment line in agent and skill frontmatter: the file loads, there is no unknown-key debug line, receipt.pl's effort regex is unaffected, and B10's body is unchanged. | IDs go on the last body line, as text. | **Holds at both.** Agent and skill files with a `# rules: …` line load (init's `agents` and `slash_commands`), and the comment reaches no request. No debug line names them, while a control agent with `bogus-key: 1` gets `[WARN] Agent file … has a frontmatter key Claude Code does not recognize or apply: "bogus-key"`. (A skill gets no such line even for an unknown key, so for skills only loading can be told.) Receipts VALID with `effort_file=xhigh`, no `instructions-differ`. |
| F4 | `.claude/rules/method/*.md` (subfolder, no `paths`) reaches the main session's and a gate's first request; HTML comments are stripped or kept. | If they do not load, the rules go to the project CLAUDE.md template (step 7) and this plan is re-versioned. If comments are kept, the budget counts them. | **Loads at both; comments partly kept.** The file reaches the first request of the main session, of every gate and of the architect ("Contents of …/.claude/rules/method/method.md (project instructions, checked into the codebase)"). An HTML comment that shares a line with text is kept as written; a comment alone on its line is stripped. Applied: the budget counts the ID comments at sentences' ends (S7, 6.1). |
| F5 | Started in a project subfolder, do the root's rules load? (M140; step5.md:711) | M140's line also goes in step 7's CLAUDE.md template, with a rule-map note. | **Holds at both.** Started in `sub/deeper`, the root's rules file reaches the first request, and the project's agents and skills load. The project settings do not (no METHOD-ACTIVE line, effort medium: E12), which is the case M140 is for. |
| F6 | `.claude/skills/method-start/SKILL.md` is listed in init's `slash_commands`; `-p "/method-start"` expands; `${CLAUDE_EFFORT}` and `${CLAUDE_SKILL_DIR}` substitute; a typed skill fires no PreToolUse (expected [D]). | Without `${CLAUDE_EFFORT}`, the skill reads effort from status's effort area alone. | **Holds at both.** `method-start` is in `slash_commands`. `-p "/method-start typedarg"` sends the body as `effort=[xhigh] dir=[<project>/.claude/skills/method-start] args=[typedarg]`. The debug log shows no PreToolUse hook run for the typed skill; in the control session the model's Skill call shows `Hooks: PreToolUse:Skill [… guard.sh"] finished with status 0`. |
| F8 | In this repo, touching `method/.claude/rules/method/…` or `method/.claude/skills/…` loads them into the session (TASKS.md:110), and whether a loaded M140 then fires with the hooks off (V1.5). | AGENTS.md's line (S2) is already in place. If M140 still makes the builder stop, the files are kept from loading here (a `claudeMdExcludes` entry in this repo's settings) by a recorded decision. | **Partly measured, the same at both.** In a copy of this repo with its own settings (no hooks), one Read of `method/settings.fragment.json` loads both stand-in `method/.claude/rules/method/*.md` files into the next request ("Contents of …/method/.claude/rules/method/method.md") and lists the stand-in skill ("method-start: … (from method/.claude/skills — applies when working on files under method/)"). Whether a loaded M140 makes the builder stop is model behaviour the fake cannot show: it is seen in this repo's first real session after 6.1. The fallback was measured: `claudeMdExcludes: ["**/method/.claude/rules/**"]` in the project settings keeps both rules files out, but the skill is still listed. |
| F9 | Two different gates launched in one message both get VALID receipts, with no `write-mark`. | `/method-finish` launches them one after the other (cost: time only). | **Holds at both.** Reviewer and security checker in one message: both `VALID why=none`, in default and auto mode, and their start and stop hooks overlap in the debug log (they ran at once). With each gate running a Bash call the guard counts as a write, both stay VALID and no mark is written (a gate's own calls never mark, receipt.pl:320). The control, the main session writing while a background gate runs, gives that gate `INVALID why=write-mark`. |
| F11 | Whether an Agent call from the main session runs in the background by default, and whether `run_in_background: false` is honoured for two calls in one message (V1.8). | The skill text already names `false`. If it is not honoured, gates are launched one per message and waited for. | **Background by default at both; `false` honoured.** A call without the key returns "Async agent launched successfully" and the report comes later as a task notification (its receipt VALID). With `false`, two and three calls in one message all return before the main session's next request: as the tool results in default mode; in auto mode as "This agent's report was delivered to you as a message … (its SubagentHandback call)". The skill's `false` is needed, as planned. |
| F12 | Three `method-reviewer` runs (one name) launched in one message all get VALID receipts, each its own run. | Deep review launches them one after the other. | **Holds at both.** Three receipts, three agent ids, all `VALID why=none`, with overlapping start and stop hooks; the same with a Bash call in each run. |


Not measured, and why:
- F7 (a personal skill beats the project's): only the known limit's wording would change (V2.10).
- F10 (description bytes in the request): the budget counts the `description` fields' bytes (S7, V2.10).
- `omitClaudeMd`: not used (S5).
- `isolation` from an agent file: lint forbids it in method files, and B10 catches another file of the gate's name.
- Preloaded `skills:` hooks: method agents set no `skills:`.
- Workflows: never set.

## 7. Critique and what changed

V1 = the feasibility critique, V2 = the scope, value and safety critique. Every finding, in each critique's order.

| Finding | Disposition | Where |
|---|---|---|
| V1.1 Deep review contradicts itself; the builder votes | Accepted: three VALID reviewer receipts, all approving, no other word; no vote; every finding gets a disposition | S13, S14, M146, prediction d |
| V1.2 Scripts cannot name gates or words | Accepted, option (a): roles by place in verdicts.txt's header, checked by verdicts.test.sh, read by `Verdicts::roles`; S4's "do not change" corrected | S4, 6.2 |
| V1.3 Nothing runs "seen failing first"; receipts lost in a new cloud session; weak evidence | Accepted: `method-plan`'s post-approval step; the `git switch -c` re-run route; per-clone receipts a known limit; "any failure" said plainly | S11, S14, section 2, section 5, 6b.3 |
| V1.4 ESCALATE and visual items leave FULL no route to READY | Accepted, option (a): [EYES] and [AUTHORITY] listed in the report and put first in the pull request; ESCALATE only when a person must decide; M028 mapped in writing | S4, S6, owner.md |
| V1.5 M140 misfires in subagents and maybe in this repo | Accepted: M140 worded for the main session, both line forms named; AGENTS.md line now; F8 measures it | S2, S17, F8 |
| V1.6 A `method-*` pattern does not fit G6's machinery | Accepted: a fixed `@METHOD_SKILLS` list of `dir` entries feeding all four places; plants for the version check | S10, 6.3 |
| V1.7 The shouting rule fails on today's files; `**` needs bash 4 | Accepted: scope limited to agents, rules and skills, walked by perl; replaced by a denylist (V2.10) rather than an allowlist of terms | S8 |
| V1.8 Foreground launch not measured | Accepted: F11, and the skill names `run_in_background: false`. The guard clause is rejected: a background gate that collides with writes is already INVALID (`write-mark`), as S16 reasons for the agent-launch guard | F11, S16 |
| V1.9 HIGH_RISK_PATHS can be dropped on its own branch; second syntax | Accepted: union of main tip's and HEAD's; PRODUCT_PATHS' syntax; plant; older-conf note | S13, 6b.3, section 5 |
| V1.10 The lock is under-defined; order differs from R6 | Accepted: the anchor rule (first commit carrying HEAD's exact Approved line, so a re-approval moves it and a re-added line does not); TESTS FAIL after the anchor; R6 reading recorded; promotion needs a re-plan | S11, S14 |
| V1.11 The squash default is assumed | Accepted: Claude cannot set it; owner action now; `/method-start` reads it with a GET; Co-authored-by trap a known limit | section 0, S12 |
| V1.12 report-check flags numbers from no log; exit codes open | Accepted: `/method-finish` logs git's and done-check's output first; exit 1 for anything listed | S15 |
| V1.13 Missed plants and harness: settings plant, `h_method`, README list | Accepted: all three in 6.2 | section 2, 6.2 |
| V1.14 Decisions superseded silently: A11, one plan per branch, design branch | Accepted: A11's two clauses stated (S13) and recorded; one task per merge, one reply can approve several; design branch gets a LIGHT task folder | S11, S13, Records |
| V1.15a Model ID in two places | Accepted: the lint compares with the fragment's `model` | S5, S8 |
| V1.15b `claude -p` guidance wording | Moot: M081 becomes `later` (V2.10) | S16 |
| V1.15c `gh pr list` unauthenticated | Accepted: "could not read" (M121) | method-start |
| V1 missing F11 to F14 | F11, F12 accepted; F13 folded into F8; F14 folded into F1 (the architect's allowlist) | section 6 |
| V2.1 The reporter runs before the report; report-check unenforced | Accepted: `method-finish` reordered (report, report-check, reporter, done-check); the reporter refuses a failing report-check; why.md says it is not done-check's | S4, S15, section 2 |
| V2.2 Deep review contradicts itself; the vote drops lone findings | Accepted (with V1.1); M087's wording changes, recorded in A74 | S13 |
| V2.3 The Approved line passes from any "go"; section 0 overclaims | Accepted: fixed question, `approve <id>` checked against the folder; section 0 and M144 reworded | S11, M144, section 0 |
| V2.4 A change can lower its tier or move its lock | Accepted: Tier and Paths locked with expected.tsv; anchor rule; HIGH_RISK_PATHS union; three plants. Rejected in part: "touching method.conf makes it FULL and high-risk", because the union already stops a branch removing a path | S11, S13, 6b.3 |
| V2.5 Review can be narrowed or shopped; round cap unenforced | Accepted: receipts record the packet's base, chained to the merge base; more than three rounds is NOT READY (M009 gets a script home); the gate history goes in the pull request; ESCALATE's resolution stated | S14, 6b.1 |
| V2.6 "Seen failing" accepts any failure | Accepted: said plainly in section 0, M145, why.md and section 5. The test-files-only check is rejected: no key names test files, and PRODUCT_PATHS may hold tests | S14, S16 |
| V2.7 Drafting agents have Bash | Accepted: the architect has no Bash; the planner is not built; the lint forbids write tools on non-gates | S5, S8 |
| V2.8 Section 0 overclaims | Accepted: each item says what is checked | section 0 |
| V2.9 why.md incomplete and not shipped | Accepted: ships as `docs/method/why.md`; four tables including "partly enforced" and the agent and skill rules | section 2 |
| V2.10 Cuts | Accepted: lint part three keeps folder, name, list, `context: fork`, `agent:` (drops `!` and `hooks:`; agent `hooks:` too; `memory:` kept, no other home); emphasis denylist; `/method-explain` to Track 4; M081 `later`; `/method-checks` only if M045 arrives; the planner agent dropped; M122 and `# defaults:` `later`; F7 and F10 not measured; no A37-style reading; 6b reordered R4, R8, R6 | S4, S8, S9, S11, S13, S16, section 4, section 6 |
| V2.11 The trailer needs the squash default | Accepted (with V1.11): owner action before the 5 and 5b merge | section 0, S12 |
| V2.12 The method's rules may load here | Accepted: AGENTS.md says now that `method/.claude/` text is product and M140 does not apply; F8 names M140 | S2, F8 |
| V2.13 Field neutrality of M141 and M099 | Accepted: "where the project uses packages"; "the thinnest end-to-end version first" | S17 |
| V2.14a Gates load "keep going" | Accepted: "You check; you never change files" opens the Checking agents part | S5, section 2 |
| V2.14b LIGHT's reporter | Accepted as convention: `/method-finish` runs it for [EYES] or [CHECK] items; why.md lists it as partly enforced | S13, section 2 |
| V2.14c The reporter's acceptance run writes product files | Accepted: a temporary copy or `.method/local/` | S4, agents table |
| V2.14d M006 "write nothing" against the plan folder | Accepted: reworded | S6 |
