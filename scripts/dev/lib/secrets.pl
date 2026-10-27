#!/usr/bin/env perl
# Scans files for secrets and personal data. Called by scripts/dev/scan-secrets.sh.
# Usage: perl secrets.pl ALLOW_FILE FILE...
# Prints one line per finding (masked, never in full), one NOTE line per
# skipped binary file, then "EXAMINED n", "BAD n" and "SKIPPED n".
#
# Text in UTF-16 (the default output of Windows PowerShell 5.1) is decoded
# before scanning, so it cannot hide a secret.
use strict;
use warnings;
use Encode qw(decode);

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

my $kw = qr/password|passwd|pwd|secret|api_?key|apikey|access_?token|auth_?token|private_?key|client_?secret|secret_?key/i;
my @secret_rules = (
  [qr/sk-ant-[A-Za-z0-9_-]{20,}/, 'Anthropic API key'],
  [qr/(?<![A-Za-z0-9])sk-(?:proj-)?[A-Za-z0-9]{32,}/, 'OpenAI-style API key'],
  [qr/(?<![A-Za-z0-9])gh[pousr]_[A-Za-z0-9]{36,}/, 'GitHub token'],
  [qr/(?<![A-Za-z0-9])github_pat_[A-Za-z0-9_]{40,}/, 'GitHub fine-grained token'],
  [qr/(?<![A-Za-z0-9])AKIA[0-9A-Z]{16}(?![0-9A-Z])/, 'AWS access key'],
  [qr/(?<![A-Za-z0-9])AIza[0-9A-Za-z_-]{35}(?![0-9A-Za-z_-])/, 'Google API key'],
  [qr/(?<![A-Za-z0-9])xox[abprs]-[A-Za-z0-9-]{10,}/, 'Slack token'],
  [qr/-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----/, 'private key'],
  # name contains a credential word (also as part of a longer name such as
  # DB_PASSWORD or client_secret), value quoted
  [qr/(?<![A-Za-z0-9])[A-Za-z0-9_.-]*(?:$kw)[A-Za-z0-9_.-]*["']?\s*[:=]\s*["'][^"'\s]{8,}["']/, 'hard-coded credential'],
  # env-file style: NAME=value without quotes
  [qr/^\s*(?:export\s+)?[A-Za-z0-9_]*(?:$kw|(?i:token))[A-Za-z0-9_]*\s*=\s*(?![\$<{"'\/.~])[^\s#]{8,}/, 'credential in an env-style assignment'],
);

my $email_re = qr/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/;
my $file_ext = qr/png|jpe?g|gif|svg|webp|ico|bmp|tgz|gz|bz2|xz|zip|tar|js|mjs|cjs|ts|tsx|jsx|css|scss|json|md|html?|txt|pdf|ya?ml|lock|wasm|map|py|rb|go|rs|sh/;

sub email_ok {
  my ($e) = @_;
  my $l = lc $e;
  my ($local, $domain) = split /\@/, $l, 2;
  return 1 if $domain =~ /\.(?:$file_ext)$/;      # logo@2x.png, pkg@1.2.3.tgz
  return 1 if $local eq 'git';                     # git@host:org/repo.git
  return 1 if $domain =~ /(?:^|\.)(?:example\.(?:com|org|net)|invalid|test|example|localhost)$/;
  return 1 if $domain eq 'users.noreply.github.com';
  return 1 if $l eq 'noreply@anthropic.com' || $l eq 'noreply@github.com';
  return 0;
}

# Phone numbers in international format: +, country code, then groups of
# digits split by spaces, dots, dashes or brackets. Flag when some prefix
# ending at a group boundary holds 10 to 15 digits (E.164 length), so a
# number followed by other figures is still caught.
sub phone_hits {
  my ($line) = @_;
  my @hits;
  while ($line =~ /(?<![\w.+\/=])(\+\d{1,3}(?:(?:[ .-]|\)\s?|\s?\()?\d{1,4}){1,8})/g) {
    my $span = $1;
    my @groups = $span =~ /(\d+)/g;
    my ($digits, $hit) = (0, 0);
    for my $g (@groups) {
      $digits += length $g;
      if ($digits >= 10 && $digits <= 15) { $hit = 1; last }
      last if $digits > 15;
    }
    push @hits, $span if $hit;
  }
  return @hits;
}

sub iban_valid {
  my ($s) = @_;
  return 0 if length($s) < 15 || length($s) > 34;
  return 0 unless ($s =~ tr/0-9//) >= 8;
  my $r = substr($s, 4) . substr($s, 0, 4);
  my $m = 0;
  for my $ch (split //, $r) {
    my $v = $ch =~ /[A-Z]/ ? ord($ch) - 55 : $ch;
    $m = ($m * 10 + $_) % 97 for split //, $v;
  }
  return $m == 1;
}

# IBANs: try every length from 15 to 34 characters (spaces ignored), so
# trailing words or numbers do not hide a valid account number.
sub iban_hits {
  my ($line) = @_;
  my @hits;
  while ($line =~ /(?<![A-Za-z0-9])([A-Z]{2}\d{2}(?: ?[A-Z0-9]){11,40})/g) {
    my $span = $1;
    (my $compact = $span) =~ s/ //g;
    for my $len (reverse 15 .. (length($compact) < 34 ? length($compact) : 34)) {
      my $cand = substr($compact, 0, $len);
      if (iban_valid($cand)) { push @hits, $cand; last }
    }
  }
  return @hits;
}

sub mask {
  my ($s) = @_;
  return length($s) <= 6 ? '***' : substr($s, 0, 6) . '...(' . length($s) . ' chars)';
}

sub read_text {
  my ($file) = @_;
  open my $fh, '<:raw', $file or return (undef, 'unreadable');
  local $/;
  my $bytes = <$fh>;
  close $fh;
  $bytes = '' unless defined $bytes;
  if ($bytes =~ /^\xFF\xFE/) { return (decode('UTF-16LE', substr($bytes, 2)), 'utf16') }
  if ($bytes =~ /^\xFE\xFF/) { return (decode('UTF-16BE', substr($bytes, 2)), 'utf16') }
  if (index($bytes, "\0") >= 0) {
    my $head = substr($bytes, 0, 4096);
    my ($odd, $odd_nul) = (0, 0);
    for (my $i = 1; $i < length $head; $i += 2) { $odd++; $odd_nul++ if substr($head, $i, 1) eq "\0" }
    return (decode('UTF-16LE', $bytes), 'utf16') if $odd && $odd_nul / $odd > 0.9;
    return (undef, 'binary');
  }
  return ($bytes, 'text');
}

my ($examined, $bad, $skipped) = (0, 0, 0);
for my $file (@ARGV) {
  my ($text, $kind) = read_text($file);
  if (!defined $text) {
    if ($kind eq 'binary') { print "NOTE skipped binary file $file\n"; $skipped++; }
    else { print "secrets: cannot read $file\n"; $bad++; }
    next;
  }
  $examined++;
  my $n = 0;
  for my $line (split /\n/, $text) {
    $n++;
    for my $r (@secret_rules) {
      while ($line =~ /($r->[0])/g) {
        next if $allowed{$1};
        print "secrets: $file:$n: $r->[1]: " . mask($1) . "\n";
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
}
print "EXAMINED $examined\nBAD $bad\nSKIPPED $skipped\n";
