#!/usr/bin/env perl
# The guard's command reader (step 5.5; docs/plans/step5.md, section 6.2).
# It reads a bash command the way the guard needs: which simple commands it
# runs, with which words, assignments and redirections, and which parts it
# cannot read with confidence. It reads words, it is not a shell: what it
# cannot read is said, never guessed (A57), and the guard refuses such a
# call when it also names something the guard watches (G0). Loaded with
# require; nothing runs when it is loaded.
#
#   Shell::commands(TEXT) gives a list of simple commands, each a hash:
#     words    the words after quote removal (the command word first), with
#              the leading assignments taken out
#     raw      the same words as written, before quote removal
#     hbody    the text of its here-documents and here-strings
#     pipe_from the text of the command that feeds its input, when piped
#     assigns  the leading NAME=VALUE assignments (after quote removal);
#              assigns_raw the same as written
#     header   a for or select header's words as written (on its "for"
#              command, kept when they cannot be read)
#     redirs   [OP, TARGET] for each redirection (TARGET after quote removal)
#     piped    1 when the command's input comes from a pipe
#     heredoc  1 when it reads a here-document or here-string
#     bg       1 when it runs in the background (&)
#     via      the carriers it was found inside ("bash -c", "eval",
#              "xargs", "find -exec", "env", ...), outermost first
#     scope    which shell it runs in, as a path ("t", "t/s2", "t/c5"):
#              a subshell ( ) or a carrier that starts a new process
#              (bash -c, env, xargs, find -exec, nohup ...) gets a scope
#              of its own below its parent's, so a cd there changes only
#              the commands in that scope (eval, trap, builtin, command and time run in their parent's)
#     to_pipe  1 when its output goes into a pipe (it runs in a subshell)
#     unread   the reasons it cannot be read with confidence (the "cannot
#              read" list): command substitution or backticks; a variable,
#              arithmetic or a process substitution where a word is built;
#              a variable as the command word (ANSI-C quoting is decoded,
#              so $'\x67it' is read as git); eval of anything but a
#              literal; bash -c with an expansion; an interpreter's inline
#              program (-c, -e); a pipe, here-doc or here-string into an
#              interpreter; source or "."; a glob or a brace in a write
#              target; a case statement; text the reader could not split
#              (an open quote, an unclosed $( ). A variable in a write
#              target, a cd to a path not written out before a write, and
#              a script file run by a shell are not on the list: G6 (5.7)
#              judges where a write lands, and a script written and then
#              run is a known limit (A50).
#   Shell::interpreters: the command words that run code they read.
package Shell;
use strict;
use warnings;

our @INTERP = qw(sh bash zsh dash ksh mksh fish csh tcsh perl python python2 python3 node nodejs deno bun ruby php lua awk gawk mawk nawk tclsh Rscript pwsh powershell osascript);
my %INTERP = map { $_ => 1 } @INTERP;
my %SHELL = map { $_ => 1 } qw(sh bash zsh dash ksh mksh csh tcsh fish);
# ([[ is the command word of its test, as [ is, so a variable first in it
# is no command word)
my %KEYWORD = map { $_ => 1 } qw(if then elif else fi while until do done for in select function ! time { } ]]);
# an interpreter's inline-program options, where they differ from -c and -e
my $NODE_INLINE = qr/\A-[A-Za-z]*[ep][A-Za-z]*\z|\A--(?:eval|print)\b|\A-[ep]\S/;
# (perl: -e or -E, alone or after its flags; -Mstrict or -Ilib is no
# program)
my %INLINE = (node => $NODE_INLINE, nodejs => $NODE_INLINE, bun => $NODE_INLINE, deno => $NODE_INLINE,
  perl => qr/\A-[nplawsStTWXUu0-9]*[eE]/,
  # (tclsh has no inline program: its code comes from a file or stdin)
  tclsh => qr/(?!)/,
  php => qr/\A-[A-Za-z]*r[A-Za-z]*\z|\A-r\S/,
  pwsh => qr/\A-(?:c|command|encodedcommand|ec|e)\z/i, powershell => qr/\A-(?:c|command|encodedcommand|ec|e)\z/i);
# prefix commands that run the rest of their words as a command
my %PREFIX = map { $_ => 1 } qw(nohup time command builtin exec nice ionice sudo doas stdbuf setsid chronic caffeinate);
# where a program reads its code from stdin rather than from a file
my $STDIN_FILE = qr{\A(?:-|/dev/stdin|/dev/fd/[0-9]+|/proc/self/fd/[0-9]+)\z};
# an interpreter's options that take the next word as their value
my $SHELL_VALUE = qr/\A[-+][oO]\z|\A--(?:rcfile|init-file)\z/;
my %VALUE = (python => qr/\A-[WXQ]\z/, node => qr/\A(?:-r|--require|--import|--loader|--experimental-loader|--env-file|--conditions|-C|--input-type|--title)\z/,
  ruby => qr/\A-[rIEC]\z/, php => qr/\A-[cdz]\z/);
$VALUE{$_} = $VALUE{node} for qw(nodejs bun deno);
# (perl -I and -M can take their value as the next word; lua -l, tclsh
# -encoding and osascript -l and -s do; step 5.5 repair loop 3)
$VALUE{perl} = qr/\A-[IM]\z/;
$VALUE{lua} = qr/\A-[lW]\z/;
$VALUE{tclsh} = qr/\A-encoding\z/;
$VALUE{osascript} = qr/\A-[ls]\z/;
# python modules that read their code from stdin
my %STDIN_MODULE = map { $_ => 1 } qw(code pdb asyncio idlelib);

# --- shapes the reader may read differently from bash (step 5.5, repair
# loop 3; A57): rather than read each exactly, the guard refuses a call
# that holds one and names a watched word (G0) ---

# TEXT with its single-quoted parts blanked (they are plain text in bash),
# and a second copy with its double-quoted parts blanked too, unless they
# hold a substitution (which runs)
sub blank_quotes {
  my ($t) = @_;
  my ($s, $q) = ('', '');
  my $i = 0;
  my $n = length $t;
  while ($i < $n) {
    my $ch = substr($t, $i, 1);
    if ($ch eq '\\') { my $two = substr($t, $i, 2); $s .= $two; $q .= $two; $i += 2; next }
    # (a here-document's quoted delimiter stays, so its body can be found)
    if (($ch eq "'" || $ch eq '"') && $s =~ /<<-?[ \t]*\z/) {
      my $j = index($t, $ch, $i + 1);
      my $len = ($j < 0 ? $n : $j + 1) - $i;
      my $part = substr($t, $i, $len);
      $s .= $part; $q .= $part; $i += $len;
      next;
    }
    if ($ch eq "'") {
      my $ansi = $i > 0 && substr($t, $i - 1, 1) eq '$';
      my $j = $i + 1;
      while ($j < $n && substr($t, $j, 1) ne "'") { $j += ($ansi && substr($t, $j, 1) eq '\\') ? 2 : 1 }
      my $len = ($j < $n ? $j + 1 : $n) - $i;
      $s .= ' ' x $len; $q .= ' ' x $len; $i += $len;
      next;
    }
    if ($ch eq '"') {
      my $j = $i + 1;
      while ($j < $n && substr($t, $j, 1) ne '"') { $j += substr($t, $j, 1) eq '\\' ? 2 : 1 }
      my $len = ($j < $n ? $j + 1 : $n) - $i;
      my $part = substr($t, $i, $len);
      $s .= $part;
      $q .= $part =~ /\$\(|`/ ? $part : ' ' x $len;
      $i += $len;
      next;
    }
    $s .= $ch; $q .= $ch; $i++;
  }
  return ($s, $q);
}

# TEXT (its single quotes blanked, as blank_quotes gives it) with the
# bodies of its here-documents blanked: all of a body whose delimiter is
# quoted (plain text), and with ALL true also one whose delimiter is not
# (where only $ and backticks expand)
sub blank_bodies {
  my ($t, $all) = @_;
  my @lines = split /(?<=\n)/, $t;
  my @pending;
  my $out = '';
  for my $l (@lines) {
    if (@pending) {
      my ($word, $quoted, $tabs) = @{ $pending[0] };
      (my $bare = $l) =~ s/\r?\n\z//;
      $bare =~ s/\A\t+// if $tabs;
      shift @pending if $bare eq $word;
      $out .= ($quoted || $all) ? ($l =~ s/[^\n]/ /gr) : $l;
      next;
    }
    $out .= $l;
    while ($l =~ /(?<!<)<<(-?)[ \t]*(?:'([^'\n]+)'|"([^"\n]+)"|\\?([A-Za-z0-9_.-]+))/g) {
      push @pending, [defined $2 ? $2 : defined $3 ? $3 : $4, (defined $2 || defined $3 || substr($l, $-[0], length($&)) =~ /\\/) ? 1 : 0, $1 eq '-'];
    }
  }
  return $out;
}

# the reasons TEXT holds a shape the reader may read differently from
# bash; an empty list when it holds none
sub doubts {
  my ($t) = @_;
  my @why;
  my ($s, $q) = blank_quotes($t);
  # (a here-document's body is text, apart from what expands in it)
  $s = blank_bodies($s, 0);
  $q = blank_bodies($q, 1);
  # a lone carriage return, or one on a here-document's end line
  push @why, 'a carriage return' if $t =~ /\r/;
  # arithmetic: an (( )) command where the reader may take it for a
  # subshell (after for, function, time -p, with no blank after a keyword),
  # or one holding <<, a substitution or a backtick; $[ ] and let. ($(( ))
  # is read as one unit, its substitutions as commands; code kept in a
  # variable it names is the next check.)
  my $arith = 0;
  while ($q =~ /\(\(/g) {
    my $at = $-[0];
    next if $at > 0 && substr($q, $at - 1, 1) eq '$';
    my $before = substr($q, 0, $at);
    my $close = index($q, '))', $at + 2);
    my $in = $close < 0 ? substr($q, $at + 2) : substr($q, $at + 2, $close - $at - 2);
    if ($close < 0 || $in =~ /<<|\$\(|`/ || $before !~ /(?:\A|[;&|(\n]|(?:\A|[\s;&|(])(?:if|elif|while|until|!|then|do|else|for|\{)[ \t])[ \t]*\z/) { $arith = 1; last }
  }
  push @why, 'arithmetic' if $arith || $s =~ /\$\[/ || $q =~ /(?:\A|[\s;&|(])let\s/;
  # code kept in a variable (arithmetic or an indirection can run it)
  push @why, 'code held in a variable' if $t =~ /(?:\A|[\s;&|(])[A-Za-z_]\w*(?:\[[^\]\n]*\])?\+?=(?:'[^']*(?:\$\(|`)|\$'(?:[^'\\]|\\.)*?(?:\$\(|`)|"[^"]*\\(?:\$\(|`))/;
  # ${ } holding a quote, a space, a substitution or a process
  # substitution (bash 5.3's ${ cmd; } runs a command)
  while ($s =~ /\$\{/g) {
    my $from = pos $s;
    my $end = index($s, '}', $from);
    my $in = $end < 0 ? substr($s, $from) : substr($s, $from, $end - $from);
    if ($end < 0 || $in =~ /['"`\s;|&<>(]/) { push @why, 'a ${ } the guard cannot read'; last }
  }
  # an extended glob, a zsh glob qualifier or = expansion
  push @why, 'an extended glob or a zsh form' if $q =~ /[@+!*?]\(/ || $q =~ /(?:\A|[\s;&|(])=[A-Za-z\/]/ || $q =~ /\$[=~^][A-Za-z{]/;
  # a comment right after ( or ), where the reader does not see one start
  # (a comment after a blank is read as bash reads it)
  push @why, 'a comment right after a parenthesis' if $q =~ /[()]#/;
  # more substitutions than the guard reads in its time
  my $subs = () = $s =~ /\$\(|(?<!\\)`/g;
  push @why, 'more substitutions than the guard reads' if $subs > 64;
  return @why;
}

# TEXT with its line continuations (a backslash before a newline, outside
# single quotes and comments) removed, as bash removes them: (TEXT, 1); or
# (TEXT, 0) when it holds one beside a here-document, a substitution, ${
# } or ANSI-C quoting, where the guard does not remove them itself
sub join_lines {
  my ($t) = @_;
  return ($t, 1) unless $t =~ /\\\r?\n/;
  if ($t =~ /(?<!<)<<(?!<)|\$\(|`|\$\{|\$'/) {
    # (a backslash at a line's end inside quotes or a quoted here-document's
    # body joins nothing that matters to the reader)
    my ($s) = blank_quotes($t);
    return ($t, blank_bodies($s, 0) =~ /\\\r?\n/ ? 0 : 1);
  }
  my $out = '';
  my $state = '';
  my $n = length $t;
  for (my $i = 0; $i < $n; $i++) {
    my $ch = substr($t, $i, 1);
    if ($state eq "'") { $out .= $ch; $state = '' if $ch eq "'"; next }
    if ($state eq '#') { $out .= $ch; $state = '' if $ch eq "\n"; next }
    if ($ch eq '\\') {
      my $next = substr($t, $i + 1, 1);
      if ($next eq "\n") { $i++; next }
      $out .= $ch . $next;
      $i++;
      next;
    }
    if ($state eq '"') { $out .= $ch; $state = '' if $ch eq '"'; next }
    if ($ch eq "'" || $ch eq '"') { $state = $ch }
    elsif ($ch eq '#' && ($i == 0 || substr($t, $i - 1, 1) =~ /[\s;&|()]/)) { $state = '#' }
    $out .= $ch;
  }
  return ($out, 1);
}

# the position after any backslash-newline pairs (line continuations) at
# POS in S
sub after_cont {
  my ($s, $pos) = @_;
  $pos += 2 while substr($s, $pos, 2) eq "\\\n";
  return $pos;
}

# the here-document delimiter written at POS in S (after << or <<-, and
# any blanks): (DELIM, LENGTH, QUOTED), read as bash reads that word
# (quotes and backslashes removed), or () when it cannot be read
sub heredoc_word {
  my ($s, $pos) = @_;
  my ($d, $q, $j, $n) = ('', 0, $pos, length $s);
  while ($j < $n) {
    my $c = substr($s, $j, 1);
    last if $c =~ /[ \t\n;&|<>()]/;
    if ($c eq '\\') { $d .= substr($s, $j + 1, 1); $q = 1; $j += 2; next }
    if ($c eq "'" || $c eq '"') {
      my $e = index($s, $c, $j + 1);
      return () if $e < 0;
      $d .= substr($s, $j + 1, $e - $j - 1);
      $q = 1;
      $j = $e + 1;
      next;
    }
    if ($c eq '$' && substr($s, $j + 1, 1) eq "'") {
      my $e = index($s, "'", $j + 2);
      return () if $e < 0;
      $d .= ansi_c(substr($s, $j + 2, $e - $j - 2));
      $q = 1;
      $j = $e + 1;
      next;
    }
    return () if $c eq '$' || $c eq '`';
    $d .= $c;
    $j++;
  }
  return () if $d eq '' || $d =~ /\r/;
  return ($d, $j - $pos, $q);
}

# the end of a $( ... ) or ` ... ` starting at POS in S (after the opener);
# undef when it is not closed
sub close_paren {
  my ($s, $pos, $arith) = @_;
  my $depth = 1;
  my $i = $pos;
  my $n = length $s;
  my @pending;    # here-documents named on this line: [DELIM, STRIP]
  while ($i < $n) {
    my $c = substr($s, $i, 1);
    if ($c eq '\\') { $i += 2; next }
    # a here-document's body is text, whatever quotes it holds (not in
    # arithmetic, where << shifts); a delimiter that cannot be read leaves
    # the substitution unread
    if (!$arith && $c eq '<' && substr($s, $i, 3) =~ /\A<<[^<]/) {
      my $j = $i + 2;
      my $strip = substr($s, $j, 1) eq '-' ? 1 : 0;
      $j += $strip;
      $j++ while substr($s, $j, 1) =~ /[ \t]/ && $j < $n;
      my ($d, $len) = heredoc_word($s, $j);
      return undef unless defined $d;
      push @pending, [$d, $strip];
      $i = $j + $len;
      next;
    }
    if ($c eq "\n" && @pending) {
      $i++;
      for my $h (@pending) {
        while ($i < $n) {
          my $e = index($s, "\n", $i);
          $e = $n if $e < 0;
          my $line = substr($s, $i, $e - $i);
          $i = $e + 1;
          $line =~ s/\r\z//;
          $line =~ s/\A\t+// if $h->[1];
          last if $line eq $h->[0];
        }
      }
      @pending = ();
      next;
    }
    if ($c eq "'") { my $j = index($s, "'", $i + 1); return undef if $j < 0; $i = $j + 1; next }
    if ($c eq '"') {
      my $j = $i + 1;
      while ($j < $n && substr($s, $j, 1) ne '"') { $j += substr($s, $j, 1) eq '\\' ? 2 : 1 }
      return undef if $j >= $n;
      $i = $j + 1;
      next;
    }
    # a comment runs to the end of its line (a quote or ) in it counts for
    # nothing)
    if (!$arith && $c eq '#' && ($i == $pos || substr($s, $i - 1, 1) =~ /[ \t\n;&|(]/)) {
      my $e = index($s, "\n", $i);
      return undef if $e < 0;
      $i = $e;
      next;
    }
    if ($c eq '(') { $depth++ }
    elsif ($c eq ')') { $depth--; return $i if $depth == 0 }
    $i++;
  }
  return undef;
}

# the text of $( INNER ) when INNER is only cat reading a here-document that
# expands nothing (a quoted delimiter, or a body with no $, backtick or
# backslash): bash gives exactly that text, so it is read as quoted text.
# Claude Code writes commit messages and PR bodies this way.
sub literal_cat {
  my ($inner) = @_;
  return undef unless $inner =~ /\A[ \t]*cat[ \t]*<<(-?)[ \t]*(['"]?)([A-Za-z0-9_.-]+)\2[ \t]*\r?\n(.*?)\r?\n(\t*)\3\r?\n?[ \t\r\n]*\z/s;
  my ($strip, $q, $delim, $body, $tabs) = ($1, $2, $3, $4, $5);
  return undef if $tabs ne '' && !$strip;
  return undef if !$q && $body =~ /[\$`\\]/;
  # bash ends the here-document at its first end line, and runs what comes
  # after it: a body that holds that line is not text
  for my $l (split /\n/, $body) {
    $l =~ s/\r\z//;
    $l =~ s/\A\t+// if $strip;
    return undef if $l eq $delim;
  }
  $body =~ s/^\t+//mg if $strip;
  return $body;
}

# the text of an ANSI-C quoted string ($'...'), its escapes read
sub ansi_c {
  my ($inner) = @_;
  my %e = (a => "\a", b => "\b", e => "\e", E => "\e", f => "\f", n => "\n", r => "\r", t => "\t", v => "\x0B", '\\' => '\\', "'" => "'", '"' => '"', '?' => '?');
  $inner =~ s/\\(?:x([0-9A-Fa-f]{1,2})|u([0-9A-Fa-f]{1,4})|U([0-9A-Fa-f]{1,8})|([0-7]{1,3})|c(.)|(.))/
    defined $1 ? chr(hex $1) : defined $2 ? chr(hex $2) : defined $3 ? chr(hex $3) : defined $4 ? chr(oct $4) : defined $5 ? chr(ord(uc $5) ^ 64) : exists $e{$6} ? $e{$6} : "\\$6"/ge;
  return $inner;
}

# the end of a ${ ... } or $[ ... ] starting at POS in S (after the
# opener), matching CLOSE; undef when it is not closed
sub close_brace {
  my ($s, $pos, $open, $close) = @_;
  my ($depth, $i, $n) = (1, $pos, length $s);
  while ($i < $n) {
    my $c = substr($s, $i, 1);
    if ($c eq '\\') { $i += 2; next }
    if ($c eq "'") { my $j = index($s, "'", $i + 1); return undef if $j < 0; $i = $j + 1; next }
    if ($c eq '"') {
      my $j = $i + 1;
      while ($j < $n && substr($s, $j, 1) ne '"') { $j += substr($s, $j, 1) eq '\\' ? 2 : 1 }
      return undef if $j >= $n;
      $i = $j + 1;
      next;
    }
    if ($c eq '$' && substr($s, $i + 1, 1) eq '(') { my $e = close_paren($s, $i + 2); return undef unless defined $e; $i = $e + 1; next }
    if ($c eq $open) { $depth++ }
    elsif ($c eq $close) { $depth--; return $i if $depth == 0 }
    $i++;
  }
  return undef;
}

# the commands bash runs to expand TEXT, an unquoted here-document's body:
# the inside of each $( ) and backtick in it
sub subs_in {
  my ($t) = @_;
  my @subs;
  my ($i, $n) = (0, length $t);
  while ($i < $n) {
    my $c = substr($t, $i, 1);
    if ($c eq '\\') { $i += 2; next }
    if ($c eq '$') {
      my $k = after_cont($t, $i + 1);
      if (substr($t, $k, 1) eq '(' && substr($t, $k + 1, 1) ne '(') {
        my $e = close_paren($t, $k + 1);
        if (defined $e) { push @subs, substr($t, $k + 1, $e - $k - 1); $i = $e + 1; next }
      }
    }
    if ($c eq '`') {
      my $e = close_tick($t, $i + 1);
      if ($e > 0) { push @subs, unbacktick(substr($t, $i + 1, $e - $i - 1)); $i = $e + 1; next }
    }
    $i++;
  }
  return @subs;
}

# the position of the backtick that closes one opened before POS in S: the
# next one not escaped by a backslash (an escaped one nests), or -1
sub close_tick {
  my ($s, $pos) = @_;
  for (my $i = $pos; $i < length $s; $i++) {
    my $c = substr($s, $i, 1);
    if ($c eq '\\') { $i++; next }
    return $i if $c eq '`';
  }
  return -1;
}

# the command inside backticks, as bash reads it (\\, \` and \$ unescaped)
sub unbacktick { my ($t) = @_; $t =~ s/\\([\\`\$])/$1/g; return $t }

# tokens of S: words (text after quote removal, with flags) and operators;
# a word's subs are the commands of its substitutions, as text
sub tokens {
  my ($s) = @_;
  my (@t, @heredocs);
  my $n = length $s;
  my $i = 0;
  my $word;
  my $start_word = sub { $word //= { text => '', flags => {}, raw => '' } };
  my $end_word = sub {
    return unless defined $word;
    if (@t && exists $t[-1]{heredoc_start}) {
      my $st = pop @t;
      # (bash keeps a carriage return in the delimiter; the reader would not
      # end the body where bash does, so such a delimiter is not read)
      if ($word->{text} =~ /\r/) { push @t, { error => 'a here-document delimiter with a carriage return' }; $word = undef; return }
      my $h = { delim => $word->{text}, quoted => $word->{flags}{quoted} ? 1 : 0, strip => $st->{heredoc_start} };
      push @t, { word => $word, heredoc => $h };
      push @heredocs, $h;
    } else {
      push @t, { word => $word };
    }
    $word = undef;
  };
  while ($i < $n) {
    my $c = substr($s, $i, 1);
    # here-document bodies start after the line that named them
    $end_word->() if $c eq "\n";
    if ($c eq "\n" && @heredocs) {
      push @t, { op => ';' };
      $i++;
      for my $h (@heredocs) {
        my $found = 0;
        while ($i < $n) {
          my $e = index($s, "\n", $i);
          $e = $n if $e < 0;
          my $line = substr($s, $i, $e - $i);
          $i = $e + 1;
          (my $cmp = $line) =~ s/\r\z//;    # a CRLF line ends at its CR
          $cmp =~ s/^\t+// if $h->{strip};
          if ($cmp eq $h->{delim}) { $found = 1; last }
          $h->{body} .= "$line\n";
        }
        # (in a body bash expands, a backslash-newline joins two lines before
        # $( is looked for)
        if (!$h->{quoted}) {
          (my $joined = $h->{body} // '') =~ s/\\\r?\n//g;
          $h->{body_subst} = 1 if $joined =~ /\$\(|`/;
          $h->{subs} = [subs_in($joined)];
        }
        # (the delimiter is the command's text, so it is not repeated)
        push @t, { error => 'a here-document with no end line' } unless $found;
      }
      @heredocs = ();
      next;
    }
    # (a carriage return is a word character to bash, except where it ends
    # a CRLF line)
    if ($c eq ' ' || $c eq "\t" || ($c eq "\r" && substr($s, $i + 1, 1) eq "\n")) { $end_word->(); $i++; next }
    if ($c eq "\n") { $end_word->(); push @t, { op => ';' }; $i++; next }
    if ($c eq '#' && !defined $word) {
      my $e = index($s, "\n", $i);
      $i = $e < 0 ? $n : $e;
      next;
    }
    if ($c eq '\\') {
      if (substr($s, $i + 1, 1) eq "\n") { $i += 2; next }    # a line continued
      $start_word->();
      $word->{text} .= substr($s, $i + 1, 1);
      $word->{raw} .= substr($s, $i, 2);
      $i += 2;
      next;
    }
    if ($c eq "'") {
      my $j = index($s, "'", $i + 1);
      if ($j < 0) { push @t, { error => 'an open single quote' }; last }
      $start_word->();
      $word->{text} .= substr($s, $i + 1, $j - $i - 1);
      $word->{raw} .= substr($s, $i, $j - $i + 1);
      $word->{flags}{quoted} = 1;
      $i = $j + 1;
      next;
    }
    if ($c eq '$' && substr($s, $i + 1, 1) eq "'") {
      my $j = $i + 2;
      while ($j < $n && substr($s, $j, 1) ne "'") { $j += substr($s, $j, 1) eq '\\' ? 2 : 1 }
      if ($j >= $n) { push @t, { error => 'an open $\'...\' quote' }; last }
      my $inner = substr($s, $i + 2, $j - $i - 2);
      $start_word->();
      # the escapes are read, so $'\x67it' is the word git
      $word->{text} .= ansi_c($inner);
      $word->{raw} .= substr($s, $i, $j - $i + 1);
      $word->{flags}{quoted} = 1;
      $i = $j + 1;
      next;
    }
    # $"..." (a string for the locale) is read as "..."
    if ($c eq '$' && substr($s, $i + 1, 1) eq '"') { $i++; next }
    if ($c eq '"') {
      my $j = $i + 1;
      my $text = '';
      $start_word->();
      while ($j < $n && substr($s, $j, 1) ne '"') {
        my $d = substr($s, $j, 1);
        if ($d eq '\\' && $j + 1 < $n) {
          my $e = substr($s, $j + 1, 1);
          $text .= $e =~ /[\$`"\\\n]/ ? ($e eq "\n" ? '' : $e) : "\\$e";
          $j += 2;
          next;
        }
        # ($ then a backslash-newline then ( is still a substitution)
        my $k = $d eq '$' ? after_cont($s, $j + 1) : $j;
        if ($d eq '$' && substr($s, $k, 1) eq '(') {
          my $arith = substr($s, $k + 1, 1) eq '(';
          my $e = close_paren($s, $k + 1, $arith);
          if (!defined $e) { push @t, { error => 'an unclosed $(' }; return @t }
          # ($((cmd) ) is a substitution of a subshell, not arithmetic)
          $arith = 0 if $arith && substr($s, $e - 1, 1) ne ')';
          my $lit = $arith ? undef : literal_cat(substr($s, $k + 1, $e - $k - 1));
          if (defined $lit) { $text .= $lit; $j = $e + 1; next }
          # (arithmetic with no substitution in it builds a word, it runs nothing)
          $word->{flags}{($arith && substr($s, $k + 1, $e - $k - 1) !~ /\$\(|`/) ? 'var' : 'subst'} = 1;
          # (inside arithmetic, its own substitutions are what runs)
          push @{ $word->{subs} }, $arith ? subs_in(substr($s, $k + 1, $e - $k - 1)) : substr($s, $k + 1, $e - $k - 1);
          $text .= substr($s, $j, $e - $j + 1);
          $j = $e + 1;
          next;
        }
        if ($d eq '`') {
          my $e = close_tick($s, $j + 1);
          if ($e < 0) { push @t, { error => 'an unclosed backtick' }; return @t }
          $word->{flags}{subst} = 1;
          push @{ $word->{subs} }, unbacktick(substr($s, $j + 1, $e - $j - 1));
          $text .= substr($s, $j, $e - $j + 1);
          $j = $e + 1;
          next;
        }
        if ($d eq '$' && substr($s, $j + 1, 1) =~ /[A-Za-z_{0-9@*#?\$!-]/) { $word->{flags}{var} = 1 }
        $text .= $d;
        $j++;
      }
      if ($j >= $n) { push @t, { error => 'an open double quote' }; last }
      $word->{text} .= $text;
      $word->{raw} .= substr($s, $i, $j - $i + 1);
      $word->{flags}{quoted} = 1;
      $i = $j + 1;
      next;
    }
    my $k = $c eq '$' ? after_cont($s, $i + 1) : $i;
    if ($c eq '$' && substr($s, $k, 1) eq '(') {
      my $arith = substr($s, $k + 1, 1) eq '(';
      my $e = close_paren($s, $k + 1, $arith);
      if (!defined $e) { push @t, { error => 'an unclosed $(' }; last }
      $arith = 0 if $arith && substr($s, $e - 1, 1) ne ')';
      $start_word->();
      my $lit = $arith ? undef : literal_cat(substr($s, $k + 1, $e - $k - 1));
      if (defined $lit) {
        $word->{text} .= $lit;
        $word->{raw} .= substr($s, $i, $e - $i + 1);
        $word->{flags}{quoted} = 1;
        $i = $e + 1;
        next;
      }
      $word->{flags}{($arith && substr($s, $k + 1, $e - $k - 1) !~ /\$\(|`/) ? 'var' : 'subst'} = 1;
      push @{ $word->{subs} }, $arith ? subs_in(substr($s, $k + 1, $e - $k - 1)) : substr($s, $k + 1, $e - $k - 1);
      $word->{text} .= substr($s, $i, $e - $i + 1);
      $word->{raw} .= substr($s, $i, $e - $i + 1);
      $i = $e + 1;
      next;
    }
    if ($c eq '`') {
      my $e = close_tick($s, $i + 1);
      if ($e < 0) { push @t, { error => 'an unclosed backtick' }; last }
      $start_word->();
      $word->{flags}{subst} = 1;
      push @{ $word->{subs} }, unbacktick(substr($s, $i + 1, $e - $i - 1));
      $word->{text} .= substr($s, $i, $e - $i + 1);
      $word->{raw} .= substr($s, $i, $e - $i + 1);
      $i = $e + 1;
      next;
    }
    # ${ ... } and $[ ... ]: one unit, whatever they hold (a << in them
    # starts no here-document)
    if ($c eq '$' && (substr($s, $k, 1) eq '{' || substr($s, $k, 1) eq '[')) {
      my $o = substr($s, $k, 1);
      my $e = close_brace($s, $k + 1, $o, $o eq '{' ? '}' : ']');
      if (!defined $e) { push @t, { error => "an unclosed \$$o" }; last }
      $start_word->();
      $word->{flags}{var} = 1;
      $word->{flags}{subst} = 1 if substr($s, $k, $e - $k) =~ /\$\(|`/;
      push @{ $word->{subs} }, subs_in(substr($s, $k + 1, $e - $k - 1));
      $word->{text} .= substr($s, $i, $e - $i + 1);
      $word->{raw} .= substr($s, $i, $e - $i + 1);
      $i = $e + 1;
      next;
    }
    if ($c eq '$' && substr($s, $i + 1, 1) =~ /[A-Za-z_{0-9@*#?\$!-]/) {
      $start_word->();
      $word->{flags}{var} = 1;
      $word->{text} .= '$';
      $word->{raw} .= '$';
      $i++;
      next;
    }
    if (($c eq '<' || $c eq '>') && substr($s, $i + 1, 1) eq '(') {
      my $e = close_paren($s, $i + 2);
      if (!defined $e) { push @t, { error => 'an unclosed process substitution' }; last }
      $start_word->();
      $word->{flags}{subst} = 1;
      $word->{flags}{procsub} = 1;
      push @{ $word->{subs} }, substr($s, $i + 2, $e - $i - 2);
      $word->{text} .= substr($s, $i, $e - $i + 1);
      $i = $e + 1;
      next;
    }
    # an arithmetic command (( ... )): one unit, read by its own text (a <<
    # in it shifts, it starts no here-document)
    if ($c eq '(' && substr($s, $i + 1, 1) eq '(' && !defined $word
      && (!@t || $t[-1]{op} || ($t[-1]{word} && !$t[-1]{word}{flags}{quoted} && $t[-1]{word}{text} =~ /\A(?:if|elif|while|until|!|time|\{|then|do|else|for)\z/))) {
      my $e = close_paren($s, $i + 2, 1);
      if (!defined $e || substr($s, $e + 1, 1) ne ')') { push @t, { error => 'an unclosed ((' }; last }
      $e++;
      $start_word->();
      my $text = substr($s, $i, $e - $i + 1);
      $word->{text} .= $text;
      $word->{raw} .= $text;
      $word->{flags}{arith} = 1;
      $word->{flags}{subst} = 1 if $text =~ /\$\(|`/;
      push @{ $word->{subs} }, subs_in(substr($text, 2, -2));
      $i = $e + 1;
      next;
    }
    # redirections: [n]> [n]>> >| < <> &> &>> [n]>&m <<< << <<-
    # (the look-ahead reads a short window, so a long command is not copied
    # for every character)
    if ($c =~ /[<>&]/ || ($c =~ /[0-9]/ && !defined $word && substr($s, $i, 24) =~ /\A[0-9]+[<>]/)) {
      if (substr($s, $i, 24) =~ /\A([0-9]*)(<<-|<<<|<<|<>|>>|>\||>&|<&|&>>|&>|>|<)/) {
        my ($fd, $op) = ($1, $2);
        if ($op eq '&>' || $op eq '&>>' || $fd ne '' || $c ne '&') {
          $end_word->();
          $i += length($fd) + length($op);
          push @t, { redir => $op, fd => $fd };
          if ($op eq '<<' || $op eq '<<-') {
            # the delimiter word follows; it is read as a word, then noted
            push @t, { heredoc_start => ($op eq '<<-' ? 1 : 0) };
          }
          next;
        }
      }
    }
    if ($c =~ /[;&|()]/ && substr($s, $i, 2) =~ /\A(&&|\|\||;;|\|&|[;&|()])/) {
      $end_word->();
      push @t, { op => $1 };
      $i += length $1;
      next;
    }
    $start_word->();
    $word->{text} .= $c;
    $word->{raw} .= $c;
    $word->{flags}{glob} = 1 if $c =~ /[*?\[]/;
    # (an extended glob: @( ), +( ), !( ) in bash with extglob on)
    $word->{flags}{glob} = 1 if $c =~ /[@+!]/ && substr($s, $i + 1, 1) eq '(';
    $word->{flags}{brace} = 1 if $c eq '{' && substr($s, $i, 512) =~ /\A\{[^}\s]*[,.][^}\s]*\}/;
    $i++;
  }
  $end_word->();
  if (@t && exists $t[-1]{heredoc_start}) { pop @t; push @t, { error => 'a here-document with no delimiter' } }
  for my $h (@heredocs) { push @t, { error => 'a here-document with no end line' } }
  return @t;
}

my $SEQ = 0;    # numbers the scopes

# the simple commands of S; DEPTH guards against endless nesting; SCOPE is
# the shell they run in
sub commands {
  my ($s, $via, $depth, $scope) = @_;
  $via ||= [];
  $depth ||= 0;
  $scope = 't' unless defined $scope;
  return ({ words => [], assigns => [], redirs => [], via => $via, scope => $scope, unread => ['commands nested too deep'] }) if $depth > 8;
  my @t = tokens($s);
  my @cmds;
  my $cur;
  my @scopes = ($scope);
  my $new = sub { $cur = { words => [], wflags => [], raw => [], hbody => '', assigns => [], redirs => [], piped => 0, heredoc => 0, bg => 0, via => [@$via], scope => $scopes[-1], unread => [] } };
  $new->();
  my $pending_redir;
  my $prev_op = '';
  my $header = 0;    # in a for or select header, up to its ; or do
  my ($after_time, $function) = (0, 0);
  my $in_case = 0;
  my @errors;
  # the commands of a word's substitutions, kept with the command
  my $take_subs = sub { my ($w) = @_; push @{ $cur->{subs} }, @{ $w->{subs} } if $w->{subs} };
  my $finish = sub {
    my ($op) = @_;
    my $piped = ($op eq '|' || $op eq '|&') ? 1 : 0;
    if (@{ $cur->{words} } || @{ $cur->{assigns} } || @{ $cur->{redirs} }) {
      $cur->{bg} = 1 if $op eq '&';
      $cur->{to_pipe} = 1 if $piped;
      push @cmds, $cur;
    }
    # what feeds a command's input: every earlier stage of its pipeline
    my $from = $piped ? join(' ', grep { $_ ne '' } $cur->{pipe_from} // '', @{ $cur->{assigns_raw} || [] }, @{ $cur->{raw} }, $cur->{hbody}) : '';
    $new->();
    $cur->{piped} = $piped;
    $cur->{pipe_from} = $from;
  };
  for my $tok (@t) {
    if ($tok->{error}) { push @errors, $tok->{error}; next }
    if (defined $tok->{redir}) { $pending_redir = $tok; next }
    if ($tok->{op}) {
      $in_case = 0 if $tok->{op} eq ';;';
      if ($header) {
        $header = 0;
        # (its words are kept as written, so what they run is judged)
        if (@{ $cur->{unread} }) { $cur->{words} = ['for']; $cur->{raw} = ['for', @{ $cur->{header} || [] }]; push @cmds, $cur }
        $new->();
        next;
      }
      $finish->($tok->{op});
      if ($tok->{op} eq '(') { push @scopes, "$scopes[-1]/s" . ++$SEQ; $cur->{scope} = $scopes[-1] }
      elsif ($tok->{op} eq ')' && @scopes > 1) { pop @scopes; $cur->{scope} = $scopes[-1] }
      $prev_op = $tok->{op};
      next;
    }
    my $w = $tok->{word};
    if ($pending_redir) {
      my $op = $pending_redir->{redir};
      push @{ $cur->{redirs} }, [$op, $w->{text}, $w->{flags}];
      $take_subs->($w);
      push @{ $cur->{subs} }, @{ $tok->{heredoc}{subs} } if $tok->{heredoc} && $tok->{heredoc}{subs};
      $cur->{heredoc} = 1 if $op eq '<<' || $op eq '<<-' || $op eq '<<<';
      $cur->{body_subst} = 1 if $tok->{heredoc} && $tok->{heredoc}{body_subst};
      $cur->{hbody} .= $tok->{heredoc}{body} // '' if $tok->{heredoc};
      $cur->{hbody} .= $w->{text} . "\n" if $op eq '<<<';
      push @{ $cur->{unread} }, 'command substitution or backticks' if $w->{flags}{subst};
      $pending_redir = undef;
      next;
    }
    if ($header) {
      if ($w->{text} eq 'do' && !$w->{flags}{quoted}) { $header = 0 }
      else { push @{ $cur->{unread} }, 'command substitution or backticks' if $w->{flags}{subst}; $take_subs->($w); push @{ $cur->{header} }, $w->{raw}; next }
    }
    # leading keywords and assignments
    if (!@{ $cur->{words} }) {
      if (($w->{text} eq 'for' || $w->{text} eq 'select') && !$w->{flags}{quoted}) { $header = 1; next }
      if ($w->{text} eq 'case' && !$w->{flags}{quoted}) { $in_case = 1; push @{ $cur->{unread} }, 'a case statement'; push @{ $cur->{words} }, 'case'; push @{ $cur->{wflags} }, $w->{flags}; next }
      # time -p: the option is time's, not a command word
      if ($w->{text} eq 'time' && !$w->{flags}{quoted}) { $after_time = 1; next }
      if ($after_time && ($w->{text} eq '-p' || $w->{text} eq '--')) { next }
      $after_time = 0;
      # function NAME { ...; }: the name ends the command, so the body's
      # commands are read as commands
      if ($w->{text} eq 'function' && !$w->{flags}{quoted}) { $function = 1; next }
      if ($function) { $function = 0; push @{ $cur->{words} }, 'function', $w->{text}; push @{ $cur->{wflags} }, {}, $w->{flags}; push @{ $cur->{raw} }, 'function', $w->{raw}; $finish->(';'); next }
      next if $KEYWORD{ $w->{text} } && !$w->{flags}{quoted};
      if ($w->{raw} =~ /\A[A-Za-z_][A-Za-z0-9_]*\+?=/) {
        push @{ $cur->{assigns} }, $w->{text};
        # (kept as written too: what an assignment runs is judged)
        push @{ $cur->{assigns_raw} }, $w->{raw};
        push @{ $cur->{unread} }, 'command substitution or backticks' if $w->{flags}{subst};
        $take_subs->($w);
        next;
      }
    }
    push @{ $cur->{words} }, $w->{text};
    push @{ $cur->{wflags} }, $w->{flags};
    push @{ $cur->{raw} }, $w->{raw};
    $take_subs->($w);
  }
  $finish->('');
  my @out;
  for my $c (@cmds) {
    # what a substitution runs is a command too, run before the command
    # that holds it, in a subshell of its own
    for my $inner (@{ delete $c->{subs} || [] }) {
      push @out, commands($inner, [@{ $c->{via} }, 'substitution'], $depth + 1, "$c->{scope}/c" . ++$SEQ);
    }
    push @out, expand($c, $depth);
  }
  if (@errors) {
    my $e = { words => [], assigns => [], redirs => [], via => [@$via], unread => [map { "the reader could not split it ($_)" } @errors] };
    unshift @out, $e;
  }
  return @out;
}

# a command's own judgements, and the commands its carriers run
sub expand {
  my ($c, $depth) = @_;
  my @words = @{ $c->{words} };
  my @flags = @{ $c->{wflags} };
  my @u = @{ $c->{unread} };
  for my $i (0 .. $#flags) {
    push @u, 'command substitution or backticks' if $flags[$i]{subst};
  }
  # (a program under a variable folder, its name written out, is that
  # program: $HOME/bin/tool, ${VENV}/bin/python)
  push @u, 'a variable as the command word' if @flags && ($flags[0]{var} || $flags[0]{subst})
    && ($flags[0]{subst} || ($c->{raw}[0] // '') !~ m{\A(?:\$[A-Za-z_]\w*|\$\{[A-Za-z_]\w*\}|~[A-Za-z0-9_.-]*)(?:/[A-Za-z0-9_.+-]+)+\z});
  # {} is what find -exec and xargs -I put there: a word from elsewhere
  push @u, 'a variable as the command word' if @words && $words[0] =~ /\{\}/;
  push @u, 'a glob or a brace in the command word' if @flags && ($flags[0]{glob} || $flags[0]{brace}) && !$flags[0]{arith} && $words[0] !~ /\A\[\[?\z/;
  push @u, 'here-document text that is expanded with command substitution' if $c->{body_subst};
  for my $r (@{ $c->{redirs} }) {
    my ($op, $target, $f) = @$r;
    next unless $op =~ />/;
    push @u, 'a glob or a brace in a write target' if $f->{glob} || $f->{brace};
  }
  my %seen;
  $c->{unread} = [grep { !$seen{$_}++ } @u];
  delete $c->{wflags};
  my @out = ($c);
  return @out unless @words;
  my $name = $words[0];
  $name =~ s{.*/}{};    # /bin/bash, /usr/bin/env
  my $sub = sub {
    my ($start, $carrier) = @_;
    return if $start > $#words;
    # builtin, command and time run what follows in this same shell (a cd
    # through them moves this shell); the other carriers start a process
    my $same = $carrier eq 'builtin' || $carrier eq 'command' || $carrier eq 'time';
    my $inner = { %$c, words => [@words[$start .. $#words]], wflags => [@flags[$start .. $#flags]], raw => [@{ $c->{raw} }[$start .. $#{ $c->{raw} }]], assigns => [], redirs => [], unread => [],
      via => [@{ $c->{via} }, $carrier], body_subst => 0, scope => $same ? $c->{scope} : "$c->{scope}/c" . ++$SEQ };
    push @out, expand($inner, $depth + 1);
  };
  # a versioned interpreter (python3.12, perl5.38) is that interpreter
  (my $base = $name) =~ s/[0-9][0-9.]*\z//;
  $base = $name unless $INTERP{$base};
  # the first operand (after the options and their values), and whether
  # it is a program file: then what comes in on stdin is that program's
  # data, not code. Code comes in on stdin when the operand is - or a name
  # for stdin, with a shell's -s, and with python -m code or pdb.
  my $takes = $SHELL{$base} ? $SHELL_VALUE : $VALUE{$base};
  my ($first, $module, $dashdash);
  for (my $i = 1; $i <= $#words; $i++) {
    my $w = $words[$i];
    if ($w eq '--') { $first = $i + 1; $dashdash = 1; last }
    if ($w eq '-m' && $base =~ /\Apython/) { $module = $words[ $i + 1 ]; last }
    if ($w =~ /\A[-+]./) { $i++ if $takes && $w =~ $takes; next }
    $first = $i;
    last;
  }
  my $stdin_code = (defined $first && defined $words[$first] && $words[$first] =~ $STDIN_FILE)
    || ($SHELL{$base} && grep { /\A-[A-Za-z]*s[A-Za-z]*\z/ } @words[1 .. (defined $first ? $first - 1 : $#words)])
    || (defined $module && $STDIN_MODULE{$module});
  my $runs_file = !$stdin_code && ((defined $first && defined $words[$first]) || defined $module);
  # a program that is the output of a process substitution, <(...) as its
  # file or < <(...) as its stdin: code made by another command (a script
  # file named through a variable is a file, judged as one)
  my $program_from = defined $first && defined $flags[$first] && $flags[$first]{procsub};
  my $stdin_from = grep { $_->[0] eq '<' && $_->[2]{procsub} } @{ $c->{redirs} };
  if ($name eq 'source' || $name eq '.') {
    my $f = $words[1];
    if (defined $f && (($flags[1] && $flags[1]{procsub}) || $f =~ $STDIN_FILE || $stdin_from)) { push @{ $c->{unread} }, 'source of a process substitution or stdin' }
    else { push @{ $c->{unread} }, 'source or .' }
  } elsif ($SHELL{$base}) {
    # -c takes its script from the first word that is not an option (after
    # -- when there is one), wherever -c stands among the options
    my $has_c = grep { /\A-[A-Za-z]*c[A-Za-z]*\z/ } @words[1 .. (defined $first && !$dashdash ? $first - 1 : $#words)];
    if ($has_c) {
      my $si = $first;
      my $script = defined $si ? $words[$si] : undef;
      if (!defined $script) { push @{ $c->{unread} }, "$name -c with no command" }
      elsif ($flags[$si]{subst} || $flags[$si]{var}) { push @{ $c->{unread} }, "$name -c with an expansion" }
      else { push @out, commands($script, [@{ $c->{via} }, "$name -c"], $depth + 1, "$c->{scope}/c" . ++$SEQ) }
    } elsif ($program_from || $stdin_from) {
      push @{ $c->{unread} }, "a program for $name from a process substitution";
    } elsif (($c->{piped} || $c->{heredoc}) && !$runs_file) {
      push @{ $c->{unread} }, "a pipe, here-document or here-string into $name";
    }
  } elsif ($INTERP{$base}) {
    my $inline = $INLINE{$base} || qr/\A-[A-Za-z]*[ceE][A-Za-z]*\z|\A--(?:eval|command)\b|\A-e\S/;
    # awk -f with stdin as its program file reads its code from its input
    my $awk_stdin = $base =~ /awk\z/ && grep { ($words[$_] eq '-f' && defined $words[ $_ + 1 ] && $words[ $_ + 1 ] =~ $STDIN_FILE) || $words[$_] =~ m{\A-f(?:-|/dev/stdin|/dev/fd/[0-9]+)\z} } 1 .. $#words;
    if ($awk_stdin) {
      push @{ $c->{unread} }, "a pipe, here-document or here-string into $name" if $c->{piped} || $c->{heredoc};
      push @{ $c->{unread} }, "a program for $name from a process substitution" if $stdin_from;
    } elsif (grep { $_ =~ $inline } @words[1 .. $#words]) {
      push @{ $c->{unread} }, "an inline program for $name";
    } elsif ($base =~ /awk\z/ && @words > 1) {
      push @{ $c->{unread} }, "an inline program for $name";
    } elsif (($base eq 'deno' || $base eq 'bun') && @words > 1 && $words[1] eq 'eval') {
      push @{ $c->{unread} }, "an inline program for $name";
    } elsif ($program_from || $stdin_from) {
      push @{ $c->{unread} }, "a program for $name from a process substitution";
    } elsif (!$c->{piped} && $c->{heredoc} && !$runs_file && ($c->{hbody} // '') !~ /[\$`]/) {
      # a here-document of plain text is the program, judged as -c or -e
      # would be (step 5.5)
      push @{ $c->{unread} }, "an inline program for $name";
    } elsif (($c->{piped} || $c->{heredoc}) && !$runs_file) {
      push @{ $c->{unread} }, "a pipe, here-document or here-string into $name";
    }
  } elsif ($name eq 'trap' && @words > 1 && ($words[1] !~ /\A-/ || ($words[1] eq '--' && @words > 2))) {
    # trap's first argument (after --) is code bash runs later
    my $ti = $words[1] eq '--' ? 2 : 1;
    if ($flags[$ti]{subst} || $flags[$ti]{var}) { push @{ $c->{unread} }, 'trap of anything but a literal' }
    # (it runs later in this same shell, so in this command's scope)
    else { push @out, commands($words[$ti], [@{ $c->{via} }, 'trap'], $depth + 1, $c->{scope}) }
  } elsif ($name eq 'coproc') {
    push @{ $c->{unread} }, 'a coprocess';
  } elsif ($name eq 'alias' && grep { /=/ } @words[1 .. $#words]) {
    # an alias can make any later word run git
    push @{ $c->{unread} }, 'an alias definition';
  } elsif ($name eq 'eval') {
    if (grep { $_->{subst} || $_->{var} } @flags[1 .. $#flags]) { push @{ $c->{unread} }, 'eval of anything but a literal' }
    else { push @out, commands(join(' ', @words[1 .. $#words]), [@{ $c->{via} }, 'eval'], $depth + 1, $c->{scope}) }
  } elsif ($name eq 'env') {
    my $i = 1;
    while ($i <= $#words) {
      # -S splits a string into the command: that string is not read here
      if ($words[$i] =~ /\A-[A-Za-z0-9]*S|\A--split-string/) { push @{ $c->{unread} }, 'env -S'; return @out }
      if ($words[$i] =~ /\A-[uC]\z|\A--(?:unset|chdir)\z/) { $i += 2; next }
      # (every other option is one word: -i, -0, -v, --ignore-signal=PIPE)
      if ($words[$i] =~ /\A-/) { $i++; next }
      if ($words[$i] =~ /\A[A-Za-z_][A-Za-z0-9_]*=/) { $i++; next }
      last;
    }
    $sub->($i, 'env');
  } elsif ($name eq 'xargs') {
    my $i = 1;
    while ($i <= $#words && $words[$i] =~ /\A-/) {
      last if $words[$i] eq '--' && ++$i;
      $i += $words[$i] =~ /\A-[IEdLnPsa]\z|\A--(?:arg-file|max-args|max-lines|max-procs|delimiter|max-chars|process-slot-var)\z/ ? 2 : 1;
    }
    $sub->($i, 'xargs');
  } elsif ($name eq 'find') {
    for my $i (1 .. $#words) {
      next unless $words[$i] =~ /\A-(?:exec|execdir|ok|okdir)\z/;
      my $j = $i + 1;
      my $k = $j;
      $k++ while $k <= $#words && $words[$k] ne ';' && $words[$k] ne '+';
      if ($k > $j) {
        my $inner = { %$c, words => [@words[$j .. $k - 1]], wflags => [@flags[$j .. $k - 1]], raw => [@{ $c->{raw} }[$j .. $k - 1]], assigns => [], redirs => [], unread => [],
          via => [@{ $c->{via} }, 'find -exec'], body_subst => 0, scope => "$c->{scope}/c" . ++$SEQ };
        push @out, expand($inner, $depth + 1);
      }
    }
  } elsif ($name eq 'timeout') {
    my $i = 1;
    while ($i <= $#words && $words[$i] =~ /\A-/) { $i += $words[$i] =~ /\A-[sk]\z|\A--(?:signal|kill-after)\z/ ? 2 : 1 }
    $sub->($i + 1, 'timeout');
  } elsif ($PREFIX{$name}) {
    my $i = 1;
    if ($name eq 'command' && @words > 1 && $words[1] =~ /\A-[vV]\z/) { return @out }
    # the options of each prefix that take the next word as their value (a
    # cluster such as -Eu takes it when its last letter does)
    my %takes = (nice => qr/\A(?:-n|--adjustment)\z/, exec => qr/\A-a\z/, ionice => qr/\A(?:-[A-Za-z]*[cnpPu]|--(?:class|classdata|pid|pgid|uid))\z/,
      sudo => qr/\A(?:-[A-Za-z]*[ugCDhprtUT]|--(?:user|group|chdir|host|prompt|role|type|other-user|command-timeout))\z/,
      doas => qr/\A-[A-Za-z]*[uC]\z/, stdbuf => qr/\A(?:-[A-Za-z]*[ioe]|--(?:input|output|error))\z/, time => qr/\A(?:-[A-Za-z]*[fo]|--(?:format|output))\z/);
    while ($i <= $#words && $words[$i] =~ /\A-/) {
      if ($words[$i] eq '--') { $i++; last }
      $i += ($takes{$name} && $words[$i] =~ $takes{$name}) ? 2 : 1;
    }
    $sub->($i, $name);
  }
  return @out;
}

1;
