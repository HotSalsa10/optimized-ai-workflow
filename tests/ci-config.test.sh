#!/usr/bin/env bash
# Tests the safety settings in .github/workflows/ci.yml, which cannot be run
# here: every run step first stops the runner reading workflow commands, a
# manual run and a push run use different concurrency groups, checkout does
# not keep the job token, and no pull_request event starts a run (a push run
# already checks a pull request's head; DECISIONS A76). In on:, a value
# that does not close on its line (a quote or a [ or { left open) and an
# escape in double quotes are refused, since either could hide or spell a
# trigger (step 6b, R17).
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
    # nocomment LINE: LINE without its comment, a # at the start or after a
    # space that is not inside quotes; a quote opens after a space, [, {, a
    # comma or a colon, also inside a plain value (a known limit) (step 6b'"'"'s review, R17: a quoted " #" before pull_request in
    # a flow-form on: hid the trigger), and '"''"' in single quotes is a
    # quote, not its end. Then 1 when a quote or a [ or { is still open at
    # the end of the line, else 0
    my $nocomment = sub {
      my ($s) = @_;
      my ($q, $depth) = ("", 0);
      for (my $k = 0; $k < length $s; $k++) {
        my $c = substr $s, $k, 1;
        my $prev = $k ? substr($s, $k - 1, 1) : " ";
        if ($q eq "\x22") {
          if ($c eq "\\") { $k++ } elsif ($c eq "\x22") { $q = "" }
        } elsif ($q eq "\x27") {
          if ($c eq "\x27") { if (substr($s, $k + 1, 1) eq "\x27") { $k++ } else { $q = "" } }
        } elsif (($c eq "\x22" || $c eq "\x27") && $prev =~ /[\s\[\{,:]/) {
          $q = $c;
        } elsif ($c eq "#" && $prev =~ /\s/) {
          return (substr($s, 0, $k), ($q ne "" || $depth != 0) ? 1 : 0);
        } elsif ($c eq "[" || $c eq "{") {
          $depth++;
        } elsif ($c eq "]" || $c eq "}") {
          $depth--;
        }
      }
      return ($s, ($q ne "" || $depth != 0) ? 1 : 0);
    };
    for my $i (0 .. $#l) {
      my $n = $i + 1;
      my ($t, $open) = $nocomment->($l[$i]);    # comments do not count
      if ($t =~ /^["\x27]?on["\x27]?\s*:\s*(.*)$/) {
        $on = 1;
        print "line $n: a pull_request event starts a run\n" if $1 =~ /\bpull_request/;
      } elsif ($t =~ /^\S/) {
        $on = 0;
      } elsif ($on && $t =~ /\bpull_request/) {
        print "line $n: a pull_request event starts a run\n";
      }
      # a quoted value or a flow collection in on: that runs onto the next
      # line is refused: the next line could hold a trigger after a # that
      # is inside the quotes (step 6b, R17)
      print "line $n: a value in on: does not close on its line, so its next line cannot be read\n" if $on && $open;
      # an escape in double quotes in on: could spell a trigger
      # ("pull_reques\x74"), so it is refused too
      print "line $n: a double-quoted value in on: holds an escape, so it cannot be read\n" if $on && $t =~ /\x22[^\x22]*\\/;
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
# 6. (step 6b's review, R17) the on: block in flow form on one line, with a
# quoted " #" before a pull_request trigger: the # is inside quotes, not a
# comment, so the trigger is still read
perl -0pe 's/^on:\n  push:\n    branches: \["\*\*"\]\n    tags: \["v\*"\]\n  workflow_dispatch:\n/on: {push: {branches: ["**", "skip #"], tags: ["v*"]}, pull_request: {}, workflow_dispatch: {}}\n/m' "$ci" >"$sb/ci.yml"
if cmp -s "$ci" "$sb/ci.yml"; then
  fail "the flow-form plant did not apply, so the result would mean nothing"
elif ci_problems "$sb/ci.yml" | grep -q -F -- "a pull_request event starts a run"; then
  pass "the test goes red with a pull_request trigger after a quoted \" #\" in a one-line flow-form on:"
else
  fail "the test goes red with a pull_request trigger after a quoted \" #\" in a one-line flow-form on:" "$(ci_problems "$sb/ci.yml")"
fi
# 7. a comment after a quoted value is still a comment: pull_request named
# only there is no trigger
perl -0pe 's/^on:\n  push:\n    branches: \["\*\*"\]\n    tags: \["v\*"\]\n  workflow_dispatch:\n/on: {push: {branches: ["**", "a#b"], tags: [\x27v*\x27]}, workflow_dispatch: {}} # no pull_request\n/m' "$ci" >"$sb/ci.yml"
if cmp -s "$ci" "$sb/ci.yml"; then
  fail "the flow-form comment case did not apply, so the result would mean nothing"
elif problems=$(ci_problems "$sb/ci.yml") && [ -z "$problems" ]; then
  pass "a comment after quoted values in a flow-form on: is not read: pull_request named only there is no trigger"
else
  fail "a comment after quoted values in a flow-form on: is not read: pull_request named only there is no trigger" "$problems"
fi
# 8-11. (step 6b, R17) on_case NAME ON WANT: the on: block of ci.yml
# replaced by the text ON (perl replacement text) makes the check print a
# problem holding WANT
on_case() {
  perl -0pe 's/^on:\n  push:\n    branches: \["\*\*"\]\n    tags: \["v\*"\]\n  workflow_dispatch:\n/'"$2"'/m' "$ci" >"$sb/ci.yml"
  if cmp -s "$ci" "$sb/ci.yml"; then
    fail "$1: the case did not apply, so the result would mean nothing"
  elif ci_problems "$sb/ci.yml" | grep -q -F -- "$3"; then
    pass "$1"
  else
    fail "$1" "$(ci_problems "$sb/ci.yml")"
  fi
}
on_case "the test goes red with a pull_request trigger after '' (a quote inside single quotes) and \" #\" in a one-line flow-form on:" \
  'on: {push: {branches: [\x27it\x27\x27s #\x27]}, pull_request: {}, workflow_dispatch: {}}\n' "a pull_request event starts a run"
on_case "the test goes red with a quoted value in a flow-form on: that runs onto a next line starting with #, a trigger after it" \
  'on: {push: {branches: ["**", "a\n  #b"], tags: ["v*"]}, pull_request: {}, workflow_dispatch: {}}\n' "line 7: a value in on: does not close on its line"
on_case "the test goes red with a flow-form on: whose { runs onto a next line at the start of the line, a trigger there" \
  'on: {push: {branches: ["**"]},\npull_request: {}, workflow_dispatch: {}}\n' "line 7: a value in on: does not close on its line"
on_case "the test goes red with an escape in a double-quoted key in on: (\"pull_reques\\x74\")" \
  'on: {push: {branches: ["**"]}, "pull_reques\\x74": {}, workflow_dispatch: {}}\n' "a double-quoted value in on: holds an escape"
drop_sandbox "$sb"

echo "tests: CI settings: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
