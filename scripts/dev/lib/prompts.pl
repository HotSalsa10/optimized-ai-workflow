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
# Part two (step 6.2, M096; S5 and S8), the agent files under
# method/.claude/agents/: each opens with frontmatter whose name is the
# file's name, with effort: xhigh, the settings fragment's model and a
# tools: line that lists no delegation tool (Agent, Task, Skill,
# SendMessage); an agent that is not a gate (verdicts.txt) lists none of
# Bash, Edit, Write or NotebookEdit either; none sets memory, isolation,
# permissionMode, background, skills or mcpServers (hooks is left to the
# guard's G17, M137); and every gate in verdicts.txt has its file,
# method/.claude/agents/method/<gate>.md. A problem of a whole file is
# printed without a line number.
# Part three (step 6.3; S8 and S10), the skill folders, each a folder
# directly under method/.claude/skills/: its name starts method- and is on
# G6's skill list (@METHOD_SKILLS in method/scripts/method/lib/protect.pl,
# the list's one home, which the guard protects); it holds SKILL.md, whose
# frontmatter's name is the folder's name and which sets neither context:
# fork nor agent: (a forked skill hands its work to an agent that receipts
# do not see, A72). Every name on the list has its folder, except a name
# on %NOT_BUILT below, which may have none yet and must have none: once its
# folder comes, the name is taken off. `!` lines are left to
# disableSkillShellExecution (M138), and hooks: to the guard's G17 (M137).
use strict;
use warnings;
use File::Find ();
use JSON::PP ();

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

# --- part two (step 6.2, M096; docs/plans/step6.md S5 and S8): the agent
# files. The gates come from verdicts.txt (Verdicts::gates, its one
# reader) and the model from the settings fragment, so each has one home
# (M048). A gate's file is method/.claude/agents/method/<gate>.md, the
# file gate-receipt compares (receipt.pl); every other agent file is a
# drafting agent's.
my @delegation = qw(Agent Task Skill SendMessage);
my @writing = qw(Bash Edit Write NotebookEdit);
my @never_keys = qw(memory isolation permissionMode background skills mcpServers);
my (%gate, $gates_read, $model);
{
  my @g = eval {
    local $SIG{__DIE__};
    require "$root/method/scripts/method/lib/verdicts.pl";
    map { $_->[0] } Verdicts::gates(Verdicts::rows());
  };
  if (@g) {
    %gate = map { $_ => 1 } @g;
    $gates_read = 1;
  } else {
    (my $why = $@ || 'no gate') =~ s/\s+\z//;
    say_line("lint-prompts: could not read the gates from method/scripts/method/verdicts.txt ($why), so the agent files were not checked against them (M096)");
    $bad++;
  }
  my $frag = "$root/method/settings.fragment.json";
  my $d = eval {
    open my $h, '<:raw', $frag or die "cannot read it\n";
    local $/;
    my $text = <$h>;
    close $h;
    JSON::PP->new->decode($text);
  };
  if (ref $d eq 'HASH' && defined $d->{model} && !ref $d->{model} && $d->{model} ne '') {
    $model = $d->{model};
  } else {
    say_line("lint-prompts: could not read the model from method/settings.fragment.json, so no agent's model was checked against it (M096)");
    $bad++;
  }
}

# frontmatter LINES: the frontmatter's keys and values, {KEY => VALUE},
# with a block list's items (lines "  - X" under a key with no value) as
# an array; comment lines skipped; undef when the file has none
sub frontmatter {
  my (@lines) = @_;
  return undef unless @lines && $lines[0] =~ /\A---[ \t]*\z/;
  my (%fm, $last, $closed);
  for my $l (@lines[1 .. $#lines]) {
    if ($l =~ /\A---[ \t]*\z/) { $closed = 1; last }
    next if $l =~ /\A[ \t]*(?:#|\z)/;
    if ($l =~ /\A([A-Za-z][A-Za-z0-9_-]*)[ \t]*:[ \t]*(.*?)[ \t]*\z/) {
      $last = $1;
      $fm{$last} = $2;
    } elsif (defined $last && $l =~ /\A[ \t]+-[ \t]*(.*?)[ \t]*\z/) {
      $fm{$last} = [] unless ref $fm{$last};
      push @{ $fm{$last} }, $1;
    }
  }
  return $closed ? \%fm : undef;
}
sub unquote { my ($v) = @_; $v = '' unless defined $v; $v =~ s/\A(["'])(.*)\1\z/$2/; return $v }

# agent_problems NAME LINES: the problems of one agent file, each a text
sub agent_problems {
  my ($name, @lines) = @_;
  my ($stem) = $name =~ m{([^/]+)\.md\z};
  my $fm = frontmatter(@lines);
  return ('no frontmatter: an agent file opens with a --- line and closes its frontmatter with another (M096)') unless $fm;
  my $is_gate = $gate{$stem} && $name eq "method/.claude/agents/method/$stem.md";
  my @p;
  my $n = unquote($fm->{name});
  push @p, "the name \"$n\" is not the file's name, $stem: the client finds an agent by its name, and gate-receipt by the file (M096)" if $n ne $stem;
  if (!exists $fm->{effort}) {
    push @p, 'no effort: line; a method agent runs at effort: xhigh (R5)';
  } elsif (unquote($fm->{effort}) ne 'xhigh') {
    push @p, 'the effort is "' . unquote($fm->{effort}) . '", not xhigh (R5)';
  }
  if (!exists $fm->{model}) {
    push @p, 'no model: line; a method agent names the settings fragment\'s model' . (defined $model ? " ($model)" : '');
  } elsif (defined $model && unquote($fm->{model}) ne $model) {
    push @p, 'the model "' . unquote($fm->{model}) . "\" is not the settings fragment's model, $model (one home for the model ID, M048)";
  }
  if (!exists $fm->{tools}) {
    push @p, 'no tools: line; a method agent lists its tools, or it gets every tool, the delegation tools among them (M096)';
  } else {
    my @t = ref $fm->{tools} ? @{ $fm->{tools} } : do { (my $v = $fm->{tools}) =~ s/\A\[(.*)\]\z/$1/; split /,/, $v };
    @t = grep { $_ ne '' } map { my $x = unquote(do { (my $y = $_) =~ s/\A[ \t]+|[ \t]+\z//g; $y }); $x =~ s/\(.*\z//; $x } @t;
    push @p, 'the tools: line lists no tool (M096)' unless @t;
    my %has = map { $_ => 1 } @t;
    for my $d (grep { $has{$_} } @delegation) {
      push @p, "the tools: line lists $d, a delegation tool: a method agent hands no work on, which receipts would not see (A72, M096)";
    }
    unless ($is_gate) {
      for my $w (grep { $has{$_} } @writing) {
        push @p, "the tools: line lists $w, but this is not a gate in verdicts.txt: a drafting agent runs no command and writes no file (A6, S5)";
      }
    }
  }
  for my $k (grep { exists $fm->{$_} } @never_keys) {
    push @p, "the key $k: is set; a method agent sets none of " . join(', ', @never_keys) . ' (docs/plans/step6.md S5)';
  }
  return @p;
}

# --- part three (step 6.3; docs/plans/step6.md S8 and S10): the skill
# folders against G6's skill list, read from protect.pl (its one home,
# M048); a list that cannot be read is a problem, never a pass.
# the listed skills that steps 6.4 and 6.5 build: each may have no folder
# yet, and each is taken off here when its folder comes (a name here whose
# folder exists is a problem)
my %NOT_BUILT = map { $_ => 1 } qw(method-start method-plan method-design);
my (@listed, $list_read);
{
  my $ok = eval {
    local $SIG{__DIE__};
    require "$root/method/scripts/method/lib/protect.pl";
    1;
  };
  no warnings 'once';
  if ($ok && defined &Protect::skills_re) {
    @listed = @Protect::METHOD_SKILLS;
    $list_read = 1;
  } else {
    (my $why = $@ || 'no list') =~ s/\s+\z//;
    say_line("lint-prompts: could not read G6's skill list from method/scripts/method/lib/protect.pl ($why), so the skill folders were not checked against it (S10)");
    $bad++;
  }
}
my $skills_dir = "$root/method/.claude/skills";
my @skill_dirs;
if (opendir my $sd, $skills_dir) {
  @skill_dirs = sort grep { !/\A\.\.?\z/ && -d "$skills_dir/$_" } readdir $sd;
  closedir $sd;
}

# skill_problems DIR LINES: the problems of the skill folder DIR, whose
# SKILL.md holds LINES (undef: there is none), each a text
sub skill_problems {
  my ($dir, $lines) = @_;
  my @p;
  push @p, "the folder's name does not start method-: the method's skills are method-<name>, so a personal skill or the client's own commands do not clash with them (S3)" unless $dir =~ /\Amethod-/;
  if ($list_read && !grep { $_ eq $dir } @listed) {
    push @p, "the folder is not on G6's skill list (\@METHOD_SKILLS in method/scripts/method/lib/protect.pl), so the guard would let Claude change it (S10)";
  }
  push @p, "the skill $dir has its folder now: take it off %NOT_BUILT in scripts/dev/lib/prompts.pl" if $NOT_BUILT{$dir};
  return (@p, 'no SKILL.md: a method skill folder holds its SKILL.md') unless $lines;
  my $fm = frontmatter(@$lines);
  return (@p, 'no frontmatter in SKILL.md: a method skill opens with a --- line and closes its frontmatter with another') unless $fm;
  my $n = unquote($fm->{name});
  push @p, "the name \"$n\" in SKILL.md is not the folder's name, $dir: G6's list and the slash command go by the folder (S3, S10)" if $n ne $dir;
  push @p, 'SKILL.md sets context: fork: a forked skill hands its work to an agent that receipts do not see (A72)' if exists $fm->{context} && unquote($fm->{context}) eq 'fork';
  push @p, 'SKILL.md sets the key agent:; a method skill runs in the main session, and an agent it names would do work that receipts do not see (A72)' if exists $fm->{agent};
  return @p;
}

for my $file (sort @files) {
  (my $name = $file) =~ s{\A\Q$root\E/}{};
  open my $fh, '<:raw', $file or do { say_line("lint-prompts: cannot read $name"); $bad++; next };
  $examined++;
  my $is_rules = $name =~ m{\Amethod/\.claude/rules/};
  my $is_agent = $name =~ m{\Amethod/\.claude/agents/};
  my @all;
  my $n = 0;
  while (my $line = <$fh>) {
    $n++;
    $line =~ s/\n\z//;
    push @all, $line;
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
  if ($is_agent) {
    s/\r\z// for @all;
    say_line("lint-prompts: $name: $_"), $bad++ for agent_problems($name, @all);
  }
}
for my $dir (@skill_dirs) {
  my $sf = "$skills_dir/$dir/SKILL.md";
  my $lines;
  if (-f $sf) {
    if (open my $h, '<:raw', $sf) {
      $lines = [map { my $l = $_; $l =~ s/\r?\n\z//; $l } <$h>];
      close $h;
    } else {
      say_line("lint-prompts: cannot read method/.claude/skills/$dir/SKILL.md");
      $bad++;
      next;
    }
  }
  say_line("lint-prompts: method/.claude/skills/$dir/: $_"), $bad++ for skill_problems($dir, $lines);
}
if ($list_read) {
  my @waiting;
  for my $l (@listed) {
    next if -d "$skills_dir/$l";
    if ($NOT_BUILT{$l}) { push @waiting, $l; next }
    say_line("lint-prompts: G6's skill list (\@METHOD_SKILLS in method/scripts/method/lib/protect.pl) names $l, but method/.claude/skills/$l/ does not exist: the list names the method's skill folders, no more (S10)");
    $bad++;
  }
  say_line('lint-prompts: on G6\'s skill list and not built yet (steps 6.4 and 6.5): ' . join(', ', @waiting)) if @waiting;
}
if ($gates_read) {
  for my $g (sort keys %gate) {
    next if -f "$root/method/.claude/agents/method/$g.md";
    say_line("lint-prompts: the gate $g in verdicts.txt has no file method/.claude/agents/method/$g.md; gate-receipt reads that file (M096)");
    $bad++;
  }
}
print "EXAMINED $examined\nBAD $bad\n";
