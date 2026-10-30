#!/usr/bin/env perl
# The status report (M001, M003, M077). Started by status.sh, which
# documents the areas, the words and the exit codes. Read-only: it writes
# no file, and git runs through lib/git.pl (no index refresh, no file-system
# monitor). The only network call is gh, in the ci area.
package Status;
use strict;
use warnings;
use File::Basename qw(dirname basename);
use File::Spec;
use IPC::Open2 ();
use POSIX ();
use Time::HiRes ();

my $lib = dirname(File::Spec->rel2abs(__FILE__));
require File::Spec->catfile($lib, $_) for qw(git.pl esc.pl conf.pl verdicts.pl checks.pl);

# the records every project keeps (step 7's templates must match this list)
my @RECORDS = qw(CLAUDE.md AGENTS.md SPEC.md TASKS.md DECISIONS.md ROADMAP.md RISKS.md CHANGELOG.md TESTS.md);
my $CI_SECONDS = 15;
my $VERSION_SECONDS = 10;

my (%look, @skipped_areas, @order);

# say_area AREA WORD DETAIL: one report line, escaped
sub say_area {
  my ($area, $word, $detail) = @_;
  print Esc::line("$area: $word - $detail"), "\n";
  push @order, $area unless grep { $_ eq $area } @order;
  $look{$area} = 1 if $word eq 'LOOK';
  push @skipped_areas, $area if $word eq 'SKIPPED' && !grep { $_ eq $area } @skipped_areas;
}

# area NAME CODE: runs one area; CODE returns [AREA, WORD, DETAIL] lines. An
# area that dies is a LOOK with its message, and the next area runs.
sub area {
  my ($name, $code) = @_;
  my @lines = eval { $code->() };
  if ($@) {
    (my $e = $@) =~ s/\n\z//;
    @lines = ([$name, 'LOOK', "could not be checked: $e"]);
  }
  say_area(@$_) for @lines;
}

sub short { return substr($_[0], 0, 7) }

# names LIST: up to 3 names, then "and N more"
sub names {
  my @n = @_;
  return join(', ', @n) if @n <= 3;
  return join(', ', @n[0 .. 2]) . ' and ' . (@n - 3) . ' more';
}

# run_limited DEADLINE ENV ARGV...: (status, stdout) of ARGV, with stdin and
# stderr on the null device, or () when it is still running at DEADLINE (a
# Time::HiRes time). Then it and the processes it started are stopped, and
# so are any it left behind when it ends.
sub run_limited {
  my ($deadline, $env, @argv) = @_;
  pipe(my $r, my $w) or return;
  my $pid = fork;
  return unless defined $pid;
  if (!$pid) {
    close $r;
    eval { setpgrp(0, 0) };
    %ENV = %$env if $env;
    open STDIN, '<', File::Spec->devnull;
    open STDOUT, '>&', $w or POSIX::_exit(127);
    open STDERR, '>', File::Spec->devnull;
    exec { $argv[0] } @argv or POSIX::_exit(127);
  }
  close $w;
  binmode $r;
  my ($out, $eof, $status) = ('', 0, undef);
  while (1) {
    if (!defined $status && waitpid($pid, POSIX::WNOHANG()) == $pid) { $status = $? }
    my $left = $deadline - Time::HiRes::time();
    last if $left <= 0 || ($eof && defined $status);
    if ($eof) { Time::HiRes::sleep(0.05); next }
    my $rin = '';
    vec($rin, fileno($r), 1) = 1;
    # once the process has ended, only what is already written is read
    my $n = select(my $rout = $rin, undef, undef, defined $status ? 0 : ($left < 0.1 ? $left : 0.1));
    if ($n > 0) {
      my $got = sysread $r, my $buf, 65536;
      if ($got) { $out .= $buf } else { $eof = 1 }
    } elsif (defined $status) {
      $eof = 1;
    }
  }
  close $r;
  if (defined $status) {
    kill 'TERM', -$pid;    # whatever it left running in its process group
    return ($status, $out);
  }
  kill 'TERM', -$pid or kill 'TERM', $pid;
  my $until = Time::HiRes::time() + 1;
  while (waitpid($pid, POSIX::WNOHANG()) != $pid) {
    if (Time::HiRes::time() > $until) { kill 'KILL', -$pid or kill 'KILL', $pid; waitpid $pid, 0; last }
    Time::HiRes::sleep(0.05);
  }
  return;
}

# on_path NAME: the full path of the program NAME on PATH, or undef. Only
# absolute PATH entries count, so a program in the repository (./gh) never
# runs.
sub on_path {
  my ($name) = @_;
  for my $d (split /:/, defined $ENV{PATH} ? $ENV{PATH} : '') {
    next unless File::Spec->file_name_is_absolute($d);
    for my $f ("$d/$name", "$d/$name.exe") { return $f if -f $f && -x _ }
  }
  return undef;
}

# --- work: what is not committed or not pushed ---

# worktrees GIT...: the repository's working trees, the main one first, each
# a hash of the `git worktree list --porcelain` attributes
sub worktrees {
  my @g = @_;
  my ($st, $out) = Git::run(@g, 'worktree', 'list', '--porcelain', '-z');
  my ($rec_sep, $attr_sep) = ("\0\0", "\0");
  if ($st) {    # git older than 2.36 has no -z
    $out = Git::ok(@g, 'worktree', 'list', '--porcelain');
    ($rec_sep, $attr_sep) = ("\n\n", "\n");
  }
  my @w;
  for my $rec (split /\Q$rec_sep\E/, $out) {
    my %a;
    for my $attr (split /\Q$attr_sep\E/, $rec) {
      my ($k, $v) = split / /, $attr, 2;
      $a{$k} = defined $v ? $v : 1 if length $k;
    }
    push @w, \%a if defined $a{worktree};
  }
  return @w;
}

# work_lines AREA DIR: the work report for the repository whose working
# tree has its top at DIR
sub work_lines {
  my ($area, $dir) = @_;
  my @g = ('-C', $dir);
  my @wts = worktrees(@g);
  die "git worktree list gave nothing\n" unless @wts;
  # for a submodule, or a repository made with --separate-git-dir, git
  # lists the repository's own folder as the main working tree; when DIR is
  # the main working tree (its git folder is the shared one), DIR is used
  my ($gd, $cd) = map { [stat File::Spec->rel2abs($_, $dir)] } split /\n/,
    Git::ok(@g, 'rev-parse', '--git-dir', '--git-common-dir');
  $wts[0]{worktree} = $dir if !$wts[0]{bare} && @$gd && @$cd && $gd->[0] == $cd->[0] && $gd->[1] == $cd->[1];
  my (@parts, @linked);
  for my $i (0 .. $#wts) {
    my $wt = $wts[$i];
    my $where = $i ? 'worktree ' . $wt->{worktree} . ': ' : '';
    push @linked, $wt->{worktree} if $i;
    if ($wt->{prunable} || ($i && !-d $wt->{worktree})) {
      push @parts, "${where}its folder is gone (git worktree prune removes the entry)";
      next;
    }
    next if $wt->{bare};
    my @wg = (@g, '-C', $wt->{worktree});
    my @subs = Git::submodules($wt->{worktree});
    # (a filter set only inside a submodule is off too: Git::status_options_all)
    my $st = Git::ok(@wg, Git::status_options_all($wt->{worktree}, \@subs), 'status', '--porcelain=v1', '-z',
      '--no-renames', '--untracked-files=normal', '--ignore-submodules=none');
    my $n = () = $st =~ /\0/g;
    push @parts, "$where$n uncommitted entries (a new folder counts once)" if $n;
    my ($marked, $missing) = (0, 0);
    push @parts, "${where}submodule $_->[0]: $_->[2]" for grep { defined $_->[2] } @subs;
    for my $e (Git::flagged($wt->{worktree}, \@subs)) {
      my ($path, $tag) = @$e;
      if ($tag =~ /\A[a-z]\z/) { $marked++; next }
      if (-e "$wt->{worktree}/$path" || -l "$wt->{worktree}/$path") { $marked++ } else { $missing++ }
    }
    push @parts, "$where$marked files are marked so git does not compare them (assume-unchanged or skip-worktree, also"
      . ' inside submodules)' if $marked;
    # a deletion hidden this way would drop a test from every local run
    push @parts, "$where$missing tracked files are not on disk and are marked skip-worktree, so git does not show them"
      . ' as deleted (a sparse checkout does this too)' if $missing;
    my @what = (['MERGE_HEAD', 'a merge'], ['rebase-merge', 'a rebase'], ['rebase-apply', 'a rebase or am'],
      ['CHERRY_PICK_HEAD', 'a cherry-pick'], ['REVERT_HEAD', 'a revert'], ['BISECT_LOG', 'a bisect']);
    my @paths = split /\n/, Git::ok(@wg, 'rev-parse', map { ('--git-path', $_->[0]) } @what);
    for my $k (0 .. $#what) {
      next unless defined $paths[$k];
      my $p = File::Spec->rel2abs($paths[$k], $wt->{worktree});
      push @parts, "$where$what[$k][1] is in progress" if -e $p;
    }
  }
  my ($sst, $stashes) = Git::run(@g, 'rev-list', '--walk-reflogs', 'refs/stash');
  my $ns = 0;
  $ns = () = $stashes =~ /\n/g unless $sst;
  push @parts, "$ns stashes (git stash list)" if $ns;
  my @remotes = grep { length } split /\n/, Git::ok(@g, 'remote');
  my @heads = map { $_->{HEAD} } grep { $_->{HEAD} && $_->{HEAD} =~ /[1-9a-f]/ && !$_->{prunable} && !$_->{bare} } @wts;
  my $unpushed = Git::ok(@g, 'rev-list', '--count', @heads, '--branches', '--not', '--remotes');
  $unpushed =~ s/\s+\z//;
  if (!@remotes) {
    push @parts, "no remote: nothing is backed up ($unpushed commits)" if $unpushed;
  } elsif ($unpushed) {
    my @where;
    for my $l (split /\n/, Git::ok(@g, 'for-each-ref', '--format=%(refname)%00%(upstream:track)', 'refs/heads/')) {
      my ($ref, $track) = split /\0/, $l, 2;
      my $n = Git::ok(@g, 'rev-list', '--count', $ref, '--not', '--remotes');
      next unless $n =~ /[1-9]/;
      (my $name = $ref) =~ s{\Arefs/heads/}{};
      push @where, $name . (defined $track && $track =~ /gone/ ? ' (its remote branch is gone)' : '');
    }
    for my $wt (grep { $_->{detached} && $_->{HEAD} } @wts) {
      my $n = Git::ok(@g, 'rev-list', '--count', $wt->{HEAD}, '--not', '--branches', '--remotes');
      push @where, 'a detached HEAD in ' . $wt->{worktree} if $n =~ /[1-9]/;
    }
    push @parts, "$unpushed commits not pushed" . (@where ? ' (on ' . names(@where) . ')' : '') . ', as of the last fetch';
  }
  my $wtlist = @linked ? '; linked worktrees: ' . names(@linked) : '';
  return [$area, 'LOOK', join('; ', @parts) . $wtlist] if @parts;
  return [$area, 'PASS', 'nothing uncommitted, nothing unpushed (as of the last fetch)' . $wtlist];
}

# --- verdicts: every commit on main's first-parent history since the start ---

# exact REF: the commit a ref of exactly the full name REF points at, or
# undef. git's usual lookup would also take refs/tags/REF or refs/heads/REF
# when REF itself does not exist, so a branch or tag named
# refs/remotes/origin/main could stand in for main.
# masked TEXT: TEXT with keys, credentials and personal data masked, by
# secrets.pl --mask (control characters come back escaped)
sub masked {
  my ($text) = @_;
  my ($out, $in);
  my $pid = eval { IPC::Open2::open2($out, $in, $^X, File::Spec->catfile($lib, 'secrets.pl'), '--mask') };
  die "cannot run the masking step\n" unless $pid;
  binmode $in;
  binmode $out;
  print {$in} "$text\n";
  close $in;
  my $line = <$out>;
  close $out;
  waitpid $pid, 0;
  die "the masking step failed\n" if $? || !defined $line || $line !~ /\A  (.*)\n\z/s;
  return $1;
}

# subject MESSAGE: its first non-blank line, at most 60 characters
# subject MESSAGE: its first non-blank line, masked whole (a key cut first
# could be too short for its rule), then cut to 60 characters, never inside
# an escape
sub subject {
  my ($m) = @_;
  my ($s) = grep { /\S/ } split /\r?\n/, $m;
  my $t = masked(defined $s ? $s : '');
  my $copy = $t;
  my $chars = utf8::decode($copy);
  return $t if length $copy <= 60;
  $copy = substr($copy, 0, 57);
  $copy =~ s/\\(?:x[0-9A-F]?|u(?:\{[0-9A-F]*)?)?\z//;
  utf8::encode($copy) if $chars;
  return "$copy...";
}

sub verdicts_lines {
  my ($conf) = @_;
  my $note = 'task-branch commits are not read; done-check checks the change at merge';
  my ($ref, $tip) = Git::main_ref();
  return ['verdicts', 'SKIPPED', 'no main branch (' . Git::no_main() . "); $note"] unless defined $ref;
  my ($key) = Verdicts::words('trailer-key', Verdicts::rows());
  my $j = Verdicts::judged($tip, $conf->{VERDICTS_FROM});
  my $shallow = $j->{shallow} ? '; shallow history: older commits not read' : '';
  my (@range, $since);
  if (defined $conf->{VERDICTS_FROM}) {
    return ['verdicts', 'SKIPPED', "VERDICTS_FROM in .claude/method.conf is not in this shallow history of $ref;"
      . ' fetch more history (git fetch --unshallow)'] if $j->{problem} && $shallow;
    return ['verdicts', 'LOOK', "VERDICTS_FROM in .claude/method.conf is not on ${ref}'s first-parent history"]
      if $j->{problem};
    @range = @{ $j->{ids} };
    $since = 'after ' . short($conf->{VERDICTS_FROM});
    return ['verdicts', 'SKIPPED', "no commit on $ref $since yet, so there was nothing to check"] unless @range;
  } else {
    return ['verdicts', 'SKIPPED', "no commit on $ref carries a $key line yet; $note$shallow"] unless @{ $j->{ids} };
    @range = @{ $j->{ids} };
    $since = 'since ' . short($j->{start});
  }
  my @bad = grep { defined Verdicts::trailer_problem(Git::message($_)) } @range;
  if (@bad) {
    my $old = $bad[-1];
    my @show = map { short($_) } @bad[0 .. ($#bad < 4 ? $#bad : 4)];
    return ['verdicts', 'LOOK', scalar(@bad) . " commits on $ref $since lack a valid $key line: @show"
      . (@bad > 5 ? ' ...' : '') . '; the oldest, "' . subject(Git::message($old)) . '": '
      . Verdicts::trailer_problem(Git::message($old))
      . '; accept them by moving VERDICTS_FROM in .claude/method.conf through a reviewed change; never rewrite main'
      . $shallow];
  }
  # in a shallow history the first verdict may be older than what is here
  return ['verdicts', 'SKIPPED', scalar(@range) . " commits on $ref $since carry a $key line, but the history is"
    . ' shallow, so older commits were not read; fetch more history or set VERDICTS_FROM'] if $shallow;
  return ['verdicts', 'PASS', scalar(@range) . " commits on $ref $since carry a $key line"];
}

# --- records ---

sub records_lines {
  my @lines;
  my @missing = grep { !-f $_ } @RECORDS;
  my @parts;
  push @parts, 'missing: ' . join(', ', @missing) if @missing;
  if (-f 'CLAUDE.md') {
    open my $fh, '<:raw', 'CLAUDE.md' or die "cannot read CLAUDE.md\n";
    my $import = grep { /\A\@AGENTS\.md[ \t]*\r?\n?\z/ } <$fh>;
    close $fh;
    push @parts, 'CLAUDE.md has no line @AGENTS.md, so AGENTS.md is not loaded' unless $import;
  }
  my ($checks, $problems) = Checks::read_tsv('.');
  push @parts, $_ for @$problems[0 .. ($#$problems < 2 ? $#$problems : 2)];
  push @parts, 'and ' . (@$problems - 3) . ' more checks file problems' if @$problems > 3;
  push @parts, "$_ is ignored by git, so a clone would not have it" for Conf::ignored_inputs('.');
  my $named = '';
  if (@$checks && -f 'TESTS.md') {
    open my $fh, '<:raw', 'TESTS.md' or die "cannot read TESTS.md\n";
    my $tests = do { local $/; <$fh> };
    close $fh;
    my @absent = grep { index($tests, "`$_`") < 0 } map { $_->{id} } @$checks;
    push @parts, 'TESTS.md does not name ' . names(map {"`$_`"} @absent) if @absent;
    $named = '; TESTS.md names all ' . scalar(@$checks) . ' checks' unless @absent;
  } elsif (!@$checks && !@$problems) {
    $named = '; checks/*.tsv lists no checks';
  }
  return ['records', 'LOOK', join('; ', @parts)] if @parts;
  return ['records', 'PASS', scalar(@RECORDS) . " records present; CLAUDE.md imports AGENTS.md$named"];
}

# --- Claude Code, its effort setting, perl ---

sub claude_code_lines {
  my $p = $ENV{CLAUDE_CODE_EXECPATH};
  return ['claude-code', 'SKIPPED', 'not run inside Claude Code (CLAUDE_CODE_EXECPATH is not set)']
    unless defined $p && $p ne '';
  return ['claude-code', 'SKIPPED', 'CLAUDE_CODE_EXECPATH is not an absolute path, so it was not run']
    unless File::Spec->file_name_is_absolute($p);
  my ($req, $problems) = Conf::requires(dirname($lib));
  die "$problems->[0]\n" if @$problems;
  my $floor = $req->{claude_code_min};
  die "REQUIRES has no claude_code_min\n" unless defined $floor;
  my ($st, $out) = run_limited(Time::HiRes::time() + $VERSION_SECONDS, undef, $p, '--version');
  return ['claude-code', 'SKIPPED', 'the version could not be read'] unless defined $st && !$st;
  my ($first) = split /\n/, $out;
  my @v = defined $first ? $first =~ /\A(\d+)\.(\d+)\.(\d+)\S* \(Claude Code\)\s*\z/ : ();
  return ['claude-code', 'SKIPPED', 'the version could not be read'] unless @v;
  my @f = split /\./, $floor;
  my $cmp = 0;
  for my $i (0 .. 2) { $cmp ||= $v[$i] <=> $f[$i] }
  my $have = join '.', @v;
  return ['claude-code', 'LOOK', "$have is below the floor $floor; update Claude Code"] if $cmp < 0;
  return ['claude-code', 'PASS', "$have, floor $floor"];
}

sub effort_lines {
  return ['effort', 'LOOK', 'CLAUDE_CODE_EFFORT_LEVEL is set; it overrides every per-role effort (DECISIONS A4);'
    . ' remove it where it is set and start a new session'] if exists $ENV{CLAUDE_CODE_EFFORT_LEVEL};
  return ['effort', 'SKIPPED', "not run inside Claude Code; its settings' variables are not visible here"]
    unless defined $ENV{CLAUDE_CODE_EXECPATH} && $ENV{CLAUDE_CODE_EXECPATH} ne '';
  return ['effort', 'PASS', 'CLAUDE_CODE_EFFORT_LEVEL is not set'];
}

sub perl_lines {
  my @missing;
  for my $m (qw(JSON::PP Digest::SHA)) {
    (my $file = "$m.pm") =~ s{::}{/}g;
    push @missing, $m unless eval { require $file; 1 };
  }
  return ['perl', 'LOOK', 'cannot load ' . join(' and ', @missing) . '; install the perl core modules'] if @missing;
  return ['perl', 'PASS', "JSON::PP $JSON::PP::VERSION and Digest::SHA load"];
}

# --- ci: the newest runs for HEAD and main's tip, through gh ---

# ci_judge SHA JSON: (word, detail) for one commit
sub ci_judge {
  my ($sha, $json) = @_;
  my $runs = eval { JSON::PP->new->decode($json) };
  return ('SKIPPED', 'unexpected gh output') unless ref $runs eq 'ARRAY';
  return ('SKIPPED', 'no CI run for ' . short($sha)) unless @$runs;
  my (%newest, @names);
  for my $run (@$runs) {
    return ('SKIPPED', 'unexpected gh output')
      unless ref $run eq 'HASH' && defined $run->{headSha} && !ref $run->{headSha} && $run->{headSha} eq $sha;
    my $name = defined $run->{workflowName} && !ref $run->{workflowName} ? $run->{workflowName} : '?';
    next if $newest{$name};
    $newest{$name} = $run;
    push @names, $name;
  }
  my @failed;
  for my $name (@names) {
    my $run = $newest{$name};
    my ($status, $c) = map { defined $_ && !ref $_ ? $_ : '' } $run->{status}, $run->{conclusion};
    push @failed, "$name: " . ($c ne '' ? $c : 'no conclusion')
      if $status eq 'completed' && $c !~ /\A(?:success|skipped|neutral)\z/;
  }
  return ('LOOK', names(@failed) . ' for ' . short($sha)) if @failed;
  my @running = grep { (defined $newest{$_}{status} ? $newest{$_}{status} : '') ne 'completed' } @names;
  return ('SKIPPED', 'still running for ' . short($sha) . ': ' . names(@running)) if @running;
  return ('PASS', scalar(@names) . ' workflows passed for ' . short($sha));
}

sub ci_lines {
  my ($st, $url) = Git::run('config', '--get', 'remote.origin.url');
  $url =~ s/\n\z//;
  return ['ci', 'SKIPPED', 'origin is not on github.com']
    if $st || $url !~ m{\A(?:https://(?:[^/@\s]+@)?github\.com/|ssh://(?:[^/@\s]+@)?github\.com(?::[0-9]+)?/|git\@github\.com:)\S+\z}i;
  my $gh = on_path('gh');
  return ['ci', 'SKIPPED', 'gh is not installed'] unless $gh;
  return ['ci', 'SKIPPED', 'JSON::PP cannot be loaded (see perl)'] unless eval { require JSON::PP; 1 };
  my %env = %ENV;
  delete $env{GH_REPO};
  @env{qw(GH_PROMPT_DISABLED GH_NO_UPDATE_NOTIFIER NO_COLOR)} = (1, 1, 1);
  my $deadline = Time::HiRes::time() + $CI_SECONDS;
  my @want;
  my ($hst, $head) = Git::run('rev-parse', '-q', '--verify', 'HEAD^{commit}');
  return ['ci', 'SKIPPED', 'no commit yet'] if $hst;
  push @want, ['', (split /\n/, $head)[0]];
  my ($ref, $tip) = Git::main_ref();
  push @want, ['main: ', $tip] if defined $tip && $tip ne $want[0][1];
  my (@details, %words);
  for my $w (@want) {
    my ($label, $sha) = @$w;
    my @r = run_limited($deadline, \%env, $gh, 'run', 'list', '-R', $url, '--commit', $sha, '--limit', '100', '--json',
      'workflowName,status,conclusion,headSha');
    return ['ci', 'SKIPPED', "gh did not answer within $CI_SECONDS seconds"] unless @r;
    return ['ci', 'SKIPPED', 'gh failed (not signed in, offline, or no access?)'] if $r[0];
    my ($word, $detail) = ci_judge($sha, $r[1]);
    $words{$word} = 1;
    push @details, "$label$detail";
  }
  my $word = $words{LOOK} ? 'LOOK' : $words{SKIPPED} ? 'SKIPPED' : 'PASS';
  return ['ci', $word, join('; ', @details)];
}

# --- other repositories ---

sub repo_lines {
  my ($top, $entry) = @_;
  my $area = "repo $entry";
  my $path = File::Spec->catdir($top, $entry);
  if (!-e $path) {
    return [$area, 'SKIPPED', 'not in this session (a cloud session holds one repository)']
      if ($ENV{CLAUDE_CODE_REMOTE} || '') eq 'true';
    return [$area, 'LOOK', 'not found; clone it there or remove it from REPOS in .claude/method.conf'];
  }
  # (lib/git.pl's safe.bareRepository=explicit: a folder holding a bare
  # repository's files is never read as one)
  my @g = ('-C', $path);
  my ($st, $out) = Git::run(@g, 'rev-parse', '--is-inside-work-tree', '--show-prefix');
  return [$area, 'LOOK', 'not the top folder of a git working tree'] unless !$st && $out eq "true\n\n";
  return work_lines($area, $path);
}

sub main {
  binmode STDOUT, ':raw';
  binmode STDERR, ':raw';
  $| = 1;
  if (@ARGV) {
    print "status: usage: status.sh (it takes no arguments)\n";
    exit 2;
  }
  my ($top, $elsewhere) = Git::top();
  if (!defined $top) {
    print "status: not inside a git working tree (or git refuses this one: owned by another user, or a damaged .git)\n";
    exit 2;
  }
  chdir $top or do { print "status: cannot enter the top folder of the repository\n"; exit 2 };
  # the full name, shortened here: git's own short form turns into
  # heads/main when a tag is also called main
  my ($bst, $branch) = Git::run('symbolic-ref', '-q', 'HEAD');
  $branch =~ s/\n\z//;
  $branch =~ s{\Arefs/heads/}{};
  my ($hst, $head) = Git::run('rev-parse', '-q', '--verify', 'HEAD^{commit}');
  print Esc::line('status: ' . basename($top) . ' on ' . ($bst ? 'a detached HEAD' : $branch) . ' at '
    . ($hst ? 'no commit yet' : short($head))), "\n";

  # git reads a working tree elsewhere when a core.worktree setting says so;
  # everything below is then about that folder, not this one
  say_area('work', 'LOOK', "git's working folder is $top, not this folder: a core.worktree setting points git"
    . ' elsewhere (or a .git here is damaged), so what follows is about that folder') if $elsewhere;
  my ($conf, $problems) = Conf::read('.');
  if (@$problems) {
    say_area('config', 'LOOK', $_) for @$problems[0 .. ($#$problems < 2 ? $#$problems : 2)];
    say_area('config', 'LOOK', 'and ' . (@$problems - 3) . ' more') if @$problems > 3;
  }
  area('work', sub { work_lines('work', $top) });
  area('verdicts', sub { verdicts_lines($conf) });
  area('records', \&records_lines);
  area('claude-code', \&claude_code_lines);
  area('effort', \&effort_lines);
  area('perl', \&perl_lines);
  area('ci', \&ci_lines);
  for my $entry (@{ $conf->{REPOS} || [] }) {
    area("repo $entry", sub { repo_lines($top, $entry) });
  }
  say_area('repos', 'SKIPPED', '.claude/method.conf has problems, so REPOS entries on those lines were not checked')
    if @$problems;

  my @looks = grep { $look{$_} } @order;
  my $skips = @skipped_areas ? '; ' . scalar(@skipped_areas) . ' SKIPPED (' . join(', ', @skipped_areas) . ')' : '';
  my $last = @looks ? 'status: ' . scalar(@looks) . ' areas need a look (' . join(', ', @looks) . ")$skips"
    : "status: nothing needs a look$skips";
  print Esc::line($last), "\n";
  exit(@looks ? 1 : 0);
}

main() unless caller;
1;
