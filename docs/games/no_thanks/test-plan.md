# No Thanks! — test plan

Each case is tagged with the rulebook § it covers (`docs/games/no_thanks/rulebook.md`). Terms are from `CONTEXT.md`. API used below: `NoThanks.Game.new(opts)`, `apply(game, {seat, action})`, `legal_actions(game, seat)`, `view(game, seat)`, `scores(game)`, `winners(game)`. "A fixed game" means one built with a test helper that sets the pile, removed cards, chips and cards directly, so it does not depend on a seed.

## A. Setup

1. **§2.1** Given 3, 4 or 5 players, when `new/1` runs, then every seat has 11 chips.
2. **§2.1** Given 6 players, when `new/1` runs, then every seat has 9 chips.
3. **§2.1** Given 7 players, when `new/1` runs, then every seat has 7 chips.
4. **§2.1, §8.1** Given 2 or 8 players and no house rule, when `new/1` runs, then it returns `{:error, :invalid_player_count}`.
5. **§1, §2.2** Given any valid seed, when `new/1` runs, then `removed ++ pile ++ [offer]` is a permutation of `3..35`, with no duplicates and none missing.
6. **§2.2** Given any seed, when `new/1` runs, then `length(removed) == 9`, `length(pile) == 23` and `offer` is an integer.
7. **§2.2** Given a new game, then `pot == 0`, every seat's `cards == []` and `phase == :playing`.
8. **§2.2** Given 200 different seeds, when games are created, then the removed sets are not all the same, and every value 3..35 is removed at least once (removal is random, not a fixed rule).
9. **§2.3** Given `start_seat: 2`, when `new/1` runs, then `active == 2`. Given no `start_seat`, then `active` is derived from the seed and the same seed always gives the same start seat.
10. **§1** Given 5 players, then the total starting chips is 55 (the whole supply), and `Rules.starting_chips/1` never asks for more than 55 at any count.

## B. Pass ("No thanks!")

11. **§3.1** Given the active seat has 11 chips and the pot is 0, when it passes, then it has 10 chips, the pot is 1 and the offer is unchanged.
12. **§3.1** Given seat 0 is active in a 4-player game, when it passes, then seat 1 is active.
13. **§3.1** Given the last seat (n−1) is active, when it passes, then seat 0 is active (wrap-around).
14. **§3.1, §3.4** Given every seat passes once on the same card, then the pot equals n, the turn is back at the first seat, and the offer and pile are unchanged.
15. **§3.4** Given an offer passed round the table 3 times, then the pot is 3n. There is no limit on pot size or laps.
16. **§3.2** Given the active seat has 0 chips, when it sends `:pass`, then it gets `{:error, :no_chips}` and the game is unchanged.
17. **§3.2** Given the active seat has 0 chips, then `legal_actions(game, seat) == [:take]`.
18. **§3.1** Given the active seat has ≥1 chip, then `legal_actions` is `[:take, :pass]`.

## C. Take

19. **§3.1** Given the offer is 17 with a pot of 4 and the active seat has 6 chips, when it takes, then its cards include 17, it has 10 chips and the pot is 0.
20. **§3.1, §7.3** Given a pot of 0, when the active seat takes, then its chip count does not change.
21. **§3.3** Given seat 2 takes and the pile is not empty, then the new offer is the old head of the pile, the pile shrinks by 1, the pot is 0 and **seat 2 is still active**.
22. **§3.3** Given seat 2 just took, when it takes again at once, then that is legal and it gets the second card too (back-to-back takes).
23. **§3.4** Given a card just flipped, when the active seat takes before anyone passes, then that is legal.
24. **§5, §7.7** Given cards are taken in the order 9, 7, 8, then `Player.cards` is stored sorted `[7, 8, 9]`.

## D. Turn order and illegal moves

25. **§3.1** Given seat 1 is active, when seat 3 sends `:take` or `:pass`, then it gets `{:error, :not_your_turn}` and the state is unchanged.
26. **§3.1** Given an unknown action (`:bid`, `{:pass, 2}`), when applied, then it gets `{:error, :invalid_action}`.
27. **§3.4** There is no action to pay more than 1 chip, give chips away or trade. Every pass removes exactly 1 chip.
28. **§4** Given `phase == :over`, when any seat sends any action, then it gets `{:error, :game_over}`.

## E. End of game

29. **§4** Given the pile is empty and the offer is the last card, when the active seat passes, then the game is **not** over (a pass never ends it).
30. **§4** Given the pile is empty and the offer is the last card, when the active seat takes, then `phase == :over`, `offer == nil`, the pot is 0, and the log ends with `{:game_over, scores}`.
31. **§4** Given any finished game, then the seats' card counts add up to 24, and taken cards ∪ removed = 3..35.
32. **§4** Given a new game, then the game ends after exactly 24 takes (count the `:take` log entries).
33. **§4** Given `phase == :over`, then `legal_actions(game, seat) == []` for every seat.

## F. Scoring

34. **§5** Given cards `[3]` and 11 chips, then the score is −8.
35. **§5** Given cards `[27, 28, 29, 30]` and 2 chips, then the score is 25 (only the lowest card of a run counts).
36. **§5** Given cards `[5, 7, 8, 9, 20]` and 4 chips, then the runs are `[[5], [7, 8, 9], [20]]` and the score is 28.
37. **§5, §7.6** Given cards `[33, 35]` and 0 chips, then the runs are `[[33], [35]]` and the score is 68 (a gap breaks the run).
38. **§5** Given no cards and 15 chips, then the score is −15 (a negative score is allowed).
39. **§5** Given cards `[3..35 minus the removed]` in one hand, then the runs follow the gaps the removed cards leave. Property: `card_points(cards) == Σ (c for c in cards where c-1 ∉ cards)`.
40. **§5** Property: adding a card c to a set S changes card points by: +c if neither c−1 nor c+1 is in S; 0 if only c−1 is in S; −1 if only c+1 is in S; −(c+1) if both are in S (two runs merge). Examples: `[10, 12]` + 11 gives 10 (from 22). `[12]` + 11 gives 11. `[10]` + 11 gives 10.
41. **§5** Property: `runs/1` partitions the cards. Concatenated runs equal the sorted cards, and in each run consecutive elements differ by 1.

## G. Ties and winners

42. **§6** Given final scores `%{0 => 20, 1 => 15, 2 => 30}`, then `winners == [1]`.
43. **§6** Given final scores `%{0 => 15, 1 => 15, 2 => 30}`, then `winners == [0, 1]` (shared win, no tiebreak on chips or cards).
44. **§6** Given all seats tie, then every seat is a winner.

## H. Edge cases

45. **§7.2** Given every seat has 0 chips, then each offer is taken by the active seat, so that seat takes every card left. Simulate it to the end and confirm the game ends without errors.
46. **§7.2** Given seats 0 and 1 have 0 chips and seat 2 has some, when seat 0 is active, then it must take, and it stays active on the next card.
47. **§3.2** Given a seat with 0 chips takes a card with a pot of 3, then it has 3 chips and may pass on the next card.
48. **§7.4** Property (random legal play, many seeds): after every action, the chips in hands plus the pot equal the starting total.
49. **§7.5** Property: after every action, `removed + pile + (offer ? 1 : 0) + Σ cards == 33`, with no duplicate values anywhere.
50. **§2.1** Given 7 players (7 chips each), when everyone passes on the first card 7 times, then all seats have 0 chips and the pot is 49. The active seat must take and receives 49 chips.

## I. Information hiding (`view/2`)

51. **§2.2** Given any game state (including `:over`), then `view(game, seat)` for any seat contains none of the removed card values in a removed or pile field. It exposes `pile_count`, never `pile` or `removed`. Check it by searching the serialized view for the `removed` key and the pile list.
52. **§2.2** Given `view/2` before game end, then the next pile card is not shown.
53. **§2.4** Given `chips_visible: false` (default), then `view(game, s)` shows seat s's own chip count and `:hidden` for every other seat.
54. **§2.4, §8.2** Given `chips_visible: true`, then `view/2` shows every seat's chip count.
55. **§2.4, §7.8** Given any setting, then `view/2` always shows the offer, the pot, every seat's taken cards, `active` and `pile_count`.
56. **§2.4** Given `phase == :over` and hidden chips, then `view/2` shows every seat's chip count and score (the reveal at scoring). The removed cards stay hidden (§9 item 3).

## J. Generic engine invariants

57. **Liveness** Property: in any state with `phase == :playing`, `legal_actions(game, game.active)` is not empty (`:take` is always in it), and every other seat's list is `[]`.
58. **Termination** Property: from any seed, applying random legal actions always reaches `:over`. The number of actions is at most 24 + (total chips) passes. Passes are bounded because each one uses up a chip.
59. **Determinism** Given the same `new/1` options (seed, players) and the same action list, then the final states are equal (`==`), including the log.
60. **Replay** Given a finished game's log, when it is replayed from its seed, then it rebuilds the same state at every step.
61. **Purity** Calling `apply/2` twice on the same state with the same action gives equal results. The source has no `Enum.random`, `Enum.shuffle` or `:rand.uniform/1` (credo or grep check, AGENTS.md).
62. **Errors don't mutate** Property: every `{:error, _}` from `apply/2` comes with the input state unchanged (the caller keeps the old state).

## K. House rules (only if implemented)

63. **§8.3** Given `house_rules: [:tactical]` with 3–5 players, then each seat has 10 chips, `removed` contains 10, 20 and 30, and `length(removed) == 9`.
64. **§8.1** Given `house_rules: [:two_player]` and 2 players, then each seat has 11 chips, 9 cards are removed and play follows the normal rules.

---

## Proposed action vocabulary and state shape

Actions (the only two, `apply(game, {seat, action})`):

| Action | Legal when | Effect |
|---|---|---|
| `:take` | `phase == :playing` and `seat == active` | Add the offer to the seat's cards and the pot to its chips. Flip the next card (the same seat stays active) or end the game. |
| `:pass` | as above, and `chips ≥ 1` | Move 1 chip to the pot. `active = rem(active + 1, n)` |

Errors: `:not_your_turn`, `:no_chips`, `:invalid_action`, `:game_over`, `:invalid_player_count`.

```elixir
%NoThanks.Game{
  phase: :playing | :over,
  players: %{seat => %NoThanks.Player{chips: non_neg_integer, cards: [3..35]}},  # cards sorted
  seats: n,                     # 3..7
  active: seat,
  offer: 3..35 | nil,           # nil only when :over
  pot: non_neg_integer,
  pile: [3..35],                # head = next card; never in view/2
  removed: [3..35],             # 9 cards; never in view/2
  rng: :rand.state(),           # :exsss, used only by new/1
  options: %{chips_visible: false, house_rules: [], start_seat: nil},
  log: [event]                  # {:setup, ...}, {:flip, c}, {seat, :pass}, {seat, :take, c, pot}, {:game_over, scores}
}
```

Rules data (`NoThanks.Rules`): `cards/0` (3..35), `removed_count/0` (9), `starting_chips/1` (3..5 → 11, 6 → 9, 7 → 7), `player_counts/0` (3..7). Scoring (`NoThanks.Score`): `runs/1`, `card_points/1`, `score/1`, `winners/1`.
