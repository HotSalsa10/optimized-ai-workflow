#!/usr/bin/env bash
# Tests for the release's uninstall, scripts/release/sync.sh --uninstall and
# lib/uninstall.pl (step 8.2; M162; docs/plans/step8.md S7). Each case runs
# from a throwaway release, a git repository holding this repo's method/
# and scripts/release/ and tagged v0.7.0 (and a clone of it, tagged v0.7.1,
# with one file changed), into a throwaway project of its own: installed by
# that release's sync, the install committed unless the case says not, then
# taken out. The guard's refusal of sync --write is tested in
# tests/guard-protect.test.sh.
# shellcheck disable=SC2016 # single-quoted perl code is expanded by perl
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: uninstall"
root=$(repo_root)
work=$(new_sandbox_dir) || abort_sandbox
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
mkdir -p "$HOME"
git config --global user.name T
git config --global user.email t@example.invalid
git config --global commit.gpgsign false
git config --global core.autocrlf false
git config --global init.defaultBranch main

# the releases: rel at v0.7.0; rel71 a clone of it at v0.7.1, where why.md
# has one more line
rel="$work/rel"
rel71="$work/rel71"
if ! { mkdir -p "$rel/scripts" &&
  cp -R "$root/method" "$rel/method" &&
  cp -R "$root/scripts/release" "$rel/scripts/release" &&
  (cd "$rel" && git init -q && git add -A && git commit -q -m release && git tag v0.7.0) &&
  git clone -q "$rel" "$rel71" &&
  (cd "$rel71" && printf '\nA line added in v0.7.1.\n' >>method/docs/method/why.md && git add -A && git commit -q -m v0.7.1 && git tag v0.7.1); }; then
  abort_sandbox
fi

can_link=0
if ln -s target "$work/link-probe" 2>/dev/null && [ -L "$work/link-probe" ]; then can_link=1; fi
rm -f "$work/link-probe"

# proj NAME: a new project (a git repository with one commit); its path in p
proj() {
  p="$work/p-$1"
  rm -rf "$p"
  mkdir -p "$p" && (cd "$p" && git init -q && printf 'hello\n' >README.md && git add -A && git commit -q -m init)
}
# commit MESSAGE: everything in p committed
commit() { (cd "$p" && git add -A && git commit -q -m "$1"); }
# install [ARG...]: rel's sync into p with --write; sets out and code
install() {
  out=$(bash "$rel/scripts/release/sync.sh" --to "$p" --write "$@" 2>&1)
  code=$?
  [ "$code" -eq 0 ] || printf '%s\n' "$out" | tail -5
}
# un [ARG...]: rel's sync.sh --uninstall into p (UN_REL picks another
# release); sets out and code
un() {
  out=$(bash "${UN_REL:-$rel}/scripts/release/sync.sh" --to "$p" --uninstall "$@" 2>&1)
  code=$?
}
# cut AT ARG...: rel's uninstall into p with --write and ARG..., run as
# sync.sh runs it but stopped (exit 9) just before it renames a new copy
# onto, or removes, the path ending in AT; sets out and code
cut() {
  c_at=$1
  shift
  c_prog='BEGIN {
      *CORE::GLOBAL::rename = sub { exit 9 if $_[1] =~ /\Q$ENV{CUT_AT}\E\z/; CORE::rename($_[0], $_[1]) };
      *CORE::GLOBAL::unlink = sub { for (@_) { exit 9 if /\Q$ENV{CUT_AT}\E\z/ } CORE::unlink(@_) } }
    my $f = shift; do $f; die $@ if $@'
  out=$(CUT_AT="$c_at" perl -e "$c_prog" "$rel/scripts/release/lib/sync.pl" "$rel" --to "$p" --uninstall --write "$@" 2>&1)
  code=$?
}
# same_tree REV: p's files, ignored ones left out, are REV's tree, byte for
# byte
same_tree() { (cd "$p" && git add -A && git diff --cached --quiet "$1" && git reset -q); }
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
# missing_hooks DIR: each hook script DIR's settings name under
# .claude/hooks/method/ that is not there, one per line
missing_hooks() {
  perl -MJSON::PP -e 'my $d = shift; open my $h, "<", "$d/.claude/settings.json" or exit 0;
    my $s = JSON::PP->new->decode(do { local $/; <$h> });
    for my $ev (values %{ $s->{hooks} || {} }) { for my $g (@$ev) { for my $e (@{ $g->{hooks} || [] }) {
      next unless ($e->{command} // "") =~ m{\.claude/hooks/method/([A-Za-z0-9._-]+)};
      print "$1\n" unless -f "$d/.claude/hooks/method/$1" } } }' "$1"
}
# jget FILE EXPR: the perl EXPR on $d, the decoded JSON FILE, printed
jget() {
  perl -MJSON::PP -e 'open my $h, "<", $ARGV[0] or die; my $d = JSON::PP->new->decode(do { local $/; <$h> }); my $v = eval $ARGV[1]; die $@ if $@; print ref $v ? JSON::PP->new->canonical->encode($v) : (defined $v ? $v : "(undef)"), "\n"' "$1" "$2"
}
# has TEXT...: out holds each TEXT
has() {
  h_missing=""
  for t in "$@"; do
    case "$out" in *"$t"*) ;; *) h_missing="$h_missing [$t]" ;; esac
  done
  [ -z "$h_missing" ]
}
ok() { pass "$1"; }
no() { fail "$1" "${2:-exit $code;${h_missing:+ missing$h_missing;} $(printf '%s\n' "$out" | grep -v -E '^uninstall: remove    ' | tail -8)}"; }

# adopted: a project of its own, with its own settings (a key and a deny
# entry equal to the method's, a kept claudeMdExcludes, its own hook, allow
# rule, deny entry and key), a .gitignore without a final newline and an
# empty .gitattributes
adopted='{"autoMemoryEnabled": false, "claudeMdExcludes": ["vendor/**"], "cleanupPeriodDays": 30,
 "permissions": {"allow": ["Bash(npm test)"], "deny": ["Bash(rm -rf /)", "mcp__*__merge_pull_request"]},
 "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "bash tools/done.sh"}]}]}}'
adopt() {
  proj "$1"
  mkdir -p "$p/.claude" && printf '%s\n' "$adopted" >"$p/.claude/settings.json" &&
    printf 'node_modules' >"$p/.gitignore" && : >"$p/.gitattributes" && commit adopted
}

# --- a new project ---
n="a new project: install committed, then uninstall, gives the before commit's tree back byte for byte"
n2="a new project's .claude/settings.json, .gitattributes, .gitignore and empty method folders are absent after"
if wanted_any "$n" "$n2" "a dry run writes nothing" "a second run says not installed (exit 1)"; then
  proj new
  b=$(git -C "$p" rev-parse HEAD)
  install && commit install
  before=$(snap "$p")
  un
  if [ "$code" -eq 0 ] && has "the before commit: $b" "dry run - nothing written" && [ "$(snap "$p")" = "$before" ]; then ok "a dry run writes nothing"; else no "a dry run writes nothing"; fi
  un --write
  if [ "$code" -eq 0 ] && has "WROTE - the method v0.7.0 taken out" "start a new Claude Code session" && same_tree "$b"; then ok "$n"; else no "$n"; fi
  if [ ! -e "$p/.claude" ] && [ ! -e "$p/.gitattributes" ] && [ ! -e "$p/.gitignore" ] && [ ! -e "$p/scripts" ] && [ ! -e "$p/docs" ] && [ ! -e "$p/.method" ]; then ok "$n2"; else no "$n2" "left: $(cd "$p" && ls -A)"; fi
  un --write
  if [ "$code" -eq 1 ] && has "not installed"; then ok "a second run says not installed (exit 1)"; else no "a second run says not installed (exit 1)"; fi
fi

# --- an adopted project ---
n="an adopted project: install committed, then uninstall, gives the before commit's tree back byte for byte"
if wanted "$n"; then
  adopt adopted
  b=$(git -C "$p" rev-parse HEAD)
  install --keep claudeMdExcludes && commit install
  un --write
  if [ "$code" -eq 0 ] && same_tree "$b" &&
    has "keep      .claude/settings.json (the key autoMemoryEnabled, which the before commit held with this value)" \
      "keep      .claude/settings.json (the deny entry mcp__*__merge_pull_request, which the before commit held)" \
      "update    .claude/settings.json (the method's keys, deny entries and hooks taken out; its bytes as the before commit holds them)"; then
    ok "$n"
  else no "$n" "exit $code; ${h_missing:-}; $(cd "$p" && git status --short | head -5)"; fi
fi

# --- no before commit ---
n="with no before commit, every removed key and deny entry equal to the method's is named, and an emptied file is kept and named"
if wanted "$n"; then
  proj nobefore
  mkdir -p "$p/.claude" && printf '%s\n' "$adopted" >"$p/.claude/settings.json" && printf 'node_modules' >"$p/.gitignore"
  install --keep claudeMdExcludes
  un --write
  if [ "$code" -eq 0 ] && has "no before commit: the install is not committed" \
    "the key autoMemoryEnabled is removed: it equals the method's" "the deny entry mcp__*__merge_pull_request is removed: it equals one of the method's" \
    ".gitattributes is kept, now empty" &&
    [ -f "$p/.gitattributes" ] && [ ! -s "$p/.gitattributes" ] && printf 'node_modules\n' | cmp -s - "$p/.gitignore" &&
    [ "$(jget "$p/.claude/settings.json" '[$d->{autoMemoryEnabled}, $d->{permissions}{deny}, $d->{cleanupPeriodDays}, $d->{claudeMdExcludes}, $d->{hooks}]')" = '[null,["Bash(rm -rf /)"],30,["vendor/**"],{"Stop":[{"hooks":[{"command":"bash tools/done.sh","type":"command"}]}]}]' ] &&
    [ ! -e "$p/scripts" ]; then
    ok "$n"
  else no "$n"; fi
fi

# --- install, uninstall, install ---
n="install, uninstall, install gives the first install's bytes"
if wanted "$n"; then
  adopt again
  install --keep claudeMdExcludes && commit install
  first=$(snap "$p")
  un --write
  c1=$code
  install --keep claudeMdExcludes
  if [ "$c1" -eq 0 ] && [ "$code" -eq 0 ] && [ "$(snap "$p")" = "$first" ]; then ok "$n"; else no "$n" "exit $c1 then $code; $(diff <(printf '%s\n' "$first") <(snap "$p") | head -5)"; fi
fi

# --- conflicts: each named with its action, nothing written; --keep ---
# conflict NAME SETUP-CMD TEXT [KEEP-ARG CHECK-CMD]: a committed install,
# SETUP-CMD run in p, then the uninstall must refuse naming TEXT and write
# nothing; with KEEP-ARG it must then pass and CHECK-CMD hold
conflict() {
  c_name=$1
  wanted "$c_name" || return 0
  proj "c$((c_n = ${c_n:-0} + 1))"
  install && commit install
  (cd "$p" && eval "$2")
  c_before=$(snap "$p")
  un --write
  if [ "$code" -ne 1 ] || ! has "conflict  " "$3" "nothing was written" || [ "$(snap "$p")" != "$c_before" ]; then no "$c_name"; return 0; fi
  if [ -z "${4:-}" ]; then ok "$c_name"; return 0; fi
  un --write --keep "$4"
  if [ "$code" -eq 0 ] && (cd "$p" && eval "$5"); then ok "$c_name"; else no "$c_name" "with --keep $4: exit $code; $(printf '%s\n' "$out" | tail -4)"; fi
}
conflict "a changed method file is named with its action, and --keep PATH keeps it" \
  "printf '# mine\n' >>scripts/method/status.sh" \
  "scripts/method/status.sh (changed since method.lock: keep it with --keep scripts/method/status.sh, or put back the method's copy)" \
  scripts/method/status.sh "tail -1 scripts/method/status.sh | grep -q -x '# mine' && [ ! -e scripts/method/lib ]"
conflict "a method key the project changed is named with its action, and --keep KEY keeps it" \
  "perl -0pi -e 's/\"effortLevel\": \"xhigh\"/\"effortLevel\": \"high\"/' .claude/settings.json" \
  ".claude/settings.json (the project changed the method key effortLevel: keep it with --keep effortLevel)" \
  effortLevel "[ \"\$(jget .claude/settings.json '[\$d->{effortLevel}, exists \$d->{model} ? 1 : 0]')\" = '[\"high\",0]' ]"
conflict "a file the system made under a method path gets \"delete it\"" \
  "printf x >.claude/hooks/method/.DS_Store" \
  ".claude/hooks/method/.DS_Store (not in method.lock: delete it (a file your system made))"
conflict "an extra file under a method path is named with its action, and --keep PATH keeps it" \
  "printf 'mine\n' >docs/method/mine.md" \
  "docs/method/mine.md (not in method.lock: move it out, or keep it with --keep docs/method/mine.md)" \
  docs/method/mine.md "[ \"\$(cat docs/method/mine.md)\" = mine ] && [ ! -e docs/method/why.md ]"
conflict "a broken method block is named with its action" \
  "grep -v '^# <<< method\$' .gitignore >g.tmp && mv g.tmp .gitignore" \
  ".gitignore (its method block is broken: put back both marker lines"
if [ "$can_link" -eq 1 ]; then
  conflict "a link on a path it would touch is named with its action" \
    "mv .gitattributes ga.real && ln -s ga.real .gitattributes" \
    ".gitattributes (a link on its path (.gitattributes): replace the link with a plain file or remove it)"
  conflict "a link under the method's paths is named with its action" \
    "ln -s ../../../README.md .claude/rules/method/linked.md" \
    "a link: .claude/rules/method/linked.md: replace the link with a plain file or remove it"
else
  skip "a link on a path it would touch is named with its action" "links cannot be made here"
  skip "a link under the method's paths is named with its action" "links cannot be made here"
fi

# --- a run cut off after each stage is finished by a re-run ---
# (the project has a log in .method/local/, so stage 1 writes its .gitignore)
for at in ".claude/settings.json:after its first stage (.method/local/.gitignore)" \
  ".claude/agents/method/method-architect.md:after its second stage (the settings)" \
  "scripts/method/settings.method.json:in its third stage, after profiles.tsv went, before the fragment" \
  ".gitattributes:after its third stage (the method's files)" \
  "scripts/method/method.lock:after its fourth stage (the blocks)"; do
  n="a run cut off ${at#*:} is finished by a re-run, and no hook entry names a missing script"
  wanted "$n" || continue
  adopt "cut$((cut_n = ${cut_n:-0} + 1))"
  b=$(git -C "$p" rev-parse HEAD)
  install --keep claudeMdExcludes && commit install
  mkdir -p "$p/.method/local" && printf 'a log\n' >"$p/.method/local/run.log"
  cut "${at%%:*}"
  c1=$code
  miss=$(missing_hooks "$p")
  un --write
  if [ "$c1" -eq 9 ] && [ -z "$miss" ] && [ "$code" -eq 0 ] && same_tree "$b" && [ "$(cat "$p/.method/local/.gitignore")" = '*' ]; then ok "$n"; else no "$n" "cut: exit $c1, hooks naming missing scripts: [$miss]; re-run: exit $code; $(printf '%s\n' "$out" | grep -E 'conflict|REFUSED|FAIL' | head -3); $(cd "$p" && git status --short | head -3)"; fi
done

# --- .method/local/ ---
n=".method/local/ with a log and a stray file stays, is ignored after, and is named"
n2="an existing .method/local/.gitignore is never written over"
if wanted_any "$n" "$n2"; then
  proj local
  b=$(git -C "$p" rev-parse HEAD)
  install && commit install
  printf 'a log\n' >"$p/.method/local/run.log" && printf 'stray\n' >"$p/.method/local/stray.txt"
  un --write
  if [ "$code" -eq 0 ] && has "write     .method/local/.gitignore" "keep      .method/local/ (the method's logs and review receipts, which git does not keep" &&
    [ "$(cat "$p/.method/local/run.log")" = 'a log' ] && [ "$(cat "$p/.method/local/stray.txt")" = stray ] && [ "$(cat "$p/.method/local/.gitignore")" = '*' ] &&
    same_tree "$b" && [ -z "$(cd "$p" && git status --porcelain --untracked-files=all | grep -E '^.. \.method/')" ]; then ok "$n"; else no "$n"; fi
  proj local2
  install && commit install
  printf '*.log\n' >"$p/.method/local/.gitignore" && printf 'a log\n' >"$p/.method/local/run.log"
  un --write
  if [ "$code" -eq 0 ] && ! has "write     .method/local/.gitignore" && [ "$(cat "$p/.method/local/.gitignore")" = '*.log' ]; then ok "$n2"; else no "$n2"; fi
fi

# --- /method-setup's files stay and are named ---
n="after /method-setup, its files stay and the output lists exactly the files that mention the method"
if wanted "$n"; then
  proj setup
  install && commit install
  printf 'DECIDES\tclaude\nREPORTS\tshort\nPACE\tsmall\nTOUCHES\tnone\nSTRICT\tstandard\nPROFILE\tbest\nPROJECT_WHAT\tA test project.\nNEVER_WRONG\tNothing lost.\nHOW_IT_STARTS\t\nTEST_COMMAND\tbash test.sh\nRULE\tKeep it small.\n' >"$p/.claude/setup-answers.txt"
  s_out=$(cd "$p" && bash scripts/method/setup-write.sh --write 2>&1)
  s_code=$?
  commit setup
  # (the files setup wrote, and the always-loaded ones, that mention the
  # method, apart from the method's own files and settings)
  git -C "$p" diff --name-only HEAD~1 HEAD >"$work/cand.txt"
  (cd "$p" && ls CLAUDE.md AGENTS.md .claude/CLAUDE.md 2>/dev/null) >>"$work/cand.txt"
  (cd "$p" && find .claude/rules -type f 2>/dev/null) | sed 's|^\./||' >>"$work/cand.txt"
  grep -v -E '^(scripts/method/|\.claude/settings\.json$|\.claude/rules/method/)' "$work/cand.txt" | sort -u >"$work/cand2.txt"
  : >"$work/want.txt"
  while read -r f; do
    if grep -q -E 'scripts/method/|\.claude/rules/method/|/method-|>>> method-setup' "$p/$f" 2>/dev/null; then printf '%s\n' "$f" >>"$work/want.txt"; fi
  done <"$work/cand2.txt"
  want=$(cat "$work/want.txt")
  un --write
  got=$(printf '%s\n' "$out" | sed -n 's/^uninstall: keep      \(.*\) (it mentions the method: remove or edit it with Claude on the same branch)$/\1/p')
  left=$(printf '%s\n' "$want" | while read -r f; do [ -f "$p/$f" ] || echo "$f"; done)
  if [ "$s_code" -eq 0 ] && [ "$code" -eq 0 ] && [ -n "$want" ] && [ "$got" = "$want" ] && [ -z "$left" ] &&
    [ -f "$p/.claude/method.conf" ] && [ -f "$p/.claude/setup-answers.txt" ] && [ -f "$p/.claude/rules/pack/working.md" ] &&
    grep -q '>>> method-setup' "$p/SPEC.md" && [ ! -e "$p/scripts/method" ]; then
    ok "$n"
  else
    no "$n" "setup exit $s_code ($(printf '%s\n' "$s_out" | tail -1)); uninstall exit $code; wanted [$want]; got [$got]; missing after [$left]"
  fi
fi

# --- a later release takes out an earlier one ---
n="a checkout at a later tag uninstalls a project installed from the earlier one"
if wanted "$n"; then
  proj later
  b=$(git -C "$p" rev-parse HEAD)
  install && commit install
  UN_REL=$rel71 un --write
  if [ "$code" -eq 0 ] && has "v0.7.1 (" "takes out the method v0.7.0" && same_tree "$b"; then ok "$n"; else no "$n"; fi
fi

# --- step 8's review, its repair loop (F1 to F4, F10 to F14) ---
n="a run cut off after its third stage with --keep PATH is finished by a re-run with the same --keep (review F1)"
if wanted "$n"; then
  adopt keepcut
  install --keep claudeMdExcludes && commit install
  cut .gitattributes --keep docs/method/why.md
  c1=$code
  un --write --keep docs/method/why.md
  if [ "$c1" -eq 9 ] && [ "$code" -eq 0 ] && [ -f "$p/docs/method/why.md" ] && [ ! -e "$p/scripts/method/method.lock" ] && [ -z "$(missing_hooks "$p")" ]; then ok "$n"; else no "$n" "cut: exit $c1; re-run: exit $code; $(printf '%s\n' "$out" | grep -E 'conflict|REFUSED' | head -3)"; fi
fi

n="the method's settings files removed by hand, with no copy saved by an earlier run, are refused and nothing is written (review F2)"
if wanted "$n"; then
  proj byhand
  install && commit install
  rm -f "$p/scripts/method/settings.method.json" "$p/scripts/method/profiles.tsv"
  before=$(snap "$p")
  un --write
  if [ "$code" -eq 1 ] && has "conflict  scripts/method/settings.method.json (it is missing, so the method's keys in .claude/settings.json cannot be told: put back the release's copy)" "nothing was written" && [ "$(snap "$p")" = "$before" ]; then ok "$n"; else no "$n"; fi
fi

n="what of the project's own stays in its settings is named, by kind (review F3)"
if wanted "$n"; then
  adopt ownnamed
  install --keep claudeMdExcludes && commit install
  un
  if [ "$code" -eq 0 ] && has "keep      .claude/settings.json (the project's own: claudeMdExcludes; cleanupPeriodDays; permissions.allow; 1 deny entry; 1 hook)"; then ok "$n"; else no "$n"; fi
fi

# check NAME SETUP TEXT [ARG]: a committed install, SETUP run in p, then
# the uninstall (with ARG) is refused naming TEXT, nothing written, exit
# CODE (1 unless SETUP sets want_code)
refused() {
  r_name=$1
  wanted "$r_name" || return 0
  proj "r$((r_n = ${r_n:-0} + 1))"
  install && commit install
  want_code=1
  (cd "$p" && eval "$2")
  r_before=$(snap "$p")
  if [ -n "${4:-}" ]; then un --write --keep "$4"; else un --write; fi
  case "$r_name" in *"(exit 2)"*) want_code=2 ;; esac
  if [ "$code" -eq "$want_code" ] && has "$3" && [ "$(snap "$p")" = "$r_before" ]; then ok "$r_name"; else no "$r_name"; fi
}
refused "a changed installed settings.method.json is refused, as uninstall reads the method's keys from it (review F4)" \
  "printf ' ' >>scripts/method/settings.method.json" \
  "conflict  scripts/method/settings.method.json (changed since method.lock; uninstall reads the method's keys from it, so it cannot be kept: put back the method's copy)"
refused "a changed installed profiles.tsv is refused the same way (review F4)" \
  "printf '# x\n' >>scripts/method/profiles.tsv" \
  "conflict  scripts/method/profiles.tsv (changed since method.lock; uninstall reads the method's keys from it"
refused "--keep of the installed profiles.tsv, which the keys are read from, is bad usage (exit 2) (review F4, F10)" ":" \
  "--keep scripts/method/profiles.tsv cannot be kept" scripts/method/profiles.tsv
refused "a lock whose settings line does not match the installed fragment and profile is refused (review F4)" \
  "perl -pi -e 's/^settings\t[0-9a-f]{64}\$/\"settings\t\" . (\"0\" x 64)/e' scripts/method/method.lock" \
  "conflict  scripts/method/method.lock (its settings line does not match scripts/method/settings.method.json and the profile best"
refused "a lock that cannot be read is refused (review F4)" \
  "printf 'version\tv0.7.0\nnot a lock\n' >scripts/method/method.lock" \
  "method.lock cannot be read, so what the method put there cannot be told"
refused "a sync run that was cut off is refused until sync finishes it (review F4)" \
  "mkdir -p .method/local && printf 'v0.7.0\nbest\n' >.method/local/sync-in-progress" \
  "a sync run was cut off here (.method/local/sync-in-progress is there); finish it with the same sync first"
refused "--keep of a key that is not the method's is bad usage (exit 2) (review F10)" ":" \
  "--keep foo is not one of the method's keys" foo
refused "--keep of method.lock is bad usage (exit 2) (review F10)" ":" \
  "--keep scripts/method/method.lock cannot be kept" scripts/method/method.lock
refused "--keep of a file the method does not have is bad usage (exit 2) (review F10)" ":" \
  "--keep docs/method/none.md names no file of the method's in this project" docs/method/none.md
refused "a .gitignore that is a folder is a conflict with its action (review F13)" \
  "mv .gitignore gi.keep && mkdir .gitignore" \
  ".gitignore (.gitignore is a link or not a regular file: replace it with a plain file or remove it)"

n="the guard's own lists in .claude/method-local/ stay and are named (review F12)"
if wanted "$n"; then
  proj ownlists
  install && commit install
  mkdir -p "$p/.claude/method-local" && printf 'stash :: kept aside\n' >"$p/.claude/method-local/git-shapes.txt"
  un --write
  if [ "$code" -eq 0 ] && has "keep      .claude/method-local/ (the project's own lines for the guard's lists" && [ -f "$p/.claude/method-local/git-shapes.txt" ]; then ok "$n"; else no "$n"; fi
fi

n="a local settings file git no longer ignores once the .gitignore block goes is named (review F14)"
if wanted "$n"; then
  proj localsettings
  install && commit install
  printf '{"disableAllHooks": true}\n' >"$p/.claude/settings.local.json"
  un --write
  if [ "$code" -eq 0 ] && has "keep      .claude/settings.local.json (git no longer ignores it once the method's .gitignore block goes"; then ok "$n"; else no "$n"; fi
fi

n="from a linked worktree, the run state in git's common folder is named (review F11)"
if wanted "$n"; then
  proj worktree
  install && commit install
  git -C "$p" worktree add -q "$work/wt-linked" HEAD 2>/dev/null
  printf 'x\n' >"$p/.git/method-receipt-test.json"
  out=$(bash "$rel/scripts/release/sync.sh" --to "$work/wt-linked" --uninstall 2>&1)
  code=$?
  if [ "$code" -eq 0 ] && has "keep      git's own folder (the method's run state there (method-receipt-test.json)"; then ok "$n"; else no "$n"; fi
fi

# --- the source checks and usage ---
n="an untagged release checkout is refused"
n2="a dirty release checkout is refused"
n3="--profile with --uninstall is bad usage (exit 2)"
if wanted_any "$n" "$n2" "$n3"; then
  proj src
  install && commit install
  before=$(snap "$p")
  git clone -q "$rel" "$work/relu" && (cd "$work/relu" && printf 'x\n' >>method/docs/method/why.md && git commit -qam untagged)
  UN_REL="$work/relu" un --write
  if [ "$code" -eq 1 ] && has "not at a v* tag" && [ "$(snap "$p")" = "$before" ]; then ok "$n"; else no "$n"; fi
  git clone -q "$rel" "$work/reld" && printf 'x\n' >"$work/reld/untracked.txt"
  UN_REL="$work/reld" un --write
  if [ "$code" -eq 1 ] && has "has changes or untracked files" && [ "$(snap "$p")" = "$before" ]; then ok "$n2"; else no "$n2"; fi
  un --write --profile budget
  if [ "$code" -eq 2 ] && has "--uninstall" && [ "$(snap "$p")" = "$before" ]; then ok "$n3"; else no "$n3"; fi
fi

drop_sandbox "$work" || true
echo "tests: uninstall: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
