#!/usr/bin/env perl
# Checks GitHub Actions workflow files. Called by scripts/dev/lint-workflows.sh.
# Usage: perl workflows.pl FILE...
# Prints one line per problem, then "EXAMINED n" and "BAD n".
# Rules:
# - every "uses:" of an action is pinned to a full 40-character commit SHA;
# - the workflow sets top-level "permissions:";
# - no "permissions:" line, top-level or in a job, grants write-all;
# - every job sets "timeout-minutes:" at job level (any indentation).
use strict;
use warnings;

my ($examined, $bad) = (0, 0);
for my $file (@ARGV) {
  open my $fh, '<', $file or do { print "workflows: cannot read $file\n"; $bad++; next };
  my @lines = <$fh>;
  close $fh;
  $examined++;

  if (!grep { /^permissions:/ } @lines) {
    print "workflows: $file: no top-level permissions:\n"; $bad++;
  }

  my ($in_jobs, $job_indent, $job, $child_indent) = (0, undef, undef, undef);
  my (%timeout, @order);
  my $n = 0;
  for my $l (@lines) {
    $n++;
    if ($l =~ /^\s*-?\s*uses:\s*([^\s#]+)/) {
      my $ref = $1;
      $ref =~ s/^["']|["']$//g;
      if ($ref !~ m{^\./} && $ref !~ m{^docker://} && $ref !~ /\@[0-9a-f]{40}$/) {
        print "workflows: $file:$n: '$ref' is not pinned to a commit SHA\n"; $bad++;
      }
    }
    if ($l =~ /^\s*permissions:\s*["']?write-all["']?\s*(?:#.*)?$/) {
      print "workflows: $file:$n: permissions are write-all; grant only what is needed\n"; $bad++;
    }
    next if $l =~ /^\s*(?:#|$)/;
    if ($l =~ /^jobs:\s*(?:#.*)?$/) { $in_jobs = 1; $job_indent = undef; $job = undef; next; }
    next unless $in_jobs;
    if ($l =~ /^\S/) { $in_jobs = 0; next; }
    my ($lead) = $l =~ /^( *)/;
    my $ind = length $lead;
    $job_indent = $ind unless defined $job_indent;
    if ($ind == $job_indent) {
      if ($l =~ /^\s*["']?([A-Za-z0-9_-]+)["']?:\s*(?:#.*)?$/) {
        $job = $1; $child_indent = undef;
        push @order, $job unless exists $timeout{$job};
        $timeout{$job} = 0;
      }
      next;
    }
    next unless defined $job && $ind > $job_indent;
    $child_indent = $ind unless defined $child_indent;
    $timeout{$job} = 1 if $ind == $child_indent && $l =~ /^\s*timeout-minutes:\s*\S/;
  }
  for my $j (@order) {
    unless ($timeout{$j}) { print "workflows: $file: job '$j' has no timeout-minutes\n"; $bad++; }
  }
}
print "EXAMINED $examined\nBAD $bad\n";
