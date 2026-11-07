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

- "Getting started with Claude Code Mods": what mods are and how to make them; its safety notes match the docs.
- "You're probably overprompting Claude": newer models need fewer instructions; remove some and add back what the model misses; subagents only for substantial standalone work. A sort of the rule map found 15 of 122 rules that a current model may follow without being told; the "over 80%" cut it reports was Claude Code's own general prompt (seen only as a search summary). Step 6 merges overlapping rules; a with-and-without trial of the 15 was judged not worth its cost for now (TASKS).
- "Critical thinking when agents do the work": offloading, deferral and surrender; a green check proves one thing; define "verified" up front; list the agent's decisions; a quiz before merge; the orchestration tax. Source of M123 to M127.

## Other sources

- Chris Titus, "My AI Coding Workflow That Actually Works" and the titus-ai repo (read in full): the step order, the merge gate, pinned versions.
- Cloudflare, "Cutting our inference bill by 68% by being obsessive about optimization" (Oct 2026, read in full through a public mirror): cache-friendly prompts, fixed tool lists, a randomised test where a reviewer at high effort caught more serious findings than at medium. (A3, A7)
- Independent studies on agents (mix of read in full and summary): one writer for connected work beats delegation (Anthropic measurements, an independent single-task test); valid outside tests raise solve rates (TDFlow); agents game tests mostly on impossible or ambiguous tasks (ImpossibleBench, EvilGenie); models favour their own output when judging it; long always-loaded instruction files reduce success; AI review tools catch only part of known issues.

## Limits

Many research sites are blocked from the cloud environment used for planning, so some sources were seen only through search summaries. The main conclusions rest on sources read in full. Re-check with `/research-update` (planned).
