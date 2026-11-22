#!/usr/bin/env bash
# Plants for gate-receipt (steps 5b.1 and 5b.2, and step 5b's review,
# named "review F<n>" after its findings): each planted break in
# lib/receipt.pl or the wrapper turns tests/gate-receipt.test.sh red for
# its stated reason, in a throwaway copy of the repo, with only the cases
# kept for that reason (after they pass on the clean copy). The breaks are
# data: "=== NAME | FILE | REASON", the text OLD (in FILE exactly once),
# "---", the text NEW (tests/lib.sh, plant_data). PLANT_SHARD=K/N runs
# every Nth one from the Kth.
# shellcheck disable=SC2016 # the plants are literal perl and shell text
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: gate-receipt"
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/plants.txt" <<'PLANTS-END'
=== the context line without the gate and tree | method/scripts/method/lib/receipt.pl | a gate's start is answered with its context line, the gate and the tree
additionalContext => $line }
---
additionalContext => 'METHOD-ACTIVE' }
=== any agent taken for a gate | method/scripts/method/lib/receipt.pl | an agent that is not a gate gets nothing and no receipt
    return 0 unless defined $gate && !ref $gate && exists $w->{gate}{$gate};
---
    return 0 unless defined $gate && !ref $gate;
=== any id taken | method/scripts/method/lib/receipt.pl | an agent id that is not a plain id gets nothing
sub id_ok { my ($s) = @_; return defined $s && !ref $s && $s =~ /\A[A-Za-z0-9_.-]{1,128}\z/ }
---
sub id_ok { my ($s) = @_; return defined $s && !ref $s }
=== an opening word only alone | method/scripts/method/lib/receipt.pl | an opening word alone, or followed by a space or a colon, is read: REQUEST CHANGES: two findings
$first eq $_ || index($first, "$_ ") == 0 || index($first, "$_:") == 0 }
---
$first eq $_ || index($first, "$_ ") == 0 }
=== trailing spaces and CRs kept | method/scripts/method/lib/receipt.pl | trailing spaces, CRs and blank lines around the lines are let be
$x =~ s/[ \t\r]+\z//;
---
$x =~ s/[ \t]+\z//;
=== any end line taken | method/scripts/method/lib/receipt.pl | an end line with another tree is sent back
defined $word && $last eq "$w->{end} $tree";
---
defined $word && index($last, $w->{end}) == 0;
=== never sent back | method/scripts/method/lib/receipt.pl | a first line that is not a word is sent back: '**APPROVE**'
      if (!$r->{blocked} && !@why) {
---
      if (0) {
=== sent back every time | method/scripts/method/lib/receipt.pl | still without its lines: let go once, not checked
      if (!$r->{blocked} && !@why) {
---
      if (!@why) {
=== the receipt written after the block | method/scripts/method/lib/receipt.pl | the receipt says it was sent back, before the gate answers again
        $r->{why} = [$code];
        save($dir, $name, $r);
        return Hook::block
---
        return Hook::block
=== a handback never refused | method/scripts/method/lib/receipt.pl | a handback without its lines is refused once
  if (!$ok && !$r->{denied}) {
---
  if (0) {
=== a handback refused every time | method/scripts/method/lib/receipt.pl | the second handback without its lines is let through
  if (!$ok && !$r->{denied}) {
---
  if (!$ok) {
=== auto mode judged like default mode | method/scripts/method/lib/receipt.pl | auto mode with no handback: no report was delivered; no block
  } elsif ($auto) {
---
  } elsif (0) {
=== a resumed gate's earlier receipt left standing | method/scripts/method/lib/receipt.pl | resumed under the same agent id, its earlier receipt no longer stands
    $o->{state} = $w->{unchecked};
---
    next;
=== a stop with no start judged | method/scripts/method/lib/receipt.pl | a stop with no start: not checked, never blocked
  push @why, 'no-start' unless defined $r->{started};
---
  1;
=== review F1: a handback's receipt with no start judged | method/scripts/method/lib/receipt.pl | a handback with no start, then its stop: not checked
  push @why, 'no-start' unless defined $r->{started};
---
  push @why, 'no-start' unless $r->{stops} || $r->{handback} || defined $r->{started};
=== review F1: a second stop of a run with no start judged | method/scripts/method/lib/receipt.pl | a second stop of a run with no start: not checked, never blocked
  push @why, 'no-start' unless defined $r->{started};
---
  push @why, 'no-start' unless $r->{stops} || defined $r->{started};
=== review F2: a stop takes the run of its prompt id | method/scripts/method/lib/receipt.pl | a background gate whose stop comes after the owner's next message gets its run's receipt
  my $r = load($dir, $name) || fresh($in, $gate, 'no-start', $run);
---
  my $r = load($dir, $name);
  $r = undef if $r && ($r->{prompt} // '') ne ($in->{prompt_id} // '');
  $r ||= fresh($in, $gate, 'no-start', $run);
=== review F2: a handback takes the run of its prompt id | method/scripts/method/lib/receipt.pl | a handback after the owner's next message is noted in its run's receipt
  my (undef, undef, $name, $r) = current($in, $gate, $dir);
---
  my (undef, undef, $name, $r) = current($in, $gate, $dir);
  $r = fresh($in, $gate, 'no-start', 1) if ($r->{prompt} // '') ne ($in->{prompt_id} // '');
=== review F2: a prompt id required | method/scripts/method/lib/receipt.pl | a stop with no prompt id takes the agent's newest run
    return 0 unless id_ok($in->{session_id}) && id_ok($in->{agent_id});
---
    return 0 unless id_ok($in->{session_id}) && id_ok($in->{agent_id}) && id_ok($in->{prompt_id});
=== review F2: a start takes the agent's newest run again | method/scripts/method/lib/receipt.pl | a start makes the agent's next run
    $run = newest($dir, $part) + 1;
---
    $run = newest($dir, $part) || 1;
=== review F2: no receipt before the start's clean check | method/scripts/method/lib/receipt.pl | a start cut off before it has looked at the files leaves its run not checked
    eval { save($dir, $name, fresh($in, $gate, 'starting', $run)) };
---

=== review F2: a cut-off start's run without a tree | method/scripts/method/lib/receipt.pl | a start cut off before it has looked at the files leaves its run not checked
 if !defined $r->{started} && ($r->{tree} // 'none') eq 'none';
---
 if !$r;
=== no gates.log line | method/scripts/method/lib/receipt.pl | gates.log gets one fixed-field line
  log_line($project, $r, $in);
---
  1;
=== the context line's cap too low | method/scripts/method/lib/receipt.pl | the context line with a SHA-256 tree
our $CONTEXT_MAX = 120;
---
our $CONTEXT_MAX = 100;
=== code 3 without its line taken as a block | method/.claude/hooks/method/gate-receipt.sh | code 3 without its line is exit 0
  if [ -n "$line" ]; then
---
  if true; then
=== a crash passed on | method/.claude/hooks/method/gate-receipt.sh | a crash is exit 0, with nothing printed
fi
exit 0
---
fi
exit "$code"
=== the store taken through its link | method/scripts/method/lib/receipt.pl | with .git a link, the receipt is written where it points
  return defined $real && -d $real ? $real : undef;
---
  return -d $c && !-l $c ? $c : undef;
=== 5b.2 unclean at the start not judged | method/scripts/method/lib/receipt.pl | files not clean at the start make it INVALID
    push @why, 'unclean-start' if defined $r->{clean_start} && !$r->{clean_start};
---
    1;
=== 5b.2 sent back though the start makes it INVALID | method/scripts/method/lib/receipt.pl | a report without its lines is not sent back when the start already makes it INVALID
      if (!$r->{blocked} && !@why) {
---
      if (!$r->{blocked} && !grep { $_ eq 'no-start' } @why) {
=== 5b.2 unclean at the stop not judged | method/scripts/method/lib/receipt.pl | files not clean at the stop make it INVALID
  push @why, 'unclean-stop' if defined $g->{clean} && !$g->{clean};
---

=== 5b.2 the tree not compared | method/scripts/method/lib/receipt.pl | a tree changed while the gate ran makes it INVALID
  push @why, 'tree-changed' if $g->{tree} ne $r->{tree};
---

=== 5b.2 the stop's folder judged though it is another worktree | method/scripts/method/lib/receipt.pl | a stop run from another repository leaves the files not checked
  my $same = defined $g->{top} && defined $r->{top} && $g->{top} eq $r->{top};
---
  my $same = 1;
=== 5b.2 files that cannot be told clean taken as clean | method/scripts/method/lib/receipt.pl | files that cannot be told clean leave it not checked
  push @why, 'clean-unknown' unless $same && defined $g->{clean} && defined $r->{clean_start};
---

=== 5b.2 write marks not judged | method/scripts/method/lib/receipt.pl | a write by the main session while the gate runs makes it INVALID
  push @why, 'write-mark' if $marked;
---

=== 5b.2 a gate's own call marked | method/scripts/method/lib/receipt.pl | the gate's own writes leave no mark
  return 0 if defined $type && !ref $type && exists words()->{gate}{$type};
---

=== 5b.2 marks before the start counted | method/scripts/method/lib/receipt.pl | a mark before the gate's start does not count
$l->[1] > $r->{started} && $l->[1] < $r->{stopped}
---
$l->[1] < $r->{stopped}
=== 5b.2 marks of another worktree counted | method/scripts/method/lib/receipt.pl | a write in another worktree of the repository does not count
$l->[2] eq $r->{top} && $l->[1] > $r->{started}
---
$l->[1] > $r->{started}
=== 5b.2 marks that cannot be read taken as none | method/scripts/method/lib/receipt.pl | marks that cannot be read leave it not checked
  push @why, 'marks-unreadable' unless defined $marked;
---

=== 5b.2 no running file at the start | method/scripts/method/lib/receipt.pl | the start writes a running file in git's folder, so the guard marks writes
      running($dir, 1);
      Log::write_whole($dir, running_of(
---
      running($dir, 1);
      0 && Log::write_whole($dir, running_of(
=== 5b.2 the running file kept after the stop | method/scripts/method/lib/receipt.pl | the stop removes the running file
  unlink File::Spec->catfile($dir, running_of(
---
  0 && unlink File::Spec->catfile($dir, running_of(
=== review F3: the running file removed at auto mode's stop with no handback | method/scripts/method/lib/receipt.pl | auto mode: a stop with no handback keeps the running file
 running_of($part, $run)) unless $nudged;
---
 running_of($part, $run));
=== review F4: no judging receipt before the stop's checks | method/scripts/method/lib/receipt.pl | a second stop of a VALID run, cut off while it waits for the record, leaves it not checked
  @$r{qw(state why stopped)} = ($w->{unchecked}, ['judging'], Time::HiRes::time());
  save($dir, $name, $r);
---
  @$r{qw(state why stopped)} = ($w->{unchecked}, ['judging'], Time::HiRes::time());
=== review F6: the last request's cache reads kept for the first's | method/scripts/method/lib/receipt.pl | the receipt keeps the first request's cache reads apart
$ev->{tokens}{cache_read_first} = 0 + $c if $first &&
---
$ev->{tokens}{cache_read_first} = 0 + $c if
=== 5b.2 a running file left by a crash kept | method/scripts/method/lib/receipt.pl | a running file left by a crash a day ago is removed at the next start
elsif ($prune) { unlink $p }
---
elsif (0) { }
=== 5b.2 the record not waited for | method/scripts/method/lib/receipt.pl | a record written 0.3 s after the stop began still makes it VALID
  my $until = Time::HiRes::time() + ($ctx->{wait} ? $WAIT : 0);
---
  my $until = Time::HiRes::time();
=== 5b.2 a record that never completes taken as read | method/scripts/method/lib/receipt.pl | a record that never completes leaves it not checked
    return 'record-late' if Time::HiRes::time() >= $until;
---
    return undef if Time::HiRes::time() >= $until;
=== 5b.2 any file read as the record | method/scripts/method/lib/receipt.pl | a record that is not a regular file leaves it not checked
      return 'record-unreadable' unless -f $fh;
---

=== 5b.2 a record of any size read | method/scripts/method/lib/receipt.pl | a record over 200 MB is not read
      return 'record-unreadable' if !defined $size || $size > $RECORD_MAX;
---
      return 'record-unreadable' if !defined $size;
=== 5b.2 lines that are not JSON skipped | method/scripts/method/lib/receipt.pl | a record line that is not JSON leaves it not checked
  push @why, 'record-unreadable' if $ev{bad};
---

=== 5b.2 models not checked against the list | method/scripts/method/lib/receipt.pl | a model off the project's list makes it INVALID
  push @why, 'model-off-list' if !%allowed || grep { !$allowed{$_} } @{ $ev{models} };
---
  push @why, 'model-off-list' if !%allowed;
=== 5b.2 no model list taken as any model | method/scripts/method/lib/receipt.pl | no availableModels in the project's settings makes it INVALID
  push @why, 'model-off-list' if !%allowed || grep { !$allowed{$_} } @{ $ev{models} };
---
  push @why, 'model-off-list' if %allowed && grep { !$allowed{$_} } @{ $ev{models} };
=== 5b.2 a reply the client wrote taken as a model's | method/scripts/method/lib/receipt.pl | a reply the client wrote itself leaves it not checked
    if ($model eq '<synthetic>') { $ev->{synthetic} = 1 }
---
    if (0) { }
=== 5b.2 no model line not required | method/scripts/method/lib/receipt.pl | a record with no model line leaves it not checked
  push @why, 'no-model' if $whole && !@{ $ev{models} };
---

=== 5b.2 efforts not judged | method/scripts/method/lib/receipt.pl | a request at effort low makes it INVALID
  push @why, 'effort-low' if $floor && grep { ($RANK{$_} || 0) < $floor } @{ $ev{efforts} };
---

=== 5b.2 the request's effort not read | method/scripts/method/lib/receipt.pl | a request at effort low makes it INVALID
    effort_seen($ev, $p->{output_config}{effort}) if
---
    1 if
=== 5b.2 an assistant line's effort not read | method/scripts/method/lib/receipt.pl | an assistant line at effort low makes it INVALID
    effort_seen($ev, part($f->{$k})) if exists $f->{$k};
---
    1;
=== 5b.2 no effort not required | method/scripts/method/lib/receipt.pl | a record with no effort leaves it not checked
  push @why, 'no-effort' if $whole && !@{ $ev{efforts} };
---

=== 5b.2 the method file's effort not required | method/scripts/method/lib/receipt.pl | a method file without its effort makes it INVALID
    push @why, 'instructions-differ' if defined $r->{top} && !$r->{effort_file};
---
    1;
=== 5b.2 instructions not compared | method/scripts/method/lib/receipt.pl | instructions other than the method file's make it INVALID
    push @why, 'instructions-differ' if $same && !($m && trimmed($ev{prompt}) eq $m->{body});
---
    1;
=== 6.2 instructions not compared, on the method's own gate files | method/scripts/method/lib/receipt.pl | a method gate file edited after the start makes it INVALID
    push @why, 'instructions-differ' if $same && !($m && trimmed($ev{prompt}) eq $m->{body});
---
    1;
=== 6.2 the frontmatter kept in the body, on the method's own gate files | method/scripts/method/lib/receipt.pl | a method gate file's own body makes it VALID
? ($1, $2) : ('', $text);
---
? ($1, $text) : ('', $text);
=== 5b.2 the body compared untrimmed | method/scripts/method/lib/receipt.pl | its receipt is good, with its opening word
sub trimmed { my ($s) = @_; $s =~ s/\A\s+//; $s =~ s/\s+\z//; return $s }
---
sub trimmed { return $_[0] }
=== 5b.2 the frontmatter kept in the body | method/scripts/method/lib/receipt.pl | its receipt is good, with its opening word
? ($1, $2) : ('', $text);
---
? ($1, $text) : ('', $text);
=== 5b.2 no prompt snapshot not required | method/scripts/method/lib/receipt.pl | a record with no prompt snapshot leaves it not checked
    push @why, 'no-instructions';
---
    1;
=== 5b.2 Agent calls not seen | method/scripts/method/lib/receipt.pl | an Agent call makes it INVALID
      $ev->{called} = 1 if $name eq 'Agent' || $name eq 'Task';
---

=== 5b.2 folders not compared | method/scripts/method/lib/receipt.pl | a turn in another folder makes it INVALID
  $ev->{elsewhere} = 1 if !defined $c || ref $c || sha('cwd', $c) ne $ctx->{cwd};
---

=== 5b.2 background shells not judged | method/scripts/method/lib/receipt.pl | a background shell of its own still running leaves it not checked
  push @why, 'background-task' if grep {
---
  push @why, 'background-task' if 0 && grep {
=== 5b.2 any running shell taken as the gate's own | method/scripts/method/lib/receipt.pl | another's background shell still running does not count
    && defined $_->{id} && !ref $_->{id} && $ev{bg}{ $_->{id} } } @tasks;
---
    } @tasks;
=== 5b.2 a shell that ended counted | method/scripts/method/lib/receipt.pl | another's background shell still running does not count
($_->{status} // '') eq 'running'
---
1
=== 5b.2 packets not judged | method/scripts/method/lib/receipt.pl | a packet built for other files makes it INVALID
  push @why, 'packet-other-tree' if grep { $_ ne $r->{tree} } @{ $ev{packets} };
---

=== 5b.2 a Read result's line numbers kept | method/scripts/method/lib/receipt.pl | a packet for other files read with line numbers makes it INVALID
    $x =~ s/\A[ \t]*[0-9]+(?:\t|\x{2192})//;
---

=== 5b.2 tokens counted on every line | method/scripts/method/lib/receipt.pl | tokens are counted once a message id
!(defined $id && $ev->{counted}{$id}++)
---
1
=== 5b.2 the handback not confirmed | method/scripts/method/lib/receipt.pl | a handback the record shows refused leaves it not checked
  push @why, 'handback-unconfirmed' if defined $hb
---
  push @why, 'handback-unconfirmed' if 0 && defined $hb
=== 5b.2 a refused handback taken as accepted | method/scripts/method/lib/receipt.pl | a handback the record shows refused leaves it not checked
      $ev->{hb_ok} = $c->{is_error} ? 0 : 1;
---
      $ev->{hb_ok} = 1;
=== 5b.2 the handback's message not compared | method/scripts/method/lib/receipt.pl | a handback the record shows with another message leaves it not checked
$ev{hb_sha} eq ($r->{handback}{sha} // '')
---
1
=== 5b.2 the second word's reasons not first | method/scripts/method/lib/receipt.pl | with reasons of both kinds, INVALID, its reasons first
  return ((grep { $WRONG{$_} } @why), (grep { !$WRONG{$_} } @why));
---
  return @why;
=== 5b.2 the second word never given | method/scripts/method/lib/receipt.pl | a model off the project's list makes it INVALID
  return $w->{wrong} if grep { $WRONG{$_} } @why;
---

=== 5b.2 gates.log without the model | method/scripts/method/lib/receipt.pl | gates.log gets one fixed-field line
  my $model = ref $r->{models} eq 'ARRAY' ? $r->{models}[0] : undef;
---
  my $model;
=== 5b.2 models, efforts and tokens not kept | method/scripts/method/lib/receipt.pl | the receipt keeps the models, efforts and tokens
  $r->{tokens} = $ev{tokens};
---

PLANTS-END
# Git Bash copies a link, so a .git link cannot be made there: that plant
# is skipped, and said so
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    perl -0pi -e 's/^=== the store taken through its link \|.*?(?=^=== |\z)//msg' "$work/plants.txt"
    skip "the plant on a .git link (Git Bash cannot make one)"
    ;;
esac
plant_data "$work/plants.txt" tests/gate-receipt.test.sh only
drop_sandbox "$work" || true
echo "plants: gate-receipt: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
