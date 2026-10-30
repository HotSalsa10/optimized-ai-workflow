#!/usr/bin/env perl
# Answers "is this change ready to merge?" from the commit, the files on
# disk, main, the run-checks log and the head commit's verdict line (M008,
# M089, M108). Started by done-check.sh, which documents the conditions, the
# output and the exit codes. Read-only: it writes no file, and git runs
# through lib/git.pl.
package Done;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;

my $lib = dirname(File::Spec->rel2abs(__FILE__));
# a library that cannot load is "could not check" too (done-check.sh also
# turns any other exit into that)
if (!eval { require File::Spec->catfile($lib, $_) for qw(git.pl esc.pl conf.pl tree.pl verdicts.pl checks.pl); 1 }) {
  (my $e = $@) =~ s/[^\x20-\x7e]+/ /g;
  print "done-check: NOT READY - could not check: a library of the method did not load: $e\n";
  exit 2;
}

my $CONF = '.claude/method.conf';
my $MAX_NAMES = 3;

sub short { return substr($_[0], 0, 7) }

sub say_line { print Esc::line("done-check: $_[0]"), "\n" }

# stop REASON: the check could not be made (exit 2); the last line still
# says NOT READY, so a reader of the last line alone never takes it as ready
sub stop {
  my ($reason) = @_;
  $reason =~ s/\n\z//;
  say_line("NOT READY - could not check: $reason");
  exit 2;
}

# names LIST: up to $MAX_NAMES of them, then how many more
sub names {
  my @n = @_;
  return join(', ', @n) if @n <= $MAX_NAMES;
  return join(', ', @n[0 .. $MAX_NAMES - 1]) . ' and ' . (@n - $MAX_NAMES) . ' more';
}

# ancestor A B: 1 when A is an ancestor of B (or B itself), 0 when not
sub ancestor {
  my ($a, $b) = @_;
  my ($st) = Git::run('merge-base', '--is-ancestor', $a, $b);
  return 1 if $st == 0;
  return 0 if $st == 1 << 8;
  stop('git merge-base failed');
}

# commit_info ID: (tree, parents) from the commit, checked against its id;
# () when it is not in this repository
sub commit_info {
  my $c = eval { Git::cat('commit', $_[0]) };
  return () unless defined $c;
  my ($head) = split /\n\n/, $c, 2;
  my ($tree) = $head =~ /\Atree ([0-9a-f]+)\n/ or return ();
  return ($tree, [$head =~ /^parent ([0-9a-f]+)$/mg]);
}

# conf_value COMMIT: VERDICTS_FROM in COMMIT's .claude/method.conf, or undef,
# read as status reads it: a file that is not a regular one sets nothing, and
# a line with a problem leaves its key unset (status and run-checks report
# those problems; refusing here would also block the change that fixes them)
sub conf_value {
  my ($commit) = @_;
  my $e = Tree::lookup($commit, $CONF);
  return undef unless $e && $e->[0] =~ /\A100(?:644|755)\z/;
  my ($v) = Conf::read_text(Tree::blob($e->[1]), "$CONF in " . short($commit));
  return $v->{VERDICTS_FROM};
}

my (@failed, @ready_notes, $ready_log);

# report AREA OK DETAIL NEXT: one condition's line; NEXT is what to do when
# it failed
sub report {
  my ($area, $ok, $detail, $next) = @_;
  say_line("$area: " . ($ok ? 'PASS' : 'FAIL') . " - $detail");
  push @failed, [$area, $next] unless $ok;
  return $ok;
}

# --- 1. files: the files on disk are the commit (one definition of clean:
# run-checks' fingerprint) ---
my %KIND_WORDS = (
  changed => 'changed or staged (git status lists them)',
  untracked => 'untracked, and not ignored by git',
  cr => "with CRs before line ends that the commit's .gitattributes does not ask for (core.autocrlf, core.eol or"
    . ' .git/info/attributes on this machine can write them)',
  content => 'with bytes that are not the commit\'s (edited; or changed by a filter, which done-check does not copy)',
  missing => 'missing from disk (a sparse checkout, or a deletion hidden by skip-worktree)',
  link => 'a link that is not the committed one, or a file or link in place of the other',
  type => 'not a regular file',
  unreadable => 'unreadable',
  flag => 'marked so git does not compare them (assume-unchanged or skip-worktree)',
  submodule => 'submodules whose changes git cannot see',
);
my @KIND_ORDER = qw(changed untracked cr content missing link type unreadable flag submodule);

sub files_condition {
  my ($head) = @_;
  my $fp = Checks::fingerprint();
  my %by;
  for my $path (sort keys %{ $fp->{kinds} }) {
    push @{ $by{$_} }, $path for keys %{ $fp->{kinds}{$path} };
  }
  my $n = keys %{ $fp->{kinds} };
  if (!$n) {
    my $conv = @{ $fp->{converted} };
    return report('files', 1, 'the tracked files on disk are commit ' . short($head) . ', byte for byte'
      . ($conv ? ", $conv of them as the commit's .gitattributes asks (line ends or \$Id\$)" : '')
      . "; nothing untracked outside git's ignore rules");
  }
  my @parts = map { scalar(@{ $by{$_} }) . " $KIND_WORDS{$_}: " . names(@{ $by{$_} }) } grep { $by{$_} } @KIND_ORDER;
  my $why = $fp->{no_conversion} && ($by{cr} || $by{content}) ? "; $fp->{no_conversion}" : '';
  return report('files', 0, "$n paths are not commit " . short($head) . ': ' . join('; ', @parts) . $why,
    'commit, restore or remove them' . ($by{cr} ? '; a CR the commit does not ask for: remove it, or put the line-end rule'
    . ' in .gitattributes in a reviewed change' : ''));
}

# --- 2. up to date (M108) ---
sub up_to_date_condition {
  my ($head, $ref, $tip) = @_;
  return report('up to date', 0, 'no main branch here (' . Git::no_main() . ')', 'fetch main, then run done-check again')
    unless defined $ref;
  return report('up to date', 1, "main is $ref " . short($tip) . ' as of the last fetch; done-check does not fetch')
    if ancestor($tip, $head);
  my ($sh) = Git::ok('rev-parse', '--is-shallow-repository') =~ /\A(\w+)/;
  return report('up to date', 0, "the history here is shallow, so whether $ref is merged cannot be told",
    'fetch the whole history (git fetch --unshallow origin), then run done-check again')
    if defined $sh && $sh eq 'true';
  my ($mst) = Git::merge_base($tip, $head);
  stop('git merge-base failed') if $mst eq 'error';
  return report('up to date', 0, "$ref and this branch share no history here",
    'this branch does not grow from main; start it from main') if $mst eq 'none';
  my $behind = Git::ok('rev-list', '--count', "$head..$tip");
  chomp $behind;
  return report('up to date', 0, "$ref has $behind commits this branch does not (as of the last fetch)",
    "merge $ref into this branch, run the checks, have the merged version reviewed, and end the merge commit"
    . ' with its own verdict line');
}

# --- 3. checks (M089): the newest run-checks log of these files, from here ---
sub checks_condition {
  my ($head, $where) = @_;
  my ($head_tree, $head_parents) = commit_info($head);
  stop('HEAD cannot be read') unless defined $head_tree;
  my (@match, @gone, $unreadable_after);
  for my $path (Checks::log_files()) {
    my $log = Checks::read_log($path);
    if ($log->{problem}) { $unreadable_after = $path; next }
    next unless $log->{where} eq $where && $log->{commit} ne 'none';
    my $same = $log->{commit} eq $head;
    if (!$same) {
      my ($tree, $parents) = commit_info($log->{commit});
      if (!defined $tree) { push @gone, $path; next }
      $same = $tree eq $head_tree
        && ("@$parents" eq "@$head_parents" || ancestor($log->{commit}, $head));
    }
    next unless $same;
    push @match, [$path, $log];
    undef $unreadable_after;
  }
  my $run = 'run the checks: bash scripts/method/run-checks.sh';
  if (!@match) {
    return report('checks', 0, 'no run-checks log of these files (commit ' . short($head) . ") from here ($where)"
      . (@gone ? '; ' . scalar(@gone) . ' logs name commits that are no longer in this repository' : ''), $run);
  }
  return report('checks', 0, 'a run-checks log newer than the last one of these files cannot be read (cut off before'
    . ' its header was written?)', $run) if defined $unreadable_after;
  my ($path, $log) = @{ $match[-1] };
  my $at = short($log->{commit}) . ($log->{commit} eq $head ? '' : ', the same files as HEAD');
  return report('checks', 0, "the last run of these files ($log->{started}) did not finish (stopped, or a check hung)", $run)
    unless defined $log->{end};
  my @fail = map { $_->{id} } grep { $_->{status} eq 'FAIL' } @{ $log->{results} };
  my @skip = map { $_->{id} } grep { $_->{status} eq 'SKIPPED' && $_->{kind} ne 'not-here' } @{ $log->{results} };
  return report('checks', 0, "the last run of these files ($log->{started}) started on uncommitted changes",
    "commit first, then $run") if $log->{tree} ne 'clean';
  return report('checks', 0, "the last run of these files ($log->{started}) failed: " . names(@fail), "fix them, then $run")
    if @fail;
  return report('checks', 0, "the last run of these files ($log->{started}) skipped checks that apply here, which is"
    . ' not a pass: ' . names(@skip), "make them run, then $run") if @skip;
  return report('checks', 0, "the last run of these files ($log->{started}) did not pass (exit $log->{end})", $run)
    unless $log->{end} == 0 && $log->{last} =~ /\Arun-checks: PASS - /;
  # earlier complete runs of the same files that started clean and failed
  my @runs = grep { defined $_->[1]{end} && $_->[1]{tree} eq 'clean' } @match;
  my %flaky;
  my $bad = 0;
  for my $r (@runs[0 .. $#runs - 1]) {
    my @f = map { $_->{id} } grep { $_->{status} eq 'FAIL' } @{ $r->[1]{results} };
    next unless @f;
    $bad++;
    $flaky{$_} = 1 for @f;
  }
  if ($bad) {
    my $note = "$bad of " . scalar(@runs) . ' runs of these files failed: ' . names(sort keys %flaky)
      . '; a check that fails sometimes is a finding for the review';
    push @ready_notes, $note;
    $ready_log = $log->{started};
    return report('checks', 1, "$where run-checks log of $log->{started} at $at; a local claim (RISKS #11); $note");
  }
  $ready_log = $log->{started};
  return report('checks', 1, "$where run-checks log of $log->{started} at $at; a local claim (RISKS #11)");
}

# --- 4. elsewhere (M089): a check that runs only in the other place has no
# result here, so it never counts toward READY ---
sub elsewhere_condition {
  my ($here) = @_;
  my ($checks, $problems) = Checks::read_tsv('.');
  return report('elsewhere', 0, 'checks/*.tsv has problems (run-checks names them)', 'fix checks/*.tsv') if @$problems;
  my @other = map { $_->{id} } grep { $_->{runs_in} ne 'any' && $_->{runs_in} ne $here } @$checks;
  return report('elsewhere', 1, @$checks ? 'every check in checks/*.tsv runs here (' . scalar(@$checks) . ')'
    : 'checks/*.tsv lists no check that runs only elsewhere') unless @other;
  return report('elsewhere', 0, scalar(@other) . ' checks run only in CI and done-check reads no CI result yet (step 9): '
    . names(@other), 'these checks have not been seen to pass; until done-check reads their result, it cannot say READY here')
    if $here eq 'local';
  return report('elsewhere', 0, scalar(@other) . ' checks run only locally, and no record of a local run is read yet: '
    . names(@other), 'these checks have not been seen to pass; until done-check reads their result, it cannot say READY here');
}

# --- 5. verdict (M008): the head commit ends with a verdict line whose value
# lets a change merge (verdicts.txt, kind ready) ---
sub verdict_condition {
  my ($head) = @_;
  my @rows = Verdicts::rows();
  my @ready = Verdicts::words('ready', @rows);
  my $msg = Git::message($head);
  my $problem = Verdicts::trailer_problem($msg);
  my (undef, $parents) = commit_info($head);
  my $review = 'have this version reviewed, and end its commit with the verdict line the review gives';
  if (defined $problem) {
    return report('verdict', 0, 'the head commit merges ' . short($parents->[1]) . ' and has no valid verdict line,'
      . " so the merged version needs its own: $problem", $review) if @$parents > 1;
    return report('verdict', 0, "the head commit's verdict line: $problem", $review);
  }
  my $word = Verdicts::trailer_word($msg);
  return report('verdict', 1, "$word, as typed in commit " . short($head) . '; not yet backed by a review receipt (step 5)')
    if grep { $_ eq $word } @ready;
  my ($meaning) = map { $_->[2] } grep { $_->[1] eq $word && $_->[0] =~ /\Atrailer/ } @rows;
  return report('verdict', 0, "the verdict line says $word (" . (defined $meaning ? $meaning : 'no meaning listed')
    . '): no review approved this version (SPEC R4)' . (@ready ? '' : '; verdicts.txt names no value that lets a change merge'),
    'fix and review again; after review round 3, re-plan or the owner decides (DECISIONS A7, A10); a person\'s'
    . ' approval does not replace the review\'s, so done-check stays NOT READY');
}

# --- 6. verdicts start: what this change makes status stop judging ---
sub verdicts_start_condition {
  my ($head, $ref, $tip, $up_to_date) = @_;
  my $area = 'verdicts start';
  return report($area, 0, 'no main branch to compare with', 'fetch main, then run done-check again') unless defined $ref;
  my $new = conf_value($head);
  my $old = conf_value($tip);
  my $show = sub { defined $_[0] ? short($_[0]) : 'unset' };
  return report($area, 1, 'VERDICTS_FROM is ' . $show->($new) . ' both on main and in this change')
    if (defined $new ? $new : '') eq (defined $old ? $old : '');
  return report($area, 0, 'this change moves VERDICTS_FROM; judged once the branch is up to date with main',
    'bring the branch up to date with main first') unless $up_to_date;
  my $moves = 'this change moves VERDICTS_FROM from ' . $show->($old) . ' to ' . $show->($new);
  my $jn = Verdicts::judged($tip, $new);
  if ($jn->{problem}) {
    return report($area, 0, "$moves, which is not in this shallow history of $ref; could not check",
      'fetch more history (git fetch --unshallow origin)') if $jn->{shallow};
    return report($area, 0, "$moves, which is not on ${ref}'s first-parent history, so status would report LOOK after"
      . ' the merge', 'set VERDICTS_FROM to a commit on main');
  }
  my $jo = Verdicts::judged($tip, $old);
  return report($area, 0, "$moves; could not check what it accepts: " . ($jo->{problem} && !$jo->{shallow}
    ? "the old value is not on ${ref}'s first-parent history" : 'the history here is shallow, so older commits were not read'),
    'fetch more history (git fetch --unshallow origin)') if $jo->{problem} || $jo->{shallow} || $jn->{shallow};
  my %still = map { ($_ => 1) } @{ $jn->{ids} };
  my @accepted = grep { !$still{$_} && defined Verdicts::trailer_problem(Git::message($_)) } @{ $jo->{ids} };
  return report($area, 1, "$moves; it accepts no commit without a valid verdict line") unless @accepted;
  # DECISIONS A30: older commits are accepted by moving VERDICTS_FROM in a
  # reviewed change; the verdict condition asks for that review, and the
  # READY line names what is accepted
  my $note = 'accepts ' . scalar(@accepted) . " commits on main without a valid verdict line: "
    . join(', ', map { short($_) } @accepted[0 .. ($#accepted < 4 ? $#accepted : 4)]) . (@accepted > 5 ? ' ...' : '');
  push @ready_notes, $note;
  return report($area, 1, "$moves; it $note");
}

sub main {
  binmode STDOUT, ':raw';
  binmode STDERR, ':raw';
  $| = 1;
  if (@ARGV != 1 || $ARGV[0] ne '--ready') {
    print "done-check: usage: done-check.sh --ready\n";
    exit 2;
  }
  eval { require Digest::SHA; 1 } or stop('perl has no Digest::SHA (status.sh reports what perl lacks)');
  my ($top, $elsewhere) = eval { Git::top() };
  stop('not inside a git working tree (or git refuses this one: owned by another user, or a damaged .git)')
    unless defined $top;
  stop("git's working folder is not this folder: a core.worktree setting points git elsewhere (or a .git here is"
    . ' damaged); run done-check in the working folder itself') if $elsewhere;
  chdir $top or stop('cannot enter the top folder of the repository');
  my $ok = eval { run(); 1 };
  stop($@) unless $ok;
}

sub run {
  my ($hst, $head) = Git::run('rev-parse', '-q', '--verify', 'HEAD^{commit}');
  stop('HEAD is not a commit yet') if $hst || $head !~ s/\n\z//;
  my ($ref, $tip) = Git::main_ref();
  if (defined $ref && ancestor($head, $tip)) {
    say_line("NOTHING TO MERGE - $head is ${ref}'s tip or behind it ($tip)");
    exit 3;
  }
  my ($here, $where) = Checks::place();

  files_condition($head);
  my $up = up_to_date_condition($head, $ref, $tip);
  checks_condition($head, $where);
  elsewhere_condition($here);
  verdict_condition($head);
  verdicts_start_condition($head, $ref, $tip, $up);

  my $against = defined $ref ? "$ref $tip" : 'no main branch';
  if (@failed) {
    say_line("next: $failed[0][1]");
    say_line('NOT READY - ' . scalar(@failed) . ' conditions failed (' . join(', ', map { $_->[0] } @failed)
      . "); $head against $against");
    exit 1;
  }
  my ($word) = Verdicts::trailer_word(Git::message($head));
  say_line("READY - $head is up to date with $against; verdict $word as typed in the commit (not yet backed by a"
    . " review receipt, step 5); checks from the $where run-checks log of $ready_log, a local claim (RISKS #11)"
    . join('', map {"; $_"} @ready_notes));
  exit 0;
}

main() unless caller;
1;
