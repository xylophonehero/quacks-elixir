# Hearts — test plan

Every rule in `rulebook.md` has at least one test here, tagged with its §. Tests are written against the pure engine (`Hearts.new/1`, `Hearts.apply/2`, `Hearts.legal_cards/2`, `Hearts.view/2`), never against the LiveView.

Conventions:
- Cards in tests use a helper `c("QS")`, `c("10H")`, `c("2C")` → `{12, :spades}`, `{10, :hearts}`, `{2, :clubs}`. Hands are written `N: …` for seats 0..3.
- "Given a rigged game" means a fixture builder `Hearts.Fixture.new(hands: %{0 => [...], ...}, round: r, leader: s, ...)` that builds a valid mid-game state without dealing. Rigged games are only for tests; `Hearts.new/1` always shuffles from the seed.
- `apply/2` returns `{:ok, game}` or `{:error, reason}`; error atoms are proposals.
- Default options unless a test says otherwise: 4 players, `moon: :add_to_others`, `target: 100`.

---

## A. Setup and deal (§1, §2)

| # | § | Given | When | Then |
|---|---|---|---|---|
| T1 | §1 | — | `Hearts.new(seed: 1)` | 4 hands of 13 cards; all 52 cards distinct; union = full deck |
| T2 | §2 | the same seed twice | `new/1` | identical hands, dealer and pass direction |
| T3 | §2 | two different seeds | `new/1` | hands differ (sanity check, fixed seeds) |
| T4 | §2 | a new game | — | `round == 1`, all `scores == 0`, `hearts_broken? == false`, `taken` empty, phase `:passing` |
| T5 | §2 | round 1 dealer is seat d | round 1 ends | round 2 dealer is `d + 1 mod 4` |
| T6 | §2 | any game | after each deal and each exchange | `view(game, s).hand` is sorted by suit (♣ ♦ ♠ ♥) then rank; the engine never relies on hand order |

## B. Passing (§4)

| # | § | Given | When | Then |
|---|---|---|---|---|
| T7 | §4 | round 1 | — | `pass_direction == :left`; phase `:passing` |
| T8 | §4 | round 2 / 3 / 4 / 5 | — | `:right` / `:across` / `:hold` / `:left` |
| T9 | §4 | round 1, seat 0 passes A♠ K♠ Q♠, others pass anything | all four have passed | seat 1 holds A♠ K♠ Q♠; seat 0 no longer does; every hand still has 13 cards |
| T10 | §4 | round 2 | all pass | seat 0's cards go to seat 3 |
| T11 | §4 | round 3 | all pass | seat 0's cards go to seat 2, seat 1's to seat 3 |
| T12 | §4.4 | round 4 | game enters round 4 | no `:passing` phase; phase `:playing`; `{:pass, _}` → `{:error, :not_passing}` |
| T13 | §4 | phase `:passing` | seat 0 `{:pass, [2 cards]}` | `{:error, :must_pass_three}`; same for 4 cards |
| T14 | §4 | phase `:passing` | `{:pass, [c, c, x]}` (duplicate) | `{:error, :must_pass_three}` |
| T15 | §4 | phase `:passing` | seat 0 passes a card not in its hand | `{:error, :card_not_in_hand}` |
| T16 | §4.1 | seat 0 has passed | seat 0 passes again | `{:error, :already_passed}` |
| T17 | §4.1 | seats 0–2 have passed, seat 3 has not | — | no hand has changed yet; phase still `:passing`; `waiting_for == [3]` |
| T18 | §4.1 | seat 3 passes last | — | exchange happens in one step; phase `:playing`; turn = holder of 2♣ after the exchange |
| T19 | §4.3 | seat 0 holds 2♣ and passes it left in round 1 | exchange | seat 1 leads the first trick |
| T20 | §4.3 | a seat passes Q♠ and two hearts | — | allowed |
| T21 | §4 | phase `:passing` | any `{:play, _}` | `{:error, :not_playing}` |

## C. First trick (§5, §6, §7)

| # | § | Given | When | Then |
|---|---|---|---|---|
| T22 | §5.1 | seat 2 holds 2♣, phase `:playing`, trick 1 | — | `turn == 2`; `legal_cards(game, 2) == [2♣]` |
| T23 | §5.2 | seat 2 to lead trick 1 | `{:play, 3♣}` | `{:error, :must_lead_two_of_clubs}` |
| T24 | §5 | seat 2 to lead | seat 0 `{:play, _}` | `{:error, :not_your_turn}` |
| T25 | §6.1 | 2♣ led; seat 3 holds 5♣ 9♣ and hearts | — | legal = [5♣, 9♣] |
| T26 | §6.1 | 2♣ led; seat 3 holds clubs | `{:play, 4♦}` | `{:error, :must_follow_suit}` |
| T27 | §7.1 | 2♣ led; seat 3 has no clubs, holds 4♦, 7♠, Q♠, A♥ | — | legal = [4♦, 7♠]; Q♠ → `{:error, :no_points_on_first_trick}`; A♥ → same |
| T28 | §7.1 | 2♣ led; seat 3 void in clubs, holds only spades incl. Q♠ and hearts | — | legal = spades other than Q♠ |
| T29 | §7.2 | 2♣ led; seat 3 holds no clubs, no diamonds, no spades except Q♠, rest hearts | — | legal = Q♠ and every heart |
| T30 | §7.2 | 2♣ led; seat 3 holds 13 hearts (rigged; 2♣ elsewhere) | seat 3 plays 5♥ | `{:ok, _}`; `hearts_broken? == true` (§7.2b) |
| T31 | §7.2a | as T29 with `first_trick_exception: :hearts_only` | — | legal = hearts only (Q♠ not legal) |
| T32 | §7.3 | 2♣ led; seat 1 holds clubs and Q♠ | — | Q♠ not legal (must follow) |
| T33 | §7 | trick 2, seat void in led suit holds Q♠ | — | Q♠ is legal (rule applies only to trick 1) |
| T34 | §7 | `first_trick_points: true`, 2♣ led, seat void in clubs | — | hearts and Q♠ are legal |

## D. Leading and breaking hearts (§8)

| # | § | Given | When | Then |
|---|---|---|---|---|
| T35 | §8.1 | trick 2, seat 0 won trick 1 | — | `turn == 0` |
| T36 | §8.1 | hearts not broken; leader holds 3♥ and 5♦ | leader plays 3♥ | `{:error, :hearts_not_broken}`; legal excludes hearts |
| T37 | §8.2 | trick 3: diamond led, seat 2 void discards 4♥ | trick ends; trick 4 | `hearts_broken? == true`; leader may lead a heart |
| T38 | §8.2 | hearts broken mid-trick by a discard | — | flag set immediately (no one can lead in the same trick anyway; check flag after the card) |
| T39 | §8.3 | hearts not broken; leader holds only hearts | leader plays 7♥ | `{:ok, _}`; `hearts_broken? == true` |
| T40 | §8.4 | hearts not broken; leader holds Q♠ and hearts only | — | legal = [Q♠] |
| T41 | §8.4 | trick 2, hearts not broken | seat leads Q♠ | `{:ok, _}`; `hearts_broken? == false` |
| T42 | §8.4 | trick 4, seat void in led suit discards Q♠, no heart played yet | trick 5 lead | hearts still not broken |
| T43 | §8.4 | as T42 with `queen_breaks_hearts: true` | — | `hearts_broken? == true` |
| T44 | §8.2 | round 1 ended with hearts broken | round 2 starts | `hearts_broken? == false` |
| T45 | §8.1 | hearts broken; leader holds hearts and clubs | — | legal = every card in hand |

## E. Following and winning tricks (§6, §9)

| # | § | Given | When | Then |
|---|---|---|---|---|
| T46 | §6.1 | 7♦ led; seat holds 2♦ and K♦ | — | legal = [2♦, K♦] (no need to beat) |
| T47 | §6.2 | trick 3, 7♦ led; seat void in diamonds | — | legal = whole hand |
| T48 | §9.1 | trick: 7♦ (lead), K♦, A♠, 2♦ | 4th card played | winner = seat that played K♦ (A♠ is off-suit) |
| T49 | §9.1 | trick: 2♣ (lead), A♥, A♦, A♠ (rigged, `first_trick_points: true`) | — | winner = leader (only club) |
| T50 | §9.1 | trick with 10♣ lead, J♣, 9♣, A♣ | — | A♣ wins (rank 14 > 11 > 10 > 9) |
| T51 | §9.2 | seat 2 wins a trick containing 4♥ and Q♠ | — | `taken[2]` contains both; seat 2 leads next; `trick == []` |
| T52 | §9 | full trick played | — | log has `{:trick_won, seat, cards}`; turn order next trick starts at winner and goes clockwise |
| T53 | §9 | 13 tricks played | — | all hands empty; phase moves to scoring and the next round (or `:game_over`) |
| T54 | §9 | trick in progress | seat plays card not in hand | `{:error, :card_not_in_hand}` |

## F. Scoring a round (§10)

| # | § | Given | When | Then |
|---|---|---|---|---|
| T55 | §10 | taken at round end: seat 0 = 5 hearts; seat 1 = Q♠ + 2 hearts; seat 2 = 6 hearts; seat 3 = none | round scored | round points 5, 15, 6, 0; scores add up; total 26 |
| T56 | §10 | seat takes tricks with only clubs/diamonds/spades ≠ Q♠ | — | 0 points |
| T57 | §10 | any finished round without a moon | — | sum of round points == 26 |
| T58 | §10 | scores 10/20/30/40 before the round | round gives 5/15/6/0 | scores 15/35/36/40 |
| T59 | §10 | round scored, no one ≥ target | — | `round` +1; new deal; dealer moves left; pass direction follows round number |

## G. Shooting the moon (§11)

| # | § | Given | When | Then |
|---|---|---|---|---|
| T60 | §11 | seat 1 took all 13 hearts and Q♠; scores 0/0/0/0 | round scored (default `:add_to_others`) | scores 26/0/26/26; log `{:moon, 1}` |
| T61 | §11.1 | seat 1 took all penalty cards in only 9 of 13 tricks | — | still a moon |
| T62 | §11 | seat 1 took 13 hearts, seat 2 took Q♠ | — | no moon: 13 and 13 |
| T63 | §11 | seat 1 took 12 hearts + Q♠ | — | no moon: 25 for seat 1, 1 for the other |
| T64 | §11 | `moon: :subtract_from_shooter`, scores 30/30/30/30 | seat 1 shoots | scores 30/4/30/30 |
| T65 | §11 | `moon: :subtract_from_shooter`, shooter at 10 | shoots | score −16 (negatives allowed) |
| T66 | §11 | `moon: :shooter_choice`, seat 1 shoots | last trick taken | phase `:moon_choice`, `turn == 1`; `{:moon, :subtract}` → others unchanged, seat 1 −26; `{:moon, :add}` → others +26 |
| T67 | §11 | `moon: :shooter_choice`, phase `:moon_choice` | seat 0 sends `{:moon, :add}` | `{:error, :not_your_turn}` |
| T68 | §11.2 | `moon: :auto_best`; scores 90/50/60/95; seat 1 shoots | — | adding would leave seat 1 lowest → others +26, game ends, seat 1 wins |
| T69 | §11.2 | `moon: :auto_best`; scores 10/80/20/30; seat 1 shoots | — | adding would not make seat 1 lowest → seat 1 −26 = 54, others unchanged |
| T70 | §11, §12 | default moon; scores 80/40/85/90; seat 1 shoots | — | 106/40/111/116; game over; seat 1 wins |

## H. End of game and ties (§12)

| # | § | Given | When | Then |
|---|---|---|---|---|
| T71 | §12.1 | scores 95/50/60/70; seat 0 takes 5 | round scored | 100 → `:game_over` (exactly 100 ends) |
| T72 | §12.1 | scores 95/50/60/70; seat 0 takes 4 | round scored | 99 → next round dealt |
| T73 | §12.1 | a seat passes 100 during trick 7 (would be 103 if scored now) | — | game continues to trick 13; nothing ends mid-round |
| T74 | §12.2 | final 104/41/77/62 | game over | `winners == [1]` |
| T75 | §12.3 | final 104/50/50/90 | game over | `winners == [1, 2]` (shared win) |
| T76 | §12.3 | `tie_break: :play_on`, final 104/50/50/90 | round scored | next round dealt; game ends after the first round with one lowest seat |
| T77 | §12.1 | two seats reach ≥ 100 in the same round | — | game over; lowest wins |
| T78 | §12.5 | `target: 50`; seat reaches 52 | round scored | game over |
| T79 | §12 | phase `:game_over` | any action | `{:error, :game_over}` |
| T80 | §14 | `exact_target_reset: 50`; seat ends round on exactly 100 | — | that seat → 50; game continues unless another seat ≥ 100 |

## I. House rules and other player counts (§14)

| # | § | Given | When | Then |
|---|---|---|---|---|
| T81 | §14 `omnibus` | seat 2 takes J♦ and 3 hearts | round scored | seat 2: 3 − 10 = −7; round total 16 |
| T82 | §14 `omnibus` | moon by seat 1, J♦ taken by seat 3 | default | seat 1 0, others 26, seat 3 26 − 10 = 16 |
| T83 | §14 `spot_hearts` | seat takes A♥ and 2♥ | — | 14 + 2 = 16 points |
| T84 | §14 `black_maria` | seat takes K♠, A♠, Q♠ | — | 10 + 7 + 13 = 30; total per round 43 |
| T85 | §14 `black_maria` | trick 1; seat void in led suit | — | hearts and Q♠ are legal; hearts may be led on trick 2 without breaking |
| T86 | §14.1 | `players: 3` | `new/1` | 3 hands of 17; 2♦ absent; 2♣ present |
| T87 | §14.1 | `players: 3` | rounds 1..3 | pass `:left`, `:right`, `:hold`; never `:across` |
| T88 | §14.2 | `players: 5` | `new/1` | 5 hands of 10; 2♦ and 2♣ absent |
| T89 | §14.2 | `players: 5` | trick 1 | holder of 3♣ leads; legal = [3♣] |
| T90 | §14.1/2 | 3 and 5 players | moon | still all hearts + Q♠ (26) |
| T91 | §14 | `pass_cycle: [:left]` | rounds 1–5 | always `:left` |
| T92 | §14 | unknown option key or value | `new/1` | `{:error, {:bad_option, key}}` |

## J. Generic invariants (property tests)

Run with StreamData over random seeds and random legal-move policies (pick a random legal action using a separate test RNG).

| # | Invariant |
|---|---|
| T93 | **Always a legal action until over.** In every reachable state with phase ≠ `:game_over`, the seat(s) in `waiting_for` have at least one legal action (`legal_actions(game, seat) != []`), and `apply/2` with any of them returns `{:ok, _}`. |
| T94 | **Every legal action is accepted, every other is refused.** For a sample of states, `{:play, c}` returns `{:ok, _}` iff `c in legal_cards(game, seat)`. |
| T95 | **Card conservation.** At every step, hands ∪ current trick ∪ taken piles (∪ pending passes) == the deck in play, no duplicates. |
| T96 | **Points conservation.** Each non-moon round adds exactly 26 (or 16 with `omnibus`, 43 with `black_maria`) to the sum of scores. |
| T97 | **Termination.** A random game reaches `:game_over` in a bounded number of rounds (e.g. < 50 with target 100). |
| T98 | **Deterministic replay from seed.** `new(seed: s)` + the same action list gives a byte-identical game (`==`) and the same log; replaying the log's actions from `new(seed: s)` reproduces the final state. |
| T99 | **No global RNG.** Running a game does not change `:rand.export_seed()` of the calling process; grep-style test: engine modules do not call `Enum.random`, `Enum.shuffle` or `:rand.uniform/1`. |
| T100 | **View hides other hands.** For every state and seat s, `view(game, s)` contains s's hand and, for other seats, only their card **counts**. No card from another seat's hand appears anywhere in the view (check by collecting all cards in the view and subtracting public ones: current trick, taken piles, s's own hand). |
| T101 | **View hides passes before they are received.** During `:passing`, `view(game, s)` contains s's own chosen pass (if made) but not any other seat's chosen cards, and not the cards incoming to s; after the exchange, s's view shows its hand including the received cards and (optionally) which 3 cards it received, but never what other seats passed to each other. |
| T102 | **View is enough to act.** `legal_cards` computed from `view(game, s)` (via a pure helper) equals `legal_cards(game, s)`. Bots use only views. |
| T103 | **Turn order.** In `:playing`, the 4 cards of each trick come from 4 distinct seats in clockwise order from the leader. |
| T104 | **Log is public-safe.** The public log never contains `{:pass, seat, cards}` with cards; it holds `{:passed, seat}` and the trick plays only. |

---

## K. Proposed action vocabulary

| Action | Phase | Who | Notes |
|---|---|---|---|
| `{:pass, [c1, c2, c3]}` | `:passing` | any seat in `waiting_for` | Exactly 3 distinct cards from own hand (`pass_count`). Simultaneous: seats may act in any order. |
| `{:play, card}` | `:playing` | `turn` seat | Must be in `legal_cards/2`. The 13th trick's last card triggers scoring and the next deal (or game over) inside the same `apply/2`. |
| `{:moon, :add \| :subtract}` | `:moon_choice` | shooter | Only with `moon: :shooter_choice`. |

`apply/2` takes `{seat, action}` so the engine checks the actor: `Hearts.apply(game, {seat, {:play, card}})`. No `:deal` or `:next_round` actions: the engine deals the next round itself; any pause between rounds is a UI concern.

## L. Proposed state shape

```elixir
%Hearts.Game{
  options: %{players: 4, target: 100, moon: :add_to_others, queen_breaks_hearts: false,
             omnibus: false, first_trick_points: false, pass_cycle: [:left, :right, :across, :hold],
             pass_count: 3, tie_break: :shared},
  rng: :rand.state(),             # advanced only with the _s API
  seed: term(),
  phase: :passing | :playing | :moon_choice | :game_over,
  round: pos_integer(),            # 1-based
  dealer: seat,
  pass_direction: :left | :right | :across | :hold,
  hands: %{seat => [card]},
  pending_passes: %{seat => [card]},   # hidden; cleared on exchange
  received: %{seat => [card]},         # last exchange, shown to the receiver only
  trick_no: 1..13,
  leader: seat,
  turn: seat | nil,
  trick: [{seat, card}],          # in play order
  hearts_broken?: boolean(),
  taken: %{seat => [card]},       # penalty-relevant cards per seat this round (or all taken cards)
  round_points: %{seat => integer()},  # last scored round, for the score sheet
  scores: %{seat => integer()},
  history: [%{round: n, points: %{seat => integer()}, moon: seat | nil}],
  winners: [seat],                # set in :game_over
  log: [event]
}
```

Cards: `{rank, suit}` with `rank in 2..14` and `suit in [:clubs, :diamonds, :spades, :hearts]` (shared `Table.Kit.PlayingCards` representation, see `docs/games/card-family.md`). Seats: `0..players-1`.

Public functions: `new/1`, `apply/2`, `legal_cards/2`, `legal_actions/2`, `waiting_for/1`, `view/2`, `over?/1`, `winners/1`.
