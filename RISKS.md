# RISKS

Each risk says what could go wrong, what reduces it, and what is left.

1. Opus reviews Opus's work, so both can share a blind spot. Reduced by expected results from outside the model, mutation testing, a non-AI security scanner, Deep review on high-risk paths and a human expert before high-risk go-lives. Left: nothing closes it fully.

2. Guards that match shell commands can be bypassed by a model that is set on it. Reduced by checks that run outside the agent (CI, hashes of locked files, receipts bound to the exact version). Left: CI checks that receipts are consistent, not that they are authentic.

3. A Claude Code update renames a setting or changes behaviour. To be reduced by a minimum version check, the hook test harness (step 5) and a compatibility check in every `/research-update` and before every release; none of these exists yet. Left: breakage between checks.

4. The repo is private. Without a paid GitHub plan, GitHub does not enforce branch protection, so the merge button works even when checks are red. To be reduced by the guard hook refusing merges by Claude (step 5) and by the owner's release stop. Until step 5, nothing in the repo stops a merge; only Claude Code's permission prompts and the owner do.

5. Some research was read only through search summaries, because the cloud environment blocks many sites. The main conclusions rest on sources read in full; details may move. Reduced by `/research-update`.

6. On the Pro plan, usage limits can stop work mid-task. Reduced by checkpoints that save state to files, and a rule that a limit never justifies skipping a check.

7. The method itself grows until checking costs more than the work (the owner's 20-line rename incident). Reduced by tiers, context budgets enforced by tests, and pruning rules that no longer earn their place.

8. CI minutes on a private repo run out. This happened during Release 1 step 1: the account had used its included Actions minutes, so GitHub started no machine for any run. Reduced by running Windows and macOS only before releases and on demand, because their minutes cost more than Linux minutes. Left: no CI until the minutes renew on 1 November.

9. While the Actions minutes are used up (risk 8), CI proves nothing: every run ends in about 3 seconds with no machine and no logs. The same checks pass locally on Linux, but nothing has run on macOS or Windows yet; for now only Linux must pass (DECISIONS A27).

10. The secret scan reads the current files, not git history (a by-hand scan of the whole history during step 1 was clean), so a secret added and removed within one push is not seen. A history scan is planned for Release 2.

11. The review packet trusts its caller and runs from the change itself. It also trusts the session it runs in: PATH, git and perl. The caller picks `--base` and `--since`, so commits could be left out of a review; review-packet.sh, its helpers and verdicts.txt run from the checked-out change, so a change to them packages itself. An uncommitted edit to them, hidden from git by an index flag, does the same, because the edited builder could also skip its own check. Lockfile changes are listed by line count only, so the security check sees a swapped package source only if it opens the file. Reduced by the merge base, the "in doubt" fallback and the tests. Closed when receipts record the base and the last reviewed version (steps 4 and 5), the review machinery runs from the main branch in CI (M118, Release 2), and the security checker's dependency duty is written (M030, step 6).
