#!/usr/bin/env perl
# The guard's protected files (G6, M132) and its effort warning (G12,
# M134), step 5.7 (docs/plans/step5.md, section 6.2; DECISIONS A50, A57).
# Loaded by lib/guard.pl with require; nothing runs when it is loaded.
#
# G6: Claude may read the method's installed files, its settings, and git's
# own config and hooks, never write them. The protected paths (set):
#   in the project (each of its worktrees): .claude/hooks/method/,
#     .claude/agents/method/, .claude/rules/method/, .claude/method-local/,
#     scripts/method/, .claude/settings.json, .claude/settings.local.json;
#   in git's own folder: hooks/, config, config.worktree, and the method's
#     files there (method-*), also in each worktree's own folder; the folder
#     core.hooksPath names; every config file git reads (its --show-origin);
#   in the home folder: ~/.claude/settings*.json, ~/.claude/agents/,
#     skills/ and commands/ (also under CLAUDE_CONFIG_DIR), ~/.gitconfig,
#     ~/.config/git/;
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
#   Protect::git_versions(DIR, SUB, WORDS, PROJECT) () or ('G6', TEXT): a
#     switch, checkout, merge, cherry-pick, revert or worktree add that
#     would leave a protected file at a version that is neither HEAD's nor
#     the remote main's.
#   Protect::effort(IN, PROJECT) TEXT or undef (G12): the session's first
#     main-session tool call at an effort below xhigh gets one warning.
#   Protect::resolve(WORD, BASE) the path WORD names, as above, or undef.
package Protect;
use strict;
use warnings;
use Cwd ();
use File::Basename qw(dirname basename);
use File::Spec;

my $lib = dirname(File::Spec->rel2abs(__FILE__));
require File::Spec->catfile($lib, 'git.pl');

# 1 when the file system folds letter case (found once, by looking)
our $FOLD;

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

sub resolve {
  my ($w, $base) = @_;
  return undef unless defined $w && $w ne '' && $w !~ /\0/;
  my $p = slashes($w);
  $base = bytes($base);
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
  my $add = sub {
    my ($p, $kind, $what, $name) = @_;
    return unless defined $p && $p ne '';
    my $r = physical(slashes($p) =~ m{\A/} ? slashes($p) : File::Spec->rel2abs(slashes($p)));
    push @s, { path => $r, kind => $kind, what => $what, name => $name } if defined $r;
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
    # every config file git reads, and the hooks folder it is told to use
    my ($cst, $cout) = Git::run('-C', $project, 'config', '--show-origin', '--null', '--list');
    if ($cst == 0) {
      my $hp;
      my @f = split /\0/, $cout;
      for (my $i = 0; $i + 1 <= $#f; $i += 2) {
        my ($origin, $kv) = @f[$i, $i + 1];
        my $from = $origin =~ /\Afile:(.+)\z/s ? $1 : undef;
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
      $add->("$c/$_", 'dir', "your Claude Code $_ (~/.claude/$_/)") for qw(agents skills commands);
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
      next unless key(dirname($path)) eq $ek;
      my $n = key(basename($path));
      return $e if index($n, key($e->{name})) == 0 && ($e->{name} ne 'settings' || $n =~ /\.json\z/);
    }
  }
  return undef;
}

# the protected entry that lies below the folder PATH (PATH holds it), or
# undef
sub above {
  my ($path, $set) = @_;
  return undef unless defined $path;
  my $k = key($path);
  $k = '' if $k eq '/';
  for my $e (@{ $set->{list} }) {
    my $ek = key($e->{path});
    return $e if index($ek, "$k/") == 0;
  }
  return undef;
}

# the commands that only read (with the forms of them that write left out
# in read_only)
my %READ = map { $_ => 1 } qw(cat head tail grep egrep fgrep ls wc diff cmp stat file sha256sum sha1sum sha512sum shasum md5sum sort uniq
  cut tr nl od xxd jq cd pwd test [ [[ realpath readlink basename dirname sed find echo printf true false);
my %GIT_READ = map { $_ => 1 } qw(status log diff show blame ls-files ls-tree cat-file rev-parse grep shortlog describe rev-list whatchanged);
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

# is the simple command C one that only reads?
sub read_only {
  my ($c) = @_;
  my @w = @{ $c->{words} };
  return 1 unless @w;
  my $n = name_of($w[0]);
  if ($n eq 'git') {
    my $i = 1;
    while ($i <= $#w && $w[$i] =~ /\A-/) { $i += ($w[$i] =~ /\A-[Cc]\z/) ? 2 : 1 }
    return defined $w[$i] && $GIT_READ{ $w[$i] } ? 1 : 0;
  }
  return 0 unless $READ{$n};
  my @a = @w[1 .. $#w];
  if ($n eq 'sed') {
    return 0 if grep { /\A-[A-Za-z]*i/ || /\A--in-place/ } @a;
    # a script that writes (w, W, s///w) or runs a command (e, s///e)
    return 0 if grep { /(?:\A|[;\n{}])\s*(?:[0-9,\$]+|\/[^\/]*\/)?\s*[wWe](?:\s|\z)/ || m{s(.)(?:(?!\1).)*\1(?:(?!\1).)*\1[gpiImM0-9]*[we]} } @a;
  }
  return 0 if $n eq 'sort' && grep { /\A-[A-Za-z]*o/ || /\A--output/ } @a;
  return 0 if $n eq 'find' && grep { /\A-(?:exec|execdir|ok|okdir|delete|fprint|fprint0|fprintf|fls)\z/ } @a;
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

sub is_write_redir { my ($op) = @_; return $op =~ /\A[0-9]*(?:>|>>|>\||<>|&>|&>>)\z/ }

# the text forms of the protected paths, for code an interpreter runs
sub text_re {
  my ($set) = @_;
  my $abs = join '|', map { quotemeta $_->{path} } @{ $set->{list} };
  my $re = q!(?:\A|[\s'"=:(/,\[{])\.claude/(?:hooks/method|agents/method|rules/method|method-local|settings(?:\.local)?\.json)!
    . q!|(?:\A|[\s'"=:(,\[{])(?:\./)?scripts/method\b|\.git/(?:hooks|config)\b|\.gitconfig\b|\.config/git\b|managed-settings|ClaudeCode!;
  $re .= "|$abs" if $abs ne '';
  return $FOLD ? qr/$re/i : qr/$re/;
}

my $NO = "; the method's files, its settings and git's own config and hooks are the owner's to change: read them with cat, grep or sed -n, or tell the owner what you needed";

sub judge_bash {
  my ($cmds, $dirs, $project) = @_;
  # most calls only read: nothing to look up
  my $writes = 0;
  for my $c (@$cmds) {
    if (!read_only($c) || grep { is_write_redir($_->[0]) && $_->[1] !~ m{\A/dev/(?:null|stdout|stderr|tty|fd/[0-9]+)\z} && $_->[1] !~ /\A[0-9-]\z/ } @{ $c->{redirs} || [] }) { $writes = 1; last }
  }
  return () unless $writes;
  my $set = set($project);
  my ($top) = @{ $set->{tops} };
  my $text = text_re($set);
  # 1. does the call name a protected path?
  my $named;
  for my $k (0 .. $#$cmds) {
    my $c = $cmds->[$k];
    my $base = defined $dirs->[$k] ? $dirs->[$k] : $top;
    my @w = @{ $c->{words} };
    my @look = (@w ? (($w[0] =~ m{[/\\]}) ? $w[0] : ()) : ());
    push @look, @w[1 .. $#w] if @w > 1;
    push @look, map { /\A[A-Za-z_][A-Za-z0-9_]*\+?=(.*)\z/s ? $1 : () } @{ $c->{assigns} || [] };
    push @look, map { $_->[1] } grep { $_->[0] !~ /\A[0-9]*<<[-<]?\z/ } @{ $c->{redirs} || [] };
    my @more = map { /\A[^=]*=(.+)\z/s ? $1 : () } @look;
    for my $x (@look, @more) {
      next if $x =~ m{\A[A-Za-z][A-Za-z0-9+.-]*://};
      my $e = protected(resolve($x, $base), $set);
      if ($e) { $named = $e; last }
    }
    last if $named;
    # an inline program's code, the text piped into an interpreter, or a
    # sed script that writes
    if ((grep { /\A(?:an inline program for|a pipe, here-document or here-string into) / } @{ $c->{unread} || [] }) || (@w && name_of($w[0]) eq 'sed' && !read_only($c))) {
      my $code = bytes(join "\n", @w, $c->{hbody} // '', $c->{pipe_from} // '');
      if ($code =~ $text) { $named = { what => "one of the method's protected files" }; last }
    }
  }
  if ($named) {
    for my $k (0 .. $#$cmds) {
      my $c = $cmds->[$k];
      my $base = defined $dirs->[$k] ? $dirs->[$k] : $top;
      my @w = @{ $c->{words} };
      for my $r (@{ $c->{redirs} || [] }) {
        next unless is_write_redir($r->[0]);
        my $e = protected(resolve($r->[1], $base), $set);
        return ('G6', "this call writes into $e->{what}, which Claude may only read$NO") if $e;
      }
      next unless @w;
      next if $CARRIER{ name_of($w[0]) } || read_only($c) || method_script($c, $base, $set);
      next if ((name_of($w[0]) =~ /\A(?:bash|sh|dash|zsh|ksh)\z/) && grep { /\A-[A-Za-z]*c[A-Za-z]*\z/ } @w) && !grep { /\Aa pipe/ } @{ $c->{unread} || [] };
      return ('G6', "this call names $named->{what}, which Claude may only read, and " . shown(name_of($w[0])) . " is not on the read-only list$NO");
    }
    return ();
  }
  # 2. what each write lands on
  for my $k (0 .. $#$cmds) {
    my $c = $cmds->[$k];
    my @w = @{ $c->{words} };
    next unless @w;
    my $base = defined $dirs->[$k] ? $dirs->[$k] : $top;
    my $n = name_of($w[0]);
    my $why = lands($c, $n, $base, $set);
    return ('G6', $why . $NO) if $why;
  }
  return ();
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
    my $takes = $n eq 'cp' || $n eq 'mv' || $n eq 'ln' || $n eq 'install' ? qr/\A-[tSgmo]\z|\A--(?:target-directory|suffix|group|mode|owner)\z/ : qr/\A-[efT]\z|\A--(?:rsh|exclude|include|filter|files-from|temp-dir|partial-dir|backup-dir|suffix|chmod|chown)\z/;
    my @pos = positionals(\@w, $takes);
    my ($tdir) = map { /\A--target-directory=(.+)\z/s ? $1 : () } @a;
    for my $i (0 .. $#a - 1) { $tdir = $a[ $i + 1 ] if $a[$i] eq '-t' && $n ne 'rsync' }
    return undef if !defined $tdir && @pos < 2;
    my $dest = defined $tdir ? $tdir : pop @pos;
    return undef if $n eq 'rsync' && $dest =~ m{\A[^/]*:};    # another machine
    my $dpath = $R->($dest);
    return undef unless defined $dpath;
    my $into = defined $tdir || @pos > 1 || -d $dpath || $dest =~ m{/\z};
    my $rec = $n eq 'rsync' || $flags =~ /[rRa]/ || $long{recursive} || $long{archive};
    for my $s (@pos) {
      my $sp = $R->($s);
      my $contents = $s =~ m{/\.?\z};
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
    my $t = $base;
    for my $i (0 .. $#a) {
      $t = $a[ $i + 1 ] if ($a[$i] eq '-C' || $a[$i] eq '--directory') && defined $a[ $i + 1 ];
      $t = $1 if $a[$i] =~ /\A--directory=(.+)\z/s;
    }
    my $tp = $R->($t);
    my $e = protected($tp, $set) || above($tp, $set);
    return "this tar extracts into a folder that holds $e->{what}; extract into a new subfolder" if $e;
    return undef;
  }
  if ($n eq 'unzip' || $n eq 'patch') {
    return undef if $n eq 'unzip' && $flags =~ /[ltvZp]/;
    my $t = $base;
    for my $i (0 .. $#a) { $t = $a[ $i + 1 ] if $a[$i] eq '-d' && defined $a[ $i + 1 ]; $t = $1 if $a[$i] =~ /\A--directory=(.+)\z/s }
    my $tp = $R->($t);
    my $e = protected($tp, $set) || above($tp, $set);
    return "this $n writes into a folder that holds $e->{what}; run it in a new subfolder" if $e;
    return undef;
  }
  if ($n eq 'rm' && ($flags =~ /[rR]/ || $long{recursive})) {
    for my $s (positionals(\@w)) {
      my $e = above($R->($s), $set);
      return "this rm deletes a folder that holds $e->{what}" if $e;
    }
    return undef;
  }
  if ($n eq 'find' && grep { /\A-(?:exec|execdir|ok|okdir|delete)\z/ } @a) {
    my @start;
    for my $x (@a) { last if $x =~ /\A[-(!]/; push @start, $x }
    @start = ('.') unless @start;
    for my $s (@start) {
      my $sp = $R->($s);
      my $e = protected($sp, $set) || above($sp, $set);
      return "this find deletes or runs a command in a folder that holds $e->{what}; start it in a subfolder" if $e;
    }
    return undef;
  }
  if ($n eq 'git') {
    my $i = 1;
    while ($i <= $#w && $w[$i] =~ /\A-/) { $i += ($w[$i] =~ /\A-[Cc]\z/) ? 2 : 1 }
    my $sub = $w[$i] // '';
    return undef unless $sub eq 'rm' || $sub eq 'mv';
    for my $s (grep { !/\A-/ } @w[$i + 1 .. $#w]) {
      my $sp = $R->($s);
      my $e = protected($sp, $set) || above($sp, $set);
      return "this git $sub removes or moves a folder that holds $e->{what}" if $e;
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
  return () if $short =~ /\A(?:read|get|list|search|find|view|stat|show|head|tail|cat|describe|query|fetch)/i;
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
my @SPECS = qw(.claude/hooks/method .claude/agents/method .claude/rules/method .claude/method-local scripts/method .claude/settings.json .claude/settings.local.json);

# the protected files whose version differs between commits A and B, or
# undef when that cannot be told
sub differ {
  my ($dir, $a, $b, @only) = @_;
  my @specs = @only ? @only : @SPECS;
  my ($st, $out) = Git::run('-C', $dir, 'diff', '--no-ext-diff', '--no-textconv', '--name-only', '-z', $a, $b, '--', @specs);
  return undef unless $st == 0;
  return [grep { $_ ne '' } split /\0/, $out];
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
    if ($x eq '--') { last }
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
  } elsif ($sub eq 'worktree') {
    return () unless @pos && $pos[0] eq 'add';
    @targets = ([@pos > 2 ? $pos[-1] : 'HEAD']);
  } elsif ($sub eq 'cherry-pick' || $sub eq 'revert') {
    for my $cmt (@pos) {
      # the protected files the commit changes (against no files, for a
      # first commit)
      my ($st, $out) = Git::run('-C', $dir, 'diff-tree', '--root', '--no-commit-id', '--no-ext-diff', '--no-textconv', '-r', '--name-only', '-z', $cmt, '--', @SPECS);
      my $ch = $st == 0 ? [grep { $_ ne '' } split /\0/, $out] : undef;
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
    return ('G6', "this $sub would bring $shown to a version that is neither this branch's nor the remote main's$NO");
  }
  return ();
}

# G12: the warning for the session's first main-session call below xhigh
sub effort {
  my ($in, $project) = @_;
  return undef unless ref $in eq 'HASH';
  return undef if defined $in->{agent_id} && !ref $in->{agent_id} && $in->{agent_id} ne '';
  my $e = $in->{effort};
  my $level = ref $e eq 'HASH' ? $e->{level} : $e;
  return undef unless defined $level && !ref $level && $level ne '';
  return undef if $level =~ /\A(?:xhigh|max)\z/;
  my $shown = $level =~ /\A(?:low|medium|high)\z/ ? $level : 'not one the method knows';
  my $sid = defined $in->{session_id} && !ref $in->{session_id} ? $in->{session_id} : '';
  require Digest::SHA;
  my $hash = Digest::SHA::sha256_hex(bytes("effort\0$sid"));
  my $root = defined $project && $project ne '' ? $project : undef;
  if (defined $root) {
    require File::Spec->catfile($lib, 'log.pl');
    my ($lines) = eval { Log::lines($root, '.method/local/effort-warned') };
    return undef if $lines && grep { $_->[3] eq $hash } @$lines;
    eval { Log::append($root, '.method/local/effort-warned', 1, rule => 'G12', tool => 'effort', hash => $hash) };
  }
  return "this session runs at effort $shown, below the method's xhigh, so its work may be shallower than the method assumes; switch with /effort xhigh";
}

1;
