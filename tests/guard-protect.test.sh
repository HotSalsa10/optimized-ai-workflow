#!/usr/bin/env bash
# Tests for the guard's protected files (step 5.7): G6, Claude reads the
# method's files, its settings and git's own config and hooks but never
# writes them (lib/protect.pl), and G12, one warning when a session runs
# below xhigh. guard.sh runs with a hook's input in a real project laid out
# as sync will lay it out, with a bare origin and a home folder of its own.
# shellcheck disable=SC2016 # single-quoted commands are meant literally
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}
echo "tests: guard (protected files)"
root=$(repo_root)
lib="$root/method/scripts/method/lib"
guard="$root/method/.claude/hooks/method/guard.sh"
work=$(new_sandbox_dir) || abort_sandbox
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
unset XDG_CONFIG_HOME CLAUDE_CONFIG_DIR GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
mkdir -p "$HOME/.claude"
git config --global user.email test@example.invalid
git config --global user.name Test
git config --global init.defaultBranch main
git config --global commit.gpgsign false
printf '{}\n' >"$HOME/.claude/settings.json"

# the project: the method's files where sync puts them, on a task branch
git init -q --bare "$work/origin.git"
# (its folder name holds a non-ASCII letter, as the hook input gives it in
# characters and the file system in bytes)
git clone -q "$work/origin.git" "$work/projü" 2>/dev/null
proj="$work/projü"
(
  cd "$proj" || exit 1
  mkdir -p .claude/hooks/method .claude/method-local .claude/skills/verify .claude/skills/method-start .claude/skills/deploy scripts/method src build sub
  printf 'guard\n' >.claude/hooks/method/guard.sh
  printf '{}\n' >.claude/settings.json
  printf '#!/bin/sh\necho status\n' >scripts/method/status.sh
  printf 'skill\n' >.claude/skills/verify/SKILL.md
  printf 'method skill\n' >.claude/skills/method-start/SKILL.md
  printf 'project skill\n' >.claude/skills/deploy/SKILL.md
  printf 'notes\n' >notes.txt
  printf 'app\n' >src/app.py
  git add -A && git commit -qm one && git push -q origin main && git switch -qc task
  # a branch that changes the guard, and one that changes only the app
  git switch -qc evil && printf 'evil\n' >.claude/hooks/method/guard.sh && git commit -qam evil
  git switch -q task && git switch -qc app && printf 'app 2\n' >src/app.py && git commit -qam app
  # (step 6.3) a branch whose method-start skill differs, and one that
  # changes only a project skill
  git switch -q task && git switch -qc skillv && printf 'other skill\n' >.claude/skills/method-start/SKILL.md && git commit -qam skillv
  git switch -q task && git switch -qc deployv && printf 'project skill 2\n' >.claude/skills/deploy/SKILL.md && git commit -qam deployv
  # (step 7.2) a branch that adds a method- skill no list names
  git switch -q task && git switch -qc quickv && mkdir -p .claude/skills/method-quick && printf 'quick\n' >.claude/skills/method-quick/SKILL.md \
    && git add -A && git commit -qm quickv
  git switch -q task
) || abort_sandbox
evil=$(git -C "$proj" rev-parse evil)
appc=$(git -C "$proj" rev-parse app)
skillc=$(git -C "$proj" rev-parse skillv)

# judge NAME CWD COMMAND WANT: guard.sh on a Bash call run in CWD; WANT is
# "allow" or a rule ID (the refusal must start "guard RULE:" and exit 2)
run_guard() {
  err=$(cd "$1" && env -u CLAUDE_CODE_EXECPATH CLAUDE_PROJECT_DIR="$proj" perl -e 'alarm 60; exec @ARGV' bash "$guard" <"$work/in.json" 2>&1 >"$work/out.txt")
  code=$?
}
want() {
  name=$1
  case "$2" in
    allow) if [ "$code" -eq 0 ] && [ -z "$err" ]; then pass "$name"; else fail "$name: wanted it let through" "exit $code: $err"; fi ;;
    *) case "$err" in
        "guard $2: "*) if [ "$code" -eq 2 ]; then pass "$name"; else fail "$name: wanted exit 2" "exit $code: $err"; fi ;;
        *) fail "$name: wanted guard $2" "exit $code: $err" ;;
      esac ;;
  esac
}
judge() {
  wanted "$1" || return 0
  CMD="$3" CWD="$2" perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({tool_name => "Bash", tool_input => {command => $ENV{CMD}}, cwd => $ENV{CWD}, hook_event_name => "PreToolUse", session_id => "s1", effort => {level => "xhigh"}})' >"$work/in.json"
  run_guard "$2"
  want "$1" "$4"
}
# tool NAME TOOL JSON-INPUT WANT: guard.sh on another tool's call, from the
# project's folder
tool() {
  wanted "$1" || return 0
  TOOL="$2" INPUT="$3" CWD="$proj" perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({tool_name => $ENV{TOOL}, tool_input => JSON::PP->new->decode($ENV{INPUT}), cwd => $ENV{CWD}, hook_event_name => "PreToolUse", session_id => "s1", effort => {level => "xhigh"}})' >"$work/in.json"
  run_guard "$proj"
  want "$1" "$4"
}
jpath() { perl -MJSON::PP -e 'print JSON::PP->new->encode({file_path => $ARGV[0]})' "$1"; }
jstr() { perl -MJSON::PP -e 'print JSON::PP->new->allow_nonref->encode($ARGV[0])' "$1"; }

# --- the edit tools: each protected path, by its resolved path ---
for p in "$proj/.claude/settings.json" "$proj/.claude/settings.local.json" "$proj/.claude/hooks/method/guard.sh" "$proj/.claude/hooks/method/new.sh" \
  "$proj/.claude/agents/method/reviewer.md" "$proj/.claude/rules/method/x.md" "$proj/.claude/method-local/git-shapes.txt" "$proj/scripts/method/status.sh" \
  "$proj/.git/config" "$proj/.git/hooks/pre-commit" "$proj/.git/method-mutate-journal" "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json" \
  "$HOME/.claude/agents/x.md" "$HOME/.claude/skills/x/SKILL.md" "$HOME/.claude/commands/x.md" "$HOME/.gitconfig" "$HOME/.config/git/config" \
  /etc/gitconfig /etc/claude-code/managed-settings.json; do
  tool "Write to ${p#"$work"/} is refused" Write "$(jpath "$p")" G6
done
tool "Edit by a relative path, from the project's folder" Edit '{"file_path":".claude/settings.json","old_string":"a","new_string":"b"}' G6
tool "Edit by a path with .. in it" Edit "$(jpath "$proj/sub/../.claude/settings.json")" G6
tool "Edit by a path with // and ./ in it" Edit "$(jpath "$proj//.claude/./settings.json")" G6
ln -s "$proj/.claude" "$proj/link-to-claude"
tool "Edit through a link into a protected folder" Edit "$(jpath "$proj/link-to-claude/hooks/method/guard.sh")" G6
ln -s "$proj/.claude/settings.json" "$proj/settings-link.json"
tool "Edit of a link to a protected file" Edit "$(jpath "$proj/settings-link.json")" G6
tool "MultiEdit of a protected file" MultiEdit "$(jpath "$proj/scripts/method/status.sh")" G6
tool "NotebookEdit in a protected folder" NotebookEdit "$(perl -MJSON::PP -e 'print JSON::PP->new->encode({notebook_path => $ARGV[0]})' "$proj/.claude/method-local/n.ipynb")" G6
tool "Edit of a skill outside the method's folders passes" Edit "$(jpath "$proj/.claude/skills/verify/SKILL.md")" allow
tool "Edit of the app passes" Edit "$(jpath "$proj/src/app.py")" allow
tool "Write of a new file beside the settings passes" Write "$(jpath "$proj/.claude/notes.md")" allow
tool "Edit of a file named like a setting elsewhere passes" Edit "$(jpath "$proj/src/.claude/settings.json")" allow

# --- MCP file tools ---
tool "an MCP write tool given a protected path is refused" mcp__fs__write_file "$(perl -MJSON::PP -e 'print JSON::PP->new->encode({path => $ARGV[0], content => "x"})' "$proj/.claude/settings.json")" G6
tool "an MCP move given a protected path in a list is refused" mcp__fs__move_file "$(perl -MJSON::PP -e 'print JSON::PP->new->encode({paths => ["a", $ARGV[0]]})' "$proj/.git/config")" G6
tool "an MCP read tool given a protected path passes" mcp__fs__read_file "$(perl -MJSON::PP -e 'print JSON::PP->new->encode({path => $ARGV[0]})' "$proj/.claude/settings.json")" allow
tool "an MCP write tool given another path passes G6 (and G4 refuses it: it is not on the MCP list)" mcp__fs__write_file "$(perl -MJSON::PP -e 'print JSON::PP->new->encode({path => $ARGV[0], content => "x"})' "$proj/src/app.py")" G4

# --- Bash: a call that names a protected path may only read ---
for c in 'cat .claude/settings.json' 'head -5 scripts/method/status.sh' 'grep -rn guard .claude/hooks/method' 'ls -la .claude/hooks/method' \
  'sed -n 1,20p scripts/method/status.sh' 'wc -l .claude/settings.json > count.txt' 'jq . .claude/settings.json' 'diff .claude/settings.json ~/.claude/settings.json' \
  'find .claude -name "*.sh"' 'sha256sum .claude/hooks/method/guard.sh | cut -c1-8' 'test -f .git/config && echo yes' 'cat ~/.gitconfig' \
  'bash scripts/method/status.sh' 'bash scripts/method/status.sh --quick' 'git diff .claude/settings.json' 'git log --oneline -- scripts/method' \
  'echo .claude/settings.json' 'stat .git/hooks' 'cd .claude/hooks/method && ls'; do
  judge "reading passes: $c" "$proj" "$c" allow
done
judge "a read from another folder by its full path passes" "$work" "cd $proj && sed -n 1,20p scripts/method/status.sh" allow
for c in 'echo x > .claude/settings.json' 'echo x >> .claude/hooks/method/guard.sh' 'sed -i s/a/b/ .claude/settings.json' 'sed -i.bak s/a/b/ .claude/settings.json' \
  'cp notes.txt .claude/hooks/method/guard.sh' 'tee .git/config < notes.txt' 'rm .claude/settings.json' 'rm -rf .claude/hooks/method' \
  'mv .claude/settings.json old.json' 'touch scripts/method/new.sh' 'dd if=notes.txt of=.claude/settings.json' 'ln -sf notes.txt .claude/settings.json' \
  'chmod +x .claude/hooks/method/guard.sh' 'truncate -s 0 .git/config' 'git mv .claude/settings.json old.json' 'git rm .claude/settings.json' \
  'sort -o .claude/settings.json notes.txt' 'sed -n "w .claude/settings.json" notes.txt' 'find .claude -delete' 'find .claude -name x -exec rm {} \;' \
  'cat .claude/settings.json | python3 x.py' 'cd .claude/hooks/method && rm guard.sh' 'echo x > ~/.gitconfig' 'cp notes.txt ~/.claude/settings.json' \
  'cp notes.txt ~/.claude/settings.backup.json' 'echo x > .git/method-mutate-journal' 'F=.claude/settings.json; rm "$F"' \
  'bash -c "echo x > .claude/settings.json"' 'nohup cp notes.txt .claude/settings.json' 'echo .claude/settings.json | xargs rm' \
  'cp notes.txt sub/../.claude/settings.json' 'cp notes.txt link-to-claude/settings.json' 'echo x > settings-link.json' \
  'bash .claude/hooks/method/guard.sh' 'tar -C .claude -xf x.tar' 'unzip x.zip -d .claude/hooks/method' 'uniq notes.txt .claude/settings.json'; do
  judge "a write is refused: $c" "$proj" "$c" G6
done
judge "a write by its full path from another folder is refused" "$work" "echo x > $proj/.claude/settings.json" G6
judge "a write after a cd into the project from elsewhere is refused" "$work" "cd $proj && rm -f .claude/settings.json" G6
judge "a write after a cd within the project is judged from the folder it moved to" "$proj" 'cd sub && rm -f ../.claude/settings.json' G6
judge "a write with backslashes in the path is refused" "$proj" 'cp notes.txt .claude\\hooks\\method\\guard.sh' G6
judge "a write by a folder held in a variable is judged in the project" "$work" 'cd "$D" && rm -f .claude/settings.json' G6
judge "perl -e that writes the guard is refused" "$proj" 'perl -e '"'"'open F, ">", ".claude/hooks/method/guard.sh"'"'"'' G0
judge "python3 -c that writes the settings is refused" "$proj" 'python3 -c "open('"'"'.claude/settings.json'"'"', '"'"'w'"'"')"' G0
judge "code piped into python that names the settings is refused" "$proj" "printf 'open(\".claude/settings.json\", \"w\")' | python3" G0

# --- Bash: what a copy writes, and recursive writes ---
mkdir -p "$proj/x" && printf '{}\n' >"$proj/x/settings.json"
for c in 'cp x/settings.json .claude/' 'cp -r x/. .claude/' 'cp -r x/. .' 'cp -a x/. .' 'rsync -a x/ .' 'rsync -a x/ .claude' 'tar -xf x.tar' 'tar xzf x.tgz' \
  'unzip x.zip' 'patch -p1 < x.diff' 'rm -rf .claude' 'rm -r scripts' 'mv .claude claude-old' 'mv scripts old-scripts' 'find . -name "*.pyc" -delete' \
  'git rm -r --cached .claude' 'cp -r x .claude/hooks/method' 'mv x .claude/method-local' 'install -m 644 notes.txt .claude/settings.json'; do
  judge "a write that lands on a protected path is refused: $c" "$proj" "$c" G6
done
for c in 'cp notes.txt .' 'cp notes.txt sub/' 'cp -r src build/' 'cp -r x/. build' 'rsync -a src/ build/' 'tar -xf x.tar -C build' 'unzip x.zip -d build' \
  'rm -rf build' 'find build -name "*.pyc" -delete' 'mv notes.txt old-notes.txt' 'mv x .claude' 'echo hi > notes.txt' 'cp src/app.py .claude/skills/' \
  'npm test' 'python3 x.py > out.txt' 'make' 'git add -A' 'git commit -qm x' 'cp notes.txt .claude/hooks/' 'tar -czf out.tgz .claude'; do
  judge "an ordinary write passes: $c" "$proj" "$c" allow
done

# --- git: a protected file left at a version other than HEAD's or main's ---
judge "a cherry-pick of a commit that changes the guard is refused" "$proj" "git cherry-pick -x $evil" G6
judge "switching to a branch whose guard differs is refused" "$proj" 'git switch evil' G6
judge "checking out a branch whose guard differs is refused" "$proj" 'git checkout evil' G6
judge "a new branch from a commit whose guard differs is refused" "$proj" "git switch -c from-evil $evil" G6
judge "a cherry-pick of a commit that changes only the app passes" "$proj" "git cherry-pick -x $appc" allow
judge "switching to a branch that changes only the app passes" "$proj" 'git switch app' allow
(cd "$proj" && git switch -q main && printf 'main guard\n' >.claude/hooks/method/guard.sh && git commit -qam main-guard && git push -q origin main && git switch -q task && git fetch -q origin) || fail "setup: a guard change on main"
judge "merging the remote's main, which changed the guard, passes" "$proj" 'git merge --no-edit --ff-only origin/main' allow
judge "switching to main, whose guard is the remote main's, passes" "$proj" 'git switch main' allow

# --- the method's skills (step 6.3, S10): G6 as for .claude/agents/method/
# (protect.pl's @METHOD_SKILLS; method-start exists, method-plan and
# method-design do not yet); a project's own skill stays editable ---
(cd "$proj" && git switch -q task) || fail "setup: back to the task branch for the skill cases"
for p in "$proj/.claude/skills/method-start/SKILL.md" "$proj/.claude/skills/method-plan/SKILL.md" "$proj/.claude/skills/method-design/notes.md"; do
  tool "a method skill (6.3): Write to ${p#"$work"/} is refused" Write "$(jpath "$p")" G6
done
tool "a method skill (6.3): an Edit of method-start's SKILL.md is refused" Edit "$(jpath "$proj/.claude/skills/method-start/SKILL.md")" G6
tool "a method skill (7.5): an Edit of method-setup's SKILL.md is refused" Edit "$(jpath "$proj/.claude/skills/method-setup/SKILL.md")" G6
judge "a method skill (7.5): a write to method-setup's SKILL.md is refused" "$proj" 'echo x > .claude/skills/method-setup/SKILL.md' G6
for c in 'sed -i s/a/b/ .claude/skills/method-start/SKILL.md' 'echo x > .claude/skills/method-start/SKILL.md' 'echo x >> .claude/skills/method-plan/SKILL.md' \
  'cp notes.txt .claude/skills/method-start/SKILL.md' 'rm -rf .claude/skills/method-start' 'rm -rf .claude/skills' 'mv .claude/skills/method-start old-skill' \
  'cp -r x .claude/skills/method-design'; do
  judge "a method skill (6.3): a write is refused: $c" "$proj" "$c" G6
done
judge "a method skill (6.3): perl -e that writes method-start's SKILL.md is refused" "$proj" 'perl -e '"'"'open F, ">", ".claude/skills/method-start/SKILL.md"'"'"'' G0
for c in 'cat .claude/skills/method-start/SKILL.md' 'sed -n 1,5p .claude/skills/method-start/SKILL.md' 'grep -rn method .claude/skills' \
  'ls .claude/skills/method-start' "cp .claude/skills/method-start/SKILL.md $work/skill-copy.md"; do
  judge "a method skill (6.3): a read passes: $c" "$proj" "$c" allow
done
tool "a project skill (6.3): an Edit of deploy's SKILL.md passes" Edit "$(jpath "$proj/.claude/skills/deploy/SKILL.md")" allow
tool "a project skill (7.2): an Edit of a skill whose name starts like method but without its dash passes" Edit "$(jpath "$proj/.claude/skills/methodical/SKILL.md")" allow
for c in 'sed -i s/a/b/ .claude/skills/deploy/SKILL.md' 'echo x > .claude/skills/deploy/SKILL.md' 'cp notes.txt .claude/skills/deploy/notes.md' \
  'mkdir -p .claude/skills/release && echo x > .claude/skills/release/SKILL.md' 'echo x > .claude/skills/methodical/SKILL.md'; do
  judge "a project skill (6.3): a write passes: $c" "$proj" "$c" allow
done
# (step 7.2, step7.md S12: G6 keeps every .claude/skills/method-* entry, so
# a new method- skill folder cannot be made in a session, not only the
# listed ones; a SKILL.md naming itself method-NAME is RISKS #24's limit)
tool "a method skill (7.2): Write to projü/.claude/skills/method-quick/SKILL.md is refused" Write "$(jpath "$proj/.claude/skills/method-quick/SKILL.md")" G6
tool "a method skill (7.2): an Edit of a skill whose name starts with method- is refused" Edit "$(jpath "$proj/.claude/skills/method-start-old/SKILL.md")" G6
for c in 'mkdir -p .claude/skills/method-quick && echo x > .claude/skills/method-quick/SKILL.md' 'echo x > .claude/skills/method-starter/SKILL.md' \
  'cp -r .claude/skills/deploy .claude/skills/method-deploy'; do
  judge "a method skill (7.2): a write is refused: $c" "$proj" "$c" G6
done
judge "a method skill (6.3): switching to a branch whose method-start SKILL.md differs is refused" "$proj" 'git switch skillv' G6
judge "a method skill (6.3): a cherry-pick of a commit that changes method-start is refused" "$proj" "git cherry-pick -x $skillc" G6
judge "a project skill (6.3): switching to a branch that changes only deploy's skill passes" "$proj" 'git switch deployv' allow
judge "a method skill (7.2): switching to a branch that adds a method- skill is refused" "$proj" 'git switch quickv' G6
if wanted "a method skill (6.3): an interpreter's code naming"; then
  printf '%s\n' "open('.claude/skills/method-start/SKILL.md', 'w')" "open(\".claude/skills/method-plan/x\", \"w\")" "p = '.claude/skills/method-design'" \
    "open('.claude/skills/deploy/SKILL.md', 'w')" "open('.claude/skills/method-starter/SKILL.md', 'w')" "open('.claude/skills/methodical/SKILL.md', 'w')" >"$work/skill-forms.txt"
  out=$(cd "$proj" && perl -e 'require $ARGV[0]; my $re = Protect::text_re(Protect::set($ARGV[1])); open my $h, "<", $ARGV[2] or die; while (my $t = <$h>) { chomp $t; print $t =~ $re ? "y" : "n" }' "$lib/protect.pl" "$proj" "$work/skill-forms.txt")
  if [ "$out" = "yyynyn" ]; then pass "a method skill (6.3): an interpreter's code naming .claude/skills/method-start, method-plan, method-design or (7.2) any method- name is found, a project skill's is not"; else fail "a method skill (6.3): an interpreter's code naming a method skill is found" "$out (wanted yyynyn)"; fi
fi

# --- the method's /method-finish skill (step 6b.4) and the folders Claude
# Code loads mods and plugins from (~/.claude/dev-mods/, ~/.claude/
# plugins/; also under CLAUDE_CONFIG_DIR): G6 as for ~/.claude/agents/ ---
s="mods and plugins (6b.4):"
tool "a method skill (6b.4): an Edit of method-finish's SKILL.md is refused" Edit "$(jpath "$proj/.claude/skills/method-finish/SKILL.md")" G6
judge "a method skill (6b.4): a write is refused: sed -i s/a/b/ .claude/skills/method-finish/SKILL.md" "$proj" 'sed -i s/a/b/ .claude/skills/method-finish/SKILL.md' G6
tool "$s Write to home/.claude/dev-mods/s1/m/index.ts is refused" Write "$(jpath "$HOME/.claude/dev-mods/s1/m/index.ts")" G6
tool "$s Write to home/.claude/plugins/x is refused" Write "$(jpath "$HOME/.claude/plugins/x")" G6
for c in 'echo x > ~/.claude/dev-mods/x' 'cp m.ts ~/.claude/plugins/x'; do
  judge "$s a write is refused: $c" "$proj" "$c" G6
done
mkdir -p "$work/cfg"
CLAUDE_CONFIG_DIR="$work/cfg" tool "$s Write to a mod under CLAUDE_CONFIG_DIR is refused" Write "$(jpath "$work/cfg/dev-mods/s1/m/index.ts")" G6
CLAUDE_CONFIG_DIR="$work/cfg" tool "$s Write to a plugin under CLAUDE_CONFIG_DIR is refused" Write "$(jpath "$work/cfg/plugins/x")" G6
for c in 'ls ~/.claude/plugins' 'cat ~/.claude/dev-mods/x'; do
  judge "$s a read passes: $c" "$proj" "$c" allow
done
tool "$s Write to a folder whose name only starts like dev-mods passes" Write "$(jpath "$HOME/.claude/dev-mods-old/x")" allow

# --- path forms and letter case, read by the resolver itself ---
out=$(cd "$proj" && perl -e 'require $ARGV[0]; print Protect::resolve(q{C:\Users\a\.claude\settings.json}, "/x"), "\n", Protect::resolve("a/../b//c/./d", "/base"), "\n"' "$lib/protect.pl")
if [ "$out" = "/c/Users/a/.claude/settings.json
/base/b/c/d" ]; then pass "a drive-letter path with backslashes reads as /c/...; .., // and . read as the file system reads them"; else fail "path forms" "$out"; fi
out=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" perl -e 'require $ARGV[0]; my $s = Protect::set($ARGV[1]); $Protect::FOLD = 1; my $e = Protect::protected(Protect::resolve(".CLAUDE/Settings.JSON", $ARGV[1]), $s); print $e ? "folded" : "missed", "\n"; $Protect::FOLD = 0; $e = Protect::protected(Protect::resolve(".CLAUDE/Settings.JSON", $ARGV[1]), $s); print $e ? "folded" : "kept apart", "\n"' "$lib/protect.pl" "$proj")
if [ "$out" = "folded
kept apart" ]; then pass "another letter case is the same path where the file system folds case, and not where it does not"; else fail "letter case" "$out"; fi
(cd "$proj" && git config core.hooksPath githooks)
tool "Write into the folder core.hooksPath names is refused" Write "$(jpath "$proj/githooks/pre-commit")" G6
(cd "$proj" && git config --unset core.hooksPath)
tool "Write to git's per-worktree settings is refused" Write "$(jpath "$proj/.git/config.worktree")" G6
printf '[user]\n' >"$work/extra.gitconfig"
(cd "$proj" && git config include.path "$work/extra.gitconfig")
tool "Write to a settings file git reads through include.path is refused" Write "$(jpath "$work/extra.gitconfig")" G6
(cd "$proj" && git config --unset include.path)
GIT_CONFIG_GLOBAL="$work/global.cfg" tool "Write to the file GIT_CONFIG_GLOBAL names is refused" Write "$(jpath "$work/global.cfg")" G6
mkdir -p "$work/home2"
HOME="$work/home2" tool "Write to ~/.gitconfig before it exists is refused" Write "$(jpath "$work/home2/.gitconfig")" G6
(cd "$proj" && git worktree add -q -b wt-a "$work/wt-a" 2>/dev/null) || fail "setup: a second worktree"
tool "Write to the settings of the project's other worktree is refused" Write "$(jpath "$work/wt-a/.claude/settings.json")" G6
tool "Write to the method's files in a worktree's own git folder is refused" Write "$(jpath "$proj/.git/worktrees/wt-a/method-lock")" G6

# --- review round 1 of 5.7 (repair loop 1; A66: the forms a careless
# agent could plausibly write) ---
# a redirect with >&, and paths that start with $HOME, $PWD or
# $CLAUDE_PROJECT_DIR
for c in 'echo x >& .claude/settings.json' 'echo "{}" > "$HOME/.claude/settings.json"' 'cp x/settings.json ${HOME}/.claude/settings.json' \
  'echo x > $PWD/.claude/settings.json' 'cp notes.txt "$CLAUDE_PROJECT_DIR/.claude/settings.json"' \
  'rm -rf .clau*' 'rm -rf scr*' 'cp x/settings.json .claude/sett*.json' 'cp --target-directory .claude x/settings.json' \
  'cp -t.claude x/settings.json' 'cp -rt . x/.' 'cp -rT x .claude' \
  'echo x > .git/refs/remotes/origin/main' 'cp notes.txt .git/packed-refs'; do
  judge "a write is refused (5.7 repair loop 1): $c" "$proj" "$c" G6
done
for c in 'echo hi >&2' 'echo hi 2>&1 > out.txt' 'cp notes.txt $PWD/build/' 'rm -rf buil*' 'cp -tbuild notes.txt' 'cp -rT src build' \
  'tar -xf x.tar -Cbuild' 'unzip x.zip -dbuild' 'cat .git/packed-refs' 'ls .git/refs/remotes/origin'; do
  judge "an ordinary write or read passes (5.7 repair loop 1): $c" "$proj" "$c" allow
done
judge "tar -C with the folder attached is read (from a subfolder)" "$proj/sub" 'tar -xf x.tar -C../.claude' G6
judge "unzip -d with the folder attached is read (from a subfolder)" "$proj/sub" 'unzip x.zip -d../.claude' G6
judge "find's own options before its path do not hide the path" "$proj/sub" 'find -L .. -name x -delete' G6
judge "git -C: the paths git rm is given are read from that folder" "$proj" 'git -C .claude rm -r -q --cached hooks' G6
if ! (git init -q "$work/other" && cd "$work/other" && printf 'o\n' >o.txt && git add o.txt && git commit -qm o); then fail "setup: another repository"; fi
judge "git log --output into a protected file, from another repository, is refused" "$work/other" "git log -1 --output=$proj/.claude/settings.json" G6
judge "git log --output elsewhere passes" "$work/other" "git log -1 --output=$work/log.txt" allow
judge "a switch run from a subfolder is judged over the whole tree" "$proj/sub" 'git switch evil' G6
judge "a cherry-pick with -- before the commit is still judged" "$proj" "git cherry-pick -x -- $evil" G6
tool "Write to git's packed refs is refused" Write "$(jpath "$proj/.git/packed-refs")" G6
# a settings file, or a skill, that is a link: its real path is protected
mkdir -p "$work/dot/myskill" && printf '{}\n' >"$work/dot/claude-local.json" && printf 'skill\n' >"$work/dot/myskill/SKILL.md"
if ! (ln -s "$work/dot/claude-local.json" "$HOME/.claude/settings.local.json" && mkdir -p "$HOME/.claude/skills" && ln -s "$work/dot/myskill" "$HOME/.claude/skills/myskill"); then fail "setup: linked settings"; fi
tool "Write to the real file a linked settings file points at is refused" Write "$(jpath "$work/dot/claude-local.json")" G6
tool "Write into the real folder a linked skill points at is refused" Write "$(jpath "$work/dot/myskill/SKILL.md")" G6
tool "Write to another file in that folder passes" Write "$(jpath "$work/dot/notes.md")" allow
rm -f "$HOME/.claude/settings.local.json" "$HOME/.claude/skills/myskill"
# sed and sort as they read their options; reads that were refused
for c in "sed -n '1~2w .claude/settings.json' notes.txt" "sed '\$!w .claude/settings.json' notes.txt" 'sed --in-pl s/a/b/ .claude/settings.json' 'python3 -m json.tool notes.txt .claude/settings.json' \
  'sed -ne "s/a/b/w .claude/settings.json" notes.txt' 'sort --out=.claude/settings.json notes.txt' 'cp -l .claude/settings.json linked.json' \
  'cp -s .claude/settings.json linked.json' 'patch -o .claude/settings.json notes.txt < x.diff' 'find .claude -name x -exec sed -i s/a/b/ {} +'; do
  judge "a write is refused (5.7 repair loop 1, round 1's second part): $c" "$proj" "$c" G6
done
for c in 'sed -n -e 1,5p .claude/settings.json' "sed -n '/a/,/b/p' .claude/settings.json" "sed ':a;N;\$!ba;s/x/y/g' .claude/settings.json" \
  "sed -i 's,old,.claude/settings.json,' notes.txt" 'find . -name "*.sh" -exec grep -l guard {} +' 'find .claude -name "*.json" -exec wc -l {} ;' \
  'find .claude/hooks/method -name "*.sh" | xargs grep -n guard' 'python3 -m json.tool .claude/settings.json' "cp .claude/settings.json $work/copy.json" \
  "cp -r .claude/hooks/method $work/hooks-copy" 'git add .claude/settings.json' 'patch notes.txt < x.diff'; do
  judge "a read, or a write elsewhere, passes (5.7 repair loop 1, round 1's second part): $c" "$proj" "$c" allow
done
judge "from a subfolder, a .git folder there is not the project's" "$proj/sub" 'rm -rf .git' allow
judge "pushd with no folder leaves the folder unknown" "$proj" 'pushd && rm -f scripts/method/status.sh' G6
if ! (mkdir -p "$work/elsewhere/deep" && ln -s "$work/elsewhere/deep" "$proj/lnk"); then fail "setup: a link out of the project"; fi
judge "cd reads .. as written, before the link (as bash does)" "$proj" 'cd lnk/.. && rm -f .claude/settings.json' G6
rm -f "$proj/lnk"
tool "NotebookEdit is judged by both its path fields" NotebookEdit "{\"file_path\":$(jstr "$proj/notes.ipynb"),\"notebook_path\":$(jstr "$proj/.claude/settings.json"),\"new_source\":\"x\"}" G6
tool "an MCP tool given a file:// address of a protected path is refused" mcp__fs__write_file "{\"path\":$(jstr "file://$proj/.claude/settings.json"),\"content\":\"x\"}" G6
# --- the final review of step 5 ---
# after a cd that may have failed, a write is judged from both folders
for c in "cd .claude/hooks/method; echo 'exit 0' > guard.sh" 'cd .claude || exit 1; echo "{}" > settings.local.json' \
  'pushd .claude; echo x > settings.local.json' 'cd ~/.claude; echo "{}" > settings.json' 'if cd .claude; then echo x > settings.local.json; fi' \
  'cd .claude/hooks; rm -rf method' 'cd .git/hooks; cp ../../notes.txt pre-commit'; do
  judge "a write after a cd that may have failed is judged from the cd's folder too: $c" "$proj" "$c" G6
done
judge "a write after a cd on its own line is judged from the cd's folder too" "$proj" 'cd .git/hooks
cat > pre-commit <<EOF
exit 0
EOF' G6
for c in 'cd build; echo x > out.txt' 'cd sub; rm -rf ../build' 'cd src || exit 1; echo x > app.log'; do
  judge "an ordinary write after a cd passes: $c" "$proj" "$c" allow
done
# a for loop's header names the paths its loop writes
for c in 'for d in .claude/hooks/method scripts/method; do rm -rf "$d"; done' 'for f in scripts/method/*.sh; do sed -i "s/a/b/" "$f"; done' \
  'for f in .claude/settings.json; do echo x > "$f"; done'; do
  judge "a loop over protected paths that writes is refused: $c" "$proj" "$c" G6
done
for c in 'for f in src/*.py; do sed -i "s/a/b/" "$f"; done' 'for f in .claude/settings.json scripts/method/status.sh; do cat "$f"; done'; do
  judge "a loop that writes elsewhere, or only reads, passes: $c" "$proj" "$c" allow
done
# xargs writing on what a recursive listing found
for c in "grep -rl master . | xargs sed -i 's/master/main/g'" "git grep -l master | xargs sed -i 's/x/y/'" "find . -name '*.log' | xargs rm" \
  "rg -l old | xargs sed -i 's/old/new/'"; do
  judge "a bulk edit by xargs from the project's top is refused, as find -exec is: $c" "$proj" "$c" G6
done
for c in "grep -rl master src | xargs sed -i 's/x/y/'" "grep -rl x . | xargs grep -n y" "find build -name '*.log' | xargs rm"; do
  judge "a bulk edit in a subfolder, or a bulk read, passes: $c" "$proj" "$c" allow
done
# git pull --ff-only is checked against the branch's upstream
(cd "$proj" && git push -q origin evil && git fetch -q origin && git switch -q -c track task && git branch -q -u origin/evil) || fail "setup: a branch that tracks the evil one"
judge "a pull whose upstream changed the guard is refused" "$proj" 'git pull --ff-only' G6
(cd "$proj" && git switch -q task && git branch -q -D track) || fail "setup: back to the task branch"
# the text forms an interpreter's code is searched for: each line of
# forms.txt is "y TEXT" (TEXT is found), "n TEXT" (it is not) or "d TEXT"
# (found: a folder's name with dots or spaces after it, which Windows
# drops, so agents./ opens agents/ there; step 6b's review, R18)
cat >"$work/forms.txt" <<'TEXT'
y open(os.path.expanduser('~/.claude/skills/x/SKILL.md'), 'w')
y open(f"{HOME}/.claude/agents/a.md", "w")
y open('.git/method-lock', 'w')
y open('.git/packed-refs', 'w')
y open('.git/refs/remotes/origin/main', 'w')
n open('notes.txt', 'w')
y open(os.path.expanduser('~/.claude/dev-mods/s1/m/index.ts'), 'w')
y open(f"{HOME}/.claude/plugins/x", "w")
n open(os.path.expanduser('~/.claude/dev-mods-old/x'), 'w')
n open(f"{HOME}/.claude/plugins-cache.txt", "w")
n open('~/.claude/skills.bak/x', 'w')
y p = '~/.claude/plugins'
d open(os.path.expanduser('~/.claude/agents./x.md'), 'w')
d open('~/.claude/skills. /x/SKILL.md', 'w')
d open(f"{HOME}/.claude/commands../c.md", "w")
n open('~/.claude/skills.d/x', 'w')
TEXT
# shellcheck disable=SC2016 # perl code, expanded by perl
if ! forms=$(cd "$proj" && perl -e 'require $ARGV[0]; my $re = Protect::text_re(Protect::set($ARGV[1])); open my $h, "<", $ARGV[2] or die; while (my $l = <$h>) { chomp $l; my ($k, $t) = $l =~ /\A(\S) (.*)\z/ or die "bad line: $l\n"; my $got = $t =~ $re ? "y" : "n"; print "$k $got $t\n" }' "$lib/protect.pl" "$proj" "$work/forms.txt" 2>&1); then forms="the reader stopped: $forms"; fi
# form_group KIND WANT NAME: the lines of KIND (y, n or d) each gave WANT,
# and there is one at least
form_group() {
  fg_bad=$(printf '%s\n' "$forms" | awk -v k="$1" -v w="$2" '$1 == k && $2 != w')
  if [ "${forms#the reader stopped}" = "$forms" ] && [ -z "$fg_bad" ] && printf '%s\n' "$forms" | awk -v k="$1" '$1 == k { n++ } END { exit !n }'; then pass "$3"; else fail "$3" "${fg_bad:-$forms}"; fi
}
form_group y y "the text forms: an interpreter's code naming ~/.claude/skills, agents, .git/method-*, packed-refs, refs/remotes, dev-mods or plugins is found"
form_group n n "the text forms: a folder whose name only starts like one (dev-mods-old, plugins-cache.txt, skills.bak, skills.d) is not found"
form_group d y "the text forms: a folder's name with dots or spaces after it (agents./, skills. /, commands../), which Windows drops, is found"

# --- G12: one warning per session below xhigh ---
if wanted G12; then
  effort() {
    SID="$1" LEVEL="$2" AGENT="$3" CWD="$proj" perl -MJSON::PP -e 'my %h = (tool_name => "Bash", tool_input => {command => "ls"}, cwd => $ENV{CWD}, hook_event_name => "PreToolUse", session_id => $ENV{SID}); $h{effort} = {level => $ENV{LEVEL}} if $ENV{LEVEL} ne ""; $h{agent_id} = $ENV{AGENT} if $ENV{AGENT} ne ""; print JSON::PP->new->canonical->encode(\%h)' >"$work/in.json"
    run_guard "$proj"
  }
  effort e1 high ''
  first=$(cat "$work/out.txt")
  effort e1 high ''
  second=$(cat "$work/out.txt")
  case "$first" in
    '{"systemMessage":"guard G12: this session runs at effort high, below the method'"'"'s xhigh'*) if [ "$code" -eq 0 ] && [ -z "$second" ]; then pass "G12: the first call below xhigh gets one warning (exit 0), the next call none"; else fail "G12: one warning per session" "second: $second"; fi ;;
    *) fail "G12: the first call below xhigh gets a warning" "exit $code: $first $err" ;;
  esac
  effort e2 low ''
  case "$(cat "$work/out.txt")" in *"effort low"*) pass "G12: another session below xhigh gets its own warning" ;; *) fail "G12: another session gets its own warning" "$(cat "$work/out.txt")" ;; esac
  effort e3 xhigh ''
  if [ ! -s "$work/out.txt" ] && [ "$code" -eq 0 ]; then pass "G12: xhigh gets no warning"; else fail "G12: xhigh gets no warning" "$(cat "$work/out.txt")"; fi
  effort e4 max ''
  if [ ! -s "$work/out.txt" ]; then pass "G12: max gets no warning"; else fail "G12: max gets no warning" "$(cat "$work/out.txt")"; fi
  effort e5 low agent-1
  if [ ! -s "$work/out.txt" ]; then pass "G12: a call inside a subagent gets no warning"; else fail "G12: a call inside a subagent gets no warning" "$(cat "$work/out.txt")"; fi
  effort e6 '' ''
  if [ ! -s "$work/out.txt" ]; then pass "G12: a call with no effort field gets no warning"; else fail "G12: no effort field" "$(cat "$work/out.txt")"; fi
  effort e7 'low"x' ''
  case "$(cat "$work/out.txt")" in *"not one the method knows"*) pass "G12: an effort word the method does not know is not shown" ;; *) fail "G12: an unknown effort word" "$(cat "$work/out.txt")" ;; esac
  # (sessions run side by side are each warned once: the note keeps the last
  # 20; 5.7 repair loop 1)
  effort e1 high ''
  if [ ! -s "$work/out.txt" ]; then pass "G12: a session warned before another one is not warned again"; else fail "G12: a session warned before another one is not warned again" "$(cat "$work/out.txt")"; fi
  if [ "$(wc -l <"$proj/.method/local/effort-warned")" -eq 3 ]; then pass "G12: its note has one line per warned session"; else fail "G12: its note has one line per warned session" "$(cat "$proj/.method/local/effort-warned")"; fi
  for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do effort "f$n" high ''; done
  if [ "$(wc -l <"$proj/.method/local/effort-warned")" -eq 20 ]; then pass "G12: its note keeps the last 20 sessions"; else fail "G12: its note keeps the last 20 sessions" "$(wc -l <"$proj/.method/local/effort-warned") lines"; fi
  # (step 7.3) the threshold is the profile's effort: the lock's profile
  # line and its row in profiles.tsv; xhigh with no lock (above) or an
  # unknown profile
  cp "$root/method/scripts/method/profiles.tsv" "$proj/scripts/method/profiles.tsv"
  g12_lock() { printf 'version\tv0.7.0\nsource\t%040d\nprofile\t%s\nsettings\t%064d\n' 0 "$1" 0 >"$proj/scripts/method/method.lock"; }
  g12_lock balanced
  effort p1 medium ''
  if [ ! -s "$work/out.txt" ] && [ "$code" -eq 0 ]; then pass "G12: silent at Balanced's own effort (medium)"; else fail "G12: silent at Balanced's own effort (medium)" "$(cat "$work/out.txt")"; fi
  effort p2 low ''
  case "$(cat "$work/out.txt")" in *"effort low, below the medium that the project's profile (balanced) sets"*"switch with /effort medium"*) pass "G12: below Balanced's effort, a warning naming the profile's effort" ;; *) fail "G12: below Balanced's effort, a warning naming the profile's effort" "$(cat "$work/out.txt")" ;; esac
  g12_lock budget
  effort p3 medium ''
  if [ ! -s "$work/out.txt" ]; then pass "G12: silent at Budget's own effort (medium)"; else fail "G12: silent at Budget's own effort (medium)" "$(cat "$work/out.txt")"; fi
  effort p4 low ''
  case "$(cat "$work/out.txt")" in *"below the medium that the project's profile (budget) sets"*) pass "G12: below Budget's effort, a warning" ;; *) fail "G12: below Budget's effort, a warning" "$(cat "$work/out.txt")" ;; esac
  g12_lock best
  effort p5 high ''
  case "$(cat "$work/out.txt")" in *"below the xhigh that the project's profile (best) sets"*) pass "G12: below Best results' effort (xhigh), a warning" ;; *) fail "G12: below Best results' effort (xhigh), a warning" "$(cat "$work/out.txt")" ;; esac
  g12_lock turbo
  effort p6 high ''
  case "$(cat "$work/out.txt")" in *"below the method's xhigh"*) pass "G12: a profile the release does not know is held to xhigh" ;; *) fail "G12: a profile the release does not know is held to xhigh" "$(cat "$work/out.txt")" ;; esac
  rm -f "$proj/scripts/method/method.lock" "$proj/scripts/method/profiles.tsv"

fi
# --- speed ---
if wanted "a call that writes"; then
  CMD='cp -r src build/ && npm test' CWD="$proj" perl -MJSON::PP -e 'print JSON::PP->new->encode({tool_name => "Bash", tool_input => {command => $ENV{CMD}}, cwd => $ENV{CWD}})' >"$work/in.json"
  : >"$work/times.txt"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    s=$(perl -MTime::HiRes=time -e 'printf "%.0f", time * 1000')
    (cd "$proj" && CLAUDE_PROJECT_DIR="$proj" bash "$guard" <"$work/in.json" >/dev/null 2>&1)
    e=$(perl -MTime::HiRes=time -e 'printf "%.0f", time * 1000')
    echo $((e - s)) >>"$work/times.txt"
  done
  times=$(sort -n "$work/times.txt" | sed -n 5p)
  if [ "$times" -lt 400 ]; then pass "a call that writes takes ${times} ms (median of 10), under 400"; else fail "a call that writes is quick" "median ${times} ms"; fi
fi

drop_sandbox "$work" || true
echo "tests: guard (protected files): $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
