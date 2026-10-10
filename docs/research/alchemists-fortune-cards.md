# The Alchemists: the 20 new fortune teller cards

Scope: the full text of the 20 fortune teller cards of "The Quacks of Quedlinburg: The Alchemists"
(German "Die Alchemisten", Schmidt Spiele 2020; English edition), and how each card maps to our
engine. Compiled 2026-10-11. This file replaces the "texts not found" part of
`alchemists-essences.md` §4. Text marked ⚠️ is not verified against an official source.

**Result: all 20 cards have their full English card text, read from scans of the real card faces.**
The German text is complete for 4 cards and partly visible for 2 more. The German texts of the other
14 cards were not found (see §5).

## 1. Sources

| Id | Source | What it gave |
|---|---|---|
| F1 | **Nick's TTS mod, workshop 1864138254** ("The Quacks of Quedlinburg + The Herb Witches + The Alchemists"). Card sheet `http://cloud-3.steamusercontent.com/ugc/1754688643079298199/ED4C6FB94EC4B29FA8224038E081719D56CEF36A/` (cached copy from Nick's machine). Mod JSON `~/Library/Tabletop Simulator/Mods/Workshop/1864138254.json` (read only). | **Primary source.** A 6×4 sheet of scanned English card faces: 21 faces + 1 card back. The mod puts 20 of them in 3 decks (bag "Additional Fortune Telling Decks"): 14 cards for any game (card ids 301–304, 309–313, 316–320), 3 Herb Witches cards (305, 314, 315), 3 Alchemists cards (306, 307, 308). Slot 300 ("A Good Start") is a base-game card, not one of the 20 (see §4). The cards have no Nickname or Description in the JSON. Crops: `scratchpad/alchemists-cards/tts-00.jpg` … `tts-20.jpg`. |
| F2 | The same sheet in the public workshop mod 2804616513 ("The Quacks of Quedlinburg (with All Expansions)"), downloaded with the public Steam `GetPublishedFileDetails` API. | Confirms F1: the same sheet URL, deck "Extra Fortune Teller Cards" (14 cards, ids 301–320). |
| F3 | BGG image 7718583 (photo of the English base rulebook, p. 4, and a sleeved card), from thread 3148099 "Fortune card 'A Small Donation'": https://boardgamegeek.com/thread/3148099 | Photo of the printed English cards "A small donation", "A rat to cherish…" and "Spoiled for choice…". Same words as F1, so F1 is the official English print. |
| F4 | BGG thread 2909963 "The White Blessing" and thread 3293305 "Fortune Card: From good to better" (read with the public JSON API `https://api.geekdo.com/api/articles?threadid=…`) | Players quote the English cards "The white blessing" and "From good to better" word for word. Same words as F1. Also rules discussion (explosion = stop; no chip effects on an exchanged chip). |
| F5 | BGG thread 2716353 "Missing Fortune Teller Card" (same API) | The 10 official English purple titles. Same as F1. |
| F6 | BGG image 6123280 "some new cards" (German cards on a table), Alchemists gallery | **German** text of Essentielle Essenz, Ende gut alles gut, Wiedersehen macht Freude, Glück im Unglück (complete), Tausch-Rausch (nearly complete) and Hexenbesuch (partly hidden). Shows the expansion symbols: flask = Alchemists, witch hat = Herb Witches. |
| F7 | unknowns.de thread 25012 (= A6 in `alchemists-essences.md`): https://unknowns.de/forum/thread/25012-liste-der-wahrsagekarten-in-quacksalber-von-quedlinburg-die-alchemisten/ | The 20 German titles (10 purple, 10 blue), transcribed from the box. The first post also pairs the English and German purple titles. |
| F8 | BGG thread 2921256 "'Neighbor in need' Any reason to ever select the second option?", thread 2995649/2995657 | Rules talk only, no new text. |
| F9 | BGG thread 2280105 "Fortune Teller: A Good Start" (base game forum, 2019) | Shows that "A Good Start" is a base-game card (posted one year before The Alchemists). |

Tried without result: BGG file pages 211602 (English rules "updated with Fortune Teller Cards"),
323908 (Italian card translation PDF) and 226141 (Japanese rules "Updated Fortune Teller Cards") —
the download needs a BGG login (403), so not used. BGG XML API: 401 without a token. grep.app: blocked
by a bot check. Web searches for the German titles, rulespal.com, Board Game Quest: titles only.

## 2. The 20 cards

Colour: **purple** = resolve once, before the round; **blue** = a rule for this round (or the end of
it). Symbol: **—** = any game; **Witches** = only with The Herb Witches; **Alchemists** = only with
The Alchemists. "Tile" = the F1 crop `tts-NN.jpg`. Confidence: **high** = read from the card face in
F1 (and the same words in F3/F4 where noted).

| # | Colour | German title | Official English title | English card text (F1) | Symbol | Tile | Confidence |
|---|---|---|---|---|---|---|---|
| P1 | purple | Wer die Wahl hat... | Spoiled for choice ... | "Choose: Receive 1 ruby, 1 die roll and 3 additional rat-tails OR 1 red 2-chip." | — | 09 | high (also F3) |
| P2 | purple | Rubin-Fieber | Ruby fever | "Each player immediately draws one chip from the bag and takes as many rubies as the value of the chip drawn. Then return the chips to the bag and begin the Preparation Phase." | — | 10 | high |
| P3 | purple | Ein Geben und Nehmen | Give and take | "You can surrender 1, 2, or 4 rubies. Take a 1-chip, 2-chip, or 4-chip (any color except purple) in return OR take 2 rubies." | — | 13 | high |
| P4 | purple | Reiche Gaben | Rich offerings | "Choose: Receive 8 additional rat-tails OR roll 4 times OR move your droplet forward 3 spaces." | — | 12 | high |
| P5 | purple | Eine kleine Spende | A small donation | "If you have 2 or more rat-tails in your cauldron at the start of a round, you may roll the die once." | — | 11 | high (also F3) |
| P6 | purple | Eine Ratte in Ehren... | A rat to cherish ... | "You may surrender up to 3 rubies. For each ruby you surrender, you receive 3 additional rat-tails." | — | 20 | high (also F3) |
| P7 | purple | Tausch-Rausch | A quick exchange | "You may surrender one of your witch pennies in exchange for a chip of your choice." | **Witches** | 15 | high |
| P8 | purple | Nachbar in Not | Neighbor in need | "Choose: The player to your left may permanently remove a white 1-chip OR take a chip of their choice." | — | 19 | high |
| P9 | purple | Nützliches Nagetier | Useful rodent | "You may forgo 2, 4, or 6 rat-tails and take a 1-chip, 2-chip, or 4-chip in exchange (any color except purple)." | — | 18 | high |
| P10 | purple | Ein starker Tropfen | A powerful tipple | "You may move your droplet back 1 or 2 spaces and take a 2-chip or 4-chip in exchange." | — | 01 | high |
| B1 | blue | Aus gut wird besser | From good to better | "After you STOP: you can permanently remove 1 colored 2-chip or 4-chip from your cauldron. Take another 2-chip or 4-chip from the supply pile in exchange and place it in the same position." | — | 02 | high (also F4) |
| B2 | blue | Abverkauf | Sale | "If you buy 2 chips in this round, you receive the cheaper one a second time for free." | — | 04 | high |
| B3 | blue | Der weiße Segen | The white blessing | "After you STOP: If the last chip in your cauldron is white, receive as many victory points as the value indicated on that chip." | — | 17 | high (also F4) |
| B4 | blue | Der Segen der Ratten | A rat's blessing | "In this round, your purchasing power increases by twice the number of rat-tails in your cauldron." | — | 16 | high |
| B5 | blue | Eine gute Nachbarschaft | A good neighborhood | "If your cauldron has not exploded yet, you may return your white 3-chip to your bag at ANY time. If you do so, the player to your left receives 2 rubies." | — | 03 | high |
| B6 | blue | Glück im Unglück | A blessing in disguise | "If your cauldron explodes in this round, your essence increases by 2 additional spaces." | **Alchemists** | 06 | high |
| B7 | blue | Essentielle Essenz | Essential essence | "The player(s) whose essence has the highest value after the Essence Phase may roll the die once OR refill their flask." | **Alchemists** | 07 | high |
| B8 | blue | Hexenbesuch | Visit from a witch | "Immediately draw a random herb witch from the ones not currently in play. Each player may use this once in this round for free." | **Witches** | 14 | high |
| B9 | blue | Ende gut, alles gut | All's well that ends well. | "Your essence increases by the number of spaces corresponding to the value of the last chip in your cauldron." | **Alchemists** | 08 | high |
| B10 | blue | Wiedersehen macht Freude | A joyful reunion | "At the end of the round, one of your witch pennies is returned to you." | **Witches** | 05 | high |

Six cards have a symbol: 3 Witches (P7, B8, B10), 3 Alchemists (B6, B7, B9). This agrees with the
TTS deck split (F1) and with F7 ("6 cards carry an expansion symbol").

German–English pairing: F7 gives the purple pairs. The blue pairs follow from the card texts (F6
shows the German faces of B6, B7, B9, B10 and the titles match by meaning). ⚠️ The pairs B1–B5 are
by meaning of the title only (no German face seen): Aus gut wird besser = From good to better,
Abverkauf = Sale, Der weiße Segen = The white blessing, Der Segen der Ratten = A rat's blessing,
Eine gute Nachbarschaft = A good neighborhood. Each pair is the only possible one.

### 2.1 German card text (F6)

| # | German text | Status |
|---|---|---|
| B7 Essentielle Essenz | "Der/die Spieler deren Essenz nach der Essenzphase den höchsten Wert hat, dürfen 1x würfeln ODER ihre Flasche auffüllen." | complete |
| B9 Ende gut, alles gut | "Deine Essenz steigt um die Zugweite des letzten Chips in deinem Kessel." | complete |
| B10 Wiedersehen macht Freude | "Am Ende der Runde bekommst du einen deiner Hexenpfennige zurück." | complete |
| B6 Glück im Unglück | "Explodiert dein Kessel in dieser Runde, steigt deine Essenz um 2 zusätzliche Felder." | complete |
| P7 Tausch-Rausch | "Du darfst einen [dei]ner Hexenpfennige [ab]geben und dir dafür [ei]nen beliebigen Chip nehmen." | ⚠️ letters in [ ] are hidden by the next card |
| B8 Hexenbesuch | "…t eine […]erhexe, die […] im Spiel ist. […]er Spieler in […] einmal gratis […]tzen." | ⚠️ left half hidden; probably "Zieh(t) eine Kräuterhexe, die nicht im Spiel ist. Jeder Spieler in dieser Runde darf sie einmal gratis einsetzen." (our guess) |

**Important difference, B9:** the German card says "um die **Zugweite** des letzten Chips" — the
number of spaces the last chip moved (its move, "Zugweite"), not its printed value. The English card
says "the number of spaces corresponding to the value of the last chip". For most chips this is the
same. It is different for locoweed (the Zugweite comes from the locoweed book) and for a chip that
moved extra (for example a red chip after oranges, a pumpkin on Pumpkin Party). **Recommendation:**
use the German meaning (the spaces the last chip moved), because German is the original. ⚠️ Nick to
confirm.

## 3. Rules questions and engine mapping

Engine terms: `Quacks.Rules.Fortune` (card data, ids `:b1…:b11`, `:p1…:p13` today) and
`Quacks.Game.Fortune` (`auto/2` for the automatic part of a purple card, `choices/4` + `choose/4`
for the `:fortune_choice` phase, `@rats_first`, `@reveal_cards`, `@choice_cards`, and the blue hooks
`on_stop/2`, `explode_above/1`, `extra_move/2`, `die_rolls/1`, `ruby_space/2`, `refill_flasks/1`,
`potion_choices/2`). Expansion cards need a deck filter by `game.expansions` (like `Cards.ids/1`
does for solo). New ids proposed: `:ap1…:ap10`, `:ab1…:ab10` (A = Alchemists box).

General points for all cards:
- **"Rat-tails"** = the rat stone of this round (`Player.rat_stone`). "Additional rat-tails" moves the
  rat stone further. So every card that reads or changes rat tails must be in `@rats_first` (rats
  placed, then the card resolves), like Infestation and Good Start today.
- **Solo:** our solo game has no rats (rulebook.md §6). Cards that only give or use rat tails do
  nothing in solo. Cards about "the player to your left" have no target in solo.
- **"Roll the die"** = the bonus die. Reuse the P12 Take a Chance roll (`auto(g, :p12)`); `die_rolls/1`
  (Double Double) does not apply, because it is a blue card and cannot be active at the same time.
- **Yellow/purple chips from a card:** only when that book is uncovered (A7 in
  `alchemists-essences.md`, the base rulebook p. 4 in F3). `takes/2` already uses the shop.

| # | Card | Maps to | Rules questions |
|---|---|---|---|
| P1 | Spoiled for choice | `@choice_cards` + `@rats_first`: 2 options, `[:bundle, {:take, {:red, 2}}]`. Bundle = ruby +1, one die roll, rat stone +3. | Two options only (the ruby, the roll and the rats go together; the line breaks on the card confirm this). Rat stone +3 must restart `pot_index` (`move_rats/3`). If no red 2-chip is in supply: only the bundle. Solo: the bundle still gives ruby + roll (rats do nothing). |
| P2 | Ruby fever | `@reveal_cards` (like P8 Less is More): every seat draws 1 chip, gets rubies = value, chip back. Automatic, no choice. | Locoweed value? (BGG: 1 by default ⚠️). White chip: rubies = its value (1, 2, 3). Black and purple = 1. Our engine needs a "printed value" helper. |
| P3 | Give and take | `@choice_cards` like P3 Wheeling and Dealing: `{:give, n, chip}` with n ∈ {1,2,4} rubies → a chip of value n; or `:rubies2`. | Value must equal rubies given (1→1-chip, 2→2-chip, 4→4-chip) — the card lists them in the same order ⚠️. "Any colour except purple": black 1 and orange 1 allowed; white? (no player wants it; allow ⚠️). Locoweed has no printed value: not allowed (as P3 today). |
| P4 | Rich offerings | `@choice_cards` + `@rats_first`: `:rats8` (rat stone +8), `:roll4` (4 die rolls), `:droplet3`. | 4 rolls: each result applies (like B4 both count). Solo: `:rats8` is useless; keep it as an option or hide it. |
| P5 | A small donation | `auto/2` + `@rats_first`: every seat with rat stone ≥ 2 may roll once. Make it automatic (a roll has no downside ⚠️). | "At the start of a round" means this round only (BGG F3 thread: all cards are for one round). Solo: never applies → add to the solo skip list (`@solo_skip`) and redraw. |
| P6 | A rat to cherish | `@choice_cards` + `@rats_first`: `{:cherish, k}` k = 0..min(rubies, 3); rubies −k, rat stone +3k. | Solo: useless → solo skip. |
| P7 | A quick exchange | `@choice_cards`: `{:exchange, colour, chip}` for each unspent penny; or `:skip`. Spends the penny like `Witches` (sets `pennies[colour]`). | "A chip of your choice": any shop chip in supply (book rule for yellow/purple applies ⚠️). Is black allowed? The card says any ⚠️. The penny is gone: no 2 VP at the end and that witch can no longer be called. Only with Herb Witches. |
| P8 | Neighbor in need | New pattern: each seat chooses **for its left neighbour**: `:neighbour_remove_white` or `:neighbour_take`; then the left neighbour picks the chip (`{:take, chip}`) or the white 1 is removed (if the bag has one). | Who picks "a chip of their choice" — the neighbour (text: "of their choice"). Any colour/value? ⚠️ (text has no limit; use the shop chips in supply). Why would the chooser give a free chip instead of the white removal? (F8: in most cases removing a white 1 is better; it is the chooser's call.) Our choices today only touch the seat's own state: this card needs a 2-step cross-seat choice. Solo: no left player → solo skip. 2 players: the left player is the other player. |
| P9 | Useful rodent | `@choice_cards` + `@rats_first`: `{:rodent, n, chip}` n ∈ {2,4,6} rat tails → chip of value 1/2/4 (2→1, 4→2, 6→4 ⚠️ by order); rat stone −n. | Needs rat stone ≥ n. "Any colour except purple" as P3. Solo: no rats → solo skip. |
| P10 | A powerful tipple | `@choice_cards`: `{:tipple, 1, chip2}` or `{:tipple, 2, chip4}` (droplet −1 → a 2-chip, droplet −2 → a 4-chip ⚠️ by order); `:skip`. `Game.move_droplet/3` with a negative number. | The pairing 1→2-chip, 2→4-chip is our reading (the card does not say "respectively") ⚠️. Any colour (also purple? no 2/4 purple exists; yellow only with its book). The droplet cannot go below its start space ⚠️. |
| B1 | From good to better | Blue hook `on_stop/2` (new clause) → a seat choice `{:upgrade_pot, old, new}` or `:skip`, before the evaluation. | "Another 2-chip or 4-chip": same value as the removed chip, or any 2/4? Text allows any 2- or 4-chip ⚠️ (F4 players read it as a colour swap of the same value). The new chip does not trigger its draw effect (F4) and the pot is not recalculated; the end-of-round effects (green, purple) see the new chip. Explosion counts as stop (base rule p. 5: card actions are not affected by an explosion, F4). The removed chip returns to the supply. |
| B2 | Sale | Shop hook: after the second purchase, give the cheaper chip again (if in supply). | Only with exactly 2 purchases (the maximum). Equal prices: either. Limited supply: no copy left → nothing. Herb Witches C3 (buy a copy) interaction: does a free copy count as a "buy"? No ⚠️. |
| B3 | The white blessing | `on_stop/2` (or evaluation step) clause: if the last pot chip is white, VP + its value. | Explosion counts (F4: base rule p. 5, most replies). Then the last chip is almost always white. |
| B4 | A rat's blessing | Shop hook: coins + 2 × `rat_stone`. | "Rat-tails in your cauldron" = this round's rat stone. Exploded seat that takes VP does not buy: no effect. Solo: no effect → solo skip. |
| B5 | A good neighborhood | `potion_choices/2` clause (like B10 Cauldron Bubble): `:return_white3` while not exploded and a white 3 is in the pot; left neighbour + 2 rubies. | "At ANY time": also after stop, before the evaluation? We say during the potions phase until the seat is done ⚠️. The chip goes from the pot back to the bag; `pot_index` and the white sum go down (like the flask). Solo: no left player — skip or allow without the gift ⚠️. |
| B6 | A blessing in disguise | Essence hook: `reach + 2` for an exploded seat. | Cap at 10 (`Essence` uses `min(10, …)`) ⚠️. Only with Alchemists. |
| B7 | Essential essence | Essence hook after the essence phase: seat(s) with the highest essence choose `:roll` or `:refill_flask`. | Tie: every tied seat. Round 9 (essence = VP only): still applies? ⚠️ (a roll in round 9 has the normal bonus; refill has no use). Solo: the single seat is always highest → always applies. |
| B8 | Visit from a witch | New: draw a random witch of `Quacks.Rules.Witches` not in `game.witches` (with `:rand.uniform_s/2`); every seat may call her once this round **without** a penny. | Her colour gives her timing (silver/copper/gold rules in `Witches`). The extra witch leaves at round end. The free call does not spend a penny. Only with Herb Witches. |
| B9 | All's well that ends well | Essence hook: `reach + move of the last pot chip`. | German "Zugweite" (spaces moved) vs English "value" — see §2.1. Exploded pot: the last chip is white → its value. Cap at 10 ⚠️. |
| B10 | A joyful reunion | End-of-round hook: a seat with a spent penny gets one back. | Several spent: the player chooses which ⚠️ (or the engine picks if only one). None spent: nothing. After the round 9 end: the penny is worth 2 VP at game end ⚠️. |

Solo summary (proposal ⚠️): skip P5, P6, P8, P9, B4 in solo (no rats or no neighbour). Keep P1 and
P4 with the rat part doing nothing, or skip them too — Nick to decide.

## 4. Side findings

- **"A Good Start" is the 21st face on the TTS sheet** (tile 00). It is the base-game card P9 (F9),
  not an Alchemists card; the mod uses it in the base deck. Its English text on the card is:
  "Choose: Use your rat stone normally OR pass up on 1–3 rat tails and take that many rubies (1-3)
  instead." Our `Quacks.Rules.Fortune` P9 text ("move your rat marker back by 1-3 spaces and take
  that many rubies") has the same meaning.
- The base card sheet in the mod (`scratchpad/alchemists-cards/httpcloud3…734BA1CF…13452.jpg`, 23 faces +
  back) uses the **Schmidt English** titles ("A Second Chance", "Rat Infestation", "Wheel and Deal",
  "Choose Wisely", "Living in Luxury", …). `docs/research/rulebook.md` §5 uses the North Star titles
  ("Second Chances", "Infestation", "Wheeling and Dealing", …). Same cards; only the names differ.
- The Schmidt English edition calls them "chips", "rat-tails", "witch pennies", "droplet", "flask",
  "essence" — the same words as our glossary.

## 5. Gaps and what is left to try

- **German text missing for 14 cards:** P1–P6, P8–P10 and B1–B5. The 4 complete German texts (B6, B7,
  B9, B10) show that the German and English cards can differ in a detail (B9). Best next step: **a
  photo of Nick's German cards** (if his box is German), or of any German Alchemists deck.
- B8 Hexenbesuch and P7 Tausch-Rausch: German text only partly visible.
- Not tried (needs a login): BGG files 323908 (Italian card PDF) and 226141 (Japanese rules with card
  list).
