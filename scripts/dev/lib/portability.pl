#!/usr/bin/env perl
# Scans shell scripts for constructs that break on macOS (bash 3.2, BSD
# tools) or on Git Bash for Windows. Called by scripts/dev/lint-portability.sh.
# Usage: perl portability.pl FILE...
# Prints one line per problem, then "EXAMINED n" and "BAD n".
#
# Each rule looks at one view of the line:
#   raw       the line as written
#   nosingle  single-quoted text blanked (single quotes do not expand)
#   code      all quoted text and trailing comments blanked (for commands
#             and flags, so text inside strings is not mistaken for them)
use strict;
use warnings;

my @rules = (
  # bash 4 and later
  ['nosingle', qr/\b(?:declare|local|typeset)\s+-[a-zA-Z]*A/, 'associative arrays need bash 4'],
  ['nosingle', qr/\b(?:declare|local|typeset)\s+-[a-zA-Z]*n\b/, 'namerefs need bash 4.3'],
  ['nosingle', qr/\b(?:declare|local|typeset)\s+-[a-zA-Z]*g/, 'declare -g needs bash 4.2'],
  ['code', qr/\b(?:mapfile|readarray)\b/, 'mapfile/readarray need bash 4'],
  ['nosingle', qr/\$\{(?:[A-Za-z_][A-Za-z0-9_]*|\d+|[@*])(?:\[[^\]]*\])?(?:,,?|\^\^?)[^}]*\}/, 'case conversion such as ${x,,} needs bash 4'],
  ['nosingle', qr/\$\{[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]*\])?@[QEPAaUuLK]\}/, '${x@Q} needs bash 4.4'],
  ['nosingle', qr/\$\{[A-Za-z_][A-Za-z0-9_]*\[-\d+\]\}/, 'negative array index needs bash 4.3'],
  ['nosingle', qr/\$\{[^}:\s]+:[^}:]*:\s*-\d/, 'negative substring length ${x:0:-1} needs bash 4.2'],
  ['code', qr/(?<![|&])\|&/, '|& needs bash 4'],
  ['code', qr/&>>/, '&>> needs bash 4'],
  ['code', qr/\bcoproc\b/, 'coproc needs bash 4'],
  ['code', qr/\bwait\s+-n\b/, 'wait -n needs bash 4.3'],
  ['code', qr/(?:\[\[?\s+|\btest\s+)-v\s/, 'the -v test needs bash 4.2'],
  ['code', qr/\{\d+\.\.\d+\.\.\d+\}/, 'stepped brace ranges need bash 4'],
  ['code', qr/\bshopt\s+-s\s+(?:globstar|lastpipe|autocd|direxpand)\b/, 'this shopt option needs bash 4'],
  ['nosingle', qr/\$\{?(?:EPOCHSECONDS|EPOCHREALTIME|BASHPID)\b/, 'this variable needs bash 4 or 5'],
  ['code', qr/\bread\b[^;|&]*\s-[a-zA-Z]*i\b/, 'read -i needs bash 4'],
  ['code', qr/(?<!\$)\{[A-Za-z_][A-Za-z0-9_]*\}[<>]/, 'named file descriptors {fd}> need bash 4.1'],
  ['raw', qr/\bprintf\b.*%\([^)]*\)T/, 'printf %(...)T needs bash 4.2'],
  # bash 3.2 parser limits
  ['raw', qr/\$\((?!\()[^)]*<</, 'a here-doc inside $( ) can fail to parse on bash 3.2; move the text to a file'],
  ['raw', qr/\$\((?!\()[^)]*\bcase\b/, 'a case statement inside $( ) can fail to parse on bash 3.2'],
  # GNU-only flags (the flag may come anywhere among the options)
  ['code', qr/\bsed\b[^|;&]*\s(?:-[a-zA-Z]*i\b|--in-place)/, 'sed -i differs between GNU and BSD; write to a temp file and mv'],
  ['code', qr/\bsed\b[^|;&]*\s(?:-[a-zA-Z]*r\b|--regexp-extended)/, 'sed -r is GNU only; use sed -E'],
  ['code', qr/\bgrep\b[^|;&]*\s(?:-[a-zA-Z]*P|--perl-regexp)/, 'grep -P is GNU only; use perl'],
  ['code', qr/\breadlink\b[^|;&]*\s-[a-zA-Z]*f/, 'readlink -f is missing on older macOS'],
  ['code', qr/\bdate\b[^|;&]*\s(?:-d\b|--date)/, 'date -d is GNU only'],
  ['code', qr/\bstat\b[^|;&]*\s(?:-c\b|--format|--printf)/, 'stat -c is GNU only'],
  ['code', qr/\bxargs\b[^|;&]*\s(?:-[a-zA-Z0-9]*r\b|--no-run-if-empty)/, 'xargs -r is GNU only'],
  ['code', qr/\bfind\b[^|;&]*\s-printf\b/, 'find -printf is GNU only'],
  ['code', qr/\bsort\b[^|;&]*\s(?:-[a-zA-Z0-9,]*V|--version-sort)/, 'sort -V is GNU only'],
  ['code', qr/\bbase64\b[^|;&]*\s-w\b/, 'base64 -w is GNU only'],
  ['code', qr/\b(?:head|tail)\b[^|;&]*\s-n\s*-\d/, 'a negative head/tail count is GNU only'],
  ['code', qr/(?:^\s*|[;&|]\s*|\$\(\s*|\b(?:then|do|else|exec|xargs)\s+)(?:tac|sha256sum|sha1sum|md5sum|timeout|nproc)\b/, 'this command is missing on macOS by default'],
);

my ($examined, $bad) = (0, 0);
for my $file (@ARGV) {
  open my $fh, '<', $file or do { print "portability: cannot read $file\n"; $bad++; next };
  my @lines = <$fh>;
  close $fh;
  next unless @lines;
  my $is_shell = $file =~ /\.(?:sh|bash)$/ || $lines[0] =~ /^#!.*\b(?:ba)?sh\b/;
  next unless $is_shell;
  $examined++;
  my $n = 0;
  for my $line (@lines) {
    $n++;
    next if $line =~ /^\s*#/;
    my $nosingle = $line;
    $nosingle =~ s/'[^']*'/''/g;
    my $code = $nosingle;
    $code =~ s/"(?:[^"\\]|\\.)*"/""/g;
    $code =~ s/(?:^|\s)#.*$//;
    my %view = (raw => $line, nosingle => $nosingle, code => $code);
    for my $r (@rules) {
      if ($view{$r->[0]} =~ $r->[1]) {
        print "portability: $file:$n: $r->[2]\n";
        $bad++;
      }
    }
  }
}
print "EXAMINED $examined\nBAD $bad\n";
