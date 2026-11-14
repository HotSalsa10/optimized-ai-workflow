#!/usr/bin/env perl
# Checks the method's prompt text. Called by scripts/dev/lint-prompts.sh.
# Usage: perl prompts.pl ROOT
# Walks ROOT/method/.claude/agents, rules and skills (File::Find: bash 3.2
# has no **) and reads every .md file there. Prints one line per problem,
# then "EXAMINED n" and "BAD n". A folder that does not exist is skipped;
# the caller fails when nothing was examined.
# Rules (M095, part one of step 6's lint; docs/plans/step6.md S8):
# - no "think carefully" or "think step by step" line;
# - no fixed-format reasoning request: a reasoning tag such as <thinking>,
#   or a phrase such as "reason in this format";
# - no emphasis word in capitals: IMPORTANT, MUST, NEVER, ALWAYS, REMEMBER,
#   DO NOT. A short denylist: the method's own terms in capitals (FULL,
#   LIGHT, CRITICAL, HIGH_RISK_PATHS, the verdict words) pass, and so do
#   the words in lower case, inside a longer word or in an identifier;
# - in the rules files (method/.claude/rules/), an HTML comment is a line
#   of its own, from the line's first character to its last. The client
#   drops such a line and keeps a comment that shares a line with text, or
#   has spaces before it (measured at 2.1.316 and 2.1.319, plan F4), so the
#   rule IDs cost nothing only on a line of their own. Two comments on one
#   line, or one over several lines, are refused too: the budget counts
#   them, and they are not needed.
use strict;
use warnings;
use File::Find ();

# Prints one line of output. Control characters taken from file names or
# content (also UTF-8 C1 controls) are shown as \xNN, and the CI runner's
# old command form (## [) is broken up, so text from a file cannot start a
# new line of output, move the cursor or reach the CI runner as a command.
sub say_line {
  my ($s) = @_;
  $s =~ s/([\x00-\x1F\x7F])/sprintf('\\x%02X', ord $1)/ge;
  $s =~ s/\xC2([\x80-\x9F])/sprintf('\\xC2\\x%02X', ord $1)/ge;
  $s =~ s/##\[/#\\x23[/g;
  print "$s\n";
}

my $root = shift @ARGV;
die "usage: perl prompts.pl ROOT\n" unless defined $root && -d $root && !@ARGV;

my $think_re = qr/\bthink(?:ing)?\s+(?:(?:very|really|more)\s+)?(?:carefully|step[\s-]+by[\s-]+step)\b/i;
my $tag_re = qr/<\s*\/?\s*(?:thinking|think|reasoning|scratchpad|thoughts?|inner[_-]?monologue)\b[^>]*>/i;
my $format_re = qr/\b(?:reason|think)(?:ing)?\s+(?:in|using|with)\s+(?:this|the\s+following|the\s+given)\s+(?:format|structure|template)\b|\b(?:format|structure|template)\s+(?:for|of)\s+your\s+(?:reasoning|thinking|thoughts)\b/i;
my $shout_re = qr/(?<![A-Za-z0-9_-])(IMPORTANT|MUST|NEVER|ALWAYS|REMEMBER|DO[ \t]+NOT)(?![A-Za-z0-9_-])/;
my $comment_alone_re = qr/\A<!--(?:(?!-->|<!--).)*-->\z/;

my @files;
for my $part (qw(agents rules skills)) {
  my $dir = "$root/method/.claude/$part";
  next unless -d $dir;
  File::Find::find({ no_chdir => 1, wanted => sub { push @files, $_ if /\.md\z/ && -f $_ } }, $dir);
}

my ($examined, $bad) = (0, 0);
for my $file (sort @files) {
  (my $name = $file) =~ s{\A\Q$root\E/}{};
  open my $fh, '<:raw', $file or do { say_line("lint-prompts: cannot read $name"); $bad++; next };
  $examined++;
  my $is_rules = $name =~ m{\Amethod/\.claude/rules/};
  my $n = 0;
  while (my $line = <$fh>) {
    $n++;
    $line =~ s/\n\z//;
    my $problem = sub { say_line("lint-prompts: $name:$n: $_[0]"); $bad++ };
    $problem->('a "think carefully" or "think step by step" line (M095)') if $line =~ $think_re;
    $problem->('a fixed-format reasoning request, a reasoning tag or "reason in this format" (M095)') if $line =~ $tag_re || $line =~ $format_re;
    while ($line =~ /$shout_re/g) {
      (my $w = $1) =~ s/[ \t]+/ /;
      $problem->("the emphasis word $w in capitals; write the rule plainly (M095)");
    }
    if ($is_rules && ($line =~ /<!--|-->/) && $line !~ $comment_alone_re) {
      $problem->('a comment not alone on its line (text, a space or another comment beside it) or running over lines; the client keeps such a line or may, so it costs bytes in every session: put each comment on a line of its own');
    }
  }
  close $fh;
}
print "EXAMINED $examined\nBAD $bad\n";
