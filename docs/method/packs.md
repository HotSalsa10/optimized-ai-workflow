# Your project's own pack

A pack is the project's own rules, checks and procedures, kept in places Claude Code already loads. There is no pack file, manifest or loader: the paths below are the pack. The method ships no pack for any one field of work; each project makes its own, and `/method-setup` starts it.

A pack adds to the method and never weakens it. How a conflict between a pack rule and a method rule is settled, and the one thing a pack may change, is the method's rule M151, under "The method is on" in `.claude/rules/method/method.md`.

## Where each part goes

| Part | Where | When Claude reads it |
|---|---|---|
| Short rules: what must always or never happen here, each ending with its reason | `.claude/rules/pack/*.md` | In every session; a rule file with a `paths:` line in its frontmatter only when Claude works on the files it names |
| Procedures: how a task here is done, step by step | `.claude/skills/pack-<name>/SKILL.md` | Its description in every session, the rest when the skill is used |
| Checks: commands that must pass | `checks/pack.tsv`, in the same five fields as `checks/project.tsv` | At every run of `bash scripts/method/run-checks.sh`; a row that uses a built-in check's id is refused |
| Risky paths: where a change gets the full route with three reviewers | `HIGH_RISK_PATHS` in `.claude/method.conf` | By done-check, before a merge |
| Lessons: what to look for after something went wrong | `docs/incident-checklist.md` | By the reviewers, in every review packet |

A pack never holds settings, hooks or agents, and nothing under the method's own paths (`scripts/method/`, `.claude/hooks/method/`, `.claude/agents/method/`, `.claude/rules/method/`, `.claude/skills/method-*`, `docs/method/`). The method's sync never reads or writes a pack, so an update of the method leaves it as it is. A change to a pack is reviewed and merged like any other change, on the full route: done-check counts `.claude/rules/pack/`, `.claude/skills/pack-*`, `checks/`, `.claude/method.conf` and the incident checklist as high-risk whatever `HIGH_RISK_PATHS` says, so such a change needs three approving reviewers.

## How it starts

`/method-setup` writes the pack's first two files from your answers:

- `.claude/rules/pack/working.md`: who decides, how much reports say, the pace, and what the project touches;
- `.claude/rules/pack/project.md`: the rules you typed, word for word.

Setup owns the block between the `method-setup` marker lines in each; run `/method-setup` again to change it. Add rules of your own outside the block, or in other files beside these two.

## Keep it small

Every session loads the project's own text: `CLAUDE.md`, `.claude/CLAUDE.md`, `AGENTS.md` and each rule file under `.claude/rules/` without a `paths:` line (the method's own rules are counted apart). When that text passes 8,000 bytes, `bash scripts/method/status.sh` says so in its `context` line, naming the biggest files. Long instructions are followed less well. To make room:

- give a rule that is about some files a `paths:` line, so it loads only for them;
- move a procedure into a skill, whose body loads only when it is used;
- cut a rule that a check already enforces.

## Examples of what a project may add

A rule that loads only for the files it is about, `.claude/rules/pack/data-files.md`:

```
---
paths:
  - "data/**"
---
- Never change a saved file's columns in place: add a new file and a step that converts the old one. Why: older copies must still read.
```

A check, a line of `checks/pack.tsv` (fields separated by tabs):

```
links	any	-	^links: (\d+) pages	perl tools/check-links.pl
```

A rollout switch: a short-lived setting that turns a change people will see on or off without a new release, with a rule saying where the switches live and when each is removed. A pack may add such a rule and a check that lists the switches still in place.

## What is not checked

No check reads what a pack rule means. A pack line that would weaken the method, such as "skip the review for small changes", loses to the method rule, and the review reads it; nothing refuses it when it is written.
