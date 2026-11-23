#!/usr/bin/env bash
# Plants for tests/budget.test.sh (step 6.1, SPEC R12): in a throwaway copy
# of the repo, the method's own text is put one byte over each budget, which
# must turn the test red for its stated reason, and exactly at each budget,
# which must leave it green. The plants count with their own small reader
# (a line holding only a comment is dropped, as the client drops it), so a
# fault in the test's counter is not shared.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: budget"
owner=method/.claude/rules/method/owner.md

# rules_bytes ROOT: the rules files' bytes that reach the model
rules_bytes() {
  # shellcheck disable=SC2016 # perl code, expanded by perl
  find "$1/method/.claude/rules" -type f -name '*.md' -exec perl -ne '$n += length unless /\A<!--(?:(?!-->).)*-->\n?\z/; END { print $n + 0, "\n" }' {} + | awk '{ s += $1 } END { print s + 0 }'
}
# descs ROOT: "BYTES FILES" for the description fields of the method's
# agents and skills (one-line values)
descs() {
  # shellcheck disable=SC2016 # perl code, expanded by perl
  { find "$1/method/.claude/agents" -type f -name '*.md' 2>/dev/null; find "$1/method/.claude/skills" -mindepth 2 -maxdepth 2 -type f -name SKILL.md 2>/dev/null; } |
    perl -ne 'chomp; open my $h, "<", $_ or next; my @l = <$h>; $f++; if (@l && $l[0] =~ /\A---\s*\z/) { for (@l[1 .. $#l]) { last if /\A---\s*\z/; if (/\Adescription:[ \t]*(.*?)[ \t]*\n?\z/) { $b += length $1; last } } } END { print $b + 0, " ", $f + 0, "\n" }'
}
# pad ROOT FILE N: adds a line of N - 1 bytes of text and its newline to FILE
pad() {
  perl -e 'open my $h, ">>", $ARGV[0] or die; print $h "y" x ($ARGV[1] - 1), "\n"' "$1/$2" "$3"
}
# agent ROOT NAME N: a new agent file whose description is N bytes
agent() {
  mkdir -p "$1/method/.claude/agents/method" &&
    perl -e 'open my $h, ">", $ARGV[0] or die; print $h "---\nname: $ARGV[1]\ndescription: ", "d" x $ARGV[2], "\n---\nA planted agent.\n"' "$1/method/.claude/agents/method/$2.md" "$2" "$3"
}
# judge NAME SB RESULT REASON: tests/budget.test.sh in SB is red with a line
# "  FAIL  REASON..." (RESULT red), or green (RESULT green)
judge() {
  got=$(cd "$2" && bash tests/budget.test.sh 2>&1)
  rc=$?
  case "$3:$rc" in
    green:0) pass "$1" ;;
    green:*) fail "$1: the budget test went red" "$(printf '%s\n' "$got" | grep FAIL)" ;;
    red:0) fail "$1: the budget test stayed green" "$(printf '%s\n' "$got" | grep -e PASS -e SKIP | head -4)" ;;
    red:*)
      if printf '%s\n' "$got" | grep -q -F -- "  FAIL  $4"; then pass "$1"; else fail "$1: went red, but not for the stated reason ('$4')" "$(printf '%s\n' "$got" | grep FAIL)"; fi
      ;;
  esac
}

sb=$(make_sandbox) || abort_sandbox
judge "budget green on a clean copy" "$sb" green
drop_sandbox "$sb"

# the rules files: exactly at 8,000 bytes, then one byte over
for want in 8000 8001; do
  sb=$(make_sandbox) || abort_sandbox
  now=$(rules_bytes "$sb")
  pad "$sb" "$owner" $((want - now))
  if expect_landed "rules at $want bytes" test "$(rules_bytes "$sb")" = "$want"; then
    if [ "$want" = 8000 ]; then
      judge "budget green with the rules files at exactly 8000 bytes" "$sb" green
    else
      judge "budget red with the rules files one byte over (8001)" "$sb" red "rules: 8001 bytes of the rules files reach the model, over the budget of 8000"
    fi
  fi
  drop_sandbox "$sb"
done

# a long comment on a line of its own costs nothing: green
sb=$(make_sandbox) || abort_sandbox
before=$(rules_bytes "$sb")
perl -e 'open my $h, ">>", $ARGV[0] or die; print $h "<!-- ", "M999 " x 1000, "-->\n"' "$sb/$owner"
if expect_landed "a 5,000-byte comment line" grep -q '^<!-- M999 M999' "$sb/$owner" && expect_landed "the comment line not counted" test "$(rules_bytes "$sb")" = "$before"; then
  judge "budget green with a 5,000-byte comment on a line of its own (the client drops it)" "$sb" green
fi
drop_sandbox "$sb"

# one description: 300 bytes, then 301
for n in 300 301; do
  sb=$(make_sandbox) || abort_sandbox
  agent "$sb" method-planted "$n"
  if expect_landed "a description of $n bytes" grep -q "^description: d\{$n\}\$" "$sb/method/.claude/agents/method/method-planted.md"; then
    if [ "$n" = 300 ]; then
      judge "budget green with a description of exactly 300 bytes" "$sb" green
    else
      judge "budget red with a description one byte over (301)" "$sb" red "descriptions: a description over the budget of 300 bytes"
    fi
  fi
  drop_sandbox "$sb"
done

# (step 6.6, the review's F1) a real description wrapped onto an indented
# next line, 301 bytes as YAML joins the two lines with a space (the client
# sends it whole): red
sb=$(make_sandbox) || abort_sandbox
tester=method/.claude/agents/method/method-tester.md
# shellcheck disable=SC2016 # perl code, expanded by perl
perl -0pi -e 's/^(description: ([^\n]*))\n/"$1\n  " . ("w" x (300 - length $2)) . "\n"/me' "$sb/$tester"
# shellcheck disable=SC2016 # perl code, expanded by perl
if expect_landed "the tester's description wrapped, 301 bytes joined" perl -0ne 'exit !(/^description: ([^\n]*)\n  (w+)\n/m && length("$1 $2") == 301)' "$sb/$tester"; then
  judge "budget red with a description wrapped onto an indented line, 301 bytes as YAML reads it" "$sb" red "descriptions: a description over the budget of 300 bytes"
fi
drop_sandbox "$sb"

# (step 6b.4, L24) a real description as a | block of its text, a blank
# line and a second line, 301 bytes as YAML reads it (each line and the
# blank one end with a line break); a counter that joins a block's lines
# with spaces reads 299: red
sb=$(make_sandbox) || abort_sandbox
# shellcheck disable=SC2016 # perl code, expanded by perl
perl -0pi -e 's/^description: ([^\n]*)\n/"description: |\n  $1\n\n  " . ("w" x (298 - length $1)) . "\n"/me' "$sb/$tester"
# shellcheck disable=SC2016 # perl code, expanded by perl
if expect_landed "the tester's description as a | block, 301 bytes as YAML reads it" perl -0ne 'exit !(/^description: \|\n  ([^\n]*)\n\n  (w+)\n/m && length("$1\n\n$2\n") == 301)' "$sb/$tester"; then
  judge "budget red with a description as a | block, 301 bytes as YAML reads it (not 299, its lines joined by spaces)" "$sb" red "descriptions: a description over the budget of 300 bytes"
fi
drop_sandbox "$sb"

# (step 6b.4's check) a real description as a plain value of its text, two
# blank lines and a second line, 301 bytes as YAML reads it (one line
# break for each blank line); a counter that joins the lines with a space
# reads 300: red
sb=$(make_sandbox) || abort_sandbox
# shellcheck disable=SC2016 # perl code, expanded by perl
perl -0pi -e 's/^description: ([^\n]*)\n/"description: $1\n\n\n  " . ("w" x (299 - length $1)) . "\n"/me' "$sb/$tester"
# shellcheck disable=SC2016 # perl code, expanded by perl
if expect_landed "the tester's description as a plain value with two blank lines inside, 301 bytes as YAML reads it" perl -0ne 'exit !(/^description: ([^\n]*)\n\n\n  (w+)\n/m && length("$1\n\n$2") == 301)' "$sb/$tester"; then
  judge "budget red with a description as a plain value with two blank lines inside, 301 bytes as YAML reads it (not 300, its lines joined by a space)" "$sb" red "descriptions: a description over the budget of 300 bytes"
fi
drop_sandbox "$sb"

# the descriptions in all: exactly 3,000 bytes, then one byte over, in new
# files of at most 300 bytes each
for want in 3000 3001; do
  sb=$(make_sandbox) || abort_sandbox
  have=$(descs "$sb")
  left=$((want - ${have% *}))
  i=0
  while [ "$left" -gt 0 ]; do
    i=$((i + 1))
    n=300
    [ "$left" -lt 300 ] && n=$left
    agent "$sb" "method-planted-$i" "$n"
    left=$((left - n))
  done
  if expect_landed "descriptions at $want bytes in all" test "$(descs "$sb" | cut -d' ' -f1)" = "$want"; then
    if [ "$want" = 3000 ]; then
      judge "budget green with the descriptions at exactly 3000 bytes in all" "$sb" green
    else
      judge "budget red with the descriptions one byte over in all (3001)" "$sb" red "descriptions: 3001 bytes in all, over the budget of 3000"
    fi
  fi
  drop_sandbox "$sb"
done

echo "plants: budget: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
