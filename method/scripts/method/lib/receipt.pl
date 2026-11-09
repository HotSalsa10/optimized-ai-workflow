#!/usr/bin/env perl
# gate-receipt's perl part (step 5b; docs/plans/step5b.md, sections 1 and
# 2). .claude/hooks/method/gate-receipt.sh runs it with the hook's JSON
# input on standard input, at three events of a checking agent (a "gate";
# the gates are listed in verdicts.txt, never spelled here, M039):
# - SubagentStart: the start is recorded (the checkout's HEAD and its tree)
#   and the gate is told, through additionalContext, the line its report
#   must end with: "METHOD-ACTIVE gate=<name> tree=<tree>".
# - PreToolUse of SubagentHandback (auto mode, B7): a report without its
#   lines is refused once with a plain reason; the second time it is let
#   through and the receipt says so.
# - SubagentStop: the report is judged (B2: its first line opens with one
#   of the gate's words, its last line is exactly the end key and the
#   start's tree); a report without its lines is sent back once (B6:
#   exit 2, only in default mode, only when no handback was seen); then
#   the receipt is written, and one fixed-field line goes to
#   .method/local/gates.log.
# A receipt is one JSON file per gate run in git's common folder
# (method-receipt-<16 hex for session and agent><8 hex for the prompt>.json,
# which G6 protects), written whole, the newest 500 kept. Its state is one
# of the receipt words: the first (every check holds), the second (it
# checked the wrong thing or the wrong way), the third (not checked), with
# reason codes, never text. Each stop first writes the third word with the
# reason "judging", so a crash never leaves an earlier first word standing.
# Anything that goes wrong is exit 0 (B11): at SubagentStop an exit 2 sends
# the gate back to work, and at the handback a refusal on every crash would
# loop; only a deliberate block exits 3, which the wrapper turns into 2.
package Receipt;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Glob qw(bsd_glob GLOB_QUOTE GLOB_NOSORT);
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
sub glob_quote { my ($s) = @_; $s =~ s/([\\*?\[\]{}~])/\\$1/g; return $s }
sub sha { return Digest::SHA::sha256_hex(Hook::bytes(join "\0", @_)) }

# the project: CLAUDE_PROJECT_DIR (bytes), else the input's cwd
sub project {
  my ($in) = @_;
  my $p = $ENV{CLAUDE_PROJECT_DIR};
  $p = Hook::bytes($in->{cwd}) if (!defined $p || $p eq '') && defined $in->{cwd} && !ref $in->{cwd};
  return defined $p && $p ne '' && -d $p ? $p : undef;
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

sub agent_part { my ($sid, $aid) = @_; return substr(sha('receipt', $sid, $aid), 0, 16) }
sub name_of { my ($sid, $aid, $pid) = @_; return $PREFIX . agent_part($sid, $aid) . substr(sha('prompt', $pid), 0, 8) . '.json' }

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

# B2: (1, OPENING WORD) when the report opens with one of the gate's words
# and ends with "<end key> <tree>"; (0, REASON CODE) otherwise
sub lines_ok {
  my ($report, $gate, $tree) = @_;
  my $w = words();
  return (0, 'no-report') unless defined $report && !ref $report;
  my @l = grep { /\S/ } map { my $x = $_; $x =~ s/[ \t\r]+\z//; $x } split /\n/, $report;
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

sub fresh {
  my ($in, $gate, $why) = @_;
  return { v => 1, gate => $gate, agent => $in->{agent_id}, prompt => $in->{prompt_id}, started => undef, stopped => undef,
    head => 'none', tree => 'none', state => words()->{unchecked}, why => [$why], open => undef, stops => 0,
    blocked => 0, denied => 0, handback => undef };
}

sub effort_of { my ($e) = @_; $e = $e->{level} if ref $e eq 'HASH'; return defined $e && !ref $e && $e =~ /\A(low|medium|high|xhigh|max)\z/ ? $1 : 'none' }

sub log_line {
  my ($project, $r, $in) = @_;
  my @why = @{ $r->{why} || [] };
  eval {
    Log::append($project, $LOG, $LOG_CAP, word => $r->{state}, gate => $r->{gate}, tree => $r->{tree} =~ /\A[0-9a-f]{7,64}\z/ ? $r->{tree} : 'none',
      model => 'none', effort => effort_of($in->{effort}), why => @why ? $why[0] : 'none');
  };
  return;
}

# --- the three events ---

sub start {
  my ($in, $gate, $project, $dir) = @_;
  my $w = words();
  my $cwd = defined $in->{cwd} && !ref $in->{cwd} && $in->{cwd} ne '' ? Hook::bytes($in->{cwd}) : $project;
  my ($head, $tree) = tree_of($cwd);
  if ($dir) {
    # a background gate resumed under the same agent id: its earlier
    # receipts no longer stand for what it does now
    my $part = agent_part($in->{session_id}, $in->{agent_id});
    my $name = name_of($in->{session_id}, $in->{agent_id}, $in->{prompt_id});
    for my $p (bsd_glob(glob_quote($dir) . "/$PREFIX$part*.json", GLOB_QUOTE | GLOB_NOSORT)) {
      my $other = (File::Spec->splitpath($p))[2];
      next if $other eq $name;
      my $o = load($dir, $other) or next;
      next unless ($o->{state} // '') eq $w->{good};
      $o->{state} = $w->{unchecked};
      $o->{why} = ['resumed-after-report'];
      eval { save($dir, $other, $o) };
    }
    my $r = fresh($in, $gate, 'running');
    @$r{qw(started head tree)} = (Time::HiRes::time(), $head, $tree);
    eval { save($dir, $name, $r) };
  }
  my $line = "METHOD-ACTIVE gate=$gate tree=$tree";
  $line = "METHOD-ACTIVE tree=$tree" if length $line > $CONTEXT_MAX;
  return Hook::json({ hookSpecificOutput => { hookEventName => 'SubagentStart', additionalContext => $line } });
}

sub handback {
  my ($in, $gate, $dir) = @_;
  return 0 unless $dir;
  my $name = name_of($in->{session_id}, $in->{agent_id}, $in->{prompt_id});
  my $r = load($dir, $name);
  unless ($r) {
    $r = fresh($in, $gate, 'no-start');
    @$r{qw(head tree)} = tree_of(Hook::bytes($in->{cwd} // '.'));
  }
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
  my $name = name_of($in->{session_id}, $in->{agent_id}, $in->{prompt_id});
  my $r = load($dir, $name);
  my @why;
  unless ($r) {
    $r = fresh($in, $gate, 'no-start');
    @$r{qw(head tree)} = tree_of(Hook::bytes($in->{cwd} // '.'));
    push @why, 'no-start';
  }
  $r->{stops}++;
  # (1) not checked until judged, so a crash leaves no earlier good word
  @$r{qw(state why stopped)} = ($w->{unchecked}, ['judging'], Time::HiRes::time());
  save($dir, $name, $r);
  # (2) and (3): the report and its lines
  my $auto = ($in->{permission_mode} // '') eq 'auto';
  my ($ok, $word);
  if ($r->{handback}) {
    ($ok, $word) = ($r->{handback}{lines}, $r->{handback}{open});
    push @why, 'lines-missing-after-retry' unless $ok;
  } elsif ($auto) {
    ($ok, $word) = (0, undef);
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
  $r->{open} = $word;
  $r->{why} = [@why];
  $r->{state} = @why ? $w->{unchecked} : $w->{good};
  save($dir, $name, $r);
  log_line($project, $r, $in);
  return 0;
}

sub main {
  my ($in) = Hook::read_input();
  return 0 unless $in;
  my $rc = eval {
    my $w = words();
    my $gate = $in->{agent_type};
    return 0 unless defined $gate && !ref $gate && exists $w->{gate}{$gate};
    return 0 unless id_ok($in->{session_id}) && id_ok($in->{agent_id}) && id_ok($in->{prompt_id});
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
