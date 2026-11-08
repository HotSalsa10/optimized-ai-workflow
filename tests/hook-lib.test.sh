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
pl "Json::encode writes every number Json::decode gives (fractions, exponents, long integers)" 'my ($d) = Json::decode(q({"a":1.5,"b":1e3,"c":123456789012345678901234,"d":-7})); my $e = Json::encode($d); print($e eq q({"a":1.5,"b":1000,"c":123456789012345678901234,"d":-7}) ? "ok" : $e)'
pl "Json::decode's error after non-ASCII text names the place in the text as given, not in its escaped copy" 'require JSON::PP; my $in = qq({"a":"\xc3\xa9\xc3\xa9", x}); eval { JSON::PP->new->utf8->decode($in) }; my ($want) = $@ =~ /(at character offset \d+)/; my (undef, $e) = Json::decode($in); print(defined $e && defined $want && index($e, $want) >= 0 ? "ok" : "got: " . ($e // "no error") . "; JSON::PP: " . ($want // "?"))'
pl "Json::decode with plain gives perl's own numbers, not objects" 'my ($d) = Json::decode(q({"a":1.5,"b":30}), "plain"); print(!ref $d->{a} && !ref $d->{b} && $d->{a} == 1.5 && Json::encode($d) eq q({"a":1.5,"b":30}) ? "ok" : Json::encode($d))'
pl "Json::decode reads non-ASCII text as get does, also around backslashes" 'my @c = ([qq({"a":"caf\xc3\xa9 \xf0\x9f\x98\x80","b":"\\\\\xc3\xa9"}), "caf\x{e9} \x{1F600}|\\\x{e9}"], [qq({"a":"\\\xc3\xa9"}), "ERR illegal backslash escape"], [qq({"a":1} \xc3\xa9), "ERR garbage after JSON"], [qq(\xc3\xa9), "ERR malformed JSON string"]); my $bad = ""; for (@c) { my ($in, $want) = @$_; my ($d, $e) = Json::decode($in); my $got = defined $e ? "ERR $e" : "$d->{a}|$d->{b}"; (my $w = $want) =~ s{\AERR }{}; $bad .= " [$got]" unless $want =~ /\AERR / ? $got =~ /\AERR .*\Q$w\E/ : $got eq $want } print($bad eq "" ? "ok" : $bad)'
pl "Json::decode reads 2 MB of non-ASCII text in time that grows with its length (JSON::PP alone takes the square of it): within 6 times the same text sent as escapes" 'use Time::HiRes qw(time); alarm 120; my $s = "\x{4e2d}" x 700000; my $j = qq({"c":"$s"}); utf8::encode($j); my $base = q({"c":") . (q(中) x 700000) . q("}); my $t0 = time; Json::decode($base); my $b = time - $t0; my $t = time; my ($d, $e) = Json::decode($j); my $took = time - $t; print(!defined $e && length($d->{c}) == 700000 && $took <= 6 * $b + 0.5 ? "ok" : sprintf("took %.1f s against %.1f s, %s", $took, $b, $e // "read"))'
pl "an escaped backslash before uD800 keeps the fast reading (it is not an escaped surrogate)" 'use Time::HiRes qw(time); alarm 120; my $s = "\x{4e2d}" x 700000; my $j = qq({"c":"\\\\uD800 $s"}); utf8::encode($j); my $base = q({"c":"\\uD800 ) . (q(中) x 700000) . q("}); my $t0 = time; Json::decode($base); my $b = time - $t0; my $t = time; my ($d, $e) = Json::decode($j); my $took = time - $t; print(!defined $e && $d->{c} eq "\\uD800 $s" && $took <= 6 * $b + 0.5 ? "ok" : sprintf("took %.1f s against %.1f s, %s", $took, $b, $e // "read"))'

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

got=$(printf '{"t":1.5,"n":2}' | PERL_UNICODE=S perl -e 'require "$ENV{LIBDIR}/hook.pl"; my ($d, $e) = Hook::read_input(); print defined $e ? $e : (ref $d->{t} ? "object" : "plain") . " $d->{t} $d->{n}"' 2>&1)
if [ "$got" = "plain 1.5 2" ]; then pass "read_input gives plain numbers, and reads bytes whatever PERL_UNICODE asks"; else fail "read_input gives plain numbers, and reads bytes whatever PERL_UNICODE asks" "$got"; fi

# --- hook.pl: output ---
# the words a Stop-type hook's stderr must not hold, as Claude Code 2.1.319 reads them
pl "clean breaks up the words that make a block read as a missing file, wherever they stand" 'my $bad = ""; for my $t ("errNo such file", "x\nNo such file or directory", "x_No such directory", "No\tsuch\tfile", "cannot do it: can\x27t open x", "CAN\x27T OPEN") { my $s = Hook::clean($t); $bad .= " [$s]" if $s =~ /no such file|can\x27t open/i } print($bad eq "" ? "ok" : $bad)'
pl "clean gives one line with every control and invisible character escaped" 'my $s = Hook::clean("a\nb\rc\x1b[31md\x07e\x{2028}f\x{202E}g\x{200B}h\x00i"); print($s eq q(a\x0Ab\x0Dc\x1B[31md\x07e\u{2028}f\u{202E}g\u{200B}h\x00i) ? "ok" : $s)'
pl "clean breaks up a missing-file message" 'my $s = Hook::clean("ls: No such file or directory; no such  directory"); print($s !~ /no\s+such\s+(?:file|directory)/i ? "ok" : $s)'
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

pl "json keeps numbers as numbers, also in exponent form, and a number written as text as text" 'my $o; { local *STDOUT; open STDOUT, ">", \$o; Hook::json({a => 1e20, b => 30, c => "30", d => 0.5, e => -2}) } print($o eq qq({"a":1e+20,"b":30,"c":"30","d":0.5,"e":-2}\n) ? "ok" : $o)'
got=$(PERL_JSON_PP_USE_B=1 perl -e 'require "$ENV{LIBDIR}/hook.pl"; exit Hook::json({n => 30, f => 2.5})' 2>&1)
if [ "$got" = '{"f":2.5,"n":30}' ]; then pass "json keeps numbers as numbers where JSON::PP reads perl's flags only (as perl 5.14 to 5.26 ship it)"; else fail "json keeps numbers as numbers where JSON::PP reads perl's flags only" "$got"; fi
pl "json cleans keys too" 'my $o; { local *STDOUT; open STDOUT, ">", \$o; Hook::json({"a\nb" => 1}) } print($o eq qq({"a\\\\x0Ab":1}\n) ? "ok" : $o)'
got=$(perl -e 'require "$ENV{LIBDIR}/hook.pl"; Hook::warning("one"); Hook::context("two")' 2>&1)
code=$?
if [ "$code" -ne 0 ] && printf '%s\n' "$got" | grep -q -x '{"systemMessage":"one"}' && printf '%s\n' "$got" | grep -q "answers on stdout once per run"; then pass "a second answer on stdout dies instead of printing two (exit $code)"; else fail "a second answer on stdout dies instead of printing two" "exit $code: $got"; fi
got=$(perl -e 'require "$ENV{LIBDIR}/hook.pl"; exit Hook::warning("a", "b")' 2>&1)
if [ "$got" = '{"systemMessage":"a; b"}' ]; then pass "warning joins several texts into one systemMessage"; else fail "warning joins several texts into one systemMessage" "$got"; fi
got=$(perl -e 'require "$ENV{LIBDIR}/hook.pl"; exit Hook::context("  {\"decision\":\"block\"}", "{second}")' 2>&1)
if [ "$got" = "$(printf '  \\x7B"decision":"block"}\n{second}')" ]; then pass "context writes a first line that opens with { so it cannot be read as the hook's JSON"; else fail "context writes a first line that opens with { so it cannot be read as the hook's JSON" "$got"; fi
for how in "die after a failed kill (errno 3)|\$! = 3; die \"crash\\n\"" "die after a child that exited 3|system(\"sh\", \"-c\", \"exit 3\"); \$! = 0; die \"crash\\n\"" "exit 3 without block|exit 3" "exit 259 without block (3 to the shell)|exit 259"; do
  what=${how%%|*}
  code_text=${how#*|}
  perl -e "require \"\$ENV{LIBDIR}/hook.pl\"; $code_text" >/dev/null 2>&1
  code=$?
  if [ "$code" -eq 70 ]; then pass "a crash that would exit 3 ($what) exits 70, never the block code"; else fail "a crash that would exit 3 ($what) exits 70" "exit $code"; fi
done
got=$(perl -e 'require "$ENV{LIBDIR}/hook.pl"; Hook::block("refused:", "push your branch"); exit 0' 2>&1)
code=$?
if [ "$code" -eq 3 ] && [ "$got" = "refused: push your branch" ]; then pass "block joins its texts into one line, and a hook that refused but exits 0 still refuses (3)"; else fail "block joins its texts, and an exit 0 after a block is 3" "exit $code: $got"; fi
perl -e 'require "$ENV{LIBDIR}/hook.pl"; Hook::block("refused"); exit 256' >/dev/null 2>&1
code=$?
if [ "$code" -eq 3 ]; then pass "a hook that refused but exits 256 (0 to the shell) still refuses (3)"; else fail "a hook that refused but exits 256 still refuses" "exit $code"; fi
mkdir -p "$work/noesc"
cp "$lib/hook.pl" "$lib/json.pl" "$work/noesc/"
got=$(perl -e 'eval { require "$ENV{WORK}/noesc/hook.pl"; 1 } or print STDOUT "load failed\n"; exit 0' 2>&1)
code=$?
if [ "$code" -eq 0 ] && [ "$got" = "load failed" ]; then pass "when hook.pl cannot load a helper, its END block adds no warning and leaves the exit code alone"; else fail "when hook.pl cannot load a helper, its END block adds no warning" "exit $code: $got"; fi
for first in "" "	" "$(printf '\343\200\200')" " "; do
  got=$(FIRST="$first" perl -e 'require "$ENV{LIBDIR}/hook.pl"; my $f = $ENV{FIRST}; utf8::decode($f); exit Hook::context($f, "{\"continue\":false}")' 2>&1)
  # Claude Code trims the output (JavaScript's trim) and reads it as JSON when it opens with {
  trimmed=$(printf '%s' "$got" | perl -CS -0777 -ne 's/\A[\s\x{3000}\x{a0}\x{feff}]+//; print substr($_, 0, 1)')
  if [ "$trimmed" != "{" ] && printf '%s' "$got" | grep -q 'x7B"continue"'; then pass "context escapes the { a blank first line ($(printf '%s' "$first" | od -An -c | tr -s ' ')) would leave at the start"; else fail "context escapes the { after a blank first line" "$got"; fi
done
perl -e 'require "$ENV{LIBDIR}/hook.pl"; exit Hook::block("refused")' >/dev/null 2>&1
code=$?
if [ "$code" -eq 3 ]; then pass "a block still exits 3"; else fail "a block still exits 3" "exit $code"; fi

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
export OUTSIDE="$work/outside.txt"
# kept PATH: the outside file still holds only "keep me"
kept='open my $f, "<", $ENV{OUTSIDE}; my $t = do { local $/; <$f> }; $t eq "keep me\n"'
# Git Bash can make a copy where a link was asked for; then the link cases
# would test a plain file, so they are skipped (not a pass), as in the other
# test files
can_link=0
if ln -s "$work/outside.txt" "$work/link-probe" 2>/dev/null && [ -L "$work/link-probe" ]; then can_link=1; fi
if [ "$can_link" -eq 1 ]; then
  ln -s "$work/outside.txt" "$root/link.log"
  pl "a log that is a link is refused and its target left alone" "eval { Log::append(\$ENV{ROOT}, \"link.log\", undef, rule => \"G1\", tool => \"Bash\", hash => \$ENV{H}) }; print(\$@ =~ /link\\.log is a link or not a regular file/ && do { $kept } ? \"ok\" : \"bad: \$@\")"
  mkdir -p "$work/elsewhere"
  ln -s "$work/elsewhere" "$root/.linked"
  pl "a folder on the way that is a link is refused, and nothing is written through it" 'eval { Log::append($ENV{ROOT}, ".linked/guard.log", undef, rule => "G1", tool => "Bash", hash => $ENV{H}) }; opendir my $d, "$ENV{WORK}/elsewhere"; my @in = grep { !/^\.\.?$/ } readdir $d; print($@ =~ /is a link; the log is not used through it/ && !@in ? "ok" : "bad: $@ @in")'
  mkdir -p "$root/lk"
  ln -s "$work/outside.txt" "$root/lk/guard.log.lock"
  pl "a lock file that is a link is refused and its target left alone" "eval { Log::append(\$ENV{ROOT}, \"lk/guard.log\", undef, rule => \"G1\", tool => \"Bash\", hash => \$ENV{H}) }; print(\$@ =~ /guard\\.log\\.lock is a link or not a regular file/ && do { $kept } && !-e \"\$ENV{ROOT}/lk/guard.log\" ? \"ok\" : \"bad: \$@\")"
  ln -s "$root" "$work/root-link"
  pl "a root folder that is a link is refused" 'eval { Log::append("$ENV{WORK}/root-link", "r.log", undef, rule => "G1", tool => "Bash", hash => $ENV{H}) }; print($@ =~ /missing or a link/ ? "ok" : "bad: $@")'
else
  skip "the link cases of the log: links cannot be made here"
fi
if ln "$work/outside.txt" "$root/hard.log" 2>/dev/null; then
  pl "a log with a second name (a hard link) is refused, and the other file left alone" "eval { Log::append(\$ENV{ROOT}, \"hard.log\", undef, rule => \"G1\", tool => \"Bash\", hash => \$ENV{H}) }; print(\$@ =~ /another name \\(a hard link\\)/ && do { $kept } ? \"ok\" : \"bad: \$@\")"
  perl -e 'open my $f, ">", "$ENV{ROOT}/trim.log"; printf $f "2026-01-01T00:00:00Z\tG0\tBash\t%064x\n", $_ for 1 .. 1000'
  perl -e 'link $ENV{OUTSIDE}, "$ENV{ROOT}/trim.log.tmp.$_" for $$ + 1 .. $$ + 600'
  pl "the trim never writes through a hard link planted at its temporary file's name" "Log::append(\$ENV{ROOT}, \"trim.log\", undef, rule => \"G9\", tool => \"Bash\", hash => \$ENV{H}); my (\$ok) = Log::lines(\$ENV{ROOT}, \"trim.log\"); print(do { $kept } && @\$ok == 1000 && \$ok->[-1][1] eq \"G9\" ? \"ok\" : \"bad: \" . scalar(@\$ok))"
else
  skip "the hard-link cases of the log: hard links cannot be made here"
fi
pl "a name that climbs out with .. is refused" 'eval { Log::append($ENV{ROOT}, "../x.log", undef, rule => "G1", tool => "Bash", hash => $ENV{H}) }; print($@ =~ /relative path/ && !-e "$ENV{WORK}/x.log" ? "ok" : "bad: $@")'
pl "a name with a backslash or a drive letter is refused" 'my $n = 0; for my $name ("a\\\\b.log", "C:x.log", "a/./b.log", "a//b.log") { eval { Log::append($ENV{ROOT}, $name, undef, rule => "G1", tool => "Bash", hash => $ENV{H}) }; $n++ if $@ =~ /relative path/ } print($n == 4 ? "ok" : "only $n of 4 refused")'
# (a file system without sparse files, as Git Bash over NTFS, would write
# the 3 GB in full: a 64 MB probe decides)
perl -e 'open my $f, ">", "$ENV{ROOT}/probe.log" or die; seek $f, 64 * 1024 * 1024, 0; print $f "x\n"'
if perl -e 'my @s = stat "$ENV{ROOT}/probe.log"; exit(($s[12] // 1e9) * 512 < 8 * 1024 * 1024 ? 0 : 1)'; then
  rm -f "$root/probe.log"
  perl -e 'open my $f, ">", "$ENV{ROOT}/huge.log" or die; seek $f, 3 * 1024 * 1024 * 1024, 0; printf $f "2026-01-01T00:00:00Z\tG0\tBash\t%064x\n", $_ for 1 .. 1500'
  pl "a huge, mostly empty log is trimmed from its end, without reading it all" 'alarm 30; my $t = time; Log::append($ENV{ROOT}, "huge.log", undef, rule => "G9", tool => "Bash", hash => $ENV{H}); my ($ok, $bad) = Log::lines($ENV{ROOT}, "huge.log"); print(@$ok == 1000 && $ok->[-1][1] eq "G9" && !$bad && -s "$ENV{ROOT}/huge.log" < 200000 && time - $t < 20 ? "ok" : scalar(@$ok) . " lines, $bad bad, " . (-s "$ENV{ROOT}/huge.log") . " bytes")'
else
  rm -f "$root/probe.log"
  skip "the huge sparse log: this file system does not make sparse files"
fi
pl "a half line left by a write that failed stays a line of its own, and the next line is whole" 'Log::append($ENV{ROOT}, "half.log", undef, rule => "G1", tool => "Bash", hash => $ENV{H}); open my $f, ">>", "$ENV{ROOT}/half.log" or die; print $f "2026-11-08T00:00:00Z\tG2\tBa"; close $f; Log::append($ENV{ROOT}, "half.log", undef, rule => "G3", tool => "Bash", hash => $ENV{H}); my ($ok, $bad) = Log::lines($ENV{ROOT}, "half.log"); print(@$ok == 2 && $bad == 1 && $ok->[-1][1] eq "G3" ? "ok" : scalar(@$ok) . " whole lines, $bad bad")'
pl "the time is UTC whatever the time zone" 'local $ENV{TZ} = "Asia/Riyadh"; my $st = sub { my @t = gmtime $_[0]; sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ", $t[5] + 1900, $t[4] + 1, @t[3, 2, 1, 0] }; my $a = $st->(time); Log::append($ENV{ROOT}, "tz.log", undef, rule => "G1", tool => "Bash", hash => $ENV{H}); my $b = $st->(time); my ($ok) = Log::lines($ENV{ROOT}, "tz.log"); my $t = $ok->[0][0]; print($t ge $a && $t le $b ? "ok" : "$t not between $a and $b")'
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
got=$(GIT_INDEX_FILE=planted perl -e 'my %e = %ENV; require "$ENV{LIBDIR}/secrets.pl"; my @d = grep { !exists $ENV{$_} || $ENV{$_} ne $e{$_} } keys %e; my @n = grep { !exists $e{$_} } keys %ENV; print(!@d && !@n ? "ok" : "changed: @d @n")' 2>&1)
if [ "$got" = "ok" ]; then pass "loading secrets.pl leaves the environment alone"; else fail "loading secrets.pl leaves the environment alone" "$got"; fi
pl "scan_bytes reads UTF-16 text and binary content as the file scan does" 'my $k = "ghp_" . ("Z9y8" x 10); my $le = "\xff\xfe" . join("", map { "$_\0" } split //, "token $k\n"); my $nobom = join("", map { "$_\0" } split //, "x token $k\n"); my $bin = "\0\0\x01bin " . "sk-ant-" . ("a1B2" x 10) . "\0"; my @a = Secrets::scan_bytes($le); my @b = Secrets::scan_bytes($nobom); my @c = Secrets::scan_bytes($bin); print(@a == 1 && $a[0][0] eq "GitHub token" && @b == 1 && @c == 1 && $c[0][0] eq "Anthropic API key" ? "ok" : join "|", map { @$_ } @a, @b, @c)'
got=$(perl -e 'require "$ENV{LIBDIR}/../lib/json.pl"; require "$ENV{LIBDIR}/../lib/esc.pl"; require "$ENV{LIBDIR}/secrets.pl"; require "$ENV{LIBDIR}/hook.pl"; print "loaded"' 2>&1)
if [ "$got" = "loaded" ]; then pass "the helpers load once, with no warning, when two paths spell their folder differently"; else fail "the helpers load once, with no warning, when two paths spell their folder differently" "$got"; fi
pl "scan_text finds nothing in clean text" 'my @f = Secrets::scan_text("Step 5.1: shared helpers\n\nReview-Verdict: approve\n"); print(@f ? join("|", map { @$_ } @f) : "ok")'
pl "scan_bytes reads ASCII text after a UTF-16 part as text too" 'my $k = "ghp_" . ("Z9y8" x 10); my $b = "\xff\xfe" . join("", map { "$_\0" } split //, "note\n") . "\n\nplain $k and a.person\@gmail.com\n"; my %k = map { ($_->[0] => 1) } Secrets::scan_bytes($b); print($k{"GitHub token"} && grep({ /email/ } keys %k) ? "ok" : join "|", keys %k)'

# --- review round 2 of 5.1 ---
# A lone escaped high surrogate before a character above U+FFFF is not JSON
# (JSON::PP on the text itself says so); the fast reading must not make it
# one. Client-shaped: JSON.stringify writes a lone surrogate as \udXXX.
for t in "$(printf '{"a":"x\\ud83d\360\237\230\200y"}')" "$(printf '{"a":"\\uD800 x \360\220\200\200"}')"; do
  base=$(printf '%s' "$t" | perl -MJSON::PP -e 'local $/; my $r = eval { JSON::PP->new->utf8->allow_nonref->decode(<STDIN>) }; print defined $r ? "read" : ($@ =~ /(missing low surrogate)/ ? $1 : "other")')
  got=$(printf '%s' "$t" | perl "$lib/json.pl" get a 2>&1)
  code=$?
  lib_got=$(printf '%s' "$t" | perl -e 'require "$ENV{LIBDIR}/json.pl"; local $/; my ($d, $e) = Json::decode(<STDIN>, "plain"); print defined $e ? $e : "read"')
  case "$base|$code|$got|$lib_got" in
    "missing low surrogate|2|json: not valid JSON: missing low surrogate"*"|not valid JSON: missing low surrogate"*) pass "a lone escaped high surrogate before a character above U+FFFF is refused, as JSON::PP refuses the text itself" ;;
    *) fail "a lone escaped high surrogate before a character above U+FFFF is refused" "base $base; get exit $code: $got; library: $lib_got" ;;
  esac
done
pl "escaped pairs next to characters above U+FFFF still read right" 'my $t = "{\"a\":\"\\ud83d\\ude00 \x{1F600} \x{4e2d}\"}"; utf8::encode($t); my ($d) = Json::decode($t, "plain"); print($d->{a} eq "\x{1F600} \x{1F600} \x{4e2d}" ? "ok" : "bad")'
pl "plain reading of 2 MB of non-ASCII text that is not JSON takes about as long as reading it as escapes, and its reason counts the text's own characters" 'use Time::HiRes qw(time); alarm 120; my $t = "{\"a\":\"" . ("\x{4e2d}" x 700000) . "\"} x"; utf8::encode($t); my $base = q({"a":") . (q(中) x 700000) . q("} x); my $s0 = time; Json::decode($base, "plain"); my $b = time - $s0; my $s = time; my ($d, $e) = Json::decode($t, "plain"); my $took = time - $s; print(defined $e && $e =~ /garbage after JSON object, at character offset 700010\b/ && $took <= 6 * $b + 0.5 ? "ok" : sprintf("%s in %.1f s against %.1f s", $e // "read", $took, $b))'
pl "the plain reason counts a character above U+FFFF (two escapes in the fast copy) as one" 'my $t = "{\"a\":\"\x{1F600}\x{1F600}\" x \"\x{4e2d}\x{4e2d}\"}"; utf8::encode($t); my ($d, $e) = Json::decode($t, "plain"); print(defined $e && $e =~ /character offset 10\b/ ? "ok" : $e // "read")'
pl "encode dies on a number JSON cannot hold (plain 1e400, its minus, not a number)" 'my ($d) = Json::decode("[1e400,-1e400]", "plain"); my $n = 0; for my $v (@$d, $d->[0] - $d->[0]) { eval { Json::encode({ x => $v }) }; $n++ if $@ =~ /not finite/ } print($n == 3 ? "ok" : "$n of 3 refused")'
pl "encode dies on data nested more than 512 deep, and on a structure that holds itself, instead of running on" 'alarm 10; my $deep = 1; $deep = [$deep] for 1 .. 600; my $self = {}; $self->{me} = $self; my $n = 0; for my $v ($deep, $self) { eval { Json::encode($v) }; $n++ if $@ =~ /nested too deep/ } my $ok = eval { Json::encode([[[[1]]]]) }; print($n == 2 && $ok eq "[[[[1]]]]" ? "ok" : "$n of 2 refused")'
pl "encode dies at once on an integer of more than 10000 digits, which decode gives" 'alarm 10; my ($d) = Json::decode("[" . ("9" x 10001) . "]"); eval { Json::encode($d) }; print($@ =~ /exponent beyond 10000/ ? "ok" : "not refused: $@")'
pl "encode dies at once on an exact number with an exponent beyond 10000, as get refuses it" 'alarm 10; my ($d) = Json::decode("[1e1000000000,1e-1000000000]"); my $n = 0; for my $v (@$d) { eval { Json::encode([$v]) }; $n++ if $@ =~ /exponent beyond 10000/ } print($n == 2 ? "ok" : "$n of 2 refused")'
pl "a hook that answers with a number JSON cannot hold crashes; it never prints a broken answer" 'my ($d) = Json::decode("{\"t\":1e400}", "plain"); my $r = eval { Hook::json({ t => $d->{t} }); 1 }; print(!$r && $@ =~ /not finite/ ? "ok" : "printed")'
pl "lines refuses a name that climbs out, as append does" 'eval { Log::lines($ENV{ROOT}, "../x.log") }; print($@ =~ /relative path/ ? "ok" : "bad: $@")'
pl "lines writes nothing: a missing folder stays missing" 'my ($ok, $bad) = Log::lines($ENV{ROOT}, "nofolder/deeper/x.log"); print(!-e "$ENV{ROOT}/nofolder" && !@$ok && !$bad ? "ok" : "bad")'
perl -e 'open my $f, ">", "$ENV{ROOT}/dirtmp.log"; printf $f "2026-01-01T00:00:00Z\tG0\tBash\t%064x\n", $_ for 1 .. 1000'
pl "a folder planted at the trim's temporary name does not stop the trim" 'mkdir "$ENV{ROOT}/dirtmp.log.tmp.$$" or die; Log::append($ENV{ROOT}, "dirtmp.log", undef, rule => "G9", tool => "Bash", hash => $ENV{H}); open my $f, "<", "$ENV{ROOT}/dirtmp.log"; my @l = <$f>; print(@l == 1000 && $l[-1] =~ /\tG9\t/ ? "ok" : scalar(@l) . " lines")'
perl -e 'open my $f, ">", "$ENV{ROOT}/cut.log"; print $f "2026-01-01T00:00:00Z\tG7\tBash\t" . ("f" x 64) . ("x" x 600) . "\n"; printf $f "2026-01-01T00:00:00Z\tG0\tBash\t%064x\n", $_ for 1 .. 2'
pl "a line cut by the start of the read window is dropped, not read as a line" 'local $Log::LINE_MAX = 100; my ($l, $more) = Log::tail("$ENV{ROOT}/cut.log", 3); print(@$l == 2 && !grep({ /G7|x{10}/ } @$l) ? "ok" : join "|", @$l)'
if [ "$can_link" -eq 1 ]; then
  ln -s "$work/elsewhere" "$work/root-link2"
  pl "a root folder that is a link is refused also when spelled with a trailing / or /." 'my $n = 0; for my $r ("$ENV{WORK}/root-link2/", "$ENV{WORK}/root-link2/.", "$ENV{WORK}/root-link2//./") { eval { Log::append($r, "r.log", undef, rule => "G1", tool => "Bash", hash => $ENV{H}) }; $n++ if $@ =~ /missing or a link/ } opendir my $d, "$ENV{WORK}/elsewhere"; my @in = grep { !/\A\.\.?\z/ } readdir $d; print($n == 3 && !@in ? "ok" : "$n refused; written: @in")'
  mkdir -p "$root/real/sub"
  ln -s "$root/real" "$root/rlink"
  pl "lines refuses a folder on the way that is a link" 'eval { Log::lines($ENV{ROOT}, "rlink/sub/x.log") }; print($@ =~ /is a link/ ? "ok" : "bad: $@")'
fi
# A reader takes no lock, so it may open the log just as a trim renames a
# new log over it; it must open the new one, not die with a false alarm.
perl -e 'open my $f, ">", "$ENV{ROOT}/busy.log"; printf $f "2026-01-01T00:00:00Z\tG0\tBash\t%064x\n", $_ for 1 .. 1000'
for i in 1 2 3 4 5 6 7 8; do
  perl -e 'require "$ENV{LIBDIR}/log.pl"; Log::append($ENV{ROOT}, "busy.log", undef, rule => "G$ARGV[0]", tool => "Bash", hash => $ENV{H}) for 1 .. 40' "$i" &
done
for i in 1 2 3 4; do
  perl -e 'require "$ENV{LIBDIR}/log.pl"; my $died = 0; for (1 .. 150) { eval { Log::lines($ENV{ROOT}, "busy.log"); 1 } or do { $died++; print STDERR $@ } } open my $o, ">", "$ENV{WORK}/reader.$ARGV[0]"; print $o "$died\n"' "$i" 2>"$work/reader-err.$i" &
done
wait
died=$(cat "$work"/reader.[1-4] 2>/dev/null | perl -ne '$n += $_; END { print $n + 0 }')
if [ "$died" = "0" ] && [ "$(cat "$work"/reader.[1-4] | wc -l | tr -d ' ')" = "4" ]; then pass "readers of a log that hooks are trimming never die with a false alarm"; else fail "readers of a log that hooks are trimming never die with a false alarm" "$died died: $(head -c 300 "$work/reader-err.1")"; fi

drop_sandbox "$work" || true
echo "tests: hook helpers: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
