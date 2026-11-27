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
#   session's model not the one the project's profile sets
#   (claude-opus-5-5 with no lock; lib/lock.pl); the PowerShell tool not off on
#   Windows; input that cannot be read; in the project's local settings, a
#   key the method sets, disableAllHooks, skill shell lines on,
#   claudeMdExcludes, a PreToolUse or PermissionRequest hook (the method's
#   are in the project's settings only); in local and user settings
#   ($CLAUDE_CONFIG_DIR's when that is set), an env variable, an enabled
#   plugin, an effort cap below xhigh (also per model), the user file's
#   line saying to tell the owner; in the project's settings, what a first
#   install refuses unless it is kept by name (Lock::refused: a hook of the
#   project's own on an event @Lock::KEEP_EVENTS names,
#   claudeMdExcludes, enabledPlugins, a key that runs a
#   program; step 7.3, step7.md S6); a settings file that is not a regular file, is
#   over 1 MB or is not JSON; the lines a project adds to the guard's lists
#   in .claude/method-local/ (git, gh and MCP), counted. Names only,
#   never a settings value: a model id only in the shape Anthropic's ids
#   have, the effort level by name.
# It also writes G16's snapshot of the local and user settings when a
# session starts (lib/watch.pl; step 5.9), never at clear, compact or fork.
# Since step 8.4 (M164), before every other line, the user-level audit:
# what the person's own Claude Code folder adds that can hide or replace
# the method (a personal skill shadowing a method skill; claudeMdExcludes,
# a method skill switched off, the instruction-files setting; hooks on the
# events a first install refuses), each kind on a line of its own that
# tells Claude to tell the owner what to do (audit_lines, below).
# Since step 5b.2, one LOOK line names how many of the gates' receipts for
# the files at HEAD do not say the first receipt word, and how many say
# each other word (lib/receipt-read.pl; the words are verdicts.txt's).
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
# (a settings file is small; a larger one is named, not read, so reading
# it cannot take the hook past its time)
our $SETTINGS_MAX = 1024 * 1024;
# the whole hook's perl part ends within this many seconds; $OUT is set
# when the time is up, and checked after each step whose own eval could
# have caught the alarm (Json::decode, status's areas)
our $DEADLINE = 20;
our $OUT = 0;
sub in_time { die "out of time\n" if $OUT }

sub look { return "session-status: LOOK - $_[0]" }

# a settings file's data, or (undef, why it cannot be told what it sets);
# only a regular file is opened (a FIFO would hold the hook past its time)
sub read_settings {
  my ($path) = @_;
  return (undef, undef) unless -e $path || -l $path;
  return (undef, 'is not a regular file') unless -f $path;
  return (undef, 'is over 1 MB') if -s _ > $SETTINGS_MAX;
  open my $f, '<:raw', $path or return (undef, "cannot be read");
  my $text = do { local $/; <$f> };
  return (undef, 'is not a regular file') unless -f $f;
  # (a byte-order mark at the start, as some Windows editors write: Claude
  # Code reads such a file, so it is read here too)
  $text =~ s/\A\xEF\xBB\xBF//;
  my ($d, $e) = Json::decode($text, 'plain');
  in_time();
  return (undef, 'is not JSON') if defined $e || ref $d ne 'HASH';
  # (an integer too long for perl comes back from the plain reading as a
  # string of digits, like a JSON string of digits: read again with big
  # numbers, it is a number object, so is_text tells them apart; F23 and
  # the fresh check. When that reading fails, the plain one stands)
  if ($text =~ /[0-9]{19}/) {
    my ($b, $be) = Json::decode($text);
    in_time();
    $d = $b if !defined $be && ref $b eq 'HASH';
  }
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
    # (an effort level set for one model wins over the project's for it)
    my $e = grep { ref $s->{modelSettings}{$_} eq 'HASH' && $low->($s->{modelSettings}{$_}{effortLevel}) } keys %{ $s->{modelSettings} };
    push @what, "an effortLevel below xhigh for $e model" . ($e == 1 ? '' : 's') . ' (modelSettings)' if $e;
  }
  return @what;
}

# what a settings file sets that weakens or overrides the method. Local
# settings rank above the project's, so every key the method sets counts;
# in user settings the project wins for those, so only what adds to a
# session counts: env variables, plugins and effort caps (a user hook is
# on the audit's own line, audit_lines). The method registers its hooks in
# the project's settings only, so every PreToolUse or PermissionRequest
# hook in local settings is another's (a copy of the method's would replace
# the project's, with its own fields)
sub weakens {
  my ($s, $user) = @_;
  my @what;
  if (!$user) {
    my $skill_off = exists $s->{disableSkillShellExecution} && !$s->{disableSkillShellExecution};
    # (switched off, the skill shell setting is named once, as such)
    push @what, grep { exists $s->{$_} && !($skill_off && $_ eq 'disableSkillShellExecution') } @FRAGMENT_KEYS;
    push @what, 'disableAllHooks' if $s->{disableAllHooks};
    push @what, 'disableSkillShellExecution false' if $skill_off;
    # (step 8.4: it keeps the method's rules out, F4)
    push @what, 'claudeMdExcludes' if exists $s->{claudeMdExcludes};
  }
  # (a list is added to the project's, not replaced by it: a model listed
  # in user settings can be chosen in every session)
  push @what, 'availableModels (lists add up)' if $user && exists $s->{availableModels};
  if (ref $s->{env} eq 'HASH') {
    my @k = grep { !$user || !$FRAGMENT_ENV{$_} } keys %{ $s->{env} };
    push @what, 'env ' . env_names(@k) if @k;
  }
  # (a user hook has the audit's own line, audit_lines, step 8.4)
  if (!$user && ref $s->{hooks} eq 'HASH') {
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
    push @what, "$n enabled plugin" . ($n == 1 ? '' : 's') . ' (hooks not read)' if $n;
  }
  push @what, effort_caps($s);
  return @what;
}

# --- the user-level audit (M164; step 8.4, docs/plans/step8.md S9) ---
# What the person's own Claude Code folder ($CLAUDE_CONFIG_DIR when that is
# set, ~/.claude otherwise, as for settings) adds that can hide or replace
# the method in every project: a personal skill named like a method- skill
# the project has (it wins for a typed name and a Skill call, F5; skills/
# synced/ is the client's own and is skipped, F27; personal commands lose
# to the project's skill, F25; a folder counts only when it holds a
# SKILL.md, the file the client reads); in user settings, claudeMdExcludes
# (F4), a skillOverrides entry for one of the project's method- skills set
# to anything but on or name-only (F6; the client's values are on,
# name-only, which only drops the description, user-invocable-only and
# off), the agents-md plugin's instruction files resolved to managed-only
# (F9; its only value that drops the project's instruction files), and a
# hook the client would run on an event a first install refuses
# (@Lock::KEEP_EVENTS, F8). The plugin's settings key is its name or alias
# with @builtin (pluginConfigs["cc-plugin-agents-md@builtin" or
# "agents-md@builtin"].options, the part after @ in any letter case), and
# its option resolves as instruction_files says (instructionFiles, or the
# older projectInstructions, whose value none is managed-only): read from
# the client's strings at 2.1.316 and 2.1.319, and both pinned by harness
# cases (step 8.4). The lines
# go to Claude's context, not to the owner's screen, and the folder is the
# person's, which the guard stops Claude from changing (F13), so each line
# says to tell the owner and what they do. Names only, through Esc::line,
# each cut to $NAME_BYTES; each line within $LINE_BYTES, its names first,
# a long list ending "and N more", what the owner does always whole; they
# come before every other line, as a finding can also hide the text that
# would pass a later line on.
# (the events a first install refuses, when lib/lock.pl does not load)
our @AUDIT_EVENTS = qw(PreToolUse PermissionRequest ConfigChange SessionStart SubagentStart SubagentStop UserPromptSubmit PostToolUse PostToolUseFailure PostToolBatch);
our $AGENTS_MD_KEY = qr/\A(?:cc-plugin-)?agents-md\@builtin\z/i;
our $KEEPS_OUT = 'managed-only';
# the plugin's option as the client resolves it (its strings, the same at
# both pins): instructionFiles is one of these, or else the default; the
# older projectInstructions, when it is set and instructionFiles resolves
# to the default, is read through its own values (any other: claude-md)
our @IF_VALUES = qw(claude-md claude-md-or-agents-md claude-md-and-agents-md managed-only);
our $IF_DEFAULT = 'claude-md-or-agents-md';
our %PI_VALUES = (none => 'managed-only', claude => 'claude-md', 'agents-fallback' => 'claude-md-or-agents-md', both => 'claude-md-and-agents-md');
# the skillOverrides values that leave a skill to the model and to /name
our %SKILL_ON = map { ($_ => 1) } qw(on name-only);
# the hook types the client runs, each with the string fields it needs; it
# drops any other entry
our %HOOK_TYPES = (command => ['command'], prompt => ['prompt'], agent => ['prompt'], http => ['url'], mcp_tool => ['server', 'tool']);
our $NAME_BYTES = 40;
my $TELL = 'tell the owner: ';
my $BY_HAND = 'by hand (Claude cannot): give steps';

# a name as a line shows it: as UTF-8 bytes, through Esc::line, a TAB
# escaped too (Esc::line keeps one, as text may hold it; a name should
# not), cut to $NAME_BYTES so one long name cannot crowd out the rest
sub shown_name {
  my $n = $_[0];
  utf8::encode($n) if utf8::is_utf8($n);
  $n = substr($n, 0, 4 * $NAME_BYTES) if length $n > 4 * $NAME_BYTES;
  $n = Esc::line($n);
  $n =~ s/([\x00-\x1F\x7F])/sprintf('\\x%02X', ord $1)/ge;
  if (printed($n) > $NAME_BYTES) {
    $n = substr($n, 0, $NAME_BYTES - 3);
    $n = substr($n, 0, -1) while printed($n) > $NAME_BYTES - 3;
    # (never half an escape: a cut \x0 would hide what the name holds)
    $n =~ s/\\(?:x[0-9A-F]?|u(?:\{[0-9A-F]*)?)?\z//;
    $n .= '...';
  }
  return $n;
}

# is_text VALUE: a JSON string (JSON::PP gives a number with no string
# part, which the client does not take for text, and an integer too long
# for perl as a number object, read_settings's second reading)
sub is_text {
  my ($v) = @_;
  return 0 unless defined $v && !ref $v;
  require B;
  my $f = B::svref_2object(\$v)->FLAGS;
  return ($f & B::SVp_POK()) || !($f & (B::SVp_IOK() | B::SVp_NOK())) ? 1 : 0;
}

# instruction_files OPTIONS: (the option the client acts on, its value as
# written) when the agents-md plugin resolves OPTIONS to managed-only, the
# one value that drops the project's instruction files; else ()
sub instruction_files {
  my ($o) = @_;
  my $if = $o->{instructionFiles};
  my $r = defined $if && !ref $if && grep({ $_ eq $if } @IF_VALUES) ? $if : $IF_DEFAULT;
  if (exists $o->{projectInstructions} && defined $o->{projectInstructions} && $r eq $IF_DEFAULT) {
    my $pi = $o->{projectInstructions};
    my $p = !ref $pi && exists $PI_VALUES{$pi} ? $PI_VALUES{$pi} : 'claude-md';
    return $p eq $KEEPS_OUT ? ('projectInstructions', $pi) : ();
  }
  return $r eq $KEEPS_OUT ? ('instructionFiles', $r) : ();
}

sub audit_events {
  my $ok = eval { require File::Spec->catfile($lib, 'lock.pl'); 1 };
  no warnings 'once';
  return $ok && @Lock::KEEP_EVENTS ? @Lock::KEEP_EVENTS : @AUDIT_EVENTS;
}

# the person's folder, as (PATH, how a line names it), or ()
sub user_dir {
  return ($ENV{CLAUDE_CONFIG_DIR}, '$CLAUDE_CONFIG_DIR') if defined $ENV{CLAUDE_CONFIG_DIR} && $ENV{CLAUDE_CONFIG_DIR} ne '';
  return (File::Spec->catfile($ENV{HOME}, '.claude'), '~/.claude') if defined $ENV{HOME} && $ENV{HOME} ne '';
  return ();
}

# listed HEAD NAMES TAIL [SEP] [EXTRA]: one LOOK line, "tell the owner: "
# HEAD, NAMES in their order as far as they fit, "and N more" for those
# left out, EXTRA when it fits, then TAIL (what the owner does), never over
# $LINE_BYTES and TAIL always whole. Each name is tried once, in order: one
# that does not fit is left out and counted, and a shorter one after it
# may still come (so a long item cannot hide the short ones), each try a
# line of at most about $LINE_BYTES, so the work stays small whatever
# their number. When the first name is left out, the most of it that fits
# comes first, ending "...".
sub listed {
  my ($head, $names, $tail, $sep, $extra) = @_;
  $sep = ', ' unless defined $sep;
  $extra = '' unless defined $extra;
  my $n = @$names;
  my $fit = sub { printed(look("$TELL$head$_[0]$tail")) <= $LINE_BYTES };
  my $more = sub { $_[0] ? " and $_[0] more" : '' };
  my (@in, $out, $first_out);
  $out = 0;
  for my $i (0 .. $n - 1) {
    in_time();
    my $x = $names->[$i];
    $x = substr($x, 0, $LINE_BYTES) if length $x > $LINE_BYTES;
    if ($fit->(join($sep, @in, $x) . $more->($out + $n - $i - 1))) { push @in, $x; next }
    $out++;
    $first_out = 1 if $i == 0;
  }
  if ($first_out) {
    my $c = substr($names->[0], 0, $LINE_BYTES);
    $c = substr($c, 0, -1) while length $c && !$fit->(join($sep, "$c...", @in) . $more->($out - 1));
    if (length $c) { unshift @in, "$c..."; $out-- }
  }
  my $list = join($sep, @in) . $more->($out);
  $list .= $extra if $extra ne '' && $fit->("$list$extra");
  return look("$TELL$head$list$tail");
}

sub audit_lines {
  my ($project) = @_;
  my ($dir, $shown) = user_dir();
  return () unless defined $dir;
  my @w;
  # personal skills named like the project's method- skills
  my %mine;
  if (opendir my $d, File::Spec->catfile($project, '.claude', 'skills')) {
    %mine = map { ($_ => 1) } grep { /\Amethod-/ } readdir $d;
    closedir $d;
  }
  if (opendir my $d, File::Spec->catfile($dir, 'skills')) {
    my @own;
    while (defined(my $e = readdir $d)) {
      next if $e eq '.' || $e eq '..' || $e eq 'synced' || $e !~ /\Amethod-/;
      push @own, $e if -f File::Spec->catfile($dir, 'skills', $e, 'SKILL.md');
      in_time() unless @own % 1000;
    }
    closedir $d;
    # (method-start first: it is the skill that reports to the owner)
    my @shadow = sort { ($b eq 'method-start') <=> ($a eq 'method-start') || $a cmp $b } grep { $mine{$_} } @own;
    my $other = grep { !$mine{$_} } @own;
    if (@shadow) {
      my $one = @shadow == 1;
      push @w, listed('personal skill' . ($one ? ' ' : 's '), [map { shown_name($_) } @shadow],
        " in $shown/skills " . ($one ? 'runs' : 'run') . " in place of the project's; they remove or rename " . ($one ? 'it' : 'them') . " $BY_HAND",
        undef, $other ? " (+$other other personal method-*, not named)" : undef);
    }
  }
  in_time();
  my ($s) = read_settings(File::Spec->catfile($dir, 'settings.json'));
  return @w unless $s;
  my $file = "$shown/settings.json";
  # settings that keep the method's text out or switch a method skill off
  # (the instruction files first: they drop CLAUDE.md, AGENTS.md and the
  # method's rules at once)
  my @out;
  if (ref $s->{pluginConfigs} eq 'HASH') {
    # (the client reads both keys and merges their options, agents-md@builtin
    # first and cc-plugin-agents-md@builtin after it, the later one winning
    # for each option, then resolves the result once; step 8's review, F7)
    my (%merged, $any);
    for my $key (sort { ($a =~ /\Acc-plugin-/i ? 1 : 0) <=> ($b =~ /\Acc-plugin-/i ? 1 : 0) || $a cmp $b } keys %{ $s->{pluginConfigs} }) {
      next unless $key =~ $AGENTS_MD_KEY;
      my $o = ref $s->{pluginConfigs}{$key} eq 'HASH' ? $s->{pluginConfigs}{$key}{options} : undef;
      next unless ref $o eq 'HASH';
      %merged = (%merged, %$o);
      $any = 1;
    }
    if ($any) {
      my ($opt, $v) = instruction_files(\%merged);
      push @out, "agents-md $opt $v" if defined $opt;
    }
  }
  push @out, 'claudeMdExcludes' if exists $s->{claudeMdExcludes};
  if (ref $s->{skillOverrides} eq 'HASH') {
    my $ov = $s->{skillOverrides};
    # (only the project's own method- skills: an override for another
    # skill changes nothing of the method, and its name is the person's)
    # (a key is characters, a folder's name bytes: compared as UTF-8)
    my $byte = sub { my $k = $_[0]; utf8::encode($k) if utf8::is_utf8($k); $k };
    my @off = sort grep { $mine{ $byte->($_) } && !(defined $ov->{$_} && !ref $ov->{$_} && $SKILL_ON{ $ov->{$_} }) } keys %$ov;
    push @out, map { 'skillOverrides ' . shown_name($_) } @off;
  }
  push @w, listed('', \@out, " in $file keep the method out; they remove " . (@out == 1 ? 'it' : 'them') . " $BY_HAND") if @out;
  # hooks the client would run on the events a first install refuses
  if (ref $s->{hooks} eq 'HASH') {
    my @on;
    for my $ev (audit_events()) {
      next unless ref $s->{hooks}{$ev} eq 'ARRAY';
      my $n = 0;
      for my $g (@{ $s->{hooks}{$ev} }) {
        next unless ref $g eq 'HASH' && ref $g->{hooks} eq 'ARRAY';
        $n += grep {
          my $e = $_;
          ref $e eq 'HASH' && is_text($e->{type}) && $HOOK_TYPES{ $e->{type} }
            && !grep { !is_text($e->{$_}) || $e->{$_} eq '' } @{ $HOOK_TYPES{ $e->{type} } }
        } @{ $g->{hooks} };
      }
      push @on, "$ev ($n)" if $n;
    }
    push @w, listed('hooks on ', \@on, " in $file run beside the guard or reach every prompt; they remove or keep them $BY_HAND") if @on;
  }
  return @w;
}

sub warnings_for {
  my ($in, $top, $in_err) = @_;
  my @w;
  push @w, look("the hook's input could not be read ($in_err), so the session's model was not checked") if defined $in_err;
  push @w, look("the advisor is not switched off (CLAUDE_CODE_DISABLE_ADVISOR_TOOL is not 1; the method's settings switch it off)")
    unless ($ENV{CLAUDE_CODE_DISABLE_ADVISOR_TOOL} // '') eq '1';
  push @w, look('auto memory is switched on by CLAUDE_CODE_DISABLE_AUTO_MEMORY=0 (M104)')
    if defined $ENV{CLAUDE_CODE_DISABLE_AUTO_MEMORY} && $ENV{CLAUDE_CODE_DISABLE_AUTO_MEMORY} eq '0';
  my $model = ref $in eq 'HASH' ? $in->{model} : undef;
  # the model the project's profile sets (claude-opus-5-5 with no lock, or
  # when the lock or its row cannot be read)
  my $project = defined $ENV{CLAUDE_PROJECT_DIR} && -d $ENV{CLAUDE_PROJECT_DIR} ? $ENV{CLAUDE_PROJECT_DIR} : $top;
  my $lock_ok = eval { require File::Spec->catfile($lib, 'lock.pl'); 1 };
  my ($pname, $prow) = $lock_ok ? eval { Lock::profile($project) } : ();
  my ($want, $sets) = $prow ? ($prow->{model}, "the model the project's profile ($pname) sets") : ('claude-opus-5-5', 'the model the method sets');
  # (a model id is shown only in the shape Anthropic's ids have)
  push @w, look('this session runs ' . ($model =~ /\Aclaude-[a-z0-9.-]{1,60}\z/ ? $model : 'a model') . ", not $want, $sets")
    if defined $model && !ref $model && $model ne '' && $model ne $want;
  push @w, look('the PowerShell tool is not switched off (CLAUDE_CODE_USE_POWERSHELL_TOOL is not 0); the guard refuses it')
    if $^O =~ /\A(?:msys|MSWin32|cygwin)\z/ && ($ENV{CLAUDE_CODE_USE_POWERSHELL_TOOL} // '') ne '0';
  # local settings: the project's own, which Claude Code reads (not the
  # folder Claude moved into); user settings: where Claude Code reads them
  my @files = (['.claude/settings.local.json', File::Spec->catfile($project, '.claude', 'settings.local.json'), 0]);
  if (defined $ENV{CLAUDE_CONFIG_DIR} && $ENV{CLAUDE_CONFIG_DIR} ne '') {
    push @files, ['$CLAUDE_CONFIG_DIR/settings.json', File::Spec->catfile($ENV{CLAUDE_CONFIG_DIR}, 'settings.json'), 1];
  } elsif (defined $ENV{HOME} && $ENV{HOME} ne '') {
    push @files, ['~/.claude/settings.json', File::Spec->catfile($ENV{HOME}, '.claude', 'settings.json'), 1];
  }
  for my $f (@files) {
    my ($name, $path, $user) = @$f;
    my ($s, $e) = read_settings($path);
    if (defined $e) { push @w, look($user ? "${TELL}$name $e, so what it changes is not known; they fix it $BY_HAND" : "$name $e, so what it changes is not known"); next }
    next unless $s;
    my @what = weakens($s, $user);
    next unless @what;
    # (the user's file is the person's to change, so the line says to tell
    # them, as the audit's lines do, and keeps that whole; step 8.4)
    push @w, $user ? listed("$name adds to every session: ", \@what, "; they change it $BY_HAND", '; ')
      : look("$name sets " . join('; ', @what) . "; it ranks above the method's settings");
  }
  # the project's settings: what runs or loads beside the method that a
  # first install refuses unless kept by name (named, never its value)
  if ($lock_ok) {
    my ($s) = read_settings(File::Spec->catfile($project, '.claude', 'settings.json'));
    my @kept = $s ? eval { map { $_->[1] } Lock::refused($s) } : ();
    push @w, look('.claude/settings.json keeps ' . join('; ', @kept) . ", which run or load beside the method's hooks (a first install refuses each unless kept by name)") if @kept;
  }
  # the project's own lines in the guard's lists: the guard lets each
  # through (only a regular file, under the settings' size cap, is read)
  for my $l (['git-shapes.txt', 'git shape', 'G3'], ['gh-shapes.txt', 'gh shape', 'G4'], ['mcp-tools.txt', 'MCP tool line', 'G4']) {
    my ($file, $what, $rule) = @$l;
    my $path = File::Spec->catfile($top, '.claude', 'method-local', $file);
    next unless -e $path || -l $path;
    my $name = ".claude/method-local/$file";
    if (!-f $path) { push @w, look("$name is not a regular file, so what it adds is not known"); next }
    if (-s _ > $SETTINGS_MAX) { push @w, look("$name is over 1 MB, so what it adds is not known"); next }
    my $g;
    if (!open $g, '<', $path) { push @w, look("$name cannot be read, so what it adds is not known"); next }
    my $n = grep { /\S/ && !/\A\s*#/ } <$g>;
    close $g;
    in_time();
    push @w, look("$n $what" . ($n == 1 ? '' : 's') . " added in $name; the guard lets them through ($rule)") if $n;
  }
  return @w;
}

# the gates' receipts for HEAD's tree in TOP that do not say the first
# receipt word: one LOOK line, or none
sub receipt_lines {
  my ($top, $project) = @_;
  my @c = eval { require File::Spec->catfile($lib, 'receipt-read.pl'); Receipt::counts($project, $top) };
  my $err = $@;
  in_time();
  return (look("the gates' receipts could not be read; .method/local/gates.log has a line for each gate run")) if $err;
  return () unless @c;
  my $n = 0;
  $n += $_->[1] for @c;
  return (look("$n gate receipt" . ($n == 1 ? '' : 's') . " for the files at HEAD " . ($n == 1 ? 'does' : 'do') . ' not say '
    . Receipt::words()->{good} . ': ' . join(', ', map { "$_->[1] $_->[0]" } @c) . ' (.method/local/gates.log says why)'));
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
  my $project = defined $ENV{CLAUDE_PROJECT_DIR} && -d $ENV{CLAUDE_PROJECT_DIR} ? $ENV{CLAUDE_PROJECT_DIR} : $top;
  # (within 20 s in all, so the hook ends well inside its 30 s and
  # METHOD-ACTIVE always reaches Claude; a nested run skips status only)
  my @lines;
  my $ok = eval {
    local $SIG{ALRM} = sub { $OUT = 1; die "out of time\n" };
    alarm $DEADLINE;
    # G16's snapshot, inside the deadline (a git call that hangs cannot hold
    # the hook; final review of step 5); a failure leaves none, and G16
    # then judges what the files hold
    eval { require File::Spec->catfile($lib, 'watch.pl'); Watch::snapshot($in, $project) };
    in_time();
    # (the user-level audit first: what it names can hide the text that
    # would pass later lines on, and the caps drop lines from the end)
    push @lines, audit_lines($project);
    in_time();
    push @lines, status_lines($top) unless ($ENV{METHOD_NESTED} // '') eq '1';
    in_time();
    push @lines, warnings_for($in, $top, $in_err);
    in_time();
    push @lines, receipt_lines($top, $project);
    alarm 0;
    1;
  };
  alarm 0;
  $ok = 0, $@ = "out of time\n" if $OUT;
  if (!$ok) {
    (my $e = $@ || 'it stopped') =~ s/\n.*//s;
    push @lines, $e eq 'out of time'
      ? look("session-status ran out of time ($DEADLINE s), so part of its checks is missing; run bash scripts/method/status.sh")
      : look("session-status could not finish: $e; run bash scripts/method/status.sh");
  }
  Hook::context(capped(@lines)) if @lines;
  return 0;
}

return 1 if caller;
exit main();
