# shellcheck shell=bash
# score.sh: the game's rules, sourced by game.sh and test.sh.

# score_guess WORD GUESS: prints the guess's score: 0 when it is not the
# word, else 10 points less one for each hint taken (HINTS, 0 when unset),
# never below 1
score_guess() {
  if [ "$1" != "$2" ]; then
    echo 0
    return
  fi
  sg_score=$((10 - ${HINTS:-0}))
  [ "$sg_score" -lt 1 ] && sg_score=1
  echo "$sg_score"
}

# scramble WORD: prints WORD with its letters in reverse order, a fixed
# shuffle, so a round can be tested
scramble() {
  sc_out=''
  sc_word=$1
  while [ -n "$sc_word" ]; do
    sc_out=$sc_out${sc_word#"${sc_word%?}"}
    sc_word=${sc_word%?}
  done
  echo "$sc_out"
}
