# The Alchemists (expansion 2): the essence phase, the patients and locoweed III

Scope: the **alchemist's flask**, the **essence phase**, the **patients** (essence cards and patient
charts), locoweed book A (our **locoweed III**) and the 20 new fortune cards of "The Quacks of
Quedlinburg: The Alchemists" (Wolfgang Warsch, Schmidt Spiele 2020; English edition 2023), and how
to add them to the engine. Compiled 2026-10-03. Read with `alchemists.md` (the locoweed books, the
component list) and `herb-witches.md` (the expansion flag, the concurrent choices).
Text marked ⚠️ could not be verified against an official source.

Sources:
- A1 Official German rulebook "Die Alchemisten", 6 pages (text extracted, again on 2026-10-03):
  https://www.schmidtspiele.de/files/Retail/72dpi_PNG/49383_Die_Alchemisten_DE.pdf
- A2 Official English rulebook (Schmidt, translation Birgit Irgang), 6 pages (text extracted; pages
  1–5 rendered at 300 dpi to read the flask, the essence cards and the patient charts):
  https://www.schmidtspiele.de/files/Retail/300dpi_JPG/88319_Alchemisten_GB_web.pdf
- A3 BGG entry: https://boardgamegeek.com/boardgameexpansion/316597/the-quacks-of-quedlinburg-the-alchemists
  (the file page with the English card texts, https://boardgamegeek.com/filepage/211602, gives 403 to the fetcher)
- A4 Board Game Quest review: https://www.boardgamequest.com/the-quacks-of-quedlinburg-the-alchemists-expansion-review/
- A6 unknowns.de forum, "Liste der Wahrsagekarten in Quacksalber von Quedlinburg: Die Alchemisten"
  (user TerraformingArse transcribed the 20 titles from the box, 2023-11):
  https://unknowns.de/forum/thread/25012-liste-der-wahrsagekarten-in-quacksalber-von-quedlinburg-die-alchemisten/
- A7 Roger BellWest, "The Quacks of Quedlinburg" all-expansion summary, v0.002, 2024-05-15:
  http://tekeli.li/rogers-rules/quacks_rules.pdf

A1 and A2 agree on every rule below (A1 has one more sentence for Vampirism, §2.5). Quotes are from
A2 (English) unless marked A1.

**Two corrections to the handoff's picture.** (1) A patient is **not cured** and is **not bought**
with essences. Each player picks **one** patient at setup and keeps it for the whole game. The
essence is a **level** (0–10) on one track, not a stock of essences "by kind". (2) The essence phase
comes **before** the evaluation, not after it: "once all players have finished the Preparation
Phase, but **before the scoring**" (A2 p. 3; A1 "noch vor der Wertung"). In our engine:
`:potions → :essence → evaluation (4a–4d) → :shopping`.

---

## 1. Components and setup

Components (A2 p. 1): "5 alchemist's flasks, 5 essence markers, 8 patient markers, 8 patient
charts, 20 essence cards, 2 ingredient books (double-sided), 20 fortune telling cards, 40
firecracker chips (25 1-chips, 10 2-chips, and 5 3-chips), 30 locoweed chips."

- **Alchemist's flask** (one board per player colour, laid above the cauldron): an essence track
  with spaces **0 to 10** (the 0 space is in the flask bulb, 1–3 climb the neck, 4–10 run along
  the tube; read from the A2 p. 3 picture). After 10 the tube ends in a small bottle with no number
  ⚠️ (see §2.6). Ten tubes run from spaces 1–10 down to ten glass slots on the essence card. The
  bulb label repeats the 3 steps of the phase (colours, white = 7, exploded neighbours).
- **Essence card**: 4 double-sided cards per colour = all 8 essences. Each card has 10 glass slots,
  one per space 1–10. A slot holds a bonus (VP, rat tail, or a patient bonus in an oval glass) or
  is empty.
- **Patient chart**: the patient's picture and a text panel that says *when* the patient acts
  ("Start of the game", "Preparation Phase", "End of the Essence Phase").
- **Patient marker**: a token per patient, only to draw 3 patients at random.

Setup (A2 p. 2):

> "Each player additionally receives the alchemist's flask, essence marker, and 4 essence cards in
> their chosen color. [...] Place your alchemist's flasks above your cauldron and the essence marker
> on the 0 space in your alchemist's flask.
> Put the 8 patient markers in a bag and draw 3. Then find the matching patient charts and place them
> in the middle of the table with the picture side facing up. Then return all 8 of the patient
> markers and the 5 remaining patient charts to the box.
> Each player must now decide which of the 3 patients they wish to treat and place the corresponding
> essence card on their alchemist's flask. (You may look at your essence cards before you decide on
> a patient.)
> Beware: Several players may choose the same patient!
> You don't need the remaining essences in this game and can return them to the box."

Start chips: two patients change the starting bag (§2.5). Carrot nose: "take 1 additional 1-chip
pumpkin [...] So you start the game with 10 chips." Forgetfulness: "take 1 additional 1-chip crow
skull and 1 additional 1-chip toadstool [...] So you start the game with 11 chips."

Firecracker chips: replacement white chips only ("Use the new firecracker chips to replace your old
ones when they have worn out", A2 p. 2). Locoweed chips: the expansion's own 30 (see `alchemists.md`).

Multiplayer: the 3 patients are **shared and not used up**. There is no first come, first served.
The choice is free and the rulebook does not give an order; in the engine all seats choose at the
same time. The phase is played "at the same time" by all players (A2 p. 3).

---

## 2. The essence phase

### 2.1 When

> "There is now an additional phase to play once all players have finished the Preparation Phase,
> but before the scoring: the Essence Phase. During this phase, you distill an additional essence
> from your potion (regardless of whether your cauldron has already exploded or not). Similar to the
> Preparation Phase, you all perform the Essence Phase at the same time." (A2 p. 3)
>
> "After the Essence Phase, the evaluation takes place as usual." (A2 p. 3)

So it comes after the last stop or explosion (our soft stops are final, red chips beside the pot are
placed, B2 and B7 are resolved) and before step 4a (bonus die). It happens in every round, 1–9.

### 2.2 The three steps

> "At the start of the Essence Phase, always place your essence marker on the "0" space in the
> alchemist's flask. Just like when you prepare a potion, you cannot "save" anything for the next
> round. Complete the following three steps one after the other:
> 1. Count how many different ingredients (colors) are in your cauldron. Do not count the white
>    chips here! Place your essence marker on the appropriate space in the alchemist's flask.
> 2. Add up the white chips in your cauldron. If the sum totals exactly 7, move your essence marker
>    forward 1 additional space in the flask.
> 3. If the cauldron of the player directly to your left or right explodes, move the essence marker
>    forward yet another space. If the cauldrons of your two immediate neighbors explode, move the
>    essence marker forward 2 spaces. (So in the 2-player game, you may advance a maximum of 1 space.)"
> (A2 p. 3)

Example (A2 p. 3): 2 red, 1 orange, 1 blue = 3 colours → space 3; whites sum to 7 → 4; left
neighbour exploded, right not → 5.

Reading:
- Colours: orange, green, blue, red, yellow, purple, black and locoweed. Only chips **in the pot**
  (`drawn`); not the overflow bowl ⚠️, not red chips still beside the pot (A2's Ear worm special
  case says a drawn red Set-2 chip "is also counted" — only for the Ear worm count, §2.5).
- "exactly 7" is the white **sum of printed values**, like the B1 card. ⚠️ With the house rule
  `explode_above` ≠ 7 the card still says 7; we keep 7 (no rule says otherwise).
- Neighbours: the seats left and right (seat − 1 and seat + 1, wrapped). 2 players: the one
  opponent counts once. **Solo: no neighbours, step 3 gives 0** (open question 2).
- Locoweed book A (our III) adds a step 1b, §3.
- Max reach without book A: 8 colours + 1 + 2 = 11. The flask ends at 10 (§2.6).

### 2.3 The bonus

> "Check afterwards what bonus you have earned for your essence. Follow the glass tube that leads
> from your essence marker to the essence card. If the tube ends in a glass, you receive the bonus
> shown in that glass—either a rat stone, points, or a special bonus. Some essences allow you to
> perform a special action, which you can use in the next Preparation Phase. You may also perform
> this action if your tube does not end in a glass."
>
> "Note: In rare cases, it may be useful to select a lower space than the one you could reach. In
> this case, place your essence marker on the desired space before you receive your bonus."
>
> "- If victory points are displayed in the selected space, immediately move your point marker
>   forward by the specified number of points.
> - If a rat stone is displayed in the space, move your rat stone forward by 1 additional space at
>   the beginning of the next round.
> - Points and rat stones are always bonuses that you receive in addition to your patient bonus or
>   patient action.
> - If your current space displays a bonus in an oval glass, your patient chart will tell you when
>   you will receive the bonus.
> - Place the essence marker back on the "0" space at the start of the next Essence Phase."
> (A2 p. 3)

So the marker **stays** on its space until the next essence phase. For the four "action"
patients the space is a budget that the player spends ("reduce your essence by N spaces") during the
next preparation phase. The bonus glass is paid when the marker lands, not again when it is spent.

### 2.4 Final round

> "In the ninth round, there is a final Essence Phase. In this round, you do not earn any of the
> bonuses, rat tails, or points shown on the essence, but rather 1 point per space that you advanced
> on the alchemist's flask." (A2 p. 3)

Round 9: VP = final space (0–10). No patient bonus (Ear worm does not draw, Vampirism does not buy,
Chicken eyes gives nothing) ⚠️ ("any of the bonuses" read as all glass bonuses).

### 2.5 The eight patients (essences)

Glass slot n belongs to flask space n. Slot values are read from the card pictures in A2 pp. 1, 3,
4, 5 at 300 dpi. The pictures are small: **every slot table is ⚠️** (the texts are not). "rat" = 1
extra rat tail next round; a bare number = VP; "—" = empty slot.

| Id | Patient (DE) | Chart: when | Start chips | Slots 1…10 (⚠️) |
|---|---|---|---|---|
| `:nervousness` | Schreckhaftigkeit | Preparation Phase (start) | – | rat, 1×, 2×, 3×, 4×, 5×, 6×, 7×, 8×, 10× (chips to draw) |
| `:ear_worm` | Ohrwurm | End of the Essence Phase | – | 1×, 1×+rat, 2×, 2×+rat, 3×, 3×+rat, 4×, 4×+rat, 5×, 6× (chips to draw) |
| `:carrot_nose` | Rübennase | Start of the game + Preparation Phase | +1 orange 1 | rat, —, rat, —, rat, —, 1, 1, 2, 2 |
| `:wing_ears` | Segelohren | Preparation Phase | – | rat, —, —, —, —, —, 1, 1, 2, 2 |
| `:chicken_eyes` | Hühneraugen | End of the Essence Phase | – | 1 ruby, orange 1-chip, swap 1→2, fill flask, red 1-chip, 3 rubies, die ×2, droplet +2, swap 1→4, die ×4 |
| `:witch_hump` | Hexenbuckel | Preparation Phase | – | rat, —, rat, —, rat, —, 1, 1, 2, 2 |
| `:forgetfulness` | Vergesslichkeit | Start of the game + Preparation Phase | +1 black 1, +1 red 1 | —, —, —, —, —, —, 1, 1, 2, 2 |
| `:vampirism` | Vampirismus | End of the Essence Phase | – | rat, then a "buy a chip" glass on 2–10 |

The texts (A2 pp. 4–6):

**Nervousness.** "If your essence marker lands on space 1, you receive 1 additional rat tail at the
start of the next round. If you land on a different space, draw the specified number of chips from
the bag at the start of your next Preparation Phase. After drawing your chips, return the
firecrackers to the bag. Lay the rest of the chips out in front of you. During the Preparation
Phase, you may decide before you place each chip in the cauldron whether to place one of the chips
on display in the cauldron or to take a new chip from the bag and place it in the cauldron instead.
You may not put any of the chips in the cauldron if it has exploded." Special case: "Red book, set 2.
If you draw red chips from your bag, you may only place them after you stop."
- Engine: next round, before the first draw: draw n chips (`rng`), whites back to the bag, the rest
  in a new `Player.display`. Each step: `:draw` or `{:essence, {:place, chip}}` (a normal draw, with
  its action). At the end of the round, display chips go back to the bag with the rest.

**Ear worm.** "Once you have finished your essence, draw the specified number of chips from your bag
one by one. So draw a chip from the bag, place it in your cauldron according to its value (just like
in the Preparation Phase), and carry out the chip action as necessary. Repeat this as often as your
essence allows. If you draw white chips, also put them in the cauldron. Your cauldron will not
explode if the sum of the white chips totals more than 7." Special case: "Red book, set 2. If you
draw a red chip, it is also counted even if you do not put it in the cauldron in this round."
- This changes the **scoring space** before the evaluation. It applies to an exploded pot too ⚠️
  (the phase runs "regardless" of the explosion, and the text does not exclude it).
- Engine: forced draws in the `:essence` phase, `explode?` off. On-draw choices (blue, yellow,
  Y6, locoweed V, R6) open as in brewing. Not in round 9.

**Carrot nose.** "At the start of the game, take 1 additional 1-chip pumpkin and place it in your
bag. [...] At first, you will only receive the points you achieve or the rat tail as a bonus. You
can only use the essence's actual function in the Preparation Phase of the following round. Every
time you draw a pumpkin chip, you may choose to reduce your essence by 2 spaces. If you do this, place
the pumpkin you just drew on the next free ruby space. The value indicated is irrelevant."
- Engine: on an orange draw with `essence >= 2`: player phase `:essence_offer`,
  `{:essence, :carrot}` (place on the next ruby space of `PotTrack` after `pot_index`, essence −2) or
  `{:essence, :pass}`.

**Wing ears.** "Every time you draw a white chip, you get to choose: Move the white chip forward by
twice as many spaces as its value indicates. [...] To do this, you must reduce your essence by 2
spaces (regardless of your move distance). OR Return the chip to the bag. If you do this, you must
reduce your essence by 3 spaces. You may of course also choose not to use either of these 2 actions.
Then you just place it as usual." "Beware: You may not use either of the actions if the white chip
you just drew causes your cauldron to explode."
- Engine: on a white draw that does not explode: `{:essence, :double}` (≥ 2), `{:essence, :return}`
  (≥ 3), `{:essence, :pass}`. The white still counts toward the explosion when doubled ⚠️ (only its
  move doubles).

**Chicken eyes.** "You will receive your bonus immediately after the Essence Phase." Glasses
(labels on A2 p. 5): "Take 1 ruby." "Take a 1-chip pumpkin." "Swap a 1-chip from your cauldron for a
2-chip of the same color." "Fill your flask." "Take a 1-chip toadstool." "Take 3 rubies." "Roll the
die twice and take the bonus after each roll." "Move your droplet forward 2 spaces." "Swap a 1-chip
from your cauldron for a 4-chip of the same color." "Roll the die 4 times and take the bonus after
each roll." (Slot order ⚠️, from the picture.)
- The swaps: colour 1-chips with a 2/4-chip in that colour (white? ⚠️ we say coloured only, and
  only colours that have the value: green/blue/red/yellow 4, orange has no 2 or 4 ⚠️).
  A choice in `:essence` like `:chip_choice`.

**Witch's hump.** "Each time you place a chip on a ruby space, you may use your essence. Reduce it
by 2 spaces. Depending on which chip you have just placed, you receive the bonus indicated on the
patient chart. The value indicated on the chip always counts for the action. [...] If you are allowed
to take a chip as a bonus, put it in your bag immediately. If you roll a droplet, move your droplet
immediately (you may have to place it on your first chip). The chips you have already placed do not
move at all." "Beware: Red book, set 2. If you place red chips in your cauldron after your stop, you
can no longer perform an essence action with them." Chart: "For a 1-chip, take 1 ruby. For a 2-chip
or an African death's head hawkmoth, roll the bonus die once. For a 3-chip or ghost's breath, take a
1-chip mandrake. For a 4 chip or locoweed, take 3 victory points."
- So black (hawkmoth) counts as 2, purple (ghost's breath) as 3, locoweed as 4. White chips on a ruby
  space count too ⚠️ (the text says "a chip"). The orange 6-chip has no row ⚠️ (default: none).
- Engine: after a placement on a ruby space with `essence >= 2`: `{:essence, :hump}` / `{:essence, :pass}`.

**Forgetfulness.** "At the start of the game, take 1 additional 1-chip crow skull and 1 additional
1-chip toadstool [...] At first, you will only receive the points you achieve as a bonus. [...] At
any point during your turn, you may return any colored chip from your cauldron to your bag (except
the locoweed). Reduce your essence by as many spaces as the value on the chip. This does not change
the position of the other chips in your cauldron. So there may be "gaps" in your cauldron."
"Beware: You cannot return white chips to the bag."
- Engine: in `:potions`, `{:essence, {:forget, chip}}` when `essence >= value`. Same removal code as
  locoweed V (`Potions.last_index/2`, `return_to_bag/3`).

**Vampirism.** "If your essence marker lands on space 1, you receive 1 additional rat tail at the
start of the next round. If you land on another space, you may immediately buy an additional chip
for the value you reached at the end of the Essence Phase. Place this chip in your bag right away."
A1 adds: "Dies hat keinerlei Auswirkung auf das folgende „Chips kaufen" in der Wertung." (It has no
effect on the normal chip buy in the evaluation.)
- "the value you reached" = the space number as coins ⚠️ (2–10 coins). One chip, any buyable colour
  (round limits for yellow/purple apply ⚠️). Unspent coins are lost.

### 2.6 Edge cases (no official text)

- Space above 10: the tube ends in a bottle. Default: cap at 10 ⚠️ (open question 3).
- "select a lower space": allowed by the rules. Useful for Nervousness 1 (rat) vs 2 (draw 1) or for
  an empty slot. Default: offer it (§5.3).
- Rat tail in solo: our solo has no rat stone. Default: the bonus still gives a rat stone of 1 next
  round ⚠️ (open question 2).
- Herb Witches combined: no rule interaction is written. Overflow bowl chips are not "in the cauldron".

---

## 3. Locoweed book A (our locoweed III)

Book card (A2 p. 6 picture): "Number of spaces to move: 1. In the Essence Phase, you may move your
essence marker forward 1 ADDITIONAL space for each locoweed in your cauldron."

Rulebook text (A2 p. 6): "Once you have counted the chips of each different color in your cauldron
during the Essence Phase and placed your essence marker on the appropriate space, you may move 1
additional space for each locoweed in your cauldron. For example, if you have 2 locoweeds in the
cauldron, you may move forward 3 spaces in total: 1 space because the locoweed itself is a new color
in the cauldron and 2 spaces for the two locoweed actions."

- Step 1b, after the colour count and before the white-7 step. +1 per locoweed chip in the pot
  (`drawn`; not in the bowl). "may": always good unless the lower-space rule applies (§2.6).
- Price 11 (from `alchemists.md` §2). On draw it moves 1, no action.
- Engine: in the essence step, `+ count({:locoweed, _} in drawn)` when `sets[:locoweed] == 3`. Log
  part `locoweed: n`. Unlock III in `Game.sets!/2` and the picker only when `:alchemists` is on.

---

## 4. The 20 new fortune cards

A2 p. 2: "Shuffle the new fortune teller cards together with the ones from the basic game. Some of
the fortune teller cards can only be used with "The Herb Witches" or "The Alchemists" game
extension. You will recognize these cards by the symbol at the bottom right. Cards not bearing a
symbol can also be used with the basic game without any of the game extensions."

**Superseded (2026-10-11): the full English texts of all 20 cards are in `alchemists-fortune-cards.md`, read from the real card faces (Nick's TTS mod).** The card texts are not in the rulebook. A6 gives the 20 German
titles, transcribed from the box; the original poster says 6 cards carry an expansion symbol. A7
says: "Cards making reference to purple and yellow chips, or to Essence, are only available if they
are in play; otherwise draw again." English titles below are our translation, not the official ones.

| # | Colour | German title (A6) | Our translation | Needs (⚠️ guess from the title) |
|---|---|---|---|---|
| 1 | purple | Wer die Wahl hat... | Spoilt for choice | ? |
| 2 | purple | Rubin-Fieber | Ruby fever | ? |
| 3 | purple | Ein Geben und Nehmen | Give and take | ? |
| 4 | purple | Reiche Gaben | Rich gifts | ? |
| 5 | purple | Eine kleine Spende | A small donation | ? |
| 6 | purple | Eine Ratte in Ehren... | Honour the rat | ? |
| 7 | purple | Tausch-Rausch | Swap frenzy | ? |
| 8 | purple | Nachbar in Not | Neighbour in need | ? (neighbours: multiplayer) |
| 9 | purple | Nützliches Nagetier | Useful rodent | ? (rats) |
| 10 | purple | Ein starker Tropfen | A strong drop | ? |
| 11 | blue | Aus gut wird besser | Good becomes better | ? |
| 12 | blue | Abverkauf | Clearance sale | ? |
| 13 | blue | Der weiße Segen | The white blessing | ? |
| 14 | blue | Der Segen der Ratten | The rats' blessing | ? (rats) |
| 15 | blue | Eine gute Nachbarschaft | Good neighbours | ? (neighbours) |
| 16 | blue | Glück im Unglück | A blessing in disguise | ? |
| 17 | blue | Essentielle Essenz | Essential essence | **Alchemists** (essence) |
| 18 | blue | Hexenbesuch | A witch's visit | **Herb Witches** (witches) ⚠️ |
| 19 | blue | Ende gut, alles gut | All's well that ends well | ? |
| 20 | blue | Wiedersehen macht Freude | Nice to see you again | ? |

(A6 lists 10 blue titles but counts "Wiedersehen macht Freude" as an 11th in one post; one of the
blue titles may be a base-game card. ⚠️)

Recommendation: ship the essence phase **without** the new cards. Add them later from a
transcription of the real cards (Nick's box, or the BGG file A3). The existing 24 cards
(`Quacks.Rules.Fortune`) work with the expansion as they are.

---

## 5. Engine proposal

### 5.1 Expansions as a set

Replace `game.expansion :: nil | :herb_witches` with `game.expansions :: MapSet` of
`:herb_witches | :alchemists` (any subset; A2 p. 1 allows both together). Keep `expansion:` in
`Game.new/1` as an alias (`expansion: :herb_witches` → `MapSet.new([:herb_witches])`) for old saved
configs and tests. `Game.expansion?(g, :alchemists)` replaces `g.expansion` checks. First log
entries: one `{:expansion, x}` per expansion, in a fixed order.

### 5.2 Data: `Quacks.Rules.Alchemists`

- `patients/0`: the 8 ids (order of A2 pp. 4–6).
- `get(id)`: `%{name:, de:, when: :start_of_essence | :end_of_essence | :preparation, start_chips:,
  slots: %{1 => [...], ...}, text:}`. Slot terms: `{:vp, n}`, `:rat`, `{:draw, n}` (Nervousness),
  `{:ear_worm, n}`, `{:buy, coins}`, `{:rubies, n}`, `{:chip, chip}`, `{:swap, 1, 2}`, `:flask`,
  `{:dice, n}`, `{:droplet, n}`.
- `hump_bonus(chip)`: the Witch's hump table. `max_space/0` = 10.
- `deal(rng)`: 3 patients from a jump of the seed (like `WitchCards.deal/1`; `:rand` `_s` API only).

### 5.3 State

`Game`: `patients: [id, id, id]` (or `nil`). `Player`: `patient: id | nil`, `essence: 0..10` (the
marker; reset to 0 at the start of the essence phase, spent by actions next round), `display:
[chip]` (Nervousness), `essence_reach: 0..10` (the reached space while the lower-space choice is
open). `Player.phase` gains `:patient_choice`, `:essence_choice`, `:essence_offer`.

### 5.4 Flow and actions

- **Setup**: `Game.new/1` with `:alchemists` deals the patients and opens game phase
  `:patient_choice` before round 1 (all seats at once, **concurrent choice**). Action
  `{:patient, id}`. Start chips go into the bag; then round 1 starts (fortune card, potions).
- **Round**: `:potions` → `:essence` → evaluation (4a–4d) → `:shopping`. The essence step runs
  for every seat when the last stop is final, before `Evaluation.run/1`:
  1. compute `reach = min(10, colours + locoweed_III + white7 + neighbours)` (round 9: VP = reach;
     done).
  2. `:essence_choice` (concurrent): `{:essence, {:space, n}}` with `0 <= n <= reach`, default
     button = reach. Bots and an auto-skip pick `reach` when lower is never better ⚠️.
  3. pay the slot: VP now; `:rat` → `rat_bonus` for next round; patient glasses:
     Ear worm draws (one `:draw` each, explosion off, on-draw choices allowed), Chicken eyes
     (automatic; the swaps as `{:essence, {:swap, chip}}`), Vampirism (`{:essence, {:buy, chip}}`
     or `{:essence, :pass}`).
  4. game phase ends when nobody is left; then `Evaluation.run/1` as today.
- **Next preparation phase** (patient actions, cost from `essence`):
  Nervousness `{:essence, {:place, chip}}` from `display`; Carrot nose `{:essence, :carrot}`;
  Wing ears `{:essence, :double}` / `{:essence, :return}`; Witch's hump `{:essence, :hump}`;
  Forgetfulness `{:essence, {:forget, chip}}`; every offer has `{:essence, :pass}`.
- The marker reset to 0 happens at the **start** of the next essence phase, not at round end.

### 5.5 Log entries

- `{:expansion, :alchemists}` and `{:patients, [ids]}` (untagged, game start).
- `{seat, {:patient, id}}`.
- `{seat, {:essence, space, %{colours: n, locoweed: n, white7: 0 | 1, neighbours: 0..2}}}`.
- `{seat, {:essence_bonus, bonus}}` (the slot term, e.g. `{:vp, 2}`, `:rat`, `{:rubies, 3}`).
- `{seat, {:essence_spent, n, :carrot | :double | :return | :hump | {:forget, chip}}}`.
- Round 9: `{seat, {:essence_vp, n}}`.

### 5.6 AI (minimal legal play)

- Patient: a fixed preference for the automatic ones: Chicken eyes > Ear worm > Vampirism >
  Witch's hump > the rest; ties by the order shown. (Profiles can weigh it later.)
- Essence choice: always `reach`.
- Chicken eyes swap: the first 1-chip that can swap. Vampirism: the shop heuristic with `coins`
  = space.
- Ear worm draws: automatic, with the bot's existing on-draw choices.
- Preparation actions: `:pass` always (legal). Later: Witch's hump `:hump` when essence ≥ 2;
  Wing ears `:return` on a white that would take the pot to 6+.
- `mix quacks.sim` with `expansions: [:alchemists]` to check that no game blocks.

### 5.7 Configure screen

An "The Alchemists" toggle beside "The Herb Witches" (both may be on). On: the patient choice at
the start, the essence phase, locoweed III selectable (no longer greyed), and later the new fortune
cards. Off: locoweed III greyed with "needs The Alchemists". Supply with `supply: :limited`: +30
locoweed ⚠️.

### 5.8 Mobile UI sketch

- **Flask strip** above the pot, full width, about 40px: 11 small beads 0–10 in the player colour,
  the marker as a filled bead with the number. Before the evaluation it fills step by step
  (colours, then +locoweed, +white 7, +neighbours), each with a short label.
- **Patient badge** at the left of the strip: the patient icon and name. Tap opens a bottom sheet
  with the patient text and the 10 glass slots in a 5×2 grid; the reached slot has a ring.
- **Essence choice**: a sheet with the reached space, the slot bonus, a stepper to pick a lower
  space, and "Take".
- **Preparation actions**: the offer shows inline under the drawn chip, as the blue/yellow offers do
  today ("Spend 2 essence: pumpkin to the ruby space" / "No"). Forgetfulness: tap a pot chip,
  "Return (−n essence)". Nervousness: the display chips in a row above the Draw button; tap one
  to place it.
- Other players: the same strip, small, in their summary card.

---

## 6. Open questions for Nick

1. **New fortune cards**: the texts are not online (only titles). Default: ship the essence phase
   without them; add them later from the real cards (can you photograph or transcribe your box?).
2. **Solo**: step 3 (exploded neighbours) gives 0 in solo, and the rat-tail glass would do nothing,
   as solo has no rat stone. Default: neighbours 0; the rat-tail glass gives a rat stone of 1 next
   round even in solo.
3. **Flask above 10**: the tube ends in a bottle with no number. Default: cap at 10 (also 10 VP max
   in round 9).
4. **Lower space**: the rules allow a lower space. Default: offer the stepper only when a lower space
   gives a different bonus kind (for example rat vs draw); otherwise take the reached space without
   a click.
