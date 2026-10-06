# 6. Components

[Back to the guide](../GUIDE.md)

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

(`lib/quacks_web/components/game_components.ex:153-213`, shortened)

| React | Phoenix |
|---|---|
| `function Chip({chip, size = "md", ...rest})` | `def chip(assigns)` with `attr` lines above it |
| TS prop types | `attr :size, :atom, default: :md, values: [...]`; the compiler warns on a wrong or missing attribute |
| `{...rest}` | `attr :rest, :global` and `{@rest}`: `id`, `data-*`, `phx-*` pass through |
| `<Chip chip={c} />` | `<.chip chip={c} />` (the dot: a function in scope) |
| `props.children` | `slot :inner_block` and `{render_slot(@inner_block)}` |
| `useMemo` | compute in the body and `assign/2` before `~H` |

Components do not change state: "Rendering only: nothing in here changes game state"
(`lib/quacks_web/components/game_components.ex:3-5`). A button in a component sends a
`phx-click` to the LiveView that renders it.

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
`localStorage` (round 14: also the herb witch picks), `NameMemory` keeps your name,
`RevealSettings` keeps the reveal settings, `AppStatus` writes the menu's "App"
line, and `PotMotion` animates the pot (see "Motion" below).

**The witch pickers (round 14).** With The Herb Witches on, the configure screen's
books form shows a tile per penny colour (copper, silver, gold). A tap opens a
popover sheet with "Random" and the colour's four cards as radio cards
(`witches[colour]`), the same pattern as the book pickers. `parse_witches/1`
(`lib/quacks_web/components/setup_components.ex:273`) turns the form into
`%{copper: :c3, silver: nil, gold: nil}`, which goes to `GameServer.configure/3`
and on to `Game.new(witches: ...)`. The engine deals first and then replaces the
picked colours (`pick_witches/2`, `lib/quacks/game.ex:399`), so the random stream
stays the same. The witches sheet in the game has a title row now, so its × no
longer squeezes the first card.

**The App line (round 14).** The menu ends with
`App: worker: active · display: browser · install prompt: fired`. `AppStatus`
reads `navigator.serviceWorker.getRegistration()`, `matchMedia("(display-mode:
standalone)")` and whether `beforeinstallprompt` fired. On a phone with no Install
button it shows which of Chrome's rules fails.

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
  height: 100dvh;
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
| Landscape phone (`orientation: landscape` and `max-height: 30rem`) | the pot on the left, full height; header, players, notices, context, bar and the test tubes on the right |
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
- The name cards reserve their update-chip row (`grid-rows-[auto_2.125rem_2.25rem]`
  on `#players-row`), so the round results do not make the row taller. A hidden
  element at the end of a `space-y-*` block still gets a margin on its neighbour, so
  the replay marker `<i id="replay-start-N">` is the first child of its block.
- Phones: the bar has a fixed height (`.game-bar`, `--bar-h`). Its rare extras
  (Mandrake, Ear worm, the patient's chips, the bonus die) are in `.game-tray`, which
  is `position: absolute; bottom: 100%`: it floats over the pot's lower band.
- From 64rem the pot spans the bar's row too ("pot context" / "pot bar"). A taller
  bar takes room from the context column, never from the pot. Grid sizes an `auto`
  row only from the items that do not span a flexible row, so the pot does not
  size it.

A landscape phone moves the test tubes out of the pot column: `.pot-column` becomes
`display: contents`, so its children are grid items and the tubes can take the
`tubes` area. All sheets slide in from the right there, over the right column only.
Tailwind gets a matching variant for small fixes:
`@custom-variant phone-landscape (@media (orientation: landscape) and (max-height: 30rem));`
(`assets/css/app.css:21`), used as `phone-landscape:sr-only`.

One trap: CSS written in `app.css` outside a layer beats every Tailwind utility.
`.action-bar { display: grid }` made `lg:hidden` on the bar do nothing, so that
rule is inside `@layer components` (`assets/css/app.css:679`).

**The context column (64rem).** `<aside class="context-column" data-area="context">`
(`lib/quacks_web/live/game_live.ex:1181`) holds what happens now, top to bottom:
the fortune teller card, the Take a Chance rolls (`chance_panel/1`, line 2770), the
round results while they play (`results_panel/1`, line 2806), the decision panel and
the witches. Below 64rem it is `display: contents` and holds only the sheets. The
bar (`<footer class="game-bar" data-area="bar">`, line 1428) is its foot from 64rem:
Draw is the large button, Stop and a flask button sit under it. An exploded pot
shows "Your pot exploded" and the next step there.

The results panel reuses the replay beats: `result_rows/3` (line 2733) takes every
seat's bonus die lines and this seat's other lines from `QuacksWeb.Replay.beats/3`,
and each row gets `style="--beat: N"`, the same formula as the update chips. Round
11 changed the replay order: the bonus dice of the whole table roll first, one
after the other in seat order, two beats each (`dice_slots/2`,
`lib/quacks_web/replay.ex:59`); then every seat's other lines start together. The
Take a Chance card is not part of the replay (its rolls come at the round's start),
so its rows use their own `--chance-step` (`.chance-row`, `assets/css/app.css:896`)
and are not cut short by `.replay-done`.

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

**The books column (≥ 80rem).** `books_in_play/1`
(`lib/quacks_web/components/game_components.ex`) lists the books in play in board
order (`Chips.order/0`, chapter 7), left of the pot (`id="books-column"`,
`data-area="books"`).

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
(`lib/quacks_web/components/game_components.ex:112-142`). The result is stored in
module attributes:

```elixir
@positions List.to_tuple([{0.0, 0.0} | positions])
@groove Enum.map_join([{0.0, 0.0} | positions], " ", fn {x, y} -> "#{x},#{y}" end)
```

At runtime a space's position is a tuple lookup, `elem(@positions, index)`
(`lib/quacks_web/components/game_components.ex:904-907`). In JS this would be a
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

## Tailwind: full class names in maps

Tailwind v4 scans the source for class names (`@source "../../lib/quacks_web"`,
`assets/css/app.css:8`) and finds only *literal* strings. `"bg-player-#{seat}"` would
build a class Tailwind never saw, so its CSS would not exist. So the seat classes
are a map of full names (`lib/quacks_web/components/game_components.ex:47-58`):

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
(`lib/quacks_web/components/game_components.ex:780-784`):

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

(`lib/quacks_web/components/game_components.ex:924-927`)

`placed` counts the chips this seat placed on that space this game (from the log).
A chip that lands where a returned chip was gets a new id, so it lands again
(`test/quacks_web/live/motion_b3_test.exs:39`).

The VP and ruby counters use the same idea the other way round
(`stat/1`, `lib/quacks_web/components/game_components.ex:1372-1397`): the counter
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
(`card_count/1` in `lib/quacks_web/components/game_components.ex`), on each pot ring (`beat_ring/1`, lines 877-898), each pot effect (lines 509-549)
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
`<dialog>`: a bottom sheet on a phone, centred from 64rem. The beats still play
under it; they are secondary now.

**Pure slides.** `QuacksWeb.Reveal` (`lib/quacks_web/reveal.ex`) has no state, like
`Replay`. `moment/1` names what there is to reveal: `{:card, round}` at the round's
start, `{:results, round}` in the shop phase, `{:final, 9}` at the game's end.
`slides(game, seat)` (line 76) builds the list from the `Replay` lines and the log,
with no new engine data: one `:die` slide per seat that rolled, one `:book` slide per
book and seat with a result (the chips that count, the reward, and for black the
neighbours' black chips), `:scoring`, `:more` (cards, essence, witches),
`:summary`; at the end `:final` and `:podium`. `test/quacks_web/reveal_test.exs`
tests it without a browser.

**Per browser, on the server.** The LiveView keeps
`reveal: %{key, slides, index, tick}` (`open_reveal/1`,
`lib/quacks_web/live/game_live.ex:2739`). `put_game/2` calls it after every game
update: a seat that has not seen the moment (`seen`, see **seen** in
`docs/CONTEXT.md`) gets the slides from index 0. The list is taken once, so a bot's
move does not change what the overlay shows; the game itself does not wait. A
reload mid-reveal starts at the first slide. A spectator gets no overlay.

**Controls.** `reveal_overlay/1`
(`lib/quacks_web/components/reveal_components.ex:35`) renders the slide and a bar:

| Input | Event | Effect |
|---|---|---|
| Next, a tap on the slide | `reveal_next` | next slide; on the last one, the end |
| Enter, Space (focus not on a button) | `hotkey` | as Next |
| Skip | `reveal_skip` | the last slide |
| Esc, × | the dialog's `close` → `reveal_close` | the end |

The end (`close_reveal/1`, line 2796) acks the moment (`GameServer.ack/4`, now
also `:final`), runs `auto_done/2` and pushes `quacks:open` with the dialog that
waited: the shop, a decision or `#game-over`. app.js opens it with the usual
`sideOpen` (`assets/js/app.js:336`). Decision dialogs mount with
`auto_open={is_nil(@reveal)}`, so nothing opens under the overlay. The overlay is
the last element of the page, so `remodal` keeps it on top.

A fortune card that asks this seat a choice keeps its own dialog (the card and the
choice in one); the overlay skips that card and counts it as seen.

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

### `PotMotion`: animate on top of the patch

Some motion needs a path or a measured target: a ruby flies from a chip to the
ruby counter in the header, a returned chip flies to the flask or the bag. CSS
cannot do this, because it does not know where the counter is. So your large pot
carries a hook: `phx-hook={@size == :lg && "PotMotion"}`
(`lib/quacks_web/components/game_components.ex:283`). The hook is in
`assets/js/app.js:80-197`.

A hook is an object whose callbacks LiveView calls around each patch: `mounted`,
`beforeUpdate`, `updated`, `destroyed`. Think of `useLayoutEffect` with a ref, but
the element comes from the server. `PotMotion` does FLIP (First, Last, Invert,
Play):

- **First.** `beforeUpdate()` (`assets/js/app.js:96`) calls `snapshot()`
  (lines 154-158): the chip ids, the flask, the round.
- **Last.** LiveView applies the patch. The DOM now shows the final pot.
- **Invert and play.** `updated()` (lines 97-111) compares. A chip with a new id
  drops in on its space (`land`, lines 169-178). A chip that went away flies as a
  ghost to the flask or the bag (`ghost`, lines 181-196). At a new round the old
  chips fade and the new rats slide in from the droplet (`ratsIn`, lines 142-153).
  Then `flights()` (lines 121-139) sends each new `[data-role=ruby-flight]` to the
  ruby counter, with the same delay formula as the CSS (it reads `--beat-lead` and
  `--beat-step` from `:root`). Each one is `el.animate(frames, opts)`, the Web
  Animations API, with only `transform` and `opacity`.

Why patches and client animation do not fight:

- **The patch comes first.** The DOM is already final. The animation only moves the
  element from where it seemed to be to where it is. A tap never waits for it.
- **Fixed ids** (above) make "new chip" mean "an id not in the snapshot". Each chip
  also has `data-index` and `data-order` (`lib/quacks_web/components/game_components.ex:824-825`),
  each space has `data-x` and `data-y` (lines 371-372), and each pot effect carries
  its own `data-x`, `data-y` and `data-beat` (lines 515-520). The hook reads the
  positions from the server's spiral and measures only the target (the counter,
  the bag).
- **Each flight plays once.** The hook keeps the ids it has flown in a `Set`, so a
  later patch (a bot's draw) does not fly the same ruby again.
- **Exits get their own layer.** LiveView has already removed a returned chip.
  `ghost` puts the detached element into `<g data-role="pot-fx" phx-update="ignore">`
  (`lib/quacks_web/components/game_components.ex:551-552`), a layer that LiveView
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
  installed app it gets `data-install="ios"` and a Share-menu hint. The state is on
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
