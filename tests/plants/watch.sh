#!/usr/bin/env bash
# Plants for what could change the session's hooks once it has started
# (step 5.9, G16 and G17, lib/watch.pl): each G16 key dropped, the snapshot
# taken again at a compaction, the judging with no snapshot and of a file
# it cannot read removed, the one-time message's parts removed, and G17's
# frontmatter check and each place it looks removed, turn
# tests/guard-watch.test.sh red for the stated reason. Each runs in a
# throwaway copy of the repo.
# shellcheck disable=SC2016 # the plants are literal perl text
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: settings changes and skill hooks"
# plant NAME REASON FILE OLD NEW: in a fresh copy, the text OLD in
# method/scripts/method/lib/FILE (it must be there exactly once) becomes
# NEW; tests/guard-watch.test.sh must then fail with REASON
plant() {
  name=$1
  reason=$2
  sb=$(make_sandbox) || abort_sandbox
  if ! (cd "$sb" && OLD="$4" NEW="$5" perl -0pi -e 'my ($o, $n) = ($ENV{OLD}, $ENV{NEW}); my $i = index($_, $o); die "missing\n" if $i < 0; die "twice\n" if index($_, $o, $i + 1) >= 0; substr($_, $i, length $o) = $n' "method/scripts/method/lib/$3"); then
    fail "$name: the plant did not apply, so the check result would mean nothing"
  else
    got=$(cd "$sb" && bash tests/guard-watch.test.sh 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then
      fail "$name: the test stayed green" "$(printf '%s\n' "$got" | tail -2)"
    elif ! printf '%s\n' "$got" | grep -F -q -- "FAIL  $reason"; then
      fail "$name: went red, but not for the stated reason ('$reason')" "$(printf '%s\n' "$got" | grep FAIL | head -3)"
    else
      pass "$name"
    fi
  fi
  drop_sandbox "$sb" || true
}

# --- G16 ---
plant "env dropped from the keys compared" "any change to an env value is refused" watch.pl 'for my $k (qw(env hooks disableAllHooks enabledPlugins), @RUNS) {' 'for my $k (qw(hooks disableAllHooks enabledPlugins), @RUNS) {'
plant "hooks dropped from the keys compared" "hooks added to the user settings are refused" watch.pl 'for my $k (qw(env hooks disableAllHooks enabledPlugins), @RUNS) {' 'for my $k (qw(env disableAllHooks enabledPlugins), @RUNS) {'
plant "disableAllHooks dropped from the keys compared" "disableAllHooks in the local settings is refused" watch.pl 'for my $k (qw(env hooks disableAllHooks enabledPlugins), @RUNS) {' 'for my $k (qw(env hooks enabledPlugins), @RUNS) {'
plant "enabledPlugins dropped from the keys compared" "a plugin enabled is refused" watch.pl 'for my $k (qw(env hooks disableAllHooks enabledPlugins), @RUNS) {' 'for my $k (qw(env hooks disableAllHooks), @RUNS) {'
plant "the settings that run a program not compared" "a statusLine added to the user settings is refused" watch.pl 'for my $k (qw(env hooks disableAllHooks enabledPlugins), @RUNS) {' 'for my $k (qw(env hooks disableAllHooks enabledPlugins)) {'
plant "processWrapper not among the settings that run a program" "a processWrapper added to the user settings is refused" watch.pl ' proxyAuthHelper subagentStatusLine processWrapper);' ' proxyAuthHelper subagentStatusLine);'
plant "a removed deny entry not seen" "a permissions.deny entry removed is refused" watch.pl "push @why, 'a permissions.deny entry removed' if" "push @why, 'a permissions.deny entry removed' if 0 &&"
plant "skill shell lines turned on not seen" "skill shell lines turned on in the local settings is refused" watch.pl "push @why, 'disableSkillShellExecution turned off' if is_false(\$now->{disableSkillShellExecution}) && !is_false(\$snap->{disableSkillShellExecution});" ''
plant "the project's settings let change" "any change to the project's settings is refused" watch.pl "if \$src eq 'project_settings';" "if 0;"
plant "the snapshot taken again at a compaction" "a compact keeps the snapshot" watch.pl "return unless \$src eq 'startup' || (\$src eq 'resume' && !-e \$path);" "return unless \$src ne '';"
plant "no judging without a snapshot" "with no snapshot, a user settings file that holds env is refused" watch.pl 'push @why, grep { exists $now->{$_} } qw(env hooks enabledPlugins);' ''
plant "a file it cannot read let through" "a local settings file that is not JSON is refused" watch.pl 'so what it changes cannot be told; $later") if defined $e;' 'so what it changes cannot be told; $later") if 0;'
plant "no note of a refused change" "the next call brings a message" guard.pl 'Watch::note_refused($project);' ''
plant "the message kept after it is shown" "one message only" watch.pl '  unlink $p;
  return "a settings change' '  return "a settings change'
# --- G17 ---
plant "the frontmatter check removed" "a project skill that declares hooks is refused" watch.pl 'return $fm =~ /^["'"'"']?hooks["'"'"']?[ \t]*:/m ? 1 : 0;' 'return 0;'
plant "plugins not looked in" "a plugin's skill that declares hooks is refused" watch.pl 'my @plugins = plugin_roots($cfg);' 'my @plugins = ();'
plant "commands not looked in by their short name" "a plugin's command that declares hooks is refused" watch.pl "push @f, File::Spec->catfile(\$r, 'commands', \"\$n.md\");" ''
plant "agents not found by their frontmatter name" "an agent, found by its frontmatter name, that declares hooks is refused" watch.pl 'my $a = agent_name($_); $a eq $short || $a eq $name' '0'
plant "a definition it cannot read let through" "a skill whose definition is not a regular file is refused" watch.pl 'so whether it declares hooks cannot be told; it is refused; tell the owner") if defined $e;' 'so whether it declares hooks cannot be told; it is refused; tell the owner") if 0;'
plant "a name with a path let through" "a skill named as a path is refused" watch.pl 'if ($name =~ m{[/\\\0]|\.\.}) {' 'if (0) {'
plant "Task not judged" "the same agent through Task is refused" guard.pl 'if ($tool =~ /\A(?:Skill|Agent|Task)\z/) {
    require' 'if ($tool =~ /\A(?:Skill|Agent)\z/) {
    require'

echo "plants: settings changes and skill hooks: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
