# Step 5b plan: gate-receipt, the third hook

**Version 2**, 9 November 2026: version 1, drawn from a map of the code built in step 5 and a first round of measurements, went to two critics (one looked for ways a run could get a VALID receipt it should not, or honest work refused; the other for what was not measured or did not fit the code); their findings and a second round of measurements with the real client at 2.1.316 and 2.1.319 shaped this version. The owner left the decisions to me ("i trust ur judgment"); B1 to B12 are recorded in DECISIONS when 5b closes (5b.3). The measurement scripts, runs and critiques stayed in the planning session's scratch space and are not kept here.

This plan starts from docs/plans/step5.md section 6.3 (reviewed) and section 8's 5b. It changes them where the client facts measured for this plan (2.1.316 and 2.1.319, at $0 against the local fake), the code built in step 5, or DECISIONS A63 to A69 require it; section 3 lists each change. Labels: [M] measured for this plan, [D] documented, [I] inferred. Process: A66 (one review, one repair loop; fix what a careless agent could plausibly hit, record the exotic as known limits).

## 0. In plain words

**What it adds.** When a checking agent (a "gate") finishes, gate-receipt writes a receipt: did it finish with its verdict lines, on which model and effort, and did it look at the committed files, unchanged while it worked. In 5b the gates are the reviewer, the security checker, diagnose and the tester; planner and reporter join in step 6.

**What it stops.**
- A cut-off review counted as an approval: a reply without its last line, `END-VERDICT <files id>`, is sent back once; still without it, the receipt says INCOMPLETE (not checked).
- A stale review: one made on uncommitted files, on files that changed while it worked, or on a packet built for other files. INVALID.
- A gate quietly running off the allowed models or below its effort, or handing its work to another agent. INVALID.
- A gate run from a definition other than the method's own file (another file with its name, a plugin's, one given on the command line): the gate's actual instructions are compared with the method's file. INVALID.

**What it does not stop.** Whether the verdict is right. A receipt forged by a program Claude writes and runs (receipts are local files; RISKS #2). Until step 6 nothing reads receipts: done-check still reads the typed verdict line. No receipt is made where hooks do not run.

**What you will see.** After each gate, one plain line, for example `gate-receipt: method-reviewer VALID for files a1b2c3d (claude-opus-5-5, xhigh)` or `gate-receipt: method-reviewer INCOMPLETE - not checked: no END-VERDICT line`. In CI, the harness lines for each case at both pinned versions.

**What it costs.** About 0.05 s at a gate's start and up to about 0.1 s at its stop, while the client finishes writing the agent's record [M]; at most one extra turn for a gate that ends without its lines; one review and one repair loop to build (A66).

## 1. Decisions (recommended; the owner said "i trust ur judgment")

**B1. The gates and their words.** The gates are named `method-reviewer`, `method-security-checker`, `method-diagnose` and `method-tester`, each defined in `.claude/agents/method/` (which G6 protects). A prefix keeps them apart from the reviewer or tester agents projects often have already: measured, with two files of one name the client silently used either [M]. Each opens its report with words from verdicts.txt: reviewer and security checker A10's verdict words; diagnose `ROOT CAUSE`, `SYMPTOM CHASE` or `SPEC QUESTION`; tester `TESTS PASS`, `TESTS FAIL` or `TESTS NOT RUN` (bare PASS and FAIL are status's words). verdicts.txt gains the kinds `gate-verdict`, `gate-diagnosis` and `gate-test-result` (each line: the gate's name, then its words, so the mapping has one home), `receipt` (VALID, INVALID, INCOMPLETE) and `end-key` (END-VERDICT). A10's words stay.

**B2. The report's form.** The first non-empty line is `<word>` alone or followed by a space or a colon; the last non-empty line is exactly `END-VERDICT <tree>`, the tree given at the gate's start. Trailing spaces and CRs are stripped; markdown emphasis or a heading on the first line is not accepted, and the refusal says the exact form. The five-part report sits between. Step 6's agent files and AGENTS.md say the same order.

**B3. The tree at start.** The start answers with `METHOD-ACTIVE gate=<name> tree=<tree>` through additionalContext, which reaches only the gate [M]; at most 120 bytes, also for SHA-256 repositories (64 hex). review-packet.sh's header gains a `Tree:` line, so a packet can be matched to the files it was built for.

**B4. The store.** One file per gate run in git's common folder, `method-receipt-<16 hex of SHA-256 of session and agent ids>.json` (G6 protects `method-*` there; a subfolder would not be [M]), written whole (O_EXCL temporary, then rename), the newest 500 kept with explicit times. One keep-N writer in lib/log.pl, which G16's snapshot uses too.

**B5. The states.** VALID: every check holds; the receipt carries the opening word (ESCALATE included). INVALID (it checked the wrong thing or the wrong way): unclean at start or at stop; the tree changed; a write mark in its window; its instructions not the method file's; effort below the file's on some turn; a model off the list; it called Agent or Task; it ran in another folder; a packet for another tree in its prompt or reads. INCOMPLETE (not checked): no start record; no report; the lines still missing after the one retry; its record not complete in time; a background task of its own still running at stop; a reply the client wrote itself (`<synthetic>`); unreadable input; a crash. Each stop first writes INCOMPLETE "judging", then the result, so a crash never leaves an earlier VALID standing. Every reason is listed.

**B6. Default mode: block once.** At a stop whose report lacks its lines, exit 2 once with a plain reason that gives the exact first and last lines and asks for the whole report again. "Once" comes from the receipt's note, never from stop_hook_active, which the client sets after its own nudges [M]. No block when an INVALID reason known at start already holds.

**B7. Auto mode.** The client offers SubagentHandback to the gate [M]. At its PreToolUse: lines missing on the first try, deny with the same reason; on the second, allow and record INCOMPLETE (the client sets no limit on denials [M]). The report is the accepted handback's message. At stop: block only when no handback was seen and permission_mode is not auto; after an accepted handback a block has no effect [M].

**B8. Write marks.** While a gate runs, a call from the main session or a non-gate agent that G6 counts as writing (its `$writes` test, already built and planted) marks the gate, after every refusal check, with a Time::HiRes time and the worktree's top; marks strictly after the gate's start, in its own worktree, count. A foreground gate blocks the main session, so marks matter for background gates and parallel calls. A gate's own calls never mark.

**B9. Effort and models.** The method file's `effort:` is required; every turn's effort in the agent's record (each assistant line's effort and the request's) must be at least the file's (low < medium < high < xhigh < max). Every assistant line's model must be on the project settings' `availableModels` (none set: INVALID); at least one model-bearing line is required. Hooks get no model field [M].

**B10. The instructions check.** The agent's record holds the system prompt the client built from the definition it used (a prompt_snapshot line) [M]. It must equal the method file's body (without frontmatter). This covers another file with the gate's name, a plugin's agent, `--agents`, and a definition cached before a mid-session merge changed the file.

**B11. Crashes.** Any exit but the deliberate block is exit 0, at every event: at SubagentStop exit 2 sends the gate back to work, and at the handback a refusal on every crash would loop. The receipt stays INCOMPLETE.

**B12. Deferred to step 6.** status's gates area, done-check reading receipts, planner and reporter, a G6 rule for agent files outside `.claude/agents/method/` (B1's prefix and B10 make it unneeded now).

## 2. The design

**Entries** (fragment), each `BASH_ENV= ENV= bash -p "$CLAUDE_PROJECT_DIR/.claude/hooks/method/gate-receipt.sh"`, no onFailure: SubagentStart and SubagentStop with matcher `^(method-reviewer|method-security-checker|method-diagnose|method-tester)$` (timeouts 30 and 60), PreToolUse `SubagentHandback` (30). The hook also checks agent_type against the words.

**At start.** Record gate, agent and session ids, time, the checkout's top, HEAD, its tree, clean (Checks::fingerprint, untracked files counted), the method file's SHA-256 and effort. Answer with the context line. Outside a git repository: no receipt; `tree=none`.

**At handback.** B7. Record the message's SHA-256 and the tool call id.

**At stop.** (1) INCOMPLETE "judging". (2) The report: the accepted handback's message, else last_assistant_message, else none. (3) Its lines (B2); missing: B6. (4) Wait for the record: poll its tail, at most 5 s, for the END-VERDICT text or the handback id; paths from the input go through utf8::encode; a regular file of at most 200 MB. (5) Read the record, decoding only lines of type assistant, user and the first prompt_snapshot; usage counted once per message id. (6) Evidence: clean and tree again, marks, B9, B10, Agent or Task calls, cwds, background_tasks of its own, packet trees. (7) Write the receipt; print the plain line as a systemMessage (5b.1 measures whether the client shows it).

**The wrapper.** guard.sh's shape: perl and library checks, hook-env.sh, `command perl`, stderr kept aside; perl's code 3 becomes 2, everything else 0.

## 3. Changes from section 6.3

1. Command form bash -p (A68). 2. One review, one repair loop (A66). 3. Four gates, prefixed names, words in verdicts.txt (B1). 4. Context through additionalContext; `tree=` instead of the version (B3). 5. Clean by Checks::fingerprint, which counts untracked files. 6. Flat files in git's folder (B4). 7. The definition check is the record's system prompt against the method file (B10), not a file search. 8. Effort per turn, at least the file's; models only from the record (B9). 9. Wait for the record [M]. 10. Block once and deny once keyed on the receipt's note [M]. 11. Auto mode runs at $0 against the fake (2.1.316 sends its safety check to the fake; 2.1.319 needs a test-only hook that allows the Agent call) [M], so A48's "cannot run against the fake" and "up to three times" are corrected: the client sets no limit on denials, and three is the number of its own nudges. 12. Crashes exit 0 everywhere (B11). 13. Marks by G6's write test (B8). 14. Status's gates area and G6's agent clause deferred (B12). 15. New INVALID and INCOMPLETE reasons: handing work to another agent, another folder, a packet for other files, a background task still running, a reply the client wrote.

## 4. Increments

**Before code (5b.1's first task):** measure, with the real fragment and an Opus agent at both versions, default and auto mode (and auto with the test-only allow hook): whether the allowlist blocks auto mode's check model (claude-sonnet-5) or flags every handback; what background_tasks holds for a Bash task the gate started; whether the client shows a systemMessage at SubagentStop; a 30 KB final reply's last_assistant_message. If the allowlist blocks auto mode, B7 changes and the owner is told.

**5b.1 The gate's life.** gate-receipt.sh, lib/receipt.pl (start, handback, stop, the states, block once, deny once, the store), verdicts.txt and lib/verdicts.pl (the new kinds), packet.pl (the Tree line), lib/log.pl's keep-N writer (watch.pl's snapshot moved onto it), the fragment's three entries and the settings test, tests/gate-receipt.test.sh with recorded input shapes (personal values removed) in tests/gate-receipt-cases/, tests/plants/gate-receipt.sh, harness cases at both versions: the context line in the gate's request only; a name an unanchored matcher would take (`my-method-reviewer`) gets no hook at all; default mode complete (VALID), cut off then complete (one more turn whose feedback names gate-receipt, then VALID), never complete (INCOMPLETE); auto mode with a handback missing its lines then complete, twice missing, plain text only. The test agent is `tests/harness/agents/method/method-reviewer.md`, committed before the case's tree is taken.

**5b.2 The evidence.** lib/receipt.pl's checks (clean, tree, marks, B9, B10, other agents, folders, background tasks, packet trees, the record's wait), the guard's mark (one require and one call in guard.pl's main, after the refusals), tests for each reason (the record written 0.3 s late still VALID; a record that never completes INCOMPLETE; a Haiku line; an effort low turn; a second definition; a stale packet: built, a fix committed, the old packet reviewed), harness cases (an effort override, a second project file named method-reviewer, models and tokens read from the client's real record), plants for each check, and the cost on a 10,000-file repository and a 50 MB record (limit: 5 s at stop on Linux).

**5b.3 Close.** One review (a reviewer and a security check) and one repair loop (A66); the hooks README's gate-receipt section; DECISIONS (B1 to B12 settled; A48 corrected); rule map M053, M078, M106, M116 done; RISKS: the real auto-mode check and the real API's model and usage fields unproven until step 9 (new), receipts forgeable by a program Claude runs (#2); TESTS, TASKS, CHANGELOG. Then the owner says "merge".

## 5. Known limits

Whether the verdict is right; receipts, marks or records changed by a program Claude writes and runs; a crash or time-out at stop (INCOMPLETE, never VALID); an edit made and undone by a script during a gate; a write in the same instant as a gate's start; a gate's own edit undone before it stops; a gate launched with a doctored prompt (step 6's packet covers more); the clean check's speed with a cold cache on a very large repository or under Git Bash; no receipt where hooks do not run; a SubagentStop hook that always blocks is cut off by the client after 8 blocks with no notice [M], so no method hook relies on blocking more than once.

## 6. Measured before code (2.1.316 and 2.1.319, the method's fragment, an Opus gate at xhigh)

- The gate runs on claude-opus-5-5 at xhigh on every turn, in the record's request and assistant lines; the anchored matcher fires for each gate name [M].
- Auto mode works with the fragment. Its safety check then runs on claude-opus-5-5 (claude-sonnet-5 without the allowlist) and answers `<block>no</block>`; the harness's fake must answer that form, and, once the project has a CLAUDE.md, match the check by its second message. At 2.1.319 a test-only PreToolUse hook that allows the Agent call is still needed against the fake; at 2.1.316 it is harmless [M].
- A handback whose check cannot run is still delivered ("send") with handbackReport.warning saying the check was unavailable [M]. gate-receipt cannot see that warning at its three events: recorded as a known limit (step 6's done-check, which reads the Agent call's result, can).
- background_tasks lists every running task of the session with no owner field [M]. The gate's own shells are found by matching ids against "Command running in background with ID: <id>" in its record. A foreground gate's background shell is killed about 35 ms after its stop; a background gate is resumed under the same agent id when its shell ends, with a second start and stop. So: at stop, a task of the gate's own still running makes the receipt INCOMPLETE; a second start for an agent id that already has a receipt marks that receipt INCOMPLETE ("resumed after its report"), and the new run gets its own.
- A SubagentStop systemMessage reaches neither the client's output nor any request [M]. The plain receipt line is therefore written to `.method/local/gates.log` (lib/log.pl, capped), and session-status names INVALID or INCOMPLETE receipts for the current tree in one LOOK line (the only status change in 5b); status's full gates area stays in step 6.
- A 30 KB final reply arrives whole in last_assistant_message and as one record line [M].
- The record's systemPrompt[0] is the agent file's body without frontmatter, trimmed of leading and trailing whitespace [M]: B10 compares trimmed text.
