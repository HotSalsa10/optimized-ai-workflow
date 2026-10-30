#!/usr/bin/env bash
# Tests for method/scripts/method/status.sh (rules M001, M003, M077). Each
# test builds a small project with a local bare remote in a throwaway
# folder and reads the report.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: status"
root=$(repo_root)
status="$root/method/scripts/method/status.sh"
work=$(new_sandbox_dir) || abort_sandbox
repos=""
saved_home=$HOME
mkdir -p "$work/home"
# a clean home and no system settings, so the owner's git settings play no part
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1

# new_project: prints the path of a folder holding remote.git (bare) and w,
# a project on main with the nine records, one commit with a verdict,
# pushed, and origin/HEAD set
new_project() {
  b=$(new_sandbox_dir) || return 1
  repos="$repos $b"
  (
    cd "$b" || exit 1
    git init -q --bare remote.git
    git --git-dir=remote.git symbolic-ref HEAD refs/heads/main
    git init -q w
    cd w || exit 1
    git symbolic-ref HEAD refs/heads/main
    git config user.name "Test"
    git config user.email "test@example.invalid"
    git config commit.gpgsign false
    git config core.autocrlf false
    for f in AGENTS.md SPEC.md TASKS.md DECISIONS.md ROADMAP.md RISKS.md CHANGELOG.md TESTS.md; do printf '# %s\n' "$f" >"$f"; done
    printf '@AGENTS.md\n' >CLAUDE.md
    printf 'hello\n' >a.txt
    git add -A
    git commit -q -m "Add the records" -m "Review-Verdict: approve"
    git remote add origin ../remote.git
    git push -q -u origin main 2>/dev/null
    git remote set-head origin main
  ) || return 1
  printf '%s\n' "$b"
}

# cm DIR MESSAGE: an empty commit in DIR whose message is MESSAGE (printf format)
cm() {
  # shellcheck disable=SC2059 # the message is a printf format on purpose
  printf "$2" >"$work/msg"
  (cd "$1" && git commit -q --allow-empty --cleanup=verbatim -F "$work/msg")
}

# st DIR [VAR=VALUE...]: runs status in DIR outside Claude Code, with the
# variables set. Sets out, code and last.
st() {
  d=$1
  shift
  (cd "$d" && unset CLAUDE_CODE_EXECPATH CLAUDE_CODE_EFFORT_LEVEL CLAUDE_CODE_REMOTE GH_REPO && env "$@" bash "$status") >"$work/out" 2>&1
  code=$?
  out=$(cat "$work/out")
}

# expect NAME CODE STRING...: the last report exited CODE and holds every STRING
expect() {
  name=$1
  want=$2
  shift 2
  missing=""
  for s in "$@"; do
    case "$out" in
      *"$s"*) ;;
      *) missing="$missing [$s]" ;;
    esac
  done
  if [ "$code" -ne "$want" ]; then
    fail "$name: exit $code, wanted $want" "$out"
  elif [ -n "$missing" ]; then
    fail "$name: missing$missing" "$out"
  else
    pass "$name"
  fi
}

# 1. a clean project
p=$(new_project) || abort_sandbox
w="$p/w"
st "$w"
head7=$(cd "$w" && git rev-parse --short=7 HEAD)
expect "a clean, pushed project needs no look (exit 0)" 0 "status: w on main at $head7" \
  "work: PASS - nothing uncommitted, nothing unpushed (as of the last fetch)" \
  "verdicts: PASS - 1 commits on refs/remotes/origin/main since $head7 carry a Review-Verdict line" \
  "records: PASS - 9 records present; CLAUDE.md imports AGENTS.md; checks/*.tsv lists no checks" \
  "claude-code: SKIPPED - not run inside Claude Code" "effort: SKIPPED - not run inside Claude Code" "perl: PASS - JSON::PP " \
  "ci: SKIPPED - origin is not on github.com" "status: nothing needs a look; 3 SKIPPED (claude-code, effort, ci)"
if [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 9 ]; then pass "the report is one line per area plus a first and a last line"; else fail "the report is one line per area" "$out"; fi
out=$(cd "$w" && bash "$status" extra 2>&1)
code=$?
expect "any argument is bad usage" 2 "status: usage: status.sh (it takes no arguments)"
mkdir -p "$work/plain"
(cd "$work/plain" && GIT_CEILING_DIRECTORIES=$work bash "$status") >"$work/out" 2>&1
code=$?
out=$(cat "$work/out")
expect "outside a git working tree it exits 2" 2 "status: not inside a git working tree"

# 2. work
echo more >>"$w/a.txt"
st "$w"
expect "a changed file is a LOOK (exit 1)" 1 "work: LOOK - 1 uncommitted entries" "status: 1 areas need a look (work)"
(cd "$w" && git add a.txt)
st "$w"
expect "a staged change is a LOOK" 1 "work: LOOK - 1 uncommitted entries"
(cd "$w" && git reset -q --hard)
(cd "$w" && git config status.showUntrackedFiles no)
mkdir -p "$w/newdir"
: >"$w/newdir/one"
: >"$w/newdir/two"
st "$w"
expect "a new folder is seen even when git status is set to hide untracked files, and counts once" 1 "work: LOOK - 1 uncommitted entries"
rm -rf "$w/newdir"
(cd "$w" && git config --unset status.showUntrackedFiles)
printf '#!/bin/sh\n: >"%s/fsmonitor-ran"\nexit 1\n' "$work" >"$work/fsmonitor"
chmod +x "$work/fsmonitor"
(cd "$w" && git config core.fsmonitor "$work/fsmonitor")
echo edit >>"$w/a.txt"
st "$w"
if [ "$code" -eq 1 ] && [ ! -e "$work/fsmonitor-ran" ] && printf '%s\n' "$out" | grep -q '^work: LOOK - 1 uncommitted'; then
  pass "a file-system monitor set in the repository never runs, and the edit is seen"
else
  fail "a file-system monitor set in the repository never runs, and the edit is seen" "$out"
fi
(cd "$w" && git config --unset core.fsmonitor && git checkout -q a.txt)
printf '#!/bin/sh\n: >"%s/filter-ran"\nprintf "hello\\n"\n' "$work" >"$work/filter"
chmod +x "$work/filter"
(cd "$w" && git config filter.hide.clean "$work/filter" && printf 'a.txt filter=hide\n' >.git/info/attributes)
printf 'HELLO\n' >"$w/a.txt"
st "$w"
if [ "$code" -eq 1 ] && [ ! -e "$work/filter-ran" ] && printf '%s\n' "$out" | grep -q '^work: LOOK - 1 uncommitted'; then
  pass "a filter program set in the repository never runs, and the same-size edit it would hide is seen"
else
  fail "a filter program set in the repository never runs, and the same-size edit it would hide is seen" "$out"
fi
(cd "$w" && git config filter.hide.required true)
st "$w"
expect "a filter marked required is turned off too, and the edit is still seen" 1 "work: LOOK - 1 uncommitted"
st "$w" GIT_CONFIG=/dev/null
expect "GIT_CONFIG from the caller cannot hide the repository's filters from the switch-off" 1 "work: LOOK - 1 uncommitted"
(cd "$w" && git config --unset filter.hide.clean && git config --unset filter.hide.required)
(cd "$w" && git config 'filter..clean' "$work/filter" && printf 'a.txt filter=\n' >.git/info/attributes)
st "$w"
if [ "$code" -eq 1 ] && [ ! -e "$work/filter-ran" ] && printf '%s\n' "$out" | grep -q '^work: LOOK - 1 uncommitted'; then
  pass "a filter with an empty name never runs either"
else
  fail "a filter with an empty name never runs either" "$out"
fi
(cd "$w" && git config --unset 'filter..clean' && rm -f .git/info/attributes && git checkout -q a.txt)
# an edit of the same size with its old time stamp put back, under settings
# that tell git to trust size and time alone
(cd "$w" && touch -t 202001010000 a.txt && git update-index -q --refresh && cp -p a.txt "$work/stamp")
# git compares change times to the second, so the edit must come a second later
sleep 1
(cd "$w" && git config core.trustctime false && git config core.checkStat minimal)
printf 'HELLO\n' >"$w/a.txt"
touch -r "$work/stamp" "$w/a.txt"
st "$w"
expect "an edit hidden from git's stat check by core.trustctime and core.checkStat is seen" 1 "work: LOOK - 1 uncommitted"
(cd "$w" && git config --unset core.trustctime && git config --unset core.checkStat && git checkout -q a.txt)
printf 'garbage' >"$work/index.keep"
cp "$w/.git/index" "$work/index.keep"
printf 'garbage' >"$w/.git/index"
st "$w"
expect "an area that fails is a LOOK naming the git command, and the next areas still report" 1 \
  "work: LOOK - could not be checked: git status failed" "verdicts: PASS" "perl: PASS"
cp "$work/index.keep" "$w/.git/index"
(cd "$w" && git update-index --assume-unchanged a.txt)
echo hidden >>"$w/a.txt"
st "$w"
expect "a file marked assume-unchanged is a LOOK" 1 "1 files are marked so git does not compare them"
(cd "$w" && git update-index --no-assume-unchanged a.txt && git checkout -q a.txt && git update-index --skip-worktree a.txt)
st "$w"
expect "a file marked skip-worktree that is on disk is a LOOK" 1 "1 files are marked so git does not compare them"
(cd "$w" && git update-index --no-skip-worktree a.txt)
(cd "$w" && git update-index --skip-worktree a.txt)
rm "$w/a.txt"
st "$w"
expect "a tracked file deleted and hidden by skip-worktree (or left out by a sparse checkout) is a LOOK" 1 \
  "work: LOOK - 1 tracked files are not on disk and are marked skip-worktree, so git does not show them as deleted"
(cd "$w" && git update-index --no-skip-worktree a.txt && git checkout -q a.txt)
st "$w" GIT_INDEX_FILE="$work/no-index"
expect "GIT_INDEX_FILE from the caller does not change what status reads" 0 "work: PASS"
mkdir -p "$work/plib/Digest"
printf 'die "a module from PERL5LIB was loaded\\n";\n1;\n' >"$work/plib/Digest/SHA.pm"
st "$w" PERL5LIB="$work/plib"
expect "modules on the caller's PERL5LIB are not loaded" 0 "perl: PASS"
echo stashed >>"$w/a.txt"
(cd "$w" && git stash -q)
st "$w"
expect "a stash is a LOOK" 1 "work: LOOK - 1 stashes (git stash list)"
(cd "$w" && git stash drop -q)

# a project with two branches that change the same line, for merges in progress
c=$(new_project) || abort_sandbox
cw="$c/w"
(
  cd "$cw" || exit 1
  git checkout -q -b other
  echo theirs >a.txt
  git commit -q -am "Theirs" -m "Review-Verdict: approve"
  git checkout -q main
  echo ours >a.txt
  git commit -q -am "Ours" -m "Review-Verdict: approve"
  git push -q origin main other 2>/dev/null
) || fail "could not build the conflict project"
(cd "$cw" && git merge -q other >/dev/null 2>&1)
st "$cw"
expect "a merge in progress is a LOOK" 1 "a merge is in progress"
(cd "$cw" && git merge --abort && git checkout -q other && git rebase -q main >/dev/null 2>&1)
st "$cw"
expect "a rebase in progress is a LOOK" 1 "a rebase is in progress"
(cd "$cw" && git rebase --abort && git checkout -q main && git cherry-pick other >/dev/null 2>&1)
st "$cw"
expect "a cherry-pick in progress is a LOOK" 1 "a cherry-pick is in progress"
(cd "$cw" && git cherry-pick --abort && git revert --no-edit HEAD >/dev/null 2>&1 && git bisect start >/dev/null 2>&1)
st "$cw"
expect "a bisect in progress is a LOOK" 1 "a bisect is in progress" "1 commits not pushed (on main)"
(cd "$cw" && git bisect reset -q >/dev/null 2>&1 && git reset -q --hard origin/main)

(cd "$w" && git checkout -q -b feature && cm "$w" 'Feature work\n' && git checkout -q main)
st "$w"
expect "a commit on a branch never pushed is a LOOK naming the branch" 1 "work: LOOK - 1 commits not pushed (on feature), as of the last fetch"
st "$w" GIT_NAMESPACE=other
expect "GIT_NAMESPACE from the caller does not hide branches" 1 "work: LOOK - 1 commits not pushed (on feature)"
echo dirty >>"$cw/a.txt"
st "$w" GIT_DIR="$cw/.git" GIT_WORK_TREE="$cw"
expect "GIT_DIR and GIT_WORK_TREE from the caller do not point status elsewhere" 1 "work: LOOK - 1 commits not pushed (on feature)"
case "$out" in *"uncommitted"*) fail "status read the other repository's changes" "$out" ;; esac
(cd "$cw" && git checkout -q a.txt)
for b in b1 b2 b3; do (cd "$w" && git checkout -q -b "$b" main && cm "$w" "$b\n" && git checkout -q main); done
st "$w"
expect "more than 3 branches are cut to 3 names and a count" 1 "4 commits not pushed (on b1, b2, b3 and 1 more)"
(cd "$w" && git branch -q -D b1 b2 b3)
(cd "$w" && git push -q -u origin feature 2>/dev/null)
st "$w"
expect "once pushed it is not" 0 "work: PASS"
(cd "$w" && git checkout -q feature && cm "$w" 'More\n' && git checkout -q main && git push -q origin --delete feature 2>/dev/null && git fetch -q --prune)
st "$w"
expect "a branch whose remote branch is gone is named so" 1 "(on feature (its remote branch is gone))"
(cd "$w" && git branch -q -D feature && git checkout -q --detach && cm "$w" 'Detached work\n')
st "$w"
expect "commits on a detached HEAD are a LOOK" 1 "1 commits not pushed (on a detached HEAD in "
(cd "$w" && git checkout -q main)
(cd "$w" && git worktree add -q "$p/linked" -b linked origin/main 2>/dev/null)
echo dirty >>"$p/linked/a.txt"
st "$w"
expect "a change in a linked worktree is a LOOK naming it" 1 "worktree $p/linked: 1 uncommitted entries" "linked worktrees: $p/linked"
(cd "$p/linked" && git checkout -q a.txt)
st "$w"
expect "a clean linked worktree is named in a PASS" 0 "work: PASS - nothing uncommitted, nothing unpushed (as of the last fetch); linked worktrees: $p/linked"
(cd "$w" && git worktree remove --force "$p/linked" && git branch -q -D linked)
(cd "$w" && git worktree add -q "$p/gone" -b gone origin/main 2>/dev/null)
rm -rf "$p/gone"
st "$w"
expect "a linked worktree whose folder is gone is a LOOK" 1 "worktree $p/gone: its folder is gone (git worktree prune removes the entry)"
(cd "$w" && git worktree prune && git branch -q -D gone)
(cd "$w" && git remote remove origin)
st "$w"
expect "commits with no remote at all are a LOOK" 1 "work: LOOK - no remote: nothing is backed up (1 commits)"
(cd "$w" && git remote add origin ../remote.git && git fetch -q origin && git branch -q -u origin/main main && git remote set-head origin main)
sub=$(new_project) || abort_sandbox
(
  cd "$w" || exit 1
  git -c protocol.file.allow=always submodule -q add -b main "$sub/remote.git" lib 2>/dev/null
  git config submodule.lib.ignore all
  git commit -q -m "Add lib" -m "Review-Verdict: approve"
  git push -q origin main 2>/dev/null
  cd lib && git config user.name Test && git config user.email test@example.invalid && git commit -q --allow-empty -m moved
) || fail "could not build the submodule project"
st "$w"
expect "a submodule change is seen even when the submodule is set to be ignored" 1 "work: LOOK - 1 uncommitted entries"

# 3. verdicts
v=$(new_project) || abort_sandbox
vw="$v/w"
cm "$vw" 'Good one\n\nReview-Verdict: approve\n'
cm "$vw" 'No trailer here\n'
(cd "$vw" && git push -q origin main 2>/dev/null)
bad1=$(cd "$vw" && git rev-parse --short=7 HEAD)
st "$vw"
expect "a commit after the first verdict without one is a LOOK naming it and the reason" 1 \
  "verdicts: LOOK - 1 commits on refs/remotes/origin/main since " "lack a valid Review-Verdict line: $bad1; the oldest, \"No trailer here\": no line starts with Review-Verdict:" \
  "accept them by moving VERDICTS_FROM in .claude/method.conf through a reviewed change; never rewrite main"
st "$vw" PERLIO=:crlf
expect "PERLIO=:crlf from the caller adds no CR to what status reads back" 1 "\"No trailer here\": no line starts"
printf 'VERDICTS_FROM=%s\n' "$(cd "$vw" && git rev-parse HEAD)" >"$vw/.claude-method.conf.tmp"
mkdir -p "$vw/.claude"
mv "$vw/.claude-method.conf.tmp" "$vw/.claude/method.conf"
(cd "$vw" && git add .claude && git commit -q -m "Accept the old commits" -m "Review-Verdict: approve" && git push -q origin main 2>/dev/null)
st "$vw"
expect "VERDICTS_FROM moves the start" 0 "verdicts: PASS - 1 commits on refs/remotes/origin/main after $bad1 carry a Review-Verdict line"
accepted=$(cd "$vw" && git rev-parse HEAD)
for case in "only the trailer|Review-Verdict: approve\n|the message is only the Review-Verdict line" \
  "an unknown value|Subject\n\nReview-Verdict: maybe\n|unknown value" \
  "GitHub's co-author block|Subject\n\nReview-Verdict: approve\n\n---------\n\nCo-authored-by: A <a@example.invalid>\n|GitHub's ---------/Co-authored-by block"; do
  name=${case%%|*}
  rest=${case#*|}
  msg=${rest%%|*}
  reason=${rest#*|}
  (cd "$vw" && git reset -q --hard "$accepted")
  cm "$vw" "$msg"
  (cd "$vw" && git push -q -f origin main 2>/dev/null)
  st "$vw"
  expect "a commit with $name is a LOOK with the reason" 1 "verdicts: LOOK - 1 commits" "$reason"
done
(cd "$vw" && git reset -q --hard "$accepted")
cm "$vw" '\033[31mA subject that is far too long to show in full on one line of the report\n'
(cd "$vw" && git push -q -f origin main 2>/dev/null)
st "$vw"
if [ "$code" -eq 1 ] && ! printf '%s\n' "$out" | grep -q "$(printf '\033')" \
  && printf '%s\n' "$out" | grep -F -q 'the oldest, "\x1B[31mA subject that is far too long to show in full on...": '; then
  pass "a commit subject is shown escaped and cut to 60 characters, never inside an escape"
else
  fail "a commit subject is shown escaped and cut to 60 characters, never inside an escape" "$out"
fi
(cd "$vw" && git reset -q --hard "$accepted")
cm "$vw" 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\033[31mmore\n'
(cd "$vw" && git push -q -f origin main 2>/dev/null)
st "$vw"
if printf '%s\n' "$out" | grep -F -q 'the oldest, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...": '; then
  pass "a subject cut where an escape starts loses the whole escape, not half of it"
else
  fail "a subject cut where an escape starts loses the whole escape, not half of it" "$out"
fi
(cd "$vw" && git reset -q --hard "$accepted" && git push -q -f origin main 2>/dev/null)
(cd "$vw" && git checkout -q -b task && cm "$vw" 'wip\n' && git push -q origin task 2>/dev/null && git checkout -q main)
st "$vw"
expect "commits on a task branch are not judged" 0 "verdicts: PASS"
(cd "$vw" && git branch -q origin/main task && git tag main task)
st "$vw"
expect "main is found by its full name, past a branch and a tag that shadow it" 0 "status: w on main at" \
  "verdicts: PASS - 1 commits on refs/remotes/origin/main after"
(cd "$vw" && git branch -q -D origin/main && git tag -d main >/dev/null)
printf 'VERDICTS_FROM=%s\n' "$(cd "$vw" && git rev-parse task)" >"$vw/.claude/method.conf"
st "$vw"
expect "VERDICTS_FROM not on main is a LOOK" 1 "verdicts: LOOK - VERDICTS_FROM in .claude/method.conf is not on refs/remotes/origin/main's first-parent history"
printf 'VERDICTS_FROM=%s\n' "$(cd "$vw" && git rev-parse origin/main)" >"$vw/.claude/method.conf"
st "$vw"
expect "VERDICTS_FROM at main's tip leaves nothing to check: SKIPPED, not a pass" 1 \
  "verdicts: SKIPPED - no commit on refs/remotes/origin/main after $(cd "$vw" && git rev-parse --short=7 origin/main) yet"
(cd "$vw" && git checkout -q .claude/method.conf)
n=$(new_project) || abort_sandbox
nw="$n/w"
(cd "$nw" && git commit -q --amend -m "Records, no verdict" && git push -q -f origin main 2>/dev/null)
st "$nw"
expect "with no verdict anywhere the area is SKIPPED" 0 "verdicts: SKIPPED - no commit on refs/remotes/origin/main carries a Review-Verdict line yet; task-branch commits are not read"
(cd "$nw" && git remote remove origin)
st "$nw"
expect "without a remote, main is the local main branch" 1 "verdicts: SKIPPED - no commit on refs/heads/main"
(cd "$nw" && git branch -q -m main trunk)
st "$nw"
expect "with no main branch at all the area is SKIPPED" 1 "verdicts: SKIPPED - no main branch (looked for origin/HEAD"

oh=$(new_project) || abort_sandbox
ohw="$oh/w"
(cd "$ohw" && git checkout -q -b trunk && cm "$ohw" 'No verdict\n' && git push -q origin trunk 2>/dev/null && git checkout -q main && git remote set-head origin trunk)
st "$ohw"
expect "main is the branch origin/HEAD names" 1 "verdicts: LOOK - 1 commits on refs/remotes/origin/trunk"
(
  cd "$ohw" || exit 1
  git remote set-head origin main
  git checkout -q -b side
  # dated an hour later, so that without --first-parent git would list it
  # before the commit where the verdicts start
  GIT_COMMITTER_DATE="$(($(date +%s) + 3600)) +0000" git commit -q --allow-empty -m 'wip, no verdict'
  git checkout -q main
  git merge -q --no-ff side -m "Merge side" -m "Review-Verdict: approve"
  git push -q origin main 2>/dev/null
) || fail "could not build the merge project"
st "$ohw"
expect "commits that came in through a merge are not judged; the merge is" 0 "verdicts: PASS - 2 commits on refs/remotes/origin/main"
(cd "$ohw" && git branch -q task side && git symbolic-ref refs/remotes/origin/HEAD refs/heads/task)
st "$ohw"
expect "an origin/HEAD that points at a local branch is not taken for main" 0 "verdicts: PASS - 2 commits on refs/remotes/origin/main"
(cd "$ohw" && git remote set-head origin main && git branch -q -D task)
xm=$(new_project) || abort_sandbox
xw="$xm/w"
(cd "$xw" && git remote remove origin)
cm "$xw" 'No verdict\n'
(cd "$xw" && git branch -q refs/remotes/origin/main HEAD~1 2>/dev/null)
st "$xw"
expect "a branch named refs/remotes/origin/main does not stand in for main" 1 "verdicts: LOOK - 1 commits on refs/heads/main"
(cd "$xw" && git branch -q -D refs/remotes/origin/main 2>/dev/null && git tag refs/remotes/origin/main HEAD~1 2>/dev/null)
st "$xw"
expect "a tag named refs/remotes/origin/main does not stand in for main" 1 "verdicts: LOOK - 1 commits on refs/heads/main"
printf '%s\n' "$(cd "$xw" && git rev-parse HEAD)" >"$work/shallow"
st "$xw" GIT_SHALLOW_FILE="$work/shallow"
expect "GIT_SHALLOW_FILE from the caller does not cut the history status reads" 1 "verdicts: LOOK - 1 commits on refs/heads/main"
# shellcheck disable=SC2034 # a key shape, built from pieces
tok="gh""p_abcdefghijklmnopqrstuvwxyz0123456789"
(cd "$xw" && git reset -q --hard HEAD~1)
cm "$xw" "deploy with $tok\n"
st "$xw"
if [ "$code" -eq 1 ] && ! printf '%s\n' "$out" | grep -F -q -- "$tok" && printf '%s\n' "$out" | grep -F -q 'ghp_...('; then
  pass "a key in a commit subject is masked"
else
  fail "a key in a commit subject is masked" "$out"
fi
(cd "$xw" && git reset -q --hard HEAD~1)
cm "$xw" "a subject of forty characters before it: $tok\n"
st "$xw"
if ! printf '%s\n' "$out" | grep -F -q 'ghp_abcdefghij' && printf '%s\n' "$out" | grep -F -q 'before it: ghp_...(40 chars)'; then
  pass "a key that the 60-character cut would split is masked whole first"
else
  fail "a key that the 60-character cut would split is masked whole first" "$out"
fi
cwp=$(new_project) || abort_sandbox
(cd "$cwp" && git clone -q remote.git copy 2>/dev/null)
(cd "$cwp/w" && git config core.worktree "$cwp/copy")
st "$cwp/w"
expect "a core.worktree setting that points git elsewhere is a LOOK naming the folder" 1 \
  "work: LOOK - git's working folder is $cwp/copy, not this folder: a core.worktree setting points git elsewhere"
(cd "$oh" && git clone -q --depth 1 "file://$oh/remote.git" shallow 2>/dev/null)
st "$oh/shallow"
expect "a shallow clone is SKIPPED: where the verdicts start may be older than what is here" 0 \
  "verdicts: SKIPPED - 1 commits on refs/remotes/origin/main since " "but the history is shallow, so older commits were not read"
mkdir -p "$oh/shallow/.claude"
printf 'VERDICTS_FROM=%s\n' "$(cd "$ohw" && git rev-list --max-parents=0 HEAD)" >"$oh/shallow/.claude/method.conf"
st "$oh/shallow"
expect "a VERDICTS_FROM older than a shallow history is SKIPPED, not a LOOK" 1 \
  "verdicts: SKIPPED - VERDICTS_FROM in .claude/method.conf is not in this shallow history of refs/remotes/origin/main"
rm -rf "$oh/shallow/.claude"

# 4. records
r=$(new_project) || abort_sandbox
rw="$r/w"
for f in CLAUDE.md AGENTS.md SPEC.md TASKS.md DECISIONS.md ROADMAP.md RISKS.md CHANGELOG.md TESTS.md; do
  mv "$rw/$f" "$work/kept.md"
  st "$rw"
  expect "a missing $f is a LOOK" 1 "records: LOOK - missing: $f"
  mv "$work/kept.md" "$rw/$f"
done
printf '# no import\n' >"$rw/CLAUDE.md"
st "$rw"
expect "CLAUDE.md without @AGENTS.md is a LOOK" 1 "records: LOOK - CLAUDE.md has no line @AGENTS.md"
(cd "$rw" && git checkout -q CLAUDE.md)
mkdir -p "$rw/checks"
printf 'unit\tany\t-\t^([0-9]+) passed\techo "1 passed"\n' >"$rw/checks/main.tsv"
st "$rw"
# shellcheck disable=SC2016 # backticks are part of the text
expect "TESTS.md that does not name a check is a LOOK" 1 'records: LOOK - TESTS.md does not name `unit`'
# shellcheck disable=SC2016
printf '| `unit` | checks/main.tsv |\n' >>"$rw/TESTS.md"
st "$rw"
expect "TESTS.md that names every check passes" 1 "records: PASS - 9 records present; CLAUDE.md imports AGENTS.md; TESTS.md names all 1 checks"
printf 'unit any - x\n' >>"$rw/checks/main.tsv"
st "$rw"
expect "a malformed checks file is a LOOK naming the line" 1 "records: LOOK - checks/main.tsv line 2: expected 5 TAB-separated fields"
rm -rf "$rw/checks"
(cd "$rw" && git checkout -q TESTS.md)
printf 'checks/\n' >"$rw/.gitignore"
mkdir -p "$rw/checks"
printf 'x\tany\t-\t^([0-9]+) passed\techo "1 passed"\n' >"$rw/checks/x.tsv"
st "$rw"
expect "a checks file git ignores is a LOOK" 1 "checks/x.tsv is ignored by git, so a clone would not have it"
rm -rf "$rw/checks" "$rw/.gitignore"
mkdir -p "$rw/sub/deeper"
st "$rw/sub/deeper"
expect "status run from a subfolder reads the records at the top" 0 "records: PASS - 9 records present"

# 5. config
mkdir -p "$rw/.claude"
printf 'PRODUCT_PATHS=src\nNOPE=1\nREPOS ../x\n' >"$rw/.claude/method.conf"
st "$rw"
expect "config problems are a LOOK, and the other areas still report" 1 \
  "config: LOOK - .claude/method.conf line 2: unknown key NOPE" "config: LOOK - .claude/method.conf line 3: is not KEY=VALUE" \
  "work: LOOK - 1 uncommitted entries" "repos: SKIPPED - .claude/method.conf has problems" "status: 2 areas need a look (config, work)"
printf 'PRODUCT_PATHS=.\n' >"$work/elsewhere.conf"
rm -f "$rw/.claude/method.conf"
ln -s "$work/elsewhere.conf" "$rw/.claude/method.conf"
st "$rw"
expect "a method.conf that is a link is a config LOOK" 1 "config: LOOK - .claude/method.conf: .claude or the file is a link"
rm -f "$rw/.claude/method.conf"
printf 'A=1\nB=1\nC=1\nD=1\nE=1\n' >"$rw/.claude/method.conf"
st "$rw"
expect "more than 3 config problems are cut to 3 and a count" 1 "config: LOOK - and 2 more"
shown=$(printf '%s\n' "$out" | grep -c '^config: LOOK - ')
if [ "$shown" -eq 4 ]; then pass "exactly 3 config problems are shown, then the count"; else fail "exactly 3 config problems are shown, then the count: $shown lines" "$out"; fi
rm -rf "$rw/.claude"

# 6. Claude Code, effort and perl
mkdir -p "$work/cc"
for v in "2.1.290 (Claude Code)" "2.1.312 (Claude Code)" "2.1.1000 (Claude Code)" "v22.11.0"; do
  f="$work/cc/claude-$(printf '%s' "$v" | tr -cd '0-9')"
  printf '#!/bin/sh\necho "%s"\n' "$v" >"$f"
  chmod +x "$f"
done
st "$rw" CLAUDE_CODE_EXECPATH="$work/cc/claude-21290"
expect "a Claude Code below the floor is a LOOK" 1 "claude-code: LOOK - 2.1.290 is below the floor 2.1.295; update Claude Code"
st "$rw" CLAUDE_CODE_EXECPATH="$work/cc/claude-21312"
expect "a Claude Code at or above the floor passes" 0 "claude-code: PASS - 2.1.312, floor 2.1.295" "effort: PASS - CLAUDE_CODE_EFFORT_LEVEL is not set"
st "$rw" CLAUDE_CODE_EXECPATH="$work/cc/claude-211000"
expect "versions compare as numbers, not as text" 0 "claude-code: PASS - 2.1.1000, floor 2.1.295"
st "$rw" CLAUDE_CODE_EXECPATH="$work/cc/claude-22110"
expect "an output that is not a Claude Code version is SKIPPED" 0 "claude-code: SKIPPED - the version could not be read"
# shellcheck disable=SC2016 # a script for the stand-in to run
printf '#!/bin/sh\nif read -r x; then echo "read: $x"; else echo "2.1.312 (Claude Code)"; fi\n' >"$work/cc/claude-stdin"
printf '#!/bin/sh\necho "2.1.312 (Claude Code)"\nexit 1\n' >"$work/cc/claude-fails"
chmod +x "$work/cc/claude-stdin" "$work/cc/claude-fails"
printf 'hello\n' >"$work/hello"
st "$rw" CLAUDE_CODE_EXECPATH="$work/cc/claude-stdin" <"$work/hello"
expect "Claude Code is asked for its version with no input" 0 "claude-code: PASS - 2.1.312"
st "$rw" CLAUDE_CODE_EXECPATH="$work/cc/claude-fails"
expect "a version command that fails is SKIPPED" 0 "claude-code: SKIPPED - the version could not be read"
mkdir -p "$work/m"
cp -R "$root/method/scripts/method/." "$work/m/"
printf 'claude_code_min=2.1\n' >"$work/m/REQUIRES"
out=$(cd "$rw" && unset CLAUDE_CODE_EFFORT_LEVEL && CLAUDE_CODE_EXECPATH="$work/cc/claude-21312" bash "$work/m/status.sh" 2>&1)
code=$?
expect "an area that fails is a LOOK with its reason, and the next areas still report" 1 \
  "claude-code: LOOK - could not be checked: REQUIRES line 1: claude_code_min: a version like 2.1.295" "effort: PASS" "perl: PASS"
(cd "$work/cc" && cd "$rw" && unset CLAUDE_CODE_EFFORT_LEVEL && CLAUDE_CODE_EXECPATH=claude-21312 PATH="$work/cc:$PATH" bash "$status") >"$work/out" 2>&1
code=$?
out=$(cat "$work/out")
expect "a relative CLAUDE_CODE_EXECPATH is never run" 0 "claude-code: SKIPPED - CLAUDE_CODE_EXECPATH is not an absolute path"
st "$rw" CLAUDE_CODE_EXECPATH="$work/cc/claude-21312" CLAUDE_CODE_EFFORT_LEVEL=high
expect "CLAUDE_CODE_EFFORT_LEVEL set is a LOOK" 1 "effort: LOOK - CLAUDE_CODE_EFFORT_LEVEL is set; it overrides every per-role effort (DECISIONS A4)"
st "$rw" CLAUDE_CODE_EXECPATH="$work/cc/claude-21312" CLAUDE_CODE_EFFORT_LEVEL=
expect "CLAUDE_CODE_EFFORT_LEVEL set but empty is a LOOK" 1 "effort: LOOK - CLAUDE_CODE_EFFORT_LEVEL is set"
st "$rw" CLAUDE_CODE_EFFORT_LEVEL=low
expect "CLAUDE_CODE_EFFORT_LEVEL set outside Claude Code is a LOOK" 1 "effort: LOOK - CLAUDE_CODE_EFFORT_LEVEL is set"
mkdir -p "$work/badperl/lib/JSON" "$work/badperl/bin"
# shellcheck disable=SC2016 # perl code and a script for the stand-in perl
printf 'die "planted: JSON::PP cannot load\\n";\n' >"$work/badperl/lib/JSON/PP.pm"
printf '#!/bin/sh\nexec "%s" -I"%s" "$@"\n' "$(command -v perl)" "$work/badperl/lib" >"$work/badperl/bin/perl"
chmod +x "$work/badperl/bin/perl"
(cd "$rw" && unset CLAUDE_CODE_EXECPATH CLAUDE_CODE_EFFORT_LEVEL && PATH="$work/badperl/bin:$PATH" bash "$status") >"$work/out" 2>&1
code=$?
out=$(cat "$work/out")
expect "a perl that cannot load JSON::PP is a LOOK, and every other area still reports" 1 \
  "perl: LOOK - cannot load JSON::PP" "work: PASS" "verdicts: PASS" "records: PASS" "ci: SKIPPED"

# 7. ci, through a stand-in gh
g=$(new_project) || abort_sandbox
gw="$g/w"
(cd "$gw" && git config remote.origin.url https://github.com/example/project.git)
gsha=$(cd "$gw" && git rev-parse HEAD)
mkdir -p "$work/gh"
# gh_says JSON: the stand-in gh records how it was called and prints JSON
# (SHA in the JSON becomes the commit gh was asked about)
gh_says() {
  printf '%s\n' "$1" >"$work/gh/answer"
  : >"$work/gh/args"
  cat >"$work/gh/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$work/gh/args"
printf 'GH_REPO=%s GH_PROMPT_DISABLED=%s\n' "\${GH_REPO-unset}" "\${GH_PROMPT_DISABLED-unset}" >"$work/gh/env"
sha=
prev=
for a in "\$@"; do
  if [ "\$prev" = --commit ]; then sha=\$a; fi
  prev=\$a
done
sed "s/SHA/\$sha/g" "$work/gh/answer"
EOF
  chmod +x "$work/gh/gh"
}
run_ok() { printf '{"workflowName":"%s","status":"%s","conclusion":"%s","headSha":"%s"}' "$1" "$2" "$3" "${4:-SHA}"; }
gh_says "[$(run_ok build completed success),$(run_ok lint completed failure),$(run_ok lint completed success)]"
st "$gw" PATH="$work/gh:$PATH" GH_REPO=other/repo
expect "a workflow whose newest run failed is a LOOK, even after another workflow passed" 1 "ci: LOOK - lint: failure for ${gsha%"${gsha#???????}"}"
if [ "$(cat "$work/gh/args")" = "run list -R https://github.com/example/project.git --commit $gsha --limit 100 --json workflowName,status,conclusion,headSha" ] \
  && [ "$(cat "$work/gh/env")" = "GH_REPO=unset GH_PROMPT_DISABLED=1" ]; then
  pass "gh is asked about origin and this commit, with GH_REPO removed and prompts off"
else
  fail "gh is asked about origin and this commit, with GH_REPO removed" "$(cat "$work/gh/args" "$work/gh/env")"
fi
gh_says "[$(run_ok build completed success),$(run_ok lint completed skipped)]"
st "$gw" PATH="$work/gh:$PATH"
expect "passed and skipped runs pass" 0 "ci: PASS - 2 workflows passed for "
gh_says "[$(run_ok build completed cancelled)]"
st "$gw" PATH="$work/gh:$PATH"
expect "a cancelled run is a LOOK" 1 "ci: LOOK - build: cancelled"
gh_says "[$(run_ok build in_progress '')]"
st "$gw" PATH="$work/gh:$PATH"
expect "a run still going is SKIPPED" 0 "ci: SKIPPED - still running for "
gh_says "[$(run_ok build completed success 0123456789abcdef0123456789abcdef01234567)]"
st "$gw" PATH="$work/gh:$PATH"
expect "a run for another commit is SKIPPED" 0 "ci: SKIPPED - unexpected gh output"
gh_says "[]"
st "$gw" PATH="$work/gh:$PATH"
expect "no run at all is SKIPPED" 0 "ci: SKIPPED - no CI run for "
gh_says "not json"
st "$gw" PATH="$work/gh:$PATH"
expect "output that is not JSON is SKIPPED" 0 "ci: SKIPPED - unexpected gh output"
gh_says "{}"
st "$gw" PATH="$work/gh:$PATH"
expect "JSON that is not a list of runs is SKIPPED" 0 "ci: SKIPPED - unexpected gh output"
(cd "$gw" && git checkout -q -b ahead && cm "$gw" 'Ahead\n\nReview-Verdict: approve\n')
ahead7=$(cd "$gw" && git rev-parse --short=7 HEAD)
gh_says "[$(run_ok build completed success)]"
st "$gw" PATH="$work/gh:$PATH"
calls=$(wc -l <"$work/gh/args" | tr -d ' ')
if [ "$calls" -eq 2 ] && printf '%s\n' "$out" | grep -F -q "ci: PASS - 1 workflows passed for $ahead7; main: 1 workflows passed for ${gsha%"${gsha#???????}"}"; then
  pass "CI is read for HEAD and for main's tip"
else
  fail "CI is read for HEAD and for main's tip: $calls calls" "$out"
fi
(cd "$gw" && git checkout -q main && git branch -q -D ahead)
mkdir -p "$work/nogh"
for tool in bash git perl env; do ln -s "$(command -v "$tool")" "$work/nogh/$tool"; done
st "$gw" PATH="$work/nogh"
expect "without gh the area is SKIPPED" 0 "ci: SKIPPED - gh is not installed"
# a sleep length of its own, so other test runs at the same time do not count
nap="9$$"
printf '#!/bin/sh\nsleep %s\necho never\n' "$nap" >"$work/gh/gh"
start=$(date +%s)
out=$(cd "$gw" && unset CLAUDE_CODE_EXECPATH CLAUDE_CODE_EFFORT_LEVEL && PATH="$work/gh:$PATH" bash "$status" 2>&1)
code=$?
took=$(($(date +%s) - start))
if [ "$took" -lt 25 ] && printf '%s\n' "$out" | grep -q '^ci: SKIPPED - gh did not answer within 15 seconds$'; then
  pass "a gh that hangs is stopped within the time limit (${took}s)"
else
  fail "a gh that hangs is stopped within the time limit: ${took}s" "$out"
fi
if ps -A -o args= >/dev/null 2>&1; then
  # shellcheck disable=SC2009 # pgrep is not on every system the tests run on
  left=$(ps -A -o args= | grep -c "^sleep $nap\$")
  if [ "$left" -eq 0 ]; then pass "what a stopped gh started is stopped too"; else fail "what a stopped gh started is stopped too: $left left"; fi
else
  skip "what a stopped gh started is stopped too: ps cannot list command lines here"
fi
mkdir -p "$gw/relbin"
printf '#!/bin/sh\n: >"%s/relgh-ran"\n' "$work" >"$gw/relbin/gh"
chmod +x "$gw/relbin/gh"
st "$gw" PATH="relbin:$work/nogh"
if [ ! -e "$work/relgh-ran" ] && printf '%s\n' "$out" | grep -q '^ci: SKIPPED - gh is not installed$'; then
  pass "a gh in a relative PATH entry (inside the repository) is never run"
else
  fail "a gh in a relative PATH entry (inside the repository) is never run" "$out"
fi
rm -rf "$gw/relbin"

# 8. other repositories
o=$(new_project) || abort_sandbox
ow="$o/w"
other=$(new_project) || abort_sandbox
mkdir -p "$ow/.claude" "$ow/inner"
: >"$ow/inner/file"
(cd "$o" && git clone -q "$other/remote.git" site 2>/dev/null)
printf 'REPOS=../site\nREPOS=../missing\nREPOS=inner\n' >"$ow/.claude/method.conf"
(cd "$ow" && git add -A && git commit -q -m "Repos" -m "Review-Verdict: approve" && git push -q origin main 2>/dev/null)
st "$ow" CLAUDE_CODE_REMOTE=true
expect "other repositories are reported; a missing one is SKIPPED in a cloud session" 1 \
  "repo ../site: PASS - nothing uncommitted, nothing unpushed" "repo ../missing: SKIPPED - not in this session" \
  "repo inner: LOOK - not the top folder of a git working tree"
st "$ow"
expect "a missing repository elsewhere is a LOOK" 1 "repo ../missing: LOOK - not found; clone it there or remove it from REPOS"
echo dirty >>"$o/site/a.txt"
st "$ow"
expect "a change in another repository is a LOOK" 1 "repo ../site: LOOK - 1 uncommitted entries"
(cd "$o/site" && git checkout -q a.txt && git bisect start >/dev/null 2>&1)
st "$ow"
expect "work in progress in another repository is found there" 1 "repo ../site: LOOK - a bisect is in progress"
case "$out" in *"work: LOOK"*) fail "the other repository's bisect was reported for this one" "$out" ;; esac
(cd "$o/site" && git bisect reset -q >/dev/null 2>&1)
echo dirty >>"$o/site/a.txt"
mkdir -p "$ow/evil/objects" "$ow/evil/refs/heads"
printf 'ref: refs/heads/main\n' >"$ow/evil/HEAD"
mkdir -p "$ow/evil/info"
printf '[core]\n\trepositoryformatversion = 0\n\tbare = false\n\tworktree = .\n\tfsmonitor = %s\n[filter "hide"]\n\tclean = %s\n' \
  "$work/fsmonitor" "$work/filter" >"$ow/evil/config"
printf '* filter=hide\n' >"$ow/evil/info/attributes"
: >"$ow/evil/refs/heads/.keep"
: >"$ow/evil/objects/.keep"
printf 'REPOS=evil\n' >"$ow/.claude/method.conf"
(cd "$ow" && git add -A && git commit -q -m "A repository layout" -m "Review-Verdict: approve")
rm -f "$work/fsmonitor-ran"
st "$ow"
if [ "$code" -eq 1 ] && [ ! -e "$work/fsmonitor-ran" ] && [ ! -e "$work/filter-ran" ] \
  && printf '%s\n' "$out" | grep -q '^repo evil: LOOK - not the top folder of a git working tree$'; then
  pass "a committed folder laid out like a bare repository is never used as one"
else
  fail "a committed folder laid out like a bare repository is never used as one" "$out"
fi

# 9. from review round 3: a submodule, and a repository made with --separate-git-dir
sm=$(new_project) || abort_sandbox
smw="$sm/w"
lib=$(new_project) || abort_sandbox
(
  cd "$smw" || exit 1
  git -c protocol.file.allow=always submodule -q add -b main "$lib/remote.git" lib 2>/dev/null
  mkdir -p .claude
  printf 'REPOS=lib\n' >.claude/method.conf
  git add -A
  git commit -q -m "Add lib" -m "Review-Verdict: approve"
  git push -q origin main 2>/dev/null
) || fail "could not build the submodule project"
st "$smw/lib"
expect "status inside a submodule reads its work area" 0 "work: PASS - nothing uncommitted, nothing unpushed"
st "$smw"
expect "a REPOS entry that is a submodule is read" 0 "repo lib: PASS - nothing uncommitted, nothing unpushed"
echo dirty >>"$smw/lib/a.txt"
st "$smw/lib"
expect "a change inside a submodule is seen there" 1 "work: LOOK - 1 uncommitted entries"
(cd "$smw" && git worktree add -q -b side "$sm/linked" 2>/dev/null) || fail "could not add a linked worktree"
st "$sm/linked"
expect "status run in a linked worktree reads the main working tree from its own folder" 1 \
  "work: LOOK - 1 uncommitted entries (a new folder counts once); linked worktrees: $sm/linked"
(cd "$smw/lib" && git checkout -q a.txt && git update-index --skip-worktree a.txt && rm a.txt)
st "$smw"
expect "a file deleted and hidden by skip-worktree inside a submodule is a LOOK" 1 \
  "work: LOOK - 1 tracked files are not on disk and are marked skip-worktree"
(cd "$smw/lib" && git update-index --no-skip-worktree a.txt && git checkout -q a.txt && echo hidden >>a.txt && git update-index --assume-unchanged a.txt)
st "$smw"
expect "an edit hidden by assume-unchanged inside a submodule is a LOOK" 1 \
  "work: LOOK - 1 files are marked so git does not compare them (assume-unchanged or skip-worktree, also inside submodules)"
(cd "$smw/lib" && git update-index --no-assume-unchanged a.txt && git checkout -q a.txt)
(cd "$lib" && git clone -q --separate-git-dir "$lib/sep.git" remote.git sep 2>/dev/null) || fail "could not clone with --separate-git-dir"
st "$lib/sep"
expect "a clone made with --separate-git-dir is read" 0 "work: PASS - nothing uncommitted, nothing unpushed"

# 10. read-only
ro=$(new_project) || abort_sandbox
rw2="$ro/w"
(cd "$rw2" && git config core.trustctime false && git config core.fsmonitor "$work/fsmonitor" && git config core.untrackedCache true)
echo change >>"$rw2/a.txt"
: >"$rw2/untracked.txt"
touch "$rw2/AGENTS.md"
# manifest: every file under the project, .git included, with its bytes' hash and its modification time
manifest() { (cd "$rw2" && find . -type f | LC_ALL=C sort | perl -MDigest::SHA -ne 'chomp; my @s = stat; print "$_ ", Digest::SHA->new(256)->addfile($_)->hexdigest, " $s[9]\n"'); }
before=$(manifest)
rm -f "$work/fsmonitor-ran"
st "$rw2"
after=$(manifest)
if [ -n "$before" ] && [ "$before" = "$after" ] && [ ! -e "$work/fsmonitor-ran" ] && [ "$code" -eq 1 ]; then
  pass "status changes no file, .git and the index included"
else
  fail "status changes no file, .git and the index included" "$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after"))"
fi

for d in $repos; do drop_sandbox "$d"; done
export HOME="$saved_home"
unset GIT_CONFIG_NOSYSTEM
drop_sandbox "$work"
echo "tests: status: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
