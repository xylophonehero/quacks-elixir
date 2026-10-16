# No Thanks! — rules reference for the engine

Scope: the base game, 3 to 7 players. Compiled 2026-10-16 for issue #85, step 1.
Each rule has a source tag (S1 to S6). A ⚠️ value has no official source, or the sources do not agree. The engine must keep these values as options or as written decisions.

Glossary: `docs/games/no_thanks/CONTEXT.md`. Test plan: `docs/games/no_thanks/test-plan.md`.

## Sources

- **S1** Official AMIGO English rules, 2018 (Item # 18414 V1-0918), "Invented by Thorsten Gimmler", 3-7 players. https://www.world-of-board-games.com.sg/docs/No-Thanks.pdf (text extracted with `pdftotext`).
- **S2** Dutch translation of the AMIGO 2004 rules ("Geschenkt", 3-5 players), by A. Van den Bergh and H. Bellekens. https://spellenlab.be/media/files/cf34605d1007379b66c3d4e1e9471145c0b40448.pdf (text extracted with `pdftotext`).
- **S3** Wikipedia, "No Thanks! (game)". https://en.wikipedia.org/wiki/No_Thanks!_(game)
- **S4** 64 Ounce Games accessible rules (3-5 player edition text). https://www.64ouncegames.com/pages/no-thanks
- **S5** Board Game Arena game help. https://en.doc.boardgamearena.com/Gamehelpnothanks
- **S6** BoardGameGeek, German second edition (2011) version page. https://boardgamegeek.com/boardgameversion/90203/german-second-edition

S1 is the primary source. S2 is the primary source for the 2004 text. When S1 and S2 do not agree, this document says so.

---

## §1 Components

- **§1.1** There are 33 cards. Each card has one number from 3 to 35. Each number occurs one time. (S1 "33 Cards, numbered from 3-35"; S2 "33 speelkaarten met de waarde 3 - 35")
- **§1.2** There are 55 counters (chips). All chips are equal; a chip has no value printed on it. (S1 "55 Counters"; S2 "55 chips")
- **§1.3** A card is worth points equal to its number. Points are bad. (S1 "Each card is worth the number of points shown on the card (but remember, points are bad!)")

## §2 Set-up

- **§2.1** Shuffle the 33 cards. Put 9 cards back in the box without looking at them. Nobody uses these 9 cards in this game. (S1 Set up 1; S2 "De overige 9 kaarten ... ongezien terug in de doos")
- **§2.2** The other 24 cards are a face-down stack (the deck). (S1 Set up 2; S2 "24 kaarten worden verdekt geteld")
- **§2.3** Each player gets chips by player count (S1 Set up 3; S3; S5):

  | Players | Chips each | Chips in play | Chips back in box |
  |---|---|---|---|
  | 3 | 11 | 33 | 22 |
  | 4 | 11 | 44 | 11 |
  | 5 | 11 | 55 | 0 |
  | 6 | 9 | 54 | 1 |
  | 7 | 7 | 49 | 6 |

  Chips that are not given out go back in the box. They do not come back into the game. (S1 "Return any remaining counters to the box"; S2)
- **§2.4** Player count is 3 to 7. (S1 cover "3-7 PLAYERS"; S3) ⚠️ The 2004 edition is 3 to 5 players with 11 chips (S2, S4). A Spielbound listing (seen in search results only, not opened) says the 6 and 7 player counts came with the 2011 German edition; S6 says the 2011 German second edition has "no rule changes". The engine uses S1 (3 to 7). 2 players is not an official count.
- **§2.5** The oldest player starts. (S1 Game play 1) S2 says only "decide who starts". ⚠️ The engine has no ages: the start seat is seat 0, or a seat from the seed (decision for Nick, see §9).
- **§2.6** Turn order is clockwise: play passes "to the player on your left". (S1 Game play 2; S2 "met de klok mee")

## §3 Turn

- **§3.1** The start player turns over the top card of the deck. This card is the **offer**. (S1 Game play 1a; S2)
- **§3.2** The player whose turn it is must do one of these two actions (S1 Game play 1a; S2):
  1. **Take**: take the offer and all chips on it (§3.4).
  2. **No thanks**: put one of their own chips on the offer (§3.3).
- **§3.3** After a "no thanks", the turn goes to the next player on the left. That player has the same choice. (S1 Game play 2; S2)
- **§3.4** When a player takes the offer, they put the card face up in front of them. They add all chips on it to their own chips. (S1 Game play 2; S2)
- **§3.5** After a take, the same player turns over the next card and has the choice again. The turn stays with them while they take cards. The turn passes only after they say "no thanks". (S1 Game play 3 "If you keep taking cards, your turn continues"; S2 example: Lisa takes the 11, then turns over the 16)
- **§3.6** A player with no chips must take the offer. (S1 Game play 4; S2 "ten laatste op het moment dat hij geen chips meer bezit")
- **§3.7** There is no limit on how many times an offer goes round the table. A player can say "no thanks" to the same offer many times. (S1 Game play 2 "play will go around and around"; S2 "meerdere ronden")
- **§3.8** A player with chips may take any offer at any time. A take is always legal. (S1, S2: "take the card" is one of the two choices with no condition) As a result, there is always a legal action until the game ends.

## §4 End of the game

- **§4.1** The game ends when the deck is empty and the last offer is taken. (S1 Winning the game "when the stack is gone and there are no cards left to collect"; S2 "Nadat alle 24 kaarten een eigenaar gevonden hebben")
- **§4.2** All 24 cards in the deck are taken by a player. No card stays on the table. (S1, S2, from §3.6 and §4.1)
- **§4.3** The 9 removed cards are not part of the end. Nobody turns them over. (S1, S2 say only "put back without looking") ⚠️ Whether the page shows them at the end is a decision for Nick (§9).

## §5 Scoring

- **§5.1** A **run** is two or more cards with consecutive numbers in front of one player. (S1 Game play 5 "A series can be made up of as few as two cards"; S2 "getallenkettingen")
- **§5.2** A run counts only its lowest number. A card that is not in a run counts its own number. (S1 Game play 5; S2; S3) Examples:
  - 13, 15, 16 → 13 + 15 = 28. (S1)
  - Then add 14: 13, 14, 15, 16 → 13. (S1, S2)
  - 17, 18, 19, 20 → 17. (S2)
  - 27, 28, 29, 30 → 27. (S3)
- **§5.3** A run can become longer, or two runs can join, when a player takes a card later. The score always uses the cards at the end of the game. (S1 example "If you later collect the 14")
- **§5.4** Each chip a player has at the end subtracts 1 point. (S1 Winning the game; S2; S3)
- **§5.5** Score = (sum of the lowest card of each run and of each single card) − chips. (S1) Worked examples:
  - Cards 3, 7, 12, 15, 25 (as runs and singles) and 8 chips → 62 − 8 = 54. (S1)
  - Cards 3, 7, 10, 14, 25 (as runs and singles) and 8 chips → 59 − 8 = 51. (S2)
  - Single cards 4, 6, 10, 21 → 41. (S2)
- **§5.6** The player with the lowest score wins. (S1 "The player with the lowest total wins"; S2)
- **§5.7** ⚠️ Ties: S1 and S2 have no tie rule. S3 says "The player(s) with the lowest number of points win(s)", so a tie is a shared win. S5 (BGA) gives no tie-breaker either. The engine uses a shared win; there is no tie-breaker.
- **§5.8** A score can be negative (for example, few low cards and many chips). (from §5.5)

## §6 Hidden and public information

- **§6.1** The 9 removed cards are hidden from all players for the full game. (S1 §2.1 "without looking at them"; S2)
- **§6.2** The order of the deck is hidden. Only the offer is face up. (S1 "face-down, to form a stack")
- **§6.3** The number of cards left in the deck is public: the stack is on the table. ⚠️ S1 and S2 do not say it in words; it follows from a physical stack. With §6.1, a player knows 24 − (cards taken) − 1 offer cards are left.
- **§6.4** The cards in front of each player are public, with all numbers visible. (S1 Game play 5 "players can still see the numbers"; S2 "Alle getallen moeten altijd goed zichtbaar zijn")
- **§6.5** The offer and the number of chips on it are public. (S1 example: Eli "adds the three counters on it"; chips are put "onto the card")
- **§6.6** Each player's chip count is hidden from the other players. ⚠️ The sources do not agree on how strong this rule is:
  - S2 (2004) and S4: a rule. "Iedere speler moet zijn voorraad chips ... verborgen houden" ("each player must keep their chips hidden"); S4 "all players should keep their chips hidden in their hand".
  - S1 (2018): a hint. "HINT: It's a good idea to keep your counters hidden."
  - S3: players "may" hide their chips.
  - S5 (BGA): a table option, "Chip tracking".
- **§6.7** Note for the engine: a player with a perfect memory can count every chip count from the public actions (start chips §2.3, one chip per "no thanks", the chips on each taken offer). So the hidden count (§6.6) is only a memory test. If `view/2` hides chip counts, the page must also not show a full public log of "no thanks" actions by seat, or the count leaks. (from §2.3, §3.3, §3.4) ⚠️ Decision for Nick (§9).
- **§6.8** At the end of the game all chip counts are shown, because the score needs them. (S1 §5.4 "subtract the number of counters you have")

## §7 Invariants (follow from the rules)

- **§7.1** Chips are never made or lost: the chips of all players plus the chips on the offer equal the chips in play from §2.3. (from §2.3, §3.3, §3.4)
- **§7.2** A player's chip count is never below 0. (§3.6)
- **§7.3** Each of the 24 deck cards is in exactly one place: the deck, the offer, or one player's cards. The 9 removed cards never move. (§2.1, §3.4)
- **§7.4** When there is no offer and the deck is not empty, the next card becomes the offer at once. The engine has no separate "turn over" action. ⚠️ Engine decision: S1 says the player "flips" the card, but there is no choice in it.

## §8 Variants (house rules)

- **§8.1** Tactical variant: each player starts with 10 chips (not 11). Remove the 10, 20 and 30 first. Shuffle the other 30 cards, deal 24 as the deck, and put the other 6 back unseen. (S2 "Tactische variant"; S4; S5) ⚠️ S2 and S4 are 3-5 player texts. The chips for 6 and 7 players in this variant are not known.
- **§8.2** Chip tracking: chip counts are public. (S5 option; S1 makes hidden chips only a hint, §6.6)

## §9 Open decisions for Nick

1. **Chip counts**: hide them in `view/2` (S2, S4) or show them (S1 hint only, S5 option)? Default proposal: hidden, with house rule `show_chips` (§8.2). If hidden, also decide how the log shows "no thanks" actions (§6.7).
2. **Start seat**: seat 0, or a seat from the seed (§2.5)?
3. **Removed cards at the end**: show the 9 removed cards on the results screen, or keep them hidden (§4.3)? They have no effect on the score.
4. **Ties**: shared win, no tie-breaker (§5.7). Confirm.
5. **Player count**: 3-7 only (§2.4), or also allow 2 players as a house rule (chips unknown)?
6. **Tactical variant** (§8.1): add it as a house rule now, and with what chips for 6 and 7 players?

## §10 Table.Kit modules the engine needs

See issue #83.

| Module | Use in No Thanks! |
|---|---|
| `Table.Kit.Rng` | `shuffle/2` for the 33 cards from the seed (§2.1); a start seat from the seed if Nick picks that (§2.5). |
| `Table.Kit.Deck` | Remove 9 cards unseen (§2.1), draw the top card as the offer (§3.1, §3.5), the size of the deck (§6.3). |
| `Table.Kit.Zone` | Visibility per zone for `view/2`: removed cards `:hidden` (§6.1); deck `:hidden` with a public size (§6.2, §6.3); offer and its chips `:public` (§6.5); each player's cards `:public` (§6.4); each player's chips `:owner`, or `:public` with `show_chips` (§6.6, §8.2). |

Not needed: `Table.Kit.Bag`, `Table.Kit.Dice`, `Table.Kit.PlayingCards`. Chips are counts (integers), not a kit component.
