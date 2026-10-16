defmodule Quacks.GameHelpers do
  @moduledoc """
  Test helpers for hand-building and driving `Quacks.Game` structs. Most tests play
  seat 0 of a solo game, so every helper defaults to seat 0.
  """

  alias Quacks.{AI, Game, GameServer, Player}

  @game_keys [:round, :supply, :fortune_card, :fortune_deck]
  @shopping [:upgrade, :shop, :ready]

  @doc "Apply an action for `seat` (default 0), asserting it is legal."
  def apply!(game, seat \\ 0, action) do
    {:ok, game} = Game.apply(game, seat, action)
    game
  end

  @doc "Apply a list of seat-0 actions in order."
  def run(game, actions), do: Enum.reduce(actions, game, &apply!(&2, &1))

  @doc "Draw exactly these chips, in order, by replacing the bag before each draw."
  def force_draws(game, seat \\ 0, chips),
    do: Enum.reduce(chips, game, &apply!(put(&2, seat, bag: [&1]), seat, :draw))

  @doc """
  Set fields on the game or on `seat`'s player. `phase: :over` sets the game phase.
  `phase: :shop | :ready` puts the game in `:shopping`; when it was not shopping yet,
  every seat gets that sub-phase. Shorthands: `phase: :buy` is `:shop`; `phase:
  :rubies` is `:shop` after the buy (`bought?: true`). Any other `phase:` is the
  player's own phase. `round:`, `supply:`, `fortune_card:` and `fortune_deck:` are
  game fields; the rest are player fields. Unknown keys raise.
  """
  def put(game, seat \\ 0, fields) do
    Enum.reduce(fields, game, fn
      {:phase, :over}, g ->
        %{g | phase: :over}

      {:phase, :buy}, g ->
        put(g, seat, phase: :shop)

      {:phase, :rubies}, %{phase: :shopping} = g ->
        put(g, seat, phase: :shop, bought?: true)

      {:phase, :rubies}, g ->
        g = put(g, seat, phase: :shop)
        %{g | players: Map.new(g.players, fn {s, p} -> {s, %{p | bought?: true}} end)}

      {:phase, sub}, %{phase: :shopping} = g when sub in @shopping ->
        put_in(g.players[seat].phase, sub)

      {:phase, sub}, g when sub in @shopping ->
        players = Map.new(g.players, fn {s, p} -> {s, %{p | phase: sub}} end)
        %{g | phase: :shopping, players: players}

      {:phase, phase}, g ->
        put_in(g.players[seat].phase, phase)

      {key, value}, g when key in @game_keys ->
        Map.replace!(g, key, value)

      {key, value}, g ->
        put_in(g.players[seat], Map.replace!(g.players[seat], key, value))
    end)
  end

  @doc "The player at `seat` (default 0)."
  def me(game, seat \\ 0), do: game.players[seat]

  @doc """
  Every chip in the game per kind: supply + all bags, pots, overflow bowls, offers
  (blue, cards, the silver witch S2), red chips beside pots and Nervousness displays.
  """
  def inventory(g) do
    chips =
      g.players
      |> Map.values()
      |> Enum.flat_map(
        &(&1.bag ++
            Player.pot_chips(&1) ++
            &1.bowl ++ &1.pending ++ &1.witch_offer ++ &1.aside ++ &1.display)
      )
      |> Enum.frequencies()

    Map.merge(g.supply, chips, fn _chip, a, b -> a + b end)
  end

  @doc """
  Change the game inside the running `Quacks.GameServer` `id` with `fun` and tell
  every page (the `{:game, id, game}` broadcast). For LiveView tests that need a
  hand-built state, e.g. round 9.
  """
  def replace_game(id, fun) do
    [{pid, _}] = Registry.lookup(Quacks.GameRegistry, id)
    state = :sys.replace_state(pid, fn st -> put_in(st.session.game, fun.(st.session.game)) end)
    game = state.session.game
    Phoenix.PubSub.broadcast(Quacks.PubSub, GameServer.topic(id), game_update(id, game))
    game
  end

  @doc """
  Make every absent seat of game `id` look away for longer than
  `GameServer.rejoin_after_ms/0`, and tell the pages (as the server's own tick does).
  """
  def age_away(id) do
    [{pid, _}] = Registry.lookup(Quacks.GameRegistry, id)
    ago = GameServer.rejoin_after_ms() + 1_000

    :sys.replace_state(pid, fn st ->
      %{st | away: Map.new(st.away, fn {seat, since} -> {seat, since - ago} end)}
    end)

    send(pid, :away_tick)
    _ = :sys.get_state(pid)
    :ok
  end

  @doc """
  For a test that stores games (not async: the directory is app config, read when a
  game starts): a new games directory under `tmp/` for this test. When the test
  ends, the games it started stop first (a stop writes a pending change), then the
  directory goes. Before, a game that ran on wrote its file after the directory was
  deleted, so the directory came back; a later run that drew the same
  `System.unique_integer/1` found that stale file and restored one game too many.
  Returns the directory.
  """
  def games_dir do
    dir = Path.join("tmp", "test-games-#{Base.url_encode64(:crypto.strong_rand_bytes(6))}")
    before = game_pids()
    Application.put_env(:quacks, :games_dir, dir)

    ExUnit.Callbacks.on_exit(fn ->
      for pid <- game_pids() -- before,
          do: DynamicSupervisor.terminate_child(Quacks.GameSupervisor, pid)

      Application.delete_env(:quacks, :games_dir)
      File.rm_rf!(dir)
    end)

    dir
  end

  defp game_pids,
    do: for({_, pid, _, _} <- DynamicSupervisor.which_children(Quacks.GameSupervisor), do: pid)

  # -- the running game, by outcome (architecture review G3, G6) ---------------------
  #
  # These helpers know the shape of the server's broadcast and how a page waits for
  # the next game. A refactor of `Quacks.GameServer` (#80, #81) changes them here, not
  # in every test.

  @doc "The message every page of game `id` hears when its game changes."
  def game_update(id, game), do: {:game, id, game}

  @doc """
  Assert that a game update of `id` arrives within `timeout:` ms (default 100) and
  return its game. `via:` a listener pid that forwards what it hears as
  `{:forwarded, pid, message}`.
  """
  def assert_game_update(id, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 100)

    case Keyword.fetch(opts, :via) do
      {:ok, via} ->
        receive do
          {:forwarded, ^via, {:game, ^id, game}} -> game
        after
          timeout -> ExUnit.Assertions.flunk("no game update of #{id} via #{inspect(via)}")
        end

      :error ->
        receive do
          {:game, ^id, game} -> game
        after
          timeout -> ExUnit.Assertions.flunk("no game update of #{id}")
        end
    end
  end

  @doc "Assert that no game update (of any game) arrives within `timeout:` ms (default 50)."
  def refute_game_update(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 50)

    receive do
      {:game, id, _game} -> ExUnit.Assertions.flunk("unexpected game update of #{id}")
      {:forwarded, _via, {:game, id, _}} -> ExUnit.Assertions.flunk("unexpected update of #{id}")
    after
      timeout -> :ok
    end
  end

  @doc "Send the page `pid` a game update of `id`, as the server's broadcast does."
  def send_game_update(pid, id, game), do: send(pid, game_update(id, game))

  @doc """
  Wait (at most `timeout` ms) until the game of `id` satisfies `pred`; return it. A
  helper process listens to the game's updates, so the caller's mailbox stays as
  it was.
  """
  def await_game(id, pred, timeout \\ 2_000) do
    Task.async(fn ->
      :ok = Phoenix.PubSub.subscribe(Quacks.PubSub, GameServer.topic(id))
      await_loop(id, pred)
    end)
    |> Task.await(timeout)
  end

  defp await_loop(id, pred) do
    {:ok, %{game: game}} = GameServer.get(id)

    if pred.(game) do
      game
    else
      receive do
        {:game, ^id, _game} -> await_loop(id, pred)
      end
    end
  end

  @doc """
  Play game `id` (bots in the other seats) until the game is over or `until` is true
  for it. The human at `seat` stops at once and otherwise plays like a cautious bot;
  the bots play through the server as they do for a page. Returns the game.
  """
  def play_human(id, seat, until \\ fn _game -> false end) do
    profile = AI.Profile.get(:cautious)

    Enum.reduce_while(1..5_000, AI.new_rng({0, 0, 0}, seat), fn _, rng ->
      game = await_game(id, &(Game.over?(&1) or until.(&1) or human_turn?(&1, seat)))

      cond do
        Game.over?(game) or until.(game) ->
          {:halt, game}

        :stop in Game.legal_actions(game, seat) ->
          {:ok, _} = GameServer.apply(id, seat, :stop)
          {:cont, rng}

        true ->
          {action, rng} = AI.decide(game, seat, profile, rng)
          {:ok, _} = GameServer.apply(id, seat, action)
          {:cont, rng}
      end
    end)
  end

  defp human_turn?(game, seat),
    do: Game.phase(game, seat) != :stopped and Game.legal_actions(game, seat) -- [:resume] != []

  @doc """
  Play `steps` random legal actions (a random seat with actions, then a random action
  of it) on the `:rand` state `rng`. Stops early when the game is over. Returns
  `{game, rng}`.
  """
  def random_play(game, steps, rng) do
    Enum.reduce_while(1..steps//1, {game, rng}, fn _, {g, rng} ->
      case Enum.filter(g.seats, &(Game.legal_actions(g, &1) != [])) do
        [] ->
          {:halt, {g, rng}}

        active ->
          {seat, rng} = pick(active, rng)
          {action, rng} = pick(Game.legal_actions(g, seat), rng)
          {:cont, {apply!(g, seat, action), rng}}
      end
    end)
  end

  defp pick(list, rng) do
    {i, rng} = :rand.uniform_s(length(list), rng)
    {Enum.at(list, i - 1), rng}
  end
end
