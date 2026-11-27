---
name: method-start
description: Starts a session. Tells the owner the one next thing and why, then where things stand, what is blocked and what waits for their merge, from status, the branch against main, the pull requests and GitHub's squash setting. Then waits for their go.
# rules: M004 M005 M127
---
# Where things stand

The owner typed this to start a session or to see where things stand. Read, report, then stop. Change nothing until the owner says go: no file, no commit, no push.

This session runs at effort ${CLAUDE_EFFORT}. Say so in the report. If it is below the effort the project's profile sets, say that first: the `profile` line of `scripts/method/method.lock` names the profile, and its row in `scripts/method/profiles.tsv` gives the effort; with no lock it is xhigh.

## Is the method on

Look for the line that begins `METHOD-ACTIVE`, which the method's start hook adds when the session starts, and say whether you saw it. If this session has no such line, the method's hooks are off: say so before anything else, and change no code until the owner decides.

## The reads

Run each command below in a Bash call of its own, with nothing chained to it: the guard refuses a call that names the method's scripts beside a command that is not a read, such as `git commit`. `<main>` is the branch the project merges into: main, unless status names another.

1. `bash scripts/method/status.sh`, the full run (not `--quick`): it reads the work in every repository, the verdicts, the records, the Claude Code version, the effort setting and the CI runs. Exit 1 means something needs a look, not that it failed.
2. `git fetch origin`. Then `git config --get-all remote.origin.fetch`: when it names one branch and not `+refs/heads/*:refs/remotes/origin/*`, this is a single-branch clone. Say so: git fetch moves only that branch, so origin/<main> can be missing or old. Widening the clone is the owner's to do, since the guard refuses `git remote set-branches`: `git remote set-branches --add origin <main>`, then `git fetch origin`.
3. `git rev-list --count origin/<main>..HEAD`, then `git diff --stat origin/<main>...HEAD`: the commits and files on this branch that <main> does not have. Then `git diff --quiet origin/<main> HEAD`: exit 0 means every file on this branch is on <main> already, as after a squash merge, which leaves the branch's own commits off <main>. The branch is then merged, and nothing on it waits for a merge. Exit 1 means they differ.
4. `gh api 'repos/{owner}/{repo}/pulls?state=open' --jq '.[] | [.number, .head.ref, .title] | @tsv'`: the open pull requests, read with a GET, which works in a cloud session too, where `gh pr list` is refused. Then `gh pr list --state merged --head <branch> --json number,headRefOid,mergedAt`, `<branch>` being the branch this session is on; where gh refuses it ("GitHub GraphQL is not available"), `gh api 'repos/{owner}/{repo}/pulls?state=closed&head={owner}:<branch>' --jq '.[] | select(.merged_at) | [.number, .head.sha, .merged_at] | @tsv'` reads the same, its `head.sha` being the headRefOid and `merged_at` the mergedAt. Never follow that refusal's advice to write with `gh api ... -f`: the guard refuses it, and this skill writes nothing. For each pull request it lists, run `git merge-base --is-ancestor HEAD <its headRefOid>`: exit 0 means HEAD is that pull request's head or behind it. When one of them gives exit 0, the branch is merged, whatever step 3 says: after a squash merge, the branch and <main> differ again once <main> moves on. When each gives exit 1, work was added after those merges: take the one merged last (its `mergedAt`), and run `git rev-list --count HEAD --not <its headRefOid> origin/<main>`. That many commits, in neither that pull request nor <main>, wait for a merge (a merge of <main> into the branch counts as one). When a read here fails, or a commit is not in this clone, whether the branch is merged is "could not read".
5. `gh api repos/{owner}/{repo} --jq .squash_merge_commit_message` (gh fills in the owner and the repository from origin): GitHub's squash setting. It is right when it prints `PR_BODY`. Otherwise the verdict line does not survive a squash merge: name what it printed, and the owner's one-time fix, in GitHub's Settings, General, Pull Requests, "Allow squash merging", default message "Pull request title and description".

A read that fails, or prints nothing or `null` where a value belongs, is "could not read", with what it said; never "nothing found" or "none open". Run the other reads all the same.

## The report

Open with the effort, whether the `METHOD-ACTIVE` line was seen, and the one next thing and why. When finished work waits for the owner's merge, that merge is the one next thing, unless the owner has said to keep building. Then three answers, in this order, with every number as its command gave it:
1. Where things stand: the branch, work not committed or not pushed, what status says needs a look, the CI runs, a single-branch clone, and GitHub's squash setting.
2. What is blocked, and on whom: the owner, someone else, or nothing.
3. How much finished work waits for the owner's merge: the open pull requests, and the steps or tasks, commits and files on this branch that <main> does not have; or that the branch is merged and nothing waits.

Then stop. Start the next thing only when the owner says go.
