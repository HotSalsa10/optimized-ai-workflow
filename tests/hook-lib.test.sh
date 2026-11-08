#!/usr/bin/env bash
# shellcheck disable=SC2016 # the single-quoted text is perl code: perl expands it
# Tests for the hooks' shared helpers (step 5.1): lib/hook.pl (input and
# output), lib/log.pl (the capped log, M072), json.pl as a library
# (Json::decode, Json::encode) and Secrets::scan_text in lib/secrets.pl.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: hook helpers"
lib="$(repo_root)/method/scripts/method/lib"
work=$(new_sandbox_dir) || abort_sandbox
export LIBDIR="$lib" WORK="$work"

# pl NAME CODE: runs CODE in perl with the helpers loaded; it must print
# exactly "ok" (anything else is shown as the failure).
pl() {
  name=$1
  got=$(perl -e 'require "$ENV{LIBDIR}/hook.pl"; require "$ENV{LIBDIR}/log.pl"; require "$ENV{LIBDIR}/secrets.pl";' -e "$2" 2>&1)
  if [ "$got" = "ok" ]; then pass "$name"; else fail "$name" "$got"; fi
}

# --- json.pl as a library ---
got=$(printf 'input that must not be read' | perl -e 'require "$ENV{LIBDIR}/json.pl"; my $rest = <STDIN>; print "after require: $rest"' 2>&1)
if [ "$got" = "after require: input that must not be read" ]; then pass "requiring json.pl runs nothing and reads no input"; else fail "requiring json.pl runs nothing and reads no input" "$got"; fi
got=$(PERL5OPT=-Mbigint perl -e 'require "$ENV{LIBDIR}/json.pl"; print "loaded"' 2>&1)
if [ "$got" = "loaded" ]; then pass "requiring json.pl under -Mbigint gives no warning"; else fail "requiring json.pl under -Mbigint gives no warning" "$got"; fi
pl "Json::decode reads an object" 'my ($d, $e) = Json::decode(qq({"a":[1,"x"],"b":null})); print(!defined $e && $d->{a}[1] eq "x" && exists $d->{b} && !defined $d->{b} ? "ok" : "bad")'
pl "Json::decode gives undef with no reason for null" 'my ($d, $e) = Json::decode("null"); print(!defined $d && !defined $e ? "ok" : "bad")'
for pair in "empty|" "not JSON|{" "invalid UTF-8|\"\\377\"" "a raw NUL byte|\"a\\000\"" "a surrogate|\"\\355\\240\\200\""; do
  what=${pair%%|*}
  input=${pair#*|}
  # shellcheck disable=SC2059 # the input is a printf format on purpose (octal escapes)
  printf "$input" >"$work/bad.json"
  cli=$(perl "$lib/json.pl" get <"$work/bad.json" 2>&1)
  lib_reason=$(perl -e 'require "$ENV{LIBDIR}/json.pl"; local $/; open my $f, "<:raw", "$ENV{WORK}/bad.json"; my ($d, $e) = Json::decode(scalar <$f>); print "json: ", $e // "NO REASON"' 2>&1)
  if [ -n "$cli" ] && [ "$cli" = "$lib_reason" ]; then pass "Json::decode refuses $what with the reason get gives"; else fail "Json::decode refuses $what with the reason get gives" "get: $cli / library: $lib_reason"; fi
done
pl "Json::encode writes compact JSON, keys sorted, ASCII only" 'print(Json::encode({b => 1, a => ["x", "caf\x{e9}", "\x{1F600}"]}) eq q({"a":["x","caf\u00e9","\ud83d\ude00"],"b":1}) ? "ok" : Json::encode({b => 1, a => ["x", "caf\x{e9}", "\x{1F600}"]}))'
pl "Json::encode escapes control characters" 'print(Json::encode("a\nb\x1b\x00") eq q("a\nb\u001b\u0000") ? "ok" : Json::encode("a\nb\x1b\x00"))'
pl "what Json::encode writes, Json::decode reads back" 'my $v = {k => ["\x{263a}", 2.5, "line\nbreak"]}; my ($d) = Json::decode(Json::encode($v)); print($d->{k}[0] eq "\x{263a}" && $d->{k}[1] == 2.5 && $d->{k}[2] eq "line\nbreak" ? "ok" : "bad")'

# --- hook.pl: input ---
# read FILE: runs Hook::read_input on FILE as standard input and prints
# "ok KEYS" or "reason: ..."
read_as() {
  perl -e 'require "$ENV{LIBDIR}/hook.pl"; my ($d, $e) = Hook::read_input(undef, $ARGV[0]); print defined $e ? "reason: $e" : "ok " . join(",", sort keys %$d)' "${2:-4194304}" <"$1" 2>&1
}
printf '{"tool_name":"Bash","tool_input":{"command":"ls"}}' >"$work/in.json"
got=$(read_as "$work/in.json")
if [ "$got" = "ok tool_input,tool_name" ]; then pass "read_input reads a hook's JSON object from standard input"; else fail "read_input reads a hook's JSON object from standard input" "$got"; fi
for pair in "empty input|the input is empty|" "an array|not a JSON object|[1]" "null|not a JSON object|null" "a string|not a JSON object|\"x\"" "malformed JSON|not valid JSON|{\"a\":" "invalid UTF-8|not valid UTF-8|{\"a\":\"\\377\"}"; do
  what=${pair%%|*}
  rest=${pair#*|}
  want=${rest%%|*}
  input=${rest#*|}
  # shellcheck disable=SC2059 # the input is a printf format on purpose (octal escapes)
  printf "$input" >"$work/in.json"
  got=$(read_as "$work/in.json")
  case "$got" in
    "reason: "*"$want"*) pass "read_input refuses $what ($want)" ;;
    *) fail "read_input refuses $what ($want)" "$got" ;;
  esac
done
perl -e 'print "{\"a\":\"", "x" x (4 * 1024 * 1024), "\"}"' >"$work/big.json"
got=$(read_as "$work/big.json")
case "$got" in
  "reason: the input is over 4194304 bytes") pass "read_input refuses input over 4 MB" ;;
  *) fail "read_input refuses input over 4 MB" "$(printf '%s' "$got" | head -c 200)" ;;
esac
perl -e 'print "{\"a\":\"", "x" x (4 * 1024 * 1024 - 8), "\"}"' >"$work/edge.json"
got=$(read_as "$work/edge.json")
if [ "$got" = "ok a" ]; then pass "read_input reads input of exactly 4 MB"; else fail "read_input reads input of exactly 4 MB" "$(printf '%s' "$got" | head -c 200)"; fi
printf '{"c":"a\\u0000b\\u001b[2J\\nc"}' >"$work/ctl.json"
got=$(read_as "$work/ctl.json")
if [ "$got" = "ok c" ]; then pass "read_input reads control characters written as JSON escapes"; else fail "read_input reads control characters written as JSON escapes" "$got"; fi

# --- hook.pl: output ---
pl "clean gives one line with every control and invisible character escaped" 'my $s = Hook::clean("a\nb\rc\x1b[31md\x07e\x{2028}f\x{202E}g\x{200B}h\x00i"); print($s eq q(a\x0Ab\x0Dc\x1B[31md\x07e\u{2028}f\u{202E}g\u{200B}h\x00i) ? "ok" : $s)'
pl "clean breaks up a missing-file message" 'my $s = Hook::clean("ls: No such file or directory; no such  directory"); print($s !~ /no such (?:file|directory)/i ? "ok" : $s)'
pl "clean marks a line that would open a packet section" 'print(Hook::clean("=== FAKE ===") =~ /\A\\===/ ? "ok" : Hook::clean("=== FAKE ==="))'
perl -e 'require "$ENV{LIBDIR}/hook.pl"; exit Hook::block("guard G4: refused \x1b[2J\nsecond line")' 2>"$work/err" >"$work/out"
code=$?
err=$(cat "$work/err")
if [ "$code" -eq 3 ] && [ ! -s "$work/out" ] && [ "$err" = 'guard G4: refused \x1B[2J\x0Asecond line' ] && [ "$(wc -l <"$work/err")" -eq 1 ]; then
  pass "block prints one clean line on stderr, nothing on stdout, and returns 3"
else
  fail "block prints one clean line on stderr, nothing on stdout, and returns 3" "exit $code, stderr: $err"
fi
got=$(perl -e 'require "$ENV{LIBDIR}/hook.pl"; exit Hook::warning("effort is low \x1b]0;title\x07 \x{263a}")' 2>&1)
code=$?
back=$(printf '%s' "$got" | perl "$lib/json.pl" get systemMessage 2>&1)
if [ "$code" -eq 0 ] && [ "$back" = "$(printf 'effort is low \\x1B]0;title\\x07 \342\230\272')" ] && ! printf '%s' "$got" | LC_ALL=C grep -q '[^ -~]'; then
  pass "warning prints a systemMessage in ASCII JSON that decodes to no control character"
else
  fail "warning prints a systemMessage in ASCII JSON that decodes to no control character" "exit $code: $got / $back"
fi
got=$(perl -e 'require "$ENV{LIBDIR}/hook.pl"; exit Hook::context("METHOD-ACTIVE vtest", "two\nlines")' 2>&1)
if [ "$got" = "$(printf 'METHOD-ACTIVE vtest\ntwo\\x0Alines')" ]; then pass "context prints each line clean"; else fail "context prints each line clean" "$got"; fi
got=$(perl -e 'require "$ENV{LIBDIR}/hook.pl"; require JSON::PP; exit Hook::json({hookSpecificOutput => {permissionDecision => "deny", permissionDecisionReason => "no\nway"}, n => 30, t => JSON::PP::true()})' 2>&1)
if [ "$got" = '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"no\\x0Away"},"n":30,"t":true}' ]; then
  pass "json prints a decision with its strings cleaned, numbers and true left as they are"
else
  fail "json prints a decision with its strings cleaned, numbers and true left as they are" "$got"
fi

# --- log.pl ---
root="$work/repo"
mkdir -p "$root"
h=$(printf 'x' | perl -MDigest::SHA=sha256_hex -e 'print sha256_hex(<STDIN>)')
export ROOT="$root" H="$h"
pl "append writes the time, rule, tool and hash, tab-separated, making the folders" 'Log::append($ENV{ROOT}, ".method/local/guard.log", undef, rule => "G4", tool => "mcp__github__merge_pull_request", hash => $ENV{H}); open my $f, "<", "$ENV{ROOT}/.method/local/guard.log"; my @l = <$f>; print(@l == 1 && $l[0] =~ /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\tG4\tmcp__github__merge_pull_request\t$ENV{H}\n\z/ ? "ok" : "@l")'
pl "lines reads the well-formed lines and counts the others" 'open my $f, ">>", "$ENV{ROOT}/.method/local/guard.log"; print $f "free text line\n"; close $f; my ($ok, $bad) = Log::lines($ENV{ROOT}, ".method/local/guard.log"); print(@$ok == 1 && $ok->[0][1] eq "G4" && $bad == 1 ? "ok" : scalar(@$ok) . " $bad")'
pl "an absent log has no lines" 'my ($ok, $bad) = Log::lines($ENV{ROOT}, "none.log"); print(!@$ok && !$bad ? "ok" : "bad")'
for pair in "a field that is not a log field|note|free text" "a tool name holding a space|tool|Bash rm -rf" "a lower-case rule ID|rule|g4" "a short hash|hash|abc" "a rule ID holding a tab|rule|G4	x"; do
  what=${pair%%|*}
  rest=${pair#*|}
  key=${rest%%|*}
  val=${rest#*|}
  got=$(KEY="$key" VAL="$val" perl -e 'require "$ENV{LIBDIR}/log.pl"; my %f = (rule => "G4", tool => "Bash", hash => $ENV{H}); $f{$ENV{KEY}} = $ENV{VAL}; eval { Log::append($ENV{ROOT}, "fixed.log", undef, %f); 1 } and print "WRITTEN"; print $@' 2>&1)
  case "$got" in
    "log: "*)
      if [ -e "$root/fixed.log" ]; then fail "the log refuses $what" "the log was written"; else pass "the log refuses $what"; fi
      ;;
    *) fail "the log refuses $what" "$got" ;;
  esac
done
pl "a missing field is refused" 'eval { Log::append($ENV{ROOT}, "fixed.log", undef, rule => "G4", tool => "Bash") }; print($@ =~ /hash is missing/ && !-e "$ENV{ROOT}/fixed.log" ? "ok" : "bad: $@")'
perl -e 'open my $f, ">", "$ENV{ROOT}/big.log"; printf $f "2026-01-01T00:00:00Z\tG0\tBash\t%064x\n", $_ for 1 .. 5000'
pl "a planted 5000-line log is trimmed to its cap of 1000, keeping the newest lines" 'Log::append($ENV{ROOT}, "big.log", undef, rule => "G9", tool => "Edit", hash => $ENV{H}); open my $f, "<", "$ENV{ROOT}/big.log"; my @l = <$f>; print(@l == 1000 && $l[0] =~ /\t0{60}0fa2\n/ && $l[-1] =~ /\tG9\tEdit\t/ ? "ok" : scalar(@l) . " first: $l[0] last: $l[-1]")'
pl "a cap of 3 keeps 3 lines" 'Log::append($ENV{ROOT}, "three.log", 3, rule => "G$_", tool => "Bash", hash => $ENV{H}) for 1 .. 5; my ($ok) = Log::lines($ENV{ROOT}, "three.log"); print(join(",", map { $_->[1] } @$ok) eq "G3,G4,G5" ? "ok" : "bad")'
pl "a cap that is not a whole number above 0 is refused" 'eval { Log::append($ENV{ROOT}, "x.log", 0, rule => "G1", tool => "Bash", hash => $ENV{H}) }; print($@ =~ /cap/ ? "ok" : "bad: $@")'
printf 'keep me\n' >"$work/outside.txt"
ln -s "$work/outside.txt" "$root/link.log"
pl "a log that is a link is refused and its target left alone" 'eval { Log::append($ENV{ROOT}, "link.log", undef, rule => "G1", tool => "Bash", hash => $ENV{H}) }; open my $f, "<", "$ENV{WORK}/outside.txt"; my $t = do { local $/; <$f> }; print($@ =~ /link\.log is a link or not a regular file/ && $t eq "keep me\n" ? "ok" : "bad: $@ $t")'
mkdir -p "$work/elsewhere"
ln -s "$work/elsewhere" "$root/.linked"
pl "a folder on the way that is a link is refused, and nothing is written through it" 'eval { Log::append($ENV{ROOT}, ".linked/guard.log", undef, rule => "G1", tool => "Bash", hash => $ENV{H}) }; opendir my $d, "$ENV{WORK}/elsewhere"; my @in = grep { !/^\.\.?$/ } readdir $d; print($@ =~ /is a link; the log is not written through it/ && !@in ? "ok" : "bad: $@ @in")'
pl "a name that climbs out with .. is refused" 'eval { Log::append($ENV{ROOT}, "../x.log", undef, rule => "G1", tool => "Bash", hash => $ENV{H}) }; print($@ =~ /relative path/ && !-e "$ENV{WORK}/x.log" ? "ok" : "bad: $@")'
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  perl -e 'require "$ENV{LIBDIR}/log.pl"; Log::append($ENV{ROOT}, "many.log", undef, rule => "G$ARGV[0]", tool => "Bash", hash => $ENV{H})' "$i" &
done
wait
pl "20 hooks logging at the same time lose no line and break none" 'my ($ok, $bad) = Log::lines($ENV{ROOT}, "many.log"); my %r = map { ($_->[1] => 1) } @$ok; print(@$ok == 20 && !$bad && keys(%r) == 20 ? "ok" : scalar(@$ok) . " lines, $bad bad")'
# A full log is trimmed on every line added, so hooks that log at the same
# time race between one's trim (read, write, rename) and another's line;
# the lock must keep every new line. Done 3 times, as one race can miss.
lost=""
for round in 1 2 3; do
  perl -e 'open my $f, ">", "$ENV{ROOT}/full.log"; printf $f "2026-01-01T00:00:00Z\tG0\tBash\t%064x\n", $_ for 1 .. 1000'
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    perl -e 'require "$ENV{LIBDIR}/log.pl"; Log::append($ENV{ROOT}, "full.log", undef, rule => "G$ARGV[0]", tool => "Bash", hash => $ENV{H})' "$i" &
  done
  wait
  r=$(perl -e 'require "$ENV{LIBDIR}/log.pl"; my ($ok, $bad) = Log::lines($ENV{ROOT}, "full.log"); my %r = map { ($_->[1] => 1) } grep { $_->[1] ne "G0" } @$ok; print scalar(@$ok), " lines, ", scalar(keys %r), " new"')
  [ "$r" = "1000 lines, 30 new" ] || lost="$lost round $round: $r;"
done
if [ -z "$lost" ]; then pass "30 hooks logging at the same time into a full log keep every new line and the cap"; else fail "30 hooks logging at the same time into a full log keep every new line and the cap" "$lost"; fi

# --- Secrets::scan_text ---
got=$(printf 'input that must not be read' | perl -e 'require "$ENV{LIBDIR}/secrets.pl"; my $rest = <STDIN>; print "after require: $rest @ARGV"' a b 2>&1)
if [ "$got" = "after require: input that must not be read a b" ]; then pass "requiring secrets.pl runs nothing and leaves its arguments alone"; else fail "requiring secrets.pl runs nothing and leaves its arguments alone" "$got"; fi
pl "scan_text finds a planted key and gives it only masked" 'my $k = "sk-ant-" . ("a1B2" x 10); my @f = Secrets::scan_text("fix the build\n\nkey: $k\n"); my $all = join "|", map { @$_ } @f; print(@f == 1 && $f[0][0] eq "Anthropic API key" && $f[0][1] eq "sk-a...(47 chars)" && index($all, $k) < 0 ? "ok" : $all)'
pl "scan_text finds personal data and leaves example addresses" 'my @f = Secrets::scan_text("mail a.person\@gmail.com or ok\@example.com"); print(@f == 1 && $f[0][0] =~ /email/ && $f[0][1] !~ /gmail/ ? "ok" : join "|", map { @$_ } @f)'
pl "scan_text finds a key right after an escape written as text" 'my $k = "AKIA" . ("Q" x 16); my @f = Secrets::scan_text(q{print("\x1b[1m} . $k); print(@f == 1 && $f[0][0] eq "AWS access key" ? "ok" : join "|", map { @$_ } @f)'
pl "scan_text reads characters as well as bytes, and gives each find once" 'my $k = "ghp_" . ("Z9y8" x 10); my @f = Secrets::scan_text("caf\x{e9} $k\n$k"); print(@f == 1 && $f[0][0] eq "GitHub token" ? "ok" : join "|", map { @$_ } @f)'
pl "scan_text reads characters as their UTF-8 bytes, as scan_bytes and the file scan do (a masked length counts bytes)" 'my $c = "password = \"p\x{e4}ssw\x{f6}rd12\""; my $b = $c; utf8::encode($b); my @f = map { join "=", @$_ } Secrets::scan_text($c); my @g = map { join "=", @$_ } Secrets::scan_bytes($b); print("@f" eq "@g" && @f == 1 ? "ok" : "chars: @f bytes: @g")'
pl "scan_bytes refuses characters, so a caller cannot mix the two up" 'eval { Secrets::scan_bytes("key \x{263a}") }; print($@ =~ /given characters/ ? "ok" : "bad: $@")'
pl "scan_text finds nothing in clean text" 'my @f = Secrets::scan_text("Step 5.1: shared helpers\n\nReview-Verdict: approve\n"); print(@f ? join("|", map { @$_ } @f) : "ok")'

drop_sandbox "$work" || true
echo "tests: hook helpers: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
