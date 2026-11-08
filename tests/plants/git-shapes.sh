#!/usr/bin/env bash
# Plants for the guard's git list (step 5.6, G3): each line of
# .claude/hooks/method/git-shapes.txt is needed (with it removed, an example
# made from that line is refused), and each planted widening of the list,
# or of the push rule's code, turns tests/guard-git.test.sh red for its
# stated reason. Each runs in a throwaway copy of the repo.
# shellcheck disable=SC2016 # the plants are perl code: perl expands them
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/../lib.sh" || {
  echo "plants: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "plants: git list"
work=$(new_sandbox_dir) || abort_sandbox
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
git config --global user.email test@example.invalid
git config --global user.name Test
git config --global init.defaultBranch main
git config --global commit.gpgsign false
git init -q --bare "$work/origin.git"
git clone -q "$work/origin.git" "$work/proj" 2>/dev/null
(cd "$work/proj" && printf 'a\n' >a.txt && git add a.txt && git commit -qm one && git push -q origin main && git switch -qc task && git fetch -q origin) || abort_sandbox

# --- 1. every line of the list is needed ---
# For each shape, an example is made from its own words (the subcommand,
# its required options, one word for each word it needs); it must pass
# with the whole list and be refused with that line removed.
sb=$(make_sandbox) || abort_sandbox
# the check, as a perl file (a long $( ) breaks bash 3.2)
cat >"$work/lines.pl" <<'PERL'
  my ($sb, $proj) = @ARGV;
  require "$sb/method/scripts/method/lib/gitlist.pl";
  my $file = "$sb/method/.claude/hooks/method/git-shapes.txt";
  open my $h, "<", $file or die; my @lines = <$h>; close $h;
  my %v = (NAME => "user.email", ARG => "x", REMOTE => "origin", BRANCH => "main", NEWBRANCH => "fresh-branch", COMMIT => "HEAD", MAIN => "origin/main", REFNAME => "task");
  my $guard = "$sb/method/.claude/hooks/method/guard.sh";
  my $run = sub {
    my ($cmd) = @_;
    require JSON::PP;
    my $j = JSON::PP->new->encode({ tool_name => "Bash", tool_input => { command => $cmd }, cwd => $proj });
    local $ENV{CLAUDE_PROJECT_DIR} = $proj;
    chdir $proj;
    open my $p, "|-", "bash $guard >/dev/null 2>&1" or die;
    print $p $j;
    close $p;
    return $? >> 8;
  };
  my ($n, $bad) = (0, 0);
  for my $i (0 .. $#lines) {
    my ($s) = @{ (GitList::parse($lines[$i], "x"))[0] };
    next unless $s;
    $n++;
    my @w = ("git", @{ $s->{path} });
    for my $o (sort keys %{ $s->{opts} }) {
      my $spec = $s->{opts}{$o};
      next unless $spec->{required};
      push @w, $o;
      push @w, $v{ $spec->{type} // "ARG" } if $spec->{kind} eq "value";
    }
    for my $p (@{ $s->{pos} }) { push @w, $v{ $p->{type} } unless $p->{opt} }
    my $cmd = join " ", @w;
    if ($run->($cmd) != 0) { print "line ", $i + 1, ": its example ($cmd) is refused with the whole list\n"; $bad++; next }
    open my $o, ">", $file or die; print $o @lines[grep { $_ != $i } 0 .. $#lines]; close $o;
    my $code = $run->($cmd);
    open $o, ">", $file or die; print $o @lines; close $o;
    if ($code != 2) { print "line ", $i + 1, ": removed, its example ($cmd) still passes (another line covers it)\n"; $bad++ }
  }
  print "checked $n lines; $bad wrong\n";
PERL
out=$(perl "$work/lines.pl" "$sb" "$work/proj" 2>&1)
case "$out" in
  "checked "*"; 0 wrong") pass "every line of the git list is needed: removed, an example made from it is refused (${out#checked })" ;;
  *) fail "every line of the git list is needed" "$out" ;;
esac
drop_sandbox "$sb" || true

# --- 2. widenings and code plants ---
# plant NAME FILE REASON CODE: in a fresh copy, CODE (perl, on $_, FILE's
# text) changes FILE; tests/guard-git.test.sh must then fail with REASON
plant() {
  name=$1
  file=$2
  reason=$3
  code=$4
  sb=$(make_sandbox) || abort_sandbox
  if ! (cd "$sb" && CODE="$code" perl -0pi -e 'my $before = $_; eval "$ENV{CODE}; 1" or die $@; die "no change\n" if $_ eq $before' "$file"); then
    fail "$name: the plant did not apply, so the check result would mean nothing"
  else
    got=$(cd "$sb" && bash tests/guard-git.test.sh 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then
      fail "$name: the git test stayed green" "$(printf '%s\n' "$got" | tail -2)"
    elif ! printf '%s\n' "$got" | grep -F -q -- "FAIL  $reason"; then
      fail "$name: went red, but not for the stated reason ('$reason')" "$(printf '%s\n' "$got" | grep FAIL | head -3)"
    else
      pass "$name"
    fi
  fi
  drop_sandbox "$sb" || true
}
list=method/.claude/hooks/method/git-shapes.txt
guard=method/scripts/method/lib/guard.pl
plant "commit -n allowed" "$list" "not on the list: git commit -n -m x" 's/ !-n !--no-verify/ !--no-verify/'
plant "commit --no-verify allowed" "$list" "not on the list: git commit --no-verify -m x" 's/ !-n !--no-verify/ !-n/'
plant "diff --output allowed" "$list" "not on the list: git diff --output=x" 's/^diff -\* !--output ARG/diff -* ARG/m'
plant "restore without --staged" "$list" "not on the list: git restore a.txt" 's/^restore \+--staged ARG/restore --staged ARG/m'
plant "a switch with uncommitted changes" "$list" "switching branches while a tracked file has uncommitted changes is refused" 's/^switch BRANCH \@clean/switch BRANCH/m'
plant "a merge on main" "$list" "merging the remote's main while on main is refused" 's/ MAIN \@off-main/ MAIN/'
plant "a merge of any branch" "$list" "not on the list: git merge task" 's/ MAIN \@off-main/ ARG... \@off-main/'
plant "a new branch named main" "$list" "not on the list: git switch -c main" 's/\+-c=NEWBRANCH/+-c=/'
plant "a fetch with a refspec" "$list" "not on the list: git fetch origin main:refs/remotes/origin/x" 's/ REMOTE REFNAME\.\.\. ::/ REMOTE ARG... ::/'
plant "a cherry-pick of a range" "$list" "not on the list: git cherry-pick HEAD~2..HEAD" 's/^cherry-pick -x COMMIT/cherry-pick -x ARG.../m'
plant "a list line with no reason" "$list" "the method's git list reads" 's/\z/stash\n/'
plant "the push-alone check removed" "$guard" "push refused: git checkout main && git push origin HEAD" 's/return "a push may not share its Bash call with git \$sub, which can move what it sends; run the push on its own";/next;/'
plant "the symref check removed" "$guard" "a push of a branch that is a symbolic ref is refused (K3a)" 's/return "what this push sends is a symbolic ref, so where it goes cannot be told; push your task branch by its own name" if \$sym == 0;//'
plant "the effective settings read limited to the repository's file" "$guard" "a remote.*.mirror setting in the global settings refuses the push" 's/git_at\(\$dir, \x27config\x27, \x27--get-regexp\x27/git_at(\$dir, \x27config\x27, \x27--local\x27, \x27--get-regexp\x27/'
plant "GIT_ settings let through" "$guard" "a GIT_ setting is refused: GIT_DIR=../clone/.git git status" 's/    next unless \@bad;\n/    next;\n/'
# review round 1 of 5.6 (repair loop 1)
plant "a cd that may have failed is followed" "$guard" "a reset after a cd that may have failed is judged as this repository's" 's/\$dir\{\$scope\} = undef unless \(\$c->\{next_op\} \/\/ \x27\x27\) eq \x27&&\x27;//'
plant "an unknown remote taken for a folder" "$guard" "a push from a clone made in the same call is judged in full" 's/\} elsif \(\$target =~ m\{/} elsif (1 || \$target =~ m{/'
plant "git's own options read as its subcommand" "$guard" "git -C before a switch next to a push" 's/my \(\$sub, \@args\) = git_sub\(\@w\);/my (\$sub, \@args) = grep { !\/\\A-\/ } \@w[1 .. \$#w];/'
plant "reading forms next to a push refused" "$guard" "reading git commands next to a push pass" 's/      next if git_reads\(\$sub, \@args\);\n//'
plant "HOME on git let through" "$guard" "HOME set on a push" 's/if \(\(\$is_session \|\| \$sub eq \x27push\x27\) && grep/if (0 && grep/'
plant "~ in git -C not read as the home folder" "$guard" "git -C with ~ is read as the home folder" 's/elsif \(\$v =~ s\{\\A~/elsif (0 && \$v =~ s{\\A~/'
plant "a refusal names the push's remote" "$guard" "a push refusal names no word of the push (a URL can hold a token)" 's/"this push\x27s remote is not one of this repository\x27s remotes; \$form"/"\\"\$target\\" is not one of this repository\x27s remotes; \$form"/'
plant "git rm -f allowed" "$list" "git rm -f drops uncommitted changes: refused" 's/^rm -\* !-f !--force/rm -*/m'
plant "git worktree remove --force allowed" "$list" "git worktree remove --force is refused" 's/^worktree remove NAME/worktree remove -* NAME/m'
plant "a pull that can merge allowed" "$list" "a plain git pull is still refused (it can merge)" 's/^pull \+--ff-only/pull --ff-only/m'
plant "git init with a template allowed" "$list" "git init with a template is refused in this repository" 's/^init -b=/init --template= -b=/m'
plant "G8 judging commit only" "$guard" "a cherry-pick --continue while a mutate journal is there is refused (G8)" 's/\(\?:commit\|merge\|cherry-pick\|revert\|pull\)/(?:commit)/'

drop_sandbox "$work" || true
echo "plants: git list: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
