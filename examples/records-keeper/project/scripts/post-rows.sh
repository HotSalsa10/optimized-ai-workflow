#!/usr/bin/env bash
# post-rows.sh: posts the rows of ledger.csv to the live ledger. Here the
# live ledger is a local file outside this repository, standing in for
# real records (KEEPER_LIVE names it; ../records-keeper-live.csv when
# unset). It goes through the method's live-write helper
# (scripts/method/live-write.sh): it refuses to run without
# --reason "why", and writes only with --live; without it, it says what it
# would run and writes nothing. A row the live ledger already holds is not
# posted again (append-rows.sh). It needs the method installed: without
# the helper it refuses and writes nothing.
#
# Usage: bash scripts/post-rows.sh --reason "why" [--live]
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=${here%/*}
if [ ! -f "$root/scripts/method/live-write.sh" ]; then
  echo "post-rows: REFUSED - scripts/method/live-write.sh is not here; it comes with the method, so install the method first" >&2
  exit 2
fi
# shellcheck source=/dev/null # installed by the method's sync
. "$root/scripts/method/live-write.sh" || exit 2
method_live_opts "$@" || exit 2
method_live_write bash "$root/scripts/append-rows.sh" "$root/ledger.csv" "${KEEPER_LIVE:-$root/../records-keeper-live.csv}"
