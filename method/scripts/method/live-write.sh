# shellcheck shell=bash
# live-write.sh: the helper for a project's own script that writes to live
# records, that is, real data outside this repository (a database, a shared
# sheet, an account reached through its API) (step 7.6;
# docs/plans/step7.md S13; DECISIONS A78 (13)).
#
# A project's script sources it, hands it the person's words, then names
# the command that writes:
#
#   . scripts/method/live-write.sh || exit 2
#   method_live_opts "$@" || exit 2
#   method_live_write perl tools/post-rows.pl rows.csv
#
# and the person runs that script with --reason "<why>", and with --live
# only when the write is meant. The command is the script's own: no word
# the person gives becomes part of it. A script with options of its own
# reads them first and passes on only --reason and --live.
#
#   method_live_opts [--reason TEXT] [--live]
#     reads the person's words, which may be only these two options;
#     refuses and returns 2, with the refusal on stderr: no --reason, a
#       reason that is empty or holds a control character (a new line or
#       a tab), --reason given twice, or any other word (-- included);
#     returns 0 and keeps the reason and the choice of --live for
#       method_live_write. Each call first forgets what an earlier one
#       kept, so after a refusal no reason is kept.
#   method_live_write COMMAND [ARG...]
#     refuses, runs nothing and returns 2, with the refusal on stderr:
#       method_live_opts has not accepted a reason, or no command;
#     prints the reason as its first line: "live-write: reason: TEXT";
#     without --live (the default) does a dry run: prints the command it
#       would run, runs nothing and returns 0;
#     with --live prints the command, runs it with METHOD_LIVE_REASON set
#       to the reason, and returns its status.
# It keeps no log file and changes no shell option of the script that
# sources it. What it keeps is set when it is sourced, so none of it comes
# from the environment. Run on its own (bash live-write.sh), it runs
# nothing.
#
# Rule it serves:
# - M063: a script that writes to live records refuses to run without a
#   stated reason, and does a dry run unless told otherwise.

if [ -z "${BASH_VERSION:-}" ]; then
  echo "live-write: FAIL - source this file from a bash script; this shell is not bash" >&2
  # shellcheck disable=SC2317 # exit is reached when the file was run, not sourced
  return 2 2>/dev/null || exit 2
fi
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "live-write: FAIL - this file runs nothing on its own; source it from the project's script (. scripts/method/live-write.sh) and call method_live_opts and method_live_write" >&2
  exit 2
fi

# what method_live_opts keeps for method_live_write: set here, so a value
# in the environment never counts
_method_live_ok=0 _method_live_reason='' _method_live_on=0

# _method_live_refuse TEXT: the refusal, on stderr
_method_live_refuse() {
  printf 'live-write: REFUSED - %s; nothing was run\n' "$1" >&2
}

method_live_opts() {
  _method_live_ok=0 _method_live_reason='' _method_live_on=0
  local reason='' have_reason=0 live=0
  while [ $# -gt 0 ]; do
    case $1 in
      --reason)
        if [ "$have_reason" = 1 ]; then
          _method_live_refuse '--reason is given twice; give one reason'
          return 2
        fi
        if [ $# -lt 2 ]; then
          _method_live_refuse '--reason needs its text: --reason "why this write is made"'
          return 2
        fi
        reason=$2
        have_reason=1
        shift 2
        ;;
      --live)
        live=1
        shift
        ;;
      *)
        _method_live_refuse "the word $1 is not known here; give only --reason \"why\" and, to write, --live (the script names the command)"
        return 2
        ;;
    esac
  done
  if [ "$have_reason" = 0 ]; then
    _method_live_refuse 'no reason given: a write to live records needs one, given as --reason "why this write is made"'
    return 2
  fi
  case $reason in
    *[![:space:]]*) ;;
    *)
      _method_live_refuse 'the reason is empty: say why this write is made'
      return 2
      ;;
  esac
  case $reason in
    *[[:cntrl:]]*)
      _method_live_refuse 'the reason holds a control character (a new line or a tab): write it on one line'
      return 2
      ;;
  esac
  _method_live_reason=$reason _method_live_on=$live _method_live_ok=1
  return 0
}

method_live_write() {
  if [ "$_method_live_ok" != 1 ]; then
    _method_live_refuse 'no reason given: a write to live records needs one, given as --reason "why this write is made" and read by method_live_opts'
    return 2
  fi
  if [ $# -eq 0 ]; then
    _method_live_refuse 'no command: the script names the command that writes'
    return 2
  fi
  printf 'live-write: reason: %s\n' "$_method_live_reason"
  if [ "$_method_live_on" != 1 ]; then
    printf 'live-write: dry run, nothing written; add --live to write. It would run:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  printf 'live-write: live, running:'
  printf ' %q' "$@"
  printf '\n'
  METHOD_LIVE_REASON=$_method_live_reason "$@"
}
