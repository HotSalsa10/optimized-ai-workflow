#!/usr/bin/env bash
# Plants for run-checks' built-in check method-files and the lock
# (step 7.2; lib/lock.pl, lib/checks.pl): each planted break turns
# tests/method-files.test.sh red for its stated reason, in a throwaway copy
# of the repo. The breaks are data: "=== NAME | FILE | REASON", the text
# OLD (in FILE exactly once), "---", the text NEW (tests/lib.sh,
# plant_data). PLANT_SHARD=K/N runs every Nth one from the Kth.
# shellcheck disable=SC2016 # the plants are literal perl text
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: method-files"
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/plants.txt" <<'PLANTS-END'
=== the check skips the settings hash | method/scripts/method/lib/lock.pl | a stale lock line is red
      if k_hash($k) ne $l->{settings};
---
      if 0;
=== it ignores a changed file | method/scripts/method/lib/lock.pl | a changed file is red
    next if $h eq $want;
---
    next;
=== it ignores files the lock does not list | method/scripts/method/lib/lock.pl | an extra untracked .claude/rules/method/zz.md is red
  push @f, map { ['extra',
---
  0 and push @f, map { ['extra',
=== it compares the method keys with the current settings.json, not settings.method.json | method/scripts/method/lib/lock.pl | a changed method key is red
  my ($f, $e) = read_json(File::Spec->catfile($root, $FRAGMENT), $FRAGMENT);
---
  my ($f, $e) = read_json(File::Spec->catfile($root, $SETTINGS), $FRAGMENT);
=== a CRLF file reported as changed, not as CRLF | method/scripts/method/lib/lock.pl | a CRLF file is red, named as CRLF
    if (defined $lf && $lf eq $want) {
---
    if (0) {
=== a missing file not reported | method/scripts/method/lib/lock.pl | a missing file is red
      push @f, ['missing', 'missing: ' . Esc::line($rel)] unless -l $abs;
---
      1;
=== the method's deny entries not compared | method/scripts/method/lib/lock.pl | a removed method deny entry is red
grep { !$have{$_} } @{ $k->{deny} };
---
grep { 0 } @{ $k->{deny} };
=== the method's hooks not compared | method/scripts/method/lib/lock.pl | a changed method hook is red
    next if ($cur{$h} || 0) >= $want{$h};
---
    next;
=== the method- skills not walked | method/scripts/method/lib/lock.pl | an extra .claude/skills/method-quick/SKILL.md is red
    $walk->("$SKILLS/$_") for @e;
---
    1 for @e;
=== a link under the method's paths not named | method/scripts/method/lib/lock.pl | a link under the method's paths is red
    if (-l _) { push @p, ['link', 'a link: ' . Esc::line($rel)]; return }
---
    if (0) { }
=== hidden files under the method's paths not walked | method/scripts/method/lib/lock.pl | an extra hidden .claude/rules/method/.zz.md is red
    my @e = sort grep { $_ ne '.' && $_ ne '..' } readdir $d;
---
    my @e = sort grep { !/\A\./ } readdir $d;
=== an entry that is not a regular file named a link | method/scripts/method/lib/lock.pl | a FIFO under the method's paths is red, not named a link
    if (!-d _) { push @p, ['odd', 'not a regular file: '
---
    if (!-d _) { push @p, ['link', 'not a regular file: '
=== the hint for a file not in the lock says git checkout | method/scripts/method/lib/checks.pl | an extra file ignored by git is red too
    push @fix, 'remove each file not in method.lock' if $n{extra};
---
    push @fix, 'put each back as released (git checkout -- PATH)' if $n{extra};
=== a missing lock not reported | method/scripts/method/lib/lock.pl | no lock beside the method's files is red
    push @f, ['lock', "$LOCK is missing, so the method's files cannot be compared with the release"] unless @$lp;
---
    1;
=== method-files never run | method/scripts/method/lib/checks.pl | untouched: method-files passes
  $run->('method-files', '-', \&check_method_files) if Lock::installed('.');
---
  1;
=== method-files run where the method is not installed | method/scripts/method/lib/lock.pl | without the method installed, method-files is not run
  return @$disk || @$fp ? 1 : 0;
---
  return 1;
PLANTS-END
# where links or FIFOs cannot be made (Git Bash may make a copy instead of
# a link), the test skips those cases, so their plants are dropped, and
# said so
if ! { ln -s target "$work/link-probe" 2>/dev/null && [ -L "$work/link-probe" ]; }; then
  perl -0pi -e 's/^=== a link under the method.s paths not named \|.*?(?=^=== |\z)//msg' "$work/plants.txt"
  skip "the plant on a link under the method's paths (this system cannot make links)"
fi
if ! { mkfifo "$work/fifo-probe" 2>/dev/null && [ -p "$work/fifo-probe" ]; }; then
  perl -0pi -e 's/^=== an entry that is not a regular file named a link \|.*?(?=^=== |\z)//msg' "$work/plants.txt"
  skip "the plant on a FIFO under the method's paths (this system cannot make one)"
fi
rm -f "$work/link-probe" "$work/fifo-probe"
plant_data "$work/plants.txt" tests/method-files.test.sh only
drop_sandbox "$work" || true
echo "plants: method-files: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
