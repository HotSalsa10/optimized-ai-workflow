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
my %SHELL = map { $_ => 1 } qw(sh bash zsh dash ksh mksh);
my %KEYWORD = map { $_ => 1 } qw(if then elif else fi while until do done for in select function ! time { } [[ ]]);
# an interpreter's inline-program options, where they differ from -c and -e
my $NODE_INLINE = qr/\A-[A-Za-z]*[ep][A-Za-z]*\z|\A--(?:eval|print)\b|\A-[ep]\S/;
my %INLINE = (node => $NODE_INLINE, nodejs => $NODE_INLINE, bun => $NODE_INLINE, deno => $NODE_INLINE,
  php => qr/\A-[A-Za-z]*r[A-Za-z]*\z|\A-r\S/,
  pwsh => qr/\A-(?:c|command|encodedcommand|ec|e)\z/i, powershell => qr/\A-(?:c|command|encodedcommand|ec|e)\z/i);
# prefix commands that run the rest of their words as a command
my %PREFIX = map { $_ => 1 } qw(nohup time command builtin exec nice ionice sudo doas stdbuf setsid chronic caffeinate);

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
    # arithmetic, where << shifts)
    if (!$arith && $c eq '<' && substr($s, $i, 3) =~ /\A<<[^<]/ && substr($s, $i + 2, 200) =~ /\A(-?)[ \t]*(['"]?)([A-Za-z0-9_.-]+)\2/) {
      push @pending, [$3, $1 eq '-'];
      $i += 2 + length $&;
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
  my ($strip, $q, $body, $tabs) = ($1, $2, $4, $5);
  return undef if $tabs ne '' && !$strip;
  return undef if !$q && $body =~ /[\$`\\]/;
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

# tokens of S: words (text after quote removal, with flags) and operators
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
          $h->{body_subst} = 1 if !$h->{quoted} && $line =~ /\$\(|`/;
        }
        # (the delimiter is the command's text, so it is not repeated)
        push @t, { error => 'a here-document with no end line' } unless $found;
      }
      @heredocs = ();
      next;
    }
    if ($c eq ' ' || $c eq "\t" || $c eq "\r") { $end_word->(); $i++; next }
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
        if ($d eq '$' && substr($s, $j + 1, 1) eq '(') {
          my $e = close_paren($s, $j + 2, substr($s, $j + 2, 1) eq '(');
          if (!defined $e) { push @t, { error => 'an unclosed $(' }; return @t }
          my $lit = literal_cat(substr($s, $j + 2, $e - $j - 2));
          if (defined $lit) { $text .= $lit; $j = $e + 1; next }
          $word->{flags}{subst} = 1;
          $text .= substr($s, $j, $e - $j + 1);
          $j = $e + 1;
          next;
        }
        if ($d eq '`') {
          my $e = index($s, '`', $j + 1);
          if ($e < 0) { push @t, { error => 'an unclosed backtick' }; return @t }
          $word->{flags}{subst} = 1;
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
    if ($c eq '$' && substr($s, $i + 1, 1) eq '(') {
      my $e = close_paren($s, $i + 2, substr($s, $i + 2, 1) eq '(');
      if (!defined $e) { push @t, { error => 'an unclosed $(' }; last }
      $start_word->();
      my $lit = literal_cat(substr($s, $i + 2, $e - $i - 2));
      if (defined $lit) {
        $word->{text} .= $lit;
        $word->{raw} .= substr($s, $i, $e - $i + 1);
        $word->{flags}{quoted} = 1;
        $i = $e + 1;
        next;
      }
      $word->{flags}{subst} = 1;
      $word->{text} .= substr($s, $i, $e - $i + 1);
      $word->{raw} .= substr($s, $i, $e - $i + 1);
      $i = $e + 1;
      next;
    }
    if ($c eq '`') {
      my $e = index($s, '`', $i + 1);
      if ($e < 0) { push @t, { error => 'an unclosed backtick' }; last }
      $start_word->();
      $word->{flags}{subst} = 1;
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
      $word->{text} .= substr($s, $i, $e - $i + 1);
      $i = $e + 1;
      next;
    }
    # an arithmetic command (( ... )): one unit, read by its own text (a <<
    # in it shifts, it starts no here-document)
    if ($c eq '(' && substr($s, $i + 1, 1) eq '(' && !defined $word && (!@t || $t[-1]{op})) {
      my $e = close_paren($s, $i + 2, 1);
      if (!defined $e || substr($s, $e + 1, 1) ne ')') { push @t, { error => 'an unclosed ((' }; last }
      $e++;
      $start_word->();
      my $text = substr($s, $i, $e - $i + 1);
      $word->{text} .= $text;
      $word->{raw} .= $text;
      $word->{flags}{arith} = 1;
      $word->{flags}{subst} = 1 if $text =~ /\$\(|`/;
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
      else { push @{ $cur->{unread} }, 'command substitution or backticks' if $w->{flags}{subst}; push @{ $cur->{header} }, $w->{raw}; next }
    }
    # leading keywords and assignments
    if (!@{ $cur->{words} }) {
      if (($w->{text} eq 'for' || $w->{text} eq 'select') && !$w->{flags}{quoted}) { $header = 1; next }
      if ($w->{text} eq 'case' && !$w->{flags}{quoted}) { $in_case = 1; push @{ $cur->{unread} }, 'a case statement'; push @{ $cur->{words} }, 'case'; push @{ $cur->{wflags} }, $w->{flags}; next }
      # time -p: the option is time's, not a command word
      if ($w->{text} eq 'time' && !$w->{flags}{quoted}) { $after_time = 1; next }
      if ($after_time && $w->{text} eq '-p') { $after_time = 0; next }
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
        next;
      }
    }
    push @{ $cur->{words} }, $w->{text};
    push @{ $cur->{wflags} }, $w->{flags};
    push @{ $cur->{raw} }, $w->{raw};
  }
  $finish->('');
  my @out;
  for my $c (@cmds) {
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
  push @u, 'a variable as the command word' if @flags && ($flags[0]{var} || $flags[0]{subst});
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
  # a program file or module as the first operand: what comes in on stdin
  # is that program's data, not code
  my ($first) = grep { $words[$_] !~ /\A-/ } 1 .. $#words;
  my $runs_file = (defined $first && $words[$first] ne '-') || grep { $_ eq '-m' } @words[1 .. $#words];
  if ($name eq 'source' || $name eq '.') {
    push @{ $c->{unread} }, 'source or .';
  } elsif ($SHELL{$base}) {
    my ($ci) = grep { $words[$_] =~ /\A-[A-Za-z]*c[A-Za-z]*\z/ } 1 .. $#words;
    if (defined $ci) {
      my $script = $words[ $ci + 1 ];
      if (!defined $script) { push @{ $c->{unread} }, "$name -c with no command" }
      elsif ($flags[ $ci + 1 ]{subst} || $flags[ $ci + 1 ]{var}) { push @{ $c->{unread} }, "$name -c with an expansion" }
      else { push @out, commands($script, [@{ $c->{via} }, "$name -c"], $depth + 1, "$c->{scope}/c" . ++$SEQ) }
    } elsif (($c->{piped} || $c->{heredoc}) && !$runs_file) {
      push @{ $c->{unread} }, "a pipe, here-document or here-string into $name";
    }
  } elsif ($INTERP{$base}) {
    my $inline = $INLINE{$base} || qr/\A-[A-Za-z]*[ceE][A-Za-z]*\z|\A--(?:eval|command)\b|\A-e\S/;
    if (grep { $_ =~ $inline } @words[1 .. $#words]) {
      push @{ $c->{unread} }, "an inline program for $name";
    } elsif ($base =~ /awk\z/ && @words > 1) {
      push @{ $c->{unread} }, "an inline program for $name";
    } elsif (($base eq 'deno' || $base eq 'bun') && @words > 1 && $words[1] eq 'eval') {
      push @{ $c->{unread} }, "an inline program for $name";
    } elsif (($c->{piped} || $c->{heredoc}) && !$runs_file) {
      push @{ $c->{unread} }, "a pipe, here-document or here-string into $name";
    }
  } elsif ($name eq 'trap' && @words > 1 && $words[1] !~ /\A-/) {
    # trap's first argument is code bash runs later
    if ($flags[1]{subst} || $flags[1]{var}) { push @{ $c->{unread} }, 'trap of anything but a literal' }
    # (it runs later in this same shell, so in this command's scope)
    else { push @out, commands($words[1], [@{ $c->{via} }, 'trap'], $depth + 1, $c->{scope}) }
  } elsif ($name eq 'coproc') {
    push @{ $c->{unread} }, 'a coprocess';
  } elsif ($name eq 'eval') {
    if (grep { $_->{subst} || $_->{var} } @flags[1 .. $#flags]) { push @{ $c->{unread} }, 'eval of anything but a literal' }
    else { push @out, commands(join(' ', @words[1 .. $#words]), [@{ $c->{via} }, 'eval'], $depth + 1, $c->{scope}) }
  } elsif ($name eq 'env') {
    my $i = 1;
    while ($i <= $#words) {
      # -S splits a string into the command: that string is not read here
      if ($words[$i] =~ /\A-[A-Za-z0-9]*S|\A--split-string/) { push @{ $c->{unread} }, 'env -S'; return @out }
      if ($words[$i] =~ /\A-[iv0]+\z/ || $words[$i] =~ /\A--(?:ignore-environment|null|debug)\z/) { $i++; next }
      if ($words[$i] =~ /\A-[uC]\z|\A--(?:unset|chdir)\z/) { $i += 2; next }
      if ($words[$i] =~ /\A-[uC].|\A--(?:unset|chdir)=/) { $i++; next }
      if ($words[$i] =~ /\A[A-Za-z_][A-Za-z0-9_]*=/) { $i++; next }
      last;
    }
    $sub->($i, 'env');
  } elsif ($name eq 'xargs') {
    my $i = 1;
    while ($i <= $#words && $words[$i] =~ /\A-/) { $i += $words[$i] =~ /\A-[IEdLnPs]\z/ ? 2 : 1 }
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
    # the options of each prefix that take the next word as their value
    my %takes = (nice => qr/\A(?:-n|--adjustment)\z/, exec => qr/\A-a\z/, ionice => qr/\A-[cnp]\z/,
      sudo => qr/\A(?:-[ugCDhprtUT]|--(?:user|group|chdir|host|prompt|role|type|other-user|command-timeout))\z/,
      doas => qr/\A-[uC]\z/, stdbuf => qr/\A-[ioe]\z/);
    while ($i <= $#words && $words[$i] =~ /\A-/) { $i += ($takes{$name} && $words[$i] =~ $takes{$name}) ? 2 : 1 }
    $sub->($i, $name);
  }
  return @out;
}

1;
