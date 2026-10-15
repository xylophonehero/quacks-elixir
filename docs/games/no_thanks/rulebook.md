# No Thanks! (Geschenkt) — rules reference for an implementation

Design: Thorsten Gimmler. Publisher: Amigo (2004, *Geschenkt … ist noch zu teuer!*; re-released 2011 as *Geschenkt*, 3–7 players; 2024 edition no. 02455 adds special cards). English editions: Z-Man Games (2005), Mayfair (2015), Amigo (2018, 2024), CMYK (2025, base game only).
Scope: base game only. Compiled 2026-10-15 for GitHub issue #85.

Numbers marked ⚠️ could not be verified against an official source.

**Method note.** The official PDFs could not be downloaded from this environment (egress proxy refuses the hosts). Every fact below comes from web-search extracts of the listed pages. A fact quoted from S1 or S2 is an official-text extract; nothing was read from a scan or image. Someone with network access should read S1 once end to end and clear the ⚠️ marks.

Sources:
- S1 Official Amigo English rulebook, product 02455 (2024): https://blog.amigo-spiele.de/content/ap/rule/02455-GB-AmigoRule.pdf
- S2 Official Amigo English instructions (older edition), ManualsLib transcription: https://www.manualslib.com/manual/2035714/Amigo-No-Thanks.html
- S3 Board Game Arena game help (rules + implemented variants): https://en.doc.boardgamearena.com/Gamehelpnothanks
- S4 Wikipedia, *No Thanks! (game)*: https://en.wikipedia.org/wiki/No_Thanks!_(game)
- S5 Dale Yu, review of No Thanks! (2024 Amigo edition), Opinionated Gamers: https://opinionatedgamers.com/2024/12/24/dale-yu-review-of-no-thanks-2024/
- S6 Dale Yu, review of No Thanks (2025 CMYK edition): https://opinionatedgamers.com/2025/10/17/dale-yu-review-of-no-thanks-2025-version/
- S7 Ultra BoardGames rules summary: https://www.ultraboardgames.com/no-thanks/game-rules.php
- S8 Dutch Amigo rulebook copy (2004), spellenlab.be: https://spellenlab.be/media/files/cf34605d1007379b66c3d4e1e9471145c0b40448.pdf
- S9 H@LL9000 German review of *Geschenkt*: https://www.hall9000.de/html/spiel/geschenkt
- S10 MediaMarkt product listing (Amigo *Geschenkt*, box contents): https://www.mediamarkt.de/de/product/_amigo-geschenkt-spiele-143539159.html
- S11 University of Waterloo quick-start sheet: https://uwaterloo.ca/childrens-communication-lab/sites/default/files/uploads/documents/no-thanks.pdf
- S12 BoardGameGeek variants forum: https://boardgamegeek.com/forum/14261/no-thanks/variants

---

## 1. Components (S1, S2, S8, S10)

| Component | Count / notes |
|---|---|
| Number cards | 33, values **3 to 35**, one of each (S8: "33 speelkaarten met de waarde 3 - 35") |
| Chips | **55** (S10: "33 Spielkarten, 55 Chips"). The English rules call them **counters** (S2); summaries say chips or tokens. |
| Rules | 1 |

55 chips cover 5 × 11 = 55, 6 × 9 = 54 and 7 × 7 = 49, so the supply is never short. The 2024 Amigo edition adds special cards for an advanced game (§8.4), outside this scope.

## 2. Setup (S1, S2, S3)

### 2.1 Chips per player (verified)

| Players | Chips each | Chips used |
|---|---|---|
| 3 | 11 | 33 |
| 4 | 11 | 44 |
| 5 | 11 | 55 |
| 6 | 9 | 54 |
| 7 | 7 | 49 |

S1: "11 if you are 3–5 players, 9 if you are 6 players, 7 if you are 7 players". S2 and S3 give the same numbers. Leftover chips go back to the box (S7).

Player count: **3 to 7** (S1, S10). The 2004 original was for 3 to 5. There are no official rules for 2 players (§8.1).

### 2.2 Deck

1. Shuffle the 33 cards.
2. Put **9 cards back in the box unseen**. They stay out of the game (S2: "put nine cards back into the box without looking at them. These cards will not be used."). Nobody sees them, not even at game end. ⚠️ No source says whether they are revealed at the end. Treat them as hidden for the whole game.
3. The other **24 cards** form a face-down draw pile (S5, S9).
4. Turn over the top card. This is the **offer**. It starts with no chips on it.

### 2.3 Start player

⚠️ The base-game start player was not found in any extract. S1's expansion section says "The player who has said 'No thanks!' most recently starts the game", which only applies to the special-card game. Engine proposal: choose the start seat from the seed, or take it as an option.

### 2.4 Chip secrecy

Players hold their chips in hand, hidden (S9: chips "verdeckt in der Hand"; S2 tip: "it's a good idea to keep your counters hidden"; S5: chips "held in your hand and remain a secret"; S4: players "may choose to hide their chips"). So hiding chips is the official default, but it is advice rather than a strict rule. BGA has an option for it (S3 "Chip tracking: you can choose whether the amount of chips are visible"). Engine default: **hidden**, with an option `chips_visible: true`.

Public information: the face-up offer, the chips on the offer (S1 describes them lying next to the card), every player's taken cards (placed face up, S4), and the size of the draw pile.

## 3. Turn (S1, S2, S4)

### 3.1 Choice

The active player must choose one of two actions on the face-up offer:

- **Pass ("No thanks!")**: put **one** of your own chips on or next to the card. The turn goes to the next player clockwise (S9: the card goes on "to the left neighbour"). The card stays where it is.
- **Take**: take the card **and all the chips on it**. Put the card face up in front of you. Add the chips to your own.

### 3.2 No chips means take

A player with **0 chips cannot pass and must take** the card. ⚠️ No extract quotes this sentence verbatim, but every summary implies it. It follows from §3.1, since a pass needs a chip.

### 3.3 After a take

The player who took the card turns over the next card from the pile and is the **first to decide on it** (S4: "the player who collected the card … flips over the next card, also deciding on whether to take the card or pass it"; Amigo listing: "after you take a card you uncover the next card"). So a take does **not** move the turn. The same player acts again on the new offer and may take it at once.

### 3.4 Other rules

- A player can take a card the moment it is turned over, before anyone passes.
- There is no limit on how many times a card goes round the table. A card goes round until someone takes it.
- There is no limit on how many chips a card can collect.
- A pass is always exactly 1 chip. Players cannot pay more, give chips to each other, or trade.
- ⚠️ Not stated in the sources: players may not count the chips on an offer before deciding. In the physical game they are visible, so the engine shows them.

## 4. End of game (S1, S11)

The game ends **as soon as the last (24th) card has been taken** (S1). The draw pile is empty and nothing is on offer. Then players score. All 24 cards end up in players' hands. A pass can never end the game.

## 5. Scoring (S1, S2, S4)

1. Each card counts its face value as **plus points**.
2. **Runs**: a run of consecutive values counts **only its lowest card** (S4: "if you have cards of consecutive values, you only take the lowest value for the entire set"). A single card is a run of length 1.
3. Each remaining chip is **−1 point** (S4: "Chips are worth one negative point each").
4. **The lowest total wins** (S4).

`score = Σ min(run) over the runs − chips`

The score can be negative (no cards, chips left). The 9 removed cards can break runs, which is part of the game.

Examples:

| Cards | Chips | Runs | Score |
|---|---|---|---|
| 3 | 11 | [3] | 3 − 11 = **−8** |
| 27, 28, 29, 30 | 2 | [27–30] | 27 − 2 = **25** |
| 5, 7, 8, 9, 20 | 4 | [5] [7–9] [20] | 5 + 7 + 20 − 4 = **28** |
| 35, 33 | 0 | [33] [35] (34 is missing) | **68** |
| (none) | 15 | — | **−15** |

## 6. Ties (S1)

"If there is a tie, all players involved in it share the victory." (S1). There is no tiebreaker. The engine returns a list of winners.

## 7. Edge cases and FAQ

| # | Case | Ruling |
|---|---|---|
| 7.1 | Player has 0 chips | Must take (§3.2). |
| 7.2 | Every player has 0 chips | Each offer is taken by the active player. That player keeps acting until a chip is taken (they win any chips on a card), so the same seat can take many cards in a row. |
| 7.3 | Taking a card with chips on it | The player gains all of them at once, even 0. |
| 7.4 | Chip conservation | Chips in hands plus chips on the offer always equals the starting total. |
| 7.5 | Card conservation | 9 removed + pile + offer (0 or 1) + taken cards = 33. |
| 7.6 | Run through a removed card | Not possible. The removed card is not in anyone's hand, so the run breaks there (for example 20, 21, [22 removed], 23 scores 20 + 23). |
| 7.7 | Order of taken cards | Does not matter. Runs come from the set of values. |
| 7.8 | Can you see others' cards? | Yes. Taken cards are face up (S4). |
| 7.9 | Can you see others' chips? | No by default (§2.4). This is an option. |
| 7.10 | Ending | Only a take ends the game, after the last card. |

## 8. Variants (not in the base rules)

### 8.1 Two players ⚠️ house rule

No official 2-player rules were found. Neither S1 nor S2 mentions 2 players, and BGA (S3) supports only 3–7. BGG (S12) has several fan variants, none clearly accepted. A sensible engine-side house rule if we want it: 2 players, 11 chips each, remove 9 cards (same as 3 players). It is often criticised as too predictable. **Not in the MVP.**

### 8.2 Visible chips (BGA "chip tracking", S3) — house option

Chip counts are open to everyone. See §2.4.

### 8.3 Tactical variant (BGA, S3) — house rule

"Each player starts with 10 chips instead of 11. However, cards 10, 20 and 30 are guaranteed to be removed." That is 3 fixed cards plus 6 random cards (⚠️ S3 does not say whether the total stays 9; we assume it does). This is for 3–5 players. ⚠️ The adjustment for 6 or 7 players is unknown.

### 8.4 2024 Amigo special cards (S1, S5) — official expansion, out of scope

There are pink special cards (bad, which you can refuse with a chip like number cards) and green special cards (good; players **outbid** each other with chips for them). Setup: shuffle the pink special cards into the 33 number cards. Shuffle the green cards on their own, put 7 back in the box, and shuffle the rest into the deck. Then the player who said "No thanks!" most recently starts the game. ⚠️ The counts disagree (one extract says 16 pink + 16 green, S5 says 22 special cards in total), and the card effects were not read. It needs its own research pass.

## 9. Open items (⚠️ summary)

1. Base-game start player (§2.3).
2. A verbatim official sentence for "0 chips means you must take" (§3.2). The rule is not in doubt.
3. Whether the removed cards are revealed at the end (§2.2). Proposal: never.
4. Chip secrecy is advice in the rules ("good idea"), not a hard rule. Default hidden plus an option (§2.4).
5. No official 2-player rules (§8.1).
6. The tactical variant's total removed and its 6/7-player chips (§8.3).
7. The 2024 special-card counts and effects (§8.4).
