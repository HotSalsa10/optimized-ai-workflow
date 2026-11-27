#!/usr/bin/env bash
# Plants for validate's perl-syntax and shellcheck checks, each run through
# scripts/dev/validate.sh whole: each check must be green on a clean copy
# and red, for its stated reason, on a copy with the planted defect. Each
# plant first confirms it really landed in the file. Strings that would trip
# the checks are assembled at run time, so this file itself stays clean.
# (Split from tests/plants/dev-checks.sh at step 8's review, F9: its whole
# validate runs, each with shellcheck, kept that file past its part's time
# margin. The case numbers are dev-checks.sh's, kept so older records still
# point at them.)
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: perl syntax and shellcheck"

d='$' # a dollar sign, so planted shell text needs no single-quoted $
key="sk-ant""-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef0123456789"

# can_create DIR NAME: this file system lets a file named NAME be made in DIR.
can_create() {
  : >"$1/$2" 2>/dev/null && rm -f "$1/$2"
}

# --- perl syntax (run through validate.sh) -------------------------------------------------
# 77. a perl file that does not compile
sb=$(make_sandbox) || abort_sandbox
printf 'use strict;\nmy %sx = ;\n' "$d" >"$sb/scripts/dev/lib/planted.pl"
(cd "$sb" && git add scripts/dev/lib/planted.pl)
if expect_landed "perl-syntax plant" grep -q "= ;" "$sb/scripts/dev/lib/planted.pl"; then
  expect_red "perl-syntax red on a file that does not compile" "$sb" "perl-syntax: FAIL - 1 of" bash scripts/dev/validate.sh
fi
drop_sandbox "$sb"

# 77b. a perl file under method/scripts/ that does not compile
sb=$(make_sandbox) || abort_sandbox
mkdir -p "$sb/method/scripts/method/lib"
printf 'use strict;\nmy %sx = ;\n' "$d" >"$sb/method/scripts/method/lib/planted.pl"
(cd "$sb" && git add method/scripts/method/lib/planted.pl)
if expect_landed "perl-syntax plant 2" grep -q "= ;" "$sb/method/scripts/method/lib/planted.pl"; then
  expect_red "perl-syntax red on a method file that does not compile" "$sb" "./method/scripts/method/lib/planted.pl line 2" bash scripts/dev/validate.sh
fi
drop_sandbox "$sb"

# --- shellcheck (run through validate.sh) --------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  # 78. an unchecked cd
  sb=$(make_sandbox) || abort_sandbox
  printf '#!/usr/bin/env bash\ncd "%s1"\nrm -f ./tmpfile\n' "$d" >"$sb/planted-cd.sh"
  (cd "$sb" && git add planted-cd.sh)
  if expect_landed "shellcheck plant 1" grep -q -F "cd \"${d}1\"" "$sb/planted-cd.sh"; then
    out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
    if printf '%s\n' "$out" | grep -q "\./planted-cd\.sh:2:" &&
      printf '%s\n' "$out" | grep -q "SC2164" &&
      printf '%s\n' "$out" | grep -q "validate: FAIL - shellcheck"; then
      pass "shellcheck red on an unchecked cd"
    else
      fail "shellcheck red on an unchecked cd" "$out"
    fi
  fi
  drop_sandbox "$sb"

  # 79. an unquoted variable
  sb=$(make_sandbox) || abort_sandbox
  printf '#!/usr/bin/env bash\nf=%s1\nrm -f %sf\n' "$d" "$d" >"$sb/planted-unquoted.sh"
  (cd "$sb" && git add planted-unquoted.sh)
  if expect_landed "shellcheck plant 2" grep -q -F "rm -f ${d}f" "$sb/planted-unquoted.sh"; then
    out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
    if printf '%s\n' "$out" | grep -q "\./planted-unquoted\.sh:3:" &&
      printf '%s\n' "$out" | grep -q "SC2086" &&
      printf '%s\n' "$out" | grep -q "validate: FAIL - shellcheck"; then
      pass "shellcheck red on an unquoted variable"
    else
      fail "shellcheck red on an unquoted variable" "$out"
    fi
  fi
  drop_sandbox "$sb"

  # 80. SHELLCHECK_OPTS in the environment cannot switch shellcheck off
  sb=$(make_sandbox) || abort_sandbox
  printf '#!/usr/bin/env bash\nf=%s1\nrm -f %sf\n' "$d" "$d" >"$sb/planted-unquoted4.sh"
  (cd "$sb" && git add planted-unquoted4.sh)
  if expect_landed "shellcheck plant 7" grep -q "rm -f" "$sb/planted-unquoted4.sh"; then
    expect_red "shellcheck is not switched off by SHELLCHECK_OPTS" "$sb" "./planted-unquoted4.sh:3:" env SHELLCHECK_OPTS="-e SC2086" bash scripts/dev/validate.sh
  fi
  drop_sandbox "$sb"

  # 81. a tracked .shellcheckrc cannot switch shellcheck off
  sb=$(make_sandbox) || abort_sandbox
  printf 'disable=all\n' >"$sb/.shellcheckrc"
  printf '#!/usr/bin/env bash\nf=%s1\nrm -f %sf\n' "$d" "$d" >"$sb/planted-unquoted3.sh"
  (cd "$sb" && git add .shellcheckrc planted-unquoted3.sh)
  if expect_landed "shellcheck plant 6" grep -q "disable=all" "$sb/.shellcheckrc"; then
    expect_red "shellcheck is not switched off by a tracked .shellcheckrc" "$sb" "./planted-unquoted3.sh:3:" bash scripts/dev/validate.sh
  fi
  drop_sandbox "$sb"

  # 82. a file named like a shellcheck option is linted as a file, not read as one
  sb=$(make_sandbox) || abort_sandbox
  printf '#!/usr/bin/env bash\ntrue\n' >"$sb/--rcfile=sc.sh"
  printf '# disable=all\ndisable=all\n' >"$sb/sc.sh"
  printf '#!/usr/bin/env bash\nf=%s1\nrm -f %sf\n' "$d" "$d" >"$sb/planted-unquoted2.sh"
  (cd "$sb" && git add -- --rcfile=sc.sh sc.sh planted-unquoted2.sh)
  if expect_landed "shellcheck plant 3" test -f "$sb/--rcfile=sc.sh"; then
    expect_red "shellcheck is not switched off by a file named --rcfile=sc.sh" "$sb" "./planted-unquoted2.sh:3:" bash scripts/dev/validate.sh
  fi
  drop_sandbox "$sb"

  # 83. a key on a line shellcheck flags is not printed in full
  sb=$(make_sandbox) || abort_sandbox
  printf '#!/usr/bin/env bash\necho %s1 "%s"\n' "$d" "$key" >"$sb/planted-leak.sh"
  (cd "$sb" && git add planted-leak.sh)
  if expect_landed "shellcheck plant 4" grep -q "api03" "$sb/planted-leak.sh"; then
    out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
    if printf '%s\n' "$out" | grep -F -q -- "$key"; then
      fail "validate printed a key in full from shellcheck's output" "$out"
    elif printf '%s\n' "$out" | grep -q "planted-leak.sh:2:.*SC2086"; then
      pass "shellcheck findings show no key in full"
    else
      fail "shellcheck findings show no key in full: SC2086 was not reported" "$out"
    fi
  fi
  drop_sandbox "$sb"

  # 84. no output line starts with "::", which the CI runner would read as a command
  sb=$(make_sandbox) || abort_sandbox
  cmd_name='::warning title=Spoof::x.sh'
  if can_create "$sb" "$cmd_name"; then
    printf '#!/usr/bin/env bash\nrm -f %s1\n' "$d" >"$sb/$cmd_name"
    (cd "$sb" && git add -- "./$cmd_name")
    if expect_landed "shellcheck plant 5" test -f "$sb/$cmd_name"; then
      out=$(cd "$sb" && bash scripts/dev/validate.sh 2>&1)
      if printf '%s\n' "$out" | grep -q '^[[:space:]]*::'; then
        fail "validate printed a line that starts with :: (after any spaces)" "$out"
      elif printf '%s\n' "$out" | grep -q "SC2086"; then
        pass "validate prints no line that starts with ::, even for a file named ::warning"
      else
        fail "validate prints no line that starts with ::: the planted SC2086 was not reported" "$out"
      fi
    fi
  else
    skip "a file named ::warning: this file system does not allow a colon"
  fi
  drop_sandbox "$sb"
elif [ "${REQUIRE_SHELLCHECK:-0}" = "1" ]; then
  fail "shellcheck plants: shellcheck is required here but not installed"
else
  skip "shellcheck plants: shellcheck not installed"
fi

echo "plants: perl syntax and shellcheck: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
