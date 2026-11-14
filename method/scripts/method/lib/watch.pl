#!/usr/bin/env perl
# What could change the session's hooks once it has started (step 5.9;
# docs/plans/step5.md, sections 6.1 and 6.2; DECISIONS A50, A68). Loaded
# by lib/guard.pl and lib/session.pl with require; nothing runs when it is
# loaded.
#
# G16 settings-change (M136): Claude Code reads its settings files again
# when they change during a session, and a changed hook, env variable,
# plugin or disableAllHooks could switch the method's hooks off or run
# something around them. At its ConfigChange event (sources user_settings,
# project_settings and local_settings) the guard refuses:
#   - any change to the project's settings (.claude/settings.json);
#   - in the local or user settings, a change to env, hooks,
#     disableAllHooks, enabledPlugins or a setting that runs a program
#     (statusLine, apiKeyHelper and the like), a permissions.deny entry removed,
#     or disableSkillShellExecution turned off, compared with the snapshot
#     session-status took when the session started (in git's folder, which
#     G6 protects); with no snapshot, a file that holds any of those (or
#     disableAllHooks or disableSkillShellExecution in their weakening
#     value) is refused;
#   - a settings file it cannot read.
# Claude Code shows nobody a refused change, so the refusal is logged and
# the next call the guard lets through brings a one-time message.
#
# G17 skill-and-agent-hooks (M137): a skill's or agent's frontmatter hooks
# are registered when it is used, for the rest of the session. At a Skill,
# Agent or Task call, the call is refused when any definition of that name
# (the project's and the user's skills, commands and agents, and those of
# the plugins installed in the user's folder) declares hooks in its
# frontmatter, or cannot be read.
#
# Interface:
#   Watch::snapshot(IN, PROJECT): at SessionStart, writes the snapshot when
#     the session starts (source startup, or resume with none yet); never at
#     clear, compact or fork, so a change refused mid-session never becomes
#     the baseline.
#   Watch::judge_change(IN, PROJECT) () or ('G16', TEXT).
#   Watch::note_refused(PROJECT), Watch::take_note(PROJECT) TEXT or undef:
#     the one-time message.
#   Watch::judge_def(TOOL, INPUT, PROJECT) () or ('G17', TEXT).
package Watch;
use strict;
use warnings;
use File::Basename qw(dirname basename);
use File::Glob qw(bsd_glob GLOB_QUOTE GLOB_NOSORT);
use File::Spec;
use JSON::PP ();

my $lib = dirname(File::Spec->rel2abs(__FILE__));
require File::Spec->catfile($lib, 'hook.pl');
require File::Spec->catfile($lib, 'git.pl');
require File::Spec->catfile($lib, 'log.pl');

our $MAX = 1024 * 1024;    # a settings or definition file is small
our $KEEP = 20;            # snapshots kept: the last sessions' (A67's G12 note keeps as many)
# the settings that run a program outside the hooks: compared with the
# snapshot too (final review of step 5)
our @RUNS = qw(statusLine apiKeyHelper fileSuggestion otelHeadersHelper awsAuthRefresh awsCredentialExport);
our @KEYS = (qw(env hooks disableAllHooks enabledPlugins disableSkillShellExecution), @RUNS);
our $NOTE = '.method/local/settings-refused';

sub bytes { my ($s) = @_; utf8::encode($s) if defined $s && utf8::is_utf8($s); return $s }

# a small file's text: (TEXT), (undef, undef) when it is not there, or
# (undef, why it cannot be read); only a regular file is opened
sub small_file {
  my ($path) = @_;
  return (undef, undef) unless defined $path && (-e $path || -l $path);
  return (undef, 'is not a regular file') unless -f $path;
  return (undef, 'is over 1 MB') if -s _ > $MAX;
  open my $f, '<:raw', $path or return (undef, 'cannot be read');
  my $text = do { local $/; <$f> };
  return (undef, 'is not a regular file') unless -f $f;
  return ($text // '', undef);
}

# a settings file's data: (DATA), (undef, undef) when it is not there, or
# (undef, why what it sets cannot be told)
sub read_settings {
  my ($path) = @_;
  my ($text, $e) = small_file($path);
  return (undef, $e) unless defined $text;
  $text =~ s/\A\xEF\xBB\xBF//;
  my ($d, $je) = Json::decode($text, 'plain');
  return (undef, 'is not JSON') if defined $je || ref $d ne 'HASH';
  return ($d, undef);
}

my $CANON = JSON::PP->new->canonical->allow_nonref->allow_blessed->convert_blessed;
sub canon { my ($v) = @_; return $CANON->encode($v) }

# the keys G16 watches in settings DATA: each as canonical JSON text, and
# deny as the sorted list of its plain entries
sub watched {
  my ($s) = @_;
  my %w = (deny => []);
  return \%w unless ref $s eq 'HASH';
  for my $k (@KEYS) { $w{$k} = canon($s->{$k}) if exists $s->{$k} }
  my $d = ref $s->{permissions} eq 'HASH' ? $s->{permissions}{deny} : undef;
  $w{deny} = [sort grep { defined && !ref } @$d] if ref $d eq 'ARRAY';
  return \%w;
}

# the settings files, by the source Claude Code names
sub files {
  my ($project) = @_;
  my %f;
  if (defined $project && $project ne '') {
    $f{project_settings} = File::Spec->catfile($project, '.claude', 'settings.json');
    $f{local_settings} = File::Spec->catfile($project, '.claude', 'settings.local.json');
  }
  my $cfg = config_dir();
  $f{user_settings} = File::Spec->catfile($cfg, 'settings.json') if defined $cfg;
  return \%f;
}

# the user's Claude Code folder ($CLAUDE_CONFIG_DIR, or ~/.claude)
sub config_dir {
  return $ENV{CLAUDE_CONFIG_DIR} if defined $ENV{CLAUDE_CONFIG_DIR} && $ENV{CLAUDE_CONFIG_DIR} ne '';
  return File::Spec->catfile($ENV{HOME}, '.claude') if defined $ENV{HOME} && $ENV{HOME} ne '';
  return undef;
}

# the snapshot's path for session SID: in git's own folder (method-*,
# which G6 protects), named by a hash of the session's id; undef with no
# git folder or no session id
sub snapshot_path {
  my ($project, $sid) = @_;
  return undef unless defined $project && $project ne '' && defined $sid && !ref $sid && $sid ne '';
  my ($st, $out) = Git::run('-C', $project, 'rev-parse', '--git-common-dir');
  return undef unless $st == 0;
  my ($c) = split /\n/, $out;
  return undef unless defined $c && $c ne '';
  $c = File::Spec->rel2abs($c, $project);
  # (where the folder is a link, as when .git links to a store elsewhere,
  # the folder it names: the writer refuses to write through a link)
  require Cwd;
  my $real = Cwd::realpath($c);
  $c = $real if defined $real;
  require Digest::SHA;
  return File::Spec->catfile($c, 'method-settings-' . substr(Digest::SHA::sha256_hex(bytes("settings\0$sid")), 0, 16) . '.json');
}

sub snapshot {
  my ($in, $project) = @_;
  return unless ref $in eq 'HASH';
  my $src = defined $in->{source} && !ref $in->{source} ? $in->{source} : '';
  my $path = snapshot_path($project, $in->{session_id});
  return unless defined $path;
  return unless $src eq 'startup' || ($src eq 'resume' && !-e $path);
  my $f = files($project);
  my %snap;
  for my $k (qw(local_settings user_settings)) {
    my ($d, $e) = read_settings($f->{$k});
    $snap{$k} = defined $e ? { unreadable => 1 } : watched($d);
  }
  # (written whole, as ASCII JSON, so a non-ASCII value reads back; the
  # last $KEEP sessions' snapshots are kept, always the one just written)
  my ($dir, $name) = (dirname($path), basename($path));
  eval { Log::write_whole($dir, $name, Json::encode(\%snap), 0600) } or return;
  eval { Log::keep_newest($dir, 'method-settings-', '.json', $KEEP, $name) };
  return 1;
}

sub glob_quote { my ($s) = @_; $s =~ s/([\\*?\[\]{}~])/\\$1/g; return $s }

sub is_false { my ($v) = @_; return defined $v && $v eq 'false' }

sub judge_change {
  my ($in, $project) = @_;
  return () unless ref $in eq 'HASH';
  my $src = defined $in->{source} && !ref $in->{source} ? $in->{source} : '';
  return () unless $src =~ /\A(?:user_settings|project_settings|local_settings)\z/;
  my $later = 'the change is refused for this session and applies from the next one; if you made it yourself, start a new session';
  return ('G16', "the project's settings (.claude/settings.json) changed during this session; $later") if $src eq 'project_settings';
  my $name = $src eq 'local_settings' ? 'the local settings (.claude/settings.local.json)' : 'your user settings (~/.claude/settings.json)';
  my $f = files($project);
  my ($d, $e) = read_settings($f->{$src});
  return ('G16', "$name changed during this session and $e, so what it changes cannot be told; $later") if defined $e;
  my $now = watched($d);
  my $snap;
  my $path = snapshot_path($project, $in->{session_id});
  if (defined $path) {
    my ($text) = small_file($path);
    my ($s) = defined $text ? Json::decode($text, 'plain') : ();
    $snap = $s->{$src} if ref $s eq 'HASH' && ref $s->{$src} eq 'HASH';
  }
  my @why;
  if ($snap && !$snap->{unreadable}) {
    for my $k (qw(env hooks disableAllHooks enabledPlugins), @RUNS) {
      push @why, $k if ($now->{$k} // '') ne ($snap->{$k} // '');
    }
    my %has = map { $_ => 1 } @{ $now->{deny} };
    push @why, 'a permissions.deny entry removed' if grep { !$has{$_} } @{ ref $snap->{deny} eq 'ARRAY' ? $snap->{deny} : [] };
    push @why, 'disableSkillShellExecution turned off' if is_false($now->{disableSkillShellExecution}) && !is_false($snap->{disableSkillShellExecution});
  } else {
    # (no snapshot to compare with: what the file holds now)
    push @why, grep { exists $now->{$_} } qw(env hooks enabledPlugins);
    push @why, 'disableAllHooks' if exists $now->{disableAllHooks} && !is_false($now->{disableAllHooks});
    push @why, 'disableSkillShellExecution turned off' if is_false($now->{disableSkillShellExecution});
  }
  return () unless @why;
  return ('G16', "$name changed during this session (" . join(', ', @why) . "), which could switch the method's hooks off or run something around them; $later");
}

sub note_refused {
  my ($project) = @_;
  return unless defined $project && $project ne '';
  eval { Log::append($project, $NOTE, 1, rule => 'G16', tool => 'ConfigChange', hash => '0' x 64) };
}

sub take_note {
  my ($project) = @_;
  return undef unless defined $project && $project ne '';
  my $p = File::Spec->catfile($project, split m{/}, $NOTE);
  return undef unless -f $p;
  unlink $p;
  return "a settings change was refused during this session (see .method/local/guard.log); it applies from the next session. If you made it yourself (/permissions, /plugin, an edit), start a new session";
}

# --- G17 ---

# a definition's frontmatter: 1 when it declares hooks, 0 when not, or
# (undef, why it cannot be read)
sub declares_hooks {
  my ($path) = @_;
  my ($text, $e) = small_file($path);
  return (undef, $e) unless defined $text;
  $text =~ s/\A\xEF\xBB\xBF//;
  return 0 unless $text =~ /\A---[ \t]*\r?\n(.*?)^---[ \t]*\r?$/ms;
  my $fm = $1;
  return $fm =~ /^["']?hooks["']?[ \t]*:/m ? 1 : 0;
}

# an agent file's own name (its frontmatter's name, or its file name)
sub agent_name {
  my ($path) = @_;
  my ($text) = small_file($path);
  if (defined $text && $text =~ /\A(?:\xEF\xBB\xBF)?---[ \t]*\r?\n(.*?)^---/ms) {
    my $fm = $1;
    return $1 if $fm =~ /^name[ \t]*:[ \t]*["']?([^"'\r\n]+?)["']?[ \t]*\r?$/m;
  }
  (my $n = basename($path)) =~ s/\.md\z//i;
  return $n;
}

# the plugin folders under the user's folder, a few levels down (an
# installed plugin's skills/, commands/ or agents/ folder), at most 2000
sub plugin_roots {
  my ($cfg) = @_;
  return () unless defined $cfg;
  my $base = glob_quote(File::Spec->catfile($cfg, 'plugins'));
  my @r;
  for my $depth (1 .. 5) {
    push @r, map { dirname($_) } bsd_glob($base . ('/*' x $depth) . '/{skills,commands,agents}', GLOB_QUOTE | GLOB_NOSORT | File::Glob::GLOB_BRACE());
    last if @r > 2000;
  }
  my %seen;
  return grep { !$seen{$_}++ } @r;
}

# every file that could define the skill or agent NAME (plugin:name too)
sub def_files {
  my ($kind, $name, $project) = @_;
  my ($plugin, $short) = $name =~ /\A([^:]+):(.+)\z/ ? ($1, $2) : (undef, $name);
  my $cfg = config_dir();
  my @roots = map { File::Spec->catfile($_, '.claude') } grep { defined && $_ ne '' } $project;
  push @roots, $cfg if defined $cfg;
  my @plugins = plugin_roots($cfg);
  my @f;
  if ($kind eq 'skill') {
    # a skill folder, or a command file (its : read as a subfolder too)
    (my $sub = $name) =~ s{:}{/}g;
    for my $r (@roots, @plugins) {
      for my $n ($short, $name) {
        push @f, File::Spec->catfile($r, 'skills', $n, 'SKILL.md');
        push @f, File::Spec->catfile($r, 'commands', "$n.md");
      }
      push @f, File::Spec->catfile($r, 'commands', "$sub.md");
    }
  } else {
    for my $r (@roots, @plugins) {
      my $d = File::Spec->catfile($r, 'agents');
      next unless -d $d;
      my @md;
      my @dirs = ($d);
      while (@dirs && @md < 2000) {
        my $x = shift @dirs;
        opendir my $h, $x or next;
        for my $e (readdir $h) {
          next if $e eq '.' || $e eq '..';
          my $p = File::Spec->catfile($x, $e);
          if (-d $p && !-l $p) { push @dirs, $p if @dirs < 200 }
          elsif ($e =~ /\.md\z/i) { push @md, $p }
        }
        closedir $h;
      }
      push @f, grep { my $a = agent_name($_); $a eq $short || $a eq $name } @md;
    }
  }
  my %seen;
  return grep { (-e $_ || -l $_) && !$seen{$_}++ } @f;
}

sub judge_def {
  my ($tool, $input, $project) = @_;
  return () unless ref $input eq 'HASH';
  my $kind = $tool eq 'Skill' ? 'skill' : 'agent';
  my $name = $kind eq 'skill' ? ($input->{skill} // $input->{command} // $input->{name}) : $input->{subagent_type};
  return () unless defined $name && !ref $name;
  $name =~ s{\A\s*/}{};
  $name =~ s/\s.*//s;
  return () if $name eq '';
  my $shown = $name =~ /\A[A-Za-z0-9._:-]{1,80}\z/ ? "\"$name\"" : 'asked for';
  if ($name =~ m{[/\\\0]|\.\.}) {
    return ('G17', "the $kind $shown names a path, so where it is defined cannot be told; it is refused");
  }
  for my $f (def_files($kind, $name, $project)) {
    my ($h, $e) = declares_hooks($f);
    return ('G17', "a definition of the $kind $shown $e, so whether it declares hooks cannot be told; it is refused; tell the owner") if defined $e;
    next unless $h;
    return ('G17', "the $kind $shown declares hooks in its frontmatter, which would run for the rest of the session outside the method's settings; it is refused; ask the owner to remove its hooks, or use another $kind");
  }
  return ();
}

1;
