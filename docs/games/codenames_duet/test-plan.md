# Codenames Duet test plan

One line per test. The § numbers refer to `rulebook.md`. Files: `test/codenames_duet/game_test.exs` (G), `test/codenames_duet/property_test.exs` (P), `test/codenames_duet/table_test.exs` (T). Builders: `test/support/codenames_duet_scenario.ex` (`fixed/1`: a known board and key; the index table is in its moduledoc).

## Rules

- §1.1 (G) 2 seats; one result for both.
- §1.1 (T) A room has 0 bots (a bot seat is refused); each seat gets its own view.
- §1.2 (G) 25 different words from the list; the first event is the set-up.
- §1.2 (G) The same seed deals the same words and key; another seed others.
- §1.2 §1.4 (P) A seed and the same actions give the same game.
- §1.3 (G) Each side: 9 green, 3 assassins, 13 bystanders (30 seeds).
- §1.4 (G) The pairs of each key are the layout: 3 G/G, 5 G/N, 5 N/G, 1 G/A, 1 A/G, 1 A/A, 1 A/N, 1 N/A, 7 N/N; 15 greens.
- §1.3 §1.4 (P) Every key has the layout's pairs.
- §1.5 (G) 9 tokens; `timer` 1..11; 0 and 12 refused.
- §1.6 (G) A seat sees only its side; a spectator none; the log has no key.
- §1.6 (G) At the end the whole key shows.
- §1.6 (P) A view does not change when the partner's hidden colours are shuffled (seats and spectator).
- §2.1 (G) Both seats can give the first clue; then the other seat guesses.
- §2.2 (G) The clue giver cannot guess; the guesser cannot give a clue.
- §2.3 (G) The seats alternate.
- §2.4 (G) A done side gives no more clues; the partner gives all clues.
- §3.1 (G) Numbers 0..9; 10, −1, `:unlimited`, `"2"` refused.
- §3.2 (G) A visible word is refused in any case and with spaces.
- §3.2 (G) A covered word is fine; one bystander mark keeps a word visible.
- §3.2 (G) A word marked from both sides is covered.
- §3.3 (G) Word forms (`apples`, `baked`) and parts of 4+ letters (`earth`) refused; `ear`, `hearth` fine.
- §3.4 (G) One word: letters, inside hyphen or apostrophe, 30 letters at most.
- §3.6 (G) An invalid clue is refused and uses no token.
- §4.1 (G) The clue giver's side decides the guess.
- §4.2 (G) Green: agent, guess again past the clue number.
- §4.2 (G) A green/green word is found for both sides.
- §4.3 (G) Bystander: marked for the clue giver, the turn ends, one token, the other seat clues next.
- §4.4 (G) Assassin of the clue giver's side: both lose; no actions after.
- §4.4 (G) An assassin of the guesser's own side does not count for its guess.
- §4.5 (G) One mark: not again on that side's turns, yes on the other side's.
- §4.5 §6.3 (P) A guess that is not in `legal_actions` returns an error.
- §4.6 (G) Stop only after a guess, also after a 0 clue; the stop uses a token.
- §4.7 (G) Any open word can be guessed.
- §4.8 (G) The clue giver's last green: the turn ends with a token.
- §5.1 (G) One token per turn, by a bystander or a stop.
- §5.1 §6.1 §6.2 §6.3 (P) Random legal play ends, won or lost; tokens used = turn ends.
- §5.2 (G) After the 9th turn: sudden death, no clues.
- §5.3 (G) The winning turn takes no token.
- §6.1 (G) 15 agents: both win at once.
- §6.2 (G) An assassin loses with tokens left.
- §6.3 (G) Sudden death: no clues, no stop; both seats guess in any order, each on the partner's side.
- §6.3 (G) Sudden death: a bystander loses; an assassin loses.
- §6.3 (G) Sudden death: a seat with no words left is not a guesser; the last green wins.
- §6.3 (G) Sudden death: a word marked from the partner's side cannot be guessed.
- §6.4 (G) Score: 3 per token left after the winning turn, 1 per stop, −1 for sudden death; nil for a loss.
- §8 (G) Defaults; unknown options, a bad seed, a bad seat and a bad action are refused.

§7 (out of scope) has no tests.

## Bots

None (see the report of the `codenames-engine` round).
