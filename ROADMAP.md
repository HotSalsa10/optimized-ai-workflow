# ROADMAP

Each track has one exit criterion and one named blocker. Take the next action from the highest track not waiting on a person. If every track is waiting, say so and stop.

## Track 1: Release 1, a usable core

Steps, each reviewed in a fresh context and committed with a verdict trailer:

1. Repo skeleton, this repo's own records, rule map, CI with planted defects.
1b. Fixes from step 1's security check (TASKS.md), before step 2. The owner chose this.
2. JSON helper, verdict vocabulary, review packet.
3. run-checks.sh and status.sh.
4. done-check.sh.
4b. The mutation wrapper (mutate-changed.sh), split from step 4 after its design critique (TASKS.md).
5. The settings fragment, a free test harness that proves the hooks fire, session-status and the guard (docs/plans/step5.md).
5b. gate-receipt, the third hook, split from step 5 after its plan review (A54).
6. Method rules, agents (the five checking agents and the architect) and skills (`/method-start`, `/method-plan`, `/method-design`), with checks on their text and size (docs/plans/step6.md; setup moved to step 7, DECISIONS A73, where it became `/method-setup`).
6b. A computed "Ready to merge": done-check reads the gates' receipts and the task's plan, a report check, and `/method-finish`, split from step 6 (docs/plans/step6.md S1).
7. Project templates, setup, sync, the pack format and a way to make a project's own pack (no ready-made field packs, DECISIONS A77), three example projects of different kinds (docs/plans/step7.md, DECISIONS A78). Built in 7.0 to 7.8, with no 7b; merged (pull request #5), and released as the first tag, v0.7.0.
8. First, this repo's own hooks from the first release tag (DECISIONS A47, its timing moved by A78 (16)), with `claudeMdExcludes` for `method/.claude/rules`; then the installer and uninstall, the user-level audit (personal skills named `method-*`, advisorModel) and wrappers that refuse a bare command name (docs/plans/step8.md, DECISIONS A82). Built in 8.0 to 8.5; merged (pull request #6), and released as v0.8.0.
9. First, this repo's move to v0.8.0, in a session where its hooks are off (docs/plans/step8.md S5); then project CI templates, a live test in a fresh cloud session, README v1.

Exit: a new example project set up with `/method-setup` in a fresh cloud session passes the live acceptance list.
Blocker: the owner's part of step 9: the example repository, four sessions he opens, the pre-release and `v1.0.0` tags, and the merge (docs/plans/step9.md, section 7).

## Track 2: Release 2, proof and hardening

The outgoing-secret check (G15, moved from step 5.10, A66); reviewer test (planted bugs, clean changes, old bugs, business-rule questions); the merge check run from the main branch so a change cannot grade itself; mutation testing in CI; GitHub branch rules; Deep review checked against the incident set; an end-to-end smoke test; an exact way to find a mutant in a file edited after a cut-off run (RISKS #15).

Exit: the reviewer test report exists and every Release 2 guard has its planted failure in CI.
Blocker: an API key from the owner's Max plan credits, scoped to the test runs ([CREDENTIAL], owner).

## Track 3: Release 3, moving the owner's projects over

Migration prompt; `/method-setup` for the owner; one ERPNext project first, then the second; their field rules become those projects' own packs (A77); every rule from the old AGENTS.md mapped, none dropped silently.

Exit: both projects run on the method with 0 rules dropped without a recorded decision.
Before the import: the secret scan's known credential misses are closed and a second scanner runs (TESTS.md Known limits).
Blocker: cleaned copies of the owner's status.sh, review packet, verdict file, prompts, agent files and settings ([CREDENTIAL]-free, owner).

## Track 4: later

`/lesson`, with its bar for what becomes a rule and its pruning (not built in step 6 or 6b, DECISIONS A74; until then a lesson is an ordinary reviewed change to the records), `/research <link>`, `/research-update`, `/method-explain` (M120, moved from step 6, DECISIONS A73), the model-release checklist (its first case Claude Fable 5.2, DECISIONS A81) and rule pruning; more field packs when a real project needs one.

Exit: the commands exist and one research run has produced a reviewed change.
Blocker: Track 1.
