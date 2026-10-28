#!/usr/bin/env bash
# Tests for the verdict vocabulary: method/scripts/method/verdicts.txt and its
# one reader, lib/verdicts.pl (rule M039). The expected words come from
# DECISIONS.md A10 and AGENTS.md, so this file does not spell them out either.
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
kinds="verdict trailer-key trailer trailer-reason"

# expected KIND: the words the records give for KIND, one per line.
expected() {
  perl -e '
    my ($kind, $decisions, $agents) = @ARGV;
    open my $d, "<", $decisions or die; my ($a10) = grep { /^A10\. / } <$d>;
    open my $g, "<", $agents or die; my ($key) = join("", <$g>) =~ /`([A-Za-z-]+): <value>`/;
    my ($v) = $a10 =~ /Verdict words: (.*?)\. Commit trailer values:/;
    $v =~ s/ \([^)]*\)//g;
    my @values = $a10 =~ /`([^`]+)`/g;
    my %out = (
      "verdict" => [split /, /, $v],
      "trailer-key" => [$key],
      "trailer" => [grep { !/ - </ } @values],
      "trailer-reason" => [map { (my $w = $_) =~ s/ - <.*//; $w } grep { / - </ } @values],
    );
    print "$_\n" for @{ $out{$kind} };
  ' "$1" "$root/DECISIONS.md" "$root/AGENTS.md"
}

# 1. the file holds exactly the words of DECISIONS A10 and the key of AGENTS.md
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

# 2. bad usage exits 2
for args in "" "words" "words bogus" "words verdict extra" "list verdict"; do
  # shellcheck disable=SC2086 # the words are split on purpose
  (cd "$root" && perl "$reader" $args >/dev/null 2>&1)
  code=$?
  if [ "$code" -eq 2 ]; then pass "usage '$args' exits 2"; else fail "usage '$args' exits 2: exit $code"; fi
done

# 3. a malformed vocabulary file exits 2 and names the problem
sb=$(make_sandbox) || abort_sandbox
vfile="$sb/method/scripts/method/verdicts.txt"
cp "$vfile" "$sb/verdicts.orig"
tab=$(printf '\t')
for plant in "two-fields" "four-fields" "unknown-kind" "two-keys" "no-verdict" "control-char" "empty-meaning"; do
  cp "$sb/verdicts.orig" "$vfile"
  case "$plant" in
    two-fields) printf 'verdict%sMAYBE\n' "$tab" >>"$vfile" ;;
    four-fields) printf 'verdict%sMAYBE%sa meaning%sextra\n' "$tab" "$tab" "$tab" >>"$vfile" ;;
    unknown-kind) printf 'verdikt%sMAYBE%sa typo in the kind\n' "$tab" "$tab" >>"$vfile" ;;
    two-keys) printf 'trailer-key%sOther-Key%sa second key\n' "$tab" "$tab" >>"$vfile" ;;
    no-verdict) perl -i -ne 'print unless /^verdict\t/' "$vfile" ;;
    control-char) printf 'verdict%sMAY%sBE%sa word with an escape\n' "$tab" "$(printf '\033')" "$tab" >>"$vfile" ;;
    empty-meaning) printf 'verdict%sMAYBE%s \n' "$tab" "$tab" >>"$vfile" ;;
  esac
  got=$(cd "$sb" && perl "$reader" words verdict 2>&1)
  code=$?
  case "$code:$got" in
    2:*"verdicts.txt"*) pass "a malformed vocabulary file ($plant) exits 2 and names the file" ;;
    *) fail "a malformed vocabulary file ($plant) exits 2 and names the file: exit $code" "$got" ;;
  esac
done
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
d='$' # a dollar sign, so planted code needs no single-quoted $
printf '#!/usr/bin/env bash\ncase "%s1" in\n  "%s") echo again ;;\nesac\n' "$d" "$second" >"$sb/method/scripts/method/planted.sh"
printf 'print "ok" if %sARGV[0] =~ /%s|%s/;\n# a comment may name %s\n' "$d" "$first" "$third" "$first" >"$sb/method/scripts/method/planted.pl"
(cd "$sb" && git add method)
got=$(spelled "$sb")
missing=""
for want in "planted.sh:3: $second" "planted.pl:1: $first" "planted.pl:1: $third"; do
  case "$got" in
    *"$want"*) ;;
    *) missing="$missing [$want]" ;;
  esac
done
case "$missing:$got" in
  *"planted.pl:2:"*) fail "the check finds words spelled in a script, not in a comment: the comment was reported" "$got" ;;
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

echo "tests: verdict vocabulary: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
