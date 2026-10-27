#!/usr/bin/env bash
# Fails when a tracked text file has CRLF, mixed or CR-only line endings, in
# the index or in the working tree. Only .cmd and .bat files may use CRLF.
# Checks what a fresh clone gets (tracked files), not untracked local files.
# git calls a file binary (-text) when it holds a NUL byte or a lone CR. Such a
# file, in the index or in the working tree, is read here directly unless
# .gitattributes marks it binary: if it has no NUL byte and holds a CR, it
# fails, so a lone CR cannot hide CRLF lines from this check.
set -u

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "line-endings: FAIL - not inside a git repository"
  exit 2
}
cd "$root" || exit 2

# Shows a path with control characters (also UTF-8 C1 controls) as \xNN and
# the CI runner's command forms broken up.
esc() {
  printf '%s' "$1" | perl -pe 's/([\x00-\x1F\x7F])/sprintf("\\x%02X", ord $1)/ge; s/\xC2([\x80-\x9F])/sprintf("\\xC2\\x%02X", ord $1)/ge; s/##\[/#\\x23[/g; s/::/:\\x3A/g'
}

# cr_not_binary: standard input holds a CR and no NUL byte.
cr_not_binary() {
  perl -e 'binmode STDIN; local $/; my $b = <STDIN>; $b = "" unless defined $b; exit(index($b, "\0") < 0 && index($b, "\r") >= 0 ? 0 : 1)'
}

# staged_blob PATH: the staged copy of PATH (stage 0) on standard output.
staged_blob() {
  oid=$(git ls-files -s -z -- ":(literal)$1" | perl -0ne 'print $1 if /^\d+ ([0-9a-f]+) 0\t/')
  [ -n "$oid" ] && git cat-file blob "$oid"
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
  read -r index_eol worktree_eol attr <<EOF
$info
EOF
  if [ "$index_eol" = "i/-text" ] || [ "$worktree_eol" = "w/-text" ]; then
    case "$attr" in
      *-text*) continue ;; # marked binary in .gitattributes
    esac
    found=""
    if [ "$index_eol" = "i/-text" ] && staged_blob "$path" | cr_not_binary; then
      found="the staged copy"
    fi
    if [ "$worktree_eol" = "w/-text" ] && [ -f "$path" ] && cr_not_binary <"./$path"; then
      found="${found:+$found and }the working copy"
    fi
    if [ -n "$found" ]; then
      examined=$((examined + 1))
      echo "line-endings: CR in $(esc "$path") ($found, which git reads as binary because of a lone CR)"
      bad=$((bad + 1))
      continue
    fi
    case "$index_eol" in
      i/-text) continue ;; # binary in the index: nothing more to check
    esac
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
