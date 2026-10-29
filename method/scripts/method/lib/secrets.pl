#!/usr/bin/env perl
# Scans files for secrets and personal data (M066). Called by run-checks.sh
# (its built-in check "secrets") and by this method repo's
# scripts/dev/scan-secrets.sh, both with --repo.
#
# Usage:
#   perl secrets.pl --repo [--ids] ALLOW_FILE
#       Run from the repo root: scans every tracked file that is a regular
#       file on disk (git ls-files, so no file name goes on a command line),
#       with everything --staged adds. After the count lines it prints
#       "RESULT PASS|FAIL|SKIPPED <reason>": FAIL on any finding or unreadable
#       file, SKIPPED when it examined no text file, else PASS.
#   perl secrets.pl [--staged] [--ids] ALLOW_FILE FILE...
#       Scans each FILE. With --staged (run from the repo root), also scans the
#       staged copy of every tracked file whose staged copy differs from the
#       working tree, so a secret that is staged but no longer on disk is seen;
#       the name of every tracked entry (also links, folders of other repos
#       and files missing from disk); and the stored target of every symlink.
#       With --ids, each finding also shows the ID to put in ALLOW_FILE.
#       Prints one line per finding (masked, never in full), "NOTE ..." lines,
#       then "EXAMINED n", "STAGED n", "BAD n", "ALLOWED n", "SKIPPED n", "SKIPPED_NAMES ...".
#   perl secrets.pl --mask
#       Copies standard input to standard output with keys, credentials and
#       personal email addresses masked, control characters escaped and every
#       line indented by two spaces. validate.sh sends other tools' output
#       through it, so a key a tool quotes is not printed in full either.
#
# ALLOW_FILE lines are PATH<TAB>ID<TAB>REASON. The ID is the first 12
# characters of git's object ID for "PATH", a NUL byte and the matched text,
# so an entry covers one text in one file and does not hold the text itself.
#
# Text in UTF-16 is decoded first: with a byte-order mark always, without one
# when most of it is ASCII. Lines may end in LF, CRLF or a lone CR. Binary
# files are not read as text. In every file that holds a NUL byte, the runs
# of printable bytes are also searched: for keys and tokens in binary files,
# and for everything in files decoded as UTF-16 (text added after the UTF-16
# part, for example).
use strict;
use warnings;
use File::Basename qw(dirname);
use IPC::Open2;
use File::Spec;
# lib/esc.pl: $Esc::TERM_CODE, the one pattern for a terminal code
require File::Spec->catfile(dirname(File::Spec->rel2abs(__FILE__)), 'esc.pl');
my $term_code = do { no warnings 'once'; $Esc::TERM_CODE };

# Prints one line of output. Control characters taken from file names or
# content (also UTF-8 C1 controls) are shown as \xNN, and the CI runner's
# command forms (## [ anywhere, :: at the start after spaces) are broken up,
# so text from a file can never start a new line of output, move the cursor
# or reach the CI runner as a command.
sub esc {
  my ($s) = @_;
  $s =~ s/([\x00-\x1F\x7F])/sprintf('\\x%02X', ord $1)/ge;
  $s =~ s/\xC2([\x80-\x9F])/sprintf('\\xC2\\x%02X', ord $1)/ge;
  $s =~ s/##\[/#\\x23[/g;
  return $s;
}
sub say_line {
  my $s = esc($_[0]);
  # the runner trims Unicode spaces too (no-break space, LS, PS, ideographic)
  $s =~ s/^((?:\s|\xC2\xA0|\xE1\x9A\x80|\xE2\x80[\x80-\x8A\xA8\xA9\xAF]|\xE2\x81\x9F|\xE3\x80\x80)*):(?=:)/$1\\x3A/;
  print "$s\n";
}

my ($staged, $show_ids, $mask_mode, $repo_mode) = (0, 0, 0, 0);
while (@ARGV && $ARGV[0] =~ /^--/) {
  my $opt = shift @ARGV;
  if ($opt eq '--staged') { $staged = 1 }
  elsif ($opt eq '--ids') { $show_ids = 1 }
  elsif ($opt eq '--mask') { $mask_mode = 1 }
  elsif ($opt eq '--repo') { $repo_mode = $staged = 1 }
  else { die "secrets: unknown option " . esc($opt) . "\n" }
}

# Keys and tokens with a recognisable shape.
my @token_rules = (
  [qr/sk-ant-[A-Za-z0-9_-]{20,}/, 'Anthropic API key'],
  [qr/(?<![A-Za-z0-9])sk-(?:proj-)?[A-Za-z0-9]{32,}/, 'OpenAI-style API key'],
  [qr/(?<![A-Za-z0-9])gh[pousr]_[A-Za-z0-9]{36,}/, 'GitHub token'],
  [qr/(?<![A-Za-z0-9])github_pat_[A-Za-z0-9_]{40,}/, 'GitHub fine-grained token'],
  [qr/(?<![A-Za-z0-9])AKIA[0-9A-Z]{16}(?![0-9A-Z])/, 'AWS access key'],
  [qr/(?<![A-Za-z0-9])AIza[0-9A-Za-z_-]{35}(?![0-9A-Za-z_-])/, 'Google API key'],
  [qr/(?<![A-Za-z0-9])xox[abprs]-[A-Za-z0-9-]{10,}/, 'Slack token'],
  [qr/-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----/, 'private key'],
);
# the same rules with a capture group, compiled once
my @token_cap = map { qr/($_->[0])/ } @token_rules;

# Credentials assigned to a name that contains a credential word, also as
# part of a longer name (DB_PASSWORD, client_secret). Names are capped at 64
# characters and must start at a name boundary, so long lines stay fast.
# Groups: 1 the text before the value, 2 the name, 3 the value.
my $kw = qr/password|passwd|pwd|secret|api_?key|apikey|access_?token|auth_?token|private_?key|client_?secret|secret_?key/i;
my $quoted_cred = qr/((?<![A-Za-z0-9_.-])([A-Za-z0-9_.-]{0,64}?(?:$kw)[A-Za-z0-9_.-]{0,64})["']?\s*[:=]\s*["'])([^"'\s]{8,})(?=["'])/;
my $env_cred = qr/^(\s*(?:export\s+)?([A-Za-z0-9_]{0,64}?(?:$kw|(?i:token))[A-Za-z0-9_]{0,64})\s*=\s*)([^\s#"']{8,})/;

# A name that points at a secret (a path, a file, a helper command) is not
# a secret itself, and neither is a value that is a path or a file name.
sub cred_is_real {
  my ($name, $value) = @_;
  return 0 if $name =~ /(?:path|file|helper|dir)$/i;
  return 0 if $value =~ /^(?:[.\/~\$<{]|[A-Za-z]:\\)/;
  return 0 if $value =~ /\.(?:pem|key|crt|cer|p12|pfx|sh|ps1|json|txt|ya?ml|env|cfg|conf)$/i;
  return 1;
}

my $email_re = qr/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/;
my $asset_ext = qr/png|jpe?g|gif|svg|webp|ico|bmp|avif|tgz|tar|gz|zip|whl|jar|js|mjs|cjs|css/;

sub email_ok {
  my ($e) = @_;
  my $l = lc $e;
  my ($local, $domain) = split /\@/, $l, 2;
  # an image scale or a package version, not a mail domain: logo@2x.png, pkg@1.2.3.tgz
  return 1 if $domain =~ /^(?:\d+(?:\.\d+)?x|\d+(?:\.\d+)+)\.(?:$asset_ext)$/;
  return 1 if $local eq 'git';    # git@host:org/repo.git
  return 1 if $domain =~ /(?:^|\.)(?:example\.(?:com|org|net)|invalid|test|example|localhost)$/;
  return 1 if $domain eq 'users.noreply.github.com';
  return 1 if $l eq 'noreply@anthropic.com' || $l eq 'noreply@github.com';
  return 0;
}

# Phone numbers in international format: +, a country code (no leading 0),
# then groups of digits split by spaces, dashes or brackets. Flag when some
# prefix ending at a group boundary holds 10 to 15 digits (E.164), so a
# number followed by other figures is still caught.
sub phone_hits {
  my ($line) = @_;
  my @hits;
  while ($line =~ /(?<![\w.+\/=])(\+[1-9]\d{0,2}(?:(?:[ -]|\)\s?|\s?\()?\d{1,4}){1,8})/g) {
    my $span = $1;
    my ($digits, $hit) = (0, 0);
    for my $g ($span =~ /(\d+)/g) {
      $digits += length $g;
      if ($digits >= 10 && $digits <= 15) { $hit = 1; last }
      last if $digits > 15;
    }
    push @hits, $span if $hit;
  }
  return @hits;
}

# IBAN length by country (SWIFT IBAN registry). A candidate is checked at
# exactly its country's length and must end there, so trailing text cannot
# hide it and hexadecimal hashes do not pass.
my %iban_len = (
  AD => 24, AE => 23, AL => 28, AT => 20, AZ => 28, BA => 20, BE => 16, BG => 22, BH => 22,
  BI => 27, BR => 29, BY => 28, CH => 21, CR => 22, CY => 28, CZ => 24, DE => 22, DJ => 27,
  DK => 18, DO => 28, EE => 20, EG => 29, ES => 24, FI => 18, FK => 18, FO => 18, FR => 27,
  GB => 22, GE => 22, GI => 23, GL => 18, GR => 27, GT => 28, HN => 28, HR => 21, HU => 28,
  IE => 22, IL => 23, IQ => 23, IS => 26, IT => 27, JO => 30, KW => 30, KZ => 20, LB => 28,
  LC => 32, LI => 21, LT => 20, LU => 20, LV => 21, LY => 25, MC => 27, MD => 24, ME => 22,
  MK => 19, MN => 20, MR => 27, MT => 31, MU => 30, NI => 28, NL => 18, NO => 15, OM => 23,
  PK => 24, PL => 28, PS => 29, PT => 25, QA => 29, RO => 24, RS => 22, RU => 33, SA => 24,
  SC => 31, SD => 18, SE => 24, SI => 19, SK => 24, SM => 27, SO => 23, ST => 25, SV => 28,
  TL => 23, TN => 24, TR => 26, UA => 29, VA => 22, VG => 24, XK => 20, YE => 30,
);

sub iban_checksum_ok {
  my ($s) = @_;
  my $r = substr($s, 4) . substr($s, 0, 4);
  my $m = 0;
  for my $ch (split //, $r) {
    my $v = $ch =~ /[A-Z]/ ? ord($ch) - 55 : $ch;
    $m = ($m * 10 + $_) % 97 for split //, $v;
  }
  return $m == 1;
}

my @iban_written;    # the text of each hit as written, with spaces
sub iban_hits {
  my ($line) = @_;
  my @hits;
  while ($line =~ /(?<![A-Za-z0-9])([A-Z]{2})(?=\d{2})/g) {
    my $len = $iban_len{$1} or next;
    my $rest = $len - 4;
    # exactly the country's length, in one block or in spaced groups, and
    # not running on into more letters or digits (a longer hash)
    next unless substr($line, pos($line) - 2) =~ /^([A-Z]{2}\d{2}(?: ?[A-Z0-9]){$rest})(?![A-Za-z0-9])/;
    my $written = $1;
    (my $cand = $written) =~ s/ //g;
    next unless ($cand =~ tr/0-9//) >= 8;
    push @hits, $cand if iban_checksum_ok($cand);
    push @iban_written, $written if iban_checksum_ok($cand);
  }
  return @hits;
}

# A finding is shown by its kind and length only. A key or token of 20 or
# more characters also keeps its first 4, which name the kind (sk-a, ghp_,
# AKIA) without giving the key away.
sub mask {
  my ($s, $is_token) = @_;
  my $len = length $s;
  return substr($s, 0, 4) . "...($len chars)" if $is_token && $len >= 20;
  return "***($len chars)";
}

# mask_all TEXT HIT...: every HIT in TEXT masked, in one pass (longest first)
sub mask_all {
  my ($s, @hits) = @_;
  return $s unless @hits;
  my $alt = join '|', map { quotemeta } sort { length $b <=> length $a } @hits;
  $s =~ s/($alt)/mask($1, 0)/ge;
  return $s;
}
my $pem_begin = qr/-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----/;
my $pem_end = qr/-----END (?:[A-Z]+ )*PRIVATE KEY-----/;
sub mask_pass {
  my ($s) = @_;
  # a whole private key on one line (as JSON writes it) is masked to its end
  $s =~ s/($pem_begin.*?(?:$pem_end|\z))/mask($1, 1)/ge;
  $s =~ s/$_/mask($1, 1)/ge for @token_cap;
  $s =~ s/$quoted_cred/$1 . mask($3, 0)/ge;
  $s =~ s/$env_cred/$1 . mask($3, 0)/e;
  $s =~ s/($email_re)/email_ok($1) ? $1 : mask($1, 0)/ge;
  $s = mask_all($s, phone_hits($s));
  @iban_written = ();
  iban_hits($s);
  return mask_all($s, @iban_written);
}

# mask_text TEXT: TEXT with every key, credential, personal email address,
# phone number and IBAN masked. The whole text is masked first; then each
# piece between escapes and terminal codes, because a check's output may be
# escaped already, and an escape such as \x09 or a colour code such as
# ESC[31m ends a word without leaving a space. The terminal codes are
# masked too, so a key inside one (a link's address) is not let through.
# Last, a key with a code inside it (grep's highlighting, a coloured diff)
# is whole only with the codes taken out: when that copy still holds
# something to mask, the text is shown without its codes, masked.
sub mask_text {
  my ($t) = @_;
  my $s = mask_pass($t);
  $s = join '', map { /^\\x[0-9A-F]{2}$/ ? $_ : mask_pass($_) } split /(\\x[0-9A-F]{2}|$term_code)/, $s;
  my $plain = Esc::plain($s);
  return $s if $plain eq $s || mask_pass($plain) eq $plain;
  return mask_text(Esc::plain($t));
}

# --mask: a filter for other tools' output. A private key's body lines hold
# nothing a rule can see, so every line from a BEGIN ... PRIVATE KEY line to
# its END line is masked. Lines that look like key body (base64) are held
# back until the next other line: when that is an END ... PRIVATE KEY line,
# they were the end of a key whose BEGIN line came before this input (a
# window of a longer output), and they are masked too.
if ($mask_mode) {
  my $body = qr/\A[ \t]*[A-Za-z0-9+\/=]{16,}[ \t]*\z/;
  my ($in_key, @held) = (0);
  my $out = sub { say_line('  ' . $_[0]) };
  while (my $line = <STDIN>) {
    $line =~ s/\r?\n\z//;
    my $plain = Esc::plain($line);
    if ($in_key) {
      $out->(mask($line, 0));
      $in_key = 0 if $plain =~ $pem_end;
    } elsif ($plain =~ $pem_begin) {
      $out->(mask_text($_)) for splice @held;
      $out->(mask_text($line));
      $in_key = 1 unless $plain =~ $pem_end;
    } elsif ($plain =~ $body) {
      push @held, $line;
      $out->(mask_text(shift @held)) if @held > 200;
    } elsif ($plain =~ $pem_end) {
      $out->(mask($_, 0)) for splice @held;
      $out->(mask_text($line));
    } else {
      $out->(mask_text($_)) for splice @held;
      $out->(mask_text($line));
    }
  }
  $out->(mask_text($_)) for @held;
  exit 0;
}

# git runs through lib/git.pl's fixed options and cleaned environment, so
# GIT_INDEX_FILE or a file-system monitor cannot change what is scanned.
require File::Spec->catfile(dirname(File::Spec->rel2abs(__FILE__)), 'git.pl');

# git_pipe ARGS: a pipe from git with its warnings discarded, because a
# warning can quote a file name raw.
sub git_pipe {
  my @args = @_;
  open my $saved, '>&', \*STDERR or die "secrets: cannot save stderr\n";
  open STDERR, '>', File::Spec->devnull or die "secrets: cannot silence git\n";
  my $ok = open my $p, '-|', @Git::GIT, @args;
  open STDERR, '>&', $saved or die "secrets: cannot restore stderr\n";
  die "secrets: git $args[0] did not run\n" unless $ok;
  return $p;
}

my $allow_file = shift @ARGV;
die "secrets: usage: secrets.pl --repo [--ids] ALLOW_FILE, or secrets.pl [--staged] [--ids] ALLOW_FILE FILE...\n"
  unless defined $allow_file && !($repo_mode && @ARGV);
if ($repo_mode) {
  local $/ = "\0";
  my $l = git_pipe('ls-files', '-z');
  while (my $p = <$l>) {
    chomp $p;
    push @ARGV, $p if -f $p;
  }
  close $l or die "secrets: git ls-files failed\n";
}

# The allowlist: PATH<TAB>ID<TAB>REASON. Errors name the line, never its text.
my (%allow, @allow_lines);
if (-f $allow_file) {
  open my $a, '<', $allow_file or die "secrets: cannot read $allow_file\n";
  my $ln = 0;
  while (my $l = <$a>) {
    $ln++;
    $l =~ s/\r?\n\z//;
    next if $l =~ /^\s*(?:#|$)/;
    my ($path, $id, $reason) = split /\t/, $l, 3;
    die "secrets: $allow_file line $ln is not PATH<TAB>ID<TAB>REASON with a 12-character ID and a reason\n"
      unless defined $reason && $reason =~ /\S/ && $id =~ /^[0-9a-f]{12}$/ && length $path;
    $allow{$path}{$id} = $ln;
    push @allow_lines, [$ln, $path, $id];
  }
}
my %allow_used;

# The ID of TEXT found in PATH: the start of git's object ID for
# "PATH\0TEXT". git hash-object reads it from a pipe, so the text never
# touches the disk.
my %id_cache;
sub allow_id {
  my ($path, $text) = @_;
  my $key = "$path\0$text";
  return $id_cache{$key} if exists $id_cache{$key};
  my $pid = open2(my $out, my $in, @Git::GIT, 'hash-object', '--stdin');
  binmode $in;
  print $in $key;
  close $in;
  my $oid = <$out>;
  close $out;
  waitpid $pid, 0;
  die "secrets: git hash-object did not run\n" unless defined $oid && $oid =~ /^([0-9a-f]{12})/;
  return $id_cache{$key} = $1;
}

my ($examined, $bad, $allowed_hits, $skipped, $staged_examined) = (0, 0, 0, 0, 0);
my @skipped_names;

# report PATH WHERE KIND TEXT IS_TOKEN SEEN SKIP_SEEN
sub report {
  my ($path, $where, $kind, $text, $is_token, $seen, $skip_seen) = @_;
  return if $skip_seen && $seen->{$text};
  $seen->{$text} = 1;
  if ($allow{$path}) {
    my $id = allow_id($path, $text);
    if (exists $allow{$path}{$id}) {
      $allow_used{"$path\t$id"} = 1;
      $allowed_hits++;
      return;
    }
  }
  my $tail = $show_ids ? ' [id ' . allow_id($path, $text) . ']' : '';
  say_line("secrets: $where: $kind: " . mask($text, $is_token) . $tail);
  $bad++;
}

# Every rule on one line of text.
sub scan_line {
  my ($path, $where, $line, $seen, $skip_seen) = @_;
  for my $i (0 .. $#token_rules) {
    while ($line =~ /$token_cap[$i]/g) { report($path, $where, $token_rules[$i][1], $1, 1, $seen, $skip_seen) }
  }
  while ($line =~ /$quoted_cred/g) {
    my ($name, $value) = ($2, $3);
    report($path, $where, 'hard-coded credential', $value, 0, $seen, $skip_seen) if cred_is_real($name, $value);
  }
  if ($line =~ /$env_cred/) {
    my ($name, $value) = ($2, $3);
    report($path, $where, 'credential in an env-style assignment', $value, 0, $seen, $skip_seen) if cred_is_real($name, $value);
  }
  while ($line =~ /($email_re)/g) {
    my $e = $1;
    report($path, $where, 'email address (personal data)', $e, 0, $seen, $skip_seen) unless email_ok($e);
  }
  report($path, $where, 'phone number (personal data)', $_, 0, $seen, $skip_seen) for phone_hits($line);
  report($path, $where, 'bank account number (IBAN)', $_, 0, $seen, $skip_seen) for iban_hits($line);
}

# The runs of printable bytes in raw content, with every rule or keys only.
sub scan_runs {
  my ($path, $label, $raw, $seen, $all_rules) = @_;
  for my $run ($raw =~ /([\x20-\x7E]{16,})/g) {
    if ($all_rules) {
      scan_line($path, "$label (raw bytes)", $run, $seen, 1);
      next;
    }
    for my $i (0 .. $#token_rules) {
      while ($run =~ /$token_cap[$i]/g) { report($path, "$label (binary)", $token_rules[$i][1], $1, 1, $seen, 1) }
    }
  }
}

sub share_nul {
  my ($head, $start) = @_;
  my ($all, $nul) = (0, 0);
  for (my $i = $start; $i < length $head; $i += 2) { $all++; $nul++ if substr($head, $i, 1) eq "\0" }
  return $all ? $nul / $all : 0;
}

# UTF-16 to text without the Encode module (Git for Windows' perl may lack it).
# Characters outside the BMP come out as two surrogate code points, which
# does not matter for this scan.
sub utf16 {
  my ($bytes, $order) = @_;
  $bytes = substr($bytes, 0, length($bytes) - length($bytes) % 2);
  return join '', map { chr } unpack($order eq 'LE' ? 'v*' : 'n*', $bytes);
}

# Returns (text, kind, raw): raw is set whenever the bytes hold a NUL or start
# with a UTF-16 byte-order mark.
sub classify {
  my ($bytes) = @_;
  my $raw = (index($bytes, "\0") >= 0 || $bytes =~ /^(?:\xFF\xFE|\xFE\xFF)/) ? $bytes : undef;
  return (utf16(substr($bytes, 2), 'LE'), 'text', $raw) if $bytes =~ /^\xFF\xFE/;
  return (utf16(substr($bytes, 2), 'BE'), 'text', $raw) if $bytes =~ /^\xFE\xFF/;
  if (defined $raw) {
    my $head = substr($bytes, 0, 4096);
    return (utf16($bytes, 'LE'), 'text', $raw) if share_nul($head, 1) > 0.9;
    return (utf16($bytes, 'BE'), 'text', $raw) if share_nul($head, 0) > 0.9;
    return (undef, 'binary', $raw);
  }
  return ($bytes, 'text', undef);
}

sub scan_content {
  my ($path, $label, $bytes) = @_;    # LABEL is the file name as shown, masked
  my ($text, $kind, $raw) = classify($bytes);
  my %seen;
  if ($kind eq 'binary') {
    $skipped++;
    push @skipped_names, $label;
    say_line("NOTE skipped binary file $label");
    scan_runs($path, $label, $raw, \%seen, 0);
    return;
  }
  $examined++;
  my $n = 0;
  for my $line (split /\r\n|\r|\n/, $text) {
    $n++;
    scan_line($path, "$label:$n", $line, \%seen, 0);
  }
  scan_runs($path, $label, $raw, \%seen, 1) if defined $raw;
}

sub read_raw {
  my ($file) = @_;
  open my $fh, '<:raw', $file or return undef;
  local $/;
  my $bytes = <$fh>;
  close $fh;
  return defined $bytes ? $bytes : '';
}

# With --staged, every tracked name is scanned as text, once. It is shown
# masked, so a key or an email in a name is never printed in full.
my %name_done;
sub scan_name {
  my ($path) = @_;
  return if $name_done{$path}++;
  scan_line($path, 'a tracked file name (' . mask_text($path) . ')', $path, {}, 0);
}

for my $file (@ARGV) {
  my $bytes = read_raw($file);
  if (!defined $bytes) { say_line('secrets: cannot read ' . mask_text($file)); $bad++; next; }
  scan_content($file, mask_text($file), $bytes);
}

# Staged copies that differ from the working tree.
if ($staged) {
  my %differs;
  {
    local $/ = "\0";
    # no filter program runs and no stat shortcut hides an edit (lib/git.pl)
    my $d = git_pipe(Git::status_options(), 'diff', '--name-only', '-z');
    while (my $p = <$d>) { chomp $p; $differs{$p} = 1 }
    close $d or die "secrets: git diff failed\n";
    # files marked assume-unchanged (lower-case tag) or skip-worktree (S), which
    # git diff does not compare
    my $v = git_pipe('ls-files', '-v', '-z');
    while (my $e = <$v>) {
      chomp $e;
      my ($tag, $p) = split / /, $e, 2;
      $differs{$p} = 1 if defined $p && ($tag =~ /^[a-z]$/ || $tag eq 'S');
    }
    close $v or die "secrets: git ls-files -v failed\n";
  }
  {
    local $/ = "\0";
    my $l = git_pipe('ls-files', '-s', '-z');
    my @blobs;
    while (my $e = <$l>) {
      chomp $e;
      my ($meta, $path) = split /\t/, $e, 2;
      my ($mode, $oid) = split / /, $meta;
      scan_name($path);
      # a symlink's stored target is text too, whatever it points at
      push @blobs, [$path, $oid, ' (link target)'] if $mode eq '120000';
      push @blobs, [$path, $oid, ' (staged)'] if $differs{$path} && $mode ne '160000' && $mode ne '120000';
    }
    close $l or die "secrets: git ls-files failed\n";
    for my $b (@blobs) {
      my ($path, $oid, $kind) = @$b;
      local $/;
      my $c = git_pipe('cat-file', 'blob', $oid);
      binmode $c;
      my $bytes = <$c>;
      close $c or die "secrets: git cat-file failed\n";
      my $before = $examined;
      scan_content($path, mask_text($path) . $kind, defined $bytes ? $bytes : '');
      $staged_examined += $examined - $before;
    }
  }
}

for my $e (@allow_lines) {
  my ($ln, $path, $id) = @$e;
  say_line("NOTE $allow_file line $ln matched nothing; remove it if the text is gone") unless $allow_used{"$path\t$id"};
}

my @shown = map { esc($_) } @skipped_names[0 .. ($#skipped_names < 4 ? $#skipped_names : 4)];
$examined -= $staged_examined;
print "EXAMINED $examined\nSTAGED $staged_examined\nBAD $bad\nALLOWED $allowed_hits\nSKIPPED $skipped\nSKIPPED_NAMES "
  . join(', ', @shown) . ($skipped > 5 ? ', ...' : '') . "\n";
if ($repo_mode) {
  my $extra = ($staged_examined ? " and $staged_examined staged copies and link targets" : '')
    . ($skipped ? "; $skipped binary files searched for keys only" : '') . ($allowed_hits ? "; $allowed_hits allowed" : '');
  if ($bad) { print "RESULT FAIL $bad finding(s) in $examined tracked text files\n" }
  elsif (!$examined) { print "RESULT SKIPPED examined no tracked text file\n" }
  else { print "RESULT PASS examined $examined tracked text files$extra\n" }
}
