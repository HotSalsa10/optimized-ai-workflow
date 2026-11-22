#!/usr/bin/env perl
# Answers "is this change ready to merge?" from the commit, the files on
# disk, main, the run-checks log, the task's plan, the gates' receipts and
# the head commit's verdict line (M008, M009, M089, M108, M144 to M147).
# Started by done-check.sh, which documents the conditions, the output and
# the exit codes. Read-only: it writes no file, and git runs through
# lib/git.pl. The receipts are read through lib/receipt-read.pl, which loads
# no hook library, so NOTHING TO MERGE keeps its exit 3.
package Done;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;

my $lib = dirname(File::Spec->rel2abs(__FILE__));
# a library that cannot load is "could not check" too (done-check.sh also
# turns any other exit into that)
if (!eval { require File::Spec->catfile($lib, $_) for qw(git.pl esc.pl conf.pl tree.pl verdicts.pl checks.pl receipt-read.pl); 1 }) {
  (my $e = $@) =~ s/[^\x20-\x7e]+/ /g;
  print "done-check: NOT READY - could not check: a library of the method did not load: $e\n";
  exit 2;
}

my $CONF = '.claude/method.conf';
my $MAX_NAMES = 3;
my $MAX_ROUNDS = 3;    # review rounds since the plan's approval (M009)

sub short { return substr($_[0], 0, 7) }

sub say_line { print Esc::line("done-check: $_[0]"), "\n" }

# stop REASON: the check could not be made (exit 2); the last line still
# says NOT READY, so a reader of the last line alone never takes it as ready
my $judged;    # HEAD and main, once known, for the could-not-check line
sub stop {
  my ($reason) = @_;
  $reason =~ s/\n\z//;
  say_line("NOT READY - could not check: $reason" . (defined $judged ? "; $judged" : ''));
  exit 2;
}

# names LIST: up to $MAX_NAMES of them, then how many more
sub names {
  my @n = @_;
  return join(', ', @n) if @n <= $MAX_NAMES;
  return join(', ', @n[0 .. $MAX_NAMES - 1]) . ' and ' . (@n - $MAX_NAMES) . ' more';
}

# count N ONE MANY: "N ONE" when N is 1, else "N MANY"
sub count {
  my ($n, $one, $many) = @_;
  return "$n " . ($n == 1 ? $one : $many);
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

# conf_unreadable COMMIT: why the .claude/method.conf COMMIT stores may not be
# what status reads from disk once COMMIT is checked out (.claude is a
# submodule; the file is a Git LFS pointer; the commit's own .gitattributes
# gives it a filter or an encoding), or undef. Where git cannot read the
# commit's own attributes (git older than 2.42, or rules in
# .git/info/attributes), any .gitattributes on the path that names a filter,
# an encoding or a macro counts.
sub conf_unreadable {
  my ($commit) = @_;
  my $d = Tree::lookup($commit, '.claude');
  return '.claude is a submodule' if $d && $d->[0] eq '160000';
  my $e = Tree::lookup($commit, $CONF);
  return undef unless $e && $e->[0] =~ /\A100(?:644|755)\z/;
  return 'the file is stored as a Git LFS pointer' if Tree::blob($e->[1]) =~ m{\Aversion https://git-lfs\.github\.com/spec/};
  my $a = Tree::attributes($commit, $CONF, 'filter', 'working-tree-encoding');
  if (!$a) {
    my $cp = Tree::conversion_problem();
    for my $g ('.gitattributes', '.claude/.gitattributes') {
      my $ge = Tree::lookup($commit, $g);
      next unless $ge && $ge->[0] =~ /\A100(?:644|755)\z/ && Tree::blob($ge->[1]) =~ /filter|working-tree-encoding|\[attr\]/;
      return "$g names a filter, an encoding or a macro, which cannot be read for the file here ("
        . ($cp ne '' ? $cp : 'git check-attr failed') . ')';
    }
    return undef;
  }
  for my $k ('filter', 'working-tree-encoding') {
    my $v = $a->{$k};
    return "the commit's .gitattributes gives the file a $k" if defined $v && $v ne 'unspecified' && $v ne 'unset';
  }
  return undef;
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
  lf => "with LF line ends where the commit's .gitattributes asks for CRLF",
  content => 'with bytes that are not the commit\'s (edited; or changed by a filter, which done-check does not copy)',
  missing => 'missing from disk (a sparse checkout, or a deletion hidden by skip-worktree)',
  link => 'a link that is not the committed one, or a file or link in place of the other',
  type => 'not a regular file',
  unreadable => 'unreadable',
  flag => 'marked so git does not compare them (assume-unchanged or skip-worktree)',
  submodule => 'submodules that cannot be compared with the commit (no .git of their own, a .git that points'
    . ' elsewhere, or the commit recorded for them is not in them)',
);
my @KIND_ORDER = qw(changed untracked cr lf content missing link type unreadable flag submodule);

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
    my $lfs = @{ $fp->{lfs} };
    return report('files', 1, 'the tracked files on disk are commit ' . short($head) . ', byte for byte'
      . ($conv ? ", $conv of them as the commit's .gitattributes asks (line ends, \$Id\$ or an encoding)" : '')
      . ($lfs ? ", $lfs of them Git LFS content the commit's .gitattributes asks for" : '')
      . "; nothing untracked that git lists outside its ignore rules");
  }
  my @parts = map { scalar(@{ $by{$_} }) . " $KIND_WORDS{$_}: " . names(@{ $by{$_} }) } grep { $by{$_} } @KIND_ORDER;
  my $why = $fp->{no_conversion} && ($by{cr} || $by{content}) ? "; $fp->{no_conversion}" : '';
  return report('files', 0, count($n, 'path is', 'paths are') . ' not commit ' . short($head) . ': ' . join('; ', @parts) . $why,
    'commit, restore or remove them' . ($by{cr} ? '; a CR the commit does not ask for: remove it, or put the line-end rule'
    . ' in .gitattributes in a reviewed change' : '')
    . ($by{lf} ? '; a missing CR the commit asks for: delete the file and check it out again (rm FILE && git checkout -- FILE)' : ''));
}

# unshallow: the command that fetches the whole history from main's remote
sub unshallow {
  my ($r) = Git::main_remote();
  return 'git fetch --unshallow' . (defined $r && $r ne '' ? ' ' . Git::hint_name($r) : '');
}

# --- 2. up to date (M108) ---
sub up_to_date_condition {
  my ($head, $ref, $tip) = @_;
  return report('up to date', 0, 'no main branch here (' . Git::no_main() . ')', Git::no_main_action() . ', then run done-check again')
    unless defined $ref;
  # a remote's ref counts only when git fetch moves it
  my ($r) = Git::main_remote();
  my ($branch) = defined $r && $r ne '' ? $ref =~ m{\Arefs/remotes/\Q$r\E/(.+)\z}s : ();
  if (defined $branch && !Git::fetched($r, $ref)) {
    my ($hr, $hb) = (Git::hint_name($r), Git::hint_name($branch, '<branch>'));
    return report('up to date', 0, "$ref is not moved by git fetch (the fetch settings of $r do not name it: a"
      . ' single-branch clone, or a ref fetched by hand), so it can be behind main',
      "keep main fetched (git remote set-branches --add $hr $hb && git fetch $hr), then run done-check again");
  }
  # a local main only when there is no remote (Git::main_refs)
  my $when = $ref =~ m{\Arefs/heads/} ? 'a local branch: this repository has no remote' : 'as of the last fetch';
  return report('up to date', 1, "main is $ref " . short($tip) . " ($when; done-check does not fetch)")
    if ancestor($tip, $head);
  my ($sh) = Git::ok('rev-parse', '--is-shallow-repository') =~ /\A(\w+)/;
  return report('up to date', 0, "the history here is shallow, so whether $ref is merged cannot be told",
    'fetch the whole history (' . unshallow() . '), then run done-check again')
    if defined $sh && $sh eq 'true';
  my ($mst) = Git::merge_base($tip, $head);
  stop('git merge-base failed') if $mst eq 'error';
  return report('up to date', 0, "$ref and this branch share no history here",
    'this branch does not grow from main; start it from main') if $mst eq 'none';
  my $behind = Git::ok('rev-list', '--count', "$head..$tip");
  chomp $behind;
  return report('up to date', 0, "$ref has " . count($behind, 'commit', 'commits') . " this branch does not ($when)",
    "merge $ref into this branch, run the checks, have the merged version reviewed, and end the merge commit"
    . ' with its own verdict line');
}

# --- 3. checks (M089): the newest run-checks log of these files, from here ---
sub checks_condition {
  my ($head, $where) = @_;
  my ($head_tree, $head_parents) = commit_info($head);
  stop('HEAD cannot be read') unless defined $head_tree;
  my (@match, @gone, @gone_after, $unreadable_after);
  for my $path (Checks::log_files()) {
    my $log = Checks::read_log($path);
    if ($log->{problem}) { $unreadable_after = $path; next }
    next unless $log->{where} eq $where && $log->{commit} ne 'none';
    my $same = $log->{commit} eq $head;
    if (!$same) {
      my ($tree, $parents) = commit_info($log->{commit});
      if (!defined $tree) { push @gone, $path; push @gone_after, $path; next }
      $same = $tree eq $head_tree
        && ("@$parents" eq "@$head_parents" || ancestor($log->{commit}, $head));
    }
    next unless $same;
    push @match, [$path, $log];
    undef $unreadable_after;
    @gone_after = ();
  }
  my $run = 'run the checks: bash scripts/method/run-checks.sh';
  if (!@match) {
    return report('checks', 0, 'no run-checks log of these files (commit ' . short($head) . ") from here ($where)"
      . (@gone ? '; logs that name a commit no longer in this repository: ' . scalar(@gone) : ''), $run);
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
  # a newer run whose commit is gone (an amended twin, pruned) may have
  # failed; its result cannot be tied to these files, so it is named
  if (@gone_after) {
    push @ready_notes, 'newer runs that name a commit no longer in this repository: ' . scalar(@gone_after)
      . ' (whether they were runs of these files cannot be told)';
  }
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
  }
  $ready_log = $log->{started};
  return report('checks', 1, "$where run-checks log of $log->{started} at $at; a local claim (RISKS #11)"
    . join('', map {"; $_"} @ready_notes));
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
  return report('elsewhere', 0, count(scalar(@other), 'check runs', 'checks run') . ' only in CI and done-check reads no CI result yet (step 9): '
    . names(@other), 'these checks have not been seen to pass; until done-check reads their result, it cannot say READY here')
    if $here eq 'local';
  return report('elsewhere', 0, count(scalar(@other), 'check runs', 'checks run') . ' only locally, and no record of a local run is read yet: '
    . names(@other), 'these checks have not been seen to pass; until done-check reads their result, it cannot say READY here');
}

# --- 5. the task: its plan, the gates' receipts, the rounds (M144, M146,
# M009). %T holds what run() and these conditions find: the merge base,
# the branch's commits and their trees, the receipts, the task and its
# anchor, and which of these conditions passed ---
my %T;

# the branch: its commits that main does not hold, oldest first, each
# [COMMIT, TREE]
sub branch_commits {
  my ($head, $tip) = @_;
  my @c;
  my $cur;
  for my $l (split /\n/, Git::ok('rev-list', '--reverse', '--topo-order', '--format=%T', $head, '--not', $tip, '--')) {
    if ($l =~ /\Acommit ([0-9a-f]+)\z/) { $cur = $1; next }
    push @c, [$cur, $l] if defined $cur && $l =~ /\A[0-9a-f]+\z/;
    undef $cur;
  }
  return @c;
}

# plan_paths COMMIT: the task plans COMMIT holds, each [PATH, WHAT]: WHAT is
# '' for a regular file docs/tasks/<id>/plan.md, else what stands there
# instead (a symbolic link or a submodule as the task's folder, or as its
# plan.md; a folder as its plan.md), which a check of plans would not read
my %KIND = ('120000' => 'a symbolic link', '160000' => 'a submodule', '40000' => 'a folder');
sub plan_paths {
  my ($commit) = @_;
  my $d = Tree::lookup($commit, 'docs/tasks');
  return () unless $d && $d->[0] eq '40000';
  my $e = Tree::tree_entries($d->[1]);
  my @p;
  for my $n (sort keys %$e) {
    my $m = $e->{$n}[0];
    if ($m eq '120000' || $m eq '160000') { push @p, ["docs/tasks/$n", $KIND{$m}]; next }
    next unless $m eq '40000';
    my $f = Tree::tree_entries($e->{$n}[1])->{'plan.md'};
    next unless $f;
    push @p, ["docs/tasks/$n/plan.md", $f->[0] =~ /\A100(?:644|755)\z/ ? '' : $KIND{ $f->[0] } || "mode $f->[0]"];
  }
  return @p;
}

# plan_lines COMMIT PATH: the lines of the plan at PATH in COMMIT, each
# without its trailing blanks and CR; () when it is not a regular file there
sub plan_lines {
  my ($commit, $path) = @_;
  my $e = Tree::lookup($commit, $path);
  return () unless $e && $e->[0] =~ /\A100(?:644|755)\z/;
  my @l = split /\n/, Tree::blob($e->[1]);
  s/[ \t\r]+\z// for @l;
  return @l;
}

sub plan_condition {
  my ($head, $ref) = @_;
  my $area = 'plan';
  my ($ready) = Verdicts::words('ready', Verdicts::rows());
  my $plan = 'plan the task on this branch in docs/tasks/<id>/plan.md (the method-plan skill) and ask the owner for their go on it';
  return report($area, 0, 'no main branch to compare with, so the task this branch adds cannot be told',
    Git::no_main_action() . ', then run done-check again') unless defined $ref;
  return report($area, 0, "$ref and this branch share no history here, so the task this branch adds cannot be told",
    'this branch does not grow from main; start it from main') unless defined $T{mb};
  my @added = grep { !Tree::lookup($T{mb}, $_->[0]) } plan_paths($head);
  my @odd = grep { $_->[1] ne '' } @added;
  return report($area, 0, 'this branch adds a task folder or plan that is not a plain folder and file: '
    . names(map { "$_->[0] ($_->[1])" } @odd), 'make each task plan a regular file in its own folder, docs/tasks/<id>/plan.md;'
    . ' one task, with one plan, a merge') if @odd;
  my @plans = map { $_->[0] } @added;
  return report($area, 0, 'this branch adds no task plan (docs/tasks/<id>/plan.md)', $plan) unless @plans;
  return report($area, 0, 'this branch adds ' . scalar(@plans) . ' task plans (' . names(@plans) . '); one task goes in one merge',
    'split the work: one task, with one plan, a merge') if @plans > 1;
  my $path = $plans[0];
  my ($id) = $path =~ m{\Adocs/tasks/([^/]+)/plan\.md\z};
  return report($area, 0, "the task's folder name is not an id (lower-case letters, digits and dashes): $path",
    'rename the folder, and ask the owner again') unless $id =~ /\A[a-z0-9][a-z0-9-]*\z/;
  my @lines = plan_lines($head, $path);
  my @tier = grep { /\ATier:/ } @lines;
  return report($area, 0, "$path has no Tier line (Tier: FULL or Tier: LIGHT)", "add the Tier line to $path, and ask the owner again")
    unless @tier;
  return report($area, 0, "$path has " . scalar(@tier) . ' Tier lines; it holds one', "keep one Tier line in $path, and ask the owner again")
    if @tier > 1;
  my ($tier) = $tier[0] =~ /\ATier: (FULL|LIGHT)\z/;
  return report($area, 0, "${path}'s Tier line is not Tier: FULL or Tier: LIGHT: $tier[0]", "correct the Tier line, and ask the owner again")
    unless defined $tier;
  my $ask = "ask the owner for their go on the plan (their reply holds \"$ready $id\"), then add the Approved line quoting it";
  my @app = grep { /\AApproved:/ } @lines;
  return report($area, 0, "$path has no Approved line: the owner has not approved the plan", $ask) unless @app;
  return report($area, 0, "$path has " . scalar(@app) . ' Approved lines; it holds one, the newest approval',
    'keep only the newest Approved line') if @app > 1;
  my ($date, $quote) = $app[0] =~ /\AApproved: ([0-9]{4}-[0-9]{2}-[0-9]{2}) "(.*)"\z/;
  return report($area, 0, "${path}'s Approved line is not Approved: <YYYY-MM-DD> \"<the owner's reply>\": $app[0]", $ask)
    unless defined $quote;
  return report($area, 0, "the Approved line's quote does not hold \"$ready $id\" for this task: \"$quote\"", $ask)
    unless $quote =~ /(?<![A-Za-z0-9-])(?i:\Q$ready\E)[ \t]+\Q$id\E(?![A-Za-z0-9-])/;
  # the anchor: the first commit on the branch whose plan carries this exact
  # line (a line removed and added again does not move it); and every
  # Approved line the branch has had
  my ($anchor, @had, %had);
  for my $i (0 .. $#{ $T{branch} }) {
    my $c = $T{branch}[$i][0];
    for my $l (grep { /\AApproved:/ } plan_lines($c, $path)) {
      push @had, $l unless $had{$l}++;
      $anchor = $i if !defined $anchor && $l eq $app[0];
    }
  }
  stop("the Approved line of $path is in no commit of this branch") unless defined $anchor;
  @T{qw(id path anchor tier approved)} = ($id, $path, $anchor, $tier, $app[0]);
  my $more = @had > 1 ? '; the plan was approved ' . scalar(@had) . ' times on this branch: ' . join('; ', map { substr($_, 10) } @had) : '';
  push @ready_notes, substr($more, 2) if $more ne '';
  return report($area, 1, "task $id ($path), Tier $tier; approved $date \"$quote\" in commit " . short($T{branch}[$anchor][0]) . $more);
}

# chains GATE BASE SEEN: 1 when BASE is the merge base, or a commit between
# the merge base and HEAD whose tree has a valid receipt of GATE that
# itself has a base that chains (a slice built with --since on a version
# that was reviewed from the merge base)
sub chains {
  my ($gate, $base, $seen) = @_;
  return 1 if $base eq $T{mb};
  return 0 if $seen->{$base}++;
  my ($tree) = commit_info($base);
  return 0 unless defined $tree && ancestor($T{mb}, $base) && ancestor($base, $T{head});
  my $good = Receipt::words()->{good};
  for my $r (grep { $_->{gate} eq $gate && $_->{tree} eq $tree && $_->{state} eq $good } @{ $T{receipts} }) {
    return 1 if grep { chains($gate, $_, $seen) } @{ $r->{bases} };
  }
  return 0;
}

# what each receipt in the list says, for a line
sub said {
  return join(', ', map { (defined $_->{open} ? $_->{open} : 'no word') . " ($_->{state}"
    . (ref $_->{why} eq 'ARRAY' && @{ $_->{why} } && !ref $_->{why}[0] ? ": $_->{why}[0]" : '') . ')' } @_);
}

# on_tree GATE: the receipts of GATE for HEAD's tree
sub on_tree {
  my ($gate) = @_;
  return grep { $_->{gate} eq $gate && $_->{tree} eq $T{tree} } @{ $T{receipts} };
}

# other_word YES RECEIPT...: the receipts that opened with a word other
# than YES, whatever their state (one with no word is not among them)
sub other_word {
  my ($yes, @r) = @_;
  return grep { defined $_->{open} && $_->{open} ne $yes } @r;
}

# gate_condition AREA ROLE: the reviewer or the security checker on HEAD's
# tree. Any receipt of it on these files that opened with another word
# blocks, whatever its state (a later approval of the same files does not
# clear it); one with no word neither blocks nor counts; a valid one that
# opened with the approving word counts when one of its bases chains back to
# the merge base
sub gate_condition {
  my ($area, $role) = @_;
  my %role = Verdicts::roles(Verdicts::rows());
  my ($gate, $yes) = ($role{$role}, $role{approving});
  my $good = Receipt::words()->{good};
  my $files = 'these files (tree ' . short($T{tree}) . ')';
  my $run = "run $gate on these files, in the foreground, with a review packet from the merge base (review-packet.sh --base"
    . ' <main>, or --since the last version it reviewed when that review was from the merge base)';
  return report($area, 0, "no merge base with main, so a review of the whole change cannot be told", $run) unless defined $T{mb};
  my @on = on_tree($gate);
  my @other = other_word($yes, @on);
  return report($area, 0, count(scalar(@other), "receipt of $gate for $files opens", "receipts of $gate for $files open")
    . ' with another word: ' . said(@other) . '; a later review of the same files does not clear it',
    "fix what $gate found, commit, and have the new version reviewed") if @other;
  if (!@on) {
    my $elsewhere = grep { $_->{gate} eq $gate } @{ $T{receipts} };
    return report($area, 0, "no receipt of $gate for $files" . ($elsewhere ? '; its receipts here are for other versions' : '')
      . ' (receipts are kept in this clone only, the newest 500)', $run);
  }
  my @yes = grep { $_->{state} eq $good && defined $_->{open} && $_->{open} eq $yes } @on;
  return report($area, 0, "no receipt of $gate for $files is $good with $yes: " . said(@on), $run) unless @yes;
  my @based = grep { @{ $_->{bases} } } @yes;
  return report($area, 0, "the receipt of $gate that approved $files records no review packet's base (the gate read no"
    . ' packet, or an older gate-receipt made the receipt), so whether it reviewed the whole change cannot be told', $run)
    unless @based;
  my ($ok) = grep { my $r = $_; grep { chains($gate, $_, {}) } @{ $r->{bases} } } @based;
  return report($area, 0, "the receipt of $gate that approved $files reviewed from " . short($based[0]{bases}[0])
    . ', which does not chain back to the merge base ' . short($T{mb}) . ' (a packet built with --since counts only on a version'
    . " that $gate reviewed from the merge base)", $run) unless $ok;
  my ($from) = grep { $_ eq $T{mb} } @{ $ok->{bases} };
  $T{ok}{$area} = 1;
  return report($area, 1, "$gate opened with $yes on $files, $good, reviewed from "
    . (defined $from ? 'the merge base ' . short($T{mb}) : short($ok->{bases}[0]) . ', which chains back to the merge base ' . short($T{mb})));
}

# tree_plan_has TREE PATH LINE: 1 when the file at PATH in the folder TREE
# holds LINE (compared as plan_lines reads it), 0 when not; dies when TREE
# or a part of it cannot be read
sub tree_plan_has {
  my ($tree, $path, $line) = @_;
  die "not a tree id\n" unless $tree =~ /\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/;
  my @parts = split m{/}, $path;
  my $e = ['40000', $tree];
  for my $p (@parts) {
    return 0 unless $e->[0] eq '40000';
    $e = Tree::tree_entries($e->[1])->{$p};
    return 0 unless $e;
  }
  return 0 unless $e->[0] =~ /\A100(?:644|755)\z/;
  my @l = split /\n/, Tree::blob($e->[1]);
  s/[ \t\r]+\z// for @l;
  return scalar grep { $_ eq $line } @l;
}

# rounds (M009): the versions reviewed since the plan's approval, each a
# tree with a valid receipt of the reviewer: the trees of the branch's
# commits from the anchor on, and every reviewed tree whose plan holds the
# same Approved line, so a branch whose history was rewritten (squashed or
# rebased) keeps its earlier rounds; without an approved plan, the whole
# branch's trees. A reviewed tree this clone cannot read is not counted,
# and the line says so
sub rounds_condition {
  my %role = Verdicts::roles(Verdicts::rows());
  my $good = Receipt::words()->{good};
  my $from = defined $T{anchor} ? $T{anchor} : 0;
  my %on;
  $on{ $_->[1] } = 1 for @{ $T{branch} }[$from .. $#{ $T{branch} }];
  my %reviewed = map { ($_->{tree} => 1) } grep { $_->{gate} eq $role{reviewer} && $_->{state} eq $good } @{ $T{receipts} };
  my @here = grep { $on{$_} } sort keys %reviewed;
  my (@off, $unread);
  if (defined $T{anchor}) {
    for my $t (grep { !$on{$_} } sort keys %reviewed) {
      my $has = eval { tree_plan_has($t, $T{path}, $T{approved}) };
      if (!defined $has) { $unread++; next }
      push @off, $t if $has;
    }
  }
  my $n = @here + @off;
  my $since = defined $T{anchor} ? "since the plan's approval" : 'on this branch (no approved plan to count from)';
  my $notes = @off ? ' (' . count(scalar(@off), 'of them is', 'of them are') . ' no longer on this branch: its history was rewritten)' : '';
  $notes .= '; not counted: ' . count($unread, 'version', 'versions') . " that $role{reviewer} reviewed and this clone cannot read"
    . ' (whether they hold this approval is not known)' if $unread;
  if ($n > $MAX_ROUNDS) {
    return report('rounds', 0, "$n versions were reviewed $since$notes; the limit is $MAX_ROUNDS rounds",
      "plan again: change the plan, and ask the owner for their go again (a new Approved line starts the count again)");
  }
  $T{ok}{rounds} = 1;
  return report('rounds', 1, count($n, 'version', 'versions') . " reviewed $since, of at most $MAX_ROUNDS$notes");
}

# --- the SPEC R6 set (step 6b.3): the tier and the high-risk paths (M147),
# the lock and the tester's runs (M145), the reporter and Deep review
# (M146). The conditions that apply to a change are named in @{$T{need}},
# each passed one in $T{ok}, for the verdict ---

# high_risk_list COMMIT WHERE: (the HIGH_RISK_PATHS COMMIT's
# .claude/method.conf lists, undef) or (undef, what is wrong): a file that
# cannot be read as it is stored, or a problem the parser tags
# HIGH_RISK_PATHS or cannot tie to a key, fails closed, so a typo never
# reads as a shorter list
sub high_risk_list {
  my ($commit, $where) = @_;
  my $label = "$CONF $where (" . short($commit) . ')';
  my $d = Tree::lookup($commit, '.claude');
  return ([], undef) unless $d;
  return (undef, "$label: .claude is " . ($d->[0] eq '160000' ? 'a submodule' : 'not a folder')) if $d->[0] ne '40000';
  my $e = Tree::lookup($commit, $CONF);
  return ([], undef) unless $e;
  return (undef, "$label: not a regular file in the commit") unless $e->[0] =~ /\A100(?:644|755)\z/;
  my $why = conf_unreadable($commit);
  return (undef, "$label: $why") if defined $why;
  my ($v, $problems, $tags) = Conf::read_text(Tree::blob($e->[1]), $label);
  my @bad = map { $problems->[$_] } grep { !defined $tags->[$_] || $tags->[$_] eq 'HIGH_RISK_PATHS' } 0 .. $#$problems;
  return (undef, names(@bad)) if @bad;
  return ($v->{HIGH_RISK_PATHS} || [], undef);
}

# touched: the paths this change touches from the merge base, sorted; a
# moved or copied file counts at its old path too
sub touched {
  my %p;
  for my $f (Tree::changed($T{mb}, $T{head})) {
    $p{ $f->{path} } = 1;
    $p{ $f->{old} } = 1 if $f->{st} eq 'R' || $f->{st} eq 'C';
  }
  return sort keys %p;
}

sub tier_condition {
  my ($ref, $tip) = @_;
  my $area = 'tier';
  push @{ $T{need} }, $area;
  return report($area, 0, "no main branch to read main's high-risk list from", Git::no_main_action() . ', then run done-check again')
    unless defined $ref;
  return report($area, 0, "$ref and this branch share no history here, so the paths this change touches cannot be told",
    'this branch does not grow from main; start it from main') unless defined $T{mb};
  my $fix = "fix $CONF and keep it a plain file committed in this repository (on main, that fix is a small task of its own), then"
    . ' run done-check again';
  my ($main, $mwhy) = high_risk_list($tip, 'on main');
  my ($mine, $hwhy) = high_risk_list($T{head}, 'in this change');
  my @why = grep { defined } $mwhy, $hwhy;
  return report($area, 0, 'the high-risk list cannot be read: ' . join('; ', @why) . '; a broken setting is not read as a shorter list', $fix)
    if @why;
  # main's list and the branch's together: a branch can add a path, never
  # remove one
  my %seen;
  my @list = grep { !$seen{$_}++ } @$main, @$mine;
  my @high = grep { Conf::under($_, \@list) } touched();
  $T{high} = \@high;
  my $lists = @list ? '(HIGH_RISK_PATHS, main\'s and this change\'s together: ' . names(@list) . ')'
    : '(no HIGH_RISK_PATHS on main or in this change)';
  my $which = @high ? count(scalar(@high), 'changed path is', 'changed paths are') . ' high-risk: ' . names(@high) . " $lists"
    : "no changed path is high-risk $lists";
  if (!$T{ok}{plan}) {
    $T{ok}{$area} = 1;
    return report($area, 1, "no approved plan to take the tier from (plan above); $which");
  }
  $T{full} = $T{tier} eq 'FULL' || @high ? 1 : 0;
  return report($area, 0, "the plan says Tier LIGHT, but $which; judged FULL, and the plan was not made as FULL",
    'plan again as FULL (Tier: FULL, with expected.tsv), and ask the owner for their go again') if $T{tier} eq 'LIGHT' && @high;
  $T{ok}{$area} = 1;
  return report($area, 1, "Tier $T{tier}, as the plan says" . (@high ? "; $which, so Deep review applies" : $T{tier} eq 'LIGHT' ? ": $which" : "; $which"));
}

# locked COMMIT: what the lock holds in COMMIT: the plan's Tier lines, its
# Paths lines, and expected.tsv (its mode and blob, or undef when absent)
sub locked {
  my ($commit) = @_;
  my @l = plan_lines($commit, $T{path});
  (my $dir = $T{path}) =~ s{/plan\.md\z}{};
  my $e = Tree::lookup($commit, "$dir/expected.tsv");
  return { 'the Tier line' => join("\n", grep { /\ATier:/ } @l), 'the Paths line' => join("\n", grep { /\APaths:/ } @l),
    'expected.tsv' => $e ? "$e->[0] $e->[1]" : undef };
}

# lock (M145): since the plan's approval, its Tier and Paths lines and its
# expected.tsv are unchanged: HEAD's are the anchor's; a FULL task had
# expected.tsv when it was approved
sub lock_condition {
  my $area = 'lock';
  return unless $T{ok}{plan};
  push @{ $T{need} }, $area;
  my $at = $T{branch}[ $T{anchor} ][0];
  my ($then, $now) = (locked($at), locked($T{head}));
  my @moved = grep { (defined $then->{$_} ? $then->{$_} : '') ne (defined $now->{$_} ? $now->{$_} : '') }
    'the Tier line', 'the Paths line', 'expected.tsv';
  return report($area, 0, "changed since the plan's approval in commit " . short($at) . ': ' . join(', ', @moved),
    'a change to the tier, the paths or the expected results is a new plan: ask the owner for their go again, and replace'
    . ' the Approved line with the new reply') if @moved;
  (my $dir = $T{path}) =~ s{/plan\.md\z}{};
  return report($area, 0, "the task is FULL, but its plan had no expected.tsv when it was approved in commit " . short($at)
    . ': a FULL plan locks its expected results', "write $dir/expected.tsv, and ask the owner for their go again")
    if $T{full} && !defined $then->{'expected.tsv'};
  $T{ok}{$area} = 1;
  return report($area, 1, "the plan's Tier and Paths lines and its expected.tsv are as approved in commit " . short($at)
    . (defined $then->{'expected.tsv'} ? '' : ' (no expected.tsv, as approved)'));
}

# failing run (M145): a valid tester receipt that opened with the fail word
# on a commit from the anchor on (git ancestry, as trees repeat across
# commits) and strictly before HEAD, with files other than HEAD's
sub failing_condition {
  my $area = 'failing run';
  return unless $T{ok}{plan} && $T{full};
  push @{ $T{need} }, $area;
  my %role = Verdicts::roles(Verdicts::rows());
  my $good = Receipt::words()->{good};
  my $at = $T{branch}[ $T{anchor} ][0];
  my (%not, $ok);
  for my $r (grep { $_->{gate} eq $role{tester} && $_->{state} eq $good && defined $_->{open} && $_->{open} eq $role{fail} }
    @{ $T{receipts} }) {
    my $h = $r->{head};
    if (!defined $h || $h !~ /\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/ || !defined((commit_info($h))[0])) { $not{gone}++; next }
    if ($r->{tree} eq $T{tree}) { $not{here}++; next }
    if (!ancestor($at, $h) || $h eq $T{head} || !ancestor($h, $T{head})) { $not{off}++; next }
    $ok = $r;
  }
  if ($ok) {
    $T{ok}{$area} = 1;
    return report($area, 1, "$role{tester} opened with $role{fail} on commit " . short($ok->{head}) . ", after the plan's approval in commit "
      . short($at) . ' and before these files');
  }
  my @notes;
  push @notes, "$not{here} on these files (a run on the finished files does not show the tests failing first)" if $not{here};
  push @notes, "$not{off} on a commit outside this branch's history from the approval to HEAD" if $not{off};
  push @notes, "$not{gone} on a commit this clone does not have" if $not{gone};
  return report($area, 0, "no $good receipt of $role{tester} that opened with $role{fail} on a commit from the plan's approval (commit "
    . short($at) . ") to before HEAD, with other files than HEAD's" . (@notes ? '; not counted: ' . join('; ', @notes) : ''),
    "run $role{tester} where the tests are in and the code is not: on this branch after the approval, a commit that takes the"
    . " product's files back to before the code (plan.md and expected.tsv unchanged), $role{tester} there, then a commit that puts"
    . ' the code back (the method-plan skill); a lost receipt of such a run: git switch -c <name> <that commit>, the tester there,'
    . ' then switch back');
}

# newest AREA ROLE WORD WHY: the newest receipt (by its stop time) of the
# gate in ROLE on HEAD's tree is valid and opened with WORD (the tester's
# passing run, the reporter: M146)
sub newest_condition {
  my ($area, $role, $want, $why) = @_;
  return unless $T{ok}{plan} && $T{full};
  push @{ $T{need} }, $area;
  my %role = Verdicts::roles(Verdicts::rows());
  my ($gate, $word) = ($role{$role}, $role{$want});
  my $good = Receipt::words()->{good};
  my $files = 'these files (tree ' . short($T{tree}) . ')';
  my @r = Receipt::by_stopped(on_tree($gate));
  my $run = "run $gate on these files, in the foreground, and fix what it finds";
  return report($area, 0, "no receipt of $gate for $files$why", $run) unless @r;
  my $n = $r[-1];
  my $said = (defined $n->{open} ? $n->{open} : 'no word') . " ($n->{state})";
  return report($area, 0, "the newest receipt of $gate for $files is $said, not $word ($good)", $run)
    unless $n->{state} eq $good && defined $n->{open} && $n->{open} eq $word;
  $T{ok}{$area} = 1;
  return report($area, 1, "the newest receipt of $gate for $files opened with $word, $good");
}

# deep review (M146, M087): a change that touches a high-risk path needs
# three valid receipts of the reviewer on HEAD's tree that opened with the
# approving word, each reviewed from the merge base or chained back to it,
# and no receipt of it there with another word
sub deep_condition {
  my $area = 'deep review';
  return unless $T{high} && @{ $T{high} };
  push @{ $T{need} }, $area;
  my %role = Verdicts::roles(Verdicts::rows());
  my ($gate, $yes) = ($role{reviewer}, $role{approving});
  my $good = Receipt::words()->{good};
  my $files = 'these files (tree ' . short($T{tree}) . ')';
  my @on = on_tree($gate);
  my @other = other_word($yes, @on);
  my @yes = grep { my $r = $_; $r->{state} eq $good && defined $r->{open} && $r->{open} eq $yes && defined $T{mb}
    && grep { chains($gate, $_, {}) } @{ $r->{bases} } } @on;
  my $paths = 'the change touches high-risk paths (' . names(@{ $T{high} }) . ')';
  if (@yes >= 3 && !@other) {
    $T{ok}{$area} = 1;
    return report($area, 1, scalar(@yes) . " receipts of $gate opened with $yes on $files, $good, reviewed from the merge base or"
      . " chained back to it; $paths");
  }
  return report($area, 0, "$paths, so it needs three receipts of $gate that opened with $yes on $files, $good and reviewed from"
    . ' the merge base or chained back to it: ' . scalar(@yes) . (@yes == 1 ? ' does' : ' do')
    . (@other ? ', and ' . scalar(@other) . ' opened with another word (' . said(@other) . ')' : ''),
    "run $gate three times on these files, launched in one message in the foreground (Deep review), each with a review packet"
    . ' from the merge base; every finding of any of them gets a disposition in the report');
}

# history: every gate's word on the branch's versions, in commit order (a
# version by the first commit that has its tree), each version's receipts
# by the time they stopped
sub history {
  my $w = Receipt::words();
  my (%seen, @parts);
  for my $c (@{ $T{branch} }) {
    next if $seen{ $c->[1] }++;
    my @r = Receipt::by_stopped(grep { $_->{tree} eq $c->[1] && exists $w->{gate}{ $_->{gate} } } @{ $T{receipts} });
    next unless @r;
    push @parts, short($c->[0]) . ': ' . join(', ', map { "$_->{gate} " . (defined $_->{open} ? $_->{open} : 'no word')
      . ($_->{state} eq $w->{good} ? '' : " ($_->{state})") } @r);
  }
  say_line('history - ' . (@parts ? join('; ', @parts) : 'no gate receipt for the versions on this branch'));
}

# --- 6. verdict (M008): the head commit ends with the verdict line the
# receipts give (verdicts.txt, kind ready), when the plan, both reviews, the
# rounds and every condition of the SPEC R6 set that applies passed;
# otherwise no line lets it merge ---
sub verdict_condition {
  my ($head) = @_;
  my @rows = Verdicts::rows();
  my ($ready) = Verdicts::words('ready', @rows);
  my ($key) = Verdicts::words('trailer-key', @rows);
  my $line = "$key: $ready";
  my $msg = Git::message($head);
  my $problem = Verdicts::trailer_problem($msg);
  my (undef, $parents) = commit_info($head);
  my %need = map { ($_ => 1) } 'plan', 'reviewer', 'security checker', 'rounds', @{ $T{need} };
  my @behind = grep { $need{$_} && !$T{ok}{$_} } 'plan', 'tier', 'lock', 'failing run', 'passing run', 'reviewer',
    'security checker', 'deep review', 'rounds', 'reporter';
  my $review = 'have this version reviewed, and end its commit with the verdict line the receipts give';
  my $add = "end the head commit's message with this line, as its last paragraph: $line (in an empty commit when the branch"
    . ' is pushed: the files stay the same)';
  my $next = @behind ? $review : $add;
  if (defined $problem) {
    return report('verdict', 0, 'the head commit merges ' . short($parents->[1]) . ' and has no valid verdict line,'
      . " so the merged version needs its own: $problem", $next) if @$parents > 1;
    return report('verdict', 0, "the head commit's verdict line: $problem", $next);
  }
  my $word = Verdicts::trailer_word($msg);
  if ($word eq $ready) {
    return report('verdict', 0, "the verdict line says $word, but the receipts do not give it (" . join(', ', @behind)
      . ' above): a typed line is not a review', $review) if @behind;
    return report('verdict', 1, "$word, as the receipts give it (commit " . short($head) . ')');
  }
  my ($meaning) = map { $_->[2] } grep { $_->[1] eq $word && $_->[0] =~ /\Atrailer/ } @rows;
  my $says = "the verdict line says $word (" . (defined $meaning ? $meaning : 'no meaning listed') . ')';
  return report('verdict', 0, "$says; the receipts give $ready", $add) unless @behind;
  return report('verdict', 0, "$says: no review approved this version (SPEC R4)",
    'fix and review again; after review round 3, plan again or the owner decides; a person\'s'
    . ' go does not replace the review\'s, so done-check stays NOT READY');
}

# --- 7. verdicts start: what this change makes status stop judging ---
sub verdicts_start_condition {
  my ($head, $ref, $tip, $up_to_date) = @_;
  my $area = 'verdicts start';
  return report($area, 0, 'no main branch to compare with', Git::no_main_action() . ', then run done-check again')
    unless defined $ref;
  my $new = conf_value($head);
  my $old = conf_value($tip);
  my $show = sub { defined $_[0] ? short($_[0]) : 'unset' };
  # status reads the file on disk (A37); the commit is read here, so the two
  # must agree (a submodule, Git LFS or another filter can keep them apart)
  my ($disk) = Conf::read('.');
  my $dv = $disk->{VERDICTS_FROM};
  return report($area, 0, 'VERDICTS_FROM is ' . $show->($dv) . ' in .claude/method.conf on disk, but '
    . $show->($new) . ' in the file commit ' . short($head) . ' stores (an uncommitted edit; or .claude is a submodule,'
    . ' or the file goes through Git LFS or another filter, so the commit does not hold what status reads)',
    'keep .claude/method.conf a plain file committed in this repository')
    if (defined $dv ? $dv : '') ne (defined $new ? $new : '');
  my $hwhy = conf_unreadable($head);
  return report($area, 0, "VERDICTS_FROM in this change cannot be read as status will read it once checked out: $hwhy",
    'keep .claude/method.conf a plain file committed in this repository') if defined $hwhy;
  my $why = conf_unreadable($tip);
  return report($area, 0, "VERDICTS_FROM on main ($ref " . short($tip) . ") cannot be read as status reads it: $why;"
    . ' could not check', 'keep .claude/method.conf a plain file committed on main (the change that makes it one cannot be'
    . ' checked here: compare with status on main)') if defined $why;
  return report($area, 1, 'VERDICTS_FROM is ' . $show->($new) . ' both on main and in this change')
    if (defined $new ? $new : '') eq (defined $old ? $old : '');
  return report($area, 0, 'this change moves VERDICTS_FROM; judged once the branch is up to date with main',
    'bring the branch up to date with main first') unless $up_to_date;
  my $moves = 'this change moves VERDICTS_FROM from ' . $show->($old) . ' to ' . $show->($new);
  my $jn = Verdicts::judged($tip, $new);
  if ($jn->{problem}) {
    return report($area, 0, "$moves, which is not in this shallow history of $ref; could not check",
      'fetch more history (' . unshallow() . ')') if $jn->{shallow};
    return report($area, 0, "$moves, which is not on ${ref}'s first-parent history, so status would report LOOK after"
      . ' the merge', 'set VERDICTS_FROM to a commit on main');
  }
  my $jo = Verdicts::judged($tip, $old);
  return report($area, 0, "$moves; could not check what it accepts: " . ($jo->{problem} && !$jo->{shallow}
    ? "the old value is not on ${ref}'s first-parent history" : 'the history here is shallow, so older commits were not read'),
    'fetch more history (' . unshallow() . ')') if $jo->{problem} || $jo->{shallow} || $jn->{shallow};
  my %still = map { ($_ => 1) } @{ $jn->{ids} };
  my @accepted = grep { !$still{$_} && defined Verdicts::trailer_problem(Git::message($_)) } @{ $jo->{ids} };
  return report($area, 1, "$moves; it accepts no commit without a valid verdict line") unless @accepted;
  # DECISIONS A30: older commits are accepted by moving VERDICTS_FROM in a
  # reviewed change; the verdict condition asks for that review, and the
  # READY line names what is accepted
  my $note = 'accepts ' . count(scalar(@accepted), 'commit', 'commits') . ' on main without a valid verdict line: '
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
  $judged = "$head against " . (defined $ref ? "$ref $tip" : 'no main branch');
  if (defined $ref && ancestor($head, $tip)) {
    say_line("NOTHING TO MERGE - $head is ${ref}'s tip or behind it ($tip)");
    exit 3;
  }
  my ($here, $where) = Checks::place();
  my ($head_tree) = commit_info($head);
  stop('HEAD cannot be read') unless defined $head_tree;
  %T = (head => $head, tree => $head_tree, branch => [], receipts => [], ok => {}, need => []);
  if (defined $ref) {
    my ($mst, @mbs) = Git::merge_base($tip, $head);
    stop('git merge-base failed') if $mst eq 'error';
    $T{mb} = $mst eq 'ok' ? $mbs[0] : undef;
    $T{branch} = [branch_commits($head, $tip)];
  }
  $T{receipts} = [Receipt::query(Receipt::store('.'))];

  files_condition($head);
  my $up = up_to_date_condition($head, $ref, $tip);
  checks_condition($head, $where);
  elsewhere_condition($here);
  $T{ok}{plan} = plan_condition($head, $ref);
  tier_condition($ref, $tip);
  lock_condition();
  failing_condition();
  newest_condition('passing run', 'tester', 'pass', '');
  gate_condition('reviewer', 'reviewer');
  gate_condition('security checker', 'security-checker');
  deep_condition();
  rounds_condition();
  newest_condition('reporter', 'reporter', 'approving', '; a FULL change needs the reporter\'s word on its report');
  verdict_condition($head);
  verdicts_start_condition($head, $ref, $tip, $up);
  history();

  my $against = defined $ref ? "$ref $tip" : 'no main branch';
  if (@failed) {
    say_line("next: $failed[0][1]");
    say_line('NOT READY - ' . count(scalar(@failed), 'condition', 'conditions') . ' failed (' . join(', ', map { $_->[0] } @failed)
      . "); $head against $against");
    exit 1;
  }
  my %role = Verdicts::roles(Verdicts::rows());
  my ($word) = Verdicts::trailer_word(Git::message($head));
  say_line("READY - $head is up to date with $against; verdict $word from the receipts ($role{reviewer} and"
    . " $role{'security-checker'} on tree " . short($T{tree}) . ", task $T{id}); checks from the $where run-checks log of"
    . " $ready_log, a local claim (RISKS #11)" . join('', map {"; $_"} @ready_notes));
  exit 0;
}

main() unless caller;
1;
