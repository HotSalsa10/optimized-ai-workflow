#!/usr/bin/env perl
# Scans files for secrets and personal data. Called by scripts/dev/scan-secrets.sh.
# Usage: perl secrets.pl ALLOW_FILE FILE...
# Prints one line per finding (masked, never in full), one "NOTE skipped
# binary file X" line per binary file, then "EXAMINED n", "BAD n",
# "SKIPPED n" and "SKIPPED_NAMES ...".
#
# Text in UTF-16 (with or without a byte-order mark) is decoded first.
# Binary files are not read as text. In every file that holds a NUL byte
# (binary, or text guessed to be UTF-16), the runs of printable bytes are
# also searched for keys and tokens, so a key cannot hide behind NUL bytes.
use strict;
use warnings;

my $allow_file = shift @ARGV;
my %allowed;
if (-f $allow_file) {
  open my $a, '<', $allow_file or die "cannot read $allow_file\n";
  while (my $l = <$a>) {
    chomp $l;
    $l =~ s/\r$//;
    next if $l =~ /^\s*(?:#|$)/;
    my ($text, $reason) = split /\t/, $l, 2;
    die "scan-allow.txt: every entry needs a reason after a tab: $text\n"
      unless defined $reason && $reason =~ /\S/;
    $allowed{$text} = 1;
  }
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
my $kw = qr/password|passwd|pwd|secret|api_?key|apikey|access_?token|auth_?token|private_?key|client_?secret|secret_?key/i;
my $quoted_cred = qr/(?<![A-Za-z0-9_.-])([A-Za-z0-9_.-]{0,64}?(?:$kw)[A-Za-z0-9_.-]{0,64})["']?\s*[:=]\s*["']([^"'\s]{8,})["']/;
my $env_cred = qr/^\s*(?:export\s+)?([A-Za-z0-9_]{0,64}?(?:$kw|(?i:token))[A-Za-z0-9_]{0,64})\s*=\s*([^\s#"']{8,})/;

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

sub mask {
  my ($s) = @_;
  return length($s) <= 6 ? '***' : substr($s, 0, 6) . '...(' . length($s) . ' chars)';
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

sub read_text {
  my ($file) = @_;
  open my $fh, '<:raw', $file or return (undef, 'unreadable', undef);
  local $/;
  my $bytes = <$fh>;
  close $fh;
  $bytes = '' unless defined $bytes;
  return (utf16(substr($bytes, 2), 'LE'), 'text', undef) if $bytes =~ /^\xFF\xFE/;
  return (utf16(substr($bytes, 2), 'BE'), 'text', undef) if $bytes =~ /^\xFE\xFF/;
  if (index($bytes, "\0") >= 0) {
    my $head = substr($bytes, 0, 4096);
    return (utf16($bytes, 'LE'), 'text', $bytes) if share_nul($head, 1) > 0.9;
    return (utf16($bytes, 'BE'), 'text', $bytes) if share_nul($head, 0) > 0.9;
    return (undef, 'binary', $bytes);
  }
  return ($bytes, 'text', undef);
}

# Keys and tokens in the printable runs of raw bytes; a match already
# reported for this file is not reported again.
sub scan_runs {
  my ($file, $raw, $seen) = @_;
  my $found = 0;
  for my $run ($raw =~ /([\x20-\x7E]{16,})/g) {
    for my $r (@token_rules) {
      while ($run =~ /($r->[0])/g) {
        next if $allowed{$1} || $seen->{$1}++;
        print "secrets: $file (binary): $r->[1]: " . mask($1) . "\n";
        $found++;
      }
    }
  }
  return $found;
}

my ($examined, $bad, $skipped) = (0, 0, 0);
my @skipped_names;
for my $file (@ARGV) {
  my ($text, $kind, $raw) = read_text($file);
  if ($kind eq 'unreadable') { print "secrets: cannot read $file\n"; $bad++; next; }
  if ($kind eq 'binary') {
    $skipped++;
    push @skipped_names, $file;
    print "NOTE skipped binary file $file\n";
    $bad += scan_runs($file, $raw, {});
    next;
  }
  $examined++;
  my %seen;
  my $n = 0;
  for my $line (split /\n/, $text) {
    $n++;
    for my $r (@token_rules) {
      while ($line =~ /($r->[0])/g) {
        next if $allowed{$1};
        $seen{$1}++;
        print "secrets: $file:$n: $r->[1]: " . mask($1) . "\n";
        $bad++;
      }
    }
    while ($line =~ /$quoted_cred/g) {
      my ($name, $value) = ($1, $2);
      next if !cred_is_real($name, $value) || $allowed{$value};
      print "secrets: $file:$n: hard-coded credential: " . mask($value) . "\n";
      $bad++;
    }
    if ($line =~ /$env_cred/) {
      my ($name, $value) = ($1, $2);
      if (cred_is_real($name, $value) && !$allowed{$value}) {
        print "secrets: $file:$n: credential in an env-style assignment: " . mask($value) . "\n";
        $bad++;
      }
    }
    while ($line =~ /($email_re)/g) {
      my $e = $1;
      next if email_ok($e) || $allowed{$e};
      print "secrets: $file:$n: email address (personal data): " . mask($e) . "\n";
      $bad++;
    }
    for my $p (phone_hits($line)) {
      next if $allowed{$p};
      print "secrets: $file:$n: phone number (personal data): " . mask($p) . "\n";
      $bad++;
    }
    for my $i (iban_hits($line)) {
      next if $allowed{$i};
      print "secrets: $file:$n: bank account number (IBAN): " . mask($i) . "\n";
      $bad++;
    }
  }
  $bad += scan_runs($file, $raw, \%seen) if defined $raw;
}
print "EXAMINED $examined\nBAD $bad\nSKIPPED $skipped\nSKIPPED_NAMES " . join(', ', @skipped_names[0 .. ($#skipped_names < 4 ? $#skipped_names : 4)]) . ($skipped > 5 ? ', ...' : '') . "\n";
