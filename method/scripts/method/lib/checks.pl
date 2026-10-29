#!/usr/bin/env perl
# Runs the method's built-in checks and the project's own checks, and keeps
# their whole output in a log (M002, M050, M051, M066). Started by
# run-checks.sh, which documents the checks file, the results, the screen,
# the log and the exit codes. Checks::read_tsv is the one reader of
# checks/*.tsv (M048): status.pl loads this file with require for it, and
# then nothing runs.
package Checks;
use strict;
use warnings;
use Fcntl qw(O_WRONLY O_CREAT O_EXCL);
use File::Basename qw(dirname);
use File::Spec;
use POSIX ();

# The caller's environment, taken before git.pl cleans it: the project's
# checks run in it, with the caller's perl settings put back (run-checks.sh
# passes them on as METHOD_CALLER_*).
our %CALLER_ENV;
BEGIN { %CALLER_ENV = %ENV }

my $lib = dirname(File::Spec->rel2abs(__FILE__));
require File::Spec->catfile($lib, $_) for qw(git.pl esc.pl conf.pl);

our @RESERVED = qw(secrets fresh-clone tree-unchanged project-checks);
my $LOCAL = '.method/local';
my $LOGS = "$LOCAL/logs";
my $KEEP_LOGS = 20;
my $LOG_NAME = qr/\Arun-checks-[0-9]{8}T[0-9]{6}Z-[0-9]{10}\.log\z/;

# --- checks/*.tsv ---

# read_tsv ROOT: (checks, problems). Each check is a hash: file, line, id,
# runs_in, needs ([KIND, NAME] pairs), count (compiled), command. Each
# problem is "checks/FILE line N: reason"; the reason never quotes a field.
sub read_tsv {
  my ($root) = @_;
  my (@checks, @problems, %seen);
  my $dir = File::Spec->catdir($root, 'checks');
  # a link could stand for checks that a clone does not have
  return (\@checks, ['checks: a link, so its checks would not run everywhere']) if -l $dir;
  return (\@checks, \@problems) unless -d $dir;
  opendir my $dh, $dir or return (\@checks, ['checks: cannot read the folder']);
  my @files = sort grep { /\A[^.].*\.tsv\z/s } readdir $dh;
  closedir $dh;
  for my $name (@files) {
    my $label = 'checks/' . Esc::line($name);
    # a link or a folder could stand for checks that a clone does not have
    my $path = File::Spec->catfile($dir, $name);
    if (-l $path || !-f $path) { push @problems, "$label: not a regular file, so its checks would not run everywhere"; next }
    my $fh;
    if (!open $fh, '<:raw', File::Spec->catfile($dir, $name)) { push @problems, "$label: cannot read the file"; next }
    my $n = 0;
    while (my $l = <$fh>) {
      $n++;
      my $problem = sub { push @problems, "$label line $n: $_[0]" };
      $l =~ s/\r?\n\z//;
      $l =~ s/\A\xEF\xBB\xBF// if $n == 1;    # a byte-order mark some editors add
      next if $l =~ /\A[ \t]*(?:#|\z)/;
      if ($l =~ /[\x00-\x08\x0A-\x1F\x7F]/) { $problem->('holds a control character'); next }
      my @f = split /\t/, $l, -1;
      if (@f != 5) {
        my $hint = (@f == 1 && $l =~ / /) ? '; fields are separated by TAB characters and this line has none' : '';
        $problem->('expected 5 TAB-separated fields (id, runs_in, needs, count, command), found ' . scalar(@f) . $hint);
        next;
      }
      my ($id, $runs_in, $needs, $count, $command) = @f;
      if ($id !~ /\A[a-z][a-z0-9-]*\z/) { $problem->('the id must be lower-case letters, digits and -, starting with a letter'); next }
      if (grep { $_ eq $id } @RESERVED) { $problem->("the id $id is the name of a built-in check"); next }
      if ($seen{$id}) { $problem->("the id $id is already used at $seen{$id}"); next }
      if ($runs_in !~ /\A(?:any|ci|local)\z/) { $problem->('runs_in must be any, ci or local'); next }
      my @needs;
      if ($needs ne '-') {
        my $bad;
        for my $need (split /,/, $needs, -1) {
          my ($kind, $what) = $need =~ /\A(cmd|env|file):(.*)\z/;
          if (!defined $kind) { $bad = 'each need must be cmd:NAME, env:NAME or file:PATH, or the field is -'; last }
          if ($kind eq 'cmd' && $what !~ /\A[A-Za-z0-9][A-Za-z0-9._+-]*\z/) { $bad = 'a cmd: need names one command'; last }
          if ($kind eq 'env' && $what !~ /\A[A-Za-z_][A-Za-z0-9_]*\z/) { $bad = 'an env: need names one variable'; last }
          if ($kind eq 'file') {
            $what = Conf::check_path($what, 0);
            if (!defined $what) { $bad = 'a file: need is a relative path with no ., .. or empty part, no leading : or -, and none of * ? [ \\'; last }
          }
          push @needs, [$kind, $what];
        }
        if ($bad) { $problem->($bad); next }
      }
      # perl's warnings would quote the pattern's bytes raw, so they are dropped
      local $SIG{__WARN__} = sub { };
      my $re = eval { qr/$count/ };
      if (!$re) { $problem->('the count pattern does not compile (code inside a pattern is not allowed)'); next }
      # with the empty line ruled out, only the empty branch of the second
      # match can match, and every capture group comes back undefined; a
      # pattern can also fail when it is matched (endless recursion, say)
      my ($empty, @caps);
      if (!eval { $empty = '' =~ $re; @caps = ('' =~ /$re|/); 1 }) { $problem->('the count pattern fails when it is matched'); next }
      if ($empty) { $problem->('the count pattern matches an empty line'); next }
      if (@caps != 1 || defined $caps[0]) { $problem->('the count pattern needs exactly one capture group, around the number'); next }
      if ($command !~ /\S/) { $problem->('the command is empty'); next }
      $seen{$id} = "$label line $n";
      push @checks, { file => $label, line => $n, id => $id, runs_in => $runs_in, needs => \@needs,
        count => $re, command => $command };
    }
    close $fh;
  }
  return (\@checks, \@problems);
}

# --- running ---

my ($LOG, $log_path, @temps, $parent_pid);

# stop REASON [LINES]: end the run with exit 2
sub stop {
  my ($reason) = @_;
  my $last = "run-checks: FAIL - $reason; the run stopped";
  print "$last\n";
  if ($LOG) {
    print {$LOG} "$last\nEND\texit 2\n";
    close $LOG;
  }
  exit 2;
}

# temp_file: a new private file under .method/local for one output
my $temp_n = 0;
sub temp_file {
  my $path = sprintf '%s/run-checks-%d-%d.out', $LOCAL, $$, ++$temp_n;
  unlink $path;
  sysopen my $fh, $path, O_WRONLY | O_CREAT | O_EXCL, 0600
    or stop('cannot create an output file in .method/local (did a check delete the folder, with git clean -x say?)');
  close $fh;
  push @temps, $path;
  return $path;
}

END { unlink @temps if defined $parent_pid && $$ == $parent_pid }

# run_to_file ENV ARGV OUT: runs ARGV with stdin from the null device and
# stdout and stderr into the file OUT (ENV: a hash, or undef for this
# process's own). Waits for that process only, not for the end of its
# output, so a server a check leaves running does not hold the run up.
sub run_to_file {
  my ($env, $argv, $out) = @_;
  my $pid = fork;
  stop('cannot start a process') unless defined $pid;
  if (!$pid) {
    %ENV = %$env if $env;
    open STDIN, '<', File::Spec->devnull or POSIX::_exit(127);
    open STDOUT, '>>', $out or POSIX::_exit(127);
    open STDERR, '>&', \*STDOUT or POSIX::_exit(127);
    exec { $argv->[0] } @$argv or POSIX::_exit(127);
  }
  waitpid $pid, 0;
  return $?;
}

sub write_lines {
  my ($path, @lines) = @_;
  open my $fh, '>>:raw', $path or stop('cannot write an output file in .method/local');
  print {$fh} map { "$_\n" } @lines;
  close $fh or stop('cannot write an output file in .method/local');
}

# mask_file FILE SUB: each line of FILE (split at LF or CRLF), masked by
# secrets.pl --mask (keys, credentials and personal data masked, control
# characters escaped, indented by two spaces), then through Esc::line,
# passed to SUB
sub mask_file {
  my ($file, $each) = @_;
  my $pid = open(my $fh, '-|');
  stop('cannot run the masking step') unless defined $pid;
  if (!$pid) {
    open STDIN, '<', $file or POSIX::_exit(2);
    open STDERR, '>', File::Spec->devnull;
    exec { $^X } $^X, File::Spec->catfile($lib, 'secrets.pl'), '--mask' or POSIX::_exit(127);
  }
  binmode $fh;
  while (my $l = <$fh>) {
    $l =~ s/\n\z//;
    $each->(Esc::line($l));
  }
  close $fh;
  stop('the masking step failed') if $?;
}

# masked LINES: the lines masked and escaped as mask_file does
sub masked {
  my @in = @_;
  return () unless @in;
  my $tmp = temp_file();
  write_lines($tmp, @in);
  my @out;
  mask_file($tmp, sub { push @out, $_[0] });
  unlink $tmp;
  return @out;
}

# tail_lines FILE: (the lines of FILE's last 64 KB, split at LF, CRLF or
# CR; a line cut by that window is left out, so a key cut in half is never
# shown; whether a line was left out that way)
sub tail_lines {
  my ($file) = @_;
  open my $fh, '<:raw', $file or return ([], 0);
  my $size = -s $fh;
  my $start = $size > 65536 ? $size - 65536 : 0;
  seek $fh, $start, 0;
  my $buf = do { local $/; <$fh> };
  close $fh;
  $buf = '' unless defined $buf;
  my @l = split /\r\n|\r|\n/, $buf, -1;
  pop @l if @l && $l[-1] eq '';
  my $cut = 0;
  if ($start > 0 && @l) { shift @l; $cut = !@l }
  return (\@l, $cut);
}

# cut LINE MAX: LINE cut to MAX bytes, never inside a UTF-8 character or
# an escape, saying how much was cut
sub cut {
  my ($s, $max) = @_;
  return $s if length $s <= $max;
  my $c = substr $s, 0, $max;
  $c =~ s/[\xC0-\xFF][\x80-\xBF]*\z//;
  $c =~ s/\\(?:x[0-9A-F]?|u(?:\{[0-9A-F]*)?)?\z//;
  return $c . ' (' . (length($s) - length($c)) . ' bytes cut)';
}

# count_in FILE RE: the capture of the last output line RE matches (lines
# split at LF, CRLF or CR, terminal colour and cursor codes removed);
# (matched, capture)
sub count_in {
  my ($file, $re) = @_;
  open my $fh, '<:raw', $file or return (0, undef);
  my ($matched, $value) = (0, undef);
  while (my $chunk = <$fh>) {
    $chunk =~ s/\n\z//;
    for my $line (split /\r/, $chunk, -1) {
      $line = Esc::plain($line);
      if ($line =~ $re) { $matched = 1; $value = $1 }
    }
  }
  close $fh;
  return ($matched, $value);
}

# the environment a project check runs in
sub check_env {
  my %e = %CALLER_ENV;
  for my $v (qw(PERL_UNICODE PERL5OPT PERL5LIB PERLLIB PERL_USE_UNSAFE_INC PERLIO)) {
    delete $e{$v};
    $e{$v} = $e{"METHOD_CALLER_$v"} if exists $e{"METHOD_CALLER_$v"};
    delete $e{"METHOD_CALLER_$v"};
  }
  return \%e;
}

# fingerprint: what a check must leave as it found it. HEAD's commit and the
# branch it is on, the commit of every branch and tag, and every path git
# does not ignore that is changed, untracked, or marked so git does not
# compare it (assume-unchanged, or skip-worktree, also with the file gone
# from disk: a sparse checkout, or a deletion hidden that way), each with
# its mode and the SHA-256 of what is on disk (.method/local left out). git
# status runs with no filter program and no stat shortcut
# (Git::status_options).
sub fingerprint {
  require Digest::SHA;    # loaded here, so status.pl can load this file without it
  my ($st, $head) = Git::run('rev-parse', '-q', '--verify', 'HEAD^{commit}');
  $head = $st ? 'none' : (split /\n/, $head)[0];
  my ($bst, $branch) = Git::run('symbolic-ref', '-q', 'HEAD');
  $branch = $bst ? 'detached' : (split /\n/, $branch)[0];
  my $refs = Git::ok('for-each-ref', '--format=%(refname) %(objectname)', 'refs/heads/', 'refs/tags/');
  my $out = Git::ok(Git::status_options(), 'status', '--porcelain=v1', '-z', '--no-renames',
    '--untracked-files=all', '--ignore-submodules=none');
  my @paths;
  for my $rec (split /\0/, $out) {
    push @paths, [substr($rec, 3), substr($rec, 0, 2)] if length $rec >= 4;
  }
  for my $rec (split /\0/, Git::ok('ls-files', '-v', '-z')) {
    my ($tag, $path) = split / /, $rec, 2;
    next unless defined $path;
    push @paths, [$path, "flag $tag"] if $tag =~ /\A[a-z]\z/ || $tag eq 'S';
  }
  my %e;
  for my $p (@paths) {
    my ($path, $why) = @$p;
    next if index($path, "$LOCAL/") == 0;
    my $h = '-';
    my @s = lstat $path;
    if (-l _) {
      my $t = readlink $path;
      $h = 'link ' . (defined $t ? Digest::SHA::sha256_hex($t) : '?');
    } elsif (-f _) {
      $h = eval { Digest::SHA->new(256)->addfile($path, 'b')->hexdigest };
      $h = 'unreadable' unless defined $h;
    }
    $e{$path} = join ' ', grep { defined } $e{$path}, $why, (@s ? sprintf('%o', $s[2]) : '-'), $h;
  }
  return { head => $head, branch => $branch, refs => $refs, e => \%e };
}

sub tracked_count {
  my $out = Git::ok('ls-files', '-z');
  return scalar(() = $out =~ /\0/g);
}

# --- the built-in checks; each fills OUT and returns its result ---

sub check_secrets {
  my ($out) = @_;
  my $raw = temp_file();
  my $st = run_to_file(undef, [$^X, File::Spec->catfile($lib, 'secrets.pl'), '--repo', '--ids', 'checks/scan-allow.txt'], $raw);
  open my $fh, '<:raw', $raw or stop('cannot read the secret scan output');
  my (%n, $result, @lines);
  while (my $l = <$fh>) {
    $l =~ s/\n\z//;
    if ($l =~ /\A(EXAMINED|STAGED|BAD|ALLOWED|SKIPPED) ([0-9]+)\z/) { $n{$1} = $2; next }
    next if $l =~ /\ASKIPPED_NAMES /;
    if ($l =~ /\ARESULT (PASS|FAIL|SKIPPED) (.*)\z/) { $result = [$1, $2]; next }
    push @lines, $l;
  }
  close $fh;
  unlink $raw;
  write_lines($out, @lines);
  if ($st || !$result || !defined $n{EXAMINED}) {
    my $why = $st & 127 ? 'killed by signal ' . ($st & 127) : 'exit ' . ($st >> 8);
    return { status => 'FAIL', kind => 'exit', examined => '-',
      detail => $st ? "the scan itself did not run ($why)" : 'the scan ran, but its output could not be read' };
  }
  my ($status, $detail) = @$result;
  return { status => 'PASS', kind => 'pass', examined => $n{EXAMINED}, detail => $detail } if $status eq 'PASS';
  return { status => 'SKIPPED', kind => 'examined-nothing', examined => 0, detail => $detail } if $status eq 'SKIPPED';
  return { status => 'FAIL', kind => 'finding', examined => $n{EXAMINED}, detail => $detail,
    hint => 'to accept a false positive, add PATH<TAB>ID<TAB>a real reason to checks/scan-allow.txt' };
}

# local_only CONF: patterns for LOCAL_ONLY. A bare name matches any path
# segment (* and ? stay inside one segment); a path matches itself and
# everything under it.
sub local_only {
  my ($list) = @_;
  my @re;
  for my $e (@{ $list || [] }) {
    if ($e =~ m{/}) { push @re, qr/\A\Q$e\E(?:\/|\z)/; next }
    my $g = join '', map { $_ eq '*' ? '[^/]*' : $_ eq '?' ? '[^/]' : quotemeta } split /([*?])/, $e;
    push @re, qr/(?:\A|\/)$g(?:\/|\z)/;
  }
  return @re;
}

sub check_fresh_clone {
  my ($conf, $out) = @_;
  my @pp = @{ $conf->{PRODUCT_PATHS} || [] };
  return { status => 'SKIPPED', kind => 'not-configured', examined => '-',
    detail => 'PRODUCT_PATHS is not set in .claude/method.conf, so nothing says which files make up the product' }
    unless @pp;
  my (%tracked, @typo);
  for my $p (@pp) {
    my @t = split /\0/, Git::ok('ls-files', '-z', '--', $p);
    push @typo, $p unless @t;
    $tracked{$_} = 1 for @t;
  }
  my @lo = local_only($conf->{LOCAL_ONLY});
  my ($aside, @left) = (0);
  for my $f (sort split /\0/, Git::ok('ls-files', '-z', '--others', '--ignored', '--exclude-standard', '--', @pp)) {
    next if index($f, "$LOCAL/") == 0 || $f =~ m{(?:\A|/)\.claude/settings\.local\.json\z} || $f =~ m{(?:\A|/)CLAUDE\.local\.md\z};
    if (grep { $f =~ $_ } @lo) { $aside++; next }
    push @left, $f;
  }
  # a name may hold a line break, which would make it look like two lines
  write_lines($out, (map { 'ignored by git, so not in a clone: ' . Esc::line($_) } @left),
    (map {"a PRODUCT_PATHS entry that matches no tracked file: $_"} @typo));
  my $examined = keys %tracked;
  if (@left || @typo) {
    my @why;
    push @why, scalar(@left) . ' ignored files under PRODUCT_PATHS are here but not in a clone, so a check that passes here'
      . ' may fail there; add the name or path to LOCAL_ONLY in .claude/method.conf if a clone is meant to lack it' if @left;
    push @why, scalar(@typo) . ' PRODUCT_PATHS entries match no tracked file (a typo?)' if @typo;
    return { status => 'FAIL', kind => 'finding', examined => $examined, detail => join('; ', @why) };
  }
  return { status => 'PASS', kind => 'pass', examined => $examined,
    detail => "examined $examined tracked files under PRODUCT_PATHS; $aside ignored files set aside by LOCAL_ONLY" };
}

sub check_tree_unchanged {
  my ($before, $out) = @_;
  my $after = fingerprint();
  my %all = (%{ $before->{e} }, %{ $after->{e} });
  my @changed = sort grep { ($before->{e}{$_} || '') ne ($after->{e}{$_} || '') } keys %all;
  write_lines($out, map { 'changed during the run: ' . Esc::line($_) } @changed);
  my %refs_before = map { split / /, $_, 2 } split /\n/, $before->{refs};
  my %refs_after = map { split / /, $_, 2 } split /\n/, $after->{refs};
  # a branch that moved, appeared or went, or a tag that moved or went (a
  # fetch may bring new tags, which is allowed)
  my %all_refs = (%refs_before, %refs_after);
  my @moved = sort grep { ($refs_before{$_} || '') ne ($refs_after{$_} || '') && (exists $refs_before{$_} || m{\Arefs/heads/}) }
    keys %all_refs;
  write_lines($out, map {"moved during the run: $_"} @moved);
  my @why;
  push @why, 'HEAD moved during the run' if $before->{head} ne $after->{head};
  push @why, 'HEAD is on another branch than before the run' if $before->{branch} ne $after->{branch};
  push @why, scalar(@moved) . ' branches or tags moved during the run' if @moved;
  push @why, 'the checks changed ' . scalar(@changed) . ' files' if @changed;
  my $examined = tracked_count();
  return { status => 'FAIL', kind => 'finding', examined => $examined, detail => join('; ', @why) } if @why;
  return { status => 'SKIPPED', kind => 'examined-nothing', examined => 0,
    detail => 'the repository tracks no file, so there was nothing to compare' } unless $examined;
  return { status => 'PASS', kind => 'pass', examined => $examined,
    detail => "HEAD, its branch, the branches and tags, and the files on disk are as they were before the checks ran" };
}

sub check_project {
  my ($c, $here, $env, $out) = @_;
  my $at = "$c->{file} line $c->{line}";
  if ($c->{runs_in} ne 'any' && $c->{runs_in} ne $here) {
    my $only = $c->{runs_in} eq 'ci' ? 'in CI only' : 'locally only';
    return { status => 'SKIPPED', kind => 'not-here', examined => '-', detail => "runs $only ($at)" };
  }
  for my $need (@{ $c->{needs} }) {
    my ($kind, $what) = @$need;
    my $met = $kind eq 'cmd' ? !run_to_file($env, ['bash', '-c', 'command -v "$1"', 'bash', $what], File::Spec->devnull)
      : $kind eq 'env' ? defined $env->{$what} && $env->{$what} ne ''
      : -e $what;
    next if $met;
    my $why = $kind eq 'cmd' ? 'is not on PATH' : $kind eq 'env' ? 'is not set' : 'does not exist';
    return { status => 'SKIPPED', kind => 'needs', examined => '-', detail => "needs $kind:$what, which $why ($at)" };
  }
  my $st = run_to_file($env, ['bash', '-o', 'pipefail', '-c', $c->{command}], $out);
  return { status => 'FAIL', kind => 'exit', examined => '-', detail => 'killed by signal ' . ($st & 127) . " ($at)" }
    if $st & 127;
  return { status => 'FAIL', kind => 'exit', examined => '-', detail => 'exit ' . ($st >> 8) . " ($at)" } if $st;
  my ($matched, $v) = count_in($out, $c->{count});
  return { status => 'SKIPPED', kind => 'no-count', examined => '-',
    detail => "it passed, but no output line matched its count pattern, so nothing shows it examined anything ($at)" }
    unless $matched;
  return { status => 'SKIPPED', kind => 'no-count', examined => '-',
    detail => "it passed, but its count pattern caught something that is not a number ($at)" }
    unless defined $v && $v =~ /\A[0-9]+\z/;
  (my $n = $v) =~ s/\A0+(?=.)//;
  return { status => 'SKIPPED', kind => 'examined-nothing', examined => 0,
    detail => "it passed, but its count is 0, so it examined nothing ($at)" } if $n eq '0';
  return { status => 'PASS', kind => 'pass', examined => $n, detail => "examined $n ($at)" };
}

# --- the log ---

sub open_log {
  for my $d ('.method', $LOCAL, $LOGS) {
    stop("$d is a symbolic link; run-checks writes its log only into a real folder") if -l $d;
    next if -d _;
    mkdir $d, 0700 or stop("cannot create the folder $d");
  }
  chmod 0700, $LOGS;
  my @t = gmtime;
  my $stamp = sprintf '%04d%02d%02dT%02d%02d%02dZ', $t[5] + 1900, $t[4] + 1, @t[3, 2, 1, 0];
  $log_path = sprintf '%s/run-checks-%s-%010d.log', $LOGS, $stamp, $$;
  sysopen $LOG, $log_path, O_WRONLY | O_CREAT | O_EXCL, 0600 or do { undef $LOG; stop("cannot create the log $log_path") };
  binmode $LOG;
  select((select($LOG), $| = 1)[0]);
  return sprintf '%04d-%02d-%02dT%02d:%02d:%02dZ', $t[5] + 1900, $t[4] + 1, @t[3, 2, 1, 0];
}

# ignore_local: writes .method/local/.gitignore holding * when git does not
# ignore the new log yet, never over an existing file; says what it did.
# (git check-ignore takes no literal paths, so ls-files answers instead.)
sub ignore_local {
  my ($st, $out) = Git::run('ls-files', '-z', '--others', '--ignored', '--exclude-standard', '--', $log_path);
  return 'git ls-files did not answer, so .method/local/.gitignore was not written' if $st;
  return undef if $out ne '';
  my $gi = "$LOCAL/.gitignore";
  return '.method/local/.gitignore exists but does not make git ignore the folder; it was left as it is' if -e $gi || -l $gi;
  sysopen my $fh, $gi, O_WRONLY | O_CREAT | O_EXCL, 0600 or return 'cannot write .method/local/.gitignore';
  print {$fh} "*\n";
  close $fh or return 'cannot write .method/local/.gitignore';
  return 'wrote .method/local/.gitignore, so git ignores the folder';
}

# prune_logs: keeps the newest run-checks logs; deletes only untracked
# regular files named exactly like a log, never the current one
sub prune_logs {
  opendir my $d, $LOGS or return;
  my @logs = sort grep { $_ =~ $LOG_NAME } readdir $d;
  closedir $d;
  my $tracked = eval { Git::ok('ls-files', '-z', '--', $LOGS) };
  return unless defined $tracked;
  my %tracked = map { $_ => 1 } split /\0/, $tracked;
  my @cand = grep { my $p = "$LOGS/$_"; !$tracked{$p} && !-l $p && -f _ } @logs;
  for my $name (@cand[0 .. $#cand - $KEEP_LOGS]) {
    my $p = "$LOGS/$name";
    unlink $p unless $p eq $log_path;
  }
}

# --- main ---

my (@results, @skipped_lines, @passed);

# finish ID RUNS_IN RESULT OUT: the check's masked output and RESULT line go
# to the log; a FAIL goes to the screen at once, with its last output lines
sub finish {
  my ($id, $runs_in, $r, $out) = @_;
  mask_file($out, sub { print {$LOG} "$_[0]\n" }) if -s $out;
  # a detail is this file's own text with counts and checks/ file names
  my $detail = Esc::line($r->{detail});
  $detail =~ s/\t/\\x09/g;
  print {$LOG} join("\t", 'RESULT', $id, $r->{status}, $r->{kind}, $runs_in, $r->{examined}, $detail), "\n";
  push @results, { %$r, id => $id, project => $runs_in ne '-' };
  if ($r->{status} eq 'FAIL') {
    print "$id: FAIL - $detail\n";
    # the whole window is masked, so a private key whose BEGIN line is
    # above the last 10 lines is still masked; then the last 10 are shown
    my ($tail, $cut) = tail_lines($out);
    my @shown = masked(@$tail);
    splice @shown, 0, @shown - 10 if @shown > 10;
    if (@shown) { print cut($_, 300), "\n" for @shown }
    elsif ($cut) { print "  (its last output line is longer than 64 KB; see the log)\n" }
    else { print "  (no output)\n" }
    print "  $r->{hint}\n" if $r->{hint};
  } elsif ($r->{status} eq 'SKIPPED') {
    push @skipped_lines, "$id: SKIPPED - $detail";
  } else {
    push @passed, $id;
  }
}

sub passed_lines {
  my @ids = @_;
  return () unless @ids;
  my @lines = ('passed:');
  for my $id (@ids) {
    if (length("$lines[-1] $id") > 100) { push @lines, '       ' }
    $lines[-1] .= " $id";
  }
  return @lines if @lines <= 3;
  my @words = split ' ', join(' ', @lines[0 .. 2]);
  shift @words;
  my $more = @ids - @words;
  my $last = $lines[2];
  while (length("$last and $more more") > 100) {
    $last =~ s/ \S+\z//;
    $more++;
  }
  return (@lines[0 .. 1], "$last and $more more");
}

sub main {
  binmode STDOUT, ':raw';
  binmode STDERR, ':raw';
  $| = 1;
  $parent_pid = $$;
  if (@ARGV) {
    print "run-checks: usage: run-checks.sh (it takes no arguments)\n";
    exit 2;
  }
  my ($top, $elsewhere) = Git::top();
  stop('not inside a git working tree (or git refuses this one: owned by another user, or a damaged .git)')
    unless defined $top;
  stop("git's working folder is not this folder: a core.worktree setting points git elsewhere (or a .git here is"
    . ' damaged); run the checks in the working folder itself') if $elsewhere;
  chdir $top or stop('cannot enter the top folder of the repository');

  my ($conf, $cp) = Conf::read('.');
  if (@$cp) {
    print 'run-checks: ' . Esc::line($_) . "\n" for @$cp;
    stop('.claude/method.conf has problems (above); fix them first');
  }
  my @ign = eval { Conf::ignored_inputs('.') };
  if ($@) {
    (my $err = $@) =~ s/\n\z//;
    stop(Esc::line($err));
  }
  if (@ign) {
    print 'run-checks: ' . Esc::line($_) . " is ignored by git, so a clone would not have it; track it with git add -f\n"
      for @ign;
    stop('a config file is ignored by git');
  }
  my ($checks, $tp) = read_tsv('.');
  if (@$tp) {
    print 'run-checks: ' . Esc::line($_) . "\n" for @$tp;
    stop('checks/*.tsv has problems (above); no check was run');
  }
  my $here = ($ENV{CI} || '') eq 'true' ? 'ci' : 'local';
  my $where = $here eq 'ci' ? 'CI' : 'local';

  my $started = open_log();
  print "run-checks: log $log_path\n";
  # from here on, an error (git failing, say) still ends the log with END
  my $exit = eval { run_all($conf, $checks, $here, $where, $started) };
  if (!defined $exit) {
    (my $err = $@) =~ s/\n\z//;
    stop(Esc::line($err));
  }
  prune_logs();
  exit $exit;
}

# run_all CONF CHECKS HERE WHERE STARTED: runs every check after the log is
# open, writes the end of the screen and the log; the exit code
sub run_all {
  my ($conf, $checks, $here, $where, $started) = @_;
  my $note = ignore_local();
  my $before = fingerprint();
  my $dirty = %{ $before->{e} } ? 1 : 0;
  print {$LOG} "run-checks log\nstarted $started\ncommit $before->{head}\n",
    'tree at start ' . ($dirty ? 'uncommitted changes' : 'clean') . "\nwhere $where\nsystem " . (POSIX::uname())[0] . "\n";
  print {$LOG} "note $note\n" if $note;

  my $env = check_env();
  my $run = sub {
    my ($id, $runs_in, $code) = @_;
    print {$LOG} "=== CHECK $id ===\n";
    my $out = temp_file();
    finish($id, $runs_in, $code->($out), $out);
    unlink $out;
  };
  $run->('secrets', '-', \&check_secrets);
  $run->('fresh-clone', '-', sub { check_fresh_clone($conf, $_[0]) });
  if (!@$checks) {
    $run->('project-checks', '-', sub {
      { status => 'SKIPPED', kind => 'not-configured', examined => '-',
        detail => "checks/*.tsv lists no checks, so the project's own tests were not run" } });
  }
  for my $c (@$checks) {
    $run->($c->{id}, $c->{runs_in}, sub { check_project($c, $here, $env, $_[0]) });
  }
  $run->('tree-unchanged', '-', sub { check_tree_unchanged($before, $_[0]) });

  my @failed = map { $_->{id} } grep { $_->{status} eq 'FAIL' } @results;
  my @skipped = grep { $_->{status} eq 'SKIPPED' } @results;
  my $not_here = grep { $_->{kind} eq 'not-here' } @skipped;
  my $applies = grep { $_->{kind} ne 'not-here' } @skipped;
  my $none_here = @$checks && !grep { $_->{project} && $_->{kind} ne 'not-here' } @results;
  my $tail = "where $where" . ($dirty ? '; on uncommitted changes' : '');
  my ($exit, $last);
  if (@failed) {
    $exit = 1;
    $last = 'run-checks: FAIL - ' . scalar(@failed) . ' failed (' . join(' ', @failed) . '), ' . scalar(@passed)
      . ' passed, ' . scalar(@skipped) . " skipped; $tail";
  } elsif ($applies || $none_here) {
    $exit = 3;
    $last = 'run-checks: SKIPPED - ' . scalar(@skipped) . ' checks did not run here or examined nothing, this is not a pass'
      . ($none_here ? '; no project check runs here' : '') . '; ' . scalar(@passed) . " passed; $tail";
  } else {
    $exit = 0;
    $last = 'run-checks: PASS - ' . scalar(@passed) . ' passed' . ($not_here ? ", $not_here not for here" : '') . "; $tail";
  }
  my @show = @skipped_lines > 10 ? @skipped_lines[0 .. 9] : @skipped_lines;
  print "$_\n" for @show;
  print 'and ' . (@skipped_lines - 10) . " more SKIPPED, see the log\n" if @skipped_lines > 10;
  print "$_\n" for passed_lines(@passed);
  print "$last\n";
  print {$LOG} "$last\nEND\texit $exit\n";
  close $LOG;
  undef $LOG;
  return $exit;
}

main() unless caller;
1;
