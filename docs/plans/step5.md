# Step 5 plan, version 3: the settings fragment, a free test harness, session-status and the guard; then 5b, gate-receipt

**Approved** by the owner on 8 November 2026, with every recommendation ("choose whatever is best"). The decisions are recorded as DECISIONS A45 to A62.

The planning evidence stayed in the planning session's scratch space and is not kept here: the probe and its runs, the critics' and checkers' runs, and versions 1 and 2. Every `[M]` label cites one of those runs (section 12). The harness re-measures each claim the build relies on, from increment 5.2.

How this version came about:
- Version 1 (not kept) went to two critics:
  - a feasibility critic, findings C1-F1 to C1-F14;
  - a bypass critic, findings C2-F1 to C2-F14. It ran 16 attacks against the real client at $0. 6 of them got past a guard built to the v1 design.
- Version 2 (not kept) went to a fresh checker, findings K1 to K10. It measured more ways past v2's guard: skill frontmatter hooks, inline interpreters, a symref branch, a hook route through `git -c`, and a locally moved `origin/main`.
- Every round so far found new ways round a list of forbidden command forms. That list does not converge. So version 3 turns the guard's git, GitHub, Claude and MCP rules into lists of what is allowed (D8). Anything touching those that is not on a list is refused.
- Section 13 lists every finding and what this version does with it.

How claims are labelled:
- **VERIFIED** claims carry `[D: page#anchor]` or `[M: Ex]`.
  - `[D: page#anchor]` is documented at `https://code.claude.com/docs/en/page#anchor` (docs and changelog checked Nov 2026, up to 2.1.319).
  - `[M: Ex]` is measured. `Ex` points to the evidence index in section 12.
- **INFERRED** claims carry `[I]`. Each one is reasoned, not measured.
- Record IDs: A = DECISIONS, M = rule map, R = SPEC, RISKS #n.

---

## 0. In plain words

**Status:** approved; increment 5.1 is next. The owner left the four predictions in section 1 to be compared after the build.

**What step 5 adds:**
- **A settings file** that every method project gets. It sets:
  - Opus 5.5 only, at effort xhigh;
  - the advisor, auto memory and commit attribution off;
  - shell lines inside skills off.
- **Two small scripts** that Claude Code runs by itself:
  - **session-status:** at each session start, it tells Claude "the method is on" and lists anything that needs a look.
  - **guard:** before Claude runs a command, edits a file or uses an outside tool, it checks it:
    - Commands that touch git, GitHub, another Claude, outside tools or the method's own files must match a short list of known, safe shapes. Anything else that touches them is refused, with what to do instead.
    - Among what it refuses: a push to main or a merge; discarding work; editing the method's own files or settings; switching the hooks off mid-session; starting another Claude; sending a secret to GitHub.
- **A free test harness.** The real Claude Code program talks to a fake Claude on the same machine. That proves at no cost that the scripts really fire and really hold.

**Step 5b adds the third script, gate-receipt.** When a checking agent such as the reviewer finishes, it writes a receipt: did the agent finish, on which model and effort, and which exact version of the files did it look at.

**What it stops:**
- Claude pushing to main or merging. Until step 6, you merge on GitHub.
- Lost work: force pushes, hard resets, deleted branches.
- Claude quietly switching the guard off, through the routes the reviews found and measured, except the few kept as known limits (D8).
- In 5b: a cut-off or stale review counted as an approval, or a checking agent running off Opus or below its effort unseen.

**What it does not stop** (D8):
- **The guard is a seatbelt, not a lock.** It reads what Claude types. It cannot read:
  - a program Claude writes to a file and then runs;
  - words put together only when the command runs.
  - A model set on getting round the guard can use those. Its changes show in the review and in CI afterwards; they are not prevented.
- **The real locks sit outside the session:**
  - your merge on GitHub;
  - later, a CI check that the method's files match the release (to be planned in steps 7 and 9);
  - GitHub's branch protection, which a private repo gets only on a paid plan (RISKS #4).
- Anything in a cloud session with several repositories, or in a Projects thread: no repo hooks run there.
- A session started in a subfolder of the project: the hooks and the effort setting do not load [M: E12].

**What it costs:**
- **Money:** $0 for every test [M: E1, E19].
- **Session start:** about 0.1 s, and at most 1,200 bytes of text [M: E3; I].
- **Each command or edit:** about 30 to 45 ms on Linux [M: E24], and more on Windows [I].
- **CI:** about 1 to 2 more Linux minutes per run [I].
- **Building it:** 11 increments in step 5 and 3 in 5b. Each has up to 3 review rounds. With three reviewers per round where hook code is written (D13), that is at most about 115 reviewer runs. Step 4b's increments mostly needed all 3 rounds.
- **Friction** (measured against the 16,014 commands recorded on this machine, check-v3):
  - a git or gh command that is not on a list is refused. With the lists as planned, about 4 in 100 of the git commands typed in this repo's main sessions would have been refused. The owner adds a shape in the project's `.claude/method-local/` lists, which Claude cannot edit; in a cloud session that is an edit on GitHub;
  - a command that names one of the method's files may only read it or run the method's scripts (G6);
  - every `claude` command, and every outside tool not on the list, is refused;
  - your own `/plugin install` or project-scope `/permissions` change mid-session is refused until the next session (G16).
- **Your plan usage:** the reviewer runs above use your Claude plan's usage; only the tests are $0.

**What you will see when it is done:**
- A green CI run whose harness job prints one PASS line per rule. Each line was proven in the real client at two pinned versions.
- One plain page per hook: what it stops, what it costs, how it was seen to fire, where it does not run, and what to do when it blocks wrongly.

---

## 1. Four points to confirm before building (M125)

1. **Who it is for.** You, alone, on Linux and in single-repository cloud sessions (A27). The hooks protect your method projects.
   - In step 5 they run only in tests. They reach a project in step 7, when sync installs the method.
2. **What is out of scope:** section 4 has the table. In short:
   - gate-receipt: step 5b;
   - the agents, task folders, your approval records, Claude's own merge route, done-check reading receipts, and the workflows setting: step 6;
   - packs, sync and the Balanced and Budget profiles: step 7;
   - the installer: step 8;
   - the paid live cloud test: step 9;
   - Windows and macOS runs: A27.
3. **What done looks like that you can see.**
   - A green CI run on GitHub. Its harness job has a PASS line per rule, for example "guard G4: git push origin main refused, real client 2.1.316". It also shows each planted break turning red.
   - Each increment ends with one "you will see" line copied from a log (section 8).
   - The hooks README, one plain page per hook.
4. **What you expect to happen.** Please answer in your own words before I build.
   - a. In a method project, Claude types `git push origin main`. What happens?
   - b. (5b) The reviewer's answer is cut off by a usage limit right after "APPROVE". What does the receipt say?
   - c. You open a cloud session with two repositories. Do the hooks run?
   - d. Claude runs a command the guard cannot read with confidence. Is it allowed or refused?
   - My answers, to compare with yours:
     - a. Refused, with a plain reason. The guard reads what Claude types, so a model set on getting round it could still push through a program it writes and then runs. That would show in the review and in CI afterwards.
     - b. "Not checked" (INCOMPLETE). It is never an approval.
     - c. No. This answer comes from the docs; the harness cannot test cloud sessions.
     - d. It depends on what the command touches. If it names git, gh, claude, curl, wget, a write such as `>` or `cp`, or one of the method's files: refused, with what to do instead. Otherwise: allowed.

---

## 2. Decisions for the owner

Each decision has a recommended answer and the reason for it.

**D1. Raise the Claude Code floor from 2.1.295 to 2.1.316.**
- **Recommended:** yes.
- **Why:**
  - Before 2.1.311, the stop event for a checking agent fired about twice a minute while the agent was still running [D: changelog 2.1.311].
  - Before 2.1.314, a guard matching Bash did not see commands started by the Monitor tool [D: hooks#match-monitor-commands].
  - 2.1.299, 2.1.309, 2.1.310 and 2.1.316 fixed Windows cases where a hook let a call through [D: changelog].
  - It costs nothing today: this machine runs 2.1.319 [M: E2].
- **What changes, in 5.2:** the SPEC "Supported versions" table, REQUIRES, and the status tests' floor strings. The harness reads the floor from REQUIRES, so there is no second copy (C1-F12).

**D2. Until step 6, Claude never lands a change; you merge on GitHub.**
- **Meaning:** the guard refuses every push to main and every merge by Claude:
  - git: a push passes only in the listed forms, to a branch that is not main (G3);
  - gh: `gh pr merge` and every `gh api` call that writes (G4);
  - the MCP merge tools, on any server (G4, and `permissions.deny`).
- **Recommended:** yes.
- **Why:**
  - Today done-check reads a typed verdict line (A33).
  - Claude's own landing route needs receipts, which done-check reads in step 6.
  - RISKS #4: without a paid GitHub plan, nothing on GitHub stops a merge.
- **Cost to you now:** none. No project runs these hooks before step 7, and this repo keeps its own route (D3). This decision settles the rule and its message.

**D3. Do not switch the hooks on in this repo's own sessions until step 7.**
- **Recommended:** yes.
- **Why:**
  - The guard would refuse edits to this repo's `.claude/settings.json`, which later steps must change.
  - The landing rule would block the merge route you chose for this repo.
  - Wiring them in now would need a second copy of the hook settings (M048).
- **Step 7 design, recorded now (C1-F2):** this repo will run the copy that sync installs from the last tagged release. Editing `method/` then never changes the guard the builder is running. A broken guard edit cannot lock the builder out mid-step.

**D4. Keep auto mode in method projects.**
- **Background:** in auto mode, a subagent hands its report back through a tool called SubagentHandback [D: hooks#subagentstop]. Auto mode cannot run against the fake Claude [M: probe].
- **Recommended:** keep auto mode. In 5b, gate-receipt checks the report at the SubagentHandback call. If the verdict lines are missing, it refuses the call once with the JSON `permissionDecision: "deny"`, as the docs say. The client then tells the subagent to try again, up to three times [D: hooks#pretooluse-decision-control] (C1-F5, K10).
- This path is proven only by recorded inputs until step 9's live cloud test. If it fails, the gate reads "not checked", never approved.

**D5. Withdrawn from step 5: the workflows setting** (C1-F9).
- A project file that sets `enableWorkflows` hides the switch from you in `/config`, so a cloud session would have no way back [D: settings-reference#enableworkflows].
- It also decides part of step 6's Deep review before that design exists.
- It moves to step 6. This repo's settings stay as they are.

**D6. Run the harness in CI on every Linux change, in its own job.**
- **Recommended:** yes.
  - It runs at the floor (read from REQUIRES) and at one pinned tested version (2.1.319). Each binary is checked against a recorded checksum and cached between runs. It is about 340 MB per version [M: E2].
  - A missing client fails the job only where the job says a client must be there (`METHOD_HARNESS_CLIENT`). Elsewhere, including the existing test jobs, the harness prints SKIPPED, which never counts as a pass (C1-F1, M053).
  - Versions are raised by hand in `/research-update` (A21), not on a schedule.
- **Cost:** about 1 to 2 more Linux minutes per run [I]. The probe's 9 client runs took 8.1 s [M: E1].

**D7. No hook records your approvals in step 5.**
- **Recommended:** yes. Settle it in step 6, together with task folders.
- **Why:** the prompt event also fires for prompts nobody typed: scheduled tasks, /loop, background agents reporting back, and messages from other sessions [D: hooks#userpromptsubmit; M: E19]. No input field tells them apart. A record that a machine can fake is worse than none.

**D8. The guard is a seatbelt that works from lists, not a lock.**
- **The question:** how far should the guard go against a model that tries to get around it?
  - It runs from a file in the working tree, which the model can change. No guard on the client can be a real lock; RISKS #2 already says so.
  - Both review rounds of this plan found new ways past a list of forbidden forms: 6 in v1, then more in v2 (K1 to K4). Each fix to a forbidden list left a nearby form open.
- **Options:**
  - **a. A seatbelt built from allowed lists (recommended).**
    - Every git and gh command Claude types must match a listed shape (G3, G4). So do MCP tools (D10).
    - A command that names a method file may only read it (G6).
    - Everything else that touches these is refused, with what to do instead.
    - This closes, by construction, every git route the reviews found: plumbing, symrefs, config tricks, hook paths, a moved `origin/main`, carriers like `rebase --exec`.
    - The cost: an ordinary command that is not on a list is refused until the list grows. Measured against this machine's recorded commands, the lists as now planned would refuse about 4 in 100 of the git commands typed in this repo's main sessions (F1). Each project has its own extra lists in `.claude/method-local/`, which you edit and Claude cannot; the refusal names them.
  - **b. Keep adding forbidden forms.** Each review round finds more, so this does not converge.
  - **c. Only the obvious mistakes** (force push, push to main, hard reset). Smaller and cheaper, but a model that retries a refused push in another spelling gets through.
- **Either way, known limits, written in the README and RISKS:**
  - a program Claude writes to a file and then runs, and words put together only at run time (RISKS #2);
  - a renamed copy of the claude binary;
  - MCP write tools whose names look read-only;
  - another hook that changes a command after the guard approved it, when that hook already existed at session start. session-status lists such hooks [M: E30];
  - a settings or PATH change made between sessions. The next session starts with it. Only step 6's "no METHOD-ACTIVE line" rule catches it;
  - a managed policy file, which cannot be blocked [D: hooks#configchange]. Claude runs as root in cloud sessions [M: E33]. G6 refuses a Bash write there, but a written-then-run program could still make one;
  - under Git Bash, a settings `BASH_ENV` runs in the outer shell before the hook's prefix applies [M: K5; D: hooks#exec-form-and-shell-form];
  - a mod, which can approve what the guard refuses on an account like yours [D: permissions#precedence-among-rules-hooks-and-mods];
  - places hooks do not run: a multi-repository cloud session, a Projects thread, a session before you accept the trust dialog, a session started in a subfolder [M: E12], and a session you started with hooks switched off (section 6.6).
- **The real locks sit outside the session:**
  - your merge on GitHub (D2);
  - a CI check in each project that the method's files equal the installed release. It is not planned yet; section 11 adds it to steps 7 and 9;
  - GitHub branch protection, which a private repo gets only on a paid GitHub plan (RISKS #4). Not needed for step 5; worth deciding before step 7 puts the method into your projects.
- **Not chosen:** a check after every tool call that compares what ran with what the guard saw (C2-F4). It doubles the cost of every call, and it only notices after the command has run. G16 and G17 block adding such a hook mid-session.

**D9. Skills cannot run shell lines.**
- **Meaning:** `disableSkillShellExecution: true` in the fragment.
- **Why:** a skill's `!` line runs a command before Claude sees the skill, and no guard fires [M: E27]. Claude can write a project skill, so this is a way around every rule.
- **Recommended:** yes. Step 6's skills tell Claude to run commands instead; those go through the guard.
- **Also note:** in method projects this also turns off `!` lines in your own user-level and plugin skills [D: settings-reference#disableskillshellexecution] (K10).
- **Not covered by this setting:** a skill's or agent's frontmatter `hooks`. Those are registered when the skill is used, for the rest of the session [D: hooks#hooks-in-skills-and-agents; M: K1]. G17 covers them.

**D10. Outside tools (MCP) only from a list.**
- **Meaning:** read-only tools pass. A named list of write tools passes only for this repository and a task branch. Every other MCP tool is refused until you add it to the list.
- **Why:** a list of forbidden names missed tools that start a new cloud session or send a message to another session. Those can run with no repo hooks at all (C2-F7).
- **Recommended:** yes. Over-refusal is accepted: the refusal says how to add a tool.
- **What it means for you:** in method projects, Claude cannot start or message other sessions or create scheduled tasks that start new sessions. Scheduling a reminder into the same session, and watching a pull request, stay allowed. The merge and session tools are also denied in the settings file. Lifting a deny means editing the project's settings, which in a cloud session is done on GitHub (K8).

**D11. Claude cannot start another Claude in step 5.**
- **Why:** a nested `claude` run with one flag, or started in a subfolder, runs with no project hooks [M: E29]. `claude plugin install` installs a mod the same way.
- **Recommended:** yes. The method's own nested runs (M081) come in step 6, through one protected wrapper script that the guard allows by name.
- **Limit:** a renamed copy of the binary does not contain the word "claude" (D8) [I: K7].

**D12. Split step 5 into step 5 and step 5b, as 4 and 4b were.**
- **Step 5:** the fragment, the harness, session-status and the guard (5.1 to 5.11).
- **Step 5b:** gate-receipt (5b.1 to 5b.3).
- **Why:** with the critics' fixes, the guard alone is about as large as step 4. Splitting it gives you a merge point after the guard, and gate-receipt is planned once the guard's harness exists.
- **Recommended:** yes. ROADMAP gets a 5b line.

**D13. How many reviewers per round** (K6).
- **Background:** you asked for full three-reviewer rounds for steps whose code runs with your rights, and hooks qualify. The method's minimum is one reviewer plus one security check.
- **Recommended:**
  - three reviewers per round for increments that write hook code or code hooks load: 5.1, 5.4 to 5.10, and 5b;
  - the minimum for 5.2 (the test harness, which never ships) and 5.3 (the settings file and its test);
  - the closing increments 5.11 and 5b.3 get one reviewer, with a security check, over the whole step.
- **Cost:** at most about 115 reviewer runs over the two steps (10 increments × 3 rounds × 3, plus 4 × 3 × 2), against about 125 if every increment used three. Most of the cost is the guard, which is where the risk is.

---

## 3. What changed since the earlier design (plan v3, `plan-v3-full.md`)

Where the reports and plan v3 disagree, the measured and documented facts win.

| # | Plan v3 said | Now | Source |
|---|---|---|---|
| 1 | A $0 probe cannot fire the pre-tool hook; guard and receipt proofs go to a paid cloud test | A local fake Claude makes the real client fire every hook used here. The paid test keeps only cloud-only items (step 9). | [M: E1]; ROADMAP step 9 |
| 2 | SessionStart matcher `startup\|resume\|clear\|compact` | No matcher, so every source fires, including `fork` | [D: hooks#sessionstart] |
| 3 | session-status warns when effort is below xhigh | SessionStart has no effort field. The guard warns at the first tool call (G12). | [M: E1]; [D: hooks#common-input-fields] |
| 4 | status prints FAIL below the floor | LOOK (A32). Inside a hook the version cannot be read, so it is SKIPPED there. | [M: E16; E1] |
| 5 | Guard matchers: Bash, PowerShell and the edit tools | Add Monitor, ExitWorktree, SendMessage, Skill, Agent, Task and `^mcp__`, and ConfigChange. git, gh and MCP are judged by lists of allowed shapes (D8). | [D: hooks#match-monitor-commands, hooks#match-mcp-tools, hooks#configchange]; [M: E1, E28] |
| 6 | gate-receipt reads `last_assistant_message` | In auto mode the report comes through SubagentHandback (D4) | [D: hooks#subagentstop] |
| 7 | In auto mode, classifier requests loop against the mock | On 2.1.319 auto mode refuses the Agent tool behind a custom base URL. The harness uses default mode, plus one acceptEdits case. | [M: probe, E26] |
| 8 | `/clear` does not exist in the cloud | It does; SessionStart source `clear` can fire there | [D: claude-code-on-the-web#manage-context] |
| 9 | Critique 22b: add `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` | Rejected: no effect from project settings; from the environment the client refused to start without bubblewrap | [M: E7, E8] |
| 10 | Weekly `drift.yml` probe | Rejected (A21, A25). Versions are pinned and raised by hand. | A21 |
| 11 | Critique #4: a prompt hook records the owner's approvals | Deferred (D7) | [D: hooks#userpromptsubmit] |
| 12 | Exec form avoided because it "would find the WSL launcher" | Shell form is kept (A23), with the placeholder in double quotes, now behind `BASH_ENV= ENV=` | [D: hooks#exec-form-and-shell-form]; [M: E28] |
| 13 | (not covered) | Agents run in the background by default | [M: probe] |
| 14 | (not covered) | Project hooks and settings do not load when Claude Code starts in a subfolder | [M: E12] |
| 15 | (not covered) | Settings files reload mid-session, hooks and env included. One write switched the guard off. | [M: E28]; [D: settings#when-edits-take-effect] |
| 16 | (not covered) | Skill `!` lines run with no PreToolUse hook | [M: E27] |
| 17 | M106 says "any new commit voids it"; A35 accepts an amend that only adds the verdict line | 5b keys on the tree of files. M106 is reworded to "any change to the files voids it". | A35 |

Other conflicts in the records are resolved by the later record:
- A10 keeps the four verdict words; 5b only adds new kinds to verdicts.txt.
- The rule map homes M073 in the hooks README.
- SPEC R5 has profiles; step 5 ships the "Best results" fragment only.

---

## 4. Scope

### Built in step 5

| Item | Requirement or rule |
|---|---|
| `method/settings.fragment.json` and its test | R5 (Best results only), M076, M104, A2 to A5, A22 |
| `session-status.sh` | R1, M073 |
| `guard.sh`, rules G0 to G17 (section 6.2), each with a rule-map row, and its lists `git-shapes.txt`, `gh-shapes.txt`, `mcp-tools.txt` | R7, RISKS #2 and #4, M072, the rows in section 6.2 |
| Shared helpers: hook input and output, capped log, JSON writer, a library form of the secret scan | M048, M072 |
| status.sh: `--quick`, a guard area, a settings area | M001 |
| `tests/harness/`: the real client against a local fake Claude, $0 | R7 acceptance, RISKS #3 |
| Hooks README, with "when the guard blocks wrongly" | M073, RISKS #16 |

### Built in step 5b

`gate-receipt.sh` (section 6.3), the guard's "write during a gate" mark, status's gates area. M053, M078, M106, M116.

### Waits for a later step, and how each behaves until then

M053: never silently off.

| Rule | Needs | Step | Until then |
|---|---|---|---|
| Landing allowed when what lands is the commit done-check judged | receipts read by done-check | 6 | Every landing by Claude is refused: "the owner merges on GitHub; Claude's route comes with receipts (step 6)" |
| done-check reads receipts | agents and 5b | 6 | done-check's READY line says the verdict line is typed, not a receipt |
| Owner approval records | task folders | 6 | Not built (D7) |
| Nested Claude runs (M081) | the wrapper script | 6 | Every `claude` command is refused (D11) |
| The workflows setting | Deep review design | 6 | Not set (D5) |
| Which files planner and reporter may write | agents | 6 | 5b applies the unchanged-files rule only to reviewer, security-checker, diagnose and tester |
| Agent-launch guard (packet template, no effort or model override) | /finish packet template | 6 | 5b marks a wrong effort or model INVALID |
| Protection of plan.md, task.conf, oracles.lock, owner.tsv | task folders | 6 | Those files do not exist yet |
| Changes to `.github/workflows/`, `docs/incident-checklist.md`, `docs/domain-rules.md` and `.claude/method.conf` through an approved plan (touches-method) | plans and packs | 6, 7 | Not protected by G6 in step 5. A change shows in the diff and the review (C1-F3). |
| High-stakes paths below xhigh; edits outside the plan's paths | conf keys and tiers | 6 | G12 warns once per session below xhigh |
| Blocking finding without run evidence becomes a question (M117) | the findings format | 6 | Rule map row moves to step 6 |
| Live-write patterns (the earlier design's rule 5) | packs | 7 | The README lists it under "cannot catch yet" |
| METHOD-ACTIVE version | method.lock | 7 | Prints `vunreleased` |
| Balanced and Budget profiles; sync merges the fragment | sync | 7 | Only the fragment file exists |
| Full user-level audit (skills, advisorModel) | installer lock | 8 | session-status checks hooks and `maxEffortLevel` in user settings |
| Live cloud proofs (SubagentHandback, phone and web prompts, `!` commands, multi-repo) | paid run | 9 | The README states each one as unproven |
| Windows and macOS runs | A27 | later | The scripts follow the portability rules. They are not run. |

---

## 5. The settings fragment

File: `method/settings.fragment.json` (M076 and M104 home). In a project, step 7's sync merges it into `.claude/settings.json`.

| Key | Value | Why | Notes | Tested by |
|---|---|---|---|---|
| `model` | `"claude-opus-5-5"` | A2 | `--model` or `ANTHROPIC_MODEL` can change one session; the allowlist still applies [D: settings-reference#availablemodels] | static; harness init event [M: E11] |
| `availableModels` | `["claude-opus-5-5"]` | A2 | A managed list replaces it [D] | static |
| `enforceAvailableModels` | `true` | A2 | Ignored where any managed settings exist [D] | static |
| `effortLevel` | `"xhigh"` | A3 | `/effort` and `CLAUDE_CODE_EFFORT_LEVEL` rank above it; a user `maxEffortLevel` caps it [D: settings-reference#effortlevel] | static; harness: the request carries effort xhigh [M: E12, E19] |
| `attribution` | `{"commit":"","pr":"","sessionUrl":false}` | A22 | Object form accepted by every version [D] | static |
| `autoMemoryEnabled` | `false` | M104 | `CLAUDE_CODE_DISABLE_AUTO_MEMORY` overrides it for one session [D] | static; session-status warns on `=0` |
| `disableSkillShellExecution` | `true` | D9 (new row M138) | Bundled and managed skills are not affected [D: skills#inject-dynamic-context]. It does not stop frontmatter hooks (G17). | static; harness: a project skill's `!` line reaches the request as the placeholder and its marker file is absent [M: E27] |
| `skillOverrides` | `{"code-review":"user-invocable-only"}` | M075: not a gate | The rule map notes this key under M075; M075's home stays method.md (C1-F9) | static |
| `disableAllHooks` | `false` | Beats a user-level `true` [D: settings-reference#disableallhooks] | Local settings and `--settings` still win [D] | static |
| `minimumVersion` | the floor (D1) | Stops auto-update below the floor; does not stop an old binary [D] | | static: equals REQUIRES |
| `env.CLAUDE_CODE_DISABLE_ADVISOR_TOOL` | `"1"` | A5, M076 | | static; harness: present in the hook's environment [M: E7] |
| `env.CLAUDE_CODE_USE_POWERSHELL_TOOL` | `"0"` | Backs G2 | No effect on Linux or macOS [D: env-vars] | static |
| `hooks` | section 6.4 | R7 | Single-repository sessions only [D: settings#settings-in-cloud-sessions] | settings test; harness |
| `permissions.deny` | globs over every server name (K8): `mcp__*__merge_pull_request`, `mcp__*__enable_pr_auto_merge`, `mcp__*__create_session`, `mcp__*__send_message`, `mcp__*__create_trigger`, `mcp__*__fire_trigger`, `mcp__*__update_trigger`, `mcp__*__unarchive_session` | Still holds when hooks are switched off (new row M139). Server names differ by surface, so names are globbed. | Deny rules accept tool-name globs, and a bare-name deny removes the tool from Claude's context [D: permissions#tool-name-wildcards] | static; harness: no startup warning [M: E13], and the fake MCP server under two server names has its merge tool removed |

**Never set**, and the test fails if any committed settings file sets one:
- `CLAUDE_CODE_EFFORT_LEVEL` (A4);
- `autoContinueAtUsageLimit`: a project value turns the feature off [D];
- `permissions.defaultMode` set to `auto` or `bypassPermissions`: neither takes effect from a project file [D];
- `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` [M: E7, E8];
- `CLAUDE_CODE_REMOTE`: ignored from every file [D];
- `enableWorkflows` and `disableWorkflows` (D5, until step 6).

**What the project file cannot control:**
- a lower user-level `maxEffortLevel`;
- user-level hooks;
- local settings, which rank above the project's;
- managed settings;
- what a cloud session loads [D].
- session-status reports the first three where it can read them.

**How it is tested:**
- `tests/settings.test.sh`, static and fast:
  - every key and value above;
  - the never-set list, in the fragment and in this repo's `.claude/settings.json`;
  - this repo's shared keys equal the fragment's;
  - `minimumVersion` equals REQUIRES;
  - the hook rules in section 6.4.
- Harness case "fragment loads", at both versions:
  - the init event shows `claude-opus-5-5`;
  - the request carries effort xhigh;
  - the hook's environment has the advisor variable;
  - stderr has no settings warning.
- Plant: a value shape the client rejects. Whether the client skips the whole file or only the key is measured in 5.3.

This repo's `.claude/settings.json` stays as it is in step 5 (D3, D5).

---

## 6. The hooks

### 6.0 Common to all three

- **Files:** `method/.claude/hooks/method/{session-status.sh, guard.sh, gate-receipt.sh, README.md}`, plus the guard's three lists beside them: `git-shapes.txt`, `gh-shapes.txt` and `mcp-tools.txt`. Each list line has a shape and a reason.
- **The sh wrapper never hands over to perl** (no exec). It calls `command perl`, so an exported shell function named perl cannot stand in for it [M: K5], and it maps perl's exit code (C1-F4):
  - perl dies with exit 2 after a failed file call or a missing library [M: E21]. At SubagentStop, exit 2 would send the gate back to work.
  - So perl says "block" with a private code, 3. The wrapper turns 3 into 2.
  - Any other code is a crash. In guard.sh a crash becomes a G0 refusal (exit 2) with one line. In session-status a crash still prints METHOD-ACTIVE, from sh, with a warning. In gate-receipt a crash leaves INCOMPLETE.
- **Library path:** `../../../scripts/method/lib` from the script. That path works both here and in a project [I; the harness lays out the project form and proves it].
- **Command form:** `BASH_ENV= ENV= bash "$CLAUDE_PROJECT_DIR/.claude/hooks/method/<name>.sh"`.
  - Shell form (A23), with the placeholder in double quotes [D: hooks#exec-form-and-shell-form].
  - The empty `BASH_ENV` and `ENV` stop a settings env from running code inside the hook's bash [M: E28].
  - The harness proves it with a space, an apostrophe and ü in the path.
- **Input:** one JSON object on stdin, read once through JSON::PP in `lib/hook.pl`. Over 4 MB, or not JSON, is "cannot read": the guard refuses (G0), session-status warns, gate-receipt writes INCOMPLETE.
- **Which repository:** for a file, the file's own repository (`git -C <its folder> rev-parse --show-toplevel`), after resolving `..`, `.`, `//`, symlinks and letter case (C2-F12). For a command, the input's `cwd`, which follows Claude into a worktree [D: hooks#common-input-fields].
- **Output:**
  - A refusal is exit 2 with one plain stderr line that names the rule and the fix [D: hooks#exit-code-2]. The text never contains "No such file" [D: hooks#exit-code-output].
  - A warning is exit 0 with a JSON `systemMessage`.
  - Context is plain stdout on exit 0 [M: E9].
- **No secrets:** every hook's environment holds `ANTHROPIC_API_KEY` and `CLAUDE_CODE_MESSAGING_TOKEN` [M: E7].
  - No hook prints or logs its environment or a command's text.
  - Logs hold fixed fields and hashes only, through one helper, `lib/log.pl`, which caps every log (M072).
- **Logs:** under `.method/local/`, which git ignores [M: E17].
- **Timeouts:** 30 s (60 s for gate-receipt at stop). A blocking hook that times out blocks [D: hooks#command-hook-fields].
- **Hooks inside subagents** fire for the subagent's tool calls, with `agent_id` and `agent_type` in the input [D].

### 6.1 session-status.sh

**Event and matcher:** SessionStart, no matcher, so startup, resume, clear, compact and fork all fire [D: hooks#sessionstart].

**What it prints:** at most 10 lines and at most 1,200 bytes (an R12 budget with its own plant, C1-F11). It exits 0 whatever happens.
1. `METHOD-ACTIVE v<version>`, printed by sh before perl starts. The version is `unreleased` until step 7.
2. From `status.sh --quick`, with an inner 5 s limit: its LOOK lines and its summary line.
3. Its own warnings, one line each:
   - perl or JSON::PP missing;
   - the advisor variable not `1`;
   - `CLAUDE_CODE_DISABLE_AUTO_MEMORY=0`;
   - local or user settings that set a fragment key, `disableAllHooks`, `disableSkillShellExecution: false`, or any `env` key;
   - shapes added in `.claude/method-local/`, one line naming how many;
   - PreToolUse or PermissionRequest hooks in user settings, local settings or enabled plugins that are not the method's (C2-F4);
   - a user `maxEffortLevel` below xhigh;
   - the session model, when the input has one, not `claude-opus-5-5`;
   - on Windows, the PowerShell tool not set to 0.
4. Over the cap: `... N more: run bash scripts/method/status.sh`.

**It also writes a snapshot** of the settings keys G16 watches, to git's own folder, for G16 to compare against. It writes it only when a session starts (`startup`, or `resume` with no snapshot for that session ID), never on `clear`, `compact` or `fork`, so a change refused mid-session cannot become the new baseline after a compaction (check-v3).

With `METHOD_NESTED=1` it prints one line, `METHOD-ACTIVE v<version> (nested: status skipped)`.

**Changes to status.sh:**
- `--quick` skips the ci area: `ci: SKIPPED - not checked at session start; /start checks it`. Measured: about 0.11 s without gh against 1.5 to 1.75 s with it [M: E3].
- "Inside Claude Code" also counts when `CLAUDE_PROJECT_DIR` is set, because hooks get no `CLAUDE_CODE_EXECPATH` [M: E1].
- Inside a hook, the claude-code area says `SKIPPED - a hook cannot see the client's version; /start checks it` [M: E16].
- A new settings area reads local and user settings for G16's keys and prints LOOK, so `/start` sees what a hook may not (C2-F2).

**What it prevents:** working while the method is silently off or weakened; lost orientation after compaction or `/clear`.

**Cost:** about 0.1 s per start [M: E3]; at most 1,200 bytes of context.

**Proven to fire:**
- **Fixtures:** each warning; exit 0 when status exits 0, 1 or 2, crashes or times out; both caps; the nested run; the library missing.
- **Harness:** the line is in the first request [M: E9]; still there with a dirty tree; still there with perl removed from PATH; the `resume` source.

**Cannot catch:** it cannot block [D]; it never runs where hooks do not run; it cannot see effort or the client version [M: E1].

### 6.2 guard.sh

**Events and matchers:**
- PreToolUse, `onFailure: "block"`, timeout 30 s:
  - `Bash|PowerShell|Monitor|Edit|Write|MultiEdit|NotebookEdit|ExitWorktree|SendMessage|Skill|Agent|Task`, an exact list. The init event lists the agent tool as `Task` [M: E11]; both names are matched;
  - `^mcp__`, a regular expression [D: hooks#match-mcp-tools].
- ConfigChange, sources `user_settings|project_settings|local_settings`, `onFailure: "block"`, which works on this event [D: hooks#command-hook-fields] (K5) (G16).

**How it reads a Bash command:** it splits the command into simple commands at `;`, `&&`, `||`, `|`, `&` and newlines, honouring quotes and here-docs. It reads the inside of `bash -c`, `sh -c`, `eval` with a literal string, `xargs`, `find -exec`, `env`, `nohup`, `timeout` and `command` as commands too. Each simple command is judged on its own, and the call is refused if any one is refused.

**Speed (C1-F10):** a call with no watched word exits before any library loads or git runs. The watched words are git, gh, claude, curl, wget, a write word, and a protected path. Libraries load only when a rule needs them. Targets on Linux: median at most 40 ms, 90th percentile at most 60 ms [I; the bench with real libraries gave medians of 33 to 43 ms, M: E24]. A push takes longer, because G15 scans what it sends: about 0.4 s [M: E6]. Git Bash is slower per process [I]; the README gives an estimate for A27's later run.

**Rules.** Each rule has an ID used in the refusal, the log and the tests, and a rule-map row (C1-F3). Row numbers are provisional.

| ID | Row | Refuses | Planted inputs (must be refused) | Look-alikes (must pass) |
|---|---|---|---|---|
| G0 cannot-tell | new M128 (with G1: refuse what cannot be checked) | A simple command the guard cannot read, when the call also names a watched word. "Cannot read" is a fixed list (C2-F10): command substitution or backticks; `eval` of anything but a literal; a variable as the command word; a pipe or here-doc into sh, bash, perl, python, node, ruby or awk; an interpreter's inline program (`-c`, `-e`); `source` or `.`; glob or brace characters in a write target; `cd` to a path that is not written out, before a write. Also input it cannot parse and git state it cannot read. | One per item, each with a watched word; `perl -e 'open F,">",".claude/hooks/method/guard.sh"'`; `python3 -c "open('.claude/hooks/method/guard.sh','w')"` (K2); malformed JSON; a git failure | The same shapes with no watched word, such as `python3 -c "print(1)"`; commands run outside any repository (C1-F8) |
| G1 perl-missing | M128 | Every call when perl or JSON::PP is missing: the sh wrapper exits 2 | PATH without perl (harness) | n/a |
| G2 powershell | new M129 | Every PowerShell call | `tool_name: "PowerShell"` | n/a |
| G3 git-shapes | new M130 | **Every `git` command aimed at the session's repository must match a shape in `git-shapes.txt`, or in the project's own `.claude/method-local/git-shapes.txt`** (D8). The repository is found after resolving `-C` and `cd`; a path held in a variable is G0. Anything else is refused: "not on the method's git list; the owner can add a shape to .claude/method-local/git-shapes.txt". **Aimed at another repository** (a scratch clone, a test folder), only `push`, `remote`, and `config --global` or `--system` writes are judged (friction check). **The first list:** `--version`, `help`; read commands (`status`, `diff`, `log`, `show`, `blame`, `grep`, `ls-files`, `ls-tree`, `rev-parse`, `rev-list`, `merge-base`, `cat-file`, `describe`, `shortlog`, `for-each-ref`, `show-ref`, `check-ignore`, `check-attr`, `ls-remote`, `diff-tree`, `name-rev`, `count-objects`, `reflog` and `reflog show`, `stash list` and `stash show`, `remote -v`, `remote get-url`, `remote show`, `config` reads, `branch` with no name or with `-a`, `-r`, `-v`, `-vv`, `--list`, `--show-current`, `--contains`, `--merged`, `worktree list`, bare `tag` and `tag -l`); `add`, `rm` and `mv` (paths judged by G6); `restore --staged`; `commit`, without `-n` or `--no-verify`; `switch` or `checkout` to an existing branch, refused while tracked files have uncommitted changes; `switch -c` and `checkout -b` to a new branch; `branch <new>` and `branch -d`; `fetch` with at most a remote name and `--prune` or `--tags`, no refspec, not from `.` or a path (K4); `merge` with at most `--no-edit` or `--ff-only` of `<remote>/<main>`, not while on main; `cherry-pick` and `revert` of one commit; `reset --soft` and `reset` (mixed); `worktree add -b <new> <path>` from HEAD only. `-q` and `--quiet` are allowed on every listed shape, and short flags may be combined. **Global options:** `-C <dir>`, `--no-pager`, `--no-optional-locks`, and `-c` only for `core.quotepath`, `color.*`, `user.name`, `user.email`. Any `GIT_*=` assignment refuses the command (K3). **Push:** only `git push [-q] [-u] <remote> HEAD`, `HEAD:<dest>`, `<branch>` or `<branch>:<dest>`. The destination, with any `refs/heads/` or `heads/` removed, is not `main`, `master` or main_ref's name. `<branch>` is not a symref (K3a). The effective config (all scopes, includes, and `GIT_CONFIG_*` in the environment) has no `remote.*.push` or `remote.*.mirror` [M: K3]. The push may share its Bash call only with commands that cannot move HEAD, refs or config: `add`, `commit`, read shapes, `sleep`, and a retry loop's `break`. It is refused beside checkout, switch, merge, reset, branch, config, cherry-pick or revert, and when backgrounded (K3b). **ExitWorktree** with `discard_changes: true` is refused (C2-F13). | Each measured form: the 9 from E31, the symref push, and the same-call checkout or merge (K3a, K3b); `git -c core.hooksPath=H commit`, `git -c core.fsmonitor=CMD status` and `GIT_CONFIG_COUNT=1 ... git commit` (K3c); `git fetch . x:refs/remotes/origin/main` (K4); `git pull`; `git rebase --exec`; `git stash`; `git reset --hard`; `git clean -f`; `git checkout -- <path>`; `git branch -D`; `git branch -f main x`; `git symbolic-ref HEAD refs/heads/main`; the E32 plumbing chain; `git remote set-head`; `git config alias.x ...`; `git worktree add <path> main` | `git push -u origin HEAD` on a task branch; `git add -A && git commit -m x && git push -u origin HEAD`; `git -c core.quotepath=false log`; `git fetch -q --prune origin` then `git merge origin/main`; `git log --grep=stash`; `git checkout -qb new`; `git switch task` on a clean tree; `git init` in a scratch folder |
| G4 outside | new M131 | **gh by a list (`gh-shapes.txt`, plus the project's `.claude/method-local/gh-shapes.txt`):** `--version`, `help`, `--help` on any verb, `pr create\|view\|list\|diff\|checks\|comment`, `issue view\|list\|create\|comment`, `run list\|view\|watch`, `search repos\|code\|issues\|prs`, `repo view`, `auth status`, and `api` with GET only. Everything else is refused, including `pr merge`, every `api` call that writes, and `gist` (K4, K7). **HTTP clients:** `curl` or `wget` naming a GitHub host is refused unless it is a plain GET with no data, upload or method flag (check-v3). **Nested Claude (D11):** every `claude` command, by any path, after env assignments or under a carrier; `npx @anthropic-ai/claude-code`; assignments to `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_SIMPLE` or `CLAUDE_CODE_SAFE_MODE`. **MCP, by a list (D10, C2-F7):** read-only tools pass by name (`get_*`, `list_*`, `search_*`, `*_read`). Named write tools in `mcp-tools.txt` pass only when owner and repo are this repository's origin and the branch is not main. Same-session tools pass: `send_later`, `subscribe_pr_activity`, `unsubscribe_pr_activity`. Every other MCP tool is refused. **SendMessage** is refused in step 5. | `gh pr merge 1`; `gh api -X PUT repos/o/r/contents/x`; `gh api -f x=y repos/o/r/pulls`; `curl -X PUT https://api.github.com/...`; each nested form from E29; the MCP merge tool on two server names; `create_session`; `send_message`; `create_trigger` | `gh pr create`; `gh search code x`; `gh pr merge --help`; `gh api repos/o/r/pulls`; `curl -s https://api.github.com/repos/o/r`; an MCP write to a task branch of this repo; `send_later` |
| G6 protected | new M132 | **Paths in step 5 (C1-F3, K3, K5, check-v3):** `.claude/hooks/method/`, `.claude/agents/method/`, `.claude/rules/method/`, `.claude/method-local/`, `scripts/method/`, `.claude/settings.json`, `.claude/settings.local.json`, `~/.claude/settings*.json`, `~/.claude/{agents,skills,commands}/`, the managed-settings file and folder, `.git/hooks/`, `.git/config`, `~/.gitconfig`, `~/.config/git/`, the system git config, the folder an existing `core.hooksPath` names, and the method's files in git's own folder (`method-*`: the settings snapshot, the lock, the journal; in 5b the receipts). In 5b, also any `.claude/agents/**` file that declares a gate name (C2-F8). **Routes:** the edit tools, by the file's resolved path. MCP file tools, by path. **Bash:** a call that names a protected path may only read it, or run one of the method's own scripts. Every command word in such a call must be on the read-only list: `cat`, `head`, `tail`, `grep`, `ls`, `wc`, `diff`, `cmp`, `stat`, `file`, `sha256sum`, `shasum`, `md5sum`, `sort`, `uniq`, `cut`, `tr`, `nl`, `od`, `xxd`, `jq`, `cd`, `pwd`, `test`, `realpath`, `readlink`, `basename`, `dirname`, `sed` without `-i`, `find` without `-exec`, `-delete` or `-fprint`, `echo` and `printf` with no redirect into a protected path, and G3's read shapes. The method's scripts pass as `bash` or `sh` followed by a listed path under `scripts/method/`, with plain arguments and no `-c`. Anything else is refused (K2). **Recursive writes** (`cp -r`, `cp -a`, `rsync`, `tar -x`, `unzip`, `mv` of a folder) into a folder that holds a protected path, the repository root included, are refused. A write of one file is judged by its resulting path. **Git:** `cherry-pick`, `revert`, `merge`, `switch`, `checkout` and `worktree add` are refused when a protected file would end at a version other than HEAD's or `origin/<main>`'s. `origin/<main>` moves only by a plain fetch, which G3 limits (K4). | Each path; `cp -r x/. .claude/` and `cp -r x/. .` (K2); `dd of=`, `find -delete`, `git mv`, `tar -C` on a protected path; backslash paths with drive letters; a symlink into a protected folder; `..` and `//` forms; a different letter case where the file system folds case (A36); a merge of a branch that changed guard.sh | `cat .claude/settings.json`; `cd <repo> && sed -n 1,20p scripts/method/lib/git.pl`; `bash scripts/method/status.sh`; `.claude/skills/verify/**`; `cp notes.txt .`; `git merge origin/main` when main's guard.sh is the incoming one |
| G8 mutant-commit | new M133 | `git commit` while `RunState::probe` reports a mutate journal or a run, or cannot tell (A41) | A journal present | No journal |
| G12 effort (a warning) | new M134 | The first main-session tool call below xhigh gets one `systemMessage` and exit 0. No log until done-check reads one (C1-F9). | effort `low` | xhigh or max; a call inside a subagent |
| G15 outgoing-secrets | new M135 | Text that leaves the machine (C2-F14, K7): at `git push`, the messages and added lines of the commits it sends; in MCP writes, the `message`, `content`, `files[].content`, `title` and `body` fields; in gh, `--title`, `--body`, `-t`, `-b`, `--body-file` and `-F`. A secret, personal data, a claude.ai session link or a `Co-Authored-By` line naming Claude (A22) is refused and shown masked. It uses the same scanner library as the secret check (M066), so the rule is not implemented twice (M048). | A planted fake key in a pushed commit's message, in an added line, in an MCP `push_files` content, and in `gh pr create --body` | A clean push |
| G16 settings-change | new M136 | At ConfigChange (C2-F2, K5): in local or user settings, **any change to `env`**, to `hooks`, to `disableAllHooks`, to `enabledPlugins`, a removed `permissions.deny` entry, or `disableSkillShellExecution` turned off. Any mid-session change to the project settings. It compares with session-status's snapshot, which G6 protects; with no snapshot, it refuses a file that holds any of those keys. The client shows nobody a blocked change [D: hooks#configchange]. So each block goes to `guard.log`, status shows it, and the next guard call returns a one-time `systemMessage`: "a settings change was refused mid-session; it applies at the next session". | Each E28 route: local `disableAllHooks`, user env `BASH_ENV`, user env `PATH`; user env `BASH_FUNC_perl%%` (K5); `LD_PRELOAD` | A local change of an unlisted key, such as a theme. Your own `/plugin install` and project-scope `/permissions` are refused too; the one-time message says so. |
| G17 skill-and-agent-hooks | new M137 | At a `Skill`, `Agent` or `Task` call: refused when any definition of that skill or agent name, in the project or user folders or a readable plugin, declares `hooks` in its frontmatter and is not a method file. A skill's frontmatter hooks stay registered for the rest of the session once it is used [D: hooks#hooks-in-skills-and-agents; M: K1]. | The K1 skill `helper` with a PreToolUse hook; an agent file with hooks | A skill without hooks; the method's own agents |

**How refusals are worded:** one line, for example: `guard G3: pushing to main is refused. The owner merges on GitHub until review receipts exist (step 6). Push your task branch instead.` A refusal of a command that is not on a list names the list file and says the owner can add a shape there. A G0 refusal names the owner's way out (section 6.6).

**Each refusal also says: do not try another form of the same command; tell the owner what you needed.** A model that retries a refused push in another spelling is the case D8's option c misses.

**Log:** each refusal adds one line to `.method/local/guard.log`: time, rule ID, tool name, and the SHA-256 of the input, capped at 1,000 lines [I]. status gets a "guard" area: `LOOK - N refusals since <time>: <rule IDs>`, or `PASS - none`.

**What it prevents:** Claude landing changes (RISKS #4); lost work; edits to the method's own files and settings; switching the hooks off mid-session; a commit over a mutant; secrets leaving the machine; an unnoticed drop in effort; MCP tools, gh, nested runs and skill hooks getting around all of this.

**Proven to fire, and to hold:**
- Fixture tests for every rule and every list line, built from input shapes recorded from the real client.
- Harness, on the real client: one refusal per rule family; a Monitor command; an acceptEdits refusal; with `guard.sh` removed, the call is blocked [M: E1]; PATH without perl.
- **"Holds" cases, one per measured bypass (C2-F11):** the skill `!` line (E27); the skill frontmatter hook (K1); local `disableAllHooks`, user `BASH_ENV`, user `PATH` and `BASH_FUNC_perl%%` reloads (E28, K5); nested `claude` with a settings flag and from a subfolder (E29); each push form (E31, K3); the hook routes through `git -c` (K3c); the moved `origin/main` (K4); the plumbing chain (E32); the inline interpreters (K2). Each one is refused. A command-rewriting hook that is present before the session starts (E30) is a named known limit. Its case checks that session-status lists it.

**Cannot catch:**
- A program Claude writes to a file and then runs, and words put together at run time (RISKS #2).
- A renamed copy of the claude binary.
- MCP write tools whose names look read-only.
- A mod (D8); an owner-typed `!` command, unproven until step 9; anywhere hooks do not run.
- Over-matching is accepted. The refusal says why and what to do instead.

### 6.3 gate-receipt.sh (step 5b)

Kept here so 5b starts from a reviewed design. 5b's own plan revisits it after step 5 closes.

**Events and matchers:**
- SubagentStart and SubagentStop, matcher: the six gate names (exact), from a new `gate` kind in verdicts.txt.
- PreToolUse, matcher `SubagentHandback`, no onFailure (D4, C1-F5).

**At start:**
- Records: agent ID and type, time, HEAD, HEAD's tree, the clean state judged as lib/tree.pl does (untracked files counted), the base (A38), the SHA-256 of the agent's file.
- Finds every definition of that gate name: every `.claude/agents/` from the cwd up to the repo root, `~/.claude/agents/`, and plugin agents. More than one, or not the method's file, means INVALID (C2-F8).
- Returns `METHOD-ACTIVE v<version> gate=<agent> task=none` as context, at most 120 bytes (C1-F11) [M: E1].

**At handback (auto mode):** checks the verdict lines in `tool_input.message`. Missing on the first try: the JSON `permissionDecision: "deny"` (K10), with `End with your verdict lines. If you did not finish, answer ESCALATE.` On the second try: allow, and record INCOMPLETE.

**At stop:**
1. The report is the handback message if one was seen, otherwise `last_assistant_message`.
2. It must end with `END-VERDICT <tree>`, the tree at start. The reviewer and security-checker open with a verdict word; diagnose with ROOT CAUSE, SYMPTOM CHASE or SPEC QUESTION; all from verdicts.txt.
3. Missing in default mode: the first stop exits 2 with the same message; the second gives INCOMPLETE.
4. A refusal or an unreadable report is INCOMPLETE (M078).

**Evidence:**
- VALID needs a clean tree at start and at stop, and the same tree (C1-F6, C2-F9).
- While a gate runs, each write the guard sees from the main session or a non-gate agent marks the gate. A marked gate is INVALID: "files changed while it reviewed". This catches an edit made and undone mid-review without freezing work (C2-F9).
- The unchanged-files rule applies to reviewer, security-checker, diagnose and tester. Planner and reporter wait for step 6.
- `effort.level` equals the agent file's frontmatter; every model in the agent transcript is on the allowlist [M: E14].
- Tokens by class, each message ID counted once, and first-request cache reads. Transcript lines are filtered before decoding: 8.7 s against 0.25 s on 20 MB [M: E25]. No `spend.tsv` (C1-F9).

**Store:** under `git rev-parse --git-common-dir`, so a worktree's receipts survive the worktree (C1-F6) [M: E22]. One file per agent ID, written in one step, capped at the newest 500. Verdict lines, counts and hashes only.

**Cannot catch:** whether the verdict is right; a receipt forged through Bash; a crash at stop (onFailure has no effect there [D]; no receipt means "not checked"); a gate launched with a doctored prompt (step 6).

### 6.4 What the fragment registers

| Event | Matcher | Script | onFailure | Timeout | Step |
|---|---|---|---|---|---|
| SessionStart | none | session-status.sh | not set: cannot block [D] | 30 | 5 |
| PreToolUse | `Bash\|PowerShell\|Monitor\|Edit\|Write\|MultiEdit\|NotebookEdit\|ExitWorktree\|SendMessage\|Skill\|Agent\|Task` | guard.sh | block | 30 | 5 |
| PreToolUse | `^mcp__` | guard.sh | block | 30 | 5 |
| ConfigChange | `user_settings\|project_settings\|local_settings` | guard.sh | block: it works on this event (K5) | 30 | 5 |
| SubagentStart | the six gate names | gate-receipt.sh | not set | 30 | 5b |
| SubagentStop | the six gate names | gate-receipt.sh | not set: no effect there [D] | 60 | 5b |
| PreToolUse | `SubagentHandback` | gate-receipt.sh | not set | 30 | 5b |

The settings test checks:
- only the three named `.sh` files in the hooks folder;
- every command has the `BASH_ENV= ENV=` prefix and the quoted placeholder;
- `onFailure: "block"` on the guard's PreToolUse and ConfigChange entries;
- no `onFailure` on events where it has no effect (RISKS #16).

### 6.5 Considered and not built

- **A Stop hook:** `onFailure` has no effect there, and no gate rests on it (RISKS #16).
- **A prompt hook for owner records:** D7.
- **PreModelSwitch:** the allowlist already refuses a switch off the list [D].
- **A check after every tool call against what the guard saw (C2-F4):** D8.
- **ConfigChange on the `skills` source:** a skill's frontmatter hooks are registered when the skill is used, not when its file changes [D: hooks#hooks-in-skills-and-agents]. So G17 checks at the `Skill` call, which also covers a skill written before the session (K1).

### 6.6 When the guard blocks something it should not (C1-F2)

A README section in plain steps, built in 5.5:
- **On your own computer:** start Claude Code with `--settings '{"disableAllHooks": true}'`, or put `{"disableAllHooks": true}` in `.claude/settings.local.json` before you start the session [M: E20]. Both are shown to work by harness cases. The session then has no METHOD-ACTIVE line, which shows the method is off.
- **In a cloud session:** the guard refuses Claude's repairs, by design. Edit the file on GitHub's website (the exact clicks are written there), then start a new session.
- G16 refuses the same change when Claude makes it mid-session; it does not stop you at a session's start.
- RISKS records the cloud case.

---

## 7. The $0 harness

**What it is:** `tests/harness/`, built from the probe [M: E1]:
- `mock.pl`: a fake Messages API in core perl, on 127.0.0.1, port 0. Its readiness answer is read under an alarm (C1-F7) [M: E23].
- `bound.pl`: a time limit by process group, without GNU `timeout`;
- `run-case.sh`, with `cases/<name>/`;
- `VERSIONS`: the tested version and a SHA-256 per binary. The floor comes from REQUIRES (C1-F12);
- `tools.txt`: the client's tools from a `-p` run, each marked guarded or not, with a reason. ExitWorktree, SendMessage, Skill, Workflow and CronCreate are each given their reason. Tools that exist only in interactive or cloud sessions are outside its scope, and the README says so (C1-F14);
- test-only fixture hooks and a fake MCP server, never shipped.

**One case:**
1. Make a temp folder with `home/`, `project/`, `tmp/` and `mock/`. `project/` gets `git init`, one commit, the real fragment as `.claude/settings.json`, and the method's files laid out the way sync will.
2. Start the fake and check it answers, within a time limit.
3. Run the client with an environment built from an allowlist: `HOME`, `PATH=/usr/bin:/bin`, `TMPDIR=<case>/tmp`, `ANTHROPIC_BASE_URL=http://127.0.0.1:<port>`, `ANTHROPIC_API_KEY=dummy`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, `DISABLE_AUTOUPDATER=1`, and `HTTPS_PROXY=<the fake's trap>`. The runner refuses to start if the key is not `dummy`, or if any OAuth, auth-token, Bedrock or Vertex variable would pass (C1-F7).
4. Stop the fake.

**Assertions** look at effects: the fake's request log, files written, the fake MCP server's log, receipts. Never `permission_denials`, which leaves out exit-2 refusals [M: probe]. Every case also asserts:
- at least one request reached the fake;
- no outside connection was attempted;
- no case went over its request cap;
- nothing new appeared in `/tmp/claude-<uid>` (C1-F7) [M: E23].

**Plants for the harness's own checks (C1-F7):**
- WebFetch to `example.invalid` through the trap: the fake must log a CONNECT [M: E23];
- a base URL pointed at a dead local port: red;
- a request cap of 1: red.
- The README says the trap sees only traffic that honours `HTTPS_PROXY`; the $0 guarantee rests on the dummy key and the empty HOME.

**What it proves:** each hook is registered, fires and holds in the real client; the matchers; exit-code meaning; context reaching the model and the subagent; `onFailure`; the MCP refusal; real input shapes; the fragment loading; awkward paths; `core.autocrlf=true`; the tool list (a new tool turns the run red); the version.

**What it cannot prove:** how a real model behaves; the real API (tokens, cost, limits, fallback); auto mode [M: probe]; cloud and interactive behaviour; the real GitHub MCP server's argument names; Windows and macOS.

**Runtime:** 9 client runs took 8.1 s [M: E1]. Step 5's set is about 40 runs per version, so about 40 s per version [I].

**CI, Linux:**
- A separate `harness` job sets `METHOD_HARNESS_CLIENT`. `get-client.sh` fetches each version through the documented installer and checks the SHA-256 in VERSIONS [I: the exact command is confirmed in 5.2]. Cached by version.
- The job runs `bash tests/harness/run.sh` once per version, then one bypassPermissions case, which this machine cannot run as root [M: E26].
- With `METHOD_HARNESS_CLIENT` set and no client: the job fails (a plant shows it). Without it, `tests/harness.test.sh` prints SKIPPED. The existing Linux, Windows and macOS jobs stay green (C1-F1).
- Every action is pinned by commit (`lint-workflows`).

**Windows and macOS:** not run until A27's later run. Known gaps [I]: `env -i` under Git Bash drops `SYSTEMROOT`; msys perl's process groups need their own check.

**False refusals (C1-F8):** in 5.5, the guard's command reader is run over the Bash commands recorded in this machine's session transcripts (15,845 [M: E24]). Local only. Only counts per rule are reported; the commands are never committed or printed, since they may hold secrets.

---

## 8. Increments, in build order

Each increment gets a fresh-context review: a five-part report and a verdict (AGENTS.md), with records updated before it, at most 3 rounds. The number of reviewers per round is set by D13. Each increment names one line you will see, copied from a log (C1-F13).

### Step 5

**5.1 Shared helpers.**
- `lib/hook.pl`, `lib/log.pl` (the M072 home); `lib/json.pl` split into a library and its command line, with `get` unchanged (C1-F14); `lib/secrets.pl` gets a function for text, with the command-line output unchanged.
- **Acceptance:** the existing tests pass unchanged; `scan-secrets.sh` output byte for byte the same; `hook.pl` handles empty, malformed, over 4 MB and control-character input; `log.pl` takes fixed fields only; a 5,000-line log is trimmed to its cap, keeping the newest.
- **Plants:** trimming removed; masking removed; a free-text field let into the log; escaping removed.
- **You will see:** `scan-secrets: output identical on 65 files` and `log: 5000 lines trimmed to 1000`.

**5.2 Harness skeleton, with D1's records.**
- `tests/harness/*`, `tests/harness.test.sh`, the CI job; REQUIRES, SPEC and the status tests at 2.1.316.
- **Acceptance**, with fixture hooks: SessionStart context reaches the request; a fixture refusal reaches the model; SubagentStart context reaches the subagent; a stop block gives a second turn; a missing script blocks under `onFailure` only; the MCP fixture refusal stops the fake tool; the safety checks of section 7; the tool list; the version.
- **Measured and recorded:** starting in a subfolder [M: E12]; the `resume` source.
- **Plants:** no guard (the push runs); the fake never answers; a line removed from `tools.txt`; the wrong binary; the three safety plants; `METHOD_HARNESS_CLIENT` set with no client.
- **You will see:** the CI harness job listing each fixture proof as PASS at 2.1.316 and 2.1.319.

**5.3 Settings fragment and settings test.** Section 5, without `hooks` and the `permissions.deny` entries (each hook entry comes with its hook, from 5.4; the deny entries come in 5.8). M076, M104 and M138 are done here.
- **Plants:** each key wrong or missing; each never-set key present; a fourth hook script; a missing `BASH_ENV= ENV=` prefix; an unquoted placeholder; `onFailure` on SubagentStop; a rejected value shape.
- **You will see:** `fragment loads: model claude-opus-5-5, effort xhigh, skill shell lines off`.

**5.4 session-status.sh.** Section 6.1, the status.sh changes, the first README section.
- **Plants:** exiting with status's code (the line goes missing [M: E9]); no line cap; no byte cap; the ci area run (a fake `gh` writes a marker); METHOD-ACTIVE printed from perl only (missing when the library is gone).
- **You will see:** the first request of a harness session, carrying `METHOD-ACTIVE vunreleased` and the status lines.

**5.5 Guard frame.** The command reader (quotes, `bash -c`, `&&`, `;`, CRLF, here-docs) with its own corpus tests; G0, G1, G2; the log and status's guard area; the fast exit; the fragment's PreToolUse entries; README section 6.6 with both break-glass harness cases; the false-refusal run.
- **Plants:** each G0 item removed; the fast exit taken for a call with a watched word; the log cap removed; a refusal by exit 1 instead of 2.
- **You will see:** a table from the false-refusal run: commands read, refused, and per rule.

**5.6 The git list: G3 and G8.** `git-shapes.txt`, the push checks, the effective-config read, ExitWorktree. The false-refusal run is repeated over every recorded git command, and each refused shape is either added to the list with a reason or kept refused with a reason.
- **Plants:** each list line removed or widened, one at a time, in a throwaway copy; a list line without a reason; the push-alone check removed; the symref check removed; the effective-config read limited to the repository file.
- **You will see:** a table of commands, each refused or allowed with its reason, and the share of recorded git commands the list refuses.

**5.7 Protected files: G6 and G12.** The paths, the read-only rule for Bash, the edit and MCP routes, the git version check, the path forms.
- **Plants:** each protected path dropped; a write word added to the read-only list; the recursive-write rule removed; path resolution of `..` and symlinks removed; the git version check removed.
- **You will see:** `perl -e` and `python3 -c` writes to guard.sh refused, `cat .claude/settings.json` allowed, and `git merge origin/main` allowed.

**5.8 Outside: G4, `gh-shapes.txt`, `mcp-tools.txt`, the `permissions.deny` entries.** The deny entries stay only if the harness shows no startup warning [M: E13]. The false-refusal run is repeated over the recorded gh commands.
- **Plants:** each gh and MCP list line widened; the GitHub-host check for curl removed; the nested-Claude rule removed; a deny entry dropped.
- **You will see:** `gh pr merge` and the MCP merge tool on two server names refused, `gh pr create` allowed.

**5.9 Settings changes and skill hooks: G16, G17,** the hook-command prefix and `command perl` proven in the harness; all "holds" cases of section 6.2.
- **Plants:** each G16 key dropped; the snapshot rewritten on `compact`; the prefix removed; `command` removed before perl; G17's frontmatter check removed.
- **You will see:** each E28 and K5 route refused, each with its guard.log line, and the K1 skill refused.

**5.10 Outgoing secrets: G15.** The push scan, the MCP fields and the gh text fields; the push-scan time measured. If the step has run long, this increment can move to Release 2 with RISKS #10's history scan. I would tell you before moving it.
- **Plants:** each scanned field dropped; masking removed.
- **You will see:** a planted fake key refused at push and in `gh pr create --body`, shown masked.

**5.11 Close step 5.** The README complete; a planted-break run over all hook code; costs copied from logs; records cross-checked; CI read after the push. Then you say "merge", and I merge with the verdict line in the merge commit (A30).
- **Exit:** every step-5 rule-map row done or moved, with a reason; CI green with the harness at both versions.
- **You will see:** the step report's table of rules, each with its harness PASS line and its planted break turning red, copied from the CI log.

### Step 5b

- **5b.1 The gate's life:** start record, duplicate definitions, gate context, handback check, END-VERDICT and first-line checks, block-once, INCOMPLETE, the one-step write, the store, status's gates area; new kinds in verdicts.txt (A10's words unchanged).
- **5b.2 Evidence:** clean at start and stop, the guard's write marks, the tree key, effort, model, tokens, cache reads, the agent-file hash; a 50 MB transcript read within a stated time.
- **5b plants:** the verdict check removed (a cut-off reply turns VALID); "No such file" in the block text; block-once allowed twice; the 120-byte budget removed; the duplicate-definition check removed; the write marks ignored.
- **5b.3 Close step 5b.**
- **You will see:** a receipt printed in plain words: "reviewer: VALID for files a1b2c3, Opus 5.5, xhigh"; and a cut-off reply giving "INCOMPLETE: not checked".

---

## 9. Records to update

Each increment updates the records it touches, before its review.

**docs/rule-map.md:**
- New rows M128 to M137 for the guard rules (section 6.2), each with its reason and home `guard.sh`. New row M138 for `disableSkillShellExecution` and M139 for the `permissions.deny` entries, both homed in the fragment (K9).
- M053 done in 5b. M072: home moves to `lib/log.pl`, done in 5.1. M073 done in 5.11. M076 and M104 done in 5.3. M078, M106 and M116 done in 5b.
- M106 reworded: "An approval covers one exact version of the files; any change to them voids it" (A35).
- M079 moves to `method/.claude/rules/method/method.md`, step 6: a multi-repository session runs no repo hooks.
- M117 moves to step 6. M075 gets a note on `skillOverrides`.

**TESTS.md:** rows for `settings.test.sh`, `session-status.test.sh`, `guard.test.sh`, the helper tests and the harness; planted-break sections; known limits; "Where CI runs" gets the harness job; the two byte budgets as R12 budgets.

**DECISIONS:**

| Entry | What it records |
|---|---|
| A45 | The floor (D1) |
| A46 | Landing by Claude refused until step 6 (D2) |
| A47 | Hooks not wired in this repo until step 7; then this repo runs the last release's copy (D3) |
| A48 | Auto mode kept; the handback check (D4) |
| A49 | The harness: a local fake, $0, pinned versions with checksums, its own CI job (D6) |
| A50 | The guard is a seatbelt built from allowed lists for git, gh and MCP, with a read-only rule for method files; its known limits; the locks outside the session (D8) |
| A51 | Skill shell lines off (D9) |
| A52 | MCP tools from a list (D10) |
| A53 | No nested Claude until the step 6 wrapper (D11) |
| A54 | Step 5 split into 5 and 5b (D12) |
| A55 | `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` rejected, measured [M: E7, E8] |
| A56 | Rows moved and reworded: M072, M079, M106, M117 |
| A57 | The guard refuses what it cannot read when the command touches what it watches; over-matching is accepted |
| A58 | No Stop, prompt or PreModelSwitch hooks; no after-the-call check |
| A59 | session-status skips the ci area and prints `vunreleased` until step 7 (v1's A58, kept, K9) |
| A60 | The workflows setting withdrawn from step 5, to step 6 (D5) |
| A61 | No approval recorder until step 6 (D7) |
| A62 | Reviewers per round in steps 5 and 5b (D13) |
| 5b | Receipt key and store; new kinds in verdicts.txt |

**RISKS:**
- #2: add a program written and then run; words put together at run time; a renamed copy of the claude binary; MCP write tools whose names look read-only; a route that replaces the guard's own file; a rewriting hook present at session start; the measured friction of the lists.
- #3: add the harness and the pinned versions.
- #4: the guard refuses Claude's landing in projects; this repo is not covered until step 7.
- #16: add the trust dialog, the owner's local switch-off, starting in a subfolder, mods, settings or PATH changed between sessions, a managed policy file, and `BASH_ENV` under Git Bash; a cloud session's only repair is an edit on GitHub.
- New #17: hooks cannot see the client version or effort at session start; `/start` checks them.
- New #18 (5b): the SubagentHandback path is fixture-only until step 9.

**Other records:** ROADMAP gets the 5b line (D12). SPEC: the "Supported versions" row (D1). CHANGELOG: one entry per increment. TASKS: a step 5 section with 5.1 to 5.11 and the notes in section 11.

---

## 10. Risks and limits of this step

- **Words, not a parser.** The guard over-matches by design and still misses what it cannot see (RISKS #2). CI and done-check stay the net.
- **The guard runs from the working tree.** A model set on it can still replace it by a route the guard cannot read. The review and CI see that change afterwards.
- **Receipts (5b) are local files.** They show consistency, not authenticity.
- **Hooks are client-side.** They do not run in several places (D8, RISKS #16).
- **An undocumented variable.** status's version check relies on `CLAUDE_CODE_EXECPATH`, which is not documented and is absent in hooks [M: E1].
- **A new client version** can change hook inputs. The harness checks shapes and the tool list when it runs (RISKS #3).
- **Size.** Step 5 is about as large as step 4. If an increment needs more than 3 review rounds, I stop and report (AGENTS.md).

---

## 11. Notes for later steps, found while planning

- **Step 6:**
  - The "no METHOD-ACTIVE line" rule must load when Claude Code starts in a subfolder [M: E12].
  - `/finish` waits for background gates and makes no edits while they run.
  - The packet carries the tree ID for END-VERDICT.
  - The nested-run wrapper (D11), the workflows setting (D5), owner records (D7), the Agent-launch guard, M117.
  - Which files planner and reporter may write.
  - Whether a flow needs SendMessage.
  - The touches-method route for workflows, the incident checklist and domain rules.
  - Plants are reverted in a throwaway copy (AGENTS.md), so G3's refusals do not block the checks skill (C1-F3).
- **Step 6, skills and agents:** method skills and agents declare no frontmatter `hooks` (G17), and use no `!` lines (D9).
- **Step 7:** sync writes `minimumVersion` from REQUIRES; method.lock supplies the version and records a hash of every installed method file; wire the hooks into this repo from the last release (D3). Decide GitHub branch protection (a paid plan, RISKS #4) before the method enters your projects (D8).
- **Step 9, project CI templates:** a CI check that every installed method file equals method.lock's hash. It runs outside the session, so it catches a guard replaced by a route the guard cannot read (D8, RISKS #2).
- **Step 9, live cloud test:** the SubagentHandback path; phone and web prompts; `!` commands; SessionStart `clear` in the cloud; one repository against several.

---

## 12. Evidence index

Evidence E1 to E18 is from version 1's planning runs. E19 to E32 come from the two critics' runs, with their commands in their reports. The repo was only read; `git status` is clean at d3159a1.

| ID | Command | Result |
|---|---|---|
| E1 | `cd step5plan/probe && time bash run-all.sh` | 26 PASS, 0 FAIL, real 8.1 s, client 2.1.319. Every hook event fired; PreToolUse effort xhigh; no effort on SessionStart or SubagentStart; exit-2 and JSON denies reached the model; `CLAUDE_CODE_EXECPATH` unset in hooks; a missing script blocked under `onFailure` and ran without it; a SubagentStop exit 2 gave a second turn; an Agent effort override showed as effort `low`; the `mcp__.*` deny stopped the fake merge tool; no outside connection. |
| E2 | `claude --version`; `ls`, `readlink -f`, `file` | 2.1.319; a native ELF of 340,226,576 bytes. |
| E3 | `status.sh`, 3 runs; then without gh, 3 runs | 1,495 to 1,753 ms; without gh 109 to 117 ms. |
| E4 | timed `lib/json.pl get` ×5; bare bash; perl with modules | 18.8 to 23.5 ms; 7.7 ms; 23.8 ms. |
| E5 | `bench/guard-proto.sh` ×50 | 18.7 ms per call, with no method libraries. |
| E6 | `perl lib/secrets.pl --repo scripts/dev/scan-allow.txt` | 358 ms; 65 tracked files; PASS. |
| E7 | `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` and a probe variable in project settings' env | Hooks and Bash still had `ANTHROPIC_API_KEY` and `CLAUDE_CODE_MESSAGING_TOKEN`; the probe variable reached both. |
| E8 | the same variable in the process environment | rc=1: bubblewrap required. |
| E9 | SessionStart hook printing text, exiting 0 or 1 | Exit 0: in the request. Exit 1: absent. |
| E10 | agent file at `.claude/agents/method/reviewer.md` | Subagent events fired with `agent_type` "reviewer". |
| E11 | `claude -p --output-format stream-json --verbose` | Init event: model, permissionMode, `claude_code_version` 2.1.319, and the tool list. |
| E12 | client started in `project/sub` | No hook fired; `git push origin main` ran; effort "medium" against "xhigh" at the root. |
| E13 | `permissions.deny` naming the GitHub MCP merge tools, no MCP server | No stderr warning in `-p`. |
| E14 | read the probe's transcripts | Agent lines carry `message.model`, `message.id` and `message.usage`. |
| E15 | read the probe's recorded hook inputs | No `model` on SessionStart in `-p`; PreToolUse has `effort`; a background gate lists itself in `background_tasks`. |
| E16 | read `lib/status.pl` 342 to 371 | The floor and effort checks need `CLAUDE_CODE_EXECPATH`. |
| E17 | `cat .gitignore` | `.method/local/` is ignored. |
| E18 | `cat .claude/settings.json` | No hooks. |
| E19 | C1: probe re-run in a copy | 26 PASS, 9 s, $0. A `<task-notification>` prompt reached UserPromptSubmit with the same fields as a typed one. The fake's request log carries `output_config.effort`. |
| E20 | C1: onfail-block settings with local `disableAllHooks`, and with `--settings` | The Bash call ran both times. |
| E21 | C1: `perl -e` failed open then die; `require` of a missing file | Both exit 2. A plain die gives 255. |
| E22 | C1: `git rev-parse --git-path method-receipts` in a worktree | A folder under `.git/worktrees/wt/`, deleted with the worktree. |
| E23 | C1: WebFetch to `example.invalid` through the trap; a silent listener; `ls /tmp/claude-0` | CONNECT-REFUSED logged; the readiness read hung until killed; 18 leftover folders; TMPDIR moved them into the case folder. |
| E24 | C1: bench with git.pl, runstate.pl, esc.pl, JSON::PP, Digest::SHA, 40 runs; count of recorded Bash commands | Medians 32.6 / 34.4 / 43.1 ms (no git / 2 git calls / 7 git calls), p90 up to 48.7 ms; 15,845 recorded commands. |
| E25 | C1: JSON::PP over a 20.7 MB transcript | 8.74 s for every line; 0.25 s for lines holding "usage". |
| E26 | C1: acceptEdits and bypassPermissions cases | acceptEdits: the exit-2 deny reached the model. bypassPermissions: refused as root. |
| E27 | C2: a project skill with a `!` line, with and without `disableSkillShellExecution` | Without: no PreToolUse event, marker created. With: placeholder text, no marker. |
| E28 | C2: mid-session writes to local `disableAllHooks`, user env `BASH_ENV`, user env `PATH` | Each switched the guard off and the marker was created. A ConfigChange hook exiting 2 blocked each; the `BASH_ENV= ENV=` prefix stopped the BASH_ENV route. |
| E29 | C2: nested `claude -p` with `--settings '{"disableAllHooks":true}'`, and from a subfolder | Both created the marker; the same run from the root was refused by the nested guard. |
| E30 | C2: a user PreToolUse hook returning `updatedInput` | The guard allowed `echo SAFE`; the rewritten `touch` ran. |
| E31 | C2: nine push forms against a bare remote; `git remote set-head` | Each moved origin's main; set-head moved `Git::main_ref`. |
| E32 | C2: `hash-object -w`, `read-tree`, `update-index --cacheinfo`, `write-tree`, `commit-tree`, `merge --ff-only` | guard.sh in the working tree became `exit 0`, with a clean tree. |
| K1 | K: `check-v2/run-x.sh skillhook`: a project skill with a PreToolUse frontmatter hook, with `disableSkillShellExecution: true` | The guard logged "allowed Bash"; the skill hook's marker was created; the `!` line's marker was absent. |
| K3 | K: plain git 2.43 in `check-v2/g1` to `g3`, `g5` | A command-line `<branch>` refspec was still remapped by `remote.origin.push` (`task -> main`); `HEAD` was not. A symref branch, a checkout or merge earlier in the same call, `-c core.hooksPath`, `-c core.fsmonitor`, `GIT_CONFIG_*` and an appended `.git/config` each got work onto main. |
| K4 | K: `check-v2/g4` | `git fetch . evil2:refs/remotes/origin/main` moved origin/main with no `+`; a following `git merge origin/main` put `exit 0` into guard.sh. |
| K5 | K: `check-v2/bf` | With bash as the shell, `BASH_FUNC_perl%%` in the environment made the guard's perl a no-op returning 0; dash dropped it. |
| E33 | C2: `id` in a cloud session | uid=0. |
| F1 | check-v3 friction: `check-v3/friction/friction.pl` over the 648 transcript files on this machine (16,014 Bash calls, shapes only, no raw text kept) | With v3's first lists, G3 refused 161 of 842 main-session git commands in this repo (19.1%); with the shapes now added, 35 (4.2%). G4 refused 24 of 110 gh commands before the additions. Of the git commands, 61% were in throwaway folders under /tmp. The corpus is from building this repo, not from your projects. |

Docs pages cited are under `https://code.claude.com/docs/en/`. Saved copies are in `step5plan/req-docs/` and `step5plan/crit/docs/`.

---

## 13. What this version does with each critic finding

| Finding | Disposition |
|---|---|
| C1-F1 CI wiring | Accepted: `METHOD_HARNESS_CLIENT`, own job, SKIPPED elsewhere, plant (D6, section 7) |
| C1-F2 no way back | Accepted: section 6.6, harness cases, D3's step-7 design, RISKS #16 |
| C1-F3 rules without rows; G6 too wide | Accepted: rows M128 to M139; G6 narrowed; the waits table; the plant-revert note in section 11 |
| C1-F4 perl exit 2 | Accepted: section 6.0 wrapper codes, plants in 5.4 and 5b |
| C1-F5 handback route | Accepted: PreToolUse deny on SubagentHandback (D4, 6.3) |
| C1-F6 receipt states, worktree store | Accepted: clean at start; four gates only; common-dir store (6.3) |
| C1-F7 harness safety plants, hang, leftovers | Accepted: section 7 plants, alarm, TMPDIR, env allowlist, README note |
| C1-F8 increments too large; false refusals | Accepted: 5.5 to 5.10 split; the false-refusal run; outside-repo commands pass |
| C1-F9 items with no requirement | Accepted: D5 withdrawn; spend.tsv cut; G12 log cut; G15 given a row and its own increment; M075 note |
| C1-F10 cost | Accepted: fast exit, lazy loading, p90 target, transcript filter, inner 5 s limit, Git Bash estimate |
| C1-F11 byte budgets | Accepted: 1,200 and 120 bytes, with plants |
| C1-F12 floor's second home | Accepted: floor from REQUIRES; D1 lands in 5.2 |
| C1-F13 owner-visible acceptance | Accepted: one "you will see" line per increment; 1.4c marked as docs; D2 reworded |
| C1-F14 small gaps | Accepted: (a) push allowed list covers it; (b) acceptEdits and bypassPermissions cases; (c) tools.txt scope; (d) R10 citation removed; (e) json.pl split |
| C2-F1 skill `!` lines | Accepted: D9, harness case |
| C2-F2 mid-session settings | Accepted: G16, the prefix, G6 on `~/.claude`, status's settings area, known limit for the next session |
| C2-F3 nested Claude | Accepted: D11 |
| C2-F4 rewriting hook | Partly: G16 blocks adding one mid-session; session-status lists those present at start; the after-the-call check is not built (D8) |
| C2-F5 push forms, set-head | Accepted, then widened in v3: the git list (G3) refuses every form not listed |
| C2-F6 git routes replace guard.sh | Accepted: plumbing is not on the git list (G3); G6's version check for the commands that bring in files; residual risk in D8 and RISKS #2; answer 1.4a reworded |
| C2-F7 MCP forbidden list | Accepted: D10 |
| C2-F8 duplicate reviewer | Accepted for 5b: duplicate definitions mean INVALID; G6 protects gate-name files |
| C2-F9 gate approves unseen files | Accepted for 5b, without the write freeze: write marks make the receipt INVALID |
| C2-F10 answer 4d and G0 | Accepted: G0 defined as a list; answer 1.4d reworded |
| C2-F11 harness never tests holding | Accepted: "holds" cases (6.2, 5.9) |
| C2-F12 path forms | Accepted: section 6.0 path resolution, G6 planted inputs |
| C2-F13 ExitWorktree | Accepted: matcher and G3 |
| C2-F14 G15 and MCP | Accepted: G15 scans MCP write fields |

### What version 3 does with each of the checker's findings on version 2

| Finding | Disposition |
|---|---|
| K1 skill and agent frontmatter hooks | Accepted: G17 at the `Skill`, `Agent` and `Task` call; 6.5 corrected; a "holds" case |
| K2 inline interpreters write method files | Accepted: G6's read-only rule for any Bash call that names a protected path or a folder above one; G0 lists inline programs |
| K3 push and hook routes on main | Accepted: the git list (G3), with push alone in its call, no symref branch, no `-c` beyond four keys, no `GIT_*=`; `.git/config` and the git config files in G6 |
| K4 a locally moved origin/main | Accepted: fetch with no refspec and not from `.` or a path; `pull`, `rebase --exec` and the other carriers are not on the list; `gh api` writes refused (G4) |
| K5 G16 details | Accepted: the snapshot protected; any env change refused; `command perl`; `onFailure: "block"` on ConfigChange; a one-time message for blocked changes; the three known limits added to D8 |
| K6 build cost | Accepted: D13 and section 0's cost line |
| K7 overclaims | Accepted: section 0, answer 1.4a, G15 covers gh text, D11's renamed-binary limit |
| K8 deny names by server | Accepted: globs; D10 says what it means for you |
| K9 records | Accepted: rows M138 and M139; M079 citation fixed; A59 to A62; 5.11's "you will see" line |
| K10 handback deny form; D9's reach | Accepted: JSON `permissionDecision: "deny"`; D9 note |

### What version 3 does with the version 3 checks (check-v3)

Three checks ran on version 3: a consistency check, a friction measurement and a red team of the allowed lists. The red team stopped before measuring anything, because a safety check stopped its response. It was not re-run in another form. So the allowed-list design has had no bypass review yet. Each guard increment's three-reviewer rounds include a security reviewer, who tests that increment's rules against bypasses.

| Finding | Disposition |
|---|---|
| G6's read-only rule refused the method's own scripts and `cd` | Accepted: the method's scripts pass by listed path; the read-only list widened (`cd`, `sed` without `-i`, and others); "a folder above" now applies only to recursive writes |
| C2-F8's G6 clause dropped in v3 | Accepted: put back (5b) |
| Lists in a protected method folder need a release to grow | Accepted: each project's `.claude/method-local/` lists, protected, read by the guard |
| Interpreters as watched words contradicted the look-alikes | Accepted: removed; G0's inline-program item applies when the call names a watched word |
| The snapshot rewritten on compact | Accepted: written only at a session's start |
| Overclaims: E30 and managed policy; subfolder start; curl to GitHub | Accepted: section 0 reworded and a subfolder line added; G4 judges curl and wget to GitHub hosts |
| The friction line incomplete | Accepted: section 0 lists each kind of friction |
| Section 8 header against D13 | Accepted |
| 5.3 against 5.8; when M138 and M139 are done | Accepted |
| RISKS lines missing D8's limits | Accepted |
| System git config and managed settings not protected | Accepted: added to G6 |
| `worktree add` outside the version check | Accepted: limited to a new branch from HEAD, and added to the check |
| Increments 5.5 to 5.10 and 5b had no plants | Accepted: a plants line each |
| Naming and evidence references | Accepted: section 3's title; "both review rounds"; Task in row 5; M128 covers G0 and G1 as one rule; M139 in C1-F3; E33 added |
| Cost: plan usage; push time | Accepted: section 0 and the speed line |
| Friction: the lists refused 19.1% of main-session git commands in this repo | Accepted: the shapes recommended in F1 were added (4.2% after); git aimed at another repository is judged only for push, remote and global config |
