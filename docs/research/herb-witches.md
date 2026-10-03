# The Herb Witches (expansion 1): rules reference for the engine

Scope: everything needed to add "The Quacks of Quedlinburg: The Herb Witches" (Wolfgang
Warsch, North Star Games English edition) to the existing engine. Compiled 2026-10-03.
Read with `rulebook.md` (base rules) and `ingredient-sets-and-customisation.md` (Sets 1-4, §e1).
Text marked ⚠️ could not be verified against an official source.

Sources:
- H1 Official North Star English rulebook, 4 pages (text extracted, book images read at 200 dpi
  for prices and card art): https://cdn.1j1ju.com/medias/ab/43/c3-the-quacks-of-quedlinburg-the-herb-witches-rulebook.pdf
- H2 Ultra BoardGames summary: https://www.ultraboardgames.com/the-quacks-of-quedlinburg/the-herb-witches.php
- H3 GeekUp bit set (chip counts per kind): https://boardgamegeekstore.com/products/geekup-bit-set-quacks-of-quedlinburg-herb-witches-expansion
- H4 Oaken Vault component list: https://www.oakenvault.com/en-us/products/hej
- H5 Reviews (witch types, penny colours, "Set 6" hints): https://tabletopbellhop.com/game-reviews/herb-witches/ ,
  https://tabletopgamesblog.com/2020/07/11/the-quacks-of-quedlinburg-the-herb-witches-expansion-saturday-review/
- H6 BGG threads (403 to the fetcher, titles only): "Locoweed purchase" https://boardgamegeek.com/thread/2306568 ,
  "Question about Book 6 Locoweed" https://boardgamegeek.com/thread/2435609

No separate expansion Almanac exists in the English box: the 4-page rulebook holds all book texts (H1).
There are **no new Fortune Teller cards** in the box (H1 contents list, H2, H5).

---

## 1. Components and setup (H1, H3, H4)

| Component | Count | Note |
|---|---|---|
| 5th-player kit | 1 pot, 1 bag, 1 flask, 2 droplets, 1 scoring marker, 1 rat stone, 1 0/50 seal | 2 droplets = test-tube variant. Same pot board as the base game (no new pot boards). |
| Ingredient books | 8 | Double-sided: Set 5 / Set 6 for green, blue, red, yellow, purple, black, locoweed; plus 1 new pumpkin book. |
| Herb witches | 12 | 3 types x 4 witches. Type = penny colour: **silver, copper, gold**. |
| Witch Pennies | 15 | 5 per colour (3 per player x 5 players). |
| Overflow bowls | 5 | One per pot colour, placed under the spoon. |
| Rubies | 20 | Extra rubies for 5 players. |
| Ingredient chips | 153 + 3 spare (H1); 151 (H4) ⚠️ | Breakdown below. |

Chip breakdown, from the GeekUp plastic set that replaces the box chips 1:1 (H3). ⚠️ H3 totals 154
and H1 says 153 + 3 spares; the 3 spares are probably 1 white 1/2/3 each (as in the base game),
which gives 151 regular chips = H4.

| Kind | Count | Purpose |
|---|---|---|
| White 1 / 2 / 3 | 6 / 3 / 2 (incl. spares ⚠️) | 5th starting bag + supply |
| Orange 1 | 12 | 5th player + supply |
| Green 1 / 2 / 4 | 10 / 5 / 5 | supply |
| Blue 1 / 2 / 4 | 8 / 5 / 5 | supply |
| Red 1 / 2 / 4 | 6 / 5 / 5 | supply |
| Yellow 1 / 2 / 4 | 6 / 5 / 5 | supply |
| Purple 1 | 8 | supply |
| Black 1 | 8 | supply |
| **Orange 6** (new) | **20** | new kind |
| **Locoweed** (new, "Fool's Herb" in German) | **25** | new colour, no printed value |

Engine reading: the expansion supply = base `Chips.supply/0` + the table above (added per kind).
Orange 6 and locoweed exist only with the expansion on.

### 1.1 Setup changes (H1, quoted)

- "now you can choose to play with ingredient book sets 5 and 6."
- "Replace the pumpkin ingredient book from the standard game with the new pumpkin ingredient
  book included in The Herb Witches and add in the orange 6-chips."
- "At the start of the game, all players additionally receive 1 Witch Penny in each of the 3
  different colors."
- "Each player takes the overflow bowl in the same color as their pot and places it under the
  spoon next to the pot."
- "Turn over **1 of each of the 3 witch types** at random and place them near the Scoring
  Track/Turn Indicator." So it is 3 of 12 (one per type), not "3 of 6". All players share
  the same 3 witches.
- Starting bag, starting ruby, droplet, rats, bonus die, 9 rounds: unchanged.

### 1.2 Book prices (read from the book images in H1)

Book order in H1 is "first book, second book" per ingredient. Set numbers are not printed in the
text. ⚠️ I map **first = Set 5, second = Set 6**. Support: H5 says Set 6 is the one where "Crow
Skulls (providing rubies)" and "Mandrakes (requiring rubies)" combine, which are the second blue
and second yellow books; the BGG thread "Question about Book 6 Locoweed" fits the harder
"copy" book (second). Green/red/purple/black mapping follows the same order, unconfirmed.

| Book | 1-chip | 2-chip | 4-chip | 6-chip |
|---|---|---|---|---|
| Pumpkin (new, one book) | 3 | – | – | **22** |
| Green Set 5 | 5 | 9 | 16 | |
| Green Set 6 | 4 | 8 | 14 | |
| Blue Set 5 | 8 | 15 | 19 | |
| Blue Set 6 | 5 | 10 | 18 | |
| Red Set 5 | 6 | 11 | 18 | |
| Red Set 6 | 7 | 11 | 17 | |
| Yellow Set 5 | 10 | 14 | 20 | |
| Yellow Set 6 | 8 | 12 | 18 | |
| Purple Set 5 | 9 | | | |
| Purple Set 6 | 16 | | | |
| Black Set 5 | 10 | | | |
| Black Set 6 | 9 | | | |
| Locoweed Set 5 | 8 | | | |
| Locoweed Set 6 | 10 | | | |

⚠️ When locoweed enters the shop is not in H1. A BGG thread ("Locoweed purchase", H6) asks
exactly this; the answer was not retrievable. Suggested default: from round 1 (like orange,
green, blue, red, black), with a house-rule toggle.

---

## 2. Rule changes

### 2.1 Herb witches (H1)

"Players can call upon the help of each of the herb witches **once per game**. To activate an
herb witch and use her power, the player must hand over the Witch Penny in the same color as the
witch." "Players can use any number of their Witch Pennies in a turn. Any Witch Penny not used by
a player counts as **2 victory points at the end of the game**."

Cost is always exactly 1 penny of the witch's colour; no rubies or coins. Ids below are mine.

#### Silver witches (potions / scoring phase)

| Id | Card header | Rule text (H1) |
|---|---|---|
| S1 | Preparation phase: "Use your flask after your pot explodes." | "During the Potions Phase, if your pot has exploded, use this herb witch to activate your flask. Return the last white chip to your bag. You can then draw further chips from the bag or end your turn." Note: "your flask must be full (that is, not already used)." |
| S2 | Preparation phase: "Draw 6 chips and decide in what order to place them." | "During the Potions Phase, if your pot has not exploded, use this herb witch to draw 6 chips from your bag. You can place any of these chips into your pot in any order. Carry out the chip actions as usual. Return any chips that you decide not to use back to your bag." Note: in the last turn the simultaneous drawing pauses for this player. |
| S3 | Preparation phase (card text paraphrased ⚠️): return the last 2 white chips to the bag. | "During the Potions Phase, if your pot has not exploded, use this herb witch to return the last 2 white chips you added to your pot back to your bag. Any gaps created in your pot are not filled. You may return just 1 of the last 2 white chips ... If you do, leave the 2nd white chip in your pot where it is." Note: "The 2 white chips do not have to be next to each other or occupy the last 2 spaces in the pot." |
| S4 | Scoring phase: "Do not suffer any penalties if your pot explodes." | "During the Evaluation Phase, if your pot exploded, use this herb witch to get victory points **and** to buy chips (normally you have to choose one or the other). If you have reached the highest scoring space, you also can roll the bonus die." |

#### Copper witches (buy chips phase)

| Id | Rule text (H1) |
|---|---|
| C1 | "use this herb witch to upgrade the **last 2 chips you added** to your pot by 1 level, OR upgrade **1 chip anywhere** in your pot by 1 level. This action can only be used on chips in your pot, not chips you have just purchased. You can only upgrade a 1-chip to a 2-chip or a 2-chip to a 4-chip. You cannot upgrade orange chips." Note: usable "if your pot exploded and you have opted for victory points." |
| C2 | "use this herb witch to **double the coins** you have to buy ingredients. You still can only buy a total of 2 different-colored chips." Note: in turn 9 "you can double the amount of money to purchase victory points at the normal 5:1 ratio." |
| C3 | "use this herb witch to **buy 1 chip and get an identical chip for free**." Example: buy 2 → receive 3 (2 identical + 1 other). |
| C4 | "use this herb witch to increase the amount of coins you have by **2 for each ruby you possess**. You do not give up your rubies." Note: if exploded and you chose VP, "you may use this witch to buy ingredients ... but only using the coins generated by this witch." |

#### Gold witches (VP / rubies / end of round)

| Id | Rule text (H1) |
|---|---|
| G1 | VP phase: VP by the number of **different chip colours in your pot**. "White chips do not count. Locoweed does count." Chart on the card: **1-4 colours → 3 VP, 5 → 4, 6 → 7, 7 → 10, 8 → 14.** (8 = orange, green, blue, red, yellow, purple, black, locoweed.) |
| G2 | VP phase: "get bonus victory points for the chips remaining in your bag. Empty out your bag. You earn **2 victory points** for each of the following chips: non-white 2-chips, 4-chips and 6-chips, purple chips, and Locoweed chips. White chips, black chips, and 1-chips are not counted (except purple). Put the chips back in your bag." Note: usable if exploded and you chose to buy. |
| G3 | Rubies phase: "if there is a ruby on your scoring space, use this herb witch to take **as many rubies as there are victory points on that scoring space**. You still receive the victory points from that scoring space." Notes: usable exploded + chose buy, "but only to get the rubies"; with the card "It's Shining Extra Bright" you choose its 2 rubies **or** this witch. |
| G4 | End of evaluation: "pay **only 1 ruby** to fill your flask or move a droplet forward. You may carry out this action more than once during this phase." Note: "You may **not** use this witch to convert rubies to victory points at the end of turn 9." |

⚠️ Open witch readings (rulings not found):
- G1 with 0 non-white colours: chart starts at 1 → assume 0 VP. Exploded + chose buy: not stated; assume not allowed (it is a VP-phase witch, unlike G2/G3 which say so).
- G3: assume the witch replaces the normal 1 ruby (not +1). Max is 15 VP space → but the spoon has no ruby; highest ruby space idx 52 = 14 rubies.
- G4: "once per game" means the whole end-of-round phase of one round, any number of 1-ruby buys.
- C1 "last 2 chips you added": two upgrades at once, each by one level; a chip already at 4 or orange or white or locoweed cannot be upgraded ⚠️ (white not stated; base P13/P4 exclude white, follow that). The upgraded chip goes to the bag; the lower one to the supply (as P4).
- C3 with an empty supply for the copy: no copy ⚠️.
- S3 when the removed white was the last chip: follow the engine's mandrake reading (later chips go after the newest remaining chip) ⚠️; the scoring space is after the newest remaining chip.
- S4 is chosen before step A (bonus die). In the engine, offer it as a third explosion choice.

### 2.2 Overflow bowl (H1, quoted)

"If a player reaches the final space in the pot (33) or moves past it (regardless of how far),
they should place their chip on the 33 space. If this final chip triggers an action that affects
the next chip drawn, this action is forfeited. If the player draws additional chips from their
bag, these chips should be placed in the overflow bowl. When scoring victory points that turn,
the player first receives what is pictured on the spoon (15 victory points and 35 coins). The
player then adds the value of all the chips in their overflow bowl and receives **half this total
amount (rounded down)** in victory points. Colored chips that end up in the overflow bowl do not
trigger any more actions. However, white chips still count towards the total value of cherry bombs.
All players who reach the last space in the pot (regardless of how many chips are in the overflow
bowl) can roll the Bonus Die if their pot has not exploded."

Engine reading:
- Once `pot_index == 53`, each further draw goes to `overflow` (list on Player), not `drawn`.
- Bowl chips: no `on_draw`, no phase-B action, not "last / next-to-last" ⚠️ (they are not in the pot).
  White values add to the white sum and can explode the pot.
- Bowl VP = `div(sum of values, 2)` in step D (with the spoon's 15). Locoweed in the bowl: value 1 ⚠️.
  An exploded player who chose buy gets neither ⚠️.
- Bonus die: **every** non-exploded player on idx 53 rolls, not only the single highest
  (in practice they are all tied on the highest space, so the base tie rule already gives this).
- "Forfeited" actions: blue offer (B1 draws extra chips), Y2 next-chip double, R2/R-Set-6 aside, yellow Set 5 lookahead ⚠️.

### 2.3 Locoweed (new colour) (H1)

"The Locoweed chip has no set value. It changes every time." Phase: on draw.

| Set | Text (H1) |
|---|---|
| 5 | "If you draw a Locoweed chip from your bag, move it forward according to the number of spaces you moved your rat stone at the beginning of the turn (including Fortune Teller card effects), plus 1 space." Note: "You can only move the Locoweed chip a **maximum of 4** spaces." Book image: "Place this chip based on the total number of spaces you moved your rat stone at the beginning of the turn, plus 1 (max. 4)". |
| 6 | "If you draw a Locoweed chip from your bag, it has the **same action and value as the last colored chip** in the pot. Ignore white chips. If no colored chips have been placed, the Locoweed chip has a value of 1 and no action." |

Other books that name locoweed: Purple Set 6 "Locoweed always has a value of 1"; Yellow Set 5
"If you draw a Locoweed chip, move the yellow chip forward 1 space"; G1 counts it as a colour; G2
gives 2 VP for it. Engine: model as chip `{:locoweed, 1}` (nominal value 1 for every value
lookup: purple Set 6, bowl, G2) and compute its move in `on_draw`. ⚠️ Set 6: whether the copied
chip makes locoweed count as that colour for other books (e.g. green last/next-to-last, purple
count) is not stated; assume it stays locoweed for colour checks and only copies move + on-draw action.
⚠️ Phase-B copies (copying a green/purple/black) are not stated; assume on-draw only.

### 2.4 Pumpkin book and orange 6-chips (H1)

"Action: None! The orange 1-chip and 6-chip have no function other than filling the pot 1 or 6
spaces. Important: All upgrades, whether through books, witches or Fortune Teller cards (e.g.,
'An Opportunistic Moment') do not apply to orange chips. It is not possible to upgrade an orange
1-chip to an orange 6-chip." Prices 3 / 22. Red Set 1 and Blue Set 5 count orange **chips**, so
an orange 6 counts as one.

### 2.5 Set 5 and Set 6 books for base colours (H1, quoted; set mapping ⚠️ §1.2)

| Book | When | Text |
|---|---|---|
| Red 5 | on draw | "check if there is a higher value red chip already in your pot. If so, use that higher value to place your newly drawn red chip." Ex.: red 4 in pot → red 1 or 2 moves 4. |
| Red 6 | on draw | "place it in your pot and draw another chip and set it aside. You decide when to place this chip in your pot, but you **must use it this turn, even if your pot exploded**." Note: a white chip set aside "will still count towards determining if your pot explodes when you place it." |
| Yellow 5 | on draw | "place it in your pot as normal and then draw another chip from your bag. Move the yellow chip forward by the value of the newly drawn chip. If you draw a Locoweed chip, move the yellow chip forward 1 space. Put the additional chip back in your bag." ⚠️ Read as: yellow moves its own value + the drawn value; the drawn chip (even white) has no effect. |
| Yellow 6 | on draw | "you may give up 1 ruby from your supply to move the yellow chip forward by 3 additional spaces. You may only give up 1 ruby per yellow chip drawn." |
| Blue 5 | on draw | "see if there are **at least** as many orange chips in your pot as the value of the blue chip. If so, immediately receive victory points equal to the value of the blue chip." Orange values do not matter. |
| Blue 6 | on draw | "note its value. Then look at that same number of chips immediately preceding the blue chip. If any of these chips are white **1-chips**, you receive 1 ruby for each." |
| Green 5 | phase B | "For every green chip that is last or next-to-last in your pot, you may choose any chip that is currently in your pot to be the first chip you place in your pot for the next turn. This chip has to be equal or lower in value to the green chip. If both ... are green, you can choose 2 chips and place them as your first 2 chips in your next turn. You can place them in any order." "You may use that chip's action as normal. You may select the green chip to start the next turn." |
| Green 6 | phase B | "For every green chip placed last or next-to-last in your pot, you can roll the bonus die once. The value of the green chips is irrelevant." Note: with "The Pot is Full" card, roll twice per chip. |
| Purple 5 | phase B | "Add the victory points for all spaces where there is a purple chip. This sum becomes the number of coins you can use to buy up to 2 chips of different colors during this Chip Action Phase. In the final turn (turn 9), this sum can be used to purchase victory points as normal (5:1). You never add this sum to your coins in the Buy Chips Phase." |
| Purple 6 | phase B | "Look at the value on the chip placed in your pot directly after the purple chip. You receive victory points based only on the **printed value** of this chip (not the number of spaces the chip moved.)" "Locoweed always has a value of 1." ⚠️ purple as last chip → 0; a purple after a purple gives 1. |
| Black 5 | on buy + phase B | "When you purchase a black chip in the Buy Chips Phase (or if you receive one through a Fortune Teller card), you must place that black chip **into the bag of the player to your left**. Move your droplet 1 space forward." "During the Chip Actions Phase, you receive 1 ruby for every black chip the person to your left has in their pot. You also get a ruby for each black chip that is last or next-to-last in your own pot." |
| Black 6 | phase B | "The player whose black chip is the furthest in their pot can move their droplet 1 space forward. The player whose black chip is the second furthest in their pot receives 1 ruby." Note: "It is possible for one player to receive both bonuses. If there is a tie, all of the players involved receive the corresponding bonus." So the ranking is over **chips** (pot index), not players. |

The Set 5/6 black books replace the 2p / 3-4p black book when chosen; they ignore player count.
Note (round 9): the app numbers them black books II and III (`sets: %{black: 2 | 3}`), after the base book I.
Pumpkin has one book only. White has none.

### 2.6 Fortune Teller clarifications (H1)

No new cards. H1 rules for base cards (North Star names):
- "If a Fortune Teller card tells players to draw chips from the bag (e.g., 'Overpowering
  Ingredient' or 'A Second Chance'), this does not involve any risk. **It cannot cause the pot to
  explode**—even if the white chips in the pot exceed the explosion limit. The action of the chip
  placed with the 'Overpowering Ingredient' card is not carried out."
- Upgrades from cards ("An Opportunistic Moment") never apply to orange.
- "The Pot is Full" doubles Green-6 die rolls; "It's Shining Extra Bright" (2 rubies) vs G3.

⚠️ Name map to `Quacks.Rules.Fortune` ids (texts match, names differ): "Overpowering Ingredient" ≈ B7
(5-chip offer on stop), "A Second Chance" ≈ B3, "An Opportunistic Moment" ≈ P13, "The Pot is
Full" ≈ B4 (die twice), "It's Shining Extra Bright" ≈ B11 (but H1 says **2** rubies; B11 says 1 extra).
**Conflict with the engine:** CONTEXT.md says a B7 placement "may explode the pot". H1 says it
cannot and the chip has no action. This clarification is an official ruling for the base game
too; decide whether to apply it always or only with the expansion.

### 2.7 Five players

H1 gives no special 5-player rules. Engine reading:
- Seats `0..4`; start seat rotation, shop order, rats, bonus-die ties: unchanged formulas.
- Black base book: ⚠️ use the 3-4-player side (neighbours) for 3-5 players. Set 5/6 black books
  ignore player count.
- Rat tails, bonus die, round structure, end scoring: unchanged.
- Supply: add the 5th-player chips (§1) to the base supply when the expansion is on (or always
  when `players == 5`).

### 2.8 End scoring changes

- Unused Witch Pennies: **+2 VP each** (H1).
- C2 in round 9 doubles coins before the 5:1 VP conversion. Purple Set 5's sum converts 5:1 in round 9.
- G4 cannot be used for the round-9 ruby → VP conversion (still 2:1).
- No other change; tie-break unchanged.

---

## 3. Engine impact

Seams from `docs/CONTEXT.md` and `lib/quacks/**`: `Quacks.Player` struct, `Game.Potions.on_draw/4`
+ `bonus/3`, `Game.Evaluation.chip_action/3`, `:chip_choice` / `:red_choice` / `:fortune_choice`
phases, `Game.Fortune`, `Rules.Chips` (`@prices` is a list per set, `@supply`, `chip` type values
1|2|3|4), `Rules.PotTrack` (clamp at 53 in `Potions` line ~277), `Game.new` options (`players`
1..4 guard, `sets` 1..4), lobby `LobbyLive`.

| # | Mechanic | Seams touched | Effort |
|---|---|---|---|
| 1 | Expansion flag `expansion: :herb_witches` (or `rules.herb_witches`) | `Game.new` options, `Session`, `GameServer.start/4`, lobby | S |
| 2 | 5 players | `Game.new` guard 1..4 → 1..5, `@type seat 0..4`, supply merge, lobby seat count, LiveView layout for 5 pots, black base book for 5 | S (engine) / M (UI) |
| 3 | Orange 6-chip + new pumpkin book | `Chips.chip` value type adds 6, `@prices {:orange, 6}`, supply, all "upgrade" code paths exclude orange (P4, P13, C1), shop rendering | S |
| 4 | Sets 5/6 prices | `@prices` lists grow to 6 entries; `sets` range 1..6; lobby book picker | S |
| 5 | Locoweed colour | `Chips.colour` adds `:locoweed`, `@prices` per set, supply 25, shop timing (⚠️ round), UI chip art; `Game.sets` gains `:locoweed` key (5/6 only, required when the expansion is on) | S |
| 6 | Locoweed Set 5 (rat stone + 1, max 4) | `Potions.on_draw` reads `Player.rat_stone` (must hold the total moved incl. P7/P9 changes) | S |
| 7 | Locoweed Set 6 (copy last coloured chip) | `on_draw` recursion with the copied `{colour, value}` and its set; logs `{:effect, {:locoweed, 6}, {:copied, chip}}` | M |
| 8 | Red 5 (highest red value) | `Potions.bonus/3` | S |
| 9 | Red 6 (aside, must place this turn) | reuse `Player.aside` + `:red_choice`, but only `:place`, forced even after explosion, white counts | M |
| 10 | Yellow 5 (peek next chip) | `on_draw`: draw one, add its value (locoweed = 1), return it | S |
| 11 | Yellow 6 (1 ruby → +3) | new player phase or reuse `:yellow_choice` with `:pay_ruby` / `:keep` | S |
| 12 | Blue 5 (VP if orange count ≥ value) | `on_draw`, VP gain during potions | S |
| 13 | Blue 6 (rubies per white 1 in preceding N) | `on_draw` reads `drawn` | S |
| 14 | Green 5 (starter chips for next round) | `Player` new field `starters`; `:chip_choice` pick; round start: remove from bag and place before normal drawing, with on-draw actions | M |
| 15 | Green 6 (die roll per green) | `Evaluation.chip_action`, reuse `@die` roller; B4 doubling | S |
| 16 | Purple 5 (mini-shop in phase B) | `:chip_choice` with a buy action and a coin budget; round 9 → VP | M |
| 17 | Purple 6 (VP = printed value of next chip) | `Evaluation.chip_action` reads `drawn` order | S |
| 18 | Black 5 (buy → left bag, droplet; rubies) | `:buy_chips` apply (redirect bought chip), Fortune P1 take, `Evaluation.black` | M |
| 19 | Black 6 (furthest / second furthest chip) | `Evaluation.black` across all seats | S |
| 20 | Overflow bowl | `Player.overflow`; `Potions.place` at idx 53 → bowl; white sum; forfeit pending effects; step D bowl VP; die eligibility | M |
| 21 | Witch setup + pennies | `Game.witches` (3 ids, seeded from `rng`), `Player.pennies` (`%{silver: true, copper: true, gold: true}`), end VP +2 each, lobby (random / pick) | S |
| 22 | Silver S1-S3 (potions-time witches) | new player actions `{:witch, id}` in `legal_actions` during `:potions` / `:explosion_choice`; S1 = flask after explosion; S2 = 6-chip offer (like B7 but multi-place, ordered); S3 = remove up to 2 whites | M |
| 23 | Silver S4 (no explosion penalty) | `:explosion_choice` third option; `Evaluation` gives VP + buy + die (like B2 `:protected_explosion`) | S |
| 24 | Copper C1-C4 (shop witches) | `:buy_chips` gains `{:witch, id}` before `{:buy, ...}`; coin modifiers (C2 x2, C4 +2/ruby), C3 free copy, C1 upgrade (as P4); exploded-VP players need a shop turn when they hold copper and C1/C4 is out | M |
| 25 | Gold G1-G2 (VP phase) | new choice step between C and D (or before D): a `:witch_choice` game phase per seat, like `:chip_choice` | M |
| 26 | Gold G3 (rubies) | same `:witch_choice` step, before step C; conflicts with B11 | S |
| 27 | Gold G4 (1-ruby spends) | `:spend_rubies` cost 2 → 1 for the round once used; not in round 9 conversion | S |
| 28 | Fortune clarifications (no explosion from card draws; B7 chip no action) | `Game.Fortune` B3/B7 | S |

### 3.1 Suggested slice order

1. **Data slice** (#1, #3, #4, #5): expansion flag, orange 6, locoweed colour, Set 5/6 prices,
   supply merge. Locoweed with no book yet can be a plain 1-mover. Unblocks everything.
2. **Easy on-draw books** (#6, #8, #10, #12, #13) and **easy phase-B books** (#15, #17, #19):
   pure functions on `drawn`, existing seams, high test value.
3. **Overflow bowl** (#20): independent, changes the 53 clamp; good to land before 5-player
   long games and before witches that push far (S2).
4. **Witch frame** (#21) + the simplest witches: S4 (#23), G4 (#27), C2/C4 (#24 coin modifiers).
   Establishes `{:witch, id}`, pennies, end-of-game +2.
5. **Choice-heavy books**: Yellow 6 (#11), Red 6 (#9), Purple 5 (#16), Black 5 (#18),
   Locoweed 6 (#7), Green 5 (#14, needs a round-start hook, do last).
6. **Remaining witches**: S1-S3 (#22), C1/C3 (#24), G1-G3 (#25-26, new `:witch_choice` phase).
7. **5 players** (#2): engine change is small and can come any time; the UI for 5 pots is the cost.
8. Fortune clarifications (#28) whenever B7 is touched; decide base-game behaviour first.

---

## 4. Solo reading (anything that compares players)

| Mechanic | Comparison | Proposed solo reading |
|---|---|---|
| Locoweed Set 5 | rat-stone distance (no rats solo) | Rat stone is always 0 → locoweed always moves 1. With the Rival Quack automa, use the rats it gives you. P9 moving the stone back counts ⚠️. |
| Black Set 5 | "player to your left" | No left neighbour: a bought black chip goes back to the supply (droplet +1 still applies); "rubies per black in the left pot" = 0; own last/next-to-last black → ruby as written. Alternative house rule: chip into your own bag. |
| Black Set 6 | furthest / second-furthest black chip across players | Rank your own black chips: 1+ black → droplet +1 (furthest is yours); 2+ black → also 1 ruby (second furthest is yours; H1 allows one player both). With an automa: compare with its R-card black count ⚠️. |
| Black base book, 5 players | neighbours | n/a solo; solo house rule `black_solo` unchanged. |
| S4 bonus die | "if you have reached the highest scoring space" | Solo: always highest (same as the base solo die rule). |
| Overflow die | "all players who reach the last space" | Unchanged. |
| G3 vs "It's Shining Extra Bright" | none | Unchanged. |
| Fortune clarifications | none | Unchanged. |
| Witches in general | none | All 12 work solo. Unused pennies +2 VP each; a solo score target must add up to 6 VP for them. |
| 5-player kit | – | n/a. |

---

## 5. Open items (⚠️ summary)

1. Set 5 vs Set 6 numbering per book (assumed first-listed = 5; confirmed in spirit only for blue/yellow).
2. Locoweed shop round (assumed round 1).
3. Exact chip counts: 153+3 (H1) vs 151 (H4) vs 154 incl. spares (H3).
4. Locoweed Set 6: copies on-draw action only? counts as copied colour?
5. Yellow Set 5: own value + drawn value (assumed).
6. Overflow: bowl chips are not "last/next-to-last"; exploded+buy gets no bowl VP; locoweed = 1.
7. Witch edge cases listed under §2.1.
8. B7/B3 "cannot explode" ruling vs current engine behaviour; "It's Shining Extra Bright" = 2 rubies vs B11's 1.
9. Base black book side for 5 players (assumed 3-4 side).
