#!/usr/bin/env bash
# Tests for method/scripts/method/done-check.sh (rules M008, M009, M089,
# M108, M144, M146). Each test builds a small project with a local bare
# remote in a throwaway folder, runs the checks with run-checks.sh and reads
# done-check's report. Since step 6b.1 done-check reads the task's plan
# (docs/tasks/<id>/plan.md) and the gates' receipts in git's folder, so the
# projects carry a task, and receipts are written here as gate-receipt
# writes them (forge.pl below; a receipt is a local file, RISKS #2). The
# floor cases come first, each run only when wanted (TEST_ONLY,
# tests/lib.sh), so a plant runs only its own; the cases of the conditions
# before 6b (files, up to date, checks, elsewhere, verdict, verdicts start)
# follow, with approving receipts for HEAD written before each run (dca),
# and run only in a whole run.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: done-check"
root=$(repo_root)
done_check="$root/method/scripts/method/done-check.sh"
run_checks="$root/method/scripts/method/run-checks.sh"
work=$(new_sandbox_dir) || abort_sandbox
repos=""
# drop_all: drops every project made here: those in repos, and those on
# the list in $work/sandboxes (new_project, which runs in $( ))
drop_all() {
  for da_d in $repos; do drop_sandbox "$da_d"; done
  if [ -f "$work/sandboxes" ]; then
    while IFS= read -r da_d; do drop_sandbox "$da_d"; done <"$work/sandboxes"
  fi
}
saved_home=$HOME
mkdir -p "$work/home"
# a clean home and no system settings, so the owner's git settings play no part
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
git config --global user.name "Test"
git config --global user.email "test@example.invalid"
git config --global commit.gpgsign false
git config --global core.autocrlf false
git config --global init.defaultBranch main
git config --global protocol.file.allow always
git config --global advice.detachedHead false

OPEN='Review-Verdict: request-changes-open - not reviewed yet'
OK='Review-Verdict: approve'

# msg DIR ARGS...: commits in DIR with the message from printf ARGS (a
# subject, a blank line, the verdict line), allowing an empty commit
msg() {
  d=$1
  shift
  # shellcheck disable=SC2059 # the message is a printf format on purpose
  printf "$@" >"$work/msg"
  (cd "$d" && git commit -q --allow-empty --cleanup=verbatim -F "$work/msg")
}

# amend DIR LINE: the head commit's message becomes "Change" and LINE; its
# files and parents stay as they are
amend() {
  printf 'Change\n\n%s\n' "$2" >"$work/msg"
  (cd "$1" && git commit -q --amend --allow-empty --cleanup=verbatim -F "$work/msg")
}

# rc DIR [VAR=VALUE...]: runs run-checks in DIR (not in CI unless a VAR says
# so). Sets rc_out and rc_code.
rc() {
  d=$1
  shift
  rc_out=$(cd "$d" && env CI= "$@" bash "$run_checks" 2>&1)
  rc_code=$?
}

# dc DIR [VAR=VALUE...]: runs done-check --ready in DIR. Sets out and code.
dc() {
  d=$1
  shift
  out=$(cd "$d" && env CI= "$@" bash "$done_check" --ready 2>&1)
  code=$?
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

# lacks NAME STRING: the last report does not hold STRING
lacks() {
  case "$out" in
    *"$2"*) fail "$1" "$out" ;;
    *) pass "$1" ;;
  esac
}

# rc_ok NAME: the last run-checks passed (a test's setup)
rc_ok() {
  if [ "$rc_code" -eq 0 ]; then pass "$1"; else fail "$1: run-checks exit $rc_code" "$rc_out"; fi
}

# newest_log DIR: the path of DIR's newest run-checks log
newest_log() {
  (cd "$1" && for l in .method/local/logs/run-checks-*.log; do printf '%s\n' "$l"; done | LC_ALL=C sort | tail -n 1)
}

# add_task DIR [ID [TIER [APPROVED]]]: writes the task's plan in DIR
# (docs/tasks/ID/plan.md, default t1, LIGHT, approved with "approve ID"),
# not committed
add_task() {
  at_id=${2:-t1}
  mkdir -p "$1/docs/tasks/$at_id"
  printf '# Task %s\n\nTier: %s\nPaths: src\n%s\n\nThe task.\n' "$at_id" "${3:-LIGHT}" \
    "${4:-Approved: 2026-11-22 \"approve $at_id\"}" >"$1/docs/tasks/$at_id/plan.md"
}

# new_project [TIER]: prints a folder holding remote.git (bare) and w: main
# with one commit, pushed, origin/HEAD set, holding a project check (unit:
# fails while flaky.marker exists) and .claude/method.conf
# (PRODUCT_PATHS=src), files on the built-in high-risk list (M153), so a
# change on the branch leaves them be; then w on branch feat with src/a.txt
# and the approved plan of task t1 (add_task, Tier TIER, default LIGHT; with
# FULL also its expected.tsv), committed with an open verdict line. It is
# called in $( ), whose variables the end of the file never sees, so the
# folder goes on the list in $work/sandboxes, which drop_all drops
new_project() {
  np_tier=${1:-LIGHT}
  b=$(new_sandbox_dir) || return 1
  printf '%s\n' "$b" >>"$work/sandboxes"
  (
    cd "$b" || exit 1
    git init -q --bare remote.git
    git init -q w
    cd w || exit 1
    printf '*.marker\n' >.gitignore
    printf 'hello\n' >README
    mkdir -p checks .claude
    printf 'unit\tany\t-\t(\\d+) ok\ttest ! -e flaky.marker && echo 3 ok\n' >checks/project.tsv
    printf 'PRODUCT_PATHS=src\n' >.claude/method.conf
    git add -A
    git commit -q -m "Start" -m "Review-Verdict: not-required - the first commit"
    git remote add origin ../remote.git
    git push -q -u origin main 2>/dev/null
    git remote set-head origin main
    git checkout -q -b feat
    mkdir -p src
    printf 'x = 1\n' >src/a.txt
    add_task . t1 "$np_tier"
    [ "$np_tier" != FULL ] || printf 'case\tinputs\texpected\tsource\none\tx=1\t2\tthe owner\n' >docs/tasks/t1/expected.tsv
    git add -A
    git commit -q -m "Add the feature" -m "$OPEN"
  ) || return 1
  printf '%s\n' "$b"
}

# manifest DIR: every file under DIR with its SHA-256 and change time
manifest() { (cd "$1" && find . -type f | LC_ALL=C sort | perl -MDigest::SHA -ne 'chomp; my @s = stat; print "$_ ", Digest::SHA->new(256)->addfile($_)->hexdigest, " $s[9]\n"'); }

# forge.pl STORE KEY=VALUE...: one receipt in git's common folder STORE, as
# lib/receipt.pl's fresh and stop write it (v 1, gate, agent, run, prompt,
# started, stopped, head, tree, state, why, open, bases), named
# method-receipt-NAME.json (NAME: 24 hex). open=none and stopped=none are
# null; bases is a comma list (empty: none), bases=absent leaves the key
# out (a receipt made before step 6b.1); why is a comma list
cat >"$work/forge.pl" <<'FORGE'
use strict;
use warnings;
use JSON::PP;
my ($store, @kv) = @ARGV;
my %o;
for (@kv) { my ($k, $v) = /\A([a-z]+)=(.*)\z/s or die "forge: bad pair $_\n"; $o{$k} = $v }
my %r = (v => 1, gate => $o{gate}, agent => "a$o{name}", run => 1, prompt => undef, head => $o{head}, tree => $o{tree},
  state => $o{state}, why => [grep { length } split /,/, $o{why} // ''], open => $o{open} eq 'none' ? undef : $o{open},
  stopped => $o{stopped} eq 'none' ? undef : 0 + $o{stopped}, started => 0 + ($o{stopped} eq 'none' ? 1700000000 : $o{stopped} - 5),
  stops => 1, blocked => 0, denied => 0, handback => undef, bases => [grep { length } split /,/, $o{bases}]);
delete $r{bases} if $o{bases} eq 'absent';
my $name = "$store/method-receipt-$o{name}.json";
open my $f, '>', $name or die "forge: cannot write $name\n";
print $f JSON::PP->new->canonical->encode(\%r);
close $f or die;
FORGE
R=method-reviewer
S=method-security-checker
T=method-tester
D=method-diagnose
# store DIR: git's common folder of DIR
store() { (cd "$1" && cd "$(git rev-parse --git-common-dir)" && pwd -P); }
# mbase DIR: the merge base done-check uses, with main as lib/git.pl finds it
mbase() {
  # shellcheck disable=SC2016 # perl code, expanded by perl
  (cd "$1" && mt=$(perl -e 'require $ARGV[0]; my (undef, $t) = Git::main_ref(); print $t if defined $t' "$root/method/scripts/method/lib/git.pl") &&
    [ -n "$mt" ] && git merge-base --all "$mt" HEAD 2>/dev/null | sed -n 1p)
}
# forge DIR GATE OPEN [KEY=VALUE...]: a receipt in DIR's git folder: by
# default VALID, for HEAD and its tree, its base the merge base with main,
# stopped after every receipt forged before it
forge_n=0
forge() {
  f_dir=$1
  f_gate=$2
  f_open=$3
  shift 3
  forge_n=$((forge_n + 1))
  perl "$work/forge.pl" "$(store "$f_dir")" gate="$f_gate" open="$f_open" state=VALID head="$(cd "$f_dir" && git rev-parse HEAD)" \
    tree="$(cd "$f_dir" && git rev-parse 'HEAD^{tree}')" bases="$(mbase "$f_dir")" stopped=$((1800000000 + forge_n)) \
    name="$(printf '%024x' "$forge_n")" why= "$@"
}
# unforge DIR: removes every receipt from DIR's git folder
unforge() { rm -f "$(store "$1")"/method-receipt-*.json; }
# approve_head DIR: the receipts of a review of HEAD from the merge base,
# and nothing else: the reviewer and the security checker, both VALID,
# both opening with the approving word
approve_head() {
  unforge "$1"
  forge "$1" "$R" APPROVE
  forge "$1" "$S" APPROVE
}
# dca DIR [VAR=VALUE...]: approve_head, then done-check (dc)
dca() {
  approve_head "$1" 2>/dev/null
  dc "$@"
}

# --- the floor (step 6b.1, SPEC R4): the plan and the gates' receipts. Each
# group builds its own project, so it runs alone when wanted (TEST_ONLY) ---

# floor_project: prints a new project's working folder (new_project's w):
# the plan of task t1 approved, run-checks run, the verdict line approving,
# no receipt yet
floor_project() {
  fp_p=$(new_project) || return 1
  rc "$fp_p/w"
  amend "$fp_p/w" "$OK"
  printf '%s\n' "$fp_p/w"
}
# short ID: its first 7 characters
short() { printf '%s' "$1" | cut -c1-7; }

if wanted_any "floor: approving receipts of both gates from the merge base are READY" "floor: a typed approve with no receipts"; then
  f=$(floor_project) || abort_sandbox
  dc "$f"
  expect "floor: a typed approve with no receipts is NOT READY: no receipt of either gate, and the line is not backed" 1 \
    "done-check: reviewer: FAIL - no receipt of method-reviewer for these files" \
    "done-check: security checker: FAIL - no receipt of method-security-checker for these files" \
    "done-check: verdict: FAIL - the verdict line says approve, but the receipts do not give it (reviewer, security checker above): a typed line is not a review" \
    "done-check: next: run method-reviewer on these files, in the foreground, with a review packet from the merge base" \
    "done-check: NOT READY - 3 conditions failed (reviewer, security checker, verdict)"
  forge "$f" "$R" APPROVE
  forge "$f" "$S" APPROVE
  dc "$f"
  expect "floor: approving receipts of both gates from the merge base are READY" 0 "done-check: reviewer: PASS" "done-check: security checker: PASS" \
    "done-check: READY - "
fi

if wanted_any "floor: NOTHING TO MERGE still exits 3"; then
  f=$(floor_project) || abort_sandbox
  (cd "$f" && git checkout -q main)
  dc "$f"
  expect "floor: NOTHING TO MERGE still exits 3 with the receipt library loaded" 3 "done-check: NOTHING TO MERGE - "
fi

if wanted_any "floor: no plan" "floor: two task plans" "floor: a plan with no Tier line" "floor: a plan with a Tier line that is neither" \
  "floor: a plan with no Approved line" "floor: an Approved line without" "floor: an Approved line that names another task" \
  "floor: an Approved line not in its form" "floor: a plan that main already holds" "floor: a plan with two" \
  "floor: an Approved line whose quote only ends" "floor: an Approved line with"; then
  f=$(floor_project) || abort_sandbox
  approve_head "$f"
  # plan PLAN-TEXT: the task's plan becomes PLAN-TEXT, committed, approved
  # by both gates
  plan() {
    printf '%b' "$1" >"$f/docs/tasks/t1/plan.md"
    (cd "$f" && git add -A)
    msg "$f" 'Plan\n\n%s\n' "$OK"
    rc "$f"
    approve_head "$f"
  }
  plan '# Task t1\n\nTier: LIGHT\nPaths: src\nApproved: 2026-11-22 "looks good, go ahead"\n'
  dc "$f"
  expect "floor: an Approved line without approve <id> is NOT READY" 1 \
    "done-check: plan: FAIL - the Approved line's quote does not hold \"approve t1\" for this task: \"looks good, go ahead\"" \
    "done-check: next: ask the owner for their go on the plan (their reply holds \"approve t1\"), then add the Approved line quoting it" \
    "done-check: NOT READY - 2 conditions failed (plan, verdict)"
  plan '# Task t1\n\nTier: LIGHT\nPaths: src\nApproved: 2026-11-22 "approve"\n'
  dc "$f"
  expect "floor: an Approved line without the task's id (\"approve\" alone) is NOT READY" 1 "done-check: plan: FAIL - the Approved line's quote does not hold \"approve t1\""
  plan '# Task t1\n\nTier: LIGHT\nPaths: src\nApproved: 2026-11-22 "approve t2"\n'
  dc "$f"
  expect "floor: an Approved line that names another task is NOT READY" 1 "done-check: plan: FAIL - the Approved line's quote does not hold \"approve t1\" for this task: \"approve t2\""
  plan '# Task t1\n\nTier: LIGHT\nPaths: src\nApproved: 2026-11-22 "approve t1x"\n'
  dc "$f"
  expect "floor: an Approved line that names another task whose id starts with this one's is NOT READY" 1 "done-check: plan: FAIL - the Approved line's quote does not hold"
  plan '# Task t1\n\nTier: LIGHT\nPaths: src\nApproved: today "approve t1"\n'
  dc "$f"
  expect "floor: an Approved line not in its form is NOT READY" 1 "done-check: plan: FAIL - docs/tasks/t1/plan.md's Approved line is not Approved: <YYYY-MM-DD>"
  plan '# Task t1\n\nTier: LIGHT\nPaths: src\n'
  dc "$f"
  expect "floor: a plan with no Approved line is NOT READY" 1 "done-check: plan: FAIL - docs/tasks/t1/plan.md has no Approved line: the owner has not approved the plan"
  plan '# Task t1\n\nPaths: src\nApproved: 2026-11-22 "approve t1"\n'
  dc "$f"
  expect "floor: a plan with no Tier line is NOT READY" 1 "done-check: plan: FAIL - docs/tasks/t1/plan.md has no Tier line (Tier: FULL or Tier: LIGHT)"
  plan '# Task t1\n\nTier: SMALL\nPaths: src\nApproved: 2026-11-22 "approve t1"\n'
  dc "$f"
  expect "floor: a plan with a Tier line that is neither FULL nor LIGHT is NOT READY" 1 "done-check: plan: FAIL - docs/tasks/t1/plan.md's Tier line is not Tier: FULL or Tier: LIGHT: Tier: SMALL"
  plan '# Task t1\n\nTier: LIGHT\nTier: FULL\nPaths: src\nApproved: 2026-11-22 "approve t1"\n'
  dc "$f"
  expect "floor: a plan with two Tier lines is NOT READY" 1 "done-check: plan: FAIL - docs/tasks/t1/plan.md has 2 Tier lines; it holds one" \
    "done-check: next: keep one Tier line in docs/tasks/t1/plan.md, and ask the owner again"
  plan '# Task t1\n\nTier: LIGHT\nPaths: src\nApproved: 2026-11-22 "approve t1"\nApproved: 2026-11-23 "approve t1 again"\n'
  dc "$f"
  expect "floor: a plan with two Approved lines is NOT READY" 1 "done-check: plan: FAIL - docs/tasks/t1/plan.md has 2 Approved lines; it holds one, the newest approval" \
    "done-check: next: keep only the newest Approved line"
  plan '# Task t1\n\nTier: LIGHT\nPaths: src\nApproved: 2026-11-22 "I disapprove t1"\n'
  dc "$f"
  expect "floor: an Approved line whose quote only ends in the ready word (\"I disapprove t1\") is NOT READY" 1 \
    "done-check: plan: FAIL - the Approved line's quote does not hold \"approve t1\" for this task: \"I disapprove t1\""
  for tm in 25:00 9:30 12:60 '12:30:00' T12:30; do
    plan "# Task t1\n\nTier: LIGHT\nPaths: src\nApproved: 2026-11-22 $tm \"approve t1\"\n"
    dc "$f"
    expect "floor: an Approved line with a malformed time ($tm) is NOT READY" 1 \
      "done-check: plan: FAIL - docs/tasks/t1/plan.md's Approved line is not Approved: <YYYY-MM-DD> <HH:MM> \"<the owner's reply>\" (the time, on a 24-hour clock, may be left out): Approved: 2026-11-22 $tm \"approve t1\""
  done
  plan '# Task t1\n\nTier: LIGHT\nPaths: src\nApproved: 2026-11-22 23:59 "approve t1"\n'
  dc "$f"
  expect "floor: an Approved line with a time after the date is READY" 0 \
    "done-check: plan: PASS - task t1 (docs/tasks/t1/plan.md), Tier LIGHT; approved 2026-11-22 23:59 \"approve t1\" in commit " "done-check: READY - "
  plan '# Task t1\n\nTier: LIGHT\nPaths: src\nApproved: 2026-11-22 "Approve t1, thanks"\n'
  dc "$f"
  expect "setup: an approval that quotes \"Approve t1\" in capitals is READY" 0 "done-check: plan: PASS - task t1 (docs/tasks/t1/plan.md), Tier LIGHT; approved 2026-11-22 \"Approve t1, thanks\"" "done-check: READY - "
  add_task "$f" t2
  (cd "$f" && git add -A)
  msg "$f" 'Two\n\n%s\n' "$OK"
  rc "$f"
  approve_head "$f"
  dc "$f"
  expect "floor: two task plans on one branch are NOT READY" 1 "done-check: plan: FAIL - this branch adds 2 task plans (docs/tasks/t1/plan.md, docs/tasks/t2/plan.md); one task goes in one merge"
  (cd "$f" && git rm -q -r docs)
  msg "$f" 'None\n\n%s\n' "$OK"
  rc "$f"
  approve_head "$f"
  dc "$f"
  expect "floor: no plan is NOT READY" 1 "done-check: plan: FAIL - this branch adds no task plan (docs/tasks/<id>/plan.md)" \
    "done-check: next: plan the task on this branch in docs/tasks/<id>/plan.md (the method-plan skill) and ask the owner for their go on it" \
    "done-check: rounds: PASS - 1 version reviewed on this branch (no approved plan to count from), of at most 3"
  # a plan main already holds is not this branch's task
  (cd "$f" && git checkout -q main && add_task . && git add -A && git commit -q -m "An old task" -m "$OK" && git push -q origin main 2>/dev/null &&
    git checkout -q feat && git merge -q --no-edit main 2>/dev/null)
  amend "$f" "$OK"
  approve_head "$f"
  dc "$f"
  expect "floor: a plan that main already holds is not this branch's task: no plan, NOT READY" 1 "done-check: plan: FAIL - this branch adds no task plan"
fi

if wanted_any "floor: no reviewer receipt" "floor: no security checker receipt" "floor: a receipt for another tree"; then
  f=$(floor_project) || abort_sandbox
  forge "$f" "$S" APPROVE
  dc "$f"
  expect "floor: no reviewer receipt is NOT READY" 1 "done-check: reviewer: FAIL - no receipt of method-reviewer for these files (tree " \
    "(receipts are kept in this clone only, the newest 500)" "done-check: security checker: PASS"
  unforge "$f"
  forge "$f" "$R" APPROVE
  dc "$f"
  expect "floor: no security checker receipt is NOT READY" 1 "done-check: security checker: FAIL - no receipt of method-security-checker for these files (tree " \
    "done-check: reviewer: PASS"
  approve_head "$f"
  echo y >"$f/src/a.txt"
  (cd "$f" && git add -A)
  msg "$f" 'Fix\n\n%s\n' "$OK"
  rc "$f"
  dc "$f"
  expect "floor: a receipt for another tree does not count: NOT READY" 1 \
    "done-check: reviewer: FAIL - no receipt of method-reviewer for these files (tree $(short "$(cd "$f" && git rev-parse 'HEAD^{tree}')")); its receipts here are for other versions"
fi

if wanted_any "floor: an INVALID approving receipt" "floor: an INCOMPLETE approving receipt" "floor: a receipt with no word"; then
  f=$(floor_project) || abort_sandbox
  forge "$f" "$S" APPROVE
  forge "$f" "$R" APPROVE state=INVALID why=write-mark
  dc "$f"
  expect "floor: an INVALID approving receipt does not count: NOT READY" 1 \
    "done-check: reviewer: FAIL - no receipt of method-reviewer for these files (tree " ") is VALID with APPROVE: APPROVE (INVALID: write-mark)"
  unforge "$f"
  forge "$f" "$S" APPROVE
  forge "$f" "$R" APPROVE state=INCOMPLETE why=record-late
  dc "$f"
  expect "floor: an INCOMPLETE approving receipt does not count: NOT READY" 1 \
    "done-check: reviewer: FAIL - no receipt of method-reviewer for these files (tree " ") is VALID with APPROVE: APPROVE (INCOMPLETE: record-late)"
  forge "$f" "$R" none state=INCOMPLETE why=lines-missing-after-retry
  forge "$f" "$R" APPROVE
  dc "$f"
  expect "floor: a receipt with no word beside an APPROVE neither blocks nor counts: READY" 0 "done-check: reviewer: PASS" "done-check: READY - " \
    "method-reviewer no word (INCOMPLETE), method-reviewer APPROVE"
fi

if wanted_any "floor: a REQUEST CHANGES beside an APPROVE"; then
  f=$(floor_project) || abort_sandbox
  for st in VALID INVALID INCOMPLETE; do
    unforge "$f"
    forge "$f" "$S" APPROVE
    forge "$f" "$R" "REQUEST CHANGES" state=$st
    forge "$f" "$R" APPROVE
    dc "$f"
    expect "floor: a REQUEST CHANGES beside an APPROVE on one tree is NOT READY, whatever its state ($st)" 1 \
      "done-check: reviewer: FAIL - 1 receipt of method-reviewer for these files (tree " "opens with another word: REQUEST CHANGES ($st" \
      "a later review of the same files does not clear it" "done-check: next: fix what method-reviewer found, commit, and have the new version reviewed"
  done
  unforge "$f"
  forge "$f" "$R" APPROVE
  forge "$f" "$S" ESCALATE
  forge "$f" "$S" APPROVE
  dc "$f"
  expect "floor: a REQUEST CHANGES beside an APPROVE: the security checker's ESCALATE blocks too" 1 \
    "done-check: security checker: FAIL - 1 receipt of method-security-checker for these files (tree " "opens with another word: ESCALATE (VALID)"
fi

if wanted_any "floor: a receipt with no base" "floor: a first review built with --since" "floor: a review built with --since that chains"; then
  f=$(floor_project) || abort_sandbox
  mb=$(mbase "$f")
  first=$(cd "$f" && git rev-parse HEAD)
  forge "$f" "$S" APPROVE
  forge "$f" "$R" APPROVE bases=absent
  dc "$f"
  expect "floor: a receipt with no base (made before receipts had one) does not count: NOT READY" 1 \
    "done-check: reviewer: FAIL - the receipt of method-reviewer that approved these files (tree " "records no review packet's base"
  unforge "$f"
  forge "$f" "$S" APPROVE
  forge "$f" "$R" APPROVE bases=
  dc "$f"
  expect "floor: a receipt with no base (no packet read) does not count: NOT READY" 1 "records no review packet's base"
  # the first round, from the merge base, asked for changes; the fix is then
  # reviewed from the first round's version (--since)
  unforge "$f"
  forge "$f" "$R" "REQUEST CHANGES"
  forge "$f" "$S" "REQUEST CHANGES"
  echo y >"$f/src/a.txt"
  (cd "$f" && git add -A)
  msg "$f" 'Fix\n\n%s\n' "$OK"
  rc "$f"
  forge "$f" "$R" APPROVE bases="$first"
  forge "$f" "$S" APPROVE bases="$first"
  dc "$f"
  expect "floor: a review built with --since that chains to a review from the merge base is READY" 0 \
    "done-check: reviewer: PASS - method-reviewer opened with APPROVE on these files (tree " "reviewed from $(short "$first"), which chains back to the merge base $(short "$mb")" \
    "done-check: READY - "
  # the same slice, with no review of the first version
  unforge "$f"
  forge "$f" "$R" APPROVE bases="$first"
  forge "$f" "$S" APPROVE
  dc "$f"
  expect "floor: a first review built with --since that does not chain is NOT READY" 1 \
    "done-check: reviewer: FAIL - the receipt of method-reviewer that approved these files (tree " \
    "reviewed from $(short "$first"), which does not chain back to the merge base $(short "$mb")" "done-check: security checker: PASS"
  # the first version reviewed with a base that does not chain either
  first_tree=$(cd "$f" && git rev-parse "$first^{tree}")
  forge "$f" "$R" "REQUEST CHANGES" tree="$first_tree" head="$first" bases="$first"
  dc "$f"
  expect "floor: a first review built with --since, on a version whose own review does not chain, is NOT READY" 1 "which does not chain back to the merge base"
fi

if wanted_any "floor: a fourth round since the anchor" "floor: three rounds since the anchor" "floor: rounds before the anchor are not counted"; then
  f=$(floor_project) || abort_sandbox
  # round N: a new version, reviewed (with changes asked for, but the last)
  round() {
    echo "$1" >"$f/src/a.txt"
    (cd "$f" && git add -A)
    msg "$f" 'Round\n\n%s\n' "$OK"
    rc "$f"
    forge "$f" "$R" "$2"
    forge "$f" "$S" "$2"
  }
  forge "$f" "$R" "REQUEST CHANGES"
  forge "$f" "$S" "REQUEST CHANGES"
  round 2 "REQUEST CHANGES"
  round 3 APPROVE
  dc "$f"
  expect "floor: three rounds since the anchor are READY" 0 "done-check: rounds: PASS - 3 versions reviewed since the plan's approval, of at most 3" "done-check: READY - "
  : >"$f/src/b.txt"
  (cd "$f" && git add -A)
  msg "$f" 'Unreviewed\n\n%s\n' "$OK"
  round 4 APPROVE
  dc "$f"
  expect "floor: a fourth round since the anchor is NOT READY: plan again" 1 \
    "done-check: rounds: FAIL - 4 versions were reviewed since the plan's approval; the limit is 3 rounds" \
    "done-check: next: plan again: change the plan, ask the owner for their go again, and replace the Approved line with their new reply, with today's date and the time (Approved: YYYY-MM-DD HH:MM \"<the reply>\"); the new line starts the count again" \
    "done-check: NOT READY - 2 conditions failed (rounds, verdict)"
  # a new approval moves the anchor; the rounds before it are not counted
  add_task "$f" t1 LIGHT 'Approved: 2026-11-23 "approve t1, with the new plan"'
  (cd "$f" && git add -A)
  msg "$f" 'Plan again\n\n%s\n' "$OK"
  round 5 APPROVE
  anchor=$(cd "$f" && git rev-parse HEAD~1)
  dc "$f"
  expect "floor: rounds before the anchor are not counted: READY after a new approval" 0 \
    "done-check: plan: PASS - task t1 (docs/tasks/t1/plan.md), Tier LIGHT; approved 2026-11-23 \"approve t1, with the new plan\" in commit $(short "$anchor"); the plan was approved 2 times on this branch: 2026-11-22 \"approve t1\"; 2026-11-23 \"approve t1, with the new plan\"" \
    "done-check: rounds: PASS - 1 version reviewed since the plan's approval" "done-check: READY - " \
    "; the plan was approved 2 times on this branch: 2026-11-22 \"approve t1\"; 2026-11-23 \"approve t1, with the new plan\""
fi

# a rewritten history keeps its rounds (M009): the versions reviewed under
# the same Approved line count, on the branch or not
if wanted_any "floor: rounds survive a squash" "floor: rounds survive a rebase" "floor: an Approved line removed and added again" \
  "floor: a reviewed version this clone cannot read"; then
  # next_round DIR TEXT WORD: a new version of src/a.txt, committed and
  # reviewed by both gates with WORD
  next_round() {
    echo "$2" >"$1/src/a.txt"
    (cd "$1" && git add -A)
    msg "$1" 'Round\n\n%s\n' "$OK"
    rc "$1"
    forge "$1" "$R" "$3"
    forge "$1" "$S" "$3"
  }
  f=$(floor_project) || abort_sandbox
  mb=$(mbase "$f")
  forge "$f" "$R" "REQUEST CHANGES"
  forge "$f" "$S" "REQUEST CHANGES"
  next_round "$f" 2 "REQUEST CHANGES"
  next_round "$f" 3 "REQUEST CHANGES"
  next_round "$f" 4 APPROVE
  (cd "$f" && git reset -q --soft "$mb")
  msg "$f" 'Squashed\n\n%s\n' "$OK"
  rc "$f"
  dc "$f"
  expect "floor: rounds survive a squash: four versions reviewed, one commit left, NOT READY" 1 \
    "done-check: rounds: FAIL - 4 versions were reviewed since the plan's approval (3 of them are no longer on this branch: its history was rewritten); the limit is 3 rounds" \
    "done-check: reviewer: PASS" "done-check: NOT READY - 2 conditions failed (rounds, verdict)"

  f=$(floor_project) || abort_sandbox
  forge "$f" "$R" "REQUEST CHANGES"
  forge "$f" "$S" "REQUEST CHANGES"
  next_round "$f" 2 "REQUEST CHANGES"
  next_round "$f" 3 "REQUEST CHANGES"
  (cd "$f" && git checkout -q main && echo more >>README && git commit -q -a -m "Main moves" -m "$OK" && git push -q origin main 2>/dev/null &&
    git checkout -q feat && git rebase -q main >/dev/null 2>&1)
  next_round "$f" 4 APPROVE
  dc "$f"
  expect "floor: rounds survive a rebase onto a main that moved: NOT READY" 1 \
    "done-check: up to date: PASS" \
    "done-check: rounds: FAIL - 4 versions were reviewed since the plan's approval (3 of them are no longer on this branch: its history was rewritten); the limit is 3 rounds"

  # the line is taken out and put back: the anchor stays at its first
  # commit, so the version without the line still counts
  f=$(floor_project) || abort_sandbox
  forge "$f" "$R" "REQUEST CHANGES"
  forge "$f" "$S" "REQUEST CHANGES"
  printf '# Task t1\n\nTier: LIGHT\nPaths: src\n\nThe task.\n' >"$f/docs/tasks/t1/plan.md"
  next_round "$f" 2 "REQUEST CHANGES"
  add_task "$f"
  next_round "$f" 3 "REQUEST CHANGES"
  next_round "$f" 4 APPROVE
  dc "$f"
  expect "floor: an Approved line removed and added again does not move the anchor: a fourth round is NOT READY" 1 \
    "done-check: rounds: FAIL - 4 versions were reviewed since the plan's approval; the limit is 3 rounds"

  f=$(floor_project) || abort_sandbox
  approve_head "$f"
  forge "$f" "$R" "REQUEST CHANGES" tree=abababababababababababababababababababab
  dc "$f"
  expect "floor: a reviewed version this clone cannot read is not counted, and the line says so: READY" 0 \
    "done-check: rounds: PASS - 1 version reviewed since the plan's approval, of at most 3; not counted: 1 version that method-reviewer reviewed and this clone cannot read (whether they hold this approval is not known)" \
    "done-check: READY - "
fi

# a second task's plan, or its folder, as a symbolic link is still a second
# task: one task goes in one merge
if wanted_any "floor: a second task plan that is a symbolic link" "floor: a second task folder that is a symbolic link"; then
  f=$(floor_project) || abort_sandbox
  mkdir -p "$f/docs/tasks/t2"
  if ! ln -s ../t1/plan.md "$f/docs/tasks/t2/plan.md" 2>/dev/null || ! [ -L "$f/docs/tasks/t2/plan.md" ]; then
    skip "a second task plan or folder that is a symbolic link: this system cannot make symlinks"
  else
    (cd "$f" && git add -A)
    msg "$f" 'Link\n\n%s\n' "$OK"
    rc "$f"
    approve_head "$f"
    dc "$f"
    expect "floor: a second task plan that is a symbolic link is NOT READY" 1 \
      "done-check: plan: FAIL - this branch adds a task folder or plan that is not a plain folder and file: docs/tasks/t2/plan.md (a symbolic link)" \
      "done-check: next: make each task plan a regular file in its own folder, docs/tasks/<id>/plan.md; one task, with one plan, a merge"
    (cd "$f" && git rm -q -r docs/tasks/t2 && ln -s t1 docs/tasks/t2 && git add -A)
    msg "$f" 'Folder link\n\n%s\n' "$OK"
    rc "$f"
    approve_head "$f"
    dc "$f"
    expect "floor: a second task folder that is a symbolic link is NOT READY" 1 \
      "done-check: plan: FAIL - this branch adds a task folder or plan that is not a plain folder and file: docs/tasks/t2 (a symbolic link)"
  fi
fi

# a task folder whose name is not an id, or one stored as a submodule
if wanted_any "floor: a task folder whose name is not an id"; then
  f=$(floor_project) || abort_sandbox
  (cd "$f" && git mv docs/tasks/t1 docs/tasks/T_1)
  add_task "$f" T_1
  (cd "$f" && git add -A)
  msg "$f" 'Rename\n\n%s\n' "$OK"
  rc "$f"
  approve_head "$f"
  dc "$f"
  expect "floor: a task folder whose name is not an id (T_1) is NOT READY" 1 \
    "done-check: plan: FAIL - the task's folder name is not an id (lower-case letters, digits and dashes): docs/tasks/T_1/plan.md" \
    "done-check: next: rename the folder, and ask the owner again"
fi
if wanted_any "floor: a second task folder stored as a submodule"; then
  f=$(floor_project) || abort_sandbox
  mkdir -p "$f/docs/tasks/t2"
  (cd "$f" && git update-index --add --cacheinfo "160000,$(git rev-parse HEAD),docs/tasks/t2")
  msg "$f" 'Submodule\n\n%s\n' "$OK"
  rc "$f"
  approve_head "$f"
  dc "$f"
  expect "floor: a second task folder stored as a submodule (a gitlink) is NOT READY" 1 \
    "done-check: plan: FAIL - this branch adds a task folder or plan that is not a plain folder and file: docs/tasks/t2 (a submodule)"
fi

# the rounds since the anchor are the anchor and the branch's commits it is
# an ancestor of: a side line made before the approval, reviewed there and
# merged after it, is listed after the anchor but is not counted
if wanted_any "floor: a side line reviewed before the approval and merged after it"; then
  f=$(floor_project) || abort_sandbox
  printf '# Task t1\n\nTier: LIGHT\nPaths: src\n\nThe task.\n' >"$f/docs/tasks/t1/plan.md"
  (cd "$f" && git add -A)
  msg "$f" 'Not approved\n\n%s\n' "$OPEN"
  (cd "$f" && git switch -q -c side)
  for n in 1 2 3; do
    echo "side $n" >"$f/src/a.txt"
    (cd "$f" && git add -A)
    msg "$f" 'Side\n\n%s\n' "$OPEN"
    forge "$f" "$R" "REQUEST CHANGES"
  done
  (cd "$f" && git switch -q feat)
  add_task "$f" t1 LIGHT 'Approved: 2026-11-23 "approve t1"'
  (cd "$f" && git add -A)
  msg "$f" 'Approved\n\n%s\n' "$OPEN"
  anchor=$(cd "$f" && git rev-parse HEAD)
  (cd "$f" && git merge -q --no-edit side >/dev/null 2>&1)
  amend "$f" "$OK"
  rc "$f"
  forge "$f" "$R" APPROVE
  forge "$f" "$S" APPROVE
  dc "$f"
  expect "floor: a side line reviewed before the approval and merged after it is not counted: READY" 0 \
    "done-check: plan: PASS - task t1 (docs/tasks/t1/plan.md), Tier LIGHT; approved 2026-11-23 \"approve t1\" in commit $(short "$anchor")" \
    "done-check: rounds: PASS - 1 version reviewed since the plan's approval, of at most 3" "done-check: READY - "
fi

# a re-approval on the same day: the time after the date makes it a new
# line, so a new anchor, and the rounds start again
if wanted_any "floor: a same-day re-approval with a time moves the anchor"; then
  f=$(floor_project) || abort_sandbox
  # again DIR TEXT WORD: a new version of src/a.txt, committed and reviewed
  # by both gates with WORD
  again() {
    echo "$2" >"$1/src/a.txt"
    (cd "$1" && git add -A)
    msg "$1" 'Round\n\n%s\n' "$OK"
    rc "$1"
    forge "$1" "$R" "$3"
    forge "$1" "$S" "$3"
  }
  add_task "$f" t1 LIGHT 'Approved: 2026-11-22 09:15 "approve t1"'
  again "$f" 1 "REQUEST CHANGES"
  again "$f" 2 "REQUEST CHANGES"
  again "$f" 3 "REQUEST CHANGES"
  again "$f" 4 "REQUEST CHANGES"
  dc "$f"
  expect "setup: four rounds since a 09:15 approval are NOT READY" 1 \
    "done-check: rounds: FAIL - 4 versions were reviewed since the plan's approval; the limit is 3 rounds"
  add_task "$f" t1 LIGHT 'Approved: 2026-11-22 16:30 "approve t1"'
  (cd "$f" && git add -A)
  msg "$f" 'Plan again\n\n%s\n' "$OK"
  anchor=$(cd "$f" && git rev-parse HEAD)
  again "$f" 5 APPROVE
  dc "$f"
  expect "floor: a same-day re-approval with a time moves the anchor: the rounds start again, READY" 0 \
    "done-check: plan: PASS - task t1 (docs/tasks/t1/plan.md), Tier LIGHT; approved 2026-11-22 16:30 \"approve t1\" in commit $(short "$anchor"); the plan was approved 3 times on this branch: 2026-11-22 \"approve t1\"; 2026-11-22 09:15 \"approve t1\"; 2026-11-22 16:30 \"approve t1\"" \
    "done-check: rounds: PASS - 1 version reviewed since the plan's approval, of at most 3" "done-check: READY - "
fi

# shipped output names no record of the method's own repository (its risk,
# requirement or decision numbers) and promises no later step of it
if wanted_any "floor: done-check's lines name no record of the method's own repository"; then
  f=$(floor_project) || abort_sandbox
  approve_head "$f"
  dc "$f"
  expect "setup: a reviewed change is READY" 0 "done-check: checks: PASS" "done-check: READY - "
  all=$out
  printf 'integ\tci\t-\t(\\d+) ok\techo 0 ok; exit 1\n' >>"$f/checks/project.tsv"
  (cd "$f" && git add -A)
  amend "$f" "$OPEN"
  rc "$f"
  unforge "$f"
  dc "$f"
  expect "setup: a CI-only check and an open verdict line with no review are NOT READY" 1 "done-check: elsewhere: FAIL - " \
    "done-check: verdict: FAIL - the verdict line says request-changes-open" "no review approved this version"
  all="$all
$out"
  # shellcheck disable=SC2016 # perl code, expanded by perl
  ids=$(printf '%s\n' "$all" | perl -ne 'print if /RISKS #[0-9]|SPEC R[0-9]|\(step [0-9]|DECISIONS A[0-9]|(?<![A-Za-z0-9_-])A[0-9]{1,3}(?![A-Za-z0-9_])/')
  if [ -z "$ids" ]; then
    pass "floor: done-check's lines name no record of the method's own repository and promise no later step"
  else
    fail "floor: done-check's lines name no record of the method's own repository and promise no later step" "$ids"
  fi
fi

if wanted_any "floor: a pruned receipt reads as missing"; then
  f=$(floor_project) || abort_sandbox
  approve_head "$f"
  rm -f "$(store "$f")/method-receipt-$(printf '%024x' "$forge_n").json"
  dc "$f"
  expect "floor: a pruned receipt reads as missing: NOT READY" 1 "done-check: security checker: FAIL - no receipt of method-security-checker for these files"
fi

if wanted_any "floor: approving receipts at the parent, HEAD an empty trailer commit"; then
  f=$(floor_project) || abort_sandbox
  amend "$f" "$OPEN"
  rc "$f"
  approve_head "$f"
  msg "$f" 'Verdict\n\n%s\n' "$OK"
  dc "$f"
  expect "floor: approving receipts at the parent, HEAD an empty trailer commit: READY (the same tree)" 0 "done-check: reviewer: PASS" "done-check: READY - "
fi

if wanted_any "floor: the history lists every gate's word" "floor: two receipts whose name order and stopped order disagree" "floor: a diagnose receipt shows in the history"; then
  f=$(floor_project) || abort_sandbox
  c1=$(cd "$f" && git rev-parse HEAD)
  forge "$f" "$R" "REQUEST CHANGES"
  forge "$f" "$D" "ROOT CAUSE"
  echo y >"$f/src/a.txt"
  (cd "$f" && git add -A)
  msg "$f" 'Fix\n\n%s\n' "$OK"
  rc "$f"
  c2=$(cd "$f" && git rev-parse HEAD)
  # (named so the later run sorts first by name)
  forge "$f" "$T" "TESTS PASS" name=000000000000000000000000 stopped=1900000002
  forge "$f" "$R" APPROVE stopped=1900000001
  forge "$f" "$S" APPROVE stopped=1900000003
  forge "$f" "$S" none state=INCOMPLETE stopped=none
  dc "$f"
  expect "floor: the history lists every gate's word on the branch's versions, in commit order" 0 \
    "done-check: history - $(short "$c1"): method-reviewer REQUEST CHANGES, method-diagnose ROOT CAUSE; $(short "$c2"): " "done-check: READY - "
  expect "floor: a diagnose receipt shows in the history" 0 "method-diagnose ROOT CAUSE"
  expect "floor: two receipts whose name order and stopped order disagree are listed by the time they stopped" 0 \
    "$(short "$c2"): method-reviewer APPROVE, method-tester TESTS PASS, method-security-checker APPROVE"
  lacks "floor: a receipt with no stopped time is not in the history" "method-security-checker no word"
fi


# --- the SPEC R6 set (step 6b.3): the tier and the high-risk paths, the
# lock, the failing and the passing runs, the reporter, Deep review
# (M145, M146, M147) ---
P=method-reporter
# full_project: sets f to a new project's working folder for a FULL task:
# the plan of task t1 (Tier FULL, with expected.tsv) approved in the first
# commit on feat (the anchor, its id in anchor), with src/a.txt as before
# the code; a second commit adds the tests (tests/cases.txt, its id in
# tcommit), where method-tester's receipt says TESTS FAIL; a third commit
# is the code (src/a.txt), run-checks run, its verdict line approving; no
# other receipt. Not in a subshell, so the receipts' count goes on.
full_project() {
  fl_p=$(new_project FULL) || return 1
  f="$fl_p/w"
  anchor=$(cd "$f" && git rev-parse HEAD)
  mkdir -p "$f/tests" && printf 'case one\n' >"$f/tests/cases.txt"
  (cd "$f" && git add -A)
  msg "$f" 'Tests\n\n%s\n' "$OPEN"
  tcommit=$(cd "$f" && git rev-parse HEAD)
  forge "$f" "$T" "TESTS FAIL"
  printf 'x = 2\n' >"$f/src/a.txt"
  (cd "$f" && git add -A)
  msg "$f" 'Code\n\n%s\n' "$OPEN"
  rc "$f"
  amend "$f" "$OK"
}
# finish DIR: the receipts of a finished FULL change on HEAD's tree, in
# this order: the tester's pass, the reviewer, the security checker, the
# reporter
finish() {
  forge "$1" "$T" "TESTS PASS"
  forge "$1" "$R" APPROVE
  forge "$1" "$S" APPROVE
  forge "$1" "$P" APPROVE
}
# recommit DIR SUBJECT: commits every change in DIR, runs the checks and
# approves the verdict line
recommit() {
  (cd "$1" && git add -A)
  msg "$1" "$2"'\n\n%s\n' "$OPEN"
  rc "$1"
  amend "$1" "$OK"
}

if wanted_any "R6: a FULL change" "R6: no failing run" "R6: a failing run on HEAD's tree only" "R6: a failing run on HEAD's files" "R6: a failing run before the plan's approval" \
  "R6: no passing run" "R6: the tester's newest word" "R6: no reporter" "R6: the reporter's newest word" \
  "R6: an INCOMPLETE failing run"; then
  full_project || abort_sandbox
  finish "$f"
  dc "$f"
  expect "R6: a FULL change with the failing run after the approval, the passing run, the reporter and both reviews is READY" 0 \
    "done-check: tier: PASS - Tier FULL, as the plan says; no changed path is high-risk (no HIGH_RISK_PATHS on main or in this change)" \
    "done-check: lock: PASS - the plan's Tier and Paths lines and its expected.tsv are as approved in commit $(short "$anchor")" \
    "done-check: failing run: PASS - method-tester opened with TESTS FAIL on commit $(short "$tcommit"), after the plan's approval in commit $(short "$anchor") and before these files" \
    "done-check: passing run: PASS - the newest receipt of method-tester for these files (tree " ") opened with TESTS PASS, VALID" \
    "done-check: reporter: PASS - the newest receipt of method-reporter for these files (tree " ") opened with APPROVE, VALID" \
    "done-check: READY - "
  lacks "R6: a FULL change off the high-risk paths has no deep review line" "done-check: deep review:"
  # the tester's newest word decides, by the time it stopped
  forge "$f" "$T" "TESTS FAIL" stopped=1700000000
  dc "$f"
  expect "R6: the tester's newest word decides: TESTS FAIL, then TESTS PASS on one tree is READY" 0 "done-check: passing run: PASS" "done-check: READY - "
  forge "$f" "$T" "TESTS FAIL"
  dc "$f"
  expect "R6: the tester's newest word decides: TESTS PASS, then TESTS FAIL on one tree is NOT READY" 1 \
    "done-check: passing run: FAIL - the newest receipt of method-tester for these files (tree " ") is TESTS FAIL (VALID), not TESTS PASS (VALID)" \
    "done-check: next: run method-tester on these files, in the foreground, and fix what it finds"
  forge "$f" "$T" "TESTS PASS" state=INVALID why=write-mark
  dc "$f"
  expect "R6: the tester's newest word decides: an INVALID TESTS PASS is not a pass" 1 "is TESTS PASS (INVALID), not TESTS PASS (VALID)"
  forge "$f" "$T" "TESTS PASS" stopped=none
  dc "$f"
  expect "R6: the tester's newest word decides: a run with no stop time never decides" 1 "is TESTS PASS (INVALID), not TESTS PASS (VALID)"
  forge "$f" "$T" "TESTS PASS"
  forge "$f" "$P" "REQUEST CHANGES" stopped=1700000000
  dc "$f"
  expect "R6: the reporter's newest word decides: REQUEST CHANGES, then APPROVE on one tree is READY" 0 "done-check: reporter: PASS" "done-check: READY - "
  forge "$f" "$P" "REQUEST CHANGES"
  dc "$f"
  expect "R6: the reporter's newest word decides: APPROVE, then REQUEST CHANGES on one tree is NOT READY" 1 \
    "done-check: reporter: FAIL - the newest receipt of method-reporter for these files (tree " ") is REQUEST CHANGES (VALID), not APPROVE (VALID)"
  # no passing run, no reporter
  unforge "$f"
  forge "$f" "$T" "TESTS FAIL" head="$tcommit" tree="$(cd "$f" && git rev-parse "$tcommit^{tree}")"
  forge "$f" "$R" APPROVE
  forge "$f" "$S" APPROVE
  dc "$f"
  expect "R6: no passing run at HEAD and no reporter on FULL: NOT READY" 1 \
    "done-check: passing run: FAIL - no receipt of method-tester for these files (tree " \
    "done-check: reporter: FAIL - no receipt of method-reporter for these files (tree " "a FULL change needs the reporter's word on its report" \
    "done-check: NOT READY - 3 conditions failed (passing run, reporter, verdict)"
  expect "R6: no reporter on FULL is NOT READY" 1 "done-check: reporter: FAIL - no receipt of method-reporter for these files"
  expect "R6: no passing run at HEAD is NOT READY" 1 "done-check: passing run: FAIL - no receipt of method-tester for these files"
  # no failing run; one on HEAD's tree only; one before the approval
  unforge "$f"
  finish "$f"
  dc "$f"
  expect "R6: no failing run after the approval is NOT READY" 1 \
    "done-check: failing run: FAIL - no VALID receipt of method-tester that opened with TESTS FAIL on a commit from the plan's approval (commit $(short "$anchor")) to before HEAD, with other files than HEAD's" \
    "done-check: next: run method-tester where the tests are in and the code is not" "done-check: NOT READY - 2 conditions failed (failing run, verdict)"
  forge "$f" "$T" "TESTS FAIL" stopped=1700000000
  dc "$f"
  expect "R6: a failing run on HEAD's tree only is NOT READY" 1 "done-check: failing run: FAIL - no VALID receipt of method-tester" \
    "; not counted: 1 on these files (a run on the finished files does not show the tests failing first)"
  # (an empty commit on top: the run's commit is now before HEAD, its files still HEAD's)
  msg "$f" 'Verdict\n\n%s\n' "$OK"
  dc "$f"
  expect "R6: a failing run on HEAD's files at an earlier commit (an empty commit on top) is NOT READY" 1 \
    "done-check: failing run: FAIL - no VALID receipt of method-tester" "; not counted: 1 on these files"
  base=$(mbase "$f")
  forge "$f" "$T" "TESTS FAIL" head="$base" tree="$(cd "$f" && git rev-parse "$base^{tree}")"
  dc "$f"
  expect "R6: a failing run before the plan's approval is NOT READY" 1 "done-check: failing run: FAIL - no VALID receipt of method-tester" \
    "1 on a commit outside this branch's history from the approval to HEAD"
  forge "$f" "$T" "TESTS FAIL" head="$tcommit" tree="$(cd "$f" && git rev-parse "$tcommit^{tree}")" state=INCOMPLETE why=record-late
  dc "$f"
  expect "R6: an INCOMPLETE failing run does not count: NOT READY" 1 "done-check: failing run: FAIL - no VALID receipt of method-tester"
fi

# the lock (M145): Tier, Paths and expected.tsv as approved; a re-approval
# moves the anchor, and the failing run is made again after it
if wanted_any "R6: the lock" "R6: a re-approval" "R6: the code-removed commit" "R6: a failing run on a side branch" "R6: a failing run re-made with git switch -c" \
  "R6: a FULL plan with no expected.tsv" "R6: a failing run on an expected value changed and changed back"; then
  for what in tier paths expected readd; do
    full_project || abort_sandbox
    case $what in
      tier) perl -pi -e 's/^Tier: FULL$/Tier: LIGHT/' "$f/docs/tasks/t1/plan.md" ;;
      paths) perl -pi -e 's/^Paths: src$/Paths: src, lib/' "$f/docs/tasks/t1/plan.md" ;;
      expected) printf 'case\tinputs\texpected\tsource\none\tx=1\t3\tthe owner\n' >"$f/docs/tasks/t1/expected.tsv" ;;
      readd)
        # the Approved line taken out with the change, and put back as it was
        perl -ni -e 'print unless /^Approved:/' "$f/docs/tasks/t1/plan.md"
        printf 'case\tinputs\texpected\tsource\none\tx=1\t3\tthe owner\n' >"$f/docs/tasks/t1/expected.tsv"
        recommit "$f" Unapproved
        add_task "$f" t1 FULL
        ;;
    esac
    recommit "$f" Change
    finish "$f"
    dc "$f"
    case $what in
      tier) expect "R6: the lock: the Tier line changed after the approval is NOT READY" 1 \
        "done-check: lock: FAIL - changed since the plan's approval in commit $(short "$anchor"): the Tier line" \
        "done-check: next: a change to the tier, the paths or the expected results is a new plan: ask the owner for their go again, and replace the Approved line with their new reply, with today's date and the time (Approved: YYYY-MM-DD HH:MM \"<the reply>\")" ;;
      paths) expect "R6: the lock: the Paths line changed after the approval is NOT READY" 1 "done-check: lock: FAIL - changed since the plan's approval in commit $(short "$anchor"): the Paths line" ;;
      expected) expect "R6: the lock: expected.tsv changed after the approval is NOT READY" 1 "done-check: lock: FAIL - changed since the plan's approval in commit $(short "$anchor"): expected.tsv" ;;
      readd) expect "R6: the lock: the Approved line removed and added again does not move the anchor: expected.tsv changed meanwhile is NOT READY" 1 \
        "done-check: lock: FAIL - changed since the plan's approval in commit $(short "$anchor"): expected.tsv" ;;
    esac
  done
  # a FULL plan approved with no expected.tsv
  fl_p=$(new_project) || abort_sandbox
  f="$fl_p/w"
  add_task "$f" t1 FULL 'Approved: 2026-11-23 "approve t1 as FULL"'
  recommit "$f" Full
  finish "$f"
  dc "$f"
  expect "R6: a FULL plan with no expected.tsv when it was approved is NOT READY" 1 \
    "done-check: lock: FAIL - the task is FULL, but its plan had no expected.tsv when it was approved in commit " \
    "done-check: next: write docs/tasks/t1/expected.tsv, ask the owner for their go again, and replace the Approved line with their new reply, with today's date and the time (Approved: YYYY-MM-DD HH:MM \"<the reply>\")"

  # a re-approval: a wrong expected value found at the failing run, a new
  # reply, so a new Approved line and a new anchor; the failing run before
  # it no longer counts
  full_project || abort_sandbox
  printf 'case\tinputs\texpected\tsource\none\tx=1\t3\tthe owner\n' >"$f/docs/tasks/t1/expected.tsv"
  add_task "$f" t1 FULL 'Approved: 2026-11-23 "approve t1 with the corrected case"'
  recommit "$f" Reapproved
  anchor2=$(cd "$f" && git rev-parse HEAD)
  finish "$f"
  dc "$f"
  expect "R6: a re-approval moves the anchor: the lock holds, and the failing run before it does not count" 1 \
    "done-check: lock: PASS - the plan's Tier and Paths lines and its expected.tsv are as approved in commit $(short "$anchor2")" \
    "done-check: failing run: FAIL - no VALID receipt of method-tester that opened with TESTS FAIL on a commit from the plan's approval (commit $(short "$anchor2"))" \
    "1 on a commit outside this branch's history from the approval to HEAD"
  # a fail receipt on a side branch from the new anchor does not count
  (cd "$f" && git switch -q -c side && printf 'x = 1\n' >src/a.txt && git commit -q -a -m "Side" -m "$OPEN")
  forge "$f" "$T" "TESTS FAIL"
  (cd "$f" && git switch -q feat)
  dc "$f"
  expect "R6: a failing run on a side branch does not count: NOT READY" 1 "done-check: failing run: FAIL - no VALID receipt of method-tester" \
    "2 on a commit outside this branch's history from the approval to HEAD"
  # the route: a commit that takes the code out (plan and expected.tsv kept),
  # the tester there, then a commit that puts it back
  printf 'x = 1\n' >"$f/src/a.txt"
  recommit "$f" 'Code out'
  out_commit=$(cd "$f" && git rev-parse HEAD)
  forge "$f" "$T" "TESTS FAIL"
  printf 'x = 2\n' >"$f/src/a.txt"
  recommit "$f" 'Code back'
  finish "$f"
  dc "$f"
  expect "R6: the code-removed commit after a re-approval gives the failing run: READY" 0 \
    "done-check: failing run: PASS - method-tester opened with TESTS FAIL on commit $(short "$out_commit"), after the plan's approval in commit $(short "$anchor2") and before these files" \
    "done-check: READY - "

  # the lock compares HEAD with the anchor only: a failing run made while
  # expected.tsv held another value, put back before HEAD, does not count
  full_project || abort_sandbox
  unforge "$f"
  printf 'case\tinputs\texpected\tsource\none\tx=1\t999\tthe owner\n' >"$f/docs/tasks/t1/expected.tsv"
  recommit "$f" 'Wrong expected'
  forge "$f" "$T" "TESTS FAIL"
  printf 'case\tinputs\texpected\tsource\none\tx=1\t2\tthe owner\n' >"$f/docs/tasks/t1/expected.tsv"
  recommit "$f" 'Expected back'
  finish "$f"
  dc "$f"
  expect "R6: a failing run on an expected value changed and changed back does not count: NOT READY" 1 \
    "done-check: lock: PASS - the plan's Tier and Paths lines and its expected.tsv are as approved in commit $(short "$anchor")" \
    "done-check: failing run: FAIL - no VALID receipt of method-tester" \
    "; not counted: 1 on a commit whose plan Tier or Paths line or expected.tsv differs from the approved one"

  # a lost failing receipt (a new clone) re-made at the commit before the
  # code, on a branch made there with git switch -c
  full_project || abort_sandbox
  unforge "$f"
  (cd "$f" && git switch -q -c redo "$tcommit")
  forge "$f" "$T" "TESTS FAIL"
  (cd "$f" && git switch -q feat && git branch -q -D redo)
  finish "$f"
  dc "$f"
  expect "R6: a failing run re-made with git switch -c at the commit before the code, an ancestor of HEAD: READY" 0 \
    "done-check: failing run: PASS - method-tester opened with TESTS FAIL on commit $(short "$tcommit")" "done-check: READY - "
fi

# the tier and the high-risk paths (M147, M146's Deep review)
if wanted_any "R6: a LIGHT plan on a high-risk path" "R6: a branch that drops a high-risk path main lists" "R6: a rename out of a high-risk path" \
  "R6: Deep review" "R6: two reviewers on a high-risk path" "R6: three reviewers, one asking for changes"; then
  f=$(floor_project) || abort_sandbox
  printf 'PRODUCT_PATHS=src\nHIGH_RISK_PATHS=src\n' >"$f/.claude/method.conf"
  recommit "$f" 'High risk'
  approve_head "$f"
  dc "$f"
  expect "R6: a LIGHT plan on a high-risk path is judged FULL: NOT READY" 1 \
    "done-check: tier: FAIL - the plan says Tier LIGHT, but 2 changed paths are high-risk: .claude/method.conf, src/a.txt (HIGH_RISK_PATHS, main's and this change's together: src; the built-in list of the files that steer the method: .claude/method.conf); judged FULL, and the plan was not made as FULL" \
    "done-check: next: plan again as FULL (Tier: FULL, with expected.tsv), ask the owner for their go again, and replace the Approved line with their new reply, with today's date and the time (Approved: YYYY-MM-DD HH:MM \"<the reply>\")" \
    "done-check: lock: FAIL - the task is FULL, but its plan had no expected.tsv" "done-check: deep review: FAIL"

  # main lists src as high-risk; the branch's own list drops it
  f=$(floor_project) || abort_sandbox
  (cd "$f" && git checkout -q main && mkdir -p .claude && printf 'PRODUCT_PATHS=src\nHIGH_RISK_PATHS=src\n' >.claude/method.conf && git add -A &&
    git commit -q -m "High-risk list" -m "$OK" && git push -q origin main 2>/dev/null && git checkout -q feat && git merge -q -s ours --no-edit main)
  amend "$f" "$OK"
  rc "$f"
  approve_head "$f"
  dc "$f"
  expect "R6: a branch that drops a high-risk path main lists, Tier LIGHT: NOT READY (judged FULL)" 1 \
    "done-check: up to date: PASS" \
    "done-check: tier: FAIL - the plan says Tier LIGHT, but 2 changed paths are high-risk: .claude/method.conf, src/a.txt (HIGH_RISK_PATHS, main's and this change's together: src; the built-in list of the files that steer the method: .claude/method.conf); judged FULL"

  # a file moved out of a high-risk folder: its old path counts
  f=$(floor_project) || abort_sandbox
  (cd "$f" && git checkout -q main && mkdir -p keys && printf 'k\n' >keys/k.txt && git add -A && git commit -q -m "Keys" -m "$OK" &&
    git push -q origin main 2>/dev/null && git checkout -q feat && git merge -q --no-edit main && mkdir -p pub && git mv keys/k.txt pub/k.txt)
  printf 'PRODUCT_PATHS=src\nHIGH_RISK_PATHS=keys\n' >"$f/.claude/method.conf"
  recommit "$f" Move
  approve_head "$f"
  dc "$f"
  expect "R6: a rename out of a high-risk path is high-risk: Tier LIGHT is NOT READY" 1 \
    "done-check: tier: FAIL - the plan says Tier LIGHT, but 2 changed paths are high-risk: .claude/method.conf, keys/k.txt (HIGH_RISK_PATHS, main's and this change's together: keys; the built-in list of the files that steer the method: .claude/method.conf)"

  # Deep review: three approving reviewers on a high-risk path
  full_project || abort_sandbox
  printf 'PRODUCT_PATHS=src\nHIGH_RISK_PATHS=src\n' >"$f/.claude/method.conf"
  recommit "$f" 'High risk'
  finish "$f"
  forge "$f" "$R" APPROVE
  dc "$f"
  expect "R6: two reviewers on a high-risk path are NOT READY" 1 \
    "done-check: tier: PASS - Tier FULL, as the plan says; 2 changed paths are high-risk: .claude/method.conf, src/a.txt (HIGH_RISK_PATHS, main's and this change's together: src; the built-in list of the files that steer the method: .claude/method.conf), so Deep review applies" \
    "done-check: deep review: FAIL - the change touches high-risk paths (.claude/method.conf, src/a.txt), so it needs three receipts of method-reviewer that opened with APPROVE on these files (tree " "reviewed from the merge base or chained back to it: 2 do" \
    "done-check: next: run method-reviewer three times on these files, launched in one message in the foreground (Deep review)" \
    "done-check: NOT READY - 2 conditions failed (deep review, verdict)"
  forge "$f" "$R" APPROVE bases=
  dc "$f"
  expect "R6: Deep review: a reviewer's approval with no base is not one of the three" 1 "done-check: deep review: FAIL" ": 2 do"
  forge "$f" "$R" APPROVE
  dc "$f"
  expect "R6: Deep review: three approving reviewers on a high-risk path are READY" 0 \
    "done-check: deep review: PASS - 3 receipts of method-reviewer opened with APPROVE on these files (tree " "the change touches high-risk paths (.claude/method.conf, src/a.txt)" \
    "done-check: rounds: PASS - 1 version reviewed since the plan's approval" "done-check: READY - "
  forge "$f" "$R" "REQUEST CHANGES"
  dc "$f"
  expect "R6: three reviewers, one asking for changes, are NOT READY" 1 \
    "done-check: reviewer: FAIL - 1 receipt of method-reviewer for these files" \
    "done-check: deep review: FAIL - the change touches high-risk paths (.claude/method.conf, src/a.txt)" ": 3 do, and 1 opened with another word (REQUEST CHANGES (VALID))"
fi

# a broken high-risk list fails closed, on main's side and on the branch's
if wanted_any "R6: HIGH_RISK_PATHS"; then
  for side in branch main; do
    for line in 'HIGH_RISK_PATHS=../src' 'HIGH_RISK_PATH=src' 'HIGH_RISK_PATHS = src' 'MUTATION_CHECKS=Not An Id' lfs; do
      f=$(floor_project) || abort_sandbox
      if [ "$line" = lfs ]; then
        text='version https://git-lfs.github.com/spec/v1\noid sha256:0000000000000000000000000000000000000000000000000000000000000000\nsize 40\n'
      else
        text="PRODUCT_PATHS=src\\n$line\\n"
      fi
      if [ "$side" = branch ]; then
        # shellcheck disable=SC2059 # the text is a printf format on purpose
        printf "$text" >"$f/.claude/method.conf"
        recommit "$f" Conf
        where='in this change'
      else
        # shellcheck disable=SC2059 # the text is a printf format on purpose
        (cd "$f" && git checkout -q main && mkdir -p .claude && printf "$text" >.claude/method.conf && git add -A &&
          git commit -q -m "Conf" -m "$OK" && git push -q origin main 2>/dev/null && git checkout -q feat && git merge -q -s ours --no-edit main)
        amend "$f" "$OK"
        rc "$f"
        where='on main'
      fi
      approve_head "$f"
      dc "$f"
      case $line in
        MUTATION_CHECKS=*)
          expect "R6: HIGH_RISK_PATHS: a problem of another key ($side side) leaves the list readable" "$code" \
            "done-check: tier: FAIL - the plan says Tier LIGHT, but 1 changed path is high-risk: .claude/method.conf (no HIGH_RISK_PATHS on main or in this change; the built-in list of the files that steer the method: .claude/method.conf)"
          ;;
        lfs)
          expect "R6: HIGH_RISK_PATHS: an unreadable method.conf ($side side, a Git LFS pointer) is NOT READY" 1 \
            "done-check: tier: FAIL - the high-risk list cannot be read: .claude/method.conf $where (" "): the file is stored as a Git LFS pointer"
          ;;
        *)
          case $line in
            *=../*) why="HIGH_RISK_PATHS: a relative path" ;;
            *_PATH=*) why="unknown key HIGH_RISK_PATH" ;;
            *) why="is not KEY=VALUE" ;;
          esac
          expect "R6: HIGH_RISK_PATHS: $line on the $side side is NOT READY" 1 \
            "done-check: tier: FAIL - the high-risk list cannot be read: .claude/method.conf $where (" ") line 2: $why"
          # (on the branch's side run-checks refuses the file too, so its next: comes first)
          [ "$side" = branch ] || expect "R6: HIGH_RISK_PATHS: $line on the main side names the fix" 1 \
            "done-check: next: fix .claude/method.conf and keep it a plain file committed in this repository (on main, that fix is a small task of its own), then run done-check again"
          ;;
      esac
    done
  done

  # an entry that names no path in the change's files protects nothing it
  # was meant to (a comment on the line, a misspelt path): it fails closed;
  # an entry whose files this change deletes still names them
  for v in 'src # money code' scr; do
    f=$(floor_project) || abort_sandbox
    printf 'PRODUCT_PATHS=src\nHIGH_RISK_PATHS=%s\n' "$v" >"$f/.claude/method.conf"
    recommit "$f" 'High risk'
    approve_head "$f"
    dc "$f"
    expect "R6: HIGH_RISK_PATHS: an entry that names no path ($v) is NOT READY" 1 \
      "done-check: tier: FAIL - the high-risk list cannot be read: .claude/method.conf in this change (" \
      "): HIGH_RISK_PATHS adds an entry that names no path in its files: $v (the path may be misspelt or deleted, or the line may hold a comment, which the file does not allow)"
  done
  f=$(floor_project) || abort_sandbox
  (cd "$f" && git checkout -q main && mkdir -p keys && printf 'k\n' >keys/k.txt && git add -A && git commit -q -m "Keys" -m "$OK" &&
    git push -q origin main 2>/dev/null && git checkout -q feat && git merge -q --no-edit main && git rm -q -r keys)
  printf 'PRODUCT_PATHS=src\nHIGH_RISK_PATHS=keys\n' >"$f/.claude/method.conf"
  recommit "$f" Delete
  approve_head "$f"
  dc "$f"
  expect "R6: HIGH_RISK_PATHS: an entry whose files this change deletes is read: Tier LIGHT is NOT READY (judged FULL)" 1 \
    "done-check: tier: FAIL - the plan says Tier LIGHT, but 2 changed paths are high-risk: .claude/method.conf, keys/k.txt (HIGH_RISK_PATHS, main's and this change's together: keys; the built-in list of the files that steer the method: .claude/method.conf); judged FULL"

  # main's .claude or method.conf stored so that it cannot be read as a list
  for kind in file link filter; do
    f=$(floor_project) || abort_sandbox
    (cd "$f" && git checkout -q main && case $kind in
      file) rm -r .claude && printf 'x\n' >.claude ;;
      link) printf 'PRODUCT_PATHS=src\n' >.claude/other.conf && rm .claude/method.conf && ln -s other.conf .claude/method.conf ;;
      filter) mkdir -p .claude && printf 'PRODUCT_PATHS=src\nHIGH_RISK_PATHS=src\n' >.claude/method.conf && printf '.claude/method.conf filter=x\n' >.gitattributes ;;
    esac && git add -A && git commit -q -m "Conf" -m "$OK" && git push -q origin main 2>/dev/null && git checkout -q feat && git merge -q -s ours --no-edit main)
    amend "$f" "$OK"
    rc "$f"
    approve_head "$f"
    dc "$f"
    case $kind in
      file) why='.claude is not a folder' ;;
      link) why='not a regular file in the commit' ;;
      *)
        # (git before 2.42 cannot read a commit's own attributes, so it names the file)
        case $out in
          *"gives the file a filter"*) why="the commit's .gitattributes gives the file a filter" ;;
          *) why='.gitattributes names a filter, an encoding or a macro' ;;
        esac
        ;;
    esac
    expect "R6: HIGH_RISK_PATHS: main's method.conf unreadable ($kind) is NOT READY" 1 \
      "done-check: tier: FAIL - the high-risk list cannot be read: .claude/method.conf on main (" "): $why"
  done
fi


# expected.tsv that is not a regular file at the anchor (a symbolic link
# leads to values the lock cannot see change; a submodule or a folder holds
# no values): the lock fails, naming it, and a failing run there does not
# count
if wanted_any "R6: the lock: expected.tsv as" "R6: the failing run: expected.tsv as"; then
  for kind in 'a symbolic link' 'a submodule' 'a folder'; do
    fl_p=$(new_project) || abort_sandbox
    f="$fl_p/w"
    add_task "$f" t1 FULL 'Approved: 2026-11-23 "approve t1 as FULL"'
    printf 'case\tinputs\texpected\tsource\none\tx=1\t2\tthe owner\n' >"$f/docs/values.tsv"
    xp="$f/docs/tasks/t1/expected.tsv"
    case $kind in
      'a symbolic link')
        if ! ln -s ../../values.tsv "$xp" 2>/dev/null || ! [ -L "$xp" ]; then
          skip "expected.tsv as a symbolic link: this system cannot make symlinks"
          continue
        fi
        ;;
      'a submodule') mkdir -p "$xp" && (cd "$f" && git update-index --add --cacheinfo "160000,$(git rev-parse HEAD),docs/tasks/t1/expected.tsv") ;;
      *) mkdir -p "$xp" && cp "$f/docs/values.tsv" "$xp/values.tsv" ;;
    esac
    (cd "$f" && git add -A)
    msg "$f" 'Full\n\n%s\n' "$OPEN"
    anchor=$(cd "$f" && git rev-parse HEAD)
    mkdir -p "$f/tests" && printf 'case one\n' >"$f/tests/cases.txt"
    (cd "$f" && git add -A)
    msg "$f" 'Tests\n\n%s\n' "$OPEN"
    forge "$f" "$T" "TESTS FAIL"
    # the value the link leads to changes with the code
    printf 'case\tinputs\texpected\tsource\none\tx=1\t999\tthe owner\n' >"$f/docs/values.tsv"
    printf 'x = 2\n' >"$f/src/a.txt"
    recommit "$f" Code
    finish "$f"
    dc "$f"
    expect "R6: the lock: expected.tsv as $kind when the plan was approved is NOT READY" 1 \
      "done-check: lock: FAIL - docs/tasks/t1/expected.tsv is $kind when the plan was approved in commit $(short "$anchor"), so the values the lock compares are not the ones read through it: expected.tsv must be a regular file" \
      "done-check: next: make docs/tasks/t1/expected.tsv a regular file, and ask the owner for their go again"
    expect "R6: the failing run: expected.tsv as $kind at the anchor does not count: NOT READY" 1 \
      "done-check: failing run: FAIL - no VALID receipt of method-tester" \
      "; not counted: 1 on a commit where expected.tsv, or the approved one, is not a regular file"
  done
fi

# a re-approval on the same day: the time after the date makes a new line,
# so a new anchor: the lock compares with it, and the failing run follows it
if wanted_any "R6: a same-day re-approval with a time"; then
  fl_p=$(new_project) || abort_sandbox
  f="$fl_p/w"
  add_task "$f" t1 FULL 'Approved: 2026-11-22 09:15 "approve t1"'
  printf 'case\tinputs\texpected\tsource\none\tx=1\t2\tthe owner\n' >"$f/docs/tasks/t1/expected.tsv"
  (cd "$f" && git add -A)
  msg "$f" 'Full\n\n%s\n' "$OPEN"
  mkdir -p "$f/tests" && printf 'case one\n' >"$f/tests/cases.txt"
  (cd "$f" && git add -A)
  msg "$f" 'Tests\n\n%s\n' "$OPEN"
  forge "$f" "$T" "TESTS FAIL"
  printf 'x = 2\n' >"$f/src/a.txt"
  recommit "$f" Code
  # a wrong expected value found, the owner's new reply the same day
  printf 'case\tinputs\texpected\tsource\none\tx=1\t3\tthe owner\n' >"$f/docs/tasks/t1/expected.tsv"
  add_task "$f" t1 FULL 'Approved: 2026-11-22 16:30 "approve t1"'
  recommit "$f" Reapproved
  anchor2=$(cd "$f" && git rev-parse HEAD)
  finish "$f"
  dc "$f"
  expect "R6: a same-day re-approval with a time moves the lock's anchor, and the failing run before it does not count" 1 \
    "done-check: plan: PASS - task t1 (docs/tasks/t1/plan.md), Tier FULL; approved 2026-11-22 16:30 \"approve t1\" in commit $(short "$anchor2")" \
    "done-check: lock: PASS - the plan's Tier and Paths lines and its expected.tsv are as approved in commit $(short "$anchor2")" \
    "done-check: failing run: FAIL - no VALID receipt of method-tester that opened with TESTS FAIL on a commit from the plan's approval (commit $(short "$anchor2"))" \
    "1 on a commit outside this branch's history from the approval to HEAD"
  printf 'x = 1\n' >"$f/src/a.txt"
  recommit "$f" 'Code out'
  out_commit=$(cd "$f" && git rev-parse HEAD)
  forge "$f" "$T" "TESTS FAIL"
  printf 'x = 2\n' >"$f/src/a.txt"
  recommit "$f" 'Code back'
  finish "$f"
  dc "$f"
  expect "R6: a same-day re-approval with a time: the failing run after the new anchor counts, READY" 0 \
    "done-check: failing run: PASS - method-tester opened with TESTS FAIL on commit $(short "$out_commit"), after the plan's approval in commit $(short "$anchor2") and before these files" \
    "done-check: READY - "
fi

# main lists a path that a merged change deleted: a plain path that an
# earlier commit of main had blocks no later branch that keeps the list as
# it is, and the tier line says to drop it; an entry on main's list that
# names no path main ever had (a comment on the line, a misspelt path)
# still fails closed
if wanted_any "R6: HIGH_RISK_PATHS: an entry main lists"; then
  f=$(floor_project) || abort_sandbox
  (cd "$f" && git checkout -q main && mkdir -p .claude keys && printf 'PRODUCT_PATHS=src\nHIGH_RISK_PATHS=keys\n' >.claude/method.conf &&
    printf 'k\n' >keys/k.txt && git add -A && git commit -q -m "Keys" -m "$OK" && git rm -q -r keys &&
    git commit -q -m "Keys deleted" -m "$OK" && git push -q origin main 2>/dev/null && git checkout -q feat && git merge -q -s ours --no-edit main)
  printf 'PRODUCT_PATHS=src\nHIGH_RISK_PATHS=keys\n' >"$f/.claude/method.conf"
  recommit "$f" 'Main list'
  approve_head "$f"
  dc "$f"
  expect "R6: HIGH_RISK_PATHS: an entry main lists whose path a merged change deleted blocks no other branch: READY" 0 \
    "done-check: tier: PASS - Tier LIGHT, as the plan says: no changed path is high-risk (HIGH_RISK_PATHS, main's and this change's together: keys); main's list names keys, which is in none of these files but main had in an earlier commit: a merged change deleted it; drop it from HIGH_RISK_PATHS on main (a small task of its own)" \
    "done-check: READY - "
  # ('keys # old': main once had a file of that name, but an entry with a
  # space or a # reads as a comment on the line)
  for v in 'src # money code' scr 'keys # old'; do
    f=$(floor_project) || abort_sandbox
    [ "$v" != 'keys # old' ] || (cd "$f" && git checkout -q main && printf 'k\n' >"$v" && git add -A && git commit -q -m Old -m "$OK" &&
      git rm -q "$v" && git commit -q -m "Old deleted" -m "$OK" && git checkout -q feat)
    (cd "$f" && git checkout -q main && mkdir -p .claude && printf 'PRODUCT_PATHS=src\nHIGH_RISK_PATHS=%s\n' "$v" >.claude/method.conf &&
      git add -A && git commit -q -m "High-risk list" -m "$OK" && git push -q origin main 2>/dev/null && git checkout -q feat &&
      git merge -q -s ours --no-edit main)
    amend "$f" "$OK"
    rc "$f"
    approve_head "$f"
    dc "$f"
    case "$v" in
      scr) name="R6: HIGH_RISK_PATHS: an entry main lists that names no path main ever had ($v), a LIGHT change on src: NOT READY" ;;
      'keys # old') name="R6: HIGH_RISK_PATHS: an entry main lists with a # and spaces, though main once had that path ($v): NOT READY" ;;
      *) name="R6: HIGH_RISK_PATHS: an entry main lists with a comment on its line ($v), a LIGHT change on src: NOT READY" ;;
    esac
    expect "$name" 1 \
      "done-check: tier: FAIL - the high-risk list cannot be read: .claude/method.conf on main (" \
      "): HIGH_RISK_PATHS has an entry that names no path in these files and is not a plain path (no space, no #) that main had in an earlier commit: $v (the path may be misspelt, or the line may hold a comment, which the file does not allow); a broken setting is not read as a shorter list"
  done
  # a branch behind a main commit that adds a listed path: main's tip has
  # the path, so nothing deleted it and the tier line must not say to drop it
  f=$(floor_project) || abort_sandbox
  (cd "$f" && git checkout -q main && mkdir -p .claude vault && printf 'PRODUCT_PATHS=src\nHIGH_RISK_PATHS=vault\n' >.claude/method.conf &&
    printf 'v\n' >vault/x.txt && git add -A && git commit -q -m "Vault" -m "$OK" && git push -q origin main 2>/dev/null && git checkout -q feat)
  approve_head "$f"
  dc "$f"
  expect "R6: HIGH_RISK_PATHS: an entry main lists on a path main's tip has, on a branch behind it: NOT READY (not up to date)" 1 \
    "done-check: tier: PASS - Tier LIGHT"
  lacks "R6: HIGH_RISK_PATHS: an entry main lists on a path main's tip has is not called deleted" "drop it from HIGH_RISK_PATHS"
fi

# the built-in list of the files that steer the method (M153; step 7 plan,
# S12): high-risk whatever HIGH_RISK_PATHS says, added after the check that
# each entry names a path
STEER='the built-in list of the files that steer the method'
if wanted_any "M153: a LIGHT plan touching" "M153: three approving reviewers"; then
  for what in checks pack settings; do
    f=$(floor_project) || abort_sandbox
    slash=/
    if [ "$what" = checks ]; then
      printf '# a note on the checks\n' >>"$f/checks/project.tsv"
      p=checks/project.tsv
      e=checks
    elif [ "$what" = settings ]; then
      # a profile change, as setup-write makes it
      printf '{"model":"claude-sonnet-5-5","effortLevel":"medium"}\n' >"$f/.claude/settings.json"
      p=.claude/settings.json
      e=.claude/settings.json
      slash=
    else
      mkdir -p "$f/.claude/rules/pack" && printf '# Rules\n\nAlways keep the ledger balanced. Why: a test case.\n' >"$f/.claude/rules/pack/rules.md"
      p=.claude/rules/pack/rules.md
      e=.claude/rules/pack
    fi
    recommit "$f" Steer
    approve_head "$f"
    dc "$f"
    expect "M153: a LIGHT plan touching ${e}$slash is judged FULL: NOT READY" 1 \
      "done-check: tier: FAIL - the plan says Tier LIGHT, but 1 changed path is high-risk: $p (no HIGH_RISK_PATHS on main or in this change; $STEER: $e); judged FULL, and the plan was not made as FULL" \
      "done-check: deep review: FAIL - the change touches high-risk paths ($p)"
  done
  # the full route: three approving reviewers
  full_project || abort_sandbox
  printf '# a note on the checks\n' >>"$f/checks/project.tsv"
  mkdir -p "$f/.claude/rules/pack" && printf '# Rules\n\nAlways keep the ledger balanced. Why: a test case.\n' >"$f/.claude/rules/pack/rules.md"
  recommit "$f" Steer
  finish "$f"
  forge "$f" "$R" APPROVE
  dc "$f"
  expect "M153: two reviewers on a change to checks/ and .claude/rules/pack/ are NOT READY" 1 \
    "done-check: tier: PASS - Tier FULL, as the plan says; 2 changed paths are high-risk: .claude/rules/pack/rules.md, checks/project.tsv (no HIGH_RISK_PATHS on main or in this change; $STEER: .claude/rules/pack, checks), so Deep review applies" \
    "done-check: deep review: FAIL - the change touches high-risk paths (.claude/rules/pack/rules.md, checks/project.tsv)" ": 2 do"
  forge "$f" "$R" APPROVE
  dc "$f"
  expect "M153: three approving reviewers on a change to checks/ and .claude/rules/pack/ are READY" 0 \
    "done-check: deep review: PASS - 3 receipts of method-reviewer opened with APPROVE on these files (tree " \
    "the change touches high-risk paths (.claude/rules/pack/rules.md, checks/project.tsv)" "done-check: READY - "
fi

if wanted_any "M153: a project with none of the built-in paths" "M153: a change to the method's own skill"; then
  # main holds none of the files on the built-in list
  b=$(new_sandbox_dir) || abort_sandbox
  repos="$repos $b"
  (cd "$b" && git init -q --bare remote.git && git init -q w && cd w && printf '*.marker\n' >.gitignore && printf 'hello\n' >README &&
    git add -A && git commit -q -m "Start" -m "Review-Verdict: not-required - the first commit" && git remote add origin ../remote.git &&
    git push -q -u origin main 2>/dev/null && git remote set-head origin main && git checkout -q -b feat && mkdir -p src &&
    printf 'x = 1\n' >src/a.txt && add_task . && git add -A && git commit -q -m "Add the feature" -m "$OPEN") || abort_sandbox
  f="$b/w"
  rc "$f"
  amend "$f" "$OK"
  approve_head "$f"
  dc "$f"
  # (without checks/ and .claude/method.conf run-checks skips two checks, so
  # the checks condition fails; the tier is what this case asks about)
  expect "M153: a project with none of the built-in paths has no tier problem" 1 \
    "done-check: tier: PASS - Tier LIGHT, as the plan says: no changed path is high-risk (no HIGH_RISK_PATHS on main or in this change)" \
    "done-check: NOT READY - 1 condition failed (checks);"
  # main holds checks/ and .claude/method.conf only, and the change touches
  # neither: the absent entries are no problem
  f=$(floor_project) || abort_sandbox
  dca "$f"
  expect "M153: a project with none of the built-in paths but checks/ and .claude/method.conf, untouched: READY" 0 \
    "done-check: tier: PASS - Tier LIGHT, as the plan says: no changed path is high-risk (no HIGH_RISK_PATHS on main or in this change)" \
    "done-check: READY - "
  # the method's own skills are kept by G6 and method-files, not by this
  # list (here method-files fails, as the skill is not in a method.lock)
  f=$(floor_project) || abort_sandbox
  mkdir -p "$f/.claude/skills/method-start" && printf -- '---\nname: method-start\n---\nStart.\n' >"$f/.claude/skills/method-start/SKILL.md"
  recommit "$f" Skill
  approve_head "$f"
  dc "$f"
  expect "M153: a change to the method's own skill (.claude/skills/method-start/) is not high-risk" 1 \
    "done-check: tier: PASS - Tier LIGHT, as the plan says: no changed path is high-risk (no HIGH_RISK_PATHS on main or in this change)" \
    "done-check: NOT READY - 1 condition failed (checks);"
fi

# (the conditions before step 6b follow; a run that keeps only some cases
# ends here)
if [ -n "${TEST_ONLY:-}" ]; then
  drop_all
  export HOME="$saved_home"
  drop_sandbox "$work"
  echo "tests: done-check: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
  [ "$tests_fail" -eq 0 ]
  exit
fi

# --- READY ---
p=$(new_project) || abort_sandbox
w="$p/w"
rc "$w"
rc_ok "setup: run-checks passes on the feature"
amend "$w" "$OK"
head=$(cd "$w" && git rev-parse HEAD)
h7=$(cd "$w" && git rev-parse --short=7 HEAD)
main=$(cd "$w" && git rev-parse origin/main)
t7=$(cd "$w" && git rev-parse --short=7 'HEAD^{tree}')
approve_head "$w"
before=$(manifest "$w")
dc "$w"
after=$(manifest "$w")
expect "READY after run-checks and an amend that only adds the verdict line, with no new run (exit 0)" 0 \
  "done-check: files: PASS - the tracked files on disk are commit $h7, byte for byte; nothing untracked that git lists outside its ignore rules" \
  "done-check: up to date: PASS - main is refs/remotes/origin/main ${main%"${main#???????}"} (as of the last fetch; done-check does not fetch)" \
  "done-check: checks: PASS - local run-checks log of " "the same files as HEAD; a local claim: a record written in this clone, not proof" \
  "done-check: elsewhere: PASS - every check in checks/*.tsv runs here (1)" \
  "done-check: plan: PASS - task t1 (docs/tasks/t1/plan.md), Tier LIGHT; approved 2026-11-22 \"approve t1\" in commit $h7" \
  "done-check: reviewer: PASS - method-reviewer opened with APPROVE on these files (tree $t7), VALID, reviewed from the merge base ${main%"${main#???????}"}" \
  "done-check: security checker: PASS - method-security-checker opened with APPROVE on these files (tree $t7), VALID, reviewed from the merge base" \
  "done-check: rounds: PASS - 1 version reviewed since the plan's approval, of at most 3" \
  "done-check: verdict: PASS - approve, as the receipts give it (commit $h7)" \
  "done-check: verdicts start: PASS - VERDICTS_FROM is unset both on main and in this change" \
  "done-check: history - $h7: method-reviewer APPROVE, method-security-checker APPROVE" \
  "done-check: READY - $head is up to date with refs/remotes/origin/main $main; verdict approve from the receipts (method-reviewer and method-security-checker on tree $t7, task t1)"
lacks "READY has no next: line" "done-check: next:"
mkdir -p "$work/plib/Digest"
printf 'die "a module from PERL5LIB was loaded\\n";\n1;\n' >"$work/plib/Digest/SHA.pm"
dca "$w" PERL5LIB="$work/plib"
expect "modules on the caller's PERL5LIB are not loaded" 0 "done-check: READY - "
if [ "$before" = "$after" ]; then pass "done-check changes no file, .git and the index included"; else fail "done-check changes no file" "$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after"))"; fi
if [ "$(printf '%s\n' "$out" | sed -n '$p')" = "$(printf '%s\n' "$out" | grep '^done-check: READY')" ]; then pass "READY is the last line"; else fail "READY is the last line" "$out"; fi

printf 'x = 2\n' >"$w/src/a.txt"
(cd "$w" && git add -A)
msg "$w" 'More\n\n%s\n' "$OPEN"
rc "$w"
msg "$w" 'Verdict\n\n%s\n' "$OK"
dca "$w"
expect "READY with an empty verdict commit on top of the run's commit" 0 "the same files as HEAD" "done-check: READY - "

# --- files ---
echo more >>"$w/src/a.txt"
dca "$w"
expect "an edit fails files, with the next step (exit 1)" 1 \
  "done-check: files: FAIL - 1 path is not commit" "changed or staged (git status lists them): src/a.txt" \
  "done-check: next: commit, restore or remove them" "done-check: NOT READY - 1 condition failed (files); $(cd "$w" && git rev-parse HEAD) against refs/remotes/origin/main"
(cd "$w" && git checkout -q -- src/a.txt)
: >"$w/src/new.txt"
dca "$w"
expect "an untracked file fails files" 1 "untracked, and not ignored by git: src/new.txt"
rm -f "$w/src/new.txt"
: >"$w/flaky2.marker"
dca "$w"
expect "a file git ignores does not fail files" 0 "done-check: READY - "
rm -f "$w/flaky2.marker"
# core.ignoreCase=true (as copied from a Mac or Windows) would hide an
# untracked file whose name differs from a tracked one only by case
(cd "$w" && git config core.ignoreCase true)
: >"$w/src/A.txt"
if [ -z "$(cd "$w" && git status --porcelain)" ]; then pass "setup: git status itself hides the case twin"; else fail "setup: git status itself hides the case twin" "$(cd "$w" && git status --porcelain)"; fi
dca "$w"
expect "an untracked case twin of a tracked file fails files under core.ignoreCase=true" 1 "untracked, and not ignored by git: src/A.txt"
rm -f "$w/src/A.txt"
# where the working tree's file system tells case apart, ignore patterns
# match case exactly; where it folds case (simulated: the top folder's name
# with its case flipped, W, is the same folder), git's own core.ignoreCase
# stays, so a pattern of another case still ignores a file
printf '*.LOG\n' >>"$w/.git/info/exclude"
: >"$w/src/debug.log"
dca "$w"
expect "on a file system that tells case apart, *.LOG does not ignore debug.log" 1 "untracked, and not ignored by git: src/debug.log"
mkdir "$p/W"
dca "$w"
expect "a separate folder W next to w is not the same folder, so the pin stays" 1 "untracked, and not ignored by git: src/debug.log"
rmdir "$p/W"
ln -s w "$p/W"
dca "$w"
expect "on one that folds case, git's own core.ignoreCase stays, so *.LOG ignores debug.log as git does" 0 "done-check: READY - "
rm -f "$p/W"
# a linked worktree is probed by its own top folder
(cd "$w" && git worktree add -q "$p/wt" 2>/dev/null)
: >"$p/wt/src/debug.log"
dca "$p/wt"
expect "in a linked worktree on a file system that tells case apart, *.LOG does not ignore debug.log" 1 \
  "untracked, and not ignored by git: src/debug.log"
ln -s wt "$p/WT"
dca "$p/wt"
expect "in a linked worktree on one that folds case, *.LOG ignores debug.log" 1 "done-check: files: PASS"
rm -f "$p/WT"
(cd "$w" && git worktree remove --force "$p/wt" && git branch -q -D wt)
rm -f "$w/src/debug.log"
perl -ni -e 'print unless /^\*\.LOG$/' "$w/.git/info/exclude"
(cd "$w" && git config --unset core.ignoreCase)

# a project with a committed line-end rule and a script
printf '*.sh text eol=lf\n' >"$w/.gitattributes"
printf '#!/bin/sh\nset -e\nfalse\necho reached\n' >"$w/t.sh"
printf '@echo off\necho hi\n' >"$w/run.bat"
(cd "$w" && git add -A)
msg "$w" 'Scripts\n\n%s\n' "$OK"
rc "$w"
rc_ok "setup: run-checks passes with a committed eol=lf rule"
dca "$w"
expect "a committed line-end rule is READY" 0 "done-check: READY - "
perl -pi -e 's/\n/\r\n/ if $. == 2' "$w/t.sh"
dca "$w"
expect "one CR added to one line under eol=lf fails files, though git status sees nothing" 1 \
  "with CRs before line ends that the commit's .gitattributes does not ask for" "t.sh"
rm -f "$w/t.sh" && (cd "$w" && git checkout -q -- t.sh)
printf 'run.bat text eol=crlf\n' >"$w/.git/info/attributes"
rm -f "$w/run.bat" && (cd "$w" && git checkout -q -- run.bat)
dca "$w"
expect "a CRLF that only .git/info/attributes asks for fails files, and says why" 1 \
  "with CRs before line ends that the commit's .gitattributes does not ask for" "run.bat" \
  ".git/info/attributes holds rules, so a conversion cannot be told from an edit"
rm -f "$w/.git/info/attributes" "$w/run.bat" && (cd "$w" && git checkout -q -- run.bat)
(cd "$w" && git config core.autocrlf true)
perl -pi -e 's/\n/\r\n/' "$w/t.sh"
(cd "$w" && git add t.sh 2>/dev/null)
st_short=$(cd "$w" && git status --porcelain)
dca "$w"
if [ -z "$st_short" ]; then pass "setup: core.autocrlf hides a CRLF set -e script from git status"; else fail "setup: core.autocrlf hides the CRLF" "$st_short"; fi
expect "a set -e script made CRLF under a local core.autocrlf and added fails files" 1 \
  "with CRs before line ends that the commit's .gitattributes does not ask for" "t.sh"
(cd "$w" && git config --unset core.autocrlf)
rm -f "$w/t.sh" && (cd "$w" && git checkout -q -- t.sh && git reset -q)
dca "$w"
expect "setup: back to READY" 0 "done-check: READY - "

# a committed eol=crlf file and an ident file, in a fresh clone on Linux
printf '*.sh text eol=lf\n*.bat text eol=crlf\n*.txt text\nid.txt ident\n*.dat filter=x\n' >"$w/.gitattributes"
printf 'raw\n' >"$w/data.dat"
# shellcheck disable=SC2016 # $Id$ is meant literally
printf 'version $Id$\n' >"$w/id.txt"
(cd "$w" && git add -A 2>/dev/null)
msg "$w" 'Line ends\n\n%s\n' "$OK"
(cd "$w" && git push -q origin feat 2>/dev/null)
(cd "$p" && git clone -q -b feat remote.git fresh 2>/dev/null)
f="$p/fresh"
if grep -q "$(printf '\r')" "$f/run.bat" && grep -q 'Id: ' "$f/id.txt"; then pass "setup: the fresh clone has CRLF in run.bat and an expanded \$Id\$"; else fail "setup: the clone's checkout converted"; fi
rc "$f"
rc_ok "run-checks passes in a fresh clone with committed CRLF and ident files"
if grep -q '^tree at start clean$' "$f/$(newest_log "$f")"; then pass "its log says the tree was clean at the start"; else fail "its log says the tree was clean at the start" "$(cat "$f/$(newest_log "$f")")"; fi
rc "$f" CI=true
rc_ok "the same with CI=true"
if grep -q '^tree at start clean$' "$f/$(newest_log "$f")" && grep -q '^where CI$' "$f/$(newest_log "$f")"; then pass "the CI log says clean too"; else fail "the CI log says clean too" "$(cat "$f/$(newest_log "$f")")"; fi
dca "$f"
expect "a fresh clone with files the commit's .gitattributes converts is READY" 0 \
  "done-check: files: PASS - the tracked files on disk are commit" "2 of them as the commit's .gitattributes asks" "done-check: READY - "
dca "$f" CI=true
expect "and READY in CI from the CI log" 0 "done-check: checks: PASS - CI run-checks log of " "done-check: READY - "
# conversions are accepted only from the commit's own attributes, and only
# when git can be told to read nothing else
realgit=$(command -v git)
mkdir -p "$work/oldgit"
# shellcheck disable=SC2016 # the $@ is for the script being written
printf '#!/bin/sh\nfor a in "$@"; do\n  if [ "$a" = version ]; then echo "git version 2.41.0"; exit 0; fi\ndone\nexec %s "$@"\n' "$realgit" >"$work/oldgit/git"
chmod +x "$work/oldgit/git"
dca "$f" PATH="$work/oldgit:$PATH"
expect "with git older than 2.42 no conversion is accepted, and done-check says why" 1 "done-check: files: FAIL" "run.bat" \
  "git 2.42 or later is needed to tell a conversion the commit asks for from an edit"
printf '# only a comment\n\n' >"$f/.git/info/attributes"
dca "$f"
expect "a .git/info/attributes with only comments and blank lines does not stop the conversions" 0 "done-check: READY - "
rm -f "$f/.git/info/attributes"
(cd "$f" && git config core.eol crlf && rm -f src/a.txt && git checkout -q -- src/a.txt 2>/dev/null)
dca "$f"
expect "a CRLF that only this machine's core.eol writes is a change" 1 "with CRs before line ends" "src/a.txt"
(cd "$f" && git config --unset core.eol && rm -f src/a.txt && git checkout -q -- src/a.txt)
printf 'a.txt text eol=crlf\n' >"$work/attrs"
(cd "$f" && git config core.attributesFile "$work/attrs" && rm -f src/a.txt && git checkout -q -- src/a.txt 2>/dev/null)
dca "$f"
expect "a CRLF that only a personal attributes file asks for is a change" 1 "with CRs before line ends" "src/a.txt"
(cd "$f" && git config --unset core.attributesFile && rm -f src/a.txt && git checkout -q -- src/a.txt)
printf 'a.txt text eol=crlf\n' >"$f/src/.gitattributes"
printf 'src/.gitattributes\n' >>"$f/.git/info/exclude"
(cd "$f" && rm -f src/a.txt && git checkout -q -- src/a.txt 2>/dev/null)
dca "$f"
expect "a CRLF that only an ignored .gitattributes on disk asks for is a change" 1 "with CRs before line ends" "src/a.txt"
rm -f "$f/src/.gitattributes" "$f/src/a.txt" && (cd "$f" && git checkout -q -- src/a.txt)
(cd "$f" && git config filter.x.smudge "touch $work/smudge-ran; cat")
echo edited >>"$f/data.dat"
dca "$f"
expect "a file under a filter that differs is a change" 1 "done-check: files: FAIL" "data.dat"
if [ -e "$work/smudge-ran" ]; then fail "the filter's program never runs"; else pass "the filter's program never runs"; fi
(cd "$f" && git config --unset filter.x.smudge && git checkout -q -- data.dat)
dca "$f"
expect "setup: the fresh clone is READY again" 0 "done-check: READY - "
perl -pi -e 's/\r\n/\n/ if $. == 1' "$f/run.bat"
(cd "$f" && git update-index -q --refresh 2>/dev/null)
dca "$f"
expect "a CR missing where the commit's eol=crlf rule asks for one is named for what it is, with the fix" 1 \
  "with LF line ends where the commit's .gitattributes asks for CRLF: run.bat" \
  "delete the file and check it out again (rm FILE && git checkout -- FILE)"
(cd "$f" && git add run.bat)
if [ -z "$(cd "$f" && git status --porcelain)" ]; then pass "setup: once the file is added, git status shows nothing"; else fail "setup: once the file is added, git status shows nothing" "$(cd "$f" && git status --porcelain)"; fi
dca "$f"
expect "and once it is added it is still named" 1 "with LF line ends where the commit's .gitattributes asks for CRLF: run.bat"
(cd "$f" && git checkout -q -- run.bat)
dca "$f"
expect "setup: git checkout alone leaves it as it is" 1 "with LF line ends where the commit's .gitattributes asks for CRLF: run.bat"
rm -f "$f/run.bat" && (cd "$f" && git checkout -q -- run.bat)
dca "$f"
expect "following the advice makes it the commit again" 0 "done-check: READY - "

# a submodule moved after the run
s="$p/sub"
(git init -q "$s" && cd "$s" && echo one >s.txt && git add -A && git commit -q -m one && echo two >s.txt && git commit -q -am two)
(cd "$w" && git submodule add -q "$s" sub 2>/dev/null)
(cd "$w" && git add -A)
msg "$w" 'Submodule\n\n%s\n' "$OK"
rc "$w"
dca "$w"
expect "setup: READY with a submodule" 0 "done-check: READY - "
(cd "$w/sub" && git checkout -q HEAD~1)
dca "$w"
expect "a submodule moved after the run fails files" 1 "done-check: files: FAIL" "sub"
(cd "$w/sub" && git checkout -q -)
# inside a submodule too: a CR its own core.autocrlf hides, and an edit its
# own filter hides (the filter never runs)
(cd "$w/sub" && git config core.autocrlf true && perl -pi -e 's/\n/\r\n/' s.txt && git add s.txt 2>/dev/null)
dca "$w"
expect "a CR inside a submodule, hidden by the submodule's own core.autocrlf, fails files" 1 \
  "with CRs before line ends that the commit's .gitattributes does not ask for" "sub/s.txt"
(cd "$w/sub" && git config --unset core.autocrlf && rm -f s.txt && git checkout -q -- s.txt && git reset -q)
sgd=$(cd "$w/sub" && git rev-parse --git-dir)
case "$sgd" in /*) ;; *) sgd="$w/sub/$sgd" ;; esac
mkdir -p "$sgd/info"
printf '* filter=x\n' >"$sgd/info/attributes"
(cd "$w/sub" && git config filter.x.clean "touch $work/subfilter-ran; git cat-file blob HEAD:%f" && echo edited >s.txt && git add s.txt && touch -t 202001010000 s.txt)
rm -f "$work/subfilter-ran"
dca "$w"
expect "an edit inside a submodule, hidden by the submodule's own filter, fails files" 1 "done-check: files: FAIL" "sub/s.txt"
if [ -e "$work/subfilter-ran" ]; then fail "and the submodule's filter never runs"; else pass "and the submodule's filter never runs"; fi
rm -f "$sgd/info/attributes"
(cd "$w/sub" && git config --unset filter.x.clean && git checkout -q -- s.txt && git reset -q)
dca "$w"
expect "setup: READY again with the submodule as committed" 0 "done-check: READY - "
# a submodule whose recorded commit is not in it cannot be compared
nothere=$(cd "$p/sub" && git commit-tree "$(git rev-parse "HEAD^{tree}")" -p HEAD -m "Elsewhere")
if [ -n "$nothere" ] && (cd "$w" && git update-index --cacheinfo "160000,$nothere,sub" && git commit -q -m "Point sub elsewhere" -m "$OK"); then
  pass "setup: the commit records a submodule commit that is not in the submodule"
else
  fail "setup: the commit records a submodule commit that is not in the submodule"
fi
dca "$w"
expect "a submodule whose recorded commit is not in it fails files, saying it cannot be compared" 1 "done-check: files: FAIL" "submodules that cannot be compared" "sub"
(cd "$w" && git reset -q --hard HEAD~1)
# an untracked file inside a submodule that hides untracked files from its
# own git status still counts
(cd "$w/sub" && git config status.showUntrackedFiles no)
: >"$w/sub/new.txt"
dca "$w"
expect "an untracked file inside a submodule set to hide untracked files fails files" 1 "done-check: files: FAIL" "sub"
rm -f "$w/sub/new.txt"
(cd "$w/sub" && git config --unset status.showUntrackedFiles)
# a filter set inside a submodule whose .git points at another folder never
# runs either
sgd=$(cd "$w/sub" && git rev-parse --absolute-git-dir)
mkdir -p "$work/elsewhere" "$sgd/info"
# the same size as the committed "two", so git must read it, through the filter
printf 'one\n' >"$work/elsewhere/s.txt"
touch -t 202001010000 "$work/elsewhere/s.txt"
printf '* filter=x\n' >"$sgd/info/attributes"
git --git-dir="$sgd" config filter.x.clean "touch $work/subfilter2-ran; cat"
git --git-dir="$sgd" config core.worktree "$work/elsewhere"
rm -f "$work/subfilter2-ran"
dca "$w"
expect "a submodule whose .git points at another folder fails files" 1 "done-check: files: FAIL" "sub"
if [ -e "$work/subfilter2-ran" ]; then fail "and its filter never runs"; else pass "and its filter never runs"; fi
git --git-dir="$sgd" config --unset core.worktree
git --git-dir="$sgd" config --unset filter.x.clean
rm -f "$sgd/info/attributes"
dca "$w"
expect "setup: READY again after the submodule's .git is set back" 0 "done-check: READY - "

# --- up to date (M108) ---
(cd "$p" && git clone -q remote.git other 2>/dev/null && cd other && echo later >>README && git commit -q -am "Later" -m "$OK" && git push -q origin main 2>/dev/null)
(cd "$w" && git fetch -q origin)
dca "$w"
expect "main moved on: up to date fails, with the whole next step" 1 \
  "done-check: up to date: FAIL - refs/remotes/origin/main has 1 commit this branch does not (as of the last fetch)" \
  "done-check: next: merge refs/remotes/origin/main into this branch, run the checks, have the merged version reviewed, and end the merge commit with its own verdict line"
(cd "$w" && git merge -q --no-edit origin/main 2>/dev/null)
rc "$w"
dca "$w"
expect "a merge of main with no verdict line fails the verdict, saying why" 1 "done-check: up to date: PASS" \
  "done-check: verdict: FAIL - the head commit merges" "so the merged version needs its own"
amend "$w" "$OK"
dca "$w"
expect "the same merge with an approving line is READY" 0 "done-check: READY - "
(cd "$w" && git push -q origin feat 2>/dev/null)
(cd "$p" && git clone -q --depth 1 --no-single-branch -b feat "file://$p/remote.git" shallow1 2>/dev/null)
dca "$p/shallow1"
expect "a shallow clone that cannot tell says so" 1 "done-check: up to date: FAIL - the history here is shallow, so whether refs/remotes/origin/main is merged cannot be told" \
  "fetch the whole history (git fetch --unshallow origin)"
lacks "and does not say to merge main" "commits this branch does not"
(cd "$p" && git clone -q --depth 3 --no-single-branch -b feat "file://$p/remote.git" shallow3 2>/dev/null)
dca "$p/shallow3"
expect "a shallow clone that holds main's tip passes up to date" 1 "done-check: up to date: PASS - main is refs/remotes/origin/main"
(cd "$p" && git clone -q --depth 1 -b feat "file://$p/remote.git" single 2>/dev/null)
(cd "$p/single" && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/feat)
dca "$p/single"
expect "origin/HEAD that names the task branch is not main; no main says how to fetch it" 1 \
  "done-check: up to date: FAIL - no main branch here (looked for origin/HEAD" "git remote set-branches --add origin main && git fetch origin"
# a main fetched by hand into a ref that the fetch settings do not name is
# never moved by a later git fetch, so it does not count
(cd "$p/single" && git fetch -q origin main:refs/remotes/origin/main 2>/dev/null)
dca "$p/single"
expect "a main fetched by hand that git fetch never moves fails up to date, with the command that keeps it fetched" 1 \
  "done-check: up to date: FAIL - refs/remotes/origin/main is not moved by git fetch" \
  "done-check: next: keep main fetched (git remote set-branches --add origin main && git fetch origin), then run done-check again"
(cd "$p/single" && git remote set-branches --add origin main && git fetch -q origin 2>/dev/null)
dca "$p/single"
lacks "once the fetch settings name main, it counts" "is not moved by git fetch"

# a default branch other than main: a branch made from it tracks it (git's
# default), and it is still main
for def in develop trunk; do
  dv=$(new_sandbox_dir) || abort_sandbox
  repos="$repos $dv"
  (
    cd "$dv" || exit 1
    git init -q --bare remote.git
    git --git-dir=remote.git symbolic-ref HEAD "refs/heads/$def"
    git init -q seed
    cd seed || exit 1
    mkdir -p checks .claude src
    printf 'unit\tany\t-\t(\\d+) ok\techo 3 ok\n' >checks/project.tsv
    printf 'PRODUCT_PATHS=src\n' >.claude/method.conf
    printf 'x = 1\n' >src/a.txt
    git add -A
    git commit -q -m "Start" -m "$OK"
    git remote add origin ../remote.git
    if [ "$def" = develop ]; then git push -q origin main 2>/dev/null; fi
    git checkout -q -b "$def"
    git commit -q --allow-empty -m "Default" -m "$OK"
    git push -q origin "$def" 2>/dev/null
    cd .. && git clone -q remote.git w 2>/dev/null && cd w || exit 1
    git checkout -q -b feat "origin/$def" 2>/dev/null
    echo y >src/b.txt
    add_task .
    git add -A
    git commit -q -m "Feature" -m "$OK"
  ) || abort_sandbox
  up=$(cd "$dv/w" && git rev-parse --abbrev-ref 'feat@{upstream}' 2>/dev/null)
  if [ "$up" = "origin/$def" ]; then pass "setup: the branch tracks origin/$def"; else fail "setup: the branch tracks origin/$def" "$up"; fi
  rc "$dv/w"
  dca "$dv/w"
  expect "a branch that tracks the default branch $def still has it as main" 0 "done-check: up to date: PASS - main is refs/remotes/origin/$def"
done
(cd "$dv/seed" && git commit -q --allow-empty -m "Default moves" -m "$OK" && git push -q origin trunk 2>/dev/null)
(cd "$dv/w" && git fetch -q origin)
dca "$dv/w"
expect "and when that default branch moves on, the branch is not up to date" 1 "done-check: up to date: FAIL - refs/remotes/origin/trunk has 1 commit this branch does not"

# main comes from the remote when it is not named origin, and a local main,
# which git fetch never moves, never stands in for it while there is a remote
q=$(new_project) || abort_sandbox
(cd "$q/w" && git push -q origin feat 2>/dev/null)
(cd "$q" && git clone -q -o up -b feat remote.git upc 2>/dev/null && cd upc && git branch -q main up/main)
(cd "$q/w" && git checkout -q main && git commit -q --allow-empty -m "Later" -m "$OK" && git push -q origin main 2>/dev/null && git checkout -q feat)
(cd "$q/upc" && git fetch -q up)
if [ "$(cd "$q/upc" && git rev-parse main)" != "$(cd "$q/upc" && git rev-parse up/main)" ]; then
  pass "setup: the local main is behind the fetched up/main"
else
  fail "setup: the local main is behind the fetched up/main"
fi
dca "$q/upc"
expect "with a remote named up, main is up's, not the local main that git fetch left behind" 1 \
  "done-check: up to date: FAIL - refs/remotes/up/main has 1 commit this branch does not (as of the last fetch)"
git config --global remote.origin.prune true
dca "$q/upc"
expect "a remote.origin setting in the personal settings file with no URL is not a remote" 1 \
  "done-check: up to date: FAIL - refs/remotes/up/main has 1 commit this branch does not"
git config --global --unset remote.origin.prune
(cd "$q/upc" && git symbolic-ref refs/remotes/up/HEAD refs/remotes/up/feat)
dca "$q/upc"
expect "and an up/HEAD that names the task branch is not main either" 1 \
  "done-check: up to date: FAIL - refs/remotes/up/main has 1 commit this branch does not"
(cd "$q/upc" && git symbolic-ref refs/remotes/up/HEAD refs/remotes/up/main)
(cd "$q" && git clone -q --depth 1 --no-single-branch -o up -b feat "file://$q/remote.git" upshallow 2>/dev/null)
dca "$q/upshallow"
expect "a shallow clone from a remote named up is told to fetch from up" 1 \
  "done-check: up to date: FAIL - the history here is shallow" "fetch the whole history (git fetch --unshallow up)"
# a remote's name can hold shell syntax; it never goes into a command to paste
(cd "$q" && git clone -q -o 'u;x' -b feat remote.git semi 2>/dev/null && cd semi && git symbolic-ref -d 'refs/remotes/u;x/HEAD' &&
  git update-ref -d 'refs/remotes/u;x/main')
dca "$q/semi"
expect "a remote named with shell syntax is not written into the fetch command" 1 \
  "git remote set-branches --add <remote> main && git fetch <remote> (or push main to u;x first"
lacks "and the command holds no part of that name" "git fetch u;x"
# shellcheck disable=SC2016 # the name is meant literally
(cd "$q/semi" && git remote rename 'u;x' 'a$(b)')
dca "$q/semi"
expect "nor is a remote named with \$( )" 1 "git remote set-branches --add <remote> main && git fetch <remote>"
# shellcheck disable=SC2016 # the name is meant literally
lacks "and the command holds no part of that name either" '--add a$(b)'
(cd "$q" && git clone -q --depth 1 --no-single-branch -o 'u;x' -b feat "file://$q/remote.git" semishallow 2>/dev/null)
dca "$q/semishallow"
expect "nor into the command that fetches the whole history" 1 "fetch the whole history (git fetch --unshallow <remote>)"
(cd "$q/upc" && git remote add other ../remote.git)
dca "$q/upc"
expect "with several remotes and none named origin there is no main, and done-check says why and what to do" 1 \
  "done-check: up to date: FAIL - no main branch here (this repository has several remotes and none is named origin" \
  "done-check: next: name the remote that holds main origin (git remote rename NAME origin), then run done-check again"
(cd "$q/upc" && git remote remove other && git remote rename up origin && git symbolic-ref -d refs/remotes/origin/HEAD &&
  git update-ref -d refs/remotes/origin/main)
dca "$q/upc"
expect "with a remote that has no main, the local main does not stand in for it" 1 \
  "done-check: up to date: FAIL - no main branch here (looked for origin/HEAD, refs/remotes/origin/main, refs/remotes/origin/master" \
  "git remote set-branches --add origin main && git fetch origin" "done-check: next: fetch main, then run done-check again"
(cd "$q/upc" && git config --remove-section remote.origin)
dca "$q/upc"
expect "with remote-tracking branches but no remote set up, the local main does not stand in either" 1 \
  "done-check: up to date: FAIL - no main branch here (this repository has remote-tracking branches but no remote set up" \
  "done-check: next: set up the remote that holds main (git remote add origin URL, or git remote set-url origin URL when origin is there without one) and fetch it, then run done-check again"
(cd "$q/upc" && git for-each-ref --format='%(refname)' refs/remotes/ | while read -r r; do git update-ref -d "$r"; done)
dca "$q/upc"
expect "with no remote at all, main is the local main, and the line says so" 1 \
  "done-check: up to date: PASS - main is refs/heads/main" "(a local branch: this repository has no remote; done-check does not fetch)"
(cd "$q/upc" && git branch -q -m main trunk)
dca "$q/upc"
expect "with no remote and no main, done-check says to make one" 1 \
  "done-check: up to date: FAIL - no main branch here (looked for refs/heads/main, refs/heads/master; this repository has no remote)" \
  "done-check: next: make a branch named main (or rename the default branch: git branch -m NAME main), then run done-check again"

# --- checks (M089) ---
q=$(new_project) || abort_sandbox
v="$q/w"
amend "$v" "$OK"
dca "$v"
expect "no log fails checks, saying to run them" 1 "done-check: checks: FAIL - no run-checks log of these files" \
  "done-check: next: run the checks: bash scripts/method/run-checks.sh"
rc "$v"
dca "$v"
expect "setup: READY after the run" 0 "done-check: READY - "
echo changed >"$v/src/a.txt"
(cd "$v" && git add -A)
amend "$v" "$OK"
dca "$v"
expect "a log of other files does not count" 1 "done-check: checks: FAIL - no run-checks log of these files"
rc "$v"
x=$(cd "$v" && git rev-parse HEAD)
e=$(cd "$v" && git commit-tree "$(git rev-parse "origin/main^{tree}")" -p origin/main -m "Other")
printf 'Change\n\n%s\n' "$OK" >"$work/msg"
n=$(cd "$v" && git commit-tree "$x^{tree}" -p "$e" -F "$work/msg")
(cd "$v" && git reset -q --hard "$n")
dca "$v"
expect "a log of the same files with other parents does not count" 1 "done-check: up to date: PASS" "done-check: checks: FAIL - no run-checks log of these files"
(cd "$v" && git reset -q --hard "$x")
printf 'Change, amended\n\n%s\n' "$OK" >"$work/msg"
(cd "$v" && git commit -q --amend --allow-empty --cleanup=verbatim -F "$work/msg")
(cd "$v" && git reflog expire --expire=now --all && git gc -q --prune=now 2>/dev/null)
if (cd "$v" && git cat-file -e "$x" 2>/dev/null); then fail "setup: the run's commit is pruned"; else pass "setup: the run's commit is pruned"; fi
dca "$v"
expect "a log whose commit was pruned does not count, and is named" 1 "logs that name a commit no longer in this repository: "
rc "$v"
# a newer run whose commit is gone (an empty verdict commit, then dropped and
# pruned) is named, since its result cannot be tied to these files
xa=$(cd "$v" && git rev-parse HEAD)
msg "$v" 'Verdict again\n\n%s\n' "$OK"
: >"$v/flaky.marker"
rc "$v"
rm -f "$v/flaky.marker"
(cd "$v" && git reset -q --hard "$xa" && git reflog expire --expire=now --all && git gc -q --prune=now 2>/dev/null)
dca "$v"
expect "a newer run whose commit is gone is named on the READY line" 0 "done-check: READY - " \
  "newer runs that name a commit no longer in this repository: 1 (whether they were runs of these files cannot be told)"
: >"$v/flaky.marker"
rc "$v"
dca "$v"
expect "a failing run fails checks, naming the check" 1 "done-check: checks: FAIL - the last run of these files (" ") failed: unit" \
  "done-check: next: fix them, then run the checks"
rm -f "$v/flaky.marker"
rc "$v"
dca "$v"
expect "a fail then a pass of the same files is READY, naming the failure" 0 \
  "runs of these files failed: unit; a check that fails sometimes is a finding for the review" "done-check: READY - " \
  "; 1 of 3 runs of these files failed: unit"
# logs are not read through a linked folder, which run-checks never writes
# through either (another clone's logs could stand in)
mv "$v/.method/local/logs" "$work/linked-logs" && ln -s "$work/linked-logs" "$v/.method/local/logs"
dca "$v"
expect "logs behind a linked logs folder do not count" 1 "done-check: checks: FAIL - no run-checks log of these files"
rm -f "$v/.method/local/logs" && mv "$work/linked-logs" "$v/.method/local/logs"
dca "$v"
expect "setup: READY again with the folder back" 0 "done-check: READY - "
# (not $d: dc sets it)
for ld in .method/local .method; do
  mv "$v/$ld" "$work/linked-dir" && ln -s "$work/linked-dir" "$v/$ld"
  dca "$v"
  expect "logs behind a linked $ld folder do not count" 1 "done-check: checks: FAIL - no run-checks log of these files"
  rm -f "$v/$ld" && mv "$work/linked-dir" "$v/$ld"
done
dca "$v"
expect "setup: READY again with the folders back" 0 "done-check: READY - "
newest=$(newest_log "$v")
sed '$d' "$v/$newest" | sed '$d' >"$v/.method/local/logs/run-checks-29991231T235959Z-0000000001.log"
dca "$v"
expect "a newest log without END fails checks" 1 "did not finish (stopped, or a check hung)"
printf 'junk\n' >"$v/.method/local/logs/run-checks-29991231T235959Z-0000000001.log"
dca "$v"
expect "a newer log that cannot be read fails checks" 1 "a run-checks log newer than the last one of these files cannot be read"
rm -f "$v/.method/local/logs/run-checks-29991231T235959Z-0000000001.log"
echo again >"$v/src/a.txt"
(cd "$v" && git add -A)
amend "$v" "$OK"
echo dirty >>"$v/src/a.txt"
: >"$v/flaky.marker"
rc "$v"
(cd "$v" && git checkout -q -- src/a.txt)
rm -f "$v/flaky.marker"
rc "$v"
dca "$v"
expect "a failed run that started on uncommitted changes is not named" 0 "done-check: READY - "
lacks "(no earlier failure named)" "runs of these files failed"
: >"$v/flaky.marker"
rc "$v" CI=true
rm -f "$v/flaky.marker"
dca "$v"
expect "a failed CI run does not count for a local done-check" 0 "done-check: READY - "
lacks "(not named either)" "runs of these files failed"
echo dirty >>"$v/src/a.txt"
rc "$v"
(cd "$v" && git checkout -q -- src/a.txt)
dca "$v"
expect "a newest run that started on uncommitted changes fails checks" 1 "started on uncommitted changes" "done-check: next: commit first"

# --- elsewhere (M089) ---
rc "$v"
printf 'integ\tci\t-\t(\\d+) ok\techo 0 ok; exit 1\n' >>"$v/checks/project.tsv"
(cd "$v" && git add -A)
amend "$v" "$OK"
rc "$v"
rc_ok "setup: a CI-only check is not for here, so run-checks passes locally"
dca "$v"
expect "a CI-only check has no result here, so it is not READY" 1 "done-check: checks: PASS" \
  "done-check: elsewhere: FAIL - 1 check runs only in CI, and done-check does not read CI results: integ"
printf 'unit\tany\t-\t(\\d+) ok\ttest ! -e flaky.marker && echo 3 ok\npriv\tlocal\t-\t(\\d+) ok\techo 0 ok; exit 1\n' >"$v/checks/project.tsv"
(cd "$v" && git add -A)
amend "$v" "$OK"
rc "$v" CI=true
rc_ok "setup: with CI=true, a local-only check is not for here"
dca "$v" CI=true
expect "CI=true for both: a local-only check has no result, so it is not READY" 1 \
  "done-check: elsewhere: FAIL - 1 check runs only locally, and no record of a local run is read yet: priv"
printf 'unit\tany\t-\t(\\d+) ok\ttest ! -e flaky.marker && echo 3 ok\n' >"$v/checks/project.tsv"
(cd "$v" && git add -A)
amend "$v" "$OK"
rc "$v"

# --- verdict (M008) ---
amend "$v" 'Review-Verdict: request-changes-open - round 3 fixes checked by tests, planted breaks and two checks of the fixes, not re-reviewed (3-round cap); CI waits on Actions minutes'
dca "$v"
expect "an open verdict line on approving receipts is not READY, and names the line they give" 1 \
  "done-check: verdict: FAIL - the verdict line says request-changes-open (changes are still open; the reason names them); the receipts give approve" \
  "done-check: next: end the head commit's message with this line, as its last paragraph: Review-Verdict: approve (in an empty commit when the branch is pushed" \
  "done-check: NOT READY - 1 condition failed (verdict)"
unforge "$v"
forge "$v" "$R" "REQUEST CHANGES"
forge "$v" "$S" APPROVE
dc "$v"
expect "an open verdict line with no approving review is not READY, and names the owner's way forward" 1 \
  "done-check: verdict: FAIL - the verdict line says request-changes-open (changes are still open; the reason names them): no review approved this version" \
  "done-check: next: fix what method-reviewer found, commit, and have the new version reviewed" "done-check: NOT READY - 2 conditions failed (reviewer, verdict)"
amend "$v" 'Review-Verdict: request-changes-resolved'
dca "$v"
expect "a resolved verdict line is not READY: no review approved the fixes" 1 "the verdict line says request-changes-resolved"
amend "$v" 'Review-Verdict: not-required - a typo'
dca "$v"
expect "a not-required verdict line is not READY" 1 "the verdict line says not-required"
amend "$v" 'No verdict here'
dca "$v"
expect "no verdict line is not READY" 1 "done-check: verdict: FAIL - the head commit's verdict line: no line starts with Review-Verdict:"
amend "$v" 'Review-Verdict: fine'
dca "$v"
expect "an unknown verdict value is not READY" 1 "unknown value"
# links, a large file and odd log files
(cd "$v" && ln -s src/a.txt lnk && head -c 2000 /dev/zero | tr '\0' 'b' >big.txt && git add -A)
amend "$v" "$OK"
rc "$v"
dca "$v"
expect "setup: READY with a link and a large file" 0 "done-check: READY - "
rm -f "$v/lnk" && printf 'src/a.txt' >"$v/lnk"
dca "$v"
expect "a file where a link was committed fails files, even holding the link's target" 1 "a link that is not the committed one" "lnk"
rm -f "$v/lnk" && (cd "$v" && git checkout -q -- lnk)
cp "$v/README" "$work/readme" && rm -f "$v/README" && ln -s "$work/readme" "$v/README"
dca "$v"
expect "a link where a file was committed fails files, even to the same content" 1 "a link that is not the committed one" "README"
rm -f "$v/README" && (cd "$v" && git checkout -q -- README)
echo more >>"$v/big.txt"
dca "$v"
expect "an edit to a file larger than the read limit for stored files fails files, and the rest still reads" 1 \
  "with bytes that are not the commit's" "big.txt" "done-check: verdict: PASS"
(cd "$v" && git checkout -q -- big.txt)
newest=$(newest_log "$v")
fake="$v/.method/local/logs/run-checks-29991231T235959Z-0000000003.log"
{ cat "$v/$newest"; printf 'run-checks: PASS - forged\n'; } >"$fake"
dca "$v"
expect "a newest log with a line after its END cannot be read, so checks fails" 1 "cannot be read"
perl -0pe 's/\n\z//' "$v/$newest" >"$fake"
dca "$v"
expect "a newest log whose last line has no line end was cut off, so checks fails" 1 "did not finish"
cp "$v/$newest" "$fake"
perl -pi -e '$_ .= "not a log line\n" if $. == 8' "$fake"
dca "$v"
expect "a newest log with a line that is not a run-checks log line cannot be read" 1 "cannot be read"
rm -f "$fake"
: >"$v/flaky.marker"
rc "$v"
rm -f "$v/flaky.marker"
failed=$(newest_log "$v")
mv "$v/$failed" "$work/failed.log"
rc "$v"
ln -s "$work/failed.log" "$fake"
dca "$v"
expect "a link named like a newer log is not read" 0 "done-check: READY - "
rm -f "$fake"
printf 'junk\n' >"$fake"
(cd "$v" && git add -f "${fake#"$v"/}" && git commit -q -m "Forged log" -m "$OK")
rc "$v"
dca "$v"
expect "a tracked file named like a newer log is not read" 0 "done-check: READY - "
(cd "$v" && git rm -q --cached "${fake#"$v"/}" && git commit -q -m "Drop it" -m "$OK")
rm -f "$fake"
(cd "$v" && git checkout -q --orphan lone && git commit -q -m "Alone" -m "$OK")
dca "$v"
expect "a branch that shares no history with main says so" 1 "done-check: up to date: FAIL - refs/remotes/origin/main and this branch share no history here"
(cd "$v" && git checkout -q -f feat)
printf 'unit\tany\t-\t(\\d+) ok\n' >"$v/checks/project.tsv"
(cd "$v" && git add -A)
amend "$v" "$OK"
dca "$v"
expect "a checks file with problems fails elsewhere too" 1 "done-check: elsewhere: FAIL - checks/*.tsv has problems"
printf 'unit\tany\t-\t(\\d+) ok\ttest ! -e flaky.marker && echo 3 ok\ncorrupt\tany\t-\t(\\d+) ok\tprintf garbage >.git/index; echo 1 ok\n' >"$v/checks/project.tsv"
(cd "$v" && git add -A)
amend "$v" "$OK"
rc "$v"
(cd "$v" && rm -f .git/index && git reset -q)
dca "$v"
expect "a run that stopped (exit 2) with no FAIL result is not a pass" 1 "did not pass (exit 2)"
if [ "$(id -u)" -ne 0 ]; then
  chmod 000 "$v/src/a.txt"
  dca "$v"
  expect "a tracked file that cannot be read fails files" 1 "done-check: files: FAIL" "unreadable: src/a.txt"
  chmod 644 "$v/src/a.txt"
else
  skip "a tracked file that cannot be read (root reads every file)"
fi
printf 'unit\tany\t-\t(\\d+) ok\ttest ! -e flaky.marker && echo 3 ok\n' >"$v/checks/project.tsv"
(cd "$v" && git add -A)
amend "$v" "$OK"
rc "$v"
amend "$v" "$OK"

# --- verdicts start ---
# main: r0 (no line), r1 (sets up the project), r2 (VERDICTS_FROM=r1), r3
vs=$(new_sandbox_dir) || abort_sandbox
repos="$repos $vs"
(
  cd "$vs" || exit 1
  git init -q --bare remote.git
  git init -q w
  cd w || exit 1
  printf '*.marker\n' >.gitignore
  git add -A
  git commit -q -m "Root"
  mkdir -p checks .claude src
  printf 'unit\tany\t-\t(\\d+) ok\techo 3 ok\n' >checks/project.tsv
  printf 'PRODUCT_PATHS=src\n' >.claude/method.conf
  printf 'x = 1\n' >src/a.txt
  git add -A
  git commit -q -m "Project" -m "Review-Verdict: approve"
  printf 'PRODUCT_PATHS=src\nVERDICTS_FROM=%s\n' "$(git rev-parse HEAD)" >.claude/method.conf
  git commit -q -am "Start the verdicts" -m "Review-Verdict: approve"
  git commit -q --allow-empty -m "More" -m "Review-Verdict: approve"
  git remote add origin ../remote.git
  git push -q -u origin main 2>/dev/null
  git remote set-head origin main
  git checkout -q -b feat
) || abort_sandbox
y="$vs/w"
r0=$(cd "$y" && git rev-parse HEAD~3)
r1=$(cd "$y" && git rev-parse HEAD~2)
r2=$(cd "$y" && git rev-parse HEAD~1)
# setvf DIR VALUE: commits the plan of task t1, Tier FULL with its
# expected.tsv (a change to .claude/method.conf is high-risk, M153), then
# VERDICTS_FROM=VALUE (or none), each with an approving line
setvf() {
  add_task "$1" t1 FULL
  printf 'case\tinputs\texpected\tsource\none\tx=1\t2\tthe owner\n' >"$1/docs/tasks/t1/expected.tsv"
  (cd "$1" && git add -A)
  msg "$1" 'Plan\n\n%s\n' "$OK"
  if [ -n "$2" ]; then printf 'PRODUCT_PATHS=src\nVERDICTS_FROM=%s\n' "$2" >"$1/.claude/method.conf"; else printf 'PRODUCT_PATHS=src\n' >"$1/.claude/method.conf"; fi
  (cd "$1" && git add -A)
  msg "$1" 'Move VERDICTS_FROM\n\n%s\n' "$OK"
}
# dcf DIR: the receipts of a finished FULL change with Deep review, for a
# change setvf made (the failing run on HEAD~1, the plan's commit; the
# tester's pass, three reviewers, the security checker and the reporter on
# HEAD), then done-check (dc)
dcf() {
  unforge "$1"
  forge "$1" "$T" "TESTS FAIL" head="$(cd "$1" && git rev-parse HEAD~1)" tree="$(cd "$1" && git rev-parse 'HEAD~1^{tree}')"
  finish "$1"
  forge "$1" "$R" APPROVE
  forge "$1" "$R" APPROVE
  dc "$1"
}
setvf "$y" "$r0"
rc "$y"
dcf "$y"
expect "moving VERDICTS_FROM to an older commit accepts nothing (READY)" 0 \
  "done-check: verdicts start: PASS - this change moves VERDICTS_FROM from ${r1%"${r1#???????}"} to ${r0%"${r0#???????}"}; it accepts no commit without a valid verdict line"
(cd "$y" && git reset -q --hard origin/main)
setvf "$y" "$r2"
rc "$y"
dcf "$y"
expect "moving it forward over commits with valid lines accepts nothing (READY)" 0 \
  "from ${r1%"${r1#???????}"} to ${r2%"${r2#???????}"}; it accepts no commit without a valid verdict line"
(cd "$y" && git reset -q --hard origin/main)
side=$(cd "$y" && git commit-tree "$(git rev-parse "HEAD^{tree}")" -p "$r1" -m "Side")
setvf "$y" "$side"
rc "$y"
dcf "$y"
expect "a VERDICTS_FROM that is not on main fails" 1 "which is not on refs/remotes/origin/main's first-parent history, so status would report LOOK after the merge"
(cd "$y" && git reset -q --hard origin/main)
setvf "$y" "$r0"
(cd "$vs" && git clone -q remote.git other 2>/dev/null && cd other && git commit -q --allow-empty -m "Later" -m "$OK" && git push -q origin main 2>/dev/null)
(cd "$y" && git fetch -q origin)
dcf "$y"
expect "a VERDICTS_FROM move is judged only once the branch is up to date" 1 "done-check: verdicts start: FAIL - this change moves VERDICTS_FROM; judged once the branch is up to date with main"
# VERDICTS_FROM is read as status reads it (A37): the file on disk must be
# the one the commit stores, so a move cannot hide in a submodule or in LFS
(cd "$vs" && git clone -q remote.git sm 2>/dev/null && cd sm && git checkout -q -b feat)
tipv=$(cd "$vs/sm" && git rev-parse HEAD)
(git init -q "$vs/confsub" && cd "$vs/confsub" && printf 'PRODUCT_PATHS=src\nVERDICTS_FROM=%s\n' "$tipv" >method.conf &&
  git add -A && git commit -q -m conf)
(cd "$vs/sm" && git rm -q -r .claude && git submodule add -q "$vs/confsub" .claude 2>/dev/null && add_task . && git add -A)
msg "$vs/sm" 'Settings in a submodule\n\n%s\n' "$OK"
rc "$vs/sm"
rc_ok "setup: run-checks passes with the settings in a submodule"
dca "$vs/sm"
expect "a VERDICTS_FROM set in a .claude submodule, which the commit does not hold, fails verdicts start" 1 \
  "done-check: verdicts start: FAIL - VERDICTS_FROM is ${tipv%"${tipv#???????}"} in .claude/method.conf on disk, but unset in the file commit" \
  "done-check: tier: FAIL - the high-risk list cannot be read: .claude/method.conf in this change (" "): .claude is a submodule" \
  "done-check: next: fix .claude/method.conf and keep it a plain file committed in this repository"
(cd "$vs" && git clone -q remote.git lc 2>/dev/null && cd lc && git checkout -q -b feat)
# a stand-in for git-lfs's clean filter: the pointer names the content's hash
cat >"$vs/lc/.git/lfs-clean.sh" <<'EOS'
#!/bin/sh
exec perl -MDigest::SHA -e 'binmode STDIN; local $/; my $c = <STDIN>; $c = "" unless defined $c; printf "version https://git-lfs.github.com/spec/v1\noid sha256:%s\nsize %d\n", Digest::SHA::sha256_hex($c), length $c'
EOS
(cd "$vs/lc" && git config filter.lfs.clean "sh .git/lfs-clean.sh" && git config filter.lfs.smudge cat &&
  printf '.claude/method.conf filter=lfs\n' >.gitattributes && printf 'PRODUCT_PATHS=src\nVERDICTS_FROM=%s\n' "$tipv" >.claude/method.conf &&
  add_task . && git add -A && git commit -q -m "Settings in LFS" -m "$OK" && touch -t 202001010000 .claude/method.conf && git update-index -q --refresh)
if (cd "$vs/lc" && git cat-file blob HEAD:.claude/method.conf | grep -q '^version https://git-lfs'); then
  pass "setup: the commit stores an LFS pointer for method.conf"
else
  fail "setup: the commit stores an LFS pointer for method.conf"
fi
rc "$vs/lc"
dca "$vs/lc"
expect "a VERDICTS_FROM in a method.conf stored in Git LFS fails verdicts start" 1 "done-check: files: PASS" \
  "done-check: verdicts start: FAIL - VERDICTS_FROM is ${tipv%"${tipv#???????}"} in .claude/method.conf on disk, but unset in the file commit"
# main's own VERDICTS_FROM kept in a .claude submodule, in Git LFS or under a
# filter cannot be read as status reads it, so a move away from it (here to
# a plain file, past an unreviewed hotfix) could not be checked
cp "$vs/lc/.git/lfs-clean.sh" "$work/lfs-clean.sh"
for kind in submodule lfs filter encoding; do
  mo=$(new_sandbox_dir) || abort_sandbox
  repos="$repos $mo"
  (
    cd "$mo" || exit 1
    git init -q --bare remote.git
    git init -q w
    cd w || exit 1
    mkdir -p checks src
    printf 'unit\tany\t-\t(\\d+) ok\techo 3 ok\n' >checks/project.tsv
    printf 'x = 1\n' >src/a.txt
    git add -A
    git commit -q -m "Project" -m "Review-Verdict: approve"
    start=$(git rev-parse HEAD)
    case $kind in
      submodule)
        git init -q ../confsub && printf 'PRODUCT_PATHS=src\nVERDICTS_FROM=%s\n' "$start" >../confsub/method.conf &&
          (cd ../confsub && git add -A && git commit -q -m conf) && git submodule add -q ../confsub .claude 2>/dev/null ;;
      lfs)
        git config filter.lfs.clean "sh $work/lfs-clean.sh" && git config filter.lfs.smudge cat &&
          printf '.claude/method.conf filter=lfs\n' >.gitattributes ;;
      filter)
        git config filter.strip.clean "sed /VERDICTS_FROM/d" && git config filter.strip.smudge cat &&
          printf '.claude/method.conf filter=strip\n' >.gitattributes ;;
      encoding)
        printf '.claude/method.conf working-tree-encoding=UTF-16LE\n' >.gitattributes ;;
    esac
    if [ "$kind" != submodule ]; then mkdir -p .claude && printf 'PRODUCT_PATHS=src\nVERDICTS_FROM=%s\n' "$start" >.claude/method.conf; fi
    if [ "$kind" = encoding ]; then perl -pi -e 's/(.)/$1\0/gs' .claude/method.conf; fi
    git add -A
    git commit -q -m "Settings" -m "Review-Verdict: approve"
    git commit -q --allow-empty -m "Hotfix"
    git remote add origin ../remote.git
    git push -q -u origin main 2>/dev/null
    git remote set-head origin main
    git checkout -q -b feat
    if [ "$kind" = submodule ]; then git rm -q .claude && mkdir -p .claude; else git rm -q .gitattributes; fi
    printf 'PRODUCT_PATHS=src\nVERDICTS_FROM=%s\n' "$(git rev-parse HEAD)" >.claude/method.conf
    add_task .
    git add -A
    git commit -q -m "Plain settings" -m "Review-Verdict: approve"
  ) || abort_sandbox
  case $kind in
    submodule) why='.claude is a submodule' ;;
    lfs) why='the file is stored as a Git LFS pointer' ;;
    filter) why="the commit's .gitattributes gives the file a filter" ;;
    *) why="the commit's .gitattributes gives the file a working-tree-encoding" ;;
  esac
  rc "$mo/w"
  dca "$mo/w"
  expect "main's VERDICTS_FROM kept as a $kind cannot be read as status reads it, so the move could not be checked" 1 \
    "done-check: verdicts start: FAIL - VERDICTS_FROM on main (refs/remotes/origin/main " ") cannot be read as status reads it: $why; could not check"
  if [ "$kind" = filter ]; then
    # where git cannot read main's own attributes (here: a rule in
    # .git/info/attributes), a .gitattributes that names a filter counts
    printf '*.psd binary\n' >"$mo/w/.git/info/attributes"
    dca "$mo/w"
    expect "and so it is when .git/info/attributes holds a rule, so main's attributes cannot be read" 1 \
      "cannot be read as status reads it: .gitattributes names a filter, an encoding or a macro, which cannot be read for the file here (.git/info/attributes holds rules"
    rm -f "$mo/w/.git/info/attributes"
  fi
done
# a change that adds an encoding rule for method.conf and leaves its bytes as
# they are holds the old value now, but status reads it through the encoding
# once it is checked out
(cd "$vs" && git clone -q remote.git we 2>/dev/null && cd we && git checkout -q -b feat &&
  printf '.claude/method.conf working-tree-encoding=UTF-16LE\n' >>.gitattributes && add_task . && git add .gitattributes docs &&
  git commit -q -m "An encoding rule" -m "$OK")
rc "$vs/we"
dca "$vs/we"
expect "a change that gives method.conf an encoding fails verdicts start" 1 \
  "done-check: verdicts start: FAIL - VERDICTS_FROM in this change cannot be read as status will read it once checked out: the commit's .gitattributes gives the file a working-tree-encoding"
# main's own VERDICTS_FROM is not on its first-parent history
vo=$(new_sandbox_dir) || abort_sandbox
repos="$repos $vo"
(
  cd "$vo" || exit 1
  git init -q --bare remote.git
  git init -q w
  cd w || exit 1
  mkdir -p checks .claude src
  printf 'unit\tany\t-\t(\\d+) ok\techo 3 ok\n' >checks/project.tsv
  printf 'x = 1\n' >src/a.txt
  printf 'PRODUCT_PATHS=src\n' >.claude/method.conf
  git add -A
  git commit -q -m "Project" -m "Review-Verdict: approve"
  off=$(git commit-tree "$(git rev-parse "HEAD^{tree}")" -m "Off main")
  printf 'PRODUCT_PATHS=src\nVERDICTS_FROM=%s\n' "$off" >.claude/method.conf
  git commit -q -am "Point VERDICTS_FROM off main" -m "Review-Verdict: approve"
  git remote add origin ../remote.git
  git push -q -u origin main 2>/dev/null
  git remote set-head origin main
  git checkout -q -b feat
) || abort_sandbox
setvf "$vo/w" "$(cd "$vo/w" && git rev-parse HEAD~1)"
rc "$vo/w"
dcf "$vo/w"
expect "a move from a VERDICTS_FROM that is not on main could not be checked" 1 "could not check what it accepts: the old value is not on refs/remotes/origin/main's first-parent history"

# main: b0 (no line, the project), b1 (no line), b2 (VERDICTS_FROM=b0)
vb=$(new_sandbox_dir) || abort_sandbox
repos="$repos $vb"
(
  cd "$vb" || exit 1
  git init -q --bare remote.git
  git init -q w
  cd w || exit 1
  mkdir -p checks .claude src
  printf 'unit\tany\t-\t(\\d+) ok\techo 3 ok\n' >checks/project.tsv
  printf 'PRODUCT_PATHS=src\n' >.claude/method.conf
  printf 'x = 1\n' >src/a.txt
  git add -A
  git commit -q -m "Project"
  git commit -q --allow-empty -m "Oops"
  printf 'PRODUCT_PATHS=src\nVERDICTS_FROM=%s\n' "$(git rev-parse HEAD~1)" >.claude/method.conf
  git commit -q -am "Start the verdicts" -m "Review-Verdict: approve"
  git remote add origin ../remote.git
  git push -q -u origin main 2>/dev/null
  git remote set-head origin main
  git checkout -q -b feat
) || abort_sandbox
z="$vb/w"
b0=$(cd "$z" && git rev-parse HEAD~2)
b1=$(cd "$z" && git rev-parse HEAD~1)
setvf "$z" "$b1"
rc "$z"
dcf "$z"
expect "a move over a commit with no verdict line passes, naming it on the READY line (A30)" 0 \
  "done-check: verdicts start: PASS - this change moves VERDICTS_FROM from ${b0%"${b0#???????}"} to ${b1%"${b1#???????}"}; it accepts 1 commit on main without a valid verdict line: ${b1%"${b1#???????}"}" \
  "; accepts 1 commit on main without a valid verdict line: ${b1%"${b1#???????}"}"
(cd "$z" && git push -q origin feat 2>/dev/null)
(cd "$vb" && git clone -q --depth 3 -b feat "file://$vb/remote.git" shallow 2>/dev/null)
(cd "$vb/shallow" && git remote set-branches --add origin main && git fetch -q --depth 1 origin main 2>/dev/null)
rc "$vb/shallow"
dcf "$vb/shallow"
expect "a changed value in a shallow clone could not be checked, and it alone fails" 1 \
  "done-check: verdicts start: FAIL - this change moves VERDICTS_FROM from " "which is not in this shallow history of refs/remotes/origin/main; could not check" \
  "done-check: NOT READY - 1 condition failed (verdicts start)"
gv=$(git version | perl -ne 'print /(\d+)\.(\d+)/ && ($1 > 2 || ($1 == 2 && $2 >= 44)) ? 1 : 0')
if [ "$gv" = 1 ]; then
  (cd "$vb" && git --git-dir=remote.git config uploadpack.allowFilter true && git clone -q --filter=blob:none -b feat "file://$vb/remote.git" partial 2>/dev/null)
  dcf "$vb/partial"
  expect "in a partial clone done-check never fetches a missing object: it cannot check (exit 2)" 2 "done-check: NOT READY - could not check: cannot read the stored blob"
else
  skip "a partial clone never fetches (GIT_NO_LAZY_FETCH needs git 2.44)"
fi
(cd "$z" && git reset -q --hard origin/main)
setvf "$z" ""
rc "$z"
dcf "$z"
expect "removing it so a commit with no line leaves the range names that commit" 0 \
  "from ${b0%"${b0#???????}"} to unset; it accepts 1 commit on main without a valid verdict line: ${b1%"${b1#???????}"}"
# an error while checking (here a stored file that does not match its id)
# is exit 2, never a pass
confid=$(cd "$z" && git rev-parse origin/main:.claude/method.conf)
other=$(cd "$z" && git rev-parse HEAD:src/a.txt)
obj="$z/.git/objects/$(printf '%s' "$confid" | cut -c1-2)/$(printf '%s' "$confid" | cut -c3-)"
src="$z/.git/objects/$(printf '%s' "$other" | cut -c1-2)/$(printf '%s' "$other" | cut -c3-)"
if [ -f "$obj" ] && [ -f "$src" ]; then
  cp "$obj" "$work/obj.saved" && chmod u+w "$obj" && cp "$src" "$obj"
  dcf "$z"
  expect "a stored file changed by hand stops done-check with exit 2 (could not check)" 2 "done-check: NOT READY - could not check: " "does not match its id" \
    "against refs/remotes/origin/main"
  cp "$work/obj.saved" "$obj"
else
  fail "setup: the objects are loose files"
fi

# adoption: main has no verdict line yet; the change sets VERDICTS_FROM
va=$(new_sandbox_dir) || abort_sandbox
repos="$repos $va"
(
  cd "$va" || exit 1
  git init -q --bare remote.git
  git init -q w
  cd w || exit 1
  git commit -q --allow-empty -m "Older"
  mkdir -p checks .claude src
  printf 'unit\tany\t-\t(\\d+) ok\techo 3 ok\n' >checks/project.tsv
  printf 'PRODUCT_PATHS=src\n' >.claude/method.conf
  printf 'x = 1\n' >src/a.txt
  git add -A
  git commit -q -m "Before the method"
  git remote add origin ../remote.git
  git push -q -u origin main 2>/dev/null
  git remote set-head origin main
  git checkout -q -b feat
) || abort_sandbox
u="$va/w"
c0=$(cd "$u" && git rev-parse HEAD)
setvf "$u" "$c0"
rc "$u"
dcf "$u"
expect "adopting the method (VERDICTS_FROM set on a main with no verdict line) is READY" 0 \
  "this change moves VERDICTS_FROM from unset to ${c0%"${c0#???????}"}; it accepts no commit without a valid verdict line" "done-check: READY - "
(cd "$u" && git push -q origin feat 2>/dev/null)
(cd "$va" && git clone -q --depth 2 -b feat "file://$va/remote.git" shallow 2>/dev/null)
(cd "$va/shallow" && git remote set-branches --add origin main && git fetch -q --depth 1 origin main 2>/dev/null && git fetch -q --deepen=1 origin feat 2>/dev/null)
rc "$va/shallow"
dcf "$va/shallow"
expect "adoption in a shallow history could not be checked: older commits with a verdict line may be cut off" 1 \
  "done-check: up to date: PASS" "could not check what it accepts: the history here is shallow" "done-check: NOT READY - 1 condition failed (verdicts start)"

# a method.conf with a problem on main is read as status reads it, so the
# change that fixes it can be ready
vp=$(new_sandbox_dir) || abort_sandbox
repos="$repos $vp"
(
  cd "$vp" || exit 1
  git init -q --bare remote.git
  git init -q w
  cd w || exit 1
  mkdir -p checks .claude src
  printf 'unit\tany\t-\t(\\d+) ok\techo 3 ok\n' >checks/project.tsv
  printf 'PRODUCT_PATHS=src\nBOGUS=1\n' >.claude/method.conf
  printf 'x = 1\n' >src/a.txt
  git add -A
  git commit -q -m "Project" -m "Review-Verdict: approve"
  git remote add origin ../remote.git
  git push -q -u origin main 2>/dev/null
  git remote set-head origin main
  git checkout -q -b feat
  printf 'PRODUCT_PATHS=src\n' >.claude/method.conf
  add_task .
  git add -A
  git commit -q -m "Fix the settings" -m "Review-Verdict: approve"
) || abort_sandbox
rc "$vp/w"
dca "$vp/w"
# (since step 6b.3 a problem on main that may touch HIGH_RISK_PATHS, as an unknown
# key may, makes every branch NOT READY for the tier alone until main's file
# is fixed: a broken high-risk list is never read as a shorter one)
expect "a change that fixes a method.conf with a problem on main is NOT READY for the tier alone" 1 \
  "done-check: verdicts start: PASS - VERDICTS_FROM is unset both on main and in this change" \
  "done-check: tier: FAIL - the high-risk list cannot be read: .claude/method.conf on main (" ") line 2: unknown key BOGUS" \
  "done-check: NOT READY - 2 conditions failed (tier, verdict)"

# Git LFS: content on disk counts as the commit only where the commit asks for LFS
lp=$(new_project) || abort_sandbox
l="$lp/w"
# a stand-in for git-lfs's clean filter: the pointer names the content's hash
cat >"$l/.git/lfs-clean.sh" <<'EOS'
#!/bin/sh
exec perl -MDigest::SHA -e 'binmode STDIN; local $/; my $c = <STDIN>; $c = "" unless defined $c; printf "version https://git-lfs.github.com/spec/v1\noid sha256:%s\nsize %d\n", Digest::SHA::sha256_hex($c), length $c'
EOS
(cd "$l" && git config filter.lfs.clean "sh .git/lfs-clean.sh" && git config filter.lfs.smudge cat && printf 'src/data.bin filter=lfs\n' >.gitattributes &&
  printf 'content\n' >src/data.bin && git add -A && git commit -q -m "LFS" -m "$OK" && touch -t 202001010000 src/data.bin && git update-index -q --refresh)
if (cd "$l" && git cat-file blob HEAD:src/data.bin | grep -q '^version https://git-lfs'); then pass "setup: the commit stores an LFS pointer"; else fail "setup: the commit stores an LFS pointer"; fi
rc "$l"
dca "$l"
expect "an LFS file the commit's .gitattributes asks for is the commit" 0 "done-check: files: PASS" "1 of them Git LFS content the commit's .gitattributes asks for" "done-check: READY - "
(cd "$l" && git rm -q --cached .gitattributes && rm -f .gitattributes && git commit -q -m "No more LFS" -m "$OK")
dca "$l"
expect "LFS content on disk whose path the commit no longer marks for LFS is not the commit (a clone gets the pointer)" 1 \
  "done-check: files: FAIL" "with bytes that are not the commit's" "src/data.bin"
printf 'src/data.bin filter=lfs\n' >"$l/.git/info/attributes"
dca "$l"
expect "and an LFS rule only in .git/info/attributes does not make it the commit" 1 "src/data.bin" ".git/info/attributes holds rules"
rm -f "$l/.git/info/attributes"
printf 'src/data.bin filter=lfs\n' >"$work/lfsattrs"
(cd "$l" && git config core.attributesFile "$work/lfsattrs")
dca "$l"
expect "nor does an LFS rule only in a personal attributes file" 1 "done-check: files: FAIL" "src/data.bin"
(cd "$l" && git config --unset core.attributesFile)
printf 'data.bin filter=lfs\n' >"$l/src/.gitattributes"
printf 'src/.gitattributes\n' >>"$l/.git/info/exclude"
dca "$l"
expect "nor an ignored .gitattributes on disk" 1 "done-check: files: FAIL" "src/data.bin"
rm -f "$l/src/.gitattributes"

# a tracked file in .method/local is compared like any other
(cd "$l" && git checkout -q main 2>/dev/null; git checkout -q -b helper && mkdir -p .method/local && printf 'exit 1\n' >.method/local/helper.sh &&
  git add -f .method/local/helper.sh && git commit -q -m "A helper" -m "$OK")
printf 'exit 0\n' >"$l/.method/local/helper.sh"
dca "$l"
expect "an edit to a tracked file in .method/local fails files" 1 "done-check: files: FAIL" ".method/local/helper.sh"

# a library that does not load, and a file that does not compile, are
# "could not check" (exit 2), never a pass and never a bare perl error
mkdir -p "$work/broken"
cp -R "$root/method/scripts/method" "$work/broken/"
rm -f "$work/broken/method/lib/tree.pl"
out=$(cd "$u" && bash "$work/broken/method/done-check.sh" --ready 2>&1)
code=$?
expect "a library that does not load is could-not-check (exit 2)" 2 "done-check: NOT READY - could not check: a library of the method did not load"
cp "$root/method/scripts/method/lib/tree.pl" "$work/broken/method/lib/tree.pl"
printf 'sub {\n' >>"$work/broken/method/lib/done.pl"
out=$(cd "$u" && bash "$work/broken/method/done-check.sh" --ready 2>&1)
code=$?
expect "done.pl that does not compile is could-not-check (exit 2), with that last line" 2 "done-check: NOT READY - could not check: perl stopped with exit"
rm -f "$work/broken/method/lib/done.pl"
out=$(cd "$u" && bash "$work/broken/method/done-check.sh" --ready 2>&1)
code=$?
expect "a missing done.pl is could-not-check (exit 2), with that last line" 2 "done-check: NOT READY - could not check: lib/done.pl is not next to done-check.sh"

# --- exit codes ---
(cd "$u" && git checkout -q main)
dca "$u"
expect "HEAD at main's tip: nothing to merge (exit 3)" 3 "done-check: NOTHING TO MERGE - $c0 is refs/remotes/origin/main's tip or behind it"
out=$(cd "$u" && bash "$done_check" 2>&1)
code=$?
expect "no argument is bad usage (exit 2)" 2 "done-check: usage: done-check.sh --ready"
out=$(cd "$u" && bash "$done_check" --ready extra 2>&1)
code=$?
expect "an extra argument is bad usage" 2 "done-check: usage: done-check.sh --ready"
mkdir -p "$work/plain"
out=$(cd "$work/plain" && GIT_CEILING_DIRECTORIES=$work bash "$done_check" --ready 2>&1)
code=$?
expect "outside a git working tree it cannot check (exit 2)" 2 "done-check: NOT READY - could not check: not inside a git working tree"
(cd "$q" && git clone -q remote.git elsewhere 2>/dev/null)
(cd "$v" && git config core.worktree "$q/elsewhere")
dca "$v"
expect "a core.worktree setting that points git elsewhere cannot be checked" 2 "a core.worktree setting points git elsewhere"
(cd "$v" && git config --unset core.worktree)

drop_all
export HOME="$saved_home"
unset GIT_CONFIG_NOSYSTEM
drop_sandbox "$work"
echo "tests: done-check: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
