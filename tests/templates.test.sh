#!/usr/bin/env bash
# Tests for the project templates, method/scripts/method/templates/ (step
# 7.1; M014, M015, M017, M018, M019, M094, M097, M101). The record templates
# are status.pl's list of records; the other templates are the files setup
# seeds once; a project seeded from them gives status no records or config
# problem, and its TESTS.md names every built-in check; each row the checks
# template offers reads cleanly once turned on; and no file under method/
# names a field product (a tripwire for names only: field-neutral wording
# in general is kept by the review).
#
# A template's project path is its path under templates/ without .tmpl,
# except method.conf.tmpl (.claude/method.conf),
# pull_request_template.md.tmpl (.github/pull_request_template.md) and
# method-checks.yml.tmpl (.github/workflows/method-checks.yml), which
# sit at the top so this repo holds no .claude/ or .github/ folder there.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: templates"
root=$(repo_root)
lib="$root/method/scripts/method/lib"
tdir="$root/method/scripts/method/templates"
work=$(new_sandbox_dir) || abort_sandbox
mkdir -p "$work/home"

# the files setup seeds besides the records, as template paths without .tmpl
others="REVIEW.md pull_request_template.md method-checks.yml docs/incident-checklist.md checks/project.tsv checks/scan-allow.txt method.conf"
# the field products the tripwire looks for, matched as whole words in any case
products="ERPNext Frappe Odoo Salesforce Shopify Magento WooCommerce QuickBooks NetSuite Xero"

# status.pl's list of records and checks.pl's built-in check ids, one per line
# shellcheck disable=SC2016 # perl code, expanded by perl
records=$(perl -ne 'if (/^my \@RECORDS = qw\(([^)]*)\);/) { print "$_\n" for split " ", $1 }' "$lib/status.pl" | LC_ALL=C sort)
# shellcheck disable=SC2016 # perl code, expanded by perl
builtins=$(perl -ne 'if (/^our \@RESERVED = qw\(([^)]*)\);/) { print "$_\n" for split " ", $1 }' "$lib/checks.pl")
# every template, as its path under templates/
templates=$(cd "$tdir" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)

# 1. the record templates: the .md templates at the top, but for the two
# that are not records
have=$(printf '%s\n' "$templates" | sed -n 's|^\([^/]*\.md\)\.tmpl$|\1|p' | grep -v -x -e REVIEW.md -e pull_request_template.md | LC_ALL=C sort)
name="the record templates equal status.pl's list of records"
if [ -z "$records" ]; then
  fail "$name: could not read @RECORDS in status.pl"
elif [ "$have" = "$records" ]; then
  pass "$name ($(printf '%s\n' "$records" | wc -l | tr -d ' '))"
else
  fail "$name" "$(printf 'status.pl: %s\ntemplates: %s\n' "$(printf '%s\n' "$records" | tr '\n' ' ')" "$(printf '%s\n' "$have" | tr '\n' ' ')")"
fi

# 2. every other template is one of the seeded files, and each is there
want=$(printf '%s\n' "$others" | tr ' ' '\n' | LC_ALL=C sort)
# not_records: each template that is not a record template, without .tmpl
not_records() {
  printf '%s\n' "$templates" | while IFS= read -r t; do
    case "$t" in
      *.tmpl) ;;
      *)
        echo "$t (not named .tmpl)"
        continue
        ;;
    esac
    t=${t%.tmpl}
    printf '%s\n' "$records" | grep -q -x -F -- "$t" || echo "$t"
  done
}
rest=$(not_records | LC_ALL=C sort)
name="every other template is one of the seeded files, and each is there"
if [ "$rest" = "$want" ]; then
  pass "$name ($(printf '%s\n' "$want" | wc -l | tr -d ' '))"
else
  fail "$name" "$(printf 'wanted: %s\nfound:  %s\n' "$(printf '%s\n' "$want" | tr '\n' ' ')" "$(printf '%s\n' "$rest" | tr '\n' ' ')")"
fi

# 3. CLAUDE.md.tmpl is exactly the import line (M014)
name="CLAUDE.md.tmpl is the line @AGENTS.md and nothing else"
if [ -f "$tdir/CLAUDE.md.tmpl" ] && [ "$(cat "$tdir/CLAUDE.md.tmpl")" = "@AGENTS.md" ] && [ "$(wc -l <"$tdir/CLAUDE.md.tmpl" | tr -d ' ')" = 1 ]; then
  pass "$name"
else
  fail "$name" "$(cat "$tdir/CLAUDE.md.tmpl" 2>&1)"
fi

# 4. a project seeded from the templates, read by status
p="$work/p"
mkdir -p "$p"
seed_failed=0
printf '%s\n' "$templates" | while IFS= read -r t; do
  case "$t" in
    method.conf.tmpl) to=.claude/method.conf ;;
    pull_request_template.md.tmpl) to=.github/pull_request_template.md ;;
    method-checks.yml.tmpl) to=.github/workflows/method-checks.yml ;;
    *) to=${t%.tmpl} ;;
  esac
  mkdir -p "$p/$(dirname "$to")" && cp "$tdir/$t" "$p/$to" || exit 1
done || seed_failed=1
(
  cd "$p" || exit 1
  git init -q
  git symbolic-ref HEAD refs/heads/main
  git config user.name "Test"
  git config user.email "test@example.invalid"
  git config commit.gpgsign false
  git config core.autocrlf false
  git add -A
  git commit -q -m "Seed the records" -m "Review-Verdict: approve"
) || seed_failed=1
out=$(cd "$p" && unset CLAUDE_CODE_EXECPATH CLAUDE_CODE_EFFORT_LEVEL CLAUDE_CODE_REMOTE GH_REPO && HOME="$work/home" GIT_CONFIG_NOSYSTEM=1 bash "$root/method/scripts/method/status.sh" --quick 2>&1)
n=$(printf '%s\n' "$records" | wc -l | tr -d ' ')
want_line="records: PASS - $n records present; CLAUDE.md imports AGENTS.md; checks/*.tsv lists no checks"
name="a project seeded from the templates gives status no records or config problem"
if [ "$seed_failed" -ne 0 ]; then
  fail "$name: the project could not be seeded"
elif printf '%s\n' "$out" | grep -q '^config:'; then
  fail "$name" "$(printf '%s\n' "$out" | grep '^config:')"
elif printf '%s\n' "$out" | grep -q -x -F -- "$want_line"; then
  pass "$name"
else
  fail "$name" "$(printf '%s\n' "$out" | grep '^records:')"
fi

# 5. the seeded TESTS.md names every built-in check
name="the seeded TESTS.md names every built-in check"
if [ -z "$builtins" ]; then
  fail "$name: could not read @RESERVED in checks.pl"
else
  absent=""
  for id in $builtins; do
    grep -q -F -- "\`$id\`" "$p/TESTS.md" 2>/dev/null || absent="$absent $id"
  done
  if [ -z "$absent" ]; then
    pass "$name ($(printf '%s\n' "$builtins" | wc -l | tr -d ' '))"
  else
    fail "$name: not named:$absent"
  fi
fi

# 6. each row the checks template offers, its # removed, reads cleanly
# with checks.pl's reader
mkdir -p "$work/rows/checks"
# shellcheck disable=SC2016 # perl code, expanded by perl
perl -ne 'print $1, "\n" if /^#([a-z][^\t\n]*\t[^\n]*)$/' "$tdir/checks/project.tsv.tmpl" >"$work/rows/checks/project.tsv" 2>/dev/null
offered=$(grep -c . "$work/rows/checks/project.tsv")
# shellcheck disable=SC2016 # perl code, expanded by perl
read_out=$(perl -e 'require $ARGV[0]; my ($c, $p) = Checks::read_tsv($ARGV[1]); print "PROBLEM $_\n" for @$p; print "ID $_->{id}\n" for @$c; print "COUNT ", scalar(@$c), "\n"' "$lib/checks.pl" "$work/rows" 2>&1)
name="every row checks/project.tsv.tmpl offers, turned on, reads cleanly"
if printf '%s\n' "$read_out" | grep -q '^PROBLEM'; then
  fail "$name" "$(printf '%s\n' "$read_out" | grep '^PROBLEM')"
elif [ "$offered" -lt 2 ] || ! printf '%s\n' "$read_out" | grep -q -x 'ID smoke' || ! printf '%s\n' "$read_out" | grep -q '^ID deps-'; then
  fail "$name: wanted the smoke row and the scanner rows" "$read_out"
elif ! printf '%s\n' "$read_out" | grep -q -x "COUNT $offered"; then
  fail "$name: $offered rows offered" "$read_out"
else
  pass "$name ($offered rows)"
fi

# 6b. each offered row's own echo line matches its count pattern, so a row
# turned on can pass (a row whose pattern never matches is always SKIPPED)
# shellcheck disable=SC2016 # perl code, expanded by perl
unmatched=$(perl -F'\t' -lane 'my ($id, $pat, $cmd) = @F[0, 3, 4]; my ($echo) = $cmd =~ /echo "([^"]*)"/; print $id unless defined $echo && $echo =~ /$pat/m' "$work/rows/checks/project.tsv")
name="every row checks/project.tsv.tmpl offers prints a line its own count pattern reads"
if [ -n "$unmatched" ]; then
  fail "$name: not read: $(printf '%s\n' "$unmatched" | tr '\n' ' ')"
else
  pass "$name"
fi

# 7. no file under method/ names a field product
# shellcheck disable=SC2016 # perl code, expanded by perl
scan='
  BEGIN { my $alt = join "|", map { quotemeta } split " ", $ENV{PRODUCTS}; $re = qr/(?<![A-Za-z0-9])($alt)(?![A-Za-z0-9])/i }
  chomp; my $f = $_; $n++;
  open my $h, "<", $f or do { print "cannot read $f\n"; next };
  { local $/ = "\n"; while (my $l = <$h>) { print "$f line $.: $1\n" while $l =~ /$re/g } }
  close $h;
  END { print "EXAMINED ", $n + 0, "\n" }'
found=$(cd "$root" && find method -type f -print0 | PRODUCTS=$products perl -0ne "$scan")
examined=$(printf '%s\n' "$found" | sed -n 's/^EXAMINED //p')
name="no file under method/ names a field product"
if [ -z "$examined" ] || [ "$examined" -eq 0 ]; then
  fail "$name: examined no file"
elif [ "$(printf '%s\n' "$found" | grep -c -v '^EXAMINED ')" -ne 0 ]; then
  fail "$name" "$(printf '%s\n' "$found" | grep -v '^EXAMINED ')"
else
  pass "$name ($examined files)"
fi

drop_sandbox "$work"
echo "tests: templates: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
