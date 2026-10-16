# No Thanks! test plan

One line per test. Each line becomes one ExUnit test with `@tag rule: "§x.y"` (issue #84), named by the text after the tag. Sections are in `docs/games/no_thanks/rulebook.md`. Names (`:take`, `:no_thanks`, `game.offer`, `game.pot`) are from `CONTEXT.md`.

"Scenario" means a game built in a known state (the scenario builder from #84), not a game from a seed.

## Unit tests

### §1 Components
- `§1.1` the full card set is the integers 3..35, 33 cards, no repeats.
- `§1.3` a single card scores its own number.

### §2 Set-up
- `§2.1` `new/1` removes exactly 9 cards; removed ∪ deck ∪ offer = 3..35 with no overlap.
- `§2.1` the same seed gives the same removed cards and the same deck order.
- `§2.1` two different seeds give a different deck order (fixed seeds, not random).
- `§2.2` after `new/1` the deck has 23 cards and the offer is 1 card (24 in play).
- `§2.3` 3, 4 and 5 players: each seat starts with 11 chips.
- `§2.3` 6 players: each seat starts with 9 chips.
- `§2.3` 7 players: each seat starts with 7 chips.
- `§2.3` the pot is 0 at the start.
- `§2.4` `new/1` with 2 or 8 players returns `{:error, :player_count}`.
- `§2.5` the start seat is the active seat after `new/1` (seat 0, or the seat from the seed: follows Nick's decision).
- `§2.6` after a "no thanks" by the last seat, seat 0 is active (the order wraps).

### §3 Turn
- `§3.1` after `new/1` the offer is the top card of the shuffled deck.
- `§3.2` a seat with chips has exactly the legal actions `[:take, :no_thanks]`.
- `§3.2` an action by a seat that is not active returns `{:error, :not_your_turn}`.
- `§3.3` `:no_thanks` moves 1 chip from the seat to the pot.
- `§3.3` `:no_thanks` makes the next seat active; the offer does not change.
- `§3.4` `:take` adds the offer to the seat's tableau.
- `§3.4` `:take` adds the full pot to the seat's chips and sets the pot to 0.
- `§3.5` after `:take` the next deck card is the offer and the same seat is active.
- `§3.5` scenario: a seat takes three offers in a row and stays active each time.
- `§3.6` scenario: a seat with 0 chips has the legal actions `[:take]` only.
- `§3.6` scenario: `:no_thanks` with 0 chips returns `{:error, :no_chips}` and the game does not change.
- `§3.7` scenario: the offer goes round the table twice; the pot is 2 × players.
- `§3.8` `:take` is legal in every state that is not over (also covered by property P1).

### §4 End
- `§4.1` scenario: one card left in the deck, take the offer, take the last card → `over?/1` is true.
- `§4.1` the game is not over while there is an offer.
- `§4.1` any action after the end returns `{:error, :game_over}`.
- `§4.2` at the end the deck is empty, there is no offer, and the tableaus hold 24 cards in total.
- `§4.3` at the end the 9 removed cards are still in `game.removed`, not in any tableau.

### §5 Scoring
- `§5.1` a tableau `[13, 15, 16]` has the runs `[[13], [15, 16]]`.
- `§5.1` two consecutive cards are a run (the minimum length is 2).
- `§5.2` `[13, 15, 16]` scores 28 (S1 example).
- `§5.2` `[13, 14, 15, 16]` scores 13 (S1 example).
- `§5.2` `[17, 18, 19, 20]` scores 17 (S2 example).
- `§5.2` `[27, 28, 29, 30]` scores 27 (S3 example).
- `§5.2` the order of the cards in the tableau has no effect on the score.
- `§5.3` scenario: a take that fills a gap joins two runs; the score drops to the lower start.
- `§5.4` each chip subtracts 1 from the score.
- `§5.5` S1 example: cards worth 62 with 8 chips scores 54.
- `§5.5` S2 example: cards worth 59 with 8 chips scores 51.
- `§5.5` S2 example: singles `[4, 6, 10, 21]` with 0 chips score 41.
- `§5.5` an empty tableau with 11 chips scores −11.
- `§5.6` the seat with the lowest score is the winner.
- `§5.7` two seats with the same lowest score are both winners.
- `§5.8` a negative score is allowed and wins against a positive score.

### §6 Hidden and public information (`view/2`)
- `§6.1` `view(game, seat)` for every seat has no removed cards (no `removed` field, no removed number anywhere in the view).
- `§6.1` `view/2` after the end still has no removed cards (unless Nick decides to show them, §9.3).
- `§6.2` `view/2` has no deck order: no deck card numbers.
- `§6.3` `view/2` has the deck size.
- `§6.4` `view/2` has every seat's tableau.
- `§6.5` `view/2` has the offer and the pot.
- `§6.6` without `show_chips`: `view(game, seat)` has the seat's own chips and no other seat's chips.
- `§6.6` with `show_chips`: `view/2` has every seat's chips.
- `§6.7` without `show_chips`: the public log in `view/2` does not let a seat count another seat's chips (follows Nick's decision §9.1).
- `§6.8` at the end `view/2` has every seat's chips and score, with or without `show_chips`.
- `§6.6` `view(game, :spectator)` has only public zones (no chips without `show_chips`).

### §7 Invariants
- `§7.1` chips of all seats + pot = chips in play, after every action (also in P5).
- `§7.2` no seat has fewer than 0 chips (also in P5).
- `§7.3` deck + offer + tableaus = the 24 cards from the set-up, each once (also in P5).
- `§7.4` while the deck is not empty, a `:take` always gives a new offer at once (no "flip" action).

### §8 Variants
- `§8.1` tactical variant: 10 chips each (3-5 players); 10, 20 and 30 are in `removed`; 9 removed cards in total. (Only if Nick adds the variant, §9.6.)
- `§8.2` `show_chips` only changes `view/2`; the game state and the legal actions are the same with and without it.

## Property tests (issue #80, the generic suite)

Generators: player count 3..7, a seed, house rules (`show_chips`), and a random legal action for the active seat at each step.

- `P1 §3.8` always a legal action until over: random legal play from any seed reaches `over?/1` with `legal_actions/2` non-empty for the active seat at every step.
- `P2` the game ends: the number of actions is at most 24 × (chips in play + 1) (one offer gets at most "chips in play" "no thanks" actions, because the pot cannot hold more chips than that; then a take).
- `P3` deterministic replay: the same seed, options and action list give an equal game (`==`), and an equal `view/2` for every seat.
- `P4` an illegal action changes nothing: a random illegal action (wrong seat, `:no_thanks` with 0 chips, an unknown action, any action after the end) returns `{:error, _}`, and the game is unchanged.
- `P5 §7.1 §7.2 §7.3` the invariants hold after every action.
- `P6 §6.1 §6.2` `view/2` never has hidden zones: no removed card and no deck card number in any seat's view, at any step.
- `P7 §6.6` without `show_chips`, `view(game, seat)` never has another seat's chips before the end.
- `P8 §5.6` at the end the winners are exactly the seats with the minimum score, and there is at least one winner.

## Count per §

| § | Unit tests | Property tests | Total |
|---|---|---|---|
| §1 | 2 | 0 | 2 |
| §2 | 11 | 0 | 11 |
| §3 | 13 | 1 (P1) | 14 |
| §4 | 5 | 0 | 5 |
| §5 | 16 | 1 (P8) | 17 |
| §6 | 11 | 2 (P6, P7) | 13 |
| §7 | 4 | 1 (P5) | 5 |
| §8 | 2 | 0 | 2 |
| no § | 0 | 3 (P2, P3, P4) | 3 |
| **Total** | **64** | **8** | **72** |

The `§3.8` line and P1 prove the same rule; the §7 lines and P5 also. Both stay: the unit test gives a clear failure, the property finds the edge case.
