#!/usr/bin/env perl
# The method's one line escaper (M048), loaded with require by the perl
# helpers. Every line they print that holds text taken from a repository
# (file contents, file and branch names, settings, commit messages) goes
# through Esc::line, so no such text can hide, reorder or split a line.
#
# Esc::line(BYTES): each byte that is not part of valid UTF-8 is shown as
# \xNN, control characters other than TAB as \xNN, and every other control,
# format, private-use, unassigned, invisible (default ignorable), line or
# paragraph separator character as \u{XXXX}. Then === that opens the line,
# also after blanks, marks or a diff sign, gets a backslash in front (the
# review packet's section markers, M113). Returns UTF-8 bytes.
package Esc;
use strict;
use warnings;

sub line {
  my ($bytes) = @_;
  my $s = '';
  # runs of UTF-8 as RFC 3629 defines it (no overlong forms, no surrogates,
  # nothing above U+10FFFF) are decoded; any other byte is shown on its own
  while ($bytes =~ /\G(?:((?:[\x00-\x7F]|[\xC2-\xDF][\x80-\xBF]|\xE0[\xA0-\xBF][\x80-\xBF]|[\xE1-\xEC\xEE\xEF][\x80-\xBF]{2}
      |\xED[\x80-\x9F][\x80-\xBF]|\xF0[\x90-\xBF][\x80-\xBF]{2}|[\xF1-\xF3][\x80-\xBF]{3}|\xF4[\x80-\x8F][\x80-\xBF]{2})+)|(.))/gsx) {
    if (defined $1) {
      my $run = $1;
      utf8::decode($run);
      $s .= $run;
    } else {
      $s .= sprintf '\\x%02X', ord $2;
    }
  }
  $s =~ s/([\x00-\x08\x0A-\x1F\x7F])/sprintf('\\x%02X', ord $1)/ge;
  $s =~ s/((?!\t)[\p{Cc}\p{Cf}\p{Co}\p{Cn}\p{Default_Ignorable_Code_Point}\p{Zl}\p{Zp}])/sprintf('\\u{%04X}', ord $1)/ge;
  $s =~ s/\A([+\- \t\p{Zs}\p{Mn}\p{Mc}\p{Me}\x{2800}]*)(\\*===)/$1\\$2/;
  utf8::encode($s);
  return $s;
}

1;
