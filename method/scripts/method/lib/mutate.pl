#!/usr/bin/env perl
# Breaks the code under test on purpose (M044): one changed line at a time
# gets a small text change (a mutant), the project's fast checks run, and
# the line is put back. Started by mutate-changed.sh, which documents the
# settings, the screen and the exit codes. Step 4b.2 builds the plan only
# (--list): it writes nothing and runs no check.
package Mutate;
use strict;
use warnings;
use Cwd ();
use File::Basename qw(dirname);
use File::Spec;

my $lib = dirname(File::Spec->rel2abs(__FILE__));
# checks.pl first: it takes the caller's environment before git.pl cleans it
require File::Spec->catfile($lib, $_) for qw(checks.pl git.pl esc.pl conf.pl tree.pl);

my $MAX_SIZE = 1024 * 1024;    # a changed file larger than this is not mutated
my $DEFAULT_MAX = 100;

sub say_line { print Esc::line("mutate-changed: $_[0]"), "\n" }

# stop REASON: an error (exit 2), with a last line that says so
sub stop {
  my ($reason) = @_;
  $reason =~ s/\n\z//;
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
  print "mutate-changed: usage: mutate-changed.sh --list [--max N]\n";
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
      my @at = map { { path => $p, line => $n, col => $_->[0], from => $_->[1], to => $_->[2], kind => $_->[3] } } @m;
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
    base => $base, none => \@none };
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
  my ($list, $max) = (0, $DEFAULT_MAX);
  my @args = @ARGV;
  while (@args) {
    my $a = shift @args;
    if ($a eq '--list') { $list = 1 }
    elsif ($a eq '--max' && @args && $args[0] =~ /\A[1-9][0-9]{0,5}\z/) { $max = shift @args }
    else { usage() }
  }
  stop('running mutants comes in step 4b.3; for now mutate-changed.sh plans them with --list') unless $list;
  # an error past this point (git failing, a damaged object) still ends with
  # a FAIL line and exit 2
  my $ok = eval { work($max); 1 };
  stop($@) unless $ok;
}

sub work {
  my ($max) = @_;
  my ($top, $elsewhere) = Git::top();
  stop('not inside a git working tree (or git refuses this one: owned by another user, or a damaged .git)')
    unless defined $top;
  stop("git's working folder is not this folder: a core.worktree setting points git elsewhere (or a .git here is"
    . ' damaged); run it in the working folder itself') if $elsewhere;
  chdir $top or stop('cannot enter the top folder of the repository');
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
  my $pl = plan($conf, $top, $max);
  skipped('nothing-to-mutate', counts($pl)) unless @{ $pl->{mutants} };
  say_line("planned: $_->{path}:$_->{line}:$_->{col}: " . shown($_)) for @{ $pl->{mutants} };
  say_line('checks: ' . join(' ', @use) . (@not ? '; not run here: ' . join('; ', @not) : ''));
  my $n = @{ $pl->{mutants} };
  say_line("PLAN - $n mutants" . ($pl->{possible} > $n ? " of $pl->{possible} (--max $max)" : '') . '; '
    . counts($pl) . "; against $pl->{ref} (merge base " . substr($pl->{base}, 0, 7) . ')');
  exit 0;
}

main() unless caller;
1;
