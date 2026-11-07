#!/usr/bin/env bash
# Fails when a tracked text file has CRLF, mixed or CR-only line endings, in
# the index or in the working tree. Only .cmd and .bat files, and files that
# .gitattributes marks binary, may hold CR.
# Checks what a fresh clone gets (tracked files), not untracked local files.
# The staged copy and the working copy are judged separately. git calls a
# copy binary (-text) when it holds a NUL byte or a lone CR; such a copy is
# read here directly, and fails if it holds a CR and no NUL byte, so a lone
# CR cannot hide CRLF lines from this check.
set -u
# perl reads bytes here; these settings would change how it reads them
unset PERL_UNICODE PERL5OPT

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "line-endings: FAIL - not inside a git repository"
  exit 2
}
cd "$root" || exit 2
# Pathspecs below must mean what they say, whatever the caller's settings.
unset GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS

# Shows a path with control characters (also UTF-8 C1 controls) as \xNN and
# the CI runner's old command form (## [) broken up.
esc() {
  printf '%s' "$1" | perl -pe 's/([\x00-\x1F\x7F])/sprintf("\\x%02X", ord $1)/ge; s/\xC2([\x80-\x9F])/sprintf("\\xC2\\x%02X", ord $1)/ge; s/##\[/#\\x23[/g'
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
  case "$attr" in
    *-text*) continue ;; # marked binary in .gitattributes
  esac
  crlf=""
  lone=""
  case "$index_eol" in
    i/crlf | i/mixed) crlf=1 ;;
    i/-text) staged_blob "$path" | cr_not_binary && lone="the staged copy" ;;
  esac
  case "$worktree_eol" in
    w/crlf | w/mixed) crlf=1 ;;
    w/-text) [ -f "$path" ] && cr_not_binary <"./$path" && lone="${lone:+$lone and }the working copy" ;;
  esac
  if [ -n "$crlf" ]; then
    examined=$((examined + 1))
    echo "line-endings: CRLF in $(esc "$path") ($index_eol $worktree_eol)"
    bad=$((bad + 1))
  elif [ -n "$lone" ]; then
    examined=$((examined + 1))
    echo "line-endings: CR in $(esc "$path") ($lone, which git reads as binary because of a lone CR)"
    bad=$((bad + 1))
  else
    case "$index_eol $worktree_eol" in
      "i/-text w/-text" | "i/-text w/") ;; # binary, and nothing to check
      *) examined=$((examined + 1)) ;;
    esac
  fi
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
