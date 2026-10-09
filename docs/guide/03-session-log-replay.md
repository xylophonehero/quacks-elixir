# 3. Sessions, log and replay

[Back to the guide](../GUIDE.md)

There are two lists of "what happened" in this codebase. They have different jobs.

| | `Session.actions` | `Game.log` |
|---|---|---|
| Holds | the input: `{seat, action}` pairs | the narration: actions *and* the events they caused |
| Used for | replay, undo and the bug report bundle | the UI: the log sheet, the update chips, labels, the bug report text |
| Lives in | `%Quacks.Session{}` | `%Quacks.Game{}` |
| Order | newest first | newest first |

## Session: seed + actions = the game

`Quacks.Session` is small: 169 lines (`lib/quacks/session.ex`), and half of them are
the bundle (below). Its moduledoc says it
all: "A game plus the `{seed, players, sets, rules, expansions, [{seat, action}]}`
that built it. Undo = replay minus the last action, whichever seat made it."

```elixir
def apply(%__MODULE__{} = s, seat, action) do
  with {:ok, game} <- Game.apply(s.game, seat, action),
       do: {:ok, %{s | game: game, actions: [{seat, action} | s.actions]}}
end
```

(`lib/quacks/session.ex:65-68`)

`with` runs the match on the left of `<-`. If it matches, the `do:` part runs. If not
(here: an `{:error, _}` tuple), `with` returns that value as it is. So an illegal
move returns the engine's error and the session does not change. Chapter 10 has more
on `with`.

Replay is a reduce over the actions, oldest first (`lib/quacks/session.ex:84-89`):

```elixir
def replay(seed, players, actions, opts \\ []) do
  Enum.reduce(Enum.reverse(actions), new_game(seed, players, opts), fn {seat, action}, game ->
    {:ok, game} = Game.apply(game, seat, action)
    game
  end)
end
```

Note `{:ok, game} = Game.apply(...)`. This is a *match*, not an assignment. If
`apply` returned `{:error, _}`, the match would fail and raise `MatchError`. That is
on purpose: a recorded action that is not legal on replay means a bug, and a crash
is the right answer.

Undo drops the newest action and replays the rest (`lib/quacks/session.ex:70-79`):

```elixir
def undo(%__MODULE__{actions: []} = s), do: s

def undo(%__MODULE__{actions: [_ | rest]} = s),
  do: %{
    s
    | actions: rest,
      game:
        replay(s.seed, s.players, rest, sets: s.sets, rules: s.rules, expansions: s.expansions)
  }
```

Two clauses: an empty list returns the session as it is; a non-empty list
pattern-matches the head away. No `if (actions.length === 0)`.

Undo replays the whole game. For a 9-round game that is a few hundred actions on
pure functions: fast enough, and much simpler than snapshots. The GameServer allows
undo only in solo games (`lib/quacks/game_server.ex:507-514`), because in a
multiplayer game it would take back another player's move.

This design came from the research before the first line of code:
`docs/research/state-machine-liveview.md` §3 compares snapshots, an action log and
full event sourcing, and picks "snapshot + action log". The current `%Game{}` is a
cache; `{seed, actions}` is the truth.

### Why this is safe only because of the RNG rule

Replay gives the same game only if every random pick comes from `game.rng`
(chapter 2). One `Enum.random/1` call in a chip effect would make undo show a
different pot. The property test and the replay tests catch that.

## Bundles: the session as JSON

A bug report must carry the game, so that a developer can load it again. The
session is already the whole truth: the seed, the options and the actions. So
`Session.bundle/1` writes those as plain, JSON-ready data
(`lib/quacks/session.ex:99-112`):

```elixir
%{
  version: 1,
  seed: Tuple.to_list(s.seed),
  players: s.players,
  opts: %{sets: ..., rules: ..., expansions: [...]},
  log: s.actions |> Enum.reverse() |> Enum.map(fn {seat, action} -> [seat, encode(action)] end)
}
```

JSON has no atoms and no tuples, so `encode/1` maps each Elixir shape to one JSON
shape (`lib/quacks/session.ex:141-152`): an atom is a string, a tuple is an array, a
list is `{"l": [...]}`, a map is `{"m": [[k, v], ...]}` and a string is
`{"s": "..."}`. `{:buy, [{:green, 2}]}` becomes `["buy", {"l": [["green", 2]]}]`.
Each clause is one shape, the same as a `switch (typeof x)` in a JS serializer, but
with guards in the function heads.

`Session.from_bundle/2` reads it back (`lib/quacks/session.ex:120-139`):

```elixir
def from_bundle(bundle, at \\ nil) do
  %{"version" => 1, "seed" => [_, _, _] = seed, "players" => players, "opts" => opts} =
    b = bundle |> Jason.encode!() |> Jason.decode!()

  log = if at, do: Enum.take(b["log"], at), else: b["log"]
  ...
  game = replay(s.seed, players, actions, game_opts)
  {:ok, %{s | actions: actions, game: game}}
rescue
  _error in [MatchError, ArgumentError, FunctionClauseError, CaseClauseError, KeyError] ->
    {:error, :invalid}
end
```

- **One key style.** `Jason.encode!() |> Jason.decode!()` turns atom keys into
  string keys. So the function takes a fresh bundle (atom keys) and one decoded from
  an issue (string keys) the same way.
- **`at` is time travel.** `Enum.take(log, at)` keeps only the first `at` actions,
  and `replay/4` builds the game at that point. The debug scrubber (chapter 5) uses
  it to step through a game action by action.
- **No new atoms.** `decode/1` uses `String.to_existing_atom/1`. A string that is not
  a known atom raises `ArgumentError`; it does not make a new atom (chapter 5 tells
  why that matters). The bundle comes from an issue body, so it is untrusted input.
- **One `rescue` for every bad shape.** A wrong version, a missing key, an unknown
  atom and an illegal action (the `{:ok, game} =` match in `replay/4`) all raise.
  The `rescue` turns them into `{:error, :invalid}`. Here a crash is wrong, because
  bad input is a normal outcome, so the function gives back an error tuple.

In Redux terms: `bundle/1` is the "export" of Redux DevTools (the actions and the
initial state), and `from_bundle/2` with `at` is the "import" plus the slider.
Chapter 4 shows where the bundles go: into a GitHub issue, and back into a table.

## The game log: narration for the UI

`Game.apply/3` logs the action first, then `step/3` logs the events
(`lib/quacks/game.ex:611-612`). One `:draw` can produce several entries. A draw
that explodes the pot logs (the values are an example):

```
{0, {:exploded, 9}}               <- newest, from explode/2
{0, {:drew, {:white, 3}, 12}}     <- from put_on_pot/4
{0, :draw}                        <- from apply/3
```

Each entry for one player is `{seat, event}`. A few entries concern the whole table:
`{:round_end, round}`, `{:fortune_drawn, id}`, `{:expansion, x}`, `{:patients, ids}`
(`lib/quacks/game.ex:261-271`). `docs/CONTEXT.md` has the full table of entries.

The log is the record of *why* the struct looks the way it does. The struct says
"seat 0 has 3 rubies". The log says "+1 ruby from the green chip, +1 from the
scoring space". The UI needs both.

### Who reads the log

- **The log sheet.** `GameComponents.action_log/1` turns each entry into text with
  `label/1` (`lib/quacks_web/components/game_components.ex:2464-2479`, the lines
  come from `log_lines/3` at 2512-2518). It hides actions that an event already
  tells, so the log does not say things twice:

  ```elixir
  defp narrated_by_event?(:draw), do: true
  defp narrated_by_event?({:buy, [_ | _]}), do: true
  defp narrated_by_event?({:rubies, _}), do: true
  ```

  (three of the clauses, `lib/quacks_web/components/game_components.ex:2572-2593`)

  The same lines go into a bug report: `log_text/3` (line 2509) gives the newest
  lines as plain strings.

- **Labels.** `label/1` has one clause per entry shape
  (`lib/quacks_web/components/game_components.ex:2895-3044`), for example
  `def label({:drew, chip, index}), do: "Drew #{chip_name(chip)} → space #{index}"`
  (line 2930). The same function labels buttons, because an action is also a log
  entry. The last clause, `def label(other), do: inspect(other)` (line 3044), keeps
  an unknown entry visible instead of crashing.

- **Round results.** There is no results dialog any more (layout 1). The results
  are update chips on the name cards and lines in the player sheet. Both come from
  `QuacksWeb.Replay.beats/3`, which takes the entries since the last
  `{:round_end, _}` and keeps the ones that gave VP or rubies
  (`round_entries/2`, `lib/quacks_web/replay.ex:164-172`):

  ```elixir
  game.log
  |> Enum.take_while(&(not match?({:round_end, _}, &1)))
  |> Enum.reverse()
  ```

  `Replay.gain/1` (from `lib/quacks_web/replay.ex:230`) maps each entry to
  `{vp, rubies}`. `Replay.updates/2` (`lib/quacks_web/replay.ex:125-138`) sums the
  lines into the chips of one name card: "stopped" or "exploded", then "+7 VP",
  the rubies and the droplet moves. The round summary is a view of the log, not a
  second set of counters. Chapter 6 shows how the same lines also drive the
  animation on the cards, the books and the pot.

- **The essence preview.** `essence_parts/2` finds the newest `{:essence, reach,
  parts}` entry for this seat (`lib/quacks_web/live/game_live.ex:2681-2686`).

## Why "the log is the truth the UI reads"

The page could keep its own counters ("rubies gained this round"). It does not. Each
counter would need its own update code, in the right event handler, for every
book, card and witch. A new book would need UI changes in several places.

With the log, the engine logs one event where the rule runs, and every view that
reads the log gets it for free. When a new effect has no label yet, the page shows
`inspect(entry)`: ugly, but visible, and a test can find it.

The rule for engine code: **every change to a player's resources logs an event.**
Book effects use one helper for that, `Game.effect/4`, which logs
`{seat, {:effect, {colour, set}, detail}}` (`lib/quacks/game.ex:980-982`).

## What to try in IEx

```elixir
s = Quacks.Session.new({1, 2, 3})
{:ok, s} = Quacks.Session.apply(s, :draw)
{:ok, s} = Quacks.Session.apply(s, :draw)
s.game.log |> Enum.take(4)
Quacks.Session.undo(s).game.players[0].drawn
```

Run the same lines twice: you get the same chips. That is the RNG rule at work.

A bundle goes through JSON and back:

```elixir
json = s |> Quacks.Session.bundle() |> Jason.encode!()
{:ok, back} = Quacks.Session.from_bundle(Jason.decode!(json))
back.game == s.game
{:ok, first} = Quacks.Session.from_bundle(Jason.decode!(json), 1)
length(first.actions)
```
