#!/usr/bin/env perl
# A commit's folders and files, each read through lib/git.pl's Git::cat and
# so checked against its id, and the one rule "the files on disk are the
# commit" (M048). The review packet uses it; callers load lib/git.pl first.
#
#   Tree::stored(TYPE, ID)    a stored object's content, checked against its id
#   Tree::blob(ID)            a file's content ('' for the all-zero id)
#   Tree::tree_entries(ID)    a checked folder's entries, name => [mode, id]
#   Tree::root_tree(COMMIT)   the id of COMMIT's top folder
#   Tree::lookup(COMMIT, PATH)  [mode, id] of PATH in COMMIT, or undef
#   Tree::has_file(COMMIT, PATH)  PATH is a regular file in COMMIT
#   Tree::all_files(COMMIT)   every entry of COMMIT, path => [mode, id]
#   Tree::check_trees(A, B)   every folder a comparison of A and B reads is checked
#   Tree::changed(FROM, TO)   the changed files, each {st, m1, m2, o1, o2, path, old}
#   Tree::blob_diff(A, B, N)  the hunks between two files, N lines of context
#   Tree::differences(COMMIT) how the files on disk differ from COMMIT
#
# An error goes to $Tree::FAIL when a caller set it (the packet turns it into
# its own exit code), else it dies with the message.
package Tree;
use strict;
use warnings;

our $FAIL;

sub oops {
  my ($msg) = @_;
  $msg =~ s/\n\z//;
  $FAIL->($msg) if $FAIL;
  die "$msg\n";
}

# git_ok ARGS: standard output of a git call that must succeed.
sub git_ok {
  my $out = eval { Git::ok(@_) };
  oops($@) unless defined $out;
  return $out;
}

my $zero = qr/\A0+\z/;

# stored TYPE ID: git does not check a stored file, folder or parent commit
# when it reads one, so an object changed by hand could otherwise pass for
# the committed one.
sub stored {
  my $c = eval { Git::cat(@_) };
  oops($@) unless defined $c;
  return $c;
}

sub blob {
  my ($id) = @_;
  return $id =~ $zero ? '' : stored('blob', $id);
}

my %entries_cache;
sub tree_entries {
  my ($id) = @_;
  return $entries_cache{$id} if $entries_cache{$id};
  my $c = stored('tree', $id);
  my $len = length($id) / 2;
  my %e;
  pos($c) = 0;
  while (pos($c) < length $c) {
    $c =~ /\G([0-9]+) ([^\0]*)\0(.{$len})/gcs or oops("cannot read the stored tree $id");
    $e{$2} = [$1, unpack('H*', $3)];
  }
  return $entries_cache{$id} = \%e;
}

sub root_tree {
  my ($commit) = @_;
  my $t = git_ok('rev-parse', '--verify', "$commit^{tree}");
  chomp $t;
  return $t;
}

sub lookup {
  my ($commit, $path) = @_;
  my $tree = root_tree($commit);
  my @parts = split m{/}, $path, -1;
  while (@parts) {
    my $e = tree_entries($tree)->{ shift @parts };
    return undef unless $e;
    return $e unless @parts;
    return undef unless $e->[0] eq '40000';
    $tree = $e->[1];
  }
  return undef;
}

sub has_file {
  my ($commit, $path) = @_;
  my $e = lookup($commit, $path);
  return $e && $e->[0] =~ /\A100(?:644|755)\z/;
}

sub all_files {
  my %out;
  my @todo = (['', root_tree($_[0])]);
  while (my $t = shift @todo) {
    my ($prefix, $tree) = @$t;
    my $e = tree_entries($tree);
    for my $n (keys %$e) {
      my $p = length $prefix ? "$prefix/$n" : $n;
      if ($e->{$n}[0] eq '40000') { push @todo, [$p, $e->{$n}[1]] }
      else { $out{$p} = $e->{$n} }
    }
  }
  return \%out;
}

sub check_trees {
  my @todo = ([root_tree($_[0]), root_tree($_[1])]);
  while (my $pair = shift @todo) {
    my ($x, $y) = @$pair;
    next if defined $x && defined $y && $x eq $y;
    my $ex = defined $x ? tree_entries($x) : {};
    my $ey = defined $y ? tree_entries($y) : {};
    my %names = map { ($_ => 1) } keys %$ex, keys %$ey;
    for my $n (keys %names) {
      my $tx = $ex->{$n} && $ex->{$n}[0] eq '40000' ? $ex->{$n}[1] : undef;
      my $ty = $ey->{$n} && $ey->{$n}[0] eq '40000' ? $ey->{$n}[1] : undef;
      push @todo, [$tx, $ty] if defined $tx || defined $ty;
    }
  }
}

# changed FROM TO: sorted by name. Submodules are listed whatever .gitmodules
# or the settings say, and the order is the same whatever a diff.orderFile
# setting says.
sub changed {
  my ($from_rev, $to_rev) = @_;
  my $raw = git_ok('diff', '--raw', '-z', '--no-abbrev', '-M', '--ignore-submodules=none', $from_rev, $to_rev);
  my @f = split /\0/, $raw, -1;
  pop @f if @f && $f[-1] eq '';
  my @files;
  while (@f) {
    my $meta = shift @f;
    my ($m1, $m2, $o1, $o2, $s) = $meta =~ /\A:(\d{6}) (\d{6}) ([0-9a-f]+) ([0-9a-f]+) ([A-Z])\d*\z/
      or oops('cannot read the list of changed files from git');
    my $p = shift @f;
    my $old = $p;
    $p = shift @f if $s eq 'R' || $s eq 'C';
    oops('cannot read the list of changed files from git') unless defined $p;
    push @files, { st => $s, m1 => $m1, m2 => $m2, o1 => $o1, o2 => $o2, path => $p, old => $old };
  }
  return sort { $a->{path} cmp $b->{path} } @files;
}

# blob_diff A B N: the hunks between files A and B, compared by id with fixed
# options, or undef when git shows none. A hunk header keeps only its line
# numbers: the function name git adds after them comes from a diff driver
# that attributes and settings choose.
sub blob_diff {
  my ($a, $b, $n) = @_;
  my $d = git_ok('-c', 'diff.suppressBlankEmpty=false', 'diff', '--no-ext-diff', '--no-textconv', '--no-color',
    '--text', "--unified=$n", '--inter-hunk-context=0', '--diff-algorithm=myers', '--indent-heuristic', $a, $b);
  my $at = index($d, "\n@@");
  return undef if $at < 0;
  $d = substr($d, $at + 1);
  $d =~ s/^(\@\@ -[0-9]+(?:,[0-9]+)? \+[0-9]+(?:,[0-9]+)? \@\@).*$/$1/mg;
  return $d;
}

# differences COMMIT: how the files on disk differ from COMMIT's, as
# {list => [[PATH, KIND], ...], lfs => [PATH, ...]}, sorted by path.
# A file is the commit's when it holds the same bytes, or, for Git LFS,
# content whose SHA-256 is the one the stored pointer names (listed in lfs).
# KIND: missing (not on disk); link (a symlink whose target differs);
# type (not a regular file); unreadable; cr (the same bytes once CRLF line
# ends become LF); content (anything else). Submodules are not compared.
sub differences {
  my ($commit) = @_;
  my (@list, @lfs);
  my %files = %{ all_files($commit) };
  for my $p (sort keys %files) {
    my ($mode, $id) = @{ $files{$p} };
    next if $mode eq '160000';
    if (!(-l $p || -e _)) { push @list, [$p, 'missing']; next }
    if ($mode eq '120000' && -l $p) {
      my $target = readlink $p;
      push @list, [$p, 'link'] unless defined $target && $target eq blob($id);
      next;
    }
    if (!-f $p) { push @list, [$p, 'type']; next }
    my $disk;
    if (open my $fh, '<:raw', $p) {
      $disk = do { local $/; <$fh> };
      close $fh;
    }
    if (!defined $disk) { push @list, [$p, 'unreadable']; next }
    next if Git::object_id('blob', $disk, $id) eq $id;
    (my $lf = $disk) =~ s/\r\n/\n/g;
    if (Git::object_id('blob', $lf, $id) eq $id) { push @list, [$p, 'cr']; next }
    my ($oid) = blob($id) =~ m{\Aversion https://git-lfs\.github\.com/spec/v1\noid sha256:([0-9a-f]{64})\nsize [0-9]+\n\z};
    if (defined $oid) {
      require Digest::SHA;
      if (Digest::SHA::sha256_hex($disk) eq $oid) { push @lfs, $p; next }
    }
    push @list, [$p, 'content'];
  }
  return { list => \@list, lfs => \@lfs };
}

1;
