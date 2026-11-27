# optimized-ai-workflow

A working method for building software and documents with Claude Code, for any project in any field. A tagged release of it is copied into each project, and the project is updated from later releases.

## What it is

The method makes Claude Code work in small, checked steps. Every change is planned, built, checked by the project's own checks, and reviewed by checking agents in a fresh context before you merge it. Rules that can be enforced are enforced by hooks and scripts, not left to Claude's memory. You decide what is built and when it merges; Claude builds, checks and reports in plain words.

It is not a product you run, a hosted service, or a replacement for your judgment: the method can lower the chance of a bad change, never remove it. It ships no rules for one field (such as accounting or a web shop); each project adds its own in its pack (DECISIONS A77).

## Status

Release 1 (`v1.0.0`) runs on Linux and in Claude Code cloud sessions (claude.ai/code). It is not yet supported on a Mac or a Windows computer: the scripts are written for them, but no test has run there (DECISIONS A27). Release 2 adds the comparison with plain Claude Code and more hardening (ROADMAP.md).

## Before every new session

- **Pick the model and effort.** In a cloud session, pick `claude-opus-5-5` and effort xhigh when you open it. The picker outranks the project's settings, so a session opened at a lower effort runs the main session at that effort, whatever profile the project has. The checking agents are not affected: their own files set xhigh (RISKS #29).
- **Check what is allowed.** On each new clone of a project, type `/permissions` before the first task and check that nothing is allowed that you did not allow. A clone can bring settings with it, and an allow rule you did not choose lets a command run without asking.

## Install it in a project

You need: the project's repository on GitHub, the Claude GitHub App given access to it and to this repository, and about an hour. Claude does the typing; you open the sessions, answer the questions and merge.

1. **Open the install session.** On claude.ai/code, choose "New session". Pick the project's repository first, then this one. Pick the project's main branch, the model `claude-opus-5-5` and effort xhigh. A session with two repositories runs no repository's hooks, which is what an install needs: hooks cannot guard their own replacement.
2. **Ask for the install.** Say which release, for example "Install the method v1.0.0 in this project". Claude checks this repository out at that tag, runs `scripts/release/sync.sh --to <the project>` first as a dry run, which writes nothing and lists each file, then with `--write`. Sync stops and names what it will not overwrite, such as a setting of your own that could switch the method off; you keep one only by naming it.
3. **Set it up.** In the project's folder, type `/reload-skills`, then `/method-setup`. Claude asks six choice questions and a few short ones in your own words, then shows one screen of what your answers change. Nothing is written until you reply `write`. Setup also writes `.github/workflows/method-checks.yml`, which runs the project's checks on GitHub on every push.
4. **Push the install.** Claude commits the install on a new branch, `claude/method-install`, and pushes it.
5. **Open the review session.** Choose "New session" again, with only the project's repository, on the branch `claude/method-install`, at `claude-opus-5-5` and xhigh. Its first line should begin `METHOD-ACTIVE`: the hooks are on. Claude plans the install as a change, you approve the plan, and the checking agents review it. Setup wrote files that steer the method, so the install takes the full route, with three reviewers.
6. **Open the pull request.** Claude opens it with the GitHub tools the session has. When it cannot, it writes the pull request's title and text to `.method/local/pr-body.md` and gives you the clicks: on GitHub, "Pull requests", "New pull request", the branch, then paste the title and the text.
7. **Merge it.** Read Claude's report, then merge on GitHub. Paste the whole merge message Claude gives you: its title, a blank line, its text, and the `Review-Verdict` line last. For "Squash and merge", delete the "Co-authored-by" lines GitHub adds below it, or the verdict line is no longer last.

If the review session cannot start, you may merge the install without a review, once per project (your decision of 23 November 2026, RISKS #21); status then names that commit.

## Update it

Tested offline only: the live test of Release 1 covers the install, not the update. An update runs like an install: a session with both repositories, where the project's hooks are off, on a new branch of the project; Claude runs the new release's sync (dry run, then `--write`); sync replaces only method files nobody changed since the install, and names the ones it will not touch. Then the same review session, pull request and merge as steps 5 to 7.

In a session with the project's hooks on, the guard refuses any sync run with `--write`: Claude can show you the plan there, but not write it.

## Take it out

Tested offline only. `scripts/release/sync.sh --to <the project> --uninstall` shows the plan of taking the method out and writes nothing; with `--write` it writes it, only when the whole plan holds, and again only in a session where the project's hooks are off. It removes only what the method put there and nobody changed since, and gives back the project's settings as they were before the install. What stays is named: your own files and settings, the method's logs in `.method/local/`, and the files `/method-setup` wrote that still mention the method, which Claude removes or edits with you on the same branch. More in `examples/README.md`, "Taking the method out".

## Running the method's scripts

Claude runs them for you. If you run one yourself, run it from the project's top folder by its path, for example `bash scripts/method/status.sh` or `bash scripts/method/run-checks.sh`. A script started by a bare name found elsewhere on your computer stops and says how to run it, because it could otherwise run another project's helper code.

## What the start of a session tells you

- `METHOD-ACTIVE` and the release: the hooks are on. With no such line, the hooks are off; Claude says so first and changes no code until you decide.
- `status:` and `session-status:` lines with `LOOK`: something needs your eyes, named on the line.
- A line that says "tell the owner": your own Claude Code folder (on your computer, or the account a cloud session runs under) holds something that can hide or replace the method in every project, such as a personal skill named like one of the method's, or a setting that keeps project instructions out. Only you can change that folder; Claude names what it found and gives you the steps.
- In a cloud session, `/method-start`'s "open pull requests" can read "could not read": some of GitHub's commands are not available there. It does not mean there are none.

## The three profiles

You choose one in `/method-setup`; it changes only the main session you talk to. The checking agents stay on the strongest settings in every profile.

- **Best results** (the default): Opus 5.5 at xhigh effort. In a cloud session, pick xhigh in the picker too.
- **Balanced**: Opus 5.5 at medium effort. Cheaper; slower to catch subtle bugs.
- **Budget**: Sonnet 5.5 at medium effort. Cheaper again; weaker on long or subtle work. When a check misses something, step up a profile.

## What the floor stops, and what it does not

Stops, in a session where the hooks run: a push to main, a merge or a tag made by Claude, a write to the method's own files and settings, a command the guard cannot read, a settings change mid-session that would switch the hooks off, and a review that does not count (cut off, run below its effort, or made on other files). "Ready to merge" is computed by a script from the receipts, the checks and the plan's approval, not stated by Claude.

Does not stop: anything in a session where the hooks do not run (a session with several repositories, a session started in a subfolder), a program Claude writes to a file and then runs, a mod or plugin you install yourself, or a wrong decision that every check agrees with. The checks on GitHub, the review and your merge are the locks outside the session. `docs/method/why.md`, in each project, says rule by rule what is enforced and what is only written down.

## What it costs

- **Your plan's usage.** Every session, and each checking agent it launches, uses your Claude plan. A change on the full route launches at least four checking agents; one with three reviewers, six or more. Best results uses the most.
- **GitHub Actions minutes.** The project's CI runs on every push. A public repository's minutes are free; a private one uses its monthly minutes.
- **Your time.** You approve plans, read the reports, and merge.

## Read more

- `docs/method/why.md` in each project: what enforces each rule.
- `.claude/hooks/method/README.md` in each project: each hook, what it stops and what it costs.
- What changes for you in each release: [CHANGELOG.md](CHANGELOG.md).
- What it must do: [SPEC.md](SPEC.md). What is being built and in what order: [ROADMAP.md](ROADMAP.md). Decisions and why: [DECISIONS.md](DECISIONS.md). Every rule and where it lives: [docs/rule-map.md](docs/rule-map.md).
- Three example projects: [examples/README.md](examples/README.md).

Licence: MIT.
