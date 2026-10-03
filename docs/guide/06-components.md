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

(`lib/quacks_web/components/game_components.ex:141-201`, shortened)

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
   (`lib/quacks_web/live/game_live.ex:1507-1510`).
3. `:if={cond}` and `:for={x <- list}` work on any tag or component:
   `<div :for={{title, tiles} <- @groups} ...>` and `<p :if={title} ...>`
   (`lib/quacks_web/live/game_live.ex:1488-1489`).
4. `class={[...]}` takes a list; `false` and `nil` drop out. That is `clsx`, built in.
5. `<%!-- comment --%>` never reaches the browser.

Inside a component, `@game` is the component's `game` attribute, not the LiveView's
assign. A component reads only what it gets.

## Sheets and dialogs with almost no JS

The page has many overlays: log, bag, players, books, and one dialog per decision.
They use two native browser features and no component library
(`docs/research/components-and-mobile.md` §1, §2).

**Info sheets: the Popover API.** `sheet/1` renders `<div id={@id} popover ...>` with
a close button `popovertarget={@id} popovertargetaction="hide"`
(`lib/quacks_web/components/core_components.ex:107-119`); `sheet_button/1` is a button
with `popovertarget`. The browser opens and closes it and handles Esc and "tap
outside". Zero JS, zero server state. The slide-up uses CSS `@starting-style`
(`assets/css/app.css:281-313`).

**Decisions: native `<dialog>`.** A decision must be answered, so it is a modal
`<dialog>` opened with `showModal()`. That needs one line of JS. The trick is in
`dialog_sheet/1` (`lib/quacks_web/components/core_components.ex:172-197`):

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

The listener (`assets/js/app.js:176`):

```js
window.addEventListener("quacks:modal", e => e.target.open || e.target.showModal())
```

So the server renders a decision dialog with `:if={@decision && ...}`
(`lib/quacks_web/live/game_live.ex:950-955`). It opens itself when it appears and
goes away when a render drops it. The server has no "is the dialog open" state.

Three more one-line listeners (`assets/js/app.js:179-189`) open the next dialog on
close, close a dialog on `quacks:close`, and copy to the clipboard. A chip in the
fortune card dialog sends its action and closes the dialog in one chain:
`JS.push("action") |> JS.dispatch("quacks:close", to: "#card-round-#{game.round}")`
(`lib/quacks_web/live/game_live.ex:1587-1588`). Two hooks have state:
`ConfigMemory` (`assets/js/app.js:30-40`) keeps the host's last settings in
`localStorage`, and `PotMotion` animates the pot (see "Motion" below).

## The SVG pot is computed at compile time

The pot is a spiral of 54 spaces, which needs floating-point maths. That code sits
in the module body, outside any `def`, so it runs once when the module compiles
(`lib/quacks_web/components/game_components.ex:105-130`). The result is stored in
module attributes:

```elixir
@positions List.to_tuple([{0.0, 0.0} | positions])
@groove Enum.map_join([{0.0, 0.0} | positions], " ", fn {x, y} -> "#{x},#{y}" end)
```

At runtime a space's position is a tuple lookup, `elem(@positions, index)`
(`lib/quacks_web/components/game_components.ex:808-811`). In JS this would be a
`const POSITIONS = computeSpiral()` at module top level; here it does not even run
at app start.

## Icons are read at compile time

`QuacksWeb.Icons` (`lib/quacks_web/components/icons.ex`) gives three components:
`<.ingredient_icon colour={:orange} />`, `<.piece_icon name={:ruby} />` and
`<.patient_icon id={:ear_worm} />`. `lib/quacks_web.ex:84` imports them into every
component and LiveView.

The SVG files are in `priv/static/images/icons/`, but the page never loads them
with `<img src>`. The module reads them when it compiles
(`lib/quacks_web/components/icons.ex:51-56`):

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
- `svg/1` (`lib/quacks_web/components/icons.ex:104-119`) wraps the markup in
  `<svg viewBox="0 0 512 512" fill="currentColor">` and inserts it with
  `Phoenix.HTML.raw/1`. `raw` turns off HTML escaping. That is safe here because the
  markup comes from our own files, never from a user.
- `fill="currentColor"`: the icon takes the text colour, so
  `class="size-4 text-ruby"` sizes and colours it, as with an icon font.

In React you get the same with SVGR (`import Ruby from "./ruby.svg"`): a build step
inlines the file as a component. Here the compiler does it, with no bundler plugin.

`attr :colour, :atom, values: @ingredients` makes the compiler warn on a literal
like `colour={:pink}`, and `Map.fetch!/2` raises on an unknown name at render time.
`test/quacks_web/components/icons_test.exs:21-42` checks that every chip colour,
piece and patient has an icon.

**To swap an icon:** copy the new file into `priv/static/images/icons/`, change its
file name in `@files` (`lib/quacks_web/components/icons.ex:18-48`) and credit the
author in `docs/CREDITS.md`. The file must be one filled silhouette on a 512
viewBox, because `svg/1` sets the viewBox and the fill.

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
(`assets/css/app.css:63-82`): `--color-seat-5: #e86a9e;` and
`--color-player-0: var(--color-seat-0);`. Tailwind turns `--color-player-0` into
`bg-player-0`. The page overrides the seat variables with one inline style
(`lib/quacks_web/components/game_components.ex:683-688`):

```elixir
def seat_style(colours),
  do:
    Enum.map_join(colours, " ", fn {seat, c} ->
      "--color-player-#{seat}: var(--color-seat-#{c});"
    end)
```

used as `<Layouts.app flash={@flash} full style={seat_style(@colours)}>`
(`lib/quacks_web/live/game_live.ex:565`). A colour change is one new `style` string;
the classes stay the same.

## From `legal_actions` to tappable chips

In every choice between chips the chips are the buttons. `chip_picks/1`
(`lib/quacks_web/live/game_live.ex:1460-1485`) asks each legal action which chips it
shows (`lib/quacks_web/live/game_live.ex:1539-1547`, shortened):

```elixir
defp pick_chips({:place, chip}), do: [chip]
defp pick_chips({:red, {_kind, chip}}), do: [chip]
defp pick_chips({:chip, {:upgrade, from, to}}), do: [from, to]
defp pick_chips({:chip, {:buy, chips}}), do: chips
defp pick_chips(_action), do: []
```

Each pick becomes a `<button phx-click={@click} phx-value-action={encode(action)}>`
with the chips inside (`lib/quacks_web/live/game_live.ex:1492-1497`). Actions without a
chip ("Return all", "Done") become text buttons (`text_actions/1`, line 1564). A new
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

(`lib/quacks_web/components/game_components.ex:819-822`)

`placed` counts the chips this seat placed on that space this game (from the log).
A chip that lands where a returned chip was gets a new id, so it lands again
(`test/quacks_web/live/motion_b3_test.exs:39`).

The VP and ruby counters use the same idea the other way round
(`lib/quacks_web/components/game_components.ex:1102-1116`): the counter keeps its id
and `style={"--n: #{@value}"}`, so CSS counts up from the old value; the inner
`<span id={"#{@id}-#{@value}"}>` is new for each value, so its `stat-pop` keyframe
plays. In React you write `<span key={value}>` to restart an animation.

### The replay: the server numbers the beats, CSS keeps the time

After the evaluation, the round results dialog replays step B. Each result line
shows in turn, and the pot lights up the chips that the line is about. There is no
timer on the server and none in JS.

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
indices, `:droplet`, `:ring` (the scoring space) or `:essence`. `highlights/1`
(`lib/quacks_web/replay.ex:60-65`) gives each mark the beat of its first line.

The templates write the beat into a CSS variable: `style={"--beat: #{@beat}"}`
(`beat_style/1`, `lib/quacks_web/components/game_components.ex:1984-1985`, and the
pot's `beat_ring/1`, lines 787-802). CSS turns it into a delay
(`assets/css/app.css:637-640`):

```css
#round-results [data-beat] {
  animation: beat-in 220ms var(--ease-out) both;
  animation-delay: calc(var(--beat-lead) + var(--beat) * var(--beat-step));
}
```

The server decides the *order*; CSS decides the *speed* (`--beat-step: 450ms`,
`assets/css/app.css:624-628`). The dialog lines and the pot rings use the same
formula and arrive in the same patch, so they stay in step with no code that links
them. "Skip" is `JS.add_class("replay-done", to: "##{@dialog}")`, and one CSS rule
sets every delay to 0 (`assets/css/app.css:730-733`).

In Framer Motion you would write `transition={{delay: i * 0.45}}` or
`staggerChildren`. Here the index comes from the server as a CSS variable, and
because `Replay` is pure, `test/quacks_web/live/replay_test.exs:43-82` tests the
order without a browser.

### `PotMotion`: animate on top of the patch

Some motion needs a path: a new chip flies out of the bag, hops along the spiral
and lands with a pop. CSS cannot do this, because it does not know where the chip
was before. So your large pot carries a hook:
`phx-hook={@size == :lg && "PotMotion"}`
(`lib/quacks_web/components/game_components.ex:262`). The hook is in
`assets/js/app.js:56-144`.

A hook is an object whose callbacks LiveView calls around each patch: `mounted`,
`beforeUpdate`, `updated`. Think of `useLayoutEffect` with a ref, but the element
comes from the server. `PotMotion` does FLIP (First, Last, Invert, Play):

- **First.** `beforeUpdate()` (`assets/js/app.js:58`) finishes the animations that
  still run and calls `snapshot()` (lines 73-78): the chip ids, the rat stone's
  space, the round.
- **Last.** LiveView applies the patch. The DOM now shows the final pot.
- **Invert and play.** `updated()` (lines 59-72) compares. A chip with a new id
  flies in (`fly`, lines 94-112). A chip that went away flies as a ghost to the
  flask or the bag (`ghost`, lines 115-130). At a new round the old chips fade. The
  rat stone hops (`hop`, lines 132-143). Each one is `el.animate(frames, opts)`, the
  Web Animations API, with only `transform` and `opacity`.

Why patches and client animation do not fight:

- **The patch comes first.** The DOM is already final. The animation only moves the
  element from where it seemed to be to where it is. A tap never waits for it.
- **Fixed ids** (above) make "new chip" mean "an id not in the snapshot". Each chip
  also has `data-index` and `data-order` (`lib/quacks_web/components/game_components.ex:726-729`),
  and each space has `data-x` and `data-y` (lines 315-319). The hook reads the
  positions from the server's spiral and measures nothing.
- **Exits get their own layer.** LiveView has already removed a returned chip.
  `ghost` puts the detached element into `<g data-role="pot-fx" phx-update="ignore">`
  (`lib/quacks_web/components/game_components.ex:456-457`), a layer that LiveView
  promises not to patch, and removes it when the animation ends.
- **One set of curves.** `easing("--ease-spring")` (`assets/js/app.js:48`) reads the
  CSS custom property, so CSS and JS use the same easing.

| Framer Motion | Here |
|---|---|
| `layout` / `layoutId` (FLIP by measuring) | `PotMotion` snapshot + `updated()`, positions from `data-x`/`data-y` |
| `key` | the element `id` |
| `<AnimatePresence>` exit | `ghost` in the `phx-update="ignore"` layer |
| React holds the old element until the exit ends | LiveView removes it at once; the hook plays on a detached copy |

### One opt-in view transition

At a new round the round counter rolls up to the next number. `mark_round_change/2`
(`lib/quacks_web/live/game_live.ex:1689-1693`) pushes the event `quacks:vt` with
`dispatch: :before`, so the browser gets it before the patch. In `app.js`
(lines 146-168) the event sets a flag, and the `dom.onDocumentPatch` option of the
`LiveSocket` runs that one patch inside `document.startViewTransition(start)`. Every
other patch, the bots' too, goes in at once. While a transition waits for its
snapshot, later patches queue behind it, so they stay in order. The CSS names only
`.round-counter` and turns off the root crossfade (`assets/css/app.css:751-793`).

Why opt-in: during a view transition the page is a screenshot. On every patch,
each bot move every 700 ms would flash, so `::view-transition` also lets taps
through (`pointer-events: none`).

### Reduced motion

One block, `@media (prefers-reduced-motion: reduce)` at
`assets/css/app.css:803-858`, follows one rule: keep opacity and colour, drop
translate, scale, rotation and shake. Chips fade in, the card crossfades instead of
a flip, the replay shows every line at once with the die on its face and no pot
rings. In JS, `reduced()` (`assets/js/app.js:47`) makes `fly` and `hop` return at
once and `ghost` fade, and no view transition starts.
`test/quacks_web/live/motion_test.exs:92` and
`test/quacks_web/live/replay_test.exs:176` check that the fallback is there.
Framer Motion has `useReducedMotion()`; here it is mostly CSS.

## State ownership, compared to React

| Question | React app | This app |
|---|---|---|
| Where is the game state? | a client store, or cached server state | the GameServer; each LiveView holds a copy in `assigns` |
| Who decides what the user can do? | client code, often duplicated on the server | the engine only (`legal_actions/2`) |
| How does the UI update? | set state, diff the virtual DOM in the browser | assign, diff on the server, send the HTML diff |
| UI-only toggles | `useState` | the browser (popover, `<dialog>`), or an assign when the server must know |
| Custom JS | most of the app | about 160 lines in `assets/js/app.js`, most of it the `PotMotion` hook |
