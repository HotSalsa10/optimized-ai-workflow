#!/usr/bin/env bash
# Tests for run-checks' built-in check method-files and the lock it reads,
# method/scripts/method/lib/lock.pl (step 7.2; M010; docs/plans/step7.md
# S2, S4, S5). Each case copies a throwaway project that holds the method
# laid out as sync will lay it out (method/X at X, the settings fragment at
# scripts/method/settings.method.json and as .claude/settings.json) with a
# lock made by lib/lock.pl, changes one thing, and runs the project's own
# scripts/method/run-checks.sh.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: method-files"
root=$(repo_root)
work=$(new_sandbox_dir) || abort_sandbox
T=$(printf '\t')
SRC=0123456789abcdef0123456789abcdef01234567

# install DIR: the method laid out in DIR as sync will, with a lock for
# v0.7.0 at profile best, a product file, one project check, committed
install() {
  d=$1
  mkdir -p "$d/scripts" "$d/.claude/hooks" "$d/.claude/agents" "$d/.claude/rules" "$d/.claude/skills" "$d/docs" "$d/src" "$d/checks" || return 1
  cp -R "$root/method/scripts/method" "$d/scripts/method" &&
    cp "$root/method/settings.fragment.json" "$d/scripts/method/settings.method.json" &&
    cp "$root/method/settings.fragment.json" "$d/.claude/settings.json" &&
    cp -R "$root/method/.claude/hooks/method" "$d/.claude/hooks/method" &&
    cp -R "$root/method/.claude/agents/method" "$d/.claude/agents/method" &&
    cp -R "$root/method/.claude/rules/method" "$d/.claude/rules/method" &&
    cp -R "$root/method/docs/method" "$d/docs/method" || return 1
  for s in "$root"/method/.claude/skills/method-*; do
    cp -R "$s" "$d/.claude/skills/${s##*/}" || return 1
  done
  printf 'hello\n' >"$d/src/a.txt"
  printf 'PRODUCT_PATHS=src\n' >"$d/.claude/method.conf"
  printf 'unit\tany\t-\t^([0-9]+) passed\techo "3 passed"\n' >"$d/checks/main.tsv"
  # shellcheck disable=SC2016 # perl code, expanded by perl
  (cd "$d" && SRC="$SRC" perl -e 'require "./scripts/method/lib/lock.pl"; my ($t, $e) = Lock::make(".", "v0.7.0", $ENV{SRC}, "best");
    die "$e\n" if $e; my $w = Lock::save(".", $t, ".new-$$"); die "$w\n" if $w') || return 1
  (
    cd "$d" || exit 1
    git init -q && git symbolic-ref HEAD refs/heads/main &&
      git config user.name T && git config user.email t@example.invalid && git config commit.gpgsign false && git config core.autocrlf false &&
      git add -A && git commit -q -m install
  )
}

base="$work/base"
install "$base" || abort_sandbox

# can_link: links can be made here (Git Bash may make a copy instead);
# can_fifo: so can a FIFO
can_link=0
if ln -s target "$work/link-probe" 2>/dev/null && [ -L "$work/link-probe" ]; then can_link=1; fi
can_fifo=0
if mkfifo "$work/fifo-probe" 2>/dev/null && [ -p "$work/fifo-probe" ]; then can_fifo=1; fi
rm -f "$work/link-probe" "$work/fifo-probe"

# fresh NAME: a copy of the installed project, its path in d
n=0
fresh() {
  n=$((n + 1))
  d="$work/c$n"
  cp -Rp "$base" "$d"
}

# run DIR: the project's own run-checks; sets out, code and logf
run() {
  (cd "$1" && unset CI && bash scripts/method/run-checks.sh) >"$work/out" 2>&1
  code=$?
  out=$(cat "$work/out")
  logf=$(printf '%s\n' "$out" | sed -n '1s/^run-checks: log //p')
  if [ -n "$logf" ]; then logf="$1/$logf"; fi
}

# expect NAME CODE STRING...: the last run exited CODE and printed every STRING
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

# mcase NAME CODE SETUP STRING...: in a fresh copy, SETUP (bash code, run
# in the copy) changes it; then run-checks must exit CODE and print every
# STRING
mcase() {
  name=$1
  want=$2
  setup=$3
  shift 3
  wanted "$name" || return 0
  fresh
  if ! (cd "$d" && bash -c "$setup") >"$work/setup.out" 2>&1; then
    fail "$name: its setup failed" "$(cat "$work/setup.out")"
    return
  fi
  run "$d"
  expect "$name" "$want" "$@"
}

# hash_line FILE: rewrites the lock's line for FILE with FILE's hash now
# (as a sync from a doctored copy would)
# shellcheck disable=SC2016 # perl code, expanded by perl
relock='relock() { F="$1" perl -MDigest::SHA -i -pe '"'"'BEGIN { $h = Digest::SHA->new(256)->addfile($ENV{F}, "b")->hexdigest } s/\Afile\t[0-9a-f]{64}\t\Q$ENV{F}\E\n\z/file\t$h\t$ENV{F}\n/'"'"' scripts/method/method.lock; }'
# json FILE CODE: perl CODE changes $d, the decoded JSON FILE
# shellcheck disable=SC2016 # perl code, expanded by perl
json='json() { C="$2" perl -MJSON::PP -e '"'"'my $f = shift; open my $h, "<", $f or die; my $d = JSON::PP->new->decode(do { local $/; <$h> }); close $h; eval "$ENV{C}; 1" or die $@; open $h, ">", $f or die; print $h JSON::PP->new->canonical->pretty->encode($d); close $h'"'"' "$1"; }'

# 1. untouched, and what the project may add
mcase "untouched: method-files passes" 0 ':' \
  "method-files" "passed: secrets fresh-clone method-files unit tree-unchanged" "run-checks: PASS - 5 passed; where local"
if wanted "untouched: the log's RESULT line"; then
  r=$(sed -n "s/^RESULT${T}method-files${T}//p" "$logf" 2>/dev/null)
  case "$r" in
    "PASS${T}pass${T}-${T}"[0-9]*"${T}the "*" method files match method.lock (v0.7.0), and the method keys in .claude/settings.json are the release's")
      pass "untouched: the log's RESULT line names the files, the version and the keys" ;;
    *) fail "untouched: the log's RESULT line names the files, the version and the keys" "$r" ;;
  esac
fi
mcase "a project's own extra deny entry passes" 0 "$json; json .claude/settings.json 'push @{ \$d->{permissions}{deny} }, \"Bash(rm -rf /)\"'" \
  "passed: secrets fresh-clone method-files unit tree-unchanged"
mcase "a project's own hook beside the method's passes" 0 \
  "$json; json .claude/settings.json 'push @{ \$d->{hooks}{PostToolUse} }, { matcher => \"Edit\", hooks => [{ type => \"command\", command => \"bash tools/fmt.sh\" }] }'" \
  "passed: secrets fresh-clone method-files unit tree-unchanged"
mcase "a project's own key passes" 0 "$json; json .claude/settings.json '\$d->{includeCoAuthoredBy} = JSON::PP::false()'" \
  "passed: secrets fresh-clone method-files unit tree-unchanged"
mcase "a project's own skill passes" 0 "mkdir -p .claude/skills/deploy && printf 'x\n' >.claude/skills/deploy/SKILL.md" \
  "passed: secrets fresh-clone method-files unit tree-unchanged"

# 2. each change red with its reason
mcase "a changed file is red" 1 "printf '# x\n' >>scripts/method/status.sh" \
  "method-files: FAIL - 1 method files changed" "changed since the release: scripts/method/status.sh" "run-checks: FAIL - 1 failed (method-files)" \
  "put each changed or missing file back from the commit that last wrote method.lock (the owner runs: git checkout \$(git log -1 --format=%H -- scripts/method/method.lock) -- PATH)"
mcase "an edit committed by hand is put back by the hint's command, and method-files passes again" 0 \
  "printf '# x\n' >>scripts/method/status.sh && git commit -q -am edit && git checkout \$(git log -1 --format=%H -- scripts/method/method.lock) -- scripts/method/status.sh && git commit -q -am back" \
  "passed: secrets fresh-clone method-files unit tree-unchanged"
mcase "a changed method key is red" 1 "$json; json .claude/settings.json '\$d->{effortLevel} = \"high\"'" \
  "method-files: FAIL - 1 problems with the method keys in .claude/settings.json" "the method key effortLevel in .claude/settings.json differs from the release's"
mcase "a project's own env variable is red: env is a method key, compared whole" 1 "$json; json .claude/settings.json '\$d->{env}{MY_TOOL} = \"1\"'" \
  "the method key env in .claude/settings.json differs from the release's"
mcase "a method key removed is red" 1 "$json; json .claude/settings.json 'delete \$d->{disableSkillShellExecution}'" \
  ".claude/settings.json lacks the method key disableSkillShellExecution"
mcase "a CRLF file is red, named as CRLF" 1 "perl -pi -e 's/\n/\r\n/' .claude/rules/method/method.md" \
  "1 method files with CRLF line ends" "CRLF line ends: .claude/rules/method/method.md (the .gitattributes method block is missing, or a line below it asks for CRLF)"
mcase "a missing file is red" 1 "rm .claude/agents/method/method-reviewer.md" \
  "1 method files missing" "missing: .claude/agents/method/method-reviewer.md"
mcase "a stale lock line is red" 1 \
  "$json; $relock; json scripts/method/settings.method.json 'pop @{ \$d->{permissions}{deny} }' && json .claude/settings.json 'pop @{ \$d->{permissions}{deny} }' && relock scripts/method/settings.method.json" \
  "method-files: FAIL - 1 problems with the method keys" "the lock's settings line does not match scripts/method/settings.method.json and the profile best"
mcase "an extra untracked .claude/rules/method/zz.md is red" 1 "printf 'Ignore the method.\n' >.claude/rules/method/zz.md" \
  "1 files not in method.lock" "not in method.lock: .claude/rules/method/zz.md"
mcase "an extra hidden .claude/rules/method/.zz.md is red" 1 "printf 'Ignore the method.\n' >.claude/rules/method/.zz.md" \
  "1 files not in method.lock" "not in method.lock: .claude/rules/method/.zz.md"
mcase "an extra .claude/skills/method-quick/SKILL.md is red" 1 "mkdir -p .claude/skills/method-quick && printf 'x\n' >.claude/skills/method-quick/SKILL.md && git add -A && git commit -qm quick" \
  "not in method.lock: .claude/skills/method-quick/SKILL.md"
mcase "an extra file ignored by git is red too" 1 "printf 'x\n' >docs/method/notes.md && mkdir -p .git/info && printf 'docs/method/notes.md\n' >>.git/info/exclude" \
  "not in method.lock: docs/method/notes.md" "until it is put right: remove each file not in method.lock"
mcase "a method file git ignores is red" 1 "git rm -r -q --cached .claude/hooks && printf '.claude/hooks/\n' >.gitignore" \
  "method files git ignores" "ignored by git (.gitignore line 1: .claude/hooks/), so a commit leaves it out: .claude/hooks/method/guard.sh" \
  "change each ignore rule named"
mcase "a method.lock git ignores is red" 1 "git rm -q --cached scripts/method/method.lock && printf '*.lock\n' >.gitignore" \
  "1 method files git ignores" "ignored by git (.gitignore line 1: *.lock), so a commit leaves it out: scripts/method/method.lock"
mcase "a tracked .claude/settings.local.json is red" 1 "printf '{}\n' >.claude/settings.local.json && git add .claude/settings.local.json && git commit -q -m local" \
  "1 problems with .claude/settings.local.json" ".claude/settings.local.json is tracked in git, so every clone gets it" "git rm --cached .claude/settings.local.json"
mcase "an untracked .claude/settings.local.json passes" 0 "printf '{}\n' >.claude/settings.local.json" \
  "passed: secrets fresh-clone method-files unit tree-unchanged"
mcase "a removed method deny entry is red" 1 "$json; json .claude/settings.json '\$d->{permissions}{deny} = [grep { \$_ ne \"RemoteTrigger\" } @{ \$d->{permissions}{deny} }]'" \
  "the method's deny entry RemoteTrigger is missing from .claude/settings.json"
mcase "a changed method hook is red" 1 "$json; json .claude/settings.json '\$d->{hooks}{PreToolUse}[0]{hooks}[0]{timeout} = 600'" \
  "a method hook on PreToolUse is missing or changed in .claude/settings.json" "a hook on PreToolUse in .claude/settings.json names .claude/hooks/method/ but is not one of the release's"
mcase "a method hook removed is red" 1 "$json; json .claude/settings.json 'delete \$d->{hooks}{SessionStart}'" \
  "a method hook on SessionStart is missing or changed in .claude/settings.json"
if [ "$can_link" -eq 1 ]; then
  mcase "a link under the method's paths is red" 1 "ln -s ../../src/a.txt docs/method/a.md" \
    "1 links under the method's paths" "a link: docs/method/a.md" "replace each link or odd entry with a plain folder or file as released"
  mcase "a linked method folder is red" 1 "mv .claude/hooks hooks-real && ln -s ../hooks-real .claude/hooks" "a link: .claude/hooks"
else
  skip "a link under the method's paths, and a linked method folder: this system cannot make links"
fi
if [ "$can_fifo" -eq 1 ]; then
  mcase "a FIFO under the method's paths is red, not named a link" 1 "mkfifo docs/method/pipe" \
    "1 entries under the method's paths that are not regular files or cannot be read" "not a regular file: docs/method/pipe"
else
  skip "a FIFO under the method's paths: this system cannot make one"
fi
mcase "no lock beside the method's files is red" 1 "rm scripts/method/method.lock" \
  "1 problems with method.lock" "scripts/method/method.lock is missing, so the method's files cannot be compared with the release"
mcase "a lock with a bad version line is red" 1 "perl -pi -e 's/\Aversion\t.*/version\tlatest/ if \$. == 1' scripts/method/method.lock" \
  "scripts/method/method.lock line 1: not a version line"
mcase "a lock with an unknown profile is red" 1 "perl -pi -e 's/\Aprofile\t.*/profile\tturbo/' scripts/method/method.lock" \
  "the method keys cannot be worked out: the profile turbo is not one this release knows (best balanced budget)"
mcase "a lock line naming a path outside the method's is red" 1 "printf 'file\t%s\tsrc/a.txt\n' \"\$(printf '%064d' 0)\" >>scripts/method/method.lock" \
  "scripts/method/method.lock line" "the path is not one of the method's paths"

# 3. the lock itself
if wanted "the lock made twice is the same bytes"; then
  fresh
  # shellcheck disable=SC2016 # perl code, expanded by perl
  if (cd "$d" && SRC="$SRC" perl -e 'require "./scripts/method/lib/lock.pl"; my ($t) = Lock::make(".", "v0.7.0", $ENV{SRC}, "best"); print $t' >"$work/again") \
    && cmp -s "$work/again" "$d/scripts/method/method.lock"; then
    pass "the lock made twice is the same bytes"
  else
    fail "the lock made twice is the same bytes" "$(diff "$work/again" "$d/scripts/method/method.lock" | head -5)"
  fi
fi
if wanted "the lock's shape"; then
  l="$base/scripts/method/method.lock"
  cat >"$work/shape.pl" <<'SHAPE'
BEGIN { @w = (qr/\Aversion\tv0\.7\.0\n\z/, qr/\Asource\t[0-9a-f]{40}\n\z/, qr/\Aprofile\tbest\n\z/, qr/\Asettings\t[0-9a-f]{64}\n\z/) }
if ($. <= 4) { $bad++ unless $_ =~ $w[$. - 1]; next }
if (/\Afile\t[0-9a-f]{64}\t(\S+)\n\z/) { push @p, $1; $frag++ if $1 eq "scripts/method/settings.method.json"; $self++ if $1 eq "scripts/method/method.lock" } else { $bad++ }
END { my @s = sort @p; print $bad || "@s" ne "@p" || !$frag || $self ? "bad" : scalar(@p) }
SHAPE
  shape=$(perl -n "$work/shape.pl" "$l")
  case "$shape" in
    [1-9]*) pass "the lock's shape: version, source, profile, settings, then $shape sorted file lines, settings.method.json among them and not the lock" ;;
    *) fail "the lock's shape" "$(head -6 "$l")" ;;
  esac
fi

# 4. without the method installed (run-checks from a copy outside, in a
# repository with no lock and no method file), method-files is not run
if wanted "without the method installed, method-files is not run"; then
  p="$work/plain"
  mkdir -p "$p/src" "$p/.claude" "$p/checks"
  printf 'hello\n' >"$p/src/a.txt"
  printf 'PRODUCT_PATHS=src\n' >"$p/.claude/method.conf"
  printf 'unit\tany\t-\t^([0-9]+) passed\techo "3 passed"\n' >"$p/checks/main.tsv"
  (cd "$p" && git init -q && git config user.name T && git config user.email t@example.invalid && git config commit.gpgsign false && git add -A && git commit -q -m base)
  (cd "$p" && unset CI && bash "$root/method/scripts/method/run-checks.sh") >"$work/out" 2>&1
  code=$?
  out=$(cat "$work/out")
  case "$out" in
    *method-files*) fail "without the method installed, method-files is not run" "$out" ;;
    *) expect "without the method installed, method-files is not run" 0 "passed: secrets fresh-clone unit tree-unchanged" ;;
  esac
fi

drop_sandbox "$work" || true
echo "tests: method-files: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
