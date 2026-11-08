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
# NEW2 likewise when given (PLANT_FILE names another file in lib/, such as
# guard.pl); tests/guard-protect.test.sh must then fail with REASON
# PLANT_SHARD=K/N runs only every Nth plant from the Kth (0-based), so
# several copies can run side by side; unset, every plant runs
plant_n=0
in_shard() {
  plant_n=$((plant_n + 1))
  case "${PLANT_SHARD:-}" in
    */*) [ $(((plant_n - 1) % ${PLANT_SHARD#*/})) -eq "${PLANT_SHARD%/*}" ] ;;
    *) return 0 ;;
  esac
}
plant() {
  in_shard || return 0
  name=$1
  reason=$2
  sb=$(make_sandbox) || abort_sandbox
  if ! (cd "$sb" && OLD="$3" NEW="$4" OLD2="${5:-}" NEW2="${6:-}" perl -0pi -e 'for my $k ("", "2") { my ($o, $n) = ($ENV{"OLD$k"}, $ENV{"NEW$k"}); next if $o eq ""; my $i = index($_, $o); die "missing\n" if $i < 0; die "twice\n" if index($_, $o, $i + 1) >= 0; substr($_, $i, length $o) = $n }' "method/scripts/method/lib/${PLANT_FILE:-protect.pl}"); then
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
drop "the managed settings dropped" "Write to /etc/claude-code/managed-settings.json is refused" '$_, '"'dir'"', "the managed'

# --- the read-only rule ---
plant "tee added to the read-only list" "a write is refused: tee .git/config < notes.txt" 'qw(cat head ' 'qw(cat tee head '
plant "sed -i let through" "a write is refused: sed -i s/a/b/ .claude/settings.json" "if (\$l eq 'i') { \$inplace = 1; last }" "if (\$l eq 'i') { last }"
plant "find -delete let through" "a write is refused: find .claude -delete" '/\A-(?:delete|fprint|fprint0|fprintf|fls)\z/' '/\A-(?:fprint|fprint0|fprintf|fls)\z/'
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

# --- review round 1 of 5.7 (repair loop 1) ---
plant ">& not read as a write" 'a write is refused (5.7 repair loop 1): echo x >& .claude/settings.json' '|&>|&>>|>&)\z/ }' '|&>|&>>)\z/ }'
plant '$HOME, $PWD and $CLAUDE_PROJECT_DIR not read' 'a write is refused (5.7 repair loop 1): echo x > $PWD/.claude/settings.json' '  if ($p =~ s/$START_VAR//) {' '  if (0) {'
plant "globs not expanded" 'a write is refused (5.7 repair loop 1): rm -rf .clau*' 'return @out unless defined $w && $w =~ /[*?\[]/ && $w !~ /\0/;' 'return @out;'
plant "--target-directory with a space not read" 'a write is refused (5.7 repair loop 1): cp --target-directory .claude x/settings.json' "elsif (\$a[\$i] eq '--target-directory' && defined \$a[ \$i + 1 ]) { \$tdir = \$a[ \$i + 1 ] }" ''
plant "-tDIR not read" 'a write is refused (5.7 repair loop 1): cp -t.claude x/settings.json' "if (\$1 ne '') { \$tdir = \$1 }" "if (\$1 ne '') { }"
plant "-T not read" 'a write is refused (5.7 repair loop 1): cp -rT x .claude' "my \$no_into = \$n ne 'rsync' && (\$flags =~ /T/ || \$long{'no-target-directory'});" 'my $no_into = 0;'
plant "tar -CDIR not read" "tar -C with the folder attached is read (from a subfolder)" '|| $a[$i] =~ /\A-C(.+)\z/s) { push @t, $1 }' ') { push @t, $1 }'
plant "tar judged in its own folder when another is named" "an ordinary write passes: tar -xf x.tar -C build" '    # (the folder it runs in is judged only when none is named)
    shift @t if @t > 1;
' ''
plant "unzip -dDIR not read" "unzip -d with the folder attached is read (from a subfolder)" '|| $a[$i] =~ /\A-d(.+)\z/s) { push @t, $1 }' ') { push @t, $1 }'
plant "find's own options taken for its end" "find's own options before its path do not hide the path" "while (@b && \$b[0] =~ /\\A-(?:[HLP]+|D|O[0-9]*)\\z/) { my \$o = shift @b; shift @b if \$o eq '-D' }" ''
plant "git -C not followed for git rm" "git -C: the paths git rm is given are read from that folder" '$gbase = $d if defined $d;' ''
plant "git --output read as reading" "git log --output into a protected file, from another repository, is refused" 'return 0 if grep { /\A--output(?:=|\z)/ } @w;' ''
plant "the version check run in the subfolder" "a switch run from a subfolder is judged over the whole tree" '  $dir = top_of($dir);
  return undef unless defined $dir;
' ''
plant "the commits after -- not judged" "a cherry-pick with -- before the commit is still judged" "push @pos, @r[ \$i + 1 .. \$#r ] unless \$sub eq 'checkout'; last" 'last'
drop "the remote's branches dropped" 'a write is refused (5.7 repair loop 1): echo x > .git/refs/remotes/origin/main' '"$common/refs/remotes"'
drop "git's packed refs dropped" "Write to git's packed refs is refused" '"$common/packed-refs"'
plant "a linked settings file's real path not protected" "Write to the real file a linked settings file points at is refused" 'for grep { -l } bsd_glob("$q/settings*.json", GLOB_QUOTE | GLOB_NOSORT);' 'for ();'
plant "a linked skill's real folder not protected" "Write into the real folder a linked skill points at is refused" 'for grep { -l } bsd_glob("$q/$d/*", GLOB_QUOTE | GLOB_NOSORT);' 'for ();'
plant "the new text forms dropped" "the text forms" '
    . q!|(?:~|HOME\}?)/\.claude/(?:agents|skills|commands)\b|\.git/(?:method-|refs/remotes\b|packed-refs\b)!;' ';'
plant "G12 keeps one session" "G12: a session warned before another one is not warned again" "'.method/local/effort-warned', 20," "'.method/local/effort-warned', 1,"
# (round 1's second part)
r="a write is refused (5.7 repair loop 1, round 1's second part):"
ok="a read, or a write elsewhere, passes (5.7 repair loop 1, round 1's second part):"
plant "every sed script taken as plain" "$r sed -n '1~2w .claude/settings.json' notes.txt" 'my ($i, $n) = (0, length $s);' 'return 1;'
plant "a shortened --in-place not read" "$r sed --in-pl s/a/b/ .claude/settings.json" 'if ($x =~ /\A--i/) { $inplace = 1 }' "if (\$x eq '--in-place') { \$inplace = 1 }"
plant "a shortened sort --output not read" "$r sort --out=.claude/settings.json notes.txt" '/\A--(?:o|com)/' '/\A--output/'
plant "find -exec of a reading command refused" "$ok find . -name \"*.sh\" -exec grep -l guard {} +" 'for my $e (find_execs(@a)) { return 0 unless @$e && read_only({ words => $e }, $depth + 1) }' 'return 0 if find_execs(@a);'
plant "find -exec of any command taken as reading" "$r find .claude -name x -exec sed -i s/a/b/ {} +" 'for my $e (find_execs(@a)) { return 0 unless @$e && read_only({ words => $e }, $depth + 1) }' ''
plant "xargs with a reading command refused" "$ok find .claude/hooks/method -name \"*.sh\" | xargs grep -n guard" 'return $i > $#w ? 1 : read_only({ words => [@w[$i .. $#w]] }, $depth + 1);' 'return 0;'
plant "json.tool with an output file taken as reading" "$r python3 -m json.tool notes.txt .claude/settings.json" 'return @p <= 1 ? 1 : 0;' 'return 1;'
plant "a plain cp's sources counted as named" "$ok cp .claude/settings.json " '@look = grep { !($src{$_} && $src{$_}-- > 0) } @look;' ''
plant "cp -l's sources not counted" "$r cp -l .claude/settings.json linked.json" '!grep { /\A-[A-Za-z]*[ls]/ && !/\A--/ || /\A--(?:l|sy)/ } @w[1 .. $#w]' '1'
plant "a sed -i script's text counted" "$ok sed -i 's,old,.claude/settings.json,' notes.txt" '$sed_writes = $file || grep { !sed_plain($_) } @scripts;' '$sed_writes = 1;'
plant "git add counted as writing" "$ok git add .claude/settings.json" '  add for-each-ref' '  for-each-ref'
plant "patch with its file judged by the folder" "$ok patch notes.txt < x.diff" "if (@pos && defined \$d && -f (resolve(\$pos[0], \$d) // '')) {" 'if (0) {'
plant "git's relative settings paths read from the hook's folder" "from a subfolder, a .git folder there is not the project's" 'File::Spec->rel2abs(slashes($p), File::Spec->rel2abs(slashes($project)))' 'File::Spec->rel2abs(slashes($p))' '$from = File::Spec->rel2abs(slashes($from), File::Spec->rel2abs(slashes($project))) if defined $from && slashes($from) !~ m{\A/};' ''
plant "a file:// address not read" "an MCP tool given a file:// address of a protected path is refused" '$s =~ s{\Afile://(?:localhost)?(?=/)}{}i;' ''
PLANT_FILE=guard.pl plant "pushd with no folder read as cd home" "pushd with no folder leaves the folder unknown" "\$dir{\$scope} = \$w[0] eq 'pushd' ? undef : \$ENV{HOME}" '$dir{$scope} = $ENV{HOME}'
PLANT_FILE=guard.pl plant "cd's .. read through the link" "cd reads .. as written, before the link (as bash does)" 'if (defined $dir{$scope} && !grep { /\A-[A-Za-z]*P/ } @w[1 .. $#w]) {' 'if (0) {'
PLANT_FILE=guard.pl plant "NotebookEdit judged by file_path only" "NotebookEdit is judged by both its path fields" 'for my $k (qw(file_path notebook_path)) {' 'for my $k (qw(file_path)) {'

echo "plants: protected files: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
