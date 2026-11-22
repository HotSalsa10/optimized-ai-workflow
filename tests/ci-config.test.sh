#!/usr/bin/env bash
# Tests the safety settings in .github/workflows/ci.yml, which cannot be run
# here: every run step first stops the runner reading workflow commands, a
# manual run and a push run use different concurrency groups, checkout does
# not keep the job token, and no pull_request event starts a run (a push run
# already checks a pull request's head; DECISIONS A76).
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: CI settings"

# ci_problems FILE: prints each way FILE breaks the rules above.
ci_problems() {
  perl -e '
    open my $f, "<", $ARGV[0] or die "cannot read $ARGV[0]\n";
    my @l = map { s/\r?\n\z//r } <$f>;
    my $group = 0;
    my $on = 0;    # inside the top-level on: block
    for my $i (0 .. $#l) {
      my $n = $i + 1;
      (my $t = $l[$i]) =~ s/(?:^|\s)#.*//;    # comments do not count
      if ($t =~ /^["\x27]?on["\x27]?\s*:\s*(.*)$/) {
        $on = 1;
        print "line $n: a pull_request event starts a run\n" if $1 =~ /\bpull_request/;
      } elsif ($t =~ /^\S/) {
        $on = 0;
      } elsif ($on && $t =~ /\bpull_request/) {
        print "line $n: a pull_request event starts a run\n";
      }
      $group = 1 if $l[$i] =~ /^\s*group:.*github\.event_name/;
      if ($l[$i] =~ /^\s*(?:-\s+)?run:\s*(.*)$/) {
        my $v = $1;
        if ($v =~ /^[|>]/) {
          my $j = $i + 1;
          $j++ while $j <= $#l && $l[$j] =~ /^\s*$/;
          print "line $n: the run step does not start with ::stop-commands::\n"
            unless $j <= $#l && $l[$j] =~ /::stop-commands::\S/;
        } elsif (length $v) {
          print "line $n: a one-line run step cannot start with ::stop-commands::\n";
        }    # an empty value is a settings key (defaults: run:), not a step
      }
      if ($l[$i] =~ /^(\s*)(?:-\s+)?uses:\s*actions\/checkout\@/) {
        my $ind = length $1;
        my $ok = 0;
        for (my $j = $i + 1; $j <= $#l; $j++) {
          my ($lead) = $l[$j] =~ /^(\s*)/;
          last if $l[$j] =~ /^\s*-\s/ || ($l[$j] =~ /\S/ && length($lead) < $ind);
          $ok = 1 if $l[$j] =~ /^\s*persist-credentials:\s*false\s*$/;
        }
        print "line $n: checkout keeps the job token (no persist-credentials: false)\n" unless $ok;
      }
    }
    print "the concurrency group does not include github.event_name\n" unless $group;
  ' "$1"
}

ci=$(repo_root)/.github/workflows/ci.yml

# 1. the real ci.yml
problems=$(ci_problems "$ci")
if [ -z "$problems" ]; then
  pass "ci.yml: every run step stops workflow commands, groups split by event, checkout keeps no token, no pull_request trigger"
else
  fail "ci.yml: every run step stops workflow commands, groups split by event, checkout keeps no token, no pull_request trigger" "$problems"
fi

# 2-5. the test goes red when any one of the settings is removed, or when a
# pull_request trigger is added back
sb=$(new_sandbox_dir) || abort_sandbox
for case in stop-commands event_name persist-credentials pull_request; do
  what="without $case"
  want=$case
  case "$case" in
    stop-commands) perl -0pe 's/\n[ ]+echo "::stop-commands::[^\n]*//' "$ci" >"$sb/ci.yml" ;;
    event_name) perl -pe 's/-\$\{\{ github\.event_name \}\}//' "$ci" >"$sb/ci.yml" ;;
    persist-credentials) perl -0pe 's/\n[ ]+with:\n[ ]+persist-credentials: false//' "$ci" >"$sb/ci.yml" ;;
    pull_request)
      what="with a pull_request trigger"
      want="a pull_request event starts a run"
      perl -pe 's/^(  workflow_dispatch:)$/  pull_request:\n$1/' "$ci" >"$sb/ci.yml"
      ;;
  esac
  if cmp -s "$ci" "$sb/ci.yml"; then
    fail "the $case plant did not apply, so the result would mean nothing"
  elif ci_problems "$sb/ci.yml" | grep -q -F -- "$want"; then
    pass "the test goes red $what"
  else
    fail "the test goes red $what"
  fi
done
drop_sandbox "$sb"

echo "tests: CI settings: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
