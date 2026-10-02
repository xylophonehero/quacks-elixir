# Ingredient Sets 2–4 and customisation scope

Scope: base-game Almanac Sets 2, 3 and 4 for green, blue, red, yellow and purple, plus a short
scope list for customisation. Companion to `rulebook.md` (Set 1 is in §4 there).
Compiled 2026-10-02. ⚠️ = could not verify against an official source, or the sources disagree.

## Sources

- A1 Schmidt English rulebook v1 (2018, Almanac included): https://gusandco.net/wp-content/uploads/2018/10/Quacksalber_Rules_English_v1.pdf
- A2 Schmidt English "Further explanation of the ingredient books" (stand-alone Almanac, Dec 2018, newer wording): https://tesera.ru/images/items/1387218/Quack_rules-almanac_english-web-compressed.pdf
- A3 Schmidt English rulebook 2024 (page 1 has the Crow skull entry only; same wording as A2): https://www.schmidtspiele.de/files/Retail/72dpi_PNG/88220_Quack_rules_english_2024.pdf
- A4 Ultra BoardGames Almanac (same text as A2): https://www.ultraboardgames.com/the-quacks-of-quedlinburg/ingredients.php
- A5 BGG "Garden Spider Set 3 Discrepancy": https://boardgamegeek.com/thread/2166451/garden-spider-set-3-discrepancy (HTTP 403; only the search snippet was read ⚠️)
- Quackulator and Rival Quack hold Set 1 only. They have no data for Sets 2–4 (https://github.com/coreyduval/Quackulator, https://github.com/waschinski/rivalquack).

Where A1 and A2 disagree, this note uses **A2** (the newer official text, which A3 and A4 repeat).

---

## Part 1 — Ingredient Sets 2, 3 and 4

### 1.1 Prices: they DO differ per set (correction to the brief)

The brief expected the same prices as in Set 1. That is **not** correct. Each book prints its own price.
Coins for a 1 / 2 / 4-chip. Purple is a 1-chip only.

| Colour | Set 1 | Set 2 | Set 3 | Set 4 |
|---|---|---|---|---|
| Green (garden spider) | 4/8/14 | 6/11/18 | 6/11/**18** ⚠️ | 4/8/14 |
| Blue (crow skull) | 5/10/19 | 5/10/19 | 4/8/14 | 5/10/20 |
| Red (toadstool) | 6/10/16 | 4/8/14 | 5/9/15 | 7/11/17 |
| Yellow (mandrake) | 8/12/18 | 9/13/19 | 8/12/18 | 8/12/18 |
| Purple (ghost's breath) | 9 | 12 | 10 | 11 |
| Orange, black | same book in every set (3; 10) | | | |

⚠️ Green Set 3 4-chip: A1 says **21**; A2 and A4 say **18**. A5 (snippet only) says the printed
book shows 21 and the instruction text shows 18. Make it a data value. Default to 18 (A2) until
someone checks a physical book.

Engine impact: `Quacks.Rules.Chips.@prices` is one fixed map today. It must become
`price(chip, sets)` (or a per-game price map built at `Game.new`).

### 1.2 Setup and recommended combinations

- Official advice (A1, A3): first game Set 1, then Set 2, then Set 3, then Set 4. "More
  experienced players can also put together their own sets." The base rulebook gives **no other
  recommended combinations**.
- Set number = number of bookmarks printed on the book's lower edge. Books are double-sided.
- Book timing is the same for all sets: green, blue, red at the start; yellow before turn 2;
  purple before turn 3. Orange and black books are used in every game.
- The Herb Witches adds Sets 5 and 6 (see Part 2e).

### 1.3 Effects per set (A2 text, condensed; quotes where the wording matters)

Trigger key: **draw** = when the chip is drawn and placed (potions phase); **B** = evaluation
phase step B (after every player stops); **stop** = after the player stops drawing; **passive** =
a modifier for the rest of the round.

#### Green — Garden spider

| Set | Trigger | Effect |
|---|---|---|
| 2 | B | For each green chip on the last or next-to-last placed chip: green 1 → you may put an orange 1-chip in your bag; green 2 → a blue 1 **or** red 1; green 4 → a yellow 1 **or** purple 1. |
| 3 | B | If your white chips total **exactly 7**, add the values of all green chips in your pot and move your **very last chip** (any colour) that many spaces forward. (A1 says "the value of all green chips is doubled"; the result is the same.) |
| 4 | B | For each green chip on the last or next-to-last chip, you **may pay 1 ruby** to move your droplet 1 space. Max 1 ruby per green chip (so max 2). |

Notes: G2 can give a yellow or purple chip before that book is on the table ⚠️ (no ruling found;
propose: allowed). G3 changes the scoring space, so it must resolve before steps C/D.

#### Blue — Crow skull

| Set | Trigger | Effect |
|---|---|---|
| 2 | draw → passive window | A blue 1-chip protects you for the next 1 drawn chip; 2-chip for the next 2; 4-chip for the next 4. If the pot explodes inside that window, "you receive both victory points and coins for shopping". You still cannot roll the bonus die. Windows do not add up: "you get the better bonus of the blue chips, not both" (window = max(remaining, new value)). |
| 3 | draw | If the blue chip lands on a **ruby space**, take 1 ruby at once. Value does not matter. |
| 4 | draw | If the blue chip lands on a **ruby space**, score VP at once: 1 / 2 / 4 for a 1 / 2 / 4-chip. |

⚠️ B2 stacking: A1 says a 4-chip after a 2-chip covers "the remaining 3 chips" (a cap). A2/A3/A4
say it covers the next 4 (the larger window). Use A2.

#### Red — Toadstool

| Set | Trigger | Effect |
|---|---|---|
| 2 | draw → stop | Do not place the red chip; put it **beside the pot**. After you stop (by choice or explosion), you may place each set-aside red chip after your last chip, or keep it beside the pot for a later round, or return it to the bag at any time. Decide per chip. "The Evaluation Phase begins only after every player has decided." |
| 3 | draw | If the chip placed just before it is **white**, the red chip moves its value **plus that white chip's value** (red 1 after white 2 → 3 spaces). |
| 4 | passive | Once at least 1 red chip is in your pot, every white **1-chip** drawn after it moves **2** spaces. More red chips add nothing. White 2/3-chips do not change. The white 1-chip still counts as 1 for the explosion. |

Notes: R2 is the only effect whose state survives between rounds (chips beside the pot are not
in the bag). ⚠️ Whether a set-aside red chip can be placed after an explosion to improve the
scoring space: the text says "whether forced or on your own free will", so yes.

#### Yellow — Mandrake

| Set | Trigger | Effect |
|---|---|---|
| 2 | draw → next chip | "Move the next chip that you lay twice as far." (next 2-chip moves 4). Yellow value does not matter. |
| 3 | draw → passive | After your **1st** yellow chip the white limit rises from 7 to **8**; after your **3rd** yellow chip it is **9**. Yellow value does not matter. |
| 4 | draw | Your 1st / 2nd / 3rd yellow chip this round moves **+1 / +2 / +3** spaces more. The 4th and later get no bonus. Yellow value does not matter (the chip still moves its own value). |

⚠️ Y2 open questions: does "twice as far" double the red Set 1/3 bonus too? Does a yellow chip
followed by a yellow chip chain? Propose: double the full movement of the next chip, including
its own bonus; a yellow next chip doubles itself and arms the next one again.

#### Purple — Ghost's breath

| Set | Trigger | Effect |
|---|---|---|
| 2 | B | You may **discard** drawn purple chips for one tier: 1 chip → black 1-chip + 1 VP + 1 ruby; 2 chips → green 1-chip + blue 2-chip + 3 VP + droplet +1; 3 chips → yellow 4-chip + 6 VP + 1 ruby + droplet +2. One tier only (4 chips cannot be 2+2). You may trade fewer than you drew. |
| 3 | B | VP per purple chip by **pot field**: fields 0–9 → 0; 10–19 → 1; 20–29 → 2; 30+ → 3. |
| 4 | B | Count purple chips in the pot: 1 → swap one 1-chip from your pot for a 2-chip of the same colour; 2 → one 2-chip for a 4-chip; 3+ → one 1-chip for a 4-chip. One tier only; a lower tier is allowed. "The upgraded chips are put immediately into your bag" (no effect this round). |

Notes: P2 "discard" — ⚠️ assume the purple chips go back to the supply (they leave your bag).
P4: colours with no 2/4-chip (orange, black, purple, white) cannot be upgraded ⚠️ (white is not
named; propose: no white). Supply limits apply to every chip gain (G2, P2, P4).

### 1.4 Effects that reference other players

- **None of the Set 2–4 green/blue/red/yellow/purple effects compare you with other players.**
  The only cross-player chip book is black (same in every set; see `rulebook.md` §4 and §6).
- R2 only adds a **sync barrier**: evaluation waits until every player has decided about red
  chips. Solo reading: no change. With an automa, the automa has no red chips, so no wait.
- Solo reading for black stays as in `rulebook.md` §6.1 (vs. Rival Quack R-card black count) or
  §6.2 (opponent = 0).

### 1.5 Engine capabilities needed (for estimates)

Current engine (read 2026-10-02): `Potions.on_draw/3` handles yellow S1 and blue S1;
`Potions.red_bonus/2` handles red S1; `Evaluation.chip_actions/2` resolves black, green S1 and
purple S1 **with no player choice**; `@explode_above 7` is a module constant; `Chips.@prices` is fixed.

| # | Capability | Needed by | Exists? | Effort |
|---|---|---|---|---|
| C1 | Per-game set config + price lookup per set | all | no | S |
| C2 | Dispatch effects by `{colour, set}` (on-draw and phase-B tables) | all | partly (pattern match on colour) | S |
| C3 | Look at the previous placed chip | R3 (Y1 has it) | yes | S |
| C4 | Count earlier chips of a colour this round | Y4, R4 | yes (`drawn`) | S |
| C5 | Know if the landing field is a ruby field | B3, B4 | `PotTrack` has it | S |
| C6 | Per-round player modifiers: explosion limit, "next chip ×2", white-1 move +1, protection window counter | Y3, Y2, R4, B2 | no (`@explode_above` is a constant) | M |
| C7 | Explosion outcome override: VP **and** coins, no die | B2 | no (`explosion_choice` forces one) | S |
| C8 | Set-aside zone beside pot that persists across rounds (not in bag) | R2 | no | M |
| C9 | Post-stop decision step per player (place / keep / return each red), then a barrier before evaluation | R2 | no (`:done` goes straight to evaluation) | M |
| C10 | **Interactive phase B**: per-seat choices during evaluation | G2, G4, P2, P4 (and S1 purple lower tier) | no (evaluation is automatic) | L |
| C11 | Move the last chip after stop; recompute scoring space before C/D | G3 | no | S |
| C12 | Gain chips from supply into bag (with supply limits) | G2, P2, P4 | yes (`add_from_supply`) | S |
| C13 | Remove/swap chips between pot, bag and supply | P2, P4 | partly (`return_to_bag`) | S |
| C14 | Score by pot field of each chip | P3 | yes (`drawn` holds the index) | S |
| C15 | Spend rubies as an optional action in phase B | G4 | no (ruby spend is step F only) | S (falls out of C10) |

Per-chip estimate (assuming C1 + C2 are done first):

| Colour | Set 2 | Set 3 | Set 4 |
|---|---|---|---|
| Green | M (C10, C12) | S (C11) | S–M (C10, C15) |
| Blue | M (C6, C7) | S (C5) | S (C5) |
| Red | L (C8, C9) | S (C3) | S (C6) |
| Yellow | S–M (C6) | S (C6) | S (C4) |
| Purple | M (C10, C13) | S (C14) | M (C10, C13) |

Build order suggestion: C1/C2 → all "S" chips → C6 → C10 (unlocks 4 chips) → R2 last.

---

## Part 2 — Customisation scope (ideas)

Seam names refer to the current code: `Quacks.Game.new` (options), `Game.legal_actions/2`,
`Game.apply/3`, `Rules.Chips`, `Game.Potions.on_draw`, `Game.Evaluation`.

| Item | What | Seam | Effort |
|---|---|---|---|
| a | Per-colour set choice at creation (e.g. green 2, blue 1, red 3, yellow 4, purple 2) | `Game.new(sets: %{green: 2, ...})` stored on `Game`; read by `Chips.price`, `on_draw`, `Evaluation` | S once Part 1 C1/C2 exist; each set's effects are the real cost |
| b | House-rule toggles (see table below) | `Game.new(rules: %{...})`; read where the constant lives today | S each |
| c | Rival Quack automa | new non-acting seat type; hooks in `Evaluation` (black, die, rats) and end of round | M |
| d | AI players via Jev | a driver process per AI seat: read `legal_actions(g, seat)`, pick one, call `apply(g, seat, a)` | M (L for a strong bot) |
| e1 | The Herb Witches | many seams (see below) | L |
| e2 | The Alchemists | new per-player track + patients (see below) | L |
| f | Test-tube pot side | every "droplet +1" becomes a choice | M |

### (b) House-rule toggles

| Toggle | Current location | Effort | Note |
|---|---|---|---|
| Explosion limit (7 → n) | `Potions.@explode_above` | S | Make it a per-player value anyway (Y3 needs it). |
| Extra white 1-chip before turn 6 (on/off) | `Game` round-6 hook (`add_from_supply ... {:white, 1}`) | S | Official rule; toggle is a house rule. |
| Bonus die faces | `Evaluation.@die` | S | Also settles the ⚠️ 6th face (`rulebook.md` §8). |
| Black solo rule | `Evaluation.black/3` + `neighbours/2` | S | Options: opponent = 0 (§6.2), fixed n, Rival R-card (§6.1). |
| No Fortune Teller cards | deck not in engine yet | S | Free if the deck is optional from the start. |
| Rats on/off (solo) | rat stone step | S | Solo without automa has no leader. |

### (c) Solo automa "Rival Quack"

Rules are in `rulebook.md` §6.1 (Marek Tupy, levels I–III, L/R card decks). It is a "ghost seat":
no bag, no `legal_actions`, scoring space computed from droplet + L card + rats. Touches:
`Evaluation.black` (compare with R card), bonus-die eligibility (rival never rolls), rat-tail
calculation (needs track tail positions ⚠️ §8 item 2), end-of-round ruby spend and droplet growth,
final `coins div 5` VP. Fortune cards: remove two (§5 note). Effort **M**.
Sources: https://github.com/waschinski/rivalquack, https://boardgamegeek.com/filepage/174678/solo-variant

### (d) AI players via Jev

- Jev for Elixir: https://www.jev.store/projects/jev-elixir — "a GenServer ... replies with a set
  of questions, and Jev's answer comes back as a message you pattern match on"; v0.2.1 (Sept
  2026), MIT. The site describes "typed decisions" with a confidence value; it looks LLM-backed.
  ⚠️ No public API docs or GitHub URL were found; function names, cost and latency unknown.
- Fit: the engine already has the right seam. Each AI seat = a process that, when
  `legal_actions(g, seat) != []`, sends Jev the **redacted** state (own pot, own bag contents as a
  multiset, never bag order or other hidden data) plus the action list, and calls `apply/3` with
  the answer. Reject an answer that is not in the list (fallback: first legal action).
- Actions are small (draw/stop, flask, blue pick, yellow return, buy, rubies), so one typed
  "pick one of N" question per decision is enough.
- Fallback without a network: a local heuristic bot (push-your-luck by explosion probability; shop
  rules from Quackulator `MAXIMS.md`, https://github.com/coreyduval/Quackulator). Same seam.
- Effort **M** for a working bot; **L** to make it strong.

### (e1) The Herb Witches (expansion 1)

Adds a 5th player; ingredient book **Sets 5 and 6** (new texts for existing colours, e.g. red
"use the value of a higher red already in the pot", yellow "move by the value of the next drawn
chip", blue "VP if orange count ≥ blue value"); a new pumpkin book plus **orange 6-chips**; a new
ingredient, **Locoweed** (moves rat-stone distance + 1, max 4); **overflow bowls** (a pot full past
space 33 sends later chips to a bowl worth half their value in VP); and **3 herb-witch types**
(12 cards, 1 of each type per game), each usable once per game by paying a witch penny.
Fit: good. Sets 5/6 reuse Part 1 capabilities. Witches are new actions that appear in
`legal_actions` at fixed timings. Overflow changes `PotTrack` end and scoring. Effort **L** (M per
part). Source: https://cdn.1j1ju.com/medias/ab/43/c3-the-quacks-of-quedlinburg-the-herb-witches-rulebook.pdf

### (e2) The Alchemists (expansion 2)

Adds a per-player **alchemist flask board / essence track** above the pot. It advances by the
number of different colours in your potion, with extra steps for exactly 7 white and when
opponents explode. **Patients**: 3 are shown at the start, each player picks one, and it gives
powers (spend essence for rubies or chips) or end-of-round rewards by track progress. Also new
Locoweed books, extra Fortune Teller cards, and VP by flask progress at the end. Fit: moderate. It
needs a new player resource, a new evaluation step, and a patient deck. "When opponents explode"
needs a solo reading (rival: never; or ignore). ⚠️ Summary from reviews, not the rulebook. Effort **L**.
Sources: https://www.boardgamequest.com/the-quacks-of-quedlinburg-the-alchemists-expansion-review/,
https://www.nerdly.co.uk/2022/03/04/quacks-of-quedlingburg-the-alchemists-expansion-board-game-review/

### (f) Test-tube pot side (official variant)

Use the back of the pot and put a second droplet on the far-left test tube. Whenever you may move
your droplet (Fortune card, chip action, or 2 rubies), you choose which droplet moves. A test-tube
step gives the bonus printed on that glass at once: 1 ruby, 1–4 VP, or chips into your bag.
Explosion rules still apply. Seam: every `droplet + 1` in `Evaluation` (die, black, purple S1/S2,
green S4) and the ruby spend become a `{:droplet, :pot | :tube}` choice, so this depends on
interactive phase B (C10). ⚠️ The order of glass bonuses is printed on the board only and is not
in any text source; transcribe it from a board photo (`docs/assets/player-board-reference.jpg`
may show it). Effort **M**. Sources: A1 p. "Game variation", A3 p. 8.

---

## Open items (⚠️ summary)

1. Green Set 3 4-chip price: 18 (A2/A4) vs 21 (A1, reportedly the printed book).
2. Blue Set 2 window stacking: A1 (cap) vs A2 (larger window). Using A2.
3. Yellow Set 2: does the double apply to the next chip's own bonus; does it chain?
4. Purple Set 2: discarded purples go to the supply (assumed).
5. Purple Set 4 / Green Set 2: white upgrades not allowed; yellow/purple gains before their book is out allowed (assumed).
6. Red Set 2 placement after explosion is allowed (text implies it).
7. Jev API not documented publicly.
8. Test-tube glass order not transcribed.
