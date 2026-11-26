#!/usr/bin/env bash
# Plants for the example projects (step 7.7; examples/, docs/plans/step7.md
# S15): each planted break turns tests/examples.test.sh red for its stated
# reason, in a throwaway copy of the repo, with only the cases kept for
# that reason (after they pass on the clean copy). The breaks are data:
# "=== NAME | FILE | REASON", the text OLD (in FILE exactly once), "---",
# the text NEW (tests/lib.sh, plant_data). PLANT_SHARD=K/N runs every Nth
# one from the Kth. (validate's portability lint over examples/ is planted
# in tests/plants/dev-checks.sh.)
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: examples"
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/plants.txt" <<'PLANTS-END'
=== an example whose answers would lower the floor (no review: STRICT none) | examples/word-game/answers.txt | word-game: the answers keep the floor
STRICT	standard
---
STRICT	none
=== the card's line for files stored with CRLF dropped | method/scripts/method/lib/setup.pl | records-keeper: the CRLF file is reported on the card, not changed
  if (my @crlf = @{ $det->{crlf} || [] }) {
---
  if (my @crlf = ()) {
=== make.sh lets a folder inside its repository through | examples/lib.sh | make.sh refuses a folder inside the repository it sits in
    "$es_repo"/*)
---
    "$es_repo"/nothing/*)
=== records-keeper's script writes without the live-write helper | examples/records-keeper/project/scripts/post-rows.sh | records-keeper: the live-write helper refuses a write with no reason
method_live_opts "$@" || exit 2
method_live_write bash
---
bash
=== setup's CRLF list takes the attributes as one word, as before the fix | method/scripts/method/lib/setup.pl | setup names a file stored with CRLF that no attribute asks for
        next if grep { $_ eq '-text' || $_ eq 'eol=crlf' } split /\s+/, ($attr // '');
---
        next if $info =~ m{attr/\S*(?:-text|eol=crlf)};
=== setup's CRLF list skips no file for its attributes | method/scripts/method/lib/setup.pl | setup names a file stored with CRLF that no attribute asks for
        next if grep { $_ eq '-text' || $_ eq 'eol=crlf' } split /\s+/, ($attr // '');
---

=== example_commit names the owner through git's settings, which the caller's environment overrides, and runs the caller's hooks | examples/lib.sh | make.sh gives the same history under the caller's own git name
    GIT_AUTHOR_NAME="Example Owner" GIT_AUTHOR_EMAIL=owner@example.invalid GIT_AUTHOR_DATE="$ec_date" \
      GIT_COMMITTER_NAME="Example Owner" GIT_COMMITTER_EMAIL=owner@example.invalid GIT_COMMITTER_DATE="$ec_date" \
      example_git -c core.hooksPath=.git/example-no-hooks -c commit.gpgsign=false -c i18n.commitEncoding=UTF-8 \
      commit -q -m "$ec_msg"
---
    GIT_AUTHOR_DATE="$ec_date" GIT_COMMITTER_DATE="$ec_date" git -c user.name="Example Owner" \
      -c user.email=owner@example.invalid -c commit.gpgsign=false commit -q -m "$ec_msg"
=== example_start keeps the caller's GIT_DIR, GIT_WORK_TREE and GIT_INDEX_FILE, so make.sh writes into another repository | examples/lib.sh | make.sh run with GIT_DIR, GIT_WORK_TREE and GIT_INDEX_FILE set to another repository leaves that repository as it was
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_CONFIG GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_SHALLOW_FILE GIT_IMPLICIT_WORK_TREE GIT_PREFIX GIT_INTERNAL_SUPER_PREFIX \
    GIT_NAMESPACE GIT_DIFF_OPTS GIT_EXTERNAL_DIFF GIT_REPLACE_REF_BASE \
    GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS
---
  :
=== example_start takes the caller's init template, whose exclude file skips a file | examples/lib.sh | make.sh gives the same history under the caller's own git name
  example_git -c init.defaultBranch=main -c init.defaultObjectFormat=sha1 init -q --template= || exit 2
---
  example_git -c init.defaultBranch=main -c init.defaultObjectFormat=sha1 init -q || exit 2
=== the build's git keeps the caller's global ignore file | examples/lib.sh | make.sh gives the same history under the caller's own git name
  git -c core.excludesFile=.git/example-no-ignore \
---
  git \
=== the build's git keeps the caller's global attributes file | examples/lib.sh | make.sh gives the same history under the caller's own git name
    -c core.attributesFile=.git/example-no-attributes \
---
    -c example.none=1 \
=== the build's git keeps the caller's file-system monitor | examples/lib.sh | make.sh gives the same history under the caller's own git name
    -c core.fsmonitor=false "$@"
---
    "$@"
=== example_commit keeps the caller's commit encoding | examples/lib.sh | make.sh gives the same history under the caller's own git name
-c commit.gpgsign=false -c i18n.commitEncoding=UTF-8 \
---
-c commit.gpgsign=false \
=== example_start keeps the caller's GIT_DEFAULT_HASH, so the objects are sha256 | examples/lib.sh | make.sh gives the same history under the caller's own git name
  unset GIT_DEFAULT_HASH GIT_DEFAULT_REF_FORMAT
---
  unset GIT_DEFAULT_REF_FORMAT
=== example_start keeps the caller's GIT_CONFIG_COUNT settings | examples/lib.sh | make.sh gives the same history under the caller's own git name
  unset GIT_CONFIG_COUNT
---
  :
=== example_start keeps the caller's GIT_CONFIG_PARAMETERS settings | examples/lib.sh | make.sh gives the same history under the caller's own git name
  unset GIT_CONFIG_PARAMETERS
---
  :
=== example_start writes the build's ignore setting into the built repository, where it turns off the person's own global ignore | examples/lib.sh | the built example holds none of the build's own ignore, attributes and monitor settings
  git config core.autocrlf false || exit 2
---
  git config core.autocrlf false || exit 2
  git config core.excludesFile .git/example-no-ignore || exit 2
=== records-keeper posts a row the live ledger already holds | examples/records-keeper/project/scripts/append-rows.sh | records-keeper: the live-write helper refuses a write with no reason
push @new, $l unless $have{$l}++
---
push @new, $l
=== records-keeper's post-rows runs on without the method's helper | examples/records-keeper/project/scripts/post-rows.sh | records-keeper: the live-write helper refuses a write with no reason
if [ ! -f "$root/scripts/method/live-write.sh" ]; then
---
if false; then
PLANTS-END
plant_data "$work/plants.txt" tests/examples.test.sh only
drop_sandbox "$work" || true
echo "plants: examples: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
