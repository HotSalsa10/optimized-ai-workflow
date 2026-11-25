#!/usr/bin/env bash
# Tests for the release's sync, scripts/release/sync.sh and lib/sync.pl
# (step 7.3; M155; docs/plans/step7.md S2, S3, S6). Each case runs sync
# from a throwaway release, a git repository holding this repo's method/
# and scripts/release/ and tagged v0.7.0 (and a clone of it, tagged v0.7.1,
# with one file changed, one removed and one added, and one method key and
# one deny entry dropped and one added), into a throwaway project of its own.
# shellcheck disable=SC2016 # single-quoted perl code is expanded by perl
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: sync"
root=$(repo_root)
work=$(new_sandbox_dir) || abort_sandbox
T=$(printf '\t')
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
mkdir -p "$HOME"
git config --global user.name T
git config --global user.email t@example.invalid
git config --global commit.gpgsign false
git config --global core.autocrlf false
git config --global init.defaultBranch main

# the releases: rel at v0.7.0; rel71 a clone of it at v0.7.1, where why.md
# has one more line, a template is gone, docs/method/new.md is new, and the
# fragment drops autoMemoryEnabled and the deny entry for unarchive_session
# and adds one, Bash(added in v0.7.1)
rel="$work/rel"
rel71="$work/rel71"
if ! { mkdir -p "$rel/scripts" &&
  cp -R "$root/method" "$rel/method" &&
  cp -R "$root/scripts/release" "$rel/scripts/release" &&
  (cd "$rel" && git init -q && git add -A && git commit -q -m release && git tag v0.7.0) &&
  git clone -q "$rel" "$rel71" &&
  (
    cd "$rel71" || exit 1
    printf '\nA line added in v0.7.1.\n' >>method/docs/method/why.md &&
      git rm -q method/scripts/method/templates/RISKS.md.tmpl &&
      printf '# New in v0.7.1\n' >method/docs/method/new.md &&
      perl -0pi -e 's/"mcp__\*__unarchive_session",/"Bash(added in v0.7.1)",/; s/\n *"autoMemoryEnabled": false,//' method/settings.fragment.json &&
      ! grep -q -e unarchive_session -e autoMemoryEnabled method/settings.fragment.json && grep -q 'added in v0.7.1' method/settings.fragment.json &&
      git add -A && git commit -q -m v0.7.1 && git tag v0.7.1
  ); }; then
  abort_sandbox
fi

# can_link: links can be made here (Git Bash may make a copy instead)
can_link=0
if ln -s target "$work/link-probe" 2>/dev/null && [ -L "$work/link-probe" ]; then can_link=1; fi
rm -f "$work/link-probe"

# proj NAME: a new project (a git repository with one commit); its path in p
proj() {
  p="$work/p-$1"
  rm -rf "$p"
  mkdir -p "$p" && (cd "$p" && git init -q && printf 'hello\n' >README.md && git add -A && git commit -q -m init)
}

# sync SRC DIR ARG...: the sync.sh of the release SRC, into DIR; sets out
# and code
sync() {
  s_src=$1
  s_to=$2
  shift 2
  out=$(bash "$s_src/scripts/release/sync.sh" --to "$s_to" "$@" 2>&1)
  code=$?
}

# cut AT ARG...: rel71's sync into p with --write and ARG..., run as sync.sh
# runs it but stopped (exit 9) just before it renames its new copy onto the
# path ending in AT, so that copy (the path, .sync- and a number) is left
# as a run cut off there leaves it; sets out and code
cut() {
  c_at=$1
  shift
  c_prog='BEGIN { *CORE::GLOBAL::rename = sub { exit 9 if $_[1] =~ /\Q$ENV{CUT_AT}\E\z/; CORE::rename($_[0], $_[1]) } }
    my $f = shift; do $f; die $@ if $@'
  out=$(CUT_AT="$c_at" perl -e "$c_prog" "$rel71/scripts/release/lib/sync.pl" "$rel71" --to "$p" --write "$@" 2>&1)
  code=$?
}

# leftovers DIR: the files a cut-off write left under DIR, one per line
leftovers() {
  (cd "$1" && find . -name '*.sync-*' ! -path './.git/*')
}

# snap DIR: every entry under DIR but .git, with each file's hash and mode
snap() {
  perl -MFile::Find -MDigest::SHA -e 'my $r = shift; my @l;
    find({ no_chdir => 1, wanted => sub {
      if (m{/\.git\z}) { $File::Find::prune = 1; return }
      return if $_ eq $r;
      my $rel = substr($_, length($r) + 1);
      if (-l $_) { push @l, "L $rel " . readlink($_) }
      elsif (-f _) { push @l, "F $rel " . Digest::SHA->new(256)->addfile($_, "b")->hexdigest . " " . sprintf("%o", (stat _)[2] & 0777) }
      elsif (-d _) { push @l, "D $rel" } } }, $r);
    print "$_\n" for sort @l' "$1"
}

# findings DIR: what the installed lib/lock.pl's verify finds, one per line
findings() {
  (cd "$1" && perl -e 'require "./scripts/method/lib/lock.pl"; my $v = Lock::verify("."); print "$_->[1]\n" for @{ $v->{findings} }') 2>&1
}

# jget FILE EXPR: the perl EXPR on $d, the decoded JSON FILE, printed
jget() {
  perl -MJSON::PP -e 'open my $h, "<", $ARGV[0] or die; my $d = JSON::PP->new->decode(do { local $/; <$h> }); my $v = eval $ARGV[1]; die $@ if $@; print ref $v ? JSON::PP->new->canonical->encode($v) : (defined $v ? $v : "(undef)"), "\n"' "$1" "$2"
}

# has TEXT...: out holds each TEXT; else prints the missing ones
has() {
  h_missing=""
  for t in "$@"; do
    case "$out" in *"$t"*) ;; *) h_missing="$h_missing [$t]" ;; esac
  done
  [ -z "$h_missing" ]
}

# ok NAME: a pass; no NAME [DETAIL]: a fail, with DETAIL or the exit code
# and the end of sync's output
ok() { pass "$1"; }
no() { fail "$1" "${2:-exit $code: $(printf '%s\n' "$out" | grep -v -E '^sync: (install|unchanged|update|remove) ' | tail -8)}"; }

# settings JSON: the project's .claude/settings.json before the install
settings() {
  mkdir -p "$p/.claude" && printf '%s\n' "$1" >"$p/.claude/settings.json"
}

# --- a first install, and a second run ---
n="first install: the method's files, the merged settings, the blocks and method.lock, and method-files finds nothing"
if wanted_any "$n" "a dry run writes nothing" "a second run gives the same bytes"; then
  proj first
  before=$(snap "$p")
  sync "$rel" "$p"
  if [ "$code" -eq 0 ] && has "dry run - nothing written" "install   scripts/method/lib/lock.pl" && [ "$(snap "$p")" = "$before" ]; then ok "a dry run writes nothing"; else no "a dry run writes nothing"; fi
  sync "$rel" "$p" --write
  f=$(findings "$p")
  if [ "$code" -eq 0 ] && has "WROTE v0.7.0, profile best" && [ -z "$f" ] &&
    [ "$(sed -n 1p "$p/scripts/method/method.lock")" = "version${T}v0.7.0" ] &&
    [ "$(jget "$p/.claude/settings.json" '$d->{model}')" = claude-opus-5-5 ] &&
    cmp -s "$root/method/settings.fragment.json" "$p/scripts/method/settings.method.json" &&
    cmp -s "$root/method/.claude/hooks/method/guard.sh" "$p/.claude/hooks/method/guard.sh" &&
    grep -q -x '.method/local/' "$p/.gitignore" && grep -q -x '.claude/settings.local.json' "$p/.gitignore" && grep -q -x '\*.ps1 text eol=crlf' "$p/.gitattributes" &&
    [ ! -e "$p/.method/local/sync-in-progress" ] && [ ! -e "$p/method" ] && [ ! -e "$p/settings.fragment.json" ]; then
    ok "$n"
  else
    no "$n" "exit $code; findings: $f; $(printf '%s\n' "$out" | tail -3)"
  fi
  before=$(snap "$p")
  sync "$rel" "$p" --write
  if [ "$code" -eq 0 ] && has "plan: 0 install, 0 update, " ", 0 remove, 0 conflict" && [ "$(snap "$p")" = "$before" ]; then ok "a second run gives the same bytes"; else no "a second run gives the same bytes"; fi
fi

# --- an edited method file ---
n="an edited method file is refused and named, nothing written"
if wanted "$n"; then
  proj edited
  sync "$rel" "$p" --write
  printf '# a local edit\n' >>"$p/scripts/method/status.sh"
  before=$(snap "$p")
  sync "$rel71" "$p" --write
  if [ "$code" -eq 1 ] && has "conflict  scripts/method/status.sh (changed since method.lock; sync never replaces it)" "REFUSED - 1 conflict; nothing was written" &&
    [ "$(snap "$p")" = "$before" ]; then ok "$n"; else no "$n"; fi
fi
n="a file there before the method, with other content, is refused on first install"
if wanted "$n"; then
  proj before
  mkdir -p "$p/docs/method" && printf 'mine\n' >"$p/docs/method/why.md"
  before=$(snap "$p")
  sync "$rel" "$p" --write
  if [ "$code" -eq 1 ] && has "conflict  docs/method/why.md (there before the method, with other content" && [ "$(snap "$p")" = "$before" ]; then ok "$n"; else no "$n"; fi
fi

# --- the project's own settings ---
own='{"cleanupPeriodDays": 30, "permissions": {"allow": ["Bash(npm test)"], "deny": ["Bash(rm -rf /)", "mcp__*__merge_pull_request"]},
 "hooks": {"PostToolUse": [{"matcher": "Write", "hooks": [{"type": "command", "command": "bash tools/format.sh"}]}]}}'
n="a project hook, allow rule, own deny rule and own key survive"
if wanted "$n"; then
  proj own
  settings "$own"
  sync "$rel" "$p" --write --keep PostToolUse
  c1=$code
  out1=$out
  s="$p/.claude/settings.json"
  got=$(jget "$s" '[$d->{cleanupPeriodDays}, $d->{permissions}{allow}, $d->{hooks}{PostToolUse}, scalar(grep { $_ eq "Bash(rm -rf /)" } @{ $d->{permissions}{deny} }), scalar(grep { $_ eq "mcp__*__merge_pull_request" } @{ $d->{permissions}{deny} }), scalar @{ $d->{permissions}{deny} }, $d->{permissions}{deny}[0], scalar @{ $d->{hooks}{PreToolUse} }]')
  want='[30,["Bash(npm test)"],[{"hooks":[{"command":"bash tools/format.sh","type":"command"}],"matcher":"Write"}],1,1,10,"mcp__*__merge_pull_request",3]'
  f=$(findings "$p")
  sync "$rel71" "$p" --write
  got71=$(jget "$s" '[$d->{cleanupPeriodDays}, $d->{permissions}{allow}, $d->{hooks}{PostToolUse}, scalar(grep { $_ eq "Bash(rm -rf /)" } @{ $d->{permissions}{deny} }), scalar(grep { $_ eq "mcp__*__merge_pull_request" } @{ $d->{permissions}{deny} }), scalar @{ $d->{permissions}{deny} }, $d->{permissions}{deny}[0], scalar @{ $d->{hooks}{PreToolUse} }]')
  if [ "$c1" -eq 0 ] && [ "$code" -eq 0 ] && [ "$got" = "$want" ] && [ "$got71" = "$want" ] && [ -z "$f" ] &&
    case "$out1" in *"note      .claude/settings.json is written in one layout"*) true ;; *) false ;; esac; then ok "$n"; else no "$n" "exit $c1 then $code; got $got; after the update $got71; findings: $f"; fi
fi
n="a method key and deny entry the release drops are removed on an update, the project's own kept"
if wanted "$n"; then
  proj dropped
  settings '{"permissions": {"deny": ["Bash(own)"]}}'
  sync "$rel" "$p" --write
  c1=$code
  sync "$rel71" "$p" --write
  got=$(jget "$p/.claude/settings.json" '[exists $d->{autoMemoryEnabled} ? 1 : 0, scalar(grep { $_ eq "mcp__*__unarchive_session" } @{ $d->{permissions}{deny} }), scalar(grep { $_ eq "Bash(added in v0.7.1)" } @{ $d->{permissions}{deny} }), scalar(grep { $_ eq "Bash(own)" } @{ $d->{permissions}{deny} }), scalar @{ $d->{permissions}{deny} }]')
  f=$(findings "$p")
  if [ "$c1" -eq 0 ] && [ "$code" -eq 0 ] && [ "$got" = '[0,0,1,1,10]' ] && [ -z "$f" ]; then ok "$n"; else no "$n" "exit $c1 then $code; got $got; findings: $f"; fi
fi
n="a settings.json that starts with a byte-order mark is read"
if wanted "$n"; then
  proj bom
  mkdir -p "$p/.claude" && printf '\357\273\277{"cleanupPeriodDays": 3}\n' >"$p/.claude/settings.json"
  sync "$rel" "$p" --write
  if [ "$code" -eq 0 ] && [ "$(jget "$p/.claude/settings.json" '$d->{cleanupPeriodDays}')" = 3 ] && [ "$(head -c 1 "$p/.claude/settings.json")" = '{' ]; then ok "$n"; else no "$n"; fi
fi
n="the project's own numbers keep their value"
if wanted "$n"; then
  proj numbers
  settings '{"cleanupPeriodDays": 12345678901234567890123, "x": 1.5}'
  sync "$rel" "$p" --write
  if [ "$code" -eq 0 ] && grep -q '^  "cleanupPeriodDays": 12345678901234567890123,$' "$p/.claude/settings.json" && grep -q '^  "x": 1.5$' "$p/.claude/settings.json"; then ok "$n"; else no "$n" "exit $code; $(grep -e cleanup -e '"x"' "$p/.claude/settings.json" 2>&1)"; fi
fi
n="hooks in a shape other than lists of groups are refused, nothing written"
if wanted "$n"; then
  proj hook-shape
  settings '{"hooks": {"SessionStart": {"x": 1}, "PreToolUse": [{"matcher": "Bash", "hooks": {"type": "command", "command": "bash tools/x.sh"}}]}}'
  before=$(snap "$p")
  sync "$rel" "$p" --write
  if [ "$code" -eq 1 ] && has "conflict  .claude/settings.json (its hooks.SessionStart is not a list of hook groups" "conflict  .claude/settings.json (its hooks.PreToolUse is not a list of hook groups" &&
    [ "$(snap "$p")" = "$before" ]; then ok "$n"; else no "$n"; fi
fi
n="a relative --to names the folder sync is run from"
if wanted "$n"; then
  proj relative
  out=$(cd "$p" && bash "$rel/scripts/release/sync.sh" --to . --write 2>&1)
  code=$?
  if [ "$code" -eq 0 ] && has "WROTE v0.7.0, profile best: " "method files written, 0 removed, .claude/settings.json, the .gitattributes block, the .gitignore block written, method.lock written last" && [ -z "$(findings "$p")" ]; then ok "$n"; else no "$n"; fi
fi
n="an exported CDPATH does not change the folder sync.sh finds itself in"
if wanted "$n"; then
  proj cdpath
  out=$(cd "$rel" && CDPATH=. bash scripts/release/sync.sh --to "$p" 2>&1)
  code=$?
  if [ "$code" -eq 0 ] && has "dry run - nothing written"; then ok "$n"; else no "$n"; fi
fi
n="a folder sync cannot make gives its FAIL line and exit 1"
if wanted "$n"; then
  proj mkdir-fail
  # (make_path dies as it does when a folder cannot be made, for root too)
  m_prog='require File::Path; no warnings "redefine";
    *File::Path::make_path = sub { die "mkdir $_[0]/x: Permission denied at line 1.\n" if $_[0] =~ m{/scripts/method\z}; File::Path::mkpath(@_) };
    my $f = shift; do $f; die $@ if $@'
  out=$(perl -e "$m_prog" "$rel/scripts/release/lib/sync.pl" "$rel" --to "$p" --write 2>&1)
  code=$?
  if [ "$code" -eq 1 ] && has "FAIL - cannot make the folder for scripts/method/" "run sync again with the same options to finish it"; then ok "$n"; else no "$n"; fi
fi
n="a conflicting floor key is refused on first install, nothing written"
if wanted "$n"; then
  proj floor
  settings '{"disableAllHooks": true, "model": "claude-sonnet-5-5"}'
  before=$(snap "$p")
  sync "$rel" "$p" --write
  if [ "$code" -eq 1 ] && has "the project sets the method key disableAllHooks to another value than the release's" \
    "the project sets the method key model to another value than the release's; remove it from the file, or choose the --profile whose row sets it" \
    "the project sets the method key disableAllHooks to another value than the release's; remove it from the file)" "take out each method key the project set" && [ "$(snap "$p")" = "$before" ]; then ok "$n"; else no "$n"; fi
fi
n="a hook naming the method's folder that is not the release's is refused on first install"
if wanted "$n"; then
  proj fakehook
  settings '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "bash .claude/hooks/method/mine.sh"}]}]}}'
  sync "$rel" "$p" --write
  if [ "$code" -eq 1 ] && has "a hook on Stop names .claude/hooks/method/ but is not one of the release's"; then ok "$n"; else no "$n"; fi
fi

# --- what a first install refuses unless kept: a PreToolUse hook, a
# SubagentStart hook (A79), a PostToolUse hook (A80), claudeMdExcludes,
# statusLine, gcpAuthRefresh, proxyAuthHelper, subagentStatusLine ---
for item in 'PreToolUse|{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash tools/check.sh"}]}]}}|1 PreToolUse hook of the project'"'"'s own' \
  'SubagentStart|{"hooks": {"SubagentStart": [{"hooks": [{"type": "command", "command": "bash tools/check.sh"}]}]}}|1 SubagentStart hook of the project'"'"'s own' \
  'PostToolUse|{"hooks": {"PostToolUse": [{"matcher": "Read", "hooks": [{"type": "command", "command": "bash tools/check.sh"}]}]}}|1 PostToolUse hook of the project'"'"'s own' \
  'claudeMdExcludes|{"claudeMdExcludes": ["docs/**"]}|claudeMdExcludes' \
  'statusLine|{"statusLine": {"type": "command", "command": "bash tools/line.sh"}}|statusLine' \
  'gcpAuthRefresh|{"gcpAuthRefresh": "bash tools/x.sh"}|gcpAuthRefresh' \
  'proxyAuthHelper|{"proxyAuthHelper": "bash tools/x.sh"}|proxyAuthHelper' \
  'subagentStatusLine|{"subagentStatusLine": {"type": "command", "command": "bash tools/line.sh"}}|subagentStatusLine'; do
  key=${item%%|*}
  rest=${item#*|}
  js=${rest%%|*}
  text=${rest#*|}
  n="a project's $key is refused on first install"
  if wanted "$n"; then
    proj "refuse-$key"
    settings "$js"
    before=$(snap "$p")
    sync "$rel" "$p" --write
    if [ "$code" -eq 1 ] && has "conflict  .claude/settings.json ($text: a first install refuses it unless you name it with --keep $key)" &&
      [ "$(snap "$p")" = "$before" ]; then ok "$n"; else no "$n"; fi
  fi
  n="a project's $key is kept and named with --keep"
  if wanted "$n"; then
    proj "keep-$key"
    settings "$js"
    sync "$rel" "$p" --write --keep "$key"
    got=$(jget "$p/.claude/settings.json" '$d->{'"$key"'} ? 1 : 0')
    case $key in PreToolUse | SubagentStart | PostToolUse) got=$(jget "$p/.claude/settings.json" 'scalar grep { $_->{hooks}[0]{command} eq "bash tools/check.sh" } @{ $d->{hooks}{'"$key"'} }') ;; esac
    if [ "$code" -eq 0 ] && [ "$got" = 1 ] && has "kept      $text, kept as --keep $key asked"; then ok "$n"; else no "$n" "exit $code, got $got: $(printf '%s\n' "$out" | tail -4)"; fi
  fi
done
n="--keep with a name sync does not know is bad usage"
if wanted "$n"; then
  proj keep-bad
  sync "$rel" "$p" --keep model
  if [ "$code" -eq 2 ] && has "usage - --keep names one of:"; then ok "$n"; else no "$n"; fi
fi

# --- extra files, links, removed files ---
n="an extra file under the method's paths is refused"
if wanted "$n"; then
  proj extra
  sync "$rel" "$p" --write
  printf 'mine\n' >"$p/.claude/rules/method/zz.md"
  before=$(snap "$p")
  sync "$rel71" "$p" --write
  if [ "$code" -eq 1 ] && has "conflict  .claude/rules/method/zz.md (not in method.lock" && [ "$(snap "$p")" = "$before" ]; then ok "$n"; else no "$n"; fi
fi
n="a symlinked .claude/hooks is refused"
if wanted "$n"; then
  if [ "$can_link" -eq 0 ]; then
    skip "$n (this system cannot make links)"
  else
    proj link
    mkdir -p "$work/elsewhere" "$p/.claude" && ln -s "$work/elsewhere" "$p/.claude/hooks"
    before=$(snap "$p")
    sync "$rel" "$p" --write
    if [ "$code" -eq 1 ] && has "conflict  .claude/hooks/method/" "(a link, or a file where a folder belongs, on its path (.claude/hooks))" &&
      [ "$(snap "$p")" = "$before" ] && [ -z "$(ls "$work/elsewhere")" ]; then ok "$n"; else no "$n"; fi
  fi
fi
n="a removed file is removed when unchanged"
if wanted "$n"; then
  proj removed
  sync "$rel" "$p" --write
  sync "$rel71" "$p" --write
  f=$(findings "$p")
  if [ "$code" -eq 0 ] && has "remove    scripts/method/templates/RISKS.md.tmpl" "update    docs/method/why.md" "install   docs/method/new.md" "WROTE v0.7.1" &&
    [ ! -e "$p/scripts/method/templates/RISKS.md.tmpl" ] && [ -z "$f" ] && [ "$(sed -n 1p "$p/scripts/method/method.lock")" = "version${T}v0.7.1" ]; then ok "$n"; else no "$n" "exit $code; findings $f; $(printf '%s\n' "$out" | tail -3)"; fi
fi
n="a changed file the release removes is refused"
if wanted "$n"; then
  proj removed-changed
  sync "$rel" "$p" --write
  printf 'mine\n' >>"$p/scripts/method/templates/RISKS.md.tmpl"
  sync "$rel71" "$p" --write
  if [ "$code" -eq 1 ] && has "conflict  scripts/method/templates/RISKS.md.tmpl (changed since method.lock and gone from the release"; then ok "$n"; else no "$n"; fi
fi

# --- profiles ---
n="a Budget project updated without --profile stays Budget"
if wanted "$n"; then
  proj budget
  sync "$rel" "$p" --write --profile budget
  m1=$(jget "$p/.claude/settings.json" '$d->{model} . " " . $d->{effortLevel}')
  sync "$rel71" "$p" --write
  m2=$(jget "$p/.claude/settings.json" '$d->{model} . " " . $d->{effortLevel} . " " . join(",", @{ $d->{availableModels} })')
  f=$(findings "$p")
  if [ "$code" -eq 0 ] && [ "$m1" = "claude-sonnet-5-5 medium" ] && [ "$m2" = "claude-sonnet-5-5 medium claude-opus-5-5,claude-sonnet-5-5" ] &&
    [ "$(sed -n 3p "$p/scripts/method/method.lock")" = "profile${T}budget" ] && [ -z "$f" ]; then ok "$n"; else no "$n" "exit $code; $m1; $m2; findings $f"; fi
fi
n="an update with --profile changes the profile"
if wanted "$n"; then
  proj to-balanced
  sync "$rel" "$p" --write
  sync "$rel71" "$p" --write --profile balanced
  m=$(jget "$p/.claude/settings.json" '$d->{model} . " " . $d->{effortLevel}')
  if [ "$code" -eq 0 ] && [ "$m" = "claude-opus-5-5 medium" ] && [ "$(sed -n 3p "$p/scripts/method/method.lock")" = "profile${T}balanced" ] && [ -z "$(findings "$p")" ]; then ok "$n"; else no "$n"; fi
fi
n="an unknown profile is refused"
if wanted "$n"; then
  proj noprofile
  sync "$rel" "$p" --write --profile turbo
  if [ "$code" -eq 1 ] && has "the profile turbo is not one this release knows (best balanced budget)" && [ ! -e "$p/scripts" ]; then ok "$n"; else no "$n"; fi
fi

# --- a run that was cut off ---
n="an interrupted run is finished by a re-run"
if wanted "$n"; then
  proj cut
  sync "$rel" "$p" --write
  # what a v0.7.1 run cut off after two files leaves: its marker, one file
  # updated, one installed, the old lock
  mkdir -p "$p/.method/local" && printf 'v0.7.1\n' >"$p/.method/local/sync-in-progress"
  cp "$rel71/method/docs/method/why.md" "$p/docs/method/why.md"
  cp "$rel71/method/docs/method/new.md" "$p/docs/method/new.md"
  sync "$rel71" "$p" --write
  f=$(findings "$p")
  if [ "$code" -eq 0 ] && has "an earlier run of v0.7.1 was cut off; this run finishes it" "unchanged docs/method/why.md" "unchanged docs/method/new.md" "remove    scripts/method/templates/RISKS.md.tmpl" &&
    [ ! -e "$p/.method/local/sync-in-progress" ] && [ -z "$f" ] && [ "$(sed -n 1p "$p/scripts/method/method.lock")" = "version${T}v0.7.1" ]; then ok "$n"; else no "$n" "exit $code; findings $f; $(printf '%s\n' "$out" | tail -4)"; fi
fi
n="settings the cut-off run already wrote are accepted by the re-run"
if wanted "$n"; then
  proj cut-settings
  sync "$rel" "$p" --write --profile budget
  # a run to balanced that wrote the settings, then stopped before the lock:
  # its settings come from the same run on a copy
  rm -rf "$work/cut-copy" && cp -R "$p" "$work/cut-copy"
  sync "$rel71" "$work/cut-copy" --write --profile balanced
  mkdir -p "$p/.method/local" && printf 'v0.7.1\n' >"$p/.method/local/sync-in-progress"
  cp "$work/cut-copy/.claude/settings.json" "$p/.claude/settings.json"
  sync "$rel71" "$p" --write --profile balanced
  if [ "$code" -eq 0 ] && [ -z "$(findings "$p")" ] && [ "$(sed -n 3p "$p/scripts/method/method.lock")" = "profile${T}balanced" ]; then ok "$n"; else no "$n"; fi
fi
n="a run cut off while writing the settings is finished by a re-run, which removes what it left"
if wanted "$n"; then
  proj cut-at-settings
  sync "$rel" "$p" --write
  cut /.claude/settings.json
  c1=$code
  l1=$(leftovers "$p")
  sync "$rel71" "$p" --write
  f=$(findings "$p")
  if [ "$c1" -eq 9 ] && [ -n "$l1" ] && [ "$code" -eq 0 ] && has "(left by the run that was cut off)" && [ -z "$(leftovers "$p")" ] && [ -z "$f" ] &&
    [ "$(sed -n 1p "$p/scripts/method/method.lock")" = "version${T}v0.7.1" ]; then ok "$n"; else no "$n" "exit $c1 then $code; left $l1; findings $f; $(printf '%s\n' "$out" | grep -v '^sync: unchanged' | tail -6)"; fi
fi
n="a run cut off while writing a method file is finished by a re-run with its --profile, which the re-run names"
if wanted "$n"; then
  proj cut-at-file
  sync "$rel" "$p" --write
  cut /scripts/method/settings.method.json --profile budget
  c1=$code
  l1=$(leftovers "$p")
  sync "$rel71" "$p" --write
  c2=$code
  out2=$out
  sync "$rel71" "$p" --write --profile budget
  f=$(findings "$p")
  if [ "$c1" -eq 9 ] && [ -n "$l1" ] && [ "$c2" -eq 1 ] && [ "$code" -eq 0 ] && [ -z "$(leftovers "$p")" ] && [ -z "$f" ] &&
    case "$out2" in *"an earlier run of v0.7.1 with --profile budget was cut off; this run finishes it when given the same --profile and --keep as that run"*) true ;; *) false ;; esac &&
    [ "$(sed -n 3p "$p/scripts/method/method.lock")" = "profile${T}budget" ]; then ok "$n"; else no "$n" "exit $c1, $c2, then $code; left $l1; findings $f; $(printf '%s\n' "$out2" | grep -v '^sync: unchanged' | tail -6)"; fi
fi
n="a run cut off while writing method.lock is finished by a re-run, which removes what it left"
if wanted "$n"; then
  proj cut-at-lock
  sync "$rel" "$p" --write
  cut /scripts/method/method.lock
  c1=$code
  l1=$(leftovers "$p")
  sync "$rel71" "$p" --write
  f=$(findings "$p")
  if [ "$c1" -eq 9 ] && [ -n "$l1" ] && [ "$code" -eq 0 ] && has "(left by the run that was cut off)" && [ -z "$(leftovers "$p")" ] && [ -z "$f" ] &&
    [ "$(sed -n 1p "$p/scripts/method/method.lock")" = "version${T}v0.7.1" ]; then ok "$n"; else no "$n" "exit $c1 then $code; left $l1; findings $f; $(printf '%s\n' "$out" | grep -v '^sync: unchanged' | tail -6)"; fi
fi
n="method keys changed by hand are refused on an update"
if wanted "$n"; then
  proj keys-changed
  sync "$rel" "$p" --write
  perl -MJSON::PP -i -0pe '$d = JSON::PP->new->decode($_); $d->{permissions}{deny} = [grep { $_ ne "RemoteTrigger" } @{ $d->{permissions}{deny} }]; $_ = JSON::PP->new->canonical->pretty->encode($d)' "$p/.claude/settings.json"
  before=$(snap "$p")
  sync "$rel71" "$p" --write
  if [ "$code" -eq 1 ] && has "the method's deny entry RemoteTrigger is missing from .claude/settings.json" && [ "$(snap "$p")" = "$before" ]; then ok "$n"; else no "$n"; fi
fi

# --- the managed blocks ---
n="the method blocks keep the text around them, and a broken block is refused"
if wanted "$n"; then
  proj blocks
  printf 'node_modules/\n# >>> method\nold\n# <<< method\nbuild/' >"$p/.gitignore"
  printf '*.png binary\n' >"$p/.gitattributes"
  sync "$rel" "$p" --write
  c1=$code
  g=$(cat "$p/.gitignore")
  a=$(cat "$p/.gitattributes")
  proj blocks-broken
  printf '# >>> method\n.method/local/\n' >"$p/.gitignore"
  sync "$rel" "$p" --write
  if [ "$c1" -eq 0 ] && [ "$g" = "$(printf 'node_modules/\n# >>> method\n.method/local/\n.claude/settings.local.json\n# <<< method\nbuild/')" ] &&
    [ "$a" = "$(printf '# >>> method\n* text=auto eol=lf\n*.cmd text eol=crlf\n*.bat text eol=crlf\n*.ps1 text eol=crlf\n# <<< method\n*.png binary')" ] &&
    [ "$code" -eq 1 ] && has 'conflict  .gitignore (its method block is broken'; then ok "$n"; else no "$n" "exit $c1 then $code; .gitignore: $g; .gitattributes: $a"; fi
fi

n="a new .gitattributes block goes at the top, so the project's own line-end rules still win"
if wanted "$n"; then
  proj attributes
  printf '*.sln text eol=crlf\n*.fixture -text\n' >"$p/.gitattributes"
  sync "$rel" "$p" --write
  got=$(cd "$p" && git check-attr text eol -- a.sln b.fixture c.sh 2>&1 | tr '\n' ';')
  if [ "$code" -eq 0 ] && [ "$(head -1 "$p/.gitattributes")" = '# >>> method' ] &&
    [ "$got" = 'a.sln: text: set;a.sln: eol: crlf;b.fixture: text: unset;b.fixture: eol: lf;c.sh: text: auto;c.sh: eol: lf;' ]; then ok "$n"; else no "$n" "exit $code; check-attr: $got"; fi
fi

n="a .gitattributes that starts with a byte-order mark keeps it first, so its own first rule still works"
if wanted "$n"; then
  proj attributes-bom
  printf '\357\273\277*.csv -text\n' >"$p/.gitattributes"
  sync "$rel" "$p" --write
  c1=$code
  got=$(cd "$p" && git check-attr text -- a.csv 2>&1)
  sync "$rel" "$p" --write
  if [ "$c1" -eq 0 ] && [ "$(head -c 15 "$p/.gitattributes")" = "$(printf '\357\273\277# >>> method')" ] && [ "$got" = 'a.csv: text: unset' ] &&
    [ "$code" -eq 0 ] && has "unchanged .gitattributes (the method block)"; then ok "$n"; else no "$n" "exit $c1 then $code; check-attr: $got"; fi
fi

# --- what git ignores ---
n="a path sync writes that git ignores is refused, naming the rule, nothing written"
if wanted "$n"; then
  proj ignored
  printf '.claude/\n*.lock\n' >"$p/.gitignore"
  before=$(snap "$p")
  sync "$rel" "$p" --write
  c1=$code
  out1=$out
  ok1=0
  if [ "$c1" -eq 1 ] && has "conflict  .claude/settings.json (git ignores it (.gitignore line 1: .claude/), so a commit would leave it out" \
    "conflict  .claude/hooks/method/guard.sh (git ignores it (.gitignore line 1: .claude/)" \
    "conflict  scripts/method/method.lock (git ignores it (.gitignore line 2: *.lock)" && [ "$(snap "$p")" = "$before" ]; then ok1=1; fi
  # (what the project ignores beside the method's paths, .method/ among
  # them, is no conflict, nor is a path a ! line takes back)
  proj ignored-other
  printf '.method/\nnode_modules/\n*.lock\n!scripts/method/method.lock\n' >"$p/.gitignore"
  sync "$rel" "$p" --write
  if [ "$ok1" -eq 1 ] && [ "$code" -eq 0 ]; then ok "$n"; else no "$n" "exit $c1 then $code; $(printf '%s\n' "$out1" | grep conflict | head -3)"; fi
fi

# --- an error sync did not foresee ---
n="an error sync did not foresee is a refusal with exit 1, nothing written"
if wanted "$n"; then
  proj huge-number
  settings '{"x": 1e20000}'
  before=$(snap "$p")
  sync "$rel" "$p" --write
  if [ "$code" -eq 1 ] && has "REFUSED - sync stopped on an error: " "; nothing was written" && [ "$(snap "$p")" = "$before" ]; then ok "$n"; else no "$n"; fi
fi

# --- the source ---
n="an untagged source is refused"
if wanted "$n"; then
  git clone -q "$rel" "$work/untagged" && (cd "$work/untagged" && printf 'x\n' >>method/docs/method/why.md && git commit -q -am untagged)
  proj untagged
  sync "$work/untagged" "$p" --write
  if [ "$code" -eq 1 ] && has "the release checkout is not at a v* tag" && [ ! -e "$p/scripts" ]; then ok "$n"; else no "$n"; fi
fi
n="a dirty source is refused"
if wanted "$n"; then
  git clone -q "$rel" "$work/dirty" && printf 'x\n' >"$work/dirty/method/docs/method/stray.md"
  proj dirty
  sync "$work/dirty" "$p" --write
  if [ "$code" -eq 1 ] && has "the release checkout has changes or untracked files" && [ ! -e "$p/scripts" ]; then ok "$n"; else no "$n"; fi
fi
n="--source naming another checkout is refused"
if wanted "$n"; then
  proj other-source
  sync "$rel" "$p" --write --source "$rel71"
  if [ "$code" -eq 1 ] && has "--source names another checkout than the one this sync.sh is in" && [ ! -e "$p/scripts" ]; then ok "$n"; else no "$n"; fi
fi

drop_sandbox "$work" || true
echo "tests: sync: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
