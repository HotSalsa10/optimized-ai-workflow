#!/usr/bin/env perl
# The one capped log writer for the hooks (M072: no log grows forever or
# stores secrets). Loaded with require; nothing runs when it is loaded.
#
#   Log::append(ROOT, NAME, CAP, rule => ID, tool => NAME, hash => HEX)
#     adds one line to the log at NAME under the folder ROOT (the
#     repository's top folder): the time (UTC), the rule ID, the tool name
#     and the SHA-256 of the hook's input, separated by tabs. Those are the
#     only fields, and each must have its shape (a rule ID such as G4 or
#     G16, a tool name of letters, digits and _ . : / -, 64 hex digits), so
#     no free text, and so no secret, can reach a log. Then, while the log
#     holds more than CAP lines (1000 when CAP is undef), only its newest CAP
#     lines are kept. Dies with a reason on any failure: the caller decides
#     what a failed log means, and a hook's answer never depends on it.
#   Log::lines(ROOT, NAME) gives ([TIME, RULE, TOOL, HASH]...) for the
#     well-formed lines, oldest first, and the number of other lines; an
#     absent log gives none.
#
# Safety: every folder from ROOT down to the log must be a real folder,
# not a link, and is made when missing; the log itself must be a regular
# file, opened without following a link where the system allows. A lock
# file beside the log (NAME.lock) is held while a line is added and the log
# trimmed, so hooks that run at the same time lose no line. The trimmed log
# is written to a temporary file and renamed over the old one.
package Log;
use strict;
use warnings;
use Fcntl qw(:flock O_WRONLY O_RDWR O_CREAT O_APPEND);
use File::Spec;
use Time::HiRes ();

my $NOFOLLOW = eval { Fcntl::O_NOFOLLOW() } || 0;
our $CAP = 1000;
our $WAIT = 5;    # seconds to wait for the lock

my %SHAPE = (
  rule => qr/\A[A-Z][A-Z0-9-]{0,15}\z/,
  tool => qr/\A[A-Za-z0-9_.:\/-]{1,200}\z/,
  hash => qr/\A[0-9a-f]{64}\z/,
);
my @FIELDS = qw(rule tool hash);

# the log's full path, after checking (and making) each folder below ROOT
sub place {
  my ($root, $name) = @_;
  die "log: the folder $root is missing or a link\n" unless defined $root && -d $root && !-l $root;
  die "log: the log name must be a relative path without ..\n"
    if !defined $name || $name eq '' || File::Spec->file_name_is_absolute($name) || grep { $_ eq '..' || $_ eq '' } split m{/}, $name;
  my @parts = split m{/}, $name;
  my $file = pop @parts;
  my $dir = $root;
  for my $p (@parts) {
    next if $p eq '.';
    $dir = File::Spec->catdir($dir, $p);
    if (!-e $dir && !-l $dir) { mkdir $dir or -d $dir or die "log: cannot make $dir ($!)\n" }
    die "log: $dir is a link; the log is not written through it\n" if -l $dir;
    die "log: $dir is not a folder\n" unless -d $dir;
  }
  return File::Spec->catfile($dir, $file);
}

# open PATH for writing, refusing a link or anything but a regular file
sub open_plain {
  my ($path, $flags) = @_;
  die "log: $path is a link or not a regular file\n" if -l $path || (-e $path && !-f $path);
  sysopen my $fh, $path, $flags | $NOFOLLOW, 0644 or die "log: cannot open $path ($!)\n";
  die "log: $path is not a regular file\n" unless -f $fh;
  return $fh;
}

sub stamp {
  my @t = gmtime;
  return sprintf '%04d-%02d-%02dT%02d:%02d:%02dZ', $t[5] + 1900, $t[4] + 1, @t[3, 2, 1, 0];
}

sub append {
  my ($root, $name, $cap, %f) = @_;
  $cap = $CAP unless defined $cap;
  die "log: the cap must be a whole number above 0\n" unless $cap =~ /\A[1-9][0-9]{0,8}\z/;
  for my $k (sort keys %f) {
    die "log: $k is not a log field\n" unless $SHAPE{$k};
  }
  for my $k (@FIELDS) {
    die "log: the field $k is missing or not of its shape\n" unless defined $f{$k} && $f{$k} =~ $SHAPE{$k};
  }
  my $path = place($root, $name);
  my $lock = open_plain("$path.lock", O_RDWR | O_CREAT);
  my $until = Time::HiRes::time() + $WAIT;
  until (flock $lock, LOCK_EX | LOCK_NB) {
    die "log: the log is locked by another hook for over $WAIT s\n" if Time::HiRes::time() > $until;
    Time::HiRes::sleep(0.05);
  }
  my $line = join("\t", stamp(), @f{@FIELDS}) . "\n";
  my $fh = open_plain($path, O_WRONLY | O_CREAT | O_APPEND);
  binmode $fh;
  print {$fh} $line or die "log: cannot write $path ($!)\n";
  close $fh or die "log: cannot write $path ($!)\n";
  trim($path, $cap);
  close $lock;
  return 1;
}

# keep only the newest CAP lines of PATH (the lock is held)
sub trim {
  my ($path, $cap) = @_;
  open my $in, '<:raw', $path or die "log: cannot read $path ($!)\n";
  my @lines = <$in>;
  close $in;
  return if @lines <= $cap;
  my $tmp = "$path.tmp.$$";
  unlink $tmp if -l $tmp;
  my $out = open_plain($tmp, O_WRONLY | O_CREAT | Fcntl::O_TRUNC());
  binmode $out;
  print {$out} @lines[$#lines - $cap + 1 .. $#lines] or die "log: cannot write $tmp ($!)\n";
  close $out or die "log: cannot write $tmp ($!)\n";
  rename $tmp, $path or do { unlink $tmp; die "log: cannot replace $path ($!)\n" };
}

sub lines {
  my ($root, $name) = @_;
  my $path = File::Spec->catfile($root, split m{/}, $name);
  return ([], 0) unless -e $path || -l $path;
  die "log: $path is a link or not a regular file\n" if -l $path || !-f $path;
  open my $in, '<:raw', $path or die "log: cannot read $path ($!)\n";
  my (@ok, $bad);
  $bad = 0;
  while (my $l = <$in>) {
    $l =~ s/\n\z//;
    my @f = split /\t/, $l, -1;
    if (@f == 4 && $f[0] =~ /\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z/
      && $f[1] =~ $SHAPE{rule} && $f[2] =~ $SHAPE{tool} && $f[3] =~ $SHAPE{hash}) {
      push @ok, \@f;
    } else {
      $bad++;
    }
  }
  close $in;
  return (\@ok, $bad);
}

1;
