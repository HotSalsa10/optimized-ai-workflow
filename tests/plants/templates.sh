#!/usr/bin/env bash
# Plants for tests/templates.test.sh (step 7.1): each break, made in a
# throwaway copy of the repo, must turn the test red for its stated reason.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: templates"
test_file=tests/templates.test.sh
t=method/scripts/method/templates

# plant NAME REASON CHANGE LANDED: in a new sandbox, the shell code CHANGE
# (run in it) makes the break and LANDED (run in it) confirms it; then the
# test must go red with a FAIL line that starts with REASON
plant() {
  sb=$(make_sandbox) || abort_sandbox
  if (cd "$sb" && eval "$3") && expect_landed "$1" sh -c "cd \"\$1\" && $4" sh "$sb"; then
    plant_judge "$1" "$sb" "$test_file" "$2"
  fi
  drop_sandbox "$sb"
}

sb=$(make_sandbox) || abort_sandbox
if out=$(cd "$sb" && bash "$test_file" 2>&1); then
  pass "the templates test is green on a clean copy"
else
  fail "the templates test is green on a clean copy" "$(printf '%s\n' "$out" | grep FAIL)"
fi
drop_sandbox "$sb"

plant "a record template dropped (RISKS.md.tmpl)" \
  "the record templates equal status.pl's list of records" \
  "rm $t/RISKS.md.tmpl" "test ! -e $t/RISKS.md.tmpl"

plant "REVIEW.md.tmpl dropped" \
  "every other template is one of the seeded files, and each is there" \
  "rm $t/REVIEW.md.tmpl" "test ! -e $t/REVIEW.md.tmpl"

plant "a second line in CLAUDE.md.tmpl" \
  "CLAUDE.md.tmpl is the line @AGENTS.md and nothing else" \
  "printf 'Read AGENTS.md first.\n' >>$t/CLAUDE.md.tmpl" "grep -q -x '@AGENTS.md' $t/CLAUDE.md.tmpl && grep -q -x 'Read AGENTS.md first.' $t/CLAUDE.md.tmpl"

plant "CLAUDE.md.tmpl losing @AGENTS.md" \
  "a project seeded from the templates gives status no records or config problem" \
  "printf 'Read AGENTS.md first.\n' >$t/CLAUDE.md.tmpl" "! grep -q -x '@AGENTS.md' $t/CLAUDE.md.tmpl"

plant "method.conf.tmpl setting an unknown key" \
  "a project seeded from the templates gives status no records or config problem" \
  "printf 'PRODUCT_PATH=.\n' >>$t/method.conf.tmpl" "grep -q -x 'PRODUCT_PATH=.' $t/method.conf.tmpl"

plant "TESTS.md.tmpl not naming tree-unchanged" \
  "the seeded TESTS.md names every built-in check" \
  "perl -ni -e 'print unless /\`tree-unchanged\`/' $t/TESTS.md.tmpl" "! grep -q tree-unchanged $t/TESTS.md.tmpl"

plant "a scanner row in checks/project.tsv.tmpl with spaces for its first TAB" \
  "every row checks/project.tsv.tmpl offers, turned on, reads cleanly" \
  "perl -pi -e 's/^#deps-node\t/#deps-node /' $t/checks/project.tsv.tmpl" "grep -q '^#deps-node any' $t/checks/project.tsv.tmpl"

plant "a scanner row whose count pattern its own echo line does not match" \
  "every row checks/project.tsv.tmpl offers prints a line its own count pattern reads" \
  "perl -pi -e 's/\^deps-node: \(\\\\d\+\) file/^deps-node: (\\\\d+) package/' $t/checks/project.tsv.tmpl" "grep -q 'deps-node: (.d+) package' $t/checks/project.tsv.tmpl"

plant "a field product's name joined to an underscore (AGENTS.md.tmpl)" \
  "no file under method/ names a field product" \
  "printf 'See frappe_app for records.\n' >>$t/AGENTS.md.tmpl" "grep -q frappe_app $t/AGENTS.md.tmpl"

plant "a field product's name in a template (AGENTS.md.tmpl)" \
  "no file under method/ names a field product" \
  "printf 'Use the ERPNext list view for records.\n' >>$t/AGENTS.md.tmpl" "grep -q ERPNext $t/AGENTS.md.tmpl"

plant "step 9 put back in docs/method/why.md, as a promise" \
  "no file under method/ names step 9 of this repository's plan" \
  "printf 'CI compares the files with the release (step 9).\n' >>method/docs/method/why.md" "grep -q '(step 9)' method/docs/method/why.md"

echo "plants: templates: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
