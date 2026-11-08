# shellcheck shell=bash
# The harness's helpers (step 5.2, DECISIONS A49): the real Claude Code
# client, run against the local fake Claude (fake-api.pl), in a throwaway
# project, at no cost. Source this file after tests/lib.sh; do not run it.
#
# The caller sets:
#   HARNESS  this folder
#   H_CLIENT the client binary to run
#   H_WORK   a throwaway folder (tests/lib.sh's new_sandbox_dir)
#
# A case:
#   h_case NAME          makes the case's folders and a project (git, one
#                        commit, branch main). Every case folder name holds
#                        a space, an apostrophe and a non-ASCII letter, so
#                        each hook command is seen to quote its paths.
#   h_settings           writes standard input as the project's
#                        .claude/settings.json
#   h_fixtures           copies the fixture hooks and agents into the project
#   h_fake SCRIPT [CAP]  starts the fake (fake-api.pl, or H_FAKE_API for a
#                        plant) with a script (fake-api.pl's format)
#                        and a request cap (default 40); fails when it does
#                        not answer within 5 s, and the case must stop there
#   h_client SECS [VAR=VALUE...] -- ARGS...
#                        runs the client once in the project, "-p go" with
#                        stream-json output, bounded by SECS, with an
#                        environment built from a fixed list (no key but the
#                        dummy one, no outside proxy, HOME and TMPDIR inside
#                        the case); VAR=VALUE adds to it
#   h_stop               stops the fake
# Questions about the case's results, each 0 (yes) or 1 (no), printing
# nothing: h_reached, h_no_connect, h_no_overcap, h_tmp_clean, h_req_has
# TEXT, h_tsv_has TEXT, h_ran FILE. h_safe NAME passes or fails the four
# safety questions as one line. h_init FIELD prints a field of the client's
# init event.

h_slug() {
  printf '%s' "$1" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g'
}

h_case() {
  H_DIR="$H_WORK/it's a case ü/$1"
  H_PROJ="$H_DIR/project"
  rm -rf "$H_DIR"
  mkdir -p "$H_DIR/home" "$H_DIR/tmp" "$H_DIR/fake" "$H_PROJ" || return 1
  (
    cd "$H_PROJ" || exit 1
    export HOME="$H_DIR/home" GIT_CONFIG_NOSYSTEM=1
    git init -q . &&
      git symbolic-ref HEAD refs/heads/main &&
      git config user.name Harness &&
      git config user.email harness@example.invalid &&
      git config commit.gpgsign false &&
      git commit -q --allow-empty -m init &&
      mkdir -p .claude &&
      printf '.harness/\n' >>.git/info/exclude
  ) || return 1
}

h_settings() {
  cat >"$H_PROJ/.claude/settings.json"
}

h_fixtures() {
  mkdir -p "$H_PROJ/.claude/hooks/fixture" "$H_PROJ/.claude/agents" &&
    cp "$HARNESS"/hooks/*.sh "$H_PROJ/.claude/hooks/fixture/" &&
    cp "$HARNESS"/agents/*.md "$H_PROJ/.claude/agents/"
}

h_fake() {
  rm -f "$H_DIR/fake/port"
  perl "${H_FAKE_API:-$HARNESS/fake-api.pl}" --script "$1" --log-dir "$H_DIR/fake" --port-file "$H_DIR/fake/port" \
    --max-requests "${2:-40}" --max-seconds 300 >"$H_DIR/fake/stdout" 2>&1 &
  H_FAKE_PID=$!
  perl -MTime::HiRes=sleep,time -e 'my $u = time + 5; until (-s $ARGV[0]) { exit 1 if time > $u; sleep 0.05 }' "$H_DIR/fake/port" || {
    h_stop
    return 1
  }
  H_PORT=$(cat "$H_DIR/fake/port")
  # the fake must answer before the client starts; the whole exchange is
  # under an alarm, so a listener that never answers cannot hang the case
  perl -MIO::Socket::INET -e '
    $SIG{ALRM} = sub { exit 1 }; alarm 5;
    my $s = IO::Socket::INET->new(PeerAddr => "127.0.0.1", PeerPort => $ARGV[0], Timeout => 3) or exit 1;
    print $s "GET /harness-alive HTTP/1.1\r\nHost: x\r\n\r\n";
    my $l = <$s>; exit(defined $l && $l =~ m{\AHTTP/1\.1 200 } ? 0 : 1)' "$H_PORT" || {
    h_stop
    return 1
  }
}

h_client() {
  secs=$1
  shift
  h_env=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    case "$1" in
      *OAUTH* | *AUTH_TOKEN* | *BEDROCK* | *VERTEX* | ANTHROPIC_API_KEY=* | CLAUDE_CODE_USE_*)
        echo "harness: refusing to pass $1 to the client: only the dummy key may reach it" >&2
        return 2
        ;;
    esac
    h_env+=("$1")
    shift
  done
  [ "${1:-}" = "--" ] && shift
  start=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  perl "$HARNESS/bound.pl" "$secs" env -i \
    HOME="$H_DIR/home" PATH=/usr/bin:/bin TMPDIR="$H_DIR/tmp" \
    ANTHROPIC_BASE_URL="http://127.0.0.1:$H_PORT" ANTHROPIC_API_KEY=dummy \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_AUTOUPDATER=1 \
    HTTPS_PROXY="http://127.0.0.1:$H_PORT" HTTP_PROXY="http://127.0.0.1:$H_PORT" NO_PROXY=127.0.0.1 \
    GIT_CONFIG_NOSYSTEM=1 ${h_env[@]+"${h_env[@]}"} \
    /bin/sh -c 'cd "$1" && shift && exec "$@"' sh "${H_CWD:-$H_PROJ}" \
    "$H_CLIENT" -p "${H_PROMPT:-go}" --output-format stream-json --verbose "$@" \
    </dev/null >"$H_DIR/out.jsonl" 2>"$H_DIR/err.txt"
  H_RC=$?
  end=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  H_SECS=$(perl -e 'printf "%.1f", $ARGV[1] - $ARGV[0]' "$start" "$end")
  H_TOTAL_SECS=$(perl -e 'printf "%.1f", $ARGV[0] + $ARGV[1]' "${H_TOTAL_SECS:-0}" "$H_SECS")
  H_RUNS=$((${H_RUNS:-0} + 1))
}

h_stop() {
  if [ -n "${H_FAKE_PID:-}" ]; then
    kill "$H_FAKE_PID" 2>/dev/null
    wait "$H_FAKE_PID" 2>/dev/null
    H_FAKE_PID=""
  fi
  return 0
}

# --- questions ---

h_reached() {
  LC_ALL=C grep -q "	POST	/v1/messages" "$H_DIR/fake/requests.tsv" 2>/dev/null
}
h_no_connect() {
  ! LC_ALL=C grep -q "CONNECT-REFUSED" "$H_DIR/fake/requests.tsv" 2>/dev/null
}
h_no_overcap() {
  ! LC_ALL=C grep -q "	over-cap	" "$H_DIR/fake/requests.tsv" 2>/dev/null
}
# the client's own temporary folder for this user, outside the case
h_tmp_list() {
  perl -e 'opendir my $d, $ARGV[0] or exit 0; print "$_\n" for sort readdir $d' "/tmp/claude-$(id -u)"
}
# nothing new in it that names this case's project
h_tmp_clean() {
  slug=$(h_slug "$H_PROJ")
  ! h_tmp_list | LC_ALL=C grep -F -q -- "$slug"
}
h_req_has() {
  LC_ALL=C grep -F -q -- "$1" "$H_DIR"/fake/req-*.json 2>/dev/null
}
h_tsv_has() {
  LC_ALL=C grep -F -q -- "$1" "$H_DIR/fake/requests.tsv" 2>/dev/null
}
h_ran() {
  [ -e "$H_PROJ/$1" ]
}
h_init() {
  perl "$HARNESS/read.pl" init "$1" "$H_DIR/out.jsonl"
}

h_safe() {
  why=""
  h_reached || why="$why no request reached the fake;"
  h_no_connect || why="$why an outside connection was tried;"
  h_no_overcap || why="$why the request cap was reached;"
  h_tmp_clean || why="$why the client left files in /tmp/claude-$(id -u);"
  if [ -z "$why" ]; then
    pass "$1: reached the fake, no outside connection, under the cap, no files outside the case"
  else
    fail "$1: unsafe or empty run:$why" "client exit ${H_RC:-?}; $(tail -5 "$H_DIR/err.txt" 2>/dev/null)"
  fi
}
