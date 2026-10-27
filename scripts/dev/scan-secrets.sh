#!/usr/bin/env bash
# Fails when a tracked file contains something that looks like a secret or
# personal data: API keys and tokens, private keys, personal email addresses,
# phone numbers in international format, and bank account numbers (IBANs that
# pass their checksum). Matches are shown masked, never in full.
# Known false positives go in scripts/dev/scan-allow.txt, one per line:
#   <exact text><TAB><reason>
set -u

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "secrets: FAIL - not inside a git repository"
  exit 2
}
cd "$root" || exit 2
command -v perl >/dev/null 2>&1 || {
  echo "secrets: FAIL - perl is not installed"
  exit 2
}

allow="scripts/dev/scan-allow.txt"

prog=$(cat <<'PERL'
use strict;
use warnings;
my $allow_file = shift @ARGV;
my %allowed;
if (-f $allow_file) {
  open my $a, '<', $allow_file or die "cannot read $allow_file\n";
  while (my $l = <$a>) {
    chomp $l; $l =~ s/\r$//;
    next if $l =~ /^\s*(#|$)/;
    my ($text, $reason) = split /\t/, $l, 2;
    die "scan-allow.txt: every entry needs a reason after a tab: $text\n" unless defined $reason && $reason =~ /\S/;
    $allowed{$text} = 1;
  }
}
my @secret_rules = (
  [qr/sk-ant-[A-Za-z0-9_-]{20,}/, 'Anthropic API key'],
  [qr/\bsk-(?:proj-)?[A-Za-z0-9]{32,}/, 'OpenAI-style API key'],
  [qr/\bgh[pousr]_[A-Za-z0-9]{36,}/, 'GitHub token'],
  [qr/\bgithub_pat_[A-Za-z0-9_]{40,}/, 'GitHub fine-grained token'],
  [qr/\bAKIA[0-9A-Z]{16}\b/, 'AWS access key'],
  [qr/\bAIza[0-9A-Za-z_-]{35}\b/, 'Google API key'],
  [qr/\bxox[abprs]-[A-Za-z0-9-]{10,}/, 'Slack token'],
  [qr/-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----/, 'private key'],
  [qr/(?i:\b(?:password|passwd|secret|api_?key|access_?token|auth_?token)\b)\s*[:=]\s*["'][^"'\s]{8,}["']/, 'hard-coded credential'],
);
my $email_re = qr/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/;
my $phone_re = qr/(?<![\w.+])\+\d{1,3}[ -]?\(?\d{1,4}\)?[ -]?\d{3,4}[ -]?\d{3,4}(?![\d])/;
my $iban_re = qr/\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]){11,30}\b/;
sub email_ok {
  my ($e) = @_;
  my $l = lc $e;
  return 1 if $l =~ /\@(?:[a-z0-9-]+\.)*(?:example\.(?:com|org|net)|invalid|test|example|localhost)$/;
  return 1 if $l =~ /\.(?:invalid|test|example)$/;
  return 1 if $l =~ /\@users\.noreply\.github\.com$/;
  return 1 if $l eq 'noreply@anthropic.com' || $l eq 'noreply@github.com' || $l eq 'git@github.com';
  return 0;
}
sub iban_valid {
  my ($s) = @_;
  $s =~ s/ //g;
  return 0 if length($s) < 15 || length($s) > 34;
  return 0 unless ($s =~ tr/0-9//) >= 8;
  my $r = substr($s, 4) . substr($s, 0, 4);
  my $num = join '', map { /[A-Z]/ ? ord($_) - 55 : $_ } split //, $r;
  my $m = 0;
  $m = ($m * 10 + $_) % 97 for split //, $num;
  return $m == 1;
}
sub mask { my ($s) = @_; return length($s) <= 6 ? '***' : substr($s, 0, 6) . '...(' . length($s) . ' chars)'; }
my ($examined, $bad) = (0, 0);
for my $file (@ARGV) {
  next if -B $file;
  open my $fh, '<', $file or do { print "secrets: cannot read $file\n"; $bad++; next };
  $examined++;
  my $n = 0;
  while (my $line = <$fh>) {
    $n++;
    for my $r (@secret_rules) {
      while ($line =~ /($r->[0])/g) {
        next if $allowed{$1};
        print "secrets: $file:$n: $r->[1]: " . mask($1) . "\n"; $bad++;
      }
    }
    while ($line =~ /($email_re)/g) {
      my $e = $1;
      next if email_ok($e) || $allowed{$e};
      print "secrets: $file:$n: email address (personal data): " . mask($e) . "\n"; $bad++;
    }
    while ($line =~ /($phone_re)/g) {
      next if $allowed{$1};
      print "secrets: $file:$n: phone number (personal data): " . mask($1) . "\n"; $bad++;
    }
    while ($line =~ /($iban_re)/g) {
      my $i = $1;
      next unless iban_valid($i);
      next if $allowed{$i};
      print "secrets: $file:$n: bank account number (IBAN): " . mask($i) . "\n"; $bad++;
    }
  }
  close $fh;
}
print "EXAMINED $examined\nBAD $bad\n";
PERL
)

files=()
while IFS= read -r -d '' f; do
  [ -f "$f" ] && files+=("$f")
done < <(git ls-files -z)

out=$(perl -e "$prog" "$allow" ${files[@]+"${files[@]}"}) || {
  echo "secrets: FAIL - the scan itself did not run: $out"
  exit 2
}
examined=$(printf '%s\n' "$out" | sed -n 's/^EXAMINED //p')
bad=$(printf '%s\n' "$out" | sed -n 's/^BAD //p')
printf '%s\n' "$out" | grep -v -e '^EXAMINED ' -e '^BAD '

if [ "${examined:-0}" -eq 0 ]; then
  echo "secrets: FAIL - examined 0 tracked text files; nothing was checked"
  exit 1
fi
if [ "${bad:-0}" -gt 0 ]; then
  echo "secrets: FAIL - $bad finding(s) in $examined tracked text files"
  exit 1
fi
echo "secrets: PASS - examined $examined tracked text files, no secrets or personal data found"
