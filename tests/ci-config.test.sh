#!/usr/bin/env bash
# Tests the safety settings in .github/workflows/ci.yml, which cannot be run
# here: every run step first stops the runner reading workflow commands, a
# manual run and a push run use different concurrency groups, checkout does
# not keep the job token, no pull_request event starts a run (a push run
# already checks a pull request's head; DECISIONS A76), no tag push starts a
# run (a tag names a tree already checked as its branch's head, A76 (4)), and
# a job that runs on Windows or macOS runs only when started by hand (A19,
# A27; since step 7.9). Since step 7.9's check, no create, delete or release
# trigger (each starts a run on a tag), the branches filter counts only
# under push, and runner labels are read without case. In on:, a value that does not close on its line (a
# quote or a [ or { left open) and an escape in double quotes are refused,
# since either could hide or spell a trigger (step 6b, R17). Since step 7.9
# the plants job must run exactly the parts of tests/plants/shards.txt, each
# part's measured time within 70% of the job's limit.
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
    my $branches = 0;    # push in on: names a branches filter
    my ($evind, $event) = (undef, "");    # the indent of the events in on:, and the event a line is under
    my ($jobs, $job, @other, %if) = (0, undef);    # the jobs: block
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
      my $ontext;
      my $under = 0;    # the line is under an event of the block-form on:
      if ($t =~ /^["\x27]?on["\x27]?\s*:\s*(.*)$/) {
        $on = 1;
        $ontext = $1;
        ($evind, $event) = (undef, "");
      } elsif ($t =~ /^\S/) {
        $on = 0;
      } elsif ($on) {
        $ontext = $t;
        if ($t =~ /^(\s*)\S/) {
          my $ind = length $1;
          $evind = $ind unless defined $evind;
          if ($ind <= $evind) {
            $event = $t =~ /^\s*["\x27]?([A-Za-z_]+)/ ? $1 : "";
          } else {
            $under = 1;
          }
        }
      }
      if (defined $ontext) {
        print "line $n: a pull_request event starts a run\n" if $ontext =~ /\bpull_request/;
        # with a branches filter and no tags filter, a tag push starts no
        # run (the GitHub workflow syntax)
        print "line $n: a tag push starts a run\n" if $ontext =~ /\btags/;
        # (step 7.9, its check) a create, delete or release event, named as a
        # key, starts a run on a tag too
        print "line $n: a $1 event starts a run on a tag\n"
          if $ontext =~ /(?:^|[\s{,])["\x27]?(create|delete|release)["\x27]?\s*:/;
        # the branches filter counts only under push: a filter under
        # another event leaves a tag push starting a run
        $branches = 1 if ($under && $event eq "push" && $ontext =~ /\bbranches/)
          || $ontext =~ /\bpush["\x27]?\s*:\s*\{[^{}]*\bbranches/;
      }
      # a job that names a Windows or macOS runner, and its own if:
      if ($l[$i] =~ /^jobs:\s*$/) {
        $jobs = 1;
      } elsif ($t =~ /^\S/) {
        $jobs = 0;
      } elsif ($jobs && $t =~ /^  ([A-Za-z0-9_-]+):\s*$/) {
        $job = $1;
      } elsif ($jobs && defined $job) {
        # runner labels are read without case (macOS-14, [self-hosted, macOS])
        push @other, $job if $t =~ /windows|macos/i && !grep { $_ eq $job } @other;
        $if{$job} = $1 if $t =~ /^    if:\s*(.*?)\s*$/;
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
    print "push in on: names no branches filter, so a tag push starts a run\n" unless $branches;
    for my $j (@other) {
      print "job $j: a Windows or macOS job runs without being started by hand\n"
        unless defined $if{$j} && $if{$j} eq "github.event_name == \x27workflow_dispatch\x27";
    }
  ' "$1"
}

# shard_problems CI SHARDS (since step 7.9): prints each way the plants
# job of CI and the split in SHARDS (tests/plants/shards.txt) disagree: the
# job must run exactly the parts 0/N to N-1/N of the split, and each part's
# measured seconds must stay within 70% of the job's timeout-minutes, so a
# runner up to about 40% slower than the measuring machine still finishes
shard_problems() {
  perl -e '
    open my $f, "<", $ARGV[0] or die "cannot read $ARGV[0]\n";
    my ($in, $limit, @matrix, @other) = ("", undef);
    while (my $l = <$f>) {
      $l =~ s/\r?\n\z//;
      if ($l =~ /^  ([A-Za-z0-9_-]+):\s*$/) { $in = $1; next }
      if ($in eq "plants") {
        $limit = $1 if $l =~ /^    timeout-minutes:\s*([0-9]+)\s*$/;
        @matrix = $1 =~ /"([^"]*)"/g if $l =~ /^\s+shard:\s*\[(.*)\]\s*$/;
      } elsif ($in eq "other-systems" && $l =~ /^\s+part:\s*\[(.*)\]\s*$/) {
        @other = map { /^plants (.*)$/ ? $1 : () } $1 =~ /"([^"]*)"/g;
      }
    }
    open my $s, "<", $ARGV[1] or die "cannot read $ARGV[1]\n";
    my ($parts, %sum) = (0);
    while (my $l = <$s>) {
      next unless $l =~ /^([0-9]+) \S+ ([0-9]+)\s*$/;
      $sum{$1} += $2;
      $parts = $1 + 1 if $1 + 1 > $parts;
    }
    my $want = join " ", map { "$_/$parts" } 0 .. $parts - 1;
    print "the plants job runs the shards (@matrix), not the $parts parts of the split ($want)\n"
      if "@matrix" ne $want;
    print "the Windows and macOS jobs run the plant parts (@other), not the $parts parts of the split ($want)\n"
      if "@other" ne $want;
    if (!defined $limit) {
      print "the plants job has no timeout-minutes\n";
    } else {
      for my $p (0 .. $parts - 1) {
        my $t = $sum{$p} || 0;
        print "part $p: its plant files took $t s, over 70% of the plants job limit of $limit minutes (", $limit * 42, " s)\n"
          if $t * 10 > $limit * 420;
      }
    }
  ' "$1" "$2"
}

ci=$(repo_root)/.github/workflows/ci.yml

# 1. the real ci.yml
problems=$(ci_problems "$ci")
if [ -z "$problems" ]; then
  pass "ci.yml: every run step stops workflow commands, groups split by event, checkout keeps no token, no pull_request trigger, no tag trigger, Windows and macOS only by hand"
else
  fail "ci.yml: every run step stops workflow commands, groups split by event, checkout keeps no token, no pull_request trigger, no tag trigger, Windows and macOS only by hand" "$problems"
fi

# 2-14. the test goes red when any one of the settings is removed, when a
# pull_request or a tag trigger is added back, when push loses its branches
# filter (then a tag push starts a run too), and when the Windows and macOS
# jobs run on tags again or with no if: (since step 7.9); and (step 7.9's
# check) with a create or release trigger, with the branches filter under
# another event than push, and with a runner named macOS-14 or
# [self-hosted, macOS] in a job that runs on every push
sb=$(new_sandbox_dir) || abort_sandbox
for case in stop-commands event_name persist-credentials pull_request tags branches other-tags other-if create release branches-elsewhere runner-case runner-list; do
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
    tags)
      what="with a tag trigger"
      want="a tag push starts a run"
      perl -pe 's/^(    branches: \["\*\*"\])$/$1\n    tags: ["v*"]/' "$ci" >"$sb/ci.yml"
      ;;
    branches)
      what="with no branches filter on push"
      want="push in on: names no branches filter, so a tag push starts a run"
      perl -ne 'print unless /^    branches: \["\*\*"\]$/' "$ci" >"$sb/ci.yml"
      ;;
    create | release)
      what="with a $case trigger"
      want="a $case event starts a run on a tag"
      perl -pe 's/^(  workflow_dispatch:)$/  '"$case"':\n$1/' "$ci" >"$sb/ci.yml"
      ;;
    branches-elsewhere)
      what="with the branches filter under another event than push"
      want="push in on: names no branches filter, so a tag push starts a run"
      perl -0pe 's/^  push:\n    branches: \["\*\*"\]\n/  push:\n  workflow_run:\n    workflows: [CI]\n    branches: ["**"]\n/m' "$ci" >"$sb/ci.yml"
      ;;
    runner-case | runner-list)
      label="macOS-14"
      [ "$case" = runner-list ] && label="[self-hosted, macOS]"
      what="with the harness job on $label"
      want="job harness: a Windows or macOS job runs without being started by hand"
      perl -0pe 's/^(  harness:\n(?:    [^\n]*\n)*?    runs-on: )ubuntu-latest$/${1}'"$label"'/m' "$ci" >"$sb/ci.yml"
      ;;
    other-tags)
      what="with the Windows and macOS jobs on tags again"
      want="job other-systems: a Windows or macOS job runs without being started by hand"
      perl -pe 's/^    if: github\.event_name == \x27workflow_dispatch\x27$/    if: startsWith(github.ref, \x27refs\/tags\/v\x27) || github.event_name == \x27workflow_dispatch\x27/' "$ci" >"$sb/ci.yml"
      ;;
    other-if)
      what="with the Windows and macOS jobs' if: removed"
      want="job other-systems: a Windows or macOS job runs without being started by hand"
      perl -ne 'print unless /^    if: github\.event_name == \x27workflow_dispatch\x27$/' "$ci" >"$sb/ci.yml"
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
# 15. (step 6b's review, R17) the on: block in flow form on one line, with a
# quoted " #" before a pull_request trigger: the # is inside quotes, not a
# comment, so the trigger is still read
perl -0pe 's/^on:\n  push:\n    branches: \["\*\*"\]\n  workflow_dispatch:\n/on: {push: {branches: ["**", "skip #"]}, pull_request: {}, workflow_dispatch: {}}\n/m' "$ci" >"$sb/ci.yml"
if cmp -s "$ci" "$sb/ci.yml"; then
  fail "the flow-form plant did not apply, so the result would mean nothing"
elif ci_problems "$sb/ci.yml" | grep -q -F -- "a pull_request event starts a run"; then
  pass "the test goes red with a pull_request trigger after a quoted \" #\" in a one-line flow-form on:"
else
  fail "the test goes red with a pull_request trigger after a quoted \" #\" in a one-line flow-form on:" "$(ci_problems "$sb/ci.yml")"
fi
# 16. a comment after a quoted value is still a comment: pull_request named
# only there is no trigger
perl -0pe 's/^on:\n  push:\n    branches: \["\*\*"\]\n  workflow_dispatch:\n/on: {push: {branches: ["**", "a#b"]}, workflow_dispatch: {}} # no pull_request\n/m' "$ci" >"$sb/ci.yml"
if cmp -s "$ci" "$sb/ci.yml"; then
  fail "the flow-form comment case did not apply, so the result would mean nothing"
elif problems=$(ci_problems "$sb/ci.yml") && [ -z "$problems" ]; then
  pass "a comment after quoted values in a flow-form on: is not read: pull_request named only there is no trigger"
else
  fail "a comment after quoted values in a flow-form on: is not read: pull_request named only there is no trigger" "$problems"
fi
# 17-20. (step 6b, R17) on_case NAME ON WANT: the on: block of ci.yml
# replaced by the text ON (perl replacement text) makes the check print a
# problem holding WANT
on_case() {
  perl -0pe 's/^on:\n  push:\n    branches: \["\*\*"\]\n  workflow_dispatch:\n/'"$2"'/m' "$ci" >"$sb/ci.yml"
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
  'on: {push: {branches: ["**", "a\n  #b"]}, pull_request: {}, workflow_dispatch: {}}\n' "line 10: a value in on: does not close on its line"
on_case "the test goes red with a flow-form on: whose { runs onto a next line at the start of the line, a trigger there" \
  'on: {push: {branches: ["**"]},\npull_request: {}, workflow_dispatch: {}}\n' "line 10: a value in on: does not close on its line"
on_case "the test goes red with an escape in a double-quoted key in on: (\"pull_reques\\x74\")" \
  'on: {push: {branches: ["**"]}, "pull_reques\\x74": {}, workflow_dispatch: {}}\n' "a double-quoted value in on: holds an escape"
# 21. a branch filter that names release is not a release trigger
perl -pe 's/^(    branches: \["\*\*")\]$/$1, "release\/*", "create"]/' "$ci" >"$sb/ci.yml"
if cmp -s "$ci" "$sb/ci.yml"; then
  fail "the release-branch case did not apply, so the result would mean nothing"
elif problems=$(ci_problems "$sb/ci.yml") && [ -z "$problems" ]; then
  pass "a branches filter naming release/* and create is not read as a release or create trigger"
else
  fail "a branches filter naming release/* and create is not read as a release or create trigger" "$problems"
fi
drop_sandbox "$sb"

# 22-25. (step 7.9) the plants job, and the Windows and macOS jobs, run the
# parts of tests/plants/shards.txt, each part's measured time within 70% of
# the plants job's limit; the check goes red when either drops a part, and
# when a part's time grows past 70%
shards=$(repo_root)/tests/plants/shards.txt
problems=$(shard_problems "$ci" "$shards")
if [ -z "$problems" ]; then
  pass "the plants job and the Windows and macOS jobs run every part of tests/plants/shards.txt, each part's measured time within 70% of its limit"
else
  fail "the plants job and the Windows and macOS jobs run every part of tests/plants/shards.txt, each part's measured time within 70% of its limit" "$problems"
fi
sb=$(new_sandbox_dir) || abort_sandbox
perl -pe 's/^(\s+shard: \[.*), "[0-9]+\/[0-9]+"\]$/$1]/' "$ci" >"$sb/ci.yml"
if cmp -s "$ci" "$sb/ci.yml"; then
  fail "the dropped-part case did not apply, so the result would mean nothing"
elif shard_problems "$sb/ci.yml" "$shards" | grep -q -F -- "the plants job runs the shards"; then
  pass "the shard check goes red when the plants job drops a part"
else
  fail "the shard check goes red when the plants job drops a part" "$(shard_problems "$sb/ci.yml" "$shards")"
fi
perl -pe 's/^(\s+part: \[.*), "plants [0-9]+\/[0-9]+"\]$/$1]/' "$ci" >"$sb/ci.yml"
if cmp -s "$ci" "$sb/ci.yml"; then
  fail "the dropped Windows and macOS part case did not apply, so the result would mean nothing"
elif shard_problems "$sb/ci.yml" "$shards" | grep -q -F -- "the Windows and macOS jobs run the plant parts"; then
  pass "the shard check goes red when the Windows and macOS jobs drop a part"
else
  fail "the shard check goes red when the Windows and macOS jobs drop a part" "$(shard_problems "$sb/ci.yml" "$shards")"
fi
perl -pe 's/^(0 \S+ )[0-9]+$/${1}99999/ if !$done && /^0 / && ($done = 1)' "$shards" >"$sb/shards.txt"
if cmp -s "$shards" "$sb/shards.txt"; then
  fail "the slow-part case did not apply, so the result would mean nothing"
elif shard_problems "$ci" "$sb/shards.txt" | grep -q -F -- "part 0: its plant files took"; then
  pass "the shard check goes red when a part's measured time is over 70% of the limit"
else
  fail "the shard check goes red when a part's measured time is over 70% of the limit" "$(shard_problems "$ci" "$sb/shards.txt")"
fi
drop_sandbox "$sb"

echo "tests: CI settings: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
