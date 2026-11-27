#!/usr/bin/env bash
# Plants for session-status's user-level audit (step 8.4; M164;
# lib/session.pl's audit_lines): each planted break turns
# tests/session-audit.test.sh red for its stated reason, in a throwaway
# copy of the repo, with TEST_ONLY keeping that case. The breaks are data:
# "=== NAME | FILE | REASON", the text OLD (in FILE exactly once), "---",
# the text NEW (tests/lib.sh, plant_data). PLANT_SHARD=K/N runs every Nth
# one from the Kth.
# shellcheck disable=SC2016 # the plants are literal perl text
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: session-status's user-level audit"
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/plants.txt" <<'PLANTS-END'
=== personal skills not read | method/scripts/method/lib/session.pl | a personal skill method-start that shadows the project's is named
  if (opendir my $d, File::Spec->catfile($dir, 'skills')) {
---
  if (0) { my $d;
=== skills/synced/ read as personal skills | method/scripts/method/lib/session.pl | personal skills of other names, a personal command method-start and skills/synced/ give no audit line
    closedir $d;
    # (method-start first
---
    closedir $d;
    push @own, (split m{/}, $_)[-1] for glob File::Spec->catfile($dir, 'skills', 'synced', '*', 'method-*');
    # (method-start first
=== a folder with no SKILL.md counted as a skill | method/scripts/method/lib/session.pl | a personal method-start folder with no SKILL.md gives no audit line
      push @own, $e if -f File::Spec->catfile($dir, 'skills', $e, 'SKILL.md');
---
      push @own, $e if -d File::Spec->catfile($dir, 'skills', $e);
=== a personal method- skill with no project counterpart named | method/scripts/method/lib/session.pl | a personal method- skill with no project counterpart is counted, not named
    my $other = grep { !$mine{$_} } @own;
---
    my $other = 0; push @shadow, grep { !$mine{$_} } @own;
=== method-start not named first | method/scripts/method/lib/session.pl | a long shadowing name is cut, method-start is named first
    my @shadow = sort { ($b eq 'method-start') <=> ($a eq 'method-start') || $a cmp $b } grep { $mine{$_} } @own;
---
    my @shadow = sort grep { $mine{$_} } @own;
=== a long name not cut | method/scripts/method/lib/session.pl | a long shadowing name is cut, method-start is named first
our $NAME_BYTES = 40;
---
our $NAME_BYTES = 400;
=== CLAUDE_CONFIG_DIR ignored | method/scripts/method/lib/session.pl | with CLAUDE_CONFIG_DIR set, the audit reads that folder
  return ($ENV{CLAUDE_CONFIG_DIR}, '$CLAUDE_CONFIG_DIR') if defined $ENV{CLAUDE_CONFIG_DIR} && $ENV{CLAUDE_CONFIG_DIR} ne '';
---
  return ($ENV{CLAUDE_CONFIG_DIR}, '$CLAUDE_CONFIG_DIR') if 0;
=== the user settings read from ~/.claude under CLAUDE_CONFIG_DIR | method/scripts/method/lib/session.pl | with CLAUDE_CONFIG_DIR set, the audit reads that folder
  my ($s) = read_settings(File::Spec->catfile($dir, 'settings.json'));
---
  my ($s) = read_settings(File::Spec->catfile($ENV{HOME}, '.claude', 'settings.json'));
=== the hook events back to two | method/scripts/method/lib/session.pl | a user UserPromptSubmit hook is named on its own line
  return $ok && @Lock::KEEP_EVENTS ? @Lock::KEEP_EVENTS : @AUDIT_EVENTS;
---
  return qw(PreToolUse PermissionRequest);
=== the fallback event list back to two | method/scripts/method/lib/session.pl | with lib/lock.pl not loading, the audit's own event list still names the UserPromptSubmit hook
our @AUDIT_EVENTS = qw(PreToolUse PermissionRequest ConfigChange SessionStart SubagentStart SubagentStop UserPromptSubmit PostToolUse PostToolUseFailure PostToolBatch);
---
our @AUDIT_EVENTS = qw(PreToolUse PermissionRequest);
=== hook entries the client drops counted | method/scripts/method/lib/session.pl | hook entries the client drops (not an object, an unknown type, a type without its field) are not counted
          ref $e eq 'HASH' && is_text($e->{type}) && $HOOK_TYPES{ $e->{type} }
            && !grep { !is_text($e->{$_}) || $e->{$_} eq '' } @{ $HOOK_TYPES{ $e->{type} } }
---
          ref $e eq 'HASH'
=== a hook type's own field not required | method/scripts/method/lib/session.pl | hook entries the client drops (not an object, an unknown type, a type without its field) are not counted
            && !grep { !is_text($e->{$_}) || $e->{$_} eq '' } @{ $HOOK_TYPES{ $e->{type} } }
---
            && 1
=== a JSON number taken for text | method/scripts/method/lib/session.pl | hook entries the client drops (not an object, an unknown type, a type without its field) are not counted
  return ($f & B::SVp_POK()) || !($f & (B::SVp_IOK() | B::SVp_NOK())) ? 1 : 0;
---
  return 1;
=== a skillOverrides value on named | method/scripts/method/lib/session.pl | skillOverrides set to on or name-only, or for another skill, gives no audit line
    my @off = sort grep { $mine{ $byte->($_) } && !(defined $ov->{$_} && !ref $ov->{$_} && $SKILL_ON{ $ov->{$_} }) } keys %$ov;
---
    my @off = sort grep { $mine{ $byte->($_) } } keys %$ov;
=== name-only read as switching a skill off | method/scripts/method/lib/session.pl | skillOverrides set to on or name-only, or for another skill, gives no audit line
our %SKILL_ON = map { ($_ => 1) } qw(on name-only);
---
our %SKILL_ON = map { ($_ => 1) } qw(on);
=== an override for a skill the project does not have named | method/scripts/method/lib/session.pl | a skillOverrides entry for a skill the project does not have gives no audit line
    my @off = sort grep { $mine{ $byte->($_) } && !(defined $ov->{$_} && !ref $ov->{$_} && $SKILL_ON{ $ov->{$_} }) } keys %$ov;
---
    my @off = sort grep { /\Amethod-/ && !(defined $ov->{$_} && !ref $ov->{$_} && $SKILL_ON{ $ov->{$_} }) } keys %$ov;
=== an override's key compared as characters with a folder's bytes | method/scripts/method/lib/session.pl | a skillOverrides key with a non-ASCII letter, for a project skill of that name, is shown as it is
    my $byte = sub { my $k = $_[0]; utf8::encode($k) if utf8::is_utf8($k); $k };
---
    my $byte = sub { $_[0] };
=== a non-ASCII key shown as fake byte escapes | method/scripts/method/lib/session.pl | a skillOverrides key with a non-ASCII letter, for a project skill of that name, is shown as it is
  utf8::encode($n) if utf8::is_utf8($n);
---
  1;
=== user claudeMdExcludes not named | method/scripts/method/lib/session.pl | user claudeMdExcludes is named on a line that says to tell the owner
  push @out, 'claudeMdExcludes' if exists $s->{claudeMdExcludes};
---
  1;
=== local claudeMdExcludes not named | method/scripts/method/lib/session.pl | local skillOverrides and claudeMdExcludes are named once
    push @what, 'claudeMdExcludes' if exists $s->{claudeMdExcludes};
---
    1;
=== the plugin's alias key not read | method/scripts/method/lib/session.pl | the plugin's other key, in any letter case after @, and the option's older name at none are named too
our $AGENTS_MD_KEY = qr/\A(?:cc-plugin-)?agents-md\@builtin\z/i;
---
our $AGENTS_MD_KEY = qr/\Aagents-md\@builtin\z/i;
=== the plugin key's letter case after @ compared exactly | method/scripts/method/lib/session.pl | the plugin's other key, in any letter case after @, and the option's older name at none are named too
our $AGENTS_MD_KEY = qr/\A(?:cc-plugin-)?agents-md\@builtin\z/i;
---
our $AGENTS_MD_KEY = qr/\A(?:cc-plugin-)?agents-md\@builtin\z/;
=== a bare plugin id read, which the client never reads | method/scripts/method/lib/session.pl | the instruction-files setting gives no audit line under a key the client does not read
our $AGENTS_MD_KEY = qr/\A(?:cc-plugin-)?agents-md\@builtin\z/i;
---
our $AGENTS_MD_KEY = qr/\A(?:cc-plugin-)?agents-md(?:\@builtin)?\z/i;
=== the instruction-files value not checked | method/scripts/method/lib/session.pl | the instruction-files setting gives no audit line under a key the client does not read
  return $r eq $KEEPS_OUT ? ('instructionFiles', $r) : ();
---
  return ('instructionFiles', $r);
=== the older option read although instructionFiles is set | method/scripts/method/lib/session.pl | the instruction-files setting gives no audit line under a key the client does not read
  if (exists $o->{projectInstructions} && defined $o->{projectInstructions} && $r eq $IF_DEFAULT) {
---
  if (exists $o->{projectInstructions} && defined $o->{projectInstructions}) {
=== the older option's values read as the new one's | method/scripts/method/lib/session.pl | the plugin's other key, in any letter case after @, and the option's older name at none are named too
our %PI_VALUES = (none => 'managed-only',
---
our %PI_VALUES = (none => 'claude-md', 'managed-only' => 'managed-only',
=== a line without "tell the owner" | method/scripts/method/lib/session.pl | user claudeMdExcludes is named on a line that says to tell the owner
my $TELL = 'tell the owner: ';
---
my $TELL = '';
=== a name's TAB left raw | method/scripts/method/lib/session.pl | a skill folder's name with a control character comes out escaped
  $n =~ s/([\x00-\x1F\x7F])/sprintf('\\x%02X', ord $1)/ge;
---
  1;
=== a cut name ending in half an escape | method/scripts/method/lib/session.pl | a name cut at 40 bytes never ends in half an escape
    $n =~ s/\\(?:x[0-9A-F]?|u(?:\{[0-9A-F]*)?)?\z//;
---
    1;
=== every name kept, so the line runs past the cut | method/scripts/method/lib/session.pl | thousands of skillOverrides entries end in time
    if ($fit->(join($sep, @in, $x) . $more->($out + $n - $i - 1))) { push @in, $x; next }
---
    if (1) { push @in, $x; next }
=== the first name that does not fit ends the list | method/scripts/method/lib/session.pl | a long item does not hide the short ones after it
    $out++;
    $first_out = 1 if $i == 0;
---
    $out += $n - $i;
    $first_out = 1 if $i == 0;
    last;
=== a first item too long left out, not cut | method/scripts/method/lib/session.pl | the user-settings line keeps what the owner does
  if ($first_out) {
---
  if (0) {
=== the user-settings line cut at its end | method/scripts/method/lib/session.pl | the user-settings line keeps what the owner does
    push @w, $user ? listed("$name adds to every session: ", \@what, "; they change it $BY_HAND", '; ')
---
    push @w, $user ? look("${TELL}$name adds to every session: " . join('; ', @what) . "; they change it $BY_HAND")
=== the plugin item's long wording back | method/scripts/method/lib/session.pl | the user-settings line names availableModels, a plugin and an effort cap together
    push @what, "$n enabled plugin" . ($n == 1 ? '' : 's') . ' (hooks not read)' if $n;
---
    push @what, "$n enabled plugin" . ($n == 1 ? '' : 's') . ' (their hooks were not read)' if $n;
=== the audit's lines after the others | method/scripts/method/lib/session.pl | with every item at once (~/.claude)
    push @lines, audit_lines($project);
    in_time();
    push @lines, status_lines($top) unless ($ENV{METHOD_NESTED} // '') eq '1';
    in_time();
    push @lines, warnings_for($in, $top, $in_err);
    in_time();
    push @lines, receipt_lines($top, $project);
---
    push @lines, status_lines($top) unless ($ENV{METHOD_NESTED} // '') eq '1';
    in_time();
    push @lines, warnings_for($in, $top, $in_err);
    in_time();
    push @lines, receipt_lines($top, $project);
    in_time();
    push @lines, audit_lines($project);
=== the user hooks named on the user-settings line as well | method/scripts/method/lib/session.pl | a user PreToolUse hook is named once, on the audit's line, not again on the user-settings line
  if (!$user && ref $s->{hooks} eq 'HASH') {
---
  if (ref $s->{hooks} eq 'HASH') {
=== a cut name ending in half of a \u{...} escape | method/scripts/method/lib/session.pl | a name cut at 40 bytes never ends in half an escape
    $n =~ s/\\(?:x[0-9A-F]?|u(?:\{[0-9A-F]*)?)?\z//;
---
    $n =~ s/\\(?:x[0-9A-F]?)?\z//;
=== only the last of the plugin's two keys used, not both merged | method/scripts/method/lib/session.pl | the plugin's two keys are merged as the client merges them
      %merged = (%merged, %$o);
---
      %merged = %$o;
=== the plugin's two keys merged in the other order, the cc-plugin- key first | method/scripts/method/lib/session.pl | the plugin's two keys are merged as the client merges them
    for my $key (sort { ($a =~ /\Acc-plugin-/i ? 1 : 0) <=> ($b =~ /\Acc-plugin-/i ? 1 : 0) || $a cmp $b } keys %{ $s->{pluginConfigs} }) {
---
    for my $key (sort { ($b =~ /\Acc-plugin-/i ? 1 : 0) <=> ($a =~ /\Acc-plugin-/i ? 1 : 0) || $a cmp $b } keys %{ $s->{pluginConfigs} }) {
=== an integer too long for perl taken for text | method/scripts/method/lib/session.pl | a hook command that is an integer too long for perl is not text
    my ($b, $be) = Json::decode($text);
---
    my ($b, $be) = Json::decode($text, 'plain');
=== a JSON string of digits taken for a number | method/scripts/method/lib/session.pl | a hook command that is a JSON string of digits is text
  my $f = B::svref_2object(\$v)->FLAGS;
---
  my $f = B::svref_2object(\$v)->FLAGS;
  return 0 if $v =~ /\A-?[0-9]{19,}\z/;
=== a user settings file that cannot be read named without telling the owner | method/scripts/method/lib/session.pl | a user settings file that cannot be read is named on a line that says to tell the owner
    if (defined $e) { push @w, look($user ? "${TELL}$name $e, so what it changes is not known; they fix it $BY_HAND" : "$name $e, so what it changes is not known"); next }
---
    if (defined $e) { push @w, look("$name $e, so what it changes is not known"); next }
PLANTS-END
plant_data "$work/plants.txt" tests/session-audit.test.sh only
drop_sandbox "$work" || true
echo "plants: session-status's user-level audit: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
