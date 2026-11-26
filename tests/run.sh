#!/usr/bin/env bash
# Runs every test file (tests/*.test.sh) and every plant file (tests/plants/*.sh)
# and prints how many files passed and failed. Each file prints its own detail.
# "run.sh tests" runs only the test files and "run.sh plants" only the plant
# files, so CI can run them side by side; "run.sh plants K/N" runs the plant
# files that tests/plants/shards.txt gives to part K (0-based) of its N, CI's
# shard K/N. That file is the one home of the split, fixed by measured time
# (step 7.9): it must name every plant file exactly once, as "K FILE
# SECONDS", with N parts, none empty, or a shard run stops before running
# anything. A TEST_ONLY or PLANT_SHARD left in the caller's environment is
# dropped: a run of whole files never keeps only some cases or some plants.
# (Tested in tests/suite.test.sh.)
set -u
unset TEST_ONLY PLANT_SHARD
here=$(cd "$(dirname "$0")" && pwd)
cd "$here/.." || exit 2

usage() {
  echo "usage: tests/run.sh [tests | plants [K/N]]"
  exit 2
}

# shard_files K N: prints the plant files tests/plants/shards.txt gives to
# part K of N, one a line; when the file cannot be read, misses a plant file,
# names one twice or one that is not there, has an empty part, or has other
# than N parts, prints each problem as a FAIL line and fails instead
shard_files() {
  # shellcheck disable=SC2016 # perl code, expanded by perl
  perl -e '
    my ($k, $n) = @ARGV;
    my $list = "tests/plants/shards.txt";
    open my $h, "<", $list or do { print "tests: FAIL - cannot read $list\n"; exit 1 };
    my (%part, %seen, @bad);
    while (my $line = <$h>) {
      $line =~ s/\r?\n\z//;
      next if $line =~ /^\s*(?:#|\z)/;
      if ($line =~ /^(0|[1-9][0-9]*) ([A-Za-z0-9._-]+\.sh) [0-9]+$/) {
        push @bad, "$2 is named twice" if $seen{$2}++ == 1;
        $part{$2} = $1;
      } else {
        push @bad, "line $. is not \"K FILE SECONDS\"";
      }
    }
    close $h;
    my @files = map { m{([^/]+)\z} ? $1 : $_ } glob "tests/plants/*.sh";
    my %have = map { $_ => 1 } @files;
    push @bad, "$_ is not named" for grep { !exists $part{$_} } @files;
    push @bad, "$_ is named but is not a plant file" for grep { !$have{$_} } sort keys %part;
    my $parts = 0;
    for (values %part) { $parts = $_ + 1 if $_ + 1 > $parts }
    for my $p (0 .. $parts - 1) {
      push @bad, "part $p has no file" unless grep { $_ == $p } values %part;
    }
    push @bad, "it has $parts parts, not $n" if $parts != $n;
    if (@bad) { print "tests: FAIL - $list: $_\n" for @bad; exit 1 }
    print "tests/plants/$_\n" for grep { $part{$_} == $k } @files;
  ' "$1" "$2"
}

case "${1:-all}" in
  all)
    [ $# -le 1 ] || usage
    set -- tests/*.test.sh tests/plants/*.sh
    ;;
  tests)
    [ $# -le 1 ] || usage
    set -- tests/*.test.sh
    ;;
  plants)
    [ $# -le 2 ] || usage
    if [ $# -eq 2 ]; then
      case "$2" in
        [0-9]/[1-9]) shard=$2 ;;
        *) usage ;;
      esac
      [ "${shard%/*}" -lt "${shard#*/}" ] || usage
      if ! picked=$(shard_files "${shard%/*}" "${shard#*/}"); then
        printf '%s\n' "$picked"
        echo "tests: FAIL - the plant files' split cannot be read; nothing was run"
        exit 1
      fi
      set --
      while IFS= read -r f; do
        [ -n "$f" ] && set -- "$@" "$f"
      done <<PICKED
$picked
PICKED
    else
      set -- tests/plants/*.sh
    fi
    ;;
  *) usage ;;
esac

files_pass=0
files_fail=0
found=0
for f in "$@"; do
  [ -f "$f" ] || continue
  found=$((found + 1))
  if bash "$f"; then
    files_pass=$((files_pass + 1))
  else
    files_fail=$((files_fail + 1))
    echo "tests: FAILED in $f"
  fi
done

if [ "$found" -eq 0 ]; then
  echo "tests: FAIL - found 0 test files; nothing was run"
  exit 1
fi
echo "tests: $files_pass of $found files passed, $files_fail failed"
[ "$files_fail" -eq 0 ]
