#!/usr/bin/env perl
# The guard's rules (step 5.5 onward; docs/plans/step5.md, section 6.2;
# DECISIONS A50 and A57). .claude/hooks/method/guard.sh runs this with the
# hook's JSON input on standard input. It ends with 0 (let the call
# through) or $Hook::BLOCK (refuse it, one line on stderr naming the rule
# and what to do instead). Each refusal is logged with fixed fields only
# (lib/log.pl, M072): the time, the rule, the tool and a hash of the input.
#
# The rules built so far:
#   G0 cannot-tell (M128): a call the guard cannot read, when it touches
#      something the guard watches: input that is not one JSON object, a
#      command that is not text, or a simple command with a shape on the
#      reader's "cannot read" list (lib/shell.pl) that runs git, gh, claude,
#      curl or wget, or whose own text names them or one of the method's
#      files (judge_command).
#   G1 perl-missing (M128): perl or JSON::PP missing (guard.sh, and here).
#   G2 powershell (M129): every PowerShell call; the method's checks read
#      bash.
#   G3 git-shapes (M130, step 5.6): a git command aimed at this project's
#      repository must match a shape on the git list (git-shapes.txt beside
#      guard.sh, and the project's .claude/method-local/git-shapes.txt); a
#      push is judged by push_rule (a task branch only, never main, the
#      settings that could redirect it absent, nothing beside it that could
#      move what it sends); GIT_ variables and git's global options are
#      judged; ExitWorktree that would discard changes is refused (judge_git).
#   G8 mutant-commit (M133, step 5.6): git commit, or a merge, cherry-pick,
#      revert or pull (which can make a commit; 5.6 repair loop 1), in this
#      repository while a mutate-changed run, or what one left behind, is
#      there.
#   G6 protected (M132, step 5.7): a write to the method's files, its
#      settings, or git's own config and hooks, by an edit tool, an MCP
#      tool or Bash, and a git command that would bring one of them to
#      another version (lib/protect.pl).
#   G12 effort (M134, step 5.7): not a refusal; the first main-session
#      call below xhigh gets one warning (lib/protect.pl).
#   G4 outside (M131, step 5.8): gh by a list, curl and wget to GitHub only
#      reading, no nested Claude, MCP tools by a list, no SendMessage
#      (lib/outside.pl).
#   G16 settings-change (M136, step 5.9): at the ConfigChange event, a
#      change to the project's settings, or to the hooks, env, plugins,
#      disableAllHooks, deny entries or skill shell setting of the local or
#      user settings, during a session; the next call let through brings a
#      one-time message (lib/watch.pl).
#   G17 skill-and-agent-hooks (M137, step 5.9): a Skill, Agent or Task call
#      whose skill or agent declares hooks in its frontmatter
#      (lib/watch.pl).
# A call the rules say nothing about is let through. A call let through
# that writes (as G6 counts it), made by the main session or an agent that
# is not a gate while a gate runs in its repository, leaves a write mark
# for that gate's receipt (lib/receipt.pl; step 5b.2, B8): never an answer.
package Guard;
use strict;
use warnings;
use Cwd ();
use File::Basename qw(dirname);
use File::Spec;

my $lib = dirname(File::Spec->rel2abs(__FILE__));
require File::Spec->catfile($lib, 'hook.pl');
require File::Spec->catfile($lib, 'shell.pl');
require File::Spec->catfile($lib, 'protect.pl');
require File::Spec->catfile($lib, 'outside.pl');

our $WAY_OUT = 'if the guard is wrong, see .claude/hooks/method/README.md, "When the guard blocks something it should not"';

# what the guard watches: a call that names one may not hold a shape the
# reader cannot read (G0). A watched command is git, gh, claude, curl or
# wget standing as a word of its own (so /tmp/claude-0 or github.com do not
# count); a watched path is one of the method's files, its settings, or
# git's own config and hooks.
# (in any letter case, as a file system that ignores case runs GIT as git,
# and with .exe; a backslash, brace, comma, < or > around it counts as a
# word's edge, as bash ends or splits words there)
# (watched_word reads in one pass: the regex it replaces looked back over a
# path from every edge, which took the square of the length on a run of
# backslashes, past the hook's time limit; 5.5's round 3)
our $WATCHED_NAME = qr{(?i:git(?:-[a-z][a-z0-9-]*)?|gh|claude|curl|wget)(?i:\.exe)?(?=\z|[\s;&|)`'"\\{},<>])};
my $EDGE = qr{[\s;&|(`'"=\\{},<>]};
# (the method's skills come from protect.pl's list, their one home; step
# 6.3)
our $WATCHED_PATH = qr{\.claude/(?:hooks/method|agents/method|rules/method|method-local|settings(?:\.local)?\.json)|\.claude/skills/@{[ Protect::skills_re() ]}|(?:\A|[\s/'"=])scripts/method\b|\.git/(?:hooks|config)\b|\.gitconfig\b|\.config/git\b|managed-settings}i;

# does TEXT name a watched command: the name at the start, after an edge,
# or as the last part of a path (letters, digits, _ . / -) that starts at
# the start or after an edge
sub watched_word {
  my ($t) = @_;
  return 0 unless defined $t;
  while ($t =~ /$WATCHED_NAME/g) {
    my $s = $-[0];
    next if $s > 0 && substr($t, $s - 1, 1) =~ /[\w.-]/;
    return 1 if $s == 0 || substr($t, $s - 1, 1) =~ $EDGE;
    next unless substr($t, $s - 1, 1) eq '/';
    my $i = $s - 1;
    $i-- while $i > 0 && substr($t, $i - 1, 1) =~ m{[\w./-]};
    return 1 if $i == 0 || substr($t, $i - 1, 1) =~ $EDGE;
  }
  return 0;
}
sub watched { my ($t) = @_; return defined $t && (watched_word($t) || $t =~ $WATCHED_PATH) }

# xargs's WORDS: (its replace string, or undef; the word that names the
# program it runs, or undef)
sub xargs_parts {
  my (undef, @w) = @_;
  my $rep;
  for (my $i = 0; $i <= $#w; $i++) {
    my $x = $w[$i];
    return ($rep, $w[ $i + 1 ]) if $x eq '--';
    if ($x =~ /\A--([a-z-]+)(?:=(.*))?\z/s) {
      my ($o, $v) = ($1, $2);
      if ($o eq 'replace') { $rep = defined $v ? $v : '{}' }
      elsif (!defined $v && $o =~ /\A(?:arg-file|delimiter|eof|max-lines|max-args|max-procs|max-chars|process-slot-var)\z/) { $i++ }
      next;
    }
    return ($rep, $x) unless $x =~ /\A-./s;
    my @l = split //, substr($x, 1);
    while (@l) {
      my $o = shift @l;
      my $rest = join '', @l;
      if ($o =~ /[IJ]/) { $rep = $rest ne '' ? $rest : $w[ ++$i ]; last }
      if ($o eq 'i') { $rep = $rest ne '' ? $rest : '{}'; last }
      if ($o =~ /[adELnPs]/) { $i++ if $rest eq ''; last }
      last if $o =~ /[el]/;
    }
  }
  return ($rep, undef);
}

# TEXT as bash would mostly read it: ANSI-C quoting decoded, line
# continuations, quotes and backslashes removed, // and /./ made one /.
# Watched words are looked for in this copy too, so g''it, \git, g\it and
# meth''od are seen.
sub norm_text {
  my ($t) = @_;
  $t =~ s/\$'((?:[^'\\]|\\.)*)'/Shell::ansi_c($1)/ge;
  $t =~ s/\\\r?\n//g;
  # ($"..." is the text inside it; the words in ${x:-word}, ${x/a/word}
  # and the like stand as words of their own)
  $t =~ s/\$(?=")//g;
  $t =~ s/\$\{([^{}]*)\}/' ' . join(' ', split m{[:\/=+?#%^,*\-]+}, $1) . ' '/ge;
  $t =~ s/['"\\]//g;
  1 while $t =~ s{/\.?/}{/}g;
  # each word with a brace expansion, also as each of its expansions
  my @more;
  while ($t =~ /(\S*\{[^{}\s]*(?:,|\.\.)[^{}\s]*\}\S*)/g) {
    push @more, brace_words($1);
    last if @more > 256;
  }
  return @more ? join("\n", $t, @more) : $t;
}

# WORD's brace expansions ({a,b} and {a..c}), at most 64
sub brace_words {
  my ($w) = @_;
  my @out = ($w);
  for (1 .. 4) {
    my @next;
    for my $x (@out) {
      if ($x =~ /\A(.*?)\{([^{}]*)\}(.*)\z/s) {
        my ($pre, $in, $post) = ($1, $2, $3);
        my @alt;
        if ($in =~ /\A([A-Za-z0-9])\.\.([A-Za-z0-9])\z/) { my ($a, $b) = ($1, $2); @alt = $a le $b ? ($a .. $b) : reverse($b .. $a); @alt = @alt[0 .. 25] if @alt > 26 }
        elsif ($in =~ /,/) { @alt = split /,/, $in, -1 }
        else { @alt = ("{$in}") }
        push @next, map { "$pre$_$post" } @alt;
      } else {
        push @next, $x;
      }
      last if @next > 64;
    }
    @out = @next[0 .. ($#next < 63 ? $#next : 63)];
  }
  return @out;
}

sub sha256_hex {
  require Digest::SHA;
  return Digest::SHA::sha256_hex($_[0]);
}

# log RULE TOOL RAW: one line in .method/local/guard.log of the project; a
# failure to log never changes the answer
sub log_refusal {
  my ($rule, $tool, $raw, $in) = @_;
  my $root = $ENV{CLAUDE_PROJECT_DIR};
  $root = $in->{cwd} if (!defined $root || !-d $root) && ref $in eq 'HASH' && defined $in->{cwd} && !ref $in->{cwd};
  return unless defined $root && -d $root;
  (my $t = defined $tool && !ref $tool ? $tool : 'unknown') =~ s/[^A-Za-z0-9_.:-]/_/g;
  # (an MCP tool by its server only: the rest of its name is chosen by
  # whoever wrote the server)
  $t =~ s/\A(mcp__[A-Za-z0-9_.:-]*?)__.*\z/$1/s;
  $t = substr($t, 0, 128) || 'unknown';
  eval {
    require File::Spec->catfile($lib, 'log.pl');
    Log::append($root, '.method/local/guard.log', undef, rule => $rule, tool => $t, hash => sha256_hex($raw));
    1;
  };
}

# refuse RULE TEXT: the one line Claude Code shows, and the log line
sub refuse {
  my ($rule, $text, $tool, $raw, $in) = @_;
  log_refusal($rule, $tool, $raw, $in);
  return Hook::block("guard $rule: $text");
}

# the shapes whose meaning can come from elsewhere in the call: judged
# against the whole call, not their own text
# programs that run another program given in their words, which the reader
# does not follow (the ones it does follow are Shell's carriers)
our %OPAQUE = map { $_ => 1 } qw(flock taskset unshare script strace ltrace chroot watch systemd-run firejail nsenter chrt numactl cgexec faketime valgrind xvfb-run unbuffer rlwrap parallel entr su runuser pkexec busybox tmux screen at batch dbus-launch ssh-agent proot fakeroot);
my $WIDE = qr{variable as the command word|eval of anything|-c with an expansion|could not split|case statement|nested too deep|trap of anything|a coprocess|from a process substitution|source of a process substitution};
# what lets an inline program start another program
# (a name joined to another by _ counts too: create_subprocess_shell,
# posix_spawnp, pcntl_exec; and awk's and perl's pipes, osascript's do shell
# script)
our $STARTS = qr{(?<![A-Za-z0-9])(?:system\w*|exec\w*|qx|popen\w*|spawn\w*|execSync|execFile\w*|subprocess|child_process|Popen|Runtime|ProcessBuilder|IPC::\w+|shell_exec|passthru|proc_open|Start-Process|Invoke-Expression|iex|Process|readpipe|pcntl_exec|posix_spawn\w*|create_subprocess_\w+)(?![A-Za-z0-9])|(?i:open[23])|\bDeno\.(?:Command|run)\b|`|%x[\[(\x7B<]|\bos\.(?:system|popen|exec\w*|spawn\w*)|open\s*\(?[^;]*["']\s*\||open\s*\(?[^;]*\|\s*["']|\|\s*["']\s*\)|["']-\|["']|\|-|-\||\|\s*getline|\bprintf?\b[^|;]*\|\s*["']|do\s+shell\s+script};

# judge_command TEXT: () to let it through, or (RULE, TEXT) to refuse. A
# simple command the reader cannot read is refused (G0) when it runs git,
# gh, claude, curl or wget itself, or when its own text (its words, its
# here-document, what is piped into it) names something watched; for the
# shapes whose meaning can come from elsewhere ($WIDE), when the whole call
# does. A call that names something watched and holds a shape the reader
# may read differently from bash (Shell::doubts; a line continuation it did
# not join, JOINED false) is refused whole (step 5.5, repair loop 3).
sub judge_command {
  my ($cmd, $read, $joined) = @_;
  my @cmds = $read ? @$read : Shell::commands($cmd);
  # (with ANSI-C quoting decoded, also where the reader stopped early)
  (my $decoded = $cmd) =~ s/\$'((?:[^'\\]|\\.)*)'/Shell::ansi_c($1)/ge;
  my $call_watched = watched(join("\n", $cmd, $decoded, norm_text($cmd), map { join(' ', @{ $_->{words} }, $_->{hbody} // '') } @cmds));
  if ($call_watched) {
    my @doubt = Shell::doubts($cmd);
    unshift @doubt, 'a line continuation beside a here-document, a substitution or ANSI-C quoting' if defined $joined && !$joined;
    return ('G0', "this call holds $doubt[0], which the guard may read differently from bash, in a call that names git, gh, claude, curl, wget or a method file;"
      . " write it as plain commands, one per line, with every word written out; if that is refused too, stop and tell the owner what you needed ($WAY_OUT)") if @doubt;
  }
  for my $c (@cmds) {
    my @w = @{ $c->{words} };
    next unless @w;
    (my $n = $w[0]) =~ s{.*[/\\]}{};
    $n =~ s/\.exe\z//i;
    # xargs adds words from its input to what it runs: a shell, or a
    # watched command, is then run with words the guard never sees
    if ((grep { $_ eq 'xargs' } @{ $c->{via} || [] }) && ($n =~ /\A(?:sh|bash|zsh|dash|ksh|mksh|fish|csh|tcsh)\z/ || watched_word($n))) {
      return ('G0', "xargs here runs " . ($n =~ /\A[a-z]+\z/ ? $n : 'a watched command') . " with words from its input, which the guard cannot see; write each command out ($WAY_OUT)");
    }
    if ($n eq 'xargs') {
      my ($rep, $word) = xargs_parts(@w);
      if (defined $rep && defined $word && $rep ne '' && index($word, $rep) >= 0) {
        return ('G0', "xargs here builds the name of the program it runs from its input, which the guard cannot see; write each command out ($WAY_OUT)");
      }
    }
    # a program that runs another one, whose words the reader does not
    # follow
    if ($OPAQUE{$n} && @w > 1 && watched(join ' ', @w[1 .. $#w])) {
      return ('G0', "$n runs another program, which the guard does not read through; run that program directly, or tell the owner what you needed ($WAY_OUT)");
    }
  }
  for my $c (@cmds) {
    next unless @{ $c->{unread} };
    # (its assignments and a for header's words, as written, are its own
    # text too: what they run is judged)
    my $words = join(' ', @{ $c->{assigns_raw} || [] }, @{ $c->{raw} || [] }, @{ $c->{words} }, map { $_->[1] } @{ $c->{redirs} });
    my $own = join(' ', $words, $c->{hbody} // '', $c->{pipe_from} // '');
    # (and each as bash would mostly read it)
    $words .= "\n" . norm_text($words);
    $own .= "\n" . norm_text($own);
    my $wide = grep { $_ =~ $WIDE } @{ $c->{unread} };
    # code from a variable or a substitution, piped or written into a shell
    # or an interpreter, is not this command's own text
    $wide ||= (grep { /\Aa pipe, here-document or here-string into / } @{ $c->{unread} })
      && (($c->{pipe_from} // '') =~ /[\$`]/ || ($c->{hbody} // '') =~ /[\$`]/) ? 1 : 0;
    my $inline_only = !grep { $_ !~ /\Aan inline program for / } @{ $c->{unread} };
    # (the program: its words, and a here-document that is its code)
    my $code = $c->{piped} ? $words : join("\n", $words, $c->{hbody} // '', norm_text($c->{hbody} // ''));
    my $glob_only = !grep { $_ ne 'a glob or a brace in a write target' } @{ $c->{unread} };
    # (a command that runs git, gh, claude, curl or wget names it in its
    # own text, so it is caught below)
    # (PowerShell's inline program is shell commands: a watched word runs)
    my $shell_like = @{ $c->{words} } && $c->{words}[0] =~ m{(?:\A|[/\\])(?:pwsh|powershell)(?:\.exe)?\z}i;
    # a glob or brace in the command word hides which program runs at all
    # (and nesting deeper than the reader reads hides which program runs)
    my $hit = (grep { $_ eq 'a glob or a brace in the command word' || $_ eq 'an alias definition' || $_ eq 'commands nested too deep' } @{ $c->{unread} }) ? 1
      : $wide ? $call_watched
      # an inline program: what is piped into it is data, not code; it
      # touches a watched command only by starting a program
      : $inline_only ? ($code =~ $WATCHED_PATH || (watched_word($code) && ($shell_like || $code =~ $STARTS)))
      # a glob can hide which file is written: any write near the method's
      # folders or git's own
      # (a glob in a folder's name can hide .claude or scripts/method, so a
      # glob target with a folder in it, or one that starts with a dot or a
      # glob, counts as near them)
      : $glob_only ? ((grep { $_->[0] =~ />/ && ($_->[1] =~ m{/|\A[.*?\[\x7B]} || $_->[1] =~ m{\.claude|scripts/method|\.git\b|gitconfig}i) } @{ $c->{redirs} }) || watched($own))
      : watched($own);
    next unless $hit;
    my $why = $c->{unread}[0];
    if (grep { $_ eq 'a glob or a brace in the command word' } @{ $c->{unread} }) {
      return ('G0', "this command's name holds a glob or a brace, so which program runs cannot be told; write the program's name out ($WAY_OUT)");
    }
    # (an alias can make any later word, built from any pieces, run git)
    if (grep { $_ eq 'an alias definition' } @{ $c->{unread} }) {
      return ('G0', "this call defines an alias, which can make a later word run any program; write each command out instead ($WAY_OUT)");
    }
    return ('G0', "this command holds $why, which the guard cannot read with confidence, in a call that names git, gh, claude, curl, wget or a method file;"
      . " write it as plain commands, one per line, with every word written out (a commit message or PR body can go on stdin: git commit -F - with a here-document);"
      . " if that is refused too, stop and tell the owner what you needed ($WAY_OUT)");
  }
  return ();
}

# --- G3 git-shapes and G8 mutant-commit (step 5.6, M130 and M133) ---
#
# A git command aimed at this project's repository (its working tree or any
# of its worktrees: one git common folder) must match a shape on the git
# list (git-shapes.txt beside guard.sh, and the project's own
# .claude/method-local/git-shapes.txt). The folder a git command runs in is
# followed through cd and -C, in each subshell and carrier on its own; a
# folder that cannot be told (a variable) is judged as this repository. A
# git command aimed elsewhere (a scratch clone, a test folder) is judged
# only when it pushes to somewhere that is not a local folder, or into this
# repository, and when it changes git's global or system settings.
# A push is judged by push_rule, never by a shape.

our $SHAPES_FILE = File::Spec->catfile($lib, '..', '..', '..', '.claude', 'hooks', 'method', 'git-shapes.txt');
# GIT_ settings that only name the author or narrow what git reads
my %GIT_ENV_OK = map { $_ => 1 } qw(GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE
  GIT_CONFIG_NOSYSTEM GIT_ATTR_NOSYSTEM GIT_NO_REPLACE_OBJECTS GIT_LFS_SKIP_SMUDGE GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS);
my %GIT_ENV_VALUE = (GIT_TERMINAL_PROMPT => qr/\A0\z/, GIT_PAGER => qr/\A(?:cat)?\z/, GIT_EDITOR => qr/\A(?:true|:)\z/);
my $C_OK = qr/\A(?:core\.quotepath|color\.[A-Za-z0-9.-]+|user\.name|user\.email|commit\.gpgsign)(?:=|\z)/i;
# what may share a Bash call with a push: nothing that moves HEAD, a ref or
# git's settings (K3b)
my %PUSH_MOVES = map { $_ => 1 } qw(checkout switch merge reset branch config cherry-pick revert rebase update-ref
  symbolic-ref worktree stash pull am tag notes replace filter-branch filter-repo restore clean init clone fetch remote);

sub is_git { my ($c) = @_; return @{ $c->{words} } && $c->{words}[0] =~ m{(?:\A|/)git(?:\.exe)?\z} }

# git's WORDS: (its subcommand, the words after it), git's own options and
# their values (-C DIR, -c KEY=VALUE) skipped
sub git_sub {
  my (undef, @w) = @_;
  while (@w && $w[0] =~ /\A-/) {
    my $o = shift @w;
    shift @w if $o eq '-C' || $o eq '-c' || $o eq '--git-dir' || $o eq '--work-tree' || $o eq '--namespace';
  }
  return @w;
}

# does git SUB ARGS only read (a form of a moving subcommand that changes
# nothing): branch --show-current or a listing, remote -v or get-url,
# config --get, stash list or show
sub git_reads {
  my ($sub, @a) = @_;
  return 1 if $sub eq 'branch' && (!@a || !grep { !/\A-(?:-show-current|a|r|v|vv|-list|l|-all|-remotes|-verbose|-contains|-merged|-no-merged|-format=.*)\z/ } @a);
  return 1 if $sub eq 'remote' && (!@a || (@a == 1 && $a[0] =~ /\A-(?:v|-verbose)\z/) || $a[0] eq 'get-url' || $a[0] eq 'show');
  return 1 if $sub eq 'config' && @a && $a[0] =~ /\A--(?:get|get-all|get-regexp|list)\z|\A-l\z/;
  return 1 if $sub eq 'stash' && @a && ($a[0] eq 'list' || $a[0] eq 'show');
  return 0;
}

# the GIT_ settings a command makes: its assignments, env's, export's
sub git_env {
  my ($c) = @_;
  my @w = @{ $c->{words} };
  my @a = @{ $c->{assigns} };
  my $name = @w ? $w[0] : '';
  $name =~ s{.*/}{};
  if ($name eq 'env') { for my $x (@w[1 .. $#w]) { last unless $x =~ /\A-|\A[A-Za-z_][A-Za-z0-9_]*=/; push @a, $x if $x =~ /=/ } }
  if ($name =~ /\A(?:export|declare|typeset|readonly|local)\z/) { push @a, grep { /\A[A-Za-z_][A-Za-z0-9_]*(?:=|\z)/ } @w[1 .. $#w] }
  return grep {
    my ($k, $v) = /\A([A-Za-z_][A-Za-z0-9_]*)(?:\+?=(.*))?\z/s;
    defined $k && $k =~ /\AGIT_/ && !$GIT_ENV_OK{$k} && !($GIT_ENV_VALUE{$k} && defined $v && $v =~ $GIT_ENV_VALUE{$k})
  } @a;
}

sub git_at {
  my ($dir, @args) = @_;
  return (-1, '') unless defined $dir && -d $dir;
  return Git::run('-C', $dir, @args);
}

# the real path of a folder, or of its nearest folder that exists
sub real_dir {
  my ($d) = @_;
  $d = File::Spec->rel2abs($d);
  for (1 .. 64) {
    if (-d $d) { my $r = Cwd::realpath($d); return defined $r ? $r : $d }
    my $p = dirname($d);
    return $d if $p eq $d;
    $d = $p;
  }
  return $d;
}

my %REPO;
# repo DIR: the real path of the git common folder of the repository at DIR,
# or '' when DIR is in none
sub repo {
  my ($dir) = @_;
  my $d = real_dir($dir);
  return $REPO{$d} if exists $REPO{$d};
  my ($st, $out) = git_at($d, 'rev-parse', '--git-common-dir');
  chomp $out if defined $out;
  my $r = '';
  if ($st == 0 && defined $out && $out ne '') {
    my $abs = File::Spec->rel2abs($out, $d);
    $r = Cwd::realpath($abs) // $abs;
  }
  return $REPO{$d} = $r;
}

sub load_shapes {
  my ($project) = @_;
  require File::Spec->catfile($lib, 'gitlist.pl');
  my (@all, @errors);
  for my $f ([$SHAPES_FILE, 'git-shapes.txt', 1], [File::Spec->catfile($project // '', '.claude', 'method-local', 'git-shapes.txt'), '.claude/method-local/git-shapes.txt', 0]) {
    my ($path, $name, $must) = @$f;
    next if !$must && !(defined $project && -e $path);
    my $text;
    if (open my $h, '<:raw', $path) { local $/; $text = <$h>; close $h }
    if (!defined $text) { push @errors, "$name cannot be read"; next }
    my ($s, $e) = GitList::parse($text, $name);
    push @all, @$s;
    push @errors, @$e;
  }
  return (\@all, \@errors);
}

# the main branch names a push may not reach: main, master and main_ref's
sub main_names {
  my ($dir) = @_;
  my %n = (main => 1, master => 1);
  my $old = Cwd::getcwd();
  if (defined $dir && chdir $dir) {
    my @m = eval { Git::main_ref() };
    if (@m && defined $m[0]) { (my $x = $m[0]) =~ s{\Arefs/(?:remotes/[^/]+|heads)/}{}; $n{ lc $x } = 1 }
    chdir $old;
  }
  return \%n;
}

sub remotes {
  my ($dir) = @_;
  my ($st, $out) = git_at($dir, 'remote');
  return { map { $_ => 1 } split /\n/, ($st == 0 ? $out : '') };
}

# a push URL that names a folder on this machine: its absolute path
sub local_path {
  my ($url, $dir) = @_;
  return File::Spec->rel2abs($1) if $url =~ m{\Afile://(/.*)\z};
  return $url if $url =~ m{\A/} || $url =~ m{\A[A-Za-z]:[\\/]};
  return File::Spec->rel2abs($url, $dir) if $url !~ /:/;
  return undef;
}

# push_rule: () when the push may go, or the refusal's text
sub push_rule {
  my ($dir, $words, $is_session, $session, $c, $all) = @_;
  my (@pos, $bad);
  for my $x (@$words) {
    if ($x =~ /\A-./) { if ($x =~ /\A-[qu]+\z/ || $x eq '--quiet' || $x eq '--set-upstream') { next } $bad = $x; last }
    push @pos, $x;
  }
  my $rem = remotes($dir);
  my $target = @pos ? $pos[0] : undef;
  # where it goes: pushes to folders on this machine, other than this
  # repository, are not judged when the command is aimed elsewhere
  if (!$is_session && defined $target && !$bad) {
    my @urls;
    if ($rem->{$target}) {
      my ($st, $out) = git_at($dir, 'remote', 'get-url', '--push', '--all', $target);
      @urls = $st == 0 ? split(/\n/, $out) : ();
    } elsif ($target =~ m{\A(?:file://|[./~]|[A-Za-z]:[\\/])|/} && -e (local_path($target, $dir) // '')) {
      @urls = ($target);
    }
    # (a bare name that is not one of its remotes, in a folder the guard
    # cannot read yet or with a remote added in the same call, is a remote
    # it cannot tell: judged in full; 5.6 repair loop 1)
    my $here = repo($dir);
    my $all_local = @urls ? 1 : 0;
    for my $u (@urls) {
      my $p = local_path($u, $dir);
      if (!defined $p) { $all_local = 0; last }
      my $r = repo($p);
      if ($r ne '' && $r eq $session) { $all_local = 0; last }
    }
    return () if $all_local;
  }
  # (refusals name no word of the push: a remote's URL can hold a token)
  my $form = 'write it as git push [-q] [-u] <remote> HEAD, HEAD:<branch>, <branch> or <branch>:<branch>';
  return "this option is refused on a push; $form" if defined $bad;
  return "this push names no remote and branch; $form" unless @pos == 2;
  return "this push's remote is not one of this repository's remotes; $form" unless $rem->{$target};
  my $spec = $pos[1];
  return "a forced, deleting or pattern push is refused; $form" if $spec =~ /\A\+|\A:|\*/;
  my ($src, $dst) = $spec =~ /\A([^:]+)(?::(.+))?\z/ or return "this push's branch cannot be read; $form";
  if ($src eq 'HEAD') {
    my ($st, $out) = git_at($dir, 'symbolic-ref', '-q', '--short', 'HEAD');
    chomp $out;
    return 'HEAD is not on a branch, so where this push goes cannot be told; switch to your task branch first' if $st != 0 || $out eq '';
    $dst //= $out;
  } else {
    return "what this push sends is not a local branch; $form" if $src =~ /\A-/ || $src =~ m{\Arefs/(?!heads/)};
    (my $b = $src) =~ s{\Arefs/heads/}{};
    my ($st) = git_at($dir, 'show-ref', '--verify', '-q', "refs/heads/$b");
    return "what this push sends is not a local branch; $form" if $st != 0;
    my ($sym) = git_at($dir, 'symbolic-ref', '-q', "refs/heads/$b");
    return "what this push sends is a symbolic ref, so where it goes cannot be told; push your task branch by its own name" if $sym == 0;
    $dst //= $b;
  }
  $dst =~ s{\A(?:refs/)?heads/}{};
  return "this push's destination is not a branch; $form" if $dst =~ m{\Arefs/} || $dst eq '' || $dst =~ /\A-/;
  # (refusals name no word of the push, the branch included; final review
  # of step 5)
  return "pushing to main is refused: the owner merges into main on GitHub; push your task branch instead"
    if main_names($dir)->{ lc $dst };
  my ($st, $out) = git_at($dir, 'config', '--get-regexp', '^remote\..*\.(push|mirror)$');
  return 'a remote.*.push or remote.*.mirror setting would change where this push goes; the owner must remove it first' if $st == 0 && $out ne '';
  return 'git settings cannot be read, so where this push goes cannot be told' if $st != 1 << 8;    # (a wait status: git found none)
  return 'a push that runs in the background is refused, as what it sends cannot be told when it runs' if $c->{bg};
  for my $o (@$all) {
    next if $o == $c;
    my @w = @{ $o->{words} };
    next unless @w;
    my $n = $w[0];
    $n =~ s{.*/}{};
    if (is_git($o)) {
      my ($sub, @args) = git_sub(@w);
      next unless defined $sub && $PUSH_MOVES{$sub};
      next if git_reads($sub, @args);
      return "a push may not share its Bash call with git $sub, which can move what it sends; run the push on its own";
    }
    return 'a push may not share its Bash call with a command that names git\'s own folder; run the push on its own'
      if grep { m{(?:\A|/)\.git(?:/|\z)} } (@w, map { $_->[1] } @{ $o->{redirs} });
  }
  return ();
}

# cd_to C HERE: the folder the cd or pushd C leads to from HERE, or undef
# where it cannot be told (a folder in a variable or a glob, cd -, ~user,
# a CDPATH, pushd alone); cd reads .. in the path as written, before any
# link, unless -P (5.7 repair loop 1)
sub cd_to {
  my ($c, $here) = @_;
  my @w = @{ $c->{words} };
  my ($to) = grep { !/\A-/ } @w[1 .. $#w];
  my ($raw) = grep { !/\A-/ } @{ $c->{raw} }[1 .. $#{ $c->{raw} }];
  my $d;
  if ((grep { $_ eq '-' } @w[1 .. $#w]) || (defined $to && $to =~ /\A~[^\/]/) || (defined $to && $to !~ m{\A[/.~]} && ($ENV{CDPATH} // '') ne '')) { return undef }
  elsif (!defined $to) { return $w[0] eq 'pushd' ? undef : $ENV{HOME} }
  elsif (defined $raw && $raw =~ /[\$`*?\[]/) { return undef }
  elsif (!defined $here) { return undef unless $to =~ m{\A/}; $d = $to }
  else { $to =~ s{\A~(?=/|\z)}{$ENV{HOME} // '~'}e; $d = File::Spec->rel2abs($to, $here) }
  if (!grep { /\A-[A-Za-z]*P/ } @w[1 .. $#w]) {
    my @p;
    for my $part (split m{/+}, $d) {
      next if $part eq '' || $part eq '.';
      if ($part eq '..') { pop @p } else { push @p, $part }
    }
    $d = '/' . join('/', @p);
  }
  return $d;
}

# is C a cd or pushd that moves its shell (not piped, not in the background)?
sub is_cd {
  my ($c) = @_;
  my @w = @{ $c->{words} };
  return @w && ($w[0] eq 'cd' || $w[0] eq 'pushd') && !$c->{piped} && !$c->{to_pipe} && !$c->{bg};
}

# cmd_dirs CMDS START: the folder each command runs in, followed from START
# through cd, pushd and popd in each scope (lib/shell.pl: a subshell or a
# new process has its own), or undef where it cannot be told (cd_to's
# cases, after popd, and after a cd that the next command does not depend
# on: not followed by &&, so it may have failed and left the folder as it
# was; 5.6 repair loop 1). Where it cannot be told, G3 judges git as this
# repository (the strict side for git).
sub cmd_dirs {
  my ($cmds, $start) = @_;
  my %dir;    # scope => folder, or undef when it cannot be told
  my $dir_of;
  $dir_of = sub {
    my ($s) = @_;
    return $dir{$s} if exists $dir{$s};
    (my $p = $s) =~ s{/[^/]*\z}{};
    return $dir{$s} = $p eq $s ? $start : $dir_of->($p);
  };
  my @out;
  for my $c (@$cmds) {
    my @w = @{ $c->{words} };
    my $scope = defined $c->{scope} ? $c->{scope} : 't';
    my $here = $dir_of->($scope);
    push @out, $here;
    next unless @w;
    if (is_cd($c)) {
      $dir{$scope} = cd_to($c, $here);
      # (a cd the next command does not depend on may have failed)
      $dir{$scope} = undef unless ($c->{next_op} // '') eq '&&';
    } elsif ($w[0] eq 'popd') {
      $dir{$scope} = undef;
    }
  }
  undef $dir_of;
  return @out;
}

# cmd_dir_sets CMDS START: for each command, every folder it may run in
# (undef among them where one cannot be told). For G6 a single guess is the
# lenient side: after a cd that may have failed, the write is judged from
# both the cd's folder and the folder before it (final review of step 5;
# A69). At most 16 folders per scope are kept.
sub cmd_dir_sets {
  my ($cmds, $start) = @_;
  my %set;    # scope => [folders]
  my $set_of;
  $set_of = sub {
    my ($s) = @_;
    return $set{$s} if exists $set{$s};
    (my $p = $s) =~ s{/[^/]*\z}{};
    return $set{$s} = $p eq $s ? [$start] : [@{ $set_of->($p) }];
  };
  my @out;
  for my $c (@$cmds) {
    my @w = @{ $c->{words} };
    my $scope = defined $c->{scope} ? $c->{scope} : 't';
    my $here = $set_of->($scope);
    push @out, [@$here];
    next unless @w;
    my @next;
    if (is_cd($c)) {
      @next = map { cd_to($c, $_) } @$here;
      push @next, @$here unless ($c->{next_op} // '') eq '&&';
    } elsif ($w[0] eq 'popd') {
      @next = (@$here, undef);
    } else {
      next;
    }
    my %seen;
    @next = grep { !$seen{ defined $_ ? "d:$_" : 'u' }++ } @next;
    splice @next, 16 if @next > 16;
    $set{$scope} = \@next;
  }
  undef $set_of;
  return @out;
}

# judge_git CMDS IN: () to let the call through, or (RULE, TEXT)
sub judge_git {
  my ($cmds, $in) = @_;
  # git's own programs called by their dashed names (git-push, as git-core
  # holds them) are git commands the list cannot judge in that form
  for my $c (@$cmds) {
    next unless @{ $c->{words} } && $c->{words}[0] =~ m{(?:\A|/)(git-[a-z][a-z0-9-]*)(?:\.exe)?\z};
    (my $sub = $1) =~ s/\Agit-//;
    return ('G3', "$1 is git $sub under its dashed name, which the git list does not judge; run it as git $sub");
  }
  return () unless grep { is_git($_) } @$cmds;
  require File::Spec->catfile($lib, 'git.pl');
  require Cwd;
  for my $c (@$cmds) {
    my @bad = git_env($c);
    next unless @bad;
    (my $k = $bad[0]) =~ s/=.*//s;
    return ('G3', "setting $k in a call that runs git is refused, as it can point git at other settings, hooks or repositories (K3); run the git command without it");
  }
  my $project = $ENV{CLAUDE_PROJECT_DIR};
  my $start = (ref $in eq 'HASH' && defined $in->{cwd} && !ref $in->{cwd} && $in->{cwd} ne '') ? $in->{cwd} : $project;
  $start = '.' unless defined $start;
  my $session = defined $project && $project ne '' ? repo($project) : '';
  my ($shapes, $errors);
  my @dirs = cmd_dirs($cmds, $start);
  for my $k (0 .. $#$cmds) {
    my $c = $cmds->[$k];
    my @w = @{ $c->{words} };
    next unless @w;
    my $here = $dirs[$k];
    next unless is_git($c);
    my @r = @{ $c->{raw} };
    my $i = 1;
    my $d = $here;
    my $other_c = 0;
    while ($i <= $#w && $w[$i] =~ /\A-/) {
      my $o = $w[$i];
      if ($o eq '-C') {
        my $v = $w[ $i + 1 ];
        return ('G3', "git -C needs a folder; write the folder out") unless defined $v;
        if (($r[ $i + 1 ] // '') =~ /[\$`]/ || $v =~ /\A~[^\/]/) { $d = undef }
        elsif ($v =~ s{\A~(?=/|\z)}{}) { $d = defined $ENV{HOME} ? $ENV{HOME} . $v : undef }
        elsif ($v ne '' && defined $d) { $d = File::Spec->rel2abs($v, $d) }
        elsif ($v ne '') { $d = $v =~ m{\A/} ? $v : undef }
        $i += 2;
        next;
      }
      if ($o eq '-c') {
        my $kv = $w[ $i + 1 ] // '';
        $other_c = 1 if $kv !~ $C_OK;
        $i += 2;
        next;
      }
      if ($o =~ /\A--(?:version|help)\z|\A-h\z/) { $i = -1; last }
      if ($o =~ /\A(?:--no-pager|-P|--no-optional-locks|--no-replace-objects|--literal-pathspecs)\z/) { $i++; next }
      # (an option is named only by its name; what follows it may be a key)
      my $on = $o =~ /\A(--?[A-Za-z][A-Za-z-]{0,30})/ ? $1 : 'this option';
      return ('G3', "git's option $on is refused (it can point git at another repository or settings); not on the method's git list, and the owner can add a shape to .claude/method-local/git-shapes.txt");
    }
    next if $i < 0;    # git --version, git --help
    my @rest = @w[$i .. $#w];
    next unless @rest;    # plain git prints its usage
    next if @rest == 2 && ($rest[1] eq '-h' || $rest[1] eq '--help');
    my $sub = $rest[0];
    my $repo = defined $d ? repo($d) : $session;
    my $is_session = $session ne '' && $repo eq $session;
    # inside git's own folder git may not answer (safe.bareRepository);
    # that folder is still this repository's
    $is_session = 1 if $session ne '' && defined $d && index(real_dir($d) . '/', "$session/") == 0;
    my $tdir = defined $d ? real_dir($d) : (defined $project ? $project : $start);
    # HOME or XDG_CONFIG_HOME set on git points it at other settings (and
    # other hooks): refused in this repository and on a push (5.6 repair
    # loop 1)
    if (($is_session || $sub eq 'push') && grep { /\A(?:HOME|XDG_CONFIG_HOME)=/ } @{ $c->{assigns} || [] }) {
      return ('G3', "setting HOME or XDG_CONFIG_HOME on git here is refused, as it points git at other settings and hooks; run the git command without it");
    }
    if ($other_c && ($is_session || $sub eq 'push')) {
      return ('G3', "git -c with that setting is refused (it can run a program or change where git writes); only core.quotepath, color.*, user.name, user.email and commit.gpgsign may be set with -c");
    }
    if ($sub eq 'push') {
      # (a remote or branch named through a variable, a substitution, a
      # glob or braces: where the push goes cannot be told; final review of
      # step 5)
      my @r = @{ $c->{raw} || [] };
      my ($pi) = grep { ($c->{words}[$_] // '') eq 'push' } 1 .. $#r;
      if (defined $pi && grep { /[\$`*?\[{]/ } @r[ $pi + 1 .. $#r ]) {
        return ('G3', 'this push names its remote or branch through a variable, a substitution, a glob or braces, so where it goes cannot be told; write it out: git push [-q] [-u] <remote> HEAD, or HEAD:<branch>');
      }
      my ($why) = push_rule($tdir, [@rest[1 .. $#rest]], $is_session ? 1 : 0, $session, $c, $cmds);
      # (only a push to main has no allowed form to rewrite it in)
      return ('G3', $why =~ /\Apushing to / ? "$why. Do not try another form of the same push; tell the owner what you needed" : "$why.") if $why;
      next;
    }
    if (!$is_session) {
      # elsewhere, only git's global and system settings are judged
      next unless $sub eq 'config' && grep { /\A--(?:global|system)\z/ } @rest;
      my $home_set = grep { /\A(?:HOME|XDG_CONFIG_HOME)=/ } @{ $c->{assigns} };
      next if $home_set && !grep { $_ eq '--system' } @rest;
      ($shapes, $errors) = load_shapes($project) unless $shapes;
      my ($ok) = GitList::match($shapes, \@rest, sub { $_[0] eq 'NAME' ? 1 : 0 });
      next if $ok;
      return ('G3', "changing git's global or system settings is refused; tell the owner what you needed");
    }
    ($shapes, $errors) = load_shapes($project) unless $shapes;
    if (@$errors) {
      return ('G3', "the git list cannot be read ($errors->[0]), so git commands in this repository are refused until it is fixed ($WAY_OUT)");
    }
    my $ask = git_asker($tdir);
    my ($shape, $why) = GitList::match($shapes, \@rest, $ask);
    if (!$shape) {
      return ('G3', 'switching branches while tracked files have uncommitted changes is refused; commit them first') if $why eq 'clean';
      return ('G3', 'merging into main here is refused; switch to your task branch, or let the owner merge on GitHub') if $why eq 'off-main';
      my $var = defined $d ? '' : ' (the folder it runs in is held in a variable, so it was judged as this project\'s repository; if it is a scratch folder, write its path out)';
      my $shown = $sub =~ /\A[a-z][a-z0-9-]{0,40}\z/ ? "\"git $sub\"" : 'this git command';
      return ('G3', "$shown in this form is not on the method's git list$var; the owner can add a shape to .claude/method-local/git-shapes.txt. Do not try another form of the same command; tell the owner what you needed");
    }
    if ($sub =~ /\A(?:switch|checkout|merge|cherry-pick|revert|worktree|pull)\z/) {
      my @v = Protect::git_versions($tdir, $sub, \@rest, $project);
      return @v if @v;
    }
    if ($sub =~ /\A(?:commit|merge|cherry-pick|revert|pull)\z/) {
      require File::Spec->catfile($lib, 'runstate.pl');
      my $p = eval { RunState::probe($tdir) };
      if (!$p || $p->{unknown} || $p->{journal} || $p->{mutate}) {
        my $what = $sub eq 'commit' ? 'this commit' : "the commit git $sub can make";
        return ('G8', "a mutate-changed run, or what one left behind, is in this repository, so $what could hold a mutant; wait for the run to end, or run bash scripts/method/mutate-changed.sh --recover, then commit");
      }
    }
  }
  return ();
}

# the checks a shape asks for, answered by git in DIR
sub git_asker {
  my ($dir) = @_;
  my %memo;
  return sub {
    my ($type, $v) = @_;
    my $key = join "\0", $type, $v // '';
    return $memo{$key} if exists $memo{$key};
    my $r = 0;
    if ($type eq 'REMOTE') { $r = remotes($dir)->{$v} ? 1 : 0 }
    elsif ($type eq 'BRANCH') {
      my ($st) = git_at($dir, 'show-ref', '--verify', '-q', "refs/heads/$v");
      $r = $st == 0 && $v !~ /\A-/ ? 1 : 0;
    } elsif ($type eq 'NEWBRANCH') {
      my ($ok) = git_at($dir, 'check-ref-format', '--branch', $v);
      my ($ex) = git_at($dir, 'show-ref', '--verify', '-q', "refs/heads/$v");
      $r = $ok == 0 && $ex != 0 && !main_names($dir)->{ lc $v } ? 1 : 0;
    } elsif ($type eq 'COMMIT') {
      # (a range is not one revision, so --verify refuses it; a word that
      # looks like an option never gets here)
      my ($st) = git_at($dir, 'rev-parse', '--verify', '-q', "$v^{commit}");
      $r = $st == 0 ? 1 : 0;
    } elsif ($type eq 'REFNAME') {
      # a branch or tag name alone: no refspec (:), pattern, force (+) or
      # folder, so a fetch can only update its own remote-tracking ref (K4)
      $r = $v =~ m{\A[A-Za-z0-9_][A-Za-z0-9_./-]*\z} && $v !~ m{\.\.|//|\.lock\z|/\z} ? 1 : 0;
    } elsif ($type eq 'MAIN') {
      my ($remote, $b) = $v =~ m{\A([^/]+)/(.+)\z};
      $r = defined $remote && remotes($dir)->{$remote} && main_names($dir)->{ lc $b } ? 1 : 0;
    } elsif ($type eq 'clean') {
      my ($st) = git_at($dir, 'diff', '--no-ext-diff', '--quiet', 'HEAD', '--');
      $r = $st == 0 ? 1 : 0;
    } elsif ($type eq 'off-main') {
      my ($st, $out) = git_at($dir, 'symbolic-ref', '-q', '--short', 'HEAD');
      chomp $out;
      $r = $st == 0 && $out ne '' && !main_names($dir)->{ lc $out } ? 1 : 0;
    }
    return $memo{$key} = $r;
  };
}

sub main {
  binmode STDIN, ':raw';
  # at most one byte over the limit is read, so a huge input is refused
  # without being held whole
  my $raw = '';
  my $max = defined $Hook::MAX ? $Hook::MAX : 4 * 1024 * 1024;
  while (length $raw <= $max) {
    my $n = read STDIN, $raw, 65536, length $raw;
    last unless $n;
  }
  open my $fh, '<', \$raw or die;
  my ($in, $err) = Hook::read_input($fh);
  if (!$in) {
    my $rule = $err =~ /JSON::PP/ ? 'G1' : 'G0';
    return refuse($rule, "the guard could not read this call ($err), so it is refused; try the call again, and if it is refused again tell the owner ($WAY_OUT)", undef, $raw, undef);
  }
  my $tool = $in->{tool_name};
  $tool = '' unless defined $tool && !ref $tool;
  my $input = $in->{tool_input};
  my $project = $ENV{CLAUDE_PROJECT_DIR};
  my $start = (defined $in->{cwd} && !ref $in->{cwd} && $in->{cwd} ne '') ? $in->{cwd} : $project;
  # G16: a settings file changed during the session (ConfigChange)
  if (($in->{hook_event_name} // '') eq 'ConfigChange') {
    require File::Spec->catfile($lib, 'watch.pl');
    my ($rule, $text) = Watch::judge_change($in, $project);
    return 0 unless $rule;
    Watch::note_refused($project);
    return refuse($rule, $text, 'ConfigChange', $raw, $in);
  }
  if ($tool eq 'PowerShell') {
    return refuse('G2', "the PowerShell tool is refused in method projects: the method's checks read bash; use the Bash tool ($WAY_OUT)", $tool, $raw, $in);
  }
  my @cmds;
  if ($tool eq 'Bash' || $tool eq 'Monitor') {
    my $cmd = ref $input eq 'HASH' ? $input->{command} : undef;
    if (!defined $cmd || ref $cmd) {
      return refuse('G0', "this $tool call has no command text the guard can read, so it is refused; give the command as plain text ($WAY_OUT)", $tool, $raw, $in);
    }
    # (line continuations joined first, as bash joins them)
    my ($text0, $joined) = Shell::join_lines($cmd);
    @cmds = Shell::commands($text0);
    my ($rule, $text) = judge_command($text0, \@cmds, $joined);
    ($rule, $text) = judge_git(\@cmds, $in) unless $rule;
    ($rule, $text) = Outside::judge_bash(\@cmds, $project, [cmd_dirs(\@cmds, defined $start ? $start : '.')]) unless $rule;
    ($rule, $text) = Protect::judge_bash(\@cmds, [cmd_dir_sets(\@cmds, defined $start ? $start : '.')], $project) unless $rule;
    return refuse($rule, $text, $tool, $raw, $in) if $rule;
  }
  if ($tool =~ /\A(?:Edit|Write|MultiEdit|NotebookEdit)\z/) {
    # (both path fields are judged; 5.7 repair loop 1)
    for my $k (qw(file_path notebook_path)) {
      my $p = ref $input eq 'HASH' ? $input->{$k} : undef;
      next unless defined $p;
      my ($rule, $text) = Protect::judge_file($p, $start, $project);
      return refuse($rule, $text, $tool, $raw, $in) if $rule;
    }
  }
  if ($tool =~ /\Amcp__/) {
    my ($rule, $text) = Protect::judge_mcp($tool, $input, $start, $project);
    ($rule, $text) = Outside::judge_mcp($tool, $input, $project) unless $rule;
    return refuse($rule, $text, $tool, $raw, $in) if $rule;
  }
  if ($tool eq 'SendMessage') {
    return refuse('G4', "messages to other agents or sessions are refused in this method: they can start work that runs without this project's hooks; tell the owner what you needed", $tool, $raw, $in);
  }
  if ($tool eq 'ExitWorktree' && ref $input eq 'HASH' && $input->{discard_changes}) {
    return refuse('G3', 'leaving a worktree with discard_changes would delete its uncommitted work; commit it first, or keep the worktree and tell the owner', $tool, $raw, $in);
  }
  # G4: a scheduled remote agent, or an agent run in a remote sandbox,
  # starts work that runs without this project's hooks (D10, D11; final
  # review of step 5)
  if ($tool eq 'RemoteTrigger') {
    return refuse('G4', "scheduled remote agents are refused in this method: they run without this project's hooks; tell the owner what you needed", $tool, $raw, $in);
  }
  if ($tool =~ /\A(?:Agent|Task)\z/ && ref $input eq 'HASH' && defined $input->{isolation} && !ref $input->{isolation} && $input->{isolation} eq 'remote') {
    return refuse('G4', "an agent in a remote sandbox runs without this project's hooks, so it is refused; run it here, without isolation remote", $tool, $raw, $in);
  }
  # G17: a skill or agent whose frontmatter declares hooks
  if ($tool =~ /\A(?:Skill|Agent|Task)\z/) {
    require File::Spec->catfile($lib, 'watch.pl');
    my ($rule, $text) = Watch::judge_def($tool, $input, $project);
    return refuse($rule, $text, $tool, $raw, $in) if $rule;
  }
  # B8 (step 5b.2): a call that writes, made while a gate runs, leaves a
  # mark for the gate's receipt (lib/receipt.pl); it prints nothing, and a
  # failure never changes the answer
  eval { Protect::call_writes($tool, \@cmds) && do { require File::Spec->catfile($lib, 'receipt.pl'); Receipt::mark($in, $tool, $input) }; 1 };
  # warnings, never refusals: G16's one-time message, G12
  my @say;
  if (defined $project && $project ne '' && -e File::Spec->catfile($project, '.method', 'local', 'settings-refused')) {
    require File::Spec->catfile($lib, 'watch.pl');
    my $note = eval { Watch::take_note($project) };
    push @say, "guard G16: $note" if $note;
  }
  my $warn = eval { Protect::effort($in, $project) };
  push @say, "guard G12: $warn" if $warn;
  return Hook::warning(@say) if @say;
  return 0;
}

return 1 if caller;
exit main();
