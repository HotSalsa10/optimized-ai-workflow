#!/usr/bin/env bash
# Tests for the guard's git rules (step 5.6): G3, the git list
# (.claude/hooks/method/git-shapes.txt, lib/gitlist.pl) and the push rule,
# and G8, no commit over a mutate run. guard.sh runs with a hook's input in
# real repositories: a bare origin, the session's repository cloned from it
# (on a task branch), and scratch repositories elsewhere.
# shellcheck disable=SC2016 # single-quoted commands are meant literally
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}
echo "tests: guard (git)"
root=$(repo_root)
lib="$root/method/scripts/method/lib"
guard="$root/method/.claude/hooks/method/guard.sh"
work=$(new_sandbox_dir) || abort_sandbox
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
git config --global user.email test@example.invalid
git config --global user.name Test
git config --global init.defaultBranch main
git config --global commit.gpgsign false

# the session's repository, on a task branch, with origin a bare repository
git init -q --bare "$work/origin.git"
git clone -q "$work/origin.git" "$work/proj" 2>/dev/null
proj="$work/proj"
(cd "$proj" && printf 'a\n' >a.txt && git add a.txt && git commit -qm one && git push -q origin main && git switch -qc task && printf 'b\n' >b.txt && git add b.txt && git commit -qm two && git fetch -q origin) || abort_sandbox
# a scratch repository elsewhere, its origin another bare repository
git init -q --bare "$work/other.git"
git clone -q "$work/other.git" "$work/scratch" 2>/dev/null
(cd "$work/scratch" && printf 'x\n' >x.txt && git add x.txt && git commit -qm x) || abort_sandbox
# a scratch clone of the session's repository: its origin is the session's
git clone -q "$proj" "$work/clone" 2>/dev/null

# judge NAME CWD COMMAND WANT: guard.sh on a Bash call run in CWD; WANT is
# "allow" or a rule ID (the refusal must start "guard RULE:" and exit 2)
judge() {
  wanted "$1" || return 0
  name=$1
  CMD="$3" CWD="$2" perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({tool_name => "Bash", tool_input => {command => $ENV{CMD}}, cwd => $ENV{CWD}, hook_event_name => "PreToolUse"})' >"$work/in.json"
  err=$(cd "$2" && env -u CLAUDE_CODE_EXECPATH CLAUDE_PROJECT_DIR="$proj" perl -e 'alarm 60; exec @ARGV' bash "$guard" <"$work/in.json" 2>&1 >/dev/null)
  code=$?
  case "$4" in
    allow) if [ "$code" -eq 0 ] && [ -z "$err" ]; then pass "$name"; else fail "$name: wanted it let through" "exit $code: $err"; fi ;;
    *) case "$err" in
        "guard $4: "*) if [ "$code" -eq 2 ]; then pass "$name"; else fail "$name: wanted exit 2" "exit $code: $err"; fi ;;
        *) fail "$name: wanted guard $4" "exit $code: $err" ;;
      esac ;;
  esac
}

# --- shapes on the list pass in the session's repository ---
for c in 'git status' 'git status --short' 'git log --oneline -5' 'git diff --stat HEAD' 'git show --stat' 'git add -A' 'git commit -qm "a message"' \
  'git add -A && git commit -qm x' 'git -c core.quotepath=false log' 'git -c user.name=T -c user.email=t@example.invalid -c commit.gpgsign=false commit -qm x' \
  'git fetch -q --prune origin' 'git fetch' 'git merge origin/main' 'git merge --no-edit origin/main' 'git log --grep=stash' 'git checkout -qb new-one' 'git switch -c new-two' \
  'git checkout -b new-three origin/main' 'git branch' 'git branch -a' 'git branch --show-current' 'git branch new-four' 'git branch -d task' 'git tag' 'git tag -l "v*"' \
  'git restore --staged a.txt' 'git reset --soft HEAD~1' 'git reset HEAD -- a.txt' 'git rev-parse --show-toplevel' 'git config user.email' 'git config --get remote.origin.url' 'git config -l' \
  'git stash list' 'git remote -v' 'git remote get-url origin' 'git worktree list' 'git worktree add -b wt-branch ../wt' 'git cherry-pick HEAD~1' 'git revert --no-edit HEAD' \
  'git --version' 'git version' 'git commit -h' 'git push --help' 'git ls-files -z' 'git symbolic-ref --short HEAD' 'git reflog -n 5' \
  'git -C ../proj status' 'git --no-pager log -1' 'git rm --cached a.txt' 'git mv a.txt c.txt' 'git fetch origin main' 'git fetch -q origin main task' 'git archive -o x.tar HEAD' \
  'GIT_CONFIG_NOSYSTEM=1 git status'; do
  judge "on the list: $c" "$proj" "$c" allow
done
judge "a plain switch to an existing branch while no tracked file changed" "$proj" 'git switch main' allow

# --- shapes not on the list are refused in the session's repository (K3, K4) ---
for c in 'git pull' 'git rebase --exec "x" HEAD~2' 'git stash' 'git stash pop' 'git reset --hard' 'git reset --hard origin/main' 'git clean -fd' 'git checkout -- a.txt' \
  'git checkout a.txt' 'git restore a.txt' 'git branch -D task' 'git branch -f main HEAD' 'git symbolic-ref HEAD refs/heads/main' 'git update-ref refs/heads/main HEAD' \
  'git remote set-head origin task' 'git remote add x ../x' 'git config alias.x "!sh"' 'git config user.email x@example.invalid' 'git config --unset user.email' \
  'git worktree add ../wt2 main' 'git merge task' 'git fetch . task:refs/remotes/origin/main' 'git fetch origin main:refs/remotes/origin/x' 'git fetch origin +main' 'git fetch origin "refs/*"' 'git archive --remote=origin HEAD' 'git tag v1' 'git commit -n -m x' 'git commit -nm x' \
  'git commit --no-verify -m x' 'git commit --no-veri -m x' 'git diff --output=x' 'git log --outp=x' 'git grep -O vim x' 'git ls-remote --upload-pack=x origin' \
  'git -c core.hooksPath=h commit -m x' 'git -c core.fsmonitor=x status' 'git --git-dir=.git status' 'git --work-tree=. status' 'git -c alias.st=status st' \
  'git symbolic-ref -- --delete' 'git cherry-pick HEAD~2..HEAD' 'git switch -c main' 'git checkout -B task' 'git branch -m task x' 'git am x.patch' 'git notes add -m x'; do
  judge "not on the list: $c" "$proj" "$c" G3
done

# --- GIT_ variables (K3) ---
for c in 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=h git commit -m x' 'GIT_DIR=../clone/.git git status' 'env GIT_DIR=x git status' \
  'export GIT_WORK_TREE=/; git status' 'GIT_EDITOR="sh -c x" git commit' 'GIT_SSH_COMMAND=x git fetch'; do
  judge "a GIT_ setting is refused: $c" "$proj" "$c" G3
done
for c in 'GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" git commit -qm x' 'GIT_PAGER=cat git log -1' 'GIT_TERMINAL_PROMPT=0 git fetch -q' 'GIT_EDITOR=true git commit -q'; do
  judge "a harmless GIT_ setting passes: $c" "$proj" "$c" allow
done

# --- the push rule ---
for c in 'git push -u origin HEAD' 'git push origin task' 'git push -q origin HEAD:task' 'git push origin task:task-2' 'git push -qu origin HEAD' \
  'git add -A && git commit -qm x && git push -u origin HEAD' 'for i in 1 2 3; do git push -u origin HEAD && break; sleep 2; done' 'git push origin HEAD 2>&1 | tail -3'; do
  judge "a task-branch push passes: $c" "$proj" "$c" allow
done
for c in 'git push origin main' 'git push origin HEAD:main' 'git push origin task:main' 'git push origin HEAD:refs/heads/main' 'git push origin HEAD:heads/main' \
  'git push origin HEAD:master' 'git push origin HEAD:Main' 'git push -f origin HEAD' 'git push --force-with-lease origin HEAD' 'git push origin +task' 'git push origin :task' \
  'git push --mirror origin' 'git push --all origin' 'git push' 'git push origin' 'git push origin HEAD:refs/tags/v1' 'git push ../origin.git HEAD' 'git push --no-verify origin HEAD' \
  'git push origin "task*"' 'git checkout main && git push origin HEAD' 'git merge origin/main && git push origin HEAD' 'git push origin HEAD &' \
  'echo "ref: refs/heads/main" > .git/HEAD; git push origin HEAD' 'git -c remote.origin.push=refs/heads/task:refs/heads/main push origin HEAD' 'git branch -f x; git push origin HEAD'; do
  judge "push refused: $c" "$proj" "$c" G3
done
judge "push refused: a force flag after the remote and branch" "$proj" 'git push origin HEAD --force' G3
CMD='git push origin +task' CWD="$proj" perl -MJSON::PP -e 'print JSON::PP->new->encode({tool_name => "Bash", tool_input => {command => $ENV{CMD}}, cwd => $ENV{CWD}})' >"$work/in.json"
err=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" bash "$guard" <"$work/in.json" 2>&1)
case "$err" in "guard G3: a forced, deleting or pattern push is refused;"*) pass "a forced push is refused as forced, saying the allowed form" ;; *) fail "a forced push is refused as forced" "$err" ;; esac
(cd "$proj" && git switch -q main)
judge "a push of HEAD while on main is refused" "$proj" 'git push origin HEAD' G3
judge "merging the remote's main while on main is refused" "$proj" 'git merge origin/main' G3
(cd "$proj" && git switch -q task)
(cd "$proj" && git symbolic-ref refs/heads/alias refs/heads/main)
judge "a push of a branch that is a symbolic ref is refused (K3a)" "$proj" 'git push origin alias' G3
judge "a symbolic ref is refused also with its destination written out" "$proj" 'git push origin alias:task' G3
(cd "$proj" && git symbolic-ref --delete refs/heads/alias)
(cd "$proj" && git config remote.origin.push refs/heads/task:refs/heads/main)
if wanted_any "a remote.*.push setting refuses every push (it could change where it goes)" "the refusal names the setting that could redirect the push"; then
  TEST_ONLY='' judge "a remote.*.push setting refuses every push (it could change where it goes)" "$proj" 'git push origin HEAD' G3
  case "$err" in *"a remote.*.push or remote.*.mirror setting would change where this push goes"*) pass "the refusal names the setting that could redirect the push" ;; *) fail "the refusal names the setting that could redirect the push" "$err" ;; esac
fi
(cd "$proj" && git config --unset remote.origin.push)
git config --global remote.origin.mirror true
judge "a remote.*.mirror setting in the global settings refuses the push" "$proj" 'git push origin HEAD' G3
git config --global --unset remote.origin.mirror
printf '{"tool_name":"Bash","tool_input":{"command":"git push origin HEAD"},"cwd":"%s"}' "$proj" >"$work/in.json"
err=$(cd "$proj" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.push GIT_CONFIG_VALUE_0=refs/heads/task:refs/heads/main CLAUDE_PROJECT_DIR="$proj" bash "$guard" <"$work/in.json" 2>&1)
case "$err" in "guard G3: "*) pass "a remote.*.push setting in the session's environment (GIT_CONFIG_*) refuses the push" ;; *) fail "a remote.*.push setting in the session's environment refuses the push" "$err" ;; esac
printf 'm\n' >>"$proj/a.txt"
(cd "$proj" && git show-ref --verify -q refs/heads/main) || fail "the session's main branch is still there before the dirty-tree case"
judge "switching branches while a tracked file has uncommitted changes is refused" "$proj" 'git switch main' G3
judge "making a new branch with uncommitted changes passes" "$proj" 'git switch -c carry-on' allow
(cd "$proj" && git checkout -q -- a.txt)

# --- the folder a git command runs in ---
judge "elsewhere, git is not judged (a scratch repository)" "$work/scratch" 'git reset --hard && git stash && git config user.email x@example.invalid' allow
judge "cd into a scratch repository moves the judging there" "$proj" "cd $work/scratch && git reset --hard" allow
judge "git -C a scratch repository moves the judging there" "$proj" "git -C $work/scratch reset --hard" allow
judge "git -C this repository from elsewhere is judged" "$work/scratch" "git -C $proj reset --hard" G3
judge "a relative git -C into a scratch repository moves the judging there" "$proj" 'git -C ../scratch reset --hard' allow
judge "a cd inside a subshell does not move the commands after it" "$proj" "(cd $work/scratch && true); git reset --hard" G3
judge "a cd through builtin moves this same shell, so what follows is judged where it runs" "$work/scratch" "builtin cd $proj && git reset --hard" G3
judge "a cd through command or time moves this same shell too" "$work/scratch" "command cd $proj; time cd .; git reset --hard" G3
judge "git's own programs by their dashed names are refused: /usr/lib/git-core/git-push" "$proj" "/usr/lib/git-core/git-push origin main" G3
judge "git's own programs by their dashed names are refused: git-reset" "$proj" "git-reset --hard" G3
judge "a script whose name only starts with git- is not a git command" "$proj" "./git-notes.sh" allow
judge "a cd inside bash -c does not move the commands after it" "$proj" "bash -c 'cd $work/scratch'; git reset --hard" G3
judge "a cd that feeds a pipe does not move the commands after it" "$proj" "cd $work/scratch | cat; git reset --hard" G3
judge "a folder held in a variable is judged as this repository" "$work/scratch" 'cd "$D" && git reset --hard' G3
judge "a git -C folder held in a variable is judged as this repository" "$work/scratch" 'git -C "$D" reset --hard' G3
CMD='cd "$D" && git config user.email x' CWD="$work/scratch" perl -MJSON::PP -e 'print JSON::PP->new->encode({tool_name => "Bash", tool_input => {command => $ENV{CMD}}, cwd => $ENV{CWD}})' >"$work/in.json"
err=$(cd "$work/scratch" && CLAUDE_PROJECT_DIR="$proj" bash "$guard" <"$work/in.json" 2>&1)
case "$err" in *"held in a variable, so it was judged as this project's repository; if it is a scratch folder, write its path out"*) pass "a refusal for a folder held in a variable says so, and what to do" ;; *) fail "a refusal for a folder held in a variable says so" "$err" ;; esac
judge "git inside git's own folder is this repository" "$proj" 'cd .git && git update-ref refs/heads/main HEAD' G3
judge "a linked worktree of this repository is this repository" "$proj" "git worktree add -q -b wt-x $work/wt-x >/dev/null 2>&1; true" allow
(cd "$proj" && git worktree add -q -b wt-y "$work/wt-y" 2>/dev/null)
judge "in a linked worktree of this repository the list applies" "$work/wt-y" 'git reset --hard' G3
judge "git init in a scratch folder passes" "$work" 'mkdir -p fresh && cd fresh && git init -q' allow
judge "elsewhere, a push to a folder on this machine passes" "$work/scratch" 'git push -q origin main' allow
judge "elsewhere, a push into this repository is judged (a scratch clone of it)" "$work/clone" 'git push origin HEAD:main' G3
(cd "$work/scratch" && git remote add gh https://github.com/example/example.git)
judge "elsewhere, a push to a network remote is judged" "$work/scratch" 'git push gh main' G3
judge "elsewhere, a push to a network URL is judged" "$work/scratch" 'git push https://github.com/example/example.git HEAD:main' G3
judge "elsewhere, changing git's global settings is refused" "$work/scratch" 'git config --global core.hooksPath /x' G3
judge "elsewhere, reading git's global settings passes" "$work/scratch" 'git config --global --get user.name' allow
judge "elsewhere, global settings under a test HOME pass" "$work/scratch" 'HOME=/tmp/test-home git config --global user.name x' allow

# --- ExitWorktree ---
printf '{"tool_name":"ExitWorktree","tool_input":{"discard_changes":true},"cwd":"%s"}' "$proj" >"$work/in.json"
err=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" bash "$guard" <"$work/in.json" 2>&1); code=$?
case "$code:$err" in "2:guard G3: "*) pass "ExitWorktree that would discard changes is refused" ;; *) fail "ExitWorktree that would discard changes is refused" "exit $code: $err" ;; esac
printf '{"tool_name":"ExitWorktree","tool_input":{"discard_changes":false},"cwd":"%s"}' "$proj" >"$work/in.json"
err=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" bash "$guard" <"$work/in.json" 2>&1); code=$?
if [ "$code" -eq 0 ] && [ -z "$err" ]; then pass "ExitWorktree that keeps changes passes"; else fail "ExitWorktree that keeps changes passes" "exit $code: $err"; fi

# --- G8: no commit over a mutate run ---
journal=$(cd "$proj" && git rev-parse --git-path method-mutate-journal)
(cd "$proj" && printf 'x\n' >"$journal")
judge "a commit while a mutate journal is there is refused (G8)" "$proj" 'git commit -qm x' G8
judge "a cherry-pick --continue while a mutate journal is there is refused (G8)" "$proj" 'git cherry-pick --continue' G8
judge "a merge while a mutate journal is there is refused (G8)" "$proj" 'git merge --no-edit --ff-only origin/main' G8
judge "a status while a mutate journal is there passes" "$proj" 'git status' allow
(cd "$proj" && rm -f "$journal")
judge "a commit with no mutate journal passes" "$proj" 'git commit -qm x' allow

# --- the project's own list ---
mkdir -p "$proj/.claude/method-local"
printf '# the owner allows the stash here\nstash :: the owner keeps work aside this way\nstash pop :: the owner keeps work aside this way\n' >"$proj/.claude/method-local/git-shapes.txt"
judge "a shape the owner added in .claude/method-local passes" "$proj" 'git stash' allow
judge "the owner's shapes add to the list; the rest still refuses" "$proj" 'git reset --hard' G3
judge "the owner's shapes cannot allow a push to main (pushes are judged by the guard itself)" "$proj" 'git push origin HEAD:main' G3
printf 'stash with no reason\n' >"$proj/.claude/method-local/git-shapes.txt"
judge "a line in the owner's list that cannot be read refuses git here, saying where" "$proj" 'git status' G3
printf 'stash ::   \n' >"$proj/.claude/method-local/git-shapes.txt"
judge "a line in the owner's list with an empty reason is not read, so git is refused here" "$proj" 'git stash' G3
rm -rf "$proj/.claude/method-local"

# --- review round 1 of 5.6 (repair loop 1; A66: what a careless agent
# could plausibly hit) ---
# a cd that may have failed leaves the folder unknown: judged as this
# repository
judge "a push after a cd that may have failed is judged as this repository's" "$proj" "cd $work/no-such-clone; git push -q origin HEAD:main" G3
judge "a reset after a cd that may have failed is judged as this repository's" "$proj" "cd /tmp; git reset --hard HEAD~1" G3
judge "cd - leaves the folder unknown" "$proj" "cd - && git reset --hard HEAD~1" G3
judge "a cd with && is followed: work in a scratch clone passes" "$proj" "cd $work/scratch && git reset -q --hard HEAD" allow
# a remote the guard cannot read is judged in full, not taken for a folder
judge "a remote added in the same call is not taken for a folder" "$work/scratch" "git remote add gh https://github.com/owner/repo.git && git push -q gh HEAD:main" G3
judge "a push from a clone made in the same call is judged in full" "$proj" "git clone -q https://github.com/owner/repo.git $work/newclone && cd $work/newclone && git push -q origin HEAD:main" G3
judge "a push to a local folder written as a path still passes" "$work/scratch" "git push -q $work/other.git HEAD:main" allow
# git's own options before a switch do not hide it from a push
judge "git -C before a switch next to a push" "$proj" "git -C . switch main && git push -q origin HEAD:task" G3
judge "git -c before a checkout next to a push" "$proj" "git -c core.quotepath=false checkout main; git push -q origin HEAD:task" G3
judge "reading git commands next to a push pass" "$proj" "git branch --show-current && git remote -v && git push -q -u origin HEAD" allow
judge "git config --get next to a push passes" "$proj" "git config --get remote.origin.url && git push -q origin HEAD" allow
# HOME and XDG_CONFIG_HOME on git point it at other settings and hooks
judge "HOME set on a push" "$proj" "HOME=/tmp/elsewhere git push -q origin HEAD" G3
judge "XDG_CONFIG_HOME set on a commit in this repository" "$proj" "XDG_CONFIG_HOME=/tmp/elsewhere git commit -qm x" G3
# ~ in git -C is the home folder
judge "git -C with ~ is read as the home folder" "$work/scratch" "git -C ~/../proj reset -q --hard HEAD" G3
# git init, rm -f and mv -f
judge "git init with a template is refused in this repository" "$proj" "git init --template=/tmp/t" G3
judge "a plain git init passes" "$proj" "git init -q" allow
judge "git rm -f drops uncommitted changes: refused" "$proj" "git rm -f a.txt" G3
judge "git rm -rf is refused too" "$proj" "git rm -rf ." G3
judge "git rm --cached passes" "$proj" "git rm -q --cached a.txt" allow
judge "git mv -f is refused" "$proj" "git mv -f a.txt c.txt" G3
# honest work the list now lets through
judge "git pull --ff-only on a task branch passes" "$proj" "git pull --ff-only" allow
judge "a plain git pull is still refused (it can merge)" "$proj" "git pull" G3
judge "git submodule update --init --recursive passes" "$proj" "git submodule update --init --recursive" allow
judge "git fetch --unshallow passes" "$proj" "git fetch --unshallow" allow
judge "git fetch --depth passes" "$proj" "git fetch --depth=10 origin" allow
judge "git worktree add -b from the remote main passes" "$proj" "git worktree add -b wt-one ../wt-one origin/main" allow
judge "git worktree remove passes" "$proj" "git worktree remove ../wt-one" allow
judge "git worktree remove --force is refused" "$proj" "git worktree remove --force ../wt-one" G3
judge "git worktree prune passes" "$proj" "git worktree prune" allow
# a refusal names no word of the push: a remote's URL can hold a token
tok="tok$(printf '%s' 'en12345')"
host=github.com
CMD="git push https://user:${tok}@${host}/o/r.git HEAD:main" CWD="$proj" perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({tool_name => "Bash", tool_input => {command => $ENV{CMD}}, cwd => $ENV{CWD}})' >"$work/in.json"
err=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" perl -e 'alarm 60; exec @ARGV' bash "$guard" <"$work/in.json" 2>&1 >/dev/null)
case "$err" in
  "guard G3: "*"$tok"*) fail "a push refusal names no word of the push (a URL can hold a token)" "$err" ;;
  "guard G3: "*) pass "a push refusal names no word of the push (a URL can hold a token)" ;;
  *) fail "a push to a URL is refused" "$err" ;;
esac

# --- the final review of step 5 ---
# a push named through a variable, a substitution, a glob or braces: where
# it goes cannot be told
judge "a push whose branch is a variable set before it is refused" "$proj" 'B=main; git push -q origin HEAD:$B' G3
judge "a push in a for loop over branch names is refused" "$proj" 'for b in task main; do git push -q origin HEAD:$b; done' G3
judge "a push to a quoted variable is refused" "$proj" 'git push -q origin HEAD:"$BRANCH"' G3
judge "a push to a variable with a default is refused" "$proj" 'git push -q origin HEAD:${B:-main}' G3
judge "a push to branches in braces is refused" "$proj" 'git push -q origin HEAD:{task,main}' G3
judge "a push to a remote held in a variable is refused" "$proj" 'R=origin; git push -q $R HEAD' G3
judge "a plain push of HEAD still passes" "$proj" 'git push -q -u origin HEAD' allow
# refusals name no word of the command that could hold a key
CMD='git push -q origin HEAD:MAIN' CWD="$proj" perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({tool_name => "Bash", tool_input => {command => $ENV{CMD}}, cwd => $ENV{CWD}})' >"$work/in.json"
err=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" perl -e 'alarm 60; exec @ARGV' bash "$guard" <"$work/in.json" 2>&1 >/dev/null)
case "$err" in *MAIN*) fail "a push refusal does not repeat the branch as written" "$err" ;; "guard G3: pushing to main is refused"*) pass "a push refusal does not repeat the branch as written (it says main)" ;; *) fail "a push to MAIN is refused" "$err" ;; esac
tk="sec$(printf '%s' 'ret987')"
CMD="git -chttp.extraheader=Authorization:$tk fetch origin" CWD="$proj" perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({tool_name => "Bash", tool_input => {command => $ENV{CMD}}, cwd => $ENV{CWD}})' >"$work/in.json"
err=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" perl -e 'alarm 60; exec @ARGV' bash "$guard" <"$work/in.json" 2>&1 >/dev/null)
case "$err" in *"$tk"*) fail "an option's refusal names the option only, not its value" "$err" ;; "guard G3: "*) pass "an option's refusal names the option only, not its value" ;; *) fail "an attached -c is refused" "$err" ;; esac
CMD="git Tok_$tk status" CWD="$proj" perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({tool_name => "Bash", tool_input => {command => $ENV{CMD}}, cwd => $ENV{CWD}})' >"$work/in.json"
err=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" perl -e 'alarm 60; exec @ARGV' bash "$guard" <"$work/in.json" 2>&1 >/dev/null)
case "$err" in *"$tk"*) fail "an unknown subcommand is named only when it is a plain word" "$err" ;; "guard G3: "*) pass "an unknown subcommand is named only when it is a plain word" ;; *) fail "an unknown subcommand is refused" "$err" ;; esac
# the list: honest reads in, a forced submodule update and a pull of
# another branch out
judge "git branch --merged passes" "$proj" 'git branch --merged' allow
judge "git branch --no-merged passes" "$proj" 'git branch --no-merged' allow
judge "git branch --merged with a commit passes" "$proj" 'git branch --merged origin/main' allow
judge "git submodule update --force is refused (it drops a submodule's uncommitted work)" "$proj" 'git submodule update --init --force' G3
judge "a pull of another branch by name is refused (only the branch's own upstream)" "$proj" 'git pull --ff-only origin other' G3
judge "a pull from the branch's own remote passes" "$proj" 'git pull --ff-only origin' allow

# --- the method's list itself ---
got=$(perl -e 'require "$ARGV[0]/gitlist.pl"; open my $h, "<", $ARGV[1] or die; local $/; my ($s, $e) = GitList::parse(<$h>, "git-shapes.txt"); my @no = grep { $_->{reason} !~ /\S/ } @$s; print scalar(@$s), " shapes; ", scalar(@$e), " errors; ", scalar(@no), " without a reason"' "$lib" "$root/method/.claude/hooks/method/git-shapes.txt")
case "$got" in *" shapes; 0 errors; 0 without a reason") pass "the method's git list reads, every shape with its reason ($got)" ;; *) fail "the method's git list reads, every shape with its reason" "$got" ;; esac

# speed: a call with git commands in this repository
if wanted "a commit-and-push call"; then
  median=$(CLAUDE_PROJECT_DIR="$proj" CMD='git add -A && git commit -qm x && git push -u origin HEAD' CWD="$proj" perl -MJSON::PP -MTime::HiRes=time -e 'my $j = JSON::PP->new->encode({tool_name => "Bash", tool_input => {command => $ENV{CMD}}, cwd => $ENV{CWD}}); my @t; for (1 .. 10) { my $s = time; open my $p, "|-", "bash", $ARGV[0] or die; print $p $j; close $p; push @t, (time - $s) * 1000 } @t = sort { $a <=> $b } @t; printf "%d", $t[4]' "$guard" 2>/dev/null)
  if [ -n "$median" ] && [ "$median" -lt 400 ]; then pass "a commit-and-push call takes $median ms median (fails only over 400)"; else fail "a commit-and-push call is quick" "median $median ms"; fi
fi

drop_sandbox "$work" || true
echo "tests: guard (git): $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
