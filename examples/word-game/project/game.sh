#!/usr/bin/env bash
# game.sh: a word game in the terminal. Each round shows a word with its
# letters scrambled; type the word to score. "bash game.sh --once" plays
# one round with no guess and stops, so a check can see that it starts.
# shellcheck source-path=SCRIPTDIR
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=score.sh
. "$here/score.sh"

total=0
while IFS= read -r word <&3; do
  [ -n "$word" ] || continue
  echo "Round: $(scramble "$word")"
  if [ "${1:-}" = --once ]; then
    echo "game: started, 1 round shown"
    exit 0
  fi
  printf 'Your guess: '
  IFS= read -r guess || break
  points=$(score_guess "$word" "$guess")
  total=$((total + points))
  echo "$points points (total $total)"
done 3<"$here/words.txt"
echo "Game over: $total points."
