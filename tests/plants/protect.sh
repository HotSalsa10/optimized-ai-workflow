#!/usr/bin/env bash
# Plants for the guard's protected files (step 5.7, G6 and G12): each
# protected path dropped from lib/protect.pl, each part of the read-only
# rule and of the write rules removed or widened, and the path forms left
# unread, turn tests/guard-protect.test.sh red for the stated reason. Each
# runs in a throwaway copy of the repo.
# shellcheck disable=SC2016 # the plants are literal perl text
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: protected files"
# plant NAME REASON OLD NEW [OLD2 NEW2]: in a fresh copy, the text OLD in
# lib/protect.pl (it must be there exactly once) becomes NEW, and OLD2
# NEW2 likewise when given; tests/guard-protect.test.sh must then fail with
# REASON
plant() {
  name=$1
  reason=$2
  sb=$(make_sandbox) || abort_sandbox
  if ! (cd "$sb" && OLD="$3" NEW="$4" OLD2="${5:-}" NEW2="${6:-}" perl -0pi -e 'for my $k ("", "2") { my ($o, $n) = ($ENV{"OLD$k"}, $ENV{"NEW$k"}); next if $o eq ""; my $i = index($_, $o); die "missing\n" if $i < 0; die "twice\n" if index($_, $o, $i + 1) >= 0; substr($_, $i, length $o) = $n }' method/scripts/method/lib/protect.pl); then
    fail "$name: the plant did not apply, so the check result would mean nothing"
  else
    got=$(cd "$sb" && bash tests/guard-protect.test.sh 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then
      fail "$name: the protected-files test stayed green" "$(printf '%s\n' "$got" | tail -2)"
    elif ! printf '%s\n' "$got" | grep -F -q -- "FAIL  $reason"; then
      fail "$name: went red, but not for the stated reason ('$reason')" "$(printf '%s\n' "$got" | grep FAIL | head -3)"
    else
      pass "$name"
    fi
  fi
  drop_sandbox "$sb" || true
}
# drop NAME REASON TEXT: the protected-path line that holds TEXT, switched
# off
drop() { plant "$1" "$2" "\$add->($3" "0 && \$add->($3"; }

# --- each protected path dropped ---
drop "the method's hooks dropped" "Write to projü/.claude/hooks/method/guard.sh is refused" '"$t/.claude/hooks/method"'
drop "the method's agents dropped" "Write to projü/.claude/agents/method/reviewer.md is refused" '"$t/.claude/agents/method"'
drop "the method's rules dropped" "Write to projü/.claude/rules/method/x.md is refused" '"$t/.claude/rules/method"'
drop "the owner's lists dropped" "Write to projü/.claude/method-local/git-shapes.txt is refused" '"$t/.claude/method-local"'
drop "the method's scripts dropped" "Write to projü/scripts/method/status.sh is refused" '"$t/scripts/method"'
drop "the project's settings dropped" "Write to projü/.claude/settings.json is refused" '"$t/.claude/settings.json"'
drop "the project's local settings dropped" "Write to projü/.claude/settings.local.json is refused" '"$t/.claude/settings.local.json"'
plant "the other worktrees not looked up" "Write to the settings of the project's other worktree is refused" 'if ($wst == 0) { push @tops' 'if (0) { push @tops'
drop "git's hooks dropped" "Write to projü/.git/hooks/pre-commit is refused" '"$common/hooks"'
# (.git/config is also among the files git says it reads: both are dropped)
plant "git's config dropped, with the files git reads" "Write to projü/.git/config is refused" '$add->("$g/config", ' '0 && $add->("$g/config", ' '$add->($from, ' '0 && $add->($from, '
drop "git's per-worktree config dropped" "Write to git's per-worktree settings is refused" '"$g/config.worktree"'
drop "the method's files in git's folder dropped" "Write to projü/.git/method-mutate-journal is refused" '$g, '
drop "the include files dropped" "Write to a settings file git reads through include.path is refused" '$inc, '
drop "core.hooksPath dropped" "Write into the folder core.hooksPath names is refused" '($hp =~'
drop "your Claude Code settings dropped" "Write to home/.claude/settings.json is refused" '$c, '
drop "your Claude Code agents, skills and commands dropped" "Write to home/.claude/agents/x.md is refused" '"$c/$_"'
drop "the home .gitconfig dropped" "Write to ~/.gitconfig before it exists is refused" '"$h/.gitconfig"'
drop "the home .config/git dropped" "Write to home/.config/git/config is refused" '"$xdg/git"'
drop "GIT_CONFIG_GLOBAL dropped" "Write to the file GIT_CONFIG_GLOBAL names is refused" '$ENV{$v}'
drop "/etc/gitconfig dropped" "Write to /etc/gitconfig is refused" "'/etc/gitconfig'"
drop "the managed settings dropped" "Write to /etc/claude-code/managed-settings.json is refused" '$_, '

# --- the read-only rule ---
plant "tee added to the read-only list" "a write is refused: tee .git/config < notes.txt" 'qw(cat head ' 'qw(cat tee head '
plant "sed -i let through" "a write is refused: sed -i s/a/b/ .claude/settings.json" 'return 0 if grep { /\A-[A-Za-z]*i/ || /\A--in-place/ } @a;' ''
plant "find -delete let through" "a write is refused: find .claude -delete" 'exec|execdir|ok|okdir|delete|fprint|' 'exec|execdir|ok|okdir|fprint|'
plant "sort -o let through" "a write is refused: sort -o .claude/settings.json notes.txt" "return 0 if \$n eq 'sort'" "return 0 if 0 && \$n eq 'sort'"
plant "a redirect into a protected path from a reading command let through" "a write is refused: echo x > .claude/settings.json" '"this call writes into $e->{what}, which Claude may only read$NO") if $e;' '"this call writes into $e->{what}, which Claude may only read$NO") if 0;'
plant "any script in a project folder taken for the method's own" "a write is refused: bash .claude/hooks/method/guard.sh" 'return 1 if key(dirname($p)) eq key("$t/scripts/method");' 'return 1;'
plant "the text of inline programs and sed scripts not read" "a write is refused: sed -n \"w .claude/settings.json\" notes.txt" 'if ($code =~ $text)' 'if (0)'
plant "the assignments not read" "a write is refused: F=.claude/settings.json; rm \"\$F\"" 'push @look, map { /\A[A-Za-z_][A-Za-z0-9_]*\+?=(.*)\z/s ? $1 : () }' 'push @look, map { () }'
plant "an MCP tool of any name let through" "an MCP write tool given a protected path is refused" 'return () if $short =~' 'return (); 0 if $short =~'

# --- what a copy writes, and recursive writes ---
plant "a copy's resulting path not judged" "a write that lands on a protected path is refused: cp x/settings.json .claude/" 'return "this $n writes into $e->{what}, which Claude may only read" if $e;' ''
plant "the recursive-write rule removed" "a write that lands on a protected path is refused: cp -r x/. ." 'if (($rec || ($n eq '"'mv'"' && $dir_src)) && ($e = above($r, $set)))' 'if (0)'
plant "tar's extraction not judged" "a write that lands on a protected path is refused: tar -xf x.tar" 'extract into a new subfolder" if $e;' 'extract into a new subfolder" if 0;'
plant "unzip and patch not judged" "a write that lands on a protected path is refused: unzip x.zip" 'run it in a new subfolder" if $e;' 'run it in a new subfolder" if 0;'
plant "rm -r of a folder above not judged" "a write that lands on a protected path is refused: rm -rf .claude" 'return "this rm deletes a folder that holds $e->{what}" if $e;' ''
plant "find -delete in a folder above not judged" "a write that lands on a protected path is refused: find . -name \"*.pyc\" -delete" 'start it in a subfolder" if $e;' 'start it in a subfolder" if 0;'
plant "git rm -r of a folder above not judged" "a write that lands on a protected path is refused: git rm -r --cached .claude" 'return "this git $sub removes or moves a folder that holds $e->{what}" if $e;' ''
plant "a move of a folder that holds protected paths not judged" "a write that lands on a protected path is refused: mv .claude claude-old" 'return "this mv moves a folder that holds $e->{what}";' 'return undef;'

# --- path forms ---
plant "paths compared as characters, not bytes" "Write to projü/.claude/settings.json is refused" 'utf8::encode($s) if utf8::is_utf8($s);' ''
plant "the resolution of .. removed" "Edit by a path with .. in it: wanted guard G6" "if (\$c eq '..') { \$cur =~ s{/[^/]*\\z}{}; next }" ''
plant "links not followed" "Edit through a link into a protected folder: wanted guard G6" 'if (-l $next) {' 'if (0) {'
plant "backslashes not read as /" "a write with backslashes in the path is refused" '$p =~ tr{\\}{/};' ''
plant "letter case never folded" "letter case" 'return $FOLD ? lc $p : $p' 'return $p'
plant "the folder of the call not followed" "a write after a cd within the project is judged from the folder it moved to" '    my $base = defined $dirs->[$k] ? $dirs->[$k] : $top;
    my @w = @{ $c->{words} };
    my @look' '    my $base = $top;
    my @w = @{ $c->{words} };
    my @look'

# --- git and G12 ---
plant "the git version check removed" "a cherry-pick of a commit that changes the guard is refused" 'next unless @$m;' 'next;'
plant "G12 warns at every call" "G12: one warning per session" 'return undef if $lines && grep { $_->[3] eq $hash } @$lines;' ''
plant "G12 warns inside subagents" "G12: a call inside a subagent gets no warning" "return undef if defined \$in->{agent_id} && !ref \$in->{agent_id} && \$in->{agent_id} ne '';" ''
plant "G12 warns at max" "G12: max gets no warning" '(?:xhigh|max)' '(?:xhigh)'

echo "plants: protected files: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
