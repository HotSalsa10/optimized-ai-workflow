# The method's hooks

Claude Code runs these scripts by itself, from this project's `.claude/settings.json` (M073: few hooks, each written up with what it prevents, what it costs and how it was seen to fire). The method has three:

| Hook | When it runs | What it does | Step |
|---|---|---|---|
| `session-status.sh` | every session start, resume, `/clear`, compaction and fork | tells Claude "the method is on" and lists what needs a look | 5.4 |
| `guard.sh` | before each command, edit or outside tool | refuses the risky ones | 5.5 to 5.10 |
| `gate-receipt.sh` | when a checking agent starts and stops | writes a receipt of what it checked | 5b |

## Where the hooks do not run

Then nothing in the session itself stops a risky command; CI and done-check are the net (RISKS #16).

- A cloud session with several repositories, and a Projects thread.
- A session before you accept the trust dialog for the folder.
- A session started in a subfolder of the project (measured; the harness keeps checking it).
- A session started with hooks switched off: `disableAllHooks` in `.claude/settings.local.json`, or `--settings '{"disableAllHooks": true}'`.
- A session whose settings file holds one value of the wrong type: Claude Code skips the whole file, hooks included (measured; `tests/settings.test.sh` checks every value's type).

In each of these, the session's first message has no `METHOD-ACTIVE` line. That is the sign the method is off.

## session-status.sh

**What it does.** At every session start it adds, at most, 10 lines and 1,200 bytes to what Claude reads first:

1. `METHOD-ACTIVE vunreleased` (the version comes with step 7). It is printed before perl starts, so it is there even when perl or the method's scripts are missing.
2. `status.sh --quick`'s summary line and its LOOK lines: uncommitted or unpushed work, commits missing a verdict, records, effort. CI is left to `/start`, as it waits on the network.
3. A LOOK line for each setting that weakens the method in this session:
   - the advisor not switched off;
   - auto memory switched on by `CLAUDE_CODE_DISABLE_AUTO_MEMORY=0`;
   - a model other than claude-opus-5-5;
   - on Windows, the PowerShell tool not switched off;
   - hook input it cannot read (then the model is not checked);
   - in the project's `.claude/settings.local.json`, which ranks above the project's settings: a key the method sets, `disableAllHooks`, skill shell lines switched on;
   - in it and in your user settings (`~/.claude/settings.json`, or `$CLAUDE_CONFIG_DIR/settings.json` when that is set), what adds to every session: an env variable, a PreToolUse or PermissionRequest hook (the method's own are only in the project's settings, so a copy there counts too), an enabled plugin, an effort cap below xhigh (`maxEffortLevel`, also per model in `modelSettings`);
   - a settings file that is not a regular file, is over 1 MB, or is not JSON;
   - in user settings, `availableModels` (lists add up across settings files, so a model listed there can be chosen);
   - a per-model `effortLevel` below xhigh (`modelSettings`).

   The perl part ends within 20 s, so METHOD-ACTIVE always arrives; a cut-off run says so. A nested run (`METHOD_NESTED=1`, set by the method for `claude -p` inside a session) skips status but still checks the settings, so `METHOD_NESTED` set in a settings file is named.
   Names are shown, never a settings value; a model id only in the shape Anthropic's ids have, and an effort cap by its level.
4. When more does not fit: `... N more: run bash scripts/method/status.sh`.
5. If its perl part fails, METHOD-ACTIVE is still there, with a LOOK line saying the rest is missing.

**What it prevents.** Working while the method is silently off or weakened, and losing track of where things stand after a compaction or `/clear`.

**What it costs.** About 0.2 to 0.3 s (two perl starts and status without the network) and at most 1,200 bytes of context per session start. Status gets 5 s; past that, a LOOK line says so.

**How it was seen to fire.** In the real Claude Code client against a local fake Claude (`tests/harness.test.sh`, at 2.1.316 and 2.1.319): the line and status's summary reach the first request; also with a dirty tree, after a resume (with its own status: the client does not add output identical to what the conversation already holds, so a resume with nothing new adds nothing; after a compaction this is not measured), without perl on PATH, and in a nested run. Its own tests: `tests/session-status.test.sh`.

**What it cannot do.**
- It cannot block anything: SessionStart cannot.
- It cannot see the client's version or effort level: hooks get neither. `/start` checks them.
- It always exits 0: text printed with any other exit code does not reach Claude.
- An exported shell function named `command` or `unset`, or SHELLOPTS, set through a settings file's env, can still change what its bash runs; step 5.9 proves the hook command's prefix against these.
- It never runs where hooks do not run (above).

## guard.sh

**What it does.** Before each command, file edit and outside tool, Claude Code hands the call to the guard (`lib/guard.pl`). The guard either lets it through or refuses it with one line saying which rule, why, and what to do instead. Each refusal adds a line to `.method/local/guard.log` (the time, the rule, the tool and a fingerprint of the call; never the command itself), and `status.sh` shows them as a LOOK until the log is removed.

It reads command words; it is not a shell. It is a seatbelt, not a lock (DECISIONS A50): a program Claude writes to a file and then runs, or words put together only when a command runs, are not read. CI and the review see what such a program changed, afterwards.

**The rules so far (steps 5.5 and 5.6; more come in 5.7 to 5.10):**

| Rule | Refuses | Why |
|---|---|---|
| G0 cannot-tell | A command it cannot read, when that command could touch git, gh, claude, curl, wget or one of the method's files (each command is judged by its own text; shapes whose meaning can come from elsewhere in the call by the whole call, A57). "Cannot read": command substitution or backticks (also in an assignment or a `for` header; what a substitution runs is read as commands of their own too, so the git rules see a git command inside one); eval of anything but plain text (also behind `builtin`, `time` or `trap`); a variable as the command word; a glob or brace in the command word (refused whatever it names); code piped or written into a shell or another interpreter (a program file or module reading data is fine; `-`, `/dev/stdin`, a shell's `-s` and `python -m code` read code); a program or `source` given a process substitution `<(...)`; an alias definition (refused whatever it names); an interpreter's inline program that can start a program; `source`; a glob or brace in a write target near the method's or git's folders; a case statement; a coprocess; text it cannot split. Watched words are looked for in any letter case and also with quotes and backslashes removed, so `g''it` and `\git` count. ANSI-C and locale quoting are decoded, and `$(cat <<'EOF' ... EOF)` (Claude Code's own way of writing a commit message) is read as the plain text it is. A variable in a write target is G6's (step 5.7). Also input that is not one JSON object. | A guard that reads words is safer refusing than guessing (A57). |
| G1 perl-missing | Every call, when perl or its JSON::PP module is missing. | Without perl nothing can be checked. |
| G2 powershell | Every PowerShell call. | The method's checks read bash. |
| G3 git-shapes (step 5.6) | A git command aimed at this project's repository (any of its worktrees too) that is not on the git list, `git-shapes.txt` beside the guard: reading, staging and committing, new branches, switching with no uncommitted changes, fetching the remote's branches, bringing the remote's main into a task branch. A push may go only to a task branch, named plainly (`git push [-q] [-u] <remote> HEAD`, `HEAD:<branch>`, `<branch>` or `<branch>:<branch>`), never to main, with no setting that could redirect it, and with nothing in the same call that could move what it sends. A `GIT_` variable that points git elsewhere, git's options that do the same (`--git-dir`, `-c core.hooksPath=...`), changing git's global settings, and leaving a worktree with `discard_changes`. Git's own programs called by their dashed names (`git-push`, `/usr/lib/git-core/git-reset`), which the list cannot judge in that form: run them as `git push`. Git commands aimed at another repository (a scratch clone, a test folder) are judged only when they push to a remote that is not a folder on this machine, or into this repository. | Claude lands nothing on main (RISKS #4) and loses no work; the owner merges on GitHub. |
| G8 mutant-commit (step 5.6) | `git commit` while a mutate-changed run, or what one left behind, is in this repository. | A commit could hold a mutant (A41). |

**Adding a git shape.** If your project needs a git command the list refuses, add a line to `.claude/method-local/git-shapes.txt` in the list's own form: the shape, ` :: `, and why (the form is written at the top of `git-shapes.txt`). For example `stash :: I keep work aside this way`. session-status counts such lines at every session start. Pushes are judged by the guard itself, so no line can allow a push to main.

A refused call can almost always be written plainly: one command per line, with every word written out. The guard also says: do not try another form of the same command; tell the owner what was needed.

**What it costs.** One bash and one perl start per guarded call: about 29 ms median and 37 ms at the 90th percentile on Linux (measured over 40 calls, step 5.5; the plan's targets are 40 and 60 ms). Git Bash on Windows starts processes more slowly; expect several times that (not measured yet, A27).

**How it was seen to fire.** In the real Claude Code client against a local fake Claude (`tests/harness.test.sh`): a G0 refusal reaches Claude as an error and the command does not run; a plain command runs; a Monitor command is checked too; with the guard's script missing the call is still blocked (onFailure "block"); without perl the call is refused (G1); and in acceptEdits mode the refusal holds. Its own tests: `tests/guard.test.sh`. The git list (5.6): a push to main is refused with its reason, and a task branch's push runs; its own tests, in real repositories: `tests/guard-git.test.sh`, and `tests/plants/git-shapes.sh` shows every line of the list is needed. A commit-and-push call takes about 65 ms (the guard asks git a few questions).

**What it cannot catch.** See "Where the hooks do not run" above, and DECISIONS A50's list: a program written to a file and then run; words put together at run time; a renamed copy of the claude binary; MCP write tools whose names look read-only; a mod.

## When the guard blocks something it should not

The guard refuses rather than guesses, so now and then it will refuse something harmless. What to do, in this order:

0. Ask Claude to write the command plainly: one command per line, every word written out. That is almost always enough. Or run that one command yourself, in a terminal in the project folder: the guard checks only what Claude runs.
1. If the guard itself is wrong, switch the hooks off for one session on your own computer: start Claude Code with `claude --settings '{"disableAllHooks": true}'`.
2. Or, before you start the session, make a file named `settings.local.json` in the project's `.claude` folder holding exactly this line, and delete the file afterwards (it is not committed):

   ```json
   {"disableAllHooks": true}
   ```
3. Either way, the session's first message has no `METHOD-ACTIVE` line: the method is off for that session. Do only the repair in it, and tell Claude what the guard got wrong, so the guard can be fixed.

Claude cannot do either for itself: the guard refuses a change to the settings files during a session (from step 5.9), and the change only applies to a new session anyway.

**In a cloud session:** the guard refuses Claude's repairs, by design, and there is no local file you can edit. On GitHub, open the repository, go to `.claude/settings.json`, click the pencil (Edit), set `"disableAllHooks": true`, and commit to a branch. Start a new cloud session on that branch, do the repair, then set it back to `false`. (RISKS #16.)
