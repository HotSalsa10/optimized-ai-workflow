#!/usr/bin/env perl
# The method's lock, scripts/method/method.lock (step 7.2; docs/plans/
# step7.md S2, S4, S5; DECISIONS A78; M010): which release of the method a
# project holds, and a fingerprint of every method file. This file is the
# one reader, writer and verifier of the lock (M048), and the one home of
# the method's paths (class M) and of the method's keys in
# .claude/settings.json (class K). Loaded with require (run-checks'
# built-in check method-files; the release's sync); nothing runs when it
# is loaded.
#
# The lock is LF text, one line each, in this order:
#   version<TAB>v0.7.0      the release's tag (session-status reads this
#                           first line with sh read, before perl starts)
#   source<TAB><commit>     the release's commit
#   profile<TAB>best        the project's profile
#   settings<TAB><sha256>   the hash of the method keys the release and the
#                           profile give (Lock::expected), never of the
#                           current settings.json
#   file<TAB><sha256><TAB><path>   one per method file, the release's
#                           settings.method.json among them; the lock
#                           itself is not listed
#
# The method's paths: every file under scripts/method/, .claude/hooks/
# method/, .claude/agents/method/, .claude/rules/method/ and docs/method/,
# and under .claude/skills/ every entry whose name starts with method-.
#
# The method's keys: every top-level key of scripts/method/
# settings.method.json but hooks, permissions and $schema, each equal as a
# whole; each of its permissions.deny entries present (the project's own
# entries are kept and never compared); any other permissions key equal;
# and the hook entries whose command names .claude/hooks/method/, the same
# set on the same events with the same matchers. The profile's row in
# scripts/method/profiles.tsv (step 7.3; step7.md S7) gives model,
# effortLevel and availableModels in place of the fragment's.
#
# profiles.tsv: # lines and blank lines skipped; each other line is a
# profile's name, a TAB, and one JSON object that sets exactly model,
# effortLevel and availableModels (the main session's only: the checking
# agents' own model and effort hold while claude-opus-5-5 is on the list,
# DECISIONS A78 F3). Its lint (Lock::profiles) refuses any other key, a
# list without claude-opus-5-5 (the gates would take the main session's
# model), a model missing from its own row's list (the session would fall
# back to Opus without a word), an effort other than low, medium, high or
# xhigh, and a
# best row that differs from settings.method.json.
#
#   Lock::load(ROOT) (LOCK, PROBLEMS): LOCK {version, source, profile,
#     settings, files => [[sha256, path], ...]}, or undef when the lock is
#     absent (PROBLEMS empty) or cannot be read (PROBLEMS say why).
#     Lock::parse(TEXT) the same for a lock's text in hand (setup-write's).
#   Lock::format_lock(LOCK) the lock's text from such a hash (setup-write
#     changes only its profile and settings lines with it, step 7.4).
#   Lock::settings_json(DATA) .claude/settings.json's one layout: UTF-8,
#     two-space indent, sorted keys, "key": value, exact numbers (step7.md
#     S6), written by the release's sync and by setup-write alike.
#   Lock::files(ROOT) (PATHS, PROBLEMS, BLOCKED): every file under the
#     method's paths, hidden ones too, sorted, the lock left out; PROBLEMS
#     are [KIND, TEXT]: a link under them (link), an entry that is not a
#     regular file or a folder that cannot be read (odd); a link on the way
#     to them is a link too, and then no file is listed (BLOCKED).
#   Lock::expected(ROOT, PROFILE) (K, PROBLEM): the method keys, from
#     ROOT's settings.method.json and profiles.tsv;
#     Lock::expected_from(FRAGMENT, PROFILES_TEXT, PROFILE) the same from
#     data in hand (the release's sync).
#   Lock::profiles(TEXT, FRAGMENT) (ROWS, NAMES, PROBLEMS): profiles.tsv
#     read and linted (above); FRAGMENT undef skips the best row's
#     comparison. Lock::profile(ROOT) (NAME, ROW): the project's profile,
#     from the lock's profile line and its row; (undef, undef) with no
#     lock, (NAME or '', undef) when either cannot be read.
#   Lock::refused(SETTINGS) ([KEY, TEXT], ...): what in a project's
#     settings a first install refuses unless it is named with --keep KEY
#     (step7.md S3): a hook of the project's own on an event @KEEP_EVENTS
#     names (it runs beside the guard, or its output reaches the checking
#     agents or every prompt), claudeMdExcludes, enabledPlugins, and each key that runs a
#     program (@Watch::RUNS, their one home). session-status names them.
#   Lock::k_hash(K): their SHA-256.
#   Lock::make(ROOT, VERSION, SOURCE, PROFILE) (TEXT, PROBLEM): a lock for
#     the method files now under ROOT; Lock::save(ROOT, TEXT, SUFFIX) writes
#     it (a new file, the lock's path and SUFFIX, renamed into place),
#     giving a problem or undef.
#   Lock::installed(ROOT): 1 unless there is no lock and nothing under the
#     method's paths (then the method is not installed there).
#   Lock::verify(ROOT): {examined => N, findings => [[KIND, TEXT], ...],
#     version}, KIND one of lock, changed, crlf, missing, extra, link,
#     odd, settings.
package Lock;
use strict;
use warnings;
use Fcntl qw(O_WRONLY O_CREAT O_EXCL);
use File::Basename qw(dirname);
use File::Spec;

my $lib = dirname(File::Spec->rel2abs(__FILE__));
require File::Spec->catfile($lib, $_) for qw(json.pl esc.pl);

our $LOCK = 'scripts/method/method.lock';
our $FRAGMENT = 'scripts/method/settings.method.json';
our $SETTINGS = '.claude/settings.json';
our @DIRS = qw(scripts/method .claude/hooks/method .claude/agents/method .claude/rules/method docs/method);
our ($SKILLS, $SKILL_PREFIX) = ('.claude/skills', 'method-');
our $HOOK_MARK = '.claude/hooks/method/';
# a tag, at most 23 characters, of the characters session-status accepts
our $VERSION_RE = qr/\Av[0-9][0-9A-Za-z.+-]{0,21}\z/;
our $PROFILES = 'scripts/method/profiles.tsv';
our $PROFILE_RE = qr/\A[a-z][a-z0-9-]{0,30}\z/;
our @PROFILE_KEYS = qw(availableModels effortLevel model);
# the client's effort levels, lowest first (G12 compares by this order)
our @EFFORTS = qw(low medium high xhigh max);
# the checking agents' model, which every profile's list must hold
our $GATE_MODEL = 'claude-opus-5-5';
# the hook events a first install refuses unless kept: those that run
# beside the guard or before it, and those whose output reaches the
# checking agents or every prompt (DECISIONS A79, A80)
our @KEEP_EVENTS = qw(PreToolUse PermissionRequest ConfigChange SessionStart SubagentStart SubagentStop UserPromptSubmit PostToolUse PostToolUseFailure PostToolBatch);
our @KEEP_KEYS = qw(claudeMdExcludes enabledPlugins);

sub sha_file {
  my ($path) = @_;
  require Digest::SHA;
  my $h = eval { Digest::SHA->new(256)->addfile($path, 'b')->hexdigest };
  return $h;
}

# method_path PATH: 1 when PATH (relative, with /) is under the method's paths
sub method_path {
  my ($p) = @_;
  return 1 if grep { index($p, "$_/") == 0 } @DIRS;
  return 1 if index($p, "$SKILLS/$SKILL_PREFIX") == 0;
  return 0;
}

# good_path PATH: a relative path with no empty, . or .. part, no control
# character and no backslash
sub good_path {
  my ($p) = @_;
  return 0 if !defined $p || $p eq '' || $p =~ /[\x00-\x1F\x7F\\]/ || $p =~ m{\A/};
  return !grep { $_ eq '' || $_ eq '.' || $_ eq '..' } split m{/}, $p, -1;
}

sub load {
  my ($root) = @_;
  my $path = File::Spec->catfile($root, $LOCK);
  return (undef, []) unless -e $path || -l $path;
  return (undef, ["$LOCK is a link or not a regular file"]) if -l $path || !-f _;
  open my $fh, '<:raw', $path or return (undef, ["$LOCK cannot be read"]);
  my $t = do { local $/; <$fh> };
  close $fh;
  return parse(defined $t ? $t : '');
}

sub parse {
  my ($t) = @_;
  return (undef, ["$LOCK holds a CR; it must have LF line ends (the .gitattributes method block is missing, or a line below it asks for CRLF)"]) if $t =~ /\r/;
  return (undef, ["$LOCK does not end with a line end, so it may be cut off"]) unless $t =~ /\n\z/;
  my @lines = split /\n/, $t;
  my (%l, @p, %seen);
  $l{files} = [];
  my @head = (['version', $VERSION_RE], ['source', qr/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/],
    ['profile', $PROFILE_RE], ['settings', qr/\A[0-9a-f]{64}\z/]);
  for my $i (0 .. $#head) {
    my ($k, $re) = @{ $head[$i] };
    my ($kk, $v) = split /\t/, ($lines[$i] // ''), 2;
    if (!defined $v || $kk ne $k || $v !~ $re) { push @p, "$LOCK line " . ($i + 1) . ": not a $k line"; next }
    $l{$k} = $v;
  }
  for my $n (scalar(@head) .. $#lines) {
    my @f = split /\t/, $lines[$n], -1;
    my $at = "$LOCK line " . ($n + 1);
    if (@f != 3 || $f[0] ne 'file' || $f[1] !~ /\A[0-9a-f]{64}\z/) { push @p, "$at: not a file line (file, a SHA-256, a path)"; next }
    if (!good_path($f[2]) || !method_path($f[2]) || $f[2] eq $LOCK) { push @p, "$at: the path is not one of the method's paths"; next }
    if ($seen{ $f[2] }++) { push @p, "$at: the path is listed twice"; next }
    push @{ $l{files} }, [$f[1], $f[2]];
  }
  push @p, "$LOCK does not list $FRAGMENT" unless @p || $seen{$FRAGMENT};
  return (@p ? undef : \%l, \@p);
}

sub files {
  my ($root) = @_;
  my (@files, @p);
  my $walk;
  $walk = sub {
    my ($rel) = @_;
    my $abs = File::Spec->catfile($root, $rel);
    my @st = lstat $abs;
    return unless @st;
    if (-l _) { push @p, ['link', 'a link: ' . Esc::line($rel)]; return }
    if (-f _) { push @files, $rel; return }
    if (!-d _) { push @p, ['odd', 'not a regular file: ' . Esc::line($rel)]; return }
    opendir my $d, $abs or do { push @p, ['odd', 'cannot read the folder ' . Esc::line($rel)]; return };
    my @e = sort grep { $_ ne '.' && $_ ne '..' } readdir $d;
    closedir $d;
    $walk->("$rel/$_") for @e;
  };
  # a link on the way to a method folder would point the method elsewhere
  my %up;
  for my $d (@DIRS, $SKILLS) {
    my @parts = split m{/}, $d;
    for my $i (0 .. $#parts - ($d eq $SKILLS ? 0 : 1)) {
      my $u = join '/', @parts[0 .. $i];
      next if $up{$u}++;
      push @p, ['link', "a link: $u"] if -l File::Spec->catfile($root, $u);
    }
  }
  return ([], \@p, 1) if @p;
  $walk->($_) for @DIRS;
  my $sk = File::Spec->catfile($root, $SKILLS);
  if (-d $sk && opendir my $d, $sk) {
    my @e = sort grep { index($_, $SKILL_PREFIX) == 0 } readdir $d;
    closedir $d;
    $walk->("$SKILLS/$_") for @e;
  }
  return ([sort grep { $_ ne $LOCK } @files], \@p);
}

# read_json PATH LABEL: (DATA, PROBLEM), DATA an object
sub read_json {
  my ($path, $label) = @_;
  return (undef, "$label is missing") unless -e $path || -l $path;
  return (undef, "$label is a link or not a regular file") if -l $path || !-f _;
  open my $fh, '<:raw', $path or return (undef, "$label cannot be read");
  my $t = do { local $/; <$fh> };
  close $fh;
  my ($d, $e) = Json::decode($t, 'plain');
  return (undef, "$label is not JSON") if defined $e;
  return (undef, "$label is not a JSON object") unless ref $d eq 'HASH';
  return ($d, undef);
}

# method_hooks SETTINGS: the hook entries whose command names the method's
# hooks folder, each as one string (event, matcher, the entry), sorted
sub method_hooks {
  my ($s) = @_;
  my @h;
  my $hooks = ref $s eq 'HASH' && ref $s->{hooks} eq 'HASH' ? $s->{hooks} : {};
  for my $ev (sort keys %$hooks) {
    next unless ref $hooks->{$ev} eq 'ARRAY';
    for my $g (@{ $hooks->{$ev} }) {
      next unless ref $g eq 'HASH' && ref $g->{hooks} eq 'ARRAY';
      for my $e (@{ $g->{hooks} }) {
        next unless ref $e eq 'HASH' && defined $e->{command} && !ref $e->{command} && index($e->{command}, $HOOK_MARK) >= 0;
        push @h, Json::encode([$ev, $g->{matcher}, $e]);
      }
    }
  }
  return [sort @h];
}

sub deny_of {
  my ($s) = @_;
  my $p = ref $s eq 'HASH' && ref $s->{permissions} eq 'HASH' ? $s->{permissions} : {};
  my %u = map { ($_ => 1) } grep { defined && !ref } (ref $p->{deny} eq 'ARRAY' ? @{ $p->{deny} } : ());
  return [sort keys %u];
}

# read_text PATH LABEL: (TEXT, PROBLEM); only a regular file is read
sub read_text {
  my ($path, $label) = @_;
  return (undef, "$label is missing") unless -e $path || -l $path;
  return (undef, "$label is a link or not a regular file") if -l $path || !-f _;
  open my $fh, '<:raw', $path or return (undef, "$label cannot be read");
  my $t = do { local $/; <$fh> };
  close $fh;
  return (defined $t ? $t : '', undef);
}

sub profiles {
  my ($text, $f) = @_;
  my (%rows, @names, @p);
  return ({}, [], ["$PROFILES holds a CR; it must have LF line ends"]) if $text =~ /\r/;
  my $n = 0;
  my %allowed = map { ($_ => 1) } @PROFILE_KEYS;
  # (a profile sets at most xhigh, so G12 reads no lock at xhigh or max)
  my %effort = map { ($_ => 1) } grep { $_ ne 'max' } @EFFORTS;
  for my $line (split /\n/, $text) {
    $n++;
    next if $line =~ /\A\s*(?:#|\z)/;
    my $at = "$PROFILES line $n";
    my ($name, $json) = split /\t/, $line, 2;
    if (!defined $json || $name !~ $PROFILE_RE) { push @p, "$at: not a profile line (a name, a TAB, a JSON object)"; next }
    if ($rows{$name}) { push @p, "$at: the profile $name is listed twice"; next }
    my ($d, $e) = Json::decode($json, 'plain');
    if (defined $e || ref $d ne 'HASH') { push @p, "$at: the profile $name is not one JSON object"; next }
    my @bad = grep { !$allowed{$_} } sort keys %$d;
    my @lacks = grep { !exists $d->{$_} } @PROFILE_KEYS;
    push @p, "$at: the profile $name sets " . join(', ', map { Esc::line($_) } @bad) . ', which a profile may not set (only ' . join(', ', @PROFILE_KEYS) . ')' if @bad;
    push @p, "$at: the profile $name does not set " . join(', ', @lacks) if @lacks;
    next if @bad || @lacks;
    my ($m, $ef, $list) = @$d{qw(model effortLevel availableModels)};
    my $ok = 1;
    if (!defined $m || ref $m || $m !~ /\Aclaude-[a-z0-9.-]{1,60}\z/) { push @p, "$at: the profile ${name}'s model is not a model id"; $ok = 0 }
    if (!defined $ef || ref $ef || !$effort{$ef}) { push @p, "$at: the profile ${name}'s effortLevel is not one of " . join(' ', grep { $effort{$_} } @EFFORTS); $ok = 0 }
    if (ref $list ne 'ARRAY' || grep { !defined || ref } @$list) { push @p, "$at: the profile ${name}'s availableModels is not a list of model ids"; next }
    if (!grep { $_ eq $GATE_MODEL } @$list) {
      push @p, "$at: the profile ${name}'s availableModels lacks $GATE_MODEL, so the checking agents would take the main session's model";
      $ok = 0;
    }
    if (defined $m && !ref $m && !grep { $_ eq $m } @$list) {
      push @p, "$at: the profile ${name}'s model is not on its own availableModels, so the session would fall back to Opus without a word";
      $ok = 0;
    }
    next unless $ok;
    $rows{$name} = $d;
    push @names, $name;
  }
  push @p, "$PROFILES has no best row" unless @p || $rows{best};
  if (ref $f eq 'HASH' && $rows{best}) {
    for my $k (@PROFILE_KEYS) {
      push @p, "$PROFILES: the best row's $k differs from ${FRAGMENT}'s"
        if !exists $f->{$k} || Json::encode([$f->{$k}]) ne Json::encode([$rows{best}{$k}]);
    }
  }
  return (\%rows, \@names, \@p);
}

sub expected_from {
  my ($f, $ptext, $profile) = @_;
  my ($rows, $names, $p) = profiles($ptext, $f);
  return (undef, $p->[0]) if @$p;
  return (undef, 'the profile ' . Esc::line($profile) . " is not one this release knows (@$names)") unless $rows->{$profile};
  my %k = (keys => {}, permissions => {}, deny => deny_of($f), hooks => method_hooks($f));
  $k{keys}{$_} = $f->{$_} for grep { $_ ne 'hooks' && $_ ne 'permissions' && $_ ne '$schema' } keys %$f;
  $k{keys}{$_} = $rows->{$profile}{$_} for @PROFILE_KEYS;
  if (ref $f->{permissions} eq 'HASH') {
    $k{permissions}{$_} = $f->{permissions}{$_} for grep { $_ ne 'deny' } keys %{ $f->{permissions} };
  }
  return (\%k, undef);
}

sub expected {
  my ($root, $profile) = @_;
  my ($f, $e) = read_json(File::Spec->catfile($root, $FRAGMENT), $FRAGMENT);
  return (undef, $e) if $e;
  my ($t, $te) = read_text(File::Spec->catfile($root, $PROFILES), $PROFILES);
  return (undef, $te) if $te;
  return expected_from($f, $t, $profile);
}

sub profile {
  my ($root) = @_;
  my $path = File::Spec->catfile($root, $LOCK);
  return (undef, undef) unless -e $path || -l $path;
  return ('', undef) if -l $path || !-f _;
  open my $fh, '<:raw', $path or return ('', undef);
  my @head;
  while (@head < 3 && defined(my $l = <$fh>)) { push @head, $l }
  close $fh;
  my ($name) = ($head[2] // '') =~ /\Aprofile\t([^\t\n]*)\n\z/;
  return ('', undef) unless defined $name && $name =~ $PROFILE_RE;
  my ($t, $te) = read_text(File::Spec->catfile($root, $PROFILES), $PROFILES);
  return ($name, undef) if $te;
  my ($rows, undef, $p) = profiles($t, undef);
  return ($name, @$p ? undef : $rows->{$name});
}

sub refused {
  my ($s) = @_;
  return () unless ref $s eq 'HASH';
  require File::Spec->catfile($lib, 'watch.pl');
  my @r;
  my $hooks = ref $s->{hooks} eq 'HASH' ? $s->{hooks} : {};
  for my $ev (@KEEP_EVENTS) {
    next unless ref $hooks->{$ev} eq 'ARRAY';
    my $n = 0;
    for my $g (@{ $hooks->{$ev} }) {
      next unless ref $g eq 'HASH' && ref $g->{hooks} eq 'ARRAY';
      $n += grep { !(ref $_ eq 'HASH' && defined $_->{command} && !ref $_->{command} && index($_->{command}, $HOOK_MARK) >= 0) } @{ $g->{hooks} };
    }
    push @r, [$ev, "$n $ev hook" . ($n == 1 ? '' : 's') . " of the project's own"] if $n;
  }
  push @r, map { [$_, $_] } grep { exists $s->{$_} } @KEEP_KEYS, do { no warnings 'once'; @Watch::RUNS };
  return @r;
}

sub settings_json {
  my ($d) = @_;
  require JSON::PP;
  return JSON::PP->new->utf8->canonical->pretty->indent_length(2)->space_before(0)->allow_bignum->encode($d);
}

sub k_hash {
  my ($k) = @_;
  require Digest::SHA;
  return Digest::SHA::sha256_hex(Json::encode($k));
}

# compare K SETTINGS: what differs between the method keys K and the
# settings SETTINGS, each a line naming the key, never its value
sub compare {
  my ($k, $s) = @_;
  my @w;
  for my $key (sort keys %{ $k->{keys} }) {
    if (!exists $s->{$key}) { push @w, "$SETTINGS lacks the method key " . Esc::line($key); next }
    push @w, "the method key " . Esc::line($key) . " in $SETTINGS differs from the release's"
      if Json::encode([$s->{$key}]) ne Json::encode([$k->{keys}{$key}]);
  }
  my $sp = ref $s->{permissions} eq 'HASH' ? $s->{permissions} : {};
  for my $key (sort keys %{ $k->{permissions} }) {
    push @w, "the method key permissions." . Esc::line($key) . " in $SETTINGS differs from the release's"
      if !exists $sp->{$key} || Json::encode([$sp->{$key}]) ne Json::encode([$k->{permissions}{$key}]);
  }
  my %have = map { ($_ => 1) } @{ deny_of($s) };
  push @w, map { "the method's deny entry " . Esc::line($_) . " is missing from $SETTINGS" } grep { !$have{$_} } @{ $k->{deny} };
  my (%want, %cur);
  $want{$_}++ for @{ $k->{hooks} };
  $cur{$_}++ for @{ method_hooks($s) };
  for my $h (sort keys %want) {
    next if ($cur{$h} || 0) >= $want{$h};
    my ($ev) = @{ (Json::decode($h, 'plain'))[0] };
    push @w, "a method hook on " . Esc::line($ev) . " is missing or changed in $SETTINGS";
  }
  for my $h (sort keys %cur) {
    next if ($want{$h} || 0) >= $cur{$h};
    my ($ev) = @{ (Json::decode($h, 'plain'))[0] };
    push @w, "a hook on " . Esc::line($ev) . " in $SETTINGS names $HOOK_MARK but is not one of the release's";
  }
  return @w;
}

sub format_lock {
  my ($l) = @_;
  return join '', "version\t$l->{version}\n", "source\t$l->{source}\n", "profile\t$l->{profile}\n", "settings\t$l->{settings}\n",
    map {"file\t$_->[0]\t$_->[1]\n"} sort { $a->[1] cmp $b->[1] } @{ $l->{files} };
}

sub make {
  my ($root, $version, $source, $profile) = @_;
  return (undef, 'the version is not a tag such as v0.7.0') unless defined $version && $version =~ $VERSION_RE;
  return (undef, 'the source is not a commit') unless defined $source && $source =~ /\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/;
  my ($files, $p) = files($root);
  return (undef, $p->[0][1]) if @$p;
  my ($k, $e) = expected($root, $profile);
  return (undef, $e) if $e;
  my @f;
  for my $rel (@$files) {
    my $h = sha_file(File::Spec->catfile($root, $rel));
    return (undef, 'cannot read ' . Esc::line($rel)) unless defined $h;
    push @f, [$h, $rel];
  }
  return (format_lock({ version => $version, source => $source, profile => $profile, settings => k_hash($k), files => \@f }), undef);
}

sub save {
  my ($root, $text, $suffix) = @_;
  my $path = File::Spec->catfile($root, $LOCK);
  my $tmp = $path . $suffix;
  unlink $tmp;
  sysopen my $fh, $tmp, O_WRONLY | O_CREAT | O_EXCL, 0644 or return "cannot write $LOCK";
  binmode $fh;
  my $ok = print {$fh} $text;
  $ok = close($fh) && $ok;
  if (!$ok || !rename $tmp, $path) { unlink $tmp; return "cannot write $LOCK" }
  return undef;
}

sub installed {
  my ($root) = @_;
  my $lock = File::Spec->catfile($root, $LOCK);
  return 1 if -e $lock || -l $lock;
  my ($disk, $fp) = files($root);
  return @$disk || @$fp ? 1 : 0;
}

sub verify {
  my ($root) = @_;
  my ($l, $lp) = load($root);
  my ($disk, $fp, $blocked) = files($root);
  my @f;
  push @f, @$fp;
  if (!$l) {
    push @f, map { ['lock', $_] } @$lp;
    push @f, ['lock', "$LOCK is missing, so the method's files cannot be compared with the release"] unless @$lp;
    return { examined => scalar(@$disk), findings => \@f };
  }
  my %on = map { ($_ => 1) } @$disk;
  my %listed;
  for my $e ($blocked ? () : @{ $l->{files} }) {
    my ($want, $rel) = @$e;
    $listed{$rel} = 1;
    my $abs = File::Spec->catfile($root, $rel);
    if (!$on{$rel}) {
      push @f, ['missing', 'missing: ' . Esc::line($rel)] unless -l $abs;
      next;
    }
    my $h = sha_file($abs);
    if (!defined $h) { push @f, ['changed', 'cannot read: ' . Esc::line($rel)]; next }
    next if $h eq $want;
    my $lf;
    if (open my $fh, '<:raw', $abs) {
      my $t = do { local $/; <$fh> };
      close $fh;
      require Digest::SHA;
      $lf = Digest::SHA::sha256_hex($t) if defined $t && $t =~ s/\r\n/\n/g;
    }
    if (defined $lf && $lf eq $want) {
      push @f, ['crlf', 'CRLF line ends: ' . Esc::line($rel) . ' (the .gitattributes method block is missing, or a line below it asks for CRLF)'];
    } else {
      push @f, ['changed', 'changed since the release: ' . Esc::line($rel)];
    }
  }
  push @f, map { ['extra', 'not in method.lock: ' . Esc::line($_)] } grep { !$listed{$_} } @$disk;
  my ($k, $ke) = expected($root, $l->{profile});
  if ($ke) {
    push @f, ['settings', "the method keys cannot be worked out: $ke"];
  } else {
    push @f, ['settings', "the lock's settings line does not match $FRAGMENT and the profile $l->{profile}"]
      if k_hash($k) ne $l->{settings};
    my ($s, $se) = read_json(File::Spec->catfile($root, $SETTINGS), $SETTINGS);
    if ($se) { push @f, ['settings', $se] }
    else { push @f, map { ['settings', $_] } compare($k, $s) }
  }
  return { examined => scalar(@{ $l->{files} }) + 1, findings => \@f, version => $l->{version} };
}

1;
