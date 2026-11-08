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
#   G8 mutant-commit (M133, step 5.6): git commit in this repository while
#      a mutate-changed run, or what one left behind, is there.
# A call the rules say nothing about is let through.
package Guard;
use strict;
use warnings;
use Cwd ();
use File::Basename qw(dirname);
use File::Spec;

my $lib = dirname(File::Spec->rel2abs(__FILE__));
require File::Spec->catfile($lib, 'hook.pl');
require File::Spec->catfile($lib, 'shell.pl');

our $WAY_OUT = 'if the guard is wrong, see .claude/hooks/method/README.md, "When the guard blocks something it should not"';

# what the guard watches: a call that names one may not hold a shape the
# reader cannot read (G0). A watched command is git, gh, claude, curl or
# wget standing as a word of its own (so /tmp/claude-0 or github.com do not
# count); a watched path is one of the method's files, its settings, or
# git's own config and hooks.
our $WATCHED_WORD = qr{(?:\A|[\s;&|(`'"=])(?:[\w./-]*/)?(?:git(?:-[a-z][a-z0-9-]*)?|gh|claude|curl|wget)(?=\z|[\s;&|)`'"])};
our $WATCHED_PATH = qr{\.claude/(?:hooks/method|agents/method|rules/method|method-local|settings(?:\.local)?\.json)|(?:\A|[\s/'"=])scripts/method\b|\.git/(?:hooks|config)\b|\.gitconfig\b|\.config/git\b|managed-settings}i;
our $WATCHED = qr{$WATCHED_WORD|$WATCHED_PATH};

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
my $WIDE = qr{variable as the command word|eval of anything|-c with an expansion|could not split|case statement|nested too deep|trap of anything};
# what lets an inline program start another program
our $STARTS = qr{\b(?:system|exec\w*|qx|popen\w*|spawn\w*|execSync|execFile\w*|subprocess|child_process|Popen|Runtime|ProcessBuilder|IPC::\w+|open[23]|shell_exec|passthru|proc_open|Start-Process|Invoke-Expression|iex|Process)\b|\bDeno\.(?:Command|run)\b|`|%x[\[(\x7B<]|\bos\.(?:system|popen|exec\w*|spawn\w*)|open\s*\(?[^;]*["']\s*\||\|\s*["']\s*\)|["']-\|["']|\|-|-\|};

# judge_command TEXT: () to let it through, or (RULE, TEXT) to refuse. A
# simple command the reader cannot read is refused (G0) when it runs git,
# gh, claude, curl or wget itself, or when its own text (its words, its
# here-document, what is piped into it) names something watched; for the
# shapes whose meaning can come from elsewhere ($WIDE), when the whole call
# does.
sub judge_command {
  my ($cmd, $read) = @_;
  my @cmds = $read ? @$read : Shell::commands($cmd);
  # (with ANSI-C quoting decoded, also where the reader stopped early)
  (my $decoded = $cmd) =~ s/\$'((?:[^'\\]|\\.)*)'/Shell::ansi_c($1)/ge;
  my $call_watched = join("\n", $cmd, $decoded, map { join(' ', @{ $_->{words} }, $_->{hbody} // '') } @cmds) =~ $WATCHED;
  for my $c (@cmds) {
    next unless @{ $c->{unread} };
    # (its assignments and a for header's words, as written, are its own
    # text too: what they run is judged)
    my $words = join(' ', @{ $c->{assigns_raw} || [] }, @{ $c->{raw} || [] }, @{ $c->{words} }, map { $_->[1] } @{ $c->{redirs} });
    my $own = join(' ', $words, $c->{hbody} // '', $c->{pipe_from} // '');
    my $wide = grep { $_ =~ $WIDE } @{ $c->{unread} };
    # code from a variable or a substitution, piped or written into a shell
    # or an interpreter, is not this command's own text
    $wide ||= (grep { /\Aa pipe, here-document or here-string into / } @{ $c->{unread} })
      && (($c->{pipe_from} // '') =~ /[\$`]/ || ($c->{hbody} // '') =~ /[\$`]/) ? 1 : 0;
    my $inline_only = !grep { $_ !~ /\Aan inline program for / } @{ $c->{unread} };
    my $glob_only = !grep { $_ ne 'a glob or a brace in a write target' } @{ $c->{unread} };
    # (a command that runs git, gh, claude, curl or wget names it in its
    # own text, so it is caught below)
    # (PowerShell's inline program is shell commands: a watched word runs)
    my $shell_like = @{ $c->{words} } && $c->{words}[0] =~ m{(?:\A|[/\\])(?:pwsh|powershell)(?:\.exe)?\z}i;
    # a glob or brace in the command word hides which program runs at all
    my $hit = (grep { $_ eq 'a glob or a brace in the command word' } @{ $c->{unread} }) ? 1
      : $wide ? $call_watched
      # an inline program: what is piped into it is data, not code; it
      # touches a watched command only by starting a program
      : $inline_only ? ($words =~ $WATCHED_PATH || ($words =~ $WATCHED_WORD && ($shell_like || $words =~ $STARTS)))
      # a glob can hide which file is written: any write near the method's
      # folders or git's own
      : $glob_only ? (join(' ', map { $_->[1] } grep { $_->[0] =~ />/ } @{ $c->{redirs} }) =~ m{\.claude|scripts/method|\.git\b|gitconfig}i || $own =~ $WATCHED)
      : $own =~ $WATCHED;
    next unless $hit;
    my $why = $c->{unread}[0];
    if (grep { $_ eq 'a glob or a brace in the command word' } @{ $c->{unread} }) {
      return ('G0', "this command's name holds a glob or a brace, so which program runs cannot be told; write the program's name out ($WAY_OUT)");
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
    } else { @urls = ($target) }
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
  my $form = 'only git push [-q] [-u] <remote> HEAD, HEAD:<branch>, <branch> or <branch>:<branch> is allowed';
  return "$bad is refused on a push; $form" if defined $bad;
  return "this push names no remote and branch; $form" unless @pos == 2;
  return "\"$target\" is not one of this repository's remotes; $form" unless $rem->{$target};
  my $spec = $pos[1];
  return "a forced, deleting or pattern push is refused; $form" if $spec =~ /\A\+|\A:|\*/;
  my ($src, $dst) = $spec =~ /\A([^:]+)(?::(.+))?\z/ or return "this push's branch cannot be read; $form";
  if ($src eq 'HEAD') {
    my ($st, $out) = git_at($dir, 'symbolic-ref', '-q', '--short', 'HEAD');
    chomp $out;
    return 'HEAD is not on a branch, so where this push goes cannot be told; switch to your task branch first' if $st != 0 || $out eq '';
    $dst //= $out;
  } else {
    return "\"$src\" is not a local branch; $form" if $src =~ /\A-/ || $src =~ m{\Arefs/(?!heads/)};
    (my $b = $src) =~ s{\Arefs/heads/}{};
    my ($st) = git_at($dir, 'show-ref', '--verify', '-q', "refs/heads/$b");
    return "\"$src\" is not a local branch; $form" if $st != 0;
    my ($sym) = git_at($dir, 'symbolic-ref', '-q', "refs/heads/$b");
    return "\"$src\" is a symbolic ref, so where this push goes cannot be told; push your task branch by its own name" if $sym == 0;
    $dst //= $b;
  }
  $dst =~ s{\A(?:refs/)?heads/}{};
  return "this push goes to $dst, which is not a branch; $form" if $dst =~ m{\Arefs/} || $dst eq '' || $dst =~ /\A-/;
  return "pushing to $dst is refused: the owner merges into main on GitHub (until review receipts exist, step 6); push your task branch instead"
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
      my ($sub) = grep { !/\A-/ } @w[1 .. $#w];
      next unless defined $sub && $PUSH_MOVES{$sub};
      return "a push may not share its Bash call with git $sub, which can move what it sends; run the push on its own";
    }
    return 'a push may not share its Bash call with a command that names git\'s own folder; run the push on its own'
      if grep { m{(?:\A|/)\.git(?:/|\z)} } (@w, map { $_->[1] } @{ $o->{redirs} });
  }
  return ();
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
  my $session_top;
  my ($shapes, $errors);
  my %dir;    # scope => folder, or undef when it cannot be told
  my $dir_of;
  $dir_of = sub {
    my ($s) = @_;
    return $dir{$s} if exists $dir{$s};
    (my $p = $s) =~ s{/[^/]*\z}{};
    return $dir{$s} = $p eq $s ? $start : $dir_of->($p);
  };
  for my $c (@$cmds) {
    my @w = @{ $c->{words} };
    next unless @w;
    my $scope = defined $c->{scope} ? $c->{scope} : 't';
    my $here = $dir_of->($scope);
    if (($w[0] eq 'cd' || $w[0] eq 'pushd') && !$c->{piped} && !$c->{to_pipe} && !$c->{bg}) {
      my ($to) = grep { !/\A-/ } @w[1 .. $#w];
      my ($raw) = grep { !/\A-/ } @{ $c->{raw} }[1 .. $#{ $c->{raw} }];
      if (!defined $to) { $dir{$scope} = $ENV{HOME} }
      elsif (defined $raw && $raw =~ /[\$`]/) { $dir{$scope} = undef }
      elsif (!defined $here) { $dir{$scope} = $to =~ m{\A/} ? $to : undef }
      else { $to =~ s{\A~(?=/|\z)}{$ENV{HOME} // '~'}e; $dir{$scope} = File::Spec->rel2abs($to, $here) }
      next;
    }
    if ($w[0] eq 'popd') { $dir{$scope} = undef; next }
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
        if (($r[ $i + 1 ] // '') =~ /[\$`]/) { $d = undef }
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
      return ('G3', "git's option $o is refused (it can point git at another repository or settings); not on the method's git list, and the owner can add a shape to .claude/method-local/git-shapes.txt");
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
    if ($other_c && ($is_session || $sub eq 'push')) {
      return ('G3', "git -c with that setting is refused (it can run a program or change where git writes); only core.quotepath, color.*, user.name, user.email and commit.gpgsign may be set with -c");
    }
    if ($sub eq 'push') {
      my ($why) = push_rule($tdir, [@rest[1 .. $#rest]], $is_session ? 1 : 0, $session, $c, $cmds);
      return ('G3', "$why. Do not try another form of the same push; tell the owner what you needed") if $why;
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
      return ('G3', "\"git $sub\" in this form is not on the method's git list$var; the owner can add a shape to .claude/method-local/git-shapes.txt. Do not try another form of the same command; tell the owner what you needed");
    }
    if ($sub eq 'commit') {
      require File::Spec->catfile($lib, 'runstate.pl');
      my $p = eval { RunState::probe($tdir) };
      if (!$p || $p->{unknown} || $p->{journal} || $p->{mutate}) {
        return ('G8', 'a mutate-changed run, or what one left behind, is in this repository, so this commit could hold a mutant; wait for the run to end, or run bash scripts/method/mutate-changed.sh --recover, then commit');
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
  if ($tool eq 'PowerShell') {
    return refuse('G2', "the PowerShell tool is refused in method projects: the method's checks read bash; use the Bash tool ($WAY_OUT)", $tool, $raw, $in);
  }
  if ($tool eq 'Bash' || $tool eq 'Monitor') {
    my $cmd = ref $input eq 'HASH' ? $input->{command} : undef;
    if (!defined $cmd || ref $cmd) {
      return refuse('G0', "this $tool call has no command text the guard can read, so it is refused; give the command as plain text ($WAY_OUT)", $tool, $raw, $in);
    }
    my @cmds = Shell::commands($cmd);
    my ($rule, $text) = judge_command($cmd, \@cmds);
    ($rule, $text) = judge_git(\@cmds, $in) unless $rule;
    return refuse($rule, $text, $tool, $raw, $in) if $rule;
  }
  if ($tool eq 'ExitWorktree' && ref $input eq 'HASH' && $input->{discard_changes}) {
    return refuse('G3', 'leaving a worktree with discard_changes would delete its uncommitted work; commit it first, or keep the worktree and tell the owner', $tool, $raw, $in);
  }
  return 0;
}

return 1 if caller;
exit main();
