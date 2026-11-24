# Rule map

Every rule of the method, why it exists, and the one file where it lives. A rule whose status is `done` must have its ID in its home file (or the token after `@`, when given); `scripts/dev/check-rule-map.sh` fails otherwise. Other statuses name the build step that will add it (`step N`, or `step Nb` for a step split in two), Release 2 (`R2`) or later work (`later`).

Sources: `incident` means the rule came from something that went wrong in the owner's original method. `research` names where the evidence came from; details are in docs/research/.

| ID | Rule | Source | Home | Status |
|---|---|---|---|---|
| M001 | One read-only status command orients any session: uncommitted and unpushed work in every repo, commits missing a verdict, record consistency, health | incident | method/scripts/method/status.sh | done |
| M002 | A check that examined nothing prints SKIPPED, never "ok" | incident | method/scripts/method/run-checks.sh | done |
| M003 | status exits 1 when something needs a look; it reports, it does not block | incident | method/scripts/method/status.sh | done |
| M004 | Session start says where things stand, what is blocked and on whom, and the one next thing and why | incident | method/.claude/skills/method-start/SKILL.md | done |
| M005 | Do not start work until the owner says go | incident | method/.claude/skills/method-start/SKILL.md | done |
| M006 | Plan first: read everything, change nothing but the plan's own folder before the go, mark VERIFIED and INFERRED, wait | incident | method/.claude/skills/method-plan/SKILL.md | done |
| M007 | Update the records before review, so one review covers one change | incident | method/.claude/skills/method-finish/SKILL.md | done |
| M008 | The verdict comes before the merge | incident | method/scripts/method/done-check.sh | done |
| M009 | Act on the verdict; at most 3 review rounds, then re-plan | incident; research: Claude Code team | method/scripts/method/done-check.sh | done |
| M010 | Method scripts in a project change only through sync; a built-in check compares them with method.lock (reworded, decision A78) | incident; decision A78 | method/scripts/method/run-checks.sh | done |
| M011 | Commit with the verdict trailer, push, show status | incident | method/.claude/skills/method-finish/SKILL.md | done |
| M012 | Reports open with status and next step, then what changed, what is left, risks, what is uncertain, checks | incident | method/.claude/rules/method/owner.md | done |
| M013 | If a new session cannot orient from the files, fix the files, not the handoff | incident | method/.claude/rules/method/method.md | done |
| M014 | CLAUDE.md imports AGENTS.md; AGENTS.md is authoritative for the project | incident | method/scripts/method/templates/CLAUDE.md.tmpl @@AGENTS.md | done |
| M015 | SPEC holds numbered requirements with observable acceptance criteria | incident | method/scripts/method/templates/SPEC.md.tmpl | done |
| M016 | Build nothing that no requirement covers; say so and stop | incident | method/.claude/rules/method/method.md | done |
| M017 | Each roadmap track has one exit criterion and one named blocker | incident | method/scripts/method/templates/ROADMAP.md.tmpl | done |
| M018 | Settled decisions are not reopened | incident | method/scripts/method/templates/DECISIONS.md.tmpl | done |
| M019 | TESTS lists every check and what runs it; what exists is not what runs | incident | method/scripts/method/templates/TESTS.md.tmpl | done |
| M020 | No role approves its own work | incident | method/.claude/rules/method/method.md | done |
| M021 | The planner separates known from assumed and never invents scope | incident | method/.claude/skills/method-plan/SKILL.md | done |
| M022 | The reviewer works in a fresh context and must give a verdict | incident | method/.claude/rules/method/method.md | done |
| M023 | The reviewer reads every changed file in full, not just the changed lines | incident | method/.claude/rules/method/method.md | done |
| M024 | No acceptance criteria: the reviewer says so and stops | incident | method/.claude/agents/method/method-reviewer.md | done |
| M025 | Every finding has a concrete failure scenario: this input or state gives this wrong result | incident | method/.claude/rules/method/method.md | done |
| M026 | Verify before asserting | incident | method/.claude/rules/method/method.md | done |
| M027 | Never mark CRITICAL a consequence that was not demonstrated | incident | method/.claude/rules/method/method.md | done |
| M028 | Anything visual comes back as NEEDS A HUMAN: a checking agent lists it as an [EYES] item and still gives its word on the rest; ESCALATE is for a decision a person must make first (step 6 plan, S6) | incident | method/.claude/rules/method/method.md | done |
| M029 | The tester runs the checks, reports the actual output and fixes nothing | incident | method/.claude/agents/method/method-tester.md | done |
| M030 | The security check covers secrets, personal data, permissions, injection, dependencies and dangerous shell, on the final change | incident | method/.claude/agents/method/method-security-checker.md | done |
| M031 | Check what can be checked without a screen, and write the click-by-click script for the rest | incident | method/.claude/agents/method/method-reporter.md | done |
| M032 | Each checking agent reads the project's own incident checklist | incident | method/scripts/method/review-packet.sh | done |
| M033 | Touch only the files the phase needs | incident | method/.claude/rules/method/method.md | done |
| M034 | Two owner stops: plan approval and release readiness | incident | method/.claude/rules/method/method.md | done |
| M035 | FULL tier by default; unsure means FULL | incident | method/.claude/rules/method/method.md | done |
| M036 | LIGHT relaxes exactly five things and never drops the reviewer, security check, scripted checks or merge check | incident; decision A11 | method/.claude/rules/method/method.md | done |
| M037 | No success without five parts: summary, change summary, actual check output, risks, verdict | incident | method/.claude/rules/method/owner.md | done |
| M038 | The review packet is the reviewer's whole input, leaves out the author's account, and exits non-zero when empty | incident | method/scripts/method/review-packet.sh | done |
| M039 | One verdict vocabulary file, read by every script and test | incident | method/scripts/method/verdicts.txt | done |
| M040 | The commit hook that only checks the trailer is not shipped; the trailer is generated | incident; decision A24 | DECISIONS.md @A24 | done |
| M041 | A check that has not been seen to fail is untested: plant the defect and watch it go red | incident | TESTS.md | done |
| M042 | Plant, verify and revert are three separate commands, never chained | incident | method/.claude/rules/method/method.md | done |
| M043 | After reverting a plant, diff the touched files and confirm your own work is still there | incident | method/.claude/rules/method/method.md | done |
| M044 | Break the code under test on purpose | incident | method/scripts/method/mutate-changed.sh | done |
| M045 | Twelve questions before trusting a new check | incident | method/.claude/skills/method-checks/SKILL.md | later |
| M046 | Four questions about every claim: reach, measured counts, closed or narrowed, survives re-derivation | incident | method/.claude/agents/method/method-reporter.md | done |
| M047 | Write the question in words before computing; two agreeing methods can answer the wrong question | incident | method/.claude/rules/method/method.md | done |
| M048 | The same rule implemented twice is a defect | incident | method/.claude/rules/method/method.md | done |
| M049 | Verify through the path the user takes, or say plainly that you did not | incident | method/.claude/rules/method/method.md | done |
| M050 | Check what a fresh clone gets, not only what works locally | incident | method/scripts/method/run-checks.sh | done |
| M051 | Long runs write their log where they run | incident | method/scripts/method/run-checks.sh | done |
| M052 | A plant shows a check worked once; a committed test keeps it working | incident | method/.claude/rules/method/method.md | done |
| M053 | Silence is never an outcome: loud pass, loud fail or loud skip | incident | method/.claude/hooks/method/gate-receipt.sh | done |
| M054 | Claims about how something looks go before a person before they go into a record | incident | method/.claude/rules/method/method.md | done |
| M055 | Human tags: [CHECK] agent, [EYES] owner looks, [CREDENTIAL] owner only, [AUTHORITY] empowered person | incident | method/.claude/rules/method/method.md | done |
| M056 | Stop after 3 repair loops and report what is failing and what was tried | incident | method/.claude/rules/method/method.md | done |
| M057 | One feature area at a time; other findings go into their track | incident | method/.claude/rules/method/method.md | done |
| M058 | Never rely on the implementer's own assessment | incident | method/.claude/rules/method/method.md | done |
| M059 | Never skip tests because the code looks right | incident | method/.claude/rules/method/method.md | done |
| M060 | Stop and ask before schema changes, regulated work, destructive data changes and production | incident | method/.claude/rules/method/method.md | done |
| M061 | A live system marked read-only stays read-only | incident | method/.claude/rules/method/method.md | done |
| M062 | Never hand-write regulated formats, signing, crypto, auth or payment logic when a vetted library exists; report the gap | incident | method/.claude/rules/method/method.md | done |
| M063 | A script that writes to live records refuses to run without a stated reason, and does a dry run unless told otherwise | incident; decision A77 | method/.claude/rules/method/method.md | step 7 |
| M064 | Never edit core or third-party source in place | incident | method/.claude/rules/method/method.md | done |
| M065 | Never work around the permission check; live steps are fixed scripts the owner runs | incident; decision A13 | method/.claude/rules/method/method.md | done |
| M066 | No secrets or personal data in a repo | incident | method/scripts/method/run-checks.sh | done |
| M067 | Enforcement is stated honestly: what hooks and CI enforce, and what is only convention | incident | method/docs/method/why.md | done |
| M068 | Writing for people: plain, precise, honest hedges; no machine-sounding habits | incident | method/.claude/rules/method/owner.md | done |
| M069 | A reporter agent re-derives claims before the owner approves; /supervise stays optional | incident; decision A12 | method/.claude/agents/method/method-reporter.md | done |
| M070 | The pull request and the task's plan carry reports between sessions, not a handoff file | incident | method/.claude/skills/method-finish/SKILL.md | done |
| M071 | Plain language; one complete paste-able prompt; no deadline pressure | incident | method/.claude/rules/method/owner.md | done |
| M072 | No log grows forever or stores secrets | incident | method/scripts/method/lib/log.pl | done |
| M073 | Few hooks, each documented with what it prevents, what it costs and how it was seen to fire | incident | method/.claude/hooks/method/README.md | done |
| M074 | Keep every hedge and every number exactly, with currency, sign and period | research: writing test | method/.claude/rules/method/owner.md | done |
| M075 | Never use /code-review, /goal or the advisor as a gate (the settings fragment's skillOverrides keeps /code-review to the owner; this rule's home stays method.md) | research: Claude Code internals | method/.claude/rules/method/method.md | done |
| M076 | The server-side advisor is off | research: advisor docs; decision A5 | method/settings.fragment.json @CLAUDE_CODE_DISABLE_ADVISOR_TOOL | done |
| M077 | Never set CLAUDE_CODE_EFFORT_LEVEL | research: measured; decision A4 | method/scripts/method/status.sh | done |
| M078 | A refusal or a missing verdict means "not checked" | research: model fallback docs | method/.claude/hooks/method/gate-receipt.sh | done |
| M079 | One repo per code-changing cloud session | research: cloud docs | method/.claude/rules/method/method.md | done |
| M080 | Check /permissions on each new clone | research: untrusted folders | README.md | step 9 |
| M081 | Nested claude -p runs use < /dev/null, an explicit effort and METHOD_NESTED=1 | research: measured | method/.claude/skills/method-checks/SKILL.md | later |
| M082 | When the work is done and its checks pass, stop and report; no unrequested changes | research: scope creep at high effort | method/.claude/rules/method/method.md | done |
| M083 | Every finding gets a disposition: fixed with its proving test, wrong, intentional, or not worth it | research: Claude Code team | method/.claude/agents/method/method-reviewer.md | done |
| M084 | Flag the whole class of bug; never repeat a finding already posted | research: Claude Code team | method/.claude/agents/method/method-reviewer.md | done |
| M085 | Later review rounds see only the changes since the last reviewed version, or the whole change when in doubt | research: Claude Code team, Cloudflare | method/scripts/method/review-packet.sh | done |
| M086 | Unproven serious or security findings go on an unresolved list; they are never dropped | research: evidence critique | method/.claude/agents/method/method-reviewer.md | done |
| M087 | High-risk changes get Deep review: three independent reviewers, all approving; every finding of any of them gets a disposition | research: Claude Code team | method/.claude/skills/method-finish/SKILL.md | done |
| M088 | People add a review layer and never replace the reviewer agents; they look at intent and risk before the AI findings | research: layered review; decision A8 | method/docs/method/why.md | done |
| M089 | "No findings" never counts as a pass on its own | research: Anthropic docs | method/scripts/method/done-check.sh | done |
| M090 | The reviewer checks for gaming: edited tests or expected values, skipped tests, answers hard-coded to tests, special cases, faked or display-only features | research: ImpossibleBench, harness post | method/.claude/agents/method/method-reviewer.md | done |
| M091 | The planner checks feasibility; "impossible or contradictory" is an acceptable answer; no hard-coding to tests | research: reward hacking studies | method/.claude/skills/method-plan/SKILL.md | done |
| M092 | A fresh agent writes an acceptance check after the build, from the spec, and runs it through the real user path | research: harness post | method/.claude/agents/method/method-reporter.md | done |
| M093 | Never mix restructuring and behaviour changes in one commit | research: Beck, DORA | method/.claude/rules/method/method.md | done |
| M094 | A non-AI security scanner runs alongside the security-checker | research: Anthropic security team | method/scripts/method/templates/checks/project.tsv.tmpl | done |
| M095 | Method prompts carry no "think carefully" lines, no fixed-format reasoning requests and no shouting | research: claude.dev, docs | scripts/dev/lint-prompts.sh | done |
| M096 | Checking agents have static instructions, task text last, and a fixed tool list | research: Cloudflare | scripts/dev/lint-prompts.sh | done |
| M097 | Every change states how it was tested, its risk, how to undo it and what the checks would miss | research: Claude Code team | method/scripts/method/templates/pull_request_template.md.tmpl | done |
| M098 | Changes to live systems go to a test copy first, with a backup and a one-step undo | research: Claude Code team | method/.claude/rules/method/method.md | done |
| M099 | New projects and big features start with a design stage; versions are checked against live registries; a walking skeleton is built first | research: harness post, Titus | method/.claude/skills/method-design/SKILL.md | done |
| M100 | Setup answers never lower the floor | decision A14 | method/scripts/method/lib/setup.pl | done |
| M101 | Each project has a REVIEW.md: what failure looks like, a nit cap, paths to skip, file-and-line evidence, a count-first summary | research: Claude Code team | method/scripts/method/templates/REVIEW.md.tmpl | done |
| M102 | The reviewer flags changes that leave CLAUDE.md, AGENTS.md or the architecture document out of date | research: Claude Code team | method/.claude/agents/method/method-reviewer.md | done |
| M103 | A change to the reviewer is kept only if its score on past incidents rises; re-score on any prompt, tool or model change | research: Claude Code team | bench/README.md | R2 |
| M104 | Auto memory is off in method projects; lessons go into the repo through /lesson | research: docs; decision A1 | method/settings.fragment.json @autoMemoryEnabled | done |
| M105 | No Claude Code mods during method work | research: mods docs | method/.claude/rules/method/owner.md | done |
| M106 | An approval covers one exact version of the files; any change to them voids it | research: Claude Code team | method/.claude/hooks/method/gate-receipt.sh | done |
| M107 | An agent's approval never counts as a person's | research: Claude Code team | method/.claude/rules/method/method.md | done |
| M108 | A branch must be up to date with main before it merges | research: merge queue | method/scripts/method/done-check.sh | done |
| M109 | A person is accountable for every change that ships | research: Claude Code team | method/docs/method/why.md | done |
| M110 | Improvement by hand: /research, /research-update every 2 to 4 weeks, a model-release checklist, pruning | decision A21 | method/.claude/skills/method-research-update/SKILL.md | later |
| M111 | Every rule records its reason and its one home | incident: same rule twice | scripts/dev/check-rule-map.sh | done |
| M112 | The review packet leaves out noise (lockfiles, generated and minified files) and always keeps migrations | research: Cloudflare | method/scripts/method/review-packet.sh | done |
| M113 | Packet separators are escaped so file content cannot fake a section or a verdict | research: Cloudflare | method/scripts/method/review-packet.sh | done |
| M114 | Checking agents get a "do not flag" list: unchanged code, far-fetched risks, style, "consider library X" | research: Cloudflare | method/.claude/rules/method/method.md | done |
| M115 | A checking agent reads its packet and every changed file in its first turn | research: Cloudflare | method/.claude/rules/method/method.md | done |
| M116 | Receipts record token classes, first-request cache reads and a hash of the agent's instructions | research: Cloudflare | method/.claude/hooks/method/gate-receipt.sh | done |
| M117 | A blocking finding without run evidence becomes a question | research: Cloudflare review bot | method/.claude/rules/method/method.md | done |
| M118 | In CI, checking-agent files and merge logic come from the main branch, so a change cannot grade itself | research: Cloudflare review bot | method/.github/workflows/method-gate.yml | R2 |
| M119 | Give the whole task in one message with the finish line and the stops; keep going unless input is needed or a step is destructive | research: claude.dev | method/.claude/rules/method/method.md | done |
| M120 | /explain writes a plain explainer of any part of a project | research: Claude Code team | method/.claude/skills/method-explain/SKILL.md | later |
| M121 | A failed read means "could not read", never "nothing found" | research: claude.dev | method/.claude/rules/method/method.md | done |
| M122 | Every input a plan's tests use takes at least two values, one of them not the default; a parameter that never does is a warning sign | incident | method/scripts/method/done-check.sh | later |
| M123 | A report lists the choices the builder made that the plan did not settle (defaults, scope cut or added, which requirement won a clash), each in business terms with the test or file that shows it, or says "none" | research: Osmani, critical thinking with agents | method/.claude/rules/method/owner.md | done |
| M124 | Before the owner approves a FULL merge, the owner predicts what happens in three cases taken from the locked expected results, then sees the results copied from the test log; a mismatch stops the merge for a talk | research: Osmani, critical thinking with agents | method/.claude/agents/method/method-reporter.md | done |
| M125 | Before planning a FULL task, the planner asks for whatever is missing of: who it is for, what is out of scope, what done looks like that the owner can see, and what the owner expects to happen | research: Osmani, critical thinking with agents | method/.claude/skills/method-plan/SKILL.md | done |
| M126 | The report check lists every number that appears in no log, and refuses a report whose "what the checks would miss" part is missing, empty, "nothing" or "none" (SPEC R8) | research: Osmani, critical thinking with agents | method/scripts/method/report-check.sh | done |
| M127 | Session start says how much finished work waits for the owner's merge approval (steps, commits, files) and makes that approval the one next thing, unless the owner says to keep building | incident: 117 commits waited unmerged | method/.claude/skills/method-start/SKILL.md | done |
| M128 | The guard refuses what it cannot check: a command it cannot read that names something it watches, input it cannot parse, or a missing perl | research: measured, step 5 plan | method/.claude/hooks/method/guard.sh | done |
| M129 | No PowerShell tool in method projects: the guard and the method's scripts read bash | research: docs | method/.claude/hooks/method/guard.sh | done |
| M130 | Claude's git commands at the session's repository match a short list of allowed shapes; anything else is refused with what to do instead | research: measured, step 5 plan | method/.claude/hooks/method/guard.sh | done |
| M131 | Claude never lands a change; gh, HTTP calls to GitHub, MCP tools and other Claude runs pass only from a list | incident; research: measured, step 5 plan | method/.claude/hooks/method/guard.sh | done |
| M132 | Claude only reads the method's installed files (its hooks, scripts, agents, rules and skills), its settings, git's own config and hooks, and the folders Claude Code loads mods and plugins from; it never writes them | research: measured, step 5 plan | method/.claude/hooks/method/guard.sh | done |
| M133 | No commit while a mutation run or its journal exists | research: decision A41 | method/.claude/hooks/method/guard.sh | done |
| M134 | Effort below the one the project's profile sets (xhigh for Best results and with no lock) is announced at a session's first tool call (reworded in step 7.3, step 7 plan S7) | research: decision A3 | method/.claude/hooks/method/guard.sh | done |
| M135 | Secrets, personal data and Claude attribution are stopped before they leave the machine: a push, gh text and MCP writes are scanned | incident | method/.claude/hooks/method/guard.sh | R2 |
| M136 | A settings change that switches off or weakens the hooks is refused mid-session | research: measured, step 5 plan | method/.claude/hooks/method/guard.sh | done |
| M137 | A skill or agent that declares its own hooks is refused (the method's own declare none) | research: measured, step 5 plan | method/.claude/hooks/method/guard.sh | done |
| M138 | Skills run no inline shell lines in method projects | research: measured, step 5 plan | method/settings.fragment.json @disableSkillShellExecution | done |
| M139 | Merge tools, and tools that start, message or schedule other sessions, are denied in settings, so the deny holds with hooks off | research: measured, step 5 plan | method/settings.fragment.json @mcp__*__merge_pull_request | done |
| M140 | At session start the main session looks for session-status's METHOD-ACTIVE line; with none, the method's hooks are off: say so first and change no code until the owner decides. A checking agent's own line reads `METHOD-ACTIVE gate=... tree=...`; other agents get none, and the rule is not theirs | research: measured (step 5 plan E12, RISKS #16) | method/.claude/rules/method/method.md | done |
| M141 | The architect drafts a design for a new project or big feature (options and trade-offs in business terms; where the project uses packages, versions checked against live registries; the thinnest end-to-end version first) and builds nothing | decision A16 | method/.claude/agents/method/method-architect.md | done |
| M142 | Diagnose finds the cause before any fix: it reads the evidence, changes nothing, and opens with ROOT CAUSE, SYMPTOM CHASE or SPEC QUESTION | decision A71 | method/.claude/agents/method/method-diagnose.md | done |
| M143 | When the same check fails twice, call diagnose before a third fix | plan v3, moved by step 3 (TASKS.md) | method/.claude/rules/method/method.md | done |
| M144 | A change is ready only when its task's plan carries a quoted approval naming the task | SPEC R4; decision A61 | method/scripts/method/done-check.sh | done |
| M145 | Expected results, tier and paths are locked at the plan's approval; a test run is seen failing after approval and before the code, and passing at the end | SPEC R6 | method/scripts/method/done-check.sh | done |
| M146 | Ready to merge needs VALID approving receipts for the exact files, reviewed from the merge base: reviewer and security check always; tester and reporter for FULL; three approving reviewers on high-risk paths; no other word from the reviewer or the security checker on those files, and for the tester and the reporter the newest word decides. The verdict line says what they say | SPEC R4, R6; decision A24 | method/scripts/method/done-check.sh | done |
| M147 | LIGHT only when the plan says so and the change touches no high-risk path, as main or the branch lists them | SPEC R6 | method/scripts/method/done-check.sh | done |
| M148 | When the push did not land, stop, say so and run no pull request command; the pull request's link and state are copied from what gh printed, never typed | research: Martin and Avilla, agent automations (a write counts once the destination confirms it) | method/.claude/skills/method-finish/SKILL.md | done |
| M149 | The report's change summary names each changed file outside the plan's Paths line, or says none | step 6b plan, section 1 item 13 (P6) | method/.claude/skills/method-finish/SKILL.md | done |
| M150 | When done-check's history names a diagnose word, the report offers one candidate incident-checklist line as an [EYES] item; Claude never adds it | step 6b plan, section 1 item 13 (P8) | method/.claude/skills/method-finish/SKILL.md | done |
| M151 | A project rule that conflicts with a method rule loses; a project rule may change only the length and detail of reports, which owner.md sets as a default (owner.md's other rules hold like method rules) | decision A77: a pack never weakens the core | method/.claude/rules/method/method.md | step 7 |
| M152 | status says when the project's own always-loaded text (rules outside `.claude/rules/method/` without `paths:`, CLAUDE.md, `.claude/CLAUDE.md`, AGENTS.md) passes 8,000 bytes | SPEC R12, applied to the project's own text (step 7 plan, S11) | method/scripts/method/lib/status.pl | done |
| M153 | Changes to the files that steer the method (method.conf, checks, the project's pack, CI workflows, the incident checklist, REVIEW.md, CLAUDE.md, AGENTS.md) are high-risk whatever method.conf says | step 5 plan's touches-method route, in its cheap form (step 7 plan, S12) | method/scripts/method/lib/conf.pl | step 7 |
| M154 | A flaky check: find the cause; never skip, retry or re-run it until it passes | step 6b plan, section 6 (P4) | method/.claude/rules/method/method.md | step 7 |
| M155 | Sync replaces nothing changed since the lock and writes nothing until its whole plan holds | SPEC R1 (step 7 plan, S3) | scripts/release/sync.sh | done |
| M156 | Setup writes only through setup-write from an answers file and never overwrites a project file outside its block | SPEC R3 (step 7 plan, S9, S10) | method/scripts/method/lib/setup.pl | done |
| M157 | The review packet carries the project's REVIEW.md as it stands at the merge base | step 6b plan, section 6 (P3) | method/scripts/method/lib/packet.pl | step 7 |
| M158 | The reviewer checks every item of the project's incident checklist and says so | step 6b plan, section 6 (P8 part 3) | method/.claude/agents/method/method-reviewer.md | step 7 |
| M159 | The plan names the current version's outputs at a named commit as an outside source of expected results | step 6b plan, section 6 (P9) | method/.claude/skills/method-plan/SKILL.md | step 7 |
| M160 | A FULL plan names each hard-to-undo choice with its options and a recommendation | step 6b plan, section 6 (N2) | method/.claude/skills/method-plan/SKILL.md | step 7 |
| M161 | The reviewer reviews a FULL high-risk plan before the owner is asked to approve it | step 6b plan, section 6 (P11) | method/.claude/skills/method-plan/SKILL.md | step 7 |
