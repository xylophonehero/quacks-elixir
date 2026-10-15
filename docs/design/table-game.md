# Design RFC: `Table.Game`, a generic `Session` and `view/2`

Issue #78, part of epic #75. Written 2026-10-15 against `master`. Status: proposal.

The question: what contract must a game implement, so that `Session`, the
`GameServer`, the bots, the property tests and the gallery work with any game? The
first new games are No Thanks! (#85), Sushi Go! (#86) and Hearts (#87). The long-term
targets are Dominion, Codex and Mage Wars. Quacks is the first implementation.

Every `path:line` points at `master` today. The names stay searchable when lines drift.

## 0. Summary

| Question | Decision | Section |
|---|---|---|
| The contract | `Table.Game`: 6 required callbacks (`info/0`, `new/2`, `legal_actions/2`, `apply/3`, `status/1`, `view/2`) and 5 optional ones (`pace/1`, `auto_action/2`, `determinize/3`, `describe_action/2`, `features/2`). | 2 |
| Changes to the draft | `simultaneous?/1` becomes `pace/1` (it also covers the Quacks lockstep brew). `determinize/2` becomes `/3` (it needs an rng). `encode/2` becomes `features/2` (`encode` is taken by bundles). New: `info/0`. | 2 |
| `view/2` and PubSub | The server keeps one broadcast of the full state, now `{:game, id, version, state}`. The page applies `view/2` at one entry point, before any assign; a test checks no page assigns raw state. PubSub never leaves the BEAM, so this is enough. Version-ping-and-pull is the documented next step for multi-node or a costly view. | 3 |
| Second adapter | `Table.Game` lands with a ~60-line toy hidden-card game in `test/support/` in the same PR. No Thanks! is the first real game, the third adapter. | 2, 12 |
| Chance | Randomness stays inside `apply/3`, with `rng` in the struct and the `:rand` `_s` API. No explicit chance nodes. Search bots sample chance through `determinize/3`, which must also reseed `rng`. `Table.Kit.Rng` names the streams that today are hand-counted `:rand.jump/1` calls. | 4 |
| `Session` | `Table.Session{game, seed, players, opts, actions, state}`. `opts` is one map the game validates in `new/2`; today the options are restated in about 10 places. Bundle `version: 2` names the game. Version 1 bundles load as Quacks. The writer flips to v2 one deploy after the reader. | 5 |
| Layout | `Table.*` and `TableWeb.*` inside this app, not an umbrella. A test keeps `lib/table` free of game modules. | 6 |
| Prompts | `Table.Pending`: a stack of frames as plain data. It replaces the four "open choices, then `close_choices`" copies. The same stack grows into an effect stack with timing windows. Lands after the golden corpus, with Sushi Go as its second user. | 7 |
| Reveal together | Secrecy moves into the engine (a `secret` frame plus `view/2`). The server queue stays, but only for pacing bots. `pace/1` tells the server which mode it is in. | 8 |
| Bots | `Table.Bots`: one pure driver for "ask the bot, apply, keep its rng", written 7 times today. The server, `Sim`, `Bench` and `Script` call it; `Decider` gets `Table.Bots.RandomLegal` as its second adapter. | 9 |
| Migration | About 20 small PRs. Step 0 records a golden corpus of v1 bundles. Every later step must replay it to the same log and score. | 12 |

This RFC folds in the architecture review (`docs/research/architecture-review.md`,
issue #77). Where it takes the review's advice over its own first draft, the section
says so.

## 1. Where we start

Most of the platform is already there. It only has Quacks names.

- **The engine is a pure reducer.** `Quacks.Game.apply/3` checks the action against
  `legal_actions/2` and returns `{:ok, game}` or `{:error, reason}`
  (`lib/quacks/game.ex:689-698`). That is the `Table.Game` contract already.
- **The rng is in the struct.** `rng = :rand.seed_s(:exsss, seed)` (`lib/quacks/game.ex:407`).
  Seed plus actions rebuild the game (`lib/quacks/session.ex:100-105`).
- **Bundles are generic, but for the opts.** The term encoding of actions
  (`lib/quacks/session.ex:194-212`) works for any game. Only the `opts` block
  (`lib/quacks/session.ex:122-128`) and `encode_opts/1` (`lib/quacks/session.ex:169-179`)
  name Quacks fields.
- **The bot contract is one callback** (`lib/quacks/ai/decider.ex:11-12`). It names
  `Game.t()`; nothing else in it is Quacks.
- **The bench is generic but for three calls**: `Game.new/1`, `Game.score/1` and the
  explosion stats (`lib/quacks/ai/bench.ex:116-122`, `:151`, `:184-197`).

What is Quacks-specific, and must go behind callbacks:

- `GameServer` knows the Quacks phases: `@concurrent` (`lib/quacks/game_server.ex:1222`),
  `held?/1` (`:1315-1316`), `drawing?/2` and `mid_draw?/2` (`:1373-1434`), the Mandrake
  answer `auto_return/1` (`:1208-1219`) and `keep_white` (`:802-805`), and the patient
  picks (`:238-253`).
- The whole `%Game{}` goes to every page: `reply_game/1` (`lib/quacks/game_server.ex:1561-1565`)
  and the tick (`:1126`). `GameLive` keeps it and calls engine functions on it
  (`lib/quacks_web/live/game_live.ex:2247-2252`).
- Four modules repeat "open choices, then `close_choices`" (section 7).

## 2. The contract

```elixir
defmodule Table.Game do
  @moduledoc """
  The contract every game implements. Pure: no processes, no IO, no hidden rng.
  All randomness comes from the state's own rng with the `:rand` `_s` API.
  """

  @type state :: term
  @type seat :: non_neg_integer
  @type audience :: seat | :spectator
  @type action :: term
  @type seed :: {integer, integer, integer}
  @typedoc "Validated by the game. `:players` is the one key `Table` reads."
  @type opts :: %{required(:players) => pos_integer, optional(atom) => term}
  @typedoc "Compared with Erlang term order; higher wins. Put tie-breaks in a tuple."
  @type score :: number | tuple
  @type status :: {:playing, [seat, ...]} | {:over, %{seat => score}}
  @typedoc "Whatever the game's board component renders. Never holds hidden zones."
  @type view :: term
  @type pace :: :turns | :simultaneous | {:lockstep, in_step :: [seat], steps :: [action]}

  @callback info() :: %{
              id: String.t(),
              name: String.t(),
              players: Range.t(),
              version: pos_integer,
              hidden?: boolean
            }

  @callback new(opts, seed) :: {:ok, state} | {:error, term}
  @callback legal_actions(state, seat) :: [action]
  @callback apply(state, seat, action) :: {:ok, state} | {:error, term}
  @callback status(state) :: status
  @callback view(state, audience) :: view

  # Server: how bots are paced. Default `:turns`.
  @callback pace(state) :: pace
  # Server: an answer it gives for a human at once, which the human can take back.
  @callback auto_action(state, seat) :: action | nil
  # Bots: a full state that `seat` cannot tell from the real one, with a fresh rng.
  @callback determinize(state, seat, :rand.state()) :: {state, :rand.state()}
  # UI and bug reports: one line of text. Reads the view, so it cannot leak.
  @callback describe_action(action, view) :: String.t()
  # Learning bots (#88, later): a flat numeric encoding of what `audience` sees.
  @callback features(state, audience) :: [number]

  @optional_callbacks pace: 1, auto_action: 2, determinize: 3, describe_action: 2, features: 2
end
```

### The invariants (the property suite checks them, section 10)

1. `status(s) == {:playing, active}` means `active != []`, and `active` is exactly the
   seats with `legal_actions(s, seat) != []`. This is the Quacks invariant
   (`lib/quacks/game.ex:19-20`) for every game.
2. Every action in `legal_actions(s, seat)` gives `{:ok, _}`. Anything else gives
   `{:error, _}`, and the caller keeps `s`. No second set of checks.
3. `new/2` and `apply/3` are deterministic. Same seed, same opts, same actions: same
   state.
4. `view(s, a)` holds nothing that `a` may not see (section 3, section 10).

### Why these changes to the draft

- **`info/0` is new and required.** The lobby needs a name and a player range. A
  bundle needs a stable id string (`"quacks"`, `"no_thanks"`). `version` is the rules
  version, for the log and for a bundle that no longer replays.
- **`pace/1` replaces `simultaneous?/1`.** Quacks has three bot modes, not two:
  ticks, plans in the concurrent phases, and the potions lockstep where bots draw
  with the humans (`lib/quacks/game_server.ex:1322-1349`). A boolean cannot say the
  third. Two booleans could both be true. One callback with three answers cannot.
  `simultaneous?(s)` is `pace(s) == :simultaneous`.
- **`determinize/3`, not `/2`.** It must sample, so it takes an rng and gives it
  back. It cannot use the state's own `rng`: that rng *is* the real future (section 4).
- **`features/2`, not `encode/2`.** `encode` already means "to JSON" in
  `Session.bundle/1` (`lib/quacks/session.ex:194`). #88 wants a numeric vector for a
  network. A different name avoids two meanings.
- **`describe_action/2` reads the view.** `Quacks.BugReports` calls
  `QuacksWeb.GameText.log_text/3` today (`lib/quacks/bug_reports.ex:178`): the core
  depends on the web layer. With this callback the words live in the game module,
  and both the page and the report call it.

### What stays out of the contract

- **No `phase/2`.** Phases are a Quacks idea. A game that has them shows them in its
  view.
- **No `undo/1`.** Undo is replay minus one action (`lib/quacks/session.ex:80-95`). It
  is the same for every game, so `Table.Session` owns it.
- **No `seats/1`.** `opts.players` gives the seats `0..players-1`. Every game uses
  that numbering.

### `use Table.Game`

`use Table.Game` gives the defaults: `pace/1` returns `:turns`, `auto_action/2`
returns `nil`. There is no default `determinize/3`. A wrong default there is a
cheating bot, so ISMCTS refuses a game without one.

### Quacks implements it

`Quacks.Game` already has `legal_actions/2` and `apply/3` with the right shape.
It needs four small functions:

```elixir
@impl Table.Game
def info,
  do: %{id: "quacks", name: "The Quacks of Quedlinburg", players: 1..8, version: 1, hidden?: false}

@impl Table.Game
def new(%{players: n} = opts, seed) do
  {:ok, new([seed: seed, players: n] ++ Map.to_list(Map.delete(opts, :players)))}
rescue
  e in ArgumentError -> {:error, {:bad_opts, Exception.message(e)}}
end

@impl Table.Game
def status(%__MODULE__{phase: :over} = g), do: {:over, score(g)}
def status(g), do: {:playing, Enum.filter(g.seats, &(legal_actions(g, &1) != []))}

# Step 1: the same struct, so the ~150 `Game.*` reads in lib/quacks_web keep working.
# Hidden in Quacks: the future (rng) and the order of the fortune deck.
@impl Table.Game
def view(%__MODULE__{} = g, _audience),
  do: %{g | rng: nil, fortune_deck: Enum.map(g.fortune_deck, fn _ -> :hidden end)}
```

`new/1` (keyword list, raises) stays for the tests and the gallery. `new/2` is a
different arity, so there is no clash. The bags stay in the view: a bag is public in
Quacks, and without the rng its list order tells nothing.

### A second adapter in the same PR

A behaviour with one adapter is a guess at a seam. The repo's own research says
"do not write a `Game` behaviour until a second game exists"
(`docs/research/state-machine-liveview.md`, TL;DR), and the review says the same
(§3.3). Quacks also has almost no hidden zone, so it cannot test `view/2` at all.

So `Table.Game` lands with `Table.Test.HighCard` in `test/support/`: about 60 lines.
Each seat is dealt one card face down from a shuffled 1..20; then each seat, in
order, bids or folds once; the highest card among the bidders wins. It has one
hidden zone per seat, one shuffle, a turn order and a score. In that PR it runs
through `Table.Session`, the generic property suite (section 10), `Table.Bots` with
`RandomLegal` (section 9) and `determinize/3`. It is a test fixture, never a page.
No Thanks! (#85) is then the first real game and the third adapter (section 13).

## 3. `view/2` and PubSub

### What leaks today, exactly

The server broadcasts the whole struct: `{:game, id, game}`
(`lib/quacks/game_server.ex:1561-1565`). It reaches every LiveView *process*. It does
not reach the browser: PubSub stays inside the BEAM, and LiveView sends only rendered
HTML. So in Quacks nothing leaks to a player today. The issue text ("leaks hands")
overstates it; the review corrects it (§0, §4).

The risk is what a page renders or pushes. One component that reads
`@game.players[other]` instead of `@game.players[@seat]` shows a hand. So does a
`push_event` payload, a gallery story or a debug panel. Today nothing stops that.
`view/2` stops it if the page never holds the raw state in its assigns.

### Decision: apply `view/2` in the page, before any assign

The server keeps one broadcast per change. It adds a version:

```elixir
# Table.Server, after every change (an action, a bot step, an undo, a seek):
state = %{state | version: state.version + 1}
broadcast(state, {:game, state.id, state.version, state.session.state})
{:reply, {:ok, state.version, state.session.state}, state, @idle_timeout}
```

The page turns the state into a `Table.View` at one entry point, and assigns only
that:

```elixir
defmodule Table.View do
  @moduledoc "What one audience may see, plus what the shell needs."
  defstruct [:game, :version, :audience, :status, legal: [], board: nil]

  @type t :: %__MODULE__{
          game: module,
          version: non_neg_integer,
          audience: Table.Game.audience(),
          status: Table.Game.status(),
          legal: [Table.Game.action()],
          board: Table.Game.view()
        }

  @doc "The only way a page turns a state into assigns."
  @spec build(module, Table.Game.state(), Table.Game.audience(), non_neg_integer) :: t
  def build(game, state, audience, version) do
    %__MODULE__{
      game: game,
      version: version,
      audience: audience,
      status: game.status(state),
      legal: if(is_integer(audience), do: game.legal_actions(state, audience), else: []),
      board: game.view(state, audience)
    }
  end
end
```

```elixir
# TableWeb.TableLive (GameLive until #82): the one door. `put_game/2`
# (lib/quacks_web/live/game_live.ex:2247) is that door today.
def handle_info({:game, _id, v, _state}, %{assigns: %{view: %{version: shown}}} = socket)
    when v <= shown,
    do: {:noreply, socket}

def handle_info({:game, _id, v, state}, socket),
  do: {:noreply, put_view(socket, Table.View.build(socket.assigns.game_mod, state, audience(socket), v))}
```

- **One door.** `put_view/2` is the only function that assigns game data. The
  gallery's `preview/3` is the second caller and goes through `Table.View.build/4` too.
- **A test guards it.** For every LiveView and every gallery story: after mount and
  after a broadcast, no assign holds a value whose struct is the game's state module
  (a recursive walk of `socket.assigns`, skipping `Table.View.board`). For a game whose
  view is the redacted state struct (Quacks), the walk checks `rng == nil` instead.
- **The version** replaces the "shorter log means older" check
  (`lib/quacks_web/live/game_live.ex:624-629`). A log gets shorter after an undo; a
  version never goes down.
- **Bots** get the same rule: a generic bot sees only `view/2` and `determinize/3`
  (sections 4 and 9).

### Alternatives considered

| | A. One message per seat | B. Version ping, page pulls | C. State in the BEAM, view in the page (chosen) |
|---|---|---|---|
| Hidden info in the browser | never | never | never, if the one door holds; a test checks it |
| Hidden info in a page process | never | never | in the mailbox, until `build/4` drops it |
| Server change | per-seat topics, track every page's seat | `{:view, token}` call, an audience cache | add a version to the message |
| Seat changes (begin renumbers, rejoin, a spectator sits down) | leave one topic and join another, with a gap or a double | free: the server resolves the token on each pull | free: the page uses its current seat |
| Work per change | one view per audience | one view per audience that asks, plus one call per page | one view per page |
| Burst of changes (a bot brew, a flush of plans) | one message per seat per change | coalesced by version | one message per change, older versions skipped |

My first draft chose B: the server would be the single place that knows who sees
what. The review argued for C (§4), and I agree, for three reasons:

- **The threat is the browser, not the BEAM.** A and B protect against code in our
  own node reading a mailbox. That is not an attacker we have.
- **C changes nothing on the server.** It adds a version to a message. B adds a call
  per page per change, a cache, and a third way to fail (`:not_found` during a pull).
- **C keeps the seam where it already is.** `put_game/2` is the one place a game
  enters the assigns today. The rule "assign a view, never a state" is local and
  testable.

**When to move to B.** If the table runs on more than one node (PubSub then crosses
the network, so the raw state travels). If a game's `view/2` is costly and many
spectators watch (B computes one view per audience, C one per page). The page code
does not change between C and B: only where `Table.View.build/4` runs.

### The cost for Quacks

- **CPU.** A Quacks view is a map update. `legal_actions/2` already runs in the page
  today (`lib/quacks_web/live/game_live.ex:2252`), under 0.01 ms. `Game.apply/3` is
  0.02 ms (`docs/guide/04-gameserver.md`, "What a draw costs").
- **Messages.** Same as today: one broadcast, one copy per page.
- **Patch size.** No change. The templates render the same struct (11 to 13 KB for
  the drawing tab, about 7 KB for the others).

### Bug reports and debug replay

A bundle is seed plus actions, so it holds every hidden card. Today a report goes
into a GitHub issue (`Quacks.BugReports`, chapter 4 of the guide). For a hidden-hand
game, a player could file a report mid-game and read the deal from a public issue.
Rule: the issue gets the bundle only when `status/1` is `{:over, _}` or the game
declares no hidden information (`info().hidden?` is `false`, as for Quacks).
Otherwise the bundle stays in the server's report directory and the issue holds its
id. `/debug/replay` is already gated (`lib/quacks_web/router.ex:28`).

## 4. Chance and hidden information for bots

### Decision: randomness stays inside `apply/3`

The rng stays in the struct and every random pick uses the `_s` API, as today
(`lib/quacks/game/potions.ex:644`). There is no chance node in the contract.

Explicit chance nodes (a `:chance` pseudo-seat whose "actions" are the outcomes, as
in OpenSpiel) would buy two things: exact expectimax for any game, and bundles that
record outcomes, so they do not depend on the rng algorithm. They cost more than
they give here:

- A Quacks draw is not one random event. A blue chip draws several
  (`lib/quacks/game/potions.ex:393`), the stir resolves several seats in one apply
  (`lib/quacks/game.ex:801-818`), and the deck shuffles at `new/1`. Each would split
  into "ask chance, wait, go on". The engine would change everywhere.
- Every v1 bundle would stop replaying, or need a second code path forever.
- The bot that needs exact odds already has them, with a model that fits its game
  (`Quacks.AI.Odds`, `Quacks.AI.Expectimax`). A generic search bot samples instead.

### `determinize/3`: how a search bot sees the world

A search bot must not read the true state. In Quacks the rng in the struct *is* the
future. A bot that runs `apply/3` on a copy of the real game sees which chip comes
next. `plan/2` does exactly this today (`lib/quacks/game_server.ex:1260-1283`). The
heuristic bot never reads the rng, so it is safe. A tree search would not be.

`determinize(state, seat, rng)` returns a full state that `seat` cannot tell from the
real one:

- every zone `seat` cannot see is resampled, keeping what `seat` knows (counts,
  cards already seen, cards known to be out);
- the state's rng is replaced with one drawn from the bot's rng.

For Quacks it is cheap: reseed `rng` and shuffle `fortune_deck`. The bags are public.

```elixir
@impl Table.Game
def determinize(%__MODULE__{} = g, _seat, rng) do
  {deck, rng} = Table.Kit.Rng.shuffle(g.fortune_deck, rng)
  # The world's rng: a jump of the bot's own rng, unrelated to the real future.
  world_rng = :rand.jump(rng)
  {_, rng} = :rand.uniform_s(rng)
  {%{g | fortune_deck: deck, rng: world_rng}, rng}
end
```

Chance falls out of this. Each ISMCTS iteration samples a fresh world, rng included,
so the draws in its rollout are a fair sample. No chance nodes needed.

### Named rng streams

Quacks splits its rng into independent streams by counting `:rand.jump/1` calls by
hand: the fortune deck takes 1 jump (`lib/quacks/game/fortune.ex:85`), the witches 2
(`lib/quacks/rules/witches.ex:119`), the patients 3
(`lib/quacks/rules/alchemists.ex:163`), the patient picks 4
(`lib/quacks/game/essence.ex:67`). The trick is good: a game with cards draws the
same chips as the same seed without them. The bookkeeping is not: a new deal must
know every other count, and the counts sit in four files (review §3.7).

`Table.Kit.Rng` names them once per game:

```elixir
defmodule Table.Kit.Rng do
  @type streams :: %{atom => pos_integer}

  @doc "The stream `name` of `rng`: `streams[name]` jumps. Same seed, same stream."
  @spec stream(:rand.state(), atom, streams) :: :rand.state()
  def stream(rng, name, streams),
    do: Enum.reduce(1..Map.fetch!(streams, name), rng, fn _, r -> :rand.jump(r) end)

  @doc "Sort by one uniform draw per item: the algorithm `Fortune.deck/4` uses today."
  @spec shuffle([a], :rand.state()) :: {[a], :rand.state()} when a: term
  def shuffle(list, rng) do
    {keyed, rng} =
      Enum.map_reduce(list, rng, fn x, r ->
        {u, r} = :rand.uniform_s(r)
        {{u, x}, r}
      end)

    {keyed |> Enum.sort() |> Enum.map(&elem(&1, 1)), rng}
  end

  @spec pick([a], :rand.state()) :: {a, :rand.state()} when a: term
  def pick(list, rng) do
    {i, rng} = :rand.uniform_s(length(list), rng)
    {Enum.at(list, i - 1), rng}
  end
end

# Quacks.Game declares its streams in one place:
@streams %{fortune: 1, witches: 2, patients: 3, picks: 4}
```

The numbers stay what they are, so every seed deals the same deck, witches and
patients. A golden test checks that before and after. `Kit.Bag`, `Kit.Dice` and
`Kit.Zone` wait for their second user (review §3.7): `take_random/3` is 10 lines
(`lib/quacks/game/potions.ex:644-653`), and a wrapper would not make it deeper.

### ISMCTS on the contract (#88)

Single-observer ISMCTS uses only `legal_actions/2`, `apply/3`, `status/1` and
`determinize/3`:

```elixir
def decide(game, state, seat, %{iterations: n} = budget, rng) do
  {tree, rng} =
    Enum.reduce(1..n, {Tree.new(), rng}, fn _, {tree, rng} ->
      {world, rng} = game.determinize(state, seat, rng)
      iterate(game, world, seat, tree, budget, rng)
    end)

  {Tree.best(tree), rng}
end
```

- **Select**: UCB over the actions legal *in this world*, with availability counts.
- **Expand**, then **roll out** with the random-legal bot up to a depth cap.
- **Back up** a utility from `{:over, scores}`: 1 for a win, shared on a tie, as
  `Bench` already counts wins (`lib/quacks/ai/bench.ex:155-162`).
- **Simultaneous moves**: in a secret frame (section 7) the earlier seats' answers
  are hidden from later seats. `determinize/3` resamples them. That is how
  single-observer ISMCTS handles simultaneous moves without a special case.
- **Budget**: Quacks plays about 500 actions. At 0.02 ms per apply, one full rollout
  is about 10 ms. So ISMCTS on Quacks needs the depth cap; the Quacks bots stay.
  ISMCTS is for No Thanks!, Sushi Go and Hearts, where games are short.

## 5. `Session` and bundles

### The struct

```elixir
defmodule Table.Session do
  @moduledoc "A game module, a seed, opts and the actions that built the state."

  defstruct [:game, :seed, :players, opts: %{}, actions: [], state: nil]

  @type t :: %__MODULE__{
          game: module,
          seed: Table.Game.seed(),
          players: pos_integer,
          opts: map,
          actions: [{Table.Game.seat(), Table.Game.action()}],
          state: Table.Game.state()
        }

  @spec new(module, Table.Game.seed(), map) :: {:ok, t} | {:error, term}
  def new(game, seed, %{players: n} = opts) do
    with {:ok, state} <- game.new(opts, seed),
         do: {:ok, %__MODULE__{game: game, seed: seed, players: n, opts: opts, state: state}}
  end

  @spec apply(t, Table.Game.seat(), Table.Game.action()) :: {:ok, t} | {:error, term}
  def apply(%__MODULE__{} = s, seat, action) do
    with {:ok, state} <- s.game.apply(s.state, seat, action),
         do: {:ok, %{s | state: state, actions: [{seat, action} | s.actions]}}
  end

  # undo/1, replay/4, view/2, bundle/1, from_bundle/2: as in lib/quacks/session.ex,
  # with `s.game` in place of `Quacks.Game`.
end
```

### One opaque `opts` map

The game owns its options. `Table.Session` stores the map, passes it to `new/2` and
writes it into the bundle. It reads one key: `:players`. A bad map is
`{:error, reason}` from `new/2`; the lobby shows it. This replaces `valid?/2`, which
calls `Game.new/1` and rescues (`lib/quacks/game_server.ex:1551-1557`).

Today the options are restated in about ten places (review §3.2): the session struct
(`lib/quacks/session.ex:10-19`), `@game_opts` (`:35`), `new/3` (`:54`), `undo/1`
(`:83-95`, by hand, with a different list than `new/3`), `bundle/1` (`:117`),
`from_bundle/2` (`:140`), `encode_opts/1` and `decode_opts/1` (`:169-192`); then
`GameServer.start/5`, `create/3`, `configure`, `valid?/2` and `table/1`
(`lib/quacks/game_server.ex:177`, `:203`, `:935`, `:1551`, `:1710`), and
`Keyword.take(opts, [...])` in `Sim` and `Bench` (`lib/quacks/ai/bench.ex:65`). Adding
one option touches all of them. With one map that only the game reads, adding an
option touches the game.

The review proposes a separate `config/1` callback for validation. I fold it into
`new/2`: a lobby check builds a game with a fixed seed, as `valid?/2` does today, and
that takes microseconds. One callback fewer. If a game's `new/2` ever gets costly,
`config/1` can come back as an optional callback.

Alternatives: a keyword list (as `Game.new/1` takes) does not encode to JSON well and
allows duplicate keys. A per-game opts struct gives compile-time keys, but each game
then needs its own encode and decode. A map with atom keys goes through the existing
term encoding (`lib/quacks/session.ex:194-212`) with no game code.

### Bundle version 2

```json
{
  "version": 2,
  "game": "quacks",
  "rules_version": 1,
  "seed": [1, 2, 3],
  "players": 2,
  "opts": {"m": [["rules", {"m": [["explode_above", 9]]}], ["expansions", {"l": ["herb_witches"]}]]},
  "log": [[0, "draw"], [1, "draw"], [0, ["buy", {"l": [["green", 2]]}]]],
  "names": ["Ann", "Bot"],
  "bots": [1]
}
```

- `game` is `info().id`. The module comes from a fixed map in config:
  `config :quacks, :games, %{"quacks" => Quacks.Game, "no_thanks" => NoThanks.Game}`.
  Never `String.to_atom/1` and never `Module.concat/1` on bundle input.
- `opts` and `log` use the existing encoding. Decoding uses
  `String.to_existing_atom/1`, so an unknown name is `{:error, :invalid}`, as today.
- `rules_version` is `info().version` when the bundle was written. A bundle that no
  longer replays fails the same way as now (the `{:ok, _} =` match in replay, rescued).
  The version tells the developer why.

### Old bundles still load

A bundle with `"version" => 1` and no `"game"` is a Quacks bundle. `from_bundle/2`
upcasts it before anything else:

```elixir
defp upcast(%{"version" => 1} = b) do
  opts = Quacks.Game.decode_v1_opts(b["opts"], b["players"])
  Map.merge(b, %{"version" => 2, "game" => "quacks", "rules_version" => 1, "opts" => opts})
end

defp upcast(%{"version" => 2} = b), do: b
```

`decode_v1_opts/2` is today's decoding (`lib/quacks/session.ex:147-153`), moved into
the Quacks module. It also maps the legacy `expansion` field (removed by #79) into
`expansions`. The game files on disk (`"table"` → `"opts"`, written by
`encode_opts/1`) get the same treatment.

**Deploy order.** The game files outlive a deploy (`docs/guide/04-gameserver.md`,
"Games on disk"). If the writer flips to v2 in the same release as the reader, a
rollback cannot read the files the new release wrote. So: one release reads v1 and
v2 and still writes v1. The next release writes v2.

## 6. Namespace and layout

### Decision: `Table.*` in this app

```
lib/
  table/          Table.Game, Session, View, Pending, Server, Store, Registry of games
  table/ai/       Table.AI.Decider, ISMCTS, Bench, Tune; Table.Bots (+ RandomLegal)
  table/kit/      Table.Kit.Rng, Deck, PlayingCards (Bag, Dice, Zone with their second user)
  table_web/      TableWeb.TableLive, TableWeb.Components.*, gallery shell
  quacks/         Quacks.Game (+ Game.*), Quacks.AI.*, Quacks.Rules.*
  quacks_web/     QuacksWeb.Board and the Quacks components
  no_thanks/      NoThanks.Game, NoThanks.AI
  no_thanks_web/  NoThanksWeb.Board
```

- `Table.*` never names a game module. Games are found through the config map. A
  test greps `lib/table` and `lib/table_web` for `Quacks.` and fails on a hit. It is
  plain and needs no library.
- Do not define a bare `Table` module. The hex package `table` (used by Explorer
  and Kino) defines `Table` and `Table.Reader`. Distinct submodule names do not clash;
  the bare name would.
- The OTP app stays `:quacks`. A rename touches Fly, config and the games directory
  for no gain now.

### Alternatives considered

- **An umbrella** (`apps/table`, `apps/quacks`, `apps/web`). The compiler would
  enforce the boundary. But it splits config, the release, `mix precommit`, the
  Tailwind `@source` paths and the colocated hooks, and moves hundreds of
  references. There is one deployable. The grep test buys most of the boundary for
  none of that.
- **A path dependency** (`table/` as its own Mix project). Worth it only if a second
  app ever uses `Table`. Nothing plans that. The layout above can move there later
  with no module renames.

## 7. `Table.Pending`: one prompt model

### The four copies

Each of these does the same five things: put the open seats in a "choice" phase,
list each seat's options, apply an answer, close each seat with no options left, and
go on once no seat is open.

| Module | Open | Options | Close a seat | When nobody is open |
|---|---|---|---|---|
| Fortune | `open_choices/1` (`lib/quacks/game/fortune.ex:678-685`) | `choices/2` (`:717`) | `answered/2` (`:691-700`) | `continue/1` (`:704-715`) |
| Evaluation | `run/1` (`lib/quacks/game/evaluation.ex:54-60`) | `choices/2` (`:314`) | `done/2` (`:89`) | `Witches.open_gold/1` (`:80-87`) |
| Witches | `open_gold/1` (`lib/quacks/game/witches.ex:172-182`) | `legal_actions/2` | `gold_done/2` (`:190-191`) | `Evaluation.score/1` (`:184-188`) |
| Essence | `open/1` (`lib/quacks/game/essence.ex:280-297`) | `legal_actions/2` (`:104-121`) | `settle/2` (`:250-261`) | `Fortune.after_essence/1`, `Evaluation.run/1` (`:263-267`) |

Each keeps its state in two places: `game.phase` and `player.phase`. Each also has a
private field for "what is left": `pending`, `chip_choices`, `essence_pending`,
`witch_offer` (`lib/quacks/player.ex:52-78`).

There is already a stack, too. A waiting droplet move comes before the phase's own
actions, in any phase (`lib/quacks/game.ex:571-579`). A fortune choice opens inside
the potions phase at a stop (`lib/quacks/game/fortune.ex:448-476`). Today each of
those is a special case in `legal_actions/2`.

### The model

A frame is one open question. Frames sit on a stack. The top frame owns the legal
actions of the seats it asks. Everything is data: no closures. A closure cannot be
compared, printed in the debug scrubber, built in a gallery fixture or shown in a
view ("waiting for Ann to answer Toil and Trouble").

```elixir
defmodule Table.Pending do
  @moduledoc "A stack of open questions, as data. The game gives each frame its meaning."

  defstruct frames: []

  @type seat :: Table.Game.seat()
  @typedoc """
  `:together`: every open seat answers, in any order (Quacks choices, Sushi Go).
  `:in_order`: one seat at a time, in the list order (priority, timing windows).
  """
  @type mode :: :together | :in_order
  @type frame :: %{
          id: term,
          mode: mode,
          open: [seat],
          secret: boolean,
          answers: %{seat => term},
          data: term,
          then: term
        }
  @type t :: %__MODULE__{frames: [frame]}

  @doc "What the game must give a frame."
  @callback options(state :: term, seat, frame) :: [Table.Game.action()]
  @callback answer(state :: term, seat, frame, Table.Game.action()) ::
              {state :: term, :open | :done}
  @callback reveal(state :: term, frame) :: state :: term
  @callback resume(state :: term, then :: term) :: state :: term

  @spec push(state, module, frame) :: state when state: term
  @spec legal_actions(state :: term, module, seat) :: [Table.Game.action()] | :none
  @spec answer(state, module, seat, Table.Game.action()) :: state when state: term
  @spec settle(state, module) :: state when state: term
end
```

The driver:

- `push/3` puts a frame on top, then `settle/2`.
- `legal_actions/3` is the top frame's `options/3` for a seat it asks (the first one
  for `:in_order`), `[]` for a seat it does not ask, and `:none` when the stack is
  empty, so the game's own phase answers.
- `answer/4` calls the game's `answer/4`. On `:done` the seat leaves `open`. In a
  `secret` frame the answer goes into `answers` and changes nothing else yet.
- `settle/2` is today's `close_choices` once, for all four: drop each open seat whose
  `options/3` is `[]`. If `open` is empty, pop the frame, call `reveal/2` (a secret
  frame applies its answers now, in seat order), then `resume/2` with `then`.
  `resume/2` may push again. Loop until the top frame has an open seat or the stack is
  empty.

The game's `legal_actions/2` and `apply/3` call the driver first:

```elixir
def legal_actions(g, seat) do
  case Table.Pending.legal_actions(g, __MODULE__, seat) do
    :none -> phase_actions(g, seat)
    actions -> actions
  end
end
```

Fortune then becomes one frame `%{id: {:fortune, card}, mode: :together, open: seats,
secret: false, then: :after_fortune}`. `answer/4` is today's `choose/4` plus the AP7 and
AP8 "choose again" rule (`lib/quacks/game/fortune.ex:691-695`). `resume(g,
:after_fortune)` is today's `continue/1`. The droplet move is a frame `{:droplet,
seat}` pushed by `move_droplet/3`.

Quacks answers are not secret. They apply at once, as today, which matters: with a
limited supply the first answer gets the chip (`lib/quacks/game/fortune.ex:702`).

### Rules for the migration

- **The log must not change.** The golden corpus (section 12) compares logs, event
  for event. So `answer/4` and `resume/2` must log what the old code logged, in the
  same order.
- **`player.phase` stays written** while the UI reads it (`Game.phase/2`,
  `lib/quacks/game.ex:524-534`). A later PR derives it from the top frame.
- **One module per PR**: Witches first (the smallest), then Evaluation, Fortune,
  Essence.
- **Not before its second user.** The round order is a chain of tail calls across
  four files (`Fortune.close_choices` → `Essence.run` → `Evaluation.run` →
  `Witches.open_gold` → `Evaluation.score` → the shop), and it carries many fixes.
  So `Table.Pending` lands after the golden corpus, together with Sushi Go (review
  §3.9). No Thanks! does not need it.

### Growing into an effect stack (Codex, Mage Wars)

The same stack, with two more frame kinds that the game defines:

- **An effect frame**: a spell, an attack, a trigger. It has no open seats of its own.
  It resolves when it reaches the top and the window above it closed.
- **A window frame**: `mode: :in_order`, `open` in priority order. Each seat may
  respond (which pushes a new effect frame on top) or pass. The window closes when
  every seat has passed since the last push. Then the effect under it resolves.

Casting a spell in Codex: push the effect, push a response window on it. A response
goes on top, gets its own window, and resolves first: last in, first out. A timing
window in Mage Wars ("before the attack roll", the Quickcast step) is a window frame
pushed by the game at that step. Triggers that fire together are pushed in turn
order, so the last pushed resolves first. Choosing a target is a prompt frame on top
of the effect that asked for it.

Face-down cards are not a stack question. They are zones with an owner and a
visibility (`Table.Kit.Zone`, #83), and `view/2` hides them.

## 8. "Decide in secret, reveal together"

### Today

In `@concurrent` phases (`lib/quacks/game_server.ex:1222`) a bot does not tick. It
plans its whole part on a private copy (`plan/2`, `:1260-1283`). The plan waits in
`queued` while a human still decides (`humans_deciding?/2`, `:1225-1228`). Then
`flush/1` applies every plan through `Session.apply/3` (`:1233-1256`). Human answers
are not queued: a human's buy shows as soon as it is made.

So the queue does two jobs. It hides a bot's answer until the humans answered
(secrecy). And it makes the bot decide from the state at the start of the phase, not
after it saw the humans' answers (pacing and fairness).

### Generalised

**Secrecy goes into the engine.** In Sushi Go every pick is secret, humans included.
The server cannot hide a human's answer from other humans: the engine has already
applied it. So the engine holds it. A `secret: true` frame stores answers in
`answers`. `view/2` shows other seats only that a seat has answered. `reveal/2`
applies all answers when the last one is in. The rules are now in the engine, they
replay, and a test can check them.

**Pacing stays in the server.** The server reads `pace/1`:

| `pace/1` | Server does | Quacks today |
|---|---|---|
| `:turns` | a tick per bot that can act | round 9, the patient choice |
| `:simultaneous` | bots plan from their own information and queue; flush when no human in `status/1` is active | `@concurrent` phases |
| `{:lockstep, in_step, steps}` | each human step (an action in `steps`) is counted; when every human in `in_step` stepped, each bot in `in_step` plays to its next step; when no human is in `in_step`, bots play out in one go | potions, rounds 1 to 8 (`step_bots/4`, `brew_bots/2`) |

Quacks `pace/1`:

```elixir
@concurrent [:fortune_choice, :chip_choice, :witch_choice, :shopping]

@impl Table.Game
def pace(%__MODULE__{phase: phase}) when phase in @concurrent, do: :simultaneous

def pace(%__MODULE__{phase: :potions, round: round} = g) when round < 9,
  do: {:lockstep, Enum.filter(g.seats, &drawing?(g, &1)), [:draw, :stop]}

def pace(_g), do: :turns
```

`drawing?/2` moves from the server (`lib/quacks/game_server.ex:1426-1434`) into the
engine. A bot's step ends after a step action once the bot has left `in_step` or has
a step action legal again. That replaces `mid_draw?/2` (`:1373-1381`). The migration
PR must keep `game_server_test.exs` and `game_server_r10_test.exs` green; if an edge
case differs, `drawing?/2` is the one place to fix.

**Bots plan from what they may see.** `plan/2` runs on a copy of the real state. A
generic bot reads the state only through `view/2` and `determinize/3`. A property
checks it: a bot's decision on `s` equals its decision on `determinize(s, seat, r)`
for the same bot rng. Quacks.AI reads the struct directly (the game is open but for
the rng), and passes that property.

**Sushi Go** then needs no server code: one secret `:together` frame per pick, with
`then: :pass_hands`. `pace/1` returns `:simultaneous`, so a bot does not answer in
the first millisecond. Its answer would be hidden anyway.

### The Mandrake answer: `auto_action/2`

`auto_return/1` (`lib/quacks/game_server.ex:1208-1219`) and `keep_white/2` (`:802-805`)
become generic. After each change, for each human seat, the server asks
`auto_action(state, seat)`. If it gives an action, the server applies it and keeps the
session from before in `auto_keep`. `Table.Server.take_back(id, seat, action)` applies
`action` on that saved session if it is legal there. Bots wait while `auto_keep` is
set, as today (`:1289`).

```elixir
@impl Table.Game
def auto_action(g, seat), do: if(phase(g, seat) == :yellow_choice, do: :return_white)
```

### Where `pace/1` and `auto_action/2` live

The review (Q2) would put them in a separate `Quacks.TablePolicy` module: they are
product choices, not rules. I keep them as optional callbacks of the game module, so
`Table.Server` has one module to ask, but a game may delegate them:
`defdelegate pace(state), to: Quacks.TablePolicy`. The engine stays free of UX code
either way. `pace/1` still reads rule state (the phase, the round), which is why the
callback takes the state.

### Pre-game picks

The patient picks (`lib/quacks/game_server.ex:238-253`, `pick_patient/3`) are per-seat
options chosen before the game, from a deal the seed decides. Generic form for #81:
an optional `seat_options(opts, seed) :: %{atom => [term]}`. The waiting room shows one
picker per key. The picks go into `opts`. It is not in the core contract above,
because no other planned game needs it yet.

## 9. Generic bots and `Table.Bots`

### One driver, not seven loops

"Ask the bot, apply its action, keep its rng" is written seven times (review §3.4):
the server's tick (`lib/quacks/game_server.ex:1122`), plan (`:1266`), step (`:1358`)
and brew (`:1413`), `Sim` (`lib/quacks/ai/sim.ex:89`), `Bench`
(`lib/quacks/ai/bench.ex:186`) and `Script` (`lib/quacks/scenarios/script.ex:160`).
Each calls `Quacks.AI.decide/4` by name. The `Decider` behaviour has one adapter and
no caller uses it as a behaviour. `Script` even uses `:balanced` while the table uses
`:expert` (`lib/quacks/game_server.ex:99`).

`Table.Bots` is the one pure driver. The server keeps the timers and the queue; the
choice of who acts and what is a function a test can call.

```elixir
defmodule Table.Bots do
  @moduledoc "Pure bot driver: who acts, what, and the rng after. No processes."

  @type bot :: {decider :: module, profile :: term}
  @type bots :: %{Table.Game.seat() => bot}
  @type rngs :: %{Table.Game.seat() => :rand.state()}

  @doc "One decision for `seat`, applied. `:none` when the bot does not act now."
  @spec step(Table.Session.t(), Table.Game.seat(), bot, :rand.state()) ::
          {:ok, Table.Session.t(), Table.Game.action(), :rand.state()} | :none

  @doc "A bot's whole part of a simultaneous step, on a private copy (today's `plan/2`)."
  @spec plan(module, Table.Game.state(), Table.Game.seat(), bot, :rand.state()) ::
          {[Table.Game.action()], :rand.state()}

  @doc "Apply queued plans in seat order; stop a plan at its first illegal action (`flush/1`)."
  @spec flush(Table.Session.t(), %{Table.Game.seat() => [Table.Game.action()]}) :: Table.Session.t()

  @doc "Play every bot seat until `until` holds or nobody acts: Sim, Bench, Script, brews."
  @spec run(Table.Session.t(), bots, rngs, (Table.Session.t() -> boolean)) ::
          {Table.Session.t(), rngs}
end
```

- `step/4` holds the safety net "a non-legal answer plays the first legal action"
  (`lib/quacks/ai.ex:55`), for every decider.
- `run/4` takes the lockstep and brew rules from `pace/1` (section 8). So `brew_bots/2`
  and `step_bots/4` become calls to it.
- **The rng order must not change.** Bot rngs are saved in game files
  (`lib/quacks/game_server.ex:1683`, restored at `:371`). If the driver asks bots in a
  new order, a restored game plays on legally but differently. The PR checks that
  `Bench` gives the same numbers on a fixed seed before and after.

### The decider contract

```elixir
defmodule Table.AI.Decider do
  @callback decide(
              game :: module,
              Table.Game.state(),
              Table.Game.seat(),
              profile :: term,
              :rand.state()
            ) :: {Table.Game.action(), :rand.state()} | :none
end
```

- `Quacks.AI.decide/4` (`lib/quacks/ai.ex:37-54`) gets a `decide/5` that ignores the
  module. The safety net "an unknown action still plays a legal move" (`:55`) moves
  into the server, for every decider.
- `Table.Bots.RandomLegal` picks with `:rand.uniform_s/2` on the bot rng. It is the
  second `Decider` adapter, so the behaviour is a real seam. It is the opponent in
  every property test and the rollout policy of ISMCTS.
- `AI.new_rng/2` (`lib/quacks/ai.ex:32`) moves to `Table.AI`: a bot never touches the
  game rng, for every game.
- `Bench` and `Tune` take `game:` and `opts:`. Duplicate seating, the intervals and
  the win count are already generic. Game stats (the explosion rate) come from an
  optional `bench_stats/2` hook in the game's bot module.

## 10. The generic property suite

`use Table.GameCase, game: Quacks.Game, opts: opts_generator()` gives every game the
same properties. Quacks keeps its own on top (chips conserved,
`test/quacks/game_test.exs:673`).

1. **Never stalls.** On random play by random active seats, `{:playing, active}`
   has `active != []` and matches the seats with legal actions; the game reaches
   `{:over, _}` within a step cap.
2. **Legal means applies.** A sampled legal action gives `{:ok, _}`.
3. **Illegal changes nothing.** Another seat's action, or a random term, gives
   `{:error, _}`.
4. **Replay is exact.** Fold the actions twice: equal states. Bundle, JSON, back:
   equal state.
5. **`view/2` is safe.** For every seat, `view(determinize(s, seat, r), seat) ==
   view(s, seat)`: resampling the hidden part does not change what the seat sees.
   And `view(…, :spectator)` is unchanged for any seat's determinization.
6. **`determinize/3` is honest.** `determinize(s, seat, r) ==
   determinize(determinize(s, seat, r2), seat, r)`: the result depends only on what
   the seat sees, not on the real hidden cards.

7. **Bots see only what they may.** For `RandomLegal` and every game bot:
   `decide(s, seat, bot, r) == decide(determinize(s, seat, r2), seat, bot, r)`.

Properties 5 to 7 test hidden information without listing the hidden zones. A
game with no `determinize/3` skips them. Quacks hides almost nothing, so the toy
game `Table.Test.HighCard` (section 2) is what proves these properties catch a
leak: its suite includes a deliberately leaky `view/2` that must fail.

One more test is not a property. It walks every LiveView and gallery story after
mount and after a broadcast, and fails if any assign outside `Table.View.board` holds
the game's raw state (section 3).

## 11. Gallery

- A story renders a game's board from a `Table.View`. A fixture builds a state with
  the engine, as now (`lib/quacks_web/gallery/fixtures.ex:642-646`), then calls
  `view/2`.
- A hidden-info game gets one more arg: `audience` (seat 0..n-1 or spectator). One
  story then shows what each seat sees.
- Scenarios become v2 bundles. The path gains the game id:
  `/dev/scenarios/<game>/<kind>/<id>`.
- The shell (header, seats, log, game over) has its own stories under `TableWeb`
  (#82). A new game only adds its board stories.

## 12. Migration plan

Every step is one PR. Every step runs `mix precommit` and keeps all tests,
snapshots and the golden corpus green.

**Step 0, the golden corpus.** Before any change, record v1 bundles under
`test/fixtures/bundles/`: every scenario bundle (`Quacks.Scenarios.bundle/2`), 50
seeded bot games across expansions and house rules, and a few game files. Next to each,
record the final `log` and `score`. A test replays each and compares. Compare the log,
not the struct: #79 removes a field, and the struct changes shape on purpose.

| # | PR | Issue | Green because |
|---|---|---|---|
| 0 | Golden corpus of v1 bundles with final log and score | #80 (prep) | baseline |
| 1 | `Quacks.Game.State` (`@moduledoc false`) holds the writers: `update_player/3`, `record/2,3`, the supply helpers, `move_droplet/3`, `effect/4`; `Quacks.Game` keeps its reads (`player/2` stays public, review Q6) | #79 | pure move; same log |
| 2 | Drop the legacy `expansion` field; old bundles and game files map it to `expansions` | #79 | corpus loads v1 |
| 3 | `Table.Kit.Rng` (`stream/3` with Quacks's `@streams`, `shuffle/2` by sorted uniform keys as `Fortune.deck/4` does, `pick/2`); the deals move from `Rules.*` into the engine | #83 | golden test: same deck, witches, patients and chips per seed |
| 4 | `Table.Game`, `Table.Session` and `Table.GameCase` **with the toy `Table.Test.HighCard`** as the second adapter. `Quacks.Game` implements `info/0`, `new/2`, `status/1`, `view/2`, `determinize/3`; `Quacks.Session` becomes a facade over `Table.Session`. Reader takes v1 and v2; writer still writes v1 | #80 | corpus; `bundle_test.exs`; the suite runs for both games |
| 5 | Writer writes v2 (the release after 4) | #80 | rollback-safe |
| 6 | `Table.Bots` driver and `Table.Bots.RandomLegal`; `Decider` over a module; the server's four loops, `Sim`, `Bench`, `Script` call the driver | #81, #80, #88 | same `Bench` numbers on a fixed seed; server tests |
| 7 | `Table.View.build/4` at the page's one door; `{:game, id, version, state}`; the "no raw state in assigns" test | #80 | Quacks view is the same struct; same HTML, same snapshots |
| 8 | Server reads `pace/1` and `auto_action/2`; `drawing?/2` moves into the engine; `seat_options/2` for the patients | #81 | `game_server_test.exs`, `game_server_r10_test.exs` |
| 9 | Rename to `Table.Server` and `Table.Store`; the grep test for `lib/table` | #81 | no Quacks names left |
| 10 | `TableWeb.TableLive` shell and `QuacksWeb.Board`; shared components to `TableWeb.Components` | #82 | gallery at 360, 392, 1280; snapshots |
| 11 | `Table.Kit.Deck`, `PlayingCards` (`Bag`, `Dice`, `Zone` with their second user) | #83 | unit and property tests |
| 12 | `Table.AI.ISMCTS` | #88 | the suite plays HighCard with it |
| 13 | No Thanks! | #85 | its own rulebook tests and the suite |
| 14 | `Table.Pending` driver; Quacks's Witches gold choice on it | new issue | corpus logs equal |
| 15 | Evaluation, then Fortune, then Essence on `Table.Pending` (three PRs) | new issue | corpus logs equal |
| 16 | Sushi Go! on secret frames | #86 | its own tests and the suite |

Order notes:

- Steps 1 to 3 change no interface. They can merge in any order. The review's order
  holds: facade, then session, then behaviour (1, 2, 4).
- Step 7 needs 4. Step 8 needs 6 and 7.
- No Thanks! (13) needs 4, 6, 7, 9 and 11. It does not need `Table.Pending`.
- `Table.Pending` (14, 15) waits for the golden corpus and for a second user. The
  round order carries many fixes (`@rats_first`, the round-28 rat order), so it moves
  only with a corpus to catch a change (review §3.9, Q8). Sushi Go (16) is that user.

## 13. Worked example: No Thanks!

3 to 7 players. Cards 3 to 35; 9 are removed unseen. Each player starts with 11 chips
(9 with 6 players, 7 with 7). On your turn, take the card and the chips on it, or put
a chip on it ("No thanks!"). With no chips you must take. Whoever takes turns up the
next card and goes again. At the end a run of cards scores only its lowest card;
each chip is minus 1. Lowest total wins. The rules are a sketch here; #85 writes
`docs/games/no_thanks/rulebook.md` first.

```elixir
defmodule NoThanks.Game do
  @moduledoc "No Thanks! on `Table.Game`. A sketch for the RFC, not the final engine."
  use Table.Game
  alias Table.Kit.Rng

  @chips %{3 => 11, 4 => 11, 5 => 11, 6 => 9, 7 => 7}
  defstruct seats: [], turn: 0, card: nil, pot: 0, deck: [], removed: [],
            chips: %{}, cards: %{}, rng: nil, log: []

  @impl true
  def info, do: %{id: "no_thanks", name: "No Thanks!", players: 3..7, version: 1, hidden?: true}

  @impl true
  def new(%{players: n}, seed) when n in 3..7 do
    {cards, rng} = Rng.shuffle(Enum.to_list(3..35), :rand.seed_s(:exsss, seed))
    {removed, [card | deck]} = Enum.split(cards, 9)
    seats = Enum.to_list(0..(n - 1))

    {:ok,
     %__MODULE__{seats: seats, card: card, deck: deck, removed: removed, rng: rng,
                 chips: Map.new(seats, &{&1, @chips[n]}), cards: Map.new(seats, &{&1, []})}}
  end

  def new(_opts, _seed), do: {:error, :players}

  @impl true
  def legal_actions(%{card: nil}, _seat), do: []
  def legal_actions(%{turn: seat, chips: chips}, seat) when chips[seat] > 0, do: [:take, :pass]
  def legal_actions(%{turn: seat}, seat), do: [:take]
  def legal_actions(_g, _seat), do: []

  @impl true
  def apply(g, seat, action) do
    if action in legal_actions(g, seat),
      do: {:ok, step(%{g | log: [{seat, action, g.card} | g.log]}, seat, action)},
      else: {:error, {:illegal_action, action}}
  end

  defp step(g, seat, :pass),
    do: %{g | chips: Map.update!(g.chips, seat, &(&1 - 1)), pot: g.pot + 1,
              turn: rem(seat + 1, length(g.seats))}

  defp step(g, seat, :take) do
    g = %{g | cards: Map.update!(g.cards, seat, &[g.card | &1]),
              chips: Map.update!(g.chips, seat, &(&1 + g.pot)), pot: 0}

    case g.deck do
      [] -> %{g | card: nil}
      [next | rest] -> %{g | card: next, deck: rest}
    end
  end

  @impl true
  def status(%{card: nil} = g), do: {:over, Map.new(g.seats, &{&1, -points(g, &1)})}
  def status(g), do: {:playing, [g.turn]}

  # Hidden: the deck order and the 9 removed cards. Chip counts are hidden on the
  # table, but every pass is public, so a perfect memory knows them: the view shows them.
  @impl true
  def view(g, _audience),
    do: Map.take(g, [:seats, :turn, :card, :pot, :chips, :cards, :log])
        |> Map.put(:cards_left, length(g.deck))

  @impl true
  def determinize(g, _seat, rng) do
    {unseen, rng} = Rng.shuffle(g.deck ++ g.removed, rng)
    {removed, deck} = Enum.split(unseen, 9)
    {%{g | deck: deck, removed: removed}, rng}
  end

  defp points(g, seat) do
    cards = Enum.sort(g.cards[seat])
    Enum.sum(for c <- cards, c - 1 not in cards, do: c) - g.chips[seat]
  end
end
```

What the sketch shows (it is the third adapter, after Quacks and the toy HighCard):

- **Scores where lower wins** are negated, so "higher wins" holds for `Bench` and ISMCTS.
- **`view/2` hides two zones** and nothing else. Properties 5 and 6 (section 10) hold:
  `determinize/3` only shuffles cards nobody has seen, and the view shows neither.
- **The rng is only used in `new/2`.** `determinize/3` need not reseed it here. A game
  that draws later must reseed it, as the Quacks one does.
- **No `pace/1`**: the default `:turns` is right for a turn-based game.
- **The house rule "show chip counts"** (#85) changes nothing: the view shows them
  already. The rule that hides them would be a UI choice, because the log tells.

## 14. Open questions

- **Views and the log.** Quacks shows the whole log. A card game must show "Ann drew
  a card" to others and "you drew the 7♣" to Ann. That is in `view/2` (the game
  filters its own log), not in `Table`. Is a shared log entry shape worth a
  `Table.Kit` helper? Decide with Hearts.
- **Spectators of a hidden-info game** see the spectator view. A "watch over a
  seat's shoulder" mode would give a spectator a seat's view. Who may allow that?
  Leave for after Hearts.
- **`seat_options/2`** is in the server plan (#81), not the contract. Promote it if a
  second game needs pre-game picks.
- **Timeouts.** A table that waits for a human in a secret frame waits forever, as
  Quacks does now (2 hours idle). Turn timers are a server feature for later.
