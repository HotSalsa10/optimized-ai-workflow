#!/usr/bin/env perl
# Early warning for shell constructs that break on macOS (bash 3.2, BSD
# tools) or on Git Bash for Windows. Called by scripts/dev/lint-portability.sh.
# Usage: perl portability.pl FILE...
# Prints one line per problem, then "EXAMINED n" and "BAD n".
#
# This is a best-effort lint, not a shell parser. The real proof is the test
# suite running on macOS and Windows in CI.
#
# Each line is read through a small scanner that produces:
#   raw       the line as written
#   nosingle  single-quoted text blanked (single quotes do not expand)
#   code      quoted literal text, arithmetic $(( )) and comments blanked, with
#             the contents of $( ) and backticks kept as code even inside
#             double quotes
# and reports whether a $( ) is left open at the end of the line.
use strict;
use warnings;

sub scan_line {
  my ($line) = @_;
  chomp $line;
  my @c = split //, $line;
  my ($code, $in_s, $in_d, $in_bq, $bq_d) = ('', 0, 0, 0, 0);
  my @stack;    # entries: [type, in_d_before, start_in_code]
  for (my $i = 0; $i < @c; $i++) {
    my $ch = $c[$i];
    if ($in_s) {
      if ($ch eq "'") { $in_s = 0; $code .= "'" } else { $code .= ' ' }
      next;
    }
    if ($ch eq '\\') { $code .= '  '; $i++; next; }
    if ($ch eq "'" && !$in_d) { $in_s = 1; $code .= "'"; next; }
    if ($ch eq '`') {    # backticks: their contents are code, also inside double quotes
      if ($in_bq) { $in_bq = 0; $in_d = $bq_d } else { $in_bq = 1; $bq_d = $in_d; $in_d = 0 }
      $code .= '`';
      next;
    }
    if ($ch eq '"') { $in_d = !$in_d; $code .= '"'; next; }
    if ($ch eq '$' && ($c[$i + 1] // '') eq '(') {
      if (($c[$i + 2] // '') eq '(') {    # arithmetic $(( )): blank it
        my $depth = 0;
        my $j = $i + 1;
        for (; $j < @c; $j++) {
          $depth++ if $c[$j] eq '(';
          $depth-- if $c[$j] eq ')';
          last if $depth == 0;
        }
        $code .= '$((' . (' ' x ($j - $i - 4 > 0 ? $j - $i - 4 : 0)) . '))';
        $i = $j;
        next;
      }
      push @stack, ['sub', $in_d, length($code) + 2];
      $code .= '$(';
      $in_d = 0;
      $i++;
      next;
    }
    if ($in_d) { $code .= ' '; next; }    # literal text inside double quotes
    if ($ch eq '#' && ($i == 0 || $c[$i - 1] =~ /\s/)) { last; }    # comment
    if ($ch eq '(') { push @stack, ['paren', 0, 0]; $code .= '('; next; }
    if ($ch eq ')') {
      my $top = pop @stack;
      $in_d = $top->[1] if $top && $top->[0] eq 'sub';
      $code .= ')';
      next;
    }
    $code .= $ch;
  }
  my @open = grep { $_->[0] eq 'sub' } @stack;
  my $open_tail = @open ? substr($code, $open[0][2]) : undef;
  (my $nosingle = $line) =~ s/'[^']*'/''/g;
  return ($nosingle, $code, $open_tail);
}

# Command words that start a command: at the start of a line (indented or
# not), after ; & | ( ! { ` and $(, and after shell keywords.
my $cmd_start = qr/(?:^\s*|[;&|(!{`]\s*|\$\(\s*|\b(?:if|elif|while|until|then|do|else|time|command|exec|xargs)\s+)/;

my @rules = (
  # bash 4 and later
  ['nosingle', qr/\b(?:declare|local|typeset)\s+-[a-zA-Z]*A/, 'associative arrays need bash 4'],
  ['nosingle', qr/\b(?:declare|local|typeset)\s+-[a-zA-Z]*n\b/, 'namerefs need bash 4.3'],
  ['nosingle', qr/\b(?:declare|local|typeset)\s+-[a-zA-Z]*g/, 'declare -g needs bash 4.2'],
  ['nosingle', qr/\b(?:declare|local|typeset)\s+-[a-zA-Z]*[lu]\b/, 'declare -l/-u (case attributes) needs bash 4'],
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
  ['code', qr/\{0\d+\.\.\d+\}/, 'zero-padded brace ranges need bash 4'],
  ['code', qr/\bshopt\s+-s\s+(?:globstar|lastpipe|autocd|direxpand|inherit_errexit|localvar_inherit)\b/, 'this shopt option needs bash 4 or later'],
  ['nosingle', qr/\$\{?(?:EPOCHSECONDS|EPOCHREALTIME|BASHPID)\b/, 'this variable needs bash 4 or 5'],
  ['code', qr/\bread\b[^;|&]*\s-[a-zA-Z]*i\b/, 'read -i needs bash 4'],
  ['code', qr/(?<!\$)\{[A-Za-z_][A-Za-z0-9_]*\}[<>]/, 'named file descriptors {fd}> need bash 4.1'],
  ['raw', qr/\bprintf\b.*%\([^)]*\)T/, 'printf %(...)T needs bash 4.2'],
  # GNU-only flags, wherever they appear among the options
  ['code', qr/\bsed\b[^|;&]*\s(?:-[a-zA-Z]*i|--in-place)/, 'sed -i differs between GNU and BSD; write to a temp file and mv'],
  ['code', qr/\bsed\b[^|;&]*\s(?:-[a-zA-Z]*r|--regexp-extended)/, 'sed -r is GNU only; use sed -E'],
  ['code', qr/\bgrep\b[^|;&]*\s(?:-[a-zA-Z]*P|--perl-regexp)/, 'grep -P is GNU only; use perl'],
  ['code', qr/\breadlink\b[^|;&]*\s-[a-zA-Z]*f/, 'readlink -f is missing on older macOS'],
  ['code', qr/\bdate\b[^|;&]*\s(?:-d|--date)/, 'date -d is GNU only'],
  ['code', qr/\bstat\b[^|;&]*\s(?:-c|--format|--printf)/, 'stat -c is GNU only'],
  ['code', qr/\bxargs\b[^|;&]*\s(?:-[a-zA-Z0-9]*r|--no-run-if-empty)/, 'xargs -r is GNU only'],
  ['code', qr/\bfind\b[^|;&]*\s-printf\b/, 'find -printf is GNU only'],
  ['code', qr/\bsort\b[^|;&]*\s(?:-[a-zA-Z0-9,]*V|--version-sort)/, 'sort -V is GNU only'],
  ['code', qr/\bbase64\b[^|;&]*\s-w/, 'base64 -w is GNU only'],
  ['code', qr/\b(?:head|tail)\b[^|;&]*\s-n\s*-\d/, 'a negative head/tail count is GNU only'],
  ['code', qr/${cmd_start}(?:tac|sha256sum|sha1sum|md5sum|timeout|nproc)(?![\w-])/, 'this command is missing on macOS by default'],
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
    my ($nosingle, $code, $open_tail) = scan_line($line);
    my %view = (raw => $line, nosingle => $nosingle, code => $code);
    for my $r (@rules) {
      if ($view{$r->[0]} =~ $r->[1]) {
        print "portability: $file:$n: $r->[2]\n";
        $bad++;
      }
    }
    # bash 3.2 reads $( ) by matching brackets and quotes, not by parsing, so
    # a $( ) that runs onto later lines can break, worst with a here-doc or a
    # case statement inside. Keep every $( ) on one line.
    if (defined $open_tail) {
      if ($open_tail =~ /(?<!<)<<(?!<)/) {
        print "portability: $file:$n: a here-doc inside \$( ) can fail to parse on bash 3.2; move the text to a file\n";
      } elsif ($open_tail =~ /\bcase\b/) {
        print "portability: $file:$n: a case statement inside \$( ) can fail to parse on bash 3.2\n";
      } else {
        print "portability: $file:$n: a \$( ) that continues onto the next line can fail to parse on bash 3.2; keep it on one line\n";
      }
      $bad++;
    }
  }
}
print "EXAMINED $examined\nBAD $bad\n";
