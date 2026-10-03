# Pot reverse side, Second Chances, Purple Set 2, random fortune cards

Research for the engine. Compiled 2026-10-03. Read with `rulebook.md` and
`ingredient-sets-and-customisation.md`. Text marked ⚠️ is not confirmed by an official source.

Sources:
- R1 Schmidt English rulebook 2024, p. 8 "Game Variation" (text and test-tube image):
  https://www.schmidtspiele.de/files/Retail/72dpi_PNG/88220_Quack_rules_english_2024.pdf
- R2 Schmidt English rulebook v1 2018, p. 6 "Game variation" (same text, same image) and the
  Almanac (Ghost's breath Set 2): https://gusandco.net/wp-content/uploads/2018/10/Quacksalber_Rules_English_v1.pdf
- R3 Schmidt English Almanac, Dec 2018 (Toadstool Set 2, Ghost's breath Set 2):
  https://tesera.ru/images/items/1387218/Quack_rules-almanac_english-web-compressed.pdf
- R4 North Star "The Herb Witches" rulebook, "Clarification of the Fortune Teller cards":
  https://cdn.1j1ju.com/medias/ab/43/c3-the-quacks-of-quedlinburg-the-herb-witches-rulebook.pdf
- R5 unknowns.de thread "Quacksalber von Quedlinburg – Wahrsagekarten", with an answer from
  Schmidt Spiele (Senior Product Manager): https://unknowns.de/forum/thread/11933-quacksalber-von-quedlinburg-wahrsagekarten/
- R6 BGG threads (HTTP 403 to the fetcher; only titles and search snippets were read ⚠️):
  "A Second Chance (Eine zweite Chance)" https://boardgamegeek.com/thread/2060911 ,
  "Fortune teller card - A Second Chance: Clarification of the clarification" https://boardgamegeek.com/thread/2345724 ,
  "How does the Second Chance fortune card interact with Nervousness" https://boardgamegeek.com/thread/2995649 ,
  "Fortune teller card A Second Chance" https://boardgamegeek.com/thread/3574669
- R7 BGG review snippet ("the same pot but with a row of vials in a test tube rack instead of
  supportive icons for beginners"): https://boardgamegeek.com/thread/3159467/the-quacks-of-quedlinburg-a-detailed-review

## 1. Reverse side of the pot (test-tube side)

### 1.1 Official text (R1 p. 8; R2 p. 6 has the same words)

> After playing the game a few times, you can also play the game using the back side of the pots
> (the side with the test tubes). When using the test-tube side, also place a droplet on the far
> left test tube. Throughout the course of the game, whenever you're able to move your droplet
> forward (through a Fortune Teller card, chip action or paying 2 rubies), you can decide which of
> your 2 droplets you want to move forward - the droplet in your pot or the one on your test tubes.
> If you decide to move the test tube droplet, move it 1 glass to the right. You then
> **immediately** receive the bonus shown there:
> - [ruby] The player receives 1 ruby
> - [1 2 3 4] The player receives 1, 2, 3 or 4 victory points according to the number shown.
> - [chips] The player receives the chips shown, which they immediately put into their bag.
>
> Even though it is not indicated on the back side of the pot, the rules for blowing up your pot
> still apply.

Setup (R2 p. 1): in the normal game the pot goes "with the side without the test tubes facing up".

### 1.2 The track

Image: `docs/assets/pot-reverse-reference.jpg` (crop of the R1 p. 8 picture). ⚠️ Licence: the
rulebook is © Schmidt Spiele and is free to download, but it gives no licence. Keep the crop as an
internal reference only. Do not ship it in the app; draw our own track.

13 glasses. The droplet starts on glass 0. Read from the R1 image at 450 dpi:

| Glass | Bonus |
|---|---|
| 0 | start (empty) |
| 1 | 1 ruby |
| 2 | 1 VP |
| 3 | blue 1-chip |
| 4 | 2 VP |
| 5 | black 1-chip |
| 6 | 2 VP |
| 7 | red 2-chip |
| 8 | 3 VP |
| 9 | purple 1-chip |
| 10 | 3 VP |
| 11 | yellow 4-chip |
| 12 | 4 VP |

Totals over the full track: 1 ruby, 15 VP, 5 chips (blue 1, black 1, red 2, purple 1, yellow 4).
The chip colours are fixed, so the chip uses the book of the current Ingredient Set.

### 1.3 Rules, item by item

- **What the track is:** a second droplet. It never changes where your pot starts. It only gives
  the glass bonus.
- **How you move on it:** every time you may move your droplet 1 space, you choose: the pot droplet
  (+1 start space, as now) **or** the test-tube droplet (+1 glass, take the bonus now). Sources of a
  move (R1 list "Fortune Teller card, chip action or paying 2 rubies"): the ruby shop action
  (2 rubies), the bonus die droplet face, black (droplet / droplet + ruby), purple S1 (3 chips) and
  S2 (tiers 2 and 3), fortune cards P2, P11, B1 and the others that move the droplet.
- **Moves worth more than 1:** "move it 1 glass to the right" is per move. ⚠️ Our reading: a move of
  N spaces (purple S2 tier 3: +2, P11: +2) is N single moves, and each one may go to either droplet.
- **Rubies:** no other ruby use. The ruby price stays 2 (G4: 1).
- **The pot droplet:** unchanged. The pot track, ruby spaces and scoring spaces are the same pot (R7).
  The back side has no explosion reminder icons; the explosion rules still apply (R1).
- **End of the track:** ⚠️ not stated. After glass 12 the test-tube droplet cannot move. Propose: then
  only the pot droplet can take the move.
- **End of game:** no end-game effect. The bonus is immediate. VP from the glasses count like any
  other VP. In round 9 the rubies shop action is 2 rubies → 1 VP only (rulebook), so a droplet buy
  is not offered then; a die or chip move in round 9 may still go to a glass (⚠️ our reading).
- **Chips from glasses:** they go into the bag at once. With `supply: :limited`, no chip if the
  supply is empty (⚠️ same as other gains).

### 1.4 Engine proposal

- House rule `pot_side: :front | :back` in `Game.@rule_values`/`@rules` (default `:front`). Lobby
  checkbox "Pot: reverse side".
- `Player`: `tube: 0..12` (the test-tube droplet; 0 = start) and `droplet_moves: non_neg_integer`
  (moves that wait for a choice). Rules data: a new `Quacks.Rules.TestTubes` module with the 13-glass
  list from §1.2, e.g. `[nil, :ruby, {:vp, 1}, {:chip, {:blue, 1}}, {:vp, 2}, ...]`.
- One funnel: today about 11 call sites add to `droplet` (`game.ex` shop and black,
  `evaluation.ex` die/black/purple, `fortune.ex` P2/P11/B1). Replace them with
  `Game.move_droplet(g, seat, n)`. Front side: `droplet + n` (as now). Back side with `tube < 12`:
  `droplet_moves + n`, and the seat goes to a `:droplet_choice` player phase.
- `:droplet_choice` actions: `{:droplet, :pot}` and `{:droplet, :tube}`, one per move, until
  `droplet_moves == 0`. `{:droplet, :tube}` moves `tube + 1` and pays the glass. Log event
  `{:tube, glass, bonus}`.
- Shop: keep `{:rubies, :droplet}` for the pot droplet and add `{:rubies, :tube}` (2 rubies → 1 glass,
  bonus now). Two flat actions are simpler than `{:rubies, {:track, n}}` and need no extra phase in
  the shop. The player choice when spending rubies is then: droplet, test tube, or flask.
- Bots (`ai-opponents.md`): value a glass by its bonus; the pot droplet by its long-term worth.

## 2. Second Chances (B3) and the round's state

### 2.1 What the sources say

- Card text (our English list, `rulebook.md` §5): "After you put the first 5 tokens on your
  cauldron, you can choose to continue drawing or put all of your tokens back in your bag and
  begin the round all over again. Once only."
- German card (R5, quoted by the poster): "Sind die ersten 5 Chips in deinem Kessel gelandet,
  entscheide dich: Mach weiter ODER beginne die Runde **komplett neu**." ("start the round
  completely new").
- Schmidt Spiele answer (R5): "auch wenn der Kessel innerhalb der ersten 5 Chips explodiert kannst
  du die zweite Chance nutzen." (You can use the second chance even if the pot explodes within the
  first 5 chips.) This agrees with the R4 ruling that the card's draws "cannot cause the pot to
  explode" (already in the engine, `Fortune.safe_draw?/2`).
- No official text or FAQ talks about Set 2 yellow modifiers or Set 2 red chips beside the pot.
  The four BGG threads (R6) could not be read. ⚠️

### 2.2 Verdict

**Confirmed, with one limit.** "Komplett neu" and "put all of your tokens back in your bag" mean the
round's draw state goes back to the start:

- **Round modifiers (Y2 "next chip moves double", Y3 limit, R4, B2 protect): reset.** They come from
  chips that go back in the bag; a new round starts with no modifiers. ⚠️ Inference, not a ruling.
- **Red Set 2 chips set aside this round: back in the bag.** They are "your tokens" drawn this round,
  and the R3 text lets you "put the chip back into your bag at any time".
- **Red Set 2 chips saved from an earlier round: stay beside the pot.** They were not drawn this
  round; they belong to the round's start state. ⚠️ Inference.
- Red Set 6 chips set aside this round: back in the bag (same reason).
- ⚠️ Not covered by any source; our proposal: rubies or VP already taken during the first draws
  (blue S3/S4/S5/S6, yellow S6 ruby payment) stay taken, and a used flask stays used. A physical
  table does not undo them, and the card says only to put the tokens back.

### 2.3 Engine gap (read 2026-10-03)

`Quacks.Game.Fortune.step/3` for `{:fortune, :restart_round}` resets `bag`, `drawn`, `bowl`,
`pot_index` only. It does **not** reset `mods` and does not touch `aside`. `docs/CONTEXT.md` says
mods are "reset ... by B3", so the code and the glossary disagree. Fix: reset `mods` to the default
map, and move this round's `aside` chips back to the bag. `aside` today does not record when a chip
was set aside, so this needs a marker (e.g. `aside_round: [chip]` or tag entries with the round).

## 3. Purple Set 2 — exact rewards

Confirmed against R3 and R2 (both say the same):

> In Evaluation Phase B, you can discard drawn purple chips and exchange them for the following bonuses:
> - For 1 purple chip you receive 1 black 1-chip, 1 victory point and 1 ruby.
> - For 2 purple chips you receive 1 green 1-chip, 1 blue 2-chip, 3 victory points and may move your droplet 1 space forward.
> - For 3 purple chips you receive 1 yellow 4-chip, 6 victory points, 1 ruby and you may move your droplet 2 spaces forward.
>
> You are not allowed to trade in 4 purple chips to take advantage of the action for 2 purple chips
> twice. However, you can always trade in less chips than you have drawn.

`ingredient-sets-and-customisation.md` line ~109 is correct. The droplet move is optional ("may").

Player-facing wording for the book card (tiny table, one line per tier):

| Trade in | You get |
|---|---|
| 1 purple | black 1 · 1 VP · 1 ruby |
| 2 purple | green 1 · blue 2 · 3 VP · droplet +1 |
| 3 purple | yellow 4 · 6 VP · 1 ruby · droplet +2 |

Footnote line: "Once per round. You may trade fewer than you drew."

## 4. Fortune cards with a random result the player should see

From `lib/quacks/rules/fortune.ex` and `lib/quacks/game/fortune.ex` (read 2026-10-03):

| Card | Random part | What to show | Today |
|---|---|---|---|
| P12 Take a Chance | 1 bonus die roll per player | the die face and the gain ("Die: 2 VP") | logs only the gain (`{:vp, n}`, `:ruby`, `:droplet`, `:orange`); the face is not called a die roll |
| B4 Double Double | every bonus die roll is rolled twice | both faces, both gains | each roll logged as `{:bonus_die, face}` |
| P8 Less is More (not solo) | 5 random chips from each bag | each player's 5 chips and sum, who was lowest, and the gain (blue 2 or 1 ruby) | only the gain is logged; the chips and sums are lost |
| P13 Flea Market | 4 random chips from the bag | the 4 chips; the trade made, or "no trade possible: green 1" | offer shown while choosing; on the auto green 1 the 4 chips are not shown |
| B7 Safety Procedure | up to 5 random chips after stopping | the offer and the chip placed | offer shown in the choice; result logged |
| B3 Second Chances | the 5 safe draws | normal draws (already visible); show "pot over the limit but safe" if it applies | normal draw log |

Not random: P1–P7, P9–P11, B1, B2, B5, B6, B8–B11. P11/P2/B1/purple/black droplet moves need the
§1.4 choice on the back side.

## 5. Explosion limit: do B5 and Mandrake Set 3 stack?

Added 2026-10-03. Extra sources:
- R8 unknowns.de "Fragen zu lila und gelbem Buch": https://unknowns.de/forum/thread/23421-quacksalber-von-quedlinburg-fragen-zu-lila-und-gelbem-buch/
- R9 BGG "Mandrake, Yellow chip set 3 question" https://boardgamegeek.com/thread/2039611 and
  "Book 3 and Living in Luxury" https://boardgamegeek.com/thread/2299476 (HTTP 403; only search
  snippets read ⚠️)

### 5.1 Exact wording

- B5, English (our list, `rulebook.md` §5): "This round, the cauldron explosion limit is increased
  **from 7 to 9**."
- B5, German card "Aus den vollen Schöpfen" (R5, quoted by the poster): "Der Grenzwert der Chips
  erhöht sich in dieser Runde **von 7 auf 9**." The card does **not** say "explodiert erst ab 10".
- Mandrake Set 3, Almanac (R3): "When you draw the first yellow chip from the bag, the threshold for
  blowing up the pot with white chips **rises from 7 to 8**. After drawing 3 yellow chips, the
  threshold for blowing up the pot **rises to 9**." R2 says the same ("the threshold for white chips
  is 9").

### 5.2 Verdict: they do not stack; the highest value applies

Both texts set an absolute value ("from 7 to 9", "from 7 to 8", "to 9"). Neither says "+1" or
"+2". So one yellow + B5 = **9**, three yellows + B5 = **9**. The engine (`Potions.explode_above/2`,
`Enum.max`) is correct. Nick's 10 is not supported by any source.

- No official ruling exists. Not in the Almanac, not in R4 "Clarification of the Fortune Teller
  cards" (it covers only card draws and pumpkin upgrades).
- R5, digital_tilas, to the direct question whether the card and yellow Set 3 make 10/11:
  "zu 'aus dem vollen schöpfen': auch hier ganz simpel: der Grenzwert erhöht sich auf 9. Punkt!"
  No answer disagreed; Schmidt did not answer this part. ⚠️ fan answer.
- A German forum summary seen in search results (source page not identified ⚠️): the card "devalues
  the yellow chips in that round ... 9 is 9, this is not seen as +2".
- R9 threads ask the same question; their answers could not be read ⚠️.

### 5.3 House rule `explode_above` and The Herb Witches

- `explode_above` is our own house rule, so there is no official answer. The books and the card
  name a target value, so `max` stays consistent: house rule 9 makes B5 and Y3 useless; house rule 5
  still lets B5 raise the limit to 9. ⚠️ If Nick wants the house rule to shift everything (house 8 →
  Y3 9/10, B5 10), make it an offset `explode_above - 7` added to each source. That is a design choice,
  not a rule.
- The Herb Witches: no new fortune cards (`herb-witches.md`), and no witch, locoweed or Set 5/6 book
  changes the white limit (H1 text read again: no "limit"/"threshold" entry). The only related text
  is the R4 clarification that card draws cannot explode the pot. So nothing else enters the `max`.
