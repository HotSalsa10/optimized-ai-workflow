#!/usr/bin/env bash
# Runs every repo check and prints one line per check plus a count.
# Exit 0 only when nothing failed. A check that cannot run here is reported
# as SKIPPED, which is not a pass. Setting REQUIRE_SHELLCHECK=1 turns a missing
# copy of the shellcheck tool into a failure (CI on Linux does this).
#
# Output from a failing check or tool goes through the secret scan's mask
# filter: keys and credentials a tool quotes are masked, control characters
# are escaped and each line is indented, so no line can start with text taken
# from a file. File names reach tools as ./NAME, so a name that starts with
# "-" is never read as an option. A tracked file name that holds a control
# character fails the "names" check and is kept away from the tools, whose
# output it could split into lines.
set -u
# perl reads bytes here; these settings would change how it reads them
unset PERL_UNICODE PERL5OPT

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "validate: FAIL - not inside a git repository"
  exit 2
}
cd "$root" || exit 2

passed=0
failed=0
skipped=0
failed_names=""

masked() {
  perl method/scripts/method/lib/secrets.pl --mask
}

run_check() {
  name=$1
  shift
  if out=$("$@" 2>&1); then
    passed=$((passed + 1))
    printf '%s\n' "$out" | tail -n 1
  else
    failed=$((failed + 1))
    failed_names="$failed_names $name"
    printf '%s\n' "$out" | masked
  fi
}

# names: no tracked file name may hold a control character (a newline, an
# escape, or a UTF-8 C1 control); such a name could split or steer any tool's
# output. The same byte-level test keeps such names away from the tools below.
control_re='[\x00-\x1F\x7F]|\xC2[\x80-\x9F]'
bad_names=$(git ls-files -z | CONTROL=$control_re perl -0ne 'chomp; next unless /$ENV{CONTROL}/; s/([\x00-\x1F\x7F])/sprintf("\\x%02X", ord $1)/ge; s/\xC2([\x80-\x9F])/sprintf("\\xC2\\x%02X", ord $1)/ge; print "$_\n"')
if [ -n "$bad_names" ]; then
  failed=$((failed + 1))
  failed_names="$failed_names names"
  printf '%s\n' "$bad_names" | sed 's/^/names: /' | masked
  echo "names: FAIL - tracked file names hold control characters; rename them"
else
  passed=$((passed + 1))
  echo "names: PASS - no tracked file name holds a control character"
fi

# tracked_plain PATTERN: tracked files whose names match the perl PATTERN and
# hold no control character, NUL-separated.
tracked_plain() {
  git ls-files -z | CONTROL=$control_re WANT=$1 perl -0ne 'chomp; print "$_\0" if /$ENV{WANT}/ && !/$ENV{CONTROL}/'
}

run_check line-endings bash scripts/dev/check-line-endings.sh
run_check portability bash scripts/dev/lint-portability.sh
run_check secrets bash scripts/dev/scan-secrets.sh
run_check rule-map bash scripts/dev/check-rule-map.sh
run_check workflows bash scripts/dev/lint-workflows.sh
run_check lint-prompts bash scripts/dev/lint-prompts.sh

# self-install: this repo runs the method's hooks, agents, skills and scripts
# as installed at the root from a release tag (DECISIONS A82 (2), step 8.1),
# so the root copy must match its lock, scripts/method/method.lock. The lock
# is verified by the verify of method/scripts/method/lib/lock.pl, the code
# run-checks' method-files runs (M048), never by the root copy's own
# lib/lock.pl, so a changed root lock.pl cannot vouch for itself. verify
# also refuses a version line that is not a v* tag. The root
# .claude/settings.json must keep the method's rules out of this repo's
# sessions with claudeMdExcludes "**/.claude/rules/method/**" (A82 (3)).
self_install() {
  # shellcheck disable=SC2016 # perl code, expanded by perl
  perl -e '
    use strict;
    use warnings;
    my $lib = "method/scripts/method/lib/lock.pl";
    my $pattern = "**/.claude/rules/method/**";
    my (@lines, @why);
    my $v = eval { require "./$lib"; Lock::verify(".") };
    if (!$v) {
      (my $e = $@ || "no result") =~ s/\n.*//s;
      print "self-install: $lib did not load or its verify failed: $e\n";
      print "self-install: FAIL - the root copy of the method could not be compared with its lock\n";
      exit 1;
    }
    my @f = @{ $v->{findings} };
    push @lines, map { $_->[1] } @f;
    if (!-e $Lock::LOCK && !-l $Lock::LOCK) {
      push @why, "the method is not installed at the root ($Lock::LOCK is missing); install the last release tag as DECISIONS A82 (2) says";
    } elsif (@f) {
      push @why, "the root copy of the method does not match $Lock::LOCK (" . scalar(@f) . (@f == 1 ? " finding" : " findings") . " above)";
    }
    my ($s, $se) = Lock::read_json($Lock::SETTINGS, $Lock::SETTINGS);
    my $kept = !$se && ref $s eq "HASH" && ref $s->{claudeMdExcludes} eq "ARRAY"
      && grep { defined $_ && !ref $_ && $_ eq $pattern } @{ $s->{claudeMdExcludes} };
    if (!$kept) {
      push @lines, $se if $se;
      push @why, "$Lock::SETTINGS does not list claudeMdExcludes $pattern, so the method\x27s rules would load in this repo\x27s sessions";
    }
    print "self-install: $_\n" for @lines;
    if (@why) {
      print "self-install: FAIL - ", join("; ", @why), "\n";
      exit 1;
    }
    print "self-install: PASS - the root copy of the method matches $Lock::LOCK ($v->{version}, $v->{examined} entries, verified by $lib) and $Lock::SETTINGS keeps the method\x27s rules out\n";
  '
}
run_check self-install self_install

# perl syntax: every tracked .pl file under scripts/ and method/scripts/ must
# compile. perl -c runs BEGIN blocks, so it is pointed only at this repo's
# own helpers.
# Only the file, line and the start of each message are shown.
pl_files=()
while IFS= read -r -d '' f; do
  [ -f "$f" ] && pl_files+=("./$f")
done < <(tracked_plain '^(?:scripts|method/scripts)/.*\.pl\z')
if [ "${#pl_files[@]}" -eq 0 ]; then
  failed=$((failed + 1))
  failed_names="$failed_names perl-syntax"
  echo "perl-syntax: FAIL - found 0 perl files; nothing was checked"
else
  pl_bad=0
  for f in "${pl_files[@]}"; do
    if ! msg=$(perl -c "$f" 2>&1); then
      pl_bad=$((pl_bad + 1))
      printf '%s\n' "$msg" | F=$f perl -ne '$n++, print "$2 line $3: $1\n" if /^(.{1,80}?),? at (\S+) line (\d+)/; END { print "$ENV{F}: does not compile\n" unless $n }' | masked
    fi
  done
  if [ "$pl_bad" -gt 0 ]; then
    failed=$((failed + 1))
    failed_names="$failed_names perl-syntax"
    echo "perl-syntax: FAIL - $pl_bad of ${#pl_files[@]} perl files do not compile"
  else
    passed=$((passed + 1))
    echo "perl-syntax: PASS - all ${#pl_files[@]} perl files compile"
  fi
fi

# The shellcheck tool is optional locally, and required where REQUIRE_SHELLCHECK=1.
# It runs at its default severity, so unquoted variables (SC2086) are caught,
# and in its one-line format, which does not quote source lines. It ignores
# .shellcheckrc files (--norc), so a config file cannot switch it off (an
# older version without --norc does not read those files either), and
# SHELLCHECK_OPTS, so the environment cannot either.
unset SHELLCHECK_OPTS
if command -v shellcheck >/dev/null 2>&1; then
  norc=""
  shellcheck --help 2>&1 | grep -q -- --norc && norc="--norc"
  scripts=()
  while IFS= read -r -d '' f; do
    [ -f "$f" ] && scripts+=("./$f")
  done < <(tracked_plain '\.sh\z')
  if [ "${#scripts[@]}" -eq 0 ]; then
    failed=$((failed + 1))
    failed_names="$failed_names shellcheck"
    echo "shellcheck: FAIL - found 0 shell scripts; nothing was checked"
  elif out=$(shellcheck $norc -x -f gcc "${scripts[@]}" 2>&1); then
    passed=$((passed + 1))
    echo "shellcheck: PASS - examined ${#scripts[@]} shell scripts, no findings"
  else
    failed=$((failed + 1))
    failed_names="$failed_names shellcheck"
    printf '%s\n' "$out" | masked
    echo "shellcheck: FAIL - findings in shell scripts"
  fi
elif [ "${REQUIRE_SHELLCHECK:-0}" = "1" ]; then
  failed=$((failed + 1))
  failed_names="$failed_names shellcheck"
  echo "shellcheck: FAIL - required here but not installed"
else
  skipped=$((skipped + 1))
  echo "shellcheck: SKIPPED - not installed here; this is not a pass (CI on Linux runs it)"
fi

echo "validate: $passed passed, $failed failed, $skipped skipped"
if [ "$failed" -gt 0 ]; then
  echo "validate: FAIL -$failed_names"
  exit 1
fi
