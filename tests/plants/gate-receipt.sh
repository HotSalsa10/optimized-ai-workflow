#!/usr/bin/env bash
# Plants for gate-receipt (step 5b.1): each planted break in lib/receipt.pl
# or the wrapper turns tests/gate-receipt.test.sh red for its stated
# reason, in a throwaway copy of the repo. The breaks are data:
# "=== NAME | FILE | REASON", the text OLD (in FILE exactly once), "---",
# the text NEW (tests/lib.sh, plant_data). PLANT_SHARD=K/N runs every Nth
# one from the Kth.
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
    push @why, 'no-start';
---
    1;
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
PLANTS-END
# Git Bash copies a link, so a .git link cannot be made there: that plant
# is skipped, and said so
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    perl -0pi -e 's/^=== the store taken through its link \|.*?(?=^=== |\z)//msg' "$work/plants.txt"
    skip "the plant on a .git link (Git Bash cannot make one)"
    ;;
esac
plant_data "$work/plants.txt" tests/gate-receipt.test.sh
drop_sandbox "$work" || true
echo "plants: gate-receipt: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
