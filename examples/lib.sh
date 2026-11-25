# shellcheck shell=bash
# Shared by the examples' make.sh files (step 7.7; docs/plans/step7.md
# S15). Source it; do not run it.
#
# An example is a project as it stands before the method: its files under
# project/, and the answers its owner would give /method-setup in
# answers.txt. make.sh builds it in a new folder outside this repository
# (example_start), so no CLAUDE.md, AGENTS.md or .claude/ an example needs
# is ever written under this repository's tree, where it would load into
# this repository's own sessions. Each commit has fixed names and dates
# and runs no hook (example_commit), and the caller's git settings that
# would change what is committed are turned off (example_start), so the
# same make.sh gives the same history whoever runs it. All data is
# invented.

# example_start HERE DIR: refuses (exit 2), before it writes anything, a
# DIR not given, one that is there but is not an empty folder (one ls
# cannot list counts as not empty), one whose parent folder is not there,
# and one inside this repository (HERE's grandparent); else copies
# HERE/project/ into DIR, starts a git repository there on main and enters
# DIR. The caller's GIT_DIR, GIT_INDEX_FILE and the like, which would send
# every git call to another repository, are cleared first, as
# method/scripts/method/lib/git.pl clears them. The new repository takes no
# init template, and its own settings turn off the caller's global ignore
# and attributes files (they name a file in .git that is never there) and
# any file-system monitor, so none of them changes what is committed
example_start() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_CONFIG GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_SHALLOW_FILE GIT_IMPLICIT_WORK_TREE GIT_PREFIX GIT_INTERNAL_SUPER_PREFIX \
    GIT_NAMESPACE GIT_DIFF_OPTS GIT_EXTERNAL_DIFF GIT_REPLACE_REF_BASE \
    GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS
  es_here=$1
  es_dir=${2:-}
  if [ -z "$es_dir" ]; then
    echo "make: usage: bash make.sh DIR (a new or empty folder outside this repository)" >&2
    exit 2
  fi
  if [ -e "$es_dir" ] || [ -L "$es_dir" ]; then
    # a folder ls cannot list counts as not empty
    if [ ! -d "$es_dir" ] || ! es_list=$(ls -A "$es_dir" 2>/dev/null) || [ -n "$es_list" ]; then
      echo "make: REFUSED - $es_dir is not an empty folder (or cannot be listed); name a new or empty one" >&2
      exit 2
    fi
    es_real=$(cd -P "$es_dir" && pwd -P) || exit 2
  else
    es_base=$(basename "$es_dir")
    es_up=$(cd -P "$(dirname "$es_dir")" 2>/dev/null && pwd -P) || {
      echo "make: REFUSED - the folder that would hold $es_dir is not there" >&2
      exit 2
    }
    es_real=${es_up%/}/$es_base
  fi
  # the real paths are compared, so a link into this repository is caught;
  # nothing is written before this check
  es_repo=$(cd -P "$es_here/../.." && pwd -P) || exit 2
  case "$es_real/" in
    "$es_repo"/*)
      echo "make: REFUSED - $es_dir is inside this repository; name a folder outside it" >&2
      exit 2
      ;;
  esac
  mkdir -p "$es_real" || exit 2
  cp -R "$es_here/project/." "$es_real/" || exit 2
  cd "$es_real" || exit 2
  git -c init.defaultBranch=main init -q --template= || exit 2
  git symbolic-ref HEAD refs/heads/main || exit 2
  git config core.autocrlf false || exit 2
  git config core.excludesFile .git/example-no-ignore || exit 2
  git config core.attributesFile .git/example-no-attributes || exit 2
  git config core.fsmonitor false || exit 2
}

# example_commit DATE MESSAGE [PATH...]: commits the PATHs (every file when
# none is named) as the example's owner on DATE (a fixed time, so the
# history is the same each time). The names and dates are set in the
# commit's environment, which wins over git's settings and the caller's
# own GIT_AUTHOR_* and GIT_COMMITTER_*, and no hook runs (core.hooksPath
# names a folder that is not there), so the person's own name and hooks
# never reach the example
example_commit() {
  ec_date=$1
  ec_msg=$2
  shift 2
  [ $# -gt 0 ] || set -- -A
  git add "$@" &&
    GIT_AUTHOR_NAME="Example Owner" GIT_AUTHOR_EMAIL=owner@example.invalid GIT_AUTHOR_DATE="$ec_date" \
      GIT_COMMITTER_NAME="Example Owner" GIT_COMMITTER_EMAIL=owner@example.invalid GIT_COMMITTER_DATE="$ec_date" \
      git -c core.hooksPath=.git/example-no-hooks -c commit.gpgsign=false commit -q -m "$ec_msg"
}
