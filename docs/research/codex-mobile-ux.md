# Codex board on a phone: research and visual review

Scope: how good phone card games show a dense board, the pitfalls, a review of
our Codex board (`lib/codex_web/board.ex`, `assets/css/codex.css`), and a
priority list of changes. Date: 2026-10-17.

Screenshots: `/Users/nick/dev/quacks-elixir/docs/assets/codex-ux/`
(`<preset>-<width>.png` = the first screen, `-full.png` = the full page,
`live-*.png` = a real game against the bot at 392 px).

Source quality: there are few primary sources. Most items come from reviews
that describe the phone UI. GDC talks (Hearthstone UI, Sakamoto 2015; Marvel
Snap, Brode 2023) exist but their text was not available. "(unverified)" means
the claim was not in the source text.

---

## 1. Patterns from other games

### 1.1 Compact card states

| # | Pattern | Game | Mechanic | Source |
|---|---|---|---|---|
| P1 | Half-card hand | Hearthstone phone | Hand shows only the top half (cost, art) in the bottom-right corner. Tap the stack to fan it. | https://toucharcade.com/?p=168692 |
| P2 | Cost-only peek | Legends of Runeterra | Docked hand on the right edge. With 10 cards only the cost shows; players still know ~80 % of the hand. | https://thetechnovore.com/2020/03/11/our-hands-on-with-legends-of-runeterra-mobile/ |
| P3 | Icon-first card, text on zoom | Race for the Galaxy | Cards show icons only. Zoom adds a plain-text explanation. | https://boardgamequest.com/race-for-the-galaxy-ios-review |
| P4 | Icon + number pairs | Terraforming Mars | Each resource: stock number, production above it. Player mat shrinks to a corner. | https://www.meeplemountain.com/reviews/digital-terraforming-the-terraforming-mars-app-review/ |
| P5 | Summary banner | Through the Ages | One strip at the top: resources and production. Whole tableau fits one phone screen. | https://boardgamequest.com/through-the-ages-a-new-story-of-civilization-ios-review |
| P6 | Fold duplicates | Dominion (Temple Gates) | Same cards fold together into one stack with a count. | https://eriktwice.com/en/2024/02/02/dominion-board-game-digital-app-review/ |
| P7 | Stack same-name permanents | MTG Arena mobile | Copies stack. Warning: one copy is then hard to select (see pitfall F7). | https://draftsim.com/mtg-arena-ios/ |
| P8 | Stat colour for buffs/damage | Hearthstone, Snap | Green number = above base, red = damaged/below base. Tapped = rotated (MTGA). (unverified: common knowledge, no source text) | - |

### 1.2 Zoom and inspect

| # | Pattern | Game | Mechanic | Source |
|---|---|---|---|---|
| P9 | Two levels: tap = hand larger, hold = one full card | Hearthstone phone | Full card covers most of the screen. | https://toucharcade.com/?p=168692 |
| P10 | Double-tap to enlarge | Race for the Galaxy | Any card or role. | https://boardgamequest.com/race-for-the-galaxy-ios-review |
| P11 | Tap = inspect, not play | Legends of Runeterra | Mobile tap replaces PC right-click. | https://outof.games/devtracker/legends-of-runeterra/reddit/r-legendsofruneterra/5209 |
| P12 | Tap = bring forward, "i" = details | Terraforming Mars | First tap raises the card; "i" opens full text. | https://www.meeplemountain.com/reviews/digital-terraforming-the-terraforming-mars-app-review/ |
| P13 | Tap anything to explain it | Slay the Spire mobile | Intents, potions, relics. | https://butwhytho.net/?p=73197 |
| P14 | Everything can enlarge | Through the Ages | "Touch a card to read it." | https://theboardgameschronicle.com/2021/02/26/through-the-ages-app-review/ |

### 1.3 Zones as counters and drawers

| # | Pattern | Game | Mechanic | Source |
|---|---|---|---|---|
| P15 | Hand/battlefield toggle | MTG Arena iOS | Small toggle top-right; same for deck, graveyard, sideboard. | https://draftsim.com/mtg-arena-ios/ |
| P16 | Auto-tuck hand | MTG Arena mobile | Hand moves off screen when nothing is playable; tap to fan. | https://www.wargamer.com/magic-the-gathering-arena/android-release |
| P17 | Secondary list on its own screen | LoR Expeditions | Deck list moves out of the board. | https://thetechnovore.com/2020/03/11/our-hands-on-with-legends-of-runeterra-mobile/ |
| P18 | Log in a drawer + last action by the name | Dominion | Full log on demand; opponent's last play next to their name. | https://www.boardgamequest.com/dominion-digital-review/ |

### 1.4 Opponent area

| # | Pattern | Game | Mechanic | Source |
|---|---|---|---|---|
| P19 | Opponent as a top strip, tap to expand | Race for the Galaxy | Strip across the top; tap opens the full tableau. | https://boardgamequest.com/race-for-the-galaxy-ios-review |
| P20 | Smaller avatars | MTG Arena mobile | Avatars shrink and move to free board space. | https://www.wargamer.com/magic-the-gathering-arena/android-release |
| P21 | Tap player icon for their tableau | Through the Ages | Plus a one-tap comparison. | https://theboardgameschronicle.com/2021/02/26/through-the-ages-app-review/ |
| P22 | Summary facts per opponent | HS Battlegrounds | Leaderboard shows key facts so you do not open the board. | https://www.hearthstonetopdecks.com/patch-15-6-2-is-out-bug-fixes-android-performance-update-battlegrounds-balance-changes/ |

### 1.5 Orientation and thumb zone

| # | Pattern | Game | Mechanic | Source |
|---|---|---|---|---|
| P23 | Portrait first | Marvel Snap | Portrait, columns. (layout partly unverified) | https://www.gamerefinery.com/episode-42-marvelling-at-marvel-snap/ |
| P24 | Hand under the thumb | Hearthstone, LoR | Hand bottom-right; players ask for a left-hand mirror. | https://thetechnovore.com/2020/03/11/our-hands-on-with-legends-of-runeterra-mobile/ |
| P25 | Key actions in the centre band | Hoober touch data | Error ~7 mm at centre, ~12 mm at corners. | https://www.uxmatters.com/mt/archives/2017/07/design-for-fingers-touch-and-people-part-3.php |

### 1.6 Targets and input

| # | Pattern | Game | Mechanic | Source |
|---|---|---|---|---|
| P26 | Drag arrow, release on empty = cancel | Hearthstone | Opponent sees the arrow too. | https://hearthstone.wiki.gg/wiki/Targeted_effect |
| P27 | Playable glows, unplayable shaded | RftG, TM | Glow when you can afford and play now. | https://boardgamequest.com/race-for-the-galaxy-ios-review |
| P28 | Highlight valid targets; auto-pick a single one | general | Skip a step with no choice. (hobby blog) | https://eggbert.bearblog.dev/reconsidering-the-ui/ |
| P29 | Drag or tap: player choice | Dominion, Balatro | Both inputs work. | https://eriktwice.com/en/2024/02/02/dominion-board-game-digital-app-review/ |

### 1.7 Confirm, undo, automation

| # | Pattern | Game | Mechanic | Source |
|---|---|---|---|---|
| P30 | Undo until new info shows | Dominion | Free undo until a hidden card is revealed. | https://eriktwice.com/en/2024/02/02/dominion-board-game-digital-app-review/ |
| P31 | Confirm only permanent choices | RftG, TtA | Undo for the rest; TtA undo to end of turn. | https://boardgamequest.com/through-the-ages-a-new-story-of-civilization-ios-review |
| P32 | Batch buttons | Dominion | "Play all treasures". | https://www.boardgamequest.com/dominion-digital-review/ |
| P33 | Auto-pass with stops | MTG Arena | Client stops only when you have a legal play. | https://mtgazone.com/arena-hot-keys-and-interface-guide-simplify-your-game-with-these-easy-tricks/ |
| P34 | Show only what the decision needs; next action = "big shiny button" | Temple Gates (CEO) | Automate throwaway decisions. | https://justingarydesign.substack.com/p/theresa-duringer-ui-as-game-design |
| P35 | Dense "expert" view as an option | Twilight Struggle | Off by default; new players get overwhelmed. | https://www.pocketgamer.com/twilight-struggle/talking-twilight-struggle-the-best-board-game-youve-never-heard-of/ |

### 1.8 Feedback

| # | Pattern | Game | Mechanic | Source |
|---|---|---|---|---|
| P36 | Short animations | LoR | Riot cut animation and input-block time. | https://outof.games/legends-of-runeterra/921-riot-discusses-the-state-of-the-legends-of-runeterra-beta-mobile-balance-card-backs-card-styles-more |
| P37 | Animation + haptics | Marvel Snap | Apple Design Award 2023. | https://gameworldobserver.com/2023/06/06/apple-design-awards-2023-winners-marvel-snap-re-village |
| P38 | Sound per opponent play | Dominion | Recognise plays by ear. | https://eriktwice.com/en/2024/02/02/dominion-board-game-digital-app-review/ |

No usable source found: Shadowverse, Gwent, Spirit Island, Wingspan, Root,
Ascension, Star Realms, Card Crawl, Inscryption (no iOS port found).

---

## 2. Pitfalls on phones

| # | Pitfall | Source |
|---|---|---|
| F1 | Tap targets under 44 pt / 48 dp. Spacing does not fix a small target. | https://developer.apple.com/design/tips/ , https://support.google.com/accessibility/android/answer/7101858 , https://www.nngroup.com/articles/touch-target-size/ |
| F2 | Card text too small (Apple min 11 pt). StS Android "UI for ants". | https://www.androidcentral.com/slay-spire-android-game-week |
| F3 | Inspect view covers the board (HS long-press; Twilight Struggle card hides the map). | https://forum.quartertothree.com/t/the-bright-boardgaming-dawn-of-twilight-struggle-comes-to-a-pc-near-you/124441 |
| F4 | Inspect and commit on the same tap (StS mobile takes a relic on a read-tap). | https://www.pocketgamer.com/slay-the-spire/slay-the-spire-review-genre-defining-card-roguelike-finally-goes-mobile/ |
| F5 | Confirm/skip under the wrist or next to a destructive button (StS, Balatro "Skip"). | https://www.engadget.com/gaming/balatro-is-an-almost-perfect-mobile-port-163050971.html |
| F6 | Bottom-edge targets fight system gestures (HS opened Control Center). | https://toucharcade.com/?p=168692 |
| F7 | Stacked/overlapped items cause mis-selection (MTGA). | https://draftsim.com/mtg-arena-ios/ |
| F8 | Horizontal scroll trap on a wide battlefield (MTGA). | https://draftsim.com/mtg-arena-ios/ |
| F9 | Hidden, near-invisible controls (MTGA undo; TM "dig a while"). | https://www.commonsensemedia.org/game-reviews/terraforming-mars |
| F10 | Hover-only info. | https://makandracards.com/makandra/5117-touch-devices-mouseover-events |
| F11 | Missing state cues (turn progress, "you can do X now"). | https://www.meeplemountain.com/reviews/digital-terraforming-the-terraforming-mars-app-review/ |
| F12 | Long animations hide whose turn it is. | https://www.commonsensemedia.org/game-reviews/terraforming-mars |
| F13 | No undo. | https://www.meeplemountain.com/reviews/digital-terraforming-the-terraforming-mars-app-review/ |
| F14 | Phone treated as a small tablet. Blizzard delayed HS phone for a custom UI. | https://gamesbeat.com/blizzard-delays-hearthstone-on-smartphones-while-it-works-on-figuring-out-the-interface-on-smaller-screens/ |

---

## 3. Visual review of our board

Method: worktree app on :4122, headless Chrome (CDP 9234), DPR 2. Gallery
presets `mid-game start selected attack tech codex discard buildings log free
bot p2` at 360x780, 392x850, 1280x800. Live game against the bot at 392 px:
hire a worker, summon the hero, end the turn. Sizes below are CSS px.

### 3.1 Measured facts

- Card width `--cx-w` = 3.3rem (53 x 74 px) under 400 px; 3.6rem from 400 px.
- Full page at 392 (mid-game): ~1260 px tall. The fold (850) ends at the top of
  my patrol row. **My in-play row, command zone, piles and hand are below the
  fold.** On the first screen, my own cards are 0 % visible except the hero
  in a patrol slot.
- The opponent block takes ~520 px (61 % of 850), most of it empty (empty
  `IN PLAY` box ~200 px, empty patrol slots ~190 px, a 5-back hand ~170 px).
- Tap targets under 44 px (live, 392): `cx-end-turn` 75x28, `cx-undo` 36x28,
  `cx-log-open` 28x28, `cx-reveal` 34x22, `cx-free` 34x22, `cx-pov-*` 66x24,
  `cx-build-0` 47x19, `cx-tech-open` 101x19, `cx-act-close` 28x28,
  `cx-drawer-close` 32x32, `cx-rule-*` (Hire, Summon, Level up, Attack…) h 28,
  `cx-tech-done` h 36. Cards (53x74) pass.
- Status pill truncates: "P1 · turn 2 · main …" at 360 and 392.

### 3.2 Ratings (1 = bad, 5 = good)

| Area | Rating | Notes |
|---|---|---|
| Card-state readability | 2 | Full TTS art scaled to 53 px: card text, printed ATK/HP and the hero's level bands are unreadable. Our tokens help: `L5`, `3/4` stat pill, red damage dot, `+1` rune, `new`. The `3/4` pill is the only clear stat. Units with no token show no readable ATK/HP. Exhausted = rotate 90° (good idea, but a rotated 53x74 card in a 61 px slot clips). |
| Above the fold | 1 | See 3.1: the first screen is the opponent. My hand is ~980-1090 px down. |
| Tap targets | 2 | Every board button is 19-36 px tall (F1). Cards are OK. |
| Selected-card bar | 2 | `inspector` is a fixed bottom sheet ~200-300 px. It covers my patrol row and in-play row, so the selected card itself is often hidden (gallery `selected`, `attack`). Only a text name; no card image; one action per row; close button 28 px. |
| Opponent area | 2 | Same full layout as mine; five labelled pile boxes at full card size; no compression (P19, P22). Its hand of 5 backs uses 170 px to say "5". |
| Hand | 3 | At the bottom (good for thumb, P24) but below the fold. Fan of 6 overlapping cards at 53 px; cost readable, name barely; text not readable. Tap = select + bar, which is the right model (P11). |
| Codex / tech picker | 4 | Tech sheet is good: grouped with `×2`, 4 columns, big cards (~83 px), text readable, "Picked 1 of 2" + primary button. Codex sheet does not group duplicates (P6): 36 cards = 9 rows. Free-mode hint ("drag it out") shows in a rules game. |
| Attack targeting | 2 | "Attack…" then "Tap what to attack. Cancel" in the sheet. Targets glow (`cx-targetable`, brightness pulse + ring) but the sheet covers my side and the glow is weak on light card art. Base as a target is a small pill ring (`cx-targetable-pill`) only. No arrow or line from attacker to target; no damage preview. |
| Feedback after actions | 2 | Hire: card leaves the hand, workers 4→5, gold 4→3; no motion, no toast. Summon: hero jumps from command to in play with a `new` tag; no motion. End turn: the bot plays, then the tech sheet opens at once, so I never see what the bot did (F12 inverse: no "opponent turn" summary). The log is a plain list with no turn breaks. |
| Turn / phase indicator | 3 | Red pill + a helper line ("You can hire a worker, …") is good (F11 fixed), but the pill truncates and sits mid-page, not fixed. |
| Desktop 1280 | 4 | Two rows per side + log column works. My hand is cut at 800 px height. |

### 3.3 Other notes

- Labels `SCAV.`, `TECH.`, `LOOK.` are cryptic at phone width; the slot
  meaning is only clear on desktop.
- Empty dashed slots are full card size; 5 empty slots x 2 sides = ~380 px of
  dashes on the first screen.
- Trash sits in the centre bar at full card size; it is rarely used.
- Dev-only Tidewave "Sign in" widget covers the inspector's first button at
  bottom-left on phones (dev only, but it hides bugs in review).
- Long text: "P1's · P1 in play" in the bar repeats the seat.

---

## 4. Recommendations

Order: P1 = do first (blocks play on a phone), P2 = big gain, P3 = polish.
Files: `board.ex` = `lib/codex_web/board.ex`, css = `assets/css/codex.css`.

### P1

**R1. Mini-card for board units (`cx-mini`).**
What: under 640 px, cards on the board (patrol, in play, command) render as a
mini-card 56x64: art crop (top 60 %), cost dot top-left, a stat bar at the
bottom with ATK (left) and HP (right) as 14 px bold numbers. HP number red when
damaged ("2/4" → HP shows `2` red), ATK green when buffed, purple when -1/-1.
Level badge top-left on heroes. Exhausted: greyscale 60 % + a small "tapped"
icon; no rotation (rotation clips in a slot and wastes width).
Why: P1/P2/P3 (compact state, text on inspect), P8 (stat colour), F2.
How: new `mini/1` in board.ex next to `card/1`; `card/1` picks it by a
`@compact` flag set on board zones. CSS: `.cx-mini { width: 3.5rem; aspect-ratio: 7/8; }`,
art via `background-position: top` on the existing face image; stat bar with
`absolute inset-x-0 bottom-0 grid grid-cols-2 text-[14px] font-extrabold tabular-nums`.
Remove `.cx-card.cx-exhausted { rotate }` for minis, use `grayscale opacity-70`.
Hand and sheets keep the full card.

**R2. My side first: reorder and compress the phone layout.**
What: under 640 px the page is a fixed-height app screen (100dvh), not a long
scroll: opponent strip (top, ~120 px) → shared status bar (~44 px) → my board
(patrols + in play, scrolls inside if needed) → my hand dock (bottom, ~110 px).
Piles (codex, deck, discard, workers, trash) become counter chips.
Why: 3.1 (my hand is below the fold); P5, P19, P24, F14.
How: `page/1` and `side/1` get a `:compact` layout branch (or CSS only:
`grid grid-rows-[auto_auto_1fr_auto] h-dvh` on `.cx-table` under `max-sm`).
`mat/1` and `pile/1` render as chips under 640 px (R4).

**R3. Opponent as one compact strip (`opp_strip/1`).**
What: one row: seat badge, name, HP, gold, hand count, worker count, building
icons; under it one row of opponent mini-cards (heroes + units + patrollers,
patrol slot name as a 9 px tag on the card). Tap the strip header to open the
full opponent side in a sheet (the current `side/1`).
Why: P19, P21, P22; 3.2 opponent row (61 % of the fold, mostly empty).
How: new `opp_strip/1` in board.ex; reuse `side_header/1` for the top line and
R1 minis. `flex gap-1 overflow-x-auto snap-x` only if more than 6 units; else
wrap. Empty patrol slots of the opponent: hidden on the strip.

**R4. Tap targets ≥ 44 px.**
What: End turn, Undo, Log, Build, Tech, close buttons, rule buttons (`cx-act`,
`cx-act-rule`) min 44 px tall; visual can stay smaller with a padded hit area.
Why: F1; 3.1 measurements.
How: css `.cx-act { min-height: 44px; }` under `max-width: 1023px` (replace
the `padding: 5px 9px` rule); top-bar buttons in `top_bar/1` and centre buttons
in `center/1`: `min-h-11 min-w-11`. For tight chips use
`relative after:absolute after:-inset-2 after:content-['']`.

**R5. Selected-card bar as a peek sheet that does not hide the card.**
What: the `inspector` becomes a bottom sheet with a **peek height of ~120 px**:
a 60x84 card thumb, name, ATK/HP/level line, and a horizontal row of up to 3
primary action buttons (44 px). Drag or tap the handle to expand to full card
art + all actions + token steppers. When it opens, scroll the selected card
into the visible area above the sheet (`scrollIntoView({block: "center"})` in a
hook, or `scroll-padding-bottom` = sheet height).
Why: 3.2 selected bar; F3; P9 (two levels), P12.
How: `inspector/1` in board.ex: add `@expanded` assign and a handle button;
css `.cx-inspector { max-height: 120px }` / `.cx-inspector[data-expanded] { max-height: 75dvh }`
with `transition: max-height 200ms`. Set `scroll-padding-bottom: 140px` on the
scroll container. Add a colocated hook `.ScrollToSelected`.

### P2

**R6. Attack targeting mode with a clear field.**
What: on "Attack…", collapse the sheet to a 56 px banner at the top of my
area ("Pick a target for Flagbearer · Cancel"), dim all non-targets to 35 %
opacity, give each target a 2 px gold ring + a damage preview chip ("-2" on
the target, "-1" on the attacker if it hits back). The opponent base becomes a
large target tile in the strip (44 px+). A single legal target: still ask, but
pre-highlight it (keep the tap for intent). Optional: an SVG line from attacker
to target on hover/selection (P26).
Why: P26, P27, P28; 3.2 attack row.
How: `center/1` gets a targeting banner; css `.cx-table[data-targeting] .cx-card:not(.cx-targetable) { opacity: .35 }`;
`.cx-targetable-pill` grows to a base tile in `opp_strip/1`. Damage preview
from the engine (pure function on the game, no new state).

**R7. Piles as counter chips + drawers.**
What: codex, deck, discard, workers, trash → chips `[icon 24] 21` 44 px tall
in one row. Tap: opens the existing `drawer/1` (codex sheet, discard sheet).
Why: P15, P17, P18; 3.3 (piles at full card size).
How: `pile/1` gets a `:chip` variant; `mat/1` renders chips under 640 px.

**R8. Codex sheet groups duplicates.**
What: same as the tech sheet: one card per name with `×2`; filter tabs
"Spells / Tech I / Tech II / Tech III". Hide the "drag it out" hint unless
free mode is on.
Why: P6; 3.2 codex row.
How: reuse the grouping from `tech_sheet/1` in `drawer/1` (codex branch).

**R9. Opponent-turn summary.**
What: after the bot (or the other player) ends the turn, show a "P2's turn"
card in the strip area for ~2 s or until tapped: 3-5 lines ("Played Brick
Thief", "Attacked your base: -3", "Teched 2"). Queue the tech sheet behind it
(open it after the summary is dismissed, or show a "Tech: pick 2" button).
Also flash the changed cards (R10).
Why: P18, F12; 3.2 feedback row (tech sheet hides the bot's turn).
How: derive lines from the log entries of the last turn (no new engine
state); `drawer_after/3` in board.ex: do not auto-open `:tech` while the
summary shows.

**R10. Motion that explains state change.**
What: 150-250 ms: card flies hand → workers (hire), command → in play
(summon); HP/gold numbers tick with a short scale bump and a floating "-3";
damage dot pops in. Respect `prefers-reduced-motion`.
Why: P36, P37; 3.2 feedback.
How: CSS keyframes on `phx-mounted` (`JS.transition`) for new tokens;
FLIP hook for card moves (colocated `.CardFlip`). Keep under 250 ms (P36).

### P3

**R11. Long-press / double-tap to zoom any card.**
What: hold 350 ms on any card (board, hand, opponent) → full card at ~80 % of
screen width, release closes. Tap stays "select". Desktop keeps hover preview.
Why: P9, P10, P14; F10 (no hover on touch).
How: colocated hook `.Zoom` on `card/1`/`mini/1`; reuse `.cx-preview`.

**R12. Fixed status bar.**
What: status pill + End turn + Undo in one sticky bar (`sticky top-0` or
bottom above the hand), pill text "P1 · T2 · Main" (no truncation), helper line
collapsed to an "?" chip.
Why: F11, P34 (next action = big button).
How: `center/1`; short `phase_text/1` variants under 640 px.

**R13. Clear slot names.**
What: under 640 px show icons + 2-letter tags (SL, EL, SC, TE, LO) with the
full name in the inspector and on long-press.
Why: 3.3 cryptic labels.
How: `patrol/1` labels; `@slot_names` map.

**R14. Log with turn breaks and seat colours.**
What: group lines by turn ("Turn 2 · P1"), seat colour bar, newest at top.
Why: P18.
How: `log_list/1`.

**R15. Hide Tidewave widget in phone review shots** (dev only): hide
`#tidewave-toolbar` in the gallery frame and the live page at `w < 640`, so
screenshots show real overlaps.

---

## 5. Wireframes (392 px portrait)

### 5.1 My turn (main phase)

```
+--------------------------------------+
| <-  Codex  JQV46          [eye][=]   |  44
+--------------------------------------+
| P2 River  ♥20 ●10  ✋5 ⚒5  [T1]   v  |  opp strip header (tap = full side)
| [L3 2/4][Bloom][      ][      ]      |  opp minis 56x64
+--------------------------------------+
| ● P1 · T2 · Main     [↶]  [End turn] |  sticky, 44 px
+--------------------------------------+
| LE    EL    SC    TE    LO           |  my patrol, minis
| [L5]  [  ]  [  ]  [  ]  [  ]         |
| 3/4                                  |
| IN PLAY                              |
| [3|2/2][2|3/2+1]                     |
|                                      |
| [Cx 21][Dk 4][Dc 0][Wk 5][Tr 1][⚒T1] |  chips 44 px
+--------------------------------------+
| HAND 6  ▓▓ ▓▓ ▓▓ ▓▓ ▓▓ ▓▓            |  hand dock ~110 px
+--------------------------------------+
```

### 5.2 Attack targeting

```
+--------------------------------------+
| P2 River  [ ♥20  BASE  -2 ]          |  base = big target tile
| [L3 2/4 ◎ -2]  (dim)(dim)            |  targets ringed, others 35 %
+--------------------------------------+
| ⚔ Flagbearer attacks: pick a target  |
|                           [Cancel]   |  banner replaces the sheet
+--------------------------------------+
| (dim)  ...                           |
| IN PLAY                              |
| [▶3|2/2 selected]  (dim)             |  attacker stays visible
| ...                                  |
+--------------------------------------+
| HAND (dim)                           |
+--------------------------------------+
```

### 5.3 Opponent turn (bot)

```
+--------------------------------------+
| P2 River  ♥20 ●7  ✋4   …thinking    |
| [L3 2/4][Thief 3/2 NEW]              |  new card pulses
+--------------------------------------+
| ┌ P2's turn ─────────────────────┐   |
| │ Played Brick Thief  (-2 gold)  │   |  summary card, tap to close
| │ Attacked your base   ♥ -3      │   |
| │ Teched 2 cards                 │   |
| └──────────────[OK]──────────────┘   |
+--------------------------------------+
| my board (read-only, no glow)        |
| ...                                  |
+--------------------------------------+
| HAND 5          [Tech: pick 2 →]     |  tech waits until summary closes
+--------------------------------------+
```

---

## 6. Gallery work for these changes

Per AGENTS.md, each new state needs a story arg or preset in
`CodexWeb.Gallery` / `lib/quacks_web/gallery/stories.ex`:
`compact` (on/off), `inspector expanded`, `opp-turn summary`, `exhausted +
damaged + buffed unit` (one preset with every token on one board), `codex
grouped`. Check at 360, 392, 1280.
