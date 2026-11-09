#!/usr/bin/env bash
# Plants for the guard's reader and frame (step 5.5's last repair loop,
# kept here since step 5's final review), and for its write marks for a
# running gate (step 5b.2, in lib/guard.pl, lib/protect.pl's write test and
# lib/receipt.pl's mark): each planted break turns
# tests/guard.test.sh red for its stated reason, in a throwaway copy of the
# repo. The breaks are data: "=== NAME | FILE | REASON", the text OLD (in
# FILE exactly once), "---", the text NEW (tests/lib.sh, plant_data).
# PLANT_SHARD=K/N runs every Nth one from the Kth.
# shellcheck disable=SC2016 # the plants are literal perl text
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: guard (reader)"
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/plants.txt" <<'PLANTS-END'
=== a carriage return not doubted | method/scripts/method/lib/shell.pl | a CR on a decoy end line ends the reader's here-document early [R3-F2]
  push @why, 'a carriage return' if $t =~ /\r/;
---
  push @why, 'a carriage return' if 0;
=== arithmetic not doubted | method/scripts/method/lib/shell.pl | (( << )) after if hides no lines (refused whole since 5.5 repair loop 3)
  push @why, 'arithmetic' if $arith ||
---
  push @why, 'arithmetic' if 0 &&
=== code held in a variable not doubted | method/scripts/method/lib/shell.pl | x in a (( )) runs the substitution in its value [R3-F3]
  push @why, 'code held in a variable' if $t =~
---
  push @why, 'code held in a variable' if 0 && $t =~
=== ${ } not doubted | method/scripts/method/lib/shell.pl | ${ << } hides no lines (refused whole since 5.5 repair loop 3)
{ push @why, 'a ${ } the guard cannot read'; last }
---
{ last }
=== extended globs and zsh forms not doubted | method/scripts/method/lib/shell.pl | an extglob in an argument, then git status, a known false refusal [R3-S8]
  push @why, 'an extended glob or a zsh form' if
---
  push @why, 'an extended glob or a zsh form' if 0 &&
=== a comment after a parenthesis not doubted | method/scripts/method/lib/shell.pl | a comment right after ) inside $( ) closes it early [R3-S2]
  push @why, 'a comment right after a parenthesis' if
---
  push @why, 'a comment right after a parenthesis' if 0 &&
=== no cap on substitutions | method/scripts/method/lib/shell.pl | more substitutions than the guard reads, next to git, are refused whole
if $subs > 64;
---
if 0;
=== line continuations not joined | method/scripts/method/lib/guard.pl | (( split by a line continuation hides the next line [R3-F1]
my ($text0, $joined) = Shell::join_lines($cmd);
---
my ($text0, $joined) = ($cmd, 1);
=== a continuation beside a here-document taken as joined | method/scripts/method/lib/guard.pl | (( split by a line continuation hides the next line [R3-F1]
if defined $joined && !$joined;
---
if 0;
=== the doubts not asked | method/scripts/method/lib/guard.pl | (( << )) after if hides no lines (refused whole since 5.5 repair loop 3)
my @doubt = Shell::doubts($cmd);
---
my @doubt = ();
=== xargs into a shell or a watched command let through | method/scripts/method/lib/guard.pl | xargs -I@ sh -c @ runs what is piped in [R3-F6]
if ((grep { $_ eq 'xargs' } @{ $c->{via} || [] }) &&
---
if (0 &&
=== xargs building its command word let through | method/scripts/method/lib/guard.pl | xargs building the name of the program it runs from its replace string
if (defined $rep && defined $word && $rep ne '' && index($word, $rep) >= 0) {
---
if (0) {
=== programs that run another one let through | method/scripts/method/lib/guard.pl | flock runs the command after its lock file [R3-S11]
if ($OPAQUE{$n} && @w > 1
---
if (0 && @w > 1
=== nesting too deep refused only next to a watched word | method/scripts/method/lib/guard.pl | a glob-hidden git nested ten deep [R3-F9]
 || $_ eq 'commands nested too deep' } @{ $c->{unread} }) ? 1
---
 } @{ $c->{unread} }) ? 1
=== an escaped backtick taken to close | method/scripts/method/lib/shell.pl | a glob-hidden git inside nested escaped backticks [R3-F9]
    if ($c eq '\\') { $i++; next }
    return $i if $c eq '`';
---
    return $i if $c eq '`';
=== substitutions inside arithmetic not read | method/scripts/method/lib/shell.pl | a glob-hidden git inside (( $( ) )) [R3-F9]
push @{ $word->{subs} }, subs_in(substr($text, 2, -2));
---
1;
=== $((cmd) ) taken for arithmetic | method/scripts/method/lib/shell.pl | a glob-hidden git inside $((cmd) ) [R3-F9]
      if (!defined $e) { push @t, { error => 'an unclosed $(' }; last }
      $arith = 0 if $arith && substr($s, $e - 1, 1) ne ')';
---
      if (!defined $e) { push @t, { error => 'an unclosed $(' }; last }
=== perl -Mstrict taken for an inline program | method/scripts/method/lib/shell.pl | perl -M reads its program from stdin [R3-F7]
  perl => qr/\A-[nplawsStTWXUu0-9]*[eE]/,
---
  perlx => 1,
=== perl -I dir taken for a program file | method/scripts/method/lib/shell.pl | perl -I dir reads its program from stdin [R3-F7]
$VALUE{perl} = qr/\A-[IM]\z/;
---
1;
=== awk -f /dev/stdin not read as code from stdin | method/scripts/method/lib/shell.pl | awk -f /dev/stdin reads its program from stdin [R3-F7]
    if ($awk_stdin) {
---
    if (0) {
=== the word in ${x:-word} not seen | method/scripts/method/lib/guard.pl | git in a default value as the command word [R3-F10]
  $t =~ s/\$\{([^{}]*)\}/' ' . join(' ', split m{[:\/=+?#%^,*\-]+}, $1) . ' '/ge;
---
  1;
=== $"..." not read as its text | method/scripts/method/lib/guard.pl | git spelt g$""it piped into bash [R3-S7]
  $t =~ s/\$(?=")//g;
---
  1;
=== brace expansions not expanded | method/scripts/method/lib/guard.pl | a brace-hidden git piped into bash [R3-S7]
    push @more, brace_words($1);
---
    1;
=== an extglob in a word not taken for a glob | method/scripts/method/lib/shell.pl | an extglob inside the command word, gi@(t) [R3-S8]
    $word->{flags}{glob} = 1 if $c =~ /[@+!]/ && substr($s, $i + 1, 1) eq '(';
---
    1;
=== the watched-word scan stops at the first slash | method/scripts/method/lib/guard.pl | git by its full path inside a substitution is watched
    $i-- while $i > 0 && substr($t, $i - 1, 1) =~ m{[\w./-]};
---
    1;
=== here-document bodies doubted as code | method/scripts/method/lib/shell.pl | a commit message whose body holds (( )) and @( ) text
  $q = blank_bodies($q, 1);
---
  1;
=== a here-document delimiter quote blanked | method/scripts/method/lib/shell.pl | a backslash at a line end inside a quoted here-document commit message [R3-S3]
    if (($ch eq "'" || $ch eq '"') && $s =~ /<<-?[ \t]*\z/) {
---
    if (0) {
=== a plain here-document into python taken for a pipe | method/scripts/method/lib/shell.pl | reader: a pipe into a shell cannot be read; a plain here-string into an interpreter is its program, judged as an inline one (5.5 repair loop 3)
      # would be (step 5.5)
      push @{ $c->{unread} }, "an inline program for $name";
---
      # would be (step 5.5)
      push @{ $c->{unread} }, "a pipe, here-document or here-string into $name";
=== a program under $HOME/bin taken for a variable | method/scripts/method/lib/shell.pl | reader: a variable as the command word cannot be read
&& ($flags[0]{subst} || ($c->{raw}[0] // '') !~
---
&& ($flags[0]{subst} || ($c->{raw}[0] // '') =~
=== [[ a keyword again | method/scripts/method/lib/shell.pl | [[ with a variable first, then git status [R3-FR5]
in select function ! time { } ]]);
---
in select function ! time { } [[ ]]);
=== plain arithmetic marked as a substitution | method/scripts/method/lib/shell.pl | arithmetic with numbers only in a git option [R3-FR6]
      $word->{flags}{($arith && substr($s, $k + 1, $e - $k - 1) !~ /\$\(|`/) ? 'var' : 'subst'} = 1;
      push
---
      $word->{flags}{subst} = 1;
      push
=== for (( not read as arithmetic | method/scripts/method/lib/shell.pl | reader: for (( )) is arithmetic, and the loop's body is read
then|do|else|for)\z/
---
then|do|else)\z/
=== 5b.2 the write mark not made | method/scripts/method/lib/guard.pl | a write by the main session while a gate runs leaves a mark
Receipt::mark($in, $tool, $input)
---
1
=== 5b.2 an edit tool not counted as writing | method/scripts/method/lib/protect.pl | a write by the main session while a gate runs leaves a mark
  return 1 if $tool =~ /\A(?:Edit|Write|MultiEdit|NotebookEdit)\z/;
---

=== 5b.2 a gate's own call marked | method/scripts/method/lib/receipt.pl | a gate's own call leaves no mark
  return 0 if defined $type && !ref $type && exists words()->{gate}{$type};
---

=== 5b.2 any agent's call taken for a gate's | method/scripts/method/lib/receipt.pl | an agent that is not a gate leaves a mark
  return 0 if defined $type && !ref $type && exists words()->{gate}{$type};
---
  return 0 if defined $type && !ref $type;
=== 5b.2 marks made while no gate runs | method/scripts/method/lib/receipt.pl | a write leaves no mark while no gate runs
    next unless defined $real && -d $real && running($real);
---
    next unless defined $real && -d $real;
=== 5b.2 a running file left by a crash counted | method/scripts/method/lib/receipt.pl | a running file left over a day ago marks nothing
    if (@st && $st[9] >= $old) { push @fresh, $n }
---
    if (@st) { push @fresh, $n }
=== 5b.2 the mark answers | method/scripts/method/lib/receipt.pl | the guard's answer to a marked write is unchanged
    Log::append($real, $MARKS, $MARKS_CAP,
---
    print "marked\n"; Log::append($real, $MARKS, $MARKS_CAP,
=== 5b.2 calls that only read marked | method/scripts/method/lib/protect.pl | a call that only reads leaves no mark
  return writes($cmds || []) if $tool eq 'Bash' || $tool eq 'Monitor';
---
  return 1 if $tool eq 'Bash' || $tool eq 'Monitor';
=== 5b.2 an MCP tool that reads marked | method/scripts/method/lib/protect.pl | an MCP tool whose name reads leaves no mark
    return $short =~ $MCP_READS ? 0 : 1;
---
    return 1;
=== 5b.2 an edit marked in the folder the call runs in | method/scripts/method/lib/receipt.pl | an edit leaves a mark in the worktree of its file
      push @dirs, near_dir(dirname($p));
---
      push @dirs, $cwd;
=== 5b.2 a refused call marked | method/scripts/method/lib/guard.pl | a refused call leaves no mark
  log_refusal($rule, $tool, $raw, $in);
---
  eval { require File::Spec->catfile($lib, 'receipt.pl'); Receipt::mark($in, $tool, $in->{tool_input}) }; log_refusal($rule, $tool, $raw, $in);

=== the mark outside its eval | method/scripts/method/lib/guard.pl | a mark that cannot be written leaves the answer unchanged
  eval { Protect::call_writes($tool, \@cmds) && do { require File::Spec->catfile($lib, 'receipt.pl'); Receipt::mark($in, $tool, $input) }; 1 };
---
  Protect::call_writes($tool, \@cmds) && do { require File::Spec->catfile($lib, 'receipt.pl'); Receipt::mark($in, $tool, $input) };
PLANTS-END
plant_data "$work/plants.txt" tests/guard.test.sh only
drop_sandbox "$work" || true
echo "plants: guard (reader): $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
