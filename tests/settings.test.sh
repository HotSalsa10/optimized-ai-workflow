#!/usr/bin/env bash
# Tests for method/settings.fragment.json, the settings every method
# project gets (step 5.3; docs/plans/step5.md, section 5; M076, M104,
# M138), and for every committed settings file of this repo. Static and
# fast: it reads the files, it runs no client (the harness shows the
# client loading the fragment).
#
# Some values of the wrong JSON type make Claude Code skip the whole
# settings file, hooks included (measured: tests/harness.test.sh,
# "rejected-shape", with the model allowlist written as a string; also
# seen by the review with permissions as a string), so every value's type
# is checked, not only its text, and a key the plan does not name is
# refused, permissions too until 5.8 checks its deny list.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: settings fragment"
root=$(repo_root)
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/check.pl" <<'PERL'
use strict;
use warnings;
my $root = shift;
require "$root/method/scripts/method/lib/json.pl";
binmode STDOUT, ':utf8';
my @out;
sub ok   { push @out, "PASS\t$_[0]" }
sub bad  { push @out, "FAIL\t$_[0]\t$_[1]" }
sub skip { push @out, "SKIP\t$_[0]" }
sub check { my ($name, $why) = @_; defined $why ? bad($name, $why) : ok($name) }
sub read_json {
  my ($path) = @_;
  open my $f, '<:raw', $path or return (undef, "cannot read $path");
  my $t = do { local $/; <$f> };
  my ($d, $e) = Json::decode($t, 'plain');
  return (undef, "$path: $e") if defined $e;
  return (undef, "$path is not a JSON object") unless ref $d eq 'HASH';
  return ($d, undef);
}
sub is_bool { ref $_[0] && (ref $_[0] eq 'JSON::PP::Boolean') }

my $frag = 'method/settings.fragment.json';
my ($f, $err) = read_json($frag);
if (!$f) { bad("the fragment is one JSON object", $err); print "$_\n" for @out; exit 0 }
ok("the fragment is one JSON object");

# the floor
my $floor;
if (open my $r, '<', 'method/scripts/method/REQUIRES') { while (<$r>) { $floor = $1 if /^claude_code_min=(\S+)$/ } }

# every key, its value and its JSON type (section 5)
my %want = (
  '$schema' => [str => 'https://json.schemastore.org/claude-code-settings.json'],
  model => [str => 'claude-opus-5-5'],
  availableModels => [list => ['claude-opus-5-5']],
  enforceAvailableModels => [bool => 1],
  effortLevel => [str => 'xhigh'],
  attribution => [obj => { commit => [str => ''], pr => [str => ''], sessionUrl => [bool => 0] }],
  autoMemoryEnabled => [bool => 0],
  disableSkillShellExecution => [bool => 1],
  skillOverrides => [obj => { 'code-review' => [str => 'user-invocable-only'] }],
  disableAllHooks => [bool => 0],
  minimumVersion => [str => $floor],
  env => [obj => { CLAUDE_CODE_DISABLE_ADVISOR_TOOL => [str => '1'], CLAUDE_CODE_USE_POWERSHELL_TOOL => [str => '0'] }],
);
# hooks are checked below (from 5.4); permissions come with their deny
# list (5.8), and until then any permissions key is refused, as one of the
# wrong shape makes the client skip the whole file
my %later = (hooks => 'hooks (from 5.4)');
sub same {
  my ($spec, $v, $at) = @_;
  my ($type, $w) = @$spec;
  if ($type eq 'str') {
    return "$at is not a string" if !defined $v || ref $v || Json::encode($v) !~ /\A"/;
    return "$at is \"$v\", not \"" . ($w // '(the floor in REQUIRES, missing)') . '"' unless defined $w && $v eq $w;
  } elsif ($type eq 'bool') {
    return "$at is not true or false (a JSON boolean)" unless is_bool($v);
    return "$at is " . ($v ? 'true' : 'false') . ', not ' . ($w ? 'true' : 'false') unless !!$v == !!$w;
  } elsif ($type eq 'list') {
    return "$at is not a list" unless ref $v eq 'ARRAY';
    return "$at is not exactly " . Json::encode($w) unless Json::encode($v) eq Json::encode($w);
  } elsif ($type eq 'obj') {
    return "$at is not an object" unless ref $v eq 'HASH';
    for my $k (sort keys %$w) {
      return "$at.$k is missing" unless exists $v->{$k};
      my $e = same($w->{$k}, $v->{$k}, "$at.$k");
      return $e if defined $e;
    }
    my @extra = grep { !exists $w->{$_} } sort keys %$v;
    return "$at has keys the plan does not set: @extra" if @extra;
  }
  return undef;
}
for my $k (sort keys %want) {
  if (!exists $f->{$k}) { bad("the fragment sets $k", "$k is missing"); next }
  check("the fragment sets $k as the plan says", same($want{$k}, $f->{$k}, $k));
}
my @unknown = grep { !$want{$_} && !$later{$_} } sort keys %$f;
check("the fragment sets no key the plan does not name", @unknown ? "unknown keys: @unknown" : undef);

# never set, in any committed settings file (section 5)
# (in any letter case: a case-folding file system opens .Claude/Settings.json
# as .claude/settings.json)
my @tracked = split /\0/, `git ls-files -z`;
my @files = grep { m{(?:^|/)\.claude/settings(?:\.local)?\.json\z}i || m{(?:^|/)settings\.fragment\.json\z} } @tracked;
push @files, $frag unless grep { $_ eq $frag } @files;
# (this repo's own settings are always read, so their check cannot vanish)
push @files, '.claude/settings.json' if -e '.claude/settings.json' && !grep { lc $_ eq '.claude/settings.json' } @files;
my @local = grep { m{(?:^|/)\.claude/settings\.local\.json\z}i } @tracked;
check("no settings.local.json is committed (it belongs to one machine)", @local ? "committed: @local" : undef);
# a committed link named .claude, or one inside a .claude folder: the
# client follows it to settings no check here reads
my @links = map { /\A120000 \S+ \S+\t(.*)\z/s ? $1 : () } split /\0/, `git ls-files -s -z`;
my @claude_links = grep { m{(?:^|/)\.claude(?:/|\z)}i } @links;
check("no committed link is named .claude or lies in a .claude folder", @claude_links ? "committed links: @claude_links" : undef);
for my $file (@files) {
  my ($s, $e) = read_json($file);
  if (!$s) { bad("$file is one JSON object", $e); next }
  my @found;
  my $env = ref $s->{env} eq 'HASH' ? $s->{env} : {};
  # (env names in any letter case: Windows reads them so)
  my %env_uc = map { (uc($_) => $_) } keys %$env;
  for my $v (qw(CLAUDE_CODE_EFFORT_LEVEL CLAUDE_CODE_SUBPROCESS_ENV_SCRUB CLAUDE_CODE_REMOTE)) { push @found, "env.$env_uc{$v}" if exists $env_uc{$v} }
  for my $k (qw(autoContinueAtUsageLimit enableWorkflows disableWorkflows)) { push @found, $k if exists $s->{$k} }
  my $mode = ref $s->{permissions} eq 'HASH' ? $s->{permissions}{defaultMode} : undef;
  push @found, "permissions.defaultMode $mode" if defined $mode && !ref $mode && ($mode eq 'auto' || $mode eq 'bypassPermissions');
  check("$file sets nothing on the never-set list", @found ? "it sets @found" : undef);
}

# this repo's own settings agree with the fragment on the shared keys (D3)
my ($mine, $me) = read_json('.claude/settings.json');
if ($mine) {
  # every key both set (the hooks are the method's to run in a project, not
  # here, D3), each env variable both set, and the keys this repo must set
  my @differ;
  for my $k (qw(model availableModels enforceAvailableModels effortLevel attribution)) {
    push @differ, $k unless exists $mine->{$k};
  }
  for my $k (sort grep { exists $f->{$_} && $_ ne '$schema' && $_ ne 'env' && $_ ne 'hooks' } keys %$mine) {
    push @differ, $k unless Json::encode($mine->{$k}) eq Json::encode($f->{$k});
  }
  my %me = ref $mine->{env} eq 'HASH' ? %{ $mine->{env} } : ();
  my %fe = ref $f->{env} eq 'HASH' ? %{ $f->{env} } : ();
  push @differ, 'env.CLAUDE_CODE_DISABLE_ADVISOR_TOOL' unless exists $me{CLAUDE_CODE_DISABLE_ADVISOR_TOOL};
  for my $v (sort grep { exists $fe{$_} } keys %me) {
    push @differ, "env.$v" unless Json::encode($me{$v}) eq Json::encode($fe{$v});
  }
  check("this repo's .claude/settings.json agrees with the fragment on the keys they share", @differ ? "they differ on: @differ" : undef);
} else {
  bad("this repo's .claude/settings.json agrees with the fragment on the keys they share", $me);
}

# the hook entries (section 6.4): three scripts, one command form
my $hooks = $f->{hooks};
my @scripts = qw(session-status guard gate-receipt);
my %script = map { $_ => 1 } @scripts;
my %no_onfailure = map { $_ => 1 } qw(SessionStart SubagentStart SubagentStop Stop TaskCompleted TeammateIdle);
if (!defined $hooks) {
  bad("the fragment registers the method's hooks", "it has no hooks key");
} elsif (ref $hooks ne 'HASH') {
  bad("the fragment's hooks are an object of events", "hooks is not an object");
} else {
  my (@form, @onfail, @missing_block);
  for my $event (sort keys %$hooks) {
    my $groups = $hooks->{$event};
    if (ref $groups ne 'ARRAY') { push @form, "$event is not a list"; next }
    for my $g (@$groups) {
      my $list = ref $g eq 'HASH' ? $g->{hooks} : undef;
      if (ref $list ne 'ARRAY') { push @form, "$event has an entry with no hooks list"; next }
      for my $h (@$list) {
        my $cmd = ref $h eq 'HASH' ? $h->{command} : undef;
        my ($name) = defined $cmd && !ref $cmd ? $cmd =~ m{\ABASH_ENV= ENV= bash "\$CLAUDE_PROJECT_DIR/\.claude/hooks/method/([a-z-]+)\.sh"\z} : ();
        if (!(ref $h eq 'HASH' && ($h->{type} // '') eq 'command') || !defined $name || !$script{$name}) {
          push @form, "$event: " . (defined $cmd && !ref $cmd ? $cmd : '(no command)');
          next;
        }
        if ($no_onfailure{$event}) {
          push @onfail, $event if exists $h->{onFailure};
        } elsif ($name eq 'guard' && ($event eq 'PreToolUse' || $event eq 'ConfigChange')) {
          push @missing_block, $event unless ($h->{onFailure} // '') eq 'block';
        }
      }
    }
  }
  check("every hook command is one of the three method scripts, as BASH_ENV= ENV= bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/method/NAME.sh\"", @form ? join('; ', @form) : undef);
  check("no onFailure where it has no effect (RISKS #16)", @onfail ? "onFailure on @onfail" : undef);
  check("the guard's PreToolUse and ConfigChange entries block on failure", @missing_block ? "no onFailure \"block\" on @missing_block" : undef);
  # the entries the plan registers so far (section 6.4): EVENT, MATCHER
  # (undef: none, every source), SCRIPT, TIMEOUT (seconds)
  my @registered = (['SessionStart', undef, 'session-status', 30],
    ['PreToolUse', 'Bash|PowerShell|Monitor|Edit|Write|MultiEdit|NotebookEdit|ExitWorktree|SendMessage|Skill|Agent|Task', 'guard', 30],
    ['PreToolUse', '^mcp__', 'guard', 30]);
  for my $r (@registered) {
    my ($event, $matcher, $name, $timeout) = @$r;
    my $want = qq{BASH_ENV= ENV= bash "\$CLAUDE_PROJECT_DIR/.claude/hooks/method/$name.sh"};
    my @hit = grep {
      my $g = $_;
      ref $g eq 'HASH' && (defined $matcher ? defined $g->{matcher} && $g->{matcher} eq $matcher : !exists $g->{matcher})
        && ref $g->{hooks} eq 'ARRAY' && grep { ref $_ eq 'HASH' && ($_->{command} // '') eq $want } @{ $g->{hooks} }
    } @{ ref $hooks->{$event} eq 'ARRAY' ? $hooks->{$event} : [] };
    check("the fragment runs $name.sh on $event" . (defined $matcher ? " for $matcher" : ', for every source (no matcher)'),
      @hit == 1 ? undef : (@hit ? "it is registered " . scalar(@hit) . " times" : 'it is not registered so'));
    my @t = map { my $g = $_; map { $_->{'timeout'} } grep { ref $_ eq 'HASH' && ($_->{command} // '') eq $want } @{ $g->{hooks} } } @hit;
    check("$name.sh on $event" . (defined $matcher ? " for $matcher" : "") . " has a $timeout s time limit, written as a number", (@t && !grep { !defined $_ || ref $_ || Json::encode($_) ne $timeout } @t) ? undef : 'its timeout is ' . join(', ', map { defined $_ ? Json::encode($_) : 'not set' } @t));
  }
}
# the hooks folder holds only the three scripts' .sh files
my $hd = 'method/.claude/hooks/method';
if (-d $hd) {
  opendir my $d, $hd or die;
  my @sh = grep { /\.sh\z/ } readdir $d;
  my @other = grep { my $n = $_; $n =~ s/\.sh\z//; !$script{$n} } sort @sh;
  check("the hooks folder holds no .sh but the three scripts", @other ? "also @other" : undef);
} else {
  bad("the hooks folder holds no .sh but the three scripts", "$hd is missing");
}
print "$_\n" for @out;
PERL
out=$(cd "$root" && perl "$work/check.pl" "$root" 2>&1)
code=$?
drop_sandbox "$work" || true
if [ "$code" -ne 0 ]; then
  fail "the settings checks ran" "$out"
fi
while IFS='	' read -r kind name why; do
  case "$kind" in
    PASS) pass "$name" ;;
    FAIL) fail "$name" "$why" ;;
    SKIP) skip "$name" ;;
    *) [ -n "$kind" ] && fail "the settings checks printed something unexpected" "$kind $name $why" ;;
  esac
done <<EOF
$out
EOF

echo "tests: settings fragment: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
