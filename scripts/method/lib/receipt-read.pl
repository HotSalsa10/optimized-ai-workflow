#!/usr/bin/env perl
# The gates' receipts, read (step 6b.1; docs/plans/step6b.md, section 1,
# item 3): the one reader of the receipt files gate-receipt writes (M048).
# lib/receipt.pl (the hook that writes them), lib/session.pl (session-status's
# count) and lib/done.pl (done-check) load it with require. It loads no
# hook library: lib/hook.pl's END block turns an exit 3 into 70, and
# done-check's NOTHING TO MERGE is exit 3. Nothing runs when it is loaded.
#
# A receipt is one JSON file per gate run in git's common folder, named
# method-receipt-<24 hex>.json (16 for the session and agent, 8 for the run
# number), at most 1 MB, version 1. The fields a reader uses: gate (its
# name, from verdicts.txt), run, started and stopped (seconds, or null),
# head and tree (the commit and its tree at the gate's start), state (one
# of the three receipt words), why (reason codes), open (the word the
# report opened with, or null when it had none) and bases (since step
# 6b.1: the base of each review packet the gate read, in the order read;
# none when it read no packet, and missing from receipts made before).
#
#   Receipt::words()        the gates and their opening words, the end key
#                           and the receipt words (from verdicts.txt)
#   Receipt::store(DIR)     git's common folder of DIR, absolute, or undef
#   Receipt::tree_of(DIR)   (HEAD, its tree) in DIR, or ('none', 'none')
#   Receipt::load(DIR, NAME)  one receipt, or undef
#   Receipt::query(STORE, TREE...)  the tree query: every readable receipt
#                           in STORE for one of the TREEs (every tree when
#                           none is given), each with its file name under
#                           "name"; its gate, state and tree are strings,
#                           its open and head strings or undef, its stopped
#                           a number or undef, its bases a list of commit
#                           ids (anything else in it dropped)
#   Receipt::by_stopped(RECEIPT...)  the receipts that have a stopped time,
#                           oldest first: the last is the newest. File names
#                           do not sort by time across agents (a per-agent
#                           hash, then a per-agent run number), and a run
#                           still going or cut off before its stop has no
#                           stopped time, so it never counts as the newest.
#   Receipt::counts(PROJECT, DIR)  session-status's count: for the tree of
#                           HEAD in DIR, how many receipts say the second
#                           and the third receipt word
package Receipt;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;

my $here = dirname(File::Spec->rel2abs(__FILE__));
require File::Spec->catfile($here, 'git.pl') unless defined &Git::run;
require File::Spec->catfile($here, 'json.pl') unless defined &Json::decode;
require File::Spec->catfile($here, 'verdicts.pl') unless defined &Verdicts::rows;

our $PREFIX = 'method-receipt-';
our $MAX = 1024 * 1024;                    # a receipt is small
my $ID = qr/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/;

# the words, from verdicts.txt: the gates and the kind each opens with,
# each kind's words, the end key, and the three receipt words in order
my %W;
sub words {
  return \%W if %W;
  my @rows = Verdicts::rows();
  my %gate = map { $_->[0] => $_->[1] } Verdicts::gates(@rows);
  my %open = map { $_ => [Verdicts::words($_, @rows)] } values %gate;
  my ($end) = Verdicts::words('end-key', @rows);
  my @state = Verdicts::words('receipt', @rows);
  die "receipt: verdicts.txt lacks the receipt words\n" unless @state == 3 && defined $end;
  %W = (gate => \%gate, open => \%open, end => $end, good => $state[0], wrong => $state[1], unchecked => $state[2]);
  return \%W;
}

# git's common folder of DIR, absolute, or undef outside a repository
sub store {
  my ($dir) = @_;
  return undef unless defined $dir;
  my ($st, $out) = Git::run('-C', $dir, 'rev-parse', '--git-common-dir');
  return undef if $st;
  my ($c) = split /\n/, $out;
  return undef unless defined $c && $c ne '';
  $c = File::Spec->rel2abs($c, $dir);
  # (where .git links to a store elsewhere, the folder it names: the
  # writer refuses to write through a link)
  require Cwd;
  my $real = Cwd::realpath($c);
  return defined $real && -d $real ? $real : undef;
}

# HEAD and its tree in DIR: (HEAD, TREE), or ('none', 'none')
sub tree_of {
  my ($dir) = @_;
  return ('none', 'none') unless defined $dir && $dir ne '' && -d $dir;
  my ($st, $head) = Git::run('-C', $dir, 'rev-parse', '-q', '--verify', 'HEAD^{commit}');
  return ('none', 'none') if $st || $head !~ /\A([0-9a-f]{40}|[0-9a-f]{64})\n\z/;
  $head = $1;
  my ($st2, $tree) = Git::run('-C', $dir, 'rev-parse', '-q', '--verify', "$head^{tree}");
  return ($head, 'none') if $st2 || $tree !~ /\A([0-9a-f]{40}|[0-9a-f]{64})\n\z/;
  return ($head, $1);
}

# the text of the receipt file NAME in DIR, or undef (a link, not a regular
# file, over the cap, unreadable)
sub text_of {
  my ($dir, $name) = @_;
  my $path = File::Spec->catfile($dir, $name);
  return undef if -l $path || !-f _ || -s _ > $MAX;
  open my $h, '<:raw', $path or return undef;
  local $/;
  my $text = <$h>;
  close $h;
  return $text;
}

# a receipt: the hash, or undef when there is none or it cannot be read
sub load {
  my ($dir, $name) = @_;
  my $text = text_of($dir, $name);
  return undef unless defined $text;
  my ($r) = Json::decode($text, 'plain');
  return ref $r eq 'HASH' && ($r->{v} // 0) == 1 ? $r : undef;
}

sub plain { return defined $_[0] && !ref $_[0] }

sub query {
  my ($store, @trees) = @_;
  return () unless defined $store;
  my %want = map { $_ => 1 } @trees;
  opendir my $d, $store or return ();
  my @names = sort grep { /\A\Q$PREFIX\E[0-9a-f]{24}\.json\z/ } readdir $d;
  closedir $d;
  my @out;
  for my $name (@names) {
    my $text = text_of($store, $name);
    next unless defined $text;
    # (the receipts of other trees are not decoded)
    next if @trees && !grep { index($text, qq("tree":"$_")) >= 0 } @trees;
    my ($r) = Json::decode($text, 'plain');
    next unless ref $r eq 'HASH' && ($r->{v} // 0) == 1;
    next unless plain($r->{gate}) && plain($r->{state}) && plain($r->{tree});
    next if @trees && !$want{ $r->{tree} };
    $r->{$_} = undef for grep { !plain($r->{$_}) } qw(open head);
    $r->{stopped} = undef unless plain($r->{stopped}) && $r->{stopped} =~ /\A[0-9]+(?:\.[0-9]+)?\z/;
    $r->{bases} = [grep { plain($_) && $_ =~ $ID } ref $r->{bases} eq 'ARRAY' ? @{ $r->{bases} } : ()];
    $r->{name} = $name;
    push @out, $r;
  }
  return @out;
}

sub by_stopped {
  return sort { $a->{stopped} <=> $b->{stopped} || $a->{name} cmp $b->{name} } grep { defined $_->{stopped} } @_;
}

# session-status's count (step 5b.2): the receipts in the repository of
# PROJECT for the tree of HEAD in DIR that do not say the first receipt
# word: ([WORD, COUNT]...) for the second and the third word, those with a
# count above 0
sub counts {
  my ($project, $dir) = @_;
  my $store = store($project) or return ();
  my (undef, $tree) = tree_of($dir);
  return () if $tree eq 'none';
  my $w = words();
  my %n;
  $n{ $_->{state} }++ for grep { $_->{state} ne $w->{good} } query($store, $tree);
  return map { [$_, $n{$_}] } grep { $n{$_} } $w->{wrong}, $w->{unchecked};
}

1;
