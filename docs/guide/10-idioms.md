# 10. Elixir idioms you met

[Back to the guide](../GUIDE.md)

Each idiom with one real use from this repo.

## Pattern matching in function heads

Elixir picks the first clause whose pattern and guard match. This replaces most
`switch` and `if` chains.

```elixir
def die_rolls(%{fortune_card: :b4}), do: 2
def die_rolls(_g), do: 1
```

(`lib/quacks/game/fortune.ex:183-184`)

`%{fortune_card: :b4}` matches any map (or struct) with that key and value; other
keys do not matter. The second clause is the default. `_g` is a variable the code
does not use: the `_` prefix tells the compiler.

Patterns can reach deep into data:

```elixir
def last_white?(%Player{bowl: [chip | _]}), do: match?({:white, _}, chip)
def last_white?(%Player{drawn: drawn}), do: match?([{{:white, _}, _} | _], drawn)
```

(`lib/quacks/game/potions.ex:264-265`)

`[head | tail]` splits a list. `match?/2` returns `true` or `false` without binding.

The `^` pin uses an existing value inside a pattern, instead of binding a new one:

```elixir
defp count(drawn, colour), do: Enum.count(drawn, &match?({{^colour, _}, _}, &1))
```

(`lib/quacks/game/potions.ex:614`)

A struct pattern also checks the type: `%__MODULE__{} = game` in `apply/3`
(`lib/quacks/game.ex:600`) accepts only a `%Quacks.Game{}`. `__MODULE__` is the
current module's name.

## `=` is a match

`{:ok, game} = Game.apply(game, seat, action)` (`lib/quacks/session.ex:86`) asserts the
shape and binds `game`. If the right side is `{:error, _}`, it raises `MatchError`.
Use it where a mismatch is a bug. Use `case` or `with` where it is a normal outcome.

## `with`

`with` chains steps that each return `{:ok, _}` or something else. The first
mismatch leaves the chain.

`GameLive.handle_event("action", ...)` chains `decode/1` and `GameServer.apply/3`
this way and handles both error shapes in one `else`
(`lib/quacks_web/live/game_live.ex:136-145`, quoted in chapter 5).

The bot tick uses `with` for a chain where the first step is a boolean
(`lib/quacks/game_server.ex:527-536`): `with false <- capped?(...), {action, rng} <- AI.decide(...), ...`.
Any value can be a pattern, not only `{:ok, _}`.

## Pipelines

`|>` passes the left value as the *first* argument of the next call. So engine
functions take the game first and return the game.
`start_round/1` is `g |> Fortune.draw() |> place_rats() |> Essence.rats() |>
Fortune.resolve() |> Essence.display()` (`lib/quacks/game.ex:770-777`).

Read it top to bottom as the rulebook steps.

## Anonymous functions and `&`

`fn p -> %{p | rubies: p.rubies + 1} end` is a full anonymous function. `&` is the
short form: `&%{&1 | rubies: &1.rubies + 1}`, where `&1` is the first argument. You
see it everywhere with `update_player`:

```elixir
g = update_player(g, seat, &%{&1 | phase: :ready})
```

(`lib/quacks/game.ex:694`)

`&Potions.stop(&2, &1)` swaps the arguments for `Enum.reduce/3`, whose function gets
`(element, acc)` (`lib/quacks/game.ex:738`).

## `Map.update!` and friends

```elixir
def update_player(%__MODULE__{players: players} = g, seat, fun),
  do: %{g | players: Map.update!(players, seat, fun)}
```

(`lib/quacks/game.ex:910-911`)

The `!` means "raise if the key is missing". `Map.update!/3`, `Map.fetch!/2`,
`Map.replace!/3`: use them when a missing key is a bug. `Map.get/3` with a default is
for keys that may be missing on purpose: `Map.get(sets, colour, 1)`
(`lib/quacks/rules/chips.ex:130`).

`%{map | key: value}` also raises on an unknown key. So `%{p | rubie: 1}` (a typo)
fails at once instead of adding a new key.

## Keyword lists for options

`Game.new/1` reads `Keyword.fetch!(opts, :seed)` (required) and
`Keyword.get(opts, :players, 1)` (with a default) (`lib/quacks/game.ex:341-346`).

`Game.new(seed: {1, 2, 3}, players: 2)` is `Game.new([{:seed, {1, 2, 3}}, {:players, 2}])`:
a list of 2-tuples. It is the options-object of JS. `Keyword.take/2` passes a subset
on (`lib/quacks/session.ex:92`).

## Default arguments

`def legal_actions(game, seat \\ 0)` (`lib/quacks/game.ex:495`) defines both
`legal_actions/1` and `legal_actions/2`: the arity is part of a function's name.

## `MapSet`

A set: `expansions: MapSet.new()` (`lib/quacks/game.ex:117`), queried with
`MapSet.member?/2` (`lib/quacks/game.ex:407`). Locoweed IV counts distinct colours
with `MapSet.new/2`, `MapSet.put/2` and `MapSet.size/1` (`lib/quacks/game/potions.ex:596-600`).

## Guards

Guards are the `when` part of a clause. Only a fixed set of functions is allowed
there (no `Map.get/2`, no own functions), so a guard can never have side effects.

```elixir
def phase(%__MODULE__{phase: phase, players: players}, seat)
    when phase != :over and is_map_key(players, seat) do
```

(`lib/quacks/game.ex:456-457`)

`is_map_key/2` and `:erlang.map_get/2` (`lib/quacks/game_server.ex:522`) are the map
functions that guards allow.

## `for` comprehensions

`for` maps, filters and can reduce in one expression. Patterns in the generator
filter out what does not match:

```elixir
pot = for({{:white, v}, _index} <- drawn, reduce: 0, do: (acc -> acc + v))
```

(`lib/quacks/player.ex:185`)

Only white chips match `{{:white, v}, _index}`; the others are skipped. Filters and
`uniq: true` also work (`lib/quacks/game/potions.ex:509-512`).

## `case`, `cond`, `if`

- `case value do pattern -> ... end` for one value and many shapes
  (`lib/quacks/game.ex:458-462`).
- `cond do ... end` for unrelated conditions, the `else if` chain
  (`lib/quacks/game/potions.ex:307-321`). Elixir has no `else if`.
- `if` is an expression and returns a value: `if(herb?, do: :herb_witches)` returns
  `nil` when false (`lib/quacks/game.ex:382`).

## Overriding `Kernel`

`Kernel` is auto-imported and has its own `apply/2,3`. The engine opts out to define
its own: `import Kernel, except: [apply: 2, apply: 3]` (`lib/quacks/game.ex:65`).

## `@doc`, `@spec`, `@type`

- `@moduledoc` and `@doc` are real documentation: `h Quacks.Game.apply` in IEx, and
  `mix usage_rules.docs` for dependencies. `@doc false` hides a public helper that
  other engine modules need but callers should not use (`lib/quacks/game.ex:906`).
- `@spec` writes the type of a function:
  `@spec apply(t, seat, action) :: {:ok, t} | {:error, {:illegal_action, action, phase | Player.phase()}}`
  (`lib/quacks/game.ex:598-599`). Dialyzer (`mix dialyzer`) checks specs; the compiler
  does not. Think of it as TypeScript types that a separate tool checks.
- `@type` and `@typedoc` name types: `@type action` (`lib/quacks/game.ex:131`).

## Credo rules we hit

`mix credo --strict` runs in `mix precommit`. The ones this project met:

- **`Credo.Check.Warning.StructFieldAmount`** (`.credo.exs:153`): a struct may have
  at most 31 fields (the check's default). `%Quacks.Player{}` has exactly 31
  (`lib/quacks/player.ex:45-75`). When The Alchemists needed more player state, the
  builder put it in *one* field, `essence_pending`, with a tagged-tuple type
  (`lib/quacks/player.ex:155-161`), instead of three new fields. The Log notes this
  as a judgement call. The next feature that needs player state must either reuse
  such a field or split the struct, for example move the expansion fields into a
  nested map.
- **`Credo.Check.Warning.ApplicationConfigInModuleAttribute`** (`.credo.exs:142`):
  see chapter 7.
- **`Credo.Check.Readability.MaxLineLength`** at 120 (`.credo.exs:100`); `mix format`
  breaks lines at 98.

## `:rand.uniform_s` and the `_s` family

`{i, rng} = :rand.uniform_s(length(bag), g.rng)` (`lib/quacks/game/potions.ex:638`).

{i, rng} = :rand.uniform_s(length(bag), g.rng)
```

(`lib/quacks/game/potions.ex:638`)

`:rand` is an Erlang module (Erlang modules are atoms: `:rand`, `:math`, `:crypto`).
The `_s` versions take the state and return the new state: pure functions. Use them
in the engine. `:rand.uniform/1` without `_s` reads hidden per-process state: fine
for a new random seed in the GameServer (`lib/quacks/game_server.ex:682-683`), wrong
inside a rule. Chapter 2 explains why.

## Where to read more

`mix usage_rules.docs Enum.reduce` prints the docs for the installed version;
`mix usage_rules.search_docs "with"` searches all docs; in IEx, `h Map.update!`.
