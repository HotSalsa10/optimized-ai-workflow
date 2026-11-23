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
#   joined by single spaces: a plain or quoted value wrapped onto the next
#   lines, or one that starts there; a " #" comment dropped from a value
#   not in quotes; a quoted value counted with its quotes). Step 6.6 added
#   the wrapped forms: the client joins them and sends the whole text (the
#   review's F1, measured at 2.1.319). A block value (| or >) is counted at
#   or over YAML's count: each of its lines, blank ones too, with the
#   block's indent taken off and its line break kept (step 6b.4). The key
#   may be in quotes or have spaces before its colon, a tag or an anchor
#   before the value (!!str |, &d >-) is not counted, and each escape in a
#   double-quoted value is counted at the UTF-8 size of the character YAML
#   reads (\L and \P 3 bytes; step 6b's review, R16).
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
          # the key as YAML reads it: plain or in quotes, with spaces
          # allowed before its colon (step 6b'"'"'s review, R16)
          if ($l[$i] =~ /\A(?:description|\x22description\x22|\x27description\x27)[ \t]*:[ \t]*(.*?)[ \t]*\z/) {
            $v = $1;
            # a tag or an anchor before the value (!!str |, &d >-) is not
            # part of it
            $v =~ s/\A(?:(?:&[^ \t]+|![^ \t]*)(?:[ \t]+|\z))+//;
            # the lines YAML reads as part of the value: each indented or
            # empty line after it, up to the next key, trimmed; each line
            # with text is kept with the blank lines just before it, since
            # YAML joins two lines with a space when none come between and
            # with one line break for each blank line otherwise
            my (@more, $blank);
            $blank = 0;
            for my $j ($i + 1 .. $#l) {
              last unless $l[$j] =~ /\A(?:[ \t]|\z)/;
              if ($l[$j] =~ /\A[ \t]*(\S.*?)[ \t]*\z/) { push @more, [$1, $blank]; $blank = 0 } else { $blank++ }
            }
            # the lines joined as YAML joins them (blank lines before
            # the first do not count)
            my $joined = sub { my ($f, @r) = @_; my $s = $f->[0]; $s .= ($_->[1] ? "\n" x $_->[1] : " ") . $_->[0] for @r; $s };
            if ($v =~ /\A[|>]([-+0-9]*)(?:[ \t]+#.*)?\z/) {
              # a block value: each of its lines, blank ones too, with the
              # block'"'"'s indent taken off (its number, else the first
              # line with text), and a line break after each: at or over
              # what YAML keeps (L24)
              my ($ind) = $1 =~ /([1-9])/;
              my @b;
              for my $j ($i + 1 .. $#l) { last unless $l[$j] =~ /\A(?:[ \t]|\z)/; push @b, $l[$j] }
              if (!defined $ind) { for (@b) { if (/\A([ \t]*)\S/) { $ind = length $1; last } } }
              $ind = 0 unless defined $ind;
              $v = join "", map { (my $x = $_) =~ s/\A[ \t]{0,$ind}//; "$x\n" } @b;
            } elsif ($v =~ /\A[\x22\x27]/) {
              $v = $joined->([$v, 0], @more);
              # in double quotes, each escape counted at the UTF-8 size of
              # the character YAML reads: \L and \P 3 bytes, \N and \_ 2,
              # \xHH, \uHHHH and \UHHHHHHHH the size of their character,
              # any other 1 (step 6b'"'"'s review, R16)
              if ($v =~ /\A\x22/) {
                my $u = sub { my $c = hex shift; $c < 0x80 ? 1 : $c < 0x800 ? 2 : $c < 0x10000 ? 3 : 4 };
                my %one = (L => 3, P => 3, N => 2, _ => 2);
                $v =~ s/\\(?:x([0-9A-Fa-f]{2})|u([0-9A-Fa-f]{4})|U([0-9A-Fa-f]{8})|(.))/"x" x (defined $1 ? $u->($1) : defined $2 ? $u->($2) : defined $3 ? $u->($3) : ($one{$4} || 1))/ges;
              }
            } else {
              my @p;
              for my $s (grep { length $_->[0] } [$v, 0], @more) {
                if ($s->[0] =~ /\A#/) { last if @p; next }
                (my $c = $s->[0]) =~ s/[ \t]+#.*\z//;
                push @p, [$c, $s->[1]];
                last if $c ne $s->[0];
              }
              $v = @p ? $joined->(@p) : "";
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
if counted "$d" "DESC 14 method/.claude/agents/method/q.md" && counted "$d" "DESC 14 method/.claude/agents/method/b.md" && counted "$d" "DESC 0 method/.claude/agents/method/n.md" && counted "$d" "DESC 7 method/.claude/skills/method-s/SKILL.md" && counted "$d" "DESCS 35 4"; then
  pass "the counter: a quoted value as written, a block value's lines each with its line break (14, as YAML folds it), a body line not counted, a skill's SKILL.md only"
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
  counted "$d" "DESC 5 method/.claude/agents/method/h.md" && counted "$d" "DESC 8 method/.claude/agents/method/b.md"; then
  pass "the counter: continued lines joined by one space, a value on the next line, a comment dropped from a plain value, a > block with its final line break, 8 (as YAML reads them)"
else
  fail "the counter: continued lines joined by one space, a value on the next line, a comment dropped from a plain value (as YAML reads them)" "$(budget_read "$d")"
fi
d=$(case_dir desc-wrapped) || abort_sandbox
printf 'r\n' >"$d/method/.claude/rules/method/r.md"
mkdir -p "$d/method/.claude/skills/method-w" && printf -- '---\nname: w\ndescription: %s\n  %s\n---\n' "$(xs 200)" "$(xs 100)" >"$d/method/.claude/skills/method-w/SKILL.md"
want "the counter: a description wrapped onto an indented line, 301 bytes as YAML joins it, fails" "$d" FAIL "descriptions: a description over the budget of 300 bytes"
# (step 6b.4, L24) a block value (| or >) is counted at or over what YAML
# reads: each of its lines with the block's indent taken off and its line
# break kept, blank lines too. YAML keeps the same bytes for | with its
# final break (clip), fewer when it folds blank lines (>), drops the final
# break (|-) or the trailing blank lines (clip); the values below are
# PyYAML's for the same text, where they are equal
d=$(case_dir desc-block) || abort_sandbox
printf 'r\n' >"$d/method/.claude/rules/method/r.md"
printf -- '---\nname: l\ndescription: |\n  a\n\n  b\n---\n' >"$d/method/.claude/agents/method/l.md"
printf -- '---\nname: i\ndescription: |\n  a\n    b\nmodel: x\n---\n' >"$d/method/.claude/agents/method/i.md"
printf -- '---\nname: k\ndescription: |+\n  a\n\n---\n' >"$d/method/.claude/agents/method/k.md"
printf -- '---\nname: e\ndescription: |1\n   a\n---\n' >"$d/method/.claude/agents/method/e.md"
printf -- '---\nname: s\ndescription: |-\n  a\n  b\n---\n' >"$d/method/.claude/agents/method/s.md"
printf -- '---\nname: f\ndescription: >\n  a\n\n  b\n---\n' >"$d/method/.claude/agents/method/f.md"
printf -- '---\nname: t\ndescription: |\n  a\n\n\n---\n' >"$d/method/.claude/agents/method/t.md"
if counted "$d" "DESC 5 method/.claude/agents/method/l.md" && counted "$d" "DESC 6 method/.claude/agents/method/i.md" && counted "$d" "DESC 3 method/.claude/agents/method/k.md" &&
  counted "$d" "DESC 4 method/.claude/agents/method/e.md"; then
  pass "the counter: a | block as YAML reads it: a blank line inside (5), deeper indent kept (6), kept trailing breaks (|+, 3), an indent given by its number (|1, 4)"
else
  fail "the counter: a | block as YAML reads it: a blank line inside (5), deeper indent kept (6), kept trailing breaks (|+, 3), an indent given by its number (|1, 4)" "$(budget_read "$d")"
fi
if counted "$d" "DESC 4 method/.claude/agents/method/s.md" && counted "$d" "DESC 5 method/.claude/agents/method/f.md" && counted "$d" "DESC 4 method/.claude/agents/method/t.md"; then
  pass "the counter: where YAML keeps fewer bytes, a block is counted over, never under: |- (4, YAML 3), a > block's blank line (5, YAML 4), two trailing blank lines (4, YAML 2)"
else
  fail "the counter: where YAML keeps fewer bytes, a block is counted over, never under: |- (4, YAML 3), a > block's blank line (5, YAML 4), two trailing blank lines (4, YAML 2)" "$(budget_read "$d")"
fi
d=$(case_dir desc-block-over) || abort_sandbox
printf 'r\n' >"$d/method/.claude/rules/method/r.md"
mkdir -p "$d/method/.claude/skills/method-b" && printf -- '---\nname: b\ndescription: |\n  %s\n\n  %s\n---\n' "$(xs 149)" "$(xs 149)" >"$d/method/.claude/skills/method-b/SKILL.md"
want "the counter: a | block of two lines of 149 bytes and a blank line between, 301 bytes as YAML reads it, fails" "$d" FAIL "descriptions: a description over the budget of 300 bytes"
# (step 6b.4's check) blank lines inside a plain or quoted value: YAML
# keeps one line break for each, where lines with none between are joined
# by a space; blank lines before the value's first line are not part of
# it. The values below are PyYAML's for the same text, the quoted one
# counted over (its quotes are counted as written)
d=$(case_dir desc-blank) || abort_sandbox
printf 'r\n' >"$d/method/.claude/rules/method/r.md"
printf -- '---\nname: p\ndescription: a\n\n\n  b\n---\n' >"$d/method/.claude/agents/method/p.md"
printf -- '---\nname: o\ndescription: a\n\n  b\nmodel: x\n---\n' >"$d/method/.claude/agents/method/o.md"
printf -- '---\nname: n\ndescription:\n\n  a\n\n\n  b\n---\n' >"$d/method/.claude/agents/method/n.md"
printf -- '---\nname: q\ndescription: "a\n\n\n\n\n  b"\n---\n' >"$d/method/.claude/agents/method/q.md"
if counted "$d" "DESC 4 method/.claude/agents/method/p.md" && counted "$d" "DESC 3 method/.claude/agents/method/o.md" && counted "$d" "DESC 4 method/.claude/agents/method/n.md" &&
  counted "$d" "DESC 8 method/.claude/agents/method/q.md"; then
  pass "the counter: blank lines inside a plain value, one line break each: two (4), one (3), none counted before its first line (4); in a quoted value, counted over (8, YAML 6)"
else
  fail "the counter: blank lines inside a plain value, one line break each: two (4), one (3), none counted before its first line (4); in a quoted value, counted over (8, YAML 6)" "$(budget_read "$d")"
fi
d=$(case_dir desc-blank-over) || abort_sandbox
printf 'r\n' >"$d/method/.claude/rules/method/r.md"
mkdir -p "$d/method/.claude/skills/method-p" && printf -- '---\nname: p\ndescription: %s\n\n\n  %s\n---\n' "$(xs 150)" "$(xs 149)" >"$d/method/.claude/skills/method-p/SKILL.md"
want "the counter: a plain value of two lines of 150 and 149 bytes with two blank lines between, 301 bytes as YAML reads it, fails" "$d" FAIL "descriptions: a description over the budget of 300 bytes"
# (step 6b's review, R16) the key in quotes or with a space before its
# colon, a tag or an anchor before the value, and the escapes of a
# double-quoted value, each as YAML reads it. The values below are PyYAML's
# for the same text, the quoted ones counted with their quotes
d=$(case_dir desc-key) || abort_sandbox
printf 'r\n' >"$d/method/.claude/rules/method/r.md"
printf -- '---\nname: q\n"description": abc\n---\n' >"$d/method/.claude/agents/method/q.md"
printf -- '---\nname: s\ndescription : abcd\n---\n' >"$d/method/.claude/agents/method/s.md"
printf -- "---\nname: a\n'description':  abcde\n---\n" >"$d/method/.claude/agents/method/a.md"
if counted "$d" "DESC 3 method/.claude/agents/method/q.md" && counted "$d" "DESC 4 method/.claude/agents/method/s.md" && counted "$d" "DESC 5 method/.claude/agents/method/a.md"; then
  pass "the counter: the key in double quotes (3), with a space before its colon (4), in single quotes (5), as YAML reads it"
else
  fail "the counter: the key in double quotes (3), with a space before its colon (4), in single quotes (5), as YAML reads it" "$(budget_read "$d")"
fi
d=$(case_dir desc-key-over) || abort_sandbox
printf 'r\n' >"$d/method/.claude/rules/method/r.md"
mkdir -p "$d/method/.claude/skills/method-q" && printf -- '---\nname: q\n"description": %s\n---\n' "$(xs 301)" >"$d/method/.claude/skills/method-q/SKILL.md"
want "the counter: a description of 301 bytes under a key in quotes fails" "$d" FAIL "descriptions: a description over the budget of 300 bytes"
d=$(case_dir desc-props) || abort_sandbox
printf 'r\n' >"$d/method/.claude/rules/method/r.md"
printf -- '---\nname: t\ndescription: !!str |\n  a\n    b\n---\n' >"$d/method/.claude/agents/method/t.md"
printf -- '---\nname: f\ndescription: &d >-\n  a\n  b\n---\n' >"$d/method/.claude/agents/method/f.md"
printf -- '---\nname: q\ndescription: !!str "q"\n---\n' >"$d/method/.claude/agents/method/q.md"
printf -- '---\nname: p\ndescription: &a plain words\n---\n' >"$d/method/.claude/agents/method/p.md"
if counted "$d" "DESC 6 method/.claude/agents/method/t.md" && counted "$d" "DESC 4 method/.claude/agents/method/f.md" && counted "$d" "DESC 3 method/.claude/agents/method/q.md" &&
  counted "$d" "DESC 11 method/.claude/agents/method/p.md"; then
  pass "the counter: a tag or an anchor before the value is not counted, and the block after it is read as a block: !!str | (6), &d >- (4, YAML 3), !!str and a quoted value (3, YAML 1), &a and a plain value (11)"
else
  fail "the counter: a tag or an anchor before the value is not counted, and the block after it is read as a block: !!str | (6), &d >- (4, YAML 3), !!str and a quoted value (3, YAML 1), &a and a plain value (11)" "$(budget_read "$d")"
fi
d=$(case_dir desc-props-over) || abort_sandbox
printf 'r\n' >"$d/method/.claude/rules/method/r.md"
mkdir -p "$d/method/.claude/skills/method-t" && printf -- '---\nname: t\ndescription: &d |\n  %s\n                      %s\n---\n' "$(xs 140)" "$(xs 139)" >"$d/method/.claude/skills/method-t/SKILL.md"
want "the counter: a | block after an anchor, its second line 20 spaces deeper, 301 bytes as YAML reads it, fails" "$d" FAIL "descriptions: a description over the budget of 300 bytes"
d=$(case_dir desc-escapes) || abort_sandbox
printf 'r\n' >"$d/method/.claude/rules/method/r.md"
cat >"$d/method/.claude/agents/method/e.md" <<'TEXT'
---
name: e
description: "\L\P\N\_\x41é\U0001F600\\\"\t"
---
TEXT
if counted "$d" "DESC 22 method/.claude/agents/method/e.md"; then
  pass "the counter: each escape in a double-quoted value at the UTF-8 size of its character (\\L, \\P 3; \\N, \\_ 2; \\x41 1; \\u00e9 2; \\U0001F600 4; \\\\, \\\", \\t 1): 22 with the quotes (YAML 20)"
else
  fail "the counter: each escape in a double-quoted value at the UTF-8 size of its character: 22 with the quotes (YAML 20)" "$(budget_read "$d")"
fi
d=$(case_dir desc-escapes-over) || abort_sandbox
printf 'r\n' >"$d/method/.claude/rules/method/r.md"
mkdir -p "$d/method/.claude/skills/method-e" && printf -- '---\nname: e\ndescription: "%s%s"\n---\n' "$(xs 271)" '\L\L\L\L\L\L\L\L\L\L' >"$d/method/.claude/skills/method-e/SKILL.md"
want "the counter: a double-quoted value of 271 bytes and ten \\L escapes, 301 bytes as YAML reads it (293 as written), fails" "$d" FAIL "descriptions: a description over the budget of 300 bytes"

echo "tests: budget: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
