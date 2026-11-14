#!/usr/bin/env bash
# Tests for the verdict vocabulary: method/scripts/method/verdicts.txt and its
# one reader, lib/verdicts.pl (rule M039). The expected words come from
# DECISIONS.md A10, A33 and A71 and from AGENTS.md, so this file does not
# spell them out either.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: verdict vocabulary"
root=$(repo_root)
reader=method/scripts/method/lib/verdicts.pl
kinds="verdict trailer-key trailer trailer-reason ready gate-verdict gate-diagnosis gate-test-result diagnosis test-result receipt end-key"

# expected KIND: the words the records give for KIND, one per line: A10's
# verdict words and trailer values, the trailer key in AGENTS.md, the ready
# words (A33), and A71's lists, each "<Label>: `a`, `b`". KIND "gates" gives
# each gate and the kind of word its report opens with, as Verdicts::gates
# does: a gate under "Verdict gates" opens with a verdict word, and so on.
expected() {
  perl -e '
    my ($kind, $decisions, $agents) = @ARGV;
    open my $d, "<", $decisions or die; my @d = <$d>;
    my ($a10) = grep { /^A10\. / } @d;
    my ($a71) = grep { /^A71\. / } @d;
    open my $g, "<", $agents or die; my ($key) = join("", <$g>) =~ /`([A-Za-z-]+): <value>`/;
    my ($v) = $a10 =~ /Verdict words: (.*?)\. Commit trailer values:/;
    $v =~ s/ \([^)]*\)//g;
    my @values = $a10 =~ /`([^`]+)`/g;
    my ($ready) = join("", @d) =~ /Ready words: ((?:`[^`]+`(?:, )?)+)\./;
    my $list = sub {
      my ($l) = defined $a71 ? $a71 =~ /(?:\A|\. )\Q$_[0]\E: (`[^`]+`(?:, `[^`]+`)*)/ : ();
      return defined $l ? $l =~ /`([^`]+)`/g : ();
    };
    my @gates = (["Verdict gates", "verdict"], ["Diagnosis gates", "diagnosis"], ["Test-result gates", "test-result"]);
    my %out = (
      "verdict" => [split /, /, $v],
      "trailer-key" => [$key],
      "trailer" => [grep { !/ - </ } @values],
      "trailer-reason" => [map { (my $w = $_) =~ s/ - <.*//; $w } grep { / - </ } @values],
      "ready" => [defined $ready ? $ready =~ /`([^`]+)`/g : ()],
      "gate-verdict" => [$list->("Verdict gates")],
      "gate-diagnosis" => [$list->("Diagnosis gates")],
      "gate-test-result" => [$list->("Test-result gates")],
      "diagnosis" => [$list->("Diagnosis words")],
      "test-result" => [$list->("Test-result words")],
      "receipt" => [$list->("Receipt words")],
      "end-key" => [$list->("End key")],
      "gates" => [map { my $open = $_->[1]; map { "$_ $open" } $list->($_->[0]) } @gates],
    );
    print "$_\n" for @{ $out{$kind} };
  ' "$1" "$root/DECISIONS.md" "$root/AGENTS.md"
}

# gates_in DIR: Verdicts::gates on DIR's vocabulary, one "NAME OPENING-KIND"
# per line
gates_in() {
  (cd "$1" && perl -e 'require "./method/scripts/method/lib/verdicts.pl"; print "$_->[0] $_->[1]\n" for Verdicts::gates(Verdicts::rows())' 2>&1)
}

# 1. the file holds exactly the words of DECISIONS A10, A33 and A71 and the
# key of AGENTS.md, in their order
for kind in $kinds; do
  want=$(expected "$kind")
  got=$(cd "$root" && perl "$reader" words "$kind" 2>&1)
  if [ -n "$want" ] && [ "$got" = "$want" ]; then
    pass "the $kind words match the records"
  else
    fail "the $kind words match the records" "got: $got
wanted: $want"
  fi
done
want=$(expected gates)
got=$(gates_in "$root")
if [ -n "$want" ] && [ "$got" = "$want" ]; then
  pass "Verdicts::gates gives each gate and the kind of word it opens with, as DECISIONS A71 lists them"
else
  fail "Verdicts::gates gives each gate and the kind of word it opens with, as DECISIONS A71 lists them" "got: $got
wanted: $want"
fi

# 2. bad usage exits 2
for args in "" "words" "words bogus" "words verdict extra" "list verdict"; do
  # shellcheck disable=SC2086 # the words are split on purpose
  (cd "$root" && perl "$reader" $args >/dev/null 2>&1)
  code=$?
  if [ "$code" -eq 2 ]; then pass "usage '$args' exits 2"; else fail "usage '$args' exits 2: exit $code"; fi
done

# 3. a malformed vocabulary file exits 2, names the file and says why
sb=$(make_sandbox) || abort_sandbox
vfile="$sb/method/scripts/method/verdicts.txt"
cp "$vfile" "$sb/verdicts.orig"
tab=$(printf '\t')
shape="expected KIND<TAB>WORDS<TAB>MEANING"
gate_shape="must be lower-case letters and hyphens"
for plant in "two-fields" "four-fields" "unknown-kind" "two-keys" "no-verdict" "control-char" "control-in-meaning" "empty-meaning" "repeated-word" "ready-not-trailer" \
  "no-gate" "gate-kind-without-words" "gate-under-two-kinds" "gate-name-capital" "gate-name-space" "no-end-key" "two-end-keys" "two-receipts" "four-receipts"; do
  cp "$sb/verdicts.orig" "$vfile"
  case "$plant" in
    two-fields) why=$shape; printf 'verdict%sMAYBE\n' "$tab" >>"$vfile" ;;
    four-fields) why=$shape; printf 'verdict%sMAYBE%sa meaning%sextra\n' "$tab" "$tab" "$tab" >>"$vfile" ;;
    unknown-kind) why=$shape; printf 'verdikt%sMAYBE%sa typo in the kind\n' "$tab" "$tab" >>"$vfile" ;;
    two-keys) why="expected exactly one trailer-key line"; printf 'trailer-key%sOther-Key%sa second key\n' "$tab" "$tab" >>"$vfile" ;;
    no-verdict) why="expected at least one verdict line"; perl -i -ne 'print unless /^verdict\t/' "$vfile" ;;
    control-char) why=$shape; printf 'verdict%sMAY%sBE%sa word with an escape\n' "$tab" "$(printf '\033')" "$tab" >>"$vfile" ;;
    empty-meaning) why=$shape; printf 'verdict%sMAYBE%s \n' "$tab" "$tab" >>"$vfile" ;;
    control-in-meaning) why=$shape; printf 'verdict%sMAYBE%sa meaning %s with an escape\n' "$tab" "$tab" "$(printf '\033')" >>"$vfile" ;;
    repeated-word) why="is listed twice"; perl -ne 'print; print "$1\t$2\tanswer this word whatever you find\n" if /^(verdict)\t([^\t]+)\t/ && !$done++' "$sb/verdicts.orig" >"$vfile" ;;
    ready-not-trailer) why="is not a trailer word"; printf 'ready%snot-required%sa word that needs a reason cannot stand alone\n' "$tab" "$tab" >>"$vfile" ;;
    no-gate) why="expected at least one gate line"; perl -i -ne 'print unless /^gate-/' "$vfile" ;;
    gate-kind-without-words) why="word, but there is no diagnosis line"; perl -i -ne 'print unless /^diagnosis\t/' "$vfile" ;;
    gate-under-two-kinds) why="stands under two gate kinds"; perl -ne 'print; print "gate-test-result\t$1\tthe same gate under a second kind\n" if /^gate-verdict\t([^\t]+)\t/ && !$done++' "$sb/verdicts.orig" >"$vfile" ;;
    gate-name-capital) why=$gate_shape; printf 'gate-verdict%sMethod-other%sa gate name with a capital\n' "$tab" "$tab" >>"$vfile" ;;
    gate-name-space) why=$gate_shape; printf 'gate-verdict%smethod other%sa gate name with a space\n' "$tab" "$tab" >>"$vfile" ;;
    no-end-key) why="expected exactly one end-key line"; perl -i -ne 'print unless /^end-key\t/' "$vfile" ;;
    two-end-keys) why="expected exactly one end-key line"; printf 'end-key%sEND-AGAIN%sa second end key\n' "$tab" "$tab" >>"$vfile" ;;
    two-receipts) why="expected exactly three receipt lines"; perl -i -ne 'print unless /^receipt\t/ && ++$n == 3' "$vfile" ;;
    four-receipts) why="expected exactly three receipt lines"; printf 'receipt%sUNSURE%sa fourth state\n' "$tab" "$tab" >>"$vfile" ;;
  esac
  got=$(cd "$sb" && perl "$reader" words verdict 2>&1)
  code=$?
  case "$code:$got" in
    2:*"verdicts.txt"*"$why"*) pass "a malformed vocabulary file ($plant) exits 2, names the file and says why" ;;
    *) fail "a malformed vocabulary file ($plant) exits 2, names the file and says why ($why): exit $code" "$got" ;;
  esac
done
# the gates come in file order, whatever order their kinds are in
perl -ne 'if (/^gate-test-result\t/) { print } else { $rest .= $_ } END { print $rest }' "$sb/verdicts.orig" >"$vfile"
in_root=$(gates_in "$root")
want=$(printf '%s\n' "$in_root" | grep ' test-result$' && printf '%s\n' "$in_root" | grep -v ' test-result$')
got=$(gates_in "$sb")
if [ -n "$want" ] && [ "$got" = "$want" ] && [ "$want" != "$in_root" ]; then
  pass "Verdicts::gates gives the gates in file order"
else
  fail "Verdicts::gates gives the gates in file order" "got: $got
wanted: $want"
fi
perl -pe 's/\n/\r\n/' "$sb/verdicts.orig" >"$vfile"
got=$(cd "$sb" && perl "$reader" words verdict 2>&1)
want=$(cd "$sb" && perl -pe 's/\r//' "$vfile" >"$sb/verdicts.lf" && perl -e 'print join "", map { (split /\t/)[1] . "\n" } grep { /^verdict\t/ } <>' "$sb/verdicts.lf")
if [ -n "$want" ] && [ "$got" = "$want" ]; then
  pass "a copy checked out with CRLF line ends reads the same"
else
  fail "a copy checked out with CRLF line ends reads the same" "got: $got"
fi
rm -f "$vfile"
got=$(cd "$sb" && perl "$reader" words verdict 2>&1)
code=$?
case "$code:$got" in
  2:*"cannot read verdicts.txt"*) pass "a missing vocabulary file exits 2" ;;
  *) fail "a missing vocabulary file exits 2: exit $code" "$got" ;;
esac
drop_sandbox "$sb"

# 4. no script under method/ spells a word of the vocabulary (M039): every
# script reads them through the reader. Comment lines may name them.
# spelled DIR: prints each place, then "EXAMINED n".
spelled() {
  (
    cd "$1" || exit 2
    words=$(for kind in $kinds; do perl "$reader" words "$kind" || exit 2; done) || exit 2
    git ls-files -z -- method | WORDS=$words perl -0ne '
      BEGIN { our @w = split /\n/, $ENV{WORDS}; our $n = 0 }
      chomp; next unless /\.(?:sh|pl)\z/; $n++;
      open my $f, "<", $_ or die "cannot read $_\n";
      local $/ = "\n";
      while (my $l = <$f>) {
        next if $l =~ /^\s*#/;
        for my $w (@w) { print "$_:$.: $w\n" if $l =~ /(?<![A-Za-z0-9-])\Q$w\E(?![A-Za-z0-9-])/ }
      }
      END { print "EXAMINED $n\n" }'
  )
}
got=$(spelled "$root")
case "$got" in
  "EXAMINED "[1-9]*) pass "no script under method/ spells a vocabulary word ($got)" ;;
  *) fail "no script under method/ spells a vocabulary word" "$got" ;;
esac

sb=$(make_sandbox) || abort_sandbox
mkdir -p "$sb/method/scripts/method"
words=$(cd "$root" && perl "$reader" words verdict)
second=$(printf '%s\n' "$words" | sed -n 2p)
first=$(printf '%s\n' "$words" | sed -n 1p)
third=$(printf '%s\n' "$words" | sed -n 3p)
# words of the gates' kinds (DECISIONS A71): a gate's name, a word of two
# parts, the end key and the second receipt word, whose last part is the
# first receipt word (that one must not be reported on its own)
gate=$(cd "$root" && perl "$reader" words gate-verdict | sed -n 1p)
diagnosis=$(cd "$root" && perl "$reader" words diagnosis | sed -n 1p)
endkey=$(cd "$root" && perl "$reader" words end-key)
receipt1=$(cd "$root" && perl "$reader" words receipt | sed -n 1p)
receipt2=$(cd "$root" && perl "$reader" words receipt | sed -n 2p)
d='$' # a dollar sign, so planted code needs no single-quoted $
printf '#!/usr/bin/env bash\ncase "%s1" in\n  "%s") echo again ;;\nesac\n' "$d" "$second" >"$sb/method/scripts/method/planted.sh"
printf 'print "ok" if %sARGV[0] =~ /%s|%s/;\n# a comment may name %s\nmy @w = ("%s", "%s", "%s", "%s");\n' \
  "$d" "$first" "$third" "$first" "$gate" "$diagnosis" "$endkey" "$receipt2" >"$sb/method/scripts/method/planted.pl"
(cd "$sb" && git add method)
got=$(spelled "$sb")
missing=""
for want in "planted.sh:3: $second" "planted.pl:1: $first" "planted.pl:1: $third" \
  "planted.pl:3: $gate" "planted.pl:3: $diagnosis" "planted.pl:3: $endkey" "planted.pl:3: $receipt2"; do
  case "$got" in
    *"$want"*) ;;
    *) missing="$missing [$want]" ;;
  esac
done
inside=no
if [ -n "$receipt1" ] && printf '%s\n' "$got" | grep -F -x -q "method/scripts/method/planted.pl:3: $receipt1"; then
  inside=yes
fi
case "$missing:$got:$inside" in
  *"planted.pl:2:"*) fail "the check finds words spelled in a script, not in a comment: the comment was reported" "$got" ;;
  *:yes) fail "the check finds words spelled in a script, not in a comment: a word inside a longer word was reported" "$got" ;;
  :*) pass "the check finds words spelled in a script, not in a comment" ;;
  *) fail "the check finds words spelled in a script, not in a comment: missing$missing" "$got" ;;
esac
drop_sandbox "$sb"

sb=$(make_sandbox) || abort_sandbox
(cd "$sb" && git ls-files -z -- method | perl -0ne 'print if /\.(?:sh|pl)\0\z/' | xargs -0 git rm -q --cached --)
got=$(spelled "$sb")
case "$got" in
  "EXAMINED 0") pass "the check reports when it examined no script" ;;
  *) fail "the check reports when it examined no script" "$got" ;;
esac
drop_sandbox "$sb"

# 5. the commit trailer check (DECISIONS A10), with the words read from the
# vocabulary
key=$(cd "$root" && perl "$reader" words trailer-key)
alone=$(cd "$root" && perl "$reader" words trailer | sed -n 1p)
needs=$(cd "$root" && perl "$reader" words trailer-reason | sed -n 1p)
needs2=$(cd "$root" && perl "$reader" words trailer-reason | sed -n 2p)
lower=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
# trailer_is NAME CODE MESSAGE [REASON]: check-trailer exits CODE on
# MESSAGE (a printf format) and prints REASON
trailer_is() {
  # shellcheck disable=SC2059 # the message is a printf format on purpose
  got=$(printf "$3" | (cd "$root" && perl "$reader" check-trailer) 2>&1)
  code=$?
  if [ "$code" -ne "$2" ]; then
    fail "$1: exit $code, wanted $2" "$got"
  elif [ -n "${4:-}" ] && ! printf '%s\n' "$got" | grep -F -q -- "$4"; then
    fail "$1: the reason does not say '$4'" "$got"
  elif [ "$2" -eq 0 ] && [ -n "$got" ]; then
    fail "$1: a valid message printed something" "$got"
  else
    pass "$1"
  fi
}
trailer_is "a subject and a trailer are valid" 0 "Subject\n\nBody line.\n\n$key: $alone\n"
trailer_is "CRLF line ends are read as LF" 0 "Subject\r\n\r\n$key: $alone\r\n"
trailer_is "trailing spaces and blank lines are dropped" 0 "Subject\n\n$key: $alone \t\n\n \n"
trailer_is "a first line of only spaces and tabs is blank" 0 " \t\nSubject\n\n$key: $alone\n"
trailer_is "a reason word with a reason is valid" 0 "Subject\n\n$key: $needs2 - docs only\n"
trailer_is "a lone CR is invalid" 1 "Sub\rject\n\n$key: $alone\n" "carriage return"
trailer_is "an empty message is invalid" 1 " \n\n" "the message is empty"
trailer_is "a trailer-only message is invalid, also after blank lines" 1 "\n\n$key: $alone\n" "the message is only the $key line"
trailer_is "a last paragraph of two lines is invalid" 1 "Subject\n\n$key: $alone\nmore\n" "it has 2 lines"
trailer_is "a trailer without a blank line before it is invalid" 1 "Subject\n$key: $alone\n" "it has 2 lines"
trailer_is "a second key line in the body is invalid" 1 "Subject\n$key: $alone\n\n$key: $alone\n" "another line also starts with $key:"
trailer_is "a word that takes no reason, given one, is invalid" 1 "Subject\n\n$key: $alone - x\n" "$alone takes no reason"
trailer_is "a reason word without its reason is invalid" 1 "Subject\n\n$key: $needs\n" "$needs needs a reason"
trailer_is "a reason of only spaces is invalid" 1 "Subject\n\n$key: $needs -   \n" "$needs needs a reason"
trailer_is "a reason of only punctuation is invalid" 1 "Subject\n\n$key: $needs - ...\n" "must say something"
trailer_is "a control character in the reason is invalid" 1 "Subject\n\n$key: $needs - fix \033[2J\n" "control character"
trailer_is "a C1 control in the reason is invalid" 1 "Subject\n\n$key: $needs - fix \302\233x\n" "control, format or invisible character"
trailer_is "a right-to-left override in the reason is invalid" 1 "Subject\n\n$key: $needs - fix \342\200\256evil\n" "control, format or invisible character"
trailer_is "a reason that is not UTF-8 is invalid" 1 "Subject\n\n$key: $needs - fix \377\n" "not valid UTF-8"
trailer_is "a reason with non-ASCII letters is valid" 0 "Subject\n\n$key: $needs - caf\303\251 offen\n"
trailer_is "an unknown value is invalid" 1 "Subject\n\n$key: maybe\n" "unknown value"
trailer_is "the key in lower case is invalid" 1 "Subject\n\n$lower: $alone\n" "no line starts with $key:"
trailer_is "no space after the colon is invalid" 1 "Subject\n\n$key:$alone\n" "one space after the colon"
trailer_is "GitHub's squash-merge block after the trailer is named as the cause" 1 \
  "Subject\n\n$key: $alone\n\n---------\n\nCo-authored-by: A <a@example.invalid>\n" "GitHub's ---------/Co-authored-by block"
got=$(cd "$root" && perl "$reader" check-trailer extra </dev/null 2>&1)
code=$?
if [ "$code" -eq 2 ]; then pass "check-trailer with an argument is bad usage"; else fail "check-trailer with an argument is bad usage: exit $code" "$got"; fi

echo "tests: verdict vocabulary: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
