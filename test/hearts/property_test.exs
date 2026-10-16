defmodule Hearts.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Hearts.Game
  alias Table.Kit.PlayingCards

  @max_steps 20_000

  defp options do
    fixed_map(%{
      players: member_of([3, 4, 5]),
      no_points_first_trick: boolean(),
      queen_breaks_hearts: boolean(),
      moon: member_of([:add_to_others, :subtract]),
      jack_of_diamonds: boolean(),
      target: member_of([50, 100]),
      ties: member_of([:share, :play_on])
    })
  end

  defp seed, do: tuple({integer(1..1_000_000), integer(1..1_000_000), integer(1..1_000_000)})

  # Random legal play to the end. `check` runs on every state before an action.
  defp play(game, rng, check, steps \\ 0)

  defp play(game, _rng, _check, steps) when steps > @max_steps, do: {game, steps}

  defp play(game, rng, check, steps) do
    case Game.status(game) do
      {:over, _} ->
        {game, steps}

      {:playing, seats} ->
        check.(game, rng)
        {seat, rng} = pick(seats, rng)
        {action, rng} = pick(Game.legal_actions(game, seat), rng)
        {:ok, game} = Game.apply(game, seat, action)
        play(game, rng, check, steps + 1)
    end
  end

  defp pick(list, rng) do
    {i, rng} = :rand.uniform_s(length(list), rng)
    {Enum.at(list, i - 1), rng}
  end

  defp run(opts, seed, check \\ fn _, _ -> :ok end) do
    {:ok, game} = Game.new(opts, seed)
    play(game, :rand.seed_s(:exsss, seed), check)
  end

  @tag rule: ["§3.7", "§5.1"]
  property "random legal play always ends, with the lowest totals as winners" do
    check all(opts <- options(), seed <- seed(), max_runs: 40) do
      {game, steps} = run(opts, seed)
      assert steps <= @max_steps
      assert {:over, scores} = Game.status(game)
      assert Enum.any?(scores, fn {_, s} -> s >= opts.target end)
      low = scores |> Map.values() |> Enum.min()
      assert game.winners == for({s, v} <- Enum.sort(scores), v == low, do: s)
      if opts.ties == :play_on, do: assert(length(game.winners) == 1)
    end
  end

  @tag rule: ["§3.2", "§3.6"]
  property "each trick has one card per seat; the winner played the highest card of the suit led" do
    check all(opts <- options(), seed <- seed(), max_runs: 30) do
      {game, _} = run(opts, seed)
      n = opts.players

      game.log
      |> Enum.reverse()
      |> Enum.reduce([], fn
        {:play, seat, card}, plays ->
          [{seat, card} | plays]

        {:trick_won, winner, cards, _points}, plays ->
          plays = Enum.reverse(plays)
          assert length(plays) == n
          assert plays |> Enum.map(&elem(&1, 0)) |> Enum.sort() == Enum.to_list(0..(n - 1))
          assert Enum.map(plays, &elem(&1, 1)) == cards
          assert {^winner, _} = PlayingCards.trick_winner(plays)
          []

        _, plays ->
          plays
      end)
    end
  end

  @tag rule: ["§4.1", "§4.2", "§4.3"]
  property "the points of a hand add up to 26, or the moon" do
    check all(opts <- options(), seed <- seed(), max_runs: 30) do
      {game, _} = run(opts, seed)
      jack = if opts.jack_of_diamonds, do: -10, else: 0
      others = opts.players - 1

      moon_total =
        if opts.moon == :add_to_others, do: 26 * others, else: -26

      for {:hand_scored, %{points: points, moon: moon}} <- game.log do
        expected = if moon, do: moon_total, else: 26
        assert Enum.sum(Map.values(points)) == expected + jack
      end
    end
  end

  @tag rule: "§1.2"
  property "a seed gives the same game" do
    check all(opts <- options(), seed <- seed(), max_runs: 10) do
      assert run(opts, seed) == run(opts, seed)
    end
  end

  @tag rule: ["§2.1", "§3.2"]
  property "an illegal action returns an error and changes nothing" do
    check all(opts <- options(), seed <- seed(), max_runs: 15) do
      run(opts, seed, fn game, rng ->
        {seat, rng} = pick(game.seats, rng)
        legal = Game.legal_actions(game, seat)
        {card, _} = pick(Game.deck(opts.players), rng)

        for action <- [{:play, card}, {:pass, [card]}, :draw], action not in legal do
          assert {:error, _} = Game.apply(game, seat, action)
        end

        assert {:error, _} = Game.apply(game, opts.players, hd(legal ++ [:draw]))
      end)
    end
  end

  @tag rule: "§2.1"
  property "view/2 never shows another seat's hand or secret pass" do
    check all(opts <- options(), seed <- seed(), max_runs: 15) do
      run(opts, seed, fn game, rng ->
        {viewer, _} = pick([:spectator | game.seats], rng)
        view = Game.view(game, viewer)
        secret = for {seat, hand} <- game.hands, seat != viewer, card <- hand, do: card
        other_passes = for {seat, cards} <- game.passes, seat != viewer, card <- cards, do: card

        shown = view |> Map.delete(:log) |> cards_in()
        assert MapSet.disjoint?(shown, MapSet.new(secret ++ other_passes))

        for event <- view.log do
          case event do
            {:deal, _, _, hands} ->
              assert Enum.all?(hands, fn {s, v} -> s == viewer or is_integer(v) end)

            {:pass, _, moves} ->
              assert Enum.all?(moves, fn {from, {to, v}} ->
                       viewer in [from, to] or is_integer(v)
                     end)

            _ ->
              :ok
          end
        end
      end)
    end
  end

  # every {rank, suit} card anywhere inside a term
  defp cards_in(term), do: term |> collect([]) |> MapSet.new()

  defp collect({rank, suit} = card, acc)
       when is_integer(rank) and suit in [:clubs, :diamonds, :spades, :hearts],
       do: [card | acc]

  defp collect(term, acc) when is_map(term), do: term |> Map.to_list() |> collect(acc)
  defp collect(term, acc) when is_list(term), do: Enum.reduce(term, acc, &collect/2)
  defp collect(term, acc) when is_tuple(term), do: term |> Tuple.to_list() |> collect(acc)
  defp collect(_term, acc), do: acc
end
