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
5. The three hooks, the settings fragment, a free test harness that proves the hooks fire.
6. Method rules, agents (including the architect) and skills (including setup and design).
7. Project templates, setup, sync, the money, ERPNext and documents packs, three example projects.
8. Installer and uninstall.
9. Project CI templates, a live test in a fresh cloud session, README v1.

Exit: a new example project set up with `/setup` in a fresh cloud session passes the live acceptance list.
Blocker: none; Claude does the work.

## Track 2: Release 2, proof and hardening

Reviewer test (planted bugs, clean changes, old bugs, business-rule questions); the merge check run from the main branch so a change cannot grade itself; mutation testing in CI; GitHub branch rules; Deep review checked against the incident set; an end-to-end smoke test; an exact way to find a mutant in a file edited after a cut-off run (RISKS #15).

Exit: the reviewer test report exists and every Release 2 guard has its planted failure in CI.
Blocker: an API key from the owner's Max plan credits, scoped to the test runs ([CREDENTIAL], owner).

## Track 3: Release 3, moving the owner's projects over

Migration prompt; `/setup` for the owner; one ERPNext project first, then the second; every rule from the old AGENTS.md mapped, none dropped silently.

Exit: both projects run on the method with 0 rules dropped without a recorded decision.
Before the import: the secret scan's known credential misses are closed and a second scanner runs (TESTS.md Known limits).
Blocker: cleaned copies of the owner's status.sh, review packet, verdict file, prompts, agent files and settings ([CREDENTIAL]-free, owner).

## Track 4: later

`/research <link>`, `/research-update`, the model-release checklist and rule pruning; more field packs when a real project needs one.

Exit: the commands exist and one research run has produced a reviewed change.
Blocker: Track 1.
