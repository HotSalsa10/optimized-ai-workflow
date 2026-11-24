#!/usr/bin/env perl
# check-links.pl: checks the site's links. For each page named (a .html
# file, or every .html file in a folder named), every href and src that
# points to a file of this site must name a file that is there. Links to
# other sites (with a scheme such as https:) and to a place in the same
# page (#...) are not checked.
# Usage: perl check-links.pl PAGE-OR-FOLDER...
# Prints "links: N checked, M broken" and exits 0 only when none is broken.
use strict;
use warnings;
use File::Basename qw(dirname);

my @pages;
for my $arg (@ARGV) {
  if (-d $arg) {
    opendir my $d, $arg or die "check-links: cannot read $arg\n";
    push @pages, map {"$arg/$_"} sort grep {/\.html\z/} readdir $d;
    closedir $d;
  } elsif (-f $arg) {
    push @pages, $arg;
  } else {
    die "check-links: no page or folder $arg\n";
  }
}
die "check-links: name at least one page or folder\n" unless @pages;

my ($checked, $broken) = (0, 0);
for my $page (@pages) {
  open my $h, '<', $page or die "check-links: cannot read $page\n";
  my $html = do { local $/; <$h> };
  close $h;
  while ($html =~ /\b(?:href|src)="([^"]*)"/g) {
    my $link = $1;
    next if $link =~ /\A(?:[a-z][a-z0-9+.-]*:|#)/i;
    $link =~ s/[#?].*\z//s;
    $checked++;
    next if -e dirname($page) . "/$link";
    $broken++;
    print "check-links: $page links to $link, which is not there\n";
  }
}
print "links: $checked checked, $broken broken\n";
exit($broken ? 1 : 0);
