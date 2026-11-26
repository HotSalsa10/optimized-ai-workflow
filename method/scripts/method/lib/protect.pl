#!/usr/bin/env perl
# The guard's protected files (G6, M132) and its effort warning (G12,
# M134), step 5.7 (docs/plans/step5.md, section 6.2; DECISIONS A50, A57).
# Loaded by lib/guard.pl with require; nothing runs when it is loaded.
#
# G6: Claude may read the method's installed files, its settings, and git's
# own config and hooks, never write them. The protected paths (set):
#   in the project (each of its worktrees): .claude/hooks/method/,
#     .claude/agents/method/, .claude/rules/method/, the method's skills
#     (.claude/skills/NAME/ for each NAME in @METHOD_SKILLS, step 6.3, and
#     since step 7.2 every .claude/skills/method-* entry, so a new method-
#     skill folder cannot be made in a session, by folder name only (RISKS
#     #24); step7.md S12),
#     .claude/method-local/, scripts/method/, .claude/settings.json,
#     .claude/settings.local.json;
#   in git's own folder: hooks/, config, config.worktree, and the method's
#     files there (method-*), also in each worktree's own folder; the folder
#     core.hooksPath names; every config file git reads (its --show-origin);
#   in the home folder: ~/.claude/settings*.json, ~/.claude/agents/,
#     skills/, commands/, and dev-mods/ and plugins/, where Claude Code
#     loads mods and plugins from (@HOME_DIRS; also under
#     CLAUDE_CONFIG_DIR; step 6b.4), ~/.gitconfig, ~/.config/git/;
#   on the machine: /etc/gitconfig, and the managed settings folders
#     (/etc/claude-code, /Library/Application Support/ClaudeCode,
#     C:\Program Files\ClaudeCode, C:\ProgramData\ClaudeCode).
# A path is compared after resolve: backslashes read as /, C: as /c, ~ as
# the home folder, made absolute, every link followed and . and .. read as
# the file system reads them; in any letter case where the file system
# folds case (A36).
#
#   Protect::judge_bash(CMDS, DIRS, PROJECT) () or ('G6', TEXT): CMDS are
#     the reader's commands (lib/shell.pl), DIRS the folder each runs in
#     (Guard::cmd_dirs; undef: judged as the project's). A call that names
#     a protected path, as a path or, in an inline program or the text
#     piped into an interpreter, as text, may only read: every command in
#     it must be on the read-only list or one of the method's own scripts
#     (bash scripts/method/NAME.sh), and no output may be redirected into
#     a protected path. A copy, move, link or install is judged by the path
#     it would write. A recursive copy, rsync, tar or unzip extraction,
#     patch, recursive delete, find -delete or -exec, or move of a folder,
#     into or of a folder that holds a protected path (the repository's
#     top folder too) is refused.
#   Protect::judge_file(PATH, BASE, PROJECT) () or ('G6', TEXT): an edit
#     tool's file.
#   Protect::judge_mcp(TOOL, INPUT, BASE, PROJECT) () or ('G6', TEXT): an
#     MCP tool whose name does not read, given a protected path.
#   Protect::writes(CMDS) 1 when a command in CMDS may write (G6 judges
#     only such calls), else 0. Protect::call_writes(TOOL, CMDS) 1 when a
#     call of TOOL may write as G6 counts it: Bash or Monitor whose
#     commands write, an edit tool, an MCP tool whose name does not read.
#     gate-receipt's write marks are made for these (step 5b.2, B8).
#   Protect::git_versions(DIR, SUB, WORDS, PROJECT) () or ('G6', TEXT): a
#     switch, checkout, merge, cherry-pick, revert or worktree add that
#     would leave a protected file at a version that is neither HEAD's nor
#     the remote main's.
#   Protect::effort(IN, PROJECT) TEXT or undef (G12): the session's first
#     main-session tool call at an effort below the one the project's
#     profile sets gets one warning: the lock's profile line and that row's
#     effortLevel in scripts/method/profiles.tsv (lib/lock.pl; step 7.3,
#     step7.md S7); xhigh when there is no lock, or when the lock or the
#     row cannot be read.
#   Protect::resolve(WORD, BASE) the path WORD names, as above, or undef.
#   @Protect::METHOD_SKILLS the method's skill folders, by name;
#     Protect::skills_re() the names of .claude/skills/ entries G6 keeps,
#     as a regex (for guard.pl).
package Protect;
use strict;
use warnings;
use Cwd ();
use File::Basename qw(dirname basename);
use File::Glob qw(bsd_glob GLOB_QUOTE GLOB_NOSORT);
use File::Spec;

my $lib = dirname(File::Spec->rel2abs(__FILE__));
require File::Spec->catfile($lib, 'git.pl');

# 1 when the file system folds letter case (found once, by looking)
our $FOLD;

# the method's skills, each a folder .claude/skills/NAME/ (step 6.3; docs/
# plans/step6.md S10). scripts/dev/lint-prompts.sh checks that it names
# exactly the method's skill folders, each of which starts with method-.
# Since step 7.2 G6 keeps every .claude/skills/ entry whose name starts
# with method- (step7.md S12), so a new method- skill folder cannot be made
# in a session (by folder name only: a SKILL.md naming itself method-NAME,
# or a .claude/commands/method-NAME.md, is a known limit, RISKS #24): a
# deep prefix entry in set, .claude/skills in @SPECS (the
# version check) with the names kept(), a text form in text_re, and a
# watched path in guard.pl's $WATCHED_PATH, which reads skills_re from
# here. A project's own skills, named otherwise, stay editable.
our @METHOD_SKILLS = qw(method-start method-plan method-design method-finish method-setup);

# the folders of the Claude Code folder (~/.claude, and CLAUDE_CONFIG_DIR
# when set) that hold what a session loads: its agents, skills and
# commands, and the mods and plugins that run inside Claude Code, outside
# the method's checks (step 6b.4; docs/plans/step6b.md item 19). Each is
# [folder, what the refusal calls it]; one list for the folders, the real
# folder behind each link in them, and the text forms (home_re)
our @HOME_DIRS = (['agents', 'agents'], ['skills', 'skills'], ['commands', 'commands'], ['dev-mods', 'mods'], ['plugins', 'plugins']);

# the folders of @HOME_DIRS as one regex alternation, for text_re, each
# name whole: it ends where the folder's name ends (no letter, digit, _, -
# or . follows), so ~/.claude/dev-mods-old is not one
# (step 6b.4's check). A run of dots and spaces may come first, as Windows
# drops them from the end of a folder's name: ~/.claude/agents./x opens
# ~/.claude/agents/x there, while skills.bak stays another folder
sub home_re { return '(?:' . join('|', map { quotemeta $_->[0] } @HOME_DIRS) . ')[. ]*(?![A-Za-z0-9_.-])' }

# the method's skills as one regex: a name that starts with method- (every
# name on @METHOD_SKILLS does, which lint-prompts checks), the prefix G6
# keeps since step 7.2 (step7.md S12)
sub skills_re { return 'method-' }

# a string as the bytes a file system sees: text decoded from the hook's
# JSON input is in characters, while paths from the environment and from
# git are in bytes, and the two never compare equal
sub bytes {
  my ($s) = @_;
  return $s unless defined $s;
  utf8::encode($s) if utf8::is_utf8($s);
  return $s;
}

sub slashes {
  my ($p) = @_;
  $p = bytes($p);
  $p =~ tr{\\}{/};
  $p =~ s{\A([A-Za-z]):(?=/|\z)}{'/' . lc $1}e;
  return $p;
}

sub home {
  my $h = $ENV{HOME};
  return undef unless defined $h && $h ne '';
  return slashes($h);
}

# physical PATH: an absolute PATH with every link in its existing part
# followed and . and .. read as the file system reads them; the part that
# does not exist is read as written
sub physical {
  my ($p) = @_;
  no warnings 'newline';    # a word with a line break in it is a path too
  my @parts = grep { $_ ne '' && $_ ne '.' } split m{/+}, $p;
  my $cur = '';
  my $hops = 0;
  while (@parts) {
    my $c = shift @parts;
    if ($c eq '..') { $cur =~ s{/[^/]*\z}{}; next }
    my $next = "$cur/$c";
    if (-l $next) {
      return undef if ++$hops > 40;
      my $t = readlink $next;
      return undef unless defined $t;
      $t = slashes($t);
      unshift @parts, grep { $_ ne '' && $_ ne '.' } split m{/+}, $t;
      $cur = '' if $t =~ m{\A/};
      next;
    }
    $cur = $next;
  }
  return $cur eq '' ? '/' : $cur;
}

# the value of the variable NAME at the start of a word ($HOME, $PWD,
# $CLAUDE_PROJECT_DIR), as the shell reads it in the folder BASE, or undef
my $START_VAR = qr/\A\$(?:\{(HOME|PWD|CLAUDE_PROJECT_DIR)\}|(HOME|PWD|CLAUDE_PROJECT_DIR)\b)/;
sub start_var {
  my ($name, $base) = @_;
  my $v = $name eq 'HOME' ? home() : $name eq 'PWD' ? $base : $ENV{CLAUDE_PROJECT_DIR};
  return defined $v && $v ne '' ? slashes($v) : undef;
}

sub resolve {
  my ($w, $base) = @_;
  return undef unless defined $w && $w ne '' && $w !~ /\0/;
  my $p = slashes($w);
  $base = bytes($base);
  # (a path that starts with $HOME, $PWD or $CLAUDE_PROJECT_DIR; 5.7
  # repair loop 1)
  if ($p =~ s/$START_VAR//) {
    my $v = start_var(defined $1 ? $1 : $2, $base);
    return undef unless defined $v;
    $p = $v . $p;
  }
  if ($p =~ m{\A~(?=/|\z)}) {
    my $h = home();
    return undef unless defined $h;
    $p = $h . substr($p, 1);
  }
  return undef if $p =~ m{\A~};    # ~user: not followed
  if ($p !~ m{\A/}) {
    return undef unless defined $base && $base ne '';
    $p = slashes($base) . "/$p";
  }
  return physical($p);
}

# the paths WORD names in the folder BASE: the path itself, and, when WORD
# holds *, ? or [, every path it matches, as the shell would expand it
# (at most 200; 5.7 repair loop 1)
sub glob_quote { my ($s) = @_; $s =~ s/([\\*?\[\]{}~])/\\$1/g; return $s }
sub paths {
  my ($w, $base) = @_;
  my $p = resolve($w, $base);
  my @out = defined $p ? ($p) : ();
  return @out unless defined $w && $w =~ /[*?\[]/ && $w !~ /\0/;
  my $pat = slashes($w);
  if ($pat =~ s/$START_VAR//) {
    my $v = start_var(defined $1 ? $1 : $2, bytes($base));
    return @out unless defined $v;
    $pat = glob_quote($v) . $pat;
  } elsif ($pat =~ s{\A~(?=/|\z)}{}) {
    my $h = home();
    return @out unless defined $h;
    $pat = glob_quote($h) . $pat;
  } elsif ($pat !~ m{\A/}) {
    return @out unless defined $base && $base ne '';
    $pat = glob_quote(slashes(bytes($base))) . "/$pat";
  }
  my @m = bsd_glob($pat, GLOB_QUOTE | GLOB_NOSORT);
  splice @m, 200 if @m > 200;
  push @out, grep { defined } map { physical($_) } @m;
  return @out;
}

# does the file system fold letter case? Looked at once, at DIR: the same
# folder under the other case of its last name with a letter
sub folds {
  my ($dir) = @_;
  return $FOLD if defined $FOLD;
  my @p = split m{/}, $dir;
  for my $i (reverse 0 .. $#p) {
    next unless $p[$i] =~ /[A-Za-z]/;
    (my $sw = $p[$i]) =~ tr/a-zA-Z/A-Za-z/;
    my @q = @p;
    $q[$i] = $sw;
    my $other = join '/', @q;
    my @a = stat $dir;
    my @b = stat $other;
    return $FOLD = (@a && @b && $a[0] == $b[0] && $a[1] == $b[1]) ? 1 : 0;
  }
  return $FOLD = ($^O =~ /\A(?:darwin|MSWin32|msys|cygwin)\z/) ? 1 : 0;
}

sub key { my ($p) = @_; return $FOLD ? lc $p : $p }

my %SET;
# set PROJECT: the protected paths, each { path, kind (dir, file or
# prefix), name (a start of a file name, for prefix), what }
sub set {
  my ($project) = @_;
  $project = '.' unless defined $project && $project ne '';
  return $SET{$project} if $SET{$project};
  my @s;
  # (a relative path, as git gives a settings file's, is read from the
  # project, not from the folder the hook runs in; 5.7 repair loop 1)
  # (DEEP, for a prefix: what lies below an entry the prefix names counts
  # too)
  my $add = sub {
    my ($p, $kind, $what, $name, $deep) = @_;
    return unless defined $p && $p ne '';
    my $r = physical(slashes($p) =~ m{\A/} ? slashes($p) : File::Spec->rel2abs(slashes($p), File::Spec->rel2abs(slashes($project))));
    push @s, { path => $r, kind => $kind, what => $what, name => $name, deep => $deep } if defined $r;
  };
  my $proj = physical(File::Spec->rel2abs(slashes($project)));
  folds($proj) if defined $proj;
  my ($st, $out) = Git::run('-C', $project, 'rev-parse', '--show-toplevel', '--git-common-dir');
  my ($top, $common) = $st == 0 ? split(/\n/, $out) : ();
  my @tops = grep { defined && $_ ne '' } ($top, $proj);
  if ($st == 0) {
    $common = File::Spec->rel2abs($common, $project) if defined $common;
    my ($wst, $wout) = Git::run('-C', $project, 'worktree', 'list', '--porcelain');
    if ($wst == 0) { push @tops, map { /\Aworktree (.+)\z/ ? $1 : () } split /\n/, $wout }
  }
  my %seen;
  for my $t (grep { !$seen{$_}++ } @tops) {
    $add->("$t/.claude/hooks/method", 'dir', "the method's hooks (.claude/hooks/method/)");
    $add->("$t/.claude/agents/method", 'dir', "the method's agents (.claude/agents/method/)");
    $add->("$t/.claude/rules/method", 'dir', "the method's rules (.claude/rules/method/)");
    $add->("$t/.claude/skills", 'prefix', "the method's skills (.claude/skills/method-*)", 'method-', 1);
    $add->("$t/.claude/method-local", 'dir', "the owner's own lists (.claude/method-local/)");
    $add->("$t/scripts/method", 'dir', "the method's scripts (scripts/method/)");
    $add->("$t/.claude/settings.json", 'file', "the project's settings (.claude/settings.json)");
    $add->("$t/.claude/settings.local.json", 'file', "the project's local settings (.claude/settings.local.json)");
  }
  if (defined $common && $common ne '') {
    $add->("$common/hooks", 'dir', "git's hooks (.git/hooks/)");
    for my $g ($common, glob(quotemeta($common) . '/worktrees/*')) {
      $add->("$g/config", 'file', "git's settings (.git/config)");
      $add->("$g/config.worktree", 'file', "git's settings (.git/config.worktree)");
      $add->($g, 'prefix', "the method's files in git's folder (.git/method-*)", 'method-');
    }
    # where the remote's main stands, which the method's checks compare
    # against (5.7 repair loop 1)
    $add->("$common/refs/remotes", 'dir', "git's record of the remote's branches (.git/refs/remotes/)");
    $add->("$common/packed-refs", 'file', "git's record of branches (.git/packed-refs)");
    # every config file git reads, and the hooks folder it is told to use
    my ($cst, $cout) = Git::run('-C', $project, 'config', '--show-origin', '--null', '--list');
    if ($cst == 0) {
      my $hp;
      my @f = split /\0/, $cout;
      for (my $i = 0; $i + 1 <= $#f; $i += 2) {
        my ($origin, $kv) = @f[$i, $i + 1];
        my $from = $origin =~ /\Afile:(.+)\z/s ? $1 : undef;
        $from = File::Spec->rel2abs(slashes($from), File::Spec->rel2abs(slashes($project))) if defined $from && slashes($from) !~ m{\A/};
        $add->($from, 'file', "a git settings file") if defined $from;
        $hp = $1 if $kv =~ /\Acore\.hookspath\n(.*)\z/si;
        # a file an include names, also while it is empty or missing (read
        # from the folder of the file that names it)
        if ($kv =~ /\Ainclude(?:if\..*)?\.path\n(.+)\z/si) {
          my $inc = $1;
          $inc =~ s{\A~(?=/|\z)}{home() // '~'}e;
          $inc = dirname(slashes($from)) . "/$inc" if defined $from && $inc !~ m{\A/} && $inc !~ m{\A[A-Za-z]:};
          $add->($inc, 'file', "a git settings file") if $inc =~ m{\A/} || $inc =~ m{\A[A-Za-z]:};
        }
      }
      if (defined $hp && $hp ne '') {
        $hp =~ s{\A~(?=/|\z)}{home() // '~'}e;
        $add->(($hp =~ m{\A/} || $hp =~ m{\A[A-Za-z]:}) ? $hp : "$top/$hp", 'dir', "git's hooks (core.hooksPath)") if defined $top;
      }
    }
  }
  my $h = home();
  if (defined $h) {
    my @cfg = ("$h/.claude");
    push @cfg, $ENV{CLAUDE_CONFIG_DIR} if defined $ENV{CLAUDE_CONFIG_DIR} && $ENV{CLAUDE_CONFIG_DIR} ne '';
    for my $c (@cfg) {
      $add->($c, 'prefix', "your Claude Code settings (~/.claude/settings*.json)", 'settings');
      $add->("$c/$_->[0]", 'dir', "your Claude Code $_->[1] (~/.claude/$_->[0]/)") for @HOME_DIRS;
      # a settings file, agent, skill, command, mod or plugin that is a
      # link: its real path too (5.7 repair loop 1)
      my $q = glob_quote(slashes($c));
      $add->($_, 'file', "your Claude Code settings (~/.claude/settings*.json)") for grep { -l } bsd_glob("$q/settings*.json", GLOB_QUOTE | GLOB_NOSORT);
      for my $d (@HOME_DIRS) {
        $add->($_, 'dir', "your Claude Code $d->[1] (~/.claude/$d->[0]/)") for grep { -l } bsd_glob("$q/$d->[0]/*", GLOB_QUOTE | GLOB_NOSORT);
      }
    }
    $add->("$h/.gitconfig", 'file', "your git settings (~/.gitconfig)");
    my $xdg = defined $ENV{XDG_CONFIG_HOME} && $ENV{XDG_CONFIG_HOME} ne '' ? $ENV{XDG_CONFIG_HOME} : "$h/.config";
    $add->("$xdg/git", 'dir', "your git settings (~/.config/git/)");
  }
  for my $v (qw(GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM)) {
    $add->($ENV{$v}, 'file', "a git settings file") if defined $ENV{$v} && $ENV{$v} ne '';
  }
  $add->('/etc/gitconfig', 'file', "the machine's git settings (/etc/gitconfig)");
  $add->($_, 'dir', "the managed Claude Code settings") for '/etc/claude-code', '/Library/Application Support/ClaudeCode', 'C:/Program Files/ClaudeCode', 'C:/ProgramData/ClaudeCode';
  return $SET{$project} = { list => \@s, tops => [grep { !$seen{"t:$_"}++ } map { physical($_) // () } @tops] };
}

# the protected entry PATH is or is in, or undef
sub protected {
  my ($path, $set) = @_;
  return undef unless defined $path;
  my $k = key($path);
  for my $e (@{ $set->{list} }) {
    my $ek = key($e->{path});
    if ($e->{kind} eq 'dir') { return $e if $k eq $ek || index($k, "$ek/") == 0 }
    elsif ($e->{kind} eq 'file') { return $e if $k eq $ek }
    else {
      my $n;
      if (key(dirname($path)) eq $ek) { $n = key(basename($path)) }
      elsif ($e->{deep} && index($k, "$ek/") == 0) { ($n) = substr($k, length($ek) + 1) =~ m{\A([^/]+)/} }
      next unless defined $n;
      return $e if index($n, key($e->{name})) == 0 && ($e->{name} ne 'settings' || $n =~ /\.json\z/);
    }
  }
  return undef;
}

# the protected entry that lies below the folder PATH (PATH holds it), or
# undef; a prefix's entries lie in the folder its path names
sub above {
  my ($path, $set) = @_;
  return undef unless defined $path;
  my $k = key($path);
  $k = '' if $k eq '/';
  for my $e (@{ $set->{list} }) {
    my $ek = key($e->{path});
    return $e if index($ek, "$k/") == 0 || ($e->{kind} eq 'prefix' && $ek eq $k);
  }
  return undef;
}

# the commands that only read (with the forms of them that write left out
# in read_only)
my %READ = map { $_ => 1 } qw(cat head tail grep egrep fgrep ls wc diff cmp stat file sha256sum sha1sum sha512sum shasum md5sum sort uniq
  cut tr nl od xxd jq cd pwd test [ [[ realpath readlink basename dirname sed find echo printf true false);
# (git add changes only git's index, never a file; 5.7 repair loop 1)
my %GIT_READ = map { $_ => 1 } qw(status log diff show blame ls-files ls-tree cat-file rev-parse grep shortlog describe rev-list whatchanged
  add for-each-ref show-ref name-rev merge-base check-ignore check-attr var version help count-objects cherry range-diff);
# carriers: their inner command is a command of its own (lib/shell.pl)
my %CARRIER = map { $_ => 1 } qw(nohup time command builtin exec nice ionice sudo doas stdbuf setsid chronic caffeinate timeout env eval);

sub name_of {
  my ($w) = @_;
  (my $n = $w // '') =~ s{.*[/\\]}{};
  $n =~ s/\.exe\z//i;
  return $n;
}

# a name safe to show in a refusal
sub shown { my ($n) = @_; return $n =~ /\A[A-Za-z0-9._+\[-]{1,40}\z/ ? $n : 'this command' }

sub positionals {
  my ($w, $takes) = @_;
  my @pos;
  my $i = 1;
  while ($i <= $#$w) {
    my $x = $w->[$i++];
    if ($x eq '--') { push @pos, @$w[$i .. $#$w]; last }
    if ($x =~ /\A-./) { $i++ if $takes && $x =~ $takes; next }
    push @pos, $x;
  }
  return @pos;
}

# sed's WORDS: (in place, a script from a file, the scripts), its options
# read as sed reads them, long ones in any shortened form
sub sed_parse {
  my (undef, @w) = @_;
  my ($inplace, $file, @scripts, @pos) = (0, 0);
  while (@w) {
    my $x = shift @w;
    if ($x eq '--') { push @pos, @w; last }
    if ($x =~ /\A--/) {
      if ($x =~ /\A--i/) { $inplace = 1 }
      elsif ($x =~ /\A--fi/) { $file = 1 }
      elsif ($x =~ /\A--e[a-z-]*=(.*)\z/s) { push @scripts, $1 }
      elsif ($x =~ /\A--e/) { push @scripts, shift(@w) // '' }
      elsif ($x =~ /\A--l[a-z-]*\z/) { shift @w }
      next;
    }
    if ($x =~ /\A-(.+)\z/s) {
      my @l = split //, $1;
      while (defined(my $l = shift @l)) {
        if ($l eq 'i') { $inplace = 1; last }
        if ($l eq 'f') { $file = 1; last }
        if ($l eq 'e') { push @scripts, @l ? join('', @l) : (shift(@w) // ''); last }
        if ($l eq 'l') { shift @w unless @l; last }
      }
      next;
    }
    push @pos, $x;
  }
  push @scripts, $pos[0] if !@scripts && !$file && @pos;
  return ($inplace, $file, @scripts);
}

# does the sed script S only print, delete, substitute and the like: no w,
# W, r, R, e, a, i or c, and nothing else it cannot read? (5.7 repair loop
# 1: a list of what is plain, as sed's addresses and commands have many
# forms)
sub sed_plain {
  my ($s) = @_;
  my ($i, $n) = (0, length $s);
  my $addr = sub {
    if (substr($s, $i) =~ /\A(?:[0-9]+(?:~[0-9]+)?|\$)/) { $i += length $&; return 1 }
    return 0 unless substr($s, $i, 1) eq '/';
    my $j = $i + 1;
    while ($j < $n && substr($s, $j, 1) ne '/') { $j++ if substr($s, $j, 1) eq '\\'; $j++ }
    return 0 if $j >= $n;
    $i = $j + 1;
    $i++ while $i < $n && substr($s, $i, 1) =~ /[IM]/;
    return 1;
  };
  while ($i < $n) {
    my $c = substr($s, $i, 1);
    if ($c =~ /[\s;{}]/) { $i++; next }
    if ($addr->()) {
      if (substr($s, $i, 1) eq ',') {
        $i++;
        if (substr($s, $i) =~ /\A[+~][0-9]+/) { $i += length $& }
        elsif (!$addr->()) { return 0 }
      }
      $i++ while $i < $n && substr($s, $i, 1) =~ /[ \t!]/;
      next;
    }
    if ($c =~ /[pdqQ=lnNPDgGhHxzF]/) { $i++; next }
    if ($c eq '#' || $c eq ':' || $c =~ /[btT]/) {
      # a comment, a label, a branch to one: to the end of the line or ;
      my $e = $c eq '#' ? index($s, "\n", $i) : do { my $k = $i; $k++ while $k < $n && substr($s, $k, 1) !~ /[;\n]/; $k };
      $i = $e < 0 ? $n : $e;
      next;
    }
    if ($c eq 's' || $c eq 'y') {
      my $d = substr($s, $i + 1, 1);
      return 0 if $d eq '' || $d =~ /[\s\\]/;
      my ($j, $parts) = ($i + 2, 0);
      while ($j < $n && $parts < 2) {
        my $ch = substr($s, $j, 1);
        if ($ch eq '\\') { $j += 2; next }
        $parts++ if $ch eq $d;
        $j++;
      }
      return 0 if $parts < 2;
      $i = $j;
      $i += length $1 if $c eq 's' && substr($s, $i) =~ /\A([gpiImM0-9]*)/;
      next;
    }
    return 0;
  }
  return 1;
}

# find's -exec, -execdir, -ok and -okdir commands, each as its words
sub find_execs {
  my @a = @_;
  my @ex;
  for (my $i = 0; $i <= $#a; $i++) {
    next unless $a[$i] =~ /\A-(?:exec|execdir|ok|okdir)\z/;
    my @c;
    $i++;
    while ($i <= $#a && $a[$i] ne ';' && $a[$i] ne '+') { push @c, $a[ $i++ ] }
    push @ex, \@c;
  }
  return @ex;
}

# is the simple command C one that only reads?
sub read_only {
  my ($c, $depth) = @_;
  $depth //= 0;
  return 0 if $depth > 4;
  my @w = @{ $c->{words} };
  return 1 unless @w;
  my $n = name_of($w[0]);
  # xargs running a command that only reads (5.7 repair loop 1)
  if ($n eq 'xargs') {
    my $i = 1;
    while ($i <= $#w && $w[$i] =~ /\A-/) {
      my $o = $w[ $i++ ];
      last if $o eq '--';
      $i++ if $o =~ /\A-[aEdILnPs]\z/ || $o =~ /\A--(?:arg-file|delimiter|eof|max-lines|max-args|max-procs|max-chars|replace|process-slot-var)\z/;
    }
    return $i > $#w ? 1 : read_only({ words => [@w[$i .. $#w]] }, $depth + 1);
  }
  # python -m json.tool reading one file (a second one is its output)
  if ($n =~ /\Apython[0-9.]*\z/ && @w >= 3 && $w[1] eq '-m' && $w[2] eq 'json.tool') {
    my @p;
    for (my $i = 3; $i <= $#w; $i++) {
      if ($w[$i] eq '--indent') { $i++; next }
      push @p, $w[$i] unless $w[$i] =~ /\A-/;
    }
    return @p <= 1 ? 1 : 0;
  }
  if ($n eq 'git') {
    my $i = 1;
    while ($i <= $#w && $w[$i] =~ /\A-/) { $i += ($w[$i] =~ /\A-[Cc]\z/) ? 2 : 1 }
    # (--output writes a file, whatever the subcommand; 5.7 repair loop 1)
    return 0 if grep { /\A--output(?:=|\z)/ } @w;
    return defined $w[$i] && $GIT_READ{ $w[$i] } ? 1 : 0;
  }
  return 0 unless $READ{$n};
  my @a = @w[1 .. $#w];
  if ($n eq 'sed') {
    # in place, a script from a file, or a script that is not plain
    # (5.7 repair loop 1: sed's own reading of its options and scripts)
    my ($inplace, $file, @scripts) = sed_parse(@w);
    return 0 if $inplace || $file || grep { !sed_plain($_) } @scripts;
  }
  # (sort's --output and --compress-program, in any shortened form)
  return 0 if $n eq 'sort' && grep { /\A-[A-Za-z]*o/ || /\A--(?:o|com)/ } @a;
  if ($n eq 'find') {
    return 0 if grep { /\A-(?:delete|fprint|fprint0|fprintf|fls)\z/ } @a;
    # (-exec of a command that only reads, such as grep, reads; 5.7 repair
    # loop 1)
    for my $e (find_execs(@a)) { return 0 unless @$e && read_only({ words => $e }, $depth + 1) }
  }
  return 0 if $n eq 'xxd' && (grep({ /\A-r/ } @a) || positionals(\@w, qr/\A-[cglson]\z/) > 1);
  return 0 if $n eq 'uniq' && positionals(\@w, qr/\A-[fsw]\z/) > 1;
  return 0 if $n eq 'file' && grep { /\A-[A-Za-z]*C/ || /\A--compile/ } @a;
  return 1;
}

# is C one of the method's own scripts, run as bash or sh followed by its
# path (scripts/method/NAME.sh in one of the project's worktrees)?
sub method_script {
  my ($c, $base, $set) = @_;
  my @w = @{ $c->{words} };
  return 0 unless @w;
  my $n = name_of($w[0]);
  my $script = ($n eq 'bash' || $n eq 'sh') ? $w[1] : $w[0];
  return 0 unless defined $script && $script !~ /\A-/ && $script =~ m{/};
  my $p = resolve($script, $base);
  return 0 unless defined $p && -f $p && $p =~ m{/([A-Za-z0-9_-]+)\.sh\z};
  for my $t (@{ $set->{tops} }) {
    return 1 if key(dirname($p)) eq key("$t/scripts/method");
  }
  return 0;
}

# (>& to a word that is not a number writes that file; 5.7 repair loop 1)
sub is_write_redir { my ($op) = @_; return $op =~ /\A[0-9]*(?:>|>>|>\||<>|&>|&>>|>&)\z/ }

# the text forms of the protected paths, for code an interpreter runs
sub text_re {
  my ($set) = @_;
  # (a deep prefix by its path and name: the folder it is in holds other
  # files too)
  my $abs = join '|', map { quotemeta($_->{deep} ? "$_->{path}/$_->{name}" : $_->{path}) } @{ $set->{list} };
  my $re = q!(?:\A|[\s'"=:(/,\[{])\.claude/(?:hooks/method|agents/method|rules/method|method-local|settings(?:\.local)?\.json)!
    . q!|(?:\A|[\s'"=:(/,\[{])\.claude/skills/! . skills_re()
    . q!|(?:\A|[\s'"=:(,\[{])(?:\./)?scripts/method\b|\.git/(?:hooks|config)\b|\.gitconfig\b|\.config/git\b|managed-settings|ClaudeCode!
    . q!|(?:~|HOME\}?)/\.claude/! . home_re() . q!|\.git/(?:method-|refs/remotes\b|packed-refs\b)!;
  $re .= "|$abs" if $abs ne '';
  return $FOLD ? qr/$re/i : qr/$re/;
}

my $NO = "; the method's files, its settings and git's own config and hooks are the owner's to change: read them with cat, grep or sed -n, or tell the owner what you needed";

# writes CMDS: 1 when a command in CMDS may write: it is not on the
# read-only list, or it redirects its output into a file
sub writes {
  my ($cmds) = @_;
  for my $c (@$cmds) {
    return 1 if !read_only($c) || grep { is_write_redir($_->[0]) && $_->[1] !~ m{\A/dev/(?:null|stdout|stderr|tty|fd/[0-9]+)\z} && $_->[1] !~ /\A[0-9-]\z/ } @{ $c->{redirs} || [] };
  }
  return 0;
}

# an MCP tool whose name (the part after its last __) says it only reads
our $MCP_READS = qr/\A(?:read|get|list|search|find|view|stat|show|head|tail|cat|describe|query|fetch)/i;

# call_writes TOOL CMDS: 1 when a call of TOOL may write, as G6 counts it
# (CMDS: the reader's commands of a Bash or Monitor call)
sub call_writes {
  my ($tool, $cmds) = @_;
  return 0 unless defined $tool && !ref $tool;
  return writes($cmds || []) if $tool eq 'Bash' || $tool eq 'Monitor';
  return 1 if $tool =~ /\A(?:Edit|Write|MultiEdit|NotebookEdit)\z/;
  if ($tool =~ /\Amcp__/) {
    (my $short = $tool) =~ s/\A.*__//s;
    return $short =~ $MCP_READS ? 0 : 1;
  }
  return 0;
}

sub judge_bash {
  my ($cmds, $dirs, $project) = @_;
  # most calls only read: nothing to look up
  return () unless writes($cmds);
  my $set = set($project);
  my ($top) = @{ $set->{tops} };
  my $text = text_re($set);
  # every folder a command may run in: DIRS gives one folder, or a list
  # (Guard::cmd_dir_sets); one that cannot be told is the project's top
  # (final review of step 5: after a cd that may have failed, both the cd's
  # folder and the one before it; A69)
  my $bases = sub {
    my ($k) = @_;
    my $d = $dirs->[$k];
    my @b = ref $d eq 'ARRAY' ? @$d : ($d);
    my %seen;
    return grep { !$seen{$_}++ } map { defined $_ ? $_ : $top } (@b ? @b : (undef));
  };
  # 1. does the call name a protected path?
  my $named;
  for my $k (0 .. $#$cmds) {
    my $c = $cmds->[$k];
    my @w = @{ $c->{words} };
    my @look = (@w ? (($w[0] =~ m{[/\\]}) ? $w[0] : ()) : ());
    push @look, @w[1 .. $#w] if @w > 1;
    # (a for or select header names the paths its loop works on; final
    # review of step 5)
    push @look, @{ $c->{header_text} || [] };
    # a plain cp only reads its sources (not -l or -s, which make links);
    # where it writes is judged below (5.7 repair loop 1)
    if (@w && name_of($w[0]) eq 'cp' && !grep { /\A-[A-Za-z]*[ls]/ && !/\A--/ || /\A--(?:l|sy)/ } @w[1 .. $#w]) {
      my %src;
      $src{$_}++ for cp_sources(@w);
      @look = grep { !($src{$_} && $src{$_}-- > 0) } @look;
    }
    push @look, map { /\A[A-Za-z_][A-Za-z0-9_]*\+?=(.*)\z/s ? $1 : () } @{ $c->{assigns} || [] };
    push @look, map { $_->[1] } grep { $_->[0] !~ /\A[0-9]*<<[-<]?\z/ } @{ $c->{redirs} || [] };
    my @more = map { /\A[^=]*=(.+)\z/s ? $1 : () } @look;
    for my $base ($bases->($k)) {
      for my $x (@look, @more) {
        next if $x =~ m{\A[A-Za-z][A-Za-z0-9+.-]*://};
        for my $p (paths($x, $base)) {
          my $e = protected($p, $set);
          if ($e) { $named = $e; last }
        }
        last if $named;
      }
      last if $named;
    }
    last if $named;
    # an inline program's code, the text piped into an interpreter, or a
    # sed script that writes
    # (a sed script's text counts when the script itself writes, not when
    # sed -i edits the file it is given; 5.7 repair loop 1)
    my $sed_writes = 0;
    if (@w && name_of($w[0]) eq 'sed') {
      my (undef, $file, @scripts) = sed_parse(@w);
      $sed_writes = $file || grep { !sed_plain($_) } @scripts;
    }
    if ((grep { /\A(?:an inline program for|a pipe, here-document or here-string into) / } @{ $c->{unread} || [] }) || $sed_writes) {
      my $code = bytes(join "\n", @w, $c->{hbody} // '', $c->{pipe_from} // '');
      if ($code =~ $text) { $named = { what => "one of the method's protected files" }; last }
    }
  }
  if ($named) {
    for my $k (0 .. $#$cmds) {
      my $c = $cmds->[$k];
      my @bases = $bases->($k);
      my @w = @{ $c->{words} };
      for my $base (@bases) {
        for my $r (@{ $c->{redirs} || [] }) {
          next unless is_write_redir($r->[0]);
          # (a write to a path held in a variable, in a call that names a
          # protected path: where it lands cannot be told; final review of
          # step 5)
          if ((ref $r->[2] eq 'HASH' && ($r->[2]{var} || $r->[2]{subst})) || $r->[1] =~ /[\$`]/) {
            return ('G6', "this call names $named->{what}, which Claude may only read, and writes to a path held in a variable$NO");
          }
          my $e = protected(resolve($r->[1], $base), $set);
          return ('G6', "this call writes into $e->{what}, which Claude may only read$NO") if $e;
        }
      }
      next unless @w;
      next if $CARRIER{ name_of($w[0]) } || read_only($c) || !grep { !method_script($c, $_, $set) } @bases;
      next if ((name_of($w[0]) =~ /\A(?:bash|sh|dash|zsh|ksh)\z/) && grep { /\A-[A-Za-z]*c[A-Za-z]*\z/ } @w) && !grep { /\Aa pipe/ } @{ $c->{unread} || [] };
      return ('G6', "this call names $named->{what}, which Claude may only read, and " . shown(name_of($w[0])) . " is not on the read-only list$NO");
    }
    return ();
  }
  # 2. what each write lands on, from every folder it may run in
  for my $k (0 .. $#$cmds) {
    my $c = $cmds->[$k];
    my @w = @{ $c->{words} };
    next unless @w;
    my $n = name_of($w[0]);
    for my $base ($bases->($k)) {
      my $why = lands($c, $n, $base, $set) || listed($cmds, $k, $base, $set);
      return ('G6', $why . $NO) if $why;
    }
  }
  return ();
}

# listed CMDS K BASE SET: xargs running a command that writes, on the file
# names a recursive listing earlier in its pipeline found (grep -r, rg,
# git grep, git ls-files, find, ls -R) in a folder that holds a protected
# path: the reason, or undef. The usual bulk edit, grep -rl OLD . | xargs
# sed -i, would rewrite the method's files, as find -exec would (final
# review of step 5)
sub listed {
  my ($cmds, $k, $base, $set) = @_;
  my $c = $cmds->[$k];
  my @w = @{ $c->{words} };
  return undef unless name_of($w[0]) eq 'xargs' && $c->{piped} && !read_only($c);
  for (my $j = $k - 1; $j >= 0 && $cmds->[$j]{to_pipe}; $j--) {
    my @l = @{ $cmds->[$j]{words} };
    next unless @l;
    my $ln = name_of($l[0]);
    my @a = @l[1 .. $#l];
    my $recursive;
    if ($ln =~ /\A(?:grep|egrep|fgrep)\z/) { $recursive = grep { /\A-[A-Za-z]*[rR]/ && !/\A--/ || /\A--(?:recursive|dereference-recursive)\z/ || /\A--directories=recurse\z/ } @a }
    elsif ($ln =~ /\A(?:rg|ag|ack|fd|fdfind|find)\z/) { $recursive = 1 }
    elsif ($ln eq 'ls') { $recursive = grep { /\A-[A-Za-z]*R/ && !/\A--/ || $_ eq '--recursive' } @a }
    elsif ($ln eq 'git') {
      my ($sub) = grep { !/\A-/ } @a;
      $recursive = defined $sub && ($sub eq 'grep' || $sub eq 'ls-files');
    }
    next unless $recursive;
    # where it starts: the folders it is given, or the one it runs in
    my @start = grep { my $p = resolve($_, $base); defined $p && -d $p } grep { !/\A-/ } @a;
    if (!@start && $ln eq 'find') {
      # (find's paths come first, after its own options)
      my @b = @a;
      while (@b && $b[0] =~ /\A-(?:[HLP]+|D|O[0-9]*)\z/) { my $o = shift @b; shift @b if $o eq '-D' }
      for my $x (@b) { last if $x =~ /\A[-(!]/; push @start, $x }
    }
    @start = ('.') unless @start;
    for my $s (@start) {
      my $sp = resolve($s, $base);
      my $e = protected($sp, $set) || above($sp, $set);
      return "this xargs runs a command that writes on files a listing found in a folder that holds $e->{what}; run the listing in a subfolder, or name the files" if $e;
    }
  }
  return undef;
}

# a cp's sources: its positionals but the last, or all of them with -t
my $CP_TAKES = qr/\A-[tSgmo]\z|\A--(?:target-directory|suffix|group|mode|owner)\z/;
sub cp_sources {
  my @w = @_;
  my @pos = positionals(\@w, $CP_TAKES);
  return @pos if grep { /\A-[A-Za-z]*?t/ && !/\A--/ || /\A--target-directory/ } @w[1 .. $#w];
  pop @pos;
  return @pos;
}

# does the write C makes land on a protected path, or recursively into a
# folder that holds one? The reason, or undef
sub lands {
  my ($c, $n, $base, $set) = @_;
  my @w = @{ $c->{words} };
  my @a = @w[1 .. $#w];
  my $R = sub { my ($p) = @_; resolve($p, $base) };
  my $flags = join '', map { /\A-([A-Za-z]+)\z/ ? $1 : () } grep { !/\A--/ } @a;
  my %long = map { /\A--([a-z-]+)/ ? ($1 => 1) : () } @a;
  if ($n =~ /\A(?:cp|mv|ln|install|rsync)\z/) {
    my $takes = $n eq 'cp' || $n eq 'mv' || $n eq 'ln' || $n eq 'install' ? $CP_TAKES : qr/\A-[efT]\z|\A--(?:rsh|exclude|include|filter|files-from|temp-dir|partial-dir|backup-dir|suffix|chmod|chown)\z/;
    my @pos = positionals(\@w, $takes);
    # the target folder: -t DIR, -tDIR, a cluster ending in t, or
    # --target-directory with = or a space (5.7 repair loop 1)
    my $tdir;
    if ($n ne 'rsync') {
      for my $i (0 .. $#a) {
        if ($a[$i] =~ /\A--target-directory=(.+)\z/s) { $tdir = $1 }
        elsif ($a[$i] eq '--target-directory' && defined $a[ $i + 1 ]) { $tdir = $a[ $i + 1 ] }
        elsif ($a[$i] =~ /\A-[A-Za-z]*?t(.*)\z/s && $a[$i] !~ /\A--/) {
          if ($1 ne '') { $tdir = $1 }
          elsif (defined $a[ $i + 1 ]) { $tdir = $a[ $i + 1 ]; @pos = grep { $_ ne $tdir } @pos }
        }
      }
    }
    return undef if !defined $tdir && @pos < 2;
    my $dest = defined $tdir ? $tdir : pop @pos;
    return undef if $n eq 'rsync' && $dest =~ m{\A[^/]*:};    # another machine
    my $dpath = $R->($dest);
    return undef unless defined $dpath;
    # (-T: the target is the path itself, never a folder to put things in)
    my $no_into = $n ne 'rsync' && ($flags =~ /T/ || $long{'no-target-directory'});
    my $into = !$no_into && (defined $tdir || @pos > 1 || -d $dpath || $dest =~ m{/\z});
    my $rec = $n eq 'rsync' || $flags =~ /[rRa]/ || $long{recursive} || $long{archive};
    for my $s (map { my $w = $_; map { [$w, $_] } paths($w, $base) } @pos) {
      my ($sw, $sp) = @$s;
      my $contents = $sw =~ m{/\.?\z};
      my $r = $into && !($contents && $rec) ? (defined $sp ? "$dpath/" . basename($sp) : undef) : $dpath;
      next unless defined $r;
      $r = physical($r);
      my $e = protected($r, $set);
      return "this $n writes into $e->{what}, which Claude may only read" if $e;
      my $dir_src = defined $sp && -d $sp;
      if (($rec || ($n eq 'mv' && $dir_src)) && ($e = above($r, $set))) {
        return "this $n puts a folder in place over one that holds $e->{what}; copy into a subfolder, or name the files one by one";
      }
      if ($n eq 'mv' && defined $sp && ($e = above($sp, $set) || protected($sp, $set))) {
        return "this mv moves a folder that holds $e->{what}";
      }
    }
    return undef;
  }
  if ($n eq 'tar') {
    my $x = (@a && $a[0] =~ /\A[A-Za-z]*x/ && $a[0] !~ /\A-/) || $flags =~ /x/ || $long{extract} || $long{get};
    return undef unless $x;
    # every folder it extracts into: -C DIR, -CDIR, a cluster ending in C,
    # --directory with = or a space (5.7 repair loop 1)
    my @t = ($base);
    for my $i (0 .. $#a) {
      if (($a[$i] eq '--directory' || $a[$i] =~ /\A-[A-Za-z]*C\z/) && defined $a[ $i + 1 ]) { push @t, $a[ $i + 1 ] }
      elsif ($a[$i] =~ /\A--directory=(.+)\z/s || $a[$i] =~ /\A-C(.+)\z/s) { push @t, $1 }
    }
    # (the folder it runs in is judged only when none is named)
    shift @t if @t > 1;
    for my $t (@t) {
      for my $tp (paths($t, $base)) {
        my $e = protected($tp, $set) || above($tp, $set);
        return "this tar extracts into a folder that holds $e->{what}; extract into a new subfolder" if $e;
      }
    }
    return undef;
  }
  # patch given the file it changes: that file, and its -o and -r files
  # (5.7 repair loop 1)
  if ($n eq 'patch') {
    my ($dir, @out, @pos) = ($base);
    for (my $i = 1; $i <= $#w; $i++) {
      my $x = $w[$i];
      if ($x =~ /\A-[BDFVYdgioprz]\z/) {
        my $v = $w[ ++$i ];
        next unless defined $v;
        push @out, $v if $x eq '-o' || $x eq '-r';
        $dir = $v if $x eq '-d';
        next;
      }
      if ($x =~ /\A-([or])(.+)\z/s || $x =~ /\A--(output|reject-file)=(.+)\z/s) { push @out, $2; next }
      if ($x =~ /\A-d(.+)\z/s || $x =~ /\A--directory=(.+)\z/s) { $dir = $1; next }
      next if $x =~ /\A-/;
      push @pos, $x;
    }
    my $d = resolve($dir, $base);
    if (@pos && defined $d && -f (resolve($pos[0], $d) // '')) {
      for my $f ($pos[0], @out) {
        my $e = protected(resolve($f, $d), $set);
        return "this patch writes into $e->{what}, which Claude may only read" if $e;
      }
      return undef;
    }
  }
  if ($n eq 'unzip' || $n eq 'patch') {
    # (its listing forms write nothing; a -dDIR word is not a cluster)
    return undef if $n eq 'unzip' && (join '', map { /\A-([A-Za-z]+)\z/ ? $1 : () } grep { !/\A-d/ } @a) =~ /[ltvZp]/;
    my @t = ($base);
    for my $i (0 .. $#a) {
      if (($a[$i] eq '-d' || $a[$i] eq '--directory') && defined $a[ $i + 1 ]) { push @t, $a[ $i + 1 ] }
      elsif ($a[$i] =~ /\A--directory=(.+)\z/s || $a[$i] =~ /\A-d(.+)\z/s) { push @t, $1 }
    }
    # (the last folder named is the one it uses; the folder it runs in is
    # judged only when none is named)
    shift @t if @t > 1;
    for my $t (@t) {
      for my $tp (paths($t, $base)) {
        my $e = protected($tp, $set) || above($tp, $set);
        return "this $n writes into a folder that holds $e->{what}; run it in a new subfolder" if $e;
      }
    }
    return undef;
  }
  if ($n eq 'rm' && ($flags =~ /[rR]/ || $long{recursive})) {
    for my $s (positionals(\@w)) {
      for my $sp (paths($s, $base)) {
        my $e = above($sp, $set);
        return "this rm deletes a folder that holds $e->{what}" if $e;
      }
    }
    return undef;
  }
  if ($n eq 'find' && !read_only($c)) {
    my @start;
    # (find's own options come before its paths: -H, -L, -P, -D WHAT, -O1;
    # 5.7 repair loop 1)
    my @b = @a;
    while (@b && $b[0] =~ /\A-(?:[HLP]+|D|O[0-9]*)\z/) { my $o = shift @b; shift @b if $o eq '-D' }
    for my $x (@b) { last if $x =~ /\A[-(!]/; push @start, $x }
    @start = ('.') unless @start;
    for my $s (@start) {
      for my $sp (paths($s, $base)) {
        my $e = protected($sp, $set) || above($sp, $set);
        return "this find deletes or runs a command in a folder that holds $e->{what}; start it in a subfolder" if $e;
      }
    }
    return undef;
  }
  if ($n eq 'git') {
    my $i = 1;
    # (git -C DIR: its paths are read from DIR; 5.7 repair loop 1)
    my $gbase = $base;
    while ($i <= $#w && $w[$i] =~ /\A-/) {
      if ($w[$i] eq '-C' && defined $w[ $i + 1 ]) {
        my $d = resolve($w[ $i + 1 ], $gbase);
        $gbase = $d if defined $d;
      }
      $i += ($w[$i] =~ /\A-[Cc]\z/) ? 2 : 1;
    }
    my $sub = $w[$i] // '';
    return undef unless $sub eq 'rm' || $sub eq 'mv';
    for my $s (grep { !/\A-/ } @w[$i + 1 .. $#w]) {
      for my $sp (paths($s, $gbase)) {
        my $e = protected($sp, $set) || above($sp, $set);
        return "this git $sub removes or moves a folder that holds $e->{what}" if $e;
      }
    }
  }
  return undef;
}

sub judge_file {
  my ($path, $base, $project) = @_;
  return () unless defined $path && !ref $path && $path ne '';
  my $set = set($project);
  my ($top) = @{ $set->{tops} };
  my $p = resolve($path, defined $base && $base ne '' ? $base : $top);
  my $e = protected($p, $set);
  return ('G6', "$e->{what} may not be changed by Claude, only read$NO") if $e;
  return ();
}

sub judge_mcp {
  my ($tool, $input, $base, $project) = @_;
  (my $short = $tool) =~ s/\A.*__//s;
  return () if $short =~ $MCP_READS;
  my @strings;
  my $walk;
  $walk = sub {
    my ($v, $depth) = @_;
    return if $depth > 8;
    if (ref $v eq 'HASH') { $walk->($_, $depth + 1) for values %$v }
    elsif (ref $v eq 'ARRAY') { $walk->($_, $depth + 1) for @$v }
    elsif (defined $v && !ref $v && length $v < 4096) { push @strings, $v }
  };
  $walk->($input, 0);
  undef $walk;
  my $set;
  for my $s (@strings) {
    # (a file:// address is the path it names; 5.7 repair loop 1)
    $s =~ s{\Afile://(?:localhost)?(?=/)}{}i;
    next unless $s =~ m{[/\\]|\A\.|\A~} && $s !~ m{\A[A-Za-z][A-Za-z0-9+.-]*://};
    $set ||= set($project);
    my ($top) = @{ $set->{tops} };
    my $e = protected(resolve($s, defined $base && $base ne '' ? $base : $top), $set);
    return ('G6', "this MCP tool is given $e->{what}, which Claude may only read$NO") if $e;
  }
  return ();
}

# the protected paths of the project's tracked tree (Git::run reads every
# path literally)
# (.claude/skills whole, as git reads every path literally: kept() leaves
# out the project's own skills)
my @SPECS = qw(.claude/hooks/method .claude/agents/method .claude/rules/method .claude/method-local scripts/method .claude/settings.json .claude/settings.local.json .claude/skills);

# kept PATHS: the paths G6 keeps among PATHS from @SPECS: under
# .claude/skills/, only the method- entries
sub kept {
  my ($skills, $method) = (key('.claude/skills/'), key('.claude/skills/method-'));
  return grep { my $k = key($_); index($k, $skills) != 0 || index($k, $method) == 0 } @_;
}

# the protected files whose version differs between commits A and B, or
# undef when that cannot be told
sub differ {
  my ($dir, $a, $b, @only) = @_;
  my @specs = @only ? @only : @SPECS;
  # (run at the top folder: git reads paths from the folder it runs in;
  # 5.7 repair loop 1)
  $dir = top_of($dir);
  return undef unless defined $dir;
  my ($st, $out) = Git::run('-C', $dir, 'diff', '--no-ext-diff', '--no-textconv', '--name-only', '-z', $a, $b, '--', @specs);
  return undef unless $st == 0;
  return [kept(grep { $_ ne '' } split /\0/, $out)];
}

# the top folder of the worktree DIR is in, or undef
sub top_of {
  my ($dir) = @_;
  my ($st, $out) = Git::run('-C', $dir, 'rev-parse', '--show-toplevel');
  my ($top) = $st == 0 ? split(/\n/, $out) : ();
  return defined $top && $top ne '' ? $top : undef;
}

sub git_versions {
  my ($dir, $sub, $rest, $project) = @_;
  my @r = @$rest;
  shift @r;    # the subcommand
  return () if grep { /\A--(?:abort|continue|quit|skip)\z/ } @r;
  my @pos;
  # the options that take the next word as their value
  my %val = map { $_ => 1 } qw(--strategy --strategy-option --create --force-create --orphan --reason --mainline --cleanup --gpg-sign);
  my $short = 'mXsFcCbB';
  for (my $i = 0; $i <= $#r; $i++) {
    my $x = $r[$i];
    # (after --, checkout reads paths; the others read their commits and
    # branches; 5.7 repair loop 1)
    if ($x eq '--') { push @pos, @r[ $i + 1 .. $#r ] unless $sub eq 'checkout'; last }
    if ($x =~ /\A--/) { $i++ if $val{$x}; next }
    if ($x =~ /\A-([A-Za-z]+)\z/) {
      # a cluster such as -qb: its first letter that takes a value takes
      # the rest of the cluster, or the next word
      my @l = split //, $1;
      while (my $l = shift @l) {
        next unless index($short, $l) >= 0;
        $i++ unless @l;
        last;
      }
      next;
    }
    next if $x =~ /\A-/;
    push @pos, $x;
  }
  my @targets;    # [commit whose versions would land, the paths it brings or undef]
  if ($sub eq 'switch' || $sub eq 'checkout' || $sub eq 'merge') {
    return () unless @pos;
    @targets = map { [$_] } ($sub eq 'merge' ? @pos : $pos[-1]);
  } elsif ($sub eq 'pull') {
    # (its own upstream as of the last fetch: what the pull itself fetches
    # is not seen; final review of step 5. With no upstream git refuses the
    # pull itself)
    my ($ust) = Git::run('-C', $dir, 'rev-parse', '--verify', '-q', '@{upstream}');
    return () unless $ust == 0;
    @targets = (['@{upstream}']);
  } elsif ($sub eq 'worktree') {
    return () unless @pos && $pos[0] eq 'add';
    @targets = ([@pos > 2 ? $pos[-1] : 'HEAD']);
  } elsif ($sub eq 'cherry-pick' || $sub eq 'revert') {
    my $top = top_of($dir);
    return ('G6', "whether this $sub changes the method's protected files cannot be told, so it is refused; tell the owner what you needed") unless defined $top;
    for my $cmt (@pos) {
      # the protected files the commit changes (against no files, for a
      # first commit)
      my ($st, $out) = Git::run('-C', $top, 'diff-tree', '--root', '--no-commit-id', '--no-ext-diff', '--no-textconv', '-r', '--name-only', '-z', $cmt, '--', @SPECS);
      my $ch = $st == 0 ? [kept(grep { $_ ne '' } split /\0/, $out)] : undef;
      return ('G6', "whether this $sub changes the method's protected files cannot be told, so it is refused; tell the owner what you needed") unless $ch;
      next unless @$ch;
      push @targets, [$sub eq 'revert' ? "$cmt^" : $cmt, $ch];
    }
  } else {
    return ();
  }
  # the remote's main (Git::main_ref reads the current folder's repository)
  my $main;
  my $old = Cwd::getcwd();
  if (chdir $dir) {
    my @m = eval { Git::main_ref() };
    $main = $m[0] if @m && defined $m[0];
    chdir $old if defined $old;
  }
  for my $t (@targets) {
    my ($cmt, $only) = @$t;
    my $d = differ($dir, 'HEAD', $cmt, $only ? @$only : ());
    return ('G6', "whether this $sub changes the method's protected files cannot be told, so it is refused; tell the owner what you needed") unless $d;
    next unless @$d;
    my $m = defined $main && $main ne '' ? differ($dir, $main, $cmt, @$d) : $d;
    return ('G6', "whether this $sub changes the method's protected files cannot be told, so it is refused; tell the owner what you needed") unless $m;
    next unless @$m;
    my $shown = $m->[0] =~ m{\A[A-Za-z0-9._/-]{1,200}\z} ? $m->[0] : 'a protected file';
    # (an old local branch is usually only behind the remote's main: the
    # way forward is a new branch from there; 5.7 repair loop 1)
    my $way = $sub eq 'switch' || $sub eq 'checkout' ? "; if that branch is only behind the remote's main, start a new branch from it instead (git switch -c NEW origin/main)" : '';
    return ('G6', "this $sub would bring $shown to a version that is neither this branch's nor the remote main's$way$NO");
  }
  return ();
}

# G12: the warning for the session's first main-session call below the
# profile's effort
sub effort {
  my ($in, $project) = @_;
  return undef unless ref $in eq 'HASH';
  return undef if defined $in->{agent_id} && !ref $in->{agent_id} && $in->{agent_id} ne '';
  my $e = $in->{effort};
  my $level = ref $e eq 'HASH' ? $e->{level} : $e;
  return undef unless defined $level && !ref $level && $level ne '';
  # (no profile sets more than xhigh, Lock::profiles, so xhigh and max
  # need no lock read)
  return undef if $level =~ /\A(?:xhigh|max)\z/;
  my ($want, $name, $below) = ('xhigh', undef, 1);
  if (defined $project && $project ne '' && eval { require File::Spec->catfile($lib, 'lock.pl'); 1 }) {
    my ($n, $row) = eval { Lock::profile($project) };
    if ($row) {
      my %rank;
      @rank{@Lock::EFFORTS} = 0 .. $#Lock::EFFORTS;
      ($want, $name) = ($row->{effortLevel}, $n);
      $below = !defined $rank{$level} || $rank{$level} < $rank{$want};
    }
  }
  return undef unless $below;
  my $shown = $level =~ /\A(?:low|medium|high)\z/ ? $level : 'not one the method knows';
  my $sid = defined $in->{session_id} && !ref $in->{session_id} ? $in->{session_id} : '';
  require Digest::SHA;
  my $hash = Digest::SHA::sha256_hex(bytes("effort\0$sid"));
  my $root = defined $project && $project ne '' ? $project : undef;
  if (defined $root) {
    require File::Spec->catfile($lib, 'log.pl');
    my ($lines) = eval { Log::lines($root, '.method/local/effort-warned') };
    return undef if $lines && grep { $_->[3] eq $hash } @$lines;
    # (the last 20 sessions, so sessions run side by side are each warned
    # once; 5.7 repair loop 1)
    eval { Log::append($root, '.method/local/effort-warned', 20, rule => 'G12', tool => 'effort', hash => $hash) };
  }
  my $under = defined $name ? "the $want that the project's profile ($name) sets" : "the method's xhigh";
  return "this session runs at effort $shown, below $under, so its work may be shallower than the method assumes; switch with /effort $want";
}

1;
