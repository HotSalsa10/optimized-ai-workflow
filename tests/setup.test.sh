#!/usr/bin/env bash
# Tests for setup-write, method/scripts/method/setup-write.sh and
# lib/setup.pl (step 7.4; M100, M156; docs/plans/step7.md S2, S9, S10).
# Two projects get the method from a throwaway release (this repo's
# method/, tagged v0.7.0) through the release's own sync: "new" (no commit
# on main, profile best) and "adopted" (history on main, its own AGENTS.md,
# CLAUDE.md without @AGENTS.md, SPEC.md, method.conf, settings with its own
# hook, allow and deny rules, a requirements.txt and folders of its own,
# installed on a branch at profile budget). Then:
# - one perl process tries every combination of the closed answers (2 x 2 x
#   2 x 8 x 2 x 3 = 384 on each project, 768 in all) with fixed short
#   answers, some hostile, through Setup::plan: each must keep the floor,
#   give the same bytes on a second run, and give a fresh run's result when
#   run again with every closed answer changed, apart from the kept entries
#   its card names;
# - the refusals (each answer shape, a secret, a method key changed by
#   hand, a template or method.lock's settings line changed by hand, a key
#   set twice in method.conf, a row id used twice) run setup-write.sh itself
#   and must write nothing;
# - re-runs on disk: VERDICTS_FROM once main holds the method, a smoke row
#   turned on, a named path setup writes itself, settings.json laid out
#   otherwise;
# - a sample of four combinations is written to disk by setup-write.sh and
#   read by status and done-check.
# shellcheck disable=SC2016 # single-quoted perl code is expanded by perl
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: setup"
started=$(date +%s)
root=$(repo_root)
work=$(new_sandbox_dir) || abort_sandbox
T=$(printf '\t')
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM CLAUDE_CODE_EXECPATH CLAUDE_CODE_EFFORT_LEVEL CLAUDE_CODE_REMOTE CLAUDE_PROJECT_DIR GH_REPO CI
mkdir -p "$HOME"
git config --global user.name T
git config --global user.email t@example.invalid
git config --global commit.gpgsign false
git config --global core.autocrlf false
git config --global init.defaultBranch main

# the release, and the two projects
rel="$work/rel"
pnew="$work/new"
pold="$work/adopted"
if ! { mkdir -p "$rel/scripts" &&
  cp -R "$root/method" "$rel/method" &&
  cp -R "$root/scripts/release" "$rel/scripts/release" &&
  (cd "$rel" && git init -q && git add -A && git commit -q -m release && git tag v0.7.0) &&
  mkdir -p "$pnew" && (cd "$pnew" && git init -q && printf 'A game.\n' >README.md) &&
  bash "$rel/scripts/release/sync.sh" --to "$pnew" --profile best --write >/dev/null &&
  mkdir -p "$pold/.claude" "$pold/src" "$pold/payments" "$pold/my docs" &&
  (
    cd "$pold" || exit 1
    git init -q
    printf '# Our guide\n\nOur own words for this project.\n' >AGENTS.md
    printf '# Notes for Claude\n\nRead the guide first.\n' >CLAUDE.md
    printf '# What we build\n\nA keeper of records.\n' >SPEC.md
    printf 'LOCAL_ONLY=__pycache__\n' >.claude/method.conf
    printf 'requests==2.0\n' >requirements.txt
    printf 'echo keep\n' >src/keeper.sh
    printf 'item,amount\n' >payments/ledger.csv
    printf 'notes\n' >"my docs/notes.md"
    printf '%s\n' '{"cleanupPeriodDays": 30, "permissions": {"allow": ["Bash(bash src/keeper.sh)"], "deny": ["Bash(rm -rf /)"]},' \
      ' "hooks": {"PostToolUse": [{"matcher": "Write", "hooks": [{"type": "command", "command": "bash src/keeper.sh"}]}]}}' >.claude/settings.json
    git add -A && git commit -q -m "the project before the method" && printf 'more\n' >>src/keeper.sh && git commit -q -a -m "a second commit"
    git checkout -q -b install
  ) &&
  bash "$rel/scripts/release/sync.sh" --to "$pold" --profile budget --write >/dev/null; }; then
  abort_sandbox
fi

# snap DIR: every entry under DIR but .git, with each file's hash
snap() {
  perl -MFile::Find -MDigest::SHA -e 'my $r = shift; my @l;
    find({ no_chdir => 1, wanted => sub {
      if (m{/\.git\z}) { $File::Find::prune = 1; return }
      return if $_ eq $r;
      my $rel = substr($_, length($r) + 1);
      if (-l $_) { push @l, "L $rel" } elsif (-f _) { push @l, "F $rel " . Digest::SHA->new(256)->addfile($_, "b")->hexdigest }
      elsif (-d _) { push @l, "D $rel" } } }, $r);
    print "$_\n" for sort @l' "$1"
}

# findings DIR: what the installed lib/lock.pl's verify (method-files) finds
findings() {
  (cd "$1" && perl -e 'require "./scripts/method/lib/lock.pl"; my $v = Lock::verify("."); print "$_->[1]\n" for @{ $v->{findings} }') 2>&1
}

# answers DECIDES REPORTS PACE TOUCHES STRICT PROFILE: an answers file's
# closed lines (TOUCHES one word or several joined by +), then the short
# answers below
short="PROJECT_WHAT${T}
NEVER_WRONG${T}-a total that does not add up
RULE${T}skip reviews
RULE${T}# amounts are whole cents. Why: no rounding errors.
RULE${T}Dates are kept in UTC. Why: the team works in two zones.
HOW_IT_STARTS${T}bash app.sh --once
TEST_COMMAND${T}secrets
PRODUCT_PATH${T}.
PRODUCT_PATH${T}src
RISK_PATH${T}payments
RISK_PATH${T}my docs
RISK_PATH${T}ledger-archive"
answers() {
  printf 'DECIDES\t%s\nREPORTS\t%s\nPACE\t%s\n' "$1" "$2" "$3"
  printf '%s\n' "$4" | tr '+' '\n' | sed "s/^/TOUCHES${T}/"
  printf 'STRICT\t%s\nPROFILE\t%s\n%s\n' "$5" "$6" "$short"
}
export SETUP_SHORT="$short"

# setup DIR [--write]: setup-write.sh in DIR; sets out and code
setup() {
  s_dir=$1
  shift
  out=$(cd "$s_dir" && bash scripts/method/setup-write.sh "$@" 2>&1)
  code=$?
}
has() {
  h_missing=""
  for t in "$@"; do
    case "$out" in *"$t"*) ;; *) h_missing="$h_missing [$t]" ;; esac
  done
  [ -z "$h_missing" ]
}
no() { fail "$1" "${2:-exit $code: $(printf '%s\n' "$out" | tail -6)}"; }

# copy DIR NAME: a copy of the project DIR (its .git too); its path in c
copy() {
  c="$work/c-$2"
  rm -rf "$c"
  cp -R "$1" "$c"
}

# --- every combination, in one perl process ---
loop_names="every combination is accepted and gives the card's fixed lines
every combination: no method file changed, and method.lock only in its profile and settings lines
every combination: the method keys, deny list and hooks as released, only the profile's three keys set
every combination: HIGH_RISK_PATHS keeps every entry it had
every combination: no check row has a built-in id
every combination: a second run gives the same bytes
every combination: a re-run with changed answers gives a fresh run's result, apart from the kept entries the card names
every combination: no pre-existing file changed outside a managed block
every combination: no HIGH_RISK_PATHS entry names no path, and the card names each missing one
every combination: short reports keep the five parts
every combination: method.conf and the check rows read cleanly
an adopted project: CLAUDE.md gets @AGENTS.md, AGENTS.md and SPEC.md are kept and named, Python and its scanner row are on the card"
loop_wanted=0
while IFS= read -r n; do
  if wanted "$n"; then loop_wanted=1; fi
done <<EOF
$loop_names
EOF
cat >"$work/loop.pl" <<'LOOP'
use strict;
use warnings;
my ($pnew, $pold) = @ARGV;
require "$pnew/scripts/method/lib/setup.pl";
require "$pnew/scripts/method/lib/checks.pl";
my $FIVE = 'a summary, a change summary, the actual check output, the risks and the verdict';
my (%bad, %count);
my @names = split /\n/, $ENV{LOOP_NAMES};
my $bad = sub { my ($i, $what) = @_; $bad{ $names[$i] } //= $what; $count{ $names[$i] }++ };
my $disk = sub {
  my ($root, $rel) = @_;
  my $f = "$root/$rel";
  return undef unless -f $f;
  open my $h, '<:raw', $f or return undef;
  local $/;
  return scalar <$h>;
};
my $strip = sub { my $t = shift; $t =~ s/^(?:# |<!-- )>>> method-setup(?: -->)?\n.*?^(?:# |<!-- )<<< method-setup(?: -->)?\n//msg; $t };
my $block_conf = sub {
  my $t = shift // '';
  my ($in) = $t =~ /^# >>> method-setup\n(.*?)^# <<< method-setup\n/ms;
  my %v;
  push @{ $v{$1} }, $2 while defined $in && $in =~ /^([A-Z_]+)=(.*)$/mg;
  return \%v;
};
my $all_conf = sub { my ($v) = Conf::read_text($_[0] // '', 'conf'); $v };
my @fixed = ('Every change gets: checks, an independent review, a security check.', 'Takes effect: files now; the profile from your next session.');
my %next = (best => 'balanced', balanced => 'budget', budget => 'best');
my %other = (claude => 'owner', owner => 'claude', short => 'full', full => 'short', small => 'larger', larger => 'small', standard => 'strict', strict => 'standard');
my @touch = qw(money personal outside);
my $text = sub {
  my ($d, $r, $p, $m, $s, $pr) = @_;
  my @t = map { $touch[$_] } grep { $m & (1 << $_) } 0 .. 2;
  @t = ('none') unless @t;
  return join('', "DECIDES\t$d\n", "REPORTS\t$r\n", "PACE\t$p\n", (map {"TOUCHES\t$_\n"} @t), "STRICT\t$s\n", "PROFILE\t$pr\n", $ENV{SETUP_SHORT}, "\n");
};
my $n = 0;
for my $root ($pnew, $pold) {
  my $det = Setup::detect($root);
  my ($lock0) = Lock::load($root);
  my $lock0_text = $disk->($root, $Lock::LOCK);
  my $set0 = (Json::decode($disk->($root, $Lock::SETTINGS)))[0];
  my $base_conf = $all_conf->($disk->($root, '.claude/method.conf'));
  for my $d (qw(claude owner)) { for my $r (qw(short full)) { for my $p (qw(small larger)) { for my $m (0 .. 7) { for my $s (qw(standard strict)) { for my $pr (qw(best balanced budget)) {
    $n++;
    my $tag = "$root [$d $r $p $m $s $pr]";
    my $a = $text->($d, $r, $p, $m, $s, $pr);
    my $r1 = Setup::plan($root, $a, $det, {});
    if (@{ $r1->{problems} }) { $bad->(0, "$tag: refused: $r1->{problems}[0]"); next }
    for my $f (@fixed) { $bad->(0, "$tag: the card lacks \"$f\"") unless grep { $_ eq $f } @{ $r1->{card} } }
    my %o1 = %{ $r1->{out} };
    my $get = sub { exists $o1{ $_[0] } ? $o1{ $_[0] } : $disk->($root, $_[0]) };
    # 1: no method file; the lock's other lines as they were
    my @m = grep { Lock::method_path($_) && $_ ne $Lock::LOCK } keys %o1;
    $bad->(1, "$tag: writes @m") if @m;
    my @l0 = split /\n/, $lock0_text;
    my @l1 = split /\n/, $get->($Lock::LOCK);
    $bad->(1, "$tag: method.lock changed beyond its profile and settings lines")
      if @l0 != @l1 || grep { $_ != 2 && $_ != 3 && $l0[$_] ne $l1[$_] } 0 .. $#l0;
    $bad->(1, "$tag: method.lock's profile line is not $pr") unless $l1[2] eq "profile\t$pr";
    # 2: the settings
    my $s1 = (Json::decode($get->($Lock::SETTINGS)))[0];
    my ($k) = Lock::expected($root, $pr);
    my @w = Lock::compare($k, $s1);
    $bad->(2, "$tag: $w[0]") if @w;
    $bad->(2, "$tag: disableAllHooks is not false") unless exists $s1->{disableAllHooks} && !$s1->{disableAllHooks} && JSON::PP::is_bool($s1->{disableAllHooks});
    $bad->(2, "$tag: disableSkillShellExecution is not true") unless JSON::PP::is_bool($s1->{disableSkillShellExecution}) && $s1->{disableSkillShellExecution};
    my %c0 = %$set0;
    my %c1 = %$s1;
    delete @c0{@Lock::PROFILE_KEYS};
    delete @c1{@Lock::PROFILE_KEYS};
    $bad->(2, "$tag: a settings key other than the profile's three changed") if Json::encode(\%c0) ne Json::encode(\%c1);
    # 3, 8, 10: method.conf
    my $conf1 = $get->('.claude/method.conf');
    my ($cv, $cp) = Conf::read_text($conf1 // '', 'conf');
    $bad->(10, "$tag: method.conf: $cp->[0]") if @$cp;
    my %hr = map { ($_ => 1) } @{ $cv->{HIGH_RISK_PATHS} || [] };
    my @lost = grep { !$hr{$_} } @{ $base_conf->{HIGH_RISK_PATHS} || [] };
    $bad->(3, "$tag: lost @lost") if @lost;
    for my $e (keys %hr) {
      next if $e eq '.' || -e "$root/$e" || grep { index($_, "$e/") == 0 || $_ eq $e } keys %o1;
      $bad->(8, "$tag: HIGH_RISK_PATHS names $e, which is not there");
    }
    my @named = grep { !-e "$root/$_" } qw(ledger-archive payments), 'my docs';
    for my $e (@named) { $bad->(8, "$tag: the card does not name $e") unless grep { /\ANot there yet: .*\b\Q$e\E\b/ } @{ $r1->{card} } }
    # 4, 10: the check rows
    for my $l (split /\n/, $get->('checks/project.tsv') // '') {
      next if $l =~ /\A[ \t]*(?:#|\z)/;
      my @f = split /\t/, $l, -1;
      $bad->(10, "$tag: a check row without 5 fields") if @f != 5;
      $bad->(4, "$tag: the row id $f[0] is a built-in check's") if grep { $_ eq $f[0] } @Checks::RESERVED;
    }
    # 5: a second run
    my $r2 = Setup::plan($root, $a, $det, \%o1);
    if (@{ $r2->{problems} }) { $bad->(5, "$tag: the second run is refused: $r2->{problems}[0]") }
    elsif (my @ch = grep { $r2->{out}{$_} ne ($o1{$_} // '') } keys %{ $r2->{out} }) { $bad->(5, "$tag: the second run changes @ch") }
    # 6: every closed answer changed, over the first run, and fresh
    my $fa = $text->($other{$d}, $other{$r}, $other{$p}, 7 - $m, $other{$s}, $next{$pr});
    my $r3 = Setup::plan($root, $fa, $det, \%o1);
    my $rf = Setup::plan($root, $fa, $det, {});
    if (@{ $r3->{problems} } || @{ $rf->{problems} }) { $bad->(6, "$tag: refused: " . ($r3->{problems}[0] // $rf->{problems}[0])); next }
    my %o3 = (%o1, %{ $r3->{out} });
    my %of = %{ $rf->{out} };
    my %paths = map { ($_ => 1) } keys %o3, keys %of;
    for my $f (sort keys %paths) {
      my $x3 = exists $o3{$f} ? $o3{$f} : $disk->($root, $f);
      my $xf = exists $of{$f} ? $of{$f} : $disk->($root, $f);
      next if ($x3 // '') eq ($xf // '');
      if ($f ne '.claude/method.conf') { $bad->(6, "$tag: $f differs from a fresh run's"); next }
      my ($b3, $bf, $b1) = map { $block_conf->($_) } $x3, $xf, $o1{$f} // $disk->($root, $f);
      for my $key (sort keys %{ { %$b3, %$bf } }) {
        my @want = @{ $bf->{$key} || [] };
        my %w = map { ($_ => 1) } @want;
        my @kept = grep { !$w{$_} } @{ $b1->{$key} || [] };
        my @got = @{ $b3->{$key} || [] };
        if ("@got" ne join(' ', @want, @kept)) { $bad->(6, "$tag: $key is @got, not the fresh run's @want and the kept @kept"); next }
        for my $e (@kept) { $bad->(6, "$tag: the card does not name the kept $key=$e") unless grep { /\AKept from an earlier run .*\Q$key=$e\E/ } @{ $r3->{card} } }
      }
      $bad->(6, "$tag: $f differs outside its block") if $strip->($x3) ne $strip->($xf);
    }
    my %hr3 = map { ($_ => 1) } @{ ($all_conf->($o3{'.claude/method.conf'}))->{HIGH_RISK_PATHS} || [] };
    my @lost3 = grep { !$hr3{$_} } keys %hr;
    $bad->(3, "$tag: run again with changed answers, HIGH_RISK_PATHS lost @lost3") if @lost3;
    # 7: what was there before, outside the blocks
    for my $f (grep { $_ ne $Lock::SETTINGS && $_ ne $Lock::LOCK } keys %o1) {
      my $old = $disk->($root, $f);
      next unless defined $old;
      my $new = $strip->($o1{$f});
      $bad->(7, "$tag: $f changed outside its block") unless $new eq $old || ($old !~ /\n\z/ && $new eq "$old\n");
    }
    # 9: short reports
    my $wk = $get->('.claude/rules/pack/working.md') // '';
    if ($r eq 'short') { $bad->(9, "$tag: working.md's short-reports line lacks the five parts") unless $wk =~ /^- Reports: short: .*\Q$FIVE\E/m }
    # 11: the adopted project
    if ($root eq $pold) {
      $bad->(11, "$tag: CLAUDE.md lacks the line \@AGENTS.md") unless ($get->('CLAUDE.md') // '') =~ /^\@AGENTS\.md$/m;
      $bad->(11, "$tag: AGENTS.md or SPEC.md written") if exists $o1{'AGENTS.md'} || exists $o1{'SPEC.md'};
      for my $want ('Kept as it was: SPEC.md', 'Added: the line @AGENTS.md to CLAUDE.md', 'Found Python (requirements.txt): the suggested scanner row is deps-python') {
        $bad->(11, "$tag: the card lacks \"$want\"") unless grep { index($_, $want) == 0 } @{ $r1->{card} };
      }
      $bad->(11, "$tag: the files do not name AGENTS.md as kept") unless grep { $_->[0] eq 'kept' && $_->[1] eq 'AGENTS.md' } @{ $r1->{files} };
    }
  } } } } } }
}
for my $i (0 .. $#names) {
  my $nm = $names[$i];
  if ($bad{$nm}) { print "BAD\t$nm\t$count{$nm} of $n: first $bad{$nm}\n" }
  else { print "OK\t$nm\t$n combinations\n" }
}
LOOP
if [ "$loop_wanted" -eq 1 ]; then
  loop_out=$(LOOP_NAMES=$loop_names perl "$work/loop.pl" "$pnew" "$pold" 2>&1)
  while IFS= read -r n; do
    wanted "$n" || continue
    line=$(printf '%s\n' "$loop_out" | grep -F -- "${T}${n}${T}" | head -1)
    case "$line" in
      "OK${T}"*) pass "$n (${line##*"$T"})" ;;
      "BAD${T}"*) fail "$n" "${line##*"$T"}" ;;
      *) fail "$n: the loop did not report it" "$(printf '%s\n' "$loop_out" | tail -5)" ;;
    esac
  done <<EOF
$loop_names
EOF
fi

# --- the refusals, through setup-write.sh ---
good=$(answers claude short small money+outside strict balanced)
n="shape refusals name the key or line and write nothing"
if wanted "$n"; then
  copy "$pnew" shape
  before=$(snap "$c")
  bad_cases=""
  # each case: what replaces the answers (sed program or a line added), and the reason
  try() {
    printf '%s\n' "$1" >"$c/.claude/setup-answers.txt"
    setup "$c" --write
    if [ "$code" -ne 1 ] || ! has "$2" "nothing was written" || [ "$(snap "$c" | grep -v ' .claude/setup-answers.txt ')" != "$(printf '%s\n' "$before" | grep -v ' .claude/setup-answers.txt ')" ]; then
      bad_cases="$bad_cases
[$2] exit $code: $(printf '%s\n' "$out" | head -2 | tr '\n' ' ')"
    fi
  }
  try "$good
just some words" "line 20: not KEY<TAB>value"
  try "$good
COLOUR${T}blue" "COLOUR (line 20): not a key setup knows"
  try "$good
ABCDEFGHIJKLMNOPQRSTUVWXYZ${T}x" "line 20: a key setup does not know, not shown"
  try "$(printf '%s\n' "$good" | sed "s/^PROJECT_WHAT${T}.*/PROJECT_WHAT${T}a${T}b/")" "PROJECT_WHAT (line 8): the value holds a TAB, a CR or another control character"
  try "$(printf '%s\n' "$good" | sed "s/^NEVER_WRONG${T}.*/NEVER_WRONG${T}x$(printf '\r')/")" "NEVER_WRONG (line 9): the value holds a TAB, a CR or another control character"
  try "$good
RULE${T}# >>> method-setup" "RULE (line 20): the value holds the text of a method block marker"
  try "$good
PRODUCT_PATH${T}../up" "PRODUCT_PATH: ../up is not a relative path"
  try "$good
PRODUCT_PATH${T}-rf" "PRODUCT_PATH: -rf is not a relative path"
  try "$good
RISK_PATH${T}scripts/method" "RISK_PATH: scripts/method names the method's own files"
  try "$(printf '%s\n' "$good" | sed "s/^PROFILE${T}.*/PROFILE${T}cheapest/")" "PROFILE: not one of best balanced budget"
  try "$good
TOUCHES${T}none" "TOUCHES: none stands alone"
  try "$(printf '%s\n' "$good" | sed "s/^TEST_COMMAND${T}.*/TEST_COMMAND${T}make test # quick/")" "TEST_COMMAND: the value holds a # that starts a shell comment"
  try "$(printf '%s\n' "$good" | grep -v '^DECIDES')" "DECIDES: not answered"
  try "$good
STRICT${T}strict" "STRICT (line 20): answered twice"
  if [ -z "$bad_cases" ]; then pass "$n (14 shapes)"; else fail "$n" "$bad_cases"; fi
fi

n="a token-shaped answer is refused, named by its key, and its value appears nowhere"
if wanted "$n"; then
  copy "$pnew" secret
  tok="ghp_$(perl -e 'print "A1b2C3d4E5" x 4')"
  printf '%s\n' "$good" | sed "s/^HOW_IT_STARTS${T}.*/HOW_IT_STARTS${T}bash app.sh --token $tok/" >"$c/.claude/setup-answers.txt"
  before=$(snap "$c")
  setup "$c"
  out1=$out
  code1=$code
  setup "$c" --write
  case "$out1$out" in *A1b2C3d4E5*) leaked=1 ;; *) leaked=0 ;; esac
  if [ "$code1" -eq 1 ] && [ "$code" -eq 1 ] && [ "$leaked" -eq 0 ] && has "HOW_IT_STARTS (line 13): the value looks like a key, a password or personal data" "it is not shown" "nothing was written" &&
    [ "$(snap "$c")" = "$before" ]; then pass "$n"; else no "$n" "exit $code1 then $code; leaked $leaked; $out"; fi
fi

n="a method deny entry removed by hand: --write is refused naming it, nothing is written, and method-files stays red"
if wanted "$n"; then
  copy "$pnew" deny
  (cd "$c" && perl -e 'require "./scripts/method/lib/lock.pl"; open my $h, "<", $ARGV[0] or die; my $d = (Json::decode(do { local $/; <$h> }))[0]; close $h;
    $d->{permissions}{deny} = [grep { $_ ne "mcp__*__merge_pull_request" } @{ $d->{permissions}{deny} }];
    open $h, ">", $ARGV[0] or die; print $h Lock::settings_json($d); close $h' .claude/settings.json)
  printf '%s\n' "$good" >"$c/.claude/setup-answers.txt"
  before=$(snap "$c")
  setup "$c" --write
  f=$(findings "$c")
  if [ "$code" -eq 1 ] && has "the method's deny entry mcp__*__merge_pull_request is missing from .claude/settings.json" "nothing was written" &&
    [ "$(snap "$c")" = "$before" ] && case "$f" in *"deny entry mcp__*__merge_pull_request is missing"*) true ;; *) false ;; esac; then
    pass "$n"
  else
    no "$n" "exit $code; findings: $f; $(printf '%s\n' "$out" | tail -3)"
  fi
fi

n="a key setup writes that is also set outside its block is refused and named"
if wanted "$n"; then
  copy "$pnew" twice
  printf 'PRODUCT_PATHS=.\n' >"$c/.claude/method.conf"
  printf '%s\n' "$good" >"$c/.claude/setup-answers.txt"
  before=$(snap "$c")
  setup "$c" --write
  if [ "$code" -eq 1 ] && has ".claude/method.conf sets PRODUCT_PATHS outside setup's block" "nothing was written" && [ "$(snap "$c")" = "$before" ]; then pass "$n"; else no "$n"; fi
fi

# rewrite FILE PERL-CODE: FILE put through perl -pe, without perl's -i
# (which needs a backup name on Windows)
rewrite() {
  perl -pe "$2" "$1" >"$1.new" && mv "$1.new" "$1"
}

n="a method input changed by hand (a template, method.lock's settings line): --write is refused naming it, and nothing is written"
if wanted "$n"; then
  r=""
  copy "$pnew" tmpl
  printf 'one more line\n' >>"$c/scripts/method/templates/AGENTS.md.tmpl"
  printf '%s\n' "$good" >"$c/.claude/setup-answers.txt"
  before=$(snap "$c")
  setup "$c" --write
  if [ "$code" -ne 1 ] || ! has "scripts/method/templates/AGENTS.md.tmpl differs from method.lock" "nothing was written" || [ "$(snap "$c")" != "$before" ]; then
    r="$r [a template] exit $code: $(printf '%s\n' "$out" | head -2 | tr '\n' ' ')"
  fi
  copy "$pnew" lockline
  rewrite "$c/scripts/method/method.lock" 's/^settings\t.*/"settings\t" . ("0" x 64)/e'
  printf '%s\n' "$good" >"$c/.claude/setup-answers.txt"
  before=$(snap "$c")
  setup "$c" --write
  if [ "$code" -ne 1 ] || ! has "method.lock's settings line does not match" "setup never rehashes it" "nothing was written" || [ "$(snap "$c")" != "$before" ]; then
    r="$r [the settings line] exit $code: $(printf '%s\n' "$out" | head -2 | tr '\n' ' ')"
  fi
  if [ -z "$r" ]; then pass "$n"; else fail "$n" "$r"; fi
fi

n="VERDICTS_FROM is main's tip only while main does not hold the method: a re-run after the install reached main sets none, and status still names the commit with no review line"
if wanted "$n"; then
  r=""
  copy "$pnew" history
  answers claude short small none standard best >"$c/.claude/setup-answers.txt"
  setup "$c" --write
  c1=$code
  (cd "$c" && git add -A && git commit -q -m "Install the method" -m "Review-Verdict: not-required - first install of the method v0.7.0" &&
    printf 'x\n' >other.txt && git add other.txt && git commit -q -m "a change with no trailer")
  answers claude short small none standard balanced >"$c/.claude/setup-answers.txt"
  setup "$c" --write
  st=$(cd "$c" && bash scripts/method/status.sh --quick 2>&1)
  if [ "$c1" -ne 0 ] || [ "$code" -ne 0 ] || grep -q '^VERDICTS_FROM=' "$c/.claude/method.conf" ||
    ! has "History: main already holds the method, so setup sets no VERDICTS_FROM" || ! printf '%s\n' "$st" | grep -q '^verdicts: LOOK - 1 commits'; then
    r="$r [after the install reached main] exit $c1 then $code; $(grep '^VERDICTS_FROM=' "$c/.claude/method.conf"); $(printf '%s\n' "$st" | grep '^verdicts:')"
  fi
  copy "$pold" history2
  answers claude short small none standard budget >"$c/.claude/setup-answers.txt"
  setup "$c" --write
  tip=$(cd "$c" && git rev-parse main)
  if [ "$code" -ne 0 ] || ! grep -q "^VERDICTS_FROM=$tip\$" "$c/.claude/method.conf" || ! has "History: VERDICTS_FROM is main's tip before the method"; then
    r="$r [an adopted project, main without the method] exit $code; $(grep '^VERDICTS_FROM=' "$c/.claude/method.conf")"
  fi
  if [ -z "$r" ]; then pass "$n"; else fail "$n" "$r"; fi
fi

n="a smoke row turned on stays on in a re-run with the same command, and the card says when a new command turns it off again"
if wanted "$n"; then
  r=""
  copy "$pnew" smoke
  printf '%s\n' "$good" >"$c/.claude/setup-answers.txt"
  setup "$c" --write
  rewrite "$c/checks/project.tsv" 's/^#smoke\t/smoke\t/'
  printf '%s\n' "$good" | sed "s/^PROFILE${T}.*/PROFILE${T}best/" >"$c/.claude/setup-answers.txt"
  setup "$c" --write
  if [ "$code" -ne 0 ] || ! grep -q "^smoke${T}any${T}.*bash app.sh --once" "$c/checks/project.tsv" || ! has "stays on, as it was turned on with the same command"; then
    r="$r [the same command] exit $code; $(grep 'smoke' "$c/checks/project.tsv" | tail -1)"
  fi
  printf '%s\n' "$good" | sed -e "s/^PROFILE${T}.*/PROFILE${T}best/" -e "s/^HOW_IT_STARTS${T}.*/HOW_IT_STARTS${T}bash app.sh --check/" >"$c/.claude/setup-answers.txt"
  setup "$c" --write
  if [ "$code" -ne 0 ] || ! grep -q "^#smoke${T}any${T}.*bash app.sh --check" "$c/checks/project.tsv" || grep -q "^smoke${T}" "$c/checks/project.tsv" ||
    ! has "has a new command, so it is off again"; then
    r="$r [a new command] exit $code; $(grep 'smoke' "$c/checks/project.tsv" | tail -1)"
  fi
  if [ -z "$r" ]; then pass "$n"; else fail "$n" "$r"; fi
fi

n="a row id setup turns on that checks/pack.tsv already uses is refused, naming the row, and nothing is written"
if wanted "$n"; then
  copy "$pnew" dupid
  mkdir -p "$c/checks"
  printf 'fast-tests\tany\t-\t^ok: (\\d+)\techo "ok: 1"\n' >"$c/checks/pack.tsv"
  printf '%s\n' "$good" >"$c/.claude/setup-answers.txt"
  before=$(snap "$c")
  setup "$c" --write
  if [ "$code" -eq 1 ] && has "checks/pack.tsv line 1 uses the id fast-tests, which setup's block in checks/project.tsv turns on" "leave TEST_COMMAND empty" "nothing was written" &&
    [ "$(snap "$c")" = "$before" ]; then pass "$n"; else no "$n"; fi
fi

n="a named path setup writes itself (checks, REVIEW.md) counts as there: HIGH_RISK_PATHS gets it on the first run, and a second run writes nothing"
if wanted "$n"; then
  copy "$pnew" seeded
  printf '%s\nRISK_PATH\tchecks\nRISK_PATH\tREVIEW.md\n' "$good" >"$c/.claude/setup-answers.txt"
  setup "$c" --write
  c1=$code
  missing=$(printf '%s\n' "$out" | grep 'Not there yet: ')
  setup "$c" --write
  if [ "$c1" -eq 0 ] && [ "$code" -eq 0 ] && has "WROTE 0 files" && grep -q '^HIGH_RISK_PATHS=checks$' "$c/.claude/method.conf" &&
    grep -q '^HIGH_RISK_PATHS=REVIEW.md$' "$c/.claude/method.conf" && case "$missing" in *checks* | *REVIEW.md*) false ;; *) true ;; esac; then
    pass "$n"
  else
    no "$n" "exit $c1 then $code; $missing; $(printf '%s\n' "$out" | tail -1)"
  fi
fi

n="settings.json laid out otherwise, with the profile unchanged, is left as it is"
if wanted "$n"; then
  copy "$pnew" layout
  # shellcheck disable=SC2016 # perl code
  perl -MJSON::PP -e 'local $/; my $d = JSON::PP->new->decode(<STDIN>); print JSON::PP->new->canonical->pretty->indent_length(4)->encode($d)' \
    <"$c/.claude/settings.json" >"$c/.claude/settings.json.new" && mv "$c/.claude/settings.json.new" "$c/.claude/settings.json"
  printf '%s\n' "$good" | sed "s/^PROFILE${T}.*/PROFILE${T}best/" >"$c/.claude/setup-answers.txt"
  s0=$(cksum <"$c/.claude/settings.json")
  setup "$c" --write
  f=$(findings "$c")
  if [ "$code" -eq 0 ] && [ "$(cksum <"$c/.claude/settings.json")" = "$s0" ] && has "unchanged .claude/settings.json" && [ -z "$f" ] &&
    ! has "Settings first"; then pass "$n"; else no "$n" "exit $code; findings: $f; $(printf '%s\n' "$out" | grep 'settings.json')"; fi
fi

n="a key of the project's own inside setup's method.conf block is refused on a re-run, named, and nothing is written"
if wanted "$n"; then
  copy "$pnew" ownkey
  printf '%s\n' "$good" >"$c/.claude/setup-answers.txt"
  setup "$c" --write
  c1=$code
  rewrite "$c/.claude/method.conf" '$_ .= "REPOS=other\n" if /^# >>> method-setup$/'
  before=$(snap "$c")
  setup "$c" --write
  if [ "$c1" -eq 0 ] && [ "$code" -eq 1 ] && has ".claude/method.conf sets REPOS inside setup's block" "nothing was written" &&
    [ "$(snap "$c")" = "$before" ]; then pass "$n"; else no "$n"; fi
fi

n="a copy left by a cut-off write (method.lock.setup-<pid>) is removed when setup writes that file again, and method-files then finds nothing"
if wanted "$n"; then
  copy "$pnew" leftover
  printf '%s\n' "$good" | sed "s/^PROFILE${T}.*/PROFILE${T}best/" >"$c/.claude/setup-answers.txt"
  setup "$c" --write
  c1=$code
  printf 'partial\n' >"$c/scripts/method/method.lock.setup-4242"
  printf '%s\n' "$good" | sed "s/^PROFILE${T}.*/PROFILE${T}balanced/" >"$c/.claude/setup-answers.txt"
  setup "$c" --write
  f=$(findings "$c")
  if [ "$c1" -eq 0 ] && [ "$code" -eq 0 ] && [ ! -e "$c/scripts/method/method.lock.setup-4242" ] && [ -z "$f" ]; then
    pass "$n"
  else
    no "$n" "exit $code; findings: $f; $(printf '%s\n' "$out" | tail -3)"
  fi
fi

n="a list answer left empty (RULE, PRODUCT_PATH, RISK_PATH) adds nothing: setup takes it and writes no empty rule"
if wanted "$n"; then
  copy "$pnew" emptylist
  {
    printf 'DECIDES\tclaude\nREPORTS\tshort\nPACE\tsmall\nTOUCHES\tnone\nSTRICT\tstandard\nPROFILE\tbest\n'
    printf 'PROJECT_WHAT\t\nNEVER_WRONG\t\nRULE\t\nRULE\t   \nHOW_IT_STARTS\t\nTEST_COMMAND\t\nPRODUCT_PATH\t\nRISK_PATH\t\n'
  } >"$c/.claude/setup-answers.txt"
  setup "$c" --write
  if [ "$code" -eq 0 ] && has "Your pack adds 0 rules." && ! grep -q '^- *$' "$c/.claude/rules/pack/project.md" &&
    ! grep -q '^HIGH_RISK_PATHS=$' "$c/.claude/method.conf"; then pass "$n"; else no "$n"; fi
fi

# the answers method-setup's SKILL.md asks for are the ones setup takes:
# each "KEY value" and "KEY" in brackets in the skill (alone, or in a list
# after a comma) is a key and closed value of lib/setup.pl (%CHOICES, @TOUCH
# and none, the profile names Lock::profiles reads from profiles.tsv, @TEXT,
# @MANY) and passes parse_answers, and each of those is in the skill
n="method-setup's SKILL.md asks for exactly the answer keys and values setup takes"
if wanted "$n"; then
  cat >"$work/skill-keys.pl" <<'SKILL-KEYS'
use strict; use warnings; no warnings "once";
my ($skill_f, $prof_f, $lib) = @ARGV;
require "$lib/setup.pl";
my $read = sub { open my $h, "<:raw", $_[0] or die "cannot read $_[0]\n"; local $/; my $t = <$h>; close $h; $t };
my $skill = $read->($skill_f);
my (undef, $names, $pp) = Lock::profiles($read->($prof_f));
die "profiles.tsv: @$pp\n" if @$pp;
my %want;
for my $k (keys %Setup::CHOICES) { $want{"$k $_"} = 1 for @{ $Setup::CHOICES{$k} } }
$want{"PROFILE $_"} = 1 for @$names;
$want{"TOUCHES $_"} = 1 for @Setup::TOUCH, "none";
$want{$_} = 1 for @Setup::TEXT, @Setup::MANY;
my %got;
$got{ defined $2 ? "$1 $2" : $1 } = 1 while $skill =~ /(?:\(|, )([A-Z][A-Z_]+)(?: ([a-z][a-z0-9-]*))?(?=[,)])/g;
my @bad;
push @bad, "the skill asks for $_, which setup does not take" for grep { !$want{$_} } sort keys %got;
push @bad, "the skill does not ask for $_" for grep { !$got{$_} } sort keys %want;
my %base = (map { ($_ => $Setup::CHOICES{$_}[0]) } keys %Setup::CHOICES);
$base{PROFILE} = $names->[0];
$base{TOUCHES} = "none";
for my $g (sort keys %got) {
  my ($k, $v) = split / /, $g;
  my %a = %base;
  my $extra = "";
  if (defined $v) { $a{$k} = $v } else { $extra = "$k\tsrc\n" }
  my ($ans, $p) = Setup::parse_answers(join("", map {"$_\t$a{$_}\n"} sort keys %a) . $extra, $names);
  push @bad, "$g: parse_answers refuses it: @$p" if @$p;
}
print "$_\n" for @bad;
print "keys and values: ", scalar(keys %got), "\n" unless @bad
SKILL-KEYS
  got=$(perl "$work/skill-keys.pl" "$root/method/.claude/skills/method-setup/SKILL.md" "$root/method/scripts/method/profiles.tsv" "$root/method/scripts/method/lib" 2>&1)
  case "$got" in
    "keys and values: "*) pass "$n (${got#keys and values: })" ;;
    *) fail "$n" "$got" ;;
  esac
fi

# --- a sample on disk: setup-write.sh, status and done-check ---
n1="a sample on disk: a dry run writes nothing, --write twice gives the same bytes, and method-files finds nothing"
n2="a sample on disk: status finds no records or config problem"
n3="a sample on disk: done-check finds no tier problem"
if wanted_any "$n1" "$n2" "$n3"; then
  r1=""
  r2=""
  r3=""
  k=0
  for spec in "new claude short small money+personal+outside strict budget" "new owner full larger none standard best" \
    "adopted claude short larger money+personal strict balanced" "adopted owner full small outside standard best"; do
    k=$((k + 1))
    # shellcheck disable=SC2086 # the spec's words are the arguments
    set -- $spec
    if [ "$1" = new ]; then
      copy "$pnew" "sample$k"
      (cd "$c" && git add -A && git commit -q -m "the method" && git checkout -q -b setup)
    else
      copy "$pold" "sample$k"
      (cd "$c" && git add -A && git commit -q -m "the method")
    fi
    shift
    answers "$@" >"$c/.claude/setup-answers.txt"
    before=$(snap "$c")
    setup "$c"
    c_dry=$code
    after_dry=$(snap "$c")
    setup "$c" --write
    c_w=$code
    once=$(snap "$c")
    setup "$c" --write
    c_w2=$code
    f=$(findings "$c")
    if [ "$c_dry" -ne 0 ] || [ "$after_dry" != "$before" ] || [ "$c_w" -ne 0 ] || [ "$c_w2" -ne 0 ] || [ "$(snap "$c")" != "$once" ] ||
      ! has "plan: 0 new, 0 block, 0 update," || [ -n "$f" ]; then
      r1="$r1
[$spec] exit $c_dry, $c_w, $c_w2; findings: $f; $(printf '%s\n' "$out" | tail -2 | tr '\n' ' ')"
    fi
    (cd "$c" && git add -A && git commit -q -m "setup")
    st=$(cd "$c" && bash scripts/method/status.sh --quick 2>&1)
    if ! printf '%s\n' "$st" | grep -q '^records: PASS - 9 records present; CLAUDE.md imports AGENTS.md' || printf '%s\n' "$st" | grep -q '^config:'; then
      r2="$r2
[$spec] $(printf '%s\n' "$st" | grep -e '^records:' -e '^config:')"
    fi
    dc=$(cd "$c" && bash scripts/method/done-check.sh --ready 2>&1)
    if ! printf '%s\n' "$dc" | grep -q '^done-check: tier: PASS'; then
      r3="$r3
[$spec] $(printf '%s\n' "$dc" | grep 'tier:')"
    fi
  done
  if wanted "$n1"; then if [ -z "$r1" ]; then pass "$n1 ($k)"; else fail "$n1" "$r1"; fi; fi
  if wanted "$n2"; then if [ -z "$r2" ]; then pass "$n2 ($k)"; else fail "$n2" "$r2"; fi; fi
  if wanted "$n3"; then if [ -z "$r3" ]; then pass "$n3 ($k)"; else fail "$n3" "$r3"; fi; fi
fi

drop_sandbox "$work" || true
echo "tests: setup: $tests_pass passed, $tests_fail failed, $tests_skip skipped ($(($(date +%s) - started)) s)"
[ "$tests_fail" -eq 0 ]
