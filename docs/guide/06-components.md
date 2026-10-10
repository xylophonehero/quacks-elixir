# 6. Components

[Back to the guide](../GUIDE.md)

## Module map: which file owns what

The game page's components are split by area of the page (October 2026; before, one
`GameComponents` module and the choice components in `GameLive` held them all).
Each module imports the ones it builds on: `ChipComponents` and `GameText` are the
base, `BarComponents` imports most of the others. A function moves only with its
area; the UI snapshots (`mix test --only snapshot`, chapter 8) show that a move
changes no page.

| File | Module (`QuacksWeb.`) | Owns |
| --- | --- | --- |
| `lib/quacks_web/components/chip_components.ex` (333 lines) | `ChipComponents` | `chip/1`, the bonus die (`die/1`, `die_face/1`, `replay_die/1`), `seat_dot/1`, the seat and palette colour classes (`seat_bg/1`, `seat_style/1`, ...) |
| `lib/quacks_web/components/pot_components.ex` (1082 lines) | `PotComponents` | `pot/1` (chips, scoring ring, droplet, effects), `test_tubes/1` and its `.TubeDrop` hook, the flask, `bag/1`, `bag_button/1`, `chip_counts/1`, `aside/1`, `bowl/1` |
| `lib/quacks_web/components/track_components.ex` (254 lines) | `TrackComponents` | `rat_track/1` (the score and rat track), `rat_spaces/1` |
| `lib/quacks_web/components/tile_components.ex` (974 lines) | `TileComponents` | the players row: `player_chip/1`, `seat_loop/1`, `loop_start/3`, `loop_columns/1`, `round_leaders/1`, `crown/1`, `seat_state/2`; the sheet `player_card/1`, `bot_badge/1`, `ruby_badge/1`, `result_lines/1`, `explosion_icon/1` |
| `lib/quacks_web/components/panel_components.ex` (890 lines) | `PanelComponents` | the books (`book_tile/1`, `book_list/1`, `books_in_play/1`, `book_info/3`, ...), `fold/1`, `house_rules/1`, the witches (`witch_card/1`, `witches_list/1`, `calls/2`), the fortune cards (`fortune_card/1`, `fortune_panel/1`, `fortune_tile/1`, `fortune_offer/1`, `blue_offer/1`), the log (`action_log/1`, `announcer/1`) |
| `lib/quacks_web/components/bar_components.ex` (1838 lines) | `BarComponents` | the bottom bar: `action_bar/1` (Stop, flask, Draw), `fuse_meter/1`, `reward_line/1`, `round_phase/1`; every choice in the bar (`bar_choice/1`, `chip_picks/1`, `choice_grid/1`, `choice_button/1`, `chip_row/1`, `info_row/1`), `crow_panel/1` and its `.FromBag` hook, `action_label/3`, `pick_choices/0` |
| `lib/quacks_web/components/shop_components.ex` (506 lines) | `ShopComponents` | `shop/1` (buy and rubies steps), `shop_rows/2`, `purple_buy/1`, `offer_books/1` |
| `lib/quacks_web/game_text.ex` (598 lines) | `GameText` | the words, no markup: `label/1,2`, `log_lines/3`, `log_text/3`, `chip_name/1`, `phase_name/1`, `card_outcome/2`, `vp_breakdown/3`, `plural/3` |
| `lib/quacks_web/action_code.ex` (30 lines) | `ActionCode` | `encode/1` and `decode/1`: an action term as a `phx-value-action` string and back |
| `lib/quacks_web/live/game_live.ex` (3308 lines) | `GameLive` | the LiveView: mount, `handle_event/3`, `handle_info/2`, `render/1` (the page skeleton), `preview/3`, the reveal and the hints; also `copy_link/1` and the spectator note |

Other component modules: `CoreComponents` (buttons, inputs, sheets),
`AlchemistsComponents`, `SetupComponents` (the spell book), `RevealComponents`,
`TileRevealComponents`, `CardRevealComponents`, `FinalComponents`,
`TipComponents`, `BugReportComponents`, `ScenarioComponents`, `Icons`.

## Function components

A function component is a function that takes `assigns` (a map) and returns a `~H`
template. It is a React function component without hooks: no state, no effects.
State lives in the LiveView (chapter 5).

```elixir
attr :chip, :any, required: true, doc: "a `{colour, value}` tuple"
attr :size, :atom, default: :md, values: [:xs, :sm, :md]
attr :rest, :global

def chip(assigns) do
  {colour, value} = assigns.chip

  assigns =
    assign(assigns,
      colour: colour,
      value: value,
      colour_class: Map.get(@colours, colour, "bg-zinc-400 text-white"),
      icon_class: if(colour in @ink_icon_chips, do: "text-ink", else: "text-white")
    )

  ~H"""
  <span :if={@size == :xs} ...>{face(@chip)}</span>
  <span
    :if={@size != :xs}
    class={[
      "chip-token relative inline-flex shrink-0 items-center justify-center rounded-full",
      @size == :sm && "size-6",
      @size == :md && "size-9",
      @colour_class
    ]}
    aria-label={"#{@colour} #{@value}"}
    {@rest}
  >
    <.ingredient_icon colour={@colour} class={["size-[58%]", @icon_class]} />
    <span :if={@colour != :locoweed} ... data-role="chip-value">{@value}</span>
  </span>
  """
end
```

(`chip/1` in `lib/quacks_web/components/chip_components.ex`, shortened)

| React | Phoenix |
|---|---|
| `function Chip({chip, size = "md", ...rest})` | `def chip(assigns)` with `attr` lines above it |
| TS prop types | `attr :size, :atom, default: :md, values: [...]`; the compiler warns on a wrong or missing attribute |
| `{...rest}` | `attr :rest, :global` and `{@rest}`: `id`, `data-*`, `phx-*` pass through |
| `<Chip chip={c} />` | `<.chip chip={c} />` (the dot: a function in scope) |
| `props.children` | `slot :inner_block` and `{render_slot(@inner_block)}` |
| `useMemo` | compute in the body and `assign/2` before `~H` |

Components do not change state: they only render the `Quacks.Game` struct that the
LiveView gives them. A button in a component sends a
`phx-click` to the LiveView that renders it.

### One slot table, three views: the patient's glasses (round 15)

`Quacks.Rules.Alchemists` keeps one list of terms per glass (chapter 7). Three
components in `lib/quacks_web/components/alchemists_components.ex` draw that same
data. No component keeps its own copy of a reward.

- `slot_grid/1`: the patient card, 5 glasses per row, large glyphs.
- `glass_rewards/1`: one column per flask space under the vials of `flask_strip/1`,
  one icon wide. `mini/1` turns a term into `{glyph, number}`: `{:vp, 2}` is the VP
  seal over "2", `{:buy, 6}` is a gold coin disc over "6", `{:swap, 1, 4}` is "⇄"
  over "4". Passed glasses fade, the glass under the marker has a gold underline.
- `patient_panel/1`: the patient block in the player sheet (`player_card/1`). It
  shows the picture, name, essence, card text and the `:sm` flask strip, so you can
  see the patient of each opponent. The name card has no second button: the whole
  card already opens the sheet, and HTML does not allow a button in a button.

The `:lg` strip sits on the dark iron bar and the `:sm` strip on parchment, so
`mini_colour/2` takes the size and gives a light or a dark icon colour. Each
`<li>` has a `title` and a `sr-only` text with the words of `slot_text/1`; the
glyphs are `aria-hidden`. Tests find a glyph by `data-glyph` and a column by
`data-space` (`test/quacks_web/live/alchemists_live_test.exs`).

The essence marker moves only in the essence phase, so during brewing it shows the
last round. With `preview` (only your own seat: the `:lg` strip and your own
sheet), `flask_strip/1` adds a ghost marker labelled "now" at `preview_space/2`.
That function calls `Quacks.Game.Essence.count/2`, the same count the essence phase
uses, and drops the exploded neighbours, because they are not known until they
stop. The ghost is absolute and one column wide like the real marker, so the strip
height does not change. It is under the real marker in the DOM, so on the same
space it shows as a dashed ring. Outside `:potions` it is `nil` and not rendered.
It slides with `translate` (`.essence-ghost`); reduced motion turns that off.

## HEEx in five rules

1. `{expr}` interpolates in attributes and text: `{face(@chip)}`.
2. `<%= ... %>` is for block constructs in the body, for example
   `<%= for {chip, i} <- Enum.with_index(chips) do %>`
   (`lib/quacks_web/live/game_live.ex:2293-2296`).
3. `:if={cond}` and `:for={x <- list}` work on any tag or component:
   `<div :for={{title, tiles} <- @groups} ...>` and `<p :if={title} ...>`
   (`lib/quacks_web/live/game_live.ex:2272-2273`).
4. `class={[...]}` takes a list; `false` and `nil` drop out. That is `clsx`, built in.
5. `<%!-- comment --%>` never reaches the browser.

Inside a component, `@game` is the component's `game` attribute, not the LiveView's
assign. A component reads only what it gets.

## Sheets and dialogs with almost no JS

The page has many overlays: log, bag, players, books, the bug report, and one
dialog per decision. They use two native browser features and no component library
(`docs/research/components-and-mobile.md` §1, §2).

**Info sheets: the Popover API.** `sheet/1` renders `<div id={@id} popover ...>` with
a close button `popovertarget={@id} popovertargetaction="hide"`
(`lib/quacks_web/components/core_components.ex:110-131`); `sheet_button/1` is a button
with `popovertarget`. The browser opens and closes it and handles Esc and "tap
outside". Zero JS, zero server state. The slide-up uses CSS `@starting-style`
(`assets/css/app.css:382-450`).

**Decisions: native `<dialog>`.** A decision must be answered, so it is a modal
`<dialog>` opened with `showModal()`. That needs one line of JS. The trick is in
`dialog_sheet/1` (`lib/quacks_web/components/core_components.ex:211-239`):

```heex
phx-mounted={
  if @auto_open,
    do: JS.ignore_attributes("open") |> JS.dispatch("quacks:modal"),
    else: JS.ignore_attributes("open")
}
```

- `phx-mounted` runs a `JS` command when the element enters the page.
- `JS.dispatch("quacks:modal")` fires a DOM event on the dialog.
- `JS.ignore_attributes("open")` tells LiveView to leave `open` alone. The browser
  sets it in `showModal()`; without this, the next server diff would remove it and
  close the dialog.

The listener (`assets/js/app.js:238-254`) is short, but it now picks a mode:

```js
const wide = matchMedia("(min-width: 64rem)")
const sideOpen = d => {
  if (d.open) return
  const side = wide.matches && d.dataset.side
  if (side === "hidden") return closed(d)
  side ? d.show() : d.showModal()
}
window.addEventListener("quacks:modal", e => sideOpen(e.target))
```

So the server renders a decision dialog with `:if={@decision && ...}`
(`lib/quacks_web/live/game_live.ex:1301-1311`). It opens itself when it appears and
goes away when a render drops it. The server has no "is the dialog open" state.

**A trap: a patch can move an open dialog.** When a patch adds or removes an
element before an open dialog in the same parent, morphdom moves the dialog with
`insertBefore`. A move takes the dialog out of the document for a moment, so the
browser removes it from the top layer: it is no longer modal. But `open` stays
(`ignore_attributes`), so the dialog is now a plain `position: fixed` box. The
action bar (`footer.game-bar`) comes later in the page, so it is above the box and
takes every tap on the lower part of the sheet. This happened in each shop on a
phone (round 13, issue #1): the end of the results replay opens the shop, and the
server's next patch removes `#results-N`, which is before the shop in the side
column. Close and open again fixed it, because that calls `showModal()` again. Now
`onPatchEnd` (the `dom` option of the `LiveSocket`) calls `remodal()`: if an open
dialog that must be modal is not `:modal`, it opens every such dialog again with
`showModal()`, in page order, so the new card stays on top. `moving` keeps their
`close` events from running `on_close`. To check a dead tap in the browser,
`document.elementFromPoint(x, y)` names the element that gets it, and
`document.querySelectorAll("dialog[open]:not(:modal)")` must be empty on a phone.

The other listeners are small too. `closed/1` (`assets/js/app.js:247-252`) runs on
every dialog `close` event: it runs the dialog's `on_close` JS and opens the dialog
that `then_open` names. A tap on the dimmed backdrop closes a modal sheet
(lines 261-265), so a player can look at the pot and come back with "Back to shop".
`quacks:close` closes a dialog or popover (lines 272-273), and `quacks:copy` copies
to the clipboard (line 297). A chip in the fortune card dialog sends its action and
closes the dialog in one chain:
`JS.push("action") |> JS.dispatch("quacks:close", to: "#card-round-#{game.round}")`
(`card_click/1`, `lib/quacks_web/live/game_live.ex:2432-2434`). Five hooks have
state: `ConfigMemory` (`assets/js/app.js:43-53`) keeps the host's last settings in
`localStorage` (round 14: also the herb witch picks; round 27: the config carries
`v: 27`, and an older one drops its `black_rule`, see `SetupComponents.saved_rules/1`), `NameMemory` keeps your name,
`RevealSettings` keeps the reveal settings and `PotMotion` animates the pot (see "Motion" below).

**The witch pickers (round 14).** With The Herb Witches on, the spell book's
witches page (round 29: `witch_links/1`, the Herb Witches row's Customise) shows a tile per penny colour (copper, silver, gold). A tap opens the
colour's page with "Random" and its four cards as radio cards
(`witches[colour]`), the same pattern as the book pages. `parse_witches/1`
(`lib/quacks_web/components/setup_components.ex:273`) turns the form into
`%{copper: :c3, silver: nil, gold: nil}`, which goes to `GameServer.create/3`
and on to `Game.new(witches: ...)`. The engine deals first and then replaces the
picked colours (`pick_witches/2`, `lib/quacks/game.ex:399`), so the random stream
stays the same. The witches sheet in the game has a title row now, so its × no
longer squeezes the first card.

**The App line (round 14; removed in round 29).** The menu ended with a debug
line on the service worker, the display mode and the install prompt. Nick asked
for a quieter menu, so the line and its `AppStatus` hook are gone; the seed stays.

## Layout: one dialog, every screen size

The same decision dialog is a bottom sheet on a phone and a panel in the right
column on a tablet or desktop. There is one element and no second template.

**The side panel (≥ 64rem).** `dialog_sheet` takes `side={:panel}`
(`lib/quacks_web/components/core_components.ex:199-202`). It renders as
`data-side="panel"`, and on a wide screen `sideOpen` calls `show()` instead of
`showModal()`. A non-modal dialog has no backdrop and no focus trap, so the pot and
the buttons stay live. CSS then takes it out of the overlay and puts it in the
column flow (`assets/css/app.css:565-607`):

```css
@media (width >= 64rem) {
  .sheet[data-side="panel"][open]:not(:modal) {
    display: block;
    position: static;
    ...
  }
}
```

`side={:hidden}` counts as closed at once on wide screens and hands over to the next
dialog. The new fortune card used it until round 14; now a card without a choice
shows in the reveal overlay, and the card dialog only holds a choice (as a panel). When the window
crosses 64rem, app.js closes an open panel and opens it again in the other mode
(`assets/js/app.js:256-259`). In React you would render a `<Sheet>` or a `<Panel>`
from a `useMediaQuery` hook. Here the server sends one element, and the browser
picks the mode when it opens it.

## One grid with named areas (round 11)

The game page is one CSS grid. Each block in the template names its area with a
`data-area` attribute, and `app.css` places the areas per layout
(`assets/css/app.css:624-830`). The markup stays the same on every screen; only
the template changes. The DOM order is the reading order for a screen reader:
header, players, notices, books, pot, context, bar.

```css
.game-grid {
  display: grid;
  height: 100dvh; /* with width: 100% and overflow: clip, see "The viewport lock" */
  grid-template-rows: auto auto auto minmax(0, 1fr) auto;
  grid-template-areas: "header" "players" "notices" "pot" "bar";
}

@media (width >= 64rem) {
  .game-grid {
    grid-template-columns: minmax(0, 1fr) 22rem;
    grid-template-areas:
      "header context" "players context" "notices context" "pot context" "pot bar";
  }
}
```

| Layout | Areas |
|---|---|
| Portrait, phone or tablet (< 64rem) | header, players, notices, pot, bar (one column) |
| Landscape phone (`orientation: landscape`, `max-height: 30rem` and `min-width: 35rem`) | the pot on the left, full height; header, players, notices, context, bar and the test tubes on the right |
| 64rem | the pot column on the left; the context column on the right, the bar at its foot |
| 80rem | the books column, then the pot, then the context column |

**Why the pot never moves.** The pot sits in the flexible row
(`minmax(0, 1fr)`). That row gets what the other rows leave, so the pot changes size
only when a row above or below it changes height. Round 11 makes every such row
fixed:

- No line comes and goes above the pot: the status line ("Everyone brews at the
  same time."), the rats line, the ring legend and the flask hint are gone. Stir,
  Skip, the Red Set 2 chips and the overflow bowl are `absolute` inside the pot
  square.
- The player tiles have a fixed height (round 27, see "The player tiles" below), so
  the round results do not make the row taller. A hidden
  element at the end of a `space-y-*` block still gets a margin on its neighbour, so
  the replay marker `<i id="replay-start-N">` is the first child of its block.
- Phones: the bar has a fixed height (`.game-bar`, `--bar-h`). Its rare extras
  (Ear worm, the patient's chips, the bonus die) are in `.game-tray`, which
  is `position: absolute; bottom: 100%`: it floats over the pot's lower band.
- Mandrake (round 32): the white chip that went back floats over the bag
  (`[data-role=mandrake-undo]`, `absolute` in the pot square, so no layout shift),
  with a round undo button (`#keep-white`, `keep_white`) above it. The chip bobs
  (`.mandrake-bob`, 4 px, 1.6 s); reduced motion: no bob. Drawing on keeps the
  server's answer (the chip stays in the bag).
- From 64rem the pot spans the bar's row too ("pot context" / "pot bar"). A taller
  bar takes room from the context column, never from the pot. Grid sizes an `auto`
  row only from the items that do not span a flexible row, so the pot does not
  size it.

A landscape phone moves the test tubes out of the pot column: `.pot-column` becomes
`display: contents`, so its children are grid items and the tubes can take the
`tubes` area. All sheets slide in from the right there, over the right column only.
Tailwind gets a matching variant for small fixes:
`@custom-variant phone-landscape (@media (orientation: landscape) and (max-height: 30rem) and (min-width: 35rem));`
(`assets/css/app.css:24`), used as `phone-landscape:sr-only`.

**Never gate a layout on height alone (round 23).** A portrait phone is wider than
tall whenever its layout viewport gets short: the on-screen keyboard where the
browser resizes the layout (full screen, the installed app), split screen, a pop-up
window. Before round 23, `(orientation: landscape) and (max-height: 30rem)` then
matched at 392 px wide: the game got the landscape grid (pot on the left, the
half-width Draw button) and the header ran past the right edge. Every landscape
query also needs `min-width: 35rem` (no portrait phone is that wide; the smallest
landscape phone is). The viewport meta says `interactive-widget=resizes-visual`, so
the keyboard resizes only the visual viewport where the browser honours it.

## The viewport lock (round 23)

The app never scrolls as a page. The game root (`.game-grid`) and the lobby root
(`.lobby-root`, the lobby's outer `<div>`) are `width: 100%; height: 100dvh;
overflow: clip`, and `body` has `overscroll-behavior: none`. Three rules:

- `overflow: clip`, not `hidden`. A `hidden` box is still a scroll container: focus
  or `scrollIntoView` on a child past its edge scrolls it sideways, with no
  scrollbar to scroll back. A `clip` box cannot scroll at all, and `position:
  sticky` and `fixed` children keep working.
- `width: 100%`, never `100vw` (it counts a desktop scrollbar). No `vw` or `vh` is
  left in app.css; heights use `dvh`. A width over the pot is `%`, `min()` or
  `clamp()` (the pot card is `min(64%, 15rem)` with `max-width: 100%`).
- Only the designated areas scroll: the books column, sheets and dialogs, the Games
  list, the book pages. Each has `overscroll-behavior: contain`.

`test/quacks_web/live/round23_test.exs` checks the root classes and the CSS. In the
browser: `document.documentElement.scrollWidth == innerWidth` and `scrollHeight ==
innerHeight` on every screen (lobby pages, round start, brewing, evaluation, shop,
podium) at 392x713 and 360x740.

One trap: CSS written in `app.css` outside a layer beats every Tailwind utility.
`.action-bar { display: grid }` made `lg:hidden` on the bar do nothing, so that
rule is inside `@layer components` (`assets/css/app.css:679`).

**The context column (64rem).** `<aside class="context-column" data-area="context">`
(`lib/quacks_web/live/game_live.ex`) holds what happens now, top to bottom:
the fortune teller card, the decision panel and the witches (64-80rem; from 80rem
they are in the left column, round 39). Below 64rem it is `display: contents` and
holds only the sheets. Round 39 removed the Take a Chance rolls (`chance_panel/1`)
and the results panel (`results_panel/1`): the results stage over the bar shows
both now. The
bar (`<footer class="game-bar" data-area="bar">`, line 1428) is its foot from 64rem:
Draw is the large button, Stop and a flask button sit under it. An exploded pot
shows "Your pot exploded" and the next step there.

Until round 39 a results panel here reused the replay beats. Round
11 changed the replay order: the bonus dice of the whole table roll first, one
after the other in seat order, two beats each (`dice_slots/2`,
`lib/quacks_web/replay.ex:59`); then every seat's other lines start together.

**The books drawer (48–80rem).** Below 80rem there is no books column. The header's
Books button (with a count badge) opens `#sheet-books`, a popover with the class
`sheet-drawer` (line 1722). From 48rem, and on a landscape phone, CSS makes it a
drawer from the right (`assets/css/app.css:830`): it slides over the context
column, never over the pot. A popover closes with Esc and a tap outside, with no
JS. A decision that arrives while the drawer is open does not close it: `sideOpen`
waits for the drawer's `toggle` event (`assets/js/app.js:252`):

```js
const books = document.querySelector("#sheet-books:popover-open")
if (books) return books.addEventListener("toggle", () => sideOpen(d), {once: true})
```

The drawer replaced the tablet's CSS-only tabs (radio inputs and `:has()`, layout
2). Tabs hid the decision behind a second tap; the drawer leaves the decision in
place.

**The left column (≥ 80rem).** `#left-column` (`data-area="books"`), left of the
pot, holds `books_in_play/1` (`lib/quacks_web/components/panel_components.ex`, the
books in play in board order, `Chips.order/0`, chapter 7, `id="books-column"`)
and, with The Herb Witches, the witches (`id="witches-column"`). Round 39: both
are folds (see the round 39 section).

### The player tiles: a seat loop (round 27)

The players row (`#players-row`, in the `players` area) holds one tile per seat,
yours too (`player_chip/1`, design B of the opponents page). A tile is a button that
opens the seat's sheet. It has three lines: the seat disc with the initial and the
name; this round's **pot space** (the coins of the scoring space, large) and VP;
rubies, the **black chips in the pot**, then the flask, rat tails, essence, test
tube, patient or witch pennies while they fit. The last line is one line high and
wraps into hidden overflow, so a tile never grows (`h-[3.25rem]`). Your tile has a
gold border.

The states are classes and absolute badges, so they never change the tile's size:

- exploded: red stripes (`.tile-boom`, app.css) and a large red burst on the top
  right corner (`player_state/1` with `tile`);
- stopped: the tile fades (`opacity-55`) and the corner badge is a check;
- brewing: no badge;
- **round leader** (`round_leaders/1`, the bonus die rollers: the furthest pot this
  round of the seats that did not explode, or whose explosion the silver witch took
  away): a crown on the seat disc and a gold glow (`.tile-lead`). Nobody before the
  first chip of the round, and nobody solo.

The tiles never re-order. `seat_loop/1` gives each seat a row and a column
(`grid-row`, `grid-column` inline): 2 to 4 seats one row in seat order; 5 to 8 two
rows of `ceil(n / 2)` columns (`loop_columns/1`), and the second row runs
backwards and ends under the first row's last tile, so the tiles form a loop and
neighbours touch (8: `1 2 3 4 / 8 7 6 5`; 5: `1 2 3 / _ 5 4`). Nothing scrolls
sideways: at 360 px eight tiles fit in two rows of four.

### The rat track (round 16, equal steps since round 22)

`rat_track/1` (`lib/quacks_web/components/track_components.ex`) is a slim strip
under the name cards, inside the `players` area. It has a fixed height (`h-8` since round 24) and
shows only while the rats rule is on with 2+ players, so it never comes and goes
during a game and the pot below it does not move.

Round 22 made it a track of *steps*, not a VP scale. The steps are the printed rat
tails (`ScoringTrack.tails/0`) between the last player and the leader, read from the
leader's side, so the leader is on the left:

```elixir
tails = for t <- Enum.reverse(ScoringTrack.tails()), low <= t and t < leader, do: t
steps = length(tails) + 1
# a seat's step is its rat count: 0 for the leader, one more past each tail
step = ScoringTrack.rat_tails(vp, leader)
```

Every step is the same width: a dot sits at `(step + 0.5) / steps`, a tail at
`(j + 1) / steps`, each as `left: calc(0.5rem + (100% - 1rem) * x)`. Under each rat
glyph is the VP of its tail, so a player reads "below 12 I get this rat". Seats in
one step stack, 7px apart (`data-step` on each dot). When a seat passes a tail its
`left` changes, and a CSS `transition` on `left` slides the dot: no hook. The whole
track is one `role="img"`; its `aria-label` names every seat's VP and rats, leader
first.

Round 24 adds the leader's VP above the leader's dot (`data-role="leader-vp"`): one
small bold number at the leader's step, `left` at `0.5 / steps`, so a tie for the
lead shows it once over the stacked dots. The other dots keep their `title`.

### The pot's corners (round 22)

The pot is the largest square that fits (`.pot-square`), and the round cauldron
leaves four free corners. Everything that comes and goes around the pot is
`absolute` inside that square, so the pot never moves (the round 11 rule):

| Corner | What | Markup |
|---|---|---|
| top left | the round's card, the witches below it | `[data-role=pot-corner]`: `fortune_tile/1` (`#corner-card`) and the witches button |
| top right | the kept Toadstool chips (red Set 2) | `aside/1`, a pill of chips (`[data-role=beside-pot]`) |
| bottom left | the flask | inside the SVG |
| bottom right | the bag | `bag_button/1` |

The corner card is a button with `popovertarget="sheet-fortune"`: a tap shows the
card's text in the sheet, with no server event. It is on every layout; from 64rem
the context column also shows the whole card. The header has no card tile any more.
The Toadstool pill has no visible label; its `aria-label` names the chips.

A new card hovers over the pot (`#pot-card-<round>`, `.pot-card`): see **Round 22**
under the reveal overlay.

## Hotkeys

One attribute on the grid, `phx-window-keydown="hotkey"`
(`lib/quacks_web/live/game_live.ex:977`), sends every keydown to the server. The
server knows the legal actions; the browser knows where the focus is. So app.js adds
three facts to each keydown with the LiveSocket's `metadata` option
(`assets/js/app.js:211`):

```js
metadata: {
  keydown: e => ({
    typing: !!e.target.closest?.("input, textarea, select, [contenteditable]"),
    control: !!e.target.closest?.("button, a, summary, label"),
    modal: !!document.querySelector("dialog:modal"),
  }),
},
```

`handle_event("hotkey", ...)` (line 175) maps the key with `hotkey_action/3`
(line 675) and plays it with `play/3` (line 660), the same function the
`"action"` event uses, so a key and a tap cannot differ:

| Key | Action | Only when |
|---|---|---|
| d, Space | `:draw` | `:draw in @actions` |
| s | `:stop` (or `:resume`) | it is in `@actions` |
| f | `:use_flask` | it is in `@actions` |
| b | open or close the bag sheet | this seat plays (`@me`) |
| Enter | the open decision's one primary button: the empty rubies step's Done, the shop's Done (Buy with chips ticked), a decision with one button and no chips | `enter_action/1` finds exactly one |
| Esc | nothing on the server: the browser closes the modal dialog or the drawer | |

The server downcases the key, so Shift+D works too. The bag sheet is a popover,
which only the browser can open: for b, `handle_event` answers with
`push_event(socket, "quacks:toggle", %{id: "sheet-bag"})` and app.js calls
`togglePopover()` on that element. This is the one key with JS, and it holds no
key logic either.

Letters and Space do nothing while typing or with a modal dialog open; Space and
Enter on a focused button leave it to the browser, which presses it already.
`@actions` is empty while a decision is open, so a key cannot skip a dialog. From
64rem the buttons show their key in a `<.kbd>` (`core_components.ex`), lowercase,
hidden from screen readers; `show` sets when it shows (the shop's Buy hint uses a
container query, `lg:@min-[24rem]/shop-bar:inline-block`, because the shop sheet
is a narrow column). The bag button has `aria-keyshortcuts="b"` and the title
"Bag (b)". The tests send the metadata as params:
`render_keydown(element(view, "#game"), %{"key" => "d"})`
(`test/quacks_web/live/round11_test.exs`, `round12_test.exs`).

**"Only Shift+D works" (round 12).** The cause was not in the app: Chrome with real
key events (CDP `Input.dispatchKeyEvent`) draws, stops and toggles the bag with
plain d, s and b. Nick's browser runs the Vimium extension, which binds d (scroll
half a page), f (link hints), b (bookmarks) and, with his mappings, Space as a
prefix; it takes these keydowns in the capture phase before the page sees them,
and lets Shift+D through because it binds no D. Vimium binds no s by default, so
a plain s should work; that part of the report was not reproduced. The fix is
outside the code: a Vimium exclusion rule for the game's address (or pass keys
`dsfb `). A page cannot switch off an extension's key handler.

In dev, `phoenix_live_reload` remembers the last key that went down and, while it is
"c" or "d", turns a click into "open in editor". A synthetic keydown with no keyup
(a test script) therefore swallows every later click. Real keyboards send keyup.

## The SVG pot is computed at compile time

The pot is a spiral of 54 spaces, which needs floating-point maths. That code sits
in the module body, outside any `def`, so it runs once when the module compiles
(`lib/quacks_web/components/pot_components.ex`). The result is stored in
module attributes:

```elixir
@positions List.to_tuple([{0.0, 0.0} | positions])
@groove Enum.map_join([{0.0, 0.0} | positions], " ", fn {x, y} -> "#{x},#{y}" end)
```

At runtime a space's position is a tuple lookup, `elem(@positions, index)`
(`lib/quacks_web/components/pot_components.ex`). In JS this would be a
`const POSITIONS = computeSpiral()` at module top level; here it does not even run
at app start.

## Icons are read at compile time

`QuacksWeb.Icons` (`lib/quacks_web/components/icons.ex`) gives three components:
`<.ingredient_icon colour={:orange} />`, `<.piece_icon name={:ruby} />` and
`<.patient_icon id={:ear_worm} />`. `lib/quacks_web.ex:84` imports them into every
component and LiveView.

The SVG files are in `priv/static/images/icons/`, but the page never loads them
with `<img src>`. The module reads them when it compiles
(`lib/quacks_web/components/icons.ex:55-60`):

```elixir
@icons Map.new(@files, fn {name, file} ->
         path = Path.join(@dir, file)
         @external_resource path
         [_, inner] = Regex.run(~r{<svg[^>]*>(.*)</svg>}s, File.read!(path))
         {name, String.trim(inner)}
       end)
```

- This is the trick of the pot spiral again: code in an attribute runs in the
  compiler. The compiled module holds a map `name => markup`. At runtime nothing
  reads a file and the browser fetches nothing.
- `@external_resource path` tells Mix that the module depends on that file. When
  the SVG changes, the next compile (or live reload) compiles `Icons` again.
  Without it, Mix keeps the old markup.
- `sprite/1` (`lib/quacks_web/components/icons.ex:121`) puts every icon once in a
  hidden `<svg>`, as `<symbol id="icon-NAME">`. The root layout
  (`layouts/root.html.heex`) renders it once per page, outside the LiveView, so no
  diff ever carries it. It inserts the markup with `Phoenix.HTML.raw/1`. `raw` turns
  off HTML escaping. That is safe here because the markup comes from our own files,
  never from a user.
- `svg/1` (`lib/quacks_web/components/icons.ex:148`) is then only
  `<svg viewBox="0 0 512 512" fill="currentColor"><use href="#icon-NAME"/></svg>`:
  about 150 bytes instead of 1–6 KB of paths. Before the sprite, about 40 % of each
  game diff was icon paths. `inline` (`<.piece_icon name={:ruby} inline />`) puts
  the paths in place instead, for markup that must stand alone.
- `fill="currentColor"`: the icon takes the text colour, so
  `class="size-4 text-ruby"` sizes and colours it, as with an icon font.

In React you get the same with SVGR (`import Ruby from "./ruby.svg"`): a build step
inlines the file as a component. Here the compiler does it, with no bundler plugin.

`attr :colour, :atom, values: @ingredients` makes the compiler warn on a literal
like `colour={:pink}`, and `Map.fetch!/2` raises on an unknown name at render time.
`test/quacks_web/components/icons_test.exs` checks that every chip colour,
piece and patient has an icon.

**To swap an icon:** copy the new file into `priv/static/images/icons/`, change its
file name in `@files` (`lib/quacks_web/components/icons.ex:22-52`) and credit the
author in `docs/CREDITS.md`. The file must be one filled silhouette on a 512
viewBox, because `sprite/1` and `svg/1` set the viewBox and the fill.

## The spell book: pages by URL, form-attribute fields (rounds 17 and 19)

The lobby's book (`lib/quacks_web/live/lobby_live.ex`, `.spell-book` in app.css)
is one `<section>` per page (`book_page/1` in the LiveView: the title with the
ruled underline, the content). The server shows one page on a
phone and two from 64rem with Tailwind's `hidden`/`flex` and `lg:` classes; the
sections carry `.book-page-left` or `.book-page-right` for the open book's grid.
A page that appears after a step turns in once (`page-turn`, only with
`data-turned`, so the first paint never animates). There are no bookmarks.

The pages split the forms: the expansion switches (New game's rows) belong to
`#books`, the pot-side switch to `#options`, and each colour page's radio cards
(`SetupComponents.book_options/1`, `witch_options/1`) to `#books`. Each input
names its form (`form="books"`), so the browser sends it with that form's change
and LiveView's `phx-change` sees it. `books_form/1` takes `patch` (a function from
`{:book | :witch, colour}` to a path): its tiles are links to the colour pages
(round 26: the only mode; the configure screen and its picker sheets are gone).

**The patient picker (round 26).** `AlchemistsComponents.patient_picker/1` is a
small form of radio cards (`book-card`, the same check as the book cards):
"Random" and the 3 dealt patients, each with icon, name and a 3-line clamp of the
text. It sends `"patient"`; `parse_patient/2` turns any id that is not dealt into
`:random`. The spell book and the waiting panel both use it.

**The New game flow (round 23).** The New game page (`?step=players`) has the
player count, the seats (name, colour), the Public switch, then three rows
(`page_link/1`): House rules, Expansions and Ingredient books, each with a line on
the current choice ("As in the rulebook" / "N changed", "Base game" / "Herb
Witches · test tubes", the preset or Custom). Expansions, House rules and Ingredient
books are children of New game; a colour or witch page is a child of Ingredient
books. The Expansions page has only the three expansion rows.

**Round 25.** The House rules row moved to the Expansions page, under the three
expansion rows ("hidden a bit"); House rules is now a child of Expansions (Back
goes there) and New game has two rows. The presets moved to the foot of the
Ingredient books page (`#presets-block`, below the colour rows), as a two-column
grid (three from 40rem) instead of a horizontal scroll. The bar fits a 360 px
phone: `.flow-bar` has one `minmax(0, 1fr)` column, so the summary line truncates
with an ellipsis and Back + Start keep the bar's width (before, the grid's `auto`
column took the summary's full width and pushed Start off the right edge).
`.page-link` has `min-width: 0` for the same reason, and the colour swatches
shrink (`flex-1 max-w-8`) so 8 fit.

**Round 29: one main page.** New game holds every setting as a row: the
expansions (`SetupComponents.expansion_row/1`: icon, title, a line on the current
choice, `customise_button/1`, the switch), then Ingredient books and House rules
(`page_link/1` with a Customise pill), then Public. Customise is dim and not
tappable while its expansion is off. A gold dot (`.changed-dot`) on Customise
marks a change from the default: a witch picked, a patient picked, books that are
not the Beginner preset, a house rule changed (the pot side has its own row, so
`rules_summary/1` does not count it). Every other page (witches, patients, books,
rules) is a child of New game; a witch page is a child of witches, a book page of
books. From 64rem the right page next to New game is Ingredient books. The
Alchemists' patients page keeps only "Your patient": the rulebook draws 3 patients
from the bag at random, so the game has no "available patients" filter. Start and
New game (`.start-button`, `.flow-button`) are the gold primary of Draw and Next.

**Round 29: Share.** The waiting panel shows the room code large (Kalam,
letter-spaced, to read aloud) and a **Share** button (`#share-game`, primary) that
dispatches `quacks:share` with `{title, text, url}`; app.js calls
`navigator.share`. app.js sets `data-share` on `<html>` when the browser has a
share sheet; app.css hides Share without it (`.share-only`) and then shows Copy
link as the gold main button (`.share-fallback`).

Every page of the flow ends in one bar, `flow_bar/1` (`#flow-bar`): the setup in a
line ("3 players · 2 bots · Herb Witches · private") and whether Start opens the
table or begins the game, then **Back** (secondary, `.flow-back`) and **Start**
(primary, `#new-game`). The bar is the book spread's last grid row, outside the page
that scrolls, so it never moves; on the Games page it is `hidden`. Back goes to the
page's parent (the browser's history when the visit came from there). From 64rem
the New game page is always open on the left and the bar sits under the right page;
there Back from New game or Expansions goes to the Games page (`#flow-back-home`,
`max-lg:hidden`). The row whose page is open on the right is marked (`data-open`).
`.flow-back` is in `@layer components`, so `lg:hidden` on it wins.

The book fills the locked lobby root: `.lobby-screen`, `.spell-book`,
`.book-cover` and `.book-spread` are flex or grid boxes with `min-height: 0`, and
each `.book-page` scrolls on its own. The Games page's foot (`.page-foot`, New game)
stays at the bottom, and only `#games-scroll` scrolls: the games list, then the
install button and the credits. On a phone on its side (`height < 32rem`,
landscape, at least 35rem wide) the hero goes and the page becomes a grid: the room
code over New game on the left, the list on the right. Below 64rem the
expansion cards are a list of full-width rows (icon, title, blurb, switch); from
64rem they are three cards.
`.start-button` and `.flow-button` are ink buttons in the display font with a gold
hairline inside. The presets are a grid of `.preset-card` buttons;
`aria-pressed` marks the preset that matches the books
(`Quacks.Rules.BookPresets.match/1`) or Random's last roll.

## Tailwind: full class names in maps

Tailwind v4 scans the source for class names (`@source "../../lib/quacks_web"`,
`assets/css/app.css:8`) and finds only *literal* strings. `"bg-player-#{seat}"` would
build a class Tailwind never saw, so its CSS would not exist. So the seat classes
are a map of full names (`lib/quacks_web/components/chip_components.ex`):

```elixir
# Seat colours (theme tokens `--color-player-N`, see `seat_style/1`), as full class
# names so Tailwind finds them in the source.
@seat_bg %{
  0 => "bg-player-0",
  1 => "bg-player-1",
  ...
```

The chip colours work the same way (`@colours`, lines 19-29).

## Seat colours are CSS variables

The theme defines 8 palette colours and one variable per seat
(`assets/css/app.css:64-83`): `--color-seat-5: #e86a9e;` and
`--color-player-0: var(--color-seat-0);`. Tailwind turns `--color-player-0` into
`bg-player-0`. The page overrides the seat variables with one inline style
(`lib/quacks_web/components/chip_components.ex`):

```elixir
def seat_style(colours),
  do:
    Enum.map_join(colours, " ", fn {seat, c} ->
      "--color-player-#{seat}: var(--color-seat-#{c});"
    end)
```

used as `<Layouts.app flash={@flash} full style={seat_style(@colours)}>`
(`lib/quacks_web/live/game_live.ex:864`). A colour change is one new `style` string;
the classes stay the same.

## From `legal_actions` to tappable chips

In every choice between chips the chips are the buttons. `chip_picks/1`
(`lib/quacks_web/live/game_live.ex:2233-2348`) asks each legal action which chips it
shows (`lib/quacks_web/live/game_live.ex:2351-2359`, shortened):

```elixir
defp pick_chips({:place, chip}), do: [chip]
defp pick_chips({:red, {_kind, chip}}), do: [chip]
defp pick_chips({:chip, {:upgrade, from, to}}), do: [from, to]
defp pick_chips({:chip, {:buy, chips}}), do: chips
defp pick_chips(_action), do: []
```

Each pick becomes a `<button phx-click={@click} phx-value-action={encode(action)}>`
with the chips inside (`lib/quacks_web/live/game_live.ex:2276-2281`). The tiles sort
in board order (`chip_order/1`, line 2416, from `Chips.sort_key/1`). Actions without a
chip ("Return all", "Done") become text buttons (`text_actions/1`, line 2413). A new
chip choice in the engine shows up as tappable chips with no new template, once
`pick_chips/1` knows its shape.

**Round 24: the whole ladder.** A book with tiers (Ghost's breath II: trade 1, 2 or
3 purple) listed only the rungs the player could take, so a player with 2 purple
never saw what 3 would bring. `ladder/1` in `game_live.ex` now lists every rung of
the open ladder choices in `me.chip_choices`, in order:

| Choice | Rungs | A rung is off when |
|---|---|---|
| `{:purple_trade, tier}` (Ghost's breath II) | trade 1, 2, 3 | not in `legal_actions`: "needs 3 purple, you have 2" |
| `{:ruby_move, greens}` (Garden spider IV) | pay 1, 2 rubies | too few greens on the last two spaces, or too few rubies |
| `{:upgrade, tier}` (Ghost's breath IV) | the tiers above `tier`, from `Books.get({:purple, 4}).tiers` | always (the reachable swaps are chip picks) |

A rung the player can take is the usual button; one they cannot is a greyed
`role="button"` with `aria-disabled="true"` and the reason under its label. The
legal rungs come from `legal_actions/2`, the off ones from the choice and the book
data: the engine is not touched. The decision's own button list skips the ladder
actions (`ladder_action?/1`), so no rung shows twice; "Done with chip actions"
stays at the foot.

One choice has more than one verb per chip: the Toadstool (red Set 2) can place a
chip, keep it beside the pot or return it to the bag. Round 22 gives it its own
rows (`red_rows/1` in `game_live.ex`): one row per waiting chip, the chip large on
the left, then three equal buttons, **Place** (primary, "after your last chip"),
**Keep** ("for later") and **Return** ("to the bag"), each at least 48px tall. On a
narrow phone (below 26rem) the buttons go under the chip. One line of help sits at
the top.

## Motion: CSS first, one hook where CSS cannot

The motion design is in `docs/research/animations.md`. The code uses the lightest
tool that works:

1. CSS transitions and keyframes. A server render starts them: a new node plays its
   `animation` once, a changed `style` runs its `transition`.
2. CSS custom properties that the server sets, for timing (`--beat`).
3. One JS hook, `PotMotion`, for paths that CSS cannot know.
4. One view transition, on the round counter only.

### Ids decide what animates

LiveView patches the DOM and matches old and new elements by `id`. The same id: the
element stays and gets new attributes, so a CSS transition can run. A new id: a new
element, so its CSS `animation` plays once. This is React's `key`.

```elixir
# Fixed per seat, space and placement, so LiveView patches the same node and a new
# chip is a new node (its landing plays once), also on a space a returned chip
# left. Your own pot, the first chip on space 5: `pot-chip-0-5-1`.
defp pot_chip_id(seat, index, placed, :lg), do: "pot-chip-#{seat}-#{index}-#{placed}"
```

(`lib/quacks_web/components/pot_components.ex`)

`placed` counts the chips this seat placed on that space this game (from the log).
A chip that lands where a returned chip was gets a new id, so it lands again
(`test/quacks_web/live/motion_b3_test.exs:39`).

The VP and ruby counters use the same idea the other way round
(`stat/1`, `lib/quacks_web/components/tile_components.ex`): the counter
keeps its id and `style={"--n: #{@value}"}`, so CSS counts up from the old value;
the inner `<span id={"#{@id}-#{@value}"}>` is new for each value, so its `stat-pop`
keyframe plays. In React you write `<span key={value}>` to restart an animation.

### The round results: the server numbers the beats, CSS keeps the time

After the evaluation (step B of the rules) the page replays what each seat gained.
There is no results dialog any more. The replay plays in four places at once:

- **the name cards:** the VP and ruby counters tick on their beats (round 12
  removed the *update chips*, "stopped", "+7 VP" and so on: the state badge and the
  counters already said it);
- **your pot:** the chips that a line is about light up, rubies fly to the ruby
  counter, "+N VP" tags float up, the droplet slides;
- **the books:** a book glows when its line comes;
- **the counters:** VP and rubies tick on their beat.

There is no timer on the server and none in JS for the order.

`QuacksWeb.Replay` (`lib/quacks_web/replay.ex`) is pure. It reads this round's log
entries and gives each line a *beat* (`lib/quacks_web/replay.ex:37-48`):

```elixir
def beats(game, seat, from \\ 0) do
  game
  |> round_entries(seat)
  |> Enum.map_reduce(from, fn entry, beat ->
    line = line(game, seat, entry, beat)
    {line, beat + span(line)}
  end)
  |> elem(0)
end

defp span(%{kind: :die}), do: 2
defp span(_line), do: 1
```

`Enum.map_reduce/3` is a `map` that also carries a counter: each line gets the
current beat, and the next line starts after it. A die line takes two beats (the
die rolls, then its text shows). Each line also names its *marks*: chip space
indices, `:droplet`, `:ring` (the scoring space) or `:essence`. Three functions
turn the lines into what each place needs:

- `highlights/1` (`lib/quacks_web/replay.ex:60-65`): `%{mark => beat}`, the beat of
  each mark's first line. The pot draws a gold `beat_ring` there.
- `updates/2` (`lib/quacks_web/replay.ex:125-138`): the results of one name card.
  Each is a sum (all the VP of the round) on the beat of its *last* line, so it is
  complete when it shows. The card counters tick on these beats.
- `pot_effects/1` (`lib/quacks_web/replay.ex:87-110`): the scoring sequence on the
  pot. One `%{kind: :ruby | :vp, at: mark, beat: beat, n: n}` per flying ruby (at
  most 3 per line) and per VP tag. `source/1` picks where it starts: a black ruby
  leaves the droplet, a green or purple one its chip, the space's own ruby the
  scoring space.

The templates write the beat into a CSS variable: `--beat` on each card counter
(`card_count/1` in `lib/quacks_web/components/tile_components.ex`), on each pot ring (`beat_ring/1`, lines 877-898), each pot effect (lines 509-549)
and each book (`book_line/1`, lines 2004-2016). One CSS formula turns every beat
into a delay (`assets/css/app.css:981-994`):

```css
.result-row {
  animation: update-in 320ms var(--ease-spring) both;
  animation-delay: calc(var(--beat-lead) + var(--beat) * var(--beat-step));
}
```

The server decides the *order*; CSS decides the *speed*. Since round 14 one plain
number sets it: `--beat-ms` (450 at Normal speed). The lead, the step and the die
roll follow it (`assets/css/app.css:1208`):

```css
:root {
  --beat-ms: 450;
  --beat-lead: calc(var(--beat-ms) * 0.6667ms);
  --beat-step: calc(var(--beat-ms) * 1ms);
}
```

The menu's Speed setting puts `--beat-ms` (450, 720 or 1125) on `<html>`
(`RevealSettings` in app.js). The cards, the pot, the books and the counters use
the same formula and arrive in the same patch (the shop phase begins), so they stay
in step with no code that links them. `PotMotion` cannot read a `calc()` from a
custom property (an unregistered property computes to its text), so it reads
`--beat-ms` and does the sum itself.

**The end of the replay.** Round 14 replaced the invisible `.replay-timer` (and the
pot's Skip) with the **reveal overlay** (next section): the replay ends when the
overlay ends. The server then marks the round seen, and its next render adds
`replay-done` to `#players-row`. One CSS rule per place shows the end state at once,
for example `:root:has(#players-row.replay-done) [data-role="beat-ring"]`.

`replay-done` must start fresh each round. A hidden `<i id={"replay-start-#{round}"}>`
mounts once per round with
`phx-mounted={JS.remove_class("replay-done", to: "#players-row")}`, in case JS added
the class.

**Optimistic UI versus server beats.** In React you often show the result at once
and let the server catch up (optimistic UI). Here it is the other way round. The
server state is final in the first patch: the VP are counted, the chips bought. The
animation only *delays how it shows*, with CSS delays on the final DOM. Nothing
waits for the animation, and a reload or a skip shows the same final state. In
Framer Motion you would write `transition={{delay: i * 0.45}}` or
`staggerChildren`; here `i` comes from the server as `--beat`. Because `Replay` is
pure, `test/quacks_web/live/replay_test.exs:43-122` and
`test/quacks_web/live/scoring_test.exs:45-60` test the order without a browser.

### The reveal overlay: one slide at a time (round 14)

The beats above are fast, and on a phone there was nothing to hold on to. The
overlay shows the round's reveals as *slides*, one at a time, in a modal
`<dialog>`: full screen on a phone (round 20), a bottom sheet on a tablet, centred from 64rem. The beats still play
under it; they are secondary now.

**Pure slides.** `QuacksWeb.Reveal` (`lib/quacks_web/reveal.ex`) has no state, like
`Replay`. `moment/1` names what there is to reveal: `{:card, round}` at the round's
start, `{:results, round}` in the shop phase, `{:final, 9}` at the game's end.
`slides(game, seat)` builds the list from the `Replay` lines and the log, with no
new engine data. Since round 20 the evaluation has one slide per scoring step (see
**Round 20** below), then one `:results` slide and (round 18) one `:standings`
slide; at the end `:final`, `:standings` and `:podium` (round 22). `test/quacks_web/reveal_test.exs` tests
it without a browser.

**Round 16: one results slide and a running strip.** The three closing slides
(scoring space, "also this round", summary) were one slide too many on a phone.
`results_slide/3` makes one row per seat in VP order (a tie to fewer rubies, then
the lower seat): space, coins, the space's VP and ruby, the update chips of
`Replay.updates/2`, the pot's chip counts, and the card, essence and witch lines
(round 18 moved them to a closed "Details", below). Five players or more scroll inside the list
(`max-h-[min(58dvh,30rem)]`), so Next stays under the thumb.

Each slide also carries `gains` (`%{seat => {vp, rubies}}`) and `standings`, the
running results after it. `running/2` is one `Enum.map_reduce/3` over the slides
from a base (the VP before the round's results, `Replay.before/2`; for the final
scoring the VP before the conversion). The component `strip/1` renders them as a
row of chips with a fixed height (`h-7`), so the slide under it does not move; the
slide's gain pops in on the same beat as the reward (`.reveal-gain`). The sum of
the gains is the round's VP, so the strip on the results slide shows the real
totals. No state in the LiveView: the strip is part of each slide.

**Round 18: a table, then the standings.** On a phone the round-16 results grid
fell to one column. The cause was not the layout: the tab had loaded the old
`app.css` before a deploy, LiveView reconnected it to the new server, and the new
markup used `grid-cols-[minmax(0,1fr)_2.5rem_...]`, a class with no rule in the old
stylesheet. A `grid` with no `grid-template-columns` is one column. Two fixes:

- `QuacksWeb.StaticCheck` (`lib/quacks_web/live/static_check.ex`), an `on_mount` in
  every LiveView: when `static_changed?/1` says the tab's `phx-track-static` assets
  are not the server's, it pushes `quacks:reload`, and app.js reloads the page (at
  most once a minute). In React the same problem is a stale chunk after a deploy;
  there you catch the failed `import()` and reload.
- The results are a real `<table>` (`table-fixed`, a `<colgroup>` for the widths).
  A table keeps its columns from the browser's own styles, so a missing utility
  class costs a width, not the layout.

The table had eight columns (seven since round 20, no space): rank, player (the name may wrap; the update chips sit
small under it), space, coins, VP, ruby, the bonus die face (`die_face/1`, still) and
the pot's green, black and purple chips (locoweed too with The Alchemists or a
locoweed book). The card, essence and witch lines wait in a `<details>` under the
table, closed.

Then a **Standings** slide (`standings_slide/2` in `reveal.ex`): every seat's total
VP and rubies, with `from_rank`/`rank` and the totals before and after the round.
The rows glide from the old order to the new one, with no JS. This is FLIP (First,
Last, Invert, Play) done by the server and CSS:

```heex
<div
  :for={row <- @slide.rows}
  id={"standings-row-#{row.seat}"}
  class="standings-row"
  style={"--rank: #{if @settled, do: row.rank, else: row.from_rank}"}
>
```

```css
.standings-row {
  position: absolute;
  top: 0;
  transform: translateY(calc(var(--rank) * var(--row-h)));
  transition: transform 700ms var(--ease-in-out);
}
```

The rows stay in **seat order in the DOM**: LiveView never moves a node, it only
patches one `style` attribute, and a changed `transform` is a CSS transition. If
the server sorted the rows instead, the patch would move the nodes and nothing would
animate (a JS FLIP would have to measure before and after the patch). The first
render has the old ranks (`settled: false`); `show_slide/2` in `GameLive` sends
itself `{:reveal_settle, ref}` after 300 ms, and that render has the new ranks. The
totals use the card counters' ticker (`.stat-tick`: `--n` is a registered integer,
so a new `--n` counts up). A stale settle message is ignored, like the Auto tick.
With reduced motion there is no transition: the rows jump.

**Round 20: one slide per scoring step, everyone at once.** A slide per (book,
seat) made a 4-player round 10 slides long, and you never saw the table side by
side. Now `results/2` in `reveal.ex` builds one slide per step, in this order:

| Step | Slide | Rows show |
|---|---|---|
| Bonus die | `:die` (`die_slide/2`) | every roll (base die and book G6), faces side by side, a reward tag under each |
| Black, green, purple | `:book` (`book_slide/5`) | the chips that count (small chips), black's targets ("vs" their dots and counts), the reward or "–" |
| Any other book that paid | `:book` | the same; e.g. blue III–VI pay VP or rubies while brewing |
| Scoring space | `:space` (`space_slide/3`) | coins (coin icon), VP, a ruby tag on each row that landed on a ruby |

Each slide has a row for every seat, in the final VP order of the round, so a row
does not jump between slides; a seat that did not score in the step is dimmed. A
step where nobody scores has no slide (`nil`, then `Enum.reject/2`). To find the
"other books", each `Replay` line now carries `book: {colour, set}` (from
`{:effect, book, _}` log entries, nil otherwise). The results table then adds only
the card, essence and witch lines (`gains`), so the strip ticks up step by step
and its last value is the table's total. The rows are one function component,
`step_rows/1`, with an inner block for the step's content and `:reward` and
`:lines` slots (both take `:let={row}`).

On a phone (`width < 40rem`) the overlay is the whole screen: `inset: 0`,
`height: 100dvh`, no rounded top. The sheet's × is a flex item above the slide, so
the slide container drops its `min-height: 100%` there; otherwise the bar with
Next would sit 32px below the screen.

The results table lost the Space column; the Coins header is the coin icon
(`piece_icon name={:coin}`, our own `coin.svg`), and the die column stacks up to
three faces, smaller as there are more (`die_size/1`: 20, 16, 12px), so a row
stays two lines high.

**Droplets last.** With the reverse pot side a droplet won in the evaluation waits in
`droplet_moves`. In the shop `Game.phase/2` is `:droplet_choice`, and its dialog
mounts with `auto_open={is_nil(@reveal)}`, so it already waited for the overlay;
`close_reveal/1` opens it ("Move the droplet" on the last slide). Only the
evaluation's own choices (`:chip_choice`, `:witch_choice`, books G2/G4/P2/P4 and the
gold witches) asked for the droplet first. The engine now lets the moves wait in
those two phases (`@droplets_wait` in `lib/quacks/game.ex`), so they come in the
shop, after the reveal.

**Per browser, on the server.** The LiveView keeps
`reveal: %{key, slides, index, tick}` (`open_reveal/1`,
`lib/quacks_web/live/game_live.ex:2739`). `put_game/2` calls it after every game
update: a seat that has not seen the moment (`seen`, see **seen** in
`docs/CONTEXT.md`) gets the slides from index 0. The list is taken once, so a bot's
move does not change what the overlay shows; the game itself does not wait. A
reload mid-reveal starts at the first slide. A spectator gets no overlay, except
the game's last slide once the game is over (round 22).

**Round 22: the new card over the pot.** A new card is no longer a slide in a
full-screen overlay. `GameLive` puts the card (`fortune_card/1` with `flip`) in the
pot square, absolute and not tappable, while `pot_card?/1` is true: the reveal of a
`{:card, _}` moment, or (phones only) a card choice with no drawn chips. The overlay
gets the class `reveal-card-sheet`: a bottom sheet at every width with the card's
name and Continue, and a clear `::backdrop`, so the pot is not dimmed. The text is
in the sheet as `sr-only`, because the page behind a modal is inert. While the big
card shows, the corner card is `visibility: hidden`, so its place waits empty.

When the sheet closes, `card_vt/2` pushes `quacks:vt` with `%{type: "card"}`
(`dispatch: :before`). app.js starts that patch as a view transition with
`types: ["card"]`, and only in such a transition the CSS gives the big card and the
corner card one `view-transition-name`:

```css
html:active-view-transition-type(card) .pot-card,
html:active-view-transition-type(card) .pot-square:not(:has(.pot-card)) #corner-card {
  view-transition-name: fortune-card;
}
```

The old snapshot is the big card, the new one the corner card, so the browser
shrinks one into the other. A new round does not name them, so the old corner card
does not fly into the new big card. Reduced motion: app.js runs no transition.

**Round 24: a tap before any sheet.** On a phone the round-22 bottom sheet covered
the card's lower half before the player read it. Now the card first hovers alone:

| Card | The tap (or Enter, Space, the Auto tick) |
|---|---|
| Does nothing by itself (most blue cards) | the card shrinks into the corner |
| Did something to this seat (a droplet, VP, a ruby) | the result sheet: name, one pill per outcome, Continue |
| Asks a choice | the card's choice dialog (`card-round-N`); the card stays over the pot until the choice |
| Draws chips (Safety Procedure, Flea Market) | its dialog, with the card in it; the big card shrinks |

The state is one flag on the reveal map: `held: true` while the card waits for the
tap (`start_reveal/3` sets it for a `{:card, _}` moment). `reveal_overlay/1` renders
only when `held` is false. `next_slide/1` has a clause for `held`: with outcomes and
no choice it sets `held: false` and shows the same slide again (now in the sheet),
else it ends the reveal, and `close_reveal/1` acks the card and pushes `quacks:open`
for a waiting choice. The choice dialog mounts with `auto_open={is_nil(@reveal)}`,
so it waits for the tap like every other decision. The old `reveal_step` clause
that marked a choice card seen at once is gone: the card is seen when the player
taps it.

"What it did" is `Reveal.card_outcomes/2`: the `{seat, {:fortune, id, outcome}}`
log entries since the newest `{:fortune_drawn, id}`. No new engine data; the text
is `GameText.card_outcome/2`, the log's own wording.

The tap target is one `<button id="card-tap">`, `fixed inset-0 z-40`, over the page
and under the dialogs' top layer: a tap anywhere goes on, and the pot does not move.
The big card stays `aria-hidden`; the button's `aria-label` reads the card's name
and text. Round 30: the bar shows one Continue that sends the same `card_tap`.
Under the card a "Tap to continue" caption (`.card-caption`) comes in once
the card has turned (0.8 s: the round title and the flip play first) and fades 2 s
later. It is hidden under `:active-view-transition-type(card)`, so the snapshot
that shrinks is the card alone.

**Round 24: the corner card grows back.** The corner card no longer opens the card
sheet: it pushes `card_grow` (`fortune_tile/1` takes a `click` attr; without it the
tile still opens `sheet-fortune`). `GameLive` sets `card_grown: true` and pushes
`quacks:vt` with `type: "card"` before the patch. The same two CSS rules name the
cards, in the other direction: the old snapshot is the corner card, the new one the
big card, so the browser grows one into the other. A tap on `#card-tap` (or Enter,
Space) shrinks it again, the same way. A new round clears the flag
(`same_round?/2` in `put_game/2`). The text sheet is in the menu now, "Fortune
teller" (`data-role="menu-fortune"`). From 64rem the context column still shows
the card as before; the grown card shows there too (`pot-card-reveal`).

**Round 25: grow back without the flip.** The big card over the pot renders with
`flip` (`.card-flip`, the back turning to the front) only for a new card. The grown
corner card renders the plain face (`flip={!@card_grown}`), so the card transition
alone plays: the shrink run backwards, small to big over the pot.

**Round 22: the end in one flow.** `{:final, 9}` has three slides: `:final` (coins,
rubies, pennies), `:standings` (from before the final scoring to the end) and
`:podium`. The last one renders the overlay's `:podium` slot, which `GameLive`
fills with `game_over/1`: the rising podium, the VP breakdown, Play again, Back to
lobby and Share (`quacks:share` in app.js: the share sheet, else the clipboard).
That slide has no bar and no tap-to-Next, Next does nothing there, and Auto mode
starts no timer for it. × or Esc close it; "Show the result" opens it again
(`show_result` → `open_result/1`). A page that mounts on a finished game, a
reload, a rejoin or a spectator, opens straight on that slide
(`result_on_mount/1`). There is no `#game-over` dialog any more.

**Round 29: one final tally.** Round 9's results end on the last scoring step:
no `:standings` slide, and with nothing left to decide the button says "Continue"
(not "Done"). `{:final, 9}` now has two slides: `:tally` and `:podium`. The tally
reuses the standings' CSS FLIP (`.standings`, `--rank`): every row starts at the
seat's round-9 total and rank; its final parts (coins, rubies, pennies → VP,
`parts: [{kind, count, vp}]`) pop in one after the other (`.tally-part`, `--i`);
then the settle tick (`settle_ms/2`, after the last part) sets the new totals and
ranks, so the counters count up (`.stat-tick`) and the rows glide. The final
scoring plays in Auto mode for everyone (`reveal_mode/2`; reduced motion keeps
Step). A tap on the tally while it plays settles it at once and pauses Auto
(`paused: true`); the next tap shows the podium. The podium has no VP breakdown
any more: this browser's place has a gold ring and "you" (`you_tag/1`), and the
actions stick to the sheet's bottom edge (`.sticky-actions`; a parchment backing
only while stuck, with the `scroll-state` container query).

Two fixes of the same round: a `/debug/replay` seat taken by this browser is no
bot any more (`GameServer.start_debug/2`; the podium said "You win!" over a
bot's name), and the card's choice button (phones) says "Continue". From 64rem
the card's result sheet sits in the right context column; on a phone on its side
the overlay is the right column at the pot's height and its slides fit without a
scroll (the landscape block after `.reveal-sheet` in app.css).

**Controls.** `reveal_overlay/1`
(`lib/quacks_web/components/reveal_components.ex:35`) renders the slide and a bar:

| Input | Event | Effect |
|---|---|---|
| Next, a tap on the slide | `reveal_next` | next slide; on the last one, the end (not on the game's last slide) |
| Enter, Space (focus not on a button) | `hotkey` | as Next |
| Skip | `reveal_skip` | the last slide |
| Esc, × | the dialog's `close` → `reveal_close` | the end |

The end (`close_reveal/1`, line 2796) acks the moment (`GameServer.ack/4`, now
also `:final`), runs `auto_done/2` and pushes `quacks:open` with the dialog that
waited: the shop or a decision. app.js opens it with the usual
`sideOpen` (`assets/js/app.js:336`). Decision dialogs mount with
`auto_open={is_nil(@reveal)}`, so nothing opens under the overlay. The overlay is
the last element of the page, so `remodal` keeps it on top.

A fortune card that asks this seat a choice keeps its own dialog (the card and the
choice in one). Since round 24 that dialog waits for the tap on the hovering card,
and the card counts as seen at that tap (see **Round 24** above).

**Step and Auto.** In Auto mode `show_slide/2` starts a server timer:

```elixir
tick = if assigns.reveal_mode == :auto and connected?(socket), do: make_ref()

if tick do
  ms = reveal.slides |> Enum.at(index) |> Reveal.duration(Reveal.factor(assigns.reveal_speed))
  Process.send_after(self(), {:reveal_tick, tick}, ms)
end
```

`handle_info({:reveal_tick, ref}, ...)` (line 580) only matches the current `tick`,
so a tick from a slide that Next already left does nothing. This is the LiveView
form of `clearTimeout`: you cannot cancel the message cheaply, so you make old
messages harmless. In React you would keep the timer id in a `useRef` and clear it
in the effect's cleanup.

**The settings.** The menu has two segmented controls (`reveal_settings/1`):
Reveal (Step or Auto) and Speed (Normal, Slow, Slower = 1×, 1.6×, 2.5×). They
belong to the browser, not the game, so they live in `localStorage`
(`quacks:reveal`), like the host's `quacks:config`. The `RevealSettings` hook
(`assets/js/app.js:79`) sends them on mount with `reduced` (prefers-reduced-motion),
and saves each change; the form's own `phx-change` tells the server. With reduced
motion the server forces Step and runs no timer. app.js also sets `--beat-ms` before
LiveView connects, so a reload plays the beats at the saved speed.

### The evaluation on the tiles (round 27; see round 28 below)

On the branch `round-27-eval` the menu's reveal settings have a third row,
**Results**: Overlay (the default) or **On tiles** (`quacks:reveal` keeps `show`).
On tiles, the results' reveal plays only its scoring steps (`TileReveal.slides/1`:
the bonus die, the books, the scoring space) and no dialog opens. The same
`%{slides, index}` state and Auto ticks run it; a step lasts 5 beats
(`TileReveal.duration/1`, `--beat-ms`). `tile_stage/1` names the step, with Next
(Step mode) and Skip (a pill over the pot until round 29; now in the bar). Each tile shows its seat's
badge for the step (`tile_gains/1`: the book's ingredient, VP, rubies, droplet),
which folds into the tile's counters; the counters show the running totals
(`TileReveal.totals/3`) and count up from the old value (`.tile-count`). The die
face stays by the crown until the next round; in the shop the bought chips and the
droplet pushes show on the tile (`TileReveal.shop/2`, from the log).

### Round 28: the tiles are the evaluation on phones

**Phones.** The `RevealSettings` hook (app.js) sends `phone: true` when the
screen is under `sm` (40rem, `matchMedia`), and again when that changes. On a
phone `GameLive` plays the results on the tiles whatever the Results choice says
(`reveal_show` is the effect, `reveal_choice` the saved choice), and the menu
hides the Results row (a hidden `phone` input keeps the form's own changes
right). Larger screens keep the choice, the overlay by default. The server cannot
read the width, so this is the one bit of JS; CSS alone cannot pick a server mode.

**No results table.** `Reveal.slides/2` goes from the scoring steps to the
standings, in both modes. The standings slide carries the gains that no step
showed (cards, essence, witches), so the running totals end on the real totals.
The player sheet keeps each seat's result lines.

**A slimmer tile.** No name text: the seat disc has the initial (and a small bot
icon); the name is the tile's `title` and an `sr-only` span. Top line: the disc,
the pot space and the VP in `text-xl`; the die faces (`rolls`) sit by the crown on
the tile's top edge, so the top line keeps its room (on the die step they come in
as the news goes). Bottom line (`#tile-line-N`): rubies, the droplet,
the flask (full or used), the black chips in the pot only while black book I is in
play (`black_counts?/1`; books II and III do not compare pot counts), then the
extras while they fit. At 360 px with 4 columns the line holds the four main
items (tighter padding under `sm`); the extras drop first.

**Cards that draw chips (round 30).** Once a seat has chosen and the card is gone,
its news line shows what the card gave it (`Quacks.Game.Fortune.reveals/1`): Flea
Market the chip it traded and the chip it got, Less is More the blue 2 or the ruby
(badge `{:card, id, traded, got}` or `{:rubies, 1}`). Safety Procedure's placed chip
is a draw, so the draw news shows it. `news/3` gives nil while a card is on screen.

**Card reveal rows (round 30).** `QuacksWeb.CardRevealComponents.card_reveals/1`
shows `Fortune.reveals/1` as one row per player: the seat disc with the initial,
the drawn chips (`:sm`; `compact` uses `:xs`), the sum (Less is More), and the
result (a chip, a ruby, or the chip placed on the pot). Your row is first and has a
gold ring; the best row (the lowest sum) has a gold fill. Three places use it: the
new card's result sheet after the tap (the `:card` slide's `reveals`), the fortune
sheet (`#sheet-fortune-reveals`) and the grown corner card (`compact`, only while
grown). Your Flea Market chips have a title that says why a chip could not go up.

**News on the bottom line (R2).** `TileReveal.news/3` gives a tile's news, or
nil: the die faces on the die step, a book's ingredient and rewards, the space's
VP and ruby, and the chips bought and the droplet pushes: in the shop, or the
last shop as the next round begins (the bots' buys show only once the last human
is done, `GameServer`). While the steps play the rat track follows the tiles'
running VP (`rat_track/1`'s `vps`). The bottom
line holds both the totals (`.tile-totals`) and the news (`.tile-news`); with
news (`data-news`) CSS swaps the line to the news and back over 5 beats, the
totals coming back as the step's counters count up. The line's id has the news
key, so new news is a new element and the swap plays again. Nothing hangs outside
the tile. While a step plays the droplet shows its running value
(`TileReveal.droplets/3`).

**The last draws while the round brews (round 29, B2).** In the `:potions`
phase `news/3` gives the seat's last draws (`{:drew, chip, age}`, newest first,
straight from `player.drawn`) with `hold: true`, whatever the Results choice
says. How many depends on the tile's width (`tile_draws/1`: 3 with four columns,
up to 7 with two). `data-hold` keeps the line on the news (no swap back); the key
is the draw count, so each draw slides in again. The newest chip glows once
(`.tile-draw-glow`, `beat-glow`), the pot space pops when it changes (its id has
the space), and an exploded tile shakes once (`.tile-boom`).

**The type scale (round 29, B3).** Four tokens in `app.css` `@theme`: `text-tag`
13 px (the floor), `text-label` 15, `text-num` 18, `text-big` 24. Numbers and
labels on the game screen use them, never less than `text-tag`; where space is
tight, drop the label and keep the icon and the number. The pot SVG has its own
units: `@pot_tag` is 13 px at the smallest phone pot (328 px wide), so the
coins, the VP seals and the chip values are at least 13 px there.

**Every VP on the rat track.** Each dot has its VP: one number for seats in a
step with the same VP, the numbers of a step alternating above and below the line
(`track-vp`; the leader's is `leader-vp`).

### Round 29: the bar carries every action

The two slots of Stop and Draw (`min-h-12`) are the one place for "what do I do
now". What takes their place keeps that height, so the pot (a flex child above the
bar) never moves:

- **Draw** (no "a chip") and Stop. After Stop the phase pill says "Waiting"; Draw
  stays greyed.
- **The white meter row** holds the reward and the risk as icons
  (`BarComponents.reward_line/1`): coin and count, laurel and VP, the ruby, then
  the explosion icon with the menu's **Risk** setting (Off, Percent, Chips "3/14").
  The setting is one more `segments` row in `reveal_settings/1`; `RevealSettings`
  keeps it in `localStorage` (`quacks:risk`) and sends it with the others, so the
  server renders only the chosen form (no CSS toggles).
- **A choice in the bar** (`BarComponents.bar_choice/1`, assign `@bar_choice`): the
  explosion's Take VP / Take coins, and the rubies step (Skip, test tube, flask,
  pot; "2" + ruby on each paying button, the seat's `ruby_price`; a disabled use
  says why). These decisions open no dialog (`open_waiting/1` skips them, and the
  "Back to choice" button hides). A rubies step with a witch to call keeps the
  dialog: the witch card does not fit the bar.
- **The explosion's beat** is CSS on insert, like the pot shake: `.boom` (BOOM in
  Kalam over the pot, 700 ms, `forwards`) and `.bar-choice-late` (the choice
  waits 700 ms, `visibility: hidden` in the `from` keyframe with fill `both`, so
  it cannot take a tap meant for Draw). Reduced motion swaps both to plain fades
  of the same length. The one bit of JS is the `Boom` hook: `navigator.vibrate`
  once per game and round (`sessionStorage`), guarded when the browser has none.
- **The evaluation steps** on the tiles (`tile_stage/1`): the step's name and
  number, Skip and Next, in the footer instead of a pill over the pot. The other
  footer buttons hide while it plays.
- **The shop** says **Skip** for "buy nothing". With chips ticked, Buy is the wide
  primary and Skip shrinks to a small secondary button. (Round 35: Skip is gone;
  see below.)

### Round 30: no stats strip; the bar and the pot

- **No stats strip.** The parchment row over the tiles (`status/1`) is gone on every
  screen: VP is on your tile and the rat track, the flask is drawn at the pot, the
  coins to spend are in the shop sheet's footer (`shop-total`). The height goes to
  the tiles and the pot. Measured at 392 px (8 players): the pot box stays at
  16,284 360x360 through the card, brewing, stopped, the evaluation, the rubies
  step, the shop and an explosion.
- **The ruby badge** (`TileComponents.ruby_badge/1`) sits in the pot's top right
  corner (`pot-corner-right`), the kept Toadstool chips under it. It keeps the id
  `stat-rubies`, so `PotMotion` flies the scoring's rubies to it and it ticks on
  their beat (`stat_beats/3`, rubies only now).
- **Continue** (`#card-continue`) is the contextual button area while the round's
  card waits over the pot (`card_continue?/1`: a held new card or a grown corner
  card, no choice in the bar). It sends `card_tap`, so it does what a tap on the
  card does (into the corner, or the result rows or the choice); Enter does the
  same (`hotkey`). It sits above `#card-tap` (`z-50`). Stop and Draw stay in the
  DOM with `hidden`, as for a decision.
- **Fixed number widths.** Kalam (`font-hand`) has no tabular figures: its digits
  are 5.4 to 10.6 px wide at 18 px with or without `tabular-nums`. Its numbers get
  a box of two digits, `min-w-[1.2em]` (tile pot space, tile VP right-aligned, the
  ruby badge). The bar's numbers are in the system font: `tabular-nums` and
  `min-w-[2ch]` (coins, VP), `[4.5ch]` (percent), `[5ch]` ("3/14"). The reward row
  always has the ruby slot (`data-ruby`, `opacity-25 grayscale` when the space
  pays none). The rat track's numbers are absolute: they move no layout.
- **One explosion icon** (`explosion_icon/1`: the `:explosion` piece icon,
  `text-ruby`) is the bar's risk and an exploded tile's badge.

### Round 31 (eval): one update per step, black and white on tiles, the end in place

- **One update per step.** `TileReveal.slides/1` splits the scoring space into
  up to three steps (`part`: `:coins`, `:vp`, `:rubies`), each with its own
  `gains`. While a step shows, everything reads the totals after that step
  (`tile_totals/2`): the tiles, the rat track, the pot's droplet (`pot/1`'s
  `droplet` attr) and the ruby badge (`ruby_total/4`; it ticks on the rubies
  step only, `stat_beats/4`). The pot plays only the shown step:
  `TileReveal.step_lines/3` takes the step's `Replay` lines and renumbers them
  from beat 0, so its ruby flights and VP tags play when the step comes; their
  ids carry the step (`fx_key`), so `PotMotion` flies them once per step. The
  coins step lights the scoring space (`TileReveal.marks/3`). The phone die
  strip shows on the die step only. Server state is final already: this is
  display only.
- **Next scores the step the bar names.** On the tiles `reveal.index` is the
  pending step: `tile_totals/2`, `tile_slide/1` (the step scored last),
  `TileReveal.news/3` and `tile_rolls/3` (the die faces by the crown) read the
  steps before it, so nothing of a step shows before its Next. After the last
  step `next_slide/1` goes one past it: the bar says "Round scored" and its
  button closes with the close label. The bar's picture (`step_icon/1`): a book
  step is its chip (value hidden), the die and the space parts their pieces.
- **A draw on the tile.** Draw news carries `line`, so the tile line keeps its id
  while the round brews; the chips' ids carry the draw count, so they enter
  again on each draw: `tile-draw-pop` for the new one at the left,
  `tile-draw-slide` (14 px) for the older ones.
- **Black and white on the tiles.** While the round brews (`:potions`), a tile's
  bottom line ends in `tile_brew/1`: the black count and the white sum against
  the limit ("4/7", `Potions.explode_above/2`; `data-level` safe / warn / danger,
  like the fuse). The draws stay on the left; with 5 to 8 players (four columns)
  two draws fit, and older draws tuck 4 px under the newer one. Out of brewing
  the stats line has its black count again.
- **The end in place.** No final slides and no game-over sheet. When the game is
  over, `FinalComponents.final_board/1` lies over the pot (absolute in the pot
  square, so the pot does not move): the title, then one row per seat from
  `Reveal.final_rows/1`; each total counts up from the round-9 VP (`.final-count`,
  a registered `--n` animated from `--from`). `final_actions/1` takes the
  contextual button area: Lobby, a small Share, Play again. A reload or a
  spectator sees the same; nothing is "seen" for it.

### Round 31: no full-height sheets; cards and decisions over the pot

- **A card with no choice has no sheet.** `next_slide/1` on the held new card ends
  the reveal at once. A card that drew chips for everyone (P8, P13, B7:
  `card_rows?/1`) sets `card_grown`, so the card stays over the pot with every
  player's rows (`card_reveals compact`); Continue or a tap shrinks it. Any other
  card shrinks into the corner, and `card_toast/2` puts one line over the pot
  (`#card-toast-N`, `.card-toast`: it fades in, then out after 2.8 s by itself),
  e.g. "Drop It: Droplet +1", from the slide's `outcomes`. The reveal overlay's
  card slide is no longer shown.
- **A card's choice is the bar.** `bar_choice(:fortune_choice, _)` gives
  `bar_choice/1` with `choice: :fortune_choice` (`#bar-card-N`): one button per
  `{:fortune, choice}`, an icon (the chip, chip → chip for a Flea Market trade, or a
  piece icon) with a short title and a hint line (`card_choice_title/2`,
  `card_choice_hint/3`), like the explosion's VP/coins pair. Round 33: the
  buttons are a grid (`choice_grid/1`, `choice_button/1`), 5 to 8 options in two
  rows, never a sideways scroll. The card stays over the
  pot (`pot_card?/1` is true for every `:fortune_choice`, on every screen) and
  shows the rows for the cards that drew chips; there is no `#card-tap` layer then
  (`card_tap?/1`). The choice sent closes the held reveal (`close_card_reveal/2`),
  and the card shrinks into the corner. The card's dialog (`#card-round-N`) is gone.
- **Decisions cover the pot.** `dialog_sheet` has `pot`: below 64rem app.js opens
  it with `show()` (non-modal, no backdrop) and app.css places it over the pot
  column: anchored to `[data-area=pot]` (`anchor-name: --pot-area`; its foot on the
  column's foot, as high as its content, at most the column), else a fixed box
  above the bar. The header, the players row and the bar stay in view; × closes it
  and the bar's reopen button brings it back. The shop's footer (purse, Skip, Buy)
  goes where the bar's buttons are (`position: fixed` at the screen's foot). Every
  `decision-*` dialog uses it. The tall popover sheets (player, witches, patient,
  Forgetfulness, fortune card) take the class `sheet-pot` for the same place.
- **What stays full height:** the final scoring overlay (the eval and end
  builder's), the books drawer (a reference), the menu, the bag, the log and the
  bug report (not game moves).
- **Rubies.** The rubies step stays in the bar (`bar_choice :rubies`), shown only
  when a ruby buys something (`ruby_step_action?/1`). Round 9's `{:rubies, :vp}`
  is no step: the seat's "Done" converts what it keeps (`final_conversion`), so a
  round-9 seat with no witch to call ends its round after the evaluation
  (`auto_done/2`). Round 37: on the reverse pot side round 9 offers a glass
  (`{:rubies, :tube}`), so the step shows there with two uses, tube and 1 VP
  (`ruby_uses/1`). The gold witch G4 ("Cheap rubies") has her own button at the end
  of the rubies bar (`data-role=rubies-witch`) while the seat has a ruby;
  `bar_choice/3` keeps the bar for her, and only another witch call opens the sheet.

### Round 33: the bar as the context area

Nick's rule: use the bottom context area, not a modal. A turn's small choices are
**bar choices** (`bar_choice/2` picks them, `bar_choice/1` renders them), in
`lib/quacks_web/live/game_live.ex`:

- **The grid.** `choice_grid/1` takes `count`: 1 to 4 buttons in one row, 5 or 6 in
  rows of 3, 7 or 8 in rows of 4 (`grid_cols/1`), all one width; `data-rows` says
  1 or 2. `choice_button/1` is one button: a picture in its own box (a chip, a
  piece; the chip's value badge never covers the text), a short title, a hint line.
  `action: nil` or `disabled` greys it. The bar keeps its fixed height
  (`--bar-h`); `.game-bar` sets its content at its foot, so a second row (and the
  info row) rises over the pot's lower band and the pot never moves.
- **The info row.** `info_row/1` sits over the buttons, where the white track's
  row is while brewing (`info_choice?/1` hides the fuse row). An icon slot and the
  text: what the step is.
- **Chip actions** (`:chip_choice`, also the locoweed's return while brewing): the
  info row names the books (`pick_title/2`, `rung_title/1`); the picks are chip
  buttons (`chip_item/3`), the ladder rungs follow (`rung_item/3`: a rung out of
  reach is greyed, its reason the hint), then Done when `:chip_done` is legal.
- **The droplet's free move** (`:droplet_choice`): the info row shows the cause
  (the hawkmoth's chip, the die) and its line; the buttons are Pot droplet and Test
  tube (the next glass's bonus). The test-tube strip stays where it is.
- **The sweep** (`@pick_choices`, `pick_spec/4`): the Mandrake, the crow skull and
  the silver witch (`pool_items/5`: every chip of the pool, greyed without an
  action, then Return all), the Toadstools (the first chip that waits, Place / Keep
  / Return) and the patient offer (`text_item/3`: the cost as the title).
- **The bonus die** on phones is an info row (`#info-die`) over the step bar, not
  in the tray over the test tubes.
- **The test-tube droplet** moves: `test_tubes/1` takes a required `id` and the
  colocated hook `.TubeDrop` (`Phoenix.LiveView.ColocatedHook`, in the component's
  template). On `updated()` it compares `data-tube` with the last one and animates
  the new droplet with WAAPI `translate` from the old glass (28 SVG units a glass)
  on a low arc; reduced motion: nothing. It is not in `PotMotion`, whose size is
  budgeted.

### Round 35 (eval): the results stage, and each choice on its step

**The results stage** (`TileRevealComponents.results_stage/1`, direction A of the
round's design page) is a parchment panel in the band above the bar's buttons.
It floats (app.css `.results-stage`: absolute, from the top of the step bar,
growing upwards), so the pot never moves. It shows the step on show, one row
per player in one column for every player count: the colour disc with the
initial, the short name, the reason and, at the row's end, the result. Both are
icons where possible (`TileReveal.stage_rows/3` gives cells such as
`{:count, 2, :black}`, `{:beats, seats, :both}`, `{:dice, faces}`, `{:vp, 1}`).
A row with no result fades. The bonus die rolls at the end of each roller's row
(`.stage-die`, one roll after the other per seat), and Auto waits for the rolls
(`TileReveal.duration/2`). A chip with no value (`{colour, nil}`) shows its icon
in the centre with no badge.

**The steps.** The step on show is `index - 1`; the first shows at once (index
1), and the bar names the step on show. The scoring space is one step again
(coins, VP and ruby in one row). The standings slide stays as the last step,
**Round scored**: the totals in VP order, equal VP share a place, the leader's
row is gold. Auto is the default mode (app.js, nothing saved); Step stays in the
settings.

**Rubies before Round scored.** Next on the step before it holds the steps
(`reveal.rubies`) while a ruby buys something: the bar shows the ruby uses with
**Keep** (`rubies_keep`), the panel collapses to one line. The engine allows the
ruby uses in the buy step too, so this works before the shop; rubies decided here
skip the shop's rubies step after the buy (`decide/4`).

**Choices on their steps.** On the tiles the results begin with the chip actions'
choices (`reveal_key/2`: `{:results, round}` in `:chip_choice` and
`:witch_choice`). The slides follow the game (`refresh_tiles/1`,
`TileReveal.live/2`): while the evaluation asks, there is no scoring space yet,
and a book with a waiting choice has its step at once. A decision holds the step
on show (`tile_hold/1`): a free droplet move on the step that won it (more moves
waiting than the later steps bring), a chip actions' choice on its book's step
(only that book's actions in the bar). **Done** there moves on to the next book
with a choice of this seat, else it ends the choices; a choice left only in a
passed step ends by itself (`end_choices/1`). At the end of the steps while
others still choose, Next says "Waiting…". The panel hides while the droplet or
a chip choice is asked, so the pot and the test tubes show.

### Round 35: choices in the bottom row, the shop always buys

- **The crow skull** (`bar_choice/1`, `:blue_choice`) is one row, in the button row
  only: the drawn chips (`:lg`, each a button, greyed without an action) and Skip
  (`:return_all`). The fuse row (the white track) stays over it
  (`info_choice?(:blue_choice)` is false). The colocated hook `.FromBag` animates
  with WAAPI: on `mounted()` each chip flies out of the bag button
  (`[data-role=bag-button]`) to its place, 140 ms apart; on a tap the chips not
  chosen fly back into the bag and the chosen one fades. To let them land, the row
  has `phx-remove={JS.transition("bar-to-bag", time: 520)}`: `.bar-to-bag` takes it
  out of the flow (absolute, over the bar's foot, no pointer events), so Stop and
  Draw take their place at once. Reduced motion: fades only.
- **Choices, Choices** (P1, `:fortune_choice` with `fortune_card: :p1`) is one row
  of the black chip, the 2-chips and the ruby with "3" inside
  (`data-role=ruby-count`); no info row, no grid. Other card choices keep the grid.
- **What everyone took.** `Fortune.reveals/1` also has rows for the cards that
  offer every seat a choice (`Fortune.choice_card?/1`: P1, P3, P6, P9, P10, P11,
  B2). When this seat leaves `:fortune_choice` (`chose_card?/3` in `put_game/2`),
  the card grows over the pot (`card_grown`) with `card_reveals compact`: one row
  per player, the disc and initial, then what it took with icons (`+3` ruby, `+4`
  VP, `+2` droplet, a chip, `−` the white chip, `−n` rat), "passed", or
  "choosing…" while that player still chooses (it updates live). Continue or a tap
  shrinks it. The new card's slide and the result tiles keep rows for the draw
  cards only (`Fortune.reveal_card?/1`).
- **The Toadstools beside the pot** (`aside/1`) stack in a column with a small gap,
  so each value badge shows.
- **The shop** has no Skip: a player always buys a chip (a UI rule; the engine
  still takes `{:buy, []}` and the bots are unchanged). Buy is the one button,
  disabled until a chip is ticked. Only when no chip is affordable and the shop
  still shows (a copper witch keeps it open; else the buy step is skipped) does
  **Nothing to buy** (`data-role=shop-done`) take its place.
- **The shop's book text** opens in place and dispatches `quacks:reveal` to it;
  app.js waits for the 150 ms "in" transition, then `scrollIntoView({block:
  "nearest"})` scrolls the sheet just enough to show all of it.

### `PotMotion`: animate on top of the patch

Some motion needs a path or a measured target: a ruby flies from a chip to the
ruby counter in the header, a returned chip flies to the flask or the bag. CSS
cannot do this, because it does not know where the counter is. So your large pot
carries a hook: `phx-hook={@size == :lg && "PotMotion"}`
(`lib/quacks_web/components/pot_components.ex`). The hook is in
`assets/js/app.js:80-197`.

A hook is an object whose callbacks LiveView calls around each patch: `mounted`,
`beforeUpdate`, `updated`, `destroyed`. Think of `useLayoutEffect` with a ref, but
the element comes from the server. `PotMotion` does FLIP (First, Last, Invert,
Play):

- **First.** `beforeUpdate()` (`assets/js/app.js:96`) calls `snapshot()`
  (lines 154-158): the chip ids, the flask, the round.
- **Last.** LiveView applies the patch. The DOM now shows the final pot.
- **Invert and play.** `updated()` (lines 97-111) compares. A chip with a new id
  drops in on its space (`land`, lines 169-178). Round 31: when one chip is new and
  the pot is your own (`data-mine`, set when the pot has your flask), `fly` takes it
  out of the bag instead: it starts small at the bag, follows a quadratic arc above
  both ends (six sampled keyframes) and lands on its space with the pop, 460 ms.
  It mirrors the ghost that flies a returned chip to the bag. Reduced motion: no
  flight. A chip that went away flies as a
  ghost to the flask or the bag (`ghost`, lines 181-196). At a new round the old
  chips fade and the new rats slide in from the droplet (`ratsIn`, lines 142-153).
  Round 32: when your newest move paid rubies for the droplet, the server marks it
  (`data-hop="rubies"`) and `hop` makes it jump from its old space (the snapshot's
  `data-index`) to the new one on a low arc with a 1.3× lift, 520 ms, over the CSS
  slide (a WAAPI `translate` beats the CSS transition). A flask that became full
  fills: the brew rises 34 px inside the flask's clip group, 700 ms. If that spend
  ends the round (nothing left to spend), the page waits 800 ms
  (`done_after/2`, `:show_move_ms`, 0 in the tests) before it sends `:end_round`,
  so the next round's card does not cover the move.
  Then `flights()` (lines 121-139) sends each new `[data-role=ruby-flight]` to the
  ruby counter, with the same delay formula as the CSS (it reads `--beat-lead` and
  `--beat-step` from `:root`). Each one is `el.animate(frames, opts)`, the Web
  Animations API, with only `transform` and `opacity`.

Why patches and client animation do not fight:

- **The patch comes first.** The DOM is already final. The animation only moves the
  element from where it seemed to be to where it is. A tap never waits for it.
- **Fixed ids** (above) make "new chip" mean "an id not in the snapshot". Each chip
  also has `data-index` and `data-order` (`lib/quacks_web/components/pot_components.ex`),
  each space has `data-x` and `data-y` (lines 371-372), and each pot effect carries
  its own `data-x`, `data-y` and `data-beat` (lines 515-520). The hook reads the
  positions from the server's spiral and measures only the target (the counter,
  the bag).
- **Each flight plays once.** The hook keeps the ids it has flown in a `Set`, so a
  later patch (a bot's draw) does not fly the same ruby again.
- **Exits get their own layer.** LiveView has already removed a returned chip.
  `ghost` puts the detached element into `<g data-role="pot-fx" phx-update="ignore">`
  (`lib/quacks_web/components/pot_components.ex`), a layer that LiveView
  promises not to patch, and removes it when the animation ends.
- **One set of curves.** `easing("--ease-spring")` (`assets/js/app.js:77`) reads the
  CSS custom property, so CSS and JS use the same easing.

| Framer Motion | Here |
|---|---|
| `layout` / `layoutId` (FLIP by measuring) | `PotMotion` snapshot + `updated()`, positions from `data-x`/`data-y` |
| `key` | the element `id` |
| `<AnimatePresence>` exit | `ghost` in the `phx-update="ignore"` layer |
| React holds the old element until the exit ends | LiveView removes it at once; the hook plays on a detached copy |
| `staggerChildren` | `--beat` from the server, one CSS delay formula |

### One opt-in view transition

At a new round the round counter rolls up to the next number. `mark_round_change/2`
(`lib/quacks_web/live/game_live.ex:2552-2559`) pushes the event `quacks:vt` with
`dispatch: :before`, so the browser gets it before the patch. In `app.js`
(lines 199-227) the event sets a flag, and the `dom.onDocumentPatch` option of the
`LiveSocket` runs that one patch inside `document.startViewTransition(start)`. Every
other patch, the bots' too, goes in at once. While a transition waits for its
snapshot, later patches queue behind it, so they stay in order. The CSS names only
`.round-counter` and turns off the root crossfade (`assets/css/app.css:1162-1201`).

Round 22 adds a second, named one: `quacks:vt` may carry a `type`, and app.js
passes it as `startViewTransition({update, types})`. The `card` type shrinks the new
card into the pot's corner (see the reveal overlay above); the CSS names the two
cards only under `:active-view-transition-type(card)` and takes the round counter's
name away there, so the counter does not roll.

Why opt-in: during a view transition the page is a screenshot. On every patch,
each bot move every 700 ms would flash, so `::view-transition` also lets taps
through (`pointer-events: none`).

### Reduced motion

One block, `@media (prefers-reduced-motion: reduce)` at
`assets/css/app.css:1203-1284`, follows one rule: keep opacity and colour, drop
translate, scale, rotation and shake. Chips fade in, the card crossfades instead of
a flip, the counters show at once (the replay timer runs 1 ms), and there are no pot rings, no
VP tags and no rolling die. In JS, `reduced()` (`assets/js/app.js:76`) makes
`land`, `ratsIn` and the ruby flights return at once and `ghost` fade, and no view
transition starts. `test/quacks_web/live/motion_test.exs:92`,
`test/quacks_web/live/replay_test.exs:190` and
`test/quacks_web/live/scoring_test.exs:150` check that the fallback is there.
Framer Motion has `useReducedMotion()`; here it is mostly CSS.

## An installable app with a pass-through service worker

The game installs as an app with no browser bar (a PWA in standalone mode):

- `priv/static/manifest.webmanifest`: name, `"display": "standalone"`, portrait,
  the wood theme colour, and three icons in `priv/static/images/pwa/` (192, 512 and
  a maskable 512).
- `Plug.Static` does not know the `.webmanifest` type, so the endpoint names it:
  `content_types: %{"manifest.webmanifest" => "application/manifest+json"}`
  (`lib/quacks_web/endpoint.ex:31`).
- The root layout links the manifest and the Apple touch icon and sets the theme
  colour and the Apple standalone metas
  (`lib/quacks_web/components/layouts/root.html.heex:7-13`).
- **The install button.** Chrome fires `beforeinstallprompt` when the app can be
  installed. app.js keeps the event and sets `data-install="ready"` on `<html>`
  (`assets/js/app.js:302-319`); CSS then shows the lobby's `data-role=install`
  button (`assets/css/app.css:1584-1594`). iOS Safari has no prompt, so outside the
  installed app it gets `data-install="ios"` and a Share-menu hint.
- **The menu hint (round 24).** Android Chrome can list "Install app" in its own
  menu and still never fire `beforeinstallprompt` to the page (the menu's App line
  says `install prompt: not fired`). 3 s after load, when no prompt came, the app
  does not run installed and the browser is Chromium (`navigator.userAgentData`, or
  Android), app.js sets `data-install="menu"` and CSS shows "Install from your
  browser menu: ⋮ → Install app" (`.pwa-menu-hint`). A prompt that comes later sets
  `ready`, and the button takes its place. The state is on
  `<html>` because LiveView never patches that element, so no patch resets it.

**Why the service worker caches nothing.** A service worker usually caches files so
that an app works offline. This app cannot work offline: every click goes to the
GameServer over the websocket, and the page is rendered on the server. A cache would
only add a risk: old JS and CSS after a deploy. Desktop Chrome installs an app from
the manifest alone, but Android Chrome fires `beforeinstallprompt` only when a worker
with a `fetch` listener is registered. So `priv/static/sw.js` registers an empty
fetch handler and nothing else, app.js registers it on load, and `sw.js` is in
`QuacksWeb.static_paths/0` so `Plug.Static` serves it from `/`. In a React SPA the
service worker comes with the template (for example Workbox); here the empty one is
the whole story.

**Full screen when there is no install (round 21).** Android Chrome does not always
offer the install prompt, so the game menu and the lobby's Games page have a Full
screen toggle (`CoreComponents.fullscreen_button/1`, `data-role="fullscreen"`). One
click listener in app.js (`assets/js/app.js:386-395`) calls
`document.documentElement.requestFullscreen()` or `document.exitFullscreen()`. The
call must run inside the click (a user gesture), so a hook or a `push_event` from the
server cannot do it. app.js sets `data-fullscreen="ok"` on `<html>` only when
`document.fullscreenEnabled` is true and the app does not run installed (iPhone
Safari has no Fullscreen API, and the installed app has no browser bar to remove);
without it, CSS hides the toggle. The icon and the label follow the `:fullscreen`
pseudo-class on `<html>` (`.when-windowed`, `.when-fullscreen` in app.css), so no
JS keeps the state. Entering full screen closes open popovers (the menu sheet) as
the Fullscreen spec says. The game grid uses `dvh`, so it fills the larger viewport
with no change.

### Round 35 (board): rat labels, rats in the pot, chips to the bag, tubes, patient

- **Rat track labels.** Every seat's VP sits at its dot (round 28). A rat keeps its
  VP only in a gap of 1 or 2 rats between neighbouring occupied steps; in a gap of
  3 or more the rats show without numbers, and a rat next to a step whose VP label
  sits below the line drops its number too, so no two labels collide. The tails
  come from `ScoringTrack.tails_between/2`, so they repeat after 50.
- **Rats in the pot.** `rat_spaces/1` gives the rat pebbles' spaces: after the
  droplet, at most `rat_stone`, never past `Player.mods.rat_end` (set by the round's first
  chip). A droplet move after the first draw takes the first rat's space and that
  rat goes; the rest stay. Each rat's id names its space (`rat-SEAT-SIZE-SPACE`), so
  `PotMotion.ratsOut/0` fades exactly the rat the droplet took.
- **Chips to the bag before the shop.** `pot`'s `bagged` (game_live `bagged?/1`:
  shopping, the results closed, the seat shops or is ready) renders no chips and
  sets `data-bagged`. `PotMotion.toBag/1` sends every chip that left, first drawn
  first, to the bag button as a ghost in the `pot-fx` top layer (stagger
  `min(60, 600 / n)` ms, 260 ms each; reduced motion: fade). `sideOpen` waits for
  `bagUntil`, so the shop opens after the last chip lands.
- **Test tubes.** The ruby glass uses `piece_icon :ruby`, a VP glass the `:vp` crown
  over its number (no "VP" text). The glasses are 10 units shorter (viewBox
  `0 -18 364 72`) and the main rack is `max-w-xs`: about 63px tall, was 89px.
- **Patient badge.** Below 40rem the badge is its icon only (`hidden sm:inline` on
  the name), then the essence rack; the name stays in `title`, `aria-label` and
  the patient sheet.

## State ownership, compared to React

| Question | React app | This app |
|---|---|---|
| Where is the game state? | a client store, or cached server state | the GameServer; each LiveView holds a copy in `assigns` |
| Who decides what the user can do? | client code, often duplicated on the server | the engine only (`legal_actions/2`) |
| How does the UI update? | set state, diff the virtual DOM in the browser | assign, diff on the server, send the HTML diff |
| UI-only toggles | `useState` | the browser (popover, `<dialog>`), or an assign when the server must know |
| Layout per screen | a `useMediaQuery` hook and two trees | one grid, named areas, CSS media queries |
| Keyboard shortcuts | a `useHotkeys` hook that calls the handlers | `phx-window-keydown`, the server picks the legal action |
| Timed sequences | `setTimeout`, `staggerChildren` | `--beat` from the server, CSS delays |
| Custom JS | most of the app | about 300 lines in `assets/js/app.js`: `PotMotion`, the dialog modes, the replay end, the bug report details, the install button |

### Round 36 (ui): chips to tap, pot targets, the purple buy sheet

- **Chip row** (`BarComponents.chip_row/1`): a choice among chips is the chips, as round
  buttons (`data-role="chip-option"`, `data-chip`, a card's `data-choice`); an
  upgrade shows its target on the edge (`chip-option-to`). Its inner block holds
  the buttons that follow (Done, Skip, ladders). Used by `:chip_choice` (G2, G5),
  the generic `:fortune_choice` and the silver witch's `:witch_offer`.
- **Pot targets**: `pot/1` takes `targets` (`%{chip => %{event, value, label}}`);
  each pot chip of that kind becomes a button (`.pot-target`, a gold
  `target-glow`, Enter too) and the other chips dim (app.css). `pot_targets/1`
  builds it from the open bar choice's actions (`pot_choice_actions/1`, the tile
  step's actions on a step hold): `pot_action?/1` is P4's upgrade, locoweed V's
  return and Chicken eyes' swap. One action per chip sends it; more send
  `pot_pick`, and the bar shows that chip's options (`@pot_pick`, Back clears it).
  Chicken eyes' swap is `bar_choice(:essence_bonus)` now; Vampirism's buy stays a sheet.
- **Purple buy sheet** (`purple_buy/1`): P5's `{:chip, {:buy, chips}}` actions as
  shop tiles, ticked with the shop's `select` and `@selected` (`kept_selection/4`
  keeps a legal P5 selection too), Take. A `dialog_sheet` `decision-purple-buy-N`;
  the bar's "Choose chips" reopens it.
- **Everyone-card stage** (`CardRevealComponents.card_stage/1`): the grown card's
  rows in the `.results-stage` panel over the bar (`card_stage?/1`), yours first.
- **Players row**: 2 half columns per column, each tile spans 2
  (`TileComponents.loop_start/3`), so the short second row (5, 7 seats) is centred.
- **Peeked chip**: Mandrake V's peek (`peeked/2`) sits over the bag
  (`data-role="peek-chip"`, `.peek-rise`) until this seat's next draw or the round's end.
- **Scoring pulse**: `PotMotion.scoringPulse` hides the new scoring space and ring
  during the draw's flight, then pops them with one ping ring. No flight (reduced
  motion), no pulse. Round 37 replaced it (`scoringMove`, below).

### Round 37 (board): the crow skull row, large badges, the ring, the spoon

- **Crow skull row** (`bar_choice(:blue_choice)`): the crow skull chip first
  (`data-role="blue-book"`, `{:blue, nil}` at `:md`, as a tile step shows its
  book), then a cloth (`blue-tray`, `.blue-cloth` in app.css) with the hint "Add a
  chip to the pot" (`blue-hint`) over the drawn chips, then Skip. Four `:lg` chips
  and Skip fit at 360 px; from five chips they are `:md`. When the row leaves
  (`.bar-to-bag`) the cloth and the hint fade and the chips fly to the bag.
- **Value badge at `:lg`**: `chip/1` had no badge classes for `:lg`, so the value
  sat unplaced and unsized over the icon (the crow skull's and the chip row's
  chips). Each size with a badge now places and sizes it (`:lg`: `size-5 text-sm`).
- **Scoring ring on a draw** (`PotMotion.scoringMove`): `snapshot()` copies this
  seat's marks (the gold space and the ring) before the patch (`oldMarks`). After
  a draw's flight starts, the copies sit on their old space in the `pot-fx` layer
  and shrink to 0.85 as they fade out (220 ms); the new marks wait for the chip to
  land (460 ms), then grow from 0.85 to 1 as they fade in (280 ms). Reduced
  motion: no flight, so none.
- **The spoon** (index 53): `pot/1` draws no disc there (`data-spoon`), only its
  coins and VP, so the scoring ring and the gold space can still mark it. No chip
  lands on it (`PotTrack.last_chip/0`, see 07-rules-as-data).


### Round 39 (shop): chips in the context area, every ring moves

- **Purple buy panel** (`purple_buy/1`, replaces the round 36 sheet): Ghost's
  breath V's chips are a panel in the context area (`#purple-buy-panel-N`,
  `.pick-panel` in app.css), not a `dialog_sheet`. Below 64rem it is fixed over
  the pot's lower band, from the bar up (anchored to `--pot-area` like
  `.sheet[data-pot]`), so the pot does not move; the chevron
  (`purple-buy-fold`, `JS.toggle_class("pick-folded")`) folds it to its title.
  From 64rem it is a panel in the context column that keeps its height (the
  witches under it shrink). It shows every chip of the shop (`shop_rows/2`) in a
  5-column grid; a tile that no buy allows with the ticked chips is greyed
  (`purple-buy-off`) and its `title` says why (`purple_off/5`: too dear, not in
  the shop this round, not with your other chip).
- **Purse and Take in the bar**: `bar_choice(:chip_choice)` takes `selected` and
  shows `purple-buy-total` (coins → left, `purple_purse/3`) and
  `purple-buy-take` ("Take N") in place of "Choose chips". The panel has no
  footer, so nothing scrolls under a sticky bar (the round 36 bug: the sheet's
  bottom padding let chips show under its sticky footer).
- **The shop** is a different component (`shop/1`) and stays a sheet: its footer
  is flush (`.sheet:has([data-role="shop-footer"])` drops the padding) and below
  64rem it is fixed in the bar's place, so it has no such overlap.
- **Every ring moves** (`PotMotion.scoringMove`): `marks()` takes the gold space
  and the ring of every seat. Each mark has a key (its space and its
  `outerHTML`); after each patch the marks whose key changed fade out (ghost copy)
  and the new ones grow in. Your draw's flight sets `wait` (460 ms), so the bots'
  rings, which step with your draw (round 37), reappear with yours; any other
  update (another human's draw) moves them at once. Not on a new round; reduced
  motion: none.

### Round 37 (eval): one row grid, the recap after the shop

- **One row grid** (`TileRevealComponents.stage_list/1`): every results panel
  (the evaluation steps, the recap, the everyone-cards' `card_stage/1`) draws
  its rows with it. The `<ol>` is a grid (app.css `.stage-grid`: the seat disc,
  the name, the reason, then one column per kind of result, `--cols`); each row
  is a subgrid, so counts, chips and numbers stand in one line whatever the
  names' lengths. `TileReveal.columns/1` gives the result columns in a fixed
  order (`:dice, :chip, :coins, :vp, :rubies, :droplet, :flask, :gain,
  :total`); every row gets a cell in each (`data-role="stage-got"`,
  `data-col`), "choosing…" in the first. Numbers are tabular (the sans font);
  the total has room for 3 digits.
- **Round scored moves, rows glide**: the standings rows are in the new order and
  carry `shift` (`from_rank - rank`, `TileReveal.stage_rows/3`). `.stage-shift`
  translates a row `shift` rows down and moves it to 0 after 1.5 beats (FLIP in
  CSS only, no JS); reduced motion: none. The final board (`final_board/1`) does
  the same from the round-9 order (`shifts/1`) after the VP count up, and its
  parts (coins, rubies, pennies) have one column each (`.final-grid`).
- **The recap** (`Reveal.recap_slides/1`, key `{:recap, round}`): on the tiles,
  when a round begins (round 2 on, this seat has not drawn), the last round's
  **Shop** step (each seat's chips bought, droplet pushes and flask refills; no
  step when nobody shopped) and then **Round scored**. It plays as a tile reveal
  (`start_reveal/3`), before the new card (`after_recap/2` opens the card's reveal);
  the bar's last button says "Next round"; the seat acks `:recap`
  (`GameServer.ack/4`). The totals come from the log (`split_rounds/1`): the
  seats' VP now less this round's gains, less the last round's results. The
  shop-phase steps end on the scoring space, and the rubies step follows it
  (`next_slide/1`). The overlay (desktop setting) keeps its standings slide.
- **Take a Chance** (P12): `Reveal.card_reveals/1` gives a row per seat (`die`,
  `gains`), so the card grows after its tap and `card_stage/1` shows each die.
- **Flea Market** (P13): after this seat's trade the card grows with every row
  and Continue (`chose_card?/3`), like the choice cards.

### Round 39 (desk): the evaluation in the context column, folds on the left

- **No overlay for the results.** The menu has no Results row any more, and
  app.js sends no `show` or `phone`. The `reveal_settings` event sets
  `reveal_show: :tiles` on every screen, so the evaluation plays on the tiles
  and in the results stage over the bar. From 64rem the bar is the foot of the
  context column, so the steps (with Skip and Next) are in the context column
  and the pot stays free. The overlay code stays: it is the mount default until
  the browser's settings arrive (the first push), and about 50 older tests drive
  the results through it. A later round can remove it with those tests.
- **One list per result.** The Take a Chance rolls (`chance_panel/1`) and the
  results panel (`results_panel/1`, "Round N: evaluation") showed the same as the
  stage; both are gone, with `.chance-row`, `.result-row` and `.results-panel` in
  app.css. The bonus die of the overlay rolls in the bar's info row on every
  screen (`#info-die`).
- **Folds.** `fold/1` (`PanelComponents`) is a `<details>` with a `<summary>`
  title and a chevron (`group-open:rotate-180`), closed by default.
  `phx-mounted={JS.ignore_attributes(["open"])}` keeps the user's open or closed
  state when LiveView patches the page (without it a patch drops `open`). The
  books (`#books-column`) and the witches (`#witches-column`) use it in the left
  column. The witches' title counts the witches this seat can call now
  ("1 to call", `callable_witches/2`). `witches_list/1` draws the cards and their
  call buttons for the fold and for `#sheet-witches`; from 80rem app.css hides the
  sheet in the context column (`.sheet-left-xl`), so each width shows one copy.

## Gallery

The gallery (`/dev/gallery`: stories with args, full screens, the scenarios) has
its own chapter: [12. Gallery: stories, args, screens, scenarios](12-gallery.md).

UI change: check it in `/dev/gallery` at 360/392/1280, and add a story, an arg or
a preset for any new state.
