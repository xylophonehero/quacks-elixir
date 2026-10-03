# 3. Sessions, log and replay

[Back to the guide](../GUIDE.md)

There are two lists of "what happened" in this codebase. They have different jobs.

| | `Session.actions` | `Game.log` |
|---|---|---|
| Holds | the input: `{seat, action}` pairs | the narration: actions *and* the events they caused |
| Used for | replay and undo | the UI: the log sheet, round results, labels, bot lockstep |
| Lives in | `%Quacks.Session{}` | `%Quacks.Game{}` |
| Order | newest first | newest first |

## Session: seed + actions = the game

`Quacks.Session` is small: 93 lines (`lib/quacks/session.ex`). Its moduledoc says it
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
undo only in solo games (`lib/quacks/game_server.ex:312-315`), because in a
multiplayer game it would take back another player's move.

This design came from the research before the first line of code:
`docs/research/state-machine-liveview.md` §3 compares snapshots, an action log and
full event sourcing, and picks "snapshot + action log". The current `%Game{}` is a
cache; `{seed, actions}` is the truth.

### Why this is safe only because of the RNG rule

Replay gives the same game only if every random pick comes from `game.rng`
(chapter 2). One `Enum.random/1` call in a chip effect would make undo show a
different pot. The property test and the replay tests catch that.

## The game log: narration for the UI

`Game.apply/3` logs the action first, then `step/3` logs the events
(`lib/quacks/game.ex:604-605`). One `:draw` can produce several entries. A draw
that explodes the pot logs (the values are an example):

```
{0, {:exploded, 9}}               <- newest, from explode/2
{0, {:drew, {:white, 3}, 12}}     <- from put_on_pot/4
{0, :draw}                        <- from apply/3
```

Each entry for one player is `{seat, event}`. A few entries concern the whole table:
`{:round_end, round}`, `{:fortune_drawn, id}`, `{:expansion, x}`, `{:patients, ids}`
(`lib/quacks/game.ex:266-272`). `docs/CONTEXT.md` has the full table of entries.

The log is the record of *why* the struct looks the way it does. The struct says
"seat 0 has 3 rubies". The log says "+1 ruby from the green chip, +1 from the
scoring space". The UI needs both.

### Who reads the log

- **The log sheet.** `GameComponents.action_log/1` turns each entry into text with
  `label/1` (`lib/quacks_web/components/game_components.ex:1402-1423`). It hides
  actions that an event already tells, so the log does not say things twice:

  ```elixir
  defp narrated_by_event?(:draw), do: true
  defp narrated_by_event?({:buy, [_ | _]}), do: true
  defp narrated_by_event?({:rubies, _}), do: true
  ```

  (`lib/quacks_web/components/game_components.ex:1434-1436`)

- **Labels.** `label/1` has one clause per entry shape
  (`lib/quacks_web/components/game_components.ex:1628-1769`), for example
  `def label({:drew, chip, index}), do: "Drew #{chip_name(chip)} → space #{index}"`
  (line 1655). The same function labels buttons, because an action is also a log
  entry. The last clause, `def label(other), do: inspect(other)` (line 1769), keeps
  an unknown entry visible instead of crashing.

- **Round results.** `round_gains/1` takes the entries since the last
  `{:round_end, _}` and keeps the ones that gave VP or rubies
  (`lib/quacks_web/components/game_components.ex:1558-1573`):

  ```elixir
  game.log
  |> Enum.take_while(&(not match?({:round_end, _}, &1)))
  |> Enum.reverse()
  ```

  `gain/1` (from line 1577) maps each entry to `{vp, rubies}`. The round summary is
  a view of the log, not a second set of counters.

- **The essence preview.** `essence_parts/2` finds the newest `{:essence, reach,
  parts}` entry for this seat (`lib/quacks_web/live/game_live.ex:1727`).

- **Bot lockstep.** `GameServer.round_draws/1` counts `{seat, :draw}` entries since
  the last round end, so a bot never draws more chips than the human who drew most
  (`lib/quacks/game_server.ex:580-587`).

## Why "the log is the truth the UI reads"

The page could keep its own counters ("rubies gained this round"). It does not. Each
counter would need its own update code, in the right event handler, for every
book, card and witch. A new book would need UI changes in several places.

With the log, the engine logs one event where the rule runs, and every view that
reads the log gets it for free. When a new effect has no label yet, the page shows
`inspect(entry)`: ugly, but visible, and a test can find it.

The rule for engine code: **every change to a player's resources logs an event.**
Book effects use one helper for that, `Game.effect/4`, which logs
`{seat, {:effect, {colour, set}, detail}}` (`lib/quacks/game.ex:973-975`).

## What to try in IEx

```elixir
s = Quacks.Session.new({1, 2, 3})
{:ok, s} = Quacks.Session.apply(s, :draw)
{:ok, s} = Quacks.Session.apply(s, :draw)
s.game.log |> Enum.take(4)
Quacks.Session.undo(s).game.players[0].drawn
```

Run the same lines twice: you get the same chips. That is the RNG rule at work.
