#!/usr/bin/env bash
# Tests for the three example projects, examples/ (step 7.7;
# docs/plans/step7.md S15, S16). Each example's make.sh builds it in a
# throwaway folder; it gets a bare "origin" of its own, and the method is
# installed on a branch, install, as S16's first install does: the
# release's own sync from a throwaway release (this repo's method/ and
# scripts/release/, tagged v0.7.0), then setup-write.sh with the example's
# answers.txt. Then, per example:
# - the floor holds: method-files finds nothing, the profile is the
#   answers', and the checking agents and the profile keep Opus 5.5;
# - done-check on the install branch, while main has no method.conf,
#   finds no tier or verdicts-start problem and asks for the full route
#   (three reviewers);
# - once the install is on main: status finds nothing that needs a look,
#   run-checks is green with method-files and the project's own checks,
#   done-check on a branch with one product change finds no tier or
#   verdicts-start problem, and sync and setup run again change nothing;
# - records-keeper (an adopted project): its own hook, allow and deny
#   rules and CLAUDE.md lines survive, the card names Python, its scanner
#   row and the CRLF file, which is not changed, the live-write helper
#   refuses a write with no reason, a second post adds no row twice, and
#   before the install post-rows refuses;
# - notes-site: the smoke row, turned on by hand, runs and stays on.
# Apart from the examples: make.sh's refusals, the same history whoever
# runs it, and setup's choice of the files stored with CRLF that it names.
# shellcheck disable=SC2016 # single-quoted perl code is expanded by perl
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: examples"
started=$(date +%s)
root=$(repo_root)
work=$(new_sandbox_dir) || abort_sandbox
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM CLAUDE_CODE_EXECPATH CLAUDE_CODE_EFFORT_LEVEL CLAUDE_CODE_REMOTE CLAUDE_PROJECT_DIR GH_REPO CI KEEPER_LIVE
mkdir -p "$HOME"
git config --global user.name T
git config --global user.email t@example.invalid
git config --global commit.gpgsign false
git config --global core.autocrlf false
git config --global init.defaultBranch main

# the release
rel="$work/rel"
if ! { mkdir -p "$rel/scripts" &&
  cp -R "$root/method" "$rel/method" &&
  cp -R "$root/scripts/release" "$rel/scripts/release" &&
  (cd "$rel" && git init -q && git add -A && git commit -q -m release && git tag v0.7.0); }; then
  abort_sandbox
fi

# snap DIR: every entry under DIR but .git and .method/local, with each
# file's hash
snap() {
  perl -MFile::Find -MDigest::SHA -e 'my $r = shift; my @l;
    find({ no_chdir => 1, wanted => sub {
      if (m{/\.git\z} || m{/\.method/local\z}) { $File::Find::prune = 1; return }
      return if $_ eq $r;
      my $rel = substr($_, length($r) + 1);
      if (-l $_) { push @l, "L $rel" } elsif (-f _) { push @l, "F $rel " . Digest::SHA->new(256)->addfile($_, "b")->hexdigest }
      elsif (-d _) { push @l, "D $rel" } } }, $r);
    print "$_\n" for sort @l' "$1"
}

# findings DIR: what the installed lib/lock.pl's verify (method-files) finds
findings() {
  (cd "$1" && perl -e 'require "./scripts/method/lib/lock.pl"; my $v = Lock::verify("."); print "$_->[1]\n" for @{ $v->{findings} }') 2>&1
}

# jget FILE EXPR: the perl EXPR on $d, the decoded JSON FILE, printed
jget() {
  perl -MJSON::PP -e 'open my $h, "<", $ARGV[0] or die; my $d = JSON::PP->new->decode(do { local $/; <$h> }); my $v = eval $ARGV[1]; die $@ if $@; print ref $v ? JSON::PP->new->canonical->encode($v) : (defined $v ? $v : "(undef)"), "\n"' "$1" "$2"
}

# has FILE TEXT...: FILE holds each TEXT; else prints the missing ones
has() {
  h_file=$1
  shift
  h_missing=""
  for t in "$@"; do
    grep -F -q -- "$t" "$h_file" || h_missing="$h_missing [$t]"
  done
  [ -z "$h_missing" ] || {
    printf 'missing in %s:%s\n' "${h_file##*/}" "$h_missing"
    return 1
  }
}

# line FILE PREFIX: the first line of FILE that starts with PREFIX
line() {
  grep -F -- "$2" "$1" | head -1
}

# rc NAME: the exit code step NAME of the example in o left
rc() {
  cat "$o/$1.rc" 2>/dev/null || echo none
}

# step NAME COMMAND...: runs COMMAND in the example's project p; its output
# goes to o/NAME.txt and its exit code to o/NAME.rc
step() {
  st_name=$1
  shift
  (cd "$p" && "$@") >"$o/$st_name.txt" 2>&1
  echo $? >"$o/$st_name.rc"
}

# git_q ARG...: git in p, quietly
git_q() {
  (cd "$p" && git "$@") >/dev/null 2>&1
}

# build EX: the example EX made in $work/EX (p), with its outputs in
# $work/EX.out (o), through every step the cases read. A step that fails
# leaves its exit code; the steps after it still run, so each case can say
# what it saw.
build() {
  ex=$1
  p="$work/$ex"
  o="$work/$ex.out"
  mkdir -p "$o"
  bash "$root/examples/$ex/make.sh" "$p" >"$o/make.txt" 2>&1
  echo $? >"$o/make.rc"
  [ -d "$p/.git" ] || return 0
  snap "$p" >"$o/made.snap"
  git init -q --bare "$work/$ex.git"
  git_q remote add origin "$work/$ex.git"
  git_q push -q origin main
  git_q checkout -q -b install
  # the first install (S16): the release's sync, then setup with the answers
  step sync1 bash "$rel/scripts/release/sync.sh" --to . --write
  cp "$root/examples/$ex/answers.txt" "$p/.claude/setup-answers.txt"
  step card bash scripts/method/setup-write.sh
  step setup1 bash scripts/method/setup-write.sh --write
  # notes-site's owner turns the smoke row on, as the card says, and names
  # it in TESTS.md, as the checks file asks
  if [ "$ex" = notes-site ]; then
    perl -pi -e 's/^#(smoke\t)/$1/' "$p/checks/project.tsv"
    printf '| `smoke` | The start page does not open: a link on it goes nowhere | `bash scripts/method/run-checks.sh` |\n' >>"$p/TESTS.md"
  fi
  git_q add -A
  git_q commit -q -m "Install the method v0.7.0" -m "Review-Verdict: not-required - first install of the method v0.7.0"
  git_q push -q origin install
  step dc_install bash scripts/method/done-check.sh --ready
  # the install reaches main
  git_q checkout -q main
  git_q merge -q --ff-only install
  git_q push -q origin main
  step status bash scripts/method/status.sh --quick
  step checks bash scripts/method/run-checks.sh
  # sync and setup again
  snap "$p" >"$o/before-again.snap"
  step sync2 bash "$rel/scripts/release/sync.sh" --to . --write
  step setup2 bash scripts/method/setup-write.sh --write
  snap "$p" >"$o/after-again.snap"
  (cd "$p" && git status --porcelain) >"$o/after-again.git" 2>&1
  # a branch with one product change
  git_q checkout -q -b work
  case "$ex" in
    word-game) printf 'harbour\n' >>"$p/words.txt" ;;
    notes-site) perl -pi -e 's{(<li>Leave one corner wild for the bees.</li>)}{$1\n<li>Plant garlic in the autumn.</li>}' "$p/pages/garden.html" ;;
    records-keeper) printf 'seed packets,350,2025-11-12\n' >>"$p/ledger.csv" ;;
  esac
  git_q commit -q -a -m "One product change" -m "Review-Verdict: not-required - a test of the tier"
  git_q push -q origin work
  step dc_work bash scripts/method/done-check.sh --ready
}

# per-example case names; an example is built only when one of its cases
# is wanted
cases() {
  printf '%s\n' "$1: make.sh builds the project on main, before the method" \
    "$1: the answers keep the floor: sync and setup-write take them, method-files finds nothing, and the profile and the checking agents are as released" \
    "$1: done-check on the install branch, while main has no method.conf: no tier or verdicts-start problem, and the install takes the full route (three reviewers)" \
    "$1: once the install is on main, status finds nothing that needs a look" \
    "$1: run-checks is green, with method-files and the project's own checks among those passed" \
    "$1: done-check on a branch with one product change: no tier or verdicts-start problem" \
    "$1: sync and setup run again change nothing"
  case "$1" in
    records-keeper)
      printf '%s\n' "records-keeper: the project's own hook, allow rules, deny rule and CLAUDE.md lines survive the install" \
        "records-keeper: setup's card names Python and the suggested scanner row" \
        "records-keeper: the CRLF file is reported on the card, not changed" \
        "records-keeper: the live-write helper refuses a write with no reason, does a dry run with one, and writes only with --live, never a row twice; before the install post-rows refuses"
      ;;
    notes-site)
      printf '%s\n' "notes-site: the smoke row, turned on by hand, runs in run-checks and stays on when setup runs again"
      ;;
  esac
}

# --- make.sh refuses where it must, before it writes ---
n="make.sh refuses a folder inside the repository it sits in, a folder that is not empty (or cannot be listed) and a missing parent, and writes nothing"
if wanted "$n"; then
  r=""
  fake="$work/fake"
  mkdir -p "$fake/examples" "$work/full"
  cp -R "$root/examples/word-game" "$fake/examples/word-game" && cp "$root/examples/lib.sh" "$fake/examples/lib.sh"
  printf 'x\n' >"$work/full/kept.txt"
  before=$(snap "$fake")
  for target in "$fake/inside" "$fake/examples" "$work/full" "$work/no-such/folder"; do
    out=$(bash "$fake/examples/word-game/make.sh" "$target" 2>&1)
    code=$?
    if [ "$code" -ne 2 ] || ! printf '%s\n' "$out" | grep -q 'make: REFUSED - '; then
      r="$r [$target] exit $code: $out"
    fi
  done
  out=$(cd "$fake" && bash examples/word-game/make.sh "inside2" 2>&1)
  code=$?
  [ "$code" -eq 2 ] || r="$r [a relative folder inside] exit $code: $out"
  if ln -s "$fake" "$work/link-in" 2>/dev/null && [ -L "$work/link-in" ]; then
    out=$(bash "$fake/examples/word-game/make.sh" "$work/link-in/via-link" 2>&1)
    code=$?
    [ "$code" -eq 2 ] || r="$r [a folder reached through a link into the repository] exit $code: $out"
  fi
  # a folder that is not empty and that ls cannot list (write and enter
  # only); as root ls lists it anyway, so this part runs only where it
  # cannot
  mkdir -p "$work/shut" && printf 'kept\n' >"$work/shut/game.sh" && chmod 300 "$work/shut"
  if ! ls -A "$work/shut" >/dev/null 2>&1; then
    out=$(bash "$fake/examples/word-game/make.sh" "$work/shut" 2>&1)
    code=$?
    if [ "$code" -ne 2 ] || ! printf '%s\n' "$out" | grep -q 'make: REFUSED - '; then r="$r [a folder ls cannot list] exit $code: $out"; fi
  fi
  chmod 700 "$work/shut"
  [ "$(cat "$work/shut/game.sh")" = kept ] || r="$r [the file in the folder ls cannot list was written over]"
  [ "$(snap "$fake")" = "$before" ] || r="$r [something was written in the repository]"
  [ "$(ls -A "$work/full")" = kept.txt ] || r="$r [something was written in the folder that is not empty]"
  [ ! -e "$work/no-such" ] || r="$r [the missing parent was made]"
  if [ -z "$r" ]; then pass "$n"; else fail "$n" "$r"; fi
fi

# --- make.sh gives the same history whoever runs it ---
n="make.sh gives the same history under the caller's own git name, GIT_AUTHOR_* and GIT_COMMITTER_* and commit hooks, which never run"
if wanted "$n"; then
  r=""
  bash "$root/examples/word-game/make.sh" "$work/same1" >"$work/same1.txt" 2>&1 || r="$r [make.sh: $(tail -2 "$work/same1.txt")]"
  # a caller with a name, hooks that change the message and leave a mark,
  # and the GIT_AUTHOR_* and GIT_COMMITTER_* variables of their own
  mkdir -p "$work/home2" "$work/hooks2"
  printf '#!/bin/sh\necho hook >>"%s"\necho "Signed-off-by: Real Person" >>"$1"\n' "$work/hook-ran" >"$work/hooks2/commit-msg"
  printf '#!/bin/sh\necho hook >>"%s"\n' "$work/hook-ran" >"$work/hooks2/pre-commit"
  chmod +x "$work/hooks2/commit-msg" "$work/hooks2/pre-commit"
  printf '[user]\n\tname = Real Person\n\temail = real@example.invalid\n[core]\n\thooksPath = %s\n' "$work/hooks2" >"$work/home2/.gitconfig"
  HOME="$work/home2" GIT_AUTHOR_NAME="Real Person" GIT_AUTHOR_EMAIL=real@example.invalid GIT_COMMITTER_NAME="Real Person" \
    GIT_COMMITTER_EMAIL=real@example.invalid bash "$root/examples/word-game/make.sh" "$work/same2" >"$work/same2.txt" 2>&1 ||
    r="$r [make.sh as the caller: $(tail -2 "$work/same2.txt")]"
  id1=$(cd "$work/same1" && git rev-parse HEAD 2>&1)
  id2=$(cd "$work/same2" && git rev-parse HEAD 2>&1)
  [ "$id1" = "$id2" ] || r="$r [$id1, then $id2: $(cd "$work/same2" && git log -1 --format='%an <%ae>, %cn <%ce>' 2>&1)]"
  [ ! -e "$work/hook-ran" ] || r="$r [the caller's hooks ran]"
  if [ -z "$r" ]; then pass "$n"; else fail "$n" "$r"; fi
fi

n="setup names a file stored with CRLF that no attribute asks for, and none whose attributes ask for CRLF or no conversion"
if wanted "$n"; then
  r=""
  q="$work/eol"
  mkdir -p "$q"
  for f in a.bat b.ps1 e.cmd d.png f.dat c.txt i.lf; do printf 'x\r\ny\r\n' >"$q/$f"; done
  # committed with CRLF first, then the attributes: git keeps them as stored
  if (cd "$q" && git init -q && git add -A && git commit -q -m files &&
    printf '%s\n' '*.bat eol=crlf' '*.ps1 text eol=crlf' '*.cmd text=auto eol=crlf' '*.png binary' '*.dat -text' '*.lf text eol=lf' >.gitattributes &&
    git add .gitattributes && git commit -q -m attributes); then
    got=$(cd "$q" && perl -e 'require $ARGV[0]; print join(" ", @{ Setup::detect(".")->{crlf} })' "$root/method/scripts/method/lib/setup.pl" 2>&1)
    [ "$got" = "c.txt i.lf" ] || r="$r [named: '$got', not 'c.txt i.lf'; git: $(cd "$q" && git ls-files --eol | tr '\t\n' '  ')]"
  else
    r="$r [the scratch repository could not be made]"
  fi
  if [ -z "$r" ]; then pass "$n"; else fail "$n" "$r"; fi
fi

for ex in word-game notes-site records-keeper; do
  wanted_ex=0
  while IFS= read -r n; do
    if wanted "$n"; then wanted_ex=1; fi
  done <<EOF
$(cases "$ex")
EOF
  [ "$wanted_ex" = 1 ] || continue
  build "$ex"
  case "$ex" in
    word-game) commits=1 profile=budget ;;
    notes-site) commits=2 profile=balanced ;;
    records-keeper) commits=3 profile=best ;;
  esac

  n="$ex: make.sh builds the project on main, before the method"
  if wanted "$n"; then
    r=""
    [ "$(rc make)" = 0 ] || r="$r [make.sh exit $(rc make)] $(tail -3 "$o/make.txt")"
    got_first=$(cd "$p" && git rev-list --count "$(git rev-parse install)^" 2>/dev/null)
    [ "$got_first" = "$commits" ] || r="$r [$got_first commits on main before the install, not $commits]"
    if grep -q -e ' scripts/method/' -e ' AGENTS.md ' "$o/made.snap" 2>/dev/null; then r="$r [the method or AGENTS.md was there before the install]"; fi
    if [ "$ex" != records-keeper ] && grep -q -e ' CLAUDE.md ' -e ' .claude/' "$o/made.snap" 2>/dev/null; then r="$r [a CLAUDE.md or .claude/ of its own]"; fi
    if [ -z "$r" ]; then pass "$n"; else fail "$n" "$r"; fi
  fi

  n="$ex: the answers keep the floor: sync and setup-write take them, method-files finds nothing, and the profile and the checking agents are as released"
  if wanted "$n"; then
    r=""
    [ "$(rc sync1)" = 0 ] || r="$r [sync exit $(rc sync1)] $(tail -3 "$o/sync1.txt")"
    [ "$(rc setup1)" = 0 ] || r="$r [setup-write exit $(rc setup1)] $(grep -v '^setup: \(new\|block\|unchanged\|kept\|update\) ' "$o/setup1.txt" | tail -4)"
    f=$(findings "$p")
    [ -z "$f" ] || r="$r [method-files finds: $f]"
    lock_profile=$(grep "^profile	" "$p/scripts/method/method.lock" 2>/dev/null | cut -f2)
    [ "$lock_profile" = "$profile" ] || r="$r [method.lock's profile is '$lock_profile', not $profile]"
    want=$(grep "^$profile	" "$rel/method/scripts/method/profiles.tsv" | cut -f2)
    got=$(jget "$p/.claude/settings.json" '{model => $d->{model}, effortLevel => $d->{effortLevel}, availableModels => $d->{availableModels}}' 2>&1)
    [ "$got" = "$want" ] || r="$r [the settings' profile keys are $got, not $want]"
    case "$got" in *'"claude-opus-5-5"'*) ;; *) r="$r [availableModels without claude-opus-5-5]" ;; esac
    for g in reviewer security-checker; do
      a="$p/.claude/agents/method/method-$g.md"
      if ! grep -q '^model: claude-opus-5-5$' "$a" 2>/dev/null || ! grep -q '^effort: xhigh$' "$a" 2>/dev/null; then r="$r [method-$g is not on claude-opus-5-5 at xhigh]"; fi
    done
    if [ "$(jget "$p/.claude/settings.json" '$d->{disableAllHooks} ? "on" : "off"' 2>&1)" != off ]; then r="$r [disableAllHooks is on]"; fi
    if [ -z "$r" ]; then pass "$n"; else fail "$n" "$r"; fi
  fi

  n="$ex: done-check on the install branch, while main has no method.conf: no tier or verdicts-start problem, and the install takes the full route (three reviewers)"
  if wanted "$n"; then
    r=""
    if (cd "$p" && git cat-file -e "$(git rev-parse install)~1:.claude/method.conf") 2>/dev/null; then r="$r [main had a method.conf before the install]"; fi
    has "$o/dc_install.txt" 'done-check: tier: PASS - ' 'done-check: verdicts start: PASS - ' 'done-check: deep review: FAIL - the change touches high-risk paths' \
      'needs three receipts of method-reviewer' 'done-check: NOT READY' >"$o/has.txt" ||
      r="$r $(cat "$o/has.txt"); $(grep -e 'tier:' -e 'verdicts start:' -e 'deep review:' "$o/dc_install.txt")"
    if [ -z "$r" ]; then pass "$n"; else fail "$n" "$r"; fi
  fi

  n="$ex: once the install is on main, status finds nothing that needs a look"
  if wanted "$n"; then
    if [ "$(rc status)" = 0 ] && has "$o/status.txt" 'status: nothing needs a look' 'records: PASS - 9 records present; CLAUDE.md imports AGENTS.md' >/dev/null; then
      pass "$n"
    else
      fail "$n" "exit $(rc status): $(grep -v ': PASS - ' "$o/status.txt")"
    fi
  fi

  n="$ex: run-checks is green, with method-files and the project's own checks among those passed"
  if wanted "$n"; then
    passed=" $(sed -n 's/^passed: //p' "$o/checks.txt") "
    r=""
    for id in method-files fast-tests tree-unchanged; do
      case "$passed" in *" $id "*) ;; *) r="$r [$id did not pass]" ;; esac
    done
    if [ "$(rc checks)" != 0 ] || ! grep -q '^run-checks: PASS - ' "$o/checks.txt"; then r="$r [exit $(rc checks)]"; fi
    if [ -z "$r" ]; then pass "$n"; else fail "$n" "$r $(tail -4 "$o/checks.txt")"; fi
  fi

  n="$ex: done-check on a branch with one product change: no tier or verdicts-start problem"
  if wanted "$n"; then
    tier=$(line "$o/dc_work.txt" 'done-check: tier: ')
    case "$ex" in
      records-keeper) want='HIGH_RISK_PATHS, main' ;; # strict: every change is high-risk
      *) want='no changed path is high-risk' ;;
    esac
    vs=$(line "$o/dc_work.txt" 'done-check: verdicts start: ')
    case "$tier" in
      "done-check: tier: PASS - "*"$want"*)
        case "$vs" in
          "done-check: verdicts start: PASS - VERDICTS_FROM is "*" both on main and in this change") pass "$n" ;;
          *) fail "$n" "wanted verdicts start to PASS with VERDICTS_FROM unmoved; exit $(rc dc_work): $vs" ;;
        esac
        ;;
      *) fail "$n" "wanted a PASS naming '$want'; exit $(rc dc_work): $tier" ;;
    esac
  fi

  n="$ex: sync and setup run again change nothing"
  if wanted "$n"; then
    r=""
    [ "$(rc sync2)" = 0 ] || r="$r [sync exit $(rc sync2)] $(tail -2 "$o/sync2.txt")"
    has "$o/sync2.txt" 'sync: plan: 0 install, 0 update, ' ', 0 remove, 0 conflict' >"$o/has.txt" || r="$r $(cat "$o/has.txt")"
    [ "$(rc setup2)" = 0 ] || r="$r [setup-write exit $(rc setup2)] $(tail -2 "$o/setup2.txt")"
    has "$o/setup2.txt" 'setup: plan: 0 new, 0 block, 0 update, ' >"$o/has.txt" || r="$r $(cat "$o/has.txt")"
    cmp -s "$o/before-again.snap" "$o/after-again.snap" || r="$r [files changed: $(diff "$o/before-again.snap" "$o/after-again.snap" | head -4 | tr '\n' ' ')]"
    [ ! -s "$o/after-again.git" ] || r="$r [git status: $(head -3 "$o/after-again.git" | tr '\n' ' ')]"
    if [ -z "$r" ]; then pass "$n"; else fail "$n" "$r"; fi
  fi

  if [ "$ex" = records-keeper ]; then
    n="records-keeper: the project's own hook, allow rules, deny rule and CLAUDE.md lines survive the install"
    if wanted "$n"; then
      r=""
      s="$p/.claude/settings.json"
      got=$(jget "$s" '[grep { $_->{matcher} eq "Write|Edit" && $_->{hooks}[0]{command} eq "bash scripts/check-ledger.sh" } @{ $d->{hooks}{PostToolUse} || [] }]' 2>&1)
      case "$got" in '[{'*) ;; *) r="$r [its PostToolUse hook: $got]" ;; esac
      got=$(jget "$s" '$d->{permissions}{allow}' 2>&1)
      [ "$got" = '["Bash(bash scripts/check-ledger.sh)","Bash(bash scripts/post-rows.sh --reason *)"]' ] || r="$r [allow: $got]"
      got=$(jget "$s" 'scalar grep { $_ eq "Bash(bash scripts/post-rows.sh *--live*)" } @{ $d->{permissions}{deny} }' 2>&1)
      [ "$got" = 1 ] || r="$r [its own deny rule is not there once]"
      for l in '# Notes for Claude' 'Amounts in ledger.csv are whole cents.' 'Never run scripts/post-rows.sh with --live; the owner does.' '@AGENTS.md'; do
        grep -q -x -F -- "$l" "$p/CLAUDE.md" || r="$r [CLAUDE.md lacks: $l]"
      done
      if [ -z "$r" ]; then pass "$n"; else fail "$n" "$r"; fi
    fi

    n="records-keeper: setup's card names Python and the suggested scanner row"
    if wanted "$n"; then
      if [ "$(rc card)" = 0 ] && has "$o/card.txt" 'Found Python (requirements.txt): the suggested scanner row is deps-python' >"$o/has.txt"; then
        pass "$n"
      else
        fail "$n" "exit $(rc card): $(cat "$o/has.txt")"
      fi
    fi

    n="records-keeper: the CRLF file is reported on the card, not changed"
    if wanted "$n"; then
      r=""
      has "$o/card.txt" 'Line ends: 1 file is stored with CRLF line ends: exports/2025-export.csv.' 'setup changes none' >"$o/has.txt" || r="$r $(cat "$o/has.txt")"
      made=$(grep ' exports/2025-export.csv ' "$o/made.snap")
      now=$(snap "$p" | grep ' exports/2025-export.csv ')
      [ -n "$made" ] && [ "$made" = "$now" ] || r="$r [the file changed: '$made' then '$now']"
      perl -e 'open my $h, "<:raw", $ARGV[0] or exit 1; local $/; my $t = <$h>; exit($t =~ /\r\n/ && $t !~ /(?<!\r)\n/ ? 0 : 1)' "$p/exports/2025-export.csv" || r="$r [the file no longer has CRLF line ends]"
      eol=$(cd "$p" && git ls-files --eol -- exports/2025-export.csv)
      case "$eol" in i/crlf*) ;; *) r="$r [git stores it as: $eol]" ;; esac
      if [ -z "$r" ]; then pass "$n"; else fail "$n" "$r"; fi
    fi

    n="records-keeper: the live-write helper refuses a write with no reason, does a dry run with one, and writes only with --live, never a row twice; before the install post-rows refuses"
    if wanted "$n"; then
      r=""
      live="$work/records-keeper-live.csv"
      rm -f "$live"
      # before the install the helper is not there: post-rows refuses
      mkdir -p "$work/rk-before"
      (cd "$p" && git archive install~1) | (cd "$work/rk-before" && tar -xf -)
      out=$(cd "$work/rk-before" && bash scripts/post-rows.sh --reason "before the install" --live 2>&1)
      code=$?
      if [ "$code" -ne 2 ] || [ -e "$live" ] || ! printf '%s\n' "$out" | grep -q '^post-rows: REFUSED - scripts/method/live-write.sh is not here'; then
        r="$r [before the install: exit $code: $out]"
      fi
      out=$(cd "$p" && bash scripts/post-rows.sh 2>&1)
      code=$?
      if [ "$code" -ne 2 ] || [ -e "$live" ] || ! printf '%s\n' "$out" | grep -q 'live-write: REFUSED - no reason given'; then r="$r [no reason: exit $code: $out]"; fi
      out=$(cd "$p" && bash scripts/post-rows.sh --reason "a test of the dry run" 2>&1)
      code=$?
      if [ "$code" -ne 0 ] || [ -e "$live" ] || [ "$(printf '%s\n' "$out" | head -1)" != 'live-write: reason: a test of the dry run' ] ||
        ! printf '%s\n' "$out" | grep -q 'live-write: dry run, nothing written'; then r="$r [a dry run: exit $code: $out]"; fi
      out=$(cd "$p" && bash scripts/post-rows.sh --reason "a test of the write" --live 2>&1)
      code=$?
      if [ "$code" -ne 0 ] || [ "$(wc -l <"$live" 2>/dev/null | tr -d ' ')" != 5 ]; then r="$r [--live: exit $code, $(wc -l <"$live" 2>&1) lines written: $out]"; fi
      # a second post adds no row twice (the owner's NEVER_WRONG answer)
      out=$(cd "$p" && bash scripts/post-rows.sh --reason "a test of a second write" --live 2>&1)
      code=$?
      if [ "$code" -ne 0 ] || [ "$(wc -l <"$live" 2>/dev/null | tr -d ' ')" != 5 ]; then r="$r [--live again: exit $code, $(wc -l <"$live" 2>&1) lines: $out]"; fi
      if [ -z "$r" ]; then pass "$n"; else fail "$n" "$r"; fi
    fi
  fi

  if [ "$ex" = notes-site ]; then
    n="notes-site: the smoke row, turned on by hand, runs in run-checks and stays on when setup runs again"
    if wanted "$n"; then
      r=""
      case " $(sed -n 's/^passed: //p' "$o/checks.txt") " in *" smoke "*) ;; *) r="$r [smoke did not pass in run-checks: $(tail -3 "$o/checks.txt")]" ;; esac
      grep -q "^smoke	any	-	" "$p/checks/project.tsv" || r="$r [the smoke row is off after setup ran again]"
      has "$o/setup2.txt" 'stays on, as it was turned on with the same command' >"$o/has.txt" || r="$r $(cat "$o/has.txt")"
      if [ -z "$r" ]; then pass "$n"; else fail "$n" "$r"; fi
    fi
  fi
done

drop_sandbox "$work" || true
echo "tests: examples: $tests_pass passed, $tests_fail failed, $tests_skip skipped ($(($(date +%s) - started)) s)"
[ "$tests_fail" -eq 0 ]
