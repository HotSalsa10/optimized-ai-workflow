#!/usr/bin/env bash
# Fails when a tracked text file has CRLF, mixed or CR-only line endings, in
# the index or in the working tree. Only .cmd and .bat files may use CRLF.
# Checks what a fresh clone gets (tracked files), not untracked local files.
# git calls a file binary (-text) when it holds a NUL byte or a lone CR. A
# file without a NUL byte is read here directly, so a lone CR cannot hide
# CRLF lines from this check.
set -u

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "line-endings: FAIL - not inside a git repository"
  exit 2
}
cd "$root" || exit 2

# Shows a path with control characters as \xNN.
esc() {
  printf '%s' "$1" | perl -pe 's/([\x00-\x1F\x7F])/sprintf("\\x%02X", ord $1)/ge'
}

# has_cr_not_binary FILE: FILE holds a CR and no NUL byte.
has_cr_not_binary() {
  perl -e 'open my $f, "<:raw", $ARGV[0] or exit 2; local $/; my $b = <$f>; $b = "" unless defined $b; exit(index($b, "\0") < 0 && index($b, "\r") >= 0 ? 0 : 1)' "./$1"
}

tab=$(printf '\t')
examined=0
bad=0
listed=0
while IFS= read -r -d '' line; do
  listed=$((listed + 1))
  path=${line#*"$tab"}
  info=${line%%"$tab"*}
  case "$path" in
    *.cmd | *.bat) continue ;;
  esac
  read -r index_eol worktree_eol _rest <<EOF
$info
EOF
  if [ "$index_eol" = "i/-text" ]; then
    [ -f "$path" ] || continue
    if has_cr_not_binary "$path"; then
      examined=$((examined + 1))
      echo "line-endings: CR in $(esc "$path") (git reads it as binary because of a lone CR)"
      bad=$((bad + 1))
    fi
    continue
  fi
  examined=$((examined + 1))
  case "$index_eol $worktree_eol" in
    *crlf* | *mixed*)
      echo "line-endings: CRLF in $(esc "$path") ($index_eol $worktree_eol)"
      bad=$((bad + 1))
      ;;
  esac
done < <(git ls-files -z --eol)

if [ "$listed" -eq 0 ] || [ "$examined" -eq 0 ]; then
  echo "line-endings: FAIL - examined 0 tracked text files; nothing was checked"
  exit 1
fi
if [ "$bad" -gt 0 ]; then
  printf "%s\n" "line-endings: FAIL - $bad of $examined tracked text files have CR or CRLF line endings (fix: convert each file to LF, for example perl -pi -e 's/\\r\\n?/\\n/g' FILE, then git add FILE)"
  exit 1
fi
echo "line-endings: PASS - examined $examined tracked text files, none with CRLF"
