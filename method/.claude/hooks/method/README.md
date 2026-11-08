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
   - a settings file that is not a regular file, is over 4 MB, or is not JSON.
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
