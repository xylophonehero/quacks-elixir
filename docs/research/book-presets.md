# Ingredient-book presets

Goal: 6–8 one-tap book presets for the configure screen. Compiled 2026-10-07.
⚠️ = not verified against an official source, or a design choice of this note.

## Sources

| Id | URL | What it says | Read how |
|---|---|---|---|
| S1 | https://gusandco.net/wp-content/uploads/2018/10/Quacksalber_Rules_English_v1.pdf (and 2024 rulebook, already in `ingredient-sets-and-customisation.md`) | First game Set 1, then Set 2, Set 3, Set 4. "More experienced players can also put together their own sets." | Fetched (local text copy) |
| S2 | https://cdn.1j1ju.com/medias/ab/43/c3-the-quacks-of-quedlinburg-the-herb-witches-rulebook.pdf | "Now you can choose to play with ingredient book sets 5 and 6." Replace the pumpkin book with the new one and add orange 6-chips. No other advice. | Fetched (PDF text) |
| S3 | https://www.ultraboardgames.com/the-quacks-of-quedlinburg/the-herb-witches.php | Same text as S2. No recommended mixes. | Fetched |
| S4 | https://www.schmidtspiele.de/files/Retail/72dpi_PNG/49383_Die_Alchemisten_DE.pdf | "Wir empfehlen euch die Alchemisten zunächst nur mit dem Grundspiel zu kombinieren." Locoweed books "sind keinem Set zugeordnet. Ihr dürft also jedes Narrenkraut mit jedem Set verwenden." | Fetched (PDF text) |
| S5 | German HW reviews (spieletest.at, boardgamejunkies.de, spieltroll.de) | Locoweed is only in Sets 5/6 "aus Balancegründen". Books can be freely combined. | Search snippet only |
| S6 | https://boardit.no/setup/quacks.php | Setup randomiser. Options: "Set 1 for a first game", "random set", "random book per colour". | Fetched (HTML + JS read) |
| S7 | https://boardgamegeek.com/thread/2163925/mix-sets-of-ingredients | Players mix freely; "yet to run into a bad combination"; one player uses Set 1 for new players, else random with some manual input. | Search snippet only (BGG 403) |
| S8 | https://boardgamegeek.com/thread/2227558/chosen-or-focused-ingredient-sets | Thread on themed ("focused") sets. Content not read. ⚠️ | Title only (BGG 403) |
| S9 | https://boardgamegeek.com/thread/3251920/quacks-of-quedlinburg-alchemists-that-one-book-is | Alchemists locoweed book D (sum of white values) is called overpowered. | Search snippet only (BGG 403) |
| S10 | https://boardit.no BGG thread 2746015 (randomiser feedback) | Not read. | Not read (BGG 403) |

BGG: WebFetch gives HTTP 403. The XML API (`/xmlapi2/thread?id=…`) gives "Unauthorized" (it now needs a token).
Reddit and fan sites: searches found no named community mix.

## Findings

### Base rulebook (S1)
- Only the 4 numbered sets. Order: Set 1 → 2 → 3 → 4. Then "put together your own sets".
- Confirmed: the base rulebook gives **no other recommended combinations** (matches
  `ingredient-sets-and-customisation.md` §1.2).

### The Herb Witches (S2, S3, S5)
- Adds Set 5 and Set 6 for green, blue, red, yellow, purple, black and locoweed, plus one new
  pumpkin book (orange 6-chip). The new pumpkin book replaces the base one in every HW game.
- No recommended mixes. No German "Empfehlung" beyond "Sets 5 and 6 are now available".
- ⚠️ S5: locoweed is part of Sets 5/6 only. The rulebook does not forbid locoweed with Sets 1–4.

### The Alchemists (S4, S9)
- Recommends: first combine with the base game only; add The Herb Witches later.
- The 4 locoweed books are not in a set. Any locoweed book goes with any set.
- No suggested combination. Book D is called too strong by players (S9) ⚠️.

### Community (S6–S10)
- No named community mix was found (BGG blocked; Reddit/fan sites had none).
- The common practice: Set 1 for new players, a numbered set, or a random book per colour (S6, S7).
- S6 randomiser logic (JS read): base = random set 1–4 or random 1–4 per colour. HW = random set
  1–6; with Set 5/6 it uses the same-set locoweed, else a random HW locoweed; black is base, 5 or 6
  at random. Alchemists = random set 1–4 plus an Alchemists locoweed. This matches a "Random"
  action, not a fixed preset.

## Proposed presets

Presets 1–4 and 8 are official sets. Presets 5, 6 and 7 are **designed by this note** (no
community source names them). Book effects: see `lib/quacks/rules/books.ex`.

| # | Name | Blurb | orange | green | blue | red | yellow | purple | black | locoweed | Needs | Source |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Beginner | The recommended first game. | 1 | 1 | 1 | 1 | 1 | 1 | 1 | nil | – | S1 Set 1 |
| 2 | Set 2 | Protected pots, red chips held back, chips that grow your bag. | 1 | 2 | 2 | 2 | 2 | 2 | 1 | nil | – | S1 Set 2 |
| 3 | Set 3 | Rubies on ruby spaces and a higher white limit. | 1 | 3 | 3 | 3 | 3 | 3 | 1 | nil | – | S1 Set 3 |
| 4 | Set 4 | Spend rubies to move, chip upgrades, fast yellows. | 1 | 4 | 4 | 4 | 4 | 4 | 1 | nil | – | S1 Set 4 |
| 5 | Ruby hoard | Many ways to collect rubies. | 1 | 1 | 3 | 1 | 1 | 2 | 1 | nil | – | ⚠️ designed: G1 last/next-to-last ruby, B3 ruby on ruby space, P2 tiers give rubies; R1/Y1 are the easy Set 1 books |
| 6 | Explosive | Push your luck: white chips help you, explosions hurt less. | 1 | 3 | 2 | 4 | 3 | 3 | 1 | nil | – | ⚠️ designed: B2 protects after explosion, Y3 white limit 8/9, R4 white 1s move 2, G3 rewards exactly 7 white, P3 rewards a long pot |
| 7 | Alchemists | Set 1 books with the colour-counting locoweed. | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 4 (B) | :alchemists | S4 (base + Alchemists first; any locoweed with any set); B picked ⚠️ by this note |
| 8 | Herb Witches | Set 5 with its locoweed and the new pumpkin book. | 2 | 5 | 5 | 5 | 5 | 5 | 2 | 1 | :herb_witches | S2 Set 5 (black/locoweed "Set 5" sides ⚠️ see `herb-witches.md` §1.2) |

Notes on choices:
- Alchemists: book A (3) needs the essence phase (not built yet). Book D (6) is called too strong
  (S9). C (5) is a fair second choice. B rewards a varied pot and suits Set 1.
- Herb Witches: a Set 6 preset (orange 2, colours 6, black 3, locoweed 2) is a fair swap if the
  app wants a 9th slot.
- Rubies and Explosive use base books only, so they work with no expansion.

**Random** is a separate app action, not a fixed preset: pick a random legal set per colour for
the expansions on (as S6 does), with locoweed nil unless an expansion that has locoweed is on.
