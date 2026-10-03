# The Alchemists (expansion 2): the new ingredient books

Scope: the new **ingredient books** of "The Quacks of Quedlinburg: The Alchemists" (Wolfgang
Warsch, Schmidt Spiele 2020; English edition 2023), and how to add them to the engine.
The essence phase and the patients are out of scope. Compiled 2026-10-03.
Read with `herb-witches.md` (locoweed Sets 5 and 6, §2.3) and `ingredient-sets-and-customisation.md`.
Text marked ⚠️ could not be verified against an official source.

Sources:
- A1 Official German rulebook "Die Alchemisten", 6 pages (text extracted; page 6 read at 250 dpi
  for the book cards and prices): https://www.schmidtspiele.de/files/Retail/72dpi_PNG/49383_Die_Alchemisten_DE.pdf
- A2 Official English rulebook (Schmidt, translation Birgit Irgang), 6 pages (text extracted; page 6
  read at 250 dpi): https://www.schmidtspiele.de/files/Retail/300dpi_JPG/88319_Alchemisten_GB_web.pdf
  (linked from https://www.schmidtspiele.de/detail/product/the-quacks-of-quedlinburg-the-alchemists.html)
- A3 BGG entry: https://boardgamegeek.com/boardgameexpansion/316597/the-quacks-of-quedlinburg-the-alchemists
- A4 Board Game Quest review: https://www.boardgamequest.com/the-quacks-of-quedlinburg-the-alchemists-expansion-review/
- A5 BGG threads (403 to the fetcher, titles and search snippets only):
  "Alchemist Locoweed Question" https://boardgamegeek.com/thread/2816276 (asks if the "return a chip"
  locoweed may return itself; answer not retrievable),
  "That one book is op!" https://boardgamegeek.com/thread/3251920 (the white-sum book is called too strong),
  "Locoweed value in over flow bowl" https://boardgamegeek.com/thread/3185663

A1 and A2 agree on every text below. Quotes are from A2 (English).

---

## 1. What the expansion adds

Components (A2 p. 1): 5 alchemist's flasks, 5 essence markers, 8 patient markers, 8 patient charts,
20 essence cards (4 per player colour, double-sided, so 8 essences), **2 ingredient books
(double-sided) for the locoweed**, 20 fortune teller cards, 40 firecracker chips (25 × 1, 10 × 2,
5 × 3) and **30 locoweed chips**. Rules (A2 pp. 2–6): a new **Essence Phase** after the Preparation
Phase and before scoring. Each player counts the colours in the pot (white not counted), +1 for
whites at exactly 7, +1 per exploded neighbour, and moves the essence marker in the flask. The
essence of the patient the player picked at setup (Nervousness, Ear worm, Carrot nose, Wing ears,
Chicken eyes, Witch's hump, Forgetfulness, Vampirism) then gives a bonus (VP, a rat tail, or a
special bonus) or an action for the next round. In round 9 the essence gives 1 VP per space. The new fortune
cards are marked: some need The Alchemists, some The Herb Witches, unmarked ones fit the base game.
The firecracker chips are **replacement white chips** ("Use the new firecracker chips to replace
your old ones when they have worn out", A2 p. 2), not extra supply.

**Out of scope for now:** the flask, essence marker, essence cards, Essence Phase, patients
("the thing with the flasks"), and the 20 new fortune cards (a later research task: which are
unmarked).

**In scope:** the 4 locoweed books (2 double-sided cards). There is **no new chip colour**: the
expansion uses the Herb Witches' locoweed, and it brings its own 30 locoweed chips, so it can be played
without The Herb Witches. There are **no new books for green, blue, red, yellow, purple, black or
orange**, and no Set 7 or 8 for them.

Set numbering (A2 p. 2, quoted): "Select one of the ingredient books for the locoweed and lay it
out ready. The ingredient books are **not assigned to a specific set**. So you can use each of the
locoweeds with each set." The cards have no set number. The numbers below (§3) are ours.

---

## 2. The four locoweed books

Common rules: the locoweed has no printed value (the engine keeps `{:locoweed, 1}` for value
lookups, as for Sets 5–6). Every book card has the header "Number of spaces to move" (German "Zugweite").
Price is one number per book (only a 1-chip exists). All four act **on draw**. The ids A–D follow the
order in A1/A2 p. 6.

| Id | Proposed set | Price | Trigger | Card text (A2 book image) |
|---|---|---|---|---|
| A | 7 | **11** | on draw (move) + essence phase | "Number of spaces to move: 1. In the Essence Phase, you may move your essence marker forward 1 ADDITIONAL space for each locoweed in your cauldron." |
| B | 8 | **16** | on draw | "Number of spaces to move: [orange + blue + red + locoweed + …] The number of spaces to move corresponds to the number of chips of different colors (including this one) in your cauldron." |
| C | 9 | **10** | on draw (move, then an optional choice) | "Number of spaces to move: 1. Return any colored chip (except a white one) from your cauldron to the bag." |
| D | 10 | **12** | on draw | "Number of spaces to move: [white + white + white …] The number of spaces to move is equal to the sum of the values of the white chips in your cauldron (but at least 1)." |

For comparison, Herb Witches locoweed: Set 5 = 8 coins, Set 6 = 10 coins (`herb-witches.md` §1.2).

### 2.1 Book A (11 coins): essence locoweed

Rulebook text (A2 p. 6): "Once you have counted the chips of each different color in your cauldron
during the Essence Phase and placed your essence marker on the appropriate space, you may move
1 additional space for each locoweed in your cauldron. For example, if you have 2 locoweeds in the
cauldron, you may move forward 3 spaces in total: 1 space because the locoweed itself is a new
color in the cauldron and 2 spaces for the two locoweed actions."

- Interactions: only with the essence phase. Without it the chip is a plain 1-mover.
- Engine note: **do not expose it** until the essence phase exists. If exposed now it would be
  `bonus/3` = 0 (moves 1) and nothing else, which is a worse locoweed 5.
- Proposed `text` (for later): "Moves 1; in the essence phase your essence marker moves 1 more space for each locoweed in your pot."

### 2.2 Book B (16 coins): one space per colour

Rulebook text (A2 p. 6): "Before you place the locoweed in your cauldron, count how many
ingredients of each different color are already in your cauldron (excluding white). The values on
the chips are irrelevant here. Then move the locoweed forward by as many spaces. Beware: If this is
your first locoweed, you may count it even though it is not in your cauldron yet."

- Move = number of distinct non-white colours in the pot, with locoweed always counted:
  `size(colours(pot) − {white} ∪ {locoweed})`. So the move is 1..8 (orange, green, blue, red, yellow,
  purple, black, locoweed). A second locoweed adds nothing new (locoweed is already there).
- Interactions: chips in the overflow bowl are not in the pot (and a locoweed drawn at the bowl
  goes into the bowl with no action, so the case cannot happen). Chips returned earlier (mandrake Y1, S3, book C)
  no longer count. Y2 doubles the whole move (the existing `next_chip_x2` path). Locoweed 6 is
  a different book, so no copy question. A red set aside (R2/R6) is not in the pot and does not
  count ⚠️.
- Engine note: a `Potions.bonus/3` clause like `{:locoweed, 5}`; `p.drawn` there does not yet hold
  the new chip. `n = p.drawn |> colours without :white |> MapSet.put(:locoweed) |> MapSet.size()`,
  returns `{n - 1, [{book, {:moves, n}}]}`. No new state.
- Proposed `text`: "Moves 1 space for each colour in your pot, white not counted and locoweed always counted (so at least 1)."
- Proposed `tiers`: none (the rule is a single formula).

### 2.3 Book C (10 coins): send a chip back

Rulebook text (A2 p. 6): "First, place the locoweed on the next free space in your cauldron.
Afterwards you may return a chip of any color (except white) to your bag. The position of all other
ingredients in the cauldron remains unchanged."

- Move 1, then **optional**: return 1 coloured pot chip to the bag. The empty space stays empty
  (as with S3 and the mandrake).
- ⚠️ May it return itself (BGG A5 asks, answer not retrieved)? The text says "any color (except
  white)"; the Forgetfulness essence explicitly says "except the locoweed", this book does not.
  Suggested reading: yes, any coloured chip including this locoweed; the next chip then counts from
  the newest chip left (`Potions.last_index/2`).
- Interactions: what is returned no longer counts in step B: green last/next-to-last (the locoweed is
  now the last chip, so only "next-to-last" can change), purple counts (P1/P2/P5), black counts,
  red Set 1 and blue Set 5 orange counts, P6 "the chip right after". The chip can be drawn again this round, with its
  action again. No white can be returned, so it cannot undo an explosion. A locoweed is not white, so it
  never explodes the pot; the choice never meets an explosion choice.
  Round 9 stir: the choice is made right after the draw, like Y6.
- Engine note: an `on_draw/4` clause for `{:locoweed, 9}` that, when the pot has a coloured chip,
  opens player phase `:chip_choice` with `chip_choices: [{:return, chip} …]` (distinct coloured
  chips in `drawn`, newest instance returned ⚠️). New `step(g, seat, {:chip, {:return, chip}})`:
  remove the newest `{chip, _}` from `drawn`, set `pot_index` via `Potions.last_index/2` (as S3),
  `Potions.return_to_bag/3`, effect `{{:locoweed, 9}, {:returned, chip}}`, then `:chip_done`.
  No new player fields.
- Proposed `text`: "Moves 1; then you may return 1 coloured chip (not white) from your pot to your bag, and the other chips stay where they are."

### 2.4 Book D (12 coins): white sum

Rulebook text (A2 p. 6): "Before you place the locoweed in your cauldron, count the values
indicated on all of the white chips in your cauldron. Then move the locoweed forward by as many
spaces. If you do not have any white chips yet, move the locoweed forward just 1 space."

- Move = sum of the **printed** values of the white chips in the pot, at least 1. With the default
  limit 7 the move is 1..7 (up to 9 with the Y3 mandrake / B5 / house rule `explode_above`).
- Interactions: the R4 "+1 for white 1-chips" is a move bonus, not a printed value: not counted.
  Whites returned (mandrake, S3, flask) no longer count. Bowl whites: not reachable (see B).
  Y2 doubles the move. BGG (A5) calls this book too strong: late in a round a locoweed moves about 6.
- Engine note: `Potions.bonus/3` clause: `n = max(1, sum of v for {{:white, v}, _} <- p.drawn)`,
  returns `{n - 1, [{book, {:moves, n}}]}`. No new state.
- Proposed `text`: "Moves as many spaces as the printed values of the white chips in your pot add up to, at least 1."

---

## 3. Sets, expansions and the configure screen

Rules facts:
- The Alchemists books are not tied to a set (A2 p. 2). Exactly **one** locoweed book is in play
  per game (the same as with The Herb Witches).
- The Alchemists can be played without The Herb Witches: the box has its own 30 locoweed chips. A2 p. 1
  recommends base game first, and combining with The Herb Witches later. A4: the expansion "plays the
  same with or without the previous expansion".
- With both expansions, all 6 locoweed books (Herb Witches Sets 5–6 and the 4 Alchemists books) are a
  free choice. There is no official rule that forbids any pair of books.

Proposal for `game.sets`:
- Keep `:locoweed` as the only key that changes. Allowed values become `nil | 5 | 6 | 8 | 9 | 10`;
  set 7 (book A) is reserved and is accepted only when the essence phase is built. Numbering is in
  A1/A2 page order so a later essence slice does not renumber anything.
- `Chips` `@prices {:locoweed, 1}` grows to `[nil, nil, nil, nil, 8, 10, 11, 16, 10, 12]`
  (index = set). `Books` gets `{:locoweed, 8..10}` (and later 7).
- Validation in `Game.sets!/2`: `{:locoweed, set} -> set in [nil, 5, 6, 8, 9, 10]`; the web
  `@extra_books` list in `setup_components.ex` likewise.
- **No expansion toggle.** Like Sets 5–6, black 5/6, orange 2 and locoweed 5/6 today, the new
  locoweed books are selectable in every game. `expansion: :herb_witches` keeps locoweed 5 as its
  default; the base default stays `nil`.
- Configure screen: the locoweed select gets the options "Not used / Set 5 / Set 6 / Colours (8) /
  Return a chip (9) / White sum (10)". Because the cards have no set number, the label should
  name the rule. The book text under the select already comes from `Books.get/1`.
- Supply (house rule `supply: :limited`): 25 locoweed with The Herb Witches. Suggested: 30 when a set
  8–10 book is chosen (the Alchemists' chips) ⚠️; the default infinite supply is not affected.
- Shop timing: unchanged, locoweed from round 1 (the same ⚠️ as `herb-witches.md` §1.2).

---

## 4. Solo reading

None of the three playable books compares players. They work solo as written. (Book A and the
essence phase's "exploded neighbour" step do compare players; out of scope.)

---

## 5. Open questions for Nick

1. Numbering: locoweed `8 | 9 | 10` (rulebook order, 7 kept for the essence book) or the simpler
   `7 | 8 | 9` (skip the essence book; it would get 10 later)?
2. Book C: may the locoweed return **itself** (my reading: yes)? And which of two equal chips
   goes back (my reading: the newest)?
3. Book D is called too strong on BGG. Ship it as written, or with a cap (for example max 4, as Set 5 has)?
