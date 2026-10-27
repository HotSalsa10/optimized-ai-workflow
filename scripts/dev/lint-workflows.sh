#!/usr/bin/env bash
# Checks GitHub Actions workflow files for three habits:
# - every "uses:" of an action is pinned to a full 40-character commit SHA
#   (a tag can be moved; a commit cannot);
# - the workflow sets top-level "permissions:" (least privilege);
# - every job sets "timeout-minutes:" (a stuck job cannot burn minutes).
set -u

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "workflows: FAIL - not inside a git repository"
  exit 2
}
cd "$root" || exit 2

prog=$(cat <<'PERL'
use strict;
use warnings;
my ($examined, $bad) = (0, 0);
for my $file (@ARGV) {
  open my $fh, '<', $file or do { print "workflows: cannot read $file\n"; $bad++; next };
  $examined++;
  my @lines = <$fh>;
  close $fh;
  my $has_perms = grep { /^permissions:/ } @lines;
  unless ($has_perms) { print "workflows: $file: no top-level permissions:\n"; $bad++; }
  my ($in_jobs, $job, %job_timeout) = (0, undef);
  my $n = 0;
  for my $l (@lines) {
    $n++;
    if ($l =~ /^jobs:\s*$/) { $in_jobs = 1; next; }
    if ($in_jobs && $l =~ /^\S/) { $in_jobs = 0; }
    if ($in_jobs && $l =~ /^  ([A-Za-z0-9_-]+):\s*$/) { $job = $1; $job_timeout{$job} //= 0; }
    if ($in_jobs && defined $job && $l =~ /^    timeout-minutes:\s*\d+/) { $job_timeout{$job} = 1; }
    if ($l =~ /^\s*-?\s*uses:\s*([^\s#]+)/) {
      my $ref = $1;
      next if $ref =~ m{^\./};
      next if $ref =~ m{^docker://};
      unless ($ref =~ /\@[0-9a-f]{40}$/) { print "workflows: $file:$n: '$ref' is not pinned to a commit SHA\n"; $bad++; }
    }
  }
  for my $j (sort keys %job_timeout) {
    unless ($job_timeout{$j}) { print "workflows: $file: job '$j' has no timeout-minutes\n"; $bad++; }
  }
}
print "EXAMINED $examined\nBAD $bad\n";
PERL
)

files=()
while IFS= read -r -d '' f; do
  [ -f "$f" ] && files+=("$f")
done < <(git ls-files -z -- '*.yml' '*.yaml' | tr '\0' '\n' | grep -E '(^|/)\.github/workflows/' | tr '\n' '\0')

if [ "${#files[@]}" -eq 0 ]; then
  echo "workflows: FAIL - found 0 tracked workflow files; nothing was checked"
  exit 1
fi

out=$(perl -e "$prog" "${files[@]}") || {
  echo "workflows: FAIL - the check itself did not run"
  exit 2
}
examined=$(printf '%s\n' "$out" | sed -n 's/^EXAMINED //p')
bad=$(printf '%s\n' "$out" | sed -n 's/^BAD //p')
printf '%s\n' "$out" | grep -v -e '^EXAMINED ' -e '^BAD '

if [ "${bad:-0}" -gt 0 ]; then
  echo "workflows: FAIL - $bad problem(s) in $examined workflow files"
  exit 1
fi
echo "workflows: PASS - examined $examined workflow files: actions pinned by commit, permissions set, every job has a timeout"
