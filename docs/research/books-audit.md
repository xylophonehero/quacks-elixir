# Ingredient book texts: audit

Dated 2026-10-03. Review only; no code changed.

Audited: every entry of `Quacks.Rules.Books` in worktree `.claude/worktrees/round5`
(`lib/quacks/rules/books.ex`, with `tiers` and the fixed purple 2), 38 books.

Sources:
- R1 `docs/research/rulebook.md` §4 (Set 1).
- R2 `docs/research/ingredient-sets-and-customisation.md` §1.3 (Sets 2–4).
- R3 `docs/research/herb-witches.md` §2.3–2.5 (Sets 5–6, black 5/6, locoweed, orange 6).
- A2 Schmidt/North Star "Further explanation of the ingredient books" (Almanac PDF,
  https://tesera.ru/images/items/1387218/Quack_rules-almanac_english-web-compressed.pdf),
  fetched and text-extracted today. It agrees with R1 and R2 on every Set 1–4 text.
- H1 Herb Witches rulebook PDF (https://cdn.1j1ju.com/medias/ab/43/c3-the-quacks-of-quedlinburg-the-herb-witches-rulebook.pdf),
  fetched and text-extracted today. It agrees with R3.
- Code: `lib/quacks/game/potions.ex`, `lib/quacks/game/evaluation.ex`,
  `lib/quacks/game.ex` (`buy/4`, `give_black/2`) in the round5 worktree (potions and
  evaluation are identical to the main tree).

## Summary

| Verdict | Count | Books |
|---|---|---|
| complete | 21 | orange 1; green 1, 3, 4, 6; blue 1, 3, 4, 5, 6; red 1, 3, 4, 5; yellow 1, 3, 4, 6; purple 2, 6; locoweed 5 |
| vague | 16 | white 1; orange 2; green 2, 5; blue 2; red 2, 6; yellow 2, 5; purple 1, 4, 5; black 1, 5, 6; locoweed 6 |
| wrong | 1 | purple 3 (text is ambiguous, and the code reads it the wrong way) |

Three worst offenders:
1. **Purple 3**: "by its space" does not say which number. The Almanac means the number
   printed on the pot space; the engine uses the physical index (0–53), so it pays too
   much from index 20 up (see M1).
2. **Black 1**: one cryptic line that mixes the 2-player and 3+-player sides and says
   nothing about solo, the main mode of this app. Solo pays `rules.black_solo` for 1+ black
   chip.
3. **Purple 5**: "The VP of the spaces with a purple chip become coins to buy up to 2
   chips. Round 9: VP, 5 for 1." does not say "different colours", "now, in step B",
   "unspent coins are lost" or "never added to the shop coins".

## Text vs code mismatches (flag separately)

| # | Book | Rule (source) | Code | Kind |
|---|---|---|---|---|
| M1 | purple 3 | "purple chip in spaces 0 to 9 … 10 to 19 … 20 to 29 … 30 or higher" (A2). Pot spaces are named by their printed number ("space-2", "the last space in your pot (33)", R1 §1.1). ⚠️ No ruling names the number explicitly. | `min(div(i, 10), 3)` on the physical index `i`. Index 20 (printed 17) gives 2 VP, should give 1; index 30–44 (printed 22–29) gives 3 VP, should give 2. | **code bug** (likely). Fix: `min(div(PotTrack.at(i).coins, 10), 3)`. |
| M2 | purple 1 | "it is always possible to use a lower action"; 3+ tier: "you **may** move your droplet" (A2). | Always pays the highest tier, no choice. | minor; the top tier dominates on the front pot side, but on the reverse pot side (test tubes) the droplet is a choice. Note only. |
| M3 | black 1 (2 players) | "same number of black chips as your opponent → droplet +1" (A2). | `black_payoff(0, _) -> nil`: with 0 vs 0 nobody moves. | ⚠️ rule reading. The literal text gives both players a droplet at 0–0. Decide and document. |
| M4 | black 1 (solo) | No official solo rule. | `rules.black_solo` (default `:droplet`) for 1+ black chip. | text gap: the book does not say it. |
| M5 | black 5 (solo) | "place that black chip into the bag of the player to your left" (H1). | Solo: the chip goes back to the supply, droplet +1 still (`give_black/2`). | text gap. |
| M6 | red 6 | "you must use it this turn, even if your pot exploded" (H1). | Placed after you stop, the chip moves its value with **no action** (⚠️ house reading); placed while brewing, it acts normally. | text gap. |
| M7 | yellow 2, blue 1 | Overflow: "If this final chip triggers an action that affects the next chip drawn, this action is forfeited" (H1). Yellow 2 doubling: A2 example only doubles the value. | Y2 doubles the whole move (value + bonus); both effects are lost on the last space. | text gap. |
| M8 | locoweed 6 | "same action and value as the last colored chip" (H1). | Copies value, move bonus and on-draw action; skips earlier locoweed; stays locoweed for every count; copies no step-B action (⚠️). | text gap. |
| M9 | white | "more than 7". | Limit = max(house rule 5..9, mandrake 3, card B5). | text gap (only wrong when the house rule is not 7). |
| M10 | purple 4 | Upgrade "one 1-chip … of the same color" (A2); the pumpkin book (H1) forbids orange upgrades. | Only green, blue, red, yellow (`@p4`); old chip back to the supply. | text gap. |

No mismatch found for: green 1–6, blue 1–6, red 1–5, yellow 1, 3–6, purple 2, 5, 6,
black 6, locoweed 5. Bowl chips are not "last or next-to-last" in the engine (green,
black 5), as `herb-witches.md` §2.2 proposes.

## Book by book

Format: current text → verdict → proposed `text` → proposed `tiers` (only where useful).
"Keep" means no change.

### White, orange

| Book | Current | Verdict | Proposed text | Tiers |
|---|---|---|---|---|
| white 1 | Your pot explodes when your white chips total more than 7. | vague: limit can change; no word on what an explosion does | Your pot explodes when your white chips total more than your limit (7, unless a house rule, mandrake Set 3 or a card raises it); the chip is still placed and you must stop. | – |
| orange 1 | The chip only fills the pot. | complete | Keep. | – |
| orange 2 | Adds the orange 6-chip (22 coins). Orange chips only fill the pot. | vague: H1 "upgrades … do not apply to orange chips" missing; price repeats `prices` | Orange 1- and 6-chips only fill the pot 1 or 6 spaces; no book, witch or card can upgrade an orange chip. | – |

### Green (garden spider), all at step B

| Book | Current | Verdict | Proposed text | Tiers |
|---|---|---|---|---|
| green 1 | 1 ruby for each green chip that is your last or next-to-last chip. | complete | Keep. | – |
| green 2 | For each green chip last or next-to-last: green 1 gives an orange 1, green 2 a blue 1 or red 1, green 4 a yellow 1 or purple 1. | vague: "you may", "from the supply", "into your bag" missing | For each green chip that is your last or next-to-last chip, you may put 1 chip from the supply into your bag. | `green 1` → `orange 1`; `green 2` → `blue 1 or red 1`; `green 4` → `yellow 1 or purple 1` |
| green 3 | If your white chips total exactly 7, your last chip moves on by the sum of your green values. | complete | Optional: "…by the total value of all green chips in your pot." | – |
| green 4 | For each green chip last or next-to-last, you may pay 1 ruby to move your droplet 1 space. | complete | Keep. | – |
| green 5 | For each green chip last or next-to-last, pick a pot chip of equal or lower value: it is a first chip of the next round. | vague: "you may", locoweed = 1, order, action next round | For each green chip that is your last or next-to-last chip, you may pick a chip in your pot worth at most that green (locoweed 1); next round it is placed first, in the order you picked, with its normal action. | – |
| green 6 | Roll the bonus die once for each green chip that is last or next-to-last. | complete | Keep. | – |

### Blue (crow skull), all when placed

| Book | Current | Verdict | Proposed text | Tiers |
|---|---|---|---|---|
| blue 1 | Draw 1, 2 or 4 more chips (its value). You may place one of them; the rest go back. | complete | Keep (optional "…; it acts at once"). | – |
| blue 2 | Protects the next 1, 2 or 4 chips (its value): if your pot explodes in that window, you get both VP and coins. | vague: no bonus die; windows do not add up | Protects your next 1, 2 or 4 drawn chips (its value): if one of them explodes the pot, you still get VP and coins but no bonus die; windows do not add up, the larger one counts. | – |
| blue 3 | If it lands on a ruby space, take 1 ruby. | complete | Keep. | – |
| blue 4 | If it lands on a ruby space, score VP equal to its value. | complete | Keep. | – |
| blue 5 | If your pot has at least as many orange chips as its value, score VP equal to its value. | complete | Keep. | – |
| blue 6 | Look back at as many chips as its value: 1 ruby for each white 1-chip among them. | complete | Keep. | – |

### Red (toadstool)

| Book | Current | Verdict | Proposed text | Tiers |
|---|---|---|---|---|
| red 1 | 1 or 2 orange chips in your pot: move 1 more space. 3 or more: 2 more. | complete | Keep. | optional: `0 orange` → `no extra`; `1–2 orange` → `+1 space`; `3+ orange` → `+2 spaces` |
| red 2 | Put it beside the pot. After you stop, place it, keep it for a later round or return it to the bag. | vague: per chip; also after an explosion; placed chip moves only its value | When drawn, put it beside the pot; after you stop (also after an explosion), decide for each red chip there: place it after your last chip (it moves its value), keep it for a later round, or return it to your bag. | – |
| red 3 | Right after a white chip: move that white chip's value more. | complete | Keep. | – |
| red 4 | Once a red chip is in your pot, each white 1-chip after it moves 2 spaces (it still counts 1). | complete | Keep. | – |
| red 5 | If a higher red chip is already in your pot, move by that higher value. | complete | Keep. | – |
| red 6 | Draw one more chip and set it aside. Place it when you like; you must place it this round, even after an explosion. | vague: white still counts; no action after stop (M6) | When placed, draw 1 more chip and set it aside; place it when you like, but this round, even after an explosion (a white one still counts; placed after you stop, it has no action). | – |

### Yellow (mandrake), all when placed

| Book | Current | Verdict | Proposed text | Tiers |
|---|---|---|---|---|
| yellow 1 | Right after a white chip: you may put that white chip back in your bag. | complete | Keep. | – |
| yellow 2 | The next chip you place moves twice as far. | vague: bonus spaces doubled too; lost on the last space (M7) | The next chip you place moves twice as far, bonus spaces included (lost if this yellow is on the last space). | – |
| yellow 3 | Your 1st yellow chip raises the white limit to 8, your 3rd to 9. | complete | Keep (trigger `:passive` correct). | optional: `1st yellow` → `white limit 8`; `3rd yellow` → `white limit 9` |
| yellow 4 | Your 1st, 2nd and 3rd yellow chip this round move 1, 2 and 3 more spaces. | complete | Keep. | optional: `1st yellow` → `+1 space`; `2nd` → `+2 spaces`; `3rd` → `+3 spaces`; `4th+` → `no bonus` |
| yellow 5 | Peek at one more chip: the yellow moves on by its value (locoweed 1). The chip goes back. | vague: "peek" hides that you draw it; no word on whites | Draw 1 more chip: the yellow moves on by its value (locoweed 1), then the chip goes back to your bag with no effect, even a white one. | – |
| yellow 6 | You may pay 1 ruby to move it 3 more spaces. | complete | Keep. | – |

### Purple (ghost's breath), all at step B

| Book | Current | Verdict | Proposed text | Tiers |
|---|---|---|---|---|
| purple 1 | VP, rubies and droplet moves by the number of purple chips. | vague: no sentence; "one reward only" missing | Count the purple chips in your pot and take the one reward for that count; 4 or more count as 3. | Keep (`1 purple` → `1 VP`; `2 purple` → `1 VP · 1 ruby`; `3+ purple` → `2 VP · droplet +1`). |
| purple 2 | You may trade in 1, 2 or 3 purple chips … for one reward tier. Once per round. You may trade fewer than you drew. | complete | Keep. | Keep. |
| purple 3 | VP per purple chip by its space: 0–9 none, 10–19 1 VP, 20–29 2 VP, 30+ 3 VP. | **wrong** (ambiguous; code M1) | Each purple chip scores VP by the number printed on its space: 0–9 none, 10–19 1 VP, 20–29 2 VP, 30 or more 3 VP. | `space 0–9` → `0 VP`; `space 10–19` → `1 VP`; `space 20–29` → `2 VP`; `space 30+` → `3 VP` |
| purple 4 | Swap one chip in your pot for a bigger chip of its colour (into your bag); more purple chips, bigger swap. | vague: colours, old chip, lower tier (M10) | You may swap one green, blue, red or yellow chip in your pot for a bigger one of its colour from the supply, straight into your bag; more purple chips allow a bigger swap, a smaller one is always allowed. | Keep. |
| purple 5 | The VP of the spaces with a purple chip become coins to buy up to 2 chips. Round 9: VP, 5 for 1. | vague | Add the VP of every space with a purple chip: you may spend that sum now on up to 2 chips of different colours (it never adds to your shop coins; in round 9 each 5 gives 1 VP). | – |
| purple 6 | Each purple chip scores VP equal to the printed value of the chip right after it (locoweed 1). | complete | Keep. | – |

### Black (hawkmoth), locoweed

| Book | Current | Verdict | Proposed text | Tiers |
|---|---|---|---|---|
| black 1 | As many black chips as your opponent (more than one neighbour): droplet +1. More (than both): also 1 ruby. | vague: two sides in one line; solo missing (M3, M4) | At step B, compare your black chips with the other players' (see table). | `2 players: same count` → `droplet +1`; `2 players: more` → `droplet +1 · 1 ruby`; `3+ players: more than 1 neighbour` → `droplet +1`; `3+ players: more than both` → `droplet +1 · 1 ruby`; `solo: 1+ black` → `droplet +1` |
| black 5 | A black chip you buy goes in the left player's bag; your droplet moves 1. Step B: 1 ruby per black chip in the left pot and per black last or next-to-last in yours. | vague: cards, solo (M5) | A black chip you buy or get from a card goes into the left player's bag (solo: back to the supply) and your droplet moves 1; at step B take 1 ruby per black chip in the left player's pot and per black chip that is your last or next-to-last chip. | – |
| black 6 | The furthest black chip at the table moves its owner's droplet 1; the second furthest gives 1 ruby. | vague: ties, one player both, solo | At step B, the owner of the furthest black chip at the table moves the droplet 1 and the owner of the second-furthest takes 1 ruby; one player can get both and ties share (solo: 1 black chip gives the droplet, 2 the ruby too). | – |
| locoweed 5 | Moves your rat stone distance plus 1, at most 4. No rats: it moves 1. | complete | Keep. | – |
| locoweed 6 | Copies the move and action of the last coloured chip in your pot (white skipped). None: moves 1, no action. | vague (M8) | When drawn, it acts as the last coloured chip in your pot (white and locoweed skipped): same value, bonus move and on-draw action, but it stays locoweed for every count; no coloured chip: it moves 1 with no action. | – |

Note: `Books.get/1` text is static, so the solo row of black 1 shows the default
`black_solo: :droplet`. If the house rule is `:droplet_ruby`, the UI must swap that row (or
the row says "droplet +1 (house rule: also 1 ruby)").

## Elixir fragment (changed entries only)

Paste into `@books` (replace the existing keys):

```elixir
    {:white, 1} =>
      {:none,
       "Your pot explodes when your white chips total more than your limit (7, unless a house rule, mandrake Set 3 or a card raises it); the chip is still placed and you must stop."},
    {:orange, 2} =>
      {:none,
       "Orange 1- and 6-chips only fill the pot 1 or 6 spaces; no book, witch or card can upgrade an orange chip."},
    {:green, 2} =>
      {:step_b,
       "For each green chip that is your last or next-to-last chip, you may put 1 chip from the supply into your bag."},
    {:green, 5} =>
      {:step_b,
       "For each green chip that is your last or next-to-last chip, you may pick a chip in your pot worth at most that green (locoweed 1); next round it is placed first, in the order you picked, with its normal action."},
    {:blue, 2} =>
      {:on_draw,
       "Protects your next 1, 2 or 4 drawn chips (its value): if one of them explodes the pot, you still get VP and coins but no bonus die; windows do not add up, the larger one counts."},
    {:red, 2} =>
      {:on_draw,
       "When drawn, put it beside the pot; after you stop (also after an explosion), decide for each red chip there: place it after your last chip (it moves its value), keep it for a later round, or return it to your bag."},
    {:red, 6} =>
      {:on_draw,
       "Draw 1 more chip and set it aside; place it when you like, but this round, even after an explosion (a white one still counts; placed after you stop, it has no action)."},
    {:yellow, 2} =>
      {:on_draw,
       "The next chip you place moves twice as far, bonus spaces included (lost if this yellow is on the last space)."},
    {:yellow, 5} =>
      {:on_draw,
       "Draw 1 more chip: the yellow moves on by its value (locoweed 1), then the chip goes back to your bag with no effect, even a white one."},
    {:purple, 1} =>
      {:step_b,
       "Count the purple chips in your pot and take the one reward for that count; 4 or more count as 3."},
    {:purple, 3} =>
      {:step_b,
       "Each purple chip scores VP by the number printed on its space: 0–9 none, 10–19 1 VP, 20–29 2 VP, 30 or more 3 VP."},
    {:purple, 4} =>
      {:step_b,
       "You may swap one green, blue, red or yellow chip in your pot for a bigger one of its colour from the supply, straight into your bag; more purple chips allow a bigger swap, a smaller one is always allowed."},
    {:purple, 5} =>
      {:step_b,
       "Add the VP of every space with a purple chip: you may spend that sum now on up to 2 chips of different colours (it never adds to your shop coins; in round 9 each 5 gives 1 VP)."},
    {:black, 1} =>
      {:step_b, "Compare your black chips with the other players' (see table)."},
    {:black, 5} =>
      {:step_b,
       "A black chip you buy or get from a card goes into the left player's bag (solo: back to the supply) and your droplet moves 1; at step B take 1 ruby per black chip in the left player's pot and per black chip that is your last or next-to-last chip."},
    {:black, 6} =>
      {:step_b,
       "The owner of the furthest black chip at the table moves the droplet 1 and the owner of the second-furthest takes 1 ruby; one player can get both and ties share (solo: 1 black chip gives the droplet, 2 the ruby too)."},
    {:locoweed, 6} =>
      {:on_draw,
       "Acts as the last coloured chip in your pot (white and locoweed skipped): same value, bonus move and on-draw action, but it stays locoweed for every count; no coloured chip: it moves 1 with no action."}
```

Add to `@tiers` (purple 1, 2 and 4 stay as they are):

```elixir
    {:green, 2} => [
      {"green 1", "orange 1"},
      {"green 2", "blue 1 or red 1"},
      {"green 4", "yellow 1 or purple 1"}
    ],
    {:red, 1} => [
      {"0 orange", "no extra"},
      {"1–2 orange", "+1 space"},
      {"3+ orange", "+2 spaces"}
    ],
    {:yellow, 3} => [
      {"1st yellow", "white limit 8"},
      {"3rd yellow", "white limit 9"}
    ],
    {:yellow, 4} => [
      {"1st yellow", "+1 space"},
      {"2nd yellow", "+2 spaces"},
      {"3rd yellow", "+3 spaces"},
      {"4th+ yellow", "no bonus"}
    ],
    {:purple, 3} => [
      {"space 0–9", "0 VP"},
      {"space 10–19", "1 VP"},
      {"space 20–29", "2 VP"},
      {"space 30+", "3 VP"}
    ],
    {:black, 1} => [
      {"2 players: same count", "droplet +1"},
      {"2 players: more", "droplet +1 · 1 ruby"},
      {"3+ players: more than 1 neighbour", "droplet +1"},
      {"3+ players: more than both", "droplet +1 · 1 ruby"},
      {"solo: 1+ black", "droplet +1"}
    ]
```

The `@tiers` comment ("from `ingredient-sets-and-customisation.md` §1.3") must then name
`rulebook.md` §4 and `herb-witches.md` too. The engine fix for M1 is in
`Evaluation.chip_action(g, seat, {:purple, 3})`; the purple 3 doctest/tests then need new
numbers.

## Open decisions for Nick

1. M1: confirm "space number = printed number" for purple 3, then fix the engine.
2. M3: black 1 at 0–0 with 2 players: droplet for both (literal) or nothing (engine)?
3. M2: offer the lower purple 1 tier (only matters with the reverse pot side)?
