#!/usr/bin/env perl
# gate-receipt's perl part (step 5b; docs/plans/step5b.md, sections 1 and
# 2). .claude/hooks/method/gate-receipt.sh runs it with the hook's JSON
# input on standard input, at three events of a checking agent (a "gate";
# the gates are listed in verdicts.txt, never spelled here, M039):
# - SubagentStart: the start is recorded (the worktree's top, HEAD, its
#   tree, whether the files are exactly HEAD's, the method's file for the
#   gate) and the gate is told, through additionalContext, the line its
#   report must end with: "METHOD-ACTIVE gate=<name> tree=<tree>". A
#   running file in git's folder says a gate runs, so the guard marks the
#   writes made meanwhile (B8).
# - PreToolUse of SubagentHandback (auto mode, B7): a report without its
#   lines is refused once with a plain reason; the second time it is let
#   through and the receipt says so.
# - SubagentStop: the report is judged (B2: its first line opens with one
#   of the gate's words, its last line is exactly the end key and the
#   start's tree); a report without its lines is sent back once (B6:
#   exit 2, only in default mode, only when no handback was seen and no
#   reason known at the start already makes the receipt the second word);
#   then the evidence (step 5b.2): the files again (clean, the same tree),
#   the guard's write marks in the gate's window, and the agent's record,
#   waited for at most 5 s (B9: every model on the project's
#   availableModels, every effort at least the method file's; B10: the
#   instructions the gate ran with are the method file's body; no Agent or
#   Task call; no other folder; no background shell of its own still
#   running; no packet for another tree; the handback the record holds is
#   the one noted). Then the receipt is written, and one fixed-field line
#   goes to .method/local/gates.log.
# A receipt is one JSON file per gate run in git's common folder
# (method-receipt-<16 hex for session and agent><8 hex for the run
# number>.json, which G6 protects), written whole, the newest 500 kept. A
# start makes the agent's next run; a handback and a stop take its newest
# run. (Not the prompt id: the client gives the session's id for the
# owner's current message, so a background gate's stop after the owner's
# next message carries another one; measured at 2.1.316 and 2.1.319.) Its
# state is one of the receipt words: the first (every check holds), the
# second (it checked the wrong thing or the wrong way: any reason in
# %WRONG), the third (not checked: any other reason), with reason codes,
# never text. A run whose start was not recorded is the third word at every
# stop ("no-start"), never sent back. Each stop first writes the third word
# with the reason "judging", so a crash never leaves an earlier first word
# standing. Anything that goes wrong is exit 0 (B11): at SubagentStop an
# exit 2 sends the gate back to work, and at the handback a refusal on
# every crash would loop; only a deliberate block exits 3, which the
# wrapper turns into 2.
# Also loaded with require: Receipt::mark (the guard's write mark, B8) and
# Receipt::counts (session-status's line on the receipts for HEAD's tree).
# Known limits: a record, a receipt or a mark changed by a program Claude
# writes and runs (RISKS #2), and the agent's record by any write, a plain
# sed -i or Edit included (G6 does not protect ~/.claude/projects); a
# handback the client delivers with a warning that its check could not run
# (the hook cannot see it); the record's format as measured at 2.1.316 and
# 2.1.319 (a change reads as not checked, or, for its cwd and the Bash
# tool's background-shell text, can hide a reason; another form of model
# or effort reads as the second word); the stop's folder is the main
# session's, so the files are judged at the stop only when it is the
# worktree the gate started in (otherwise not checked); a packet read only
# in part (no Tree line) reads as another tree's; a write the guard lets
# through but the permission prompt or the tool then refuses still marks;
# delegation other than an Agent or Task call (a Skill that forks into an
# agent) is not seen; user memory and rules files can add instructions
# B10 does not compare; a start that takes over 30 s leaves its run not
# checked.
package Receipt;
use strict;
use warnings;
use Fcntl qw(O_RDONLY);
use File::Basename qw(dirname);
use File::Spec;
use Digest::SHA ();
use Time::HiRes ();

my $lib = dirname(File::Spec->rel2abs(__FILE__));
require File::Spec->catfile($lib, 'hook.pl');
require File::Spec->catfile($lib, 'git.pl');
require File::Spec->catfile($lib, 'log.pl');
require File::Spec->catfile($lib, 'verdicts.pl');

our $KEEP = 500;                          # receipts kept (B4)
our $LOG = '.method/local/gates.log';      # one fixed-field line a gate run
our $LOG_CAP = 1000;
our $CONTEXT_MAX = 120;                    # the start's context line, in bytes (B3)
our $MAX = 1024 * 1024;                    # a receipt is small
our $PREFIX = 'method-receipt-';
our $RUNNING = 'method-running-';          # a gate runs: one file a run (B8)
our $MARKS = 'method-write-marks';         # the guard's write marks (B8)
our $MARKS_CAP = 1000;
our $STALE = 24 * 3600;                    # a running file older than this was left by a crash
our $WAIT = 5;                             # seconds to wait for the agent's record
our $POLL = 0.05;
our $RECORD_MAX = 200 * 1024 * 1024;       # the largest record read
our $FILE_MAX = 1024 * 1024;               # the settings file, a method agent file
my $NONBLOCK = eval { Fcntl::O_NONBLOCK() } || 0;
my %RANK = (low => 1, medium => 2, high => 3, xhigh => 4, max => 5);
# the reasons that make a receipt the second word (it checked the wrong
# thing or the wrong way); every other reason makes it the third
my %WRONG = map { $_ => 1 } qw(unclean-start unclean-stop tree-changed write-mark instructions-differ
  effort-low model-off-list called-agent other-folder packet-other-tree);

# the words, from verdicts.txt: the gates and the kind each opens with,
# each kind's words, the end key, and the three receipt words in order
my %W;
sub words {
  return \%W if %W;
  my @rows = Verdicts::rows();
  my %gate = map { $_->[0] => $_->[1] } Verdicts::gates(@rows);
  my %open = map { $_ => [Verdicts::words($_, @rows)] } values %gate;
  my ($end) = Verdicts::words('end-key', @rows);
  my @state = Verdicts::words('receipt', @rows);
  die "receipt: verdicts.txt lacks the receipt words\n" unless @state == 3 && defined $end;
  %W = (gate => \%gate, open => \%open, end => $end, good => $state[0], wrong => $state[1], unchecked => $state[2]);
  return \%W;
}

sub id_ok { my ($s) = @_; return defined $s && !ref $s && $s =~ /\A[A-Za-z0-9_.-]{1,128}\z/ }
sub sha { return Digest::SHA::sha256_hex(Hook::bytes(join "\0", @_)) }
sub secs { return 0 + sprintf('%.3f', $_[0]) }

# the project: CLAUDE_PROJECT_DIR (bytes), else the input's cwd
sub project {
  my ($in) = @_;
  my $p = $ENV{CLAUDE_PROJECT_DIR};
  $p = Hook::bytes($in->{cwd}) if (!defined $p || $p eq '') && defined $in->{cwd} && !ref $in->{cwd};
  return defined $p && $p ne '' && -d $p ? $p : undef;
}

# the folder the gate works in: the input's cwd (bytes), else the project
sub cwd_of {
  my ($in, $project) = @_;
  return defined $in->{cwd} && !ref $in->{cwd} && $in->{cwd} ne '' ? Hook::bytes($in->{cwd}) : $project;
}

# git's common folder of DIR, absolute, or undef outside a repository
sub store {
  my ($dir) = @_;
  return undef unless defined $dir;
  my ($st, $out) = Git::run('-C', $dir, 'rev-parse', '--git-common-dir');
  return undef if $st;
  my ($c) = split /\n/, $out;
  return undef unless defined $c && $c ne '';
  $c = File::Spec->rel2abs($c, $dir);
  # (where .git links to a store elsewhere, the folder it names: the
  # writer refuses to write through a link)
  require Cwd;
  my $real = Cwd::realpath($c);
  return defined $real && -d $real ? $real : undef;
}

# HEAD and its tree in DIR: (HEAD, TREE), or ('none', 'none')
sub tree_of {
  my ($dir) = @_;
  return ('none', 'none') unless defined $dir && $dir ne '' && -d $dir;
  my ($st, $head) = Git::run('-C', $dir, 'rev-parse', '-q', '--verify', 'HEAD^{commit}');
  return ('none', 'none') if $st || $head !~ /\A([0-9a-f]{40}|[0-9a-f]{64})\n\z/;
  $head = $1;
  my ($st2, $tree) = Git::run('-C', $dir, 'rev-parse', '-q', '--verify', "$head^{tree}");
  return ($head, 'none') if $st2 || $tree !~ /\A([0-9a-f]{40}|[0-9a-f]{64})\n\z/;
  return ($head, $1);
}

# G: the worktree at DIR. top: its top folder as device-inode (never a
# path); path: that folder; clean: 1 when its files are exactly HEAD's
# (Checks::fingerprint: nothing staged, changed or untracked, untracked
# files in .method/local aside), 0 when not, undef when it cannot be told;
# HEAD and its tree (from the fingerprint's HEAD, so HEAD cannot move in
# between)
sub look {
  my ($dir) = @_;
  my %g = (top => undef, path => undef, clean => undef, head => 'none', tree => 'none');
  return \%g unless defined $dir && $dir ne '' && -d $dir;
  require Cwd;
  my $back = Cwd::getcwd();
  eval {
    chdir $dir or die "receipt: cannot enter the folder\n";
    my ($top, $why) = Git::top();
    die "receipt: not a worktree's own folder\n" unless defined $top && !defined $why;
    chdir $top or die "receipt: cannot enter the top\n";
    my @st = stat '.';
    @g{qw(top path)} = ("$st[0]-$st[1]", $top) if @st;
    require File::Spec->catfile($lib, 'checks.pl');
    my $fp = Checks::fingerprint();
    my $tree = $fp->{head} eq 'none' ? 'none' : Tree::root_tree($fp->{head});
    die "receipt: no tree\n" unless $tree =~ /\A(?:[0-9a-f]{40}|[0-9a-f]{64}|none)\z/;
    @g{qw(head tree clean)} = ($fp->{head}, $tree, (keys %{ $fp->{e} }) ? 0 : 1);
    1;
  };
  @g{qw(head tree)} = tree_of($dir) unless defined $g{clean};
  chdir $back if defined $back;
  return \%g;
}

sub trimmed { my ($s) = @_; $s =~ s/\A\s+//; $s =~ s/\s+\z//; return $s }

# the method's own file for GATE in the worktree at TOP
# (.claude/agents/method/GATE.md): {sha, effort, body}, where body is the
# text after the frontmatter, trimmed as the client trims the system
# prompt it builds from it, and effort its frontmatter's effort level
# (undef when it has none); undef when the file is missing, not a regular
# file, over 1 MB or not UTF-8
sub method_file {
  my ($top, $gate) = @_;
  return undef unless defined $top;
  my $p = File::Spec->catfile($top, '.claude', 'agents', 'method', "$gate.md");
  return undef unless -f $p && -s _ <= $FILE_MAX;
  open my $h, '<:raw', $p or return undef;
  my $bytes = do { local $/; <$h> };
  close $h;
  return undef unless defined $bytes;
  my $text = $bytes;
  return undef unless utf8::decode($text);
  $text =~ s/\A\x{FEFF}//;
  my ($fm, $body) = $text =~ /\A---[ \t]*\r?\n(.*?)^---[ \t]*\r?(?:\n|\z)(.*)\z/ms ? ($1, $2) : ('', $text);
  my ($effort) = $fm =~ /^effort[ \t]*:[ \t]*["']?([A-Za-z]+)["']?[ \t]*\r?$/m;
  $effort = undef unless defined $effort && $RANK{$effort};
  return { sha => Digest::SHA::sha256_hex($bytes), effort => $effort, body => trimmed($body) };
}

# the project's availableModels (.claude/settings.json), as a list
sub allowed_models {
  my ($project) = @_;
  return () unless defined $project;
  my $p = File::Spec->catfile($project, '.claude', 'settings.json');
  return () unless -f $p && -s _ <= $FILE_MAX;
  open my $h, '<:raw', $p or return ();
  my $text = do { local $/; <$h> };
  close $h;
  return () unless defined $text;
  $text =~ s/\A\xEF\xBB\xBF//;
  my ($d) = Json::decode($text, 'plain');
  return () unless ref $d eq 'HASH' && ref $d->{availableModels} eq 'ARRAY';
  return grep { defined && !ref && $_ ne '' } @{ $d->{availableModels} };
}

sub agent_part { my ($sid, $aid) = @_; return substr(sha('receipt', $sid, $aid), 0, 16) }
# a run's receipt and running file: the agent's part, then the run number
# in 8 hex
sub name_of { my ($part, $run) = @_; return $PREFIX . $part . sprintf('%08x', $run) . '.json' }
sub running_of { my ($part, $run) = @_; return $RUNNING . $part . sprintf('%08x', $run) }

# the agent PART's newest run in DIR: the highest run number among its
# receipts and running files (a start writes its running file first), or 0
sub newest {
  my ($dir, $part) = @_;
  opendir my $d, $dir or return 0;
  my $n = 0;
  for (readdir $d) {
    next unless /\A(?:\Q$PREFIX$part\E([0-9a-f]{8})\.json|\Q$RUNNING$part\E([0-9a-f]{8}))\z/;
    my $k = hex(defined $1 ? $1 : $2);
    $n = $k if $k > $n;
  }
  closedir $d;
  return $n;
}

# a receipt: the hash, or undef when there is none or it cannot be read
sub load {
  my ($dir, $name) = @_;
  my $path = File::Spec->catfile($dir, $name);
  return undef if -l $path || !-f _ || -s _ > $MAX;
  open my $h, '<:raw', $path or return undef;
  local $/;
  my $text = <$h>;
  close $h;
  my ($r) = Json::decode($text, 'plain');
  return ref $r eq 'HASH' && ($r->{v} // 0) == 1 ? $r : undef;
}

sub save {
  my ($dir, $name, $r) = @_;
  Log::write_whole($dir, $name, Json::encode($r), 0600);
  eval { Log::keep_newest($dir, $PREFIX, '.json', $KEEP, $name) };
  return 1;
}

# --- the running files and the write marks (B8) ---

# the names of the running files in DIR that are less than a day old;
# with PRUNE, the older ones are removed
sub running {
  my ($dir, $prune) = @_;
  opendir my $d, $dir or return ();
  my @n = grep { /\A\Q$RUNNING\E[0-9a-f]{24}\z/ } readdir $d;
  closedir $d;
  my $old = Time::HiRes::time() - $STALE;
  my @fresh;
  for my $n (@n) {
    my $p = File::Spec->catfile($dir, $n);
    next unless (lstat $p) && -f _;
    my @st = Time::HiRes::stat($p);
    if (@st && $st[9] >= $old) { push @fresh, $n } elsif ($prune) { unlink $p }
  }
  return @fresh;
}

# the nearest folder at or above D that exists
sub near_dir {
  my ($d) = @_;
  for (1 .. 64) {
    return $d if -d $d;
    my $up = dirname($d);
    return undef if $up eq $d;
    $d = $up;
  }
  return undef;
}

# B8: the guard calls this for a call it lets through that writes, as G6
# counts it (Protect::call_writes). When the call is the main session's or
# an agent's that is not a gate, and a gate runs in the repository it
# writes in (a running file less than a day old in git's folder), one line
# goes to method-write-marks there: the time and the worktree's top. A
# write in a checked-out submodule marks each repository that holds it
# too, up to $SUPER levels, with that repository's worktree top: a gate's
# clean check counts the submodules. Prints nothing; dies on a failure,
# which the guard's eval catches.
our $SUPER = 4;
sub mark {
  my ($in, $tool, $input) = @_;
  my $type = $in->{agent_type};
  # (a gate's own calls never mark)
  return 0 if defined $type && !ref $type && exists words()->{gate}{$type};
  my $project = $ENV{CLAUDE_PROJECT_DIR};
  my $cwd = cwd_of($in, defined $project && $project ne '' ? $project : undef);
  my @dirs;
  # (an edit tool marks the worktree of the file it writes; any other call
  # the worktree it runs in)
  if ($tool =~ /\A(?:Edit|Write|MultiEdit|NotebookEdit)\z/ && ref $input eq 'HASH') {
    for my $k (qw(file_path notebook_path)) {
      my $p = $input->{$k};
      next unless defined $p && !ref $p && $p ne '';
      $p = Hook::bytes($p);
      $p = File::Spec->rel2abs($p, $cwd) unless File::Spec->file_name_is_absolute($p) || !defined $cwd;
      push @dirs, near_dir(dirname($p));
    }
  }
  @dirs = ($cwd) unless grep { defined } @dirs;
  my %done;
  require Cwd;
  for my $from (grep { defined && -d } @dirs) {
    my $d = $from;
    for (1 .. $SUPER) {
      my ($st, $out) = Git::run('-C', $d, 'rev-parse', '--show-toplevel', '--git-common-dir', '--show-superproject-working-tree');
      last if $st;
      my ($top, $common, $super) = split /\n/, $out;
      last unless defined $common && $common ne '' && defined $top && $top ne '';
      my $real = Cwd::realpath(File::Spec->rel2abs($common, $d));
      my @t = stat $top;
      if (defined $real && -d $real && running($real) && @t && !$done{"$real\0$t[0]-$t[1]"}++) {
        Log::append($real, $MARKS, $MARKS_CAP, at => sprintf('%.6f', Time::HiRes::time()), top => "$t[0]-$t[1]");
      }
      # (the repository this one is a checked-out submodule of)
      last unless defined $super && $super ne '' && -d $super;
      $d = $super;
    }
  }
  return 0;
}

# 1 when a write mark lies strictly inside the gate's window (its start to
# this stop) in its own worktree, 0 when none does, undef when the marks
# cannot be read
sub marked {
  my ($dir, $r) = @_;
  my ($lines) = eval { Log::lines($dir, $MARKS, [qw(at top)]) };
  return undef unless $lines;
  for my $l (@$lines) {
    return 1 if $l->[2] eq $r->{top} && $l->[1] > $r->{started} && $l->[1] < $r->{stopped};
  }
  return 0;
}

# --- the report's lines (B2) ---

# the lines of TEXT that are not blank, each without its trailing spaces,
# tabs and CR
sub nonblank {
  my ($text) = @_;
  return grep { /\S/ } map { my $x = $_; $x =~ s/[ \t\r]+\z//; $x } split /\n/, $text;
}

# B2: (1, OPENING WORD) when the report opens with one of the gate's words
# and ends with "<end key> <tree>"; (0, REASON CODE) otherwise
sub lines_ok {
  my ($report, $gate, $tree) = @_;
  my $w = words();
  return (0, 'no-report') unless defined $report && !ref $report;
  my @l = nonblank($report);
  return (0, 'no-report') unless @l;
  my ($first, $last) = ($l[0], $l[-1]);
  my ($word) = grep { $first eq $_ || index($first, "$_ ") == 0 || index($first, "$_:") == 0 } @{ $w->{open}{ $w->{gate}{$gate} } || [] };
  return (0, 'lines-missing') unless defined $word && $last eq "$w->{end} $tree";
  return (1, $word);
}

# the plain reason a block or a refusal gives: both exact lines
sub form_text {
  my ($gate, $tree) = @_;
  my $w = words();
  my @o = @{ $w->{open}{ $w->{gate}{$gate} } || [] };
  return "gate-receipt: your report must open with one of these words on its first line, alone or followed by a space or a colon: "
    . join(', ', @o) . "; and its last line must be exactly: $w->{end} $tree. Send your whole report again in that form.";
}

# --- the agent's record, read by its parts ---
# A record line is one JSON object, and JSON::PP reads about 2.5 MB a
# second, so a line is not decoded whole: obj splits an object into its
# keys' raw values and arr an array into its elements' raw values, and
# only the small parts the checks need are decoded (part). A string is
# skipped by looking for its closing quote, so a long one costs a step for
# each quote in it, not for each character, and no regular expression
# repeats a group (perl limits how often one may).

# the position just past a string's closing quote (P: just past its
# opening quote), or undef
sub skip_str {
  my ($t, $p) = @_;
  while (1) {
    my $q = index($$t, '"', $p);
    return undef if $q < 0;
    my $b = 0;
    $b++ while substr($$t, $q - $b - 1, 1) eq '\\';
    return $q + 1 unless $b % 2;
    $p = $q + 1;
  }
}

# the position just past the value at P (after any blanks), or undef
sub skip_val {
  my ($t, $p) = @_;
  pos($$t) = $p;
  $$t =~ /\G\s*/gc;
  $p = pos($$t) // $p;
  my $c = substr($$t, $p, 1);
  return skip_str($t, $p + 1) if $c eq '"';
  if ($c eq '{' || $c eq '[') {
    my $depth = 0;
    pos($$t) = $p;
    while ($$t =~ /\G[^"\[\]{}]*+(.)/sgc) {
      my $ch = $1;
      if ($ch eq '"') {
        my $e = skip_str($t, pos($$t));
        return undef unless defined $e;
        pos($$t) = $e;
      } elsif ($ch eq '{' || $ch eq '[') {
        $depth++;
      } else {
        $depth--;
        return pos($$t) if $depth == 0;
      }
    }
    return undef;
  }
  return $$t =~ /\G[-+0-9.eEa-z]+/gc ? pos($$t) : undef;
}

# {KEY => RAW} for the object in the string T refers to, or undef
sub obj {
  my ($t) = @_;
  my %f;
  pos($$t) = 0;
  return undef unless $$t =~ /\G\s*\{\s*/gc;
  return \%f if $$t =~ /\G\}/gc;
  while (1) {
    return undef unless $$t =~ /\G"/gc;
    my $ks = pos($$t);
    my $ke = skip_str($t, $ks);
    return undef unless defined $ke;
    my $key = substr($$t, $ks, $ke - $ks - 1);
    if ($key =~ /\\/) {
      ($key) = Json::decode(qq("$key"), 'plain');
      return undef unless defined $key && !ref $key;
    }
    pos($$t) = $ke;
    return undef unless $$t =~ /\G\s*:\s*/gc;
    my $vs = pos($$t);
    my $ve = skip_val($t, $vs);
    return undef unless defined $ve;
    $f{$key} = substr($$t, $vs, $ve - $vs);
    pos($$t) = $ve;
    $$t =~ /\G\s*/gc;
    next if $$t =~ /\G,\s*/gc;
    return \%f if $$t =~ /\G\}/gc;
    return undef;
  }
}

# the raw elements of the array in the string T refers to
sub arr {
  my ($t) = @_;
  my @e;
  pos($$t) = 0;
  return () unless $$t =~ /\G\s*\[\s*/gc;
  return () if $$t =~ /\G\]/gc;
  while (1) {
    my $vs = pos($$t);
    my $ve = skip_val($t, $vs);
    return @e unless defined $ve;
    push @e, substr($$t, $vs, $ve - $vs);
    pos($$t) = $ve;
    $$t =~ /\G\s*/gc;
    last unless $$t =~ /\G,\s*/gc;
  }
  return @e;
}

# a raw value decoded (a plain string without escapes directly), or undef
sub part {
  my ($raw) = @_;
  return undef unless defined $raw;
  if ($raw =~ /\A"([^"\\\x00-\x1F]*)"\z/) {
    my $s = $1;
    return utf8::decode($s) ? $s : undef;
  }
  my ($d, $e) = Json::decode($raw, 'plain');
  return defined $e ? undef : $d;
}

sub effort_seen {
  my ($ev, $e) = @_;
  my $v = defined $e && !ref $e && $RANK{$e} ? $e : 'other';
  push @{ $ev->{efforts} }, $v unless grep { $_ eq $v } @{ $ev->{efforts} };
}

sub cwd_seen {
  my ($f, $ev, $ctx) = @_;
  return unless defined $f->{cwd} && defined $ctx->{cwd};
  my $c = part($f->{cwd});
  $ev->{elsewhere} = 1 if !defined $c || ref $c || sha('cwd', $c) ne $ctx->{cwd};
}

# the texts of a user line's message: its content, or each text block and
# tool result in it
sub texts {
  my ($d) = @_;
  return () unless ref $d eq 'HASH';
  my $c = $d->{content};
  return ($c) if defined $c && !ref $c;
  my @t;
  for my $e (ref $c eq 'ARRAY' ? @$c : ()) {
    next unless ref $e eq 'HASH';
    push @t, $e->{text} if defined $e->{text} && !ref $e->{text};
    my $r = $e->{content};
    push @t, $r if defined $r && !ref $r;
    push @t, map { $_->{text} } grep { ref $_ eq 'HASH' && defined $_->{text} && !ref $_->{text} } @$r if ref $r eq 'ARRAY';
  }
  return @t;
}

# the tree each review packet in TEXT names in its header (lib/packet.pl:
# a "Tree: <id>" line between "=== PACKET HEADER <token> ===" and the
# next marker with that token; a Read result's line numbers taken off),
# "none" for a header without one
sub packet_trees {
  my ($text) = @_;
  my (@t, $open, $seen);
  for my $x (split /\n/, $text) {
    $x =~ s/\r\z//;
    $x =~ s/\A[ \t]*[0-9]+(?:\t|\x{2192})//;
    if (!defined $open) {
      ($open, $seen) = ($1, undef) if $x =~ /\A=== PACKET HEADER ([0-9a-f]{16}) ===\z/;
      next;
    }
    if ($x =~ /\A=== PACKET [A-Z]+ \Q$open\E ===\z/) {
      push @t, $seen // 'none';
      $open = undef;
      next;
    }
    $seen = $1 if !defined $seen && $x =~ /\ATree: ([0-9a-f]{40}|[0-9a-f]{64})\z/;
  }
  push @t, $seen // 'none' if defined $open;
  return @t;
}

sub on_assistant {
  my ($f, $ev, $ctx) = @_;
  cwd_seen($f, $ev, $ctx);
  for my $k (qw(effort perTurnEffort)) {
    effort_seen($ev, part($f->{$k})) if exists $f->{$k};
  }
  my $m = defined $f->{message} ? obj(\$f->{message}) : undef;
  unless ($m) { $ev->{bad}++; return }
  my $model = part($m->{model});
  if (defined $model && !ref $model) {
    if ($model eq '<synthetic>') { $ev->{synthetic} = 1 }
    elsif (!grep { $_ eq $model } @{ $ev->{models} }) { push @{ $ev->{models} }, $model }
  }
  # (a message of several content blocks is one line a block, each with
  # the whole message's usage: counted once a message id)
  my $id = part($m->{id});
  $id = undef if ref $id;
  if (defined $m->{usage} && !(defined $id && $ev->{counted}{$id}++)) {
    my $u = part($m->{usage});
    if (ref $u eq 'HASH') {
      my $first = !$ev->{usage_seen}++;
      for my $k ([input => 'input_tokens'], [output => 'output_tokens'], [cache_creation => 'cache_creation_input_tokens'], [cache_read => 'cache_read_input_tokens']) {
        my $v = $u->{ $k->[1] };
        $ev->{tokens}{ $k->[0] } += $v if defined $v && !ref $v && $v =~ /\A[0-9]{1,15}\z/;
      }
      # (M116: the first request's cache reads, kept apart)
      my $c = $u->{cache_read_input_tokens};
      $ev->{tokens}{cache_read_first} = 0 + $c if $first && defined $c && !ref $c && $c =~ /\A[0-9]{1,15}\z/;
    }
  }
  for my $c (defined $m->{content} ? arr(\$m->{content}) : ()) {
    my $e = obj(\$c) or next;
    my $type = part($e->{type}) // '';
    next if ref $type;
    if ($type eq 'tool_use') {
      my $name = part($e->{name}) // '';
      $ev->{called} = 1 if $name eq 'Agent' || $name eq 'Task';
      my $id2 = part($e->{id}) // '';
      if (defined $ctx->{hb} && $name eq 'SubagentHandback' && $id2 eq $ctx->{hb}) {
        my $i = part($e->{input});
        $ev->{hb_sha} = sha('report', $i->{message}) if ref $i eq 'HASH' && defined $i->{message} && !ref $i->{message};
      }
    } elsif ($type eq 'text' && defined $ctx->{end} && defined $e->{text} && index($e->{text}, $ctx->{end}) >= 0) {
      my $t = part($e->{text});
      my @l = defined $t && !ref $t ? nonblank($t) : ();
      $ev->{found} = 1 if @l && $l[-1] eq $ctx->{end};
    }
  }
}

sub on_user {
  my ($f, $ev, $ctx) = @_;
  cwd_seen($f, $ev, $ctx);
  my $m = $f->{message};
  return unless defined $m;
  # (a background shell's id, as the Bash tool's result gives it)
  $ev->{bg}{$1} = 1 while $m =~ /Command running in background with ID: ([A-Za-z0-9_-]{1,64})/g;
  my $d;
  if (index($m, '=== PACKET HEADER ') >= 0) {
    $d = part($m);
    push @{ $ev->{packets} }, packet_trees($_) for texts($d);
  }
  if (defined $ctx->{hb} && index($m, qq("tool_use_id":"$ctx->{hb}")) >= 0) {
    $d = part($m) unless defined $d;
    for my $c (ref $d eq 'HASH' && ref $d->{content} eq 'ARRAY' ? @{ $d->{content} } : ()) {
      next unless ref $c eq 'HASH' && ($c->{type} // '') eq 'tool_result' && ($c->{tool_use_id} // '') eq $ctx->{hb};
      $ev->{found} = 1;
      $ev->{hb_ok} = $c->{is_error} ? 0 : 1;
    }
  }
}

# one line of the record
sub consider {
  my ($l, $ev, $ctx) = @_;
  $ev->{lines}++;
  # (what the checks never read, told by how the line starts: the request
  # copies, and attachments other than the first prompt snapshot)
  return if $$l =~ /\A\{"type":"api-request-(?:shape|blob)"/;
  if ($$l =~ /\A\{(?:"[A-Za-z]{1,40}":(?:null|true|false|-?[0-9]{1,20}|"[^"\\]{0,200}"),){0,20}"attachment":\{"type":"([a-z_]{1,60})"/) {
    return if $1 ne 'prompt_snapshot' || $ev->{snap};
  }
  return unless $$l =~ /\S/;
  my $f = obj($l);
  unless ($f) { $ev->{bad}++; return }
  my $type = part($f->{type}) // '';
  return if ref $type;
  if ($type eq 'assistant') {
    on_assistant($f, $ev, $ctx);
  } elsif ($type eq 'user') {
    on_user($f, $ev, $ctx);
  } elsif ($type eq 'api-request') {
    my $p = part($f->{params});
    effort_seen($ev, $p->{output_config}{effort}) if ref $p eq 'HASH' && ref $p->{output_config} eq 'HASH' && exists $p->{output_config}{effort};
  } elsif ($type eq 'attachment' && !$ev->{snap} && defined $f->{attachment} && index($f->{attachment}, '"prompt_snapshot"') >= 0) {
    my $a = part($f->{attachment});
    return unless ref $a eq 'HASH' && ($a->{type} // '') eq 'prompt_snapshot';
    $ev->{snap} = 1;
    my $s = ref $a->{systemPrompt} eq 'ARRAY' ? $a->{systemPrompt}[0] : undef;
    $ev->{prompt} = $s if defined $s && !ref $s;
  }
}

# read the agent's record at PATH (bytes) into EV, its new lines polled
# for at most $WAIT seconds until the line CTX waits for is there (the
# report's end line in an assistant line, or the result of the noted
# handback); read once when CTX waits for nothing. undef, or why it could
# not be read whole: record-late, record-unreadable (no path, not a
# regular file, over 200 MB)
sub read_record {
  my ($path, $ev, $ctx) = @_;
  return 'record-unreadable' unless defined $path && $path ne '';
  my $until = Time::HiRes::time() + ($ctx->{wait} ? $WAIT : 0);
  my ($fh, $off, $buf) = (undef, 0, '');
  while (1) {
    if (!$fh && (-e $path || -l $path)) {
      # (opened without waiting, so a FIFO cannot hold the hook; then only
      # a regular file is read)
      sysopen($fh, $path, O_RDONLY | $NONBLOCK) or return 'record-unreadable';
      return 'record-unreadable' unless -f $fh;
      binmode $fh;
    }
    if ($fh) {
      my $size = -s $fh;
      return 'record-unreadable' if !defined $size || $size > $RECORD_MAX;
      while ($off < $size) {
        my $n = sysread($fh, $buf, 4 << 20, length $buf);
        return 'record-unreadable' unless defined $n;
        last if $n == 0;
        $off += $n;
        my $from = 0;
        while ((my $i = index($buf, "\n", $from)) >= 0) {
          my $line = substr($buf, $from, $i - $from);
          consider(\$line, $ev, $ctx);
          $from = $i + 1;
        }
        $buf = substr($buf, $from);
      }
    }
    return undef if !$ctx->{wait} || $ev->{found};
    return 'record-late' if Time::HiRes::time() >= $until;
    Time::HiRes::sleep($POLL);
  }
}

# (4) to (6) of the stop: the files again, the write marks, the method's
# file and the agent's record; the reasons found. OK: the report has its
# lines (only then is the record waited for)
sub evidence {
  my ($in, $gate, $project, $dir, $r, $ok) = @_;
  my @why;
  my $t0 = Time::HiRes::time();
  # G: the files are still exactly HEAD's, and HEAD's tree is the start's,
  # in the worktree the gate started in (the stop's folder is the main
  # session's, which may have moved since: another worktree is not judged)
  my $g = look(cwd_of($in, $project));
  my $same = defined $g->{top} && defined $r->{top} && $g->{top} eq $r->{top};
  @$r{qw(clean_stop tree_stop)} = ($g->{clean}, $g->{tree}) if $same;
  if ($same) {
    push @why, 'unclean-stop' if defined $g->{clean} && !$g->{clean};
    push @why, 'tree-changed' if $g->{tree} ne $r->{tree};
  }
  push @why, 'clean-unknown' unless $same && defined $g->{clean} && defined $r->{clean_start};
  my $t1 = Time::HiRes::time();
  # M: a write by another in the gate's window, in its worktree
  my $marked = defined $r->{top} ? marked($dir, $r) : 0;
  push @why, 'write-mark' if $marked;
  push @why, 'marks-unreadable' unless defined $marked;
  # the method's file, as it is now (it is tracked, so a change to it since
  # the start is a change to the files; its effort was read at the start)
  my $m = $same ? method_file($g->{path}, $gate) : undef;
  # R: the agent's record
  my $w = words();
  my %ev = (models => [], efforts => [], tokens => { input => 0, output => 0, cache_creation => 0, cache_read => 0, cache_read_first => undef },
    counted => {}, bg => {}, packets => [], found => 0, bad => 0, lines => 0);
  my $hb = $r->{handback} && id_ok($r->{handback}{id}) ? $r->{handback}{id} : undef;
  my %ctx = (cwd => $r->{cwd}, wait => $ok ? 1 : 0, hb => $hb, end => defined $hb ? undef : "$w->{end} $r->{tree}");
  my $path = $in->{agent_transcript_path};
  my $late = read_record(defined $path && !ref $path ? Hook::bytes($path) : undef, \%ev, \%ctx);
  push @why, $late if defined $late;
  push @why, 'record-unreadable' if $ev{bad};
  # (read whole, a record that lacks what every record holds is one the
  # checks cannot read)
  my $whole = !defined $late && !$ev{bad} && $ok;
  push @why, 'synthetic-reply' if $ev{synthetic};
  my %allowed = map { $_ => 1 } allowed_models($project);
  push @why, 'model-off-list' if !%allowed || grep { !$allowed{$_} } @{ $ev{models} };
  push @why, 'no-model' if $whole && !@{ $ev{models} };
  my $floor = defined $r->{effort_file} ? $RANK{ $r->{effort_file} } : undef;
  push @why, 'effort-low' if $floor && grep { ($RANK{$_} || 0) < $floor } @{ $ev{efforts} };
  push @why, 'no-effort' if $whole && !@{ $ev{efforts} };
  if (defined $ev{prompt}) {
    push @why, 'instructions-differ' if $same && !($m && trimmed($ev{prompt}) eq $m->{body});
  } elsif ($whole) {
    push @why, 'no-instructions';
  }
  push @why, 'called-agent' if $ev{called};
  push @why, 'other-folder' if $ev{elsewhere};
  my @tasks = ref $in->{background_tasks} eq 'ARRAY' ? @{ $in->{background_tasks} } : ();
  push @why, 'background-task' if grep { ref $_ eq 'HASH' && ($_->{type} // '') eq 'shell' && ($_->{status} // '') eq 'running'
    && defined $_->{id} && !ref $_->{id} && $ev{bg}{ $_->{id} } } @tasks;
  push @why, 'packet-other-tree' if grep { $_ ne $r->{tree} } @{ $ev{packets} };
  push @why, 'handback-unconfirmed' if defined $hb && $ok && !defined $late
    && !($ev{hb_ok} && defined $ev{hb_sha} && $ev{hb_sha} eq ($r->{handback}{sha} // ''));
  $r->{models} = [map { length $_ > 128 ? substr($_, 0, 128) : $_ } @{ $ev{models} }];
  $r->{efforts} = $ev{efforts};
  $r->{tokens} = $ev{tokens};
  $r->{cost} = { %{ $r->{cost} || {} }, files => secs($t1 - $t0), record => secs(Time::HiRes::time() - $t1), record_lines => $ev{lines} };
  return @why;
}

# the state the reasons give, and the reasons with the second word's first
sub state_of {
  my (@why) = @_;
  my $w = words();
  return $w->{wrong} if grep { $WRONG{$_} } @why;
  return @why ? $w->{unchecked} : $w->{good};
}

sub ordered {
  my %seen;
  my @why = grep { !$seen{$_}++ } @_;
  return ((grep { $WRONG{$_} } @why), (grep { !$WRONG{$_} } @why));
}

sub fresh {
  my ($in, $gate, $why, $run) = @_;
  return { v => 1, gate => $gate, agent => $in->{agent_id}, run => $run, prompt => (id_ok($in->{prompt_id}) ? $in->{prompt_id} : undef),
    started => undef, stopped => undef, head => 'none', tree => 'none', state => words()->{unchecked}, why => [$why], open => undef,
    stops => 0, blocked => 0, denied => 0, handback => undef };
}

sub effort_of { my ($e) = @_; $e = $e->{level} if ref $e eq 'HASH'; return defined $e && !ref $e && $e =~ /\A(low|medium|high|xhigh|max)\z/ ? $1 : 'none' }

sub log_line {
  my ($project, $r, $in) = @_;
  my @why = @{ $r->{why} || [] };
  # (the first model seen, when it has a model id's shape)
  my $model = ref $r->{models} eq 'ARRAY' ? $r->{models}[0] : undef;
  $model = undef unless defined $model && $model =~ /\A[A-Za-z0-9._\[\]-]{1,64}\z/;
  eval {
    Log::append($project, $LOG, $LOG_CAP, word => $r->{state}, gate => $r->{gate}, tree => $r->{tree} =~ /\A[0-9a-f]{7,64}\z/ ? $r->{tree} : 'none',
      model => defined $model ? $model : 'none', effort => effort_of($in->{effort}), why => @why ? $why[0] : 'none');
  };
  return;
}

# a background gate resumed under the same agent id: the agent PART's
# earlier receipts in DIR (all but NAME) no longer stand for what it does
# now
sub resumed {
  my ($dir, $part, $name) = @_;
  my $w = words();
  opendir my $d, $dir or return;
  my @names = grep { /\A\Q$PREFIX$part\E[0-9a-f]{8}\.json\z/ && $_ ne $name } readdir $d;
  closedir $d;
  for my $other (@names) {
    my $o = load($dir, $other) or next;
    next unless ($o->{state} // '') eq $w->{good};
    $o->{state} = $w->{unchecked};
    $o->{why} = ['resumed-after-report'];
    eval { save($dir, $other, $o) };
  }
  return;
}

# the run a handback or a stop belongs to: the agent's newest run (its
# part, number, receipt name and receipt); a run with no receipt gets one
# whose start was not recorded, and a run whose start was not recorded
# (none, or one cut off) the tree of the files now, for its lines
sub current {
  my ($in, $gate, $dir) = @_;
  my $part = agent_part($in->{session_id}, $in->{agent_id});
  my $run = newest($dir, $part) || 1;
  my $name = name_of($part, $run);
  my $r = load($dir, $name) || fresh($in, $gate, 'no-start', $run);
  @$r{qw(head tree)} = tree_of(Hook::bytes($in->{cwd} // '.')) if !defined $r->{started} && ($r->{tree} // 'none') eq 'none';
  return ($part, $run, $name, $r);
}

# --- the three events ---

sub start {
  my ($in, $gate, $project, $dir) = @_;
  my $began = Time::HiRes::time();
  my ($part, $run, $name);
  if ($dir) {
    # a start makes the agent's next run. Before the start's own clean
    # check, which takes a while on a large tree: the running file (the
    # guard's marks are made while it is there; one left by a crash is
    # removed after a day), the agent's earlier receipts set aside, and
    # the run's receipt with no start yet, so a start cut off at its
    # time-out leaves its own run not checked, never an earlier run judged
    # in its place
    $part = agent_part($in->{session_id}, $in->{agent_id});
    $run = newest($dir, $part) + 1;
    $name = name_of($part, $run);
    eval {
      running($dir, 1);
      Log::write_whole($dir, running_of($part, $run), sprintf("%.6f\n", $began), 0600);
    };
    resumed($dir, $part, $name);
    eval { save($dir, $name, fresh($in, $gate, 'starting', $run)) };
  }
  my $cwd = cwd_of($in, $project);
  my $g = look($cwd);
  my ($head, $tree) = @$g{qw(head tree)};
  if ($dir) {
    my $r = fresh($in, $gate, 'running', $run);
    @$r{qw(started head tree)} = ($began, $head, $tree);
    @$r{qw(top clean_start)} = @$g{qw(top clean)};
    $r->{cwd} = sha('cwd', defined $in->{cwd} && !ref $in->{cwd} ? $in->{cwd} : '');
    my $m = method_file($g->{path}, $gate);
    @$r{qw(method_sha effort_file)} = $m ? @$m{qw(sha effort)} : (undef, undef);
    $r->{cost} = { start => secs(Time::HiRes::time() - $began) };
    eval { save($dir, $name, $r) };
  }
  my $line = "METHOD-ACTIVE gate=$gate tree=$tree";
  $line = "METHOD-ACTIVE tree=$tree" if length $line > $CONTEXT_MAX;
  return Hook::json({ hookSpecificOutput => { hookEventName => 'SubagentStart', additionalContext => $line } });
}

sub handback {
  my ($in, $gate, $dir) = @_;
  return 0 unless $dir;
  my (undef, undef, $name, $r) = current($in, $gate, $dir);
  my $msg = ref $in->{tool_input} eq 'HASH' ? $in->{tool_input}{message} : undef;
  my ($ok, $word) = lines_ok($msg, $gate, $r->{tree});
  if (!$ok && !$r->{denied}) {
    $r->{denied} = 1;
    save($dir, $name, $r);
    return Hook::json({ hookSpecificOutput => { hookEventName => 'PreToolUse', permissionDecision => 'deny', permissionDecisionReason => form_text($gate, $r->{tree}) } });
  }
  $r->{handback} = { id => (id_ok($in->{tool_use_id}) ? $in->{tool_use_id} : undef), sha => sha('report', defined $msg && !ref $msg ? $msg : ''),
    lines => $ok ? 1 : 0, open => $ok ? $word : undef };
  save($dir, $name, $r);
  return 0;
}

sub stop {
  my ($in, $gate, $project, $dir) = @_;
  return 0 unless $dir;
  my $w = words();
  my ($part, $run, $name, $r) = current($in, $gate, $dir);
  my @why;
  # a run whose start was not recorded is not checked, at every stop of
  # it, and never sent back
  push @why, 'no-start' unless defined $r->{started};
  $r->{stops}++;
  # (1) not checked until judged, so a crash leaves no earlier good word
  @$r{qw(state why stopped)} = ($w->{unchecked}, ['judging'], Time::HiRes::time());
  save($dir, $name, $r);
  # the reasons known at the start, which make the receipt the second
  # word whatever the report says: no block for them (B6)
  if (defined $r->{started}) {
    push @why, 'unclean-start' if defined $r->{clean_start} && !$r->{clean_start};
    push @why, 'instructions-differ' if defined $r->{top} && !$r->{effort_file};
  }
  # (2) and (3): the report and its lines
  my $auto = ($in->{permission_mode} // '') eq 'auto';
  my ($ok, $word, $nudged);
  if ($r->{handback}) {
    ($ok, $word) = ($r->{handback}{lines}, $r->{handback}{open});
    push @why, 'lines-missing-after-retry' unless $ok;
  } elsif ($auto) {
    ($ok, $word, $nudged) = (0, undef, 1);
    push @why, 'no-report';    # auto mode delivers only a handback
  } else {
    ($ok, $word) = lines_ok($in->{last_assistant_message}, $gate, $r->{tree});
    if (!$ok) {
      my $code = $word;
      $word = undef;
      if (!$r->{blocked} && !@why) {
        # B6: sent back once, and the receipt says so before the block
        $r->{blocked} = 1;
        $r->{why} = [$code];
        save($dir, $name, $r);
        return Hook::block(form_text($gate, $r->{tree}));
      }
      push @why, $r->{blocked} ? "$code-after-retry" : $code;
    }
  }
  # (4) to (6): the evidence, for a run whose start was recorded
  push @why, evidence($in, $gate, $project, $dir, $r, $ok) if defined $r->{started};
  $r->{open} = $word;
  $r->{why} = [ordered(@why)];
  $r->{state} = state_of(@why);
  save($dir, $name, $r);
  log_line($project, $r, $in);
  # (in auto mode a stop with no handback is followed by the client's own
  # nudges to the gate, so its running file stays and the writes made
  # meanwhile are marked; a later stop removes it, or a start's prune
  # after a day)
  unlink File::Spec->catfile($dir, running_of($part, $run)) unless $nudged;
  return 0;
}

# session-status's count (step 5b.2): the receipts in the repository of
# PROJECT for the tree of HEAD in DIR that do not say the first receipt
# word: ([WORD, COUNT]...) for the second and the third word, those with a
# count above 0
sub counts {
  my ($project, $dir) = @_;
  my $store = store($project) or return ();
  my (undef, $tree) = tree_of($dir);
  return () if $tree eq 'none';
  my $w = words();
  opendir my $d, $store or return ();
  my @names = grep { /\A\Q$PREFIX\E[0-9a-f]{24}\.json\z/ } readdir $d;
  closedir $d;
  my %n;
  for my $name (@names) {
    my $p = File::Spec->catfile($store, $name);
    next if -l $p || !-f _ || -s _ > $MAX;
    open my $h, '<:raw', $p or next;
    my $text = do { local $/; <$h> };
    close $h;
    # (the receipts of other trees are not decoded)
    next unless defined $text && index($text, qq("tree":"$tree")) >= 0;
    my ($r) = Json::decode($text, 'plain');
    next unless ref $r eq 'HASH' && ($r->{v} // 0) == 1 && ($r->{tree} // '') eq $tree && defined $r->{state} && !ref $r->{state};
    $n{ $r->{state} }++ if $r->{state} ne $w->{good};
  }
  return map { [$_, $n{$_}] } grep { $n{$_} } $w->{wrong}, $w->{unchecked};
}

sub main {
  my ($in) = Hook::read_input();
  return 0 unless $in;
  my $rc = eval {
    my $w = words();
    my $gate = $in->{agent_type};
    return 0 unless defined $gate && !ref $gate && exists $w->{gate}{$gate};
    return 0 unless id_ok($in->{session_id}) && id_ok($in->{agent_id});
    my $event = $in->{hook_event_name} // '';
    my $project = project($in);
    my $dir = $project ? store($project) : undef;
    return start($in, $gate, $project, $dir) if $event eq 'SubagentStart';
    return stop($in, $gate, $project, $dir) if $event eq 'SubagentStop';
    return handback($in, $gate, $dir) if $event eq 'PreToolUse' && ($in->{tool_name} // '') eq 'SubagentHandback';
    return 0;
  };
  return defined $rc ? $rc : 0;
}

return 1 if caller;
exit main();
