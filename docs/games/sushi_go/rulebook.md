# Sushi Go! — rules reference for implementation

Scope: the **original** *Sushi Go!* (Phil Walker-Harding; Adventureland Games 2013, Gamewright 2014 English edition), 2–5 players, 108 cards. Research step of issue #86.
Out of scope (future): *Sushi Go Party!* (2–8 players, menu of 3 rolls / 3 appetizers / 2 specials / 1 dessert, spoon, menu, soy sauce, tea, uramaki, …), *Sushi Go! 10th Anniversary Edition*, *Sushi Roll* (dice). Their rules differ in places (e.g. Party: ties at 6–8 players, "need at least one maki to score", chopsticks wording); do not mix their text into this game.

Compiled 2026-10-15. Numbers marked ⚠️ could not be verified against official rulebook text.

**Verification caveat.** The session's network policy blocked direct downloads of every rulebook PDF and rules page (proxy 403 / DNS failure for gamewright.com, 1j1ju.com, rulespal.com, boardgamearena.com, goblins.net). Official text was therefore read only through search-engine excerpts of S1–S4 that quote the rulebook. Every statement below without ⚠️ is backed by at least one excerpt quoting S1 or a rulebook transcription (S2–S4) **and** agrees with all other sources found. A human should still re-read S1 once (see §12, Q0).

Sources:
- S1 Official Gamewright English rulebook ("Sushi Go! Rules of Play"): https://www.gamewright.com/gamewright/pdfs/Rules/SushiGoTM-RULES.pdf (mirror: https://aadl.org/files/catalog_guides/SushiGoTM-RULES.pdf)
- S2 Rulebook scan on 1j1ju: https://cdn.1j1ju.com/medias/e5/92/74-sushi-go-rulebook.pdf
- S3 Rulespal rulebook transcription: https://www.rulespal.com/sushi-go/rulebook
- S4 Goblins.net rules sheet (contents list): https://goblins.net/files/downloads/Sushi%20Go.pdf
- S5 Board Game Arena game help: https://en.doc.boardgamearena.com/Gamehelpsushigo
- S6 Ultra BoardGames rules summary: https://ultraboardgames.com/sushi-go/game-rules.php
- S7 Official Game Rules summary: https://officialgamerules.org/game-rules/sushi-go/
- S8 Geeky Hobbies rules + review: https://www.geekyhobbies.com/sushi-go-card-game-review-and-instructions/
- S9 64 Ounce Games accessible rules: https://www.64ouncegames.com/pages/sushi-go
- S10 Wikipedia: https://en.wikipedia.org/wiki/Sushi_Go!
- S11 Sushi Go Party! rulebook (for contrast only): https://www.gamewright.com/gamewright/pdfs/Rules/SushiGoPartyTM-RULES.pdf

---

## 1. Components (S2, S4, S5)

108 cards, nothing else (a score pad / paper is used for scoring).

| Card | Code name | Count | Notes |
|---|---|---|---|
| Tempura | `:tempura` | 14 | |
| Sashimi | `:sashimi` | 14 | |
| Dumpling | `:dumpling` | 14 | |
| Maki roll, 1 icon | `:maki1` | 6 | |
| Maki roll, 2 icons | `:maki2` | 12 | |
| Maki roll, 3 icons | `:maki3` | 8 | |
| Salmon nigiri | `:salmon` | 10 | 2 pts |
| Squid nigiri | `:squid` | 5 | 3 pts |
| Egg nigiri | `:egg` | 5 | 1 pt |
| Wasabi | `:wasabi` | 6 | |
| Chopsticks | `:chopsticks` | 4 | |
| Pudding | `:pudding` | 10 | |
| **Total** | | **108** | 42 + 26 + 20 + 6 + 4 + 10 |

Maki icon total in the deck: 6·1 + 12·2 + 8·3 = **54**.

## 2. Setup (S1, S2, S5)

1. Shuffle all 108 cards into one face-down deck.
2. Deal each player a hand by player count:

| Players | Cards per hand | Cards used per round | Cards used per game (3 rounds) |
|---|---|---|---|
| 2 | 10 | 20 | 60 |
| 3 | 9 | 27 | 81 |
| 4 | 8 | 32 | 96 |
| 5 | 7 | 35 | 105 |

The deck (108) never runs out in 3 rounds, so no reshuffle is ever needed.
3. Undealt cards stay as the deck for later rounds.

## 3. Turn structure — simultaneous pick, reveal, pass (S1, S5)

A round has as many **turns** as the hand size. Each turn:

1. **Pick.** Every player secretly chooses one card from their hand and places it face down in front of them. Players pick at the same time and in any order.
2. **Reveal.** When everyone has picked, all picked cards are turned face up together and added to each player's **tableau** (the cards in front of them). Cards stay in the tableau until round end; arrange by type for clarity.
3. **Pass.** Each player passes their remaining hand face down **to the player on their left** (S1). All hands always have the same size.

Repeat until hands are empty. The last turn each player has exactly one card and takes it; nothing is passed after it.

⚠️ Implementation convention: "left" = next seat number, `rem(seat + 1, n)`. With 2 players it does not matter.
Variant (fan sites only, not in S1): alternate pass direction per round. Not implemented.

## 4. Chopsticks (S1, S3)

- Chopsticks score nothing.
- Chopsticks picked on a turn go into the tableau like any card. **On a later turn**, a player who has chopsticks in their tableau may use them: pick one card normally, then (before the reveal) call "Sushi Go!" and take a **second** card from the same hand, also face down.
- Both cards are revealed with everyone else's. Then the used chopsticks card is taken from the tableau and **put into the player's hand** before hands are passed. Effect on hand size: −2 +1 = −1, so all hands stay equal.
- At most **one** chopsticks card may be used per turn, even with several in the tableau (S3, S8).
- Chopsticks cannot be used on the turn they are picked (they reach the tableau only at the reveal).
- Chopsticks need a hand of at least 2 cards (on the last turn of a round they cannot be used).
- A player may keep several chopsticks and use one per turn on consecutive turns.
- Unused chopsticks at round end are discarded with the tableau.
- Chopsticks returned to a hand are a normal card for the next player (they may pick it).
- The "Sushi Go!" call is table flavour; the engine models it as the chopsticks action.

## 5. Wasabi and nigiri (S1, S3)

- A wasabi card on its own scores nothing.
- When a player picks a nigiri (egg / salmon / squid) and has a wasabi in the tableau **without** a nigiri on it, the nigiri **must** be placed on that wasabi. It then scores **triple**: egg 3, salmon 6, squid 9.
- Each wasabi holds only one nigiri. Several empty wasabi: each new nigiri fills one; which one is irrelevant to scoring.
- A wasabi picked **after** a nigiri does not retroactively triple that nigiri (S3: "You may not place wasabi on an already placed nigiri").
- An empty wasabi at round end scores 0 and is discarded.
- ⚠️ **Wasabi + nigiri in one chopsticks turn.** Not addressed in any source found. Literal reading (wasabi must already be "in front of you") says the nigiri is *not* dipped. Common table practice lets the player pick wasabi as the first card and nigiri as the second and dip it. **Proposed engine rule:** the two cards resolve in the order the player gives them (`first`, then `second`); a wasabi as `first` can take a nigiri as `second`. Keep this behind a house-rule flag (`chopsticks_wasabi: :ordered | :strict`, default `:ordered`). See §12 Q1.

## 6. Round scoring (S1, S2, S5, S7)

At the end of each round every player scores their tableau:

### 6.1 Maki rolls — majority of icons
- Count maki **icons** (1/2/3 per card), not cards.
- Most icons: **6 points**. Tie for most: the tied players split 6 evenly, **ignoring any remainder**, and **no second-place points** are awarded.
- Second most icons: **3 points**. Tie for second: split 3 evenly, ignoring remainder.
- Split table (`div(points, tied)`):

| Tied | split 6 | split 3 |
|---|---|---|
| 1 | 6 | 3 |
| 2 | 3 | 1 |
| 3 | 2 | 1 |
| 4 | 1 | 0 |
| 5 | 1 | – |

- ⚠️ A player with **0 icons** never scores maki points (no first with 0, no second with 0). The base rulebook text found does not say this explicitly; Party (S11) does ("must have at least one maki"). With 0 icons for the "second" group the 3 points are simply not awarded.
- 2 players: same rule — the player with more icons gets 6, the other gets 3 if they have ≥1 icon (⚠️ see above); a tie gives 3 each and no second.

### 6.2 Tempura
Each **pair** scores 5. A single leftover scores 0. Score = `div(n, 2) * 5`.

### 6.3 Sashimi
Each **set of 3** scores 10. Leftovers score 0. Score = `div(n, 3) * 10`.

### 6.4 Dumplings
More is better, capped at 5:

| Dumplings | 0 | 1 | 2 | 3 | 4 | 5+ |
|---|---|---|---|---|---|---|
| Points | 0 | 1 | 3 | 6 | 10 | 15 |

### 6.5 Nigiri
Egg 1, salmon 2, squid 3; ×3 when on a wasabi (3 / 6 / 9).

### 6.6 Wasabi, chopsticks
0 on their own.

### 6.7 Pudding
Not scored per round. Pudding cards are **kept** in front of the player across rounds (§7).

Round score is added to the running total (score pad).

## 7. End of round (S1, S6)

1. Score as §6.
2. Discard all tableau cards **except pudding** (puddings stay with the player). Discards never return.
3. If fewer than 3 rounds were played, deal new hands from the deck (§2) and play the next round. Passing direction stays left.

## 8. End of game — pudding (S1, S5, S6, S7)

After round 3, after round scoring:
- Most pudding cards: **+6**, split among tied players (ignore remainder).
- Fewest pudding cards (0 counts): **−6**, split among tied players (ignore remainder, i.e. round toward zero: 2 tied −3, 3 tied −2, 4 tied −1).
- **2 players:** nobody loses points for pudding; only the +6 for most is awarded (S6, S7, S9).
- All players have the same number of puddings (including all 0): **nobody scores** pudding (S5; ⚠️ not seen in an S1 excerpt). In 2 players this means a tie gives 0, not 3 each.
- With 3+ players "most" and "fewest" are disjoint unless all are equal.

## 9. Winner (S1, S3, S4)

- Highest total score after 3 rounds plus pudding wins.
- Tie-breaker: the tied player with **more pudding cards** wins.
- ⚠️ Still tied (same score, same pudding count): no source found. **Proposed:** shared victory — `winners` is a list.

## 10. Edge cases and FAQ

| Case | Ruling | Source |
|---|---|---|
| Wasabi with no nigiri by round end | 0 points, discarded | S1, S3 |
| Nigiri picked while an empty wasabi exists | Must go on it (not optional) | S3 |
| Wasabi picked after nigiri | No effect on that nigiri | S3 |
| Two empty wasabi, one nigiri | Nigiri on one wasabi; other stays empty | S1 |
| Multiple chopsticks in tableau | Only one usable per turn | S3, S8 |
| Chopsticks on the turn they are picked | Not usable (not yet in tableau) | S1 "on a later turn" |
| Chopsticks on last turn (1 card in hand) | Impossible | derived |
| Chopsticks taking chopsticks | Allowed: it is just a card; the new one is usable from next turn | derived ⚠️ |
| Wasabi + nigiri in one chopsticks turn | ⚠️ proposed: ordered, wasabi first dips | §5 |
| 7th dumpling | Still 15 | S1 |
| Maki ties for first | Split 6, no second place | S1 |
| Nobody has maki | Nobody scores maki | derived |
| Pudding: everyone equal | Nobody scores pudding | S5 ⚠️ |
| Pudding at 2 players | No −6 | S6, S7, S9 |
| Final score tie | Most pudding wins; then ⚠️ shared | S1 / ⚠️ |
| Deck exhaustion | Cannot happen (max 105 of 108 used) | derived |

## 11. Engine notes

- Hidden information: hands, unrevealed picks, deck order. Public: tableaux (revealed), pudding counts, scores, hand sizes, which seats have already picked (but not what).
- Picks are committed; a seat cannot change its pick after submitting ⚠️ (table rule allows changing until reveal; proposed: no undo, keep it simple; revisit for UI).
- RNG: one shuffle of the 108-card deck at `new/1` from the seed (`:rand` `_s` API). No further randomness.

## 12. Open items (⚠️ summary)

- Q0. Re-read S1 directly (PDF download blocked in this session) to confirm card counts, hand sizes and the wording of §4–§9.
- Q1. Wasabi + nigiri picked together with chopsticks: ordered (proposed) or strict.
- Q2. Second-place maki with 0 icons (proposed: no points).
- Q3. "All equal puddings → nobody scores" (BGA text; likely S1, unconfirmed).
- Q4. Final tie after pudding tie-break (proposed: shared win).
- Q5. Pass direction mapping to seat numbers (proposed: seat + 1).
- Q6. Changing a pick before reveal (proposed: not allowed).
