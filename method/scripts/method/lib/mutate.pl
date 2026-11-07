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
  if ($OPEN && -f $JOURNAL && !-l $JOURNAL) {
    $reason .= '; the journal stays' . ($reason =~ /--recover/ ? '' : ': once that is fixed, run mutate-changed.sh --recover');
  }
  say_line("FAIL - $reason; the run stopped");
  exit 2;
}

# skipped KIND DETAIL: nothing to do, which is never a pass (exit 3)
# left_out PLAN: what keeps a run where every mutant was killed from being a
# pass: changed lines kept out because they name a delete or move command,
# and changed files skipped for any reason but being the method's or git's
# own (each named, at most 10, then how many more)
sub left_out {
  my ($pl) = @_;
  my $names = sub {
    my @n = @_;
    return join(', ', @n[0 .. ($#n < 9 ? $#n : 9)]) . (@n > 10 ? ' and ' . (@n - 10) . ' more' : '');
  };
  my @out;
  push @out, 'changed lines not mutated, as they name a delete or move command: ' . $names->(@{ $pl->{guarded_at} })
    if @{ $pl->{guarded_at} };
  push @out, 'changed files not mutated: ' . $names->(map {"$_->[0] ($_->[1])"} @{ $pl->{skipped_files} })
    if @{ $pl->{skipped_files} };
  return @out;
}

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
  my (%skip, @guarded_at, @skipped_files);
  # (a changed file skipped for any reason but being the method's or git's
  # own is named too: a run with such files is not a pass)
  my $skip = sub { my ($p, $why) = @_; $skip{$why}++; push @skipped_files, [$p, $why] };
  Tree::check_trees($base, $fp->{head});
  my @cand;
  for my $f (Tree::changed($base, $fp->{head})) {
    next if $f->{st} eq 'D';
    next unless under($f->{path}, $conf->{MUTATE_PATHS});
    if (excluded($f->{path}, $method)) { $skip{"left out (the method's or git's own files)"}++; next }
    if ($f->{m2} !~ /\A100(?:644|755)\z/) { $skip->($f->{path}, 'not a regular file'); next }
    push @cand, $f;
  }
  my (@files, $possible);
  for my $f (@cand) {
    my $p = $f->{path};
    if ($converted{$p}) { $skip->($p, 'converted by .gitattributes or in Git LFS'); next }
    my $text = Git::cat('blob', $f->{o2}, 1, $MAX_SIZE);
    if (!defined $text) { $skip->($p, 'larger than 1 MB'); next }
    if ($text =~ m{\Aversion https://git-lfs\.github\.com/spec/}) { $skip->($p, 'converted by .gitattributes or in Git LFS'); next }
    if ($text =~ /\0/ || !Esc::utf8_ok($text)) { $skip->($p, 'not UTF-8 text'); next }
    my $batch = $p =~ /\.(?:bat|cmd|ps1)\z/i || $text =~ m{\A#![^\n]*\bpwsh\b} ? 1 : 0;
    if (shell_like($p, $text) && destructive($text, $batch)) { $skip->($p, 'a shell script, make or batch file that deletes or moves files'); next }
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
    if ($old_text && !defined Git::cat('blob', $f->{o1}, 1, $MAX_SIZE)) { $skip->($p, 'larger than 1 MB'); next }
    my @changed = $old_text ? Tree::added_lines($f->{o1}, $f->{o2}) : (1 .. scalar @lines);
    next unless @changed;
    $c{files}++;
    my (@first, @rest);
    for my $n (@changed) {
      my $l = $lines[$n - 1];
      next unless defined $l;
      $c{lines}++;
      if (comment_like($l)) { $c{comment}++; next }
      if ($kept_out->($n - 1)) { $c{guarded}++; push @guarded_at, "$p:$n"; next }
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
    base => $base, none => \@none, fp => $fp, guarded_at => \@guarded_at, skipped_files => \@skipped_files };
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

# read_file PATH: a regular file's bytes, or undef (missing, a link, not a
# regular file, or unreadable)
sub read_file {
  my ($p) = @_;
  my @s = lstat $p;
  return undef unless @s && -f _;
  open my $fh, '<:raw', $p or return undef;
  local $/;
  my $b = <$fh>;
  close $fh;
  return defined $b ? $b : '';
}

# lines_of BYTES: its lines, without their line end (a CR before it
# included); window LINES I: line I with the lines before and after it
sub lines_of {
  my @l = split /\n/, $_[0], -1;
  s/\r\z// for @l;
  return @l;
}
sub window {
  my ($l, $i) = @_;
  return join "\n", ($i > 0 ? $l->[$i - 1] : "\0"), $l->[$i], ($i < $#$l ? $l->[$i + 1] : "\0");
}

# line_counts F BYTES: how many of BYTES' lines are the mutant's line (whose
# SHA-256 is F's ml), how many of those have the mutant's lines around them
# too (mw), and how many have each set of lines around them
sub line_counts {
  my ($f, $bytes) = @_;
  my @l = lines_of($bytes);
  my ($nl, $nw, %win) = (0, 0);
  for my $i (0 .. $#l) {
    next unless Digest::SHA::sha256_hex($l[$i]) eq $f->{ml};
    $nl++;
    my $w = Digest::SHA::sha256_hex(window(\@l, $i));
    $nw++ if $w eq $f->{mw};
    $win{$w}++;
  }
  return ($nl, $nw, \%win);
}

# the mutant's change is found by its line, not by the file's bytes: an
# edit made on top of the mutant (and then staged, committed or stashed)
# keeps that line. original F: the file's bytes at the start (checked
# against the journal). holds F BYTES: 1 when BYTES hold the mutant's line
# more often than the original does, alone or with its lines around it; 0
# when the line is not in BYTES, or each copy of it left is one of the
# original's own with its lines around it unchanged; undef when it cannot
# tell: a copy whose lines around it changed may be the mutant (an edit to
# its neighbour, or one that removed a twin of it), and where the original
# has the mutant's line with the same lines around it, any copy may be
sub original {
  my ($f) = @_;
  $f->{text} = Git::cat('blob', $f->{sb}, 1) unless defined $f->{text};
  die 'the stored original of ' . Esc::line($f->{path}) . " does not match the journal\n"
    unless Digest::SHA::sha256_hex($f->{text}) eq $f->{ss};
  return $f->{text};
}
sub holds {
  my ($f, $bytes) = @_;
  @$f{qw(bl bw bwin)} = line_counts($f, original($f)) unless defined $f->{bl};
  my ($nl, $nw, $win) = line_counts($f, $bytes);
  return 1 if $nl > $f->{bl} || $nw > $f->{bw};
  return 0 if $nl == 0;
  return undef if $f->{bw} > 0;
  for my $w (keys %$win) { return undef if $win->{$w} > ($f->{bwin}{$w} || 0) }
  return 0;
}

# journal_write J: the journal, written whole (a temp file, synced, renamed
# over it) before a mutant is written, and again once a check's process
# group is known. One file line per file that may hold a mutant: its path,
# its stored blob at the start and the mutant's, and both their SHA-256.
sub journal_text {
  my ($j) = @_;
  my $text = "mutate-changed journal 1\nstart $j->{start}\nstash $j->{stash}\ntemp " . unpack('H*', $j->{temp})
    . "\npgid " . (defined $j->{pgid} ? $j->{pgid} : '-') . "\n";
  $text .= join(' ', 'file', unpack('H*', $_->{path}), @$_{qw(sb mb ss ms)}, unpack('H*', $_->{place}), $_->{ml}, $_->{mw}) . "\n"
    for @{ $j->{files} };
  return "${text}end\n";
}

# journal_ok J: the journal on disk is J's, byte for byte
sub journal_ok {
  my ($j) = @_;
  return 0 if -l $JOURNAL || !-f $JOURNAL;
  open my $fh, '<:raw', $JOURNAL or return 0;
  local $/;
  my $t = <$fh>;
  close $fh;
  return defined $t && $t eq journal_text($j);
}

sub journal_write {
  my ($j) = @_;
  my $tmp = "$JOURNAL.tmp";
  unlink $tmp if -f $tmp && !-l $tmp;    # a cut-off write's
  my $text = journal_text($j);
  my $fh;
  sysopen $fh, $tmp, O_WRONLY | O_CREAT | O_EXCL, 0600 or die "cannot write the journal $JOURNAL ($!)\n";
  binmode $fh;
  my $ok = (print {$fh} $text) && $fh->flush && $fh->sync;
  close $fh;
  $ok = $ok && rename $tmp, $JOURNAL;
  if (!$ok) {
    my $e = "$!";
    unlink $tmp;
    die "cannot write the journal $JOURNAL ($e)\n";
  }
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
    elsif ($l =~ /\Afile ((?:[0-9a-f]{2})+) ($id) ($id) ([0-9a-f]{64}) ([0-9a-f]{64}) ((?:[0-9a-f]{2})+) ([0-9a-f]{64}) ([0-9a-f]{64})\z/) {
      push @{ $j{files} }, { path => pack('H*', $1), sb => $2, mb => $3, ss => $4, ms => $5, place => pack('H*', $6),
        ml => $7, mw => $8 };
    } else {
      return (undef, 'a line does not parse');
    }
  }
  return (undef, 'a line is missing') unless defined $j{start} && defined $j{stash} && defined $j{temp} && $j{has_pgid};
  return (undef, 'its process group is not a number of 2 or more') if defined $j{pgid} && $j{pgid} < 2;
  return (undef, 'its temp name is not one this tool makes') unless $j{temp} =~ /\A\.mutate-[0-9]+\.tmp\z/;
  my $method = method_folder('.');
  for my $f (@{ $j{files} }) {
    return (undef, 'a path is not a plain path inside the working tree')
      if $f->{path} =~ m{\A/|(?:\A|/)\.\.?(?:/|\z)|//|/\z|\0} || $f->{path} eq '';
    return (undef, 'a path names the method\'s or git\'s own files, which are never mutated')
      if $f->{path} =~ m{(?:\A|/)\.git(?:/|\z)}i || excluded($f->{path}, $method);
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
    die 'a folder on the way to ' . Esc::line($p) . " is missing\n" if !(-e $dir || -l $dir);
    die 'a folder on the way to ' . Esc::line($p) . " is a link or not a folder\n" if -l $dir || !-d _;
  }
  return $dir;
}

# put PATH BYTES WAIT EXPECT: writes BYTES as PATH and returns 1. PATH must
# hold the bytes whose SHA-256 is EXPECT right before they are replaced:
# else PATH was changed during the run, it is not overwritten, and put
# returns 0 (nothing was written: the rename is the last step). The bytes go to the
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
  my $dir = eval { folder_of($p) };
  if (!defined $dir) {
    return 0 if $@ =~ / is missing\n\z/;    # (gone: changed during the run)
    die $@;
  }
  my @st = lstat $p or return 0;    # (gone: changed during the run)
  my $t = int(Time::HiRes::time()) + 1;
  $t = $st[9] + 1 if $st[9] + 1 > $t;
  if ($wait && $t > Time::HiRes::time() + 2) {
    my $until = Time::HiRes::time() + 1;
    Time::HiRes::sleep(0.05) while !defined $SIGNAL && Time::HiRes::time() < $until && $t > Time::HiRes::time() + 2;
  }
  my $tmp = "$dir/$TEMP";
  my $fh;
  if (!sysopen $fh, $tmp, O_WRONLY | O_CREAT | O_EXCL, 0600) {
    my $e = "$!";
    return 0 unless -d $dir;    # (its folder gone while it waited: changed during the run)
    die 'cannot write next to ' . Esc::line($p) . " ($e)\n";
  }
  binmode $fh;
  my $e;
  my $ok = (print {$fh} $bytes) && $fh->flush && $fh->sync;
  $e = "$!" unless $ok;
  if (!close $fh) { $e = "$!" unless defined $e; $ok = 0 }
  if ($ok && !(chmod($st[2] & 07777, $tmp) && utime($t, $t, $tmp))) { $e = "$!"; $ok = 0 }
  if ($ok) {
    my $now = sha_file($p);
    if (!defined $now || $now ne $expect) {
      unlink $tmp;
      return 0;
    }
    $ok = rename $tmp, $p;
    $e = "$!" unless $ok;
  }
  if (!$ok) {
    unlink $tmp;
    die 'cannot write ' . Esc::line($p) . " ($e)\n";
  }
  return 1;
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
  my ($f, $fast, $start) = @_;
  my $p = Esc::line($f->{path});
  my $where = "$f->{place}; lines added above it move it";
  my $back = "put the file back as it was when the run started (git restore --source=$start --staged --worktree --"
    . ' and its name)';
  # a file changed on top of its mutant: when the mutant's line is gone
  # from it, the change stays as it is; else it is refused, and the way
  # out is to undo that one change (a copy of the file, or a diff of it,
  # would bring the mutant back)
  my $changed = sub {
    my ($what) = @_;
    my $now = read_file($f->{path});
    die "$p $what, so it may hold the mutant ($where): $back, then run mutate-changed.sh --recover\n"
      unless defined $now;
    my $r = holds($f, $now);
    die "$p $what, and it still holds the mutant's change ($where): undo that change in the file (git diff $start --"
      . " and its name shows it), then run mutate-changed.sh --recover\n" if $r;
    die "$p $what, and it cannot tell whether the mutant's change is still in it, as the original has that line, with"
      . " the same lines around it, elsewhere ($where): $back, run mutate-changed.sh --recover, then make your change"
      . " again, leaving that change out\n" unless defined $r;
    return 0;
  };
  my $h = sha_file($f->{path});
  return 0 if defined $h && $h eq $f->{ss};
  if (!defined $h || $h ne $f->{ms}) {
    die "$p is missing; a copy made from it, or the file moved, may hold the mutant's change ($where): undo that"
      . " change there. Then $back, run mutate-changed.sh --recover, and remove the file again if you meant to\n"
      if !(-e $f->{path} || -l $f->{path});
    return $changed->((-l $f->{path} || !-f _) ? 'is not a regular file' : 'was changed after its mutant was written');
  }
  # (a round keeps the start bytes, so the signal path needs no git)
  my $bytes = original($f);
  if (!eval { folder_of($f->{path}); 1 }) {
    (my $e = $@) =~ s/\n\z//;
    die "$e, and what it leads to holds the mutant ($where): make it the real folder again (as it was when the run"
      . " started), then run mutate-changed.sh --recover\n";
  }
  return put($f->{path}, $bytes, !$fast, $f->{ms}) ? 1 : $changed->('was changed while it was being put back');
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
  my $fail = sub { die "cannot tell whether git holds the mutant of $names ($_[0]" . (defined $_[1] ? $_[1] : ' failed') . "); run mutate-changed.sh --recover\n" };
  # verify WHAT: the commit WHAT names, or undef when there is none (git
  # rev-parse -q --verify exits 1 then; any other end is a failure)
  my $verify = sub {
    my ($what) = @_;
    my ($st, $id) = Git::run('rev-parse', '-q', '--verify', "$what^{commit}");
    return (split /\n/, $id)[0] unless $st;
    return undef if $st == 256;
    $fail->("git rev-parse $what");
  };
  # where else git may keep the mutant: the stashes made since the start
  # (refs/stash itself, which may have no reflog, then its reflog, newest
  # first, down to the one at the start), and an autostash a merge left
  my @kept;
  my $top = $verify->('refs/stash');
  if (!defined $top) {
    # (none: unless refs/stash names something that is not a commit, or its
    # reflog is left without it)
    my ($rst) = Git::run('rev-parse', '-q', '--verify', 'refs/stash');
    die "refs/stash names something that is not a stash, so it cannot tell whether a stash holds the mutant of"
      . " $names: make it name a stash again, or remove it (git update-ref -d refs/stash) once you are sure none of"
      . " your stashes holds the mutant, then run mutate-changed.sh --recover\n" if $rst == 0;
    $fail->('git rev-parse refs/stash') unless $rst == 256;
    my ($est) = Git::run('reflog', 'exists', 'refs/stash');
    die "a stash reflog is left without refs/stash, so it cannot tell whether a stash holds the mutant of $names:"
      . " remove that reflog (logs/refs/stash in git's folder) once you are sure none of its stashes holds the"
      . " mutant, then run mutate-changed.sh --recover\n" if $est == 0;
    $fail->('git reflog exists') unless $est == 256;
  }
  if (defined $top) {
    my ($sst, $ids) = Git::run('rev-list', '--walk-reflogs', 'refs/stash');
    if ($sst) {
      my ($est) = Git::run('reflog', 'exists', 'refs/stash');
      $fail->('git rev-list --walk-reflogs') unless $est == 256;    # (1: it has no reflog)
      $ids = '';
    }
    for my $s ($top, grep { $_ ne $top } split /\n/, $ids) {
      last if $s eq $j->{stash};
      push @kept, [$s, 'a stash made during the run', 'drop it (or take that change out of it)'];
    }
  }
  my ($ast, $auto) = Git::run('rev-parse', '--git-path', 'MERGE_AUTOSTASH');
  $fail->('git rev-parse --git-path') if $ast;
  $auto = (split /\n/, $auto)[0];
  if (defined $auto && (-e $auto || -l $auto)) {
    my $line;
    if (!-l $auto && -f _ && open my $ah, '<', $auto) { $line = <$ah>; close $ah }
    my ($id) = defined $line ? $line =~ /\A([0-9a-f]{40}|[0-9a-f]{64})\s*\z/ : ();
    $fail->('reading MERGE_AUTOSTASH') unless defined $id;
    push @kept, [$id, 'the autostash a merge left (MERGE_AUTOSTASH)',
      'git merge --quit moves it to the stash list; drop it there (or take that change out of it)'];
  }
  my $head = $verify->('HEAD');    # (none before the first commit)
  # has F ID WHERE OUT: the blob ID (in WHERE) holds the mutant, or its
  # change with others; when that cannot be told, the journal stays, and the
  # reason gives the way out there (OUT)
  my $has = sub {
    my ($f, $id, $where, $out) = @_;
    my $r = blob_holds($f, $id);
    return $r if defined $r;
    die "cannot tell whether $where holds the mutant of " . Esc::line($f->{path}) . ', as the original has its line'
      . " elsewhere too ($f->{place}): $out, then run mutate-changed.sh --recover\n";
  };
  my $from = "git restore --source=$j->{start} --staged --worktree -- and its name";
  for my $f (@{ $j->{files} }) {
    my $p = $f->{path};
    if (defined $head) {
      my ($tst, $tree) = Git::run('ls-tree', '-z', $head, '--', $p);
      $fail->('git ls-tree') if $tst;
      die 'HEAD (' . substr($head, 0, 7) . ') holds the mutant of ' . Esc::line($p) . ': undo that change in a new'
        . " commit, then run mutate-changed.sh --recover\n" if $tree =~ /\A[0-7]+ blob ([0-9a-f]+)\t/
          && $has->($f, $1, 'HEAD', "commit the file as it was when the run started ($from, then git commit); make your"
            . " change again afterwards, without the mutant's");
    }
    my ($ist, $idx) = Git::run('ls-files', '-s', '-z', '--', $p);
    $fail->('git ls-files') if $ist;
    for my $e (split /\0/, $idx) {
      die 'the index holds the mutant of ' . Esc::line($p) . ' (it was staged): unstage that change, then run'
        . " mutate-changed.sh --recover\n" if $e =~ /\A[0-7]+ ([0-9a-f]+) [0-3]\t/ && $has->($f, $1, 'the index', 'unstage it (git restore --staged -- and its name)');
    }
    for my $k (@kept) {
      my ($s, $what, $out) = @$k;
      # the stash, then its index part when it has one
      for my $rev ($s, $verify->("$s^2")) {
        next unless defined $rev;
        my ($tst, $tree) = Git::run('ls-tree', '-z', $rev, '--', $p);
        $fail->('git ls-tree') if $tst;
        die "$what holds the mutant of " . Esc::line($p) . ": $out, then run mutate-changed.sh --recover\n"
          if $tree =~ /\A[0-7]+ blob ([0-9a-f]+)\t/ && $has->($f, $1, $what, $out);
      }
    }
  }
  # (a journal removed during the round and not written again is gone already)
  # (and anything else there is not a journal: it stays, and the next run
  # refuses it)
  unlink $JOURNAL or die "cannot remove the journal $JOURNAL ($!)\n" if -l $JOURNAL || -f _;
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
  # a check may have removed or changed the journal: it is written again
  # before the files are put back; when that fails, they are put back all
  # the same, and the reason says no journal names them, and where the
  # mutant may be
  my $lost;
  if (!journal_ok($OPEN) && !eval { journal_write($OPEN); 1 }) {
    ($lost = $@) =~ s/\n\z//;
    # (one that still names this round's files is enough to recover from:
    # only its check's process group may be out of date)
    my ($cur) = journal_read();
    undef $lost if $cur && join(' ', map {"$_->{path} $_->{mb}"} @{ $cur->{files} })
      eq join(' ', map {"$_->{path} $_->{mb}"} @{ $OPEN->{files} });
  }
  my @back;
  if (!eval { @back = map { $_->{path} } grep { restore($_, $fast, $OPEN->{start}) } @{ $OPEN->{files} }; release($OPEN); 1 }) {
    die $@ unless defined $lost;
    (my $e = $@) =~ s/\n\z//;
    die "$e; and no journal names it, so --recover cannot find it (the journal was removed or changed during the round"
      . " and could not be written again: $lost): once that is done, make sure "
      . join(', ', map { Esc::line($_->{path}) . " no longer holds the mutant's change ($_->{place})" } @{ $OPEN->{files} })
      . "\n";
  }
  undef $OPEN;
  die "the journal was removed or changed during the round and could not be written again ($lost); "
    . (@back ? join(', ', map { Esc::line($_) } @back) . ' put back' : 'the files are as at the start') . "\n" if defined $lost;
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
  on_start($j);
  my ($own, $n) = ($TEMP, 0);
  $TEMP = $j->{temp};
  for my $f (@{ $j->{files} }) {
    # (a cut-off write's temp file; none where a folder on the way is gone,
    # and none is looked for behind a link: restore then says what to do)
    my $dir = eval { folder_of($f->{path}) };
    if (defined $dir) {
      my $t = "$dir/$TEMP";
      unlink $t if -f $t && !-l $t;
    }
    next unless restore($f, 1, $j->{start});
    $n++;
    say_line("recovered: $f->{path} put back (a run was cut off)");
  }
  release($j);
  $TEMP = $own;
  return $n;
}

# blob_holds F ID: holds, for the blob ID in git (1, 0, or undef: cannot
# tell); a blob git cannot read is "cannot tell" too, and stops here
sub blob_holds {
  my ($f, $id) = @_;
  return 1 if $id eq $f->{mb};
  return 0 if $id eq $f->{sb};
  my $bytes = eval { Git::cat('blob', $id, 1) };
  die 'cannot tell whether git holds the mutant of ' . Esc::line($f->{path}) . ' (git cat-file failed); run'
    . " mutate-changed.sh --recover\n" unless defined $bytes;
  return holds($f, $bytes);
}

# on_start J: recovery goes on only while HEAD is the commit the run started
# on, or one made after it, or one whose version of each file the journal
# names is the one the run started from (a rebase that kept them).
# Elsewhere the files are not what the journal speaks of: a HEAD older than
# the run (the base branch, a reset) cannot hold its mutant, so it says to
# check the start out; any other HEAD (an amend, a rebase, another branch)
# is looked at for the mutant first, as a commit made since may hold it
sub on_start {
  my ($j) = @_;
  my $cannot = sub { die "cannot tell where HEAD is from the commit the run started on ($_[0] failed); run"
    . " mutate-changed.sh --recover\n" };
  my ($st) = Git::run('merge-base', '--is-ancestor', $j->{start}, 'HEAD');
  return unless $st;
  $cannot->('git merge-base') unless $st == 256;
  my @moved;
  for my $f (@{ $j->{files} }) {
    my ($tst, $tree) = Git::run('ls-tree', '-z', 'HEAD', '--', $f->{path});
    $cannot->('git ls-tree') if $tst;
    my ($id) = $tree =~ /\A[0-7]+ blob ([0-9a-f]+)\t/;
    push @moved, [$f, $id] unless defined $id && $id eq $f->{sb};
  }
  return unless @moved;
  my ($ost, $head) = Git::run('rev-parse', '-q', '--verify', 'HEAD^{commit}');
  $cannot->('git rev-parse HEAD') if $ost;
  $head = substr((split /\n/, $head)[0], 0, 7);
  my ($older) = Git::run('merge-base', '--is-ancestor', 'HEAD', $j->{start});
  if ($older) {
    $cannot->('git merge-base') unless $older == 256;
    for my $m (@moved) {
      my ($f, $id) = @$m;
      next unless defined $id;
      my $r = blob_holds($f, $id);
      die "HEAD ($head) holds the mutant of " . Esc::line($f->{path}) . " ($f->{place}): undo that change in a new"
        . " commit, then run mutate-changed.sh --recover\n" if $r;
      die "cannot tell whether HEAD ($head) holds the mutant of " . Esc::line($f->{path}) . ', as the original has its'
        . " line elsewhere too ($f->{place}): commit the file as it was when the run started (git restore"
        . " --source=$j->{start} --staged --worktree -- and its name, then git commit), then run mutate-changed.sh"
        . " --recover\n" unless defined $r;
    }
  }
  die "HEAD is not the commit the run started on ($j->{start}), one made after it, or one with the files as they were"
    . " then: check that commit out (git checkout $j->{start}), run mutate-changed.sh --recover, then switch back; if"
    . ' you committed on the branch the run was on since, make sure those commits do not hold the mutant\'s change ('
    . join(', ', map { Esc::line($_->{path}) . ": $_->{place}" } @{ $j->{files} }) . ")\n";
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

# run_mutants PLAN CHECKS MINUTES: run A (each check once, timed), run B
# (the same again: results that do not repeat cannot be trusted), the
# control run (a line end added at the end of every file that will get a
# mutant: a check that does not pass it, like one SKIPPED in run A, cannot
# show it noticed a mutant, so it is not used, and is named), one round per
# mutant while --minutes allows, then run C (the checks still pass without
# one); ends with the last line: PASS (exit 0) only when every mutant ran
# and was killed and nothing the branch changed was left out (left_out)
sub run_mutants {
  my ($pl, $checks, $minutes) = @_;
  my $start = $pl->{fp};
  my $stash = stash_id();
  my $deadline = Checks::now() + $minutes * 60;
  my $env = Checks::check_env();
  my @mutants = @{ $pl->{mutants} };
  my $n = @mutants;
  my (%limit, %took, @a, @use, @unused);
  # run A: each check once, timed; one that fails stops the run, and one
  # SKIPPED (no count, or a count of 0) cannot show it noticed a mutant
  for my $c (@$checks) {
    my ($res, $took) = run_check($c, $env, $deadline - Checks::now(), undef);
    die "run A: $c->{id} did not end within --minutes without any mutant\n" if $res->{kind} eq 'time';
    if ($res->{status} eq 'SKIPPED') {
      push @unused, "$c->{id} (SKIPPED without any mutant: $res->{detail})";
      next;
    }
    die "run A: $c->{id} did not pass without any mutant ($res->{status}: $res->{detail}); fix it or leave it out of"
      . " MUTATION_CHECKS\n" unless $res->{status} eq 'PASS';
    $limit{ $c->{id} } = 3 * int($took + 0.999) + 30;
    $took{ $c->{id} } = $took;
    push @a, sprintf('%s passed in %d s', $c->{id}, $took + 0.5);
    push @use, $c;
  }
  my $why = changes($start, undef);
  die 'run A: ' . join('; ', @$why) . " without any mutant\n" if @$why;
  my $none = sub {
    my ($kind, $why) = @_;
    say_line('not used: ' . join('; ', @unused)) if @unused;
    skipped($kind, counts($pl) . "; $n mutants: 0 killed (0 by time limit), 0 survived, $n not run ($why)");
  };
  $none->('no-usable-check', 'no check can show it noticed one') unless @use;
  my $per = 0;
  $per += $took{ $_->{id} } for @use;
  $per = int($per + 0.999) || 1;
  say_line('run A (no mutant): ' . join(', ', @a) . '; limit per mutant: '
    . join(', ', map {"$_->{id} $limit{$_->{id}} s"} @use));
  say_line("estimate: about $n mutants x $per s, about " . int(($n + 3) * $per / 60 + 0.999)
    . ' min with runs B and C and the control run');
  # (a round's worst case: each check's limit, and the time around it)
  my $round = sub { my $s = 5; $s += $limit{ $_->{id} } + 3 for @use; return $s };
  $none->('time-reached', "runs B and C and the control run do not fit --minutes $minutes")
    if Checks::now() + 3 * $round->() > $deadline;
  # run B: the same again; results that are not repeatable cannot be trusted
  for my $c (@use) {
    my ($res) = run_check($c, $env, $limit{ $c->{id} }, undef);
    die "run B: $c->{id} did not pass a second time without any mutant ("
      . ($res->{kind} eq 'time' ? 'it ran out of time' : "$res->{status}: $res->{detail}") . '); something a run leaves'
      . " behind changes the next one (a server, a file git ignores, database rows), so mutation results cannot be"
      . " trusted\n" unless $res->{status} eq 'PASS';
  }
  $why = changes($start, undef);
  die 'run B: ' . join('; ', @$why) . " without any mutant\n" if @$why;
  # the control run: a line end added at the end of every file that will
  # get a mutant, through the same write function and journal as a mutant;
  # a check that does not pass it cannot show it noticed a mutant
  die "stopped by SIG$SIGNAL\n" if defined $SIGNAL;
  my %seen;
  my (@ctl, @cf);
  for my $m (grep { !$seen{ $_->{path} }++ } @mutants) {
    my $text = Git::cat('blob', $m->{blob}, 1);
    my $c = $text . ($text =~ /\r\n\z/ ? "\r\n" : "\n");
    push @cf, { path => $m->{path}, sb => $m->{blob}, mb => Git::object_id('blob', $c, $m->{blob}),
      ss => Digest::SHA::sha256_hex($text), ms => Digest::SHA::sha256_hex($c), text => $text,
      place => 'the control run: a line end added at the end of the file', ml => '0' x 64, mw => '0' x 64 };
    push @ctl, $c;
  }
  my $cj = { start => $start->{head}, stash => $stash, temp => $TEMP, pgid => undef, files => \@cf };
  journal_write($cj);
  $OPEN = $cj;
  for my $i (0 .. $#cf) {
    die Esc::line($cf[$i]{path}) . " was changed during the run: the control run did not write to it, and the change"
      . " is kept\n" unless put($cf[$i]{path}, $ctl[$i], 1, $cf[$i]{ss});
    die "stopped by SIG$SIGNAL\n" if defined $SIGNAL;
  }
  my @kept;
  for my $c (@use) {
    my ($res) = run_check($c, $env, $limit{ $c->{id} }, $cj);
    if ($res->{status} eq 'PASS') {
      push @kept, $c;
      next;
    }
    push @unused, "$c->{id} (" . ($res->{kind} eq 'time' ? 'it ran out of time' : $res->{status} eq 'SKIPPED'
      ? 'it was SKIPPED' : 'it failed') . ' when only a line end was added at the end of the files that get a mutant,'
      . ' so it cannot show it noticed a mutant; split it if it also runs tests)';
  }
  end_round(0);
  $why = changes($start, $stash);
  die 'after the control run: ' . join('; ', @$why) . "\n" if @$why;
  @use = @kept;
  $none->('no-usable-check', 'no check can show it noticed one') unless @use;
  say_line('not used: ' . join('; ', @unused)) if @unused;
  my ($killed, $by_time, $survived, $done, %by) = (0, 0, 0, 0);
  for my $m (@mutants) {
    # (a signal between rounds: no next mutant is written)
    die "stopped by SIG$SIGNAL\n" if defined $SIGNAL;
    # (this round and run C must fit)
    last if Checks::now() + 2 * $round->() > $deadline;
    $done++;
    my $text = Git::cat('blob', $m->{blob}, 1);
    my $mut = mutated($text, $m);
    my $j = { start => $start->{head}, stash => $stash, temp => $TEMP, pgid => undef, files => [{ path => $m->{path},
      sb => $m->{blob}, mb => Git::object_id('blob', $mut, $m->{blob}), ss => Digest::SHA::sha256_hex($text),
      ms => Digest::SHA::sha256_hex($mut), text => $text, place => "line $m->{line}, column $m->{col}: " . shown($m),
      ml => Digest::SHA::sha256_hex((lines_of($mut))[$m->{line} - 1]),
      mw => Digest::SHA::sha256_hex(window([lines_of($mut)], $m->{line} - 1)) }] };
    journal_write($j);
    $OPEN = $j;
    if (!put($m->{path}, $mut, 1, $j->{files}[0]{ss})) {
      # (nothing was written, so the file never held this mutant)
      undef $OPEN if unlink($JOURNAL) || !(-e $JOURNAL || -l $JOURNAL);
      die Esc::line($m->{path}) . " was changed during the run: no mutant was written to it, and the change is kept\n";
    }
    # (a signal while put waited for the clock: no check runs on the mutant)
    die "stopped by SIG$SIGNAL\n" if defined $SIGNAL;
    my ($kill, @nothing);
    for my $c (@use) {
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
      $by{$kill}++;
    }
  }
  # (a signal during the last round's end: said, not lost)
  die "stopped by SIG$SIGNAL\n" if defined $SIGNAL;
  # run C: after the last mutant, the checks still pass without one
  if ($done) {
    for my $c (@use) {
      my ($res) = run_check($c, $env, $limit{ $c->{id} }, undef);
      die "run C: $c->{id} no longer passes without a mutant, after the last one ("
        . ($res->{kind} eq 'time' ? 'it ran out of time' : "$res->{status}: $res->{detail}") . '); something a round'
        . " left behind changes the next run (a file git ignores, a server), so mutation results cannot be trusted\n"
        unless $res->{status} eq 'PASS';
    }
    my $w = changes($start, $stash);
    die 'run C: ' . join('; ', @$w) . " without any mutant\n" if @$w;
  }
  die "stopped by SIG$SIGNAL\n" if defined $SIGNAL;
  my $kills = join(', ', map {"$_->{id} $by{$_->{id}}"} grep { $by{ $_->{id} } } @use);
  my $tail = counts($pl) . "; $n mutants: " . ($killed + $by_time) . ' killed (' . ($kills ? "$kills; " : '')
    . "$by_time by time limit), $survived survived, " . ($n - $done) . ' not run';
  if ($survived) {
    say_line("FAIL - $tail");
    exit 1;
  }
  skipped('time-reached', "$tail (--minutes $minutes)") if $done < $n;
  skipped('max-reached', "$tail (the plan has $pl->{possible})") if $pl->{possible} > $n;
  # every mutant ran and was killed: a pass only when nothing the branch
  # changed under MUTATE_PATHS was left out, but for the method's or git's
  # own files
  my @out = left_out($pl);
  skipped('not-all-mutated', "$tail; " . join('; ', @out)) if @out;
  say_line("PASS - $tail");
  exit 0;
}

main() unless caller;
1;
