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

The other listeners are small too. `closed/1` (`assets/js/app.js:247-252`) runs on
every dialog `close` event: it runs the dialog's `on_close` JS and opens the dialog
that `then_open` names. A tap on the dimmed backdrop closes a modal sheet
(lines 261-265), so a player can look at the pot and come back with "Back to shop".
`quacks:close` closes a dialog or popover (lines 272-273), and `quacks:copy` copies
to the clipboard (line 297). A chip in the fortune card dialog sends its action and
closes the dialog in one chain:
`JS.push("action") |> JS.dispatch("quacks:close", to: "#card-round-#{game.round}")`
(`card_click/1`, `lib/quacks_web/live/game_live.ex:2432-2434`). Three hooks have
state: `ConfigMemory` (`assets/js/app.js:43-53`) keeps the host's last settings in
`localStorage`, `NameMemory` (lines 57-67) keeps your name, and `PotMotion`
animates the pot (see "Motion" below).

## Layout: one dialog, three screen sizes

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

`side={:hidden}` is for the new fortune card: on wide screens the card is already
on the page (`fortune_panel/1`), so the dialog counts as closed at once and hands
over to the next one (`lib/quacks_web/live/game_live.ex:1443`). When the window
crosses 64rem, app.js closes an open panel and opens it again in the other mode
(`assets/js/app.js:256-259`). In React you would render a `<Sheet>` or a `<Panel>`
from a `useMediaQuery` hook. Here the server sends one element, and the browser
picks the mode when it opens it.

**CSS-only tabs (64-80rem).** On a tablet the right column has two tabs,
"Decision" and "Books". They are radio inputs inside labels
(`lib/quacks_web/live/game_live.ex:1253-1283`):

```heex
<input
  type="radio"
  name="side-tab"
  id={"side-tab-#{tab}-#{@decision || "none"}"}
  class="sr-only"
  data-tab={tab}
  checked={tab == :decision == (@decision != nil)}
/>
```

The CSS reads the checked radio with `:has()` and hides the other content
(`assets/css/app.css:618-672`):

```css
[data-role="side-column"]:has([data-tab="books"]:checked)
  > :not([data-role="side-tabs"], #books-tab) {
  display: none !important;
}
```

A tap on a tab changes no assign and sends no event. But a *new* decision must
switch back to "Decision". The id names the decision, so a new decision is a new
input, rendered with `checked` again. That is the `key` trick once more: change the
id, get a fresh element with fresh state. A Headless UI `<Tab.Group>` would keep the
selected index in React state; here the browser keeps it in the radio group.

**The books column (≥ 80rem).** `books_in_play/1`
(`lib/quacks_web/components/game_components.ex:1962-1996`) lists the books in play
in board order (`Chips.order/0`, chapter 7). The page renders it twice: as a column
left of the pot on a desktop (`id="books-column"`,
`lib/quacks_web/live/game_live.ex:1007-1013`) and as the "Books" tab on a tablet
(`id="books-tab"`, lines 1498-1503). Tailwind classes show one or the other
(`xl:flex` and `lg:flex xl:hidden`). Two copies of a small list cost less than JS
that moves one copy.

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

- **the name cards:** each card gets its *update chips* ("stopped", "+7 VP", "+2"
  rubies, "+1" droplet), one after the other;
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
- `updates/2` (`lib/quacks_web/replay.ex:125-138`): the update chips of one name
  card. Each chip is a sum (all the VP of the round) that lands on the beat of its
  *last* line, so it is complete when it shows.
- `pot_effects/1` (`lib/quacks_web/replay.ex:87-110`): the scoring sequence on the
  pot. One `%{kind: :ruby | :vp, at: mark, beat: beat, n: n}` per flying ruby (at
  most 3 per line) and per VP tag. `source/1` picks where it starts: a black ruby
  leaves the droplet, a green or purple one its chip, the space's own ruby the
  scoring space.

The templates write the beat into a CSS variable: `style={"--beat: #{update.beat}"}`
on each update chip (`player_chip/1`, `lib/quacks_web/components/game_components.ex:1556-1575`),
on each pot ring (`beat_ring/1`, lines 877-898), each pot effect (lines 509-549)
and each book (`book_line/1`, lines 2004-2016). One CSS formula turns every beat
into a delay (`assets/css/app.css:981-994`):

```css
.update-chip {
  animation: update-in 320ms var(--ease-spring) both;
  animation-delay: calc(var(--beat-lead) + var(--beat) * var(--beat-step));
}
```

The server decides the *order*; CSS decides the *speed* (`--beat-lead: 300ms` and
`--beat-step: 450ms`, `assets/css/app.css:929-932`). The cards, the pot, the books
and the counters use the same formula and arrive in the same patch (the shop phase
begins), so they stay in step with no code that links them. After two skips this
browser plays faster: app.js sets `data-fast-beats` on `<html>` and CSS changes the
two variables (`assets/css/app.css:1034-1038`).

**The end of the replay.** The last chip carries `data-replay-last` and a second,
1-second animation that only holds the replay open while its ruby flies. app.js
listens for `animationend` on it (`assets/js/app.js:289-295`) and runs the players
row's `data-on-replay-end` JS: `replay_end/3` (chapter 5) adds `replay-done` to
`#players-row`, pushes `"seen"` and opens the shop. "Skip", a tap on a name card, a
tap on the pot, Space or Esc do the same. One CSS rule per place then shows the end
state at once, for example (`assets/css/app.css:1018-1021`):

```css
#players-row.replay-done .update-chip {
  animation-delay: 0s !important;
  animation-duration: 1ms !important;
}
```

`replay-done` is a class that JS adds, and JS-added classes stick across patches.
So a new round must clear it: a hidden `<i id={"replay-start-#{round}"}>` mounts
once per round with `phx-mounted={JS.remove_class("replay-done", to: "#players-row")}`
(`lib/quacks_web/live/game_live.ex:955-962`). Before this, every replay after the
first started as done.

**Optimistic UI versus server beats.** In React you often show the result at once
and let the server catch up (optimistic UI). Here it is the other way round. The
server state is final in the first patch: the VP are counted, the chips bought. The
animation only *delays how it shows*, with CSS delays on the final DOM. Nothing
waits for the animation, and a reload or a skip shows the same final state. In
Framer Motion you would write `transition={{delay: i * 0.45}}` or
`staggerChildren`; here `i` comes from the server as `--beat`. Because `Replay` is
pure, `test/quacks_web/live/replay_test.exs:43-122` and
`test/quacks_web/live/scoring_test.exs:45-60` test the order without a browser.

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
a flip, the update chips and counters show at once, and there are no pot rings, no
VP tags and no rolling die. In JS, `reduced()` (`assets/js/app.js:76`) makes
`land`, `ratsIn` and the ruby flights return at once and `ghost` fade, and no view
transition starts. `test/quacks_web/live/motion_test.exs:92`,
`test/quacks_web/live/replay_test.exs:190` and
`test/quacks_web/live/scoring_test.exs:150` check that the fallback is there.
Framer Motion has `useReducedMotion()`; here it is mostly CSS.

## An installable app with no service worker

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

**Why no service worker.** A service worker caches files so that an app works
offline. This app cannot work offline: every click goes to the GameServer over the
websocket, and the page is rendered on the server. A cache would only add a risk:
old JS and CSS after a deploy. Current Chrome installs an app without a service
worker, so the manifest is enough. In a React SPA the service worker comes with the
template (for example Workbox); here leaving it out is the simpler choice.

## State ownership, compared to React

| Question | React app | This app |
|---|---|---|
| Where is the game state? | a client store, or cached server state | the GameServer; each LiveView holds a copy in `assigns` |
| Who decides what the user can do? | client code, often duplicated on the server | the engine only (`legal_actions/2`) |
| How does the UI update? | set state, diff the virtual DOM in the browser | assign, diff on the server, send the HTML diff |
| UI-only toggles | `useState` | the browser (popover, `<dialog>`), or an assign when the server must know |
| Tabs | a `<Tabs>` component with state | radio inputs and CSS `:has()` |
| Timed sequences | `setTimeout`, `staggerChildren` | `--beat` from the server, CSS delays |
| Custom JS | most of the app | about 300 lines in `assets/js/app.js`: `PotMotion`, the dialog modes, the replay end, the bug report details, the install button |
