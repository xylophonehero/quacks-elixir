# State machine + LiveView for a turn-based board game engine

Research note, 2026-10-02. Target: solo Quacks of Quedlinburg, Elixir 1.18 / OTP 27,
Phoenix 1.8, LiveView 1.1. Audience: Nick, learning Elixir. Terse by design.
⚠️ = not verified first-hand.

## TL;DR

- Write the engine as a **pure reducer**: `%Game{phase: ...}` struct plus
  `Game.apply(game, action) :: {:ok, game} | {:error, reason}`. No process, no library.
- Inject randomness (a `:rand` state or a `draw_fun`) so tests are deterministic.
- Keep a **snapshot + list of actions** (not a full event-sourcing framework). Undo = replay.
- LiveView: game struct in `assigns`; `handle_event -> Game.apply -> assign`. No GenServer
  for solo. Add a GenServer per game + PubSub only when a second browser must see the game.
- Tailwind v4 + `core_components.ex`: keep the generated file, add your own function
  components with `attr`/`slot`. daisyUI is optional; drop it if you want full control.
- Do not write a `Game` behaviour until a second game exists. Name the seam now.

---

## 1. State machine options in Elixir

| Option | What it is | Process? | Maintained (hex, as of 2026-10) | Fit for a pure game engine |
|---|---|---|---|---|
| (a) Pure reducer | `%Game{phase: :draw}` + pattern-matched `apply/2` heads | No | n/a (stdlib) | **Best.** Zero deps, trivially testable, phase is just a field |
| (b) `:gen_statem` | OTP behaviour: state atom + data, per-state callbacks | Yes | OTP stdlib | Good once you need a live process (timeouts, multiplayer). Overkill for solo; tests need a process |
| `gen_state_machine` | Elixir wrapper around `:gen_statem` | Yes | 3.0.0, Oct 2020 — dormant | Skip. `:gen_statem` is usable directly from Elixir |
| `Machinery` | Struct FSM, transitions as a map, guards/callbacks, Phoenix hooks | No | 1.1.0, Apr 2023 — dormant | Adds a DSL for what one `case` does. Skip |
| `Finitomata` | FSM generated from PlantUML/Mermaid, GenServer-backed, `on_transition/4` | Yes | 0.43.0 / 1.0.0-rc.0, Aug 2026 — active | Workflow-oriented, process-first. Not a fit for a pure core |
| `Fsmx` | Struct FSM, opt-in Ecto | No | 0.5.0, Aug 2023 — dormant | Simple but unmaintained; adds nothing over pattern matching |
| `StateMachine` (youroff) | Struct FSM, one-line promotion to `gen_statem`, Ecto types | Optional | 0.1.9, Nov 2025 — small (23 stars) | Interesting idea, tiny community |
| `Crank` | "Moore-style pure FSM, data first, optional gen_statem adapter" | Optional | 1.1.0, Apr 2026 — new | Closest library to option (a). Still young; watch it, do not depend on it yet |
| (d) `AshStateMachine` | Ash resource extension: states + transitions on an Ash resource, Ecto-persisted | No (Ash actions) | 0.2.13, Apr 2026 — active | Only if you adopt Ash. Heavy for one in-memory game struct |

**Recommendation:** option (a). The game "state machine" is a `phase` field and a set of
function heads. Elixir's pattern matching *is* the transition table:

```elixir
defmodule Quacks.Game do
  defstruct phase: :setup, round: 1, bag: [], pot: [], rubies: 0, seed: nil, ...

  @type action :: :draw | :stop | {:buy, Chip.t()} | ...

  @spec apply(t, action) :: {:ok, t} | {:error, atom}
  def apply(%__MODULE__{phase: :drawing} = g, :draw),  do: {:ok, draw_chip(g)}
  def apply(%__MODULE__{phase: :drawing} = g, :stop),  do: {:ok, %{g | phase: :scoring}}
  def apply(%__MODULE__{phase: :buying} = g, {:buy, chip}), do: buy(g, chip)
  def apply(_g, action), do: {:error, {:illegal, action}}

  def legal_actions(%{phase: :drawing}), do: [:draw, :stop]
  ...
end
```

Trade-offs, plainly:
- A reducer is a plain function. You can run it in `iex`, in a test, in a LiveView, in a
  GenServer, or in a script. Libraries give you a DSL and callbacks you do not need, and
  most are dormant.
- `:gen_statem` buys supervision, timeouts, and a mailbox. A solo game has one player and
  no clock, so it gets nothing from that. **Wrapping later is cheap**: a GenServer whose
  `handle_call({:apply, action}, _, game)` calls `Game.apply/2` is ~15 lines
  (see section 4). Decide the process model at the edge, not in the core.
- Phase transitions are explicit: every function head names the phase it is legal in.
  Unknown phase/action pairs fall to the catch-all `{:error, ...}` head. That is the
  "whitelist" style of the Islands book (Functional Web Development with Elixir, OTP and
  Phoenix) and of dkarter's King of Tokyo talk ("the GameServer does not perform logic; it
  delegates to a functional core").

Sources: https://hex.pm/packages/machinery · https://hex.pm/packages/finitomata ·
https://hex.pm/packages/gen_state_machine · https://hex.pm/packages/fsmx ·
https://hex.pm/packages/state_machine · https://hex.pm/packages/crank ·
https://hex.pm/packages/ash_state_machine ·
https://elixirforum.com/t/crank-pure-immutable-fsms-with-seamless-gen-statem-promotion/74939 ·
https://www.erlang.org/doc/apps/stdlib/gen_statem.html

## 2. Pure core / imperative shell, with injected randomness

Rule: **the core never calls `:rand` on the process dictionary.** Randomness is data that
flows through the struct. Two workable styles:

**Style A — carry the RNG state in the struct (recommended).**
`:rand` has a functional API: every `_s` function takes a state and returns
`{value, new_state}`. Seed once at game creation, thread it through.

```elixir
def new(opts \\ []) do
  seed = Keyword.get(opts, :seed, :rand.seed_s(:exsss))          # or :rand.seed_s(:exsss, {1,2,3})
  %Game{seed: seed, bag: Chips.starting_bag(), phase: :drawing}
end

defp draw_chip(%Game{bag: bag, seed: seed} = g) do
  {i, seed} = :rand.uniform_s(length(bag), seed)
  {chip, bag} = List.pop_at(bag, i - 1)
  %{g | bag: bag, pot: [chip | g.pot], seed: seed}
end
```
Pros: fully deterministic, the whole game is one value, replay works for free (section 3).
Cons: one extra field; you must remember to write the new seed back.

**Style B — inject a `draw_fun`.** `%Game{draw_fun: &Enum.random/1}` in prod,
`fn bag -> hd(bag) end` in tests. Simpler to read, but a function in a struct does not
serialise and replay needs the same function. Fine for a first spike.

**`:rand` in ExUnit.** ExUnit already seeds `:rand` per test from `--seed` plus a hash of
module and test name (`:rand.seed(alg, {phash2(module), phash2(name), seed})`), and each
test runs in its own process, so process-dictionary `:rand` calls are reproducible given
the printed seed. That helps for tests that are *allowed* to be random. For engine tests,
do not rely on it: pass an explicit seed (`Game.new(seed: :rand.seed_s(:exsss, {1,2,3}))`)
or a fixed bag order so the assertion reads as a fact, not a coincidence.
`:rand.export_seed/0` / `:rand.seed/1` exist for saving and restoring the
process-dictionary state; with Style A you do not need them.

Hazards:
- Use `:rand`, never the deprecated `:random`.
- `Enum.random/1`, `Enum.shuffle/1`, `Enum.take_random/2` all hit the process dictionary.
  Keep them out of the core, or wrap them in a function that takes and returns a seed.
- Default algorithm is `exsss`; name it explicitly so a future OTP default change does not
  silently alter old seeds' sequences.

Sources: https://www.erlang.org/doc/apps/stdlib/rand.html ·
https://elixirforum.com/t/is-it-necessary-or-useful-to-call-rand-seed-in-tests/42016 ·
https://flexiana.com/news/2023/11/deterministic-randomness-in-elixir ·
https://hexdocs.pm/ex_unit/ExUnit.html

## 3. Event-sourced vs snapshot

| | Snapshot (`%Game{}` only) | Action log (`[action]` + initial seed) | Full event sourcing (domain events, projections) |
|---|---|---|---|
| Undo | needs history of snapshots | `Enum.reduce(Enum.drop(-1, actions), new(seed), &apply!/2)` | replay events |
| Replay / bug report | no | yes: seed + actions reproduces everything | yes |
| Save game | one term | seed + actions (tiny) | event store |
| Complexity | none | ~20 lines | library (Commanded, Incident, AshEvents) and new vocabulary |
| Risk | lose history | rules change -> old logs replay differently | same, plus upcasting |

**Recommendation: snapshot + action log.** Because `apply/2` is pure and the seed is in the
struct, the pair `{initial_seed, [actions]}` *is* the event log; the current `%Game{}` is a
cache. You get undo, replay and "send me your game" bug reports without a framework.

```elixir
defmodule Quacks.Session do
  defstruct game: nil, seed: nil, actions: []

  def apply(%{game: g, actions: as} = s, a) do
    with {:ok, g} <- Game.apply(g, a), do: {:ok, %{s | game: g, actions: [a | as]}}
  end

  def undo(%{seed: seed, actions: [_ | rest]} = s) do
    g = rest |> Enum.reverse() |> Enum.reduce(Game.new(seed: seed), &Game.apply!(&2, &1))
    %{s | game: g, actions: rest}
  end
end
```

The AppSignal Go-game posts use the other cheap variant: a list of snapshots plus an
index (`defstruct history: [%State{}], index: 0`). Simpler undo/redo, more memory, no
replay-from-seed. Either is fine for solo; the action log is smaller and doubles as a
test fixture format. Do not reach for Commanded or AshEvents here.

Sources: https://blog.appsignal.com/2019/07/04/elixir-alchemy-building-go-in-elixir-time-travel-and-the-ko-rule.html ·
https://allanmacgregor.com/posts/event-sourcing-with-elixir ·
https://github.com/pedroassumpcao/incident · https://github.com/slashdotdash/awesome-elixir-cqrs

## 4. LiveView 1.1 pattern for a solo game page

**Default: struct in assigns.** The LiveView process *is* the imperative shell.

```elixir
defmodule QuacksWeb.GameLive do
  use QuacksWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, session: Session.new())}
  end

  def handle_event("act", %{"action" => raw}, socket) do
    action = Action.parse!(raw)                      # string -> atom/tuple, whitelist
    case Session.apply(socket.assigns.session, action) do
      {:ok, s}         -> {:noreply, assign(socket, session: s)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Rules.explain(reason))}
    end
  end

  def handle_event("undo", _, socket),
    do: {:noreply, update(socket, :session, &Session.undo/1)}
end
```
Why this is enough for solo: one player, one process, state dies with the tab (persist
`{seed, actions}` to the DB or `localStorage` via a hook if you want resume). Zero
coordination. Tests use `Phoenix.LiveViewTest` on top of the pure engine tests.

**Alternative: GenServer per game + PubSub.** `GameServer` holds the `%Session{}`,
`Registry` maps `game_id -> pid`, `DynamicSupervisor` starts them, LiveViews call
`GameServer.apply(id, action)` and subscribe to `"game:#{id}"`; the server broadcasts the
new state after each apply. This is the Fly.io tictac / King of Tokyo / Level10 shape.
**Worth it when:** two or more browsers must see the same game, the game must outlive a
reconnect, or something ticks on a timer. **Not worth it for solo**: it adds a process,
a registry, a supervisor, a garbage collector for abandoned games (dkarter runs one every
2 minutes), and PubSub, for no user-visible gain. Because the core is pure, promotion
later is mechanical.

**LiveView 1.1 features that matter here**
- **Colocated hooks** (`<script :type={Phoenix.LiveView.ColocatedHook} name=".Dice">`):
  put a small JS hook (e.g. chip-draw animation, localStorage save) next to the component.
  Hook names starting with `.` are module-prefixed. Needs Phoenix 1.8 and an
  `import {hooks} from "phoenix-colocated/quacks"` line in `app.js`.
- **`Phoenix.LiveView.JS` commands**: `JS.toggle_class`, `JS.transition`, `JS.push` for
  pure client-side flips (show/hide the rules panel) without a round trip.
- **Keyed comprehensions** (`:for={chip <- @pot} :key={chip.id}`): cheaper diffs when the
  pot list changes. New default change-tracking in comprehensions helps too.
- **Streams**: for append-only, unbounded lists (a move log). Not for the pot or bag —
  those are small and fully re-rendered; plain assigns are simpler.
- **Function components + slots**: build `<.board>`, `<.chip>`, `<.pot>` as components
  with `attr`/`slot` (section 5). `<.portal>` exists for modals rendered outside a
  container.
- **LazyHTML** replaces Floki in tests; `:has()` selectors work in `assert has_element?`.

Sources: https://www.phoenixframework.org/blog/phoenix-liveview-1-1-released ·
https://phoenix-live-view.hexdocs.pm/1.1.1/changelog.html ·
https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.ColocatedHook.html ·
https://fly.io/blog/building-a-distributed-turn-based-game-system-in-elixir/ ·
https://speakerdeck.com/dkarter/building-multiplayer-games-with-phoenix-liveview

## 5. Tailwind v4 + Phoenix 1.8 `core_components.ex`

What 1.8 generates:
- `assets/css/app.css` imports Tailwind v4 (`@import "tailwindcss"`), the `@source`
  globs for your `lib/` templates, and `@plugin "../vendor/daisyui"` plus a theme file.
  No `tailwind.config.js`; v4 is CSS-first.
- `lib/quacks_web/components/core_components.ex`: slimmed down vs 1.7. `<.flash>`,
  `<.button>`, `<.input>`, `<.header>`, `<.table>`, `<.list>`, `<.icon>`, plus
  `translate_error`. Classes are daisyUI (`btn`, `input`, `alert`).
- `lib/quacks_web/components/layouts.ex`: one `Layouts.app` function component with
  slots, called explicitly from each LiveView template; `root.html.heex` stays.

Writing your own components (same file or `components/game_components.ex`):

```elixir
attr :chip, Quacks.Chip, required: true
attr :size, :atom, default: :md, values: [:sm, :md, :lg]
attr :rest, :global
slot :badge

def chip(assigns) do
  ~H"""
  <span class={["rounded-full inline-flex", chip_size(@size), chip_color(@chip.color)]} {@rest}>
    {@chip.value}
    {render_slot(@badge)}
  </span>
  """
end
```
`attr`/`slot` give compile-time warnings for missing required attrs, unknown attrs, bad
`values`. `:global` passes through `phx-click`, `id`, `class` etc. Named slots can
declare their own `attr`s inside a `do` block; `render_slot(@slot, value)` feeds `:let`.
Put the list-of-classes form `class={[...]}` to work; HEEx joins and drops `nil`/`false`.

**daisyUI: keep or drop?**
- Keep: free dark/light theming, decent defaults for buttons/inputs/modals, less CSS
  to write while learning. Cost: its class vocabulary leaks into every component.
- Drop (petar.dev recipe): remove the two `@plugin` lines from `app.css`, delete
  `assets/vendor/daisyui.js` and `daisyui-theme.js`, rewrite the handful of classes in
  `core_components.ex`, run `mix assets.build`. "No additional footprints." A board game
  with bespoke chips and a cauldron board probably wants its own look; dropping is cheap
  on day one and annoying on day sixty.

Sources: https://www.phoenixframework.org/blog/phoenix-1-8-released ·
https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html ·
https://petar.dev/notes/removing-daisy-ui-from-phoenix/ ·
https://elixirforum.com/t/option-to-pass-a-no-daisy-flag-when-creating-a-new-phoenix-project/72106

## 6. Examples in the wild

| Repo / talk | What it is | What it does well |
|---|---|---|
| https://github.com/dkarter/king_of_tokyo (+ ElixirConf 2020 deck) | King of Tokyo, multiplayer, LiveView | Explicit functional core; GenServer per game via Registry; Presence-based garbage collection of dead games. The talk is the clearest "core vs shell" walkthrough |
| https://github.com/fly-apps/tictac (Fly blog) | Tic-tac-toe, distributed | Minimal GenServer-per-game + PubSub + Horde; small enough to read in one sitting. Shows what you *add* when going multiplayer |
| https://github.com/dnsbty/level10 | Level 10 card game, multiplayer, 79 stars | Production-grade: clustering, `StateHandoff` for rolling deploys. Good reference for "later", heavy for now |
| https://github.com/adamvietro/game_site | Seven games on one Phoenix app | README states "pure Elixir game logic, fully testable without web"; ~450 tests across logic, LiveView and components. Good model for test layering ⚠️ versions not stated |
| AppSignal Go series (https://blog.appsignal.com/2019/06/18/elixir-alchemy-building-go-with-phoenix-live-view.html, part 2 above) | Go in LiveView | Pure `%State{}`, history list + index undo/redo, ko rule as a pure check. Old LiveView API, ideas still current |
| https://github.com/mreishus/demon_spirit_umbrella, https://github.com/alukasz/pentago | Abstract board games | Smaller single-purpose repos; pentago is a compact 2-player example ⚠️ not inspected in depth |
| Torben Hoffmann, "Implementing the logic for a board game in Elixir" (Acquire, NDC Oslo 2015) https://av.tib.eu/media/49673 | Talk | Rules-as-functions for a complex economic board game; closest in spirit to Quacks' rules complexity |

"Sheepish": no Elixir/LiveView game by that name was found ⚠️. Chris Ertel's ElixirConf US
2024 "Trials and Tribulations of LiveView RPG Development" and Gonçalo Tomás' ElixirConf EU
2024 multiplayer talk are relevant LiveView-game talks but not board games.
Index of more: https://github.com/njwest/Awesome-Elixir-Gaming ·
https://github.com/happycodrz/liveview-apps

## 7. Extensibility: the `Game` seam

Deep module shape: `Quacks.Game` exposes a few functions with a lot behind them. The
same five functions are what any turn-based game needs:

```elixir
defmodule Boardgame.Game do           # NOT YET — written here only to name the seam
  @callback new(opts :: keyword) :: struct
  @callback legal_actions(struct) :: [term]
  @callback apply(struct, term) :: {:ok, struct} | {:error, term}
  @callback over?(struct) :: boolean
  @callback score(struct) :: term
end
```

Recommendation: **do not create the behaviour now.** Write `Quacks.Game` with exactly
these five public names (plus private helpers). `Session` and `GameLive` call only those
five. When a second game arrives, extract the `@behaviour`, add
`@behaviour Boardgame.Game` to Quacks, and make `Session` take the module as a field
(`%Session{engine: Quacks.Game}`) — a mechanical change. Writing it now risks shaping
Quacks around guesses about game #2 (do all games have `score/1` returning an integer?
does `legal_actions/1` need player ids?). Elixir makes this cheap: a behaviour is a list
of `@callback`s, and LiveView/Session only need a module name.

Keep the seam honest in the meantime: the LiveView never reaches into `%Game{}` fields
except for rendering; everything that *changes* state goes through `apply/2`;
`legal_actions/1` drives which buttons are enabled. That discipline is what makes the
later extraction a one-commit job.

## Suggested first slice

1. `Quacks.Game` struct, `new/1` with seed, `:draw`/`:stop`, explosion check, `over?`.
   ExUnit tests with a fixed seed and a fixed bag.
2. `Quacks.Session` with action log + `undo/1`.
3. `GameLive` with struct in assigns, `<.chip>`/`<.pot>` components, Tailwind v4 only.
4. Later, if ever: persist `{seed, actions}`; GenServer + PubSub; `Boardgame.Game`.
