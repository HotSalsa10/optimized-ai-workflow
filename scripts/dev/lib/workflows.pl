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
# - every job sets "timeout-minutes:" at job level (any indentation).
# The lint reads YAML one line at a time, so it fails closed: a form it
# cannot read reliably is a finding. That covers flow mappings ({ ... }), a
# flow sequence holding a mapping, YAML tags (!!str), anchors (&a), aliases
# (*a) and merge keys (<<:). Keys may be quoted, and a value may sit on the
# next, deeper line. Text inside a block scalar (run: |) is not read.
use strict;
use warnings;

# Prints one line of output. Control characters taken from file names or
# content are shown as \xNN, so text from a file can never start a new line
# of output, move the cursor or reach the CI runner as a command.
sub say_line {
  my ($s) = @_;
  $s =~ s/([\x00-\x1F\x7F])/sprintf('\\x%02X', ord $1)/ge;
  print "$s\n";
}

# A scalar value without its comment and quotes.
sub clean {
  my ($v) = @_;
  $v = '' unless defined $v;
  $v =~ s/(?:^|\s+)#.*$//;
  $v =~ s/^\s+|\s+$//g;
  $v =~ s/^(["'])(.*)\1$/$2/;
  return $v;
}

my ($examined, $actions, $bad) = (0, 0, 0);
for my $file (@ARGV) {
  open my $fh, '<', $file or do { say_line("workflows: cannot read $file"); $bad++; next };
  my @lines = map { my $l = $_; $l =~ s/\r?\n\z//; $l } <$fh>;
  close $fh;
  my $is_workflow = $file =~ m{(?:^|/)\.github/workflows/[^/]+\.ya?ml$};
  if ($is_workflow) { $examined++ } else { $actions++ }
  my $problem = sub {
    say_line(defined $_[0] ? "workflows: $file:$_[0]: $_[1]" : "workflows: $file: $_[1]");
    $bad++;
  };

  my ($has_permissions, $in_jobs, $job_indent, $job, $child_indent) = (0, 0, undef, undef, undef);
  my (%timeout, @order);
  my $block_indent;    # set while inside a block scalar (run: |)
  for (my $i = 0; $i < @lines; $i++) {
    my $l = $lines[$i];
    my $n = $i + 1;
    next if $l =~ /^\s*(?:#|$)/;
    my ($lead) = $l =~ /^( *)/;
    my $ind = length $lead;
    if (defined $block_indent) {
      next if $ind > $block_indent;
      undef $block_indent;
    }

    # key: value, with an optional list dash and an optional quoted key
    my ($dash, $key, $value);
    if ($l =~ /^\s*(-\s+)?(["']?)([A-Za-z0-9_<-]+)\2\s*:(?:\s+(.*))?$/) {
      ($dash, $key, $value) = ($1, $3, defined $4 ? $4 : '');
    } elsif ($l =~ /^\s*-\s+(.*)$/) {
      $value = $1;
    } else {
      $value = '';
    }
    my $v = clean($value);
    # the value as written (quotes kept), without its comment and without
    # ${{ }} expressions, which are not YAML structure
    (my $plain = $value) =~ s/(?:^|\s+)#.*$//;
    $plain =~ s/\$\{\{.*?\}\}//g;
    $plain =~ s/^\s+|\s+$//g;

    # a value on the next, deeper line belongs to this key
    my $next_value = sub {
      for (my $j = $i + 1; $j < @lines; $j++) {
        next if $lines[$j] =~ /^\s*(?:#|$)/;
        my ($nl) = $lines[$j] =~ /^( *)/;
        return undef if length($nl) <= $ind;
        return $lines[$j] =~ /^\s*[^\s:#][^:#]*$/ ? clean($lines[$j]) : undef;
      }
      return undef;
    };

    # fail closed on forms a line reader cannot follow
    if ($plain =~ /^\{/ || $l =~ /^\s*(?:-\s+)?\{/ || ($plain =~ /^\[/ && $plain =~ /[{:]/)) {
      $problem->($n, 'a flow mapping ({ ... }) cannot be checked; write it in block style');
    }
    if ($plain =~ /^[!&*]/ || (defined $key && $key eq '<<')) {
      $problem->($n, 'YAML tags, anchors, aliases and merge keys cannot be checked; write the value out');
    }
    if ($v =~ /^[|>][-+0-9]*$/) { $block_indent = $ind; }

    next unless defined $key;
    if ($key eq 'uses') {
      my $ref = length $v ? $v : $next_value->();
      if (!defined $ref || !length $ref) {
        $problem->($n, 'a "uses:" without a value this lint can read');
      } elsif ($ref =~ m{^\./}) {
        # a local action: its own action file is checked
      } elsif ($ref =~ m{^docker://}) {
        $problem->($n, "'$ref' is not pinned to an \@sha256 digest") unless $ref =~ /\@sha256:[0-9a-f]{64}$/;
      } elsif ($ref !~ /^[^\s@]+\@[0-9a-f]{40}$/) {
        $problem->($n, "'$ref' is not pinned to a commit SHA");
      }
    }
    next unless $is_workflow;
    if ($key eq 'permissions') {
      $has_permissions = 1 if $ind == 0 && !$dash;
      my $p = length $v ? $v : $next_value->();
      $problem->($n, 'permissions are write-all; grant only what is needed') if defined $p && $p eq 'write-all';
    }
    if ($ind == 0) {
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
    $timeout{$job} = 1 if $ind == $child_indent && $key eq 'timeout-minutes' && (length $v || defined $next_value->());
  }
  next unless $is_workflow;
  $problem->(undef, 'no top-level permissions:') unless $has_permissions;
  for my $j (@order) {
    $problem->(undef, "job '$j' has no timeout-minutes") unless $timeout{$j};
  }
}
print "EXAMINED $examined\nACTIONS $actions\nBAD $bad\n";
