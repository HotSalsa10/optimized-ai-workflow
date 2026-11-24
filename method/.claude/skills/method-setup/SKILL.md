---
name: method-setup
description: Sets the project up for the method, or changes its setup. Asks the owner six choice questions and a few short answers, writes them to .claude/setup-answers.txt, shows setup-write's card, and writes the files only once the owner agrees.
disable-model-invocation: true
# rules: M100 M156 (served here; their home is scripts/method/lib/setup.pl)
---
# Setting up the project

The owner typed this to set the project up for the method, or to change its setup. You ask; a script writes. Only `scripts/method/setup-write.sh` writes the project's files from the answers, so the same answers always give the same files and no answer can lower the method's floor. Write none of setup's files yourself and edit no `method-setup` block by hand: change an answer and run setup again.

If you are reading this file because `/method-setup` was not found: a session that started with no `.claude/skills/` folder does not see a skill made during it. The owner can type `/reload-skills` and then `/method-setup`, or start or resume a session; or follow this file as written.

Six steps, in order:

1. **Read what is there.** Read `.claude/setup-answers.txt` when it exists: its answers are the defaults this time, and the owner changes only what they want to. Read the profile names in `scripts/method/profiles.tsv` (the first word of each line that does not start with `#`). List the folders and files at the project's top, to propose the product paths.
2. **Ask the six choice questions.** Ask them with the AskUserQuestion tool, in two calls of three (it takes at most four questions a call), each with its choices and the current answer first. When that tool is missing or refused (a plain `-p` run does not offer it), ask them in plain text, as one numbered list with the choices, and wait for the reply. Each answer's key and value for the answers file are in brackets:
   1. Who decides technical choices: Claude, telling you in one line (DECIDES claude), or you, asked each time (DECIDES owner).
   2. Reports: short, the decisions and results, still with the five parts every report has (REPORTS short), or full, also how it was done (REPORTS full).
   3. Pace: small steps, one change at a time (PACE small), or larger steps (PACE larger).
   4. Does the project touch real money, people's personal data or records outside this repository? Any of them, each on a line of its own (TOUCHES money, TOUCHES personal, TOUCHES outside), or none (TOUCHES none, alone).
   5. Strictness: standard (STRICT standard), or strict, where every change takes the full route with three reviewers (STRICT strict).
   6. Profile: Best results, the default (PROFILE best); Balanced, cheaper and slower to catch subtle bugs (PROFILE balanced); or Budget, cheaper again and weaker on long or subtle work (PROFILE budget). Every profile keeps the checking agents on Opus 5.5 at xhigh effort; a profile changes only the model and effort of the session the owner talks to, from their next session.
3. **Ask the short answers**, in plain text and in the owner's own words. Each may be left empty:
   - what the project is, in one line (PROJECT_WHAT);
   - what must never go wrong (NEVER_WRONG);
   - the rules that must always hold here, one per line (RULE, a line per rule);
   - how the project starts, as a command (HOW_IT_STARTS);
   - the command that runs the fast tests (TEST_COMMAND);
   - the product paths, where the project's own code and content are: propose them from step 1 (PRODUCT_PATH, a line per path);
   - when the project touches money, personal data or outside records, the paths that do it (RISK_PATH, a line per path).

   Tell the owner to put no key, password or personal data into an answer: setup refuses such an answer, naming it and never showing it.
4. **Write the answers and show the card.** Write `.claude/setup-answers.txt`, replacing it whole: one `KEY<TAB>value` line per answer, with a real tab between the two, in the order above. A short answer left empty is its key with nothing after the tab; a list left empty (RULE, PRODUCT_PATH, RISK_PATH) needs no line. Then run `bash scripts/method/setup-write.sh` in a Bash call of its own, with nothing chained to it (the guard refuses a call that names the method's scripts beside a command that writes). It writes nothing: it prints the card, what the answers change, and a line for each file it would write. Show the owner the card and those lines as printed. On a second run the card also names the entries setup keeps: it never removes one. When setup refuses (exit 1), tell the owner which answer it names and why, ask for that answer again, and repeat this step; repeat no refused value, and commit nothing.
5. **The owner agrees.** End with this one question, and stop:

   Reply `write` to write these files.

   On that reply, run `bash scripts/method/setup-write.sh --write`, again in a Bash call of its own. When the card's first line begins `Settings first`, tell the owner that `.claude/settings.json` now holds the profile, that the guard refuses applying a settings change during a session, and that the profile applies from their next session.
6. **Report and hand on.** Say what was written, with setup-write's last lines as printed. The change is reviewed and merged like any other: commit the answers file and what setup wrote on a branch of their own, never main, and take them on with /method-finish. On a first install, push them to the install branch; the review then runs in a fresh session started on that branch, which loads the method's newly installed hooks and checking agents. Rules the owner adds later go in `.claude/rules/pack/`, beside the two files setup writes; `docs/method/packs.md` says what a pack may hold.
