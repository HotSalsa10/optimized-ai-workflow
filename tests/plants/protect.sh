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
  if ! plant_control "$name" "$sb" tests/guard-protect.test.sh "$reason"; then
    : # plant_control said why
  elif ! (cd "$sb" && OLD="$3" NEW="$4" OLD2="${5:-}" NEW2="${6:-}" perl -0pi -e 'for my $k ("", "2") { my ($o, $n) = ($ENV{"OLD$k"}, $ENV{"NEW$k"}); next if $o eq ""; my $i = index($_, $o); die "missing\n" if $i < 0; die "twice\n" if index($_, $o, $i + 1) >= 0; substr($_, $i, length $o) = $n }' "method/scripts/method/lib/${PLANT_FILE:-protect.pl}"); then
    fail "$name: the plant did not apply, so the check result would mean nothing"
  else
    plant_judge "$name" "$sb" tests/guard-protect.test.sh "$reason" only
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
drop "your Claude Code agents, skills, commands, mods and plugins dropped" "Write to home/.claude/agents/x.md is refused" '"$c/$_->[0]"'
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
plant "the folder of the call not followed" "a write after a cd within the project is judged from the folder it moved to" 'return grep { !$seen{$_}++ } map { defined $_ ? $_ : $top } (@b ? @b : (undef));' 'return ($top);'

# --- git and G12 ---
plant "the git version check removed" "a cherry-pick of a commit that changes the guard is refused" 'next unless @$m;' 'next;'
plant "G12 warns at every call" "G12: one warning per session" 'return undef if $lines && grep { $_->[3] eq $hash } @$lines;' ''
plant "G12 warns inside subagents" "G12: a call inside a subagent gets no warning" "return undef if defined \$in->{agent_id} && !ref \$in->{agent_id} && \$in->{agent_id} ne '';" ''
plant "G12 warns at max" "G12: max gets no warning" '(?:xhigh|max)' '(?:xhigh)'
plant "G12's warning ignores the profile" "G12: silent at Balanced's own effort" '($want, $name) = ($row->{effortLevel}, $n);' ''

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
plant "find's own options taken for its end" "find's own options before its path do not hide the path" "    my @b = @a;
    while (@b && \$b[0] =~ /\\A-(?:[HLP]+|D|O[0-9]*)\\z/) { my \$o = shift @b; shift @b if \$o eq '-D' }" '    my @b = @a;'
plant "git -C not followed for git rm" "git -C: the paths git rm is given are read from that folder" '$gbase = $d if defined $d;' ''
plant "git --output read as reading" "git log --output into a protected file, from another repository, is refused" 'return 0 if grep { /\A--output(?:=|\z)/ } @w;' ''
plant "the version check run in the subfolder" "a switch run from a subfolder is judged over the whole tree" '  $dir = top_of($dir);
  return undef unless defined $dir;
' ''
plant "the commits after -- not judged" "a cherry-pick with -- before the commit is still judged" "push @pos, @r[ \$i + 1 .. \$#r ] unless \$sub eq 'checkout'; last" 'last'
drop "the remote's branches dropped" 'a write is refused (5.7 repair loop 1): echo x > .git/refs/remotes/origin/main' '"$common/refs/remotes"'
drop "git's packed refs dropped" "Write to git's packed refs is refused" '"$common/packed-refs"'
plant "a linked settings file's real path not protected" "Write to the real file a linked settings file points at is refused" 'for grep { -l } bsd_glob("$q/settings*.json", GLOB_QUOTE | GLOB_NOSORT);' 'for ();'
plant "a linked skill's real folder not protected" "Write into the real folder a linked skill points at is refused" 'for grep { -l } bsd_glob("$q/$d->[0]/*", GLOB_QUOTE | GLOB_NOSORT);' 'for ();'
plant "the new text forms dropped" "the text forms" '
    . q!|(?:~|HOME\}?)/\.claude/! . home_re() . q!|\.git/(?:method-|refs/remotes\b|packed-refs\b)!;' ';'
plant "G12 keeps one session" "G12: a session warned before another one is not warned again" "'.method/local/effort-warned', 20," "'.method/local/effort-warned', 1,"
# (the final review of step 5)
PLANT_FILE=guard.pl plant "one folder guessed after a cd that may have failed" "a write after a cd that may have failed is judged from the cd's folder too: cd .claude/hooks/method;" "Protect::judge_bash(\\@cmds, [cmd_dir_sets(" "Protect::judge_bash(\\@cmds, [cmd_dirs("
PLANT_FILE=guard.pl plant "a cd's folder dropped when it may have failed" "a write after a cd that may have failed is judged from the cd's folder too: cd .claude || exit 1;" "      push @next, @\$here unless (\$c->{next_op} // '') eq '&&';" "      @next = @\$here unless (\$c->{next_op} // '') eq '&&';"
plant "a for header not read" "a loop over protected paths that writes is refused: for d in .claude/hooks/method" "    push @look, @{ \$c->{header_text} || [] };" ''
PLANT_FILE=shell.pl plant "a readable for header dropped by the reader" "a loop over protected paths that writes is refused: for d in .claude/hooks/method" "        elsif (@{ \$cur->{header} || [] }) { push @cmds, \$cur }" ''
plant "xargs on a recursive listing not judged" "a bulk edit by xargs from the project's top is refused, as find -exec is: grep -rl master" '|| listed($cmds, $k, $base, $set);' ';'
plant "a write to a variable path let through" "a loop over protected paths that writes is refused: for f in .claude/settings.json; do echo x" "            return ('G6', \"this call names \$named->{what}, which Claude may only read, and writes to a path held in a variable\$NO\");" ''
plant "a pull not version-checked" "a pull whose upstream changed the guard is refused" "    @targets = (['@{upstream}']);" '    return ();'
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
PLANT_FILE=guard.pl plant "pushd with no folder read as cd home" "pushd with no folder leaves the folder unknown" "return \$w[0] eq 'pushd' ? undef : \$ENV{HOME}" 'return $ENV{HOME}'
PLANT_FILE=guard.pl plant "cd's .. read through the link" "cd reads .. as written, before the link (as bash does)" 'if (!grep { /\A-[A-Za-z]*P/ } @w[1 .. $#w]) {' 'if (0) {'
PLANT_FILE=guard.pl plant "NotebookEdit judged by file_path only" "NotebookEdit is judged by both its path fields" 'for my $k (qw(file_path notebook_path)) {' 'for my $k (qw(file_path)) {'

# --- the method's skills (step 6.3, S10): each feed of @METHOD_SKILLS ---
s="a method skill (6.3):"
# (since step 7.2 every feed is the method- prefix, step7.md S12;
# @METHOD_SKILLS feeds only lint-prompts, whose plants hold it)
drop "G6's method- skill prefix dropped from the set" "a method skill (7.2): Write to projü/.claude/skills/method-quick/SKILL.md is refused" '"$t/.claude/skills", '"'prefix'"
plant "the method- prefix read only for the skills folder's own entries (not deep)" "$s Write to projü/.claude/skills/method-start/SKILL.md is refused" "'method-', 1);" "'method-', 0);"
plant "the method's skills dropped from the version check (@SPECS)" "$s switching to a branch whose method-start SKILL.md differs is refused" ' .claude/skills);' ');'
plant "the version check keeps every skill, not only the method- ones (kept)" "a project skill (6.3): switching to a branch that changes only deploy's skill passes" 'index($k, $skills) != 0 || index($k, $method) == 0' '1'
plant "the version check keeps only the listed skills (@METHOD_SKILLS), not every method- one" "a method skill (7.2): switching to a branch that adds a method- skill is refused" 'index($k, $skills) != 0 || index($k, $method) == 0' 'index($k, $skills) != 0 || grep { index($k, key(".claude/skills/$_/")) == 0 } @METHOD_SKILLS'
plant "the method's skills dropped from the text forms (text_re)" "$s an interpreter's code naming" '/! . skills_re()' '/(?!)!'
PLANT_FILE=guard.pl plant "the method's skills dropped from the watched paths (\$WATCHED_PATH)" "$s perl -e that writes method-start's SKILL.md is refused" '|\.claude/skills/@{[ Protect::skills_re() ]}' ''

# --- /method-finish, and the mods and plugins folders (step 6b.4) ---
s="mods and plugins (6b.4):"
plant "dev-mods dropped from the home folders" "$s Write to home/.claude/dev-mods/s1/m/index.ts is refused" "['dev-mods', 'mods'], " ''
plant "plugins dropped from the home folders" "$s Write to home/.claude/plugins/x is refused" ", ['plugins', 'plugins']" ''
plant "CLAUDE_CONFIG_DIR not added" "$s Write to a mod under CLAUDE_CONFIG_DIR is refused" 'push @cfg, $ENV{CLAUDE_CONFIG_DIR} if' '0 && push @cfg, $ENV{CLAUDE_CONFIG_DIR} if'
# (step 6b's review, R21) one defect each: dev-mods dropped with the
# whole-name end kept, and the whole-name end dropped with dev-mods kept
plant "dev-mods dropped from the text forms" "the text forms: an interpreter's code naming" '. home_re() . q!' ". '(?:agents|skills|commands|plugins)[. ]*(?![A-Za-z0-9_.-])' . q!"
plant "the whole-name end dropped from the text forms (home_re)" "the text forms: a folder whose name only starts like one" ")[. ]*(?![A-Za-z0-9_.-])' }" ")' }"
# (step 6b's review, R18) a folder's name with dots or spaces after it
plant "trailing dots and spaces not read in the text forms (home_re)" "the text forms: a folder's name with dots or spaces after it" ")[. ]*(?![A-Za-z0-9_.-])' }" ")(?![A-Za-z0-9_.-])' }"

# --- the release's sync with --write (step 8.2) ---
plant "sync with --write let through" "sync with --write is refused: " "  if (defined(my \$why = release_write(\$cmds))) { return ('G6', \$why) }" '  if (0) { }'
plant "a sync dry run refused as if it wrote" "not a sync run with --write passes: bash " \
  "with --write, which installs, updates or takes out \$RELEASE_NO\" if grep { \$_ eq '--write' } @after;" "with --write, which installs, updates or takes out \$RELEASE_NO\" if 1;"
# (step 8's review, its repair: F5, F6, F17, F18)
plant "a project's own sync.sh, which takes no --to, refused" "not a sync run with --write passes: bash tools/sync.sh" \
  "        next unless grep { \$_ eq '--to' || /\\A--to=/ } @after;" '        1;'
plant "a word made at run time after the sync let through" "sync with --write is refused: W=--write" \
  "          if grep { /[\\\$\`]/ } @after;" '          if 0;'
plant "code given to a shell not read for the sync" "sync with --write is refused: bash <<" \
  "      if \$code =~ /sync\\.(?:sh|pl)\\b/i &&" "      if 0 && \$code =~ /sync\\.(?:sh|pl)\\b/i &&"
plant "a read-only command naming the words refused" "not a sync run with --write passes: echo bash sync.sh" \
  "    if (@w && !read_only(\$c)) {" '    if (@w) {'
plant "a here-document to cat read as code" "not a sync run with --write passes: cat <<" \
  "    next unless grep { /\\A(?:an inline program for|a pipe, here-document or here-string into|a program for \\S+ from) / } @{ \$c->{unread} || [] };" '    1;'

echo "plants: protected files: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
