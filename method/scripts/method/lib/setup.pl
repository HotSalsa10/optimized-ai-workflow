#!/usr/bin/env perl
# setup-write's work (step 7.4; docs/plans/step7.md S2, S8, S9, S10;
# DECISIONS A78 (9), (10)), started by scripts/method/setup-write.sh, which
# gives the usage and the exit codes. Rules it holds:
# - M100: setup answers never lower the floor. No answer reaches a method
#   file (class M), a method key in .claude/settings.json (class K) but the
#   profile's three, the hooks, the deny list or a built-in check, and setup
#   refuses to write when the method's keys were changed by hand.
# - M156: setup writes only through setup-write, from the answers file
#   .claude/setup-answers.txt (class A), and never overwrites a project file
#   outside its block.
#
# The answers file: LF text, one KEY<TAB>value per line; blank lines and
# lines that start with # are skipped; the spaces around a value are
# dropped. The keys:
#   DECIDES      claude | owner      who decides technical choices
#   REPORTS      short | full        how much a report says
#   PACE         small | larger      the size of a step
#   TOUCHES      money | personal | outside | none   once per answer;
#                                    none stands alone
#   STRICT       standard | strict   strict: every change is high-risk
#   PROFILE      a profile in scripts/method/profiles.tsv (best,
#                balanced, budget)
#   PROJECT_WHAT, NEVER_WRONG, HOW_IT_STARTS, TEST_COMMAND: the person's own
#                words, once each, and may be empty
#   RULE, PRODUCT_PATH, RISK_PATH: once per item; a line with an empty
#                value adds nothing
# Refused before anything else, each naming its key or line: a line that is
# not KEY<TAB>value, an unknown key, a value holding a TAB, CR or other
# control character, a value holding a method block marker's text (>>>
# method or <<< method), a value Secrets::scan_bytes finds (named by its
# key and kind, the value never shown), a closed answer outside its
# choices, a key given twice that is given once, a closed key not answered,
# a path answer that breaks method.conf's path rules (lib/conf.pl) or
# names the method's own folders or git's, and a command answer holding a
# # that starts a shell comment (it would cut the check row short).
#
# What it may write (step7.md S2, S10), and nothing else:
# - the seeded files (class S), from scripts/method/templates/: each is
#   written only when absent. A template line holding {{KEY}} becomes the
#   file's method-setup block, with the answer put in; .claude/method.conf
#   gets its block at the end. An existing file keeps every byte outside
#   its block: the block is replaced when there is one; method.conf and
#   checks/project.tsv get one added at the end; CLAUDE.md without the line
#   @AGENTS.md gets one holding that line; any other existing file is kept
#   as it is, and the card names it.
# - the pack's two files, .claude/rules/pack/working.md and project.md
#   (class P): their blocks, from the closed answers and the rules.
# - the three profile keys (model, effortLevel, availableModels) in
#   .claude/settings.json, from the profile's row (Lock::expected_from),
#   and the lock's profile and settings lines (Lock::format_lock), the lock
#   written last.
# A block is the lines between "# >>> method-setup" and "# <<< method-setup"
# (in a .md file "<!-- >>> method-setup -->" and "<!-- <<< method-setup
# -->"), each there once, in that order.
# method.conf's block: PRODUCT_PATHS (the product paths that exist),
# VERDICTS_FROM (main's tip when main has commits and its tip does not hold
# method.lock yet, A37's move; once main holds the method, its install
# commit and what follows are history status judges, S17), and
# additions to HIGH_RISK_PATHS (. when strict, and the named risk paths
# that exist and hold a file), MUTATE_PATHS (the product paths, when
# strict) and MUTATION_CHECKS (fast-tests, when strict and there is a test
# command). An entry the last run wrote stays (setup never removes one) and
# the card names it, but MUTATION_CHECKS=fast-tests goes once there is no
# test command, with its row; VERDICTS_FROM, once written, stays. A key the block
# writes that the file also sets outside it is refused. A named path that
# does not exist is not written; the card names it (a seeded file or the
# pack's two count as there, as the run writes them). checks/project.tsv's
# block: the smoke row, off, but on when the block holds it turned on with
# the same command (the card says which); the row fast-tests, on, when
# there is a test command. A row id the block turns on that another row in
# checks/*.tsv uses is refused, naming the row. settings.json is written
# only when its data changes, not for its layout alone.
#
# Before it plans, setup refuses (naming the file or key): no method.lock;
# a lock that cannot be read; the release's settings.method.json,
# profiles.tsv or a template differing from the lock's hash (setup reads
# them); the lock's settings line differing from the keys the release and
# the lock's profile give (it is never rehashed); and any method key, hook
# or deny entry in .claude/settings.json differing from those keys, the
# three profile keys aside. So a weakened deny list stays red in
# method-files, never rehashed.
#
#   Setup::parse_answers(BYTES, PROFILE_NAMES) (ANSWERS, PROBLEMS)
#   Setup::detect(ROOT) {main_tip, main_has_method, langs => [[manifest,
#     language, row]], crlf => [tracked paths stored with CRLF line ends
#     that no attribute asks for]}
#   Setup::plan(ROOT, BYTES, DETECTED, OVERLAY) {problems, card, files
#     => [[word, path, note]], out => {path => content}}; OVERLAY {path =>
#     content} is read before the disk (the tests' second runs)
#   Setup::apply(ROOT, PLAN) undef, or what could not be written
#   Setup::template_target(NAME) a template's project path
package Setup;
use strict;
use warnings;
use Cwd ();
use Fcntl qw(O_WRONLY O_CREAT O_EXCL);
use File::Basename qw(basename dirname);
use File::Path ();
use File::Spec;

my $lib = dirname(File::Spec->rel2abs(__FILE__));
require File::Spec->catfile($lib, $_) for qw(esc.pl json.pl git.pl conf.pl lock.pl secrets.pl);

our $ANSWERS = '.claude/setup-answers.txt';
our $TEMPLATES = 'scripts/method/templates';
our $CONF = '.claude/method.conf';
our $CHECKS = 'checks/project.tsv';
our ($WORKING, $PROJECT) = ('.claude/rules/pack/working.md', '.claude/rules/pack/project.md');
our %CHOICES = (DECIDES => [qw(claude owner)], REPORTS => [qw(short full)], PACE => [qw(small larger)],
  STRICT => [qw(standard strict)]);
our @TOUCH = qw(money personal outside);
our @TEXT = qw(PROJECT_WHAT NEVER_WRONG HOW_IT_STARTS TEST_COMMAND);
our @MANY = qw(RULE PRODUCT_PATH RISK_PATH);
our ($SMOKE_ID, $TEST_ID) = qw(smoke fast-tests);
our @HASH_MARK = ('# >>> method-setup', '# <<< method-setup');
our @MD_MARK = ('<!-- >>> method-setup -->', '<!-- <<< method-setup -->');
# a manifest file at the top: the language, and checks/project.tsv's
# scanner row for it (offered off; the card suggests it)
our @LANGS = (['requirements.txt', 'Python', 'deps-python'], ['pyproject.toml', 'Python', 'deps-python'],
  ['package.json', 'JavaScript', 'deps-node'], ['go.mod', 'Go', 'deps-go'], ['Cargo.toml', 'Rust', 'deps-rust']);
# the five parts owner.md requires of every report
our $FIVE = 'a summary, a change summary, the actual check output, the risks and the verdict';
my %PROFILE_WORDS = (
  best => 'Best results (the default: Opus 5.5 at xhigh effort, the strongest checking of the work)',
  balanced => 'Balanced (cheaper; slower to catch subtle bugs)',
  budget => 'Budget (cheaper again; weaker on long or subtle work)',
);
my %TOUCH_WORDS = (money => 'money', personal => 'personal data', outside => 'records outside this repository');

sub template_target {
  my ($t) = @_;
  return $CONF if $t eq 'method.conf.tmpl';
  return '.github/pull_request_template.md' if $t eq 'pull_request_template.md.tmpl';
  (my $to = $t) =~ s/\.tmpl\z//;
  return $to;
}

sub marks { return $_[0] =~ /\.md\z/ ? @MD_MARK : @HASH_MARK }

# and_list WORDS: "a", "a and b", "a, b and c"
sub and_list {
  my @w = @_;
  return $w[0] if @w == 1;
  return join(', ', @w[0 .. $#w - 1]) . ' and ' . $w[-1];
}

sub parse_answers {
  my ($text, $profiles) = @_;
  my (%a, @p);
  my %one = map { ($_ => 1) } keys %CHOICES, 'PROFILE', @TEXT;
  my %many = map { ($_ => 1) } 'TOUCHES', @MANY;
  $text =~ s/\A\xEF\xBB\xBF//;
  my $n = 0;
  for my $line (split /\n/, $text) {
    $n++;
    next if $line eq '' || $line =~ /\A#/;
    my ($k, $v) = $line =~ /\A([A-Z][A-Z_]*)\t(.*)\z/s;
    if (!defined $k) { push @p, "line $n: not KEY<TAB>value"; next }
    if (!$one{$k} && !$many{$k}) {
      push @p, $k =~ /\A[A-Z_]{1,20}\z/ ? "$k (line $n): not a key setup knows"
        : "line $n: a key setup does not know, not shown: it does not look like a key name";
      next;
    }
    my $at = "$k (line $n)";
    if ($v =~ /[\x00-\x1F\x7F]/) { push @p, "$at: the value holds a TAB, a CR or another control character"; next }
    if ($v =~ /(?:>>>|<<<) method/) { push @p, "$at: the value holds the text of a method block marker"; next }
    if (my @s = Secrets::scan_bytes($v)) {
      push @p, "$at: the value looks like a key, a password or personal data ($s[0][0]); it is not shown";
      next;
    }
    $v =~ s/\A +//;
    $v =~ s/ +\z//;
    if ($one{$k}) {
      if (exists $a{$k}) { push @p, "$at: answered twice; it takes one answer"; next }
      $a{$k} = $v;
    } else {
      # a list answer left empty (RULE, PRODUCT_PATH, RISK_PATH) adds nothing
      next if $v eq '' && $k ne 'TOUCHES';
      push @{ $a{$k} }, $v;
    }
  }
  my %choices = (%CHOICES, PROFILE => $profiles);
  for my $k (sort keys %choices) {
    if (!defined $a{$k}) { push @p, "$k: not answered"; next }
    push @p, "$k: not one of " . join(' ', @{ $choices{$k} }) unless grep { $_ eq $a{$k} } @{ $choices{$k} };
  }
  my @t = @{ $a{TOUCHES} || [] };
  my %ok_touch = map { ($_ => 1) } @TOUCH, 'none';
  if (!@t) { push @p, 'TOUCHES: not answered' }
  elsif (my @bad = grep { !$ok_touch{$_} } @t) { push @p, 'TOUCHES: not one of ' . join(' ', @TOUCH, 'none') }
  elsif (grep { $_ eq 'none' } @t and @t > 1) { push @p, 'TOUCHES: none stands alone' }
  for my $k (qw(PRODUCT_PATH RISK_PATH)) {
    my @keep;
    for my $v (@{ $a{$k} || [] }) {
      my $c = Conf::check_path($v, 1);
      if (!defined $c) { push @p, "$k: " . Esc::line($v) . ' is not a relative path with no ., .. or empty part, no leading : or -, and none of * ? [ \\'; next }
      if (Lock::method_path("$c/x") || $c eq '.git' || index($c, '.git/') == 0) {
        push @p, "$k: " . Esc::line($c) . " names the method's own files or git's; setup lists only the project's own paths";
        next;
      }
      push @keep, $c unless grep { $_ eq $c } @keep;
    }
    $a{$k} = \@keep;
  }
  for my $k (qw(HOW_IT_STARTS TEST_COMMAND)) {
    push @p, "$k: the value holds a # that starts a shell comment, which would cut its check row short"
      if defined $a{$k} && $a{$k} =~ /(?:\A|\s)#/;
  }
  $a{$_} = defined $a{$_} ? $a{$_} : '' for @TEXT;
  $a{RULE} ||= [];
  my %t = map { ($_ => 1) } @t;
  $a{touch} = [grep { $t{$_} } @TOUCH];
  return (\%a, \@p);
}

sub detect {
  my ($root) = @_;
  my %d = (langs => [], crlf => []);
  my $cwd = Cwd::getcwd();
  if (chdir $root) {
    my ($top, $why) = Git::top();
    if (!defined $why) {
      my @m = Git::main_ref();
      if (@m) {
        $d{main_tip} = $m[1];
        # main already holds the method: its install commit is history that
        # status judges, so setup moves nothing past it (S17)
        $d{main_has_method} = (Git::run('cat-file', '-e', "$m[1]:$Lock::LOCK"))[0] == 0 ? 1 : 0;
      }
      # files git stores with CRLF line ends that no attribute asks for:
      # the .gitattributes method block asks for LF, but git keeps such a
      # file as stored until it is converted on purpose, so setup names
      # them on the card and changes none. git prints the attributes as
      # words with spaces between ("attr/text=auto eol=crlf"); a file
      # whose words hold -text (binary too) or eol=crlf is left out
      my ($st, $out) = Git::run('ls-files', '-z', '--eol');
      for my $rec ($st ? () : split /\0/, $out) {
        my ($info, $path) = split /\t/, $rec, 2;
        next unless defined $path && $info =~ m{\Ai/(?:crlf|mixed)\s};
        my ($attr) = $info =~ m{attr/(.*?)\s*\z};
        next if grep { $_ eq '-text' || $_ eq 'eol=crlf' } split /\s+/, ($attr // '');
        push @{ $d{crlf} }, $path;
      }
    }
    chdir $cwd;
  }
  for my $l (@LANGS) {
    next if grep { $_->[1] eq $l->[1] } @{ $d{langs} };
    push @{ $d{langs} }, $l if -f File::Spec->catfile($root, $l->[0]);
  }
  return \%d;
}

# block_split TEXT OPEN CLOSE: ('none'), ('broken'), or ('ok', BEFORE,
# INSIDE, AFTER)
sub block_split {
  my ($t, $open, $close) = @_;
  my @l = split /(?<=\n)/, $t;
  my @o = grep { $l[$_] =~ /\A\Q$open\E\r?\n?\z/ } 0 .. $#l;
  my @c = grep { $l[$_] =~ /\A\Q$close\E\r?\n?\z/ } 0 .. $#l;
  return ('none') if !@o && !@c;
  return ('broken') unless @o == 1 && @c == 1 && $c[0] > $o[0];
  return ('ok', join('', @l[0 .. $o[0] - 1]), join('', @l[$o[0] + 1 .. $c[0] - 1]), join('', @l[$c[0] + 1 .. $#l]));
}

sub block_text {
  my ($open, $close, $lines) = @_;
  return join '', map {"$_\n"} $open, @$lines, $close;
}

sub plan {
  my ($root, $text, $det, $ov) = @_;
  $ov ||= {};
  my (@p, @card, @files, %out, @no_block);
  my $r = { problems => \@p, card => \@card, files => \@files, out => \%out };
  my $abs = sub { File::Spec->catfile($root, split m{/}, $_[0]) };
  # a link, or a file where a folder belongs, on the way to REL
  my $link_on_way = sub {
    my @parts = split m{/}, $_[0];
    for my $i (0 .. $#parts) {
      my $u = join '/', @parts[0 .. $i];
      my $q = $abs->($u);
      return $u if -l $q || ($i < $#parts && -e $q && !-d _);
    }
    return undef;
  };
  # get REL: (TEXT or undef when absent, PROBLEM)
  my $get = sub {
    my ($rel) = @_;
    return ($ov->{$rel}, undef) if exists $ov->{$rel};
    my $l = $link_on_way->($rel);
    return (undef, "$rel: a link, or a file where a folder belongs, on its path (" . Esc::line($l) . ')') if defined $l;
    my $q = $abs->($rel);
    return (undef, undef) unless -e $q;
    my ($t, $e) = Lock::read_text($q, $rel);
    return ($t, $e);
  };
  # exists REL: on disk, or among the files this run or an earlier one
  # (the overlay) writes, the seeded files and the pack's two among them,
  # so a second run with the same answers finds what the first did; a
  # folder must hold a file, as git keeps no empty folder and done-check
  # reads the commit
  my %tmpl_text;
  my $exists = sub {
    my ($rel) = @_;
    return 1 if $rel eq '.';
    return 1 if grep { $_ eq $rel || index($_, "$rel/") == 0 } (grep { defined $ov->{$_} } keys %$ov), keys %tmpl_text, $WORKING, $PROJECT;
    my $q = $abs->($rel);
    return 0 if defined $link_on_way->($rel);
    return 1 if -f $q;
    return 0 unless -d $q;
    my $found = 0;
    my $walk;
    $walk = sub {
      my ($d) = @_;
      opendir my $dh, $d or return;
      my @e = grep { $_ ne '.' && $_ ne '..' } readdir $dh;
      closedir $dh;
      for my $e (@e) {
        last if $found;
        my $f = File::Spec->catfile($d, $e);
        next if -l $f;
        if (-f $f) { $found = 1; last }
        $walk->($f) if -d _ && $e ne '.git';
      }
    };
    $walk->($q);
    return $found;
  };

  # --- the lock and the method's inputs ---
  my ($lt, $le) = $get->($Lock::LOCK);
  if ($le) { push @p, $le; return $r }
  if (!defined $lt) { push @p, "$Lock::LOCK is missing: install the method with the release's sync first; setup writes only into a project the method is installed in"; return $r }
  my ($lock, $lp) = Lock::parse($lt);
  if (!$lock) { push @p, map {"$_ (method-files is red; run the release's sync)"} @$lp; return $r }
  my %hash = map { ($_->[1] => $_->[0]) } @{ $lock->{files} };
  my @tmpl = sort grep { index($_, "$TEMPLATES/") == 0 && /\.tmpl\z/ } keys %hash;
  my %in;
  for my $rel ($Lock::FRAGMENT, $Lock::PROFILES, @tmpl) {
    my $q = $abs->($rel);
    my $h = !defined $link_on_way->($rel) && -f $q ? Lock::sha_file($q) : undef;
    if (!defined $hash{$rel} || !defined $h || $h ne $hash{$rel}) {
      push @p, "$rel differs from method.lock or is missing (method-files is red); setup reads it, so it stops: put it back as the release has it";
      next;
    }
    ($in{$rel}) = Lock::read_text($q, $rel);
  }
  return $r if @p;
  my ($frag, $fe) = Json::decode($in{$Lock::FRAGMENT}, 'plain');
  if (defined $fe || ref $frag ne 'HASH') { push @p, "$Lock::FRAGMENT is not a JSON object"; return $r }
  my (undef, $names, $pp) = Lock::profiles($in{$Lock::PROFILES}, $frag);
  if (@$pp) { push @p, @$pp; return $r }
  my ($a, $ap) = parse_answers($text, $names);
  if (@$ap) { push @p, map {"$ANSWERS: $_"} @$ap; return $r }
  %tmpl_text = map { (template_target(substr($_, length("$TEMPLATES/"))) => $in{$_}) } @tmpl;

  # --- the method keys: refused when changed by hand ---
  my ($kc, $kce) = Lock::expected_from($frag, $in{$Lock::PROFILES}, $lock->{profile});
  if ($kce) { push @p, "the method keys for the lock's profile cannot be worked out: $kce"; return $r }
  if (Lock::k_hash($kc) ne $lock->{settings}) {
    push @p, "method.lock's settings line does not match $Lock::FRAGMENT and the profile $lock->{profile}; setup never rehashes it (method-files is red; run the release's sync)";
    return $r;
  }
  my ($st, $se) = $get->($Lock::SETTINGS);
  if ($se || !defined $st) { push @p, $se || "$Lock::SETTINGS is missing (method-files is red; run the release's sync)"; return $r }
  (my $sj = $st) =~ s/\A\xEF\xBB\xBF//;
  my ($s, $sde) = Json::decode($sj);
  if (defined $sde || ref $s ne 'HASH') { push @p, "$Lock::SETTINGS is not a JSON object"; return $r }
  # the settings as data: a file laid out otherwise but holding the same
  # keys and values is not rewritten
  my $s_was = Json::encode($s);
  my %kk = (%$kc, keys => { %{ $kc->{keys} } });
  delete $kk{keys}{$_} for @Lock::PROFILE_KEYS;
  push @p, map {"$_; setup never writes over a method key changed by hand (method-files is red: put the release's settings back, or run the release's sync)"}
    Lock::compare(\%kk, $s);
  return $r if @p;
  my ($kn, $kne) = Lock::expected_from($frag, $in{$Lock::PROFILES}, $a->{PROFILE});
  if ($kne) { push @p, $kne; return $r }
  $s->{$_} = $kn->{keys}{$_} for @Lock::PROFILE_KEYS;
  my $new_settings = Lock::settings_json($s);
  my $new_lock = Lock::format_lock({ %$lock, profile => $a->{PROFILE}, settings => Lock::k_hash($kn) });

  # --- method.conf's block ---
  my @strict = $a->{STRICT} eq 'strict' ? ('.') : ();
  my @product = grep { $exists->($_) } @{ $a->{PRODUCT_PATH} };
  my @no_product = grep { !$exists->($_) } @{ $a->{PRODUCT_PATH} };
  my @risk = grep { $exists->($_) } @{ $a->{RISK_PATH} };
  my @no_risk = grep { !$exists->($_) } @{ $a->{RISK_PATH} };
  my $test_row = $a->{TEST_COMMAND} ne '';
  my %new = (PRODUCT_PATHS => \@product, HIGH_RISK_PATHS => [@strict, @risk],
    MUTATE_PATHS => $a->{STRICT} eq 'strict' ? \@product : [], MUTATION_CHECKS => $a->{STRICT} eq 'strict' && $test_row ? [$TEST_ID] : []);
  my @conf_keys = qw(PRODUCT_PATHS VERDICTS_FROM HIGH_RISK_PATHS MUTATE_PATHS MUTATION_CHECKS);
  my ($ct, $cte) = $get->($CONF);
  if ($cte) { push @p, $cte; return $r }
  my ($old_v, $outside_text) = ({}, defined $ct ? $ct : '');
  if (defined $ct) {
    my ($w, $before, $inside, $after) = block_split($ct, @HASH_MARK);
    if ($w eq 'broken') { push @p, "$CONF: its method-setup block is broken (\"$HASH_MARK[0]\" and \"$HASH_MARK[1]\" must each be there once, in that order)"; return $r }
    if ($w eq 'ok') {
      ($old_v) = Conf::read_text($inside, "$CONF (setup's block)");
      $outside_text = $before . $after;
    }
  }
  # a key of the project's own inside the block would be lost on the
  # rewrite: refuse, naming it
  my %ours = map { ($_ => 1) } @conf_keys;
  for my $k (sort grep { !$ours{$_} } keys %$old_v) {
    push @p, "$CONF sets $k inside setup's block, which setup rewrites with its own keys only; move that line out of the"
      . ' block (through a reviewed change), then run setup again';
  }
  return $r if @p;
  my (@conf_lines, @kept, @dropped, $tip, $kept_from);
  for my $k (@conf_keys) {
    if ($k eq 'VERDICTS_FROM') {
      # main's tip only while it does not hold the method, so the install
      # and what follows it stay judged (S17)
      $tip = $det->{main_has_method} ? undef : $det->{main_tip};
      my $v = defined $old_v->{$k} ? $old_v->{$k} : $tip;
      $kept_from = $v if defined $old_v->{$k} && (!defined $tip || $tip ne $v);
      push @conf_lines, "$k=$v" if defined $v;
      next;
    }
    my @n = @{ $new{$k} };
    my %seen = map { ($_ => 1) } @n;
    my @old = grep { !$seen{$_}++ } @{ $old_v->{$k} || [] };
    # (setup's own MUTATION_CHECKS=fast-tests goes with its fast-tests row,
    # so mutate-changed is not left naming a check that is gone)
    if ($k eq 'MUTATION_CHECKS' && !$test_row && grep { $_ eq $TEST_ID } @old) {
      @old = grep { $_ ne $TEST_ID } @old;
      push @dropped, "$k=$TEST_ID";
    }
    my @all = (@n, @old);
    push @kept, map {"$k=$_"} @old;
    push @conf_lines, map {"$k=$_"} @all;
  }
  my ($ov_v) = Conf::read_text($outside_text, $CONF);
  my %written = map { /\A([A-Z_]+)=/ ? ($1 => 1) : () } @conf_lines;
  for my $k (grep { $written{$_} } @conf_keys) {
    push @p, "$CONF sets $k outside setup's block, and setup writes $k in its block; a key is set in one place: move that line into"
      . ' the block or remove it (through a reviewed change), then run setup again' if exists $ov_v->{$k};
  }
  return $r if @p;

  # --- the blocks' lines, by the placeholder their template holds ---
  # the lines turned on in checks/project.tsv's block now: a smoke row the
  # owner turned on stays on while its command is the same
  my (%on_now, $smoke);
  my ($ck) = $get->($CHECKS);
  if (defined $ck) {
    my ($w, undef, $inside) = block_split($ck, @HASH_MARK);
    if ($w eq 'ok') {
      for my $l (split /\n/, $inside) { $l =~ s/\r\z//; $on_now{$l} = 1 if $l !~ /\A[ \t]*(?:#|\z)/ }
    }
  }
  my $or = sub { $_[0] ne '' ? $_[0] : $_[1] };
  my %fill = (
    PROJECT_WHAT => sub {
      (my $l = $_[0]) =~ s{\{\{PROJECT_WHAT\}\}}{$or->($a->{PROJECT_WHAT}, 'What this project is: not written yet; run /method-setup again to set it.')}e;
      return ($l);
    },
    NEVER_WRONG => sub {
      (my $l = $_[0]) =~ s{\{\{NEVER_WRONG\}\}}{$or->($a->{NEVER_WRONG}, 'What must never go wrong: not written yet; run /method-setup again to set it.')}e;
      my %t = map { ($_ => 1) } @{ $a->{touch} };
      return ($l, $t{money} ? '- Money moved, rounded or recorded wrongly.' : (),
        $t{personal} ? '- Personal data shown, logged, kept or sent where it should not be.' : (),
        $t{outside} ? '- A write to records outside this repository without a stated reason, or without a dry run first.' : ());
    },
    TEST_COMMAND => sub {
      # (the smoke row is named even while it is off, so turning it on, as
      # the card says, leaves TESTS.md naming every check)
      return ($test_row ? "- `$TEST_ID`: the project's fast tests, the command /method-setup was given ($CHECKS)" : (),
        $a->{HOW_IT_STARTS} ne '' ? "- `$SMOKE_ID`: the project starts, is checked once and stops, by how it starts as /method-setup was given it ($CHECKS; off until its # is removed)" : ());
    },
    HOW_IT_STARTS => sub {
      my @l;
      if ($a->{HOW_IT_STARTS} ne '') {
        (my $l = $_[0]) =~ s{\{\{HOW_IT_STARTS\}\}}{$a->{HOW_IT_STARTS}};
        (my $on = $l) =~ s/\A#//;
        if ($on_now{$on}) { push @l, $on; $smoke = 'on' }
        else { push @l, $l; $smoke = (grep { index($_, "$SMOKE_ID\t") == 0 } keys %on_now) ? 'off again' : 'off' }
      }
      else { push @l, '# How the project starts was not answered; run /method-setup again to add its smoke row.' }
      push @l, "$TEST_ID\tany\t-\t^$TEST_ID: (\\d+) run\t$a->{TEST_COMMAND} && echo \"$TEST_ID: 1 run passed\"" if $test_row;
      return @l;
    },
  );
  # block_lines TARGET: the lines of TARGET's block, or () when it has none
  my $block_lines = sub {
    my ($target) = @_;
    return [@conf_lines] if $target eq $CONF;
    return ['@AGENTS.md'] if $target eq 'CLAUDE.md';
    my $t = $tmpl_text{$target};
    return () unless defined $t;
    my ($line) = grep {/\{\{[A-Z_]+\}\}/} split /\n/, $t;
    return () unless defined $line;
    my ($key) = $line =~ /\{\{([A-Z_]+)\}\}/;
    return [$fill{$key}->($line)];
  };

  # --- the seeded files ---
  for my $target (sort keys %tmpl_text) {
    my $t = $tmpl_text{$target};
    my @other = grep { !$fill{$_} } $t =~ /\{\{([A-Z_]+)\}\}/g;
    if (@other) { push @p, "the template for $target holds {{$other[0]}}, which setup does not fill (a defect in the release)"; next }
    my ($open, $close) = marks($target);
    my ($cur, $e) = $get->($target);
    if ($e) { push @p, $e; next }
    if (!defined $cur) {
      my $new = '';
      for my $l (split /(?<=\n)/, $t) {
        if ($l =~ /\{\{[A-Z_]+\}\}/) { $new .= block_text($open, $close, $block_lines->($target)) }
        else { $new .= $l }
      }
      $new .= block_text($open, $close, \@conf_lines) if $target eq $CONF;
      $out{$target} = $new;
      push @files, ['new', $target];
      next;
    }
    my ($w, $before, undef, $after) = block_split($cur, $open, $close);
    if ($w eq 'broken') { push @p, "$target: its method-setup block is broken (\"$open\" and \"$close\" must each be there once, in that order)"; next }
    my ($bl) = $block_lines->($target);
    my $imports = grep {/\A\@AGENTS\.md[ \t]*\r?\z/} split /\n/, $cur;
    # (a CLAUDE.md that imports AGENTS.md needs no block)
    $bl = undef if $target eq 'CLAUDE.md' && $w eq 'none' && $imports;
    if ($w eq 'ok' && $bl) {
      my $new = $before . block_text($open, $close, $bl) . $after;
      if ($new eq $cur) { push @files, ['unchanged', $target] }
      else { $out{$target} = $new; push @files, ['block', $target, "its method-setup block; the rest kept"] }
      next;
    }
    if ($bl && ($target eq $CONF || $target eq $CHECKS || $target eq 'CLAUDE.md')) {
      $out{$target} = $cur . ($cur eq '' || $cur =~ /\n\z/ ? '' : "\n") . block_text($open, $close, $bl);
      push @files, ['block', $target, $target eq 'CLAUDE.md' ? 'it did not import AGENTS.md: the line @AGENTS.md added in a method-setup block'
        : 'a method-setup block added at its end; the rest kept'];
      next;
    }
    push @files, ['kept', $target, 'there already; setup never replaces it' . ($bl ? ', and it has no method-setup block, so its answers are not added' : '')];
    push @no_block, $target if $bl;
  }

  # --- the pack's two files ---
  my %t = map { ($_ => 1) } @{ $a->{touch} };
  my @working = (
    $a->{DECIDES} eq 'claude'
      ? '- Who decides: the owner decides plans and merges; Claude decides the other technical choices and tells the owner in one line.'
      : '- Who decides: the owner decides plans, merges and technical choices; Claude asks each time, with the options and a recommendation.',
    $a->{REPORTS} eq 'short'
      ? "- Reports: short: the decisions and the results, still with the five parts owner.md requires ($FIVE)."
      : "- Reports: full: the decisions, the results and how the work was done, with the five parts owner.md requires ($FIVE).",
    $a->{PACE} eq 'small'
      ? '- Pace: small steps, one change at a time.'
      : '- Pace: larger steps: a task may hold several related changes in one feature area; each is still planned, checked and reviewed.',
    $t{money} ? "- Real money: a change to how money is moved, rounded or recorded is high-risk; the folders that hold it are listed in HIGH_RISK_PATHS in $CONF." : (),
    $t{personal} ? "- Personal data: a change to how personal data is kept, shown or sent is high-risk; the folders that hold it are listed in HIGH_RISK_PATHS in $CONF." : (),
    $t{outside} ? '- Records outside this repository: a script that writes to them sources scripts/method/live-write.sh, states its reason with --reason and does a dry run unless --live is given.' : (),
    $a->{STRICT} eq 'strict' ? '- Strict: every change takes the full route, with three reviewers (HIGH_RISK_PATHS holds .).' : (),
  );
  my @rules = @{ $a->{RULE} } ? map {"- $_"} @{ $a->{RULE} } : ('- None yet; run /method-setup again to add them.');
  my %pack = (
    $WORKING => ["# How this project is worked on\n\nWritten by /method-setup from the owner's answers ($ANSWERS); run it again to change them."
      . " A conflict with a method rule is settled as .claude/rules/method/method.md says (M151, under \"The method is on\").\n\n", \@working],
    $PROJECT => ["# The project's own rules\n\nRules that must always hold in this project, in the owner's words, from /method-setup."
      . " A conflict with a method rule is settled as .claude/rules/method/method.md says (M151, under \"The method is on\").\n\n", \@rules],
  );
  for my $target (sort keys %pack) {
    my ($head, $lines) = @{ $pack{$target} };
    my ($cur, $e) = $get->($target);
    if ($e) { push @p, $e; next }
    if (!defined $cur) { $out{$target} = $head . block_text(@MD_MARK, $lines); push @files, ['new', $target]; next }
    my ($w, $before, undef, $after) = block_split($cur, @MD_MARK);
    if ($w eq 'broken') { push @p, "$target: its method-setup block is broken (\"$MD_MARK[0]\" and \"$MD_MARK[1]\" must each be there once, in that order)"; next }
    my $new = $w eq 'ok' ? $before . block_text(@MD_MARK, $lines) . $after
      : $cur . ($cur eq '' || $cur =~ /\n\z/ ? '' : "\n") . block_text(@MD_MARK, $lines);
    if ($new eq $cur) { push @files, ['unchanged', $target] }
    else { $out{$target} = $new; push @files, ['block', $target, 'its method-setup block; the rest kept'] }
  }
  return $r if @p;

  # --- a row id setup's block turns on, used again in checks/*.tsv ---
  my %answer_of = ($TEST_ID => 'TEST_COMMAND', $SMOKE_ID => 'HOW_IT_STARTS');
  my %ids;
  for my $l (@{ $block_lines->($CHECKS) || [] }) { $ids{$1} = 1 if $l =~ /\A([^#\t][^\t]*)\t/ }
  my @tsv;
  if (opendir my $dh, $abs->('checks')) { @tsv = sort grep { /\A[^.].*\.tsv\z/s && !-l $abs->("checks/$_") && -f _ } readdir $dh; closedir $dh }
  for my $name (@tsv) {
    my $rel = "checks/$name";
    my $t = exists $out{$rel} ? $out{$rel} : ($get->($rel))[0];
    next unless defined $t;
    my ($w) = block_split($t, @HASH_MARK);
    my $n = 0;
    my $in_block = 0;
    for my $l (split /\n/, $t) {
      $n++;
      (my $x = $l) =~ s/\r\z//;
      $x =~ s/\A\xEF\xBB\xBF// if $n == 1;
      if ($rel eq $CHECKS && $w eq 'ok') {
        if ($x eq $HASH_MARK[0]) { $in_block = 1; next }
        if ($x eq $HASH_MARK[1]) { $in_block = 0; next }
        next if $in_block;
      }
      next if $x =~ /\A[ \t]*(?:#|\z)/;
      my ($id) = split /\t/, $x;
      push @p, "$rel line $n uses the id $id, which setup's block in $CHECKS turns on; rename that row (a reviewed change) or leave "
        . ($answer_of{$id} || 'its answer') . ' empty, then run setup again' if $ids{$id};
    }
  }
  return $r if @p;

  # --- the settings and the lock, last ---
  if (Json::encode($s) ne $s_was) { $out{$Lock::SETTINGS} = $new_settings; push @files, ['update', $Lock::SETTINGS, "the profile's model, effortLevel and availableModels only"] }
  else { push @files, ['unchanged', $Lock::SETTINGS] }
  if ($new_lock ne $lt) { $out{$Lock::LOCK} = $new_lock; push @files, ['update', $Lock::LOCK, 'its profile and settings lines only, written last'] }
  else { push @files, ['unchanged', $Lock::LOCK] }
  for my $rel (sort keys %out) {
    my $l = $link_on_way->($rel);
    push @p, "$rel: a link, or a file where a folder belongs, on its path (" . Esc::line($l) . ')' if defined $l && !exists $ov->{$rel};
  }
  return $r if @p;

  # --- the card (fixed words; tests/setup.test.sh holds them) ---
  my $pname = $PROFILE_WORDS{ $a->{PROFILE} } || $a->{PROFILE};
  if ($a->{PROFILE} ne $lock->{profile}) {
    push @card, "Settings first: $Lock::SETTINGS gets the profile's model and effort. In a session with the method's hooks the guard"
      . ' refuses applying that change at once, so it applies from your next session.';
  }
  push @card, $a->{DECIDES} eq 'claude'
    ? ('You decide: plans and merges.', 'Claude decides: other technical choices, and tells you in one line.')
    : ('You decide: plans, merges and technical choices.', 'Claude decides: nothing on its own; it asks you each time, with the options and a recommendation.');
  push @card, $a->{REPORTS} eq 'short' ? 'Reports: short (decisions and results, still with the five parts every report has).'
    : 'Reports: full (decisions, results and how the work was done, with the five parts every report has).';
  push @card, $a->{PACE} eq 'small' ? 'Pace: small steps, one change at a time.' : 'Pace: larger steps, each still planned, checked and reviewed.';
  push @card, 'Every change gets: checks, an independent review, a security check.';
  my @tw = map { $TOUCH_WORDS{$_} } grep { $_ ne 'outside' } @{ $a->{touch} };
  # (from the HIGH_RISK_PATHS written, kept entries among them)
  my @hr = map { /\AHIGH_RISK_PATHS=(.*)\z/ ? $1 : () } @conf_lines;
  if ($a->{STRICT} eq 'strict') {
    push @card, 'Extra for every change (strict): three reviewers.';
  } elsif (grep { $_ eq '.' } @hr) {
    push @card, 'Extra for every change (HIGH_RISK_PATHS keeps . from an earlier run): three reviewers.';
  } elsif (@hr) {
    push @card, 'Extra for ' . (@tw ? and_list(@tw) : 'the paths named') . ' (' . join(', ', @hr) . '): three reviewers.';
  } elsif (@tw) {
    push @card, ucfirst(and_list(@tw)) . ': no folder that holds it is listed yet, so no change is high-risk by its path; name its folder'
      . ' when it exists.';
  }
  push @card, 'Records outside this repository: a script that writes to them states its reason and does a dry run first'
    . ' (scripts/method/live-write.sh).' if $t{outside};
  push @card, 'Not there yet: ' . join(', ', @no_risk) . '; add each to HIGH_RISK_PATHS in .claude/method.conf when the folder exists.' if @no_risk;
  push @card, 'Not there yet as product paths: ' . join(', ', @no_product) . '; add each to PRODUCT_PATHS when it exists.' if @no_product;
  push @card, "Profile: $pname"
    . ($a->{PROFILE} ne $lock->{profile} ? ", in place of $lock->{profile}, which method.lock names now (to keep it, answer PROFILE $lock->{profile})" : '')
    . ". The checking agents stay on Opus 5.5 at xhigh effort in every profile; when a check misses something, step up a profile.";
  my $rules = @{ $a->{RULE} } ? ': ' . join('; ', @{ $a->{RULE} }) : '';
  push @card, 'Your pack adds ' . scalar(@{ $a->{RULE} }) . ' rule' . (@{ $a->{RULE} } == 1 ? '' : 's') . $rules . ($rules =~ /[.!?]\z/ ? '' : '.');
  push @card, 'Changed from the method\'s default: reports are short (the one thing a pack may change).' if $a->{REPORTS} eq 'short';
  push @card, "The smoke row (how it starts) is in $CHECKS, off: once its command starts the project, checks it once and stops, remove its #."
    if ($smoke || '') eq 'off';
  push @card, "The smoke row (how it starts) in $CHECKS stays on, as it was turned on with the same command." if ($smoke || '') eq 'on';
  push @card, "The smoke row (how it starts) in $CHECKS has a new command, so it is off again: once that command starts the project, checks"
    . ' it once and stops, remove its #.' if ($smoke || '') eq 'off again';
  push @card, "The fast tests run in every check run (the row $TEST_ID in $CHECKS)." if $test_row;
  # (a checks/project.tsv that was there before setup lacks the template's
  # scanner rows, so the card gives the row itself)
  my $ck_now = exists $out{$CHECKS} ? $out{$CHECKS} : ($get->($CHECKS))[0];
  for my $l (@{ $det->{langs} }) {
    my $found = "Found $l->[1] ($l->[0]): the suggested scanner row is $l->[2]";
    if (defined $ck_now && $ck_now =~ /^#?\Q$l->[2]\E\t/m) { push @card, "$found, offered off in $CHECKS; install its tool, then turn it on."; next }
    my ($row) = map { substr($_, 1) } grep { index($_, "#$l->[2]\t") == 0 } split /\n/, $tmpl_text{$CHECKS};
    push @card, "$found, which $CHECKS does not hold (it was there before setup): install its tool, then add this row to $CHECKS or"
      . " checks/pack.tsv: $row";
  }
  if (my @crlf = @{ $det->{crlf} || [] }) {
    my @named = map { Esc::line($_) } @crlf[0 .. ($#crlf < 2 ? $#crlf : 2)];
    push @card, 'Line ends: ' . scalar(@crlf) . (@crlf == 1 ? ' file is' : ' files are') . ' stored with CRLF line ends: ' . join(', ', @named)
      . (@crlf > 3 ? ' and ' . (@crlf - 3) . ' more' : '') . '. The .gitattributes method block asks for LF, but git keeps such a file as'
      . ' it is stored until it is converted on purpose (git add --renormalize FILE, then commit it); setup changes none.';
  }
  if (defined $tip && grep { $_ eq "VERDICTS_FROM=$tip" } @conf_lines) {
    push @card, 'History: VERDICTS_FROM is main\'s tip before the method, so status checks review lines from the install on.';
  } elsif ($det->{main_has_method} && !grep {/\AVERDICTS_FROM=/} @conf_lines) {
    push @card, 'History: main already holds the method, so setup sets no VERDICTS_FROM and status checks main\'s review lines as they'
      . ' are; moving VERDICTS_FROM is your own reviewed change.';
  }
  push @card, "Kept from an earlier run (setup removes none, apart from its own MUTATION_CHECKS=$TEST_ID when its row goes): "
    . join(', ', @kept) . ". To drop one, delete its line inside the method-setup block of $CONF in a reviewed change; setup does not"
    . ' put it back.' if @kept;
  push @card, "Kept from an earlier run: VERDICTS_FROM=$kept_from. If its line is deleted (a reviewed change), setup writes main's"
    . ' current tip in its place while main lacks the method, and none once main holds it.' if defined $kept_from;
  push @card, 'Dropped: ' . join(', ', @dropped) . ", as the $TEST_ID row it names is gone (no fast tests were given)." if @dropped;
  push @card, "Kept as it was: $_ (it was there already, with no method-setup block, so its answers are not added)." for @no_block;
  push @card, 'Added: the line @AGENTS.md to CLAUDE.md, in a method-setup block, so AGENTS.md loads.'
    if grep { $_->[0] eq 'block' && $_->[1] eq 'CLAUDE.md' } @files;
  my @name = (($test_row ? "`$TEST_ID`" : ()), ($a->{HOW_IT_STARTS} ne '' ? "`$SMOKE_ID`" : ()));
  push @card, 'TESTS.md was there before: name ' . join(' and ', @name) . ' in it.' if @name && grep { $_->[0] eq 'kept' && $_->[1] eq 'TESTS.md' } @files;
  push @card, 'Takes effect: files now; the profile from your next session.';
  return $r;
}

# put ROOT REL CONTENT: a new file beside REL, renamed into place
sub put {
  my ($root, $rel, $content) = @_;
  my $q = File::Spec->catfile($root, split m{/}, $rel);
  eval { File::Path::make_path(dirname($q)); 1 } or return "cannot make the folder for $rel";
  my $tmp = "$q.setup-$$";
  # a copy left beside REL by a run that was cut off goes first
  my $dir = dirname($q);
  my $base = basename($q);
  if (opendir my $dh, $dir) {
    unlink map { File::Spec->catfile($dir, $_) } grep { /\A\Q$base\E\.setup-[0-9]+\z/ } readdir $dh;
    closedir $dh;
  }
  sysopen my $fh, $tmp, O_WRONLY | O_CREAT | O_EXCL, 0644 or return "cannot write $rel";
  binmode $fh;
  my $ok = print {$fh} $content;
  $ok = close($fh) && $ok;
  if (!$ok || !rename $tmp, $q) { unlink $tmp; return "cannot write $rel" }
  return undef;
}

sub apply {
  my ($root, $plan) = @_;
  my %o = %{ $plan->{out} };
  # the settings, then the lock, last: a run cut off between them leaves
  # profile keys the next run puts right
  for my $rel ((sort grep { $_ ne $Lock::SETTINGS && $_ ne $Lock::LOCK } keys %o), grep { exists $o{$_} } $Lock::SETTINGS, $Lock::LOCK) {
    my $e = put($root, $rel, $o{$rel});
    return $e if $e;
  }
  return undef;
}

sub say_line { print 'setup: ', Esc::line(join '', @_), "\n" }

sub main {
  my $write = 0;
  for my $arg (@_) {
    if ($arg eq '--write' && !$write) { $write = 1; next }
    print "setup: usage: bash scripts/method/setup-write.sh [--write]\n";
    return 2;
  }
  my $root = Cwd::realpath(File::Spec->catdir($lib, File::Spec->updir, File::Spec->updir, File::Spec->updir));
  my $af = File::Spec->catfile($root, split m{/}, $ANSWERS);
  my ($text, $te) = Lock::read_text($af, $ANSWERS);
  if ($te) {
    say_line("REFUSED - $te; /method-setup writes it from the answers; nothing was written");
    return 1;
  }
  my $plan = plan($root, $text, detect($root), {});
  if (@{ $plan->{problems} }) {
    say_line("REFUSED - $_") for @{ $plan->{problems} };
    my $n = @{ $plan->{problems} };
    say_line("REFUSED - $n problem" . ($n == 1 ? '' : 's') . '; nothing was written. Retype each answer named above in'
      . ' /method-setup (or put back what is named), then run setup again');
    return 1;
  }
  say_line('the card for ', $ANSWERS, ':');
  print '  ', Esc::line($_), "\n" for @{ $plan->{card} };
  for my $f (@{ $plan->{files} }) {
    say_line(sprintf('%-9s %s', $f->[0], $f->[1]) . (defined $f->[2] ? " ($f->[2])" : ''));
  }
  my %c;
  $c{ $_->[0] }++ for @{ $plan->{files} };
  say_line('plan: ' . join(', ', map { ($c{$_} || 0) . " $_" } qw(new block update unchanged kept)));
  if (!$write) {
    say_line('dry run - nothing written; when the owner agrees with the card, run again with --write');
    return 0;
  }
  my $e = apply($root, $plan);
  if ($e) {
    say_line("FAIL - $e; run setup again with --write to finish");
    return 1;
  }
  my $n = keys %{ $plan->{out} };
  say_line("WROTE $n file" . ($n == 1 ? '' : 's') . "; commit them with $ANSWERS, and review the change like any other");
  return 0;
}

# Loaded with require: nothing runs.
return 1 if caller;
exit main(@ARGV);
