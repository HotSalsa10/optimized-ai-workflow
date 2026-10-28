#!/usr/bin/env perl
# Checks GitHub Actions workflow files and action files. Called by
# scripts/dev/lint-workflows.sh.
# Usage: perl workflows.pl FILE...
# A file under .github/workflows/ is a workflow; any other file is an action
# file (action.yml or action.yaml), which is checked for its "uses:" only.
# Prints one line per problem, then "EXAMINED n", "ACTIONS n" and "BAD n".
# Rules:
# - every "uses:" is pinned: an action to a full 40-character commit SHA, a
#   docker:// image to an @sha256 digest. A local ./action is checked through
#   its own action file;
# - a workflow sets top-level "permissions:";
# - no "permissions:" value, top-level or in a job, is write-all;
# - every job sets "timeout-minutes:" at job level (any indentation), to a
#   number or a ${{ }} expression; a step's own timeout does not count;
# - a "permissions:" with no value has its permissions listed under it.
#
# It reads YAML one line at a time, so it accepts only plain YAML whose
# meaning a line reader can be sure of, and every other line is a finding.
# Outside a block scalar (run: |), each line must be blank, a comment, or
#   (indent)(- )KEY:        KEY made of letters, digits, _ . and -
#   (indent)(- )KEY: VALUE
#   (indent)- VALUE
# where VALUE is a plain scalar, a block scalar indicator (| or >), a quoted
# scalar closed on the same line (double quotes without backslashes), {} or
# [], or a one-line [list] of plain or quoted scalars, each optionally
# followed by a comment. A line indented deeper than a key or list item that
# already has a plain value continues that value, so it is reported too.
# Anything else (flow mappings, quoted or explicit keys, tags, anchors,
# aliases, escapes, values over several lines, line breaks other than LF) is
# reported, not guessed at. Trailing spaces are ignored. A UTF-8 byte-order mark
# at the start of a file is ignored, and "---" may open a file.
use strict;
use warnings;

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

my $key_re = qr/[A-Za-z0-9_][A-Za-z0-9_.-]*/;
# a plain scalar: no indicator first, no ": " or " #" inside, no ":" at the end
my $plain_re = qr/(?:[^\s\-?:,\[\]{}#&*!|>'"%@`]|[-?:](?=\S))(?:[^:#]|:(?!\s|$)|(?<!\s)#)*(?<![\s:])/;
my $single_re = qr/'(?:[^']|'')*'/;
my $double_re = qr/"[^"\\]*"/;
my $flow_item_re = qr/(?:[^\s\[\]{},:'"#&*!|>%@`][^\[\]{},:'"#]*?|$single_re|$double_re)/;
my $flow_seq_re = qr/\[\s*(?:$flow_item_re\s*(?:,\s*$flow_item_re\s*)*)?\]/;
my $comment_re = qr/(?:\s+#.*)?/;
my $value_re = qr/(?:$plain_re|[|>][-+0-9]*|$single_re|$double_re|\{\}|$flow_seq_re)$comment_re/;

# A scalar value without its comment and quotes.
sub clean {
  my ($v) = @_;
  $v = '' unless defined $v;
  $v =~ s/\s+#.*$// unless $v =~ /^["']/;
  $v =~ s/^(["'])(.*?)\1(?:\s+#.*)?$/$2/;
  $v =~ s/^\s+|\s+$//g;
  return $v;
}

my ($examined, $actions, $bad) = (0, 0, 0);
for my $file (@ARGV) {
  open my $fh, '<:raw', $file or do { say_line("workflows: cannot read $file"); $bad++; next };
  my $text = do { local $/; <$fh> };
  close $fh;
  $text = '' unless defined $text;
  $text =~ s/^\xEF\xBB\xBF//;    # a byte-order mark
  my $is_workflow = $file =~ m{(?:^|/)\.github/workflows/[^/]+\.ya?ml$};
  if ($is_workflow) { $examined++ } else { $actions++ }
  my $problem = sub {
    say_line(defined $_[0] ? "workflows: $file:$_[0]: $_[1]" : "workflows: $file: $_[1]");
    $bad++;
  };

  my @lines = split /\n/, $text, -1;
  pop @lines if @lines && $lines[-1] eq '';
  my ($has_permissions, $in_jobs, $job_indent, $job, $child_indent) = (0, 0, undef, undef, undef);
  my (%timeout, @order);
  my $block_indent;    # set while inside a block scalar (run: |)
  my $scalar_limit;    # a deeper line than this continues the last plain value
  for (my $i = 0; $i < @lines; $i++) {
    my $l = $lines[$i];
    my $n = $i + 1;
    $l =~ s/\r\z//;    # CRLF is the line-endings check's business
    $l =~ s/[ \t]+\z//;
    # YAML also ends a line at CR, NEL, LS and PS; a reader that splits on LF
    # alone would see two lines as one.
    if ($l =~ /\r|\xC2\x85|\xE2\x80[\xA8\xA9]/) {
      $problem->($n, 'a line break other than LF (a CR, NEL, LS or PS) cannot be read; use LF');
      next;
    }
    next if $l =~ /^\s*(?:#.*)?$/;
    my ($lead) = $l =~ /^( *)/;
    my $ind = length $lead;
    if (defined $block_indent) {
      next if $ind > $block_indent;
      undef $block_indent;
    }
    next if $n == 1 && $l =~ /^---\s*$/;
    if (defined $scalar_limit) {
      my $limit = $scalar_limit;
      undef $scalar_limit;
      if ($ind > $limit) {
        $problem->($n, 'this line continues the value above it over several lines; write the value on one line or as a block scalar');
        next;
      }
    }

    # (the parts are copied out before the value is tested, because a second
    # match resets $1, $2 and $3)
    my ($dash, $key, $value);
    my @kv = $l =~ /^ *((?:- +)*)($key_re):(?: +(.*))?$/;
    $kv[2] = undef if @kv && defined $kv[2] && $kv[2] =~ /^#/;    # KEY:  # a comment
    my @item = $l =~ /^ *((?:- +)+)(.*)$/;
    if (@kv && (!defined $kv[2] || $kv[2] =~ /^$value_re$/)) {
      ($dash, $key, $value) = ($kv[0], $kv[1], defined $kv[2] ? $kv[2] : '');
    } elsif (@item && $item[1] =~ /^$value_re$/) {
      ($dash, $value) = @item;
    } else {
      $problem->($n, 'this line is not plain YAML this check can read (a flow mapping, a quoted or explicit key, a tag, an anchor, an escape, or a value over several lines); write it as key: value on one line');
      next;
    }
    my $v = clean($value);
    # a plain or quoted value: a deeper next line would continue it
    if (length $v && $value !~ /^[|>]/) {
      $scalar_limit = defined $key ? $ind + length($dash) : $ind + length($dash) - 2;
    }
    if ($value =~ /^[|>]/) {
      $problem->($n, "a block scalar as the value of $key cannot be checked; write it on one line")
        if defined $key && $key =~ /^(?:permissions|uses|timeout-minutes)$/;
      # the block's text is everything indented deeper than this key
      $block_indent = $ind + length($dash);
    }

    next unless defined $key;
    if ($key eq 'uses') {
      if (!length $v) {
        $problem->($n, 'a "uses:" without a value');
      } elsif ($v =~ m{^\./}) {
        # a local action: its own action file is checked
      } elsif ($v =~ m{^docker://}) {
        $problem->($n, "'$v' is not pinned to an \@sha256 digest") unless $v =~ /\@sha256:[0-9a-f]{64}$/;
      } elsif ($v !~ /^[^\s@]+\@[0-9a-f]{40}$/) {
        $problem->($n, "'$v' is not pinned to a commit SHA");
      }
    }
    next unless $is_workflow;
    if ($key eq 'permissions') {
      $has_permissions = 1 if $ind == 0 && !length $dash;
      if (!length $v && $value !~ /^(?:\{\}|\[\])/) {
        my $j = $i + 1;
        $j++ while $j < @lines && $lines[$j] =~ /^\s*(?:#.*)?\r?$/;
        my ($next_lead) = $j < @lines ? $lines[$j] =~ /^( *)/ : ('');
        $problem->($n, '"permissions:" has no value and nothing listed under it; list each permission, or use {}')
          unless $j < @lines && length($next_lead) > $ind + length($dash);
      }
      $problem->($n, 'permissions are write-all; grant only what is needed') if $v eq 'write-all';
    }
    if ($ind == 0 && !length $dash) {
      $in_jobs = $key eq 'jobs';
      ($job_indent, $job) = (undef, undef);
      next;
    }
    next unless $in_jobs;
    $job_indent = $ind unless defined $job_indent;
    if ($ind == $job_indent) {
      $job = $key;
      $child_indent = undef;
      push @order, $job unless exists $timeout{$job};
      $timeout{$job} = 0;
      next;
    }
    next unless defined $job && $ind > $job_indent;
    $child_indent = $ind unless defined $child_indent;
    $timeout{$job} = 1 if $ind == $child_indent && !length($dash) && $key eq 'timeout-minutes' && $v =~ /^(?:\d+|\$\{\{.*\}\})$/;
  }
  next unless $is_workflow;
  $problem->(undef, 'no top-level permissions:') unless $has_permissions;
  for my $j (@order) {
    $problem->(undef, "job '$j' has no timeout-minutes") unless $timeout{$j};
  }
}
print "EXAMINED $examined\nACTIONS $actions\nBAD $bad\n";
