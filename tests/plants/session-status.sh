#!/usr/bin/env bash
# Plants for session-status (step 5.4's last two repair loops and step 5's
# final review, kept here since that review; since step 5b.2 its line on
# the gates' receipts too): each planted break turns
# tests/session-status.test.sh red for its stated reason, in a throwaway
# copy of the repo. The breaks are data: "=== NAME | FILE | REASON", the
# text OLD (in FILE exactly once), "---", the text NEW (tests/lib.sh,
# plant_data). PLANT_SHARD=K/N runs every Nth one from the Kth.
# shellcheck disable=SC2016 # the plants are literal perl text
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: session-status"
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/plants.txt" <<'PLANTS-END'
=== RL3 the deadline not checked after a settings read | method/scripts/method/lib/session.pl | a deadline caught inside a settings read still ends the perl part, and says so
  in_time();
  return (undef, 'is not JSON')
---
  return (undef, 'is not JSON')
=== RL3 the alarm sets no flag | method/scripts/method/lib/session.pl | a deadline caught inside a settings read still ends the perl part, and says so
local $SIG{ALRM} = sub { $OUT = 1; die "out of time\n" };
---
local $SIG{ALRM} = sub { die "out of time\n" };
=== RL3 a list read whatever kind of file it is | method/scripts/method/lib/session.pl | a list that is not a regular file, or is over 1 MB, is a LOOK and is not read
if (!-f $path) { push @w, look("$name is not a regular file, so what it adds is not known"); next }
---
if (0) { }
=== RL3 a list read whatever its size | method/scripts/method/lib/session.pl | a list that is not a regular file, or is over 1 MB, is a LOOK and is not read
if (-s _ > $SETTINGS_MAX) { push @w, look("$name is over 1 MB, so what it adds is not known"); next }
---
if (0) { }
=== RL3 gh and MCP lines not counted | method/scripts/method/lib/session.pl | gh shapes and MCP tool lines the owner added are counted too
['gh-shapes.txt', 'gh shape', 'G4'], ['mcp-tools.txt', 'MCP tool line', 'G4']
---

=== RL2 effortLevel per model not read | method/scripts/method/lib/session.pl | an effortLevel below xhigh for one model in local settings is a LOOK
push @what, "an effortLevel below xhigh for $e model"
---
0 and push @what, "an effortLevel below xhigh for $e model"
=== RL2 a user availableModels not reported | method/scripts/method/lib/session.pl | availableModels in user settings is a LOOK, as lists add up across settings files
push @what, 'availableModels (lists add up across settings files)' if $user
---
push @what, 'availableModels (lists add up across settings files)' if 0
=== RL2 settings read whatever their size | method/scripts/method/lib/session.pl | a settings file over 1 MB is named, not read, so reading it cannot take the hook past its time
return (undef, 'is over 1 MB') if -s _ > $SETTINGS_MAX;
---

=== RL2 no deadline | method/scripts/method/lib/session.pl | the perl part ends at its deadline
alarm $DEADLINE;
---
alarm 0;
=== RL2 a nested run skips the settings checks too | method/scripts/method/lib/session.pl | a nested run still checks the settings, so METHOD_NESTED set in them is named
push @lines, warnings_for($in, $top, $in_err);
---
push @lines, warnings_for($in, $top, $in_err) unless ($ENV{METHOD_NESTED} // '') eq '1';
=== RL2 a byte-order mark not stripped | method/scripts/method/lib/session.pl | a settings file that starts with a byte-order mark is read, as Claude Code reads it
$text =~ s/\A\xEF\xBB\xBF//;
---

=== 5b.2 the receipts line not added | method/scripts/method/lib/session.pl | gate receipts for the files at HEAD that do not say VALID are named in one LOOK line, by word
    push @lines, receipt_lines($top, $project);
---

=== 5b.2 receipts of every tree counted | method/scripts/method/lib/receipt-read.pl | gate receipts for the files at HEAD that do not say VALID are named in one LOOK line, by word
  $n{ $_->{state} }++ for grep { $_->{state} ne $w->{good} } query($store, $tree);
---
  $n{ $_->{state} }++ for grep { $_->{state} ne $w->{good} } query($store);
=== the snapshot left outside the deadline | method/scripts/method/lib/session.pl | a snapshot that hangs is cut off at the deadline
    eval { require File::Spec->catfile($lib, 'watch.pl'); Watch::snapshot($in, $project) };
---
    { local $SIG{ALRM} = 'IGNORE'; eval { require File::Spec->catfile($lib, 'watch.pl'); Watch::snapshot($in, $project) }; }

PLANTS-END
plant_data "$work/plants.txt" tests/session-status.test.sh
drop_sandbox "$work" || true
echo "plants: session-status: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
