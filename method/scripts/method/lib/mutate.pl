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
# what git shows.
sub excluded {
  my ($p, $method) = @_;
  return "the method's own files" if defined $method && ($p eq $method || index($p, "$method/") == 0);
  return "the method's own files" if $p =~ m{\A(?:\.claude|checks|\.method)/};
  return "git's own files" if $p =~ m{(?:\A|/)\.git(?:attributes|ignore|modules)\z};
  return undef;
}

# under PATH LIST: PATH is one of LIST's paths or lies under one ("." is all)
sub under {
  my ($p, $list) = @_;
  return grep { $_ eq '.' || $p eq $_ || index($p, "$_/") == 0 } @$list;
}

# method_folder TOP: the folder mutate-changed.sh runs from, relative to TOP,
# or undef when it is outside TOP (a method installed elsewhere)
sub method_folder {
  my ($top) = @_;
  my $m = Cwd::realpath(dirname($lib));
  my $t = Cwd::realpath($top);
  return undef unless defined $m && defined $t;
  return '.' if $m eq $t;
  return undef unless index($m, "$t/") == 0;
  return substr($m, length($t) + 1);
}

# --- mutants: the text operators ---

# shell FILE TEXT: a shell script, by its name or its first line
sub shell {
  my ($p, $text) = @_;
  return 1 if $p =~ /\.(?:sh|bash)\z/;
  return $text =~ m{\A#![^\n]*\b(?:sh|bash|dash|ksh|zsh)\b} ? 1 : 0;
}

# comment-like LINE: its first non-blank text opens a comment in a common
# language (#, //, --, /*, *, ;, %, <!--)
sub comment_like { return $_[0] =~ m{\A[ \t]*(?:#|//|--|/\*|\*|;|%|<!--)} ? 1 : 0 }

# a line a shell mutant must not touch: it deletes, moves or rewrites, so a
# swapped && or test would run it when it was meant not to
sub destructive { return $_[0] =~ /\b(?:rm|mv|dd|chmod)\b|\bgit\s+(?:clean|reset|push)\b/ ? 1 : 0 }

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

# The operators, each [regex, replacement]; a regex captures the token in $1
# at the position it changes. Kept in one table so the plan and the run use
# the same mutants.
my @OPS = (
  [qr/(===)/, sub {'!=='}], [qr/(!==)/, sub {'==='}],
  [qr/(?<![=!<>])(==)(?!=)/, sub {'!='}], [qr/(!=)(?!=)/, sub {'=='}],
  [qr/(?<![<=])(<=)(?![>=])/, sub {'<'}], [qr/(?<![>=])(>=)(?!=)/, sub {'>'}],
  [qr/(?<=\s)(-(?:lt|le|gt|ge|eq|ne))(?=\s)/, sub { { '-lt' => '-le', '-le' => '-lt', '-gt' => '-ge', '-ge' => '-gt',
    '-eq' => '-ne', '-ne' => '-eq' }->{ $_[0] } }, 'test'],
  [qr/(?<!&)(&&)(?![&=])/, sub {'||'}, 'logic'], [qr/(?<!\|)(\|\|)(?![|=])/, sub {'&&'}, 'logic'],
  [qr/\b(and)\b/, sub {'or'}, 'logic'], [qr/\b(or)\b/, sub {'and'}, 'logic'],
  [qr/\b(true|false|True|False|TRUE|FALSE)\b/, sub { { true => 'false', false => 'true', True => 'False',
    False => 'True', TRUE => 'FALSE', FALSE => 'TRUE' }->{ $_[0] } }],
  [qr/(?<![\w.\$\\])(0|[1-9][0-9]*)(?![\w.])/, \&next_int],
);

# mutants_on LINE SHELL: [column, from, to] for every position, by column
sub mutants_on {
  my ($l, $shell) = @_;
  my $guard = $shell && destructive($l);
  my @m;
  for my $op (@OPS) {
    my ($re, $to, $kind) = @$op;
    next if $guard && $kind && ($kind eq 'logic' || $kind eq 'test');
    while ($l =~ /$re/g) {
      push @m, [$-[1] + 1, $1, $to->($1)];
    }
  }
  return sort { $a->[0] <=> $b->[0] } @m;
}

# --- the plan ---

# plan CONF TOP: the changed files and lines, their mutants in run order, and
# the counts for the last line
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
  my $base = $mb[0];
  my $method = method_folder($top);
  stop('mutate-changed.sh runs from the top folder, so every file would be its own; run the copy in scripts/method')
    if defined $method && $method eq '.';
  my %c = (lines => 0, with => 0, comment => 0, nothing => 0, files => 0);
  my %skip;
  my @files;
  Tree::check_trees($base, $fp->{head});
  for my $f (Tree::changed($base, $fp->{head})) {
    next if $f->{st} eq 'D';
    my $p = $f->{path};
    next unless under($p, $conf->{MUTATE_PATHS});
    if (excluded($p, $method)) { $skip{"left out (the method's or git's own files)"}++; next }
    if ($f->{m2} !~ /\A100(?:644|755)\z/) { $skip{'not a regular file'}++; next }
    if ($converted{$p}) { $skip{'converted by .gitattributes or in Git LFS'}++; next }
    my $text = Git::cat('blob', $f->{o2}, 1, $MAX_SIZE);
    if (!defined $text) { $skip{'larger than 1 MB'}++; next }
    my $copy = $text;
    if ($text =~ /\0/ || !utf8::decode($copy)) { $skip{'not UTF-8 text'}++; next }
    my @lines = split /\n/, $text, -1;
    pop @lines if @lines && $lines[-1] eq '';
    my $old_text = $f->{m1} =~ /\A100(?:644|755)\z/ && $f->{st} ne 'A';
    my @changed = $old_text ? Tree::added_lines($f->{o1}, $f->{o2}) : (1 .. scalar @lines);
    next unless @changed;
    $c{files}++;
    my $sh = shell($p, $text);
    my (@first, @rest);
    for my $n (@changed) {
      my $l = $lines[$n - 1];
      next unless defined $l;
      $c{lines}++;
      if (comment_like($l)) { $c{comment}++; next }
      my @m = mutants_on($l, $sh);
      if (!@m) { $c{nothing}++; next }
      $c{with}++;
      my @at = map { { path => $p, line => $n, col => $_->[0], from => $_->[1], to => $_->[2] } } @m;
      push @first, shift @at;
      push @rest, @at;
    }
    push @files, [\@first, \@rest];
  }
  # round-robin over the files in path order: first one mutant per changed
  # line, then the rest, so any cap reaches every changed file before a
  # second mutant from any line
  my @order;
  for my $pass (0, 1) {
    my @q = map { [@{ $_->[$pass] }] } @files;
    while (grep {@$_} @q) {
      for my $q (@q) { push @order, shift @$q if @$q }
    }
  }
  my $all = @order;
  splice @order, $max if @order > $max;
  return { mutants => \@order, possible => $all, counts => \%c, skipped => \%skip, ref => $ref, base => $base };
}

# counts PLAN: the counts for the last line
sub counts {
  my ($pl) = @_;
  my $c = $pl->{counts};
  my $s = $pl->{skipped};
  my $line = "$c->{lines} changed lines in $c->{files} files: $c->{with} with a mutant, $c->{comment} comment-like,"
    . " $c->{nothing} with nothing to mutate";
  my @sk = map {"$s->{$_} $_"} sort keys %$s;
  $line .= '; files skipped: ' . join(', ', @sk) if @sk;
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
  my @ign = eval { Conf::ignored_inputs('.') };
  stop($@) if $@;
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
  my @unknown = grep { !$by_id{$_} } @{ $conf->{MUTATION_CHECKS} };
  stop('MUTATION_CHECKS names checks that checks/*.tsv does not have: ' . join(', ', @unknown)) if @unknown;
  my ($here) = Checks::place();
  my $env = Checks::check_env();
  my (@use, @not);
  for my $id (@{ $conf->{MUTATION_CHECKS} }) {
    my $r = Checks::applies($by_id{$id}, $here, $env);
    if ($r) { push @not, "$id ($r->{detail})" } else { push @use, $id }
  }
  skipped('not-here', 'none of MUTATION_CHECKS runs here: ' . join('; ', @not)) unless @use;
  my $pl = plan($conf, $top, $max);
  skipped('nothing-to-mutate', counts($pl)) unless @{ $pl->{mutants} };
  say_line("planned: $_->{path}:$_->{line}:$_->{col}: '$_->{from}' becomes '$_->{to}'") for @{ $pl->{mutants} };
  say_line('checks: ' . join(' ', @use) . (@not ? '; not run here: ' . join('; ', @not) : ''));
  my $n = @{ $pl->{mutants} };
  say_line("PLAN - $n mutants" . ($pl->{possible} > $n ? " of $pl->{possible} (--max $max)" : '') . '; '
    . counts($pl) . "; against $pl->{ref} (merge base " . substr($pl->{base}, 0, 7) . ')');
  exit 0;
}

main() unless caller;
1;
