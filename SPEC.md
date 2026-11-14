# SPEC: a portable working method for Claude Code

This repo holds a working method for building software and documents with Claude Code. It is meant for any project in any field, for people who read code and people who don't, working alone or in a small team. The method is copied into each project and kept up to date from tagged releases of this repo.

Every requirement has observable acceptance criteria. Anything no requirement covers is not built: say so and stop.

## Users

- A solo owner who does not read code and judges work by plain summaries, risk notes, verdicts and test evidence.
- A solo developer who reads code.
- A small team where some people can review code.

Each user's setup answers decide who does what. The floor in R4 is the same for everyone.

## Requirements

R1. Portable core. One domain-neutral core plus optional field packs, copied into each project's own repo and kept in sync from tagged releases. It behaves the same on Windows (Git Bash), macOS, Linux and Claude Code cloud sessions, with no per-machine step needed for quality.
- A fresh clone of a synced project in a cloud session prints the method's active line and enforces the model, hooks and checks.
- Syncing twice in a row changes nothing.
- A method file edited inside a project is reported, never silently overwritten.

R2. Install and uninstall. The per-machine layer is optional. The installer backs up what exists, merges instead of overwriting, can be run twice safely, has a dry run, and can be undone.
- Running the installer twice in a temporary home gives identical files and one backup.
- Uninstall restores the backed-up files.

R3. Setup. The first use in a project asks plain questions about the person and the project, detects what it can, writes the configuration and plays the consequences back. Answers change who does what, the pace and how strict checks are; they never lower the floor.
- A test runs every answer combination and confirms the floor holds in each.
- Running setup twice with the same answers gives the same configuration.

R4. The floor. In every project and profile: checks run; an independent fresh-context review and a security check run and must approve; a person approves the plan and the merge; no secrets go into a repo; nothing merges without a recorded approval for the exact version being merged.
- The merge check refuses when any floor element is missing, proven by a planted case for each element.

R5. Models and effort. The default profile "Best results" uses Opus 5.5 by full model ID for every role, enforced in project settings, with the checking agents pinned to xhigh effort. "Balanced" and "Budget" profiles exist with their trade-offs stated. The server-side advisor is off.
- A settings test confirms each profile's keys.
- A live cloud test shows only Opus in the token accounting under "Best results".

R6. Process. Tasks are tiered FULL or LIGHT from what the change touches. New projects and big features start with a design stage. Plans carry expected results from an outside source, written before the code, seen failing first, then locked. Checks run by script. Review follows the stopping rule. High-risk changes get Deep review. A computed "Ready to merge" replaces anyone's word.
- Each element is backed by a script check or a receipt, with a planted failure for each.

R7. Hooks. At most three hook scripts. Each one documents what it prevents, what it costs and how it is proven to fire. No log grows without a cap or stores secrets.
- A test counts the hook scripts.
- Every hook rule has a planted input that must be blocked.
- A harness proves the hooks fire in a real Claude Code client.
- A planted oversized log is trimmed.

R8. Evidence a non-programmer can use. Reports start with status and the next step, say what the checks would miss, and copy every number from a log.
- The report check lists any number that appears in no log.

R9. Proof of the machinery. CI plants the defect each guard exists to catch and sees it go red for the stated reason. The installer and sync are run twice. Linux runs on every change; Windows (Git Bash) and macOS run before each release and on demand. Line endings are pinned.
- CI is green and the plant suite passes on all three systems at each release.

R10. Reviewer test. The reviewer agent is run on changes with planted bugs, clean changes, changes touching old bugs and changes that depend on an unstated business rule. The report gives catches, false alarms and verdict correctness. (Release 2.)

R11. No secrets, personal data or business data in this repo.
- A scan runs on every change; planted cases prove it.

R12. Lean context. The always-loaded method text stays within budgets enforced by tests.
- Each budget has a planted violation that turns the test red.

R13. Improvement over time. `/research <link>`, `/research-update` (run by hand every 2 to 4 weeks), `/lesson`, a model-release checklist and rule pruning. Changes to the method go through the method. Every release says "what changes for you".

R14. Incident rules preserved. Every rule from the owner's original method and from the research is mapped to the file where it lives (docs/rule-map.md). None is dropped without a recorded decision.
- The rule-map test fails when a rule marked done is missing from its home file.

R15. Writing for people. Reports and docs follow the writing rules in the owner's profile. Commit messages and code comments are exempt.

## Supported versions

| Thing | Version | Why |
|---|---|---|
| Claude Code | 2.1.316 or later | hook `onFailure: "block"` (2.1.295), a subagent's stop event only when it ends (2.1.311), the Monitor tool seen by a Bash matcher (2.1.314), Windows hook fixes (to 2.1.316); DECISIONS A45 |
| Opus 5.5 | `claude-opus-5-5` | default model |
| bash | 3.2 or later | macOS ships 3.2 |
| Git for Windows | current | provides Git Bash and perl |
| perl | 5.14 or later, core modules only | JSON::PP is core from 5.14 |
| actions/checkout | v7.0.1, pinned by commit | CI |

## Non-goals

- Company-specific features such as single sign-on or organisation policy.
- Distribution as a plugin only (cloud sessions don't install repo plugins).
- A scheduled research watcher.
- A head-to-head benchmark against stock Claude Code.
- Cheaper models or efforts by default.
