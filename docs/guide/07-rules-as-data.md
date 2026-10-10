# 7. Rules as data

[Back to the guide](../GUIDE.md)

`AGENTS.md` says: "Rules data (chip prices, pot track, ingredient books) lives in plain
data modules, not in logic." The `Quacks.Rules.*` modules hold numbers and texts.
The `Quacks.Game.*` modules hold the logic that reads them.

| Module | Holds | Read by |
|---|---|---|
| `Quacks.Rules.PotTrack` | 54 spaces: coins, VP, ruby | scoring, ruby checks, the pot SVG |
| `Quacks.Rules.ScoringTrack` | where the rat tails are | `place_rats/1` |
| `Quacks.Rules.Chips` | prices per set, the supply, the starting bag, the board order | the shop, `Game.new/1`, every chip list in the UI |
| `Quacks.Rules.Books` | the book texts, triggers, tiers | the UI only |
| `Quacks.Rules.Fortune` | 24 card names and texts | `Game.Fortune`, the UI |
| `Quacks.Rules.Witches` | 12 witch cards, the deal | `Game.Witches`, the UI |
| `Quacks.Rules.TestTubes` | the 12 glass bonuses | reverse pot side |
| `Quacks.Rules.Alchemists` | 8 patients, their essence slots, the deal | `Game.Essence`, the UI |

## Why data modules

- **The rules research changes the numbers.** The rat tails were wrong at first and
  were corrected from a board photo in one commit (`cfaea11`, "fix(rules): rat tails
  after VP 1, 4, 7, 10 and every even VP 12–48"). In `lib/` that commit changed only
  `scoring_track.ex` (the `@tails` line and its moduledoc), plus tests and research
  notes. No logic changed. The books audit changed 17 book texts the same way.
- **Each number has a source.** The moduledocs name the research doc and flag unsure
  values with ⚠️, for example `Quacks.Rules.PotTrack`: "Numbers copied verbatim from
  `docs/research/rulebook.md` §1.1. ⚠️ That table is a fan transcription"
  (`lib/quacks/rules/pot_track.ex:5-6`).
- **Nick can correct them without reading logic.** `Quacks.Rules.Alchemists` says
  "Nick: correct `@slots` from the real essence cards in the box"
  (`lib/quacks/rules/alchemists.ex:8`).
- **The UI and the engine share one source.** `Books.get/1` gives the shop its prices
  from `Chips.price/2`, so the label cannot disagree with what the engine charges.

## Module attributes

A module attribute (`@name value`) is a compile-time constant. The pot track is a
tuple of tuples (`lib/quacks/rules/pot_track.ex:12-68`, shortened):

```elixir
# {coins, vp, ruby?}
@track {
  {0, 0, false},
  {1, 0, false},
  ...
  {35, 15, false}
}
```

and one function reads it (`lib/quacks/rules/pot_track.ex:76-81`):

```elixir
@doc "Payout of the space at `idx`. Indices past the spoon clamp to the spoon."
@spec at(non_neg_integer) :: space
def at(idx) when is_integer(idx) and idx >= 0 do
  {coins, vp, ruby?} = elem(@track, min(idx, @last))
  %{coins: coins, vp: vp, ruby?: ruby?}
end
```

A tuple, not a list: `elem/2` reads index `n` in constant time; `Enum.at/2` on a list
walks `n` elements.

Attributes are private to the module. Other modules call a function:
`PotTrack.last/0`, `Chips.starting_bag/0`. Round 37: `PotTrack.last_chip/0` (52)
is the last space a chip covers and `PotTrack.chip_index/1` clamps a move to it;
`last/0` (53, the spoon) stays the last scoring space, what a chip on 52 pays. A function also lets the module change its
storage later without breaking callers.

### Code in an attribute runs at compile time

```elixir
# A tail after VP `t` sits between the spaces `t` and `t + 1`.
@tails [1, 4, 7, 10] ++ Enum.to_list(12..48//2)
```

(`lib/quacks/rules/scoring_track.ex:10-11`)

`Enum.to_list(12..48//2)` runs when the module compiles. The compiled module holds
the finished list. The same idea builds a lookup map once
(`lib/quacks/rules/witches.ex:98`):

```elixir
@by_id Map.new(@cards, &{&1.id, &1})
```

and a whole table with a comprehension (`lib/quacks/game/evaluation.ex:37-39`):

```elixir
@p4 for colour <- [:green, :blue, :red, :yellow],
        {from, to, tier} <- [{1, 2, 1}, {2, 4, 2}, {1, 4, 3}],
        do: {{colour, from}, {colour, to}, tier}
```

### Attributes versus runtime config

Do not read `Application.get_env/2` into an attribute: the value freezes at compile
time, and a release would ignore the runtime config. Credo checks this
(`Credo.Check.Warning.ApplicationConfigInModuleAttribute`, `.credo.exs:142`). The
GameServer reads the bot delay at runtime, inside the function
(`lib/quacks/game_server.ex:548`):

```elixir
delay = Application.get_env(:quacks, :bot_delay, 700)
```

## Prices per Ingredient Set

Each chip has a price list, one entry per set (`lib/quacks/rules/chips.ex:32-50`,
shortened):

```elixir
@prices %{
  {:orange, 1} => [3, 3, 3, 3, 3, 3],
  {:green, 1} => [4, 6, 6, 4, 5, 4],
  ...
  {:black, 1} => [10, 10, 9],
```

The key is the chip itself, a tuple. Any term can be a map key in Elixir: tuples,
lists, maps. `price/2` picks the entry for the colour's set
(`lib/quacks/rules/chips.ex:129-130`):

```elixir
def price({colour, _} = chip, sets),
  do: Enum.at(Map.fetch!(@prices, chip), Map.get(sets, colour, 1) - 1)
```

`Map.fetch!/2` raises on an unknown chip. That is right here: an unknown chip is a
bug, not a user error.

## One board order

The board lists the ingredients in one order: white, orange, blue, red, yellow,
green, black, purple, then locoweed. Before, each list in the UI had its own order
(the shop, the books, the bag, the chip offers). Now one attribute holds it
(`lib/quacks/rules/chips.ex:19-21`):

```elixir
@order [:white, :orange, :blue, :red, :yellow, :green, :black, :purple, :locoweed]
```

Two functions read it (`lib/quacks/rules/chips.ex:153-172`): `order/0` gives the
list, and `sort_key/1` gives a chip's place in it, then its value:

```elixir
def sort_key({colour, value}), do: {Enum.find_index(@order, &(&1 == colour)), value}
```

A tuple is a good sort key, because Erlang compares tuples element by element. So
`Enum.sort_by(chips, &Chips.sort_key/1)` sorts by colour first and by value second,
like `sort((a, b) => a.colourIndex - b.colourIndex || a.value - b.value)` in JS.

The readers: `Books.in_play/2` (`lib/quacks/rules/books.ex:261-274`), the shop rows
and the chip picks in `GameLive` (`lib/quacks_web/live/game_live.ex:2199-2208` and
`chip_order/1`, line 2416), the bag counts (`chip_counts/1`,
`lib/quacks_web/components/pot_components.ex`) and the spell book's
book tiles (`SetupComponents.book_colours/0`,
`lib/quacks_web/components/setup_components.ex:404`). To change the order, change one
line; the doctests show the new order.

## Books: text, trigger and tiers

`@books` maps `{colour, set}` to `{trigger, text}` (`lib/quacks/rules/books.ex:44`):

```elixir
{:green, 1} =>
  {:step_b, "1 ruby for each green chip that is your last or next-to-last chip."},
```

`@tiers` adds a table for books whose reward grows with the count
(`lib/quacks/rules/books.ex:156-205`). A row can be limited to a table size:

```elixir
{"same count", "droplet +1", players: 2},
```

`get/1` joins the text, the tiers and the prices into one map for the UI
(`lib/quacks/rules/books.ex:220-235`). Its doctest shows the shape
(`lib/quacks/rules/books.ex:211-218`).

Note the split: `Books` has the *words*. The *behaviour* of `{:green, 1}` is a
function clause in `Quacks.Game.Evaluation`
(`defp chip_action(g, seat, {:green, 1})`, `lib/quacks/game/evaluation.ex:214`). The
engine dispatches on the same `{colour, set}` key.

## The Alchemists and the test tubes

Two newer data modules show the same pattern with less familiar data.

**Patients.** `Quacks.Rules.Alchemists` holds, per patient, one list of glasses for
the flask spaces 1..10 (`lib/quacks/rules/alchemists.ex:66-88`, shortened):

```elixir
@slots %{
  nervousness: [[:rat] | for(n <- [1, 2, 3, 4, 5, 6, 7, 8, 10], do: [{:draw, n}])],
  carrot_nose: [[:rat], [], [:rat], [], [:rat], []] ++ @vp_tail,
  chicken_eyes: [
    [{:rubies, 1}],
    [{:chip, {:orange, 1}}],
    [{:swap, 1, 2}],
    ...
```

Each glass is a list of *terms* (`{:vp, n}`, `:rat`, `{:draw, n}`, ...), and
`@type term_` lists them all (`lib/quacks/rules/alchemists.ex:28-39`). The module
only describes a glass. `Quacks.Game.Essence` pays it, one function clause per term
(for example `defp pay_now(g, seat, {:droplet, n})`,
`lib/quacks/game/essence.ex:335`). `get/1` joins the slots with the card texts in
`@info` for the UI (`lib/quacks/rules/alchemists.ex:123-127`). The ⚠️ on the module
says the slot values come from small card pictures; a fix is one line of `@slots`.

**Test tubes.** `Quacks.Rules.TestTubes` is the whole reverse pot side track in one
tuple, glass 0 to 12 (`lib/quacks/rules/test_tubes.ex:12-14`):

```elixir
@glasses {nil, :ruby, {:vp, 1}, {:chip, {:blue, 1}}, {:vp, 2}, {:chip, {:black, 1}}, {:vp, 2},
          {:chip, {:red, 2}}, {:vp, 3}, {:chip, {:purple, 1}}, {:vp, 3}, {:chip, {:yellow, 4}},
          {:vp, 4}}
```

`bonus/1` is `elem(@glasses, glass)` and `last/0` is `tuple_size(@glasses) - 1`, so
the end of the track follows the data. The engine (`Game.move_droplet/3`,
chapter 2) and the pot component (`lib/quacks_web/components/pot_components.ex`)
both read `TestTubes.last()`, never a literal 12.

## House rules are data too

The engine keeps the allowed values of each house rule in a map
(`lib/quacks/game.ex:80-91`) and the defaults in another (`lib/quacks/game.ex:92-103`).
`rules!/1` merges the caller's rules over the defaults and checks every value
(`lib/quacks/game.ex:431-440`). It builds `Map.merge(@rules, rules)`, then checks
`Enum.all?(rules, fn {key, value} -> value in @rule_values[key] end)` and raises
`ArgumentError` on a bad value.

`value in 5..9` works for a range and `value in [true, false]` for a list: `in`
asks the `Enumerable` protocol. A new house rule is two map entries and the code
that reads `g.rules.new_rule`.

A rule can also change a book's *text*. `Books.get/2` takes the house rules and
swaps in the text of `@standings` for black book I when `black_rule: :standings`
(round 16). The components pass `@game.rules` down (`book_info/3`, `book_list`), so
the same data drives the menu's Books sheet and the books beside the pot.

## Shuffles with a jump

The deal functions in the data modules take the game's `rng` and shuffle with a
*jump* of it, so they do not use up the game's own stream (chapter 2). The patients
use three jumps, so they never match the fortune deck (one jump) or the witches (two)
(`lib/quacks/rules/alchemists.ex:162-172`). It gives each patient a random key with
`:rand.uniform_s/1`, sorts by the key and takes the first 3.

"Give each item a random key, sort by the key" is a shuffle that needs no mutable
array.
