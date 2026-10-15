# Card family — 52-card games from shared parts

Plan for issue #87: a family of standard-deck games built on one shared kit, starting with Hearts (`docs/games/hearts/`). Each game still gets its own rulebook → markdown → tests → engine pass; this page only fixes what they share and the order to build them.

All games here are traditional and in the public domain; rules can be implemented freely (sources: pagat.com for each game, Bicycle / US Playing Card "How to play", Hoyle, Wikipedia). **Card face art must be our own**: no scans or traces of Bicycle, Bee, Copag or other commercial decks, court card designs or the Bicycle back. We draw pips and simple courts ourselves (see §5).

---

## 1. Games

Core list from the issue, plus cheap extras (marked +) that reuse almost everything.

| Game | Players | Family | One-line summary |
|---|---|---|---|
| Hearts | 4 (3, 5) | trick avoidance | Pass 3, avoid hearts and Q♠, moon |
| + Black Maria / Omnibus / Spot Hearts | 3–5 | trick avoidance | Hearts presets (option flags, §14 of the Hearts rulebook) — nearly free |
| Whist | 4, 2 partnerships | trick-taking | Last card dealt sets trumps; score tricks over 6 |
| + Knockout Whist | 2–7 | trick-taking | Hand shrinks each round, losers knocked out; trump picked by previous winner |
| + German Whist | 2 | trick-taking | Two-player whist with a face-up stock; good 2p filler and bot testbed |
| Oh Hell | 3–7 | trick-taking + bidding | Hand size rises/falls, bid exact tricks; "hook" rule for dealer |
| Spades | 4, 2 partnerships | trick-taking + bidding | Spades always trump, team bids, nil, bags |
| Crazy Eights | 2–5 | shedding | Match suit or rank on the discard; 8s wild, draw if you cannot play |
| Go Fish | 2–6 | asking / collecting | Ask a player for a rank; collect books of 4 |
| Gin Rummy | 2 | draw-discard + melds | Form sets and runs, knock with low deadwood, gin bonus |
| + Rummy (basic / Rummy 500) | 2–6 | draw-discard + melds | Reuses Gin's meld detection; melds go on the table |
| + Old Maid | 2–8 | pairing | Remove one Q (51 cards), discard pairs, draw blind from neighbour; reuses Go Fish's "pairs/books" + hidden draw |

Not cheap, left out: Bridge (auction + dummy), Cribbage (board + pegging scoring), Euchre / Pinochle (non-52 decks), Solitaire family (single-player, different UI).

## 2. Shared mechanics × games

✔ = needed, ◐ = small or optional variant, blank = not used.

| Mechanic | Hearts | Whist | Knockout W. | Oh Hell | Spades | Crazy 8s | Go Fish | Gin Rummy | Rummy | Old Maid |
|---|---|---|---|---|---|---|---|---|---|---|
| Seeded shuffle + deal | ✔ all | ✔ all | ✔ n per round | ✔ n per round | ✔ all | ✔ + stock | ✔ + stock | ✔ 10 + stock | ✔ + stock | ✔ all (51) |
| Rotating dealer | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ◐ | ✔ | ✔ | ◐ |
| Card passing | ✔ | | | | ◐ (some house rules) | | | | | ◐ (draw from neighbour) |
| Trick-taking | ✔ | ✔ | ✔ | ✔ | ✔ | | | | | |
| Must follow suit | ✔ | ✔ | ✔ | ✔ | ✔ | | | | | |
| Trumps | | ✔ (turned card) | ✔ (chosen) | ✔ (turned card) | ✔ (fixed ♠) | | | | | |
| Restricted leads ("broken") | ✔ hearts | | | | ✔ spades | | | | | |
| Bidding / contracts | | | | ✔ exact | ✔ team + nil | | | | | |
| Partnerships | | ✔ | | | ✔ | | | | | |
| Draw pile (stock) | | | | | | ✔ | ✔ | ✔ | ✔ | |
| Discard pile, top card matters | | | | | | ✔ | | ✔ | ✔ | |
| Reshuffle discards into stock | | | | | | ✔ | | ◐ (Gin: hand void if stock runs low) | ✔ | |
| Wild card / declared suit | | | | | | ✔ (8 + suit) | | | | |
| Melds (sets & runs) | | | | | | | | ✔ | ✔ | |
| Books / pairs | | | | | | | ✔ books of 4 | | | ✔ pairs |
| Asking another player | | | | | | | ✔ | | | |
| Public info from actions | taken cards | taken cards | taken cards | bids | bids, bags | discards, declared suit | asks + "go fish" (rank knowledge) | discards, picked-up discard | table melds | hand counts |
| Elimination | | | ✔ | | | | | | | ✔ (loser left) |
| Multi-round to a target | ✔ to 100, low wins | ✔ to 5/7 | until 1 left | fixed rounds | ✔ to 500 | ◐ to target | single deal | ✔ to 100 | ✔ to 500 | single deal |
| Simultaneous actions | ✔ pass | | | ◐ (bids can be simultaneous) | | | | | | |

## 3. `Table.Kit.PlayingCards` helpers

A pure module (no processes), shared by all engines. Same rules as the Quacks engine: RNG only through `:rand` `_s` functions, state carried in the game struct.

| Helper | Signature (proposal) | Used by | Notes |
|---|---|---|---|
| Card | `{rank, suit}`, `rank in 2..14`, `suit in [:clubs, :diamonds, :spades, :hearts]` | all | A = 14. Games with ace low (Gin, Rummy runs) map via `rank_value/2`. Jokers out of scope. |
| `deck/1` | `deck(opts \\ [])` → `[card]` | all | `remove: [{2, :diamonds}]` (3p Hearts), `remove: [{12, :clubs}]` (Old Maid). |
| `shuffle/2` | `shuffle(cards, rng) → {cards, rng}` | all | Fisher–Yates with `:rand.uniform_s/2`. Never `Enum.shuffle/1`. |
| `deal/3` | `deal(cards, seats, count \| :all) → {%{seat => [card]}, rest}` | all | One at a time clockwise from `first:` seat; `rest` becomes the stock. `:all` errors if not divisible unless `leftover: :stock`. |
| `sort/2` | `sort(cards, order)` | all (view) | Orders: `:suit_then_rank` (default, alternating colours ♣ ♦ ♠ ♥), `{:trump_last, suit}`, `:rank_then_suit` (Go Fish, Rummy), `:ace_low`. Display only; engines never rely on order. |
| `rank_value/2` | `rank_value(card, :ace_high \| :ace_low)` | Gin, Rummy, Hearts spot | 1..13 or 2..14. |
| `points/2` | `points(card, table)` | Hearts, Gin (deadwood), Crazy 8s, Rummy | `table` is a data map, e.g. Hearts `%{hearts: 1, {12, :spades} => 13}`; Gin face cards 10, A 1. Rules data stays in data modules. |
| `legal_follow/2` | `legal_follow(hand, led_suit \| nil) → [card]` | all trick games | Cards of led suit if any, else whole hand. Game-specific filters (Hearts first trick, broken suits) are applied on top by the game. |
| `trick_winner/2` | `trick_winner([{seat, card}], trump \\ nil) → seat` | all trick games | Highest trump if any trump played, else highest of led suit. Spades/Whist/Oh Hell pass a trump; Hearts passes `nil`. |
| `can_lead?/3` | `can_lead?(hand, card, broken_suits)` | Hearts, Spades | Generic "suit not led until broken unless hand is only that suit". |
| `next_seat/3` | `next_seat(seat, n, direction)` | all | `:left`, `:right`, `:across`, `{:offset, k}`; used for turn order and pass targets. |
| `pass_target/3` | `pass_target(seat, n, direction)` | Hearts | Built on `next_seat/3`. |
| `team/2` | `team(seat, n)` → `seat rem 2` | Whist, Spades | Partners sit opposite. |
| `Pile` | `draw(stock, n, rng)`, `reshuffle_discards/2` | Crazy 8s, Gin, Rummy, Go Fish | Reshuffle keeps the top discard. |
| `matches?/3` | `matches?(card, top, declared_suit)` | Crazy 8s | Same suit, same rank, or wild rank. |
| `books/2` | `books(hand, size) → {[rank], rest}` | Go Fish (4), Old Maid (2) | Groups of the same rank. |
| `melds/1`, `best_melds/2` | `best_melds(hand, opts) → {melds, deadwood}` | Gin, Rummy | Sets (3–4 of a rank) and runs (3+ consecutive, same suit, ace low). `best_melds` minimises deadwood points; with 10–11 cards an exhaustive search is fine. Also `layoffs/2` for Gin knocks. |
| `bid_constraint/3` | `forbidden_bid(bids, tricks, dealer?)` | Oh Hell | Hook rule: the dealer may not make the total equal the tricks. Spades bidding stays in the Spades module. |
| `public/2` | `hide(cards) → count` helpers for `view/2` | all | Make "never leak another seat's cards" a one-liner per game. |
| Notation | `parse("QS")`, `to_string/1`, `to_symbol/1` (`Q♠`) | tests, logs, UI | Tests use `parse`; UI uses symbols. |

Test the kit once (shuffle determinism, deal counts, `trick_winner` with/without trump, `legal_follow` void/not void, meld search incl. ace-low runs and overlapping set/run cards) so each game's tests only cover its own rules.

## 4. Suggested build order

| # | Game | Adds to the kit | Why here |
|---|---|---|---|
| 1 | **Hearts** | card, deck, shuffle, deal, sort, legal_follow, trick_winner (no trump), pass, broken-suit leads, view hiding | Most popular, no trumps and no bidding: the smallest trick-taking core. Simultaneous pass forces the "hidden choices" view work early. Presets (Black Maria, Omnibus, 3p/5p) come almost free. |
| 2 | **Whist** (with Knockout Whist as a mode) | trumps, partnerships, team scoring | One new concept on top of Hearts' trick engine: trumps. Knockout Whist adds variable hand size, needed next. |
| 3 | **Oh Hell** | variable hand size per round, bidding with the hook rule, 3–7 seats | Trumps + bidding without partnerships; exercises the trick UI at 3–7 seats. |
| 4 | **Spades** | team bids, nil, bags, spades-broken (reuses Hearts' breaking) | Everything from 1–3 combined; most popular after Hearts in the US. |
| 5 | **Crazy Eights** | stock, discard pile, reshuffle, wild + declared suit | First non-trick game: the draw/discard UI. Simple rules, good for kids/casual tables. |
| 6 | **Go Fish** (+ Old Maid) | asking another seat, books, public rank knowledge | Very simple engine, but new interaction (target a seat + rank) and a new bot problem (memory of asks). Old Maid is a weekend add-on. |
| 7 | **Gin Rummy** (+ Rummy) | melds, deadwood, knock/layoff, best-meld search | Most rules and the only real algorithm (meld optimisation); 2-player only. Do it last, when the pile UI from Crazy Eights exists. Rummy reuses the meld search. |

German Whist can slot in anywhere after Whist as a 2-player trick game.

## 5. Shared UI components

All in plain Tailwind v4 (no daisyUI), each with a `/dev/gallery` story at 360/392/1280 (`docs/guide/12-gallery.md`).

| Component | Used by | Notes |
|---|---|---|
| **Card face** (`<.playing_card card={...} />`, inline SVG) | all | Our own art: corner index (rank + suit pip), pip layout for 2–10, simple original courts (J/Q/K, e.g. letter + suit motif) and aces. Red/black plus an optional 4-colour deck setting for small screens. States: normal, legal, illegal (dimmed), selected (raised), just-played. |
| **Card back** | all | Our own pattern; also used for opponents' hands and the stock. |
| **Hand fan** | all | Own hand along the bottom. At 360px a 13-card hand overlaps cards ~22px each (index corner visible); 17 cards (3p Hearts) and Go Fish's growing hands wrap to two rows or compress further. Tap to select, tap again to play; multi-select mode for passing (Hearts) and melds (Gin). |
| **Opponent seats** | all | Name, card count (fanned backs or a number), turn indicator, bid/tricks badge, dealer chip. 3–7 seats around the table. |
| **Trick area** | Hearts, Whist, Oh Hell, Spades | Cards placed by seat position (N/E/S/W for 4; arc for 3–7), winner highlight and sweep animation to the winner, "last trick" peek. |
| **Trump / status strip** | Whist, Oh Hell, Spades, Hearts | Trump suit, hearts/spades broken, pass direction, round number. |
| **Score sheet** | all multi-round games | Rounds × seats table, totals, target line, moon/nil/gin markers; collapsible on mobile. |
| **Bid picker** | Oh Hell, Spades | 0..n buttons, forbidden bid disabled (hook), nil/blind nil for Spades. |
| **Stock + discard piles** | Crazy 8s, Gin, Rummy, Go Fish | Draw-from-stock / take-discard buttons, reshuffle animation. |
| **Suit picker** | Crazy 8s | After playing an 8. |
| **Meld area** | Gin, Rummy | Melds grouped, deadwood count, knock/gin buttons; layoff targets. |
| **Ask picker / books** | Go Fish, Old Maid | Choose a seat then a rank you hold; books shown per seat. |
| **Pass panel** | Hearts | "Pass 3 to the left" prompt, selected count, confirm; waiting-for-others state. |

The Hearts build should land the card face, card back, hand fan, opponent seats, trick area, status strip, score sheet and pass panel; later games mostly add the bid picker, piles, melds and ask picker.
