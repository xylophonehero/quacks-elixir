# Codex board on desktop: research and redesign

Scope: a desktop redesign (`lg:` and up, 1024 px+) of the Codex board, with
MTG Arena as the main reference. The phone layout stays as it is. Date: 2026-10-17.

Nick's feedback (verbatim): "Think we can make the ui a lot nicer though. Perhaps
focus on the desktop site for now. Lets look at magic the gathering arena for
inspiration." and "It was a little awkward to attack since I had to click the
attack button quite away from the card I selected but would like something
closer on the hover/focus of the card to be triggered."

Screenshots: `/Users/nick/dev/quacks-elixir/docs/assets/codex-desktop/`
(`g-<preset>-<width>.png` = gallery preset; `live-NN-*.png` = a real game
against the bot, branch `codex-r2`). Earlier phone review:
`docs/research/codex-mobile-ux.md`.

Source quality: WotC publishes few UX texts about Arena. Primary sources found:
official patch notes and one dev blog post. Most other facts come from guides.
"(play)" = the author's knowledge of the client; no text source found. Check
these items in the client before you copy them exactly.

---

## 1. Patterns from other games

### 1.1 MTG Arena (desktop)

| # | Pattern | What it does | Source |
|---|---|---|---|
| A1 | Zones by distance | Lands in a row near your hand and library; creatures nearer the centre; other permanents to the right of the lands; planeswalkers far right. Opponent mirrors at the top. | https://www.hipstersofthecoast.com/2018/03/how-to-play-mtg-arena-the-in-match-screen/ |
| A2 | Hand at the bottom, half off screen | Bottom halves off screen. Hover brings a card fully on screen. Blue outline = playable now. | same as A1 |
| A3 | Special-zone cards beside the hand | Cards playable from the graveyard show to the right of the hand, apart from it. | same as A1 |
| A4 | Phase strip by the avatar | Icons for untap, main 1, combat, main 2, end. Current phase is orange. Click an icon to set a stop. | same as A1; https://mtgazone.com/arena-hot-keys-and-interface-guide-simplify-your-game-with-these-easy-tricks/ |
| A5 | One big primary button, bottom right | Pass priority, confirm attackers, end turn: one button, one place. Space = pass. Shift+Enter = pass turn. | https://mtgazone.com/arena-hot-keys-and-interface-guide-simplify-your-game-with-these-easy-tricks/ ; https://draftsim.com/mtg-arena-keyboard-shortcuts/ |
| A6 | Avatar + life at the centre edge | Your avatar sits on the phase strip with life under it. Click avatar = emotes. Opponent life, hand, library, graveyard at the top. | same as A1 |
| A7 | Timer as a fuse | A fuse burns round the avatar when you are slow; timeouts show as dots + hourglass over the button. | same as A1 |
| A8 | Click to browse piles | Click graveyard or exile to see the cards; hover the library for the count. Same for the opponent. | same as A1 |
| A9 | Attack with all / select then target | "All Attack" button; with a planeswalker out it asks for a target per attacker. Select several creatures, then click their target. Click a stack's number to assign the stack. | https://devtrackers.gg/magic-arena/p/657c7027-apr-25-0-14-00-00-patch-notes ; https://devtrackers.gg/magic-arena/p/b545ab55-0-09-00-patch-notes ; https://mtgazone.com/playing-a-match/ |
| A10 | Click a creature to toggle it as an attacker | In declare attackers, a click moves the creature forward; button text counts attackers ("1 Attacker"). | patch note 0.9 (A9, label "1 Attacker"); rest (play) |
| A11 | Stack on the right | Spells and triggers stack at the right edge; hover an item to see its targets; a big stack grows to the centre. | https://mtgazone.com/playing-a-match/ |
| A12 | Auto-tap with preview | Hover or start to drag a spell: the lands it will tap light up. Undo (Z) before it resolves. | https://mtgazone.com/playing-a-match/ |
| A13 | Copies stack; split on change | Same tokens stack; a stack with the same counters stays grouped; the changed one splits off. | https://mtgazone.com/2021-03-patch-notes/ ; https://mtgarena-support.wizards.com/hc/en-us/articles/25947277047572-Patch-Notes-2024-36-10 |
| A14 | Badges on the permanent | Status shows as a graphic on the card (spellbook badge); details in "hangers" (side tooltips) on hover. | https://mtgarena-support.wizards.com/hc/en-us/articles/48215493589396-Patch-Notes-2026-58-0 ; https://mtgazone.com/2022-16-0-patch-notes/ |
| A15 | Digital breaks paper layout | Battles are sideways in paper; Arena does not show them sideways in hand or stack, because that is awkward and breaks effects. | https://magic.wizards.com/en/news/mtg-arena/we-put-battles-on-mtg-arena-what-was-that-like |
| A16 | Auto-pass, stops, full control | The client skips priority when you have no play; stops and Ctrl give control back. | https://mtgazone.com/arena-hot-keys-and-interface-guide-simplify-your-game-with-these-easy-tricks/ |
| A17 | Right-click = full card | Right-click any card for full details. | https://mtgazone.com/playing-a-match/ |
| A18 | Tapped = rotated 90°; targets = arrows; impact VFX | (play) Tapped permanents turn sideways; a targeting arrow runs from source to target; damage plays a hit effect and a floating number. | (play) |

### 1.2 Other card games and tableau apps

| # | Pattern | Game | Source |
|---|---|---|---|
| B1 | Red arrow from source to target; opponent sees it; empty space or right-click cancels; invalid target shows an error | Hearthstone | https://hearthstone.wiki.gg/wiki/Targeted_effect |
| B2 | Hero portrait is the target for face damage; UI is built round the portraits | Hearthstone | https://mein-mmo.de/en/hearthstone-weg-zum-megahit063,32034/ ; GDC 2015 talk https://gdcvault.com/play/1022036/Hearthstone-How-to-Create-an |
| B3 | Drag units into an attack lane, then commit with one button; undo the drag to cancel | Legends of Runeterra | https://outof.games/devtracker/legends-of-runeterra/reddit/r-legendsofruneterra/6495 |
| B4 | Drag an enemy in front of your unit to choose the block (Challenger) | Legends of Runeterra | https://invenglobal.com/articles/9639/guide-what-is-challenger-in-legends-of-runeterra |
| B5 | Few big zones (3 locations), your cards under, opponent's above; retreat bottom-left, snap top | Marvel Snap | https://marvelsnapzone.com/retreating/ ; https://marvelsnapzone.com/snapping/ |
| B6 | Icon cards; zoom adds plain text; opponent tableau as a strip | Race for the Galaxy app | https://boardgamequest.com/race-for-the-galaxy-ios-review |
| B7 | One summary strip for resources; touch any card to read it | Through the Ages app | https://boardgamequest.com/through-the-ages-a-new-story-of-civilization-ios-review ; https://theboardgameschronicle.com/2021/02/26/through-the-ages-app-review/ |
| B8 | Opponent's last play by their name; full log in a drawer | Dominion (Temple Gates) | https://www.boardgamequest.com/dominion-digital-review/ |
| B9 | "Big shiny button" for the next action; automate throwaway choices | Temple Gates | https://justingarydesign.substack.com/p/theresa-duringer-ui-as-game-design |
| B10 | Short animations; cut input-block time | Legends of Runeterra | https://outof.games/legends-of-runeterra/921-riot-discusses-the-state-of-the-legends-of-runeterra-beta-mobile-balance-card-backs-card-styles-more |

### 1.3 Contextual actions and accessibility

| # | Pattern | Use | Source |
|---|---|---|---|
| C1 | Drag needs a single-pointer alternative (WCAG 2.2 SC 2.5.7, AA): click source, then click target | Every drag in this doc has a click path | https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements |
| C2 | Content on hover or focus must be dismissible (Esc), hoverable, persistent (SC 1.4.13) | Action chips and zoom | https://www.w3.org/WAI/WCAG22/Understanding/content-on-hover-or-focus.html |
| C3 | `:focus-visible` shows a ring for keyboard focus only | Card focus ring | https://developer.mozilla.org/en-US/docs/Web/CSS/:focus-visible |
| C4 | `:focus-within` keeps a child menu open while focus is inside | Chips stay open when you Tab into them | https://developer.mozilla.org/en-US/docs/Web/CSS/:focus-within |
| C5 | Pointer events + `setPointerCapture` for a custom drag (no HTML5 DnD ghost image) | Attack arrow | https://developer.mozilla.org/en-US/docs/Web/API/Element/setPointerCapture |
| C6 | Hover-only info fails on touch | Keep the right panel and phone sheet | https://makandracards.com/makandra/5117-touch-devices-mouseover-events |
| C7 | Radial menus | Rejected: they cover the card art and the neighbours, and need JS placement. Chips in a row are simpler. | (design choice) |
| C8 | Right-click menus | Rejected as primary: hidden (F9 in the phone review). Keep right-click = cancel (B1). | https://hearthstone.wiki.gg/wiki/Targeted_effect |

---

## 2. Our board now (desktop)

Method: worktree app on :4122, headless Chrome on CDP 9234, DPR 1. Gallery
presets at 1280x800, 1440x900, 1920x1080. Live game against the bot at 1440x900
(game RMKPX): hire Bloom, summon Troq Bashar, play Timely Messenger, drag Troq
to Squad leader, attack the base with the Messenger, end turn, tech 2, Troq
attacks River Montoya.

### 2.1 Measured facts

- Layout: `.cx-layout` is a 2-column grid, board + 18-20rem right column
  (`cx-a-sheet`: inspector, "How to play", log). Width cap `max-width: 90rem`.
  At 1920 the board stays 1440 wide with 240 px of empty space each side
  (`g-mid-game-1920.png`); no card gets bigger.
- Card sizes at 1440: my board mini-card 80x91; opponent mini-card 68x78; hand
  card 94x125; opponent hand backs 50x66. The hover zoom is ~272x380 (good).
- Height: at 1280x800 the page is 842 px; the hand is cut by 42 px
  (`g-mid-game-1280.png`, `live-14-turn2-1280.png`). At 1440x900 it fits with
  ~80 px to spare.
- Empty space: 10 empty dashed patrol slots and 2 big empty "IN PLAY" boxes
  take ~45 % of the board area in a normal turn. The opponent's 5 card backs
  use a 780x90 box to say "5".
- **Attack, measured** (`live-07`, `live-08`): the selected Messenger is at
  (788, 515). The "Attack…" button is in the right column at (1151, 432):
  ~370 px away. After the click a banner and a base tile come in and push my
  side ~100 px down, so the card moves under the pointer. The base target is
  at (550, 130): ~420 px further. One attack = 3 clicks, ~800 px of pointer
  travel, 1 layout jump. This is Nick's complaint.
- Targets: the base shows as a yellow banner "Attack the base of P2" only
  during a pick. The base HP is a 19x20 px heart number in the side header at
  all other times. There is no arrow from attacker to target and no damage
  preview.
- Opponent turn: the "P2's turn" summary card goes into the grid between the
  status bar and my side. It pushes my side and hand ~216 px down; at 1440x900
  my hand goes off screen (`live-11-opp-turn-summary-1440.png`). Before that,
  the tech sheet opens on top of the bot's result (`live-10`).
- Keyboard: board cards are `<div phx-click>` with no `tabindex` and no role;
  `codex.css` has no `:focus-visible` rule. A keyboard user cannot select a
  card.
- Exhausted: grey + dim + a small ↻ icon (`live-13`). No rotation. Clear
  enough, but weaker than Arena's sideways card (A18).
- Motion that exists: FLIP flight for a card that changes zone, a bump and a
  floating "+1/−1" on numbers, hover lift of a hand card (~15 px), a 500 ms
  hover zoom beside the board. No combat motion: an attack only changes
  numbers.
- Dev only: the Tidewave "Sign in" widget covers the bottom-left corner.

### 2.2 Ratings against Arena (1 = bad, 5 = Arena level)

| Area | Score | Notes |
|---|---|---|
| Overall layout | 2 | A web page of boxes with labels (SQUAD LEA…, COMMAND, HAND · 5), not a table. Two equal panels; no centre battlefield; right column eats 22 % of the width. |
| Use of screen | 2 | Cap at 1440; cut at 1280x800; cards do not grow on 1920. |
| Card readability | 3 | Mini-card stat pills (ATK/HP, red when hurt, green when up) and level badge are good. Names truncate. |
| Hand | 3 | Fan, hover lift and zoom work. The hand sits in a full-width box with a label; Arena lets it run off the bottom edge. |
| Hover zoom | 4 | Big, crisp, shows on the far side. 500 ms is a little slow (Arena: instant on hover). |
| Attack flow | 1 | See 2.1. Action far from the card; layout jump; no arrow. |
| Targeting feedback | 2 | Glow ring on targets, dim on the rest. No arrow, no preview, base is a banner. |
| Primary button / phase | 3 | Yellow "End turn" is clear but mid-screen and moves when banners come in. Phase is a text pill; no ladder. |
| Base / workers / gold | 2 | Base HP is the key number of the game and it is the smallest. Workers are a pile counter. |
| Buildings | 2 | "Tech I" chip in a wide empty COMMAND box; build in a modal. Buildings are not targets on the board. |
| Opponent turn | 2 | Text summary pushes my side down; no replay of what moved. |
| Log | 2 | Plain list, newest first, no turn breaks, no card links. |
| Keyboard / a11y | 1 | Cards not focusable. |
| Motion and impact | 2 | Good FLIP base, but no attack lunge, hit, death or base-hit effects. |

---

## 3. The primary interaction: act on the card

### 3.1 Recommendation

**Drag a ready unit onto its target, with a live SVG arrow. Fallback: click the
unit, then click an action chip on the card, then click the target.** One
model for attacks, targeted abilities, targeted spells, patrol and play.

Why: Hearthstone's arrow is the clearest target signal in the genre (B1) and
the action starts where the eye is (Nick's ask). The click path meets WCAG
2.5.7 (C1) and keeps phone play the same (tap card → sheet). Arena's
"select, then click target" (A9) is the same click path.

### 3.2 States of a board card at `lg:`

| State | Look | Input |
|---|---|---|
| Idle, can act | Thin gold ring + small sword pip top-right (A2 "playable" outline) | Hover or focus: chips show |
| Hover / focus | Lift 4 px, chips row over the top edge of the card | Press and move > 6 px: arrow drag. Click: select |
| Selected | Ring stays, chips stay (no hover needed) | Click a chip, or press its key |
| Aiming | Arrow from card centre to pointer; legal targets lit, rest dim to 40 % | Click or release on a target = act. Esc, right-click, click on empty = cancel |
| Exhausted | Rotate 90° on desktop only (A18), grey 30 % | No chips except info |

### 3.3 Action chips

- A row of 1-3 round buttons, 32 px (`size-8`), on the top edge of the card,
  centred, `-translate-y-1/2`. Icon + `aria-label` + tooltip with the key.
  Example for a ready hero: ⚔ Attack (A), ⬆ Level up (L), ⛨ Patrol (P);
  "…" opens the full list in the right panel.
- Chip with one legal target: the chip acts at once and says so in its label
  ("Attack River Montoya"). The squad leader rule (codex.md §9) makes this
  common. Chip with several targets: it starts aiming.
- Show rule: `lg:` only. Visible on `:hover`, `:focus-within` and
  `.cx-selected`. Pure CSS (Tailwind `group`, `lg:group-hover:flex`,
  `lg:group-focus-within:flex`, `lg:group-[.cx-selected]:flex`). Hidden on
  phones (`max-lg:hidden`): the phone keeps the bottom sheet.
- Data: the server already builds `Moves.buttons/2` per card. Render them for
  every card with actions, not only the selected one (cost: one list per
  card; at most ~12 cards).

### 3.4 Same model for the rest

| Action | Drag | Click path | Chip |
|---|---|---|---|
| Attack | Unit → target (arrow) | Unit → ⚔ → target | ⚔ |
| Targeted ability | Unit → target (arrow, ability colour) | Unit → ability chip → target | icon per ability, label from `Moves.ability_label/1` |
| Untargeted ability, level up | none | Unit → chip | ✦ / ⬆ |
| Patrol | Unit → slot (exists: HTML5 DnD, `Moves.drop/4`) | Unit → ⛨ → slot lights → click slot | ⛨ |
| Sideline | Patroller → battlefield (exists) | ⛨̸ chip | ⛨̸ |
| Play from hand | Card → battlefield (exists); targeted spell then aims an arrow from the dropped card | Card → ▶ Play / ⚒ Worker chip | ▶, ⚒ |
| Summon | Hero in command → battlefield (exists) | Hero → ⬇ Summon | ⬇ |

### 3.5 LiveView fit

- Server: each actionable card gets `data-targets` (space-separated DOM ids
  of legal targets, from `Moves.options/3`) and `data-act` (targeting key).
  No round trip to start aiming.
- Client: extend the existing `.CodexTable` colocated hook. Add one
  `<svg id="cx-arrow" phx-update="ignore">` fixed overlay (`pointer-events:
  none`). `pointerdown` on `[data-targets]` + move > 6 px → `setPointerCapture`
  (C5), draw a quadratic path from source centre to pointer, snap the head to a
  hovered target's centre. `pointerup` on a target → `pushEvent("aim", {id,
  key, target})`; the server checks legality as now (`pick/2`). The hook adds
  `.cx-lit` / `.cx-dim` classes only; it never decides what is legal.
- Keep HTML5 DnD for hand → zone (it works). Do not start an arrow on a card
  with no `data-targets`, so the two drags do not fight. Later: move both to
  pointer events (one drag code path).
- Click path: the chip sends `phx-click="rule"` (exists) and the server sets
  `@targeting` (exists). The hook draws the arrow from the selected card to the
  pointer while `data-targeting="true"`. No new server state.
- Keyboard: cards become `<button>` (or `role="button" tabindex="0"`), Enter =
  select, A/L/P = chips, Tab/arrow keys move through lit targets, Enter acts,
  Esc cancels (`phx-window-keydown` exists for Escape). Focus ring:
  `focus-visible:ring-2 ring-amber-300 ring-offset-2 ring-offset-stone-950`.
- Reduced motion: arrow still draws (it is information), no wobble.

---

## 4. Recommendations

Files: `board.ex` = `lib/codex_web/board.ex`, `moves.ex` =
`lib/codex_web/moves.ex`, css = `assets/css/codex.css`, gallery =
`lib/codex_web/gallery.ex`. Every desktop change goes under `lg:` (1024 px)
or `@media (min-width: 1024px)`. Phone rules (`max-lg:`) do not change. Add a
gallery preset per new state (AGENTS.md).

### P1 (do first)

**R1. Action chips on the card (fixes Nick's complaint). Size M.**
What: §3.3. Remove the far "Attack…" step for the common case.
Why: Nick; B1; Arena select-then-target (A9).
How: new `card_chips/1` component in board.ex, rendered inside `mini/1` and
`card/1` when the card has buttons; `group relative` on `.cx-mc`; chips
`absolute left-1/2 top-0 -translate-x-1/2 -translate-y-1/2 hidden
lg:group-hover:flex lg:group-focus-within:flex gap-1`. Single-target chip
fires the full action (new `Moves.chips/2` that folds a one-value
`options/3` into a direct action). Gallery preset `chips` (hovered hero).

**R2. Drag-to-target with an SVG arrow + click fallback. Size M.**
What: §3.4, §3.5. Arrow for attack and targeted abilities/spells; targets lit,
others dim; a small preview badge at the arrow head ("2 → dies", "base 20 →
18") from a pure `Moves.preview/3` (P2 if it needs combat code).
Why: B1, A18, C1, C5.
How: hook code in the `.CodexTable` script; `data-targets` attrs; new event
`aim` in board.ex that calls `pick/2`; css `.cx-lit`, `.cx-dim`, arrow stroke
`stroke-amber-300` with a 2 px dark outline for light card art.

**R3. Stop the layout jumps. Size S.**
What: the pick banner, the base tile and the turn summary must not push the
board. At `lg:` make them overlays: pick banner = a floating pill at the top of
the centre rail (`absolute`), turn summary = a toast card on the left edge
that fades after 6 s or on click (B8), base target = the base object itself
(R5) lit, not a new tile.
Why: 2.1 (card moves ~100 px under the pointer; hand pushed off screen).
How: css: in the `lg` block drop the `note` row from `.cx-layout.cx-noted`;
`.cx-a-note { position: absolute }` at lg; `pick_banner/1` gets `lg:absolute
lg:inset-x-0 lg:top-1/2 lg:-translate-y-1/2 lg:pointer-events-none` (buttons
`pointer-events-auto`).

**R4. Full-screen table layout at `lg:` (Arena frame). Size L.**
What: one screen, no scroll, at 1280x800 and up. Rows: opponent strip →
opponent battlefield → centre rail → my battlefield → my hand (half off the
bottom edge). Right edge: a thin rail (phase ladder + End turn button low on
the right, A5) and the log as a collapsible drawer. Remove the 90rem cap; use
`--cx-w: clamp(4.6rem, 6.2vh, 7rem)` so cards grow with the screen height.
Drop the box labels (SQUAD LEA…, IN PLAY, HAND · 5); use the space for cards
(A1 groups by distance, not by labels). Wireframes in §5.
Why: A1, A2, A5, A6; 2.1 (cut at 1280; 1920 wasted).
How: css `.cx-layout` lg grid:
`grid-template-columns: 1fr 4.5rem; grid-template-rows: auto 1fr auto 1fr auto;
areas "opp rail" "oppboard rail" "mid rail" "board rail" "hand rail";
height: 100dvh; max-width: none`. board.ex: split `side/1` into `strip/1`
(avatar, base, gold, workers, piles) and `battlefield/1` (patrol + in play).
The right `cx-aside` becomes the hover/selection zoom only (floats next to
the card, as the hover preview does now) and the log drawer.

**R5. Base as a portrait target, with workers and gold beside it. Size M.**
What: each side gets a base object at the left end of its battlefield row:
96x96 tile, base art or a keep icon, HP in 28 px bold, red ring when hit.
Workers (⚒ 5) and gold (● 11) sit under it as Arena's avatar/life (A6).
Drop the arrow on the base to attack it (B2). Tech buildings and add-ons sit
in a row next to the base as small building cards (also targets).
Why: base HP is the win condition and now the smallest number on screen; B2.
How: new `base/1` component in board.ex, `data-target-id="base-#{seat}"`;
reuse `cx-hp-#{seat}` id for tests; buildings render as `mini/1`-like tiles
with HP pills. Remove `cx-base-tile` banner at lg.

**R6. Keyboard and focus. Size S.**
What: focusable cards, `:focus-visible` ring, keys from §3.5, Esc everywhere.
Why: C1-C4; 2.1 (cards not focusable).
How: `mini/1`, `card/1`: `tabindex="0" role="button" aria-pressed={@selected}`
and `phx-keydown`/`phx-key="Enter"` → `select`; css focus ring. Key help in
the End-turn tooltip.

### P2 (big gain)

**R7. Card sizes per zone at `lg:`. Size S.**
| Zone | Now (1440) | Proposed (1440x900) | 1920x1080 |
|---|---|---|---|
| My battlefield / patrol | 80x91 | 96x120 (full 4:5 mini) | 116x145 |
| Opponent battlefield | 68x78 | 88x110 | 104x130 |
| My hand | 94x125 | 120x168, half off screen, lift to full + 1.15 on hover | 140x196 |
| Opponent hand | 50x66 backs in a big box | 36x50 backs in the strip, count on top | same |
| Zoom | 272x380 | 300x420, instant on hover (150 ms) | 360x504 |
How: `--cx-w` / `--cx-mw` in the lg block from `vh` with `clamp()`; hover
delay 500 → 150 ms in the hook (`hoverTimer`).

**R8. Patrol zone as a front line. Size M.**
What: the 5 patrol slots stand in front of the battlefield, nearer the centre
line (they are the wall the attacker must hit). Empty slot = a faint outline
with a 12 px icon (crown, star, coin, cog, eye), no text box; name in a
tooltip. Filled slot shows the bonus as a small badge on the card (A14):
"🛡1" squad leader armor, "+1" elite, etc. On my turn the slots light when a
unit is dragged or ⛨ is clicked.
Why: A1 (zones by role), A14, codex.md §8; the labels truncate now.
How: `patrol/1` in board.ex: icons via `<.icon>`; css slot `lg:size-auto
lg:border-white/10`; badge in `mini/1` from slot name.

**R9. Phase ladder + one primary button. Size S.**
What: a vertical ladder in the right rail: Tech · Ready · Upkeep · Main ·
Draw, current step lit (A4). Under it the one big button (A5): "End turn"
on main; "Done" in a pick; "OK" for a summary; disabled "Bot's turn…" with a
spinner on the bot's turn. Space = the button. Undo (Z) as a small button
above it.
Why: A4, A5, B9; now the button moves with the banners.
How: `center/1` in board.ex splits into `rail/1`; `phx-window-keydown` for
Space and z; ids `cx-end-turn`, `cx-undo` stay.

**R10. Combat motion and impact. Size M.**
What: attacker lunges 40 % of the way to the target and back (200 ms);
damage number pops on the target (exists as `cx-float`; make it 24 px, red);
target shakes 3 px; a dying unit fades and drops 8 px before it flies to the
discard (FLIP exists); base hit = red flash on the base ring + screen-edge
vignette 150 ms. Off with reduced motion (exists).
Why: A18, B10 (keep it short).
How: the server pushes `push_event("combat", %{from, to, dmg})` after an
attack; the hook plays Web Animations on the two ids. No new deps.

**R11. Opponent's turn replay. Size M.**
What: on the bot's turn, play its actions one by one (300 ms each) with the
same arrow and motion as mine, and a small "P2 is playing…" pill. The summary
becomes a toast list on the left (R3). Show the tech sheet only after the
replay ends.
Why: 2.1 (tech sheet hides the bot's turn; summary pushes the board); B8.
How: board.ex `summary_after/3` already knows the lines; send them as
`push_event("replay", ...)` with card ids; delay `drawer_after/3` (tech)
until the client pushes `replay_done`.

**R12. Opponent strip. Size S.**
What: a 64 px strip: avatar + name + spec, base HP big, gold, workers, hand
count as small fanned backs, deck/discard/codex as icon + number (B6, B7).
Why: A6; 2.1 (5 backs in 780x90).
How: `strip/1` from R4; `pile/1` gets a compact variant (`lg:` icon-only).

### P3 (polish)

**R13. Log as a drawer with turns. Size S.**
What: right-rail button opens a 320 px drawer: grouped by turn ("P2 · turn 3"
header), newest at the bottom, card names as hover-zoom links, icons for
attack/death/gold. The last 2 lines show as a faint ticker on the centre
rail (B8).
How: `log_list/1`; the view needs a turn number per line (engine log is
already ordered).

**R14. Codex / tech picker. Size S.**
What: keep the modal (it scores well). Add: spec tabs (Bashing / Finesse /
Neutral), cost filter chips, owned count, the hover zoom inside the sheet,
and a sticky footer with the 2 picked cards as thumbnails. Show what the bot
teched only as a count.
Why: A8 browse patterns; phone review rated it 4.
How: `drawer/1` tech branch; filter is a server assign.

**R15. Buildings on the board. Size S.**
What: tech buildings as small cards next to the base (R5), with a build
progress clock when building ("ready next turn"). "Build" becomes a ghost
slot at the end of the row; click opens the current modal.
How: `mat/1` command block moves into `base/1` row.

**R16. Hand niceties. Size S.**
What: playable cards get a gold outline (A2), cost turns red when you cannot
pay, "Worker" drop zone appears beside the hand only while dragging (A3).
How: css on `.cx-fan > .cx-card`; `data-playable` from legal actions.

**R17. Sound (opt-in). Size S.**
Short cues for play, attack hit, death, base hit, your turn. Off by default,
toggle in the top bar.
Why: phone review P38 (Dominion: recognise plays by ear).

**R18. Drop "How to play" from the fixed column. Size S.**
Move it to a "?" button on the rail; first game shows it once.

---

## 5. Wireframes (1440x900, `lg:`)

Legend: `[96x120]` card; `◆` lit target; `·` dim; `⚔⬆⛨` chips;
`╲` arrow. Right rail 72 px wide.

### 5.1 My main phase

```
+----------------------------------------------------------------------+------+
| (P2) River Montoya · Finesse   ♥ BASE 19   ●0 ⚒6   ▯▯▯▯▯ 5   ▤22 ▥0 ▼6 | [≡]  |  64
+----------------------------------------------------------------------+ log  |
|  [BASE ]  [T1]          patrol:  [SL:River]  ( ★ )  ( ¢ )  ( ⚙ )  ( ◉ ) |      |
|  [ 19  ]                                                              | TECH |
|              in play:   [card] [card]                                 | READY|  ~330
|                                                                       | UPKP |
+--------------------------  centre rail  ------------------------------+>MAIN<|
|  last: P2 plays Wither on Timely Messenger.            P1 · turn 2    | DRAW |  40
+-----------------------------------------------------------------------+      |
|              in play:   [Troq ⚔⬆⛨]  [Brick Thief]                    |      |
|  [BASE ]  [T1][+Build]                                                | [Z]  |
|  [ 20  ]                patrol:  ( ♛ )  ( ★ )  ( ¢ )  ( ⚙ )  ( ◉ )    |      |  ~330
|  ●5 ⚒5                                                                | END  |
|                                                                       | TURN |
+-----------------------------------------------------------------------+      |
|        [Flag][Tndr][Wthr][Brck][Frut]   <- hand, half off screen      |      |  ~110
+----------------------------------------------------------------------+------+
```

Notes: patrol rows face each other across the centre rail (front lines).
Chips show on the hovered or selected card only. Card zoom floats beside the
hovered card (no fixed column).

### 5.2 Attack with an arrow

```
+----------------------------------------------------------------------+------+
| (P2) River Montoya   ♥ BASE 19  ...                                   |      |
+----------------------------------------------------------------------+      |
|  ·[BASE]·  ·[T1]·       patrol:  ◆[SL:River 2/3]◆  ( ★ ) ...          |      |
|                                      ╲  "2 → 1 HP"                    |      |
|              in play:   ·[card]·      ╲                               |      |
+------------  [ Troq: pick a target · Esc ]  (floating pill) ----------+ MAIN |
|                                         ╲                             |      |
|              in play:   [Troq ⚔]━━━━━━━━━╯  (arrow from Troq)         | DONE |
|  [BASE]  ...            patrol:  ( ♛ ) ...                            | (Esc)|
+-----------------------------------------------------------------------+      |
|        [hand dims to 60 %]                                            |      |
+----------------------------------------------------------------------+------+
```

Notes: only legal targets light (squad leader rule: here only River). Base is
dim, so the player sees why it cannot be hit. Nothing moves: the pill floats.

### 5.3 Opponent's turn

```
+----------------------------------------------------------------------+------+
| (P2) River Montoya  ♥ 19  ●3 ⚒6   [P2 is playing…]                    |      |
+----------------------------------------------------------------------+      |
|  [BASE]  [T1]           patrol:  [SL:River]  [EL:Turtle]  ...          |      |
|              in play:   [Wither]━━━━━━━━━━━━━┓  (replay arrow)        |      |
+-----------------------------------------------┃----------------------+ (P2) |
| +-------------------------+                   ┃                       | MAIN |
| | P2's turn               |                   ▼                       |      |
| | • hires a worker        |  in play:   [Messenger ✖ -1]  (shake,     | BOT'S|
| | • summons River         |                             fade)         | TURN…|
| | • Wither → Messenger    |  patrol:  ( ♛ ) ...                       |(dis- |
| +-------------------------+  (toast, left, fades)                     | abled|
+-----------------------------------------------------------------------+      |
|        [my hand, not dimmed: I can read it]                           |      |
+----------------------------------------------------------------------+------+
```

---

## 6. Top items in one line each

1. R1 Action chips on the hovered/focused/selected card: Attack where the card is.
2. R2 Drag a ready unit to its target with an SVG arrow; click path for a11y.
3. R3 Banners, base tile and turn summary float: no layout jump.
4. R4 One-screen Arena frame at `lg:`: opponent top, me bottom, rail right, hand off the edge, cards scale with height.
5. R5 Base as a big portrait target with workers, gold and buildings beside it.
6. R6 Focusable cards, `:focus-visible` ring, keys A/L/P, Enter, Esc, Space.

Order to build: R3 → R6 → R1 → R2 (needs R1's data) → R5 → R4 (largest; do
it in one round, gallery presets at 1280/1440/1920 + a 392 check that the phone
did not change).
