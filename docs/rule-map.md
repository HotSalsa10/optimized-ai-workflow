# Rule map

Every rule of the method, why it exists, and the one file where it lives. A rule whose status is `done` must have its ID in its home file (or the token after `@`, when given); `scripts/dev/check-rule-map.sh` fails otherwise. Other statuses name the build step that will add it (`step N`, or `step Nb` for a step split in two), Release 2 (`R2`) or later work (`later`).

Sources: `incident` means the rule came from something that went wrong in the owner's original method. `research` names where the evidence came from; details are in docs/research/.

| ID | Rule | Source | Home | Status |
|---|---|---|---|---|
| M001 | One read-only status command orients any session: uncommitted and unpushed work in every repo, commits missing a verdict, record consistency, health | incident | method/scripts/method/status.sh | done |
| M002 | A check that examined nothing prints SKIPPED, never "ok" | incident | method/scripts/method/run-checks.sh | done |
| M003 | status exits 1 when something needs a look; it reports, it does not block | incident | method/scripts/method/status.sh | done |
| M004 | Session start says where things stand, what is blocked and on whom, and the one next thing and why | incident | method/.claude/skills/start/SKILL.md | step 6 |
| M005 | Do not start work until the owner says go | incident | method/.claude/skills/start/SKILL.md | step 6 |
| M006 | Plan first: read everything, write nothing, mark VERIFIED and INFERRED, wait | incident | method/.claude/skills/plan-first/SKILL.md | step 6 |
| M007 | Update the records before review, so one review covers one change | incident | method/.claude/skills/finish/SKILL.md | step 6 |
| M008 | The verdict comes before the merge | incident | method/scripts/method/done-check.sh | done |
| M009 | Act on the verdict; at most 3 review rounds, then re-plan | incident; research: Claude Code team | method/.claude/agents/method/reviewer.md | step 6 |
| M010 | When scripts change, run the guards' own tests | incident | method/scripts/method/run-checks.sh | step 7 |
| M011 | Commit with the verdict trailer, push, show status | incident | method/.claude/skills/finish/SKILL.md | step 6 |
| M012 | Reports open with status and next step, then what changed, what is left, risks, what is uncertain, checks | incident | method/.claude/rules/method/owner.md | step 6 |
| M013 | If a new session cannot orient from the files, fix the files, not the handoff | incident | method/.claude/rules/method/method.md | step 6 |
| M014 | CLAUDE.md imports AGENTS.md; AGENTS.md is authoritative for the project | incident | templates/CLAUDE.md | step 7 |
| M015 | SPEC holds numbered requirements with observable acceptance criteria | incident | templates/SPEC.md | step 7 |
| M016 | Build nothing that no requirement covers; say so and stop | incident | method/.claude/rules/method/method.md | step 6 |
| M017 | Each roadmap track has one exit criterion and one named blocker | incident | templates/ROADMAP.md | step 7 |
| M018 | Settled decisions are not reopened | incident | templates/DECISIONS.md | step 7 |
| M019 | TESTS lists every check and what runs it; what exists is not what runs | incident | templates/TESTS.md | step 7 |
| M020 | No role approves its own work | incident | method/.claude/rules/method/method.md | step 6 |
| M021 | The planner separates known from assumed and never invents scope | incident | method/.claude/agents/method/planner.md | step 6 |
| M022 | The reviewer works in a fresh context and must give a verdict | incident | method/.claude/agents/method/reviewer.md | step 6 |
| M023 | The reviewer reads every changed file in full, not just the changed lines | incident | method/.claude/agents/method/reviewer.md | step 6 |
| M024 | No acceptance criteria: the reviewer says so and stops | incident | method/.claude/agents/method/reviewer.md | step 6 |
| M025 | Every finding has a concrete failure scenario: this input or state gives this wrong result | incident | method/.claude/agents/method/reviewer.md | step 6 |
| M026 | Verify before asserting | incident | method/.claude/agents/method/reviewer.md | step 6 |
| M027 | Never mark CRITICAL a consequence that was not demonstrated | incident | method/.claude/agents/method/reviewer.md | step 6 |
| M028 | Anything visual comes back as NEEDS A HUMAN | incident | method/.claude/agents/method/reviewer.md | step 6 |
| M029 | The tester runs the checks, reports the actual output and fixes nothing | incident | method/.claude/agents/method/tester.md | step 6 |
| M030 | The security check covers secrets, personal data, permissions, injection, dependencies and dangerous shell, on the final change | incident | method/.claude/agents/method/security-checker.md | step 6 |
| M031 | Check what can be checked without a screen, and write the click-by-click script for the rest | incident | method/.claude/agents/method/reporter.md | step 6 |
| M032 | Each checking agent reads the project's own incident checklist | incident | method/scripts/method/review-packet.sh | done |
| M033 | Touch only the files the phase needs | incident | method/.claude/rules/method/method.md | step 6 |
| M034 | Two owner stops: plan approval and release readiness | incident | method/.claude/rules/method/method.md | step 6 |
| M035 | FULL tier by default; unsure means FULL | incident | method/.claude/rules/method/method.md | step 6 |
| M036 | LIGHT relaxes exactly five things and never drops the reviewer, security check, scripted checks or merge check | incident; decision A11 | method/.claude/rules/method/method.md | step 6 |
| M037 | No success without five parts: summary, change summary, actual check output, risks, verdict | incident | method/.claude/rules/method/owner.md | step 6 |
| M038 | The review packet is the reviewer's whole input, leaves out the author's account, and exits non-zero when empty | incident | method/scripts/method/review-packet.sh | done |
| M039 | One verdict vocabulary file, read by every script and test | incident | method/scripts/method/verdicts.txt | done |
| M040 | The commit hook that only checks the trailer is not shipped; the trailer is generated | incident; decision A24 | DECISIONS.md @A24 | done |
| M041 | A check that has not been seen to fail is untested: plant the defect and watch it go red | incident | TESTS.md | done |
| M042 | Plant, verify and revert are three separate commands, never chained | incident | method/.claude/skills/checks/SKILL.md | step 6 |
| M043 | After reverting a plant, diff the touched files and confirm your own work is still there | incident | method/.claude/skills/checks/SKILL.md | step 6 |
| M044 | Break the code under test on purpose | incident | method/scripts/method/mutate-changed.sh | done |
| M045 | Twelve questions before trusting a new check | incident | method/.claude/skills/checks/SKILL.md | step 6 |
| M046 | Four questions about every claim: reach, measured counts, closed or narrowed, survives re-derivation | incident | method/.claude/agents/method/reporter.md | step 6 |
| M047 | Write the question in words before computing; two agreeing methods can answer the wrong question | incident | method/.claude/rules/method/method.md | step 6 |
| M048 | The same rule implemented twice is a defect | incident | method/.claude/rules/method/method.md | step 6 |
| M049 | Verify through the path the user takes, or say plainly that you did not | incident | method/.claude/rules/method/method.md | step 6 |
| M050 | Check what a fresh clone gets, not only what works locally | incident | method/scripts/method/run-checks.sh | done |
| M051 | Long runs write their log where they run | incident | method/scripts/method/run-checks.sh | done |
| M052 | A plant shows a check worked once; a committed test keeps it working | incident | method/.claude/skills/checks/SKILL.md | step 6 |
| M053 | Silence is never an outcome: loud pass, loud fail or loud skip | incident | method/.claude/hooks/method/gate-receipt.sh | step 5b |
| M054 | Claims about how something looks go before a person before they go into a record | incident | method/.claude/rules/method/method.md | step 6 |
| M055 | Human tags: [CHECK] agent, [EYES] owner looks, [CREDENTIAL] owner only, [AUTHORITY] empowered person | incident | method/.claude/rules/method/method.md | step 6 |
| M056 | Stop after 3 repair loops and report what is failing and what was tried | incident | method/.claude/rules/method/method.md | step 6 |
| M057 | One feature area at a time; other findings go into their track | incident | method/.claude/rules/method/method.md | step 6 |
| M058 | Never rely on the implementer's own assessment | incident | method/.claude/rules/method/method.md | step 6 |
| M059 | Never skip tests because the code looks right | incident | method/.claude/rules/method/method.md | step 6 |
| M060 | Stop and ask before schema changes, regulated work, destructive data changes and production | incident | method/.claude/rules/method/method.md | step 6 |
| M061 | A live system marked read-only stays read-only | incident | method/.claude/rules/method/method.md | step 6 |
| M062 | Never hand-write regulated formats, signing, crypto, auth or payment logic when a vetted library exists; report the gap | incident | method/.claude/rules/method/method.md | step 6 |
| M063 | A script that writes to live records refuses to run without a stated reason | incident | packs/frappe/templates/owner-script.sh | step 7 |
| M064 | Never edit core or third-party source in place | incident | method/.claude/rules/method/method.md | step 6 |
| M065 | Never work around the permission check; live steps are fixed scripts the owner runs | incident; decision A13 | method/.claude/rules/method/method.md | step 6 |
| M066 | No secrets or personal data in a repo | incident | method/scripts/method/run-checks.sh | done |
| M067 | Enforcement is stated honestly: what hooks and CI enforce, and what is only convention | incident | docs/why.md | step 6 |
| M068 | Writing for people: plain, precise, honest hedges; no machine-sounding habits | incident | method/.claude/rules/method/owner.md | step 6 |
| M069 | A reporter agent re-derives claims before the owner approves; /supervise stays optional | incident; decision A12 | method/.claude/agents/method/reporter.md | step 6 |
| M070 | A handoff file and the pull request carry reports between sessions | incident | method/.claude/skills/finish/SKILL.md | step 6 |
| M071 | Plain language; one complete paste-able prompt; no deadline pressure | incident | method/.claude/rules/method/owner.md | step 6 |
| M072 | No log grows forever or stores secrets | incident | method/scripts/method/lib/log.pl | done |
| M073 | Few hooks, each documented with what it prevents, what it costs and how it was seen to fire | incident | method/.claude/hooks/method/README.md | step 5 |
| M074 | Keep every hedge and every number exactly, with currency, sign and period | research: writing test | method/.claude/rules/method/owner.md | step 6 |
| M075 | Never use /code-review, /goal or the advisor as a gate (the settings fragment's skillOverrides keeps /code-review to the owner; this rule's home stays method.md) | research: Claude Code internals | method/.claude/rules/method/method.md | step 6 |
| M076 | The server-side advisor is off | research: advisor docs; decision A5 | method/settings.fragment.json @CLAUDE_CODE_DISABLE_ADVISOR_TOOL | done |
| M077 | Never set CLAUDE_CODE_EFFORT_LEVEL | research: measured; decision A4 | method/scripts/method/status.sh | done |
| M078 | A refusal or a missing verdict means "not checked" | research: model fallback docs | method/.claude/hooks/method/gate-receipt.sh | step 5b |
| M079 | One repo per code-changing cloud session | research: cloud docs | method/.claude/rules/method/method.md | step 6 |
| M080 | Check /permissions on each new clone | research: untrusted folders | README.md | step 9 |
| M081 | Nested claude -p runs use < /dev/null, an explicit effort and METHOD_NESTED=1 | research: measured | method/.claude/skills/checks/SKILL.md | step 6 |
| M082 | When the work is done and its checks pass, stop and report; no unrequested changes | research: scope creep at high effort | method/.claude/rules/method/method.md | step 6 |
| M083 | Every finding gets a disposition: fixed with its proving test, wrong, intentional, or not worth it | research: Claude Code team | method/.claude/agents/method/reviewer.md | step 6 |
| M084 | Flag the whole class of bug; never repeat a finding already posted | research: Claude Code team | method/.claude/agents/method/reviewer.md | step 6 |
| M085 | Later review rounds see only the changes since the last reviewed version, or the whole change when in doubt | research: Claude Code team, Cloudflare | method/scripts/method/review-packet.sh | done |
| M086 | Unproven serious or security findings go on an unresolved list; they are never dropped | research: evidence critique | method/.claude/agents/method/reviewer.md | step 6 |
| M087 | High-risk changes get Deep review: several independent finders and a vote on each finding | research: Claude Code team | method/.claude/skills/finish/SKILL.md | step 6 |
| M088 | People add a review layer and never replace the reviewer agents; they look at intent and risk before the AI findings | research: layered review; decision A8 | method/.claude/rules/method/method.md | step 6 |
| M089 | "No findings" never counts as a pass on its own | research: Anthropic docs | method/scripts/method/done-check.sh | done |
| M090 | The reviewer checks for gaming: edited tests or expected values, skipped tests, answers hard-coded to tests, special cases, faked or display-only features | research: ImpossibleBench, harness post | method/.claude/agents/method/reviewer.md | step 6 |
| M091 | The planner checks feasibility; "impossible or contradictory" is an acceptable answer; no hard-coding to tests | research: reward hacking studies | method/.claude/agents/method/planner.md | step 6 |
| M092 | A fresh agent writes an acceptance check after the build, from the spec, and runs it through the real user path | research: harness post | method/.claude/agents/method/reporter.md | step 6 |
| M093 | Never mix restructuring and behaviour changes in one commit | research: Beck, DORA | method/.claude/rules/method/method.md | step 6 |
| M094 | A non-AI security scanner runs alongside the security-checker | research: Anthropic security team | templates/checks/project.tsv | step 7 |
| M095 | Method prompts carry no "think carefully" lines, no fixed-format reasoning requests and no shouting | research: claude.dev, docs | scripts/dev/lint-prompts.sh | step 6 |
| M096 | Checking agents have static instructions, task text last, and a fixed tool list | research: Cloudflare | method/.claude/agents/method/reviewer.md | step 6 |
| M097 | Every change states how it was tested, its risk, how to undo it and what the checks would miss | research: Claude Code team | method/.github/pull_request_template.md | step 7 |
| M098 | Changes to live systems go to a test copy first, with a backup and a one-step undo | research: Claude Code team | method/.claude/rules/method/method.md | step 6 |
| M099 | New projects and big features start with a design stage; versions are checked against live registries; a walking skeleton is built first | research: harness post, Titus | method/.claude/skills/design/SKILL.md | step 6 |
| M100 | Setup answers never lower the floor | decision A14 | method/.claude/skills/setup/SKILL.md | step 7 |
| M101 | Each project has a REVIEW.md: what failure looks like, a nit cap, paths to skip, file-and-line evidence, a count-first summary | research: Claude Code team | templates/REVIEW.md | step 7 |
| M102 | The reviewer flags changes that leave CLAUDE.md, AGENTS.md or the architecture document out of date | research: Claude Code team | method/.claude/agents/method/reviewer.md | step 6 |
| M103 | A change to the reviewer is kept only if its score on past incidents rises; re-score on any prompt, tool or model change | research: Claude Code team | bench/README.md | R2 |
| M104 | Auto memory is off in method projects; lessons go into the repo through /lesson | research: docs; decision A1 | method/settings.fragment.json @autoMemoryEnabled | done |
| M105 | No Claude Code mods during method work | research: mods docs | method/.claude/rules/method/owner.md | step 6 |
| M106 | An approval covers one exact version of the files; any change to them voids it | research: Claude Code team | method/.claude/hooks/method/gate-receipt.sh | step 5b |
| M107 | An agent's approval never counts as a person's | research: Claude Code team | method/.claude/rules/method/method.md | step 6 |
| M108 | A branch must be up to date with main before it merges | research: merge queue | method/scripts/method/done-check.sh | done |
| M109 | A person is accountable for every change that ships | research: Claude Code team | method/.claude/rules/method/method.md | step 6 |
| M110 | Improvement by hand: /research, /research-update every 2 to 4 weeks, a model-release checklist, pruning | decision A21 | method/.claude/skills/research-update/SKILL.md | later |
| M111 | Every rule records its reason and its one home | incident: same rule twice | scripts/dev/check-rule-map.sh | done |
| M112 | The review packet leaves out noise (lockfiles, generated and minified files) and always keeps migrations | research: Cloudflare | method/scripts/method/review-packet.sh | done |
| M113 | Packet separators are escaped so file content cannot fake a section or a verdict | research: Cloudflare | method/scripts/method/review-packet.sh | done |
| M114 | Checking agents get a "do not flag" list: unchanged code, far-fetched risks, style, "consider library X" | research: Cloudflare | method/.claude/agents/method/reviewer.md | step 6 |
| M115 | A checking agent reads its packet and every changed file in its first turn | research: Cloudflare | method/.claude/agents/method/reviewer.md | step 6 |
| M116 | Receipts record token classes, first-request cache reads and a hash of the agent's instructions | research: Cloudflare | method/.claude/hooks/method/gate-receipt.sh | step 5b |
| M117 | A blocking finding without run evidence becomes a question | research: Cloudflare review bot | method/.claude/agents/method/reviewer.md | step 6 |
| M118 | In CI, checking-agent files and merge logic come from the main branch, so a change cannot grade itself | research: Cloudflare review bot | method/.github/workflows/method-gate.yml | R2 |
| M119 | Give the whole task in one message with the finish line and the stops; keep going unless input is needed or a step is destructive | research: claude.dev | method/.claude/rules/method/method.md | step 6 |
| M120 | /explain writes a plain explainer of any part of a project | research: Claude Code team | method/.claude/skills/explain/SKILL.md | step 6 |
| M121 | A failed read means "could not read", never "nothing found" | research: claude.dev | method/.claude/rules/method/method.md | step 6 |
| M122 | Every input a plan's tests use takes at least two values, one of them not the default; a parameter that never does is a warning sign | incident | method/scripts/method/done-check.sh | step 6 |
| M123 | A report lists the choices the builder made that the plan did not settle (defaults, scope cut or added, which requirement won a clash), each in business terms with the test or file that shows it, or says "none" | research: Osmani, critical thinking with agents | method/.claude/rules/method/owner.md | step 6 |
| M124 | Before the owner approves a FULL merge, the owner predicts what happens in three cases taken from the locked expected results, then sees the results copied from the test log; a mismatch stops the merge for a talk | research: Osmani, critical thinking with agents | method/.claude/agents/method/reporter.md | step 6 |
| M125 | Before planning a FULL task, the planner asks for whatever is missing of: who it is for, what is out of scope, what done looks like that the owner can see, and what the owner expects to happen | research: Osmani, critical thinking with agents | method/.claude/agents/method/planner.md | step 6 |
| M126 | The report check lists every number that appears in no log, and refuses a report whose "what the checks would miss" part is missing, empty or "nothing" (SPEC R8) | research: Osmani, critical thinking with agents | method/scripts/method/report-check.sh | step 6 |
| M127 | Session start says how much finished work waits for the owner's merge approval (steps, commits, files) and makes that approval the one next thing, unless the owner says to keep building | incident: 117 commits waited unmerged | method/.claude/skills/start/SKILL.md | step 6 |
| M128 | The guard refuses what it cannot check: a command it cannot read that names something it watches, input it cannot parse, or a missing perl | research: measured, step 5 plan | method/.claude/hooks/method/guard.sh | done |
| M129 | No PowerShell tool in method projects: the guard and the method's scripts read bash | research: docs | method/.claude/hooks/method/guard.sh | done |
| M130 | Claude's git commands at the session's repository match a short list of allowed shapes; anything else is refused with what to do instead | research: measured, step 5 plan | method/.claude/hooks/method/guard.sh | done |
| M131 | Claude never lands a change; gh, HTTP calls to GitHub, MCP tools and other Claude runs pass only from a list | incident; research: measured, step 5 plan | method/.claude/hooks/method/guard.sh | done |
| M132 | Claude only reads the method's installed files, its settings and git's own config and hooks; it never writes them | research: measured, step 5 plan | method/.claude/hooks/method/guard.sh | done |
| M133 | No commit while a mutation run or its journal exists | research: decision A41 | method/.claude/hooks/method/guard.sh | done |
| M134 | Effort below xhigh is announced at a session's first tool call | research: decision A3 | method/.claude/hooks/method/guard.sh | done |
| M135 | Secrets, personal data and Claude attribution are stopped before they leave the machine: a push, gh text and MCP writes are scanned | incident | method/.claude/hooks/method/guard.sh | step 5 |
| M136 | A settings change that switches off or weakens the hooks is refused mid-session | research: measured, step 5 plan | method/.claude/hooks/method/guard.sh | step 5 |
| M137 | A skill or agent that declares its own hooks is refused unless it is a method file | research: measured, step 5 plan | method/.claude/hooks/method/guard.sh | step 5 |
| M138 | Skills run no inline shell lines in method projects | research: measured, step 5 plan | method/settings.fragment.json @disableSkillShellExecution | done |
| M139 | Merge tools, and tools that start, message or schedule other sessions, are denied in settings, so the deny holds with hooks off | research: measured, step 5 plan | method/settings.fragment.json @mcp__*__merge_pull_request | done |
