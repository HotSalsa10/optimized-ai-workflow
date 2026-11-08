#!/usr/bin/env bash
# Tests for the guard (steps 5.5 to 5.10): .claude/hooks/method/guard.sh with
# lib/guard.pl and its command reader lib/shell.pl, run directly with a
# hook's JSON input. The harness shows the real client running it.
# shellcheck disable=SC2016 # single-quoted commands and perl code are meant literally
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: guard"
root=$(repo_root)
lib="$root/method/scripts/method/lib"
guard="$root/method/.claude/hooks/method/guard.sh"
work=$(new_sandbox_dir) || abort_sandbox
proj="$work/proj"
mkdir -p "$proj"
export LIBDIR="$lib"

# --- the command reader ---
# reads NAME COMMAND WANT: Shell::commands on COMMAND, written one command a
# line as "words|via|unread" (each list joined by spaces), must be WANT
reads() {
  got=$(CMD="$2" perl -e 'require "$ENV{LIBDIR}/shell.pl"; for my $c (Shell::commands($ENV{CMD})) { print join(" ", @{ $c->{words} }), "|", join(" ", @{ $c->{via} }), "|", join("; ", @{ $c->{unread} }), "\n" }' 2>&1)
  if [ "$got" = "$3" ]; then pass "reader: $1"; else fail "reader: $1" "got:
$got
wanted:
$3"; fi
}
reads "simple commands split at ; && || | and newlines" 'cd /x && git status; echo hi | wc -l
ls || true' 'cd /x||
git status||
echo hi||
wc -l||
ls||
true||'
reads "quotes are removed, and operators inside quotes stay words" 'git commit -m "msg; with && ops" '"'"'and | more'"'" 'git commit -m msg; with && ops and | more||'
reads "assignments before a command are not words" 'FOO=1 BAR="x y" git push' 'git push||'
# (the lines that start with a carrier are built here, on one line, so the
# portability lint does not read them as commands)
carried=$(printf '%s\n' 'nohup timeout 5 git fetch||' 'timeout 5 git fetch|nohup|' 'git fetch|nohup timeout|')
reads "bash -c, sh -c, eval, env, xargs, find -exec, nohup and timeout are followed into the command they run" 'bash -c "git push -f"; eval "git status"; env -i PATH=/bin git log; xargs -0 rm -f < list; find . -exec git add {} \;; nohup timeout 5 git fetch' 'bash -c git push -f||
git push -f|bash -c|
eval git status||
git status|eval|
env -i PATH=/bin git log||
git log|env|
xargs -0 rm -f||
rm -f|xargs|
find . -exec git add {} ;||
git add {}|find -exec|
'"$carried"
reads "a here-document's lines are its text, not commands" 'git commit -F - <<EOF
git push origin main
EOF
git log' 'git commit -F -||
git log||'
reads "if, for and while are read through to their commands" 'if git diff --quiet; then echo same; fi; for f in a b; do git add "$f"; done' 'git diff --quiet||
echo same||
git add $f||'
reads "command substitution and backticks cannot be read" 'echo $(git rev-parse HEAD); echo `date`' 'echo $(git rev-parse HEAD)||command substitution or backticks
echo `date`||command substitution or backticks'
reads "a variable as the command word cannot be read" '$CMD push' '$CMD push||a variable as the command word'
reads "a pipe or here-string into a shell or an interpreter cannot be read" 'printf x | sh; python3 <<< "print(1)"' 'printf x||
sh||a pipe, here-document or here-string into sh
python3||a pipe, here-document or here-string into python3'
reads "an interpreter's inline program cannot be read" 'perl -e 1; node -e 1; awk "{print}" f' 'perl -e 1||an inline program for perl
node -e 1||an inline program for node
awk {print} f||an inline program for awk'
reads "eval of an expansion, bash -c with an expansion and source cannot be read" 'eval "$X"; bash -c "$Y"; source f' 'eval $X||eval of anything but a literal
bash -c $Y||bash -c with an expansion
source f||source or .'
reads "a carriage return is a space, so lines ending in CRLF read as lines" "$(printf 'git status\r\ngit log -1\r')" 'git status||
git log -1||'
reads "ANSI-C quoting is decoded, so its escapes cannot hide a word" '$'"'"'\x67it'"'"' push origin main' 'git push origin main||'
reads "a glob in a write target cannot be read; a variable there is G6's to judge" 'echo x > *.txt; echo y > "$F"' 'echo x||a glob or a brace in a write target
echo y||'
reads "an open quote is said, not guessed" "echo 'open" '||the reader could not split it (an open single quote)
echo||'

# --- the rules ---
# judge NAME JSON WANT: runs guard.sh on JSON in the project; WANT is
# "allow" or a rule ID (the refusal must start "guard RULE:" and exit 2)
judge() {
  name=$1
  printf '%s' "$2" >"$work/in.json"
  err=$(cd "$proj" && env -u CLAUDE_CODE_EXECPATH CLAUDE_PROJECT_DIR="$proj" bash "$guard" <"$work/in.json" 2>&1 >"$work/out")
  code=$?
  case "$3" in
    allow) if [ "$code" -eq 0 ] && [ -z "$err" ]; then pass "$name"; else fail "$name: wanted it let through" "exit $code: $err"; fi ;;
    *) case "$err" in
        "guard $3: "*) if [ "$code" -eq 2 ] && [ "$(printf '%s\n' "$err" | wc -l | tr -d ' ')" -eq 1 ]; then pass "$name"; else fail "$name: wanted one line and exit 2" "exit $code: $err"; fi ;;
        *) fail "$name: wanted guard $3" "exit $code: $err" ;;
      esac ;;
  esac
}
bash_call() {
  CMD="$1" perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({tool_name => ($ARGV[0] // "Bash"), tool_input => {command => $ENV{CMD}}, cwd => $ARGV[1], hook_event_name => "PreToolUse"})' "${2:-Bash}" "$proj"
}
judge "a plain command is let through" "$(bash_call 'git status')" allow
judge "a plain write is let through" "$(bash_call 'echo hi > notes.txt')" allow
for c in 'echo $(git rev-parse HEAD) > x' 'echo `gh pr list`' 'git push origin $(git branch --show-current)' 'CMD=git; $CMD push origin main' 'printf "git push" | sh' 'cat <<EOF | bash
git push
EOF' 'python3 -c "import os; os.system(\"git push\")"' 'perl -e "system q(git push)"' 'node -e "require(\"child_process\").execSync(\"gh pr merge 1\")"' "perl -e 'open F, \">\", \".claude/hooks/method/guard.sh\"'" 'eval "$X"; git status' 'bash -c "$Y"; git log' 'source .claude/hooks/method/guard.sh' 'echo x > .claude/settings.*' 'case $x in a) git push;; esac' "git commit -m 'open" 'bash <<EOF
git push origin main
EOF'; do
  judge "G0 refuses a shape it cannot read next to a watched word: $(printf '%s' "$c" | head -1 | cut -c1-40)" "$(bash_call "$c")" G0
done
for c in 'echo $(date) > out.txt' 'python3 -c "print(1)"' 'ls *.txt > list.txt' 'printf x | sh' 'source venv/bin/activate' 'source helper.sh; git status' 'git log --oneline | perl -ne "print if /fix/"' 'perl -0pi -e "s/git/GIT/" notes.md' 'echo x > out-*.txt; git add -A' 'ls /tmp/claude-0/x $(pwd)' 'python3 -c "print(\"git status is fine\")"'; do
  judge "the same shapes with no watched word are let through: $c" "$(bash_call "$c")" allow
done
judge "bash -c is read through: an unreadable shape inside it next to git is refused" "$(bash_call 'bash -c "echo \$(git log)"')" G0
judge "a Monitor command is judged as a Bash one" "$(bash_call 'echo $(git rev-parse HEAD)' Monitor)" G0
judge "input that is not JSON is refused" "not json" G0
judge "input that is not one JSON object is refused" '[1,2]' G0
judge "a Bash call with no command text is refused" '{"tool_name":"Bash","tool_input":{"command":["git","push"]}}' G0
judge "every PowerShell call is refused" "$(bash_call 'dir' PowerShell)" G2
judge "a tool the rules do not name yet is let through" '{"tool_name":"Read","tool_input":{"file_path":"/etc/hosts"}}' allow

# --- the log ---
log="$proj/.method/local/guard.log"
rm -rf "$proj/.method"
key="sk-ant""-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef0123456789"
judge "a refusal of a command holding a key" "$(bash_call "echo \$(git log) $key")" G0
if [ -f "$log" ] && LC_ALL=C grep -q "^[0-9-]*T[0-9:]*Z	G0	Bash	[0-9a-f]\{64\}\$" "$log"; then pass "each refusal adds one line to .method/local/guard.log: time, rule, tool, hash"; else fail "each refusal adds one line to the guard log" "$(cat "$log" 2>/dev/null)"; fi
if ! grep -F -q -- "$key" "$log" && ! printf '%s' "$err" | grep -F -q -- "$key" && ! printf '%s' "$err" | grep -F -q -- 'git log'; then pass "the log and the refusal hold neither the key nor the command's text"; else fail "the log and the refusal hold neither the key nor the command's text" "$err"; fi
perl -e 'open my $f, ">", $ARGV[0] or die; printf $f "2026-01-01T00:00:00Z\tG0\tBash\t%064x\n", $_ for 1 .. 5000' "$log"
judge "a refusal with a full log" "$(bash_call 'echo $(git log)')" G0
n=$(wc -l <"$log" | tr -d ' ')
if [ "$n" -eq 1000 ]; then pass "a planted 5,000-line guard log is trimmed to 1,000 by the next refusal"; else fail "a planted 5,000-line guard log is trimmed to 1,000 by the next refusal" "$n lines"; fi

# --- the wrapper ---
mkdir -p "$work/noperl"
for t in bash sh env sed cat; do
  w=$(command -v "$t") && ln -s "$w" "$work/noperl/$t"
done
printf '%s' "$(bash_call 'ls')" >"$work/in.json"
err=$(cd "$proj" && PATH="$work/noperl" CLAUDE_PROJECT_DIR="$proj" bash "$guard" <"$work/in.json" 2>&1 >/dev/null)
code=$?
case "$code:$err" in
  "2:guard G1: perl is missing"*) pass "without perl every call is refused (G1), with the way out" ;;
  *) fail "without perl every call is refused (G1)" "exit $code: $err" ;;
esac
sb=$(make_sandbox) || abort_sandbox
printf 'die "planted\\n";\n' >"$sb/method/scripts/method/lib/guard.pl"
printf '%s' "$(bash_call 'ls')" >"$work/in.json"
err=$(CLAUDE_PROJECT_DIR="$proj" bash "$sb/method/.claude/hooks/method/guard.sh" <"$work/in.json" 2>&1 >/dev/null)
code=$?
case "$code:$err" in
  "2:guard G0: the guard stopped without an answer"*) pass "a guard.pl that crashes refuses the call (G0), never lets it through" ;;
  *) fail "a guard.pl that crashes refuses the call (G0)" "exit $code: $err" ;;
esac
printf '$! = 3; die "planted\\n";\n' >"$sb/method/scripts/method/lib/guard.pl"
printf 'require "%s"; $! = 3; die "planted\\n";\n' "$lib/hook.pl" >"$sb/method/scripts/method/lib/guard.pl"
err=$(CLAUDE_PROJECT_DIR="$proj" bash "$sb/method/.claude/hooks/method/guard.sh" <"$work/in.json" 2>&1 >/dev/null)
code=$?
case "$code:$err" in
  "2:guard G0: the guard stopped without an answer (code 70)"*) pass "a crash that would exit 3 is still a crash (code 70), refused" ;;
  *) fail "a crash that would exit 3 is still a crash (code 70), refused" "exit $code: $err" ;;
esac
rm -f "$sb/method/scripts/method/lib/guard.pl"
err=$(CLAUDE_PROJECT_DIR="$proj" bash "$sb/method/.claude/hooks/method/guard.sh" <"$work/in.json" 2>&1 >/dev/null)
code=$?
case "$code:$err" in
  "2:guard G0: the method's scripts are missing"*) pass "missing scripts refuse the call (G0)" ;;
  *) fail "missing scripts refuse the call (G0)" "exit $code: $err" ;;
esac
drop_sandbox "$sb" || true
mkdir -p "$work/plib/JSON"
printf 'package JSON::PP; die "planted: a JSON::PP from PERL5LIB ran\\n";\n' >"$work/plib/JSON/PP.pm"
printf '%s' "$(bash_call 'echo $(git log)')" >"$work/in.json"
err=$(cd "$proj" && PERL5LIB="$work/plib" PERL5OPT="-I$work/plib" CLAUDE_PROJECT_DIR="$proj" bash "$guard" <"$work/in.json" 2>&1 >/dev/null)
code=$?
case "$code:$err" in
  "2:guard G0: this command holds"*) pass "PERL5LIB and PERL5OPT from a settings file do not reach the guard's perl" ;;
  *) fail "PERL5LIB and PERL5OPT from a settings file do not reach the guard's perl" "exit $code: $err" ;;
esac
perl_fn=$(cd "$proj" && bash -c 'perl() { exit 0; }; export -f perl; bash "$1" <"$2"' sh "$guard" "$work/in.json" 2>&1 >/dev/null)
case "$perl_fn" in
  "guard G0: this command holds"*) pass "an exported shell function named perl does not stand in for perl" ;;
  *) fail "an exported shell function named perl does not stand in for perl" "$perl_fn" ;;
esac

# --- the time a call takes ---
printf '%s' "$(bash_call 'git status && git log --oneline -5')" >"$work/in.json"
times=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" perl -MTime::HiRes=time -e 'my @t; for (1 .. 30) { my $s = time; system("bash", "-c", "bash \"\$0\" < \"\$1\"", $ARGV[0], $ARGV[1]) == 0 or exit 1; push @t, time - $s } @t = sort { $a <=> $b } @t; printf "%d %d", 1000 * $t[15], 1000 * $t[27]' "$guard" "$work/in.json")
median=${times% *}
p90=${times#* }
if [ "$median" -le 200 ]; then pass "a call takes ${median} ms median, ${p90} ms at the 90th percentile (the plan's targets on Linux: 40 and 60; this test fails only over 200)"; else fail "a call takes ${median} ms median" "p90 $p90"; fi

drop_sandbox "$work" || true
echo "tests: guard: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
