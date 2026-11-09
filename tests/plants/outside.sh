#!/usr/bin/env bash
# Plants for the guard's rule for the outside (step 5.8, G4): each gh and
# MCP list line widened, the GitHub-host check for curl and wget removed or
# narrowed, each part of the nested-Claude rule removed, and the MCP checks
# loosened, turn tests/guard-outside.test.sh red for the stated reason. The
# settings' deny entries have their plants in tests/plants/settings.sh.
# Each runs in a throwaway copy of the repo.
# shellcheck disable=SC2016 # the plants are literal perl text
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: outside"
lib=method/scripts/method/lib/outside.pl
gh=method/.claude/hooks/method/gh-shapes.txt
mcp=method/.claude/hooks/method/mcp-tools.txt
# plant NAME REASON FILE OLD NEW: in a fresh copy, the text OLD in FILE (it
# must be there exactly once) becomes NEW; tests/guard-outside.test.sh must
# then fail with REASON
plant() {
  name=$1
  reason=$2
  sb=$(make_sandbox) || abort_sandbox
  if ! (cd "$sb" && OLD="$4" NEW="$5" perl -0pi -e 'my ($o, $n) = ($ENV{OLD}, $ENV{NEW}); my $i = index($_, $o); die "missing\n" if $i < 0; die "twice\n" if index($_, $o, $i + 1) >= 0; substr($_, $i, length $o) = $n' "$3"); then
    fail "$name: the plant did not apply, so the check result would mean nothing"
  else
    got=$(cd "$sb" && bash tests/guard-outside.test.sh 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then
      fail "$name: the outside test stayed green" "$(printf '%s\n' "$got" | tail -2)"
    elif ! printf '%s\n' "$got" | grep -F -q -- "FAIL  $reason"; then
      fail "$name: went red, but not for the stated reason ('$reason')" "$(printf '%s\n' "$got" | grep FAIL | head -3)"
    else
      pass "$name"
    fi
  fi
  drop_sandbox "$sb" || true
}
# widen NAME REASON LINE-START: the gh line that starts with LINE-START
# (two words) loses its second word, so it covers every verb of the first
widen() {
  first=${3%% *}
  plant "$1" "$2" "$gh" "
$3 " "
$first "
}
# opens NAME REASON LINE-START: the gh line that starts with LINE-START
# also takes any other option (-*)
opens() {
  plant "$1" "$2" "$gh" "
$3 " "
$3 -* "
}
# adds NAME REASON LINE-START OPTION: the gh line that starts with
# LINE-START also takes OPTION
adds() {
  plant "$1" "$2" "$gh" "
$3 " "
$3 $4 "
}

# --- each reading gh line widened to every verb of its command ---
widen "pr view widened" "gh pr merge is refused" "pr view"
widen "pr list widened" "gh pr merge is refused" "pr list"
widen "pr diff widened" "gh pr merge is refused" "pr diff"
widen "pr checks widened" "gh pr merge is refused" "pr checks"
widen "pr status widened" "gh pr merge is refused" "pr status"
widen "issue view widened" "gh issue close is refused" "issue view"
widen "issue list widened" "gh issue close is refused" "issue list"
widen "issue status widened" "gh issue close is refused" "issue status"
widen "run list widened" "gh run rerun is refused" "run list"
widen "run view widened" "gh run rerun is refused" "run view"
widen "run watch widened" "gh run rerun is refused" "run watch"
widen "workflow list widened" "gh workflow run is refused" "workflow list"
widen "workflow view widened" "gh workflow run is refused" "workflow view"
widen "repo view widened" "gh repo delete is refused" "repo view"
widen "release list widened" "gh release create is refused" "release list"
widen "release view widened" "gh release create is refused" "release view"
widen "label list widened" "gh label create is refused" "label list"
# (the search lines only read, whatever the verb: no plant)

# --- the lines that name their options, opened to any option ---
opens "pr create opened" "gh pr create asking for reviewers is refused" "pr create"
opens "pr comment opened" "gh pr comment --edit-last is refused" "pr comment"
opens "pr edit opened" "gh pr edit of the base is refused" "pr edit"
opens "issue create opened" "gh issue create with assignees is refused" "issue create"
opens "issue comment opened" "gh issue comment --edit-last is refused" "issue comment"
opens "auth status opened" "gh auth status -t is refused (it prints the token)" "auth status"
opens "api opened" "gh api -XPOST is refused" "api"
plant "gh pr create without --head let through unpushed" "gh pr create without --head is refused (gh could push the branch itself)" "$lib" "if (\$ok && \$rest[0] eq 'pr'" "if (0 && \$ok && \$rest[0] eq 'pr'"
plant "commits its upstream lacks not counted" "gh pr create without --head is refused while the branch has commits its upstream lacks" "$lib" "return \$1 > 0 ? 'the branch has commits its upstream lacks' : undef;" 'return undef;'
plant "a URL taken for a pull request" "gh pr comment on a URL is refused (it could name another repository)" "$gh" 'pr comment -b= --body= -F= --body-file= REFNAME?' 'pr comment -b= --body= -F= --body-file= ARG...'
plant "--web let through on a read" "gh pr view --web is refused (it runs the browser program)" "$gh" 'pr view -* !-w !--web' 'pr view -*'

# --- each option that writes, or reaches another repository, added ---
adds "api takes -X" "gh api -X PUT is refused" "api" "-X="
adds "api takes --method" "gh api --method POST is refused" "api" "--method="
adds "api takes -f" "gh api -f is refused (it makes a POST)" "api" "-f="
adds "api takes -F" "gh api -F after the path is refused" "api" "-F="
adds "api takes --field" "gh api --field is refused" "api" "--field="
adds "api takes --raw-field" "gh api --raw-field is refused" "api" "--raw-field="
adds "api takes --input" "gh api --input is refused" "api" "--input="
adds "pr create takes -R" "gh pr create on another repository is refused" "pr create" "-R="
adds "pr comment takes -R" "gh pr comment on another repository is refused" "pr comment" "-R="
adds "issue create takes --repo" "gh issue create with --repo is refused" "issue create" "--repo="
adds "issue comment takes --repo" "gh issue comment with --repo= is refused" "issue comment" "--repo="

# --- gh's checks in code ---
plant "--help on any command" "--help on an alias is refused (it runs the alias)" "$lib" 'return 0 unless $GH_BUILTIN{ $w[0] };' ''
plant "-h taken for help under auth" "gh auth token -h is not help (under auth, -h names a host)" "$lib" " && \$w[0] ne 'auth')" ')'
plant "--help after -- taken for help" "--help after -- is not help" "$lib" "    last if \$x eq '--';
    return 1 if" '    return 1 if'
plant "any word taken for a pull request" "gh pr comment on a URL is refused (it could name another repository)" "$lib" "return 0 unless \$type eq 'REFNAME' && defined \$v;" 'return 1;'
plant "-f dropped without a GET" "gh api -f is refused (it makes a POST)" "$lib" 'return @w unless $get;' ''
plant "-F dropped with a GET" "gh api -X GET with -F is refused (it can read a file)" "$lib" "(\$x eq '-X' || \$x eq '--method' || \$x eq '-f' || \$x eq '--raw-field') && \$i < \$#w && (\$x =~ /\\A-(?:f|-raw-field)\\z/" "(\$x eq '-X' || \$x eq '--method' || \$x =~ /\\A-[fF]\\z/ || \$x eq '--raw-field') && \$i < \$#w && (\$x =~ /\\A-(?:[fF]|-raw-field)\\z/"
plant "GH_REPO not read" "setting GH_REPO for gh is refused" "$lib" 'qw(GH_REPO GH_HOST' 'qw(GH_HOST'
plant "GH_TOKEN not read" "GH_TOKEN is refused (another account)" "$lib" 'GH_TOKEN GITHUB_TOKEN ' 'GITHUB_TOKEN '
plant "GH_BROWSER not read" "GH_BROWSER is refused (a program gh runs)" "$lib" 'GH_BROWSER BROWSER ' ''
plant "a pager of any program" "GH_PAGER with a program is refused" "$lib" '$a =~ /=(?:cat)?\z/' '$a =~ /=/'
plant "a setting earlier in the call not read" "exporting GH_REPO before gh is refused" "$lib" 'push @set, grep { /=/ } @w[1 .. $#w] if' 'push @set, () if'
plant "the gh list's errors ignored" "a gh-shapes.txt line that cannot be read refuses gh until it is fixed" "$lib" 'gh commands are refused until it is fixed") if @$errors;' 'gh commands are refused until it is fixed") if 0;'
plant "the project's own gh list not read" "a shape the owner adds in .claude/method-local/gh-shapes.txt passes" "$lib" "'.claude', 'method-local', \$name)" "'.claude', 'method-local', 'x' . \$name)"

# --- curl and wget to GitHub ---
plant "the curl and wget check removed" "curl PUT to GitHub's API is refused" "$lib" 'my $why = http_write($n, \@w, $c->{assigns} || []);' 'my $why;'
plant "the GitHub-host check removed (every host judged)" "curl posting elsewhere passes" "$lib" 'return undef unless grep { $_ =~ $GITHUB_HOST } @$w[1 .. $#$w];' ''
plant "the GitHub hosts narrowed to the API host" "curl uploading a file to GitHub is refused" "$lib" '(?:(?:[a-z0-9-]+\.)*github\.com|' '(?:api\.github\.com|'
plant "capitals not read in the host" "curl to GitHub in capitals is refused" "$lib" "(?=\\z|[/:?#\\s'\"])}i;" "(?=\\z|[/:?#\\s'\"])};"
plant "shortened long options not read" "curl with a shortened --data is refused" "$lib" 'return length($w) >= 2 && index($name, $w) == 0;' 'return $w eq $name;'
plant "curl -T not read" "curl uploading a file to GitHub is refused" "$lib" '$o =~ /\A[dFT]\z/' '$o =~ /\A[dF]\z/'
plant "an option cluster read as one option" "curl with -d inside an option cluster is refused" "$lib" 'my $o = shift @l;' 'my $o = shift @l; @l = ();'
plant "wget -e not read" "wget with a wgetrc command is refused" "$lib" "return 'a wgetrc command (-e)' if \$o eq 'e';" ''
plant "a curl config file not looked for" "curl to GitHub is refused while a ~/.curlrc is there" "$lib" 'if (!$no_rc && defined(my $rc = rc_file($n)))' 'if (0 && defined(my $rc = rc_file($n)))'
plant "a setting that moves the config file not read" "curl setting CURL_HOME is refused" "$lib" 'qw(HOME CURL_HOME XDG_CONFIG_HOME' 'qw(HOME XDG_CONFIG_HOME'

# --- another Claude ---
plant "the claude command allowed" "another Claude is refused: claude -p" "$lib" "if (lc \$n eq 'claude') {" 'if (0) {'
plant "the Claude Code package allowed" "another Claude is refused: the npm package through npx" "$lib" 'm{\@anthropic-ai/claude-code\b|\Aclaude-code\z}' 'm{\Aclaude-code\z}'
plant "the settings that start Claude without hooks allowed" "setting CLAUDE_CONFIG_DIR is refused" "$lib" 'next unless $NESTED_ENV{$1};' 'next;'
plant "a program's text not read" "setting CLAUDE_CONFIG_DIR inside a python program is refused" "$lib" 'if ($code =~ $CLAUDE_TEXT) {' 'if (0) {'

# --- MCP ---
plant "the MCP read names widened" "the GitHub MCP merge tool is refused" "$lib" '/\A(?:get|list|search|read)_/' '/_/'
plant "the same-session tools dropped" "a message to this same session passes" "$lib" 'return () if $SAME{$name};' ''
plant "the repository check removed" "a pull request on another repository is refused" "$lib" '|| lc $io ne lc $o || lc $ir ne lc $r' ''
plant "refs/heads/ not read in a branch" "a file written on refs/heads/main is refused" "$lib" 's{\A(?:refs/)?heads/}{};' 's{\A(?:refs/)?heads/\z}{};'
plant "master not taken for main" "a pull request from master is refused" "$lib" 'my %main = (main => 1, master => 1);' 'my %main = (main => 1);'
plant "origin's HEAD branch not taken for main" "an MCP push to the branch origin's HEAD names (trunk) is refused" "$lib" '$main{ lc $1 } = 1 if' '0 and $main{ lc $1 } = 1 if'
plant "a branch in any form" "a pull request from another owner's branch is refused" "$lib" ' || $b !~ m{\A[A-Za-z0-9_][A-Za-z0-9._/-]*\z}' ''
plant "an empty list taken as given" "a pull request with an empty reviewers list passes" "$lib" " || (ref \$v eq 'ARRAY' && !@\$v)" ''
plant "create_pull_request's head not checked" "a pull request from main is refused" "$mcp" 'create_pull_request head !reviewers ::' 'create_pull_request !reviewers ::'
plant "create_pull_request's reviewers let through" "a pull request asking for reviewers is refused" "$mcp" 'create_pull_request head !reviewers ::' 'create_pull_request head ::'
plant "push_files's branch not checked" "a push of files to main is refused" "$mcp" 'push_files branch ::' 'push_files ::'
plant "create_or_update_file's branch not checked" "a file written on refs/heads/main is refused" "$mcp" 'create_or_update_file branch !allow_symlink_write ::' 'create_or_update_file !allow_symlink_write ::'
plant "create_or_update_file's link writes let through" "re-pointing a link is refused" "$mcp" 'create_or_update_file branch !allow_symlink_write ::' 'create_or_update_file branch ::'
plant "delete_file's branch not checked" "a delete on main is refused" "$mcp" 'delete_file branch ::' 'delete_file ::'
plant "create_branch's branch not checked" "a branch named main is refused" "$mcp" 'create_branch branch ::' 'create_branch ::'
plant "update_pull_request's state let through" "closing a pull request is refused" "$mcp" 'update_pull_request !state !base' 'update_pull_request !base'
plant "update_pull_request on any repository" "editing a pull request of another repository is refused" "$mcp" 'update_pull_request !state !base !reviewers ::' 'update_pull_request @anywhere ::'
plant "issue_write's method not checked" "editing an issue is refused" "$mcp" 'issue_write method=create ' 'issue_write '
plant "issue_write's assignees let through" "opening an issue with assignees is refused" "$mcp" ' !assignees ' ' '
plant "the MCP list's errors ignored" "an mcp-tools.txt line that cannot be read refuses MCP writes until it is fixed" "$lib" 'MCP tools that write are refused until it is fixed") if @$errors;' 'MCP tools that write are refused until it is fixed") if 0;'

# --- the guard's wiring ---
plant "G4 not asked for Bash" "gh pr merge is refused" method/scripts/method/lib/guard.pl '($rule, $text) = Outside::judge_bash(\@cmds, $project, [cmd_dirs(\@cmds, defined $start ? $start : '"'"'.'"'"')]) unless $rule;' ''
plant "G4 not asked for MCP tools" "the GitHub MCP merge tool is refused" method/scripts/method/lib/guard.pl '($rule, $text) = Outside::judge_mcp($tool, $input, $project) unless $rule;' ''
plant "SendMessage let through" "SendMessage is refused" method/scripts/method/lib/guard.pl "if (\$tool eq 'SendMessage') {" 'if (0) {'
plant "an MCP tool's whole name logged" "an MCP refusal is logged by the tool's server only" method/scripts/method/lib/guard.pl '$t =~ s/\A(mcp__[A-Za-z0-9_.:-]*?)__.*\z/$1/s;' ''
# the final review of step 5
plant "RemoteTrigger let through" "RemoteTrigger, which schedules remote agents, is refused" method/scripts/method/lib/guard.pl "if (\$tool eq 'RemoteTrigger') {" 'if (0) {'
plant "an agent in a remote sandbox let through" "an agent in a remote sandbox (isolation remote) is refused" method/scripts/method/lib/guard.pl "&& \$input->{isolation} eq 'remote') {" "&& 0) {"
plant "an MCP write with no branch field let through" "an MCP write tool with no branch field is refused" "$lib" "if !defined \$b || (!ref \$b && \$b eq '');" "if 0;
    next unless defined \$b;"

echo "plants: outside: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
