#!/usr/bin/env bash
# Fails when a tracked text file has CRLF or mixed line endings, in the index
# or in the working tree. Only .cmd and .bat files may use CRLF.
# Checks what a fresh clone gets (tracked files), not untracked local files.
set -u

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "line-endings: FAIL - not inside a git repository"
  exit 2
}
cd "$root" || exit 2

tab=$(printf '\t')
examined=0
bad=0
listing=$(git ls-files --eol) || {
  echo "line-endings: FAIL - git ls-files --eol did not run"
  exit 2
}

while IFS= read -r line; do
  [ -n "$line" ] || continue
  path=${line#*"$tab"}
  info=${line%%"$tab"*}
  case "$path" in
    *.cmd | *.bat) continue ;;
  esac
  read -r index_eol worktree_eol _rest <<EOF
$info
EOF
  case "$index_eol" in
    i/-text) continue ;;
  esac
  examined=$((examined + 1))
  case "$index_eol $worktree_eol" in
    *crlf* | *mixed*)
      echo "line-endings: CRLF in $path ($index_eol $worktree_eol)"
      bad=$((bad + 1))
      ;;
  esac
done <<EOF
$listing
EOF

if [ "$examined" -eq 0 ]; then
  echo "line-endings: FAIL - examined 0 tracked text files; nothing was checked"
  exit 1
fi
if [ "$bad" -gt 0 ]; then
  echo "line-endings: FAIL - $bad of $examined tracked text files have CRLF line endings (fix: git add --renormalize .)"
  exit 1
fi
echo "line-endings: PASS - examined $examined tracked text files, none with CRLF"
