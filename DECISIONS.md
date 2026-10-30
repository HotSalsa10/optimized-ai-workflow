# DECISIONS

Facts that outlive the work: choices, rejected options and traps. Settled decisions are not reopened without new evidence. Each entry says why. Sources are listed in docs/research/.

A1. The method lives inside each project's repo, copied from this repo and kept in sync by releases. Not a plugin, not ~/.claude. Why: cloud sessions load only what is committed in the repo and do not install plugins a project enables (Claude Code docs, cloud environments page).

A2. Default model policy: Opus 5.5 by full ID (`claude-opus-5-5`) for every role, set in project settings with `model`, `availableModels` and `enforceAvailableModels`. Why: in a host-managed cloud session, `CLAUDE_CODE_SUBAGENT_MODEL` and its FORCE switch are dropped from project settings, while `model` plus `availableModels` forced Haiku-pinned and Haiku-requested agents onto Opus (measured by token accounting, Oct 2026).

A3. Effort, "Best results" profile: xhigh for FULL builds and every checking agent. This departs from Anthropic's default advice (start at medium; keep xhigh and max for measured gains). Why: the owner does not steer code, errors in money and data are silent, Anthropic describes xhigh as suited to long unattended coding, and Cloudflare's randomized test found a reviewer at high caught 58% more serious findings than at medium. Balanced and Budget profiles follow Anthropic's defaults.

A4. Never set `CLAUDE_CODE_EFFORT_LEVEL`. Why: it silently overrides `--effort`, `/effort` and agent frontmatter, flattening every role to one level (measured). A top-level `effortLevel` in user settings is ignored by Opus 5.5 (docs); the project file sets effort instead.

A5. The server-side advisor is off (`CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1`). Why: under the Opus allowlist it is Opus advising Opus, its advice is encrypted and unreadable to the owner, every checking agent inherits it, and Anthropic's best measured pairing was within run-to-run noise.

A6. One agent builds; subagents only check or look things up. No cheap worker agents by default. Why: Anthropic's measurements, an independent single-task test and the shared YouTube experiment all found delegating one connected build gave no quality gain and was slower.

A7. Review design: a blind fresh-context reviewer and a security-checker, once per build increment; at most 3 rounds, then re-plan; later rounds review only the changes since the last reviewed version; every finding gets a disposition (fixed with its proving test, wrong, intentional, not worth it); flag the whole bug class; never repeat a posted finding; unproven serious or security findings go to an unresolved list, never dropped; Deep review (several independent finders and a vote) for high-risk paths. Why: Anthropic's Claude Code team measured mean reviews to pass falling from 2.08 to 1.32 with these rules; reviewers prompted to find gaps usually report some even when the work is sound.

A8. People who read code add a review layer; they never replace the reviewer agents. Human reviewers look at intent, business rules, design and risky paths first, and at the AI findings after. Why: layered checks miss different things; a study found people shown an AI review mostly checked what it flagged.

A9. For an owner who does not read code, high-risk changes get Deep review, written sign-off of expected results by the person with authority (accountant, lawyer, client), the non-AI checks, a test copy and an undo plan, and a recommended paid human expert review before go-live. Without that expert, the change ships only after the owner accepts a written note saying it had no human code review. Why: Anthropic never lets automation fill a human slot on its riskiest code; no source shows a non-programmer safely relying on AI review alone.

A10. Verdict words: APPROVE, REQUEST CHANGES, REJECT (wrong approach, re-plan), ESCALATE (a person must decide). Commit trailer values: `approve`, `request-changes-resolved`, `request-changes-open - <what>`, `not-required - <reason>`. The trailer is the last paragraph of the commit message, on one line.

A11. LIGHT tasks relax five things: one review round; no new guards unless something failed; no planting or mutation testing; no planner (1 to 3 acceptance lines instead); no reporter unless there are [EYES] or [CHECK] items. LIGHT never drops the reviewer, the security-checker, the scripted checks or the merge check. Why: the owner's original three relaxations plus two the critics showed were safe; owner approved.

A12. The separate supervisor session is replaced by a reporter agent that re-derives claims, plus the scripted merge check. `/supervise` stays available. It becomes required again if overstatements get through. Owner approved.

A13. "Give the owner a ! command" becomes "fixed scripts the owner runs on their own computer". Live writes go only through reviewed scripts with a dry run by default. Owner approved.

A14. The method is flexible through `/setup`: questions about the person and the project. Answers change who does what, pace and strictness, never the floor (SPEC R4).

A15. Three profiles: Best results (default), Balanced, Budget.

A16. New projects and big features start with a design stage: an architect agent, an independent design review, a design card for the owner in business terms, versions checked against live package registries, and a walking skeleton built first.

A17. Scope: solo people, whether they code or not, and small teams. No company-specific features.

A18. This repo is private for now. MIT licence included so going public is one switch. Nothing may assume the repo is private.

A19. CI: Linux on every change; Windows (Git Bash) and macOS before each release and on demand. Why: a private repo's free CI minutes run out faster on Windows and macOS runners.

A20. No head-to-head benchmark against stock Claude Code (owner decision: the design rests on good evidence). The reviewer test from the original requirements and the planted-defect proofs stay.

A21. Improvement loop by hand: `/research <link>` any time and `/research-update` every 2 to 4 weeks. No scheduled watcher (owner decision).

A22. Commit attribution is off. No Co-Authored-By or session-link lines (owner rule).

A23. Hook scripts are bash plus perl with JSON::PP, run in shell form. Node is not assumed. Why: node is not installed by default; perl ships with Git for Windows, macOS and Linux.

A24. The commit-msg hook that refuses a missing trailer is not shipped. Why: the trailer is generated from receipts, so nobody types "approve".

A25. Rejected: a weekly watcher; `/autocompact` on top of the autocompact percentage; full ASD-STE100 writing; explainer videos; third-party usage mods; plugin-only distribution; the ECC plugin; `/code-review`, `/goal` or the advisor as a gate.

A26. Writing rule that had a measured effect: keep every hedge and every number exactly, with currency, sign and period.

A27. For now the method is for the owner alone, on Linux (including Claude Code cloud sessions). Linux is the only system that must pass. The Windows and macOS runs of A19 wait until the method is used on those systems or shared. The scripts keep following the portability rules, so that later run is a check, not a rewrite. Why: owner decision; it saves Windows and macOS minutes, which cost more.

A28. Each project keeps one incident checklist, `docs/incident-checklist.md`, and the review packet gives it to every checking agent (M032). The packet reads it from the merge base, so a change cannot weaken the list it is checked against; an edit to it shows in the diff. Why: M032 names one project list, and no record set up a list per agent; reading it from the base stops a change from grading itself against a list it wrote.

A29. The review packet has no size limit. Why: no rule asks for one; the plan's 80 KB cap would have refused this repo's own step 1b reviews (diffs of 85 KB and 121 KB), and M112 keeps migrations whatever their size. A limit enters the rule map with its reason first.

A30. status.sh judges commit trailers only on main's first-parent history: the commits after `VERDICTS_FROM` in `.claude/method.conf`, or, when that is not set, every commit from the oldest one there that has a trailer line. Why: what landed on main is what the record must show; commits on a task branch are work in progress, and done-check (step 4) checks a change when it merges. Older commits are accepted by moving `VERDICTS_FROM` in a reviewed change, never by rewriting main. This depends on every commit that lands on main ending with the trailer itself, so a merge or squash merge must pass the trailer through: GitHub's squash merge adds a `---------` line and Co-authored-by lines after it when the commits' authors differ from the pull request's author, and status names that as the cause.

A31. M050 ("check what a fresh clone gets") is met by run-checks' fresh-clone check together with CI's clean checkout, not by running the checks in a throwaway clone. Why: a project's checks need installed dependencies that a bare clone lacks, so a throwaway clone would fail for the wrong reason. The fresh-clone check fails on files under PRODUCT_PATHS that git ignores (here, but not in a clone) unless LOCAL_ONLY says a clone is meant to lack them, and CI runs the same checks from a clean checkout. The CI half reaches a project with step 9's CI templates; until then a project has the fresh-clone check alone.

A32. status.sh reports with three words: PASS, LOOK and SKIPPED, never FAIL. Why: status reports and never blocks (M003); LOOK asks a person to look, and its exit code 1 says the same to a caller. run-checks.sh keeps PASS, FAIL and SKIPPED, because its FAIL does block.

A33. Until review receipts exist (step 5), done-check takes a change as ready to merge only when its head commit's verdict line is `approve`. verdicts.txt holds this as its own kind, `ready`, apart from the grammar (`trailer` values stand alone); every `ready` word is also a `trailer` word. Ready words: `approve`. Why: SPEC R4 has the review run and approve, and `request-changes-resolved` means the last review asked for changes and no review approved the fixes (step 3 closed fixes that were checked but not re-reviewed as `request-changes-open`; plan v3 had "main accepts only approved work"). Reading a typed line for now does not reopen A24: done-check is not a commit hook, nothing gates a merge on it in step 4, and its READY line says the line is typed and not yet backed by a receipt.

A34. A check that runs only in the other place (runs_in `ci` locally, `local` under CI=true) never counts toward READY: done-check's elsewhere condition fails until it can read that place's result (step 9). Why: M089; a READY with exit 0 would let a merge through while a product check ran nowhere done-check can see. This also closes CI=true set by hand. The cost: a project with such a check is never READY locally before step 9.

A35. done-check matches a run-checks log to HEAD by files and parents, not by commit id: the log's commit is HEAD, has HEAD's tree and parents (HEAD amended to add the verdict line), or has HEAD's tree and is an ancestor (an empty verdict commit on top). The newest such log from the same place decides, complete or not. Why: the verdict line is written after the review, which needs the check output first (review-packet --checks), so matching the commit id would void every run; step 5's receipts are keyed to the files too.

A36. "The files on disk are the commit" (lib/tree.pl) accepts a file that differs from the stored bytes only when it equals what git's own checkout writes from the commit's own attributes: git is asked (cat-file --filters) with the system and personal attribute files off, attributes read from the commit, this machine's line-end settings pinned off and every filter driver off. git 2.42 is needed, and `.git/info/attributes` must hold no rule (git reads it even then); otherwise no conversion is accepted. Why: a committed `eol=crlf` (Gradle, `*.bat`, the method's own `*.cmd`) or `ident` file is never byte-equal on Linux, so a byte-only rule would leave such projects never clean; but a CR that only this machine's settings write turns `set -e` off in a shell script while git status sees nothing, which is the edit this rule exists to catch.

A37. done-check judges a change to VERDICTS_FROM by what it makes status stop judging: the commits on main without a valid verdict line that leave the range (Verdicts::judged, shared with status). None: it passes and names the move. Some: it passes and names them on the READY line. Why: A30 accepts older commits by moving VERDICTS_FROM in a reviewed change, and the verdict condition already asks for that review; refusing every move would block A30's route and every adoption (step 7).

A38. done-check has no `--base`: main is lib/git.pl's Git::main_ref, which does not take origin/HEAD when it names HEAD's own branch, its namesake on origin or its upstream. Why: M108 names main; a caller-chosen base, or an origin/HEAD a single-branch clone points at the task branch, would check the change against itself.

A39. M044 is split in two. M044 keeps "break the code under test on purpose" (mutate-changed.sh, step 4b); its second half becomes M122, "every input a plan's tests use takes at least two values, one of them not the default", homed in done-check.sh at step 6, where `--ready` reads the plan's parameter matrix (plan v3 section 10). Why: mutation shows a never-varied input only indirectly, as survivors on changed lines that use it; inputs used on unchanged lines, or by operators the mutator lacks, stay unseen. One rule, one home (M111). M118 was taken.
