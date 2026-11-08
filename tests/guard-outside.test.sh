#!/usr/bin/env bash
# Tests for the guard's rule for the outside (step 5.8): G4 (lib/outside.pl)
# - gh by a list (gh-shapes.txt), curl and wget to GitHub only reading, no
# nested Claude, MCP tools by a list (mcp-tools.txt), no SendMessage. The
# calls are read from tests/guard-cases/outside.txt (so no shell quoting
# stands in the way) and run through guard.sh in a project whose origin
# names a GitHub repository (never contacted).
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}
echo "tests: guard (outside)"
root=$(repo_root)
guard="$root/method/.claude/hooks/method/guard.sh"
work=$(new_sandbox_dir) || abort_sandbox
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
git config --global user.email test@example.invalid
git config --global user.name Test
git config --global init.defaultBranch main
git config --global commit.gpgsign false
proj="$work/proj"
mkdir -p "$proj"
(cd "$proj" && git init -q && printf 'a\n' >a.txt && git add a.txt && git commit -qm one && git switch -qc task && git remote add origin https://github.com/example-owner/example-repo.git) || abort_sandbox

# run_case RULE NAME TOOL INPUT: guard.sh on one call; RULE is allow or a
# rule ID (the refusal must start "guard RULE:" and exit 2)
run_case() {
  printf '%s' "$4" >"$work/in.json"
  err=$(cd "$proj" && env -u CLAUDE_CODE_EXECPATH CLAUDE_PROJECT_DIR="$proj" perl -e 'alarm 60; exec @ARGV' bash "$guard" <"$work/in.json" 2>&1 >/dev/null)
  code=$?
  case "$1" in
    allow) if [ "$code" -eq 0 ] && [ -z "$err" ]; then pass "$2"; else fail "$2: wanted it let through" "exit $code: $err"; fi ;;
    *) case "$err" in
        "guard $1: "*) if [ "$code" -eq 2 ]; then pass "$2"; else fail "$2: wanted exit 2" "exit $code: $err"; fi ;;
        *) fail "$2: wanted guard $1" "exit $code: $err" ;;
      esac ;;
  esac
}
# the cases: "@@ RULE TOOL NAME" opens one, its input follows (a command for
# Bash; JSON for any other tool), "@@ END" ends the list
cases="$here/guard-cases/outside.txt"
CASES="$cases" PROJ="$proj" perl -MJSON::PP -e '
  local $/; open my $h, "<", $ENV{CASES} or die "cannot read $ENV{CASES}\n"; my $t = <$h>;
  my $n = 0;
  for my $c (split /^@@ /m, $t) {
    my ($rule, $tool, $name, $body) = $c =~ /\A(\S+) (\S+) ([^\n]*)\n(.*)\z/s or next;
    $body =~ s/\n\z//;
    my $input = $tool eq "Bash" ? { command => $body } : JSON::PP->new->decode($body);
    $n++;
    open my $o, ">", "$ENV{PROJ}/../case-$n.json" or die;
    print $o JSON::PP->new->canonical->encode({ tool_name => $tool, tool_input => $input, cwd => $ENV{PROJ}, hook_event_name => "PreToolUse" });
    close $o;
    open $o, ">", "$ENV{PROJ}/../case-$n.txt" or die;
    print $o "$rule\t$name\n";
    close $o;
  }' || fail "the cases in tests/guard-cases/outside.txt can be read"
n=1
while [ -f "$work/case-$n.json" ]; do
  IFS='	' read -r rule name <"$work/case-$n.txt"
  run_case "$rule" "$name" x "$(cat "$work/case-$n.json")"
  n=$((n + 1))
done
[ "$n" -gt 60 ] || fail "the case file holds the cases" "only $((n - 1))"

# an MCP refusal is logged by its server only
if LC_ALL=C grep -q '	G4	mcp__github	' "$proj/.method/local/guard.log" && ! LC_ALL=C grep -q 'merge_pull_request' "$proj/.method/local/guard.log"; then
  pass "an MCP refusal is logged by the tool's server only, never the rest of its name"
else
  fail "an MCP refusal is logged by the tool's server only" "$(cut -f2-3 "$proj/.method/local/guard.log" 2>&1 | sort | uniq -c)"
fi

# a list line that cannot be read refuses what the list judges
mkdir -p "$proj/.claude/method-local"
printf 'pr frobnicate ::\n' >"$proj/.claude/method-local/gh-shapes.txt"
run_case G4 "a gh-shapes.txt line that cannot be read refuses gh until it is fixed" x "$(CMD='gh pr view 1' CWD="$proj" perl -MJSON::PP -e 'print JSON::PP->new->encode({tool_name => "Bash", tool_input => {command => $ENV{CMD}}, cwd => $ENV{CWD}})')"
printf 'pr merge -* ARG... :: the owner lets merges through in this project\n' >"$proj/.claude/method-local/gh-shapes.txt"
run_case allow "a shape the owner adds in .claude/method-local/gh-shapes.txt passes" x "$(CMD='gh pr merge --squash 1' CWD="$proj" perl -MJSON::PP -e 'print JSON::PP->new->encode({tool_name => "Bash", tool_input => {command => $ENV{CMD}}, cwd => $ENV{CWD}})')"
printf 'request_copilot_review :: the owner lets Claude ask for a Copilot review\n' >"$proj/.claude/method-local/mcp-tools.txt"
run_case allow "an MCP tool the owner adds in .claude/method-local/mcp-tools.txt passes" x "$(perl -MJSON::PP -e 'print JSON::PP->new->encode({tool_name => "mcp__github__request_copilot_review", tool_input => {owner => "example-owner", repo => "example-repo", pullNumber => 1}, cwd => $ARGV[0]})' "$proj")"
printf 'update_pull_request base\n' >"$proj/.claude/method-local/mcp-tools.txt"
run_case G4 "an mcp-tools.txt line that cannot be read refuses MCP writes until it is fixed" x "$(perl -MJSON::PP -e 'print JSON::PP->new->encode({tool_name => "mcp__github__add_issue_comment", tool_input => {owner => "example-owner", repo => "example-repo", issue_number => 1, body => "x"}, cwd => $ARGV[0]})' "$proj")"
rm -rf "$proj/.claude/method-local"

# a config file curl or wget reads by itself can make a plain call write
bash_json() { CMD="$1" CWD="$proj" perl -MJSON::PP -e 'print JSON::PP->new->encode({tool_name => "Bash", tool_input => {command => $ENV{CMD}}, cwd => $ENV{CWD}})'; }
printf 'request = "POST"\n' >"$HOME/.curlrc"
run_case G4 "curl to GitHub is refused while a ~/.curlrc is there" x "$(bash_json 'curl -s https://api.github.com/repos/o/r')"
run_case allow "curl -q to GitHub passes while a ~/.curlrc is there (-q skips it)" x "$(bash_json 'curl -q -s https://api.github.com/repos/o/r')"
run_case allow "curl elsewhere passes while a ~/.curlrc is there" x "$(bash_json 'curl -s https://example.com/x')"
rm -f "$HOME/.curlrc"
printf 'method = POST\n' >"$HOME/.wgetrc"
run_case G4 "wget to GitHub is refused while a ~/.wgetrc is there" x "$(bash_json 'wget https://github.com/o/r/archive/main.zip')"
run_case allow "wget --no-config to GitHub passes while a ~/.wgetrc is there" x "$(bash_json 'wget --no-config https://github.com/o/r/archive/main.zip')"
rm -f "$HOME/.wgetrc"

# main by another name: the branch origin's HEAD names is main too
(cd "$proj" && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk) || fail "origin/HEAD can be set"
run_case G4 "an MCP push to the branch origin's HEAD names (trunk) is refused" x "$(perl -MJSON::PP -e 'print JSON::PP->new->encode({tool_name => "mcp__github__push_files", tool_input => {owner => "example-owner", repo => "example-repo", branch => "trunk", files => [], message => "m"}, cwd => $ARGV[0]})' "$proj")"
(cd "$proj" && git symbolic-ref --delete refs/remotes/origin/HEAD) || fail "origin/HEAD can be removed"

# gh pr create without --head: through only when the branch is pushed and
# up to date (Claude Code's own form, with its body in a here-document)
# shellcheck disable=SC2016 # the command is data for the guard, never run
printf '%s\n' 'gh pr create --title "x" --body "$(cat <<'"'"'EOF'"'"'' '## Summary' '- one' 'EOF' ')"' >"$work/pr-form.txt"
pr_form=$(cat "$work/pr-form.txt")
(cd "$proj" && git update-ref refs/remotes/origin/task HEAD && git config branch.task.remote origin && git config branch.task.merge refs/heads/task) || fail "the task branch's upstream can be set"
run_case allow "Claude Code's gh pr create form, without --head, passes once the branch is pushed and up to date" x "$(bash_json "$pr_form")"
(cd "$proj" && git commit -q --allow-empty -m two) || fail "a commit can be made"
run_case G4 "gh pr create without --head is refused while the branch has commits its upstream lacks" x "$(bash_json "$pr_form")"
run_case allow "gh pr create --head passes whatever the upstream holds" x "$(bash_json 'gh pr create --head task --title x --body y')"

drop_sandbox "$work" || true
echo "tests: guard (outside): $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
