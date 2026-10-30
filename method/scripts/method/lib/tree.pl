#!/usr/bin/env perl
# A commit's folders and files, each read through lib/git.pl's Git::cat and
# so checked against its id, and the one rule "the files on disk are the
# commit" (M048). The review packet, run-checks and done-check use it;
# callers load lib/git.pl first. Digest::SHA is loaded only when a file is
# hashed, so status can still load this file and report it missing.
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
#   Tree::differences(COMMIT) how the files on disk differ from COMMIT; a
#                       CRLF or an $Id$ that git's checkout writes from the
#                       commit's own .gitattributes is the commit's
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

# A file larger than this that differs from the commit is not read whole:
# it counts as content.
my $BIG = 64 * 1024 * 1024;

# stream_id PATH ID SIZE: 1 when the file holds the blob ID (read as a stream,
# so a large file is never held in memory), 0 when not, undef when it cannot
# be read
sub stream_id {
  my ($p, $id, $size) = @_;
  require Digest::SHA;
  my $d = Digest::SHA->new(length($id) == 64 ? 256 : 1)->add("blob $size\0");
  open my $fh, '<:raw', $p or return undef;
  my $ok = eval { $d->addfile($fh); 1 };
  close $fh;
  return undef unless $ok;
  return $d->hexdigest eq $id ? 1 : 0;
}

sub stream_sha256 {
  my ($p) = @_;
  require Digest::SHA;
  open my $fh, '<:raw', $p or return '';
  my $h = eval { Digest::SHA->new(256)->addfile($fh)->hexdigest };
  close $fh;
  return defined $h ? $h : '';
}

# conversion_problem: '' when git can be asked for the bytes its checkout
# writes from a commit's own attributes, else why not. git reads
# .git/info/attributes even when told to take attributes from a commit, so
# that file must hold no rule; and --attr-source needs git 2.42.
my $git_version_ok;
sub conversion_problem {
  if (!defined $git_version_ok) {
    my ($st, $v) = Git::run('version');
    my ($maj, $min) = $v =~ /\Agit version ([0-9]+)\.([0-9]+)/;
    $git_version_ok = !$st && defined $maj && ($maj > 2 || ($maj == 2 && $min >= 42)) ? 1 : 0;
  }
  return 'git 2.42 or later is needed to tell a conversion the commit asks for from an edit' unless $git_version_ok;
  my ($st, $path) = Git::run('rev-parse', '--git-path', 'info/attributes');
  return 'git did not name its info/attributes file' if $st || $path !~ s/\n\z//;
  return '' unless -e $path || -l $path;
  open my $fh, '<:raw', $path or return 'cannot read .git/info/attributes';
  while (my $l = <$fh>) {
    next if $l =~ /\A[ \t]*(?:#.*)?\r?\n?\z/;
    close $fh;
    return '.git/info/attributes holds rules, so a conversion cannot be told from an edit';
  }
  close $fh;
  return '';
}

# checkout_bytes COMMIT PATH: the bytes git's checkout writes for PATH from
# COMMIT's own attributes, or undef. Only git's built-in conversions apply
# (line ends, ident, working-tree-encoding): every filter driver is off
# (Git::status_options), the system and personal attribute files are not
# read, attributes come from COMMIT, not the disk, and this machine's
# line-end settings are pinned off.
sub checkout_bytes {
  my ($commit, $p) = @_;
  require File::Spec;
  local $ENV{GIT_ATTR_NOSYSTEM} = 1;
  my ($st, $out) = Git::run('-c', 'core.autocrlf=false', '-c', 'core.eol=lf', '-c',
    'core.attributesFile=' . File::Spec->devnull, "--attr-source=$commit", Git::status_options(),
    'cat-file', '--filters', "$commit:$p");
  return $st ? undef : $out;
}

# differences COMMIT: how the files on disk differ from COMMIT's, as
# {list => [[PATH, KIND], ...], lfs => [PATH, ...], converted => [PATH, ...],
# no_conversion => why conversions could not be told apart, or undef},
# sorted by path. A file is COMMIT's when it holds the same bytes; for Git
# LFS, content whose SHA-256 is the one the stored pointer names (listed in
# lfs); or exactly the bytes git's own checkout writes from COMMIT's
# attributes (listed in converted: a CRLF or an $Id$ a committed
# .gitattributes asks for), never a conversion that only this machine's
# settings explain. KIND: missing (not on disk); link (a symlink whose target
# differs, a symlink where a file was, or a file where a symlink was); type
# (not a regular file); unreadable; cr (the same bytes once CRLF line ends
# become LF); content (anything else, also a file over 64 MB that differs).
# Submodules are not compared.
sub differences {
  my ($commit) = @_;
  my (@list, @lfs, @converted, $no_conv);
  my %files = %{ all_files($commit) };
  for my $p (sort keys %files) {
    my ($mode, $id) = @{ $files{$p} };
    next if $mode eq '160000';
    my @st = lstat $p;
    if (!@st) { push @list, [$p, 'missing']; next }
    if (-l _) {
      my $target = $mode eq '120000' ? readlink $p : undef;
      push @list, [$p, 'link'] unless defined $target && $target eq blob($id);
      next;
    }
    if ($mode eq '120000') { push @list, [$p, 'link']; next }
    if (!-f _) { push @list, [$p, 'type']; next }
    my $same = stream_id($p, $id, $st[7]);
    if (!defined $same) { push @list, [$p, 'unreadable']; next }
    next if $same;
    my $c = eval { Git::cat('blob', $id, 1, 1024) };
    oops($@) if $@;
    my ($oid, $osize) = defined $c
      ? $c =~ m{\Aversion https://git-lfs\.github\.com/spec/v1\noid sha256:([0-9a-f]{64})\nsize ([0-9]+)\n\z} : ();
    if (defined $oid && $osize == $st[7] && stream_sha256($p) eq $oid) { push @lfs, $p; next }
    if ($st[7] > $BIG) { push @list, [$p, 'content']; next }
    my $disk;
    if (open my $fh, '<:raw', $p) {
      $disk = do { local $/; <$fh> };
      close $fh;
    }
    if (!defined $disk) { push @list, [$p, 'unreadable']; next }
    $no_conv = conversion_problem() unless defined $no_conv;
    if ($no_conv eq '') {
      my $want = checkout_bytes($commit, $p);
      if (defined $want && $want eq $disk) { push @converted, $p; next }
    }
    (my $lf = $disk) =~ s/\r\n/\n/g;
    if (Git::object_id('blob', $lf, $id) eq $id) { push @list, [$p, 'cr']; next }
    push @list, [$p, 'content'];
  }
  return { list => \@list, lfs => \@lfs, converted => \@converted,
    no_conversion => defined $no_conv && $no_conv ne '' ? $no_conv : undef };
}
1;
