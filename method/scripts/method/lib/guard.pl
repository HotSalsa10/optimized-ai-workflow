#!/usr/bin/env perl
# The guard's rules (step 5.5 onward; docs/plans/step5.md, section 6.2;
# DECISIONS A50 and A57). .claude/hooks/method/guard.sh runs this with the
# hook's JSON input on standard input. It ends with 0 (let the call
# through) or $Hook::BLOCK (refuse it, one line on stderr naming the rule
# and what to do instead). Each refusal is logged with fixed fields only
# (lib/log.pl, M072): the time, the rule, the tool and a hash of the input.
#
# The rules built so far:
#   G0 cannot-tell (M128): a call the guard cannot read, when it touches
#      something the guard watches: input that is not one JSON object, a
#      command that is not text, or a simple command with a shape on the
#      reader's "cannot read" list (lib/shell.pl) that runs git, gh, claude,
#      curl or wget, or whose own text names them or one of the method's
#      files (judge_command).
#   G1 perl-missing (M128): perl or JSON::PP missing (guard.sh, and here).
#   G2 powershell (M129): every PowerShell call; the method's checks read
#      bash.
# A call the rules say nothing about is let through.
package Guard;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;

my $lib = dirname(File::Spec->rel2abs(__FILE__));
require File::Spec->catfile($lib, 'hook.pl');
require File::Spec->catfile($lib, 'shell.pl');

our $WAY_OUT = 'if the guard is wrong, see .claude/hooks/method/README.md, "When the guard blocks something it should not"';

# what the guard watches: a call that names one may not hold a shape the
# reader cannot read (G0). A watched command is git, gh, claude, curl or
# wget standing as a word of its own (so /tmp/claude-0 or github.com do not
# count); a watched path is one of the method's files, its settings, or
# git's own config and hooks.
our $WATCHED_WORD = qr{(?:\A|[\s;&|(`'"=])(?:[\w./-]*/)?(?:git|gh|claude|curl|wget)(?=\z|[\s;&|)`'"])};
our $WATCHED_PATH = qr{\.claude/(?:hooks/method|agents/method|rules/method|method-local|settings(?:\.local)?\.json)|(?:\A|[\s/'"=])scripts/method\b|\.git/(?:hooks|config)\b|\.gitconfig\b|\.config/git\b|managed-settings}i;
our $WATCHED = qr{$WATCHED_WORD|$WATCHED_PATH};

sub sha256_hex {
  require Digest::SHA;
  return Digest::SHA::sha256_hex($_[0]);
}

# log RULE TOOL RAW: one line in .method/local/guard.log of the project; a
# failure to log never changes the answer
sub log_refusal {
  my ($rule, $tool, $raw, $in) = @_;
  my $root = $ENV{CLAUDE_PROJECT_DIR};
  $root = $in->{cwd} if (!defined $root || !-d $root) && ref $in eq 'HASH' && defined $in->{cwd} && !ref $in->{cwd};
  return unless defined $root && -d $root;
  (my $t = defined $tool && !ref $tool ? $tool : 'unknown') =~ s/[^A-Za-z0-9_.:-]/_/g;
  $t = substr($t, 0, 128) || 'unknown';
  eval {
    require File::Spec->catfile($lib, 'log.pl');
    Log::append($root, '.method/local/guard.log', undef, rule => $rule, tool => $t, hash => sha256_hex($raw));
    1;
  };
}

# refuse RULE TEXT: the one line Claude Code shows, and the log line
sub refuse {
  my ($rule, $text, $tool, $raw, $in) = @_;
  log_refusal($rule, $tool, $raw, $in);
  return Hook::block("guard $rule: $text");
}

# the shapes whose meaning can come from elsewhere in the call: judged
# against the whole call, not their own text
my $WIDE = qr{variable as the command word|eval of anything|-c with an expansion|could not split|case statement|nested too deep|trap of anything};
# what lets an inline program start another program
our $STARTS = qr{\b(?:system|exec\w*|qx|popen\w*|spawn\w*|execSync|execFile\w*|subprocess|child_process|Popen|Runtime|ProcessBuilder|IPC::\w+|open[23]|shell_exec|passthru|proc_open|Start-Process|Invoke-Expression|iex|Process)\b|\bDeno\.(?:Command|run)\b|`|%x[\[(\x7B<]|\bos\.(?:system|popen|exec\w*|spawn\w*)|open\s*\(?[^;]*["']\s*\||\|\s*["']\s*\)|["']-\|["']|\|-|-\|};

# judge_command TEXT: () to let it through, or (RULE, TEXT) to refuse. A
# simple command the reader cannot read is refused (G0) when it runs git,
# gh, claude, curl or wget itself, or when its own text (its words, its
# here-document, what is piped into it) names something watched; for the
# shapes whose meaning can come from elsewhere ($WIDE), when the whole call
# does.
sub judge_command {
  my ($cmd) = @_;
  my @cmds = Shell::commands($cmd);
  # (with ANSI-C quoting decoded, also where the reader stopped early)
  (my $decoded = $cmd) =~ s/\$'((?:[^'\\]|\\.)*)'/Shell::ansi_c($1)/ge;
  my $call_watched = join("\n", $cmd, $decoded, map { join(' ', @{ $_->{words} }, $_->{hbody} // '') } @cmds) =~ $WATCHED;
  for my $c (@cmds) {
    next unless @{ $c->{unread} };
    # (its assignments and a for header's words, as written, are its own
    # text too: what they run is judged)
    my $words = join(' ', @{ $c->{assigns_raw} || [] }, @{ $c->{raw} || [] }, @{ $c->{words} }, map { $_->[1] } @{ $c->{redirs} });
    my $own = join(' ', $words, $c->{hbody} // '', $c->{pipe_from} // '');
    my $wide = grep { $_ =~ $WIDE } @{ $c->{unread} };
    # code from a variable or a substitution, piped or written into a shell
    # or an interpreter, is not this command's own text
    $wide ||= (grep { /\Aa pipe, here-document or here-string into / } @{ $c->{unread} })
      && (($c->{pipe_from} // '') =~ /[\$`]/ || ($c->{hbody} // '') =~ /[\$`]/) ? 1 : 0;
    my $inline_only = !grep { $_ !~ /\Aan inline program for / } @{ $c->{unread} };
    my $glob_only = !grep { $_ ne 'a glob or a brace in a write target' } @{ $c->{unread} };
    # (a command that runs git, gh, claude, curl or wget names it in its
    # own text, so it is caught below)
    # (PowerShell's inline program is shell commands: a watched word runs)
    my $shell_like = @{ $c->{words} } && $c->{words}[0] =~ m{(?:\A|[/\\])(?:pwsh|powershell)(?:\.exe)?\z}i;
    # a glob or brace in the command word hides which program runs at all
    my $hit = (grep { $_ eq 'a glob or a brace in the command word' } @{ $c->{unread} }) ? 1
      : $wide ? $call_watched
      # an inline program: what is piped into it is data, not code; it
      # touches a watched command only by starting a program
      : $inline_only ? ($words =~ $WATCHED_PATH || ($words =~ $WATCHED_WORD && ($shell_like || $words =~ $STARTS)))
      # a glob can hide which file is written: any write near the method's
      # folders or git's own
      : $glob_only ? (join(' ', map { $_->[1] } grep { $_->[0] =~ />/ } @{ $c->{redirs} }) =~ m{\.claude|scripts/method|\.git\b|gitconfig}i || $own =~ $WATCHED)
      : $own =~ $WATCHED;
    next unless $hit;
    my $why = $c->{unread}[0];
    if (grep { $_ eq 'a glob or a brace in the command word' } @{ $c->{unread} }) {
      return ('G0', "this command's name holds a glob or a brace, so which program runs cannot be told; write the program's name out ($WAY_OUT)");
    }
    return ('G0', "this command holds $why, which the guard cannot read with confidence, in a call that names git, gh, claude, curl, wget or a method file;"
      . " write it as plain commands, one per line, with every word written out (a commit message or PR body can go on stdin: git commit -F - with a here-document);"
      . " if that is refused too, stop and tell the owner what you needed ($WAY_OUT)");
  }
  return ();
}

sub main {
  binmode STDIN, ':raw';
  # at most one byte over the limit is read, so a huge input is refused
  # without being held whole
  my $raw = '';
  my $max = defined $Hook::MAX ? $Hook::MAX : 4 * 1024 * 1024;
  while (length $raw <= $max) {
    my $n = read STDIN, $raw, 65536, length $raw;
    last unless $n;
  }
  open my $fh, '<', \$raw or die;
  my ($in, $err) = Hook::read_input($fh);
  if (!$in) {
    my $rule = $err =~ /JSON::PP/ ? 'G1' : 'G0';
    return refuse($rule, "the guard could not read this call ($err), so it is refused; try the call again, and if it is refused again tell the owner ($WAY_OUT)", undef, $raw, undef);
  }
  my $tool = $in->{tool_name};
  $tool = '' unless defined $tool && !ref $tool;
  my $input = $in->{tool_input};
  if ($tool eq 'PowerShell') {
    return refuse('G2', "the PowerShell tool is refused in method projects: the method's checks read bash; use the Bash tool ($WAY_OUT)", $tool, $raw, $in);
  }
  if ($tool eq 'Bash' || $tool eq 'Monitor') {
    my $cmd = ref $input eq 'HASH' ? $input->{command} : undef;
    if (!defined $cmd || ref $cmd) {
      return refuse('G0', "this $tool call has no command text the guard can read, so it is refused; give the command as plain text ($WAY_OUT)", $tool, $raw, $in);
    }
    my ($rule, $text) = judge_command($cmd);
    return refuse($rule, $text, $tool, $raw, $in) if $rule;
  }
  return 0;
}

return 1 if caller;
exit main();
