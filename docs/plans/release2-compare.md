# Release 2, first item: the method against plain Claude Code (design note)

Written 27 November 2026, on claude/step9-compare, from step 9's research of that day (a workflow of 14 agents: four readers, three designs, three judges, a synthesis and three critiques; then three critics of an automated version, and Claude's simulation of the decision rule). It is a design note, not a plan: Release 2 turns it into one, after Release 1. The owner chose this timing on 27 November ("Finish v1, then test"); step 9's S19 and A83 record it. Labels: [M] measured, [D] documented, [R] read in this repo's files, [I] inferred.

## 1. The question

Does working with the method give better results than plain Claude Code, by enough to be worth its cost? Measured on realistic tasks, with the rule that turns scores into a verdict fixed and committed before any run, so the result cannot be read kindly afterwards (SPEC R16).

Three arms:
- **M**, the method as shipped (installed by sync, set up by `/method-setup`); its first message starts with `/method-plan`, the way an owner uses it.
- **C**, plain Claude Code with one careful-work paragraph in CLAUDE.md, the cheapest possible "method". M against C decides: "would a paragraph do?" is the real question behind "keep or simplify".
- **P**, plain Claude Code, nothing added. M against P answers the owner's literal question; it is reported, and does not steer (unless commit A says otherwise, with the combined false-stop rate stated, see 4).

C's paragraph, frozen on 27 November before any task text existed: "Work carefully. Before you change anything, read the files involved, tell me in two or three plain sentences what you will change, and ask me about anything the request leaves unclear. Change only what the request needs. After the change, run the project's tests or checks and try the change the way a user would. Before you say it is done, read your whole diff again. Then tell me plainly what you changed, what you checked and how, and what you did not check or are unsure about. Never put passwords or keys in files."

## 2. Why it must be automated: the size

A toy simulation of the rule (a trap task missed with probability q costs 10 points, and half the time a false "done" claim; every run gets 0 to 3 points of noise; 40,000 trials a case; Claude's scratch script of 27 November, to be committed under `tests/bench/` with its seed when this is built) gave:

| Size | Margin | Equal arms: false WIN / false LOSE | M misses traps 30% vs 50%: WIN | 20% vs 50%: WIN |
|---|---|---|---|---|
| 5 tasks × 1 run | 3 (S1 veto 3) | 7% / 8% | 15% | 21% |
| 10 tasks × 1 run | 4 | 7% / 9% | 21% | 32% |
| 10 tasks × 2 runs | 4 | 6% / 12% | 30% | 52% |
| 15 tasks × 2 runs | 5 | 5% / 6% | 37% | 64% |
| 20 tasks × 2 runs | 5 (S1 veto 8) | 8% / 9% | 52% | 81% |
| 20 tasks × 3 runs | 5 | 7% / 7% | 61% | 90% |

So a test the owner could run by hand (about five tasks) almost always ends in a draw, whatever the truth; about 20 tasks with two runs each per arm (120 runs) can see a large or moderate difference. That many runs need an automated runner on the real model, paid from API credits: the owner's API key, which is already Release 2's blocker for the reviewer test (R10). A full-route method run on a small project plausibly costs tens of dollars at list price, and the series perhaps a thousand dollars or more [I, from the scale of step 8's own sessions; no figure is recorded here, step9.md S14]: a priced trial comes first.

## 3. The bench

- **An invented business project**, "Harbour Crafts books": a small Python 3 standard-library tool (invoices, credit notes, stock, a monthly sales report), about 900 lines, invented data only, with thin realistic visible tests, a vendored library that must not be edited, a stable `show --json` output, and a way to try commands without touching the shop's books. Its dates do not depend on the calendar.
- **Five task kinds, four tasks each** (20), plus a trial task and reserves: a wrong figure reported with a plausible but wrong guess at its cause; a feature whose correct form is a business rule nobody wrote down (the right move is to ask); a report change someone outside asked for; "broken since my change, make it work again, quick", where the quick fix is the wrong one; a small clear change (the method's honest price). The owner confirms the kinds before the kit is written.
- **The hidden kit**: briefs, planted facts, the answer sheet with trigger phrases, mechanical probes with fixed severities, two reference solutions (one written blind), trap patches; validated by the plant rule (every probe red on the start and green on both references, every trap patch red, a mutant for every probe, every probe citing its brief or sheet line, triggers matching blind paraphrases). Sealed as an encrypted archive committed with its sha256 before any run (`openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 -salt -pass file:<root-only file>`, `*.enc binary` in .gitattributes), the passphrase with the owner. The kit's plain text never reaches GitHub or an artifact before the reveal.
- **Scores**: S1 = 10 points, S2 = 3, S3 = 1 (definitions as step 9's version 3 draft at c693715 lists them); false claims +3 and +3; probes grouped by root cause; no probe dropped after the pre-registration.
- **The rule** for 20 × 2: a task's score is the mean of its two runs; d = score(other) − score(M); W if d ≥ 3, L if d ≤ −3; WIN if W − L ≥ 5 and M has no more S1 faults and false claims; LOSE if L − W ≥ 5 or M has 8 or more S1 faults than the other; DRAW otherwise; INCOMPLETE if fewer than 17 of 20 tasks have all runs valid.
- **Outcomes**: WIN keeps the method; WIN over the owner's cost ceiling keeps it and cuts cost first; DRAW simplifies (C's paragraph as the rules' core; every component outside the floor with no confirmed catch made optional; the floor only by the owner's SPEC decision), and the simplified method can be measured again by the same runner; LOSE stops and diagnoses; INCOMPLETE gives no verdict.
- **The catch ledger**: probes run on M's commit before and after each checking agent's repair; a component that turned a failing group green has a confirmed catch. Whatever the verdict, it shows which parts earned their cost.

## 4. What the critics found, to be solved when this is built

Each was raised by a critic who checked it against the repo or measured it here, on 27 November.

**The runner.**
- The session proxy never adds a key to the API host: network secrets cannot be saved for Anthropic's hosts, and none is added to a request to api.anthropic.com [D, environment.secrets]. A key can only be an environment variable of a new personal environment for this repository, which the owner adds by hand under a neutral name (not `ANTHROPIC_API_KEY`, so this session's own client cannot pick it up), and which this session can read; the owner uses a dedicated Console workspace whose spend limit is the hard ceiling. Variables reach only a new session, so the bench is built and run in that new session.
- The harness keeps its dummy key: the runner points its fake-API slot (`H_FAKE_API`) at a committed relay that runs as root, reads the key from a root-only file, forwards each request to the API with curl (`-H @file`, never on a command line; perl here has no TLS module [M]), and keeps fake-api.pl's interface, so the harness's existing outside-connection and key checks still hold.
- A run's user can reach the proxy, which adds a GitHub credential to requests (curl to the GitHub API with no token answered 200 [M]), and can dial the API host directly [M]. Before each run, owner-match firewall rules for the run's uid allow only the relay's port; plants show a run dialling the proxy or the API host is refused and named. Whether `iptables` works here (NET_ADMIN) is to be measured; the fallback is `unshare --net` with the relay on a Unix socket; failing both, the series waits.
- Web search runs on the API host itself, so the host rule does not stop it: `--disallowedTools WebSearch,WebFetch` for every arm alike.
- The harness needs named changes, each with a test and a plant: a run-as user (a `setpriv` prefix inside lib.sh, never typed inline: `su` and `runuser` are refused by the guard), retries in bench mode (h_client forces zero, so any 429 or overload would void a run), request and time caps from variables, a desk feeder that answers each `result` event through the stream input (feed.pl only replays fixed steps), a work folder the run user owns outside `/tmp/claude-0`. AGENTS.md and A82 (4) are amended to name the runner as a committed route that reaches the real API. The runner is Linux-only, an exception to AGENTS.md's three systems, its tests SKIPPED on Windows and macOS.
- Each concurrent run gets its own uid and a fresh home and work folder (mode 700), deleted after the run, so no run reads another's work or transcripts; a plant shows a run reading another slot's folder is refused.
- Runs are capped below the Bash tool's two-hour limit for a background command, or started with `setsid` and checked later; whether a container lives long enough for the series is measured in the trial, and grading follows each batch so a lost container costs only extracts.
- The permission mode is named and equal for every arm (for example `acceptEdits` with Bash allowed, or bypassPermissions as the run user), and recorded as not the owner's Auto mode.
- A run's validity is judged from the requests the relay logged (M's first request holds `METHOD-ACTIVE v0.8.0`; C's and P's hold none), not from what the model chose to say.
- M's starting copy is the reviewed live example's merged main. The guard does not force this (a committed harness script may install the method in scratch, as h_method does), but it makes the runs measure exactly what the live test reviewed.

**Fairness and blinding.**
- Grading must be blind to the people who judge, not only to the packets: the runner gives each run a random code at its start and writes the code-to-arm key only into an encrypted file whose passphrase the owner holds; logs are kept by code; graders, claim judges and the reviewer of the grade sheet run as the bench user with only coded packets; "reproduced" and each severity are decided by script.
- The method's own records (docs/tasks/, .method/, record lines) are listed exactly and score 0, as are C's and P's equivalents; otherwise a one-point overhead on M alone roughly doubles the false LOSE rate [M, a critic's re-run of the simulation].
- M against P: either reported only, or, if its LOSE may stop the work, commit A states the combined false-stop rate (about 15% for equal arms in the toy model).
- The rate check is not circular: the toy generator is committed beside the verdict script, and after the trial it is re-run with noise drawn from the trial's measured per-run points; the margin is raised if false WIN or false LOSE exceeds 10%.
- The owner's setup facts are given to all arms, and checked against the kit before any counted run.
- Void rules apply to every arm alike and are mechanical; a task swap is allowed only before the first counted run.
- The desk stands in for the owner's plan approval (R4's person); the report says so, and the live test is where the owner approves himself.

**Records and process.**
- The comparison's own records: SPEC R16 (step 9 adds it), A84 onward, RISKS lines for the bench's validity and the key's exposure; every sub-step with one review and one repair loop, the grade sheet reviewed while the arms are hidden, and the reveal and report reviewed too.
- Results hold no personal or account data: outcomes, scores by code, and, if the owner allows, M's tokens and list cost as ratios to C's and P's; no amounts, no account details.

## 5. The owner's part, as now foreseen

The decision card (the size, the cost ceiling in his words, what of the cost may be published, C's paragraph); the task kinds confirmed; a Console workspace and key with a spend limit, added to a new environment as a variable; one new session on it; a ceiling set after a priced trial; the merges; reading the result. About 2 to 4 hours of his attention, and the credits.
