# 8. Tests

[Back to the guide](../GUIDE.md)

## ExUnit basics

`test/quacks/game_test.exs:1-11` opens with `use ExUnit.Case, async: true`,
`use ExUnitProperties`, `import Quacks.GameHelpers` and `doctest Game`.

- `use ExUnit.Case, async: true`: this file runs in parallel with other async files.
  The engine has no shared state, so every engine test can be async.
- `doctest Game` runs the `iex>` examples in `Game`'s docs as tests. The docs cannot
  go stale without a red test.
- `assert` takes any expression. On failure ExUnit prints both sides of `==` or the
  unmatched pattern. `assert {:error, {:illegal_action, :draw, :explosion_choice}} = Game.apply(boom, :draw)`
  (`test/quacks/game_test.exs:58`) is a *pattern* assert: it passes if the right
  side matches the left.

Run `mix test`, one file (`mix test test/quacks/game_test.exs`), one test by line
(`mix test test/quacks/game_test.exs:48`), the last failures (`--failed`) or a fixed
random order (`--seed 0`).

## Engine tests with `GameHelpers`

Most engine tests need a game in a precise state: "the pot has white 3, white 2 and
the next draw is white 3". Playing to that state with real draws would be slow and
fragile. `test/support/game_helpers.ex` builds it. (`elixirc_paths(:test)` adds
`test/support` to the compile path, `mix.exs:36`.)

`apply!/3` applies an action and asserts `{:ok, game}` (`test/support/game_helpers.ex:12-16`).

```elixir
@doc "Draw exactly these chips, in order, by replacing the bag before each draw."
def force_draws(game, seat \\ 0, chips),
  do: Enum.reduce(chips, game, &apply!(put(&2, seat, bag: [&1]), seat, :draw))
```

(`test/support/game_helpers.ex:21-23`)

`force_draws/3` sets the bag to one chip, then draws. So the "random" draw has one
choice. The draw still goes through `Game.apply/3`, with every rule.

`put/3` sets fields on the game or a player (`test/support/game_helpers.ex:33-64`).
It knows a few shortcuts, for example `phase: :rubies` puts the game in the shop
after the buy. Unknown keys raise (`Map.replace!/3`), so a typo in a test fails
loudly.

A typical test reads like the rule it checks (`test/quacks/game_test.exs:48-59`):

```elixir
test "explodes at white sum 8, not at 7" do
  safe = force_draws(new(), [{:white, 3}, {:white, 2}, {:white, 2}])
  assert Game.phase(safe, 0) == :potions
  refute me(safe).exploded?

  boom = force_draws(new(), [{:white, 3}, {:white, 2}, {:white, 3}])
  assert Game.phase(boom, 0) == :explosion_choice
  assert me(boom).exploded?
  assert length(me(boom).drawn) == 3
  assert Game.legal_actions(boom) == [{:explosion_choice, :vp}, {:explosion_choice, :buy}]
  assert {:error, {:illegal_action, :draw, :explosion_choice}} = Game.apply(boom, :draw)
end
```

No mocks. The engine is pure, so a test builds a struct, calls a function and
compares structs.

## Properties with StreamData

A *property* test generates many random inputs and checks a rule that must hold for
all of them. This is `fast-check` for Elixir. The main one plays random games
(`test/quacks/game_test.exs:656-690`, shortened):

```elixir
property "random legal play by random seats keeps the invariants and never stalls" do
  check all(
          seed <- tuple({positive_integer(), positive_integer(), positive_integer()}),
          players <- integer(1..4),
          rules <- rules(),
          picks <- list_of(non_negative_integer(), min_length: 20, max_length: 200)
        ) do
```

The body plays the game: each `pick` chooses a seat among those with legal actions,
then one of its legal actions, and applies it with `apply!/3`.

What it checks after every random move:

- **No stall**: some seat always has a legal action until the game is over. This is
  the invariant from `Quacks.Game`'s moduledoc (chapter 2).
- **The right seats act**: `expected_active/1` is a second, simpler model of "who may
  act now". The engine must agree with it.
- **No chip is created or lost**: `assert_chips_conserved/4` counts every chip in the
  supply, bags, pots and offers (`test/quacks/game_test.exs:723-733`).
- Droplets never move back; pots stay in 0..53; the round stays in 1..9.

`rules()` is a generator of random house rules (`test/quacks/game_test.exs:736-749`),
so every house rule combination gets played. When a property fails, StreamData
*shrinks* the input to a small failing case and prints it.

Two more properties do the same with the expansions
(`test/quacks/herb_witches_test.exs:381`) and with bots
(`test/quacks/ai_test.exs:181-195`).

The properties work because `legal_actions/2` is the single source of truth. The test
needs no knowledge of the rules to play a legal game.

## GameServer tests

`test/quacks/game_server_test.exs` starts real GameServers (the app's supervision
tree runs in tests) and calls the client API. Bots act at once because
`config/test.exs:25` sets `bot_delay: 0`.

`replace_game/2` reaches into a running server to set up a state
(`test/support/game_helpers.ex:92-98`):

It calls `:sys.replace_state/2` on the GameServer pid, then broadcasts the new game.
`:sys.replace_state/2` is an OTP debug function: it runs a function on a process's
state, inside that process. Use it in tests only.

## LiveView tests

`Phoenix.LiveViewTest` runs a LiveView in the test process, without a browser.

```elixir
# Every test browser gets its own player token, as the PlayerToken plug would.
setup %{conn: conn} do
  %{conn: init_test_session(conn, player_token: "solo-#{System.unique_integer()}")}
end

# A solo game in a GameServer, opened in the browser (which takes seat 0).
defp live_game(conn, seed) do
  {:ok, id} = GameServer.start(1, seed)
  live(conn, ~p"/g/#{id}")
end
```

(`test/quacks_web/live/game_live_test.exs:12-21`)

```elixir
test "Draw places a chip in the pot and Undo takes it back", %{conn: conn} do
  {:ok, view, _html} = mount(conn)

  view |> element("button", "Draw a chip") |> render_click()
  assert pot_chips(view) == 1
  assert has_element?(view, "li", ~r/Drew white \d → space \d/)
  refute has_element?(view, "li", "Draw a chip")

  view |> element("button", "Undo") |> render_click()
  assert pot_chips(view) == 0
end
```

(`test/quacks_web/live/game_live_test.exs:48-58`)

- `live/2` does both mounts (static and connected) and returns the view.
- `element(view, selector, text)` finds one element; `render_click/1` clicks it and
  runs the `phx-click` with its `phx-value-*`.
- `has_element?/3` checks for an element. The tests select by `id`, `data-role` and
  `data-slot` attributes (`[data-role=pot-chip]`), not by CSS classes, so a styling
  change does not break them.
- `render_click(view, "action", %{...})` sends an event directly, to test bad input
  (`test/quacks_web/live/game_live_test.exs:60-74`).

Multiplayer tests open two "browsers" with different tokens
(`test/quacks_web/live/multiplayer_live_test.exs:9`):

```elixir
defp browser(name), do: init_test_session(build_conn(), player_token: name)
```

Then a click in one view shows up in the other through the real GameServer and the
real PubSub: `# Alice's draw reached Bob's page through PubSub`
(`test/quacks_web/live/multiplayer_live_test.exs:58-62`).

## `mix precommit`

The alias in `mix.exs:88-94` runs, in order: `compile --warnings-as-errors`,
`deps.unlock --unused`, `format --check-formatted`, `credo --strict`,
`test --warnings-as-errors`.

`preferred_envs: [precommit: :test]` (`mix.exs:31`) runs it in the test env, so it
compiles once. `AGENTS.md` asks for it before every change is done, and CI runs it on
every push. Agents also run the suite with several `--seed` values, because the
property tests and LiveView tests use random game seeds.

## The simulator

`Quacks.AI.Sim` plays whole bot games on the pure engine, with no processes per game
(`lib/quacks/ai/sim.ex:1-5`):

```sh
mix quacks.sim --games 500 --profiles balanced,reckless,cautious,balanced --seed 1
```

`Sim.run/1` runs games in parallel with `Task.async_stream/3`
(`lib/quacks/ai/sim.ex:36-41`) and sums VP, win rate and explosion rate per profile.
Two uses:

- **Tuning bots**: change a profile, run 500 games, compare.
- **A stress test**: `Sim.play/3` raises `Quacks.AI.Stall` when nobody can act, and
  `MatchError` on an illegal action (`lib/quacks/ai/sim.ex:50-55`). Builders run a few
  hundred games after a rules change (the project note Log records "400 random full
  games ... all reach game over").
