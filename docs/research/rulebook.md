# The Quacks of Quedlinburg — rules reference for a solo implementation

Scope: base game + Ingredient Set 1 ("Book 1"), 2024 Schmidt English rulebook.
Compiled 2026-10-02. Numbers marked ⚠️ could not be verified against an official source.

Primary sources (fetched and text-extracted):
- S1 Official Schmidt English rulebook 2024: https://www.schmidtspiele.de/files/Retail/72dpi_PNG/88220_Quack_rules_english_2024.pdf
- S2 Official Schmidt English rulebook v1 (2018, includes full Almanac text): https://gusandco.net/wp-content/uploads/2018/10/Quacksalber_Rules_English_v1.pdf
- S3 Ultra BoardGames rules summary: https://www.ultraboardgames.com/the-quacks-of-quedlinburg/game-rules.php
- S4 Ultra BoardGames Almanac: https://www.ultraboardgames.com/the-quacks-of-quedlinburg/ingredients.php
- S5 Rulespal rulebook transcription: https://www.rulespal.com/quacks-of-quedlinburg/rulebook
- S6 Roger Bell-West rules summary (2024): http://tekeli.li/rogers-rules/quacks_rules.pdf
- S7 Quackulator (Set 1 simulator, transcribed board + fortune cards): https://github.com/coreyduval/Quackulator
- S8 Rival Quack solo variant app (Marek Tupy variant, source code): https://github.com/waschinski/rivalquack
- S9 Marek Tupy solo variant file on BGG: https://boardgamegeek.com/filepage/174678/solo-variant
- S10 Dice n Board component list: https://dicenboard.com/game-guides/quacks-of-quedlinburg-guide/

---

## 1. Components (S1, S10)

| Component | Count / notes |
|---|---|
| Pots (player boards) | 4; front side = standard, back side = test-tube variant |
| Bags | 4 |
| Flasks | 4 (two-sided: full / empty) |
| Droplets | 8 (4 for the test-tube variant) |
| Rat stones | 4 |
| Scoring markers | 4 |
| 0/50 seal tiles | 4 (flip to "50" when the marker laps the track) |
| Scoring track with turn indicator | 1; VP spaces 0–50 (loops); rat tails printed between some spaces |
| Flame (turn marker) | 1 |
| Bonus die | 1 |
| Fortune Teller cards | 24 |
| Rubies | 20 |
| Ingredient books | 12: 2 each green/blue/red/yellow/purple (Sets 1–4, front/back), 1 orange, 1 black (2-player side / 3–4-player side) |
| Almanac of Ingredients | 1 |
| Ingredient chips | 215 + 3 white spares |

Chip supply (S1, S10):

| Colour | 1-chips | 2-chips | 3-chips | 4-chips |
|---|---|---|---|---|
| White (cherry bomb) | 20 (+1 spare) | 8 (+1 spare) | 4 (+1 spare) | – |
| Orange (pumpkin) | 20 | – | – | – |
| Green (garden spider) | 15 | 10 | – | 13 |
| Blue (crow skull) | 14 | 10 | – | 10 |
| Red (toadstool) | 12 | 8 | – | 10 |
| Yellow (mandrake) | 13 | 6 | – | 10 |
| Purple (ghost's breath) | 15 | – | – | – |
| Black (hawkmoth) | 18 | – | – | – |

Supply is limited: "Once an ingredient has no more chips, you may not buy that ingredient." (S1)

### 1.1 Pot (cauldron) track — space by space

The pot has **54 physical spaces** (index 0–53). Printed coin numbers run 0–33; coin values **15–33 each appear on two consecutive spaces**; the last space (the "spoon") is 35 coins / 15 VP. Rulebook: "Some spaces have the same scoring value, in which case the furthest one from space-0 is the higher scoring space." (S1). Table below is transcribed from the physical board by two independent fan implementations that agree exactly (S7 `data.py TRACK`, S8 `state.js cauldronData`). ⚠️ Not from an official document; spot-check against your board.

| idx | coins | VP | ruby | | idx | coins | VP | ruby | | idx | coins | VP | ruby |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0 | | | 18 | 16 | 4 | | | 36 | 25 | 9 | R |
| 1 | 1 | 0 | | | 19 | 17 | 4 | | | 37 | 26 | 9 | |
| 2 | 2 | 0 | | | 20 | 17 | 4 | R | | 38 | 26 | 10 | |
| 3 | 3 | 0 | | | 21 | 18 | 4 | | | 39 | 27 | 10 | |
| 4 | 4 | 0 | | | 22 | 18 | 5 | | | 40 | 27 | 10 | R |
| 5 | 5 | 0 | R | | 23 | 19 | 5 | | | 41 | 28 | 11 | |
| 6 | 6 | 1 | | | 24 | 19 | 5 | R | | 42 | 28 | 11 | R |
| 7 | 7 | 1 | | | 25 | 20 | 5 | | | 43 | 29 | 11 | |
| 8 | 8 | 1 | | | 26 | 20 | 6 | | | 44 | 29 | 12 | |
| 9 | 9 | 1 | R | | 27 | 21 | 6 | | | 45 | 30 | 12 | |
| 10 | 10 | 2 | | | 28 | 21 | 6 | R | | 46 | 30 | 12 | R |
| 11 | 11 | 2 | | | 29 | 22 | 7 | | | 47 | 31 | 12 | |
| 12 | 12 | 2 | | | 30 | 22 | 7 | R | | 48 | 31 | 13 | |
| 13 | 13 | 2 | R | | 31 | 23 | 7 | | | 49 | 32 | 13 | |
| 14 | 14 | 3 | | | 32 | 23 | 8 | | | 50 | 32 | 13 | R |
| 15 | 15 | 3 | | | 33 | 24 | 8 | | | 51 | 33 | 14 | |
| 16 | 15 | 3 | R | | 34 | 24 | 8 | R | | 52 | 33 | 14 | R |
| 17 | 16 | 3 | | | 35 | 25 | 9 | | | 53 | 35 | 15 | |

Official text for the end of the track (S1): "If you happen to reach the last space in your pot (33) or move past it, place the chip on the 33 and take what is depicted on the spoon. You receive 15 victory points and can go shopping with 35 coins." Anyone on this space who did not explode rolls the bonus die. Chips that would go past idx 53 are clamped to idx 53.

Ruby spaces by printed coin number: 5, 9, 13, 15(2nd), 17(2nd), 19(2nd), 21(2nd), 22(2nd), 24(2nd), 25(2nd), 27(2nd), 28(2nd), 30(2nd), 32(2nd), 33(2nd). Pattern: from 15 up, every ruby is on the second of each doubled pair, every other number ⚠️.

### 1.2 Scoring track rat tails
Rat tails are printed between some VP spaces on the 0–50 scoring track. Official rule only: count tails strictly between your marker and the leader's marker (S1). ⚠️ Exact positions not found in any official text. S7 reconstructs them as tails after VP 1, 3, 6, 8, 10, 12, 14, … 50 (every 2 from 6) and flags it "reconstructed — verify against the board".

---

## 2. Setup and starting bag (S1)

- Each player: 1 pot (standard side), 1 bag, 1 flask (full side up, on the large trivet), 1 rat stone (small trivet), 1 droplet on space 0, scoring marker on the "0" seal tile.
- **Starting bag: 4× white 1, 2× white 2, 1× white 3, 1× orange 1, 1× green 1** (9 chips).
- **Each player starts with 1 ruby.**
- Books on the table at start: orange, black, and green + blue + red of the chosen set (Set 1 for a first game). Yellow enters before turn 2, purple before turn 3.
- Flame on turn-indicator space 1. Fortune Teller deck shuffled, face down, in front of the start player.

---

## 3. Round structure (9 turns) (S1, S3)

Each turn:

1. **Fortune Teller card** — start player reads the top card aloud; applies to all players. Purple = resolved immediately before the turn; blue = applies during/at end of the turn. If a card grants a yellow/purple chip and that book is not yet out, the chip cannot be taken.
2. **Rats (from turn 2)** — every player except the leader counts rat tails between them and the leader on the scoring track and places the rat stone that many spaces past their droplet. The first chip is placed relative to the rat stone if present. Rat stone returns to the trivet at end of turn.
3. **Potions phase** — simultaneous drawing (see 3.1).
4. **Evaluation phase** A–F (see 3.2).
5. Turn-indicator actions: before turn 2 lay out yellow book; before turn 3 lay out purple book; **before turn 6 each player adds 1 white 1-chip to their bag**; turn 9 = last turn, "Stir!" simultaneous draws, VP purchase at end.
6. Pass the Fortune Teller deck clockwise; new start player; advance the Flame.

### 3.1 Potions phase (S1)

- First chip is placed `value` spaces after the droplet (or rat stone); each later chip `value` spaces after the previous chip. Empty gaps stay empty.
- Chip values 1, 2, 3, 4.
- **Explosion: if the sum of all WHITE chip values drawn exceeds 7 (i.e. ≥ 8), the pot explodes.** Only white values count. The exploding chip is still placed. The player must stop. Fortune Teller and chip actions still happen.
- Stop any time after a chip is placed; must stop when the bag is empty. Never look in the bag.
- **Flask**: "If the last chip you drew was white, you may put it back in your bag by using your flask." Not usable if that chip caused the explosion. Flip to empty; usable once per turn until refilled (phase F, 2 rubies). After using it you may continue drawing. Position and white sum revert.
- Blue, red, yellow chips act immediately when drawn. Green, purple, black act in phase B. Any action may be declined.
- **Scoring space** = the space directly after the last placed chip (exploded or not).

### 3.2 Evaluation phase (S1)

| Step | Rule |
|---|---|
| A Bonus die | Among non-exploded players, the one with the highest scoring space rolls; equal coin number → the physically further space wins; true ties → all roll. Exploded players never roll. |
| B Chip actions | Start player first, clockwise: resolve black, green, purple chips in the pot. |
| C Rubies | Everyone whose scoring space shows a ruby takes 1 ruby, exploded or not. |
| D Victory points | Everyone takes the VP printed on the scoring space (start player first). |
| E Buy chips | Coins = coin number of scoring space. Buy **1 or 2 chips; if 2, different colours**. Prices from the books. Leftover coins are lost. Limited supply. |
| F End of turn | Any number of times: **2 rubies → droplet 1 space forward** (permanent), **2 rubies → refill flask**. All chips (pot + bought) go back in the bag. Rat stone off the pot. |

**Exploded players must choose EITHER step D (VP) OR step E (buy chips)**, not both. They still get step C rubies and step B chip actions.

Bonus die faces (S1 lists 5 outcomes for a 6-sided die):

| Face | Payoff |
|---|---|
| 1 | 1 VP |
| 2 | 2 VP |
| ruby | 1 ruby |
| droplet | droplet 1 space forward |
| pumpkin | 1 orange 1-chip into the bag |
| ⚠️ 6th face | Not stated in any rulebook found. S7 assumes the repeated face is "1 VP" (die = 1,1,2,ruby,droplet,orange). Verify on the physical die. |

---

## 4. Ingredient Set 1 ("Book 1") — effects and prices (S2 Almanac verbatim, cross-checked S4, S7)

Prices are coins for a 1-chip / 2-chip / 4-chip. "–" = not available in that value.

| Colour | Name | 1 | 2 | 4 | When | Effect (Set 1) |
|---|---|---|---|---|---|---|
| White | Cherry bomb | not buyable | | | – | No action. Only white values count toward the explosion limit (7). |
| Orange | Pumpkin | 3 | – | – | – | "None. A 1-chip in the pot has no particular function other than filling the pot by one field." Same in every set. |
| Green | Garden spider | 4 | 8 | 14 | Phase B | "You receive a ruby for every green chip (irrespective of its value) that was drawn last or next to last." Chips elsewhere give nothing. |
| Blue | Crow skull | 5 | 10 | 19 | On draw | Place it, then draw 1 / 2 / 4 extra chips (for value 1 / 2 / 4). Place at most one of them as your next chip; the rest go back in the bag; you may return all. A placed chip's own action (incl. white explosion check) resolves immediately. |
| Red | Toadstool | 6 | 10 | 16 | On draw | Count orange chips already in the pot: 0 → move only its value; 1–2 → +1 extra space; 3+ → +2 extra spaces. Position of oranges irrelevant. |
| Yellow | Mandrake | 8 | 12 | 18 | On draw | If drawn **directly after a white chip**, you may put that white chip back in the bag (any value). Its space stays empty; the yellow chip does not move back. (White sum reverts for the explosion check.) |
| Purple | Ghost's breath | 9 | – | – | Phase B | Count purple chips: 1 → 1 VP; 2 → 1 VP + 1 ruby; 3+ → 2 VP + droplet 1 forward. Exactly one tier; a lower tier may be chosen. 4 chips do not combine tiers. |
| Black | African death's head hawkmoth | 10 | – | – | Phase B | **2-player side**: equal number of black chips as opponent → droplet +1; more than opponent → droplet +1 and 1 ruby. **3–4-player side**: more than ONE neighbour → droplet +1; more than BOTH neighbours → droplet +1 and 1 ruby. Same book in every set. |

Buy availability by turn: orange, black, green, blue, red from turn 1; yellow from turn 2; purple from turn 3 (S1).

---

## 5. Fortune Teller cards (24)

The official rulebook does not list the cards. The list below is a full transcription of the **North Star Games English edition** names/texts from S7 `Fortune.txt` (fan transcription; the author's app uses it in play). ⚠️ Not verified against an official document; the Schmidt English edition uses different names (e.g. "Pot is Full", "Pumpkin Patch Party", "Rat Infestation", "Small Donation", "Strong Ingredient", "White Blessing", "From Good to Better", "Good Neighbourhood", "Less is More", "Second Chance", "Sale", "Neighbour in Need", "The Pot is Filling Up", "Well Stirred" — names seen at https://www.chiark.greenend.org.uk/~ijackson/games-rules/quacks/house-rules.md.html and BGG threads, texts not retrieved). Count split (11 blue / 13 purple) matches S7.

### Blue — applies for the whole round (11)

| # | Name | Text | Solo-relevant |
|---|---|---|---|
| B1 | Bubbling Over | If your white tokens total exactly 7 when you stop drawing, move your droplet marker a space forward. | yes |
| B2 | Toil and Trouble | If your cauldron explodes this round, the player to your left gets to take any 2-value token from the supply. | no effect solo (or: rival ignores) |
| B3 | Second Chances | After you put the first 5 tokens on your cauldron, you can choose to continue drawing or put all of your tokens back in your bag and begin the round all over again. Once only. | yes |
| B4 | Double Double | Whenever anyone rolls the bonus die this round, they can roll it twice. | yes |
| B5 | Portentous Potables | This round, the cauldron explosion limit is increased from 7 to 9. | yes |
| B6 | Pumpkin Party | This round, every orange token moves an extra space forward. | yes |
| B7 | Safety Procedure | Beginning with the start player, if you stop before your cauldron explodes, draw up to 5 tokens from your bag. You can put one of them on your cauldron. | yes |
| B8 | Lucky Devil | If your final space this round shows a ruby, score 2 victory points (even if your cauldron has exploded). | yes |
| B9 | Flask Rabbit | At the end of the round, refill all flasks for free. | yes |
| B10 | Cauldron Bubble | This round, you can put the first white token you draw back into your bag. | yes |
| B11 | Fire Burn | If your final space this round shows a ruby, take an extra ruby. | yes |

### Purple — resolved immediately before the round (13)

| # | Name | Text | Solo-relevant |
|---|---|---|---|
| P1 | Choices, Choices | Take a black token OR any 2-value token OR 3 rubies. | yes |
| P2 | Drop It | Move your droplet marker a space forward. | yes |
| P3 | Wheeling and Dealing | You can trade in a ruby for any 1-value token besides purple or black. | yes |
| P4 | Charity | The player(s) with the fewest rubies can take a ruby. | compare vs rival/skip |
| P5 | Beginner's Luck | The player(s) with the fewest victory points receives a green 1 token. | compare vs rival/skip |
| P6 | Boomberry Cleanse | Score 4 victory points OR remove a white 1 token from your bag. | yes |
| P7 | Infestation | Count your rat tails again and move your rat marker that many extra spaces. | yes (rats ×2) |
| P8 | Less is More | Everyone draws 5 tokens from their bags. The player(s) with the lowest sum takes a blue 2 token. Everyone else takes a ruby. Put the tokens back. | removed in Tupy solo |
| P9 | Good Start | You can move your rat marker back by 1-3 spaces and take that many rubies. | yes |
| P10 | Rat-a-Tat | Take any 4-value token OR score a victory point for each rat tail you're currently behind the leader. | yes |
| P11 | Decisions, Decisions... | Move your droplet marker 2 spaces forward OR take a purple token. | yes (purple only if book is out) |
| P12 | Take a Chance | Everyone rolls the bonus die once and gets the reward shown. | yes |
| P13 | Flea Market | Draw 4 tokens from your bag. You can trade one in for the next higher value of the same colour from the supply. If not possible, take a green 1 instead. Put all tokens back. | yes |

Note: Tupy's solo rules remove "Schadenfreude" (= B2 Toil and Trouble, German name) and "Less is More" (P8) (S8).

---

## 6. Solo rules

**There is no official solo mode** in the base game, in The Herb Witches, The Alchemists, or the Mega Box (S1 text has none; expansion/Mega Box listings mention none). The de-facto standard is the fan variant below.

### 6.1 "The Rival Quack of Quedlinburg" — Marek Tupy (S8, S9) — most-accepted

Setup: set up as a 2-player game (black book: 2-player side). Remove Fortune Teller cards "Schadenfreude"/"Toil and Trouble" and "Less is More". Pick level I, II or III.

Rival model (reconstructed from S8 source; the PDF uses 9 "L" cards and 9 "R" cards per level, shuffled each game, one pair revealed per round):

| Level | L-card "ratstone" values (rival's brew length) | R-card droplet growth per round | R-card black chips |
|---|---|---|---|
| I | 6,7,8,6,7,8,8,7,9 | 1,2,3,3,2,2,3,3,4 | 0,0,0,0,1,1,2,0,1 |
| II | 7,8,9,8,9,10,9,10,11 | 2,3,3,3,3,3,3,3,4 | 0,2,0,1,0,1,0,1,1 |
| III | 8,9,10,10,11,12,12,11,12 | 2,3,3,4,3,4,4,4,5 | 2,0,1,1,1,1,1,0,0 |

Per round:
- Rival's scoring space index = `rival_droplet + L.ratstone + rat_tails_rival_is_behind_you + 1` (clamped to 53); look up coins/VP/ruby in the pot table (§1.1).
- Fortune Teller cards apply only to you; the rival never benefits.
- Rat tails: you earn them normally vs the rival's VP. If you lead, the rival gets rat tails (its space moves up by that many).
- Bonus die: you roll if your scoring space ≥ rival's and you did not explode. Rival never rolls.
- Black chips: compare your black count with R.blackchips using the 2-player black book. Rival gets nothing from black. Green/purple resolve normally for you.
- Rival gains the VP and (if ruby space) 1 ruby of its scoring space. Rival starts with 1 ruby.
- End of round (rounds 1–8): rival spends 2 rubies → droplet +1 if it has ≥ 2; then droplet += R.droplet. Round 9: rival spends 2 rubies → +1 VP instead; no droplet growth.
- After round 9: rival gains `floor(coins_of_its_scoring_space / 5)` VP. You convert as usual (§7). Highest VP wins.

### 6.2 Simplest faithful solo ruleset (beat-your-score) — proposed fallback

Use when no automa is wanted. 9 rounds, normal rules, with:
- No rats, no rat-stone (no leader to compare). Remove/redraw cards that need other players: Toil and Trouble (B2), Charity (P4), Beginner's Luck (P5), Less is More (P8); treat Rat-a-Tat (P10) as "take any 4-value token"; skip Infestation (P7) and Good Start (P9) or redraw.
- Black book: treat the "opponent" as having 0 black chips → every black chip in your pot gives droplet +1 and 1 ruby (2-player side, "more than opponent"). Or simpler: 1+ black chip = droplet +1 and 1 ruby, once.
- Bonus die: roll whenever you do not explode.
- Target score (community suggestion in BGG "Quacks Simple Solo Rules", https://boardgamegeek.com/thread/2759200/quacks-simple-solo-rules — thread not retrievable, ⚠️ thresholds unverified): beat your own best; S7 self-play reports a leader typically entering round 9 on ~46 VP in a 4-seat game, so ~50+ final VP is a strong solo result.

---

## 7. End of game scoring (S1)

- The game ends after turn 9's evaluation phase.
- Turn 9 is the only turn where the buy step is replaced: "At the end of the last turn, you can decide to buy a victory point with either **5 coins or 2 rubies**. You can repeat this as often as you like." Chips may still be bought instead but are useless; implementation: VP += coins div 5 + rubies div 2 (each conversion is optional per the text, but always beneficial).
- Exploded players in turn 9 still choose VP (step D) OR coins (step E → coins/5 VP).
- Chips drawn in the last turn count normally for scoring space, rubies, phase B actions.
- Droplet position has no value after turn 9 (droplet moves bought in turn 9 are wasted; rubies should go to VP).
- Winner: furthest on the scoring track (seal tile flips to 50 when passing 50). Tie-break: who filled the pot furthest in the last turn; else shared win.

---

## 8. Open items (⚠️ summary)

1. Sixth bonus-die face (assumed second "1 VP").
2. Rat-tail positions on the 0–50 scoring track (needed only for the Tupy automa).
3. Fortune Teller card texts are a fan transcription (North Star names); Schmidt English edition wording differs.
4. Pot track table is from two agreeing fan transcriptions, not an official document.
5. BGG threads (solo rules, card rulings) returned HTTP 403 / XML API unauthorized; not read directly.
