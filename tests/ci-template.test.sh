#!/usr/bin/env bash
# Tests for the project CI template, method/scripts/method/templates/
# method-checks.yml.tmpl (step 9.3, M166; docs/plans/step9.md S7), which
# /method-setup seeds as .github/workflows/method-checks.yml. A project
# gets the method from a throwaway release (this repo's method/ and
# scripts/release/) through the release's own sync, then setup-write.sh
# with answers that turn no check row on. On the template and on the
# seeded copy:
# - the workflow lint (scripts/dev/lib/workflows.pl: every action pinned
#   to a commit, top-level permissions, a timeout for each job) finds
#   nothing;
# - its triggers are exactly push (every branch) and workflow_dispatch;
# - outside comments it names no secrets. and no github.token, and holds
#   no ${{ }} expression at all;
# - its permissions are contents: read alone, at the top, and no job sets
#   its own;
# - checkout keeps persist-credentials: false and is pinned to ci.yml's
#   commit;
# - every run starts with the stop-commands line, and the last step runs
#   CI=true bash scripts/method/run-checks.sh.
# Then: setup seeds the template byte for byte and its card names the file
# and exit 3; a second setup run, and one after the project changed the
# file, leave it as it is; and in the project, whose check rows are all
# off, the seeded run step gives exit 3.
# shellcheck disable=SC2016 # single-quoted perl code is expanded by perl
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: CI template"
root=$(repo_root)
tmpl="$root/method/scripts/method/templates/method-checks.yml.tmpl"
seeded_rel=.github/workflows/method-checks.yml
work=$(new_sandbox_dir) || abort_sandbox
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM CLAUDE_CODE_EXECPATH CLAUDE_CODE_EFFORT_LEVEL CLAUDE_CODE_REMOTE CLAUDE_PROJECT_DIR GH_REPO CI
mkdir -p "$HOME"
git config --global user.name T
git config --global user.email t@example.invalid
git config --global commit.gpgsign false
git config --global core.autocrlf false
git config --global init.defaultBranch main

# the release, and a project with the method, set up with no check row on
rel="$work/rel"
p="$work/p"
if ! { mkdir -p "$rel/scripts" &&
  cp -R "$root/method" "$rel/method" &&
  cp -R "$root/scripts/release" "$rel/scripts/release" &&
  (cd "$rel" && git init -q && git add -A && git commit -q -m release && git tag v0.9.0) &&
  mkdir -p "$p" && (cd "$p" && git init -q && printf 'A small project.\n' >README.md && git add -A && git commit -q -m "before the method") &&
  bash "$rel/scripts/release/sync.sh" --to "$p" --profile best --write >/dev/null; }; then
  abort_sandbox
fi
printf '%s\n' "DECIDES	claude" "REPORTS	full" "PACE	small" "TOUCHES	none" "STRICT	standard" "PROFILE	best" \
  "PROJECT_WHAT	A small project." "NEVER_WRONG	A wrong answer." "HOW_IT_STARTS	" "TEST_COMMAND	" >"$p/.claude/setup-answers.txt"
card=$(cd "$p" && bash scripts/method/setup-write.sh --write 2>&1)
card_rc=$?
(cd "$p" && git add -A && git commit -q -m "the method" -m "Review-Verdict: not-required - a test") >/dev/null 2>&1

# the template as a workflow file, for the lint, which reads a workflow
# only under .github/workflows/
mkdir -p "$work/t/.github/workflows"
cp "$tmpl" "$work/t/$seeded_rel"
files="$work/t/$seeded_rel $p/$seeded_rel"

# each FILE: the case's check on each of the two copies; on a FAIL the
# copy and what was seen are named
each() {
  e_name=$1
  shift
  if ! wanted "$e_name"; then return 0; fi
  e_bad=""
  for e_f in $files; do
    if [ ! -f "$e_f" ]; then
      e_bad="$e_bad
${e_f#"$work"/}: not there"
      continue
    fi
    e_got=$("$@" "$e_f" 2>&1) || e_bad="$e_bad
${e_f#"$work"/}: $e_got"
  done
  if [ -z "$e_bad" ]; then pass "$e_name"; else fail "$e_name" "${e_bad#?}"; fi
}

lint() {
  l_out=$(perl "$root/scripts/dev/lib/workflows.pl" "$1" 2>&1)
  if printf '%s\n' "$l_out" | grep -q -x 'BAD 0' && printf '%s\n' "$l_out" | grep -q -x 'EXAMINED 1'; then
    return 0
  fi
  printf '%s\n' "$l_out" | grep -v -e '^EXAMINED' -e '^ACTIONS'
  return 1
}
each "the workflow lint finds nothing (pinned actions, permissions, a timeout for each job)" lint

# triggers FILE: the keys under the top-level on:, each with the lines
# under it, as "KEY: LINE | LINE"
triggers() {
  perl -e 'open my $h, "<", $ARGV[0] or exit 2; my ($in, @k);
    while (<$h>) { chomp; next if /^\s*(?:#|$)/;
      if (/^(\S[^:]*):\s*(.*)$/) { $in = $1 eq "on"; print "on has a value: $2\n" if $in && length $2; next }
      next unless $in;
      if (/^  (\S[^:]*):\s*(.*)$/) { push @k, [$1, length $2 ? $2 : ()]; next }
      if (@k) { (my $l = $_) =~ s/^\s+//; push @{ $k[-1] }, $l } }
    print join(" | ", @$_), "\n" for @k' "$1"
}
on_is() {
  o_got=$(triggers "$1")
  o_want=$(printf '%s\n' 'push | branches: ["**"]' 'workflow_dispatch')
  [ "$o_got" = "$o_want" ] || {
    printf 'triggers: %s\n' "$(printf '%s\n' "$o_got" | tr '\n' ';')"
    return 1
  }
}
each "its triggers are exactly push, on every branch, and workflow_dispatch" on_is

# code FILE: the file's lines with comments taken out (a # that starts a
# line or follows a space)
code() {
  perl -ne 's/(?:^|\s)#.*//; print' "$1"
}
no_secret() {
  c_hits=$(code "$1" | grep -n -i -e 'secrets\.' -e 'github\.token' -e '\${{' -e "secrets\[" -e "github\[")
  [ -z "$c_hits" ] || {
    printf '%s\n' "$c_hits"
    return 1
  }
}
each "outside comments it names no secret and no token, and holds no \${{ }} expression" no_secret

perms() {
  p_got=$(code "$1" | perl -ne 'if (/^(\s*)permissions:\s*(.*)$/) { $p = length $1; print "permissions at $p: $2\n"; $in = 1; next }
    if ($in && /^(\s*)(\S.*)$/ && length $1 > $p) { print "  $2\n"; next } $in = 0')
  [ "$p_got" = "$(printf '%s\n' 'permissions at 0: ' '  contents: read')" ] || {
    printf '%s\n' "$p_got"
    return 1
  }
}
each "its permissions are contents: read alone, at the top, and no job sets its own" perms

checkout() {
  k_ci=$(sed -n 's/^ *uses: actions\/checkout@\([0-9a-f]*\).*/\1/p' "$root/.github/workflows/ci.yml" | sort -u)
  k_here=$(sed -n 's/^ *uses: actions\/checkout@\([0-9a-f]*\).*/\1/p' "$1" | sort -u)
  k_uses=$(code "$1" | grep -c 'uses:')
  [ -n "$k_ci" ] && [ "$(printf '%s\n' "$k_ci" | wc -l | tr -d ' ')" = 1 ] && [ "$k_here" = "$k_ci" ] && [ "$k_uses" = 1 ] || {
    printf 'ci.yml: %s; here: %s (%s uses lines)\n' "$(printf '%s' "$k_ci" | tr '\n' ' ')" "$(printf '%s' "$k_here" | tr '\n' ' ')" "$k_uses"
    return 1
  }
  code "$1" | grep -A 2 'uses: actions/checkout@' | grep -q '^ *persist-credentials: false *$' || {
    echo "no persist-credentials: false under the checkout"
    return 1
  }
}
each "it checks out with ci.yml's pinned checkout commit, its only action, and persist-credentials: false" checkout

# runs FILE: each run block's lines, the block's first line marked with >
runs() {
  code "$1" | perl -ne 'if (/^(\s*)(?:- )?run:\s*\|\s*$/) { $ind = length $1; $first = 1; next }
    if (defined $ind) { if (/^(\s*)\S/ && length $1 > $ind) { s/^\s+//; print $first ? "> $_" : $_; $first = 0; next } undef $ind }
    print "run on one line: $_" if /^\s*(?:- )?run:\s*[^|\s]/'
}
stops() {
  r_got=$(runs "$1")
  r_first=$(printf '%s\n' "$r_got" | grep -c '^> ')
  r_stop=$(printf '%s\n' "$r_got" | grep -c -x -F '> echo "::stop-commands::stop-$RANDOM$RANDOM$RANDOM"')
  r_last=$(printf '%s\n' "$r_got" | tail -n 1)
  [ "$r_first" -ge 1 ] && [ "$r_first" = "$r_stop" ] && ! printf '%s\n' "$r_got" | grep -q '^run on one line' &&
    [ "$r_last" = 'CI=true bash scripts/method/run-checks.sh' ] || {
    printf '%s\n' "$r_got"
    return 1
  }
}
each "every run starts with the stop-commands line, and the last runs CI=true bash scripts/method/run-checks.sh" stops

n="setup seeds it byte for byte, and its card names the file and what exit 3 means"
if wanted "$n"; then
  if [ "$card_rc" -eq 0 ] && cmp -s "$tmpl" "$p/$seeded_rel" && printf '%s\n' "$card" | grep -q "new  *$seeded_rel" &&
    printf '%s\n' "$card" | grep -q "CI: $seeded_rel runs these checks on GitHub on every push\.$" &&
    printf '%s\n' "$card" | grep -q "CI's exit 3 means nothing failed, but a check that applies there was SKIPPED"; then
    pass "$n"
  else
    fail "$n" "exit $card_rc; $(printf '%s\n' "$card" | grep -i -e 'method-checks' -e 'CI' | head -5)"
  fi
fi

n="a second setup run, and one after the project changed the file, leave it as it is, and the card says it was kept"
if wanted "$n"; then
  (cd "$p" && bash scripts/method/setup-write.sh --write) >"$work/setup-again.txt" 2>&1
  c1=$?
  same1=no
  cmp -s "$tmpl" "$p/$seeded_rel" && same1=yes
  cp "$p/$seeded_rel" "$work/changed.yml"
  printf '      - name: The project'"'"'s own step\n        run: |\n          echo "::stop-commands::stop-$RANDOM$RANDOM$RANDOM"\n          echo own\n' >>"$work/changed.yml"
  cp "$work/changed.yml" "$p/$seeded_rel"
  s2=$(cd "$p" && bash scripts/method/setup-write.sh --write 2>&1)
  c2=$?
  if [ "$c1" -eq 0 ] && [ "$same1" = yes ] && [ "$c2" -eq 0 ] && cmp -s "$work/changed.yml" "$p/$seeded_rel" &&
    printf '%s\n' "$s2" | grep -q "kept  *$seeded_rel" &&
    printf '%s\n' "$s2" | grep -q "CI: $seeded_rel runs these checks on GitHub on every push; it was there already, so setup left it as it is\.$"; then
    pass "$n"
  else
    fail "$n" "exit $c1, then $c2; the same after the first: $same1; $(printf '%s\n' "$s2" | grep -e 'method-checks' -e '^setup: CI' | head -4)"
  fi
  # the project back to the seeded file, as committed
  cp "$tmpl" "$p/$seeded_rel"
fi

# the run step's lines from the seeded file, run as GitHub runs a step
# (bash -e), in the project: with no check row on, exit 3
n="in a project whose check rows are all off, the seeded run step gives exit 3"
if wanted "$n"; then
  runs "$p/$seeded_rel" | awk '/^> /{b=""} {b=b $0 "\n"} END{printf "%s", b}' | sed 's/^> //' >"$work/step.sh"
  out=$(cd "$p" && bash -e "$work/step.sh" 2>&1)
  rc=$?
  if [ "$rc" -eq 3 ] && printf '%s\n' "$out" | grep -q '^run-checks: SKIPPED - ' && printf '%s\n' "$out" | grep -q 'CI'; then
    pass "$n"
  else
    fail "$n" "exit $rc (wanted 3); step: $(tr '\n' ';' <"$work/step.sh"); $(printf '%s\n' "$out" | tail -3)"
  fi
fi

drop_sandbox "$work" || true
echo "tests: CI template: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
