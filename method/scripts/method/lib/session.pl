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
#   Windows; and, in the project's local settings and the user's settings,
#   a key the method sets, disableAllHooks, an env variable, a PreToolUse
#   or PermissionRequest hook that is not the method's, an enabled plugin,
#   and (user settings) a maxEffortLevel below xhigh. Names only, never a
#   value.
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
require File::Spec->catfile($lib, 'status.pl');

our $MAX_LINES = 9;          # METHOD-ACTIVE is the tenth
our $MAX_BYTES = 1200 - 40;  # the METHOD-ACTIVE line takes at most 40
our $LINE_BYTES = 240;
our $STATUS_SECONDS = 5;

# the keys the method's settings set (method/settings.fragment.json)
my @FRAGMENT_KEYS = qw(model availableModels enforceAvailableModels effortLevel attribution autoMemoryEnabled
  disableSkillShellExecution skillOverrides minimumVersion);
my $METHOD_HOOK = qr{\ABASH_ENV= ENV= bash "\$CLAUDE_PROJECT_DIR/\.claude/hooks/method/(?:session-status|guard|gate-receipt)\.sh"\z};

sub look { return "session-status: LOOK - $_[0]" }

sub read_settings {
  my ($path) = @_;
  return (undef, undef) unless -e $path;
  open my $f, '<:raw', $path or return (undef, "cannot be read");
  my ($d, $e) = Json::decode(do { local $/; <$f> }, 'plain');
  return (undef, 'is not JSON') if defined $e || ref $d ne 'HASH';
  return ($d, undef);
}

# what a settings file sets that weakens or overrides the method
sub weakens {
  my ($s, $user) = @_;
  my @what;
  push @what, grep { exists $s->{$_} } @FRAGMENT_KEYS;
  push @what, 'disableAllHooks' if $s->{disableAllHooks};
  push @what, 'disableSkillShellExecution false' if exists $s->{disableSkillShellExecution} && !$s->{disableSkillShellExecution};
  if (ref $s->{env} eq 'HASH' && %{ $s->{env} }) {
    push @what, 'env ' . join(', ', sort keys %{ $s->{env} });
  }
  if (ref $s->{hooks} eq 'HASH') {
    my $n = 0;
    for my $event (qw(PreToolUse PermissionRequest)) {
      next unless ref $s->{hooks}{$event} eq 'ARRAY';
      for my $g (@{ $s->{hooks}{$event} }) {
        next unless ref $g eq 'HASH' && ref $g->{hooks} eq 'ARRAY';
        $n += grep { !(ref $_ eq 'HASH' && defined $_->{command} && !ref $_->{command} && $_->{command} =~ $METHOD_HOOK) } @{ $g->{hooks} };
      }
    }
    push @what, "$n PreToolUse or PermissionRequest hook" . ($n == 1 ? '' : 's') . " that are not the method's" if $n;
  }
  if (ref $s->{enabledPlugins} eq 'HASH') {
    my $n = grep { $s->{enabledPlugins}{$_} } keys %{ $s->{enabledPlugins} };
    push @what, "$n enabled plugin" . ($n == 1 ? '' : 's') . ' (their hooks were not read)' if $n;
  }
  if ($user && defined $s->{maxEffortLevel} && !ref $s->{maxEffortLevel} && $s->{maxEffortLevel} =~ /\A(?:low|medium|high)\z/) {
    push @what, "maxEffortLevel $s->{maxEffortLevel}, below xhigh";
  }
  return @what;
}

sub warnings_for {
  my ($in, $top) = @_;
  my @w;
  push @w, look("the advisor is not switched off (CLAUDE_CODE_DISABLE_ADVISOR_TOOL is not 1; DECISIONS A5)")
    unless ($ENV{CLAUDE_CODE_DISABLE_ADVISOR_TOOL} // '') eq '1';
  push @w, look('auto memory is switched on by CLAUDE_CODE_DISABLE_AUTO_MEMORY=0 (M104)')
    if defined $ENV{CLAUDE_CODE_DISABLE_AUTO_MEMORY} && $ENV{CLAUDE_CODE_DISABLE_AUTO_MEMORY} eq '0';
  my $model = ref $in eq 'HASH' ? $in->{model} : undef;
  push @w, look("this session runs $model, not claude-opus-5-5 (DECISIONS A2)")
    if defined $model && !ref $model && $model ne '' && $model ne 'claude-opus-5-5';
  push @w, look('the PowerShell tool is not switched off (CLAUDE_CODE_USE_POWERSHELL_TOOL is not 0); the guard refuses it')
    if $^O =~ /\A(?:msys|MSWin32|cygwin)\z/ && ($ENV{CLAUDE_CODE_USE_POWERSHELL_TOOL} // '') ne '0';
  my @files = (['.claude/settings.local.json', File::Spec->catfile($top, '.claude', 'settings.local.json'), 0]);
  push @files, ['~/.claude/settings.json', File::Spec->catfile($ENV{HOME}, '.claude', 'settings.json'), 1] if defined $ENV{HOME} && $ENV{HOME} ne '';
  for my $f (@files) {
    my ($name, $path, $user) = @$f;
    my ($s, $e) = read_settings($path);
    if (defined $e) { push @w, look("$name $e, so what it changes is not known"); next }
    next unless $s;
    my @what = weakens($s, $user);
    push @w, look("$name sets " . join('; ', @what) . "; it ranks above the method's settings") if @what;
  }
  return @w;
}

sub status_lines {
  my ($top) = @_;
  my $status = File::Spec->catfile($lib, '..', 'status.sh');
  my ($st, $out) = Status::run_limited(Time::HiRes::time() + $STATUS_SECONDS, undef, 'bash', $status, '--quick');
  return (look("status did not finish within $STATUS_SECONDS s; run bash scripts/method/status.sh")) unless defined $st;
  my @all = split /\n/, $out;
  my ($last) = grep { /\Astatus: / } reverse @all;
  my @looks = grep { /\A[a-z][a-z0-9 .\/-]*: LOOK - / } @all;
  return (look('status gave no summary line; run bash scripts/method/status.sh')) unless defined $last;
  return ($last, @looks);
}

# LINES within the caps: at most $MAX_LINES lines and $MAX_BYTES bytes, each
# line at most $LINE_BYTES; when some do not fit, the last line says how
# many more
sub capped {
  my @l = map {
    my $c = Hook::clean($_);
    my $b = Hook::bytes($c);
    if (length $b > $LINE_BYTES) {
      $c = substr($c, 0, $LINE_BYTES - 4);
      $c = substr($c, 0, -1) while length(Hook::bytes($c)) > $LINE_BYTES - 4;
      $c .= ' ...';
    }
    $c
  } @_;
  my $more = sub { my $n = shift; "... $n more: run bash scripts/method/status.sh" };
  my (@out, $bytes);
  $bytes = 0;
  for my $i (0 .. $#l) {
    my $left = @l - $i;
    my $len = length(Hook::bytes($l[$i])) + 1;
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
  my ($in) = Hook::read_input();
  my $top = ref $in eq 'HASH' && defined $in->{cwd} && !ref $in->{cwd} && -d $in->{cwd} ? $in->{cwd} : ($ENV{CLAUDE_PROJECT_DIR} // '.');
  chdir $top;
  my @lines = eval { (status_lines($top), warnings_for($in, $top)) };
  if ($@) {
    (my $e = $@) =~ s/\n.*//s;
    @lines = (look("session-status could not finish: $e; run bash scripts/method/status.sh"));
  }
  Hook::context(capped(@lines)) if @lines;
  return 0;
}

return 1 if caller;
exit main();
