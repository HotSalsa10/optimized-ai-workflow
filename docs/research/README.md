# Research behind the decisions

The evidence the method rests on, grouped by question. Full reports were produced during planning; this file keeps the sources and the main findings. "Read in full" means the source itself was read; "summary" means only a search summary was seen, which is weaker.

## Claude Code behaviour (measured in a cloud session, Oct 2026)

- Project settings `model` plus `availableModels` forced agents pinned to Haiku, and agents asked for Haiku, onto Opus (token accounting). `CLAUDE_CODE_SUBAGENT_MODEL` and its FORCE switch are dropped from project settings in host-managed cloud sessions. (DECISIONS A2)
- `CLAUDE_CODE_EFFORT_LEVEL` in project settings silently overrides `--effort`, `/effort` and agent frontmatter. (A4)
- A project hook blocking `git commit --no-verify` fired in a cloud-style run.
- The `attribution` setting removes Co-Authored-By and session-link lines. (A22)

## Official docs and Anthropic posts (read in full)

- Claude Code docs, code.claude.com: memory, settings, model configuration, sub-agents, hooks, skills, plugins, cloud environments, permission modes.
- Model launch pages for Opus 5.5, Sonnet 5.5 and Haiku 5.5, anthropic.com: scores and costs at each effort level.
- claude.dev blog: "Getting the most out of Opus 5.5", "Using Claude Code: Spending your effort", "What a task costs on Opus 5.5", "The new rules of context engineering for Claude 5 generation models", "Lessons from building Claude Code: How we use skills", "A harness for every task: dynamic workflows in Claude Code", "Claude Code in the cloud". (A3, A6)
- "How the Claude Code team does code review" (claude.dev, Oct 2026): review rounds capped at three; re-review of the new diff only; every finding answered; approval covers one commit; risk tiers set from the change; an agent's approval never counts as a person's; incidents turned into a reviewer eval. Mean reviews to pass fell from 2.08 to 1.32. (A7, A8)

## Claude Code docs, checked Nov 2026 (read in full), after the owner shared four posts by Addy Osmani

- Mods: plugins whose hooks are JS or TS modules run inside Claude Code; a hook can observe, change or answer an event (it can deny a tool call); on by default from 2.1.287 (terminal). A cloud session does not install plugins a repo names in .claude/settings.json, and never shows the workspace trust dialog a repo's .claude/skills/ plugin needs; a hook that throws or times out lets the action through; "the events and methods can change between releases". (A44)
- Settings hooks: 33 events, five hook types. A repo's committed hooks run in a cloud session with one repository; not with several, and not in a Projects cloud thread, which loads only CLAUDE.md. onFailure "block" (from 2.1.295) works on command and http hooks, not on Stop, SubagentStop, TaskCompleted, TeammateIdle or async hooks. (RISKS #16)
- /goal is a prompt-based Stop hook: a small model judges a condition from the transcript after each turn, reading no files and running no tools, so it is not a gate (M075). Auto mode is the default for interactive terminal and VS Code sessions from 2.1.283; "auto" set in project or local settings has no effect. /doctor prompt-audit (2.1.283) flags outdated or conflicting instructions. /code-review runs as a forked subagent that does not see the conversation. Typing "ultrathink" mid-turn raises the rest of the turn to xhigh (2.1.311, terminal).

## Posts by Addy Osmani (Nov 2026; read as pasted by the owner, claims checked against the docs above)

- "You're probably overprompting Claude": newer models need fewer instructions; remove some and add back what the model misses; subagents only for substantial standalone work. A sort of the rule map found 15 of 122 rules that a current model may follow without being told; the "over 80%" cut it reports was Claude Code's own general prompt (seen only as a search summary). Step 6 merges overlapping rules; a with-and-without trial of the 15 was judged not worth its cost for now (TASKS).
- "Critical thinking when agents do the work": offloading, deferral and surrender; a green check proves one thing; define "verified" up front; list the agent's decisions; a quiz before merge; the orchestration tax. Source of M123 to M127.

## claude.dev posts (read in full on 22 Nov 2026), and one post as pasted

These posts give the vendor's own numbers, from Anthropic's internal models and runs; each is marked "vendor's figure" below. No post names a Claude Code version unless noted. No number from them backs a decision. Read for the step 6b re-check (docs/plans/step6b.md, items P1 to P14 and N1 to N5).

- Addy Osmani, "Getting started with Claude Code mods" (Tutorials, 1 Oct 2026): a mod is a plugin whose JavaScript or TypeScript runs inside Claude Code and can watch, change or refuse what it does. Claude writes one from a plain request using Claude Code's built-in plugin-authoring skill, into `~/.claude/dev-mods/<session id>/`. A mod is shared and installed like any plugin (`claude plugin install <name>@<marketplace> --scope user`). Its safety notes match the docs. (M105; M132's mods and plugins folders, step 6b.4)
- Vivek Nair, "Using a 'chaos loop' to harden the Claude Docs launch" (Engineering, 17 Nov 2026): rules that must always hold, written down before the work and checked on every change; for anything hard to undo, stop and give a few options with a recommendation. Its "60 server errors across billions of requests" is the vendor's figure; its cost of "$3,000 to $10,000" for a two-week push is the author's estimate, which he says he never ran. Not seen: the text inside its figures.
- Addy Osmani, "How the Claude Code team thinks about verification" (Engineering, 16 Nov 2026): end-to-end, property and differential tests; the old system's outputs as the expected results, with a list of approved differences; run the app end to end; a smoke check must be fast and reliable; a reviewer score is trusted only on cases its tuner never read; findings tagged Important, Nit or Pre-existing. Its "up to 10 points" from a separate grader is the vendor's figure, an internal test with no data shown.
- Addy Osmani, "Which Claude model should you build with? Fable, Opus, Sonnet, or Haiku" (Playbooks, 9 Nov 2026): four generally available models (Haiku 5.5, Sonnet 5.5, Opus 5.5, Fable 5.2); Mythos 5.2 only through verification programs; switching model drops the earlier model's reasoning; alias and default facts tied to Claude Code v2.1.293.
- Barry Zhang, Tianyi Peng, Elle Najt, Keller Scholl and Lance Martin, "Safely scaling multi-agent teams with Claude Fable 5.2" (Agents, 9 Nov 2026): 1,000 agents (the vendor's figure) on an early Fable 5.2, a shared database, and a classifier that checked every shell command and file edit before it ran. Not seen: its figures and videos.
- Lance Martin and CJ Avilla, "Building effective agent automations" (Agents, 8 Oct 2026): a write counts only once the destination confirms it ("Confirm the post landed before recording it"); credentials stay outside the agent's sandbox.
- Addy Osmani, "Building with Claude Sonnet 5.5" (Playbooks, 28 Sep 2026): default effort medium in Claude Code and high on the API; for xhigh or max, consider Opus 5.5; alias facts tied to Claude Code v2.1.284.
- Lance Martin, "Automating eval design and hillclimbing with Claude" (Playbooks, 28 Sep 2026): a held-out test set, a noise check before round one, one change per round, a change kept only if the test set also rises, results with confidence intervals; read a sample of scored runs before trusting a grader. Not seen: the text inside figures 2 to 7.
- Raymond Wang, Sam Attard and Issac G., "How we made claude.ai 3x faster in two weeks" (Engineering, 23 Sep 2026; the 3x is the vendor's figure): unit tests before any optimisation; a flaky benchmark is thrown out, never used as a CI gate; anything that could cause a user-visible problem ships behind a short-lived feature flag. Not seen: its two videos.
- Thariq Shihipar, "Using Claude Code: The unreasonable effectiveness of HTML" (Playbooks, 20 May 2026): HTML pages instead of Markdown for reports a person reads; plan files kept and handed to a verification agent.
- Thariq Shihipar, "Lessons from building Claude Code: Prompt caching is everything" (Engineering, 30 Apr 2026): stable content first; one model and a fixed tool list per session; changing either rebuilds the cache. (A2, M096)
- Thariq Shihipar, "Seeing like an agent: how we design tools in Claude Code" (Agents, 10 Apr 2026): the AskUserQuestion tool for structured choices; the form may change between releases.
- Addy Osmani, "Your coding agents made you a manager" (Nov 2026; read as pasted by the owner on 19 Nov 2026, not read in full): give the agent a way to check its work; set clear context; turn a correction made twice into a standing rule; enforce only what cannot bend; plan before building, with a second session reviewing the plan; steer early and restart after two failed corrections; delegate the task, never the judgment; answer five questions before an unattended run; add agents only as fast as checks take over watching. Its claims are not checked against the original (see Limits), and nothing from it enters the method until it is read in full.
- Anthropic's model pages (read on 24 Nov 2026 for A81): the models overview, "Choosing a model" and "What's new in Claude Fable 5.2" on platform.claude.com (start with Opus 5.5; move to Fable 5.2 when evals on Opus at higher effort fall short; Fable $8/$40 per million tokens against Opus $4/$20), the launch post "Claude Fable and Mythos 5.2" (9 Nov 2026; its benchmark scores are the vendor's figures), Claude Code's model-config page (Fable 5.2 needs v2.1.321 or later; no plan selects it by default) and the support page "Claude Fable models on your plan" (up to 50% of a plan's weekly limit).

## Other sources

- Chris Titus, "My AI Coding Workflow That Actually Works" and the titus-ai repo (read in full): the step order, the merge gate, pinned versions.
- Cloudflare, "Cutting our inference bill by 68% by being obsessive about optimization" (Oct 2026, read in full through a public mirror): cache-friendly prompts, fixed tool lists, a randomised test where a reviewer at high effort caught more serious findings than at medium. (A3, A7)
- Independent studies on agents (mix of read in full and summary): one writer for connected work beats delegation (Anthropic measurements, an independent single-task test); valid outside tests raise solve rates (TDFlow); agents game tests mostly on impossible or ambiguous tasks (ImpossibleBench, EvilGenie); models favour their own output when judging it; long always-loaded instruction files reduce success; AI review tools catch only part of known issues.

## Limits

Many research sites are blocked from the cloud environment used for planning, so some sources were seen only through search summaries. The main conclusions rest on sources read in full. Re-check with `/research-update` (planned).

Not read in full: Addy Osmani, "Your coding agents made you a manager" (Nov 2026). Only the copy the owner pasted was seen; addyosmani.com is outside the build session's allowed network. To read it, allow that host or paste the full text.
