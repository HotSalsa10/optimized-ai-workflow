#!/usr/bin/env perl
# Breaks the code under test on purpose (M044): one changed line at a time
# gets a small text change (a mutant), the project's fast checks run, and
# the line is put back. Started by mutate-changed.sh, which documents the
# settings, the screen and the exit codes. --list plans only: it writes
# nothing and runs no check. A run writes each mutant into the working tree
# through one write function, with a journal in git's own folder that names
# it until it is put back, and runs the checks through lib/checks.pl's
# limited runner, holding the lock run-checks shares (lib/runstate.pl).
package Mutate;
use strict;
use warnings;
use Cwd ();
use Digest::SHA ();
use Fcntl qw(O_WRONLY O_CREAT O_EXCL);
use File::Basename qw(dirname);
use File::Spec;
use IO::Handle ();
use Time::HiRes ();

my $lib = dirname(File::Spec->rel2abs(__FILE__));
# checks.pl first: it takes the caller's environment before git.pl cleans it
require File::Spec->catfile($lib, $_) for qw(checks.pl git.pl esc.pl conf.pl tree.pl);

my $MAX_SIZE = 1024 * 1024;    # a changed file larger than this is not mutated
my $DEFAULT_MAX = 100;
my $DEFAULT_MINUTES = 8;    # a foreground tool call allows 10 minutes

# a run's state: the lock (held while this process lives), the journal's
# path, git's folder (check output files), the write function's temp name,
# the signal seen (handlers only set it), the check running now, and the
# journal of the round whose mutant may be on disk
my ($LOCK, $JOURNAL, $GITDIR, $TEMP, $SIGNAL, $RUN, $OPEN, $CHECK_OUT);
my $OUT_N = 0;

sub say_line { print Esc::line("mutate-changed: $_[0]"), "\n" }

# stop REASON: an error (exit 2), with a last line that says so. A round
# that is open is ended first: the check's group is killed and the mutant
# put back, so no error leaves one on disk; when that fails, the journal
# stays and the line says to run --recover.
sub stop {
  my ($reason) = @_;
  $reason =~ s/\n\z//;
  # a signal is the reason, whatever failed after it (a terminal's Ctrl-C
  # reaches the git processes of this run too)
  $reason = "stopped by SIG$SIGNAL (then: $reason)" if defined $SIGNAL && $reason !~ /\Astopped by SIG/;
  unlink $CHECK_OUT if defined $CHECK_OUT;    # what the check printed
  if ($RUN) {
    Checks::finish_limited($RUN, 1);
    undef $RUN;
  }
  if ($OPEN && !$OPEN->{tried}) {
    my @back = eval { end_round(1) };
    (my $e = $@) =~ s/\n\z//;
    $reason .= '; ' . join(', ', @back) . ' put back' if @back;
    $reason .= "; $e" if $e;
  }
  if ($OPEN) {
    $reason .= '; the journal stays' . ($reason =~ /--recover/ ? '' : ': once that is fixed, run mutate-changed.sh --recover');
  }
  say_line("FAIL - $reason; the run stopped");
  exit 2;
}

# skipped KIND DETAIL: nothing to do, which is never a pass (exit 3)
sub skipped {
  my ($kind, $detail) = @_;
  say_line("SKIPPED - $kind: $detail; this is not a pass");
  exit 3;
}

sub usage {
  print "mutate-changed: usage: mutate-changed.sh [--list | --recover] [--max N] [--minutes N]\n";
  exit 2;
}

# --- which files: the settings and the built-in exclusions ---

# excluded PATH METHOD: why PATH is never mutated, or undef. The method's own
# files (the folder mutate-changed.sh runs from, .claude/, checks/), its
# local folder (.method/), and git's own files, whose change would change
# what git shows. Compared without case, as a file system that folds case
# would open them.
sub excluded {
  my ($p, $method) = @_;
  my $lp = lc $p;
  return "the method's own files" if defined $method && ($lp eq lc $method || index($lp, lc("$method/")) == 0);
  return "the method's own files" if $lp =~ m{\A(?:\.claude|checks|\.method)/};
  return "git's own files" if $lp =~ m{(?:\A|/)\.git(?:attributes|ignore|modules)\z};
  return undef;
}

# under PATH LIST: PATH is one of LIST's paths or lies under one ("." is all)
sub under {
  my ($p, $list) = @_;
  return grep { $_ eq '.' || $p eq $_ || index($p, "$_/") == 0 } @$list;
}

# method_folder TOP: the folder mutate-changed.sh runs from, relative to TOP,
# or undef when it is outside TOP (a method installed elsewhere). Found by
# walking up until a folder is TOP by device and inode, as Git::top does, so
# a path typed in another case or through a link still finds it.
sub method_folder {
  my ($top) = @_;
  my @t = stat $top or return undef;
  my $d = Cwd::realpath(dirname($lib));
  return undef unless defined $d;
  my @parts;
  while (1) {
    my @s = stat $d or return undef;
    return @parts ? join('/', reverse @parts) : '.' if $s[0] == $t[0] && $s[1] == $t[1];
    my $up = dirname($d);
    return undef if $up eq $d;
    push @parts, File::Basename::basename($d);
    $d = $up;
  }
}

# --- mutants: the text operators ---

# shell_like FILE TEXT: a shell script or a make file, by its name or its
# first line: its lines run commands
sub shell_like {
  my ($p, $text) = @_;
  return 1 if $p =~ /\.(?:sh|bash|zsh|ksh|bats|fish|command|mk|mak|make|bat|cmd|ps1)\z/i
    || $p =~ m{(?:\A|/)(?:(?:GNU|BSD)?makefile(?:\.[^/]*)?|\.envrc|\.bashrc|\.bash_profile|\.profile|\.zshrc)\z}i;
  return $text =~ m{\A#![^\n]*\b(?:sh|bash|dash|ksh|zsh|fish|make|pwsh)\b} ? 1 : 0;
}

# comment-like LINE: its first non-blank text opens a comment in a common
# language (#, //, --, /*, *, ;, %, <!--)
sub comment_like { return $_[0] =~ m{\A[ \t]*(?:#|//|--|/\*|\*|;|%|<!--)} ? 1 : 0 }

# destructive TEXT BATCH: a line of TEXT names a command that deletes, moves
# or rewrites files or history. A mutant runs with the session's rights, so
# a changed condition would run it when it was meant not to. Words, not a
# parser (RISKS #13): one occurrence is enough, and over-matching only drops
# mutants. BATCH (a .bat, .cmd or .ps1 file, or a pwsh script) adds cmd's
# and PowerShell's words in any letter case. A line that ends in a
# backslash (in BATCH also ^ or `) is read with the next. The command word
# after git, find, rsync, make or robocopy counts as a word of its own, so
# an argument list such as ["git", "clean"] counts too. Each line is read
# once from its first git, find, rsync, make or robocopy, so a long line
# costs time in proportion to its length.
my $WORDS = qr/\b(?:rm|rmdir|unlink|mv|dd|chmod|chown|shred|truncate|rimraf)\b|\$[({]?(?:rm|RM)\b
  |\b(?:os\.(?:remove|unlink|rmdir|removedirs|rename|replace|RemoveAll|Remove|Rename)|shutil\.(?:rmtree|move)
    |fs\.(?:rm|rmSync|unlink|unlinkSync|rmdir|rmdirSync|rename|renameSync)|FileUtils\.(?:rm\w*|remove\w*|mv)
    |File(?:\.|\]::)(?:[Dd]elete|[Mm]ove)|Directory(?:\.|\]::)(?:Delete|Move)|Files\.(?:delete\w*|move)|fs::(?:remove\w*|rename)
    |Remove-Item|Move-Item)\b
  |\b(?:del|erase|rd)[ \t]/x;
my $BATCH_WORDS = qr/\b(?i:del|erase|rd|rmdir|move|ren|rename|remove-item|move-item)\b/;
# a command word that follows git, find, rsync, make or robocopy: any text
# but a letter, digit, _ or - before it (a space, a quote, a comma, a dot)
my $GIT_SUB = qr/(?<![\w-])(?:clean|reset|push|checkout|restore|rm|branch|stash|worktree)\b/;
# after LINE FIRST THEN: THEN comes after the first FIRST on LINE (one pass)
sub after {
  my ($l, $first, $then) = @_;
  return 0 unless $l =~ /$first/g;
  return $l =~ /\G[^\n]*?$then/ ? 1 : 0;
}

# cont BATCH: the end of a line that goes on in the next: a backslash (in
# BATCH also ^ or `), with the CR of a CRLF line
sub cont { return $_[0] ? qr/[\\^`]\r?/ : qr/\\\r?/ }

sub destructive {
  my ($text, $batch) = @_;
  my $joins = cont($batch);
  (my $joined = $text) =~ s/$joins\n/ /g;
  for my $l (split /\n/, $joined) {
    return 1 if $l =~ $WORDS || ($batch && $l =~ $BATCH_WORDS);
    # git (also run as $(GIT), ${GIT} or $GIT), find, rsync, make (also as
    # $(MAKE)) and robocopy: the command word after the first of them,
    # whatever options come between
    return 1 if after($l, qr/\bgit\b|\$[({]?(?i:git)\b/, $GIT_SUB) || after($l, qr/\bfind\b/, qr/(?<![\w-])-delete\b/)
      || after($l, qr/\brsync\b/, qr/(?<![\w-])--delete/) || after($l, qr/\bmake\b|\$[({]?MAKE\b/, qr/(?<![\w-])(?:clean|distclean|mostlyclean|maintainer-clean)\b/)
      || ($batch && after($l, qr/\b(?i:robocopy)\b/, qr/(?<![\w-])\/(?i:mir|purge|move?)\b/));
  }
  return 0;
}

# next_int N: N + 1 as decimal text (any length); 1 becomes 0, as 0 becomes 1
sub next_int {
  my ($n) = @_;
  return '0' if $n eq '1';
  my @d = reverse split //, $n;
  my $i = 0;
  while ($i < @d && $d[$i] eq '9') { $d[$i++] = '0' }
  if ($i < @d) { $d[$i]++ } else { push @d, '1' }
  return join '', reverse @d;
}

# The operators, each [regex, replacement, kind]; a regex captures the token
# in $1 at the position it changes. Kept in one table so the plan and the run
# use the same mutants. A byte of 0x80 or more counts as a letter (part of a
# non-ASCII letter).
my @OPS = (
  [qr/(?<![=!])(===)(?!=)/, sub {'!=='}], [qr/(?<![=!])(!==)(?!=)/, sub {'==='}],
  [qr/(?<![=!<>])(==)(?![=>])/, sub {'!='}], [qr/(!=)(?!=)/, sub {'=='}],
  [qr/(?<![<=])(<=)(?![<>=])/, sub {'<'}], [qr/(?<![>=])(>=)(?![=>])/, sub {'>'}],
  [qr/(?<=\s)(-(?:lt|le|gt|ge|eq|ne))(?=\s)/, sub { { '-lt' => '-le', '-le' => '-lt', '-gt' => '-ge', '-ge' => '-gt',
    '-eq' => '-ne', '-ne' => '-eq' }->{ $_[0] } }, 'test'],
  [qr/(?<!&)(&&)(?![&=])/, sub {'||'}], [qr/(?<!\|)(\|\|)(?![|=])/, sub {'&&'}],
  [qr/\b(and)\b/, sub {'or'}], [qr/\b(or)\b/, sub {'and'}],
  [qr/\b(true|false|True|False|TRUE|FALSE)\b/, sub { { true => 'false', false => 'true', True => 'False',
    False => 'True', TRUE => 'FALSE', FALSE => 'TRUE' }->{ $_[0] } }],
  [qr/(?<![\w.\$\\%\x80-\xFF])(?<!\$\{)(?<!\$\{\#)(?<![<>]&)(0|[1-9][0-9]*)(?![\w.<>\x80-\xFF])/, \&next_int, 'number'],
);

# mutants_on LINE MAX: ([column, from, to, kind] for the first MAX positions
# by column, the number of positions). A shell test word (-lt and the
# others) counts only after a [ or test on the line, so a flag such as ls -lt
# is left alone. No more than MAX are kept from each operator, so one long
# line costs no more memory than the cap needs.
sub mutants_on {
  my ($l, $max) = @_;
  my (@m, $count);
  # where a [ or test first appears (found once, so a long line costs time in
  # proportion to its length)
  my $test_at = $l =~ /\[|\btest\b/ ? $-[0] : -1;
  for my $op (@OPS) {
    my ($re, $to, $kind) = @$op;
    my $kept = 0;
    while ($l =~ /$re/g) {
      my ($at, $tok) = ($-[1], $1);
      next if defined $kind && $kind eq 'test' && !($test_at >= 0 && $test_at < $at);
      $count++;
      push @m, [$at + 1, $tok, $to->($tok), $kind || ''] if $kept++ < $max;
    }
  }
  @m = sort { $a->[0] <=> $b->[0] } @m;
  splice @m, $max if @m > $max;
  return (\@m, $count || 0);
}

# shown MUTANT: what the screen says it does. A number other than 0 and 1 is
# shown by its length only, so no PIN, account number, phone number (also
# one written in groups of one or two digits) or numeric key on a changed
# line reaches the screen.
sub shown {
  my ($m) = @_;
  return "'$m->{from}' becomes '$m->{to}'" unless $m->{kind} eq 'number' && $m->{from} ne '0' && $m->{from} ne '1';
  return "a " . length($m->{from}) . '-digit number becomes that number + 1';
}

# --- the plan ---

# plan CONF TOP MAX: the changed files and lines, their mutants in run order
# (at most MAX), and the counts for the last line
sub plan {
  my ($conf, $top, $max) = @_;
  my $fp = Checks::fingerprint();
  stop('the files on disk are not the commit (uncommitted, untracked or flagged files: see git status); commit or'
    . ' restore them first') if %{ $fp->{e} };
  my %converted = map { ($_ => 1) } @{ $fp->{converted} }, @{ $fp->{lfs} };
  my ($ref, $tip) = Git::main_ref();
  stop('no main branch here (' . Git::no_main() . '); ' . Git::no_main_action()) unless defined $ref;
  my ($mst, @mb) = Git::merge_base($tip, $fp->{head});
  stop('git merge-base failed') if $mst eq 'error';
  stop("$ref and this branch share no history here ($mb[0])") if $mst eq 'none';
  # two merge bases (criss-cross merges): which lines the branch adds cannot
  # be told from either alone
  stop("$ref and this branch have " . scalar(@mb) . ' merge bases (' . join(', ', map { substr($_, 0, 7) } @mb)
    . '), so which lines this branch adds cannot be told; merge main into this branch first') if @mb > 1;
  my $base = $mb[0];
  my $method = method_folder($top);
  stop('mutate-changed.sh runs from the top folder, so every file would be its own; run the copy in scripts/method')
    if defined $method && $method eq '.';
  my %c = (lines => 0, with => 0, comment => 0, nothing => 0, guarded => 0, files => 0);
  my %skip;
  Tree::check_trees($base, $fp->{head});
  my @cand;
  for my $f (Tree::changed($base, $fp->{head})) {
    next if $f->{st} eq 'D';
    next unless under($f->{path}, $conf->{MUTATE_PATHS});
    if (excluded($f->{path}, $method)) { $skip{"left out (the method's or git's own files)"}++; next }
    if ($f->{m2} !~ /\A100(?:644|755)\z/) { $skip{'not a regular file'}++; next }
    push @cand, $f;
  }
  my (@files, $possible);
  for my $f (@cand) {
    my $p = $f->{path};
    if ($converted{$p}) { $skip{'converted by .gitattributes or in Git LFS'}++; next }
    my $text = Git::cat('blob', $f->{o2}, 1, $MAX_SIZE);
    if (!defined $text) { $skip{'larger than 1 MB'}++; next }
    if ($text =~ m{\Aversion https://git-lfs\.github\.com/spec/}) { $skip{'converted by .gitattributes or in Git LFS'}++; next }
    if ($text =~ /\0/ || !Esc::utf8_ok($text)) { $skip{'not UTF-8 text'}++; next }
    my $batch = $p =~ /\.(?:bat|cmd|ps1)\z/i || $text =~ m{\A#![^\n]*\bpwsh\b} ? 1 : 0;
    if (shell_like($p, $text) && destructive($text, $batch)) { $skip{'a shell script, make or batch file that deletes or moves files'}++; next }
    my @lines = split /\n/, $text, -1;
    pop @lines if @lines && $lines[-1] eq '';
    # a line is read with the lines a backslash joins it to (cont), in every
    # file: @start holds where each line's run of joined lines starts, and
    # each run is judged once
    my $joins = cont($batch);
    my (@start, %kept);
    for my $i (0 .. $#lines) { $start[$i] = $i && $lines[$i - 1] =~ /$joins\z/ ? $start[$i - 1] : $i }
    my $kept_out = sub {
      my $s = $start[$_[0]];
      return $kept{$s} //= do { my $e = $s; $e++ while $e < $#lines && $lines[$e] =~ /$joins\z/; destructive(join("\n", @lines[$s .. $e]), $batch) };
    };
    my $old_text = $f->{m1} =~ /\A100(?:644|755)\z/ && $f->{st} ne 'A';
    # the old file is read through Git::cat first: git diff does not check a
    # stored file against its id, so one changed by hand could hide lines (an
    # old file over 1 MB is not read, so its file is skipped)
    if ($old_text && !defined Git::cat('blob', $f->{o1}, 1, $MAX_SIZE)) { $skip{'larger than 1 MB'}++; next }
    my @changed = $old_text ? Tree::added_lines($f->{o1}, $f->{o2}) : (1 .. scalar @lines);
    next unless @changed;
    $c{files}++;
    my (@first, @rest);
    for my $n (@changed) {
      my $l = $lines[$n - 1];
      next unless defined $l;
      $c{lines}++;
      if (comment_like($l)) { $c{comment}++; next }
      if ($kept_out->($n - 1)) { $c{guarded}++; next }
      my ($ms, $count) = mutants_on($l, $max);
      my @m = @$ms;
      if (!@m) { $c{nothing}++; next }
      $c{with}++;
      $possible += $count;
      # (no more than MAX from one file in either pass: a cap never needs more)
      my @at = map { { path => $p, blob => $f->{o2}, line => $n, col => $_->[0], from => $_->[1], to => $_->[2], kind => $_->[3] } } @m;
      push @first, shift @at if @first < $max;
      push @rest, shift @at while @at && @rest < $max;
    }
    push @files, [\@first, \@rest];
  }
  # round-robin over the files in path order: first one mutant per changed
  # line, then the rest, so any cap reaches every changed file before a
  # second mutant from any line
  my @order;
  for my $pass (0, 1) {
    my @q = map { [@{ $_->[$pass] }] } @files;
    # an empty queue is dropped, so a round costs only the files left
    while (@q = grep {@$_} @q) {
      push @order, shift @$_ for @q;
    }
  }
  splice @order, $max if @order > $max;
  # a MUTATE_PATHS entry that names no tracked file is likely a typo
  my %all = %{ Tree::all_files($fp->{head}) };
  my @none = grep { my $e = $_; !grep { under($_, [$e]) } keys %all } @{ $conf->{MUTATE_PATHS} };
  return { mutants => \@order, possible => $possible || 0, counts => \%c, skipped => \%skip, ref => $ref,
    base => $base, none => \@none, fp => $fp };
}

# counts PLAN: the counts for the last line
sub counts {
  my ($pl) = @_;
  my $c = $pl->{counts};
  my $s = $pl->{skipped};
  my $line = "$c->{lines} changed lines in $c->{files} files: $c->{with} with a mutant, $c->{comment} comment-like,"
    . " $c->{guarded} that delete or move files, $c->{nothing} with nothing to mutate";
  my @sk = map {"$s->{$_} $_"} sort keys %$s;
  $line .= '; files skipped: ' . join(', ', @sk) if @sk;
  $line .= '; MUTATE_PATHS entries that name no tracked file: ' . join(', ', @{ $pl->{none} }) if @{ $pl->{none} };
  return $line;
}

sub main {
  binmode STDOUT, ':raw';
  binmode STDERR, ':raw';
  $| = 1;
  my ($mode, $max, $minutes) = ('run', $DEFAULT_MAX, $DEFAULT_MINUTES);
  my @args = @ARGV;
  while (@args) {
    my $a = shift @args;
    if ($a eq '--list' && $mode eq 'run') { $mode = 'list' }
    elsif ($a eq '--recover' && $mode eq 'run') { $mode = 'recover' }
    elsif ($a eq '--max' && @args && $args[0] =~ /\A[1-9][0-9]{0,5}\z/) { $max = shift @args }
    elsif ($a eq '--minutes' && @args && $args[0] =~ /\A[1-9][0-9]{0,2}\z/ && $args[0] <= 600) { $minutes = shift @args }
    else { usage() }
  }
  # an error past this point (git failing, a damaged object) still ends with
  # a FAIL line and exit 2, after the round that is open is ended
  my $ok = eval { work($mode, $max, $minutes); 1 };
  stop($@) unless $ok;
}

sub work {
  my ($mode, $max, $minutes) = @_;
  my ($top, $elsewhere) = Git::top();
  stop('not inside a git working tree (or git refuses this one: owned by another user, or a damaged .git)')
    unless defined $top;
  stop("git's working folder is not this folder: a core.worktree setting points git elsewhere (or a .git here is"
    . ' damaged); run it in the working folder itself') if $elsewhere;
  chdir $top or stop('cannot enter the top folder of the repository');
  # a run, and --recover: the lock first, then recovery, before anything
  # else is read (a setting changed after a cut-off run must not keep its
  # mutant on disk)
  start_run($mode) unless $mode eq 'list';
  my ($conf, $cp) = Conf::read('.');
  if (@$cp) {
    say_line($_) for @$cp;
    stop('.claude/method.conf has problems (above); fix them first');
  }
  my @ign = Conf::ignored_inputs('.');
  if (@ign) {
    say_line("$_ is ignored by git, so a clone would not have it; track it with git add -f") for @ign;
    stop('a config file is ignored by git');
  }
  my @unset = grep { !$conf->{$_} } qw(MUTATE_PATHS MUTATION_CHECKS);
  skipped('not-configured', join(' and ', @unset) . ' ' . (@unset > 1 ? 'are' : 'is') . ' not set in .claude/method.conf'
    . ' (MUTATE_PATHS: what to mutate; MUTATION_CHECKS: the fast checks from checks/*.tsv to run against each mutant)')
    if @unset;
  my ($checks, $tp) = Checks::read_tsv('.');
  if (@$tp) {
    say_line($_) for @$tp;
    stop('checks/*.tsv has problems (above)');
  }
  my %by_id = map { ($_->{id} => $_) } @$checks;
  my %seen;
  my @ids = grep { !$seen{$_}++ } @{ $conf->{MUTATION_CHECKS} };
  my @unknown = grep { !$by_id{$_} } @ids;
  stop('MUTATION_CHECKS names checks that checks/*.tsv does not have: ' . join(', ', @unknown)) if @unknown;
  my ($here) = Checks::place();
  my $env = Checks::check_env();
  my (@use, @not);
  for my $id (@ids) {
    my $r = Checks::applies($by_id{$id}, $here, $env);
    if ($r) { push @not, "$id ($r->{detail})" } else { push @use, $id }
  }
  skipped('not-here', 'none of MUTATION_CHECKS runs here: ' . join('; ', @not)) unless @use;
  if ($mode eq 'run') {
    my @ops = RunState::operations('.');
    stop(join(' and ', @ops) . ' is in progress; finish or abort it first') if @ops;
  }
  my $pl = plan($conf, $top, $max);
  skipped('nothing-to-mutate', counts($pl)) unless @{ $pl->{mutants} };
  if ($mode eq 'run') {
    say_line('checks: ' . join(' ', @use) . (@not ? '; not run here: ' . join('; ', @not) : ''));
    run_mutants($pl, [map { $by_id{$_} } @use], $minutes);
  }
  say_line("planned: $_->{path}:$_->{line}:$_->{col}: " . shown($_)) for @{ $pl->{mutants} };
  say_line('checks: ' . join(' ', @use) . (@not ? '; not run here: ' . join('; ', @not) : ''));
  my $n = @{ $pl->{mutants} };
  say_line("PLAN - $n mutants" . ($pl->{possible} > $n ? " of $pl->{possible} (--max $max)" : '') . '; '
    . counts($pl) . "; against $pl->{ref} (merge base " . substr($pl->{base}, 0, 7) . ')');
  exit 0;
}

# --- a run: the lock, the journal, the write function, recovery ---

# start_run MODE: takes the lock (busy: another mutate-changed or a
# run-checks), sets the signal handlers, and recovers what a cut-off run
# left; --recover ends there
sub start_run {
  my ($mode) = @_;
  stop('a native Windows perl cannot run mutants (it has no fork and no process groups); run it with the perl of'
    . ' Git Bash') if $^O eq 'MSWin32';
  my $lock;
  ($lock, $JOURNAL) = RunState::paths();
  $GITDIR = dirname($lock);
  my ($fh, $kind, $why) = RunState::take('exclusive');
  stop('busy: another mutate-changed or a run-checks is running here; wait for it to end') if !$fh && $kind eq 'busy';
  stop($why) unless $fh;
  $LOCK = $fh;
  # handlers only note the signal; the run acts on it at the next safe
  # point. HUP stays ignored when it came ignored (nohup). PIPE is ignored,
  # so output into a closed pipe cannot end a round half done; the checks
  # get it back at its default (the runner).
  my $hup_off = ($SIG{HUP} || '') eq 'IGNORE';
  for my $s (qw(INT TERM HUP QUIT)) {
    next if $s eq 'HUP' && $hup_off;
    $SIG{$s} = sub { $SIGNAL = $_[0] unless defined $SIGNAL };
  }
  $SIG{PIPE} = 'IGNORE';
  $TEMP = ".mutate-$$.tmp";
  my $n = recover();
  return unless $mode eq 'recover';
  say_line(defined $n ? "RECOVERED - $n files put back; the journal is removed" : 'RECOVERED - nothing to recover (no journal)');
  exit 0;
}

# sha_file PATH: the SHA-256 of a regular file's bytes, or undef (missing, a
# link, not readable)
sub sha_file {
  my ($p) = @_;
  my @s = lstat $p;
  return undef unless @s && -f _;
  return eval { Digest::SHA->new(256)->addfile($p, 'b')->hexdigest };
}

# journal_write J: the journal, written whole (a temp file, synced, renamed
# over it) before a mutant is written, and again once a check's process
# group is known. One file line per file that may hold a mutant: its path,
# its stored blob at the start and the mutant's, and both their SHA-256.
sub journal_write {
  my ($j) = @_;
  my $tmp = "$JOURNAL.tmp";
  unlink $tmp if -f $tmp && !-l $tmp;    # a cut-off write's
  my $text = "mutate-changed journal 1\nstart $j->{start}\nstash $j->{stash}\ntemp " . unpack('H*', $j->{temp})
    . "\npgid " . (defined $j->{pgid} ? $j->{pgid} : '-') . "\n";
  $text .= join(' ', 'file', unpack('H*', $_->{path}), @$_{qw(sb mb ss ms)}) . "\n" for @{ $j->{files} };
  $text .= "end\n";
  my $fh;
  sysopen $fh, $tmp, O_WRONLY | O_CREAT | O_EXCL, 0600 or die "cannot write the journal $JOURNAL ($!)\n";
  binmode $fh;
  my $ok = (print {$fh} $text) && $fh->flush && $fh->sync;
  close $fh;
  $ok = $ok && rename $tmp, $JOURNAL;
  die "cannot write the journal $JOURNAL ($!)\n" unless $ok;
}

# journal_read: the journal as {start, stash, temp, pgid, files}, or (undef,
# why) when it cannot be trusted: an unknown first line, no end line (cut
# off while written), or a field that does not parse
sub journal_read {
  return (undef, 'it is not a regular file') if -l $JOURNAL || !-f $JOURNAL;    # a FIFO would block
  open my $fh, '<:raw', $JOURNAL or return (undef, "it cannot be read ($!)");
  my @l = map { s/\n\z//r } <$fh>;
  close $fh;
  return (undef, 'its first line is not a mutate-changed journal') unless @l && $l[0] eq 'mutate-changed journal 1';
  return (undef, 'it has no end line (it was cut off while it was written)') unless $l[-1] eq 'end';
  my %j = (files => []);
  my $id = qr/[0-9a-f]{40}|[0-9a-f]{64}/;
  for my $l (@l[1 .. $#l - 1]) {
    if ($l =~ /\Astart ($id)\z/) { $j{start} = $1 }
    elsif ($l =~ /\Astash ($id|-)\z/) { $j{stash} = $1 }
    elsif ($l =~ /\Atemp ((?:[0-9a-f]{2})+)\z/) { $j{temp} = pack 'H*', $1 }
    elsif ($l =~ /\Apgid (-|[0-9]{1,10})\z/) { $j{pgid} = $1 eq '-' ? undef : $1; $j{has_pgid} = 1 }
    elsif ($l =~ /\Afile ((?:[0-9a-f]{2})+) ($id) ($id) ([0-9a-f]{64}) ([0-9a-f]{64})\z/) {
      push @{ $j{files} }, { path => pack('H*', $1), sb => $2, mb => $3, ss => $4, ms => $5 };
    } else {
      return (undef, 'a line does not parse');
    }
  }
  return (undef, 'a line is missing') unless defined $j{start} && defined $j{stash} && defined $j{temp} && $j{has_pgid};
  return (undef, 'its process group is not a number of 2 or more') if defined $j{pgid} && $j{pgid} < 2;
  return (undef, 'its temp name is not one this tool makes') unless $j{temp} =~ /\A\.mutate-[0-9]+\.tmp\z/;
  for my $f (@{ $j{files} }) {
    return (undef, 'a path is not a plain path inside the working tree')
      if $f->{path} =~ m{\A/|(?:\A|/)\.\.?(?:/|\z)|//|/\z|\0} || $f->{path} eq '';
    return (undef, 'a path names the method\'s or git\'s own files, which are never mutated')
      if $f->{path} =~ m{(?:\A|/)\.git(?:/|\z)}i || excluded($f->{path}, undef);
  }
  return \%j;
}

# folder_of PATH: PATH's folder ("./a/b"); no folder on the way may be a link
sub folder_of {
  my ($p) = @_;
  my @parts = split m{/}, $p;
  pop @parts;
  my $dir = '.';
  for my $part (@parts) {
    $dir .= "/$part";
    die 'a folder on the way to ' . Esc::line($p) . " is a link or not a folder\n" if -l $dir || !-d _;
  }
  return $dir;
}

# put PATH BYTES WAIT EXPECT: writes BYTES as PATH, which must hold the bytes
# whose SHA-256 is EXPECT right before they are replaced: else PATH was
# changed during the run, and it is not overwritten. The bytes go to the
# temp file (a dot first and no source extension, so no build tool or test
# runner picks it up; recovery removes one a cut-off write left) in PATH's
# folder (folder_of), are synced, get PATH's mode and time, and are renamed
# over PATH. The time is the next whole second, and one past PATH's own
# time when that is later: so it is later than anything written before,
# also at the sub-second times make and other build tools compare, and a
# cache keyed on the time in whole seconds and the size never takes one
# version for another. When that is more than 2 s ahead of the clock, it
# waits up to 1 s with WAIT (never on the signal path or in recovery), then
# writes it anyway.
sub put {
  my ($p, $bytes, $wait, $expect) = @_;
  my $dir = folder_of($p);
  my @st = lstat $p or die 'cannot read ' . Esc::line($p) . " ($!)\n";
  my $t = int(Time::HiRes::time()) + 1;
  $t = $st[9] + 1 if $st[9] + 1 > $t;
  if ($wait && $t > Time::HiRes::time() + 2) {
    my $until = Time::HiRes::time() + 1;
    Time::HiRes::sleep(0.05) while !defined $SIGNAL && Time::HiRes::time() < $until && $t > Time::HiRes::time() + 2;
  }
  my $tmp = "$dir/$TEMP";
  my $fh;
  sysopen $fh, $tmp, O_WRONLY | O_CREAT | O_EXCL, 0600 or die 'cannot write next to ' . Esc::line($p) . " ($!)\n";
  binmode $fh;
  my $ok = (print {$fh} $bytes) && $fh->flush && $fh->sync;
  $ok = close($fh) && $ok;
  $ok = $ok && chmod($st[2] & 07777, $tmp) && utime($t, $t, $tmp);
  my $now = sha_file($p);
  if (!defined $now || $now ne $expect) {
    unlink $tmp;
    die Esc::line($p) . " was changed during the run, so it was not overwritten\n";
  }
  $ok = $ok && rename($tmp, $p);
  if (!$ok) {
    my $e = "$!";
    unlink $tmp;
    die 'cannot write ' . Esc::line($p) . " ($e)\n";
  }
}

# mutated TEXT MUTANT: TEXT with MUTANT's token replaced at its line and
# column (bytes)
sub mutated {
  my ($text, $m) = @_;
  my $at = 0;
  $at = index($text, "\n", $at) + 1 for 2 .. $m->{line};
  substr($text, $at + $m->{col} - 1, length $m->{from}) = $m->{to};
  return $text;
}

# restore FILE FAST: puts FILE's start bytes back when its file still holds
# the mutant (1); does nothing when it holds the start bytes (0); refuses
# anything else, which was changed after the mutant was written (the
# journal stays). The one restore rule: the round's end, a signal, an error
# and recovery all use it.
sub restore {
  my ($f, $fast) = @_;
  my $h = sha_file($f->{path});
  return 0 if defined $h && $h eq $f->{ss};
  if (!defined $h || $h ne $f->{ms}) {
    # an edit starts from the mutant, so the mutant may still be in the file
    my $what = !(-e $f->{path} || -l $f->{path}) ? 'is missing'
      : (-l $f->{path} || !-f _) ? 'is not a readable regular file' : 'was changed after its mutant was written';
    die Esc::line($f->{path}) . " $what, so it may still hold the mutant (git diff $f->{sb} $f->{mb} shows the"
      . " mutant's change). Keep a copy of your change, put the file back as committed (git checkout -- and its name,"
      . " after git restore --staged if you staged it), run mutate-changed.sh --recover, then make your change again\n";
  }
  # (a round keeps the start bytes, so the signal path needs no git)
  my $bytes = defined $f->{text} ? $f->{text} : Git::cat('blob', $f->{sb}, 1);
  die 'the stored original of ' . Esc::line($f->{path}) . " does not match the journal\n"
    unless Digest::SHA::sha256_hex($bytes) eq $f->{ss};
  put($f->{path}, $bytes, !$fast, $f->{ms});
  return 1;
}

# stash_id: refs/stash's commit, or -
sub stash_id {
  my ($st, $id) = Git::run('rev-parse', '-q', '--verify', 'refs/stash');
  return $st ? '-' : (split /\n/, $id)[0];
}

# release J: removes the journal once no file line's mutant is left where git
# keeps it (restore has put the files on disk back): in HEAD, in the index,
# or in a stash made since the run started (and its index part). Otherwise
# it stays, and the reason says where the mutant is. The one release rule.
sub release {
  my ($j) = @_;
  my $names = join(', ', map { Esc::line($_->{path}) } @{ $j->{files} });
  # a merge or rebase (one a check started, too) can hold the mutant in its
  # autostash, which comes back when it ends
  my @ops = RunState::operations('.');
  die join(' and ', @ops) . " is in progress, and its autostash can hold the mutant of $names; finish or abort it,"
    . " then run mutate-changed.sh --recover\n" if @ops;
  # a git command that fails means "cannot tell", never "not there"
  my $fail = sub { die "cannot tell whether git holds the mutant of $names ($_[0] failed); run mutate-changed.sh --recover\n" };
  # the stashes made since the start: refs/stash itself (it may have no
  # reflog), then its reflog, newest first, down to the one at the start
  my @stashes;
  my ($vst, $top) = Git::run('rev-parse', '-q', '--verify', 'refs/stash^{commit}');
  if (!$vst) {
    $top = (split /\n/, $top)[0];
    my ($sst, $ids) = Git::run('rev-list', '--walk-reflogs', 'refs/stash');
    for my $s ($top, grep { $_ ne $top } $sst ? () : split /\n/, $ids) {
      last if $s eq $j->{stash};
      push @stashes, $s;
    }
  }
  my ($hst, $head) = Git::run('rev-parse', '-q', '--verify', 'HEAD^{commit}');
  $head = $hst ? undef : (split /\n/, $head)[0];
  for my $f (@{ $j->{files} }) {
    my $p = $f->{path};
    if (defined $head) {
      my ($tst, $tree) = Git::run('ls-tree', '-z', $head, '--', $p);
      $fail->('git ls-tree') if $tst;
      die 'HEAD (' . substr($head, 0, 7) . ') holds the mutant of ' . Esc::line($p) . ': undo that change in a new'
        . " commit, then run mutate-changed.sh --recover\n" if $tree =~ /\A[0-7]+ blob \Q$f->{mb}\E\t/;
    }
    my ($ist, $idx) = Git::run('ls-files', '-s', '-z', '--', $p);
    $fail->('git ls-files') if $ist;
    die 'the index holds the mutant of ' . Esc::line($p) . ' (it was staged): unstage that change, then run'
      . " mutate-changed.sh --recover\n" if $idx =~ /\A[0-7]+ \Q$f->{mb}\E /;
    for my $s (@stashes) {
      for my $rev ($s, "$s^2") {
        my ($tst, $tree) = Git::run('ls-tree', '-z', $rev, '--', $p);
        $fail->('git ls-tree') if $tst && $rev eq $s;    # (a stash may lack its index part)
        die 'a stash made during the run holds the mutant of ' . Esc::line($p) . ': drop it (or take that change out'
          . " of it), then run mutate-changed.sh --recover\n" if !$tst && $tree =~ /\A[0-7]+ blob \Q$f->{mb}\E\t/;
      }
    }
  }
  unlink $JOURNAL or die "cannot remove the journal $JOURNAL ($!)\n";
}

# end_round FAST: the end of a round, in this order: the check's process
# group is stopped (FAST: KILL at once), the files are put back, and the
# journal is released. The paths put back.
sub end_round {
  my ($fast) = @_;
  if ($RUN) {
    Checks::finish_limited($RUN, $fast, sub { defined $SIGNAL });
    undef $RUN;
  }
  return () unless $OPEN;
  $OPEN->{tried} = 1;
  journal_write($OPEN) unless -e $JOURNAL;    # a check may have removed it
  my @back = map { $_->{path} } grep { restore($_, $fast) } @{ $OPEN->{files} };
  release($OPEN);
  undef $OPEN;
  return @back;
}

# recover: under the lock, puts back what a cut-off run left (its journal
# names it); the number of files put back, or undef when there is no
# journal. Not while a merge, rebase or
# other git operation is in progress: its autostash can hold a mutant that
# comes back when it ends. A cut-off run's checks must have ended: its
# watchdog stops them; when a harness killed that too, this waits up to 3 s,
# then refuses, naming the group.
sub recover {
  # a cut-off run's check output (it can hold what a test printed)
  unlink "$JOURNAL.tmp" if -f "$JOURNAL.tmp" && !-l "$JOURNAL.tmp";    # a cut-off journal write's
  if (opendir my $d, $GITDIR) {
    for my $o (grep { /\Amethod-mutate-[0-9]+-[0-9]+\.out\z/ } readdir $d) {
      my $p = File::Spec->catfile($GITDIR, $o);
      unlink $p if -f $p && !-l $p;
    }
    closedir $d;
  }
  return undef unless -e $JOURNAL || -l $JOURNAL;
  my ($j, $why) = journal_read();
  die "the journal $JOURNAL cannot be trusted: $why; once git status shows nothing for the files it names, remove"
    . " it by hand\n" unless $j;
  if (Checks::group_ok($j->{pgid})) {
    my $until = Checks::now() + 3;
    Time::HiRes::sleep(0.1) while kill(0, -$j->{pgid}) && Checks::now() < $until;
    die "processes of the cut-off run may still run in process group $j->{pgid} (or another program now has that"
      . " number); stop them, then run mutate-changed.sh --recover\n" if kill 0, -$j->{pgid};
  }
  my @ops = RunState::operations('.');
  die join(' and ', @ops) . ' is in progress, and its autostash can hold a mutant; finish or abort it, then run'
    . " mutate-changed.sh --recover\n" if @ops;
  my ($own, $n) = ($TEMP, 0);
  $TEMP = $j->{temp};
  for my $f (@{ $j->{files} }) {
    my $t = folder_of($f->{path}) . "/$TEMP";
    unlink $t if -f $t && !-l $t;    # a cut-off write's
    next unless restore($f, 1);
    $n++;
    say_line("recovered: $f->{path} put back (a run was cut off)");
  }
  release($j);
  $TEMP = $own;
  return $n;
}

# changes START STASH: what is not as at the start (Checks::tree_changes,
# naming up to 3 of the files), and a stash made since, when STASH is given
sub changes {
  my ($start, $stash) = @_;
  my ($why, $changed) = Checks::tree_changes($start, Checks::fingerprint());
  my @w = @$why;
  if (@$changed) {
    my @show = map { Esc::line($_) } @$changed[0 .. ($#$changed < 2 ? $#$changed : 2)];
    $w[-1] .= ' (' . join(', ', @show) . (@$changed > 3 ? ' and ' . (@$changed - 3) . ' more' : '') . ')';
  }
  push @w, 'a stash was made during the run' if defined $stash && stash_id() ne $stash;
  return \@w;
}

# run_check CHECK ENV SECONDS J: one check through the limited runner; with
# a round's journal J, the check's process group goes into it once known.
# (result, seconds taken); a time limit is the result {status FAIL, kind time}
sub run_check {
  my ($c, $env, $seconds, $j) = @_;
  my $out = $CHECK_OUT = File::Spec->catfile($GITDIR, "method-mutate-$$-" . ++$OUT_N . '.out');
  unlink $out;
  my $t0 = Checks::now();
  # (the watchdog keeps the lock: a cut-off run's lock stays held until its
  # checks are stopped)
  my $r = $RUN = Checks::start_limited($env, ['bash', '-o', 'pipefail', '-c', $c->{command}], $out, $LOCK);
  if ($j) {
    $j->{pgid} = $r->{pgid};
    journal_write($j);
  }
  my $how = Checks::wait_limited($r, $seconds, sub { defined $SIGNAL });
  die "stopped by SIG$SIGNAL\n" if $how eq 'interrupted';
  Checks::finish_limited($r, 0, sub { defined $SIGNAL });
  undef $RUN;
  my $took = Checks::now() - $t0;
  my $res = $how eq 'time' ? { status => 'FAIL', kind => 'time' } : Checks::judge($c, $r->{status}, $out);
  unlink $out;
  undef $CHECK_OUT;
  die "stopped by SIG$SIGNAL\n" if defined $SIGNAL;
  return ($res, $took);
}

# run_mutants PLAN CHECKS MINUTES: run A, then one round per mutant while
# --minutes allows; ends with the last line (never exit 0 in 4b.3: all
# killed is SKIPPED kills-unchecked until the repeat and control runs exist)
sub run_mutants {
  my ($pl, $checks, $minutes) = @_;
  my $start = $pl->{fp};
  my $stash = stash_id();
  my $deadline = Checks::now() + $minutes * 60;
  my $env = Checks::check_env();
  my (%limit, @a);
  for my $c (@$checks) {
    my ($res, $took) = run_check($c, $env, $deadline - Checks::now(), undef);
    die "run A: $c->{id} did not end within --minutes without any mutant\n" if $res->{kind} eq 'time';
    die "run A: $c->{id} did not pass without any mutant ($res->{status}: $res->{detail}); fix it or leave it out of"
      . " MUTATION_CHECKS\n" unless $res->{status} eq 'PASS';
    $limit{ $c->{id} } = 3 * int($took + 0.999) + 30;
    push @a, sprintf('%s passed in %d s', $c->{id}, $took + 0.5);
  }
  my $why = changes($start, undef);
  die 'run A: ' . join('; ', @$why) . " without any mutant\n" if @$why;
  say_line('run A (no mutant): ' . join(', ', @a) . '; limit per mutant: '
    . join(', ', map {"$_->{id} $limit{$_->{id}} s"} @$checks));
  my @mutants = @{ $pl->{mutants} };
  my ($killed, $by_time, $survived, $done) = (0, 0, 0, 0);
  for my $m (@mutants) {
    # (a signal between rounds: no next mutant is written)
    die "stopped by SIG$SIGNAL\n" if defined $SIGNAL;
    my $need = 5;
    $need += $limit{ $_->{id} } + 3 for @$checks;
    last if Checks::now() + $need > $deadline;
    $done++;
    my $text = Git::cat('blob', $m->{blob}, 1);
    my $mut = mutated($text, $m);
    my $j = { start => $start->{head}, stash => $stash, temp => $TEMP, pgid => undef, files => [{ path => $m->{path},
      sb => $m->{blob}, mb => Git::object_id('blob', $mut, $m->{blob}), ss => Digest::SHA::sha256_hex($text),
      ms => Digest::SHA::sha256_hex($mut), text => $text }] };
    journal_write($j);
    $OPEN = $j;
    put($m->{path}, $mut, 1, $j->{files}[0]{ss});
    my ($kill, @nothing);
    for my $c (@$checks) {
      my ($res) = run_check($c, $env, $limit{ $c->{id} }, $j);
      if ($res->{status} eq 'FAIL') { $kill = $res->{kind} eq 'time' ? 'time' : $c->{id}; last }
      push @nothing, $c->{id} if $res->{status} eq 'SKIPPED';
    }
    end_round(0);
    my $w = changes($start, $stash);
    die "after the mutant at $m->{path}:$m->{line}:$m->{col}: " . join('; ', @$w) . "\n" if @$w;
    if (!defined $kill) {
      $survived++;
      say_line("survived: $m->{path}:$m->{line}:$m->{col}: " . shown($m)
        . (@nothing ? ' (' . join(', ', @nothing) . ' examined nothing)' : ''));
    } elsif ($kill eq 'time') {
      $by_time++;
    } else {
      $killed++;
    }
  }
  # (a signal during the last round's end: said, not lost)
  die "stopped by SIG$SIGNAL\n" if defined $SIGNAL;
  my $n = @mutants;
  my $tail = counts($pl) . "; $n mutants: " . ($killed + $by_time) . " killed ($by_time by time limit), $survived survived, "
    . ($n - $done) . ' not run';
  if ($survived) {
    say_line("FAIL - $tail");
    exit 1;
  }
  skipped('time-reached', "$tail (--minutes $minutes)") if $done < $n;
  skipped('max-reached', "$tail (the plan has $pl->{possible})") if $pl->{possible} > $n;
  skipped('kills-unchecked', "$tail; no repeat or control run checks the kills yet (step 4b.4)");
}

main() unless caller;
1;
