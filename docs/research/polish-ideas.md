# Polish ideas: make Quacks look and feel premium

2026-10-04. Design review only. No code is changed.

**What I reviewed.** Master at `ba36f22` (The Alchemists merged), from the `polish`
worktree on :4005, Chrome CDP :9223, at 390×844 and 1280×800. The branches `anim-b1`
(animation batch 1) and `art` are not merged, so I did not see them. Ideas that they
already cover say so (see `docs/research/animations.md` and `docs/research/art-assets.md`).

**Walk-through.** Lobby → configure (player count, 2 bots, all three expansion toggles,
the locoweed book picker, Options open) → game 1: 1 human + 2 bots, base game, rounds 1–3
(one explosion, shop, rubies, round results) → game 2: Herb Witches + The Alchemists +
reverse pot + locoweed III, all 9 rounds (patient choice, essence, crow skull offer,
witches sheet, test tubes, shop, game over).

**Screenshots** (`docs/assets/review/`):

| File | What |
|---|---|
| `01-lobby-phone.png` | Lobby |
| `02-configure-phone.png`, `03-configure-options-phone.png` | Configure screen, top and Options |
| `04-round-card-phone.png` | Fortune card dialog over the board |
| `05-brew-phone.png` | Brewing, white 7/7 |
| `06-explosion-phone.png` | Explosion and its choice |
| `07-round-results-phone.png` | Round results |
| `08-shop-phone.png`, `09-rubies-phone.png` | Shop (2 chips ticked), Spend rubies |
| `10-essence-phone.png` | Alchemists essence choice |
| `11-expansions-brew-phone.png` | Board with patient strip, witches, test tubes |
| `12-brew-desktop.png`, `13-expansions-desktop.png` | Desktop board, base and expansions |
| `14-game-over-phone.png`, `15-game-over-desktop.png` | Game over |

## Verdict in one paragraph

The base is good. The palette (parchment, iron, potion green, gold) is right, the
sheets move well, the book tiles and the book picker are already near "premium", and
the phone layout does not scroll. What holds it back: **the board is a wall of equal
numbers**, the one number that makes the game tense (the white total) is a small text
cell, **all the important moments look the same as the unimportant ones** (an explosion
dialog, a shop "Done" and a game-over list are all gold buttons on parchment), text does
the work that icons should do, and the screens around the game (lobby, game over) are
bare. Most fixes are S or M.

## Top 10 (impact × effort)

| # | Idea | Where | Impact | Effort |
|---|---|---|---|---|
| 1 | White **fuse meter** next to Draw | footer / stats strip | Very high | M |
| 2 | **Pot legibility**: demote coin tags, VP badges, dim used spaces, glow the next space, larger droplet and rubies | `GameComponents.pot/1` | Very high | M |
| 3 | **Phone header and players row**: no truncated names, no "You are P…" pill, helper line only when it says something | `game_live.ex` header, `player_chip/1` | High | S |
| 4 | **One primary per dialog**, real secondary style, press and disabled states in `<.button>` | `core_components.ex` `button/1`, all dialogs | High | S |
| 5 | **Explosion choice with numbers**: "Take 3 VP" / "Buy with 13 coins" | decision dialog `:explosion` | High | S |
| 6 | **Shop**: visible ingredient identity, coin glyph, round-lock badges, sticky purse + "Buy 2 · 13 coins", "Skip" as secondary | `GameLive.shop/1` | High | M |
| 7 | **Game over**: ranked podium, winner crown, VP breakdown, hide the action bar, focus "Play again" | `GameLive.game_over/1` | High | M |
| 8 | **Stats strip as icons + Kalam numerals** (laurel, ruby, flask, coins) | `GameComponents.status/1` | Medium-high | S (after `art`) |
| 9 | **Wood table**: real grain, edge vignette, hearth glow under the pot; remove the brown slab behind the pot | `app.css` body, `pot/1` `<rect>` | Medium-high | S |
| 10 | **Configure**: sticky "Start game" bar, expansions as toggle cards at the top, themed switches and radios, books as a compact grid | `render(%{game: nil})`, `setup_components.ex` | Medium-high | M |

Details for each are below, in the area sections (marked **[Top N]**).

---

## 1. Board: the pot

**[Top 2] Track numbers are noise, not information.** Today every one of the 54 spaces
has a parchment coin tag and, on most, a VP tag. At 390 px the viewBox (536 units) scales
by about 0.69, so the 14-unit coin text is ~9.7 px and the 13-unit VP text is ~9 px, in
Kalam. That is under the 11 px floor, and 100+ boxes of equal weight hide the chips.
Proposed:

- Coins: no tag box. Plain numeral on the space disc, `--color-ink` at 70 %, system
  sans 600 with `tabular-nums` (Kalam numerals are too soft below 16 px). Font-size 17
  units (~12 px on a phone).
- VP: only where VP > 0, as a small gold seal (r 9 units, `--color-gold` radial like
  `.book-seal`, ink numeral 12 units) on the lower right of the space. Gold = VP
  everywhere in the app (see §11).
- Ruby: double the gem (path scale 1.6) and give it a 1-unit white highlight facet.
  Today it is a ~6 px red dot.
- **Used spaces**: every space before the last chip drops to `opacity: 0.45`. The eye
  goes to "where am I now".
- **Next space**: the scoring ring already exists. Add a soft fill pulse there
  (`--color-gold` at 25 %, static, not looping) and show its reward as a small tag
  outside the spiral: "+12 coins · 2 VP". This answers "is one more chip worth it?"
- Groove: today `--color-potion-deep` at 45 % is almost invisible. Use 70 % and a
  2-unit inner highlight line so the spiral path reads at a glance.
- Droplet: today a ~10 px blue drop with contrast 1.07:1 (luminance) on the green brew.
  Make it 1.6× and use the art-assets redraw (radial `#7fb0ff` → `--color-droplet` →
  `#1f4fb0`, white crescent). Add a 2-unit white halo stroke.
- Rat stone: today a grey pebble at r 8. Use the rat glyph (art set) at 20 units on a
  grey disc, so it reads as "rats moved me here".

Effort M. Biggest visual win in the app.

**Chips on the pot.** Chips are flat discs with a sans numeral. Use the art-assets
chip spec: ingredient icon at 58 % of the disc, value in a parchment badge, 3 px inner
shadow at the bottom, 2 px highlight at the top (a wooden token). Give each chip a
1.5-unit drop shadow so it sits *on* the brew. Effort S after the `art` branch.

**The brown slab.** `pot/1` draws a `--color-wood` rect under the lower half of the
cauldron ("the table under the pot"). On a phone it is clipped at both sides and reads
as a rendering error; on desktop it is a rectangle behind a circle (see
`12-brew-desktop.png`). Delete it. Put a soft radial shadow under the cauldron
(`radial-gradient` ellipse, black 45 % → 0) and, as a signature touch, a faint fire
glow below it (`--color-gold` → `#d8322b` at 12 %, see §16). Effort S.

**Exploded pot.** The red rim and two crack lines are good. Add smoke: two grey blurred
circles above the rim at 30 % (static), and tint the brew from green to a dull
`#5b6b3a` so the whole pot looks spoiled, not only its rim. Effort S. (Motion is in
`anim-b1`.)

**Fortune tile in the corner.** Charming (a pinned note). On a phone it overlaps the
rim. Keep it, but rotate −4° and give it a pin dot, so the overlap looks intended.
Effort S.

**Vertical slack on phones.** At 390×844 there is ~90 px of empty wood above the pot
and ~100 px below it (`05-brew-phone.png`). Use the lower slack for the fuse meter
(below) and the "last chip" line; do not grow the pot.

## 2. Board: risk and the action bar

**[Top 1] The white total is the game, and it is a table cell.** Today it is
"White 7 / 7" in the fourth stats cell, same size as "Flask full". Proposed: a
**fuse meter** directly above Stop / Draw:

- A row of 7 notches (or `explode_above` notches) drawn as a fuse cord, 8 px high,
  full width. Each white point lights one notch: 1–4 `--color-parchment`, 5–6
  `--color-gold`, the last notch `--color-ruby`. The cherry-bomb icon at the right end.
- Left label in Kalam 18 px: "5 / 7". Right label, small: "1 safe draw left" only
  when it is true (for example, white sum 5 and only white 3s left would say "risky").
  Keep this a count of what is *in the pot*, no odds, to stay true to the board game.
- After an explosion the meter turns into the red "Exploded" banner (it replaces the
  badge in the stats strip).
- Remove the White cell from the stats strip. That frees room for coins (§3).

Effort M (component + CSS). This is the one change that makes the game feel tense.

**Buttons.** Stop is `bg-iron-dark` on `--color-wood-dark`: enabled, it looks
disabled. Draw disabled is gold at 50 % opacity: a muddy brown that looks broken
(`15-game-over-desktop.png`). Proposed:

- Stop: parchment outline button (`ring-2 ring-parchment/60`, text parchment) with a
  cork icon. It is the "safe" action, so it should look calm, not dead.
- Draw: gold with the bag icon, 56 px high, Kalam 22 px label.
- Disabled: keep the colour, drop to `saturate(0.3)`, and replace the label with why:
  "Waiting for Ulric…" or "Choose first". Never only opacity.
- After game over, hide the action bar. Show only "Show the result".

Effort S.

## 3. Header and stats strip

**[Top 3] Phone header.** "You are" + the name pill truncates to "P…" or "Play…" at
390 px (`04-round-card-phone.png`). The players row already rings your seat and says
YOU. Proposed: on phones drop the "You are" pill. The header is then: round progress,
phase pill, Books, Results, Menu.

**Round as progress.** "Round 1 / 9" is 14 px text. Use 9 small pips (6 px, gap 3 px):
done = gold, now = gold with ring, later = parchment 20 %. Round 6 and 9 pips could
carry a tiny mark (extra white chip, Stir). Effort S.

**[Top 8] Stats strip.** Four equal parchment cells, label over value, all text
("Flask full"). Proposed: one parchment bar with icon + number pairs, no labels:
laurel + VP (Kalam 22 px), ruby gem + count, coins + count (only in the shop, today a
separate gold badge), flask glyph (full: green liquid; empty: grey glass). Labels move
to `aria-label`/`title`. Effort S after the `art` icons; the VP tick/pop from `anim-b1`
then has a real number to animate.

## 4. Players row

**[Top 3, part 2]** At 390 px the `minmax(10.5rem, 1fr)` grid gives 2 + 1 cards with an
empty cell, and every name is cut ("Pla…", "Otto…", "Balt…"). The state badge
("brewing", "ready") repeats on every card, every second.

Proposed for phones (≤ 4 players): one row, equal cards, each: seat-colour disc with
the first letter (Kalam 14 px, ink), the name (2 lines allowed, 12 px), VP. State as a
16 px icon in the disc's corner: pot (brewing), cork (stopped), crack (exploded), bag
(shopping), check (ready). 5–8 players: two rows of 4. Full name and details stay in
the player sheet. Raise `min-h-9` (36 px) to 44 px for the hit area. Effort S.

**Helper line.** "Everyone brews at the same time." stays on screen all round, also
after you exploded. Show this line only when it says something new: "Waiting for
Ulric and Percival" (with the seat discs), "Stir! Everyone draws together", or
"Ear worm: 2 more". Otherwise hide it and give the row back to the pot. Effort S.

## 5. Dialogs and sheets

The sheet mechanics are good (iOS curve, `@starting-style`, bottom sheet on phones,
card on desktop). The content is not consistent.

**[Top 4] One primary per dialog.** Today the Explosion dialog has two gold buttons,
the shop has "Buy selected" and "Done" both gold, witch calls are gold, the essence
"Take space" is gold, game over has gold + black. Rule:

| Role | Style |
|---|---|
| Primary (one per dialog, last) | gold, ink text, 48 px, `shadow`, `active:scale-[0.97]` |
| Secondary | parchment-light, `ring-1 ring-ink/25`, ink text |
| Tertiary / skip | text button, ink-soft, underline on hover |
| Special (witch call) | the witch's penny colour as a 3 px left border on a secondary button |

Put the press state (`active:scale-[0.97]`, 120 ms `--ease-out`) and
`phx-click-loading:opacity-70` into `core_components.ex` `button/1`; today only the
lobby button and a few chips have a press state. Effort S.

**[Top 5] Explosion choice.** "Exploded: take the victory points" / "Exploded: buy
chips instead" does not say how much. Proposed: title "Your cauldron exploded"
with the cracked-pot icon, one line "Choose one: points or chips". Two big choice
cards side by side, each with its number: laurel "+3 VP" / coins "13 coins to spend".
No "Exploded:" prefix. Effort S (numbers come from the scoring space).

**Focus on open.** On desktop the game-over dialog opens with the focus ring on the
close ×, a big blue circle (`15-game-over-desktop.png`). Use `autofocus` on the primary
button in decision dialogs, and on the dialog itself in info sheets. Effort S.

**Titles.** Keep Kalam h2 for every dialog. Add a 24 px icon left of the title (pot,
bag, ruby, die, card, witch, flask) so each dialog is known at a glance. Remove the
repeated word in "Crow skull" title + "Crow skull drew:" box + "Crow skull: return all…"
button: title "Crow skull", box "Place one, or put all back", button "Put all back".
Effort S.

**Round results.** A long text list per seat (`07-round-results-phone.png`). Proposed:
a compact table first, one row per seat (you first): seat disc, name, `+VP` (laurel),
`+rubies` (gem), "rats next round" as a small rat icon with a count. Tap a row to open
its detail lines (today's list). The `anim-b1`/B2 replay then animates the table cells.
Effort M.

## 6. Shop

**[Top 6]** `08-shop-phone.png`. What is flat or wrong:

- On phones the ingredient name is `sr-only`; a tile is only a coloured disc + value.
  Blue, purple and black at 1× look alike. Use the ingredient icon in the disc (art
  set), and show the name once per row as a row label (Kalam 15 px, left, above the
  tiles), not per tile.
- "3c" price text. Use the `.book-coin` glyph + numeral, as in the book picker.
- Row order (orange, blue, red, yellow, black, green, purple, locoweed) differs from the
  configure order (green, blue, red, yellow, purple, orange, black, locoweed). Use one
  order everywhere (the configure order follows the box).
- Disabled tiles are 40 % opacity for two different reasons. Split them: *locked by
  round* (yellow before round 2, purple before 3) → a small lock badge "Round 2", tile
  at full colour with a hatch; *too expensive or same colour* → 40 % as today.
- "Ingredient books: green 1 · blue 1 · …" line: remove; the ⓘ buttons cover it.
- "Selected: 13 coins. Remaining: 0 of 13." and two gold buttons. Proposed: a sticky
  footer inside the sheet: a purse "13 → 0" with the coin glyph on the left, primary
  button "Buy 2 · 13 coins" on the right; "Skip buying" as a tertiary button above.
- "Your chips: 9" box is useful. Group it as a bag icon + counts, collapsed to one line.

Effort M.

**Spend rubies** (`09-rubies-phone.png`). The ruby icon is `hero-sparkles`. Use the ruby
gem. Show the two options as cards with their effect pictured: droplet +1 (a droplet
moving one space), refill flask (flask glyph). "Keep rubies" → tertiary. Effort S.

## 7. Book tiles and the book picker

Already the best-looking part (colour bar, Kalam name, gold set seal, price chips,
checked state with gold ring). Small items:

- Add the ingredient icon (40 px, ingredient colour) left of the name, as the art spec
  says. Effort S after `art`.
- The picker sheet subtitle "Locoweed. Tap a book to use it." repeats the title. Use
  "Tap a book to use it in this game." Effort S.
- "Off" seal for "Not in play" is good; give it the iron colour, not gold, so gold
  means "a book is chosen". Effort S.

## 8. Configure screen

**[Top 10]** `02-configure-phone.png`, `03-configure-options-phone.png`. 1940 px tall on a
phone. "Start game" sits above the settings, so the host can start without seeing them.

- **Sticky start bar**: "Start game" in a bottom bar (wood, 16 px padding, safe area),
  with a one-line summary: "3 players · Herb Witches · Alchemists · test tubes".
- **Expansions first**, as three toggle cards (2 columns on phones) with an icon: witch,
  patient flask, test tube. Today they are plain checkboxes inside "Ingredient books".
- **Books** as a 2-column grid of compact tiles (icon, name, set seal) on phones; tap
  opens the existing picker sheet. Today each book is a full card with the rule text,
  8 cards tall.
- **Options**: native radios render browser blue and native checkboxes. Make
  switches for booleans (track 44×26, knob parchment, on = `--color-potion`) and a
  segmented control for the 2–3 value radios (parchment-light segments, selected =
  ink text on gold). "Explodes above" and "Starting rubies" as − / + steppers like
  Players.
- "1 of 2 seated." sits in a grey filled box that looks like a disabled input. Make it a
  line of seat dots (filled = seated) with the text beside it.
- Host-only view: the read-only view for other players can stay as is.

Effort M.

## 9. Lobby hero

`01-lobby-phone.png`: a title, one gold button, "No open games. Start one." on empty
wood. First impression is "prototype".

- Hero: the cauldron icon (art set) at 120 px with the fire glow (§16) under it,
  "Quacks" in Kalam 56 px, tagline "Brew, push your luck, don't explode." 16 px
  parchment-dim.
- Two actions: "New game" (primary, as today) and "Quick solo vs 2 bots" (secondary,
  one tap into a game with saved settings).
- Open games as cards: game id in mono, seat discs (filled/empty), host name, "Join".
- Footer: icon credits line (required by CC BY) and a "How to play" link (the
  rulebook summary).

Effort S–M.

## 10. Game over

**[Top 7]** `14-game-over-phone.png`. Same list style for the winner and the last
player, "Final round buying power" on every row, × focused, disabled Stop/Draw behind.

- Title: "Ulric wins!" (or "You win!") in Kalam 32 px, with a laurel crown icon.
- Ranking as a podium for the first three (1st tallest, seat colour column, initial
  disc on top, VP in Kalam 28 px), others as rows. Your row has a gold ring.
- Under each: a thin stacked bar of where the VP came from (pot, chip actions, rubies,
  pennies, essence, final coins). The log has all the parts.
- Primary "Play again", secondary "Lobby". Hide the action bar.
- See signature moment 5 for the reveal.

Effort M.

## 11. Typography

- Kalam: keep for titles, names in results, and **big game numerals ≥ 16 px** (VP, coins,
  round, fuse count). Do not use Kalam under 14 px: the pot numbers (9–10 px) are hard
  to read in it. Small numerals: system sans 600 `tabular-nums`.
- Body: the system sans is fine. Raise the 10–11 px texts ("YOU", state badges, stat
  labels) to 12 px minimum.
- One type scale: 12 / 14 / 16 / 20 / 28 / 40. Today there are 9, 10, 11, 12, 13, 14,
  16, 18, 20, 24, 36 in use.

Effort S (tokens + a sweep).

## 12. Colour

- **Gold has too many jobs.** Primary buttons, VP, the book seals, seat 0 ("gold"), the
  ring of "you", and the Herb Witches gold penny. Seat 0 = the host = usually you, so
  your seat pill is the same colour as every primary button. Proposed: gold = action and
  VP only; change seat 0 to "amber" `#d9902f`, or start new seats at teal and give gold
  last.
- **Iron vs wood.** Iron-dark buttons and cards on wood-dark are a low-contrast pair
  (both near-black brown/grey). Use iron only for the cauldron and the sheet border;
  use parchment outline for secondary controls on wood.
- **Potion green** is good. Keep it only for the brew and for "on" switches.
- Seat colours: violet on wood-dark is 4.37:1, fine for discs; slate seat (7) on iron is
  4.97:1. All are OK as fills. Do not use them as text colours on wood.

## 13. Feedback

- Press states on all buttons (see §5). Draw also shows `phx-click-loading` (bag icon
  wobble 1 cycle, or 70 % opacity) so a slow network does not feel like a dead tap.
- Flash/toasts: none showed up in play. The Phoenix default flash will look foreign;
  restyle it as a parchment card with an iron top border, slide from the top, 3 s.
- "Copy link" → "Copied" is good; add a check icon swap.
- When a bot acts, nothing on the board says so. A static "…" after the bot's name on
  its player card while it brews is enough (`animations.md` rejected a pulse).

## 14. Accessibility

- Contrast (computed): parchment-dim on wood-dark 6.95:1, ink-soft on parchment 6.83:1,
  ink on gold 6.69:1, white on ruby 4.76:1: all pass. The droplet on the brew fails
  (1.07:1); fix with size + white halo (§1).
- Text size: pot numerals ~9 px, badges 10–11 px. See §11.
- Hit areas: player cards 36 px high (→ 44 px), pot chips are not targets (fine). Shop
  tiles 48 px, header icons 44 px: OK.
- Colour-only identity: shop tiles on phones and pot chips. Icons fix both.
- Focus: the blue 3 px ring is good; fix autofocus on the close × (§5).
- Native radios and checkboxes in Options are accessible but off-theme; keep the native
  input under the styled control (`sr-only peer`), as the shop tiles do.
- Reduced motion: the existing blocks are good; keep the same pattern for all new
  motion.

## 15. Wood background

**[Top 9]** Today: `repeating-linear-gradient(90deg, …)` vertical stripes at 23 px and
61 px. It reads as pinstripe fabric, not wood, and the stripes run vertically through
the pot. Proposed:

- An inline SVG `feTurbulence` grain as a `data:` URI: `baseFrequency="0.006 0.12"`
  (long horizontal fibres), `numOctaves="3"`, mixed at 10 % over `--color-wood-dark`.
  About 600 bytes. Horizontal, like a tabletop.
- 3–4 faint plank seams: horizontal 1 px lines `rgb(0 0 0 / 0.25)` every ~180 px with
  a 1 px highlight under each.
- Vignette: `radial-gradient(ellipse at 50% 45%, transparent 55%, rgb(0 0 0 / 0.45))`
  on a fixed `::before`.
- Hearth glow behind the pot area only: `radial-gradient` warm gold 10 % → 0.

Effort S, CSS only.

## 16. Iconography (where images replace text)

With the `art` branch icons (game-icons.net, CC BY 3.0):

| Today (text) | Replace with |
|---|---|
| Stat labels "VP", "Rubies", "Flask", "White" | laurel, ruby, flask (full/empty), cherry bomb |
| "13 coins to spend", "3c" | coin glyph + number |
| `hero-sparkles` for rubies | ruby gem |
| Player state words | pot / cork / crack / bag / check |
| Patient slot cells "1 ruby", "orange 1", "rat", "swap 1→2" | ruby, pumpkin chip, rat, two chips with an arrow |
| Patient names only | patient icon (40 px) beside the name |
| Witch cards (text header) | witch silhouette + penny disc in the header |
| Phase pill "Brewing", "Shop", "Essence" | small icon + word (keep the word) |
| Explosion choice text | cracked pot, laurel, coins |
| Chip discs (value only) | ingredient icon + value badge |
| Fortune tile (text) | card back with an eye glyph; text in the sheet |

## 17. Desktop

`12-brew-desktop.png`, `13-expansions-desktop.png`: the pot sits in a 900 px column with
wood on both sides; the right column is a long text log; the essence dots spread over
the full width.

- Three columns ≥ 1280 px: left 18 rem = other players, each with the existing small pot
  (`size={:sm}`) and VP; centre = your pot; right = log and witches. Seeing the other
  cauldrons fill up is the table feeling the game is about. Effort L.
- Cap the flask strip (essence dots) at `max-w-md`. Effort S.
- Log: group by round with sticky "Round 4" headers; chip glyphs inline instead of
  "white 1"; your lines full colour, others at 75 %. Effort M.

## 18. Five signature moments

These are rare, high-emotion moments, so delight is allowed (Emil's frequency rule).
All need a reduced-motion version (fade only). `anim-b1` already has the building
blocks (chip ids, `chip-land`, `pot-shake`, card flip, stat pop).

1. **The draw.** Tap Draw: the bag button squashes (`scale` 0.92 → 1, 160 ms spring),
   the chip flies to the spiral and hops its value (animations.md #1), and if it is
   white the fuse meter lights its notch with a spark (one 300 ms glow on the new
   notch). At the last safe notch the fuse cord gets a tiny static ember. Frequency is
   high (~90/game), so total ≤ 700 ms and never blocks the next tap.
2. **The explosion.** The pot shakes (380 ms), the brew tints to dull olive, a smoke
   puff rises from the rim, the fuse meter bursts into the red "Exploded" banner, a
   Kalam stamp "BOOM!" rotates in at −8° (scale 1.2 → 1, 240 ms) over the pot for 1 s.
   `navigator.vibrate(60)` where it exists. Then the choice cards (§5) slide up.
3. **Stop and score.** Tap Stop: a cork drops into the pot neck (CSS translate, 200 ms),
   the scoring space glows gold, and "+12" coins and "+2" VP float up from it to the
   stats strip (240 ms each, staggered 80 ms), where the numbers tick.
4. **The evaluation.** Round results open as a short stage: the bonus die rolls on the
   leader's row (stepped strip, animations.md #3), chips that pay light up in order,
   rubies fly into the counter. A "Skip" text button always.
5. **The final reveal.** Game over shows the podium empty, then reveals places from last
   to first (600 ms per place), VP ticking up in Kalam numerals; the winner's column
   rises last with the laurel crown and a short burst of gold and ruby chip glyphs
   (12 particles, 900 ms, once). "You win!" gets the burst; a loss gets a calm
   "2nd of 3, 90 VP" with your best round named.

## 19. Smaller items

| Where | Today | Change | Effort |
|---|---|---|---|
| Patient picker (`alchemists_components.ex`) | text cards, 5×2 text grid, very tall on phones | patient icon, slot grid as icons (§16), cards collapsed to name + effect, tap to expand grid | M |
| Test-tube rack | good; droplet floats above glass 0 | align the droplet to the glass centre, done glasses at 50 % (already dimmed) | S |
| Witches button on the pot (phone) | three tiny dots + "Witches" | three penny discs 14 px, spent ones with an X | S |
| Flask in the pot corner | grey round flask; glow when usable is good | liquid level per art spec; "empty" as grey glass | S |
| Bag button | count on a bag | keep; add a "+2" pop when chips are bought | S |
| Menu sheet | button row of mixed styles | list rows with icons (Log, Books, Copy link, Lobby), seed in small mono at the bottom | S |
| Round card dialog | good flip candidate | the "OK" button → "Brew!" | S |
| Waiting room for humans | text "Waiting for X to start" | seat dots + "Waiting for Nick to start" with a slow 2 s bubble icon | S |
