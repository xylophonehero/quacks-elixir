# Hearts — rules reference for an implementation

Scope: standard 4-player American Hearts ("Black Lady" scoring: hearts + Q♠), as played in most rule books and digital versions. House rules and other player counts are in §14 and are **off by default**.
Compiled 2026-10-15 for issue #87. Points marked ⚠️ are disputed between sources or not stated by any source; each one names the default we pick.

Sources (rules are traditional and public domain; no single official text exists):
- S1 Pagat, "Hearts" (John McLeod): https://www.pagat.com/reverse/hearts.html
- S2 Pagat, "Hearts Variations": https://www.pagat.com/invented/hearts_vars.html
- S3 Bicycle / US Playing Card Co., "Hearts": https://bicyclecards.com/how-to-play/hearts/
- S4 Wikipedia, "Hearts (card game)": https://en.wikipedia.org/wiki/Hearts_(card_game)
- S5 Wikipedia, "Microsoft Hearts": https://en.wikipedia.org/wiki/Microsoft_Hearts
- S6 Wikipedia, "Black Maria (card game)": https://en.wikipedia.org/wiki/Black_Maria_(card_game)
- S7 Whisthub, "Hearts rules": https://whisthub.com/hearts/rules
- S8 World of Card Games, "How to play Hearts": https://worldofcardgames.com/how-to-play-hearts
- S9 Hearts.co, "How to play Hearts": https://hearts.co/how-to-play-hearts
- S10 Wikibooks, "Card Games/Hearts/Rules": https://en.wikibooks.org/wiki/Card_Games/Hearts/Rules
- S11 Alan Hoyle, "Alan's Hearts page": https://www.alanhoyle.com/hearts.html
- S12 Do2Learn, "Black Maria": https://do2learn.com/activities/cardgames/black_maria.htm
- S13 CardHearth, "Hearts rules": https://cardhearth.com/guides/hearts-rules/
- S14 Wikipedia, "Cancellation Hearts": https://en.wikipedia.org/wiki/Cancellation_Hearts

⚠️ Research note: direct page fetches were blocked from the research container (DNS), so the text above was checked through search-engine extracts of these pages, not full-page reads. Every rule in §1–§13 is backed by at least two sources that agree; anything resting on one source or none is marked ⚠️. Re-read S1 in full before closing the issue.

---

## 1. Cards and players (S1, S3, S4)

| Item | Value |
|---|---|
| Players | 4, each playing alone (no partnerships) |
| Deck | Standard 52 cards, no jokers |
| Suits | ♣ clubs, ♦ diamonds, ♠ spades, ♥ hearts. No suit outranks another; **there are no trumps** |
| Rank order | A (high) K Q J 10 9 8 7 6 5 4 3 2 (low) |
| Cards per player | 13 (the whole deck is dealt) |
| Direction of play | Clockwise (to the left) |
| Penalty cards | The 13 hearts and the Q♠: 26 penalty points per round |
| Aim | Have the **lowest** score when the game ends |

## 2. Seats, dealer and deal (S1, S3, S4)

- Seats 0..3 clockwise. The first dealer is chosen at random; the deal passes to the left after each round.
- The dealer shuffles and deals all 52 cards one at a time, clockwise, starting with the player to their left, so everyone gets 13.
- The dealer has no other role in 4-player Hearts (the first lead is decided by the 2♣, §5). For the engine, "shuffle and deal" is one seeded shuffle; the deal order only matters for replaying a physical deal.

## 3. Round structure

One **round** (pagat and most books call it a "hand"; see `CONTEXT.md`) is:

1. Deal (§2).
2. Pass (§4), skipped on hold rounds.
3. Play 13 tricks (§5–§9). The holder of the 2♣ leads the first; the winner of each trick leads the next.
4. Score the round (§10, §11) and add it to each player's game score.
5. If anyone has 100 or more, the game ends (§12). Otherwise the next dealer deals.

## 4. Passing (S1, S3, S4, S5)

Before the first trick, each player chooses **exactly 3 cards** from their hand and passes them face down to another player. The direction depends on the round number and repeats every 4 rounds:

| Round (1-based) | `round mod 4` | Direction | Passes to (4 players, seats clockwise) |
|---|---|---|---|
| 1, 5, 9, … | 1 | **left** | seat + 1 |
| 2, 6, 10, … | 2 | **right** | seat − 1 (= seat + 3) |
| 3, 7, 11, … | 3 | **across** | seat + 2 |
| 4, 8, 12, … | 0 | **hold** (no pass) | — |

Rules:
- 4.1 Each player must choose their 3 cards **before** picking up the cards passed to them (S1). In the engine: all four seats choose, then all exchanges happen at once. A seat's received cards are never visible to it before it has committed its own pass.
- 4.2 Cards received cannot be passed on (follows from 4.1).
- 4.3 Any 3 cards may be passed, including the 2♣, the Q♠ and hearts.
- 4.4 On a hold round there is no pass phase; play starts immediately.
- 4.5 The direction cycle continues by round number regardless of who is dealer.
- ⚠️ 4.6 Some books (S1 notes it) describe the cycle as left/right/across/hold; a few older sources pass left only, or left/right/hold. Default: left, right, across, hold.

## 5. The first trick: lead (S1, S3, S4, S7)

- 5.1 After passing, whoever holds the **2♣ must lead it** to the first trick. (After a pass the holder can have changed; it is decided after the exchange.)
- 5.2 Nobody may choose another opening lead.

## 6. Following suit and void (S1, S3, S4)

- 6.1 Each other player, in clockwise order, plays one card. A player **must follow suit** (play a card of the led suit) if they can.
- 6.2 A player with no card of the led suit (**void** in that suit) may play any card ("discard"), subject only to §7 on the first trick.
- 6.3 There is no obligation to beat the cards already played (no "must head the trick") and no obligation to trump (there are no trumps).

## 7. No penalty cards on the first trick (S1, S4, S7, S8)

- 7.1 On the first trick, a player who is void in clubs **may not play a heart or the Q♠**. They must discard a diamond or a spade other than the Q♠.
- 7.2 **Exception:** if such a player has no clubs and no card other than hearts and the Q♠ (no diamonds, no other spades), they may play a penalty card. This is rare (S7: "only if they have no other legal option").
  - ⚠️ 7.2a Which penalty card? Sources differ: some say a heart, some say any penalty card. Default: **any heart or the Q♠** may be played in this case. House rule `first_trick_exception: :hearts_only` forces a heart when the player holds one.
  - 7.2b A heart played under this exception **breaks hearts** (§8.2).
- 7.3 Following suit wins over 7.1: a player who has clubs must play a club, so 7.1 never forbids a card to someone who can follow. (The Q♠ can never be *led* to trick 1, since the 2♣ is led.)
- ⚠️ 7.4 With the 4-player deal, the exception in 7.2 needs a 13-card hand of only hearts and the Q♠ with no clubs; it is possible (13 hearts, or 12 hearts + Q♠) but astronomically rare. It still needs a test (see test plan).

## 8. Leading and breaking hearts (S1, S4, S7)

- 8.1 The winner of a trick leads to the next one. They may lead any card, **except that a heart may not be led until hearts have been broken.**
- 8.2 **Hearts are broken** once a heart has been played to any trick (normally a discard by a player void in the led suit). From then on, hearts may be led for the rest of the round. S1: "It is illegal to lead a heart until after a heart has been played to a previous trick." The flag resets each round.
- 8.3 **Exception:** a player whose hand contains **only hearts** may lead a heart even though hearts are not broken; doing so breaks hearts (S1).
- 8.4 The Q♠ does **not** break hearts by default and may be led at any time after the first trick (S1: spades may be led to any trick after the first; S7, S13). House rule `queen_breaks_hearts` (§14).
- 8.5 Hearts not broken + leader holds hearts and other suits: the leader must lead a non-heart.

## 9. Winning a trick (S1, S3, S4)

- 9.1 A trick is won by the **highest card of the suit led**. Cards of other suits never win (no trumps).
- 9.2 The winner takes the trick (keeps its cards face down in front of them) and leads the next trick.
- 9.3 Only the penalty cards inside taken tricks matter for scoring; the number of tricks taken does not.
- 9.4 Most rule sets let a player look only at the last completed trick. The engine may expose the full history to the UI; a UI may restrict it. ⚠️ Default: all taken penalty cards are public (they are in the open log anyway in digital play).

## 10. Scoring a round (S1, S3, S4)

After the 13th trick each player counts the penalty cards in the tricks they took:

| Card | Penalty points |
|---|---|
| Each heart (2♥ … A♥) | 1 |
| Q♠ | 13 |
| Every other card | 0 |
| **Total per round** | **26** |

Round points are added to each player's game score (lower is better). The total added in a round is always 26, except when the moon is shot (§11).

## 11. Shooting the moon (S1, S2, S4, S5)

A player who takes **all 13 hearts and the Q♠** in one round has "shot the moon".

| Option | Effect | Who uses it |
|---|---|---|
| **`:add_to_others` (default)** | Shooter scores 0; each other player scores 26 | S4, S5 (Microsoft Hearts), most online versions |
| `:subtract_from_shooter` | Shooter scores −26; the others score 0 | Older books (S1 main text) |
| `:shooter_choice` | Shooter picks either of the two above | S1 ("or you may choose instead…"), S2 ("Wilson system") |

Default rationale: `:add_to_others` is the rule most players know from digital Hearts, it needs no extra decision step, and scores never go below zero. The other two are house rules (§14).

- 11.1 Taking all 26 penalty points is the only condition. It does not need all 13 tricks.
- ⚠️ 11.2 Moon and the game end: with `:add_to_others` the shooter can push others past 100 and win, or push others past 100 while the shooter still is not lowest. We apply the rule mechanically and check §12 after. (A common online refinement, "add unless that makes you lose, then subtract", is a house rule `:auto_best`, S2-style.)

## 12. End of game and winner (S1, S3, S4)

- 12.1 After scoring a round, if **any player's game score is 100 or more**, the game ends. The round is always played out; the game never ends mid-round.
- 12.2 The player with the **lowest** game score wins.
- ⚠️ 12.3 **Ties for lowest:** no source we found states a rule. Default: **shared win** (all tied lowest players win; game over). House rule `tie_break: :play_on` keeps dealing rounds until a single lowest player exists after a round (some players do this ⚠️ unsourced).
- 12.4 Hitting exactly 100 still ends the game (the condition is "100 or more"). The "exactly 100 resets to 50 / 0" rule is a house rule (§14).
- 12.5 The 100 threshold is configurable (`target: 100`); 50 is a common shorter game.

## 13. Edge cases the engine must handle

| Case | Rule |
|---|---|
| Hand has no clubs on trick 1 | May discard any diamond or non-Q♠ spade (§7.1) |
| Hand has no clubs and only hearts + Q♠ on trick 1 | May play any of them (§7.2) |
| Leader has only hearts, hearts not broken | May lead a heart (§8.3) |
| Leader has hearts and Q♠ only, hearts not broken | Must lead the Q♠ (it is not a heart) |
| Player void in led suit after trick 1 | Any card, including hearts and the Q♠ |
| All 26 points taken by one player | Moon (§11) |
| Two players reach ≥100 in the same round | Game ends; lowest wins (§12) |
| Hold round | No pass phase; 2♣ holder from the deal leads |
| Last trick | Normal; the winner leads nothing further |

---

## 14. House rules and variants (off by default)

Each is an option on `Hearts.new/1` (names are proposals). Variants with a different deck size or player count reuse the same engine.

| Option | Effect | Source |
|---|---|---|
| `moon: :subtract_from_shooter` | Shooter −26, others 0 | S1 |
| `moon: :shooter_choice` | Shooter chooses; adds a `{:moon, :add \| :subtract}` action after the last trick | S1, S2 |
| `moon: :auto_best` | Add 26 to others unless that would leave the shooter not lowest (or tied); then subtract 26 | S2-style, online sites ⚠️ |
| `queen_breaks_hearts: true` | Playing the Q♠ breaks hearts (and, in some versions, the Q♠ may not be led until hearts are broken ⚠️) | S7 (as known variant), S13 |
| `first_trick_points: true` | No restriction on penalty cards on trick 1 | S1 (older rule) ⚠️ |
| `first_trick_exception: :hearts_only` | In the §7.2 case, a heart must be played if held | ⚠️ |
| `omnibus: true` (Jack of Diamonds) | Whoever takes the J♦ scores −10. Round total becomes 16. Moon does not need the J♦ by default (S11); the J♦ taker still gets −10 ⚠️ (S9 counts a moon with the J♦ as 36, others require it) | S3, S10, S11 |
| `spot_hearts: true` | Each heart scores its rank (2–10, J 11, Q 12, K 13, A 14); Q♠ 25 ⚠️ | S2 |
| `black_maria: true` | British Black Maria: also K♠ = 10 and A♠ = 7 (total 43); no first-trick restriction; hearts may be led at any time; pass to the right every round; whoever holds the 2♣ need not lead it (the player left of the dealer leads) ⚠️ details differ between S6 and S12 | S1, S6, S12 |
| `exact_target_reset: 50` | A player who reaches exactly 100 drops to 50 | folk ⚠️ |
| `pass_cycle: [:left]` etc. | Override the pass cycle | S1 |
| `pass_count: 3` | Number of cards passed (some play 4 with 3 players) | S1 ⚠️ |
| `target: 50` | Shorter game | S4 |
| `tie_break: :play_on` | §12.3 | ⚠️ |

### 14.1 Three players (S3, S4, S9)

- Remove the **2♦**; deal 17 cards each (51 cards).
- The 2♣ is still in the deck and still leads.
- Pass cycle: left, right, hold ⚠️ (no "across" with 3; S1 also lists left/right only). Default for 3: `[:left, :right, :hold]`.
- Penalty total is still 26.
- Alternative (S1): deal 17 each and put the 52nd card aside to go to the winner of the first trick ("kitty"). ⚠️ Not default.

### 14.2 Five players (S4, S9)

- Remove the **2♦ and the 2♣**; deal 10 cards each (50 cards).
- With no 2♣, the **3♣** leads the first trick ⚠️ (follows logically; S4 lists it; generalise as "the lowest club in play leads").
- Pass cycle: left, right, hold ⚠️ (some groups pass to each position in turn: left, 2-left, 2-right, right, hold).
- Penalty total is still 26.

### 14.3 Six or more players

Out of scope. Use a double deck ("Cancellation Hearts", S14) where two identical cards cancel each other in a trick. Listed only for completeness.

### 14.4 Two players

Out of scope (S2 "Two-player Hearts" uses a draw stock). Listed only for completeness.

---

## 15. Open items (⚠️ summary)

1. §7.2a Which penalty card the no-clubs-only-penalty-cards hand may play. Default: any heart or Q♠.
2. §11 Moon default: `:add_to_others` (S1's main text prefers shooter −26 or choice).
3. §12.3 Ties for lowest at game end: no source; default shared win.
4. §14.1/§14.2 Pass cycles for 3 and 5 players; default left, right, hold.
5. §14.2 First lead with 5 players: 3♣ (lowest club in play).
6. §14 Black Maria details (pass direction, first lead) differ between sources; treat as a separate preset if we build it.
7. Re-read S1 in full (the fetch was blocked; the text was confirmed from search extracts only).
