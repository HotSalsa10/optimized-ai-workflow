#!/usr/bin/env perl
# The guard's rule for the outside (G4, M131), step 5.8 (docs/plans/
# step5.md, section 6.2 and decisions D10, D11; DECISIONS A50, A57).
# Loaded by lib/guard.pl with require; nothing runs when it is loaded.
#
# What G4 refuses (DECISIONS A65 says where this refines the plan):
#   gh: a gh command that is not on the gh list (gh-shapes.txt beside
#     guard.sh, and the project's own .claude/method-local/gh-shapes.txt,
#     in git-shapes.txt's form, read by lib/gitlist.pl), and a gh call that
#     sets what points gh elsewhere or names a program gh runs (%GH_ENV).
#     gh alone, --version, version and help always pass, and so does
#     --help on one of gh's own commands (on an alias it runs the alias).
#     For gh api, a GET named with -X or --method is dropped first, with
#     the -f fields gh then puts in the query string.
#   curl and wget naming a GitHub host, unless they only read: a plain GET
#     or HEAD, with no data, form, upload, method, wgetrc command or config
#     file (an option by any start of its name), and no config file of
#     theirs in place that the call does not skip.
#   another Claude (D11): the claude command by any path or after any
#     carrier, npx and the like running @anthropic-ai/claude-code, and a
#     call (or a program's text) that sets CLAUDE_CONFIG_DIR,
#     CLAUDE_CODE_SIMPLE or CLAUDE_CODE_SAFE_MODE. A nested Claude runs
#     without this project's hooks; the method's own nested runs come in
#     step 6 through one wrapper the guard will know by name.
#   MCP tools (D10): read-only tools pass by name (get_*, list_*,
#     search_*, read_*, *_read), and so do the same-session tools
#     (send_later, subscribe_pr_activity, unsubscribe_pr_activity); any
#     other passes only when it is on the MCP list (mcp-tools.txt beside
#     guard.sh, and the project's own .claude/method-local/mcp-tools.txt),
#     and, unless the list marks it @anywhere, names this repository's
#     origin, no main branch, and the fields as its line says.
#   SendMessage is refused in lib/guard.pl.
#
#   Outside::judge_bash(CMDS, PROJECT) () or ('G4', TEXT)
#   Outside::judge_mcp(TOOL, INPUT, PROJECT) () or ('G4', TEXT)
package Outside;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;

my $lib = dirname(File::Spec->rel2abs(__FILE__));
our $GH_FILE = File::Spec->catfile($lib, '..', '..', '..', '.claude', 'hooks', 'method', 'gh-shapes.txt');
our $MCP_FILE = File::Spec->catfile($lib, '..', '..', '..', '.claude', 'hooks', 'method', 'mcp-tools.txt');

# GitHub's own hosts (and the hosts a write to GitHub can go through)
our $GITHUB_HOST = qr{(?:\A|[/@.:=\s'"])(?:(?:[a-z0-9-]+\.)*github\.com|(?:[a-z0-9-]+\.)*githubusercontent\.com|ghcr\.io)(?=\z|[/:?#\s'"])}i;
my %NESTED_ENV = map { $_ => 1 } qw(CLAUDE_CONFIG_DIR CLAUDE_CODE_SIMPLE CLAUDE_CODE_SAFE_MODE);
# claude as a command word in a program's text (by any path, in lower case
# as the command is typed; not .claude, claude-0, claude_x or the name in
# prose), or one of those names
our $CLAUDE_TEXT = qr{(?:\A|[\s'"`\[(,;|&=])(?:[^\s'"`]*[/\\])?claude(?i:\.exe)?(?=\z|[\s'"`\]),;|&])|\b(?:CLAUDE_CONFIG_DIR|CLAUDE_CODE_SIMPLE|CLAUDE_CODE_SAFE_MODE)\b};
# settings that point gh at another repository, host or account, bring in
# other config (aliases, extensions), or name a program gh runs (gh help
# environment); a pager of cat, or none, is fine
my %GH_ENV = map { $_ => 1 } qw(GH_REPO GH_HOST GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN GH_CONFIG_DIR XDG_CONFIG_HOME XDG_DATA_HOME GH_EDITOR GIT_EDITOR VISUAL EDITOR GH_BROWSER BROWSER GH_PAGER PAGER GH_FORCE_TTY GH_PATH GH_DEBUG);
my %GH_PAGER = map { $_ => 1 } qw(GH_PAGER PAGER);
# gh's own commands (gh 2.89): --help on one of these prints help; on an
# alias or an extension it runs a program
my %GH_BUILTIN = map { $_ => 1 } qw(agent-task alias api attestation auth browse cache codespace completion config copilot extension gist gpg-key help issue label org pr preview project release repo ruleset run search secret ssh-key status variable version workflow);
my %SAME = map { $_ => 1 } qw(send_later subscribe_pr_activity unsubscribe_pr_activity);

sub name_of {
  my ($w) = @_;
  (my $n = $w // '') =~ s{.*[/\\]}{};
  $n =~ s/\.(?:exe|cmd|bat)\z//i;
  return $n;
}

# a name safe to show in a refusal
sub shown { my ($n) = @_; return defined $n && $n =~ /\A[A-Za-z0-9._-]{1,60}\z/ ? $n : 'this tool' }

my $NO = "; tell the owner what you needed";

sub judge_bash {
  my ($cmds, $project, $dirs) = @_;
  my ($gh, $ghset);
  for my $k (0 .. $#$cmds) {
    my $c = $cmds->[$k];
    my @w = @{ $c->{words} };
    # settings that start a Claude with no project hooks, however set
    my @set = @{ $c->{assigns} || [] };
    my $n = @w ? name_of($w[0]) : '';
    push @set, grep { /=/ } @w[1 .. $#w] if $n eq 'env' || $n =~ /\A(?:export|declare|typeset|readonly|local)\z/;
    for my $a (@set) {
      next unless $a =~ /\A([A-Za-z_][A-Za-z0-9_]*)\+?=/;
      $ghset = $1 if $GH_ENV{$1} && !($GH_PAGER{$1} && $a =~ /=(?:cat)?\z/);
      next unless $NESTED_ENV{$1};
      return ('G4', "setting $1 is refused: it starts Claude without this project's hooks or rules (D11)$NO");
    }
    # an inline program, or the text piped into an interpreter, that runs
    # claude or sets one of those names (a word that is only a path, such
    # as a file the program reads, is not program text)
    if (grep { /\A(?:an inline program for|a pipe, here-document or here-string into|a program for \S+ from) / } @{ $c->{unread} || [] }) {
      my $code = join "\n", (grep { /[\s'"`()\[\];,|&=]/ } @w[1 .. $#w]), $c->{hbody} // '', $c->{pipe_from} // '';
      if ($code =~ $CLAUDE_TEXT) {
        return ('G4', "this program runs another Claude, or sets what starts one without this project's hooks (D11)$NO");
      }
    }
    next unless @w;
    if (lc $n eq 'claude') {
      return ('G4', "starting another Claude is refused: it would run without this project's hooks (D11; the method's own nested runs come in step 6)$NO");
    }
    if ($n =~ /\A(?:npx|bunx|pnpx|npm|pnpm|yarn)\z/ && grep { m{\@anthropic-ai/claude-code\b|\Aclaude-code\z} } @w[1 .. $#w]) {
      return ('G4', "running the Claude Code package is refused: it starts another Claude without this project's hooks (D11)$NO");
    }
    if ($n eq 'curl' || $n eq 'wget') {
      my $why = http_write($n, \@w, $c->{assigns} || []);
      return ('G4', "$n to GitHub may only read (a plain GET, with no data, form, upload, method or config file): $why; write to GitHub through gh's list, or tell the owner") if $why;
      next;
    }
    if ($n eq 'gh') {
      return ('G4', "setting $ghset with gh is refused: it changes which repository, host or settings gh uses$NO") if $ghset;
      my @rest = @w[1 .. $#w];
      next if !@rest || $rest[0] eq '--version' || $rest[0] eq 'version' || $rest[0] eq 'help' || $rest[0] eq '--help' || $rest[0] eq '-h';
      next if gh_help(@rest);
      $gh ||= [load_list($project, $GH_FILE, 'gh-shapes.txt')];
      my ($shapes, $errors) = @$gh;
      return ('G4', "the gh list cannot be read ($errors->[0]), so gh commands are refused until it is fixed") if @$errors;
      require File::Spec->catfile($lib, 'gitlist.pl');
      @rest = drop_get(@rest) if $rest[0] eq 'api';
      my ($ok) = GitList::match($shapes, \@rest, \&gh_ask);
      if ($ok && $rest[0] eq 'pr' && ($rest[1] // '') eq 'create' && !grep { /\A--head(?:=|\z)/ || /\A-[A-Za-z]*H/ } @rest) {
        my $why = unpushed(defined $dirs && defined $dirs->[$k] ? $dirs->[$k] : $project);
        return ('G4', "gh pr create without --head pushes the branch itself when $why, and that push is not judged; push your task branch first (git push -u origin HEAD), then run the same gh pr create, or name the branch with --head") if $why;
      }
      next if $ok;
      my $sub = join ' ', grep { /\A[a-z][a-z0-9-]*\z/ } @rest[0 .. ($#rest < 1 ? $#rest : 1)];
      return ('G4', "\"gh $sub\" in this form is not on the method's gh list (a merge, an api call that writes, a release, a secret and the like stay with the owner); the owner can add a shape to .claude/method-local/gh-shapes.txt. Do not try another form of the same command; tell the owner what you needed");
    }
  }
  return ();
}

# why gh pr create, run in DIR without --head, would push the branch
# itself: the branch has no upstream, or commits its upstream lacks (as
# of the last fetch); undef when it would not
sub unpushed {
  my ($dir) = @_;
  require File::Spec->catfile($lib, 'git.pl');
  return 'it cannot be told whether the branch is pushed' unless defined $dir;
  my ($st, $up) = Git::run('-C', $dir, 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}');
  return 'the branch has no upstream yet' unless $st == 0 && $up =~ /\S/;
  my ($st2, $n) = Git::run('-C', $dir, 'rev-list', '--count', '@{upstream}..HEAD');
  return 'it cannot be told whether the branch is pushed' unless $st2 == 0 && $n =~ /\A([0-9]+)\s*\z/;
  return $1 > 0 ? 'the branch has commits its upstream lacks' : undef;
}

# is gh's WORDS a call for help on one of gh's own commands? --help, or
# -h except under auth (where it names a host), before any "--"
sub gh_help {
  my @w = @_;
  return 0 unless $GH_BUILTIN{ $w[0] };
  for my $x (@w) {
    last if $x eq '--';
    return 1 if $x eq '--help' || ($x eq '-h' && $w[0] ne 'auth');
  }
  return 0;
}

# the checks gh's list asks for: REFNAME is a number or a branch name,
# never a URL or a repository; nothing else is asked
sub gh_ask {
  my ($type, $v) = @_;
  return 0 unless $type eq 'REFNAME' && defined $v;
  return $v =~ m{\A[A-Za-z0-9_][A-Za-z0-9._/-]*\z} && $v !~ m{\.\.|//|\.lock\z|/\z} ? 1 : 0;
}

# gh api's words without a GET or HEAD method (-X GET, -XGET, --method GET,
# --method=GET), which reads as a plain call does; when one was there, -f
# and --raw-field go too, as gh then puts them in the query string. Any
# other method stays, and so does every -F, --field and --input
sub drop_get {
  my @w = @_;
  my $get = 0;
  for my $i (0 .. $#w) {
    last if $w[$i] eq '--';
    $get = 1 if (($w[$i] eq '-X' || $w[$i] eq '--method') && $i < $#w && $w[ $i + 1 ] =~ /\A(?:GET|HEAD)\z/i) || $w[$i] =~ /\A(?:-X|--method=)(?i:GET|HEAD)\z/;
  }
  return @w unless $get;
  my @out;
  my $i = 0;
  while ($i <= $#w) {
    my $x = $w[$i];
    last if $x eq '--';
    if (($x eq '-X' || $x eq '--method' || $x eq '-f' || $x eq '--raw-field') && $i < $#w && ($x =~ /\A-(?:f|-raw-field)\z/ || $w[ $i + 1 ] =~ /\A(?:GET|HEAD)\z/i)) { $i += 2; next }
    if ($x =~ /\A(?:-X|--method=)(?i:GET|HEAD)\z/ || $x =~ /\A(?:-f.|--raw-field=)/s) { $i++; next }
    push @out, $x;
    $i++;
  }
  push @out, @w[ $i .. $#w ];
  return @out;
}

# the long options that make curl or wget write, or read their options from
# a file; both tools take a long option by any part of its name that is not
# shared with another (curl --dat, wget --post-d), so a word that is the
# start of one of these counts as it
my %WRITES = (
  curl => [qw(data data-ascii data-binary data-raw data-urlencode json form form-string upload-file config expand-data expand-json expand-form expand-form-string expand-upload-file expand-url)],
  wget => [qw(post-data post-file body-data body-file execute config)],
);
my %METHOD = (curl => 'request', wget => 'method');
# the short options that take a value
my %SHORT_VALUE = (curl => 'AbcCdDeEFHKmoPQrtTuUwxXyYz', wget => 'aABDeiIloOPQRtTUwX');
# settings the two tools read their defaults from
my %RC_ENV = map { $_ => 1 } qw(HOME CURL_HOME XDG_CONFIG_HOME APPDATA WGETRC SYSTEM_WGETRC);

# is the long option word X (--name or --name=value) the start of NAME?
sub long_is {
  my ($x, $name) = @_;
  my ($w) = $x =~ /\A--([^=]+)/ or return 0;
  return length($w) >= 2 && index($name, $w) == 0;
}

# a config file curl or wget reads by default, when there is one
sub rc_file {
  my ($n) = @_;
  my @dirs = $n eq 'curl'
    ? (grep { defined && $_ ne '' } $ENV{CURL_HOME}, $ENV{XDG_CONFIG_HOME}, $ENV{HOME}, (defined $ENV{HOME} ? "$ENV{HOME}/.config" : undef), $ENV{APPDATA})
    : ();
  for my $d (@dirs) { for my $f ('.curlrc', '_curlrc') { return $f if -e "$d/$f" } }
  if ($n eq 'wget') {
    return 'WGETRC' if defined $ENV{WGETRC} && $ENV{WGETRC} ne '' && -e $ENV{WGETRC};
    return '.wgetrc' if defined $ENV{HOME} && -e "$ENV{HOME}/.wgetrc";
  }
  return undef;
}

# why curl or wget, given WORDS and ASSIGNS, could write to GitHub, or undef
sub http_write {
  my ($n, $w, $assigns) = @_;
  return undef unless grep { $_ =~ $GITHUB_HOST } @$w[1 .. $#$w];
  my @a = @$w[1 .. $#$w];
  for my $s (@$assigns) {
    return "it sets $1, which moves the file $n reads its options from" if $s =~ /\A([A-Za-z_][A-Za-z0-9_]*)\+?=/ && $RC_ENV{$1};
  }
  my $no_rc = $n eq 'curl' ? (@a && ($a[0] eq '-q' || $a[0] eq '--disable')) : (grep { long_is($_, 'no-config') } @a);
  if (!$no_rc && defined(my $rc = rc_file($n))) {
    return "a $n config file ($rc) is there, which can make any call write; start the call with " . ($n eq 'curl' ? '-q' : '--no-config');
  }
  for my $i (0 .. $#a) {
    my $x = $a[$i];
    last if $x eq '--';
    my $next = $a[ $i + 1 ] // '';
    if ($x =~ /\A--/) {
      if (long_is($x, $METHOD{$n}) && $x !~ /\A--request-/) {
        my $m = $x =~ /=(.*)\z/s ? $1 : $next;
        return 'a method other than GET' unless $m =~ /\A(?:GET|HEAD)\z/i;
        next;
      }
      return 'data, a form, an upload or a config file' if grep { long_is($x, $_) } @{ $WRITES{$n} };
      next;
    }
    next unless $x =~ /\A-([A-Za-z0-9#:].*)\z/s;
    # a cluster of short options (-sSfL, -sXPOST): each letter in turn,
    # until one that takes a value, which is the rest of the word or the
    # next word
    my @l = split //, $1;
    while (@l) {
      my $o = shift @l;
      my $rest = join '', @l;
      if ($n eq 'curl') {
        return 'a config file (-K)' if $o eq 'K';
        return 'data, a form or an upload' if $o =~ /\A[dFT]\z/;
        if ($o eq 'X') { my $m = $rest ne '' ? $rest : $next; return 'a method other than GET' unless $m =~ /\A(?:GET|HEAD)\z/i; last }
      } else {
        return 'a wgetrc command (-e)' if $o eq 'e';
      }
      last if index($SHORT_VALUE{$n}, $o) >= 0;
    }
  }
  return undef;
}

# load_list PROJECT FILE NAME: the method's list in FILE and the project's
# own .claude/method-local/NAME, read by lib/gitlist.pl: (SHAPES, ERRORS)
sub load_list {
  my ($project, $file, $name) = @_;
  require File::Spec->catfile($lib, 'gitlist.pl');
  my (@all, @errors);
  for my $f ([$file, $name, 1], [File::Spec->catfile($project // '', '.claude', 'method-local', $name), ".claude/method-local/$name", 0]) {
    my ($path, $label, $must) = @$f;
    next if !$must && !(defined $project && -e $path);
    my $text;
    if (open my $h, '<:raw', $path) { local $/; $text = <$h>; close $h }
    if (!defined $text) { push @errors, "$label cannot be read"; next }
    my ($s, $e) = GitList::parse($text, $label);
    push @all, @$s;
    push @errors, @$e;
  }
  return (\@all, \@errors);
}

# the MCP list: { TOOL => { branch => [FIELDS], absent => [FIELDS],
# equal => { FIELD => VALUE }, anywhere => 0 or 1 } }, and errors. Each
# line:
#   TOOL CHECK... :: REASON         a write tool: its owner and repo must
#                                   be this repository's origin, and each
#                                   CHECK holds:
#                                     FIELD        a branch it writes,
#                                                  which may not be main
#                                     !FIELD       must not be given
#                                     FIELD=VALUE  must be given, as VALUE
#   TOOL @anywhere :: REASON        a tool that only reads, or acts only on
#                                   this session: no repository check
# TOOL is the name after the server's (create_pull_request, not
# mcp__github__create_pull_request)
sub load_mcp {
  my ($project) = @_;
  my (%t, @errors);
  for my $f ([$MCP_FILE, 'mcp-tools.txt', 1], [File::Spec->catfile($project // '', '.claude', 'method-local', 'mcp-tools.txt'), '.claude/method-local/mcp-tools.txt', 0]) {
    my ($path, $label, $must) = @$f;
    next if !$must && !(defined $project && -e $path);
    my $h;
    if (!open $h, '<:raw', $path) { push @errors, "$label cannot be read"; next }
    my $n = 0;
    while (my $line = <$h>) {
      $n++;
      $line =~ s/\r?\n\z//;
      next if $line =~ /\A\s*(?:#|\z)/;
      my ($shape, $reason) = $line =~ /\A\s*(.*?)\s+::\s+(.*?)\s*\z/;
      if (!defined $shape || $reason !~ /\S/) { push @errors, "$label line $n: not TOOL FIELD... :: REASON"; next }
      my ($tool, @checks) = split ' ', $shape;
      my %e = (branch => [], absent => [], equal => {}, anywhere => 0);
      my $bad = $tool !~ /\A[A-Za-z0-9_-]+\z/;
      if (@checks == 1 && $checks[0] eq '@anywhere') { $e{anywhere} = 1; @checks = () }
      for my $c (@checks) {
        if ($c =~ /\A([A-Za-z_][A-Za-z0-9_]*)\z/) { push @{ $e{branch} }, $1 }
        elsif ($c =~ /\A!([A-Za-z_][A-Za-z0-9_]*)\z/) { push @{ $e{absent} }, $1 }
        elsif ($c =~ /\A([A-Za-z_][A-Za-z0-9_]*)=([A-Za-z0-9_.-]+)\z/) { $e{equal}{$1} = $2 }
        else { $bad = 1 }
      }
      if ($bad) { push @errors, "$label line $n: cannot read \"$shape\""; next }
      $t{$tool} = \%e;
    }
    close $h;
  }
  return (\%t, \@errors);
}

# this repository's origin on GitHub: (OWNER, REPO), or ()
sub origin {
  my ($project) = @_;
  require File::Spec->catfile($lib, 'git.pl');
  my ($st, $url) = Git::run('-C', $project // '.', 'remote', 'get-url', 'origin');
  return () unless $st == 0;
  chomp $url;
  return ($1, $2) if $url =~ m{github\.com[:/]+([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?\z}i;
  # a session's git proxy (http://.../git/OWNER/REPO)
  return ($1, $2) if $url =~ m{/git/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?\z};
  return ();
}

sub judge_mcp {
  my ($tool, $input, $project) = @_;
  (my $name = $tool) =~ s/\A.*__//s;
  return () if $SAME{$name};
  return () if $name =~ /\A(?:get|list|search|read)_/ || $name =~ /_read\z/;
  my ($list, $errors) = load_mcp($project);
  return ('G4', "the MCP list cannot be read ($errors->[0]), so MCP tools that write are refused until it is fixed") if @$errors;
  my $entry = $list->{$name};
  return ('G4', "the MCP tool " . shown($name) . " is not on the method's list of outside tools (D10: tools that merge, or start, message or schedule other sessions, stay with the owner); the owner can add a line to .claude/method-local/mcp-tools.txt$NO") unless $entry;
  return () if $entry->{anywhere};
  $input = {} unless ref $input eq 'HASH';
  my ($o, $r) = origin($project);
  return ('G4', "this repository's origin on GitHub cannot be told, so the MCP tool " . shown($name) . " is refused$NO") unless defined $o;
  my ($io, $ir) = ($input->{owner}, $input->{repo});
  if (!defined $io || ref $io || !defined $ir || ref $ir || lc $io ne lc $o || lc $ir ne lc $r) {
    return ('G4', "the MCP tool " . shown($name) . " may write only to this repository ($o/$r)$NO");
  }
  for my $f (@{ $entry->{absent} }) {
    my $v = $input->{$f};
    next if !defined $v || (!ref $v && ($v eq '' || $v eq '0')) || (ref $v eq 'ARRAY' && !@$v) || (ref $v eq 'JSON::PP::Boolean' && !$v);
    return ('G4', "the MCP tool " . shown($name) . " is listed without its " . shown($f) . " field (see mcp-tools.txt for why)$NO");
  }
  for my $f (sort keys %{ $entry->{equal} }) {
    my $v = $input->{$f};
    next if defined $v && !ref $v && $v eq $entry->{equal}{$f};
    return ('G4', "the MCP tool " . shown($name) . " is listed only with $f " . $entry->{equal}{$f} . " (see mcp-tools.txt for why)$NO");
  }
  my %main = (main => 1, master => 1);
  my ($st, $head) = Git::run('-C', $project // '.', 'symbolic-ref', '-q', 'refs/remotes/origin/HEAD');
  $main{ lc $1 } = 1 if $st == 0 && $head =~ m{\Arefs/remotes/origin/(\S+)\n?\z};
  for my $f (@{ $entry->{branch} }) {
    my $b = $input->{$f};
    # (a missing branch field: a server may then write to the default
    # branch; final review of step 5)
    return ('G4', "the MCP tool " . shown($name) . " names no branch in its $f field, so where it writes cannot be told; name your task branch$NO") if !defined $b || (!ref $b && $b eq '');
    return ('G4', "the MCP tool " . shown($name) . " names a branch in a form the guard cannot judge$NO") if ref $b || $b !~ m{\A[A-Za-z0-9_][A-Za-z0-9._/-]*\z} || $b =~ m{\.\.};
    (my $short = $b) =~ s{\A(?:refs/)?heads/}{};
    return ('G4', "the MCP tool " . shown($name) . " may not write to main: the owner merges into main on GitHub; use your task branch$NO") if $main{ lc $short };
  }
  return ();
}

1;
