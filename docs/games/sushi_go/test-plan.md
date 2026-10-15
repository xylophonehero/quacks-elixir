# Sushi Go! — test plan

Each case is Given / When / Then and tags the rulebook section it checks (§ = `docs/games/sushi_go/rulebook.md`). Terms: `docs/games/sushi_go/CONTEXT.md`. ⚠️ marks a case that pins down a proposed ruling (rulebook §12); change the test if the ruling changes.

Notation: a tableau is written as a multiset, e.g. `[tempura×3, maki2, {wasabi, squid}]`. "Pick i" means hand index `i` (0-based). Tests that need a specific hand build the game with a helper (`SushiGo.Game.new(players: n, seed: s) |> put_hands(...)`) rather than hunting for seeds; scoring tests call `SushiGo.Scoring` directly on tableaux.

## A. Setup and deck (§1, §2)

1. **Deck composition** §1 — Given `SushiGo.Rules.Deck.counts/0`, Then it is tempura 14, sashimi 14, dumpling 14, maki1 6, maki2 12, maki3 8, salmon 10, squid 5, egg 5, wasabi 6, chopsticks 4, pudding 10, and the sum is 108.
2. **Maki icon total** §1 — Given the full deck, Then the maki icons sum to 54.
3. **Hand size 2p** §2 — Given `new(players: 2)`, Then each hand has 10 cards and the deck has 88.
4. **Hand size 3p** §2 — Given 3 players, Then 9 each, deck 81.
5. **Hand size 4p** §2 — Given 4 players, Then 8 each, deck 76.
6. **Hand size 5p** §2 — Given 5 players, Then 7 each, deck 73.
7. **Player count bounds** §2 — When `new(players: 1)` or `new(players: 6)`, Then `{:error, :bad_player_count}` (or raises ArgumentError; pick one and test it).
8. **Conservation at start** §1 — Given any new game, Then hands + deck as a multiset equal the 108-card deck.
9. **Initial state** §2 — Given a new game, Then round 1, turn 1, phase `:picking`, all picks `nil`, tableaux empty, puddings 0, round_scores empty.
10. **Seeded shuffle** §11 — Given the same seed twice, Then identical hands and deck; Given two different seeds, Then (for a fixed pair of seeds) different hands.

## B. Picking, reveal and passing (§3)

11. **Pick hides card until all pick** §3 — Given 3p turn 1, When seat 0 picks index 2, Then seat 0's hand is unchanged until the reveal, `picks[0]` is set, tableaux are still empty, phase `:picking`.
12. **Double pick rejected** §3 — Given seat 0 already picked this turn, When seat 0 picks again, Then `{:error, :already_picked}` ⚠️ (§12 Q6).
13. **Bad index** §3 — When a seat picks index = hand size, or -1, Then `{:error, :bad_index}`.
14. **Unknown seat** — When seat 7 acts in a 3p game, Then `{:error, :bad_seat}`.
15. **Reveal on last pick** §3 — Given 3p, seats 0 and 2 picked, When seat 1 picks, Then all three picked cards are in their tableaux at once, picks reset to `nil`, turn 2, and the log has one `{:reveal, %{0 => [_], 1 => [_], 2 => [_]}}`.
16. **Pick order irrelevant** §3 — Given the same hands, When the seats pick the same cards in orders 0,1,2 and 2,0,1, Then the resulting games are equal (except log order of the pick entries, if logged).
17. **Pass left** §3 — Given 3p with hands H0, H1, H2 and picks c0, c1, c2, When the reveal happens, Then seat 1 holds H0−c0, seat 2 holds H1−c1, seat 0 holds H2−c2.
18. **Pass in 2p** §3 — Given 2p, Then after a turn the two remaining hands are swapped.
19. **Equal hand sizes** §3 — Given any game, after every reveal all hands have the same size = hand size − turn + 1.
20. **Last turn** §3 — Given 4p turn 8 (one card each), When all pick index 0, Then hands are empty, no pass happens, and round scoring runs (round becomes 2 or phase `:over`).
21. **Turn count** §3 — Given 5p, Then a round takes exactly 7 reveals (no chopsticks) or still 7 reveals with chopsticks used.

## C. Chopsticks (§4)

22. **Use chopsticks** §4 — Given seat 0 tableau `[chopsticks]` and hand `[squid, tempura, egg]`, When seat 0 plays `{:pick, 0, :chopsticks, 1}` and the others pick, Then seat 0's tableau gains squid and tempura, loses the chopsticks, and the hand passed to seat 1 is `[egg, chopsticks]`.
23. **Hand sizes stay equal** §4 — Given the case above in 3p, Then after the pass every hand has hand size − turn cards (all equal).
24. **Not on pick turn** §4 — Given seat 0 has no chopsticks in tableau and picks chopsticks this turn, Then the chopsticks action is not legal this turn; When it tries `{:pick, i, :chopsticks, j}`, Then `{:error, :no_chopsticks}`.
25. **Usable next turn** §4 — Given seat 0 picked chopsticks in turn 1, Then in turn 2 `legal_actions(game, 0)` includes chopsticks pairs.
26. **One per turn** §4 — Given tableau `[chopsticks, chopsticks]`, Then no action takes 3 cards; using chopsticks removes exactly one; the other is usable next turn.
27. **Two in a row** §4 — Given tableau `[chopsticks, chopsticks]` and hand ≥2 on turns t and t+1, When seat uses chopsticks both turns, Then both succeed and the tableau ends with 0 chopsticks.
28. **Last-turn block** §4 — Given hand of 1 card and chopsticks in tableau, Then no chopsticks action is legal; trying it gives `{:error, :bad_index}` or `{:error, :hand_too_small}`.
29. **Same index twice** §4 — When `{:pick, 1, :chopsticks, 1}`, Then `{:error, :bad_index}`.
30. **Hand of exactly 2** §4 — Given hand `[maki3, pudding]` and chopsticks in tableau, When taking both, Then the passed hand is `[chopsticks]` and the next seat must take it as its last card.
31. **Chopsticks taken with chopsticks** §4 ⚠️ — Given tableau `[chopsticks]` and hand `[chopsticks, egg, …]`, When taking both, Then the tableau ends with one chopsticks (the new one) usable next turn, and one chopsticks goes into the passed hand.
32. **Unused chopsticks** §4, §6.6 — Given tableau `[chopsticks, chopsticks]` at round end, Then they score 0 and are discarded.
33. **Chopsticks pick is secret** §4, §11 — Given seat 0 submitted a chopsticks pick, Then `view(game, 1)` shows seat 0 as picked but not the cards nor that chopsticks were used.

## D. Wasabi and nigiri (§5, §6.5)

34. **Dip** §5 — Given tableau `[wasabi]`, When seat picks salmon, Then the tableau has `{wasabi, salmon}` and nigiri score 6.
35. **Triple values** §6.5 — Given tableaux `[{wasabi, egg}]`, `[{wasabi, salmon}]`, `[{wasabi, squid}]`, Then nigiri scores 3, 6, 9.
36. **Plain nigiri** §6.5 — Given `[egg, salmon, squid]` with no wasabi, Then 1+2+3 = 6.
37. **Dip is mandatory** §5 — Given tableau `[wasabi]`, When a squid is revealed, Then it is always on the wasabi (no action exists to keep it plain).
38. **One nigiri per wasabi** §5 — Given `[wasabi]`, When the seat reveals squid then (next turn) salmon, Then `[{wasabi, squid}, salmon]` = 9 + 2 = 11.
39. **Two wasabi** §5 — Given `[wasabi, wasabi]`, When egg then squid arrive, Then both dipped: 3 + 9 = 12.
40. **Wasabi after nigiri** §5 — Given `[squid]`, When wasabi is picked next, Then squid stays plain (3) and wasabi is empty (0); total 3.
41. **Empty wasabi** §5, §6.6 — Given `[wasabi]` at round end, Then 0 points.
42. **Wasabi + nigiri with chopsticks, ordered** §5 ⚠️ — Given tableau `[chopsticks]`, house rule `:ordered`, hand `[wasabi, squid, …]`, When `{:pick, 0, :chopsticks, 1}`, Then tableau has `{wasabi, squid}` (9).
43. **Reverse order** §5 ⚠️ — Same, When `{:pick, 1, :chopsticks, 0}` (squid first), Then squid plain (3) and wasabi empty.
44. **Strict house rule** §5 ⚠️ — Given `chopsticks_wasabi: :strict`, When wasabi first, squid second, Then squid is plain (3) and wasabi stays empty.
45. **Two nigiri onto existing wasabi with chopsticks** §5 — Given `[wasabi, chopsticks]`, When picking salmon and egg with chopsticks (salmon first), Then `{wasabi, salmon}` + egg = 6 + 1 = 7.

## E. Set cards (§6.2–§6.4)

46. **Tempura** §6.2 — For n = 0..5 tempura, Then scores 0, 0, 5, 5, 10, 10.
47. **Sashimi** §6.3 — For n = 0..7 sashimi, Then 0, 0, 0, 10, 10, 10, 20, 20.
48. **Dumplings** §6.4 — For n = 0..7 dumplings, Then 0, 1, 3, 6, 10, 15, 15, 15.
49. **Mixed tableau worked example** §6 — Given a 2p round end (10 cards each): seat 0 `[tempura×2, sashimi×3, dumpling×2, {wasabi, salmon}, maki3]`; seat 1 `[maki2, maki1, squid, egg, pudding, chopsticks, wasabi (picked after the nigiri, empty), tempura, dumpling, sashimi]`. Then maki icons 3 vs 3 → tie for most → 3 each, no second. Seat 0 = 5 (tempura) + 10 (sashimi) + 3 (dumplings) + 6 (salmon on wasabi) + 3 (maki) = **27**. Seat 1 = 0 + 0 + 1 + (3 + 1) + 0 + 3 = **8**; its pudding goes to `puddings[1]` and scores nothing now.

## F. Maki majority (§6.1)

50. **Simple 3p** §6.1 — Given icons A 7, B 4, C 2, Then A 6, B 3, C 0.
51. **Tie for first, 2 players** §6.1 — Given 2p icons 5 and 5, Then 3 each, no second.
52. **Tie for first, 3 players** §6.1 — Given A 6, B 6, C 3, Then A 3, B 3, C 0 (no second place).
53. **Three-way first** §6.1 — Given 3p all 4, Then 2 each.
54. **Four-way first** §6.1 — Given 4p all 2 icons, Then 1 each (6/4 remainder ignored).
55. **Five-way first** §6.1 — Given 5p all 3 icons, Then 1 each.
56. **Tie for second, 2-way** §6.1 — Given A 8, B 3, C 3, Then A 6, B 1, C 1.
57. **Tie for second, 3-way** §6.1 — Given 4p A 9, B 2, C 2, D 2, Then A 6, B/C/D 1.
58. **Tie for second, 4-way** §6.1 — Given 5p A 9, others 1 each, Then A 6, others 0.
59. **2p second place** §6.1 — Given 2p icons 6 and 1, Then 6 and 3.
60. **Zero icons get no second** §6.1 ⚠️ — Given 2p icons 4 and 0, Then 6 and 0. Given 3p A 5, B 0, C 0, Then A 6, B 0, C 0.
61. **Nobody has maki** §6.1 — Given 4p all 0 icons, Then all 0 (no split of 6 among zeros).
62. **Icons not cards** §6.1 — Given A `[maki3]` (1 card, 3 icons) and B `[maki1, maki1]` (2 cards, 2 icons), Then A 6, B 3.

## G. Round and game end (§7, §8, §9)

63. **Round end discard** §7 — Given end of round 1, Then tableaux are empty, puddings counted into `puddings[seat]`, all non-pudding tableau cards gone from play (not in deck, hands or tableaux).
64. **Puddings persist** §7 — Given seat 0 took 2 puddings in round 1 and 1 in round 2, Then `puddings[0] == 3` at start of round 3.
65. **Pudding not scored per round** §6.7 — Given a tableau of only puddings, Then round score 0.
66. **Deal round 2** §7 — Given 4p end of round 1, Then each seat has 8 new cards, deck 76 − 32 = 44, round 2 turn 1.
67. **Deck suffices 5p** §2 — Given a full 5p game, Then each of the 3 deals succeeds and 3 cards remain in the deck at the end.
68. **Round scores recorded** §7 — Given end of round 2, Then `round_scores[seat]` has 2 entries and the log has `{:round_score, 2, seat, breakdown}` for each seat.
69. **Game ends after round 3** §8 — Given the last reveal of round 3, Then phase `:over`, pudding scored, winners set, `legal_actions` empty for all seats.
70. **No actions after over** §8 — When any seat acts after `:over`, Then `{:error, :game_over}`.
71. **Pudding 3p simple** §8 — Given puddings A 4, B 2, C 1, Then A +6, B 0, C −6.
72. **Pudding tie most** §8 — Given 4p A 3, B 3, C 1, D 0, Then A +3, B +3, C 0, D −6.
73. **Pudding tie fewest** §8 — Given 3p A 2, B 0, C 0, Then A +6, B −3, C −3.
74. **Pudding 3-way fewest** §8 — Given 4p A 5, B 1, C 1, D 1, Then A +6, others −2.
75. **Pudding 4-way fewest** §8 — Given 5p A 3, others 0, Then A +6, others −1 (−6/4 rounds toward zero).
76. **Pudding 3-way most** §8 — Given 4p A 2, B 2, C 2, D 0, Then A/B/C +2, D −6.
77. **Pudding all equal 3p** §8 ⚠️ — Given 3p all 2, Then all 0.
78. **Pudding all zero** §8 ⚠️ — Given 4p all 0, Then all 0.
79. **Pudding 2p** §8 — Given 2p A 3, B 1, Then A +6, B 0 (no −6).
80. **Pudding 2p fewer is zero** §8 — Given 2p A 1, B 0, Then A +6, B 0.
81. **Pudding 2p tie** §8 ⚠️ — Given 2p A 2, B 2, Then both 0 (all-equal rule), not +3 each.
82. **Winner by score** §9 — Given totals A 40, B 38, C 35, Then winners `[A]`.
83. **Tie-break by pudding** §9 — Given totals A 40, B 40 with puddings A 2, B 3, Then winners `[B]`.
84. **Shared win** §9 ⚠️ — Given totals A 40, B 40 and equal puddings, Then winners `[A, B]` (seat order).
85. **Pudding affects winner** §8, §9 — Given 3p before pudding A 41, B 40, C 30 and puddings A 0, B 5, C 1, Then totals A 35, B 46, C 30, winners `[B]`.
86. **Full scripted 2p game** §2–§9 — Given seed `S` and a fixed list of picks (index 0 every turn, both seats), When played to the end, Then the final totals match a golden value recorded once and checked by hand against the scoring rules (regression test).

## H. Invariants (property tests over random seeds, players 2..5, random legal actions)

87. **Always a legal action** — For every reachable state with phase `:picking`, every seat that has not picked has ≥1 legal action; seats that picked have none; at least one seat can act. When `:over`, nobody can act.
88. **Every legal action applies** — For each `a` in `legal_actions(game, seat)`, `apply(game, seat, a)` returns `{:ok, _}`; any action not in the list returns `{:error, _}`.
89. **Termination** — Any sequence of legal actions reaches `:over` after exactly 3 × hand size reveals, i.e. 3 × hand size × players successful `apply` calls (one per seat per turn, chopsticks included).
90. **Card conservation** — At every state, deck + hands + tableaux (wasabi pairs counted as 2) + puddings + discard = the 108-card multiset.
91. **Deterministic replay** — Given seed and action list, replaying from `new/1` gives an identical game (struct equality, including RNG state and log). The log alone plus seed reproduces the game.
92. **Arrival order irrelevant** — Two games with the same seed and the same picks, submitted in different seat orders within each turn, end with equal state (log aside). `game.rng` is unchanged by every `apply` (the only shuffle is in `new/1`).
93. **View hides other hands** — For every state and seats s ≠ t, `view(game, s)` contains t's hand size but not t's cards; changing t's hand (same size) leaves `view(game, s)` unchanged.
94. **View hides unrevealed picks** — For every state in `:picking` where seat t has picked, replacing t's pending pick with another legal one leaves `view(game, s)` (s ≠ t) identical; only the `picked?` flag reveals that t has acted.
95. **View hides deck** — Shuffling `game.deck` differently leaves every `view` unchanged.
96. **Reveal only when all picked** — For every state, tableaux change only on the action that makes the last seat pick; after any other pick, all tableaux and hands are unchanged.
97. **Equal hands** — During `:picking`, all hands have the same size.
98. **Scores non-negative per round** — Every round score ≥ 0; pudding score in −6..6; with 2p pudding score in 0..6.
99. **Maki points conserved** — Per round, total maki points ≤ 9, = 0 if nobody has maki.
100. **Own view is complete** — `view(game, s)` contains s's exact hand and s's own pending pick.

## Proposed action vocabulary

Actions go through `SushiGo.Game.apply(game, seat, action) :: {:ok, game} | {:error, reason}`.

| Action | Meaning |
|---|---|
| `{:pick, i}` | Take hand card `i` this turn. |
| `{:pick, i, :chopsticks, j}` | Use one chopsticks from the tableau: take hand cards `i` then `j` (`i != j`, order matters for wasabi, §5). |

Errors: `:bad_seat`, `:game_over`, `:already_picked`, `:bad_index`, `:no_chopsticks`, `:hand_too_small`.
`legal_actions(game, seat)` lists every `{:pick, i}` (deduplicated by card kind is a UI concern, not the engine's) and, if allowed, every ordered `{:pick, i, :chopsticks, j}`.

## Proposed state shape

```elixir
%SushiGo.Game{
  players: 2..5,
  seed: integer,
  rng: :rand.state(),            # only used by new/1 (shuffle)
  opts: %{chopsticks_wasabi: :ordered | :strict},
  phase: :picking | :over,
  round: 1..3,
  turn: 1..hand_size,
  deck: [card],                  # top first
  discard: [card],
  hands: %{seat => [card]},
  picks: %{seat => nil | {:one, i} | {:two, i, j}},
  tableaux: %{seat => [card | {:wasabi, :egg | :salmon | :squid}]},
  puddings: %{seat => non_neg_integer},
  round_scores: %{seat => [integer]},   # newest first
  pudding_scores: %{seat => integer} | nil,
  winners: [seat],
  log: [term]                    # newest first: {:deal, round}, {:reveal, %{seat => [card]}}, {:round_score, r, seat, map}, {:pudding, map}, {:over, winners}
}
```

`view(game, seat)` returns a plain map: `round`, `turn`, `phase`, `my_hand`, `my_pick`, `picked?: %{seat => boolean}`, `hand_sizes`, `tableaux`, `puddings`, `round_scores`, `pudding_scores`, `winners`, and log entries with no hidden cards (deal entries do not list cards).
