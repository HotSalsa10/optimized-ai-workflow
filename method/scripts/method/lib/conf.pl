#!/usr/bin/env perl
# The one reader of the method's KEY=VALUE files (M048): a project's
# .claude/method.conf and the method's own REQUIRES. Loaded with require.
#
# Format: one KEY=VALUE per line, parsed, never run as shell. One trailing
# CR per line is dropped; any other control character is a problem. Blank
# lines and lines starting with # are skipped. The whole text after = is
# the value, spaces and apostrophes included; a value that is empty, starts
# or ends with a space, holds a double quote, or is wrapped in single
# quotes is a problem (a tab is a control character). A list key may be
# given once per value; any other key once. An unknown key is a problem (a
# typo, or a key from a newer method version). Problems name the file and
# line, never the value.
#
# .claude/method.conf keys:
#   PRODUCT_PATHS  (list) paths that make up the product, relative to the
#                  repo root; "." is the whole repo
#   LOCAL_ONLY     (list) what a fresh clone is meant to lack: private
#                  inputs and caches a clone rebuilds. A bare name (no "/")
#                  matches any path segment and may use * and ? inside it
#                  (__pycache__, *.pyc); a path (with "/") lies strictly
#                  under a PRODUCT_PATHS entry and matches by whole segments
#   REPOS          (list) other repositories status reports on, relative to
#                  the repo root (may start with ../)
#   VERDICTS_FROM  a full commit id on main; status checks verdicts after it
# Paths: no absolute path, no "..", "." or empty segment (but PRODUCT_PATHS
# may be the lone "."; REPOS may start with ".." segments), no leading ":"
# or "-", none of * ? [ \. A trailing "/" is dropped.
#
#   Conf::read(ROOT)           (values, problems) for ROOT/.claude/method.conf;
#                              a missing file means every key is unset; a key
#                              on a line with a problem stays unset
#   Conf::read_text(TEXT, LABEL)  (values, problems) for a method.conf held in
#                              TEXT (a committed one, say)
#   Conf::requires(DIR)        (values, problems) for DIR/REQUIRES
#   Conf::check_path(PATH, LONE_DOT_OK)  the path without a trailing "/", or
#                              undef when it breaks the path rules
#   Conf::ignored_inputs(ROOT) the project's config files that git ignores
#                              (needs lib/git.pl loaded)
package Conf;
use strict;
use warnings;
use File::Spec;

my %CONF_KEYS = (PRODUCT_PATHS => 'list', LOCAL_ONLY => 'list', REPOS => 'list', VERDICTS_FROM => 'one');
my %REQUIRES_KEYS = (claude_code_min => 'one');

sub check_path {
  my ($p, $lone_dot_ok) = @_;
  return '.' if $lone_dot_ok && ($p eq '.' || $p eq './');
  $p =~ s{/\z}{};
  # an absolute path has an empty first part, which the loop below refuses
  return undef if $p eq '' || $p =~ /\A[A-Za-z]:/ || $p =~ /\A[:-]/ || $p =~ /[*?\[\\]/;
  for my $seg (split m{/}, $p, -1) {
    return undef if $seg eq '' || $seg eq '.' || $seg eq '..';
  }
  return $p;
}

sub check_repo_path {
  my ($p) = @_;
  $p =~ s{/\z}{};
  my $rest = $p;
  $rest =~ s{\A(?:\.\./)+}{};
  return defined check_path($rest, 0) ? $p : undef;
}

# parse FILE LABEL KEYS: (values, problems)
sub parse {
  my ($file, $label, $keys) = @_;
  my (%v, @problems, %lines);
  open my $fh, '<:raw', $file or return (\%v, ["$label: cannot read the file"]);
  local $/ = "\n";    # whatever the caller set
  my $n = 0;
  while (my $l = <$fh>) {
    $n++;
    my $problem = sub { push @problems, "$label line $n: $_[0]" };
    $l =~ s/\r?\n\z//;
    $l =~ s/\A\xEF\xBB\xBF// if $n == 1;    # a byte-order mark some editors add
    next if $l =~ /\A[ \t]*(?:#|\z)/;
    if ($l =~ /[\x00-\x1F\x7F]/) { $problem->('holds a control character'); next }
    my ($k, $val) = $l =~ /\A([A-Za-z][A-Za-z0-9_]*)=(.*)\z/;
    if (!defined $k) { $problem->('is not KEY=VALUE'); next }
    my $kind = $keys->{$k};
    # a name that is not one word of letters in one case, of at most 16 (the
    # key names are shorter), may be a pasted secret that ends in = (an AWS
    # key id is 20)
    if (!$kind && $k !~ /\A(?:[A-Z_]{1,16}|[a-z_]{1,16})\z/) {
      $problem->('an unknown key, not shown: it does not look like a key name, so it may be a pasted value');
      next;
    }
    if (!$kind) { $problem->("unknown key $k (a typo, or a key from a newer method version)"); next }
    if ($val eq '') { $problem->("$k has no value"); next }
    if ($val =~ /\A |[ ]\z/) { $problem->("$k: the value starts or ends with a space"); next }
    if ($val =~ /"/ || $val =~ /\A'.*'\z/) { $problem->("$k: no quotes; write $k=value"); next }
    my $ok = check_value($k, $val);
    if (!defined $ok) { $problem->("$k: " . value_rule($k)); next }
    if ($kind eq 'one') {
      if (exists $v{$k}) { $problem->("$k is given twice"); next }
      $v{$k} = $ok;
    } else {
      push @{ $v{$k} }, $ok;
      push @{ $lines{$k} }, $n;
    }
  }
  close $fh;
  # a LOCAL_ONLY path must lie strictly under a PRODUCT_PATHS entry
  my @pp = @{ $v{PRODUCT_PATHS} || [] };
  if ($v{LOCAL_ONLY}) {
    my @keep;
    for my $i (0 .. $#{ $v{LOCAL_ONLY} }) {
      my $lo = $v{LOCAL_ONLY}[$i];
      if ($lo =~ m{/} && !grep { $_ eq '.' || index($lo, "$_/") == 0 } @pp) {
        push @problems, "$label line $lines{LOCAL_ONLY}[$i]: LOCAL_ONLY: a path must lie under a PRODUCT_PATHS entry";
        next;
      }
      push @keep, $lo;
    }
    $v{LOCAL_ONLY} = \@keep;
  }
  return (\%v, \@problems);
}

sub check_value {
  my ($k, $val) = @_;
  if ($k eq 'PRODUCT_PATHS') { return check_path($val, 1) }
  if ($k eq 'REPOS') { return check_repo_path($val) }
  if ($k eq 'LOCAL_ONLY') {
    return check_path($val, 0) if $val =~ m{/};
    # a bare name: one segment, * and ? allowed, not only wildcards
    return undef if $val eq '.' || $val eq '..' || $val =~ /\A[:-]/ || $val =~ /[\[\\]/ || $val =~ /\A[*?]+\z/;
    return $val;
  }
  if ($k eq 'VERDICTS_FROM') { return $val =~ /\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/ ? $val : undef }
  if ($k eq 'claude_code_min') { return $val =~ /\A[0-9]+\.[0-9]+\.[0-9]+\z/ ? $val : undef }
  return undef;
}

sub value_rule {
  my ($k) = @_;
  return 'a full commit id (40 or 64 hex characters)' if $k eq 'VERDICTS_FROM';
  return 'a version like 2.1.295' if $k eq 'claude_code_min';
  return 'a name like __pycache__ or *.pyc, or a path under a product path' if $k eq 'LOCAL_ONLY';
  return 'a relative path with no ., .. or empty part, no leading : or -, and none of * ? [ \\';
}

sub read {
  my ($root) = @_;
  my $file = File::Spec->catfile($root, '.claude', 'method.conf');
  # a link could stand for settings that a clone does not have
  return ({}, ['.claude/method.conf: .claude or the file is a link; settings must be in the repository itself'])
    if -l File::Spec->catfile($root, '.claude') || -l $file;
  return ({}, []) unless -e $file;
  return ({}, ['.claude/method.conf: not a regular file']) unless -f $file;
  return parse($file, '.claude/method.conf', \%CONF_KEYS);
}

# read_text TEXT LABEL: (values, problems) for a .claude/method.conf held in
# TEXT, such as the one in a commit
sub read_text {
  my ($text, $label) = @_;
  return parse(\$text, $label, \%CONF_KEYS);
}

sub requires {
  my ($dir) = @_;
  return parse(File::Spec->catfile($dir, 'REQUIRES'), 'REQUIRES', \%REQUIRES_KEYS);
}

sub ignored_inputs {
  my ($root) = @_;
  my $out = Git::ok('-C', $root, 'ls-files', '-z', '--others', '--ignored', '--exclude-standard', '--',
    '.claude/method.conf', 'checks');
  return grep { $_ eq '.claude/method.conf' || m{\Achecks/[^/.][^/]*\.tsv\z} || $_ eq 'checks/scan-allow.txt' }
    split /\0/, $out;
}

1;
