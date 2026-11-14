#!/usr/bin/env perl
# The guard's git list (step 5.6, G3, M130; docs/plans/step5.md, section
# 6.2): reads git-shapes.txt (and a project's own list, in the same form)
# and says whether a git command's words match a shape. The form is written
# at the top of .claude/hooks/method/git-shapes.txt. Loaded with require;
# nothing runs when it is loaded.
#
#   GitList::parse(TEXT, SOURCE) (SHAPES, ERRORS): each shape a hash; each
#                       error "SOURCE line N: what is wrong". A line with
#                       an error is left out.
#   GitList::match(SHAPES, WORDS, ASK) (SHAPE) when a shape matches the
#                       words after git's global options (the subcommand
#                       first), else (undef, WHY): WHY names the condition
#                       that failed when a shape matched all but that
#                       (@clean, @off-main), else 'not on the list'.
#                       ASK->(TYPE, VALUE) answers the checks (REMOTE,
#                       BRANCH, NEWBRANCH, COMMIT, MAIN, REFNAME, clean,
#                       off-main), 1 or 0; it may run git, so it is asked
#                       last.
package GitList;
use strict;
use warnings;

my %TYPE = map { $_ => 1 } qw(NAME ARG REMOTE BRANCH NEWBRANCH COMMIT MAIN REFNAME);
my %COND = map { $_ => 1 } qw(clean off-main);

sub parse {
  my ($text, $source) = @_;
  my (@shapes, @errors);
  my $n = 0;
  for my $line (split /\n/, $text) {
    $n++;
    $line =~ s/\r\z//;
    next if $line =~ /\A\s*(?:#|\z)/;
    my $where = "$source line $n";
    my ($shape, $reason) = $line =~ /\A\s*(.*?)\s+::\s+(.*?)\s*\z/;
    if (!defined $shape || $shape eq '' || $reason !~ /\S/) {
      push @errors, "$where: not SHAPE :: REASON";
      next;
    }
    my %s = (path => [], opts => {}, any => 0, forbid => [], pos => [], conds => [], reason => $reason, where => $where, line => $line);
    my $bad;
    my @tok = split ' ', $shape;
    while (@tok && $tok[0] =~ /\A[a-z][a-z0-9-]*\z/) { push @{ $s{path} }, shift @tok }
    if (!@{ $s{path} }) { push @errors, "$where: no subcommand"; next }
    for my $t (@tok) {
      if ($t eq '-*') { $s{any} = 1 }
      elsif ($t =~ /\A!(--?[A-Za-z0-9][A-Za-z0-9-]*)\z/) { push @{ $s{forbid} }, $1 }
      elsif ($t =~ /\A(\+?)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?:([=:])([A-Z]+)?)?\z/) {
        my ($req, $name, $kind, $type) = ($1, $2, $3, $4);
        if (defined $type && !$TYPE{$type}) { $bad = "unknown type $type"; last }
        $s{opts}{$name} = { kind => (!defined $kind ? 'flag' : $kind eq '=' ? 'value' : 'attached'), type => $type, required => $req ? 1 : 0 };
      } elsif ($t =~ /\A([A-Z]+)(\?|\.\.\.)?\z/ && $TYPE{$1}) {
        if (@{ $s{pos} } && $s{pos}[-1]{many}) { $bad = "$t after a ... word"; last }
        push @{ $s{pos} }, { type => $1, opt => (($2 // '') eq '?') ? 1 : 0, many => (($2 // '') eq '...') ? 1 : 0 };
      } elsif ($t =~ /\A@([a-z-]+)\z/ && $COND{$1}) { push @{ $s{conds} }, $1 }
      else { $bad = "cannot read \"$t\""; last }
    }
    if ($bad) { push @errors, "$where: $bad"; next }
    push @shapes, \%s;
  }
  return (\@shapes, \@errors);
}

# a long option NAME refused by FORBID: the same, or a prefix of it that git
# would take for it (at least --x)
sub forbidden {
  my ($name, $forbid) = @_;
  for my $f (@$forbid) {
    return 1 if $name eq $f;
    return 1 if $name =~ /\A--/ && $f =~ /\A--/ && length($name) >= 3 && index($f, $name) == 0;
  }
  return 0;
}

# try SHAPE on WORDS: (1) or (0, WHY); checks are collected in CHECKS
sub try_shape {
  my ($s, $words, $checks) = @_;
  my @w = @$words;
  my $k = @{ $s->{path} };
  return 0 if @w < $k;
  for my $i (0 .. $k - 1) { return 0 if $w[$i] ne $s->{path}[$i] }
  my @rest = @w[$k .. $#w];
  my (@pos, %seen);
  my $o = $s->{opts};
  my $value = sub {
    my ($spec, $v) = @_;
    push @$checks, [$spec->{type}, $v] if $spec->{type};
  };
  my $i = 0;
  while ($i <= $#rest) {
    my $x = $rest[$i++];
    if ($x eq '--') { push @pos, @rest[$i .. $#rest]; last }
    if ($x =~ /\A(--[^=]+)(?:=(.*))?\z/s) {
      my ($name, $v) = ($1, $2);
      if (my $spec = $o->{$name}) {
        $seen{$name}++;
        if ($spec->{kind} eq 'flag') { return 0 if defined $v }
        elsif ($spec->{kind} eq 'value') {
          if (!defined $v) { return 0 if $i > $#rest; $v = $rest[$i++] }
          $value->($spec, $v);
        } elsif (defined $v) { $value->($spec, $v) }
        next;
      }
      next if $name eq '--quiet' && !defined $v;
      return 0 unless $s->{any};
      return 0 if forbidden($name, $s->{forbid});
      next;
    }
    if ($x =~ /\A-(.+)\z/s) {
      if (my $spec = $o->{$x}) {
        if ($spec->{kind} eq 'flag') { $seen{$x}++; next }
      }
      my @l = split //, $1;
      while (@l) {
        my $name = '-' . shift @l;
        if (my $spec = $o->{$name}) {
          $seen{$name}++;
          next if $spec->{kind} eq 'flag';
          my $v = join '', @l;
          @l = ();
          if ($spec->{kind} eq 'value' && $v eq '') { return 0 if $i > $#rest; $v = $rest[$i++] }
          $value->($spec, $v) if $v ne '' || $spec->{kind} eq 'value';
          next;
        }
        next if $name eq '-q';
        return 0 unless $s->{any};
        return 0 if grep { $_ eq $name } @{ $s->{forbid} };
      }
      next;
    }
    push @pos, $x;
  }
  for my $name (keys %$o) { return 0 if $o->{$name}{required} && !$seen{$name} }
  my @spec = @{ $s->{pos} };
  my $need = grep { !$_->{opt} && !$_->{many} } @spec;
  for my $p (@spec) {
    if ($p->{many}) { push @$checks, map { [$p->{type}, $_] } @pos; @pos = (); last }
    if ($p->{opt}) {
      next unless @pos > $need;
    } else {
      return 0 unless @pos;
      $need--;
    }
    my $v = shift @pos;
    return 0 if $v =~ /\A-/ && $p->{type} ne 'ARG';
    push @$checks, [$p->{type}, $v];
  }
  return 0 if @pos;
  return 1;
}

sub match {
  my ($shapes, $words, $ask) = @_;
  my $why = 'not on the list';
  for my $s (@$shapes) {
    my @checks;
    next unless try_shape($s, $words, \@checks);
    my $ok = 1;
    for my $c (@checks) {
      next if $c->[0] eq 'ARG' || $c->[0] eq 'NAME';
      if (!$ask->($c->[0], $c->[1])) { $ok = 0; last }
    }
    next unless $ok;
    for my $c (@{ $s->{conds} }) {
      if (!$ask->($c)) { $ok = 0; $why = $c; last }
    }
    return ($s) if $ok;
  }
  return (undef, $why);
}

1;
