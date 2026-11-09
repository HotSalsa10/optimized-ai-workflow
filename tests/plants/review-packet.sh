#!/usr/bin/env bash
# Plants for the review packet's Tree line (step 5b.1): each planted break
# turns tests/review-packet.test.sh red for its stated reason, in a
# throwaway copy of the repo. The breaks are data: "=== NAME | FILE |
# REASON", the text OLD (in FILE exactly once), "---", the text NEW
# (tests/lib.sh, plant_data). The SHA-256 plant runs only where git can make
# a repository with SHA-256 ids, as the test's own case does.
# shellcheck disable=SC2016 # the plants are literal perl text
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: review packet"
work=$(new_sandbox_dir) || abort_sandbox
cat >"$work/plants.txt" <<'PLANTS-END'
=== the Tree line dropped | method/scripts/method/lib/packet.pl | the header names HEAD's tree on the line after HEAD, so the packet can be matched to its files
  "HEAD: $head",
  "Tree: $head_tree",
---
  "HEAD: $head",
=== the Tree line names HEAD's commit | method/scripts/method/lib/packet.pl | the header names HEAD's tree on the line after HEAD, so the packet can be matched to its files
  "Tree: $head_tree",
---
  "Tree: $head",
PLANTS-END
plant_data "$work/plants.txt" tests/review-packet.test.sh
probe=$(new_sandbox_dir) || abort_sandbox
if (cd "$probe" && git init -q --object-format=sha256) 2>/dev/null; then
  cat >"$work/sha256.txt" <<'PLANTS-END'
=== the Tree line cut to a SHA-1 id's 40 digits | method/scripts/method/lib/packet.pl | a repository with SHA-256 ids: the header names HEAD's whole 64-digit tree id
  "Tree: $head_tree",
---
  "Tree: " . substr($head_tree, 0, 40),
PLANTS-END
  plant_data "$work/sha256.txt" tests/review-packet.test.sh
else
  skip "the Tree line cut to a SHA-1 id's 40 digits: this git cannot make a repository with SHA-256 ids"
fi
drop_sandbox "$probe" || true
drop_sandbox "$work" || true
echo "plants: review packet: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
