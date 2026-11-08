#!/usr/bin/env perl
# The session-status hook's perl part (step 5.4; docs/plans/step5.md,
# section 6.1). .claude/hooks/method/session-status.sh prints METHOD-ACTIVE
# and then runs this, with the hook's JSON input on standard input. It
# prints at most 9 more lines and, with the METHOD-ACTIVE line, at most
# 1,200 bytes (an R12 budget), as plain text that Claude Code adds to
# Claude's context:
# - status.sh --quick's summary line and its LOOK lines, within 5 s;
# - a LOOK line for each setting that weakens the method in this session:
#   the advisor not off; auto memory switched on by its variable; the
#   session's model not claude-opus-5-5; the PowerShell tool not off on
#   Windows; input that cannot be read; in the project's local settings, a
#   key the method sets, disableAllHooks, skill shell lines on; in local
#   and user settings ($CLAUDE_CONFIG_DIR's when that is set), an env
#   variable, a PreToolUse or PermissionRequest hook (the method's are in
#   the project's settings only), an enabled plugin, an effort cap below
#   xhigh (also per model); a settings file that is not a regular file, is
#   over 4 MB or is not JSON; git shapes added in
#   .claude/method-local/git-shapes.txt (step 5.6), counted. Names only,
#   never a settings value: a model id only in the shape Anthropic's ids
#   have, the effort level by name.
# Over the caps, the last line says how many more and to run status.sh.
# Every line is one clean line (Hook::clean); anything that goes wrong
# becomes a LOOK line, never a crash that hides the rest.
package Session;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;
use Time::HiRes ();

my $lib = dirname(File::Spec->rel2abs(__FILE__));
require File::Spec->catfile($lib, 'hook.pl');
# status.pl only runs status; when it cannot load, the settings warnings
# still come (status_lines says why it gave none)
my $STATUS_LOADED = eval { require File::Spec->catfile($lib, 'status.pl'); 1 } ? 1 : 0;

our $MAX_LINES = 9;          # METHOD-ACTIVE is the tenth
our $MAX_BYTES = 1200 - 40;  # the METHOD-ACTIVE line takes at most 40
our $LINE_BYTES = 240;
our $STATUS_SECONDS = 5;

# the keys the method's settings set (method/settings.fragment.json)
my @FRAGMENT_KEYS = qw(model availableModels enforceAvailableModels effortLevel attribution autoMemoryEnabled
  disableSkillShellExecution skillOverrides minimumVersion);
# the env variables the fragment sets: the project's value wins over a user
# setting of the same name
my %FRAGMENT_ENV = map { $_ => 1 } qw(CLAUDE_CODE_DISABLE_ADVISOR_TOOL CLAUDE_CODE_USE_POWERSHELL_TOOL);
our $SETTINGS_MAX = 4 * 1024 * 1024;

sub look { return "session-status: LOOK - $_[0]" }

# a settings file's data, or (undef, why it cannot be told what it sets);
# only a regular file is opened (a FIFO would hold the hook past its time)
sub read_settings {
  my ($path) = @_;
  return (undef, undef) unless -e $path || -l $path;
  return (undef, 'is not a regular file') unless -f $path;
  return (undef, 'is over 4 MB') if -s _ > $SETTINGS_MAX;
  open my $f, '<:raw', $path or return (undef, "cannot be read");
  my $text = do { local $/; <$f> };
  return (undef, 'is not a regular file') unless -f $f;
  my ($d, $e) = Json::decode($text, 'plain');
  return (undef, 'is not JSON') if defined $e || ref $d ne 'HASH';
  return ($d, undef);
}

# env names as they are, when plain; the others counted
sub env_names {
  my @k = sort @_;
  my @plain = grep { /\A[A-Za-z_][A-Za-z0-9_%]{0,199}\z/ } @k;
  my $other = @k - @plain;
  return join(', ', @plain) . ($other ? ($other == @k ? '' : ' and ') . "$other other name" . ($other == 1 ? '' : 's') : '');
}

# an effort cap below xhigh: maxEffortLevel, and per model in modelSettings
sub effort_caps {
  my ($s) = @_;
  my @what;
  my $low = sub { defined $_[0] && !ref $_[0] && $_[0] =~ /\A(?:low|medium|high)\z/ };
  push @what, "maxEffortLevel $s->{maxEffortLevel}, below xhigh" if $low->($s->{maxEffortLevel});
  if (ref $s->{modelSettings} eq 'HASH') {
    my $n = grep { ref $s->{modelSettings}{$_} eq 'HASH' && $low->($s->{modelSettings}{$_}{maxEffortLevel}) } keys %{ $s->{modelSettings} };
    push @what, "a maxEffortLevel below xhigh for $n model" . ($n == 1 ? '' : 's') . ' (modelSettings)' if $n;
  }
  return @what;
}

# what a settings file sets that weakens or overrides the method. Local
# settings rank above the project's, so every key the method sets counts;
# in user settings the project wins for those, so only what adds to a
# session counts: env variables, hooks, plugins and effort caps. The method
# registers its hooks in the project's settings only, so every PreToolUse
# or PermissionRequest hook here is another's (a copy of the method's
# would replace the project's, with its own fields)
sub weakens {
  my ($s, $user) = @_;
  my @what;
  if (!$user) {
    push @what, grep { exists $s->{$_} } @FRAGMENT_KEYS;
    push @what, 'disableAllHooks' if $s->{disableAllHooks};
    push @what, 'disableSkillShellExecution false' if exists $s->{disableSkillShellExecution} && !$s->{disableSkillShellExecution};
  }
  if (ref $s->{env} eq 'HASH') {
    my @k = grep { !$user || !$FRAGMENT_ENV{$_} } keys %{ $s->{env} };
    push @what, 'env ' . env_names(@k) if @k;
  }
  if (ref $s->{hooks} eq 'HASH') {
    my $n = 0;
    for my $event (qw(PreToolUse PermissionRequest)) {
      next unless ref $s->{hooks}{$event} eq 'ARRAY';
      for my $g (@{ $s->{hooks}{$event} }) {
        next unless ref $g eq 'HASH' && ref $g->{hooks} eq 'ARRAY';
        $n += @{ $g->{hooks} };
      }
    }
    push @what, "$n PreToolUse or PermissionRequest hook" . ($n == 1 ? '' : 's') . " (the method's are in the project's settings only)" if $n;
  }
  if (ref $s->{enabledPlugins} eq 'HASH') {
    my $n = grep { $s->{enabledPlugins}{$_} } keys %{ $s->{enabledPlugins} };
    push @what, "$n enabled plugin" . ($n == 1 ? '' : 's') . ' (their hooks were not read)' if $n;
  }
  push @what, effort_caps($s);
  return @what;
}

sub warnings_for {
  my ($in, $top, $in_err) = @_;
  my @w;
  push @w, look("the hook's input could not be read ($in_err), so the session's model was not checked") if defined $in_err;
  push @w, look("the advisor is not switched off (CLAUDE_CODE_DISABLE_ADVISOR_TOOL is not 1; DECISIONS A5)")
    unless ($ENV{CLAUDE_CODE_DISABLE_ADVISOR_TOOL} // '') eq '1';
  push @w, look('auto memory is switched on by CLAUDE_CODE_DISABLE_AUTO_MEMORY=0 (M104)')
    if defined $ENV{CLAUDE_CODE_DISABLE_AUTO_MEMORY} && $ENV{CLAUDE_CODE_DISABLE_AUTO_MEMORY} eq '0';
  my $model = ref $in eq 'HASH' ? $in->{model} : undef;
  # (a model id is shown only in the shape Anthropic's ids have)
  push @w, look('this session runs ' . ($model =~ /\Aclaude-[a-z0-9.-]{1,60}\z/ ? $model : 'a model') . ', not claude-opus-5-5 (DECISIONS A2)')
    if defined $model && !ref $model && $model ne '' && $model ne 'claude-opus-5-5';
  push @w, look('the PowerShell tool is not switched off (CLAUDE_CODE_USE_POWERSHELL_TOOL is not 0); the guard refuses it')
    if $^O =~ /\A(?:msys|MSWin32|cygwin)\z/ && ($ENV{CLAUDE_CODE_USE_POWERSHELL_TOOL} // '') ne '0';
  # local settings: the project's own, which Claude Code reads (not the
  # folder Claude moved into); user settings: where Claude Code reads them
  my $project = defined $ENV{CLAUDE_PROJECT_DIR} && -d $ENV{CLAUDE_PROJECT_DIR} ? $ENV{CLAUDE_PROJECT_DIR} : $top;
  my @files = (['.claude/settings.local.json', File::Spec->catfile($project, '.claude', 'settings.local.json'), 0]);
  if (defined $ENV{CLAUDE_CONFIG_DIR} && $ENV{CLAUDE_CONFIG_DIR} ne '') {
    push @files, ['$CLAUDE_CONFIG_DIR/settings.json', File::Spec->catfile($ENV{CLAUDE_CONFIG_DIR}, 'settings.json'), 1];
  } elsif (defined $ENV{HOME} && $ENV{HOME} ne '') {
    push @files, ['~/.claude/settings.json', File::Spec->catfile($ENV{HOME}, '.claude', 'settings.json'), 1];
  }
  for my $f (@files) {
    my ($name, $path, $user) = @$f;
    my ($s, $e) = read_settings($path);
    if (defined $e) { push @w, look("$name $e, so what it changes is not known"); next }
    next unless $s;
    my @what = weakens($s, $user);
    next unless @what;
    push @w, look($user ? "$name adds to every session: " . join('; ', @what) : "$name sets " . join('; ', @what) . "; it ranks above the method's settings");
  }
  # the project's own git shapes: the guard lets each through (G3)
  if (open my $g, '<', File::Spec->catfile($top, '.claude', 'method-local', 'git-shapes.txt')) {
    my $n = grep { /\S/ && !/\A\s*#/ } <$g>;
    close $g;
    push @w, look("$n git shape" . ($n == 1 ? '' : 's') . " added in .claude/method-local/git-shapes.txt; the guard lets them through (G3)") if $n;
  }
  return @w;
}

sub status_lines {
  my ($top) = @_;
  return (look('status could not be loaded (lib/status.pl); run bash scripts/method/status.sh')) unless $STATUS_LOADED;
  my $status = File::Spec->catfile($lib, '..', 'status.sh');
  my ($st, $out) = Status::run_limited(Time::HiRes::time() + $STATUS_SECONDS, undef, 'bash', $status, '--quick');
  return (look("status did not finish within $STATUS_SECONDS s; run bash scripts/method/status.sh")) unless defined $st;
  my @all = split /\n/, $out;
  my ($last) = grep { /\Astatus: / } reverse @all;
  my @looks = grep { /\A[^:\n]{1,200}: LOOK - / } @all;
  return (look('status gave no summary line; run bash scripts/method/status.sh')) unless defined $last;
  return ($last, @looks);
}

# LINES within the caps: at most $MAX_LINES lines and $MAX_BYTES bytes, each
# line at most $LINE_BYTES, measured as Hook::context prints them (it cleans
# each line again); when some do not fit, the last line says how many more
sub printed { return length Hook::bytes(Hook::clean($_[0])) }
sub capped {
  my @l = map {
    my $c = Hook::clean($_);
    if (printed($c) > $LINE_BYTES) {
      $c = substr($c, 0, $LINE_BYTES - 4);
      $c = substr($c, 0, -1) while printed($c) > $LINE_BYTES - 4;
      $c .= ' ...';
    }
    $c
  } @_;
  my $more = sub { my $n = shift; "... $n more: run bash scripts/method/status.sh" };
  my (@out, $bytes);
  $bytes = 0;
  for my $i (0 .. $#l) {
    my $left = @l - $i;
    my $len = printed($l[$i]) + 1;
    my $room_lines = $MAX_LINES - @out;
    my $fits = $left == 1 ? ($room_lines >= 1 && $bytes + $len <= $MAX_BYTES)
      : ($room_lines >= 2 && $bytes + $len + length($more->($left - 1)) + 1 <= $MAX_BYTES);
    if (!$fits) {
      push @out, $more->($left);
      last;
    }
    push @out, $l[$i];
    $bytes += $len;
  }
  return @out;
}

sub main {
  my ($in, $in_err) = Hook::read_input();
  my $top = ref $in eq 'HASH' && defined $in->{cwd} && !ref $in->{cwd} && -d $in->{cwd} ? $in->{cwd} : ($ENV{CLAUDE_PROJECT_DIR} // '.');
  chdir $top;
  my @lines = eval { (status_lines($top), warnings_for($in, $top, $in_err)) };
  if ($@) {
    (my $e = $@) =~ s/\n.*//s;
    @lines = (look("session-status could not finish: $e; run bash scripts/method/status.sh"));
  }
  Hook::context(capped(@lines)) if @lines;
  return 0;
}

return 1 if caller;
exit main();
