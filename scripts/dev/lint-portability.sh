#!/usr/bin/env bash
# Fails when a tracked shell script uses something that breaks on macOS
# (bash 3.2, BSD tools) or on Git Bash for Windows: bash 4+ features and
# GNU-only tool flags. Lines that start with # are not checked.
# This file is not scanned itself: it has to name the patterns it looks for.
set -u

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "portability: FAIL - not inside a git repository"
  exit 2
}
cd "$root" || exit 2
command -v perl >/dev/null 2>&1 || {
  echo "portability: FAIL - perl is not installed"
  exit 2
}

self="scripts/dev/lint-portability.sh"

prog=$(cat <<'PERL'
use strict;
use warnings;
my $self = shift @ARGV;
my @rules = (
  [qr/\b(?:declare|local|typeset)\s+-[a-zA-Z]*A/, 'associative arrays need bash 4'],
  [qr/\b(?:declare|local|typeset)\s+-[a-zA-Z]*n\b/, 'namerefs need bash 4.3'],
  [qr/\b(?:mapfile|readarray)\b/, 'mapfile/readarray need bash 4'],
  [qr/\$\{[A-Za-z_][A-Za-z0-9_]*(?:,,?|\^\^?)\}/, 'case conversion ${x,,} needs bash 4'],
  [qr/\$\{[A-Za-z_][A-Za-z0-9_]*@[QEPAaUuLK]\}/, '${x@Q} needs bash 4.4'],
  [qr/\$\{[A-Za-z_][A-Za-z0-9_]*\[-\d+\]\}/, 'negative array index needs bash 4.3'],
  [qr/(?<![|&])\|&/, '|& needs bash 4'],
  [qr/&>>/, '&>> needs bash 4'],
  [qr/\bcoproc\b/, 'coproc needs bash 4'],
  [qr/\bwait\s+-n\b/, 'wait -n needs bash 4.3'],
  [qr/\[\[\s+-v\s/, '[[ -v ]] needs bash 4.2'],
  [qr/\{\d+\.\.\d+\.\.\d+\}/, 'stepped brace ranges need bash 4'],
  [qr/\bshopt\s+-s\s+(?:globstar|lastpipe|autocd|direxpand)\b/, 'this shopt option needs bash 4'],
  [qr/\$\{?(?:EPOCHSECONDS|EPOCHREALTIME|BASHPID)\b/, 'this variable needs bash 4 or 5'],
  [qr/\bread\b[^;|&]*\s-[a-zA-Z]*i\s/, 'read -i needs bash 4'],
  [qr/\bsed\s+(?:-[a-zA-Z]*i|--in-place)/, 'sed -i differs between GNU and BSD; write to a temp file and mv'],
  [qr/\bsed\s+(?:-[a-zA-Z]*r\b|--regexp-extended)/, 'sed -r is GNU; use sed -E'],
  [qr/\bgrep\s+(?:-[a-zA-Z]*P|--perl-regexp)/, 'grep -P is GNU only; use perl'],
  [qr/\breadlink\s+-[a-zA-Z]*f/, 'readlink -f is missing on older macOS'],
  [qr/\bdate\s+(?:-d\b|--date)/, 'date -d is GNU only'],
  [qr/\bstat\s+(?:-c\b|--format|--printf)/, 'stat -c is GNU only'],
  [qr/\bxargs\s+(?:-[a-zA-Z]*r\b|--no-run-if-empty)/, 'xargs -r is GNU only'],
  [qr/\bfind\b.*\s-printf\b/, 'find -printf is GNU only'],
  [qr/\bsort\s+(?:-[a-zA-Z]*V|--version-sort)/, 'sort -V is GNU only'],
  [qr/\bbase64\s+-w\b/, 'base64 -w is GNU only'],
  [qr/(?:^|[;&|(]\s*|\s)(?:tac|sha256sum|sha1sum|md5sum|timeout)\s/, 'this command is missing on macOS by default'],
);
my ($examined, $bad) = (0, 0);
for my $file (@ARGV) {
  next if $file eq $self;
  open my $fh, '<', $file or do { print "portability: cannot read $file\n"; $bad++; next };
  my $first = <$fh>;
  next unless defined $first;
  my $is_shell = $file =~ /\.(?:sh|bash)$/ || $first =~ /^#!.*\b(?:ba)?sh\b/;
  next unless $is_shell;
  $examined++;
  my $n = 1;
  my $line = $first;
  while (1) {
    if ($line !~ /^\s*#/) {
      for my $r (@rules) {
        if ($line =~ $r->[0]) {
          print "portability: $file:$n: $r->[1]\n";
          $bad++;
        }
      }
    }
    $line = <$fh>;
    last unless defined $line;
    $n++;
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

out=$(perl -e "$prog" "$self" ${files[@]+"${files[@]}"}) || {
  echo "portability: FAIL - the scan itself did not run"
  exit 2
}
examined=$(printf '%s\n' "$out" | sed -n 's/^EXAMINED //p')
bad=$(printf '%s\n' "$out" | sed -n 's/^BAD //p')
printf '%s\n' "$out" | grep -v -e '^EXAMINED ' -e '^BAD '

if [ "${examined:-0}" -eq 0 ]; then
  echo "portability: FAIL - examined 0 shell scripts; nothing was checked"
  exit 1
fi
if [ "${bad:-0}" -gt 0 ]; then
  echo "portability: FAIL - $bad problem(s) in $examined shell scripts"
  exit 1
fi
echo "portability: PASS - examined $examined shell scripts, no bash 4 features or GNU-only flags"
