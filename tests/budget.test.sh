#!/usr/bin/env bash
# Tests the lean-context budgets (SPEC R12; docs/plans/step6.md S7) on the
# method's own text, as it will reach a session:
# - the rules files (every .md under method/.claude/rules/), loaded in
#   every session: at most 8,000 bytes together, counting what reaches the
#   model. The client drops a line that holds only an HTML comment and
#   keeps everything else as written (measured at 2.1.316 and 2.1.319;
#   tests/harness.test.sh compares the text it sends with this count), so
#   such lines are not counted and every other byte is;
# - the description fields of the method's agents (every .md under
#   method/.claude/agents/) and skills (method/.claude/skills/*/SKILL.md):
#   each at most 300 bytes, all together at most 3,000, counted from the
#   file as YAML reads the value (the text after "description:", trimmed,
#   and each indented line after it, as YAML continues a value onto them,
#   joined by single spaces: a block value's lines, a plain or quoted value
#   wrapped onto the next lines, or one that starts there; a " #" comment
#   dropped from a value not in quotes; a quoted value counted with its
#   quotes). Step 6.6 added the wrapped forms: the client joins them and
#   sends the whole text (the review's F1, measured at 2.1.319).
# With no agent or skill file yet, the description budget says SKIPPED.
# A budget is raised only by the owner; text over it is cut. The counter is
# tested here on small cases at and one byte over each budget;
# tests/plants/budget.sh puts the method's own text one byte over each.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: budget"
RULES_MAX=8000
DESC_MAX=300
DESCS_MAX=3000

# budget_read ROOT: prints "RULES bytes files", one "DESC bytes file" per
# agent or skill file, and "DESCS bytes files"
budget_read() {
  # shellcheck disable=SC2016 # perl code, expanded by perl
  perl -MFile::Find -e '
    my $root = shift;
    my (@rules, @desc);
    File::Find::find({ no_chdir => 1, wanted => sub { push @rules, $_ if /\.md\z/ && -f } }, "$root/method/.claude/rules") if -d "$root/method/.claude/rules";
    File::Find::find({ no_chdir => 1, wanted => sub { push @desc, $_ if /\.md\z/ && -f } }, "$root/method/.claude/agents") if -d "$root/method/.claude/agents";
    if (opendir my $sd, "$root/method/.claude/skills") { push @desc, grep { -f } map { "$root/method/.claude/skills/$_/SKILL.md" } grep { !/\A\.\.?\z/ } readdir $sd }
    my $bytes = 0;
    for my $f (@rules) {
      open my $h, "<:raw", $f or die "cannot read $f\n";
      while (my $l = <$h>) { $bytes += length $l unless $l =~ /\A<!--(?:(?!-->).)*-->\n?\z/ }
    }
    print "RULES $bytes ", scalar @rules, "\n";
    my $all = 0;
    for my $f (sort @desc) {
      open my $h, "<:raw", $f or die "cannot read $f\n";
      my @l = <$h>;
      s/\r?\n\z// for @l;
      my ($v, $in) = ("", 0);
      if (@l && $l[0] eq "---") {
        for my $i (1 .. $#l) {
          last if $l[$i] eq "---";
          if ($l[$i] =~ /\Adescription:[ \t]*(.*?)[ \t]*\z/) {
            $v = $1;
            # the lines YAML reads as part of the value: each indented or
            # empty line after it, up to the next key, trimmed
            my @more;
            for my $j ($i + 1 .. $#l) { last unless $l[$j] =~ /\A(?:[ \t]|\z)/; push @more, $1 if $l[$j] =~ /\A[ \t]*(\S.*?)[ \t]*\z/ }
            if ($v =~ /\A[|>][-+0-9]*(?:[ \t]+#.*)?\z/) {
              $v = join " ", @more;
            } elsif ($v =~ /\A[\x22\x27]/) {
              $v = join " ", $v, @more;
            } else {
              my @p;
              for my $s (grep { length } $v, @more) {
                if ($s =~ /\A#/) { last if @p; next }
                (my $c = $s) =~ s/[ \t]+#.*\z//;
                push @p, $c;
                last if $c ne $s;
              }
              $v = join " ", @p;
            }
            last;
          }
        }
      }
      (my $name = $f) =~ s{\A\Q$root\E/}{};
      print "DESC ", length $v, " $name\n";
      $all += length $v;
    }
    print "DESCS $all ", scalar @desc, "\n";' "$1"
}

# budget_check ROOT LABEL: the three budgets on the method text under ROOT,
# one PASS, FAIL or SKIP line each (LABEL starts each line's name)
budget_check() {
  if ! got=$(budget_read "$1" 2>&1); then
    fail "$2rules: the counter did not run" "$got"
    return
  fi
  rb=$(printf '%s\n' "$got" | awk '$1 == "RULES" { print $2 }')
  rf=$(printf '%s\n' "$got" | awk '$1 == "RULES" { print $3 }')
  if [ "${rf:-0}" -eq 0 ]; then
    fail "$2rules: found no rules files under method/.claude/rules/; nothing was counted"
  elif [ "$rb" -gt "$RULES_MAX" ]; then
    fail "$2rules: $rb bytes of the rules files reach the model, over the budget of $RULES_MAX"
  else
    pass "$2rules: $rb of $RULES_MAX bytes of the rules files ($rf files) reach the model; lines holding only a comment are not counted"
  fi
  over=$(printf '%s\n' "$got" | awk -v max="$DESC_MAX" '$1 == "DESC" && $2 > max { print $3 " has " $2 " bytes" }')
  n=$(printf '%s\n' "$got" | awk '$1 == "DESCS" { print $3 }')
  all=$(printf '%s\n' "$got" | awk '$1 == "DESCS" { print $2 }')
  if [ "${n:-0}" -eq 0 ]; then
    skip "$2descriptions: no agent or skill file under method/.claude/ yet, so no description was counted"
    return
  fi
  if [ -n "$over" ]; then
    fail "$2descriptions: a description over the budget of $DESC_MAX bytes" "$over"
  else
    pass "$2descriptions: each of $n is at most $DESC_MAX bytes"
  fi
  if [ "$all" -gt "$DESCS_MAX" ]; then
    fail "$2descriptions: $all bytes in all, over the budget of $DESCS_MAX"
  else
    pass "$2descriptions: $all of $DESCS_MAX bytes in all ($n files)"
  fi
}

# --- the method's own text ---
budget_check "$(repo_root)" ""

# --- the counter, on small cases at and one byte over each budget ---
work=$(new_sandbox_dir) || abort_sandbox
trap 'drop_sandbox "$work" || true' EXIT
# case_dir NAME: an empty method tree for one case; prints its root
case_dir() {
  mkdir -p "$work/$1/method/.claude/rules/method" "$work/$1/method/.claude/agents/method" "$work/$1/method/.claude/skills" && printf '%s\n' "$work/$1"
}
# xs N: N bytes of x
xs() {
  perl -e 'print "x" x $ARGV[0]' "$1"
}
# desc_file FILE N: an agent or skill file whose description is N bytes
desc_file() {
  mkdir -p "$(dirname "$1")" && printf -- '---\nname: x\ndescription: %s\n---\nbody\n' "$(xs "$2")" >"$1"
}
# counted ROOT LINE: the counter prints LINE for ROOT
counted() {
  budget_read "$1" | grep -q -x -F -- "$2"
}
# want NAME ROOT RESULT TEXT: budget_check on ROOT gives a RESULT (PASS,
# FAIL or SKIP) line holding TEXT, and no FAIL line when RESULT is not FAIL
want() {
  got=$(tests_pass=0 tests_fail=0 tests_skip=0 budget_check "$2" "" 2>&1)
  if printf '%s\n' "$got" | grep -F -q -- "  $3  $4" && { [ "$3" = FAIL ] || ! printf '%s\n' "$got" | grep -q '^  FAIL'; }; then
    pass "$1"
  else
    fail "$1" "$got"
  fi
}

d=$(case_dir at-rules) || abort_sandbox
# 7,998 bytes of text and a 2-byte blank line, in two files, and three
# lines that hold only a comment (dropped by the client, so not counted)
{ printf '# R\n'; printf '<!-- M001 -->\n'; xs 3000; printf '\n'; } >"$d/method/.claude/rules/method/a.md"
{ printf '<!-- M002 M003 -->\n'; xs 4993; printf '\n\n'; printf '<!---->\n'; } >"$d/method/.claude/rules/method/b.md"
want "the counter: rules files at 8000 bytes pass, comment lines not counted" "$d" PASS "rules: 8000 of 8000 bytes of the rules files (2 files)"
printf 'y\n' >"$d/method/.claude/rules/method/c.md"
want "the counter: rules files one byte over fail (8002: a third file of two bytes)" "$d" FAIL "rules: 8002 bytes of the rules files reach the model, over the budget of 8000"
rm "$d/method/.claude/rules/method/c.md"
printf '<!-- M004 --> x\n' >>"$d/method/.claude/rules/method/b.md"
want "the counter: a comment sharing its line with text is counted" "$d" FAIL "rules: 8016 bytes"
d=$(case_dir spaced-rules) || abort_sandbox
{ xs 7984; printf '\n  <!-- M005 -->\n'; } >"$d/method/.claude/rules/method/a.md"
want "the counter: a comment line with spaces before it is counted (the client keeps it)" "$d" FAIL "rules: 8001 bytes"
d=$(case_dir deep-rules) || abort_sandbox
mkdir -p "$d/method/.claude/rules/method/more"
{ xs 8000; printf '\n'; } >"$d/method/.claude/rules/method/more/deep.md"
want "the counter: a rules file in a deeper folder is counted (8001 bytes)" "$d" FAIL "rules: 8001 bytes"
d=$(case_dir no-rules) || abort_sandbox
want "the counter: no rules files is a failure, not a pass" "$d" FAIL "rules: found no rules files"
printf 'r\n' >"$d/method/.claude/rules/method/r.md"
if counted "$d" "DESCS 0 0"; then
  want "the counter: no agent or skill file is SKIPPED, not a pass" "$d" SKIP "descriptions: no agent or skill file"
else
  fail "the counter: no agent or skill file is SKIPPED" "$(budget_read "$d")"
fi

d=$(case_dir descs) || abort_sandbox
printf 'r\n' >"$d/method/.claude/rules/method/r.md"
desc_file "$d/method/.claude/agents/method/a.md" 300
want "the counter: a description of 300 bytes passes" "$d" PASS "descriptions: each of 1 is at most 300 bytes"
desc_file "$d/method/.claude/skills/method-s/SKILL.md" 301
want "the counter: a description of 301 bytes fails, naming its file" "$d" FAIL "descriptions: a description over the budget of 300 bytes"
if budget_check "$d" "" 2>&1 | grep -q -F 'method/.claude/skills/method-s/SKILL.md has 301 bytes'; then pass "the counter: the file over the budget is named with its bytes"; else fail "the counter: the file over the budget is named with its bytes" "$(budget_check "$d" "" 2>&1)"; fi
d=$(case_dir descs-all) || abort_sandbox
printf 'r\n' >"$d/method/.claude/rules/method/r.md"
for i in 1 2 3 4 5 6 7 8 9; do desc_file "$d/method/.claude/agents/method/a$i.md" 300; done
desc_file "$d/method/.claude/skills/method-s/SKILL.md" 300
want "the counter: descriptions at 3000 bytes in all pass" "$d" PASS "descriptions: 3000 of 3000 bytes in all (10 files)"
desc_file "$d/method/.claude/skills/method-t/SKILL.md" 1
want "the counter: descriptions one byte over in all fail" "$d" FAIL "descriptions: 3001 bytes in all, over the budget of 3000"
d=$(case_dir desc-forms) || abort_sandbox
printf 'r\n' >"$d/method/.claude/rules/method/r.md"
printf -- '---\nname: q\ndescription: "quoted words"  \n---\n' >"$d/method/.claude/agents/method/q.md"
printf -- '---\nname: b\ndescription: >\n  one two\n  three\nmodel: x\n---\n' >"$d/method/.claude/agents/method/b.md"
printf -- '---\nname: n\n---\ndescription: in the body, not counted\n' >"$d/method/.claude/agents/method/n.md"
mkdir -p "$d/method/.claude/skills/method-s" && printf -- '---\nname: s\ndescription: a skill\n---\n' >"$d/method/.claude/skills/method-s/SKILL.md"
mkdir -p "$d/method/.claude/skills/method-s/more" && printf -- '---\ndescription: a support file, not a skill\n---\n' >"$d/method/.claude/skills/method-s/more/notes.md"
if counted "$d" "DESC 14 method/.claude/agents/method/q.md" && counted "$d" "DESC 13 method/.claude/agents/method/b.md" && counted "$d" "DESC 0 method/.claude/agents/method/n.md" && counted "$d" "DESC 7 method/.claude/skills/method-s/SKILL.md" && counted "$d" "DESCS 34 4"; then
  pass "the counter: a quoted value as written, a block value's lines joined, a body line not counted, a skill's SKILL.md only"
else
  fail "the counter: description forms" "$(budget_read "$d")"
fi
# (step 6.6, the review's F1) the forms YAML reads further than the line:
# an indented next line continues a plain or quoted value, joined by one
# space, as the client sends it; a value may start on the next line; a
# " #" comment ends a value not in quotes
d=$(case_dir desc-yaml) || abort_sandbox
printf 'r\n' >"$d/method/.claude/rules/method/r.md"
printf -- '---\nname: c\ndescription: one two\n  three four\n   five\nmodel: x\n---\n' >"$d/method/.claude/agents/method/c.md"
printf -- '---\nname: q\ndescription: "one\n  two"\n---\n' >"$d/method/.claude/agents/method/q.md"
printf -- '---\nname: n\ndescription:\n  on the next line\n---\n' >"$d/method/.claude/agents/method/n.md"
printf -- '---\nname: h\ndescription: words  # a comment, not sent\n---\n' >"$d/method/.claude/agents/method/h.md"
printf -- '---\nname: b\ndescription: > # a comment\n  one\n  two\n---\n' >"$d/method/.claude/agents/method/b.md"
if counted "$d" "DESC 23 method/.claude/agents/method/c.md" && counted "$d" "DESC 9 method/.claude/agents/method/q.md" && counted "$d" "DESC 16 method/.claude/agents/method/n.md" &&
  counted "$d" "DESC 5 method/.claude/agents/method/h.md" && counted "$d" "DESC 7 method/.claude/agents/method/b.md"; then
  pass "the counter: continued lines joined by one space, a value on the next line, a comment dropped from a plain value (as YAML reads them)"
else
  fail "the counter: continued lines joined by one space, a value on the next line, a comment dropped from a plain value (as YAML reads them)" "$(budget_read "$d")"
fi
d=$(case_dir desc-wrapped) || abort_sandbox
printf 'r\n' >"$d/method/.claude/rules/method/r.md"
mkdir -p "$d/method/.claude/skills/method-w" && printf -- '---\nname: w\ndescription: %s\n  %s\n---\n' "$(xs 200)" "$(xs 100)" >"$d/method/.claude/skills/method-w/SKILL.md"
want "the counter: a description wrapped onto an indented line, 301 bytes as YAML joins it, fails" "$d" FAIL "descriptions: a description over the budget of 300 bytes"

echo "tests: budget: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
