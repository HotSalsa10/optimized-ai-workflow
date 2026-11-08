#!/usr/bin/env perl
# The one capped log writer for the hooks (M072: no log grows forever or
# stores secrets). Loaded with require; nothing runs when it is loaded.
#
#   Log::append(ROOT, NAME, CAP, rule => ID, tool => NAME, hash => HEX)
#     adds one line to the log at NAME under the folder ROOT (the
#     repository's top folder): the time (UTC), the rule ID, the tool name
#     and the SHA-256 of the hook's input, separated by tabs. Those are the
#     only fields, and each must have its shape (a rule ID such as G4 or
#     G16; a tool name of at most 128 letters, digits and _ . : -; 64 hex
#     digits), so no free text reaches a log: no command, no path, no
#     message. A tool name is chosen by the hook from the tool's own name,
#     never from what the tool was given. Then, while the log holds more than
#     CAP lines (1000 when CAP is undef), only its newest CAP lines are kept.
#     Dies with a reason on any failure: the caller decides what a failed log
#     means, and a hook's answer never depends on it.
#   Log::lines(ROOT, NAME) gives ([TIME, RULE, TOOL, HASH]...) for the
#     well-formed lines among the newest 4 times CAP, oldest first, and the
#     number of other lines (an older part, not read, counts as one); an
#     absent log gives none. It writes nothing and takes no lock: a log
#     replaced by a trim while it is opened is opened again. It dies with a
#     reason, as append does, on a name or a folder append would refuse, and
#     on a log that is a link or has a second name, so its caller wraps it
#     in eval.
#
# Safety:
# - NAME is a relative path whose parts are letters, digits and . _ -
#   (not "." or ".."); every folder from ROOT down to the log must be a
#   real folder, not a link, and is made when missing.
# - The log and its lock file (NAME.lock, held while a line is added and the
#   log trimmed, so hooks that run at the same time lose no line) must be
#   regular files with one name: a link, or a second name made with ln,
#   would let a write reach a file elsewhere. They are opened without
#   following a link where the system allows, and the opened file must be
#   the one that was checked.
# - Files are opened without waiting (O_NONBLOCK), so a FIFO put in a
#   file's place is refused at once instead of holding the lock.
# - The trimmed log is written to a new temporary file (made with O_EXCL,
#   after any old file of that name is removed; another name is tried when
#   one cannot be removed) and renamed over the log; it is removed again
#   when the write fails, as on a full disk.
# - Only the end of a large log is read (the newest CAP lines take at most
#   CAP times 512 bytes), so a huge or sparse file cannot fill the memory.
# Known limit: a process that swaps a folder for a link between the checks
# and the open can still steer a write (RISKS #2: the hooks trust the
# working tree they run in).
package Log;
use strict;
use warnings;
use Fcntl qw(:flock O_WRONLY O_RDWR O_RDONLY O_CREAT O_APPEND O_EXCL SEEK_SET);
use File::Spec;
use Time::HiRes ();

my $NOFOLLOW = eval { Fcntl::O_NOFOLLOW() } || 0;
my $NONBLOCK = eval { Fcntl::O_NONBLOCK() } || 0;
our $CAP = 1000;
our $WAIT = 5;    # seconds to wait for the lock
our $LINE_MAX = 512;    # the longest line a log keeps, in bytes

my %SHAPE = (
  rule => qr/\A[A-Z][A-Z0-9-]{0,15}\z/,
  tool => qr/\A[A-Za-z0-9_.:-]{1,128}\z/,
  hash => qr/\A[0-9a-f]{64}\z/,
);
my @FIELDS = qw(rule tool hash);

# the log's full path, after checking (and making, unless READ) each folder
# below ROOT; with READ, undef when a folder is missing
sub place {
  my ($root, $name, $read) = @_;
  # a trailing / or /. would make -l follow the link it checks for
  $root =~ s{(?:/+\.?)+\z}{} if defined $root && $root =~ m{[^/]};
  die "log: the folder $root is missing or a link\n" unless defined $root && -d $root && !-l $root;
  my @parts = defined $name ? split(m{/}, $name, -1) : ();
  die "log: the log name must be a relative path of letters, digits and . _ -\n"
    if !@parts || grep { !/\A[A-Za-z0-9._-]+\z/ || $_ eq '.' || $_ eq '..' } @parts;
  my $file = pop @parts;
  my $dir = $root;
  for my $p (@parts) {
    $dir = File::Spec->catdir($dir, $p);
    if (!-e $dir && !-l $dir) {
      return undef if $read;
      mkdir $dir or do { my $e = $!; -d $dir or die "log: cannot make $dir ($e)\n" };
    }
    die "log: $dir is a link; the log is not used through it\n" if -l $dir;
    die "log: $dir is not a folder\n" unless -d $dir;
  }
  return File::Spec->catfile($dir, $file);
}

# open PATH, refusing a link, anything but a regular file, and a file with
# more than one name; the opened file must be the one checked
sub open_plain {
  my ($path, $flags) = @_;
  die "log: $path is a link or not a regular file\n" if -l $path || (-e $path && !-f $path);
  sysopen my $fh, $path, $flags | $NOFOLLOW | $NONBLOCK, 0644 or die "log: cannot open $path ($!)\n";
  my @fs = stat $fh;
  my @ps = lstat $path;
  die "log: $path is not a regular file\n" unless -f $fh;
  # replaced (a trim renamed a new log over it) since it was opened: the
  # name now holds another file (the opened one, kept open, keeps its inode
  # number, so no new file can have it)
  die "log: $path changed while it was opened\n" unless @ps && $ps[0] == $fs[0] && $ps[1] == $fs[1];
  die "log: $path has another name (a hard link); the log is not used through it\n" if $fs[3] != 1;
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
  my $fh = open_plain($path, O_RDWR | O_CREAT | O_APPEND);
  binmode $fh;
  # a half line left by a write that failed (a full disk) or was cut off
  # stays a line of its own, and this one starts on a fresh line; a write
  # that fails takes its own half line back out
  my $size = -s $fh;
  if ($size) {
    my $last = '';
    sysseek($fh, $size - 1, 0) && sysread($fh, $last, 1);
    $line = "\n$line" if $last ne "\n";
  }
  if (!(print {$fh} $line) || !close $fh) {
    my $err = $!;
    truncate $path, $size if defined $size && -f $path && !-l $path;
    die "log: cannot write $path ($err)\n";
  }
  trim($path, $cap);
  close $lock;
  return 1;
}

# the last lines of PATH, at most CAP of them, reading at most CAP times
# $LINE_MAX bytes from its end (a line cut by the start of that window is
# dropped); and whether there were more
sub tail {
  my ($path, $cap) = @_;
  my $fh;
  # a reader takes no lock: a trim may replace the log as it opens it
  for my $try (1 .. 5) {
    $fh = eval { open_plain($path, O_RDONLY) };
    last if $fh;
    die $@ unless $@ =~ /changed while it was opened/ && $try < 5;
    Time::HiRes::sleep(0.01 * $try);
  }
  binmode $fh;
  my $size = -s $fh;
  my $want = $cap * $LINE_MAX;
  my $from = $size > $want ? $size - $want : 0;
  sysseek $fh, $from, SEEK_SET or die "log: cannot read $path ($!)\n";
  my $buf = '';
  while (1) {
    my $n = sysread $fh, $buf, 1 << 20, length $buf;
    die "log: cannot read $path ($!)\n" unless defined $n;
    last if $n == 0;
  }
  close $fh;
  my @lines = $buf =~ /([^\n]*\n|[^\n]+\z)/g;
  shift @lines if $from > 0 && @lines;    # the first line may be cut
  my $more = $from > 0 || @lines > $cap;
  splice @lines, 0, @lines - $cap if @lines > $cap;
  return (\@lines, $more);
}

# keep only the newest CAP lines of PATH (the lock is held)
sub trim {
  my ($path, $cap) = @_;
  my ($lines, $more) = tail($path, $cap);
  return unless $more;
  my ($out, $tmp);
  for my $n ('', 1 .. 9) {
    $tmp = "$path.tmp.$$" . ($n eq '' ? '' : ".$n");
    unlink $tmp if -e $tmp || -l $tmp;
    last if sysopen $out, $tmp, O_WRONLY | O_CREAT | O_EXCL | $NOFOLLOW | $NONBLOCK, 0644;
    die "log: cannot make $tmp ($!)\n" unless $!{EEXIST} && $n ne '9';
  }
  binmode $out;
  my $ok = print {$out} @$lines;
  $ok = close($out) && $ok;
  if (!$ok) {
    my $e = $!;
    unlink $tmp;
    die "log: cannot write $tmp ($e)\n";
  }
  rename $tmp, $path or do { my $e = $!; unlink $tmp; die "log: cannot replace $path ($e)\n" };
}

sub lines {
  my ($root, $name) = @_;
  my $path = place($root, $name, 1);
  return ([], 0) unless defined $path && (-e $path || -l $path);
  my ($all, $more) = tail($path, $CAP * 4);
  my (@ok, $bad);
  $bad = $more ? 1 : 0;
  for my $l (@$all) {
    (my $t = $l) =~ s/\n\z//;
    my @f = split /\t/, $t, -1;
    if (@f == 4 && $f[0] =~ /\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z/
      && $f[1] =~ $SHAPE{rule} && $f[2] =~ $SHAPE{tool} && $f[3] =~ $SHAPE{hash}) {
      push @ok, \@f;
    } else {
      $bad++;
    }
  }
  return (\@ok, $bad);
}

1;
