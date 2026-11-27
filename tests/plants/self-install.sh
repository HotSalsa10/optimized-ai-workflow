#!/usr/bin/env bash
# Plants for validate's self-install check (step 8.1, DECISIONS A82): the
# root copy of the method, installed from the last release tag, must match
# its lock as method/'s lib/lock.pl judges it, and the root settings must
# keep the method's rules out. Each case runs scripts/dev/validate.sh whole
# in a throwaway copy; the check must be green on a clean copy and red, for
# its stated reason, on a copy with the planted defect. Each plant first
# confirms it really landed. (Split from tests/plants/dev-checks.sh at step
# 8's review, F9: its five whole validate runs, each with shellcheck, kept
# that file past its part's time margin.)
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: self-install"

# lacks TEXT FILE: no line of FILE matches TEXT.
lacks() {
  ! grep -q -- "$1" "$2"
}

# root_verify_empty DIR: the root copy's own lib/lock.pl, loaded from DIR,
# says the root copy matches its lock (no findings)
root_verify_empty() {
  (cd "$1" && perl -e 'require "./scripts/method/lib/lock.pl"; my $v = Lock::verify("."); exit(@{ $v->{findings} } ? 1 : 0)')
}

# 1. the root copy of the method is green on a clean copy
sb=$(make_sandbox) || abort_sandbox
out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
if printf '%s\n' "$out" | grep -q '^self-install: PASS - the root copy of the method matches scripts/method/method.lock (v'; then
  pass "self-install green on a clean copy"
else
  fail "self-install green on a clean copy" "$out"
fi
drop_sandbox "$sb"

# 2. a root method file changed
sb=$(make_sandbox) || abort_sandbox
printf '# planted\n' >>"$sb/.claude/hooks/method/guard.sh"
if expect_landed "self-install plant 1" grep -q '^# planted$' "$sb/.claude/hooks/method/guard.sh"; then
  expect_red "self-install red on a root method file changed since the release" "$sb" "self-install: changed since the release: .claude/hooks/method/guard.sh" bash scripts/dev/validate.sh
fi
drop_sandbox "$sb"

# 3. the claudeMdExcludes pattern that keeps the method's rules out removed
sb=$(make_sandbox) || abort_sandbox
perl -MJSON::PP -0777 -i -pe 'my $j = JSON::PP->new->canonical->pretty; my $s = $j->decode($_); delete $s->{claudeMdExcludes}; $_ = $j->encode($s)' "$sb/.claude/settings.json"
if expect_landed "self-install plant 2" lacks 'rules/method' "$sb/.claude/settings.json"; then
  expect_red "self-install red on the root settings without the rules pattern" "$sb" "self-install: FAIL - .claude/settings.json does not list claudeMdExcludes **/.claude/rules/method/**" bash scripts/dev/validate.sh
fi
drop_sandbox "$sb"

# 4. the root lib/lock.pl changed so its own verify finds nothing: the
#    check, which loads method/'s copy, still sees the change
sb=$(make_sandbox) || abort_sandbox
perl -0pi -e 's/(sub verify \{\n  my \(\$root\) = \@_;\n)/$1  return { examined => 1, findings => [], version => "v0.7.0" }; # planted\n/' "$sb/scripts/method/lib/lock.pl"
if expect_landed "self-install plant 3" grep -q '# planted$' "$sb/scripts/method/lib/lock.pl" &&
  expect_landed "self-install plant 3 (the root verify finds nothing)" root_verify_empty "$sb"; then
  expect_red "self-install red on a root lock.pl whose verify finds nothing" "$sb" "self-install: changed since the release: scripts/method/lib/lock.pl" bash scripts/dev/validate.sh
fi
drop_sandbox "$sb"

# 5. the root lock gone: the method is named as not installed here (step
#    8's review, F30)
sb=$(make_sandbox) || abort_sandbox
rm -f "$sb/scripts/method/method.lock"
if expect_landed "self-install plant 4" test ! -e "$sb/scripts/method/method.lock"; then
  expect_red "self-install red with no root method.lock" "$sb" "self-install: FAIL - the method is not installed at the root (scripts/method/method.lock is missing)" bash scripts/dev/validate.sh
fi

drop_sandbox "$sb"

echo "plants: self-install: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
