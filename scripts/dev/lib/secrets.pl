#!/usr/bin/env perl
# Scans files for secrets and personal data. Called by scripts/dev/scan-secrets.sh.
#
# Usage:
#   perl secrets.pl [--staged] [--ids] ALLOW_FILE FILE...
#       Scans each FILE. With --staged (run from the repo root), also scans the
#       staged copy of every tracked file whose staged copy differs from the
#       working tree, so a secret that is staged but no longer on disk is seen.
#       With --ids, each finding also shows the ID to put in ALLOW_FILE.
#       Prints one line per finding (masked, never in full), "NOTE ..." lines,
#       then "EXAMINED n", "STAGED n", "BAD n", "ALLOWED n", "SKIPPED n", "SKIPPED_NAMES ...".
#   perl secrets.pl --mask
#       Copies standard input to standard output with keys, credentials and
#       personal email addresses masked, control characters escaped and every
#       line indented by two spaces. validate.sh sends other tools' output
#       through it, so a key a tool quotes is not printed in full either.
#
# ALLOW_FILE lines are PATH<TAB>ID<TAB>REASON. The ID is the first 12
# characters of git's object ID for "PATH", a NUL byte and the matched text,
# so an entry covers one text in one file and does not hold the text itself.
#
# Text in UTF-16 is decoded first: with a byte-order mark always, without one
# when most of it is ASCII. Lines may end in LF, CRLF or a lone CR. Binary
# files are not read as text. In every file that holds a NUL byte, the runs
# of printable bytes are also searched: for keys and tokens in binary files,
# and for everything in files decoded as UTF-16 (text added after the UTF-16
# part, for example).
use strict;
use warnings;
use IPC::Open2;

# Prints one line of output. Control characters taken from file names or
# content are shown as \xNN, so text from a file can never start a new line
# of output, move the cursor or reach the CI runner as a command.
sub esc {
  my ($s) = @_;
  $s =~ s/([\x00-\x1F\x7F])/sprintf('\\x%02X', ord $1)/ge;
  return $s;
}
sub say_line { print esc($_[0]), "\n" }

my ($staged, $show_ids, $mask_mode) = (0, 0, 0);
while (@ARGV && $ARGV[0] =~ /^--/) {
  my $opt = shift @ARGV;
  if ($opt eq '--staged') { $staged = 1 }
  elsif ($opt eq '--ids') { $show_ids = 1 }
  elsif ($opt eq '--mask') { $mask_mode = 1 }
  else { die "secrets: unknown option " . esc($opt) . "\n" }
}

# Keys and tokens with a recognisable shape.
my @token_rules = (
  [qr/sk-ant-[A-Za-z0-9_-]{20,}/, 'Anthropic API key'],
  [qr/(?<![A-Za-z0-9])sk-(?:proj-)?[A-Za-z0-9]{32,}/, 'OpenAI-style API key'],
  [qr/(?<![A-Za-z0-9])gh[pousr]_[A-Za-z0-9]{36,}/, 'GitHub token'],
  [qr/(?<![A-Za-z0-9])github_pat_[A-Za-z0-9_]{40,}/, 'GitHub fine-grained token'],
  [qr/(?<![A-Za-z0-9])AKIA[0-9A-Z]{16}(?![0-9A-Z])/, 'AWS access key'],
  [qr/(?<![A-Za-z0-9])AIza[0-9A-Za-z_-]{35}(?![0-9A-Za-z_-])/, 'Google API key'],
  [qr/(?<![A-Za-z0-9])xox[abprs]-[A-Za-z0-9-]{10,}/, 'Slack token'],
  [qr/-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----/, 'private key'],
);

# Credentials assigned to a name that contains a credential word, also as
# part of a longer name (DB_PASSWORD, client_secret). Names are capped at 64
# characters and must start at a name boundary, so long lines stay fast.
# Groups: 1 the text before the value, 2 the name, 3 the value.
my $kw = qr/password|passwd|pwd|secret|api_?key|apikey|access_?token|auth_?token|private_?key|client_?secret|secret_?key/i;
my $quoted_cred = qr/((?<![A-Za-z0-9_.-])([A-Za-z0-9_.-]{0,64}?(?:$kw)[A-Za-z0-9_.-]{0,64})["']?\s*[:=]\s*["'])([^"'\s]{8,})(?=["'])/;
my $env_cred = qr/^(\s*(?:export\s+)?([A-Za-z0-9_]{0,64}?(?:$kw|(?i:token))[A-Za-z0-9_]{0,64})\s*=\s*)([^\s#"']{8,})/;

# A name that points at a secret (a path, a file, a helper command) is not
# a secret itself, and neither is a value that is a path or a file name.
sub cred_is_real {
  my ($name, $value) = @_;
  return 0 if $name =~ /(?:path|file|helper|dir)$/i;
  return 0 if $value =~ /^(?:[.\/~\$<{]|[A-Za-z]:\\)/;
  return 0 if $value =~ /\.(?:pem|key|crt|cer|p12|pfx|sh|ps1|json|txt|ya?ml|env|cfg|conf)$/i;
  return 1;
}

my $email_re = qr/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/;
my $asset_ext = qr/png|jpe?g|gif|svg|webp|ico|bmp|avif|tgz|tar|gz|zip|whl|jar|js|mjs|cjs|css/;

sub email_ok {
  my ($e) = @_;
  my $l = lc $e;
  my ($local, $domain) = split /\@/, $l, 2;
  # an image scale or a package version, not a mail domain: logo@2x.png, pkg@1.2.3.tgz
  return 1 if $domain =~ /^(?:\d+(?:\.\d+)?x|\d+(?:\.\d+)+)\.(?:$asset_ext)$/;
  return 1 if $local eq 'git';    # git@host:org/repo.git
  return 1 if $domain =~ /(?:^|\.)(?:example\.(?:com|org|net)|invalid|test|example|localhost)$/;
  return 1 if $domain eq 'users.noreply.github.com';
  return 1 if $l eq 'noreply@anthropic.com' || $l eq 'noreply@github.com';
  return 0;
}

# Phone numbers in international format: +, a country code (no leading 0),
# then groups of digits split by spaces, dashes or brackets. Flag when some
# prefix ending at a group boundary holds 10 to 15 digits (E.164), so a
# number followed by other figures is still caught.
sub phone_hits {
  my ($line) = @_;
  my @hits;
  while ($line =~ /(?<![\w.+\/=])(\+[1-9]\d{0,2}(?:(?:[ -]|\)\s?|\s?\()?\d{1,4}){1,8})/g) {
    my $span = $1;
    my ($digits, $hit) = (0, 0);
    for my $g ($span =~ /(\d+)/g) {
      $digits += length $g;
      if ($digits >= 10 && $digits <= 15) { $hit = 1; last }
      last if $digits > 15;
    }
    push @hits, $span if $hit;
  }
  return @hits;
}

# IBAN length by country (SWIFT IBAN registry). A candidate is checked at
# exactly its country's length and must end there, so trailing text cannot
# hide it and hexadecimal hashes do not pass.
my %iban_len = (
  AD => 24, AE => 23, AL => 28, AT => 20, AZ => 28, BA => 20, BE => 16, BG => 22, BH => 22,
  BI => 27, BR => 29, BY => 28, CH => 21, CR => 22, CY => 28, CZ => 24, DE => 22, DJ => 27,
  DK => 18, DO => 28, EE => 20, EG => 29, ES => 24, FI => 18, FK => 18, FO => 18, FR => 27,
  GB => 22, GE => 22, GI => 23, GL => 18, GR => 27, GT => 28, HN => 28, HR => 21, HU => 28,
  IE => 22, IL => 23, IQ => 23, IS => 26, IT => 27, JO => 30, KW => 30, KZ => 20, LB => 28,
  LC => 32, LI => 21, LT => 20, LU => 20, LV => 21, LY => 25, MC => 27, MD => 24, ME => 22,
  MK => 19, MN => 20, MR => 27, MT => 31, MU => 30, NI => 28, NL => 18, NO => 15, OM => 23,
  PK => 24, PL => 28, PS => 29, PT => 25, QA => 29, RO => 24, RS => 22, RU => 33, SA => 24,
  SC => 31, SD => 18, SE => 24, SI => 19, SK => 24, SM => 27, SO => 23, ST => 25, SV => 28,
  TL => 23, TN => 24, TR => 26, UA => 29, VA => 22, VG => 24, XK => 20, YE => 30,
);

sub iban_checksum_ok {
  my ($s) = @_;
  my $r = substr($s, 4) . substr($s, 0, 4);
  my $m = 0;
  for my $ch (split //, $r) {
    my $v = $ch =~ /[A-Z]/ ? ord($ch) - 55 : $ch;
    $m = ($m * 10 + $_) % 97 for split //, $v;
  }
  return $m == 1;
}

sub iban_hits {
  my ($line) = @_;
  my @hits;
  while ($line =~ /(?<![A-Za-z0-9])([A-Z]{2})(?=\d{2})/g) {
    my $len = $iban_len{$1} or next;
    my $rest = $len - 4;
    # exactly the country's length, in one block or in spaced groups, and
    # not running on into more letters or digits (a longer hash)
    next unless substr($line, pos($line) - 2) =~ /^([A-Z]{2}\d{2}(?: ?[A-Z0-9]){$rest})(?![A-Za-z0-9])/;
    (my $cand = $1) =~ s/ //g;
    next unless ($cand =~ tr/0-9//) >= 8;
    push @hits, $cand if iban_checksum_ok($cand);
  }
  return @hits;
}

# A finding is shown by its kind and length only. A key or token of 20 or
# more characters also keeps its first 4, which name the kind (sk-a, ghp_,
# AKIA) without giving the key away.
sub mask {
  my ($s, $is_token) = @_;
  my $len = length $s;
  return substr($s, 0, 4) . "...($len chars)" if $is_token && $len >= 20;
  return "***($len chars)";
}

# --mask: a filter for other tools' output.
if ($mask_mode) {
  while (my $line = <STDIN>) {
    $line =~ s/\r?\n\z//;
    for my $r (@token_rules) { $line =~ s/($r->[0])/mask($1, 1)/ge }
    $line =~ s/$quoted_cred/$1 . mask($3, 0)/ge;
    $line =~ s/$env_cred/$1 . mask($3, 0)/e;
    $line =~ s/($email_re)/email_ok($1) ? $1 : mask($1, 0)/ge;
    say_line("  $line");
  }
  exit 0;
}

my $allow_file = shift @ARGV;
die "secrets: usage: secrets.pl [--staged] [--ids] ALLOW_FILE FILE...\n" unless defined $allow_file;

# The allowlist: PATH<TAB>ID<TAB>REASON. Errors name the line, never its text.
my (%allow, @allow_lines);
if (-f $allow_file) {
  open my $a, '<', $allow_file or die "secrets: cannot read $allow_file\n";
  my $ln = 0;
  while (my $l = <$a>) {
    $ln++;
    $l =~ s/\r?\n\z//;
    next if $l =~ /^\s*(?:#|$)/;
    my ($path, $id, $reason) = split /\t/, $l, 3;
    die "secrets: $allow_file line $ln is not PATH<TAB>ID<TAB>REASON with a 12-character ID and a reason\n"
      unless defined $reason && $reason =~ /\S/ && $id =~ /^[0-9a-f]{12}$/ && length $path;
    $allow{$path}{$id} = $ln;
    push @allow_lines, [$ln, $path, $id];
  }
}
my %allow_used;

# The ID of TEXT found in PATH: the start of git's object ID for
# "PATH\0TEXT". git hash-object reads it from a pipe, so the text never
# touches the disk.
my %id_cache;
sub allow_id {
  my ($path, $text) = @_;
  my $key = "$path\0$text";
  return $id_cache{$key} if exists $id_cache{$key};
  my $pid = open2(my $out, my $in, 'git', 'hash-object', '--stdin');
  binmode $in;
  print $in $key;
  close $in;
  my $oid = <$out>;
  close $out;
  waitpid $pid, 0;
  die "secrets: git hash-object did not run\n" unless defined $oid && $oid =~ /^([0-9a-f]{12})/;
  return $id_cache{$key} = $1;
}

my ($examined, $bad, $allowed_hits, $skipped, $staged_examined) = (0, 0, 0, 0, 0);
my @skipped_names;

# report PATH WHERE KIND TEXT IS_TOKEN SEEN SKIP_SEEN
sub report {
  my ($path, $where, $kind, $text, $is_token, $seen, $skip_seen) = @_;
  return if $skip_seen && $seen->{$text};
  $seen->{$text} = 1;
  if ($allow{$path}) {
    my $id = allow_id($path, $text);
    if (exists $allow{$path}{$id}) {
      $allow_used{"$path\t$id"} = 1;
      $allowed_hits++;
      return;
    }
  }
  my $tail = $show_ids ? ' [id ' . allow_id($path, $text) . ']' : '';
  say_line("secrets: $where: $kind: " . mask($text, $is_token) . $tail);
  $bad++;
}

# Every rule on one line of text.
sub scan_line {
  my ($path, $where, $line, $seen, $skip_seen) = @_;
  for my $r (@token_rules) {
    while ($line =~ /($r->[0])/g) { report($path, $where, $r->[1], $1, 1, $seen, $skip_seen) }
  }
  while ($line =~ /$quoted_cred/g) {
    my ($name, $value) = ($2, $3);
    report($path, $where, 'hard-coded credential', $value, 0, $seen, $skip_seen) if cred_is_real($name, $value);
  }
  if ($line =~ /$env_cred/) {
    my ($name, $value) = ($2, $3);
    report($path, $where, 'credential in an env-style assignment', $value, 0, $seen, $skip_seen) if cred_is_real($name, $value);
  }
  while ($line =~ /($email_re)/g) {
    my $e = $1;
    report($path, $where, 'email address (personal data)', $e, 0, $seen, $skip_seen) unless email_ok($e);
  }
  report($path, $where, 'phone number (personal data)', $_, 0, $seen, $skip_seen) for phone_hits($line);
  report($path, $where, 'bank account number (IBAN)', $_, 0, $seen, $skip_seen) for iban_hits($line);
}

# The runs of printable bytes in raw content, with every rule or keys only.
sub scan_runs {
  my ($path, $label, $raw, $seen, $all_rules) = @_;
  for my $run ($raw =~ /([\x20-\x7E]{16,})/g) {
    if ($all_rules) {
      scan_line($path, "$label (raw bytes)", $run, $seen, 1);
      next;
    }
    for my $r (@token_rules) {
      while ($run =~ /($r->[0])/g) { report($path, "$label (binary)", $r->[1], $1, 1, $seen, 1) }
    }
  }
}

sub share_nul {
  my ($head, $start) = @_;
  my ($all, $nul) = (0, 0);
  for (my $i = $start; $i < length $head; $i += 2) { $all++; $nul++ if substr($head, $i, 1) eq "\0" }
  return $all ? $nul / $all : 0;
}

# UTF-16 to text without the Encode module (Git for Windows' perl may lack it).
# Characters outside the BMP come out as two surrogate code points, which
# does not matter for this scan.
sub utf16 {
  my ($bytes, $order) = @_;
  $bytes = substr($bytes, 0, length($bytes) - length($bytes) % 2);
  return join '', map { chr } unpack($order eq 'LE' ? 'v*' : 'n*', $bytes);
}

# Returns (text, kind, raw): raw is set whenever the bytes hold a NUL.
sub classify {
  my ($bytes) = @_;
  my $raw = index($bytes, "\0") >= 0 ? $bytes : undef;
  return (utf16(substr($bytes, 2), 'LE'), 'text', $raw) if $bytes =~ /^\xFF\xFE/;
  return (utf16(substr($bytes, 2), 'BE'), 'text', $raw) if $bytes =~ /^\xFE\xFF/;
  if (defined $raw) {
    my $head = substr($bytes, 0, 4096);
    return (utf16($bytes, 'LE'), 'text', $raw) if share_nul($head, 1) > 0.9;
    return (utf16($bytes, 'BE'), 'text', $raw) if share_nul($head, 0) > 0.9;
    return (undef, 'binary', $raw);
  }
  return ($bytes, 'text', undef);
}

sub scan_content {
  my ($path, $label, $bytes) = @_;
  my ($text, $kind, $raw) = classify($bytes);
  my %seen;
  if ($kind eq 'binary') {
    $skipped++;
    push @skipped_names, $label;
    say_line("NOTE skipped binary file $label");
    scan_runs($path, $label, $raw, \%seen, 0);
    return;
  }
  $examined++;
  my $n = 0;
  for my $line (split /\r\n|\r|\n/, $text) {
    $n++;
    scan_line($path, "$label:$n", $line, \%seen, 0);
  }
  scan_runs($path, $label, $raw, \%seen, 1) if defined $raw;
}

sub read_raw {
  my ($file) = @_;
  open my $fh, '<:raw', $file or return undef;
  local $/;
  my $bytes = <$fh>;
  close $fh;
  return defined $bytes ? $bytes : '';
}

for my $file (@ARGV) {
  my $bytes = read_raw($file);
  if (!defined $bytes) { say_line("secrets: cannot read $file"); $bad++; next; }
  scan_content($file, $file, $bytes);
}

# Staged copies that differ from the working tree.
if ($staged) {
  my %differs;
  {
    local $/ = "\0";
    open my $d, '-|', 'git', 'diff', '--name-only', '-z' or die "secrets: git diff did not run\n";
    while (my $p = <$d>) { chomp $p; $differs{$p} = 1 }
    close $d or die "secrets: git diff failed\n";
  }
  if (%differs) {
    local $/ = "\0";
    open my $l, '-|', 'git', 'ls-files', '-s', '-z' or die "secrets: git ls-files did not run\n";
    my @blobs;
    while (my $e = <$l>) {
      chomp $e;
      my ($meta, $path) = split /\t/, $e, 2;
      my ($mode, $oid) = split / /, $meta;
      push @blobs, [$path, $oid] if $differs{$path} && $mode ne '160000';
    }
    close $l or die "secrets: git ls-files failed\n";
    for my $b (@blobs) {
      my ($path, $oid) = @$b;
      local $/;
      open my $c, '-|', 'git', 'cat-file', 'blob', $oid or die "secrets: git cat-file did not run\n";
      binmode $c;
      my $bytes = <$c>;
      close $c or die "secrets: git cat-file failed\n";
      my $before = $examined;
      scan_content($path, "$path (staged)", defined $bytes ? $bytes : '');
      $staged_examined += $examined - $before;
    }
  }
}

for my $e (@allow_lines) {
  my ($ln, $path, $id) = @$e;
  say_line("NOTE $allow_file line $ln matched nothing; remove it if the text is gone") unless $allow_used{"$path\t$id"};
}

my @shown = map { esc($_) } @skipped_names[0 .. ($#skipped_names < 4 ? $#skipped_names : 4)];
$examined -= $staged_examined;
print "EXAMINED $examined\nSTAGED $staged_examined\nBAD $bad\nALLOWED $allowed_hits\nSKIPPED $skipped\nSKIPPED_NAMES "
  . join(', ', @shown) . ($skipped > 5 ? ', ...' : '') . "\n";
