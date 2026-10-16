defmodule CodenamesDuet.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias CodenamesDuet.{Clue, Game, Key, Words}
  alias Table.Kit.Rng

  @max_steps 500
  @words Words.all()

  defp seed, do: tuple({integer(1..1_000_000), integer(1..1_000_000), integer(1..1_000_000)})

  defp pick(list, rng) do
    {i, rng} = :rand.uniform_s(length(list), rng)
    {Enum.at(list, i - 1), rng}
  end

  # A random clue word that the engine accepts, and a number 0..9.
  defp clue(game, rng) do
    {word, rng} = pick(@words, rng)
    {n, rng} = :rand.uniform_s(10, rng)

    if Clue.check(word, n - 1, Game.visible_words(game)) == :ok,
      do: {{:clue, word, n - 1}, rng},
      else: clue(game, rng)
  end

  defp action(game, seat, rng) do
    case pick(Game.legal_actions(game, seat), rng) do
      {{:clue, :word, _}, rng} -> clue(game, rng)
      other -> other
    end
  end

  # Random legal play to the end. `check` runs on every state before an action.
  defp play(game, rng, check, steps \\ 0)

  defp play(game, _rng, _check, steps) when steps > @max_steps, do: {game, steps}

  defp play(game, rng, check, steps) do
    case Game.status(game) do
      {:over, _} ->
        check.(game, rng)
        {game, steps}

      {:playing, seats} ->
        check.(game, rng)
        {seat, rng} = pick(seats, rng)
        {action, rng} = action(game, seat, rng)
        {:ok, game} = Game.apply(game, seat, action)
        play(game, rng, check, steps + 1)
    end
  end

  defp run(opts, seed, check \\ fn _, _ -> :ok end) do
    {:ok, game} = Game.new(opts, seed)
    play(game, :rand.seed_s(:exsss, seed), check)
  end

  defp opts, do: fixed_map(%{timer: integer(1..11)})

  @tag rule: ["§5.1", "§6.1", "§6.2", "§6.3"]
  property "random legal play always ends, won or lost, with one token per turn" do
    check all(opts <- opts(), seed <- seed(), max_runs: 100) do
      {game, steps} = run(opts, seed)
      assert steps <= @max_steps
      assert {:over, %{result: result}} = Game.status(game)
      assert result in [:won, :lost]
      if result == :won, do: assert(Game.found(game) == 15)
      turn_ends = Enum.count(game.log, &match?({:turn_end, _, _, _}, &1))
      assert game.timer == opts.timer - turn_ends
      assert turn_ends <= opts.timer
      assert Enum.count(game.log, &match?({:clue, _, _, _}, &1)) in [turn_ends, turn_ends + 1]
    end
  end

  # The partner's side with its colours shuffled on the words that the table has
  # not shown for that side: no agent, no bystander mark from that side.
  defp scramble(game, side, rng) do
    open = Enum.filter(0..24, &Game.guessable?(game, &1, side))
    colors = Enum.map(open, &Enum.at(game.key[side], &1))
    {colors, _} = Rng.shuffle(colors, rng)
    moved = Map.new(Enum.zip(open, colors))

    side_key =
      game.key[side] |> Enum.with_index() |> Enum.map(fn {c, i} -> Map.get(moved, i, c) end)

    %{game | key: Map.put(game.key, side, side_key)}
  end

  @tag rule: ["§1.6"]
  property "a view never shows the other side of the key while the game is on" do
    check all(opts <- opts(), seed <- seed(), max_runs: 40) do
      run(opts, seed, fn game, rng ->
        unless Game.over?(game) do
          for seat <- [0, 1] do
            view = Game.view(game, seat)
            assert view.key == game.key[seat]
            assert view.revealed_key == nil
            other = scramble(game, Game.partner(seat), rng)
            assert Game.view(other, seat) == view
          end

          spectator = Game.view(game, :spectator)
          assert spectator.key == nil
          assert Game.view(scramble(scramble(game, 0, rng), 1, rng), :spectator) == spectator
        end
      end)
    end
  end

  @tag rule: ["§1.2", "§1.4"]
  property "a seed and the same actions give the same game" do
    check all(seed <- seed(), max_runs: 30) do
      {a, _} = run(%{}, seed)
      {b, _} = run(%{}, seed)
      assert a == b
    end
  end

  @tag rule: ["§1.3", "§1.4"]
  property "every key has the layout's pairs" do
    check all(seed <- seed(), max_runs: 100) do
      {:ok, game} = Game.new(%{}, seed)
      assert Enum.frequencies(Enum.zip(game.key[0], game.key[1])) == Map.new(Key.layout())
    end
  end

  @tag rule: ["§4.5", "§6.3"]
  property "an action that is not legal returns an error" do
    check all(seed <- seed(), max_runs: 30) do
      run(%{}, seed, fn game, _rng ->
        for seat <- [0, 1], i <- 0..24, {:guess, i} not in Game.legal_actions(game, seat) do
          assert {:error, _} = Game.apply(game, seat, {:guess, i})
        end
      end)
    end
  end
end
