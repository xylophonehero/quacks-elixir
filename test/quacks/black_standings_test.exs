defmodule Quacks.BlackStandingsTest do
  @moduledoc "House rule `black_rule: :standings` (round 16): black book I by rank."
  use ExUnit.Case, async: true

  import Quacks.GameHelpers

  alias Quacks.Game
  alias Quacks.Game.Evaluation

  @seed {1, 2, 3}

  defp new(players, rule \\ :standings),
    do:
      Game.new(
        seed: @seed,
        players: players,
        rules: %{fortune: false, black_rule: rule, rats: false}
      )

  # `vps` per seat (and optional rubies) as the standings before the evaluation.
  defp standing(g, vps, rubies \\ nil) do
    rubies = rubies || Enum.map(vps, fn _ -> 1 end)

    [vps, rubies]
    |> Enum.zip()
    |> Enum.with_index()
    |> Enum.reduce(g, fn {{vp, r}, seat}, g -> put(g, seat, vp: vp, rubies: r) end)
  end

  # Every seat exploded on index 0 with `blacks[seat]` black chips, all buying: step B
  # runs once the last seat chose (no die, no VP).
  defp evaluate(g, blacks) do
    g =
      blacks
      |> Enum.with_index()
      |> Enum.reduce(g, fn {n, seat}, g ->
        chips = List.duplicate({:black, 1}, n) ++ [{:white, 1}]
        drawn = chips |> Enum.reverse() |> Enum.with_index(1) |> Enum.reverse()
        put(g, seat, phase: :explosion_choice, exploded?: true, drawn: drawn, pot_index: 0)
      end)

    Enum.reduce(g.seats, g, &apply!(&2, &1, {:explosion_choice, :buy}))
  end

  defp black(g, seat) do
    Enum.find_value(g.log, fn
      {^seat, {:black, payoff}} -> payoff
      _ -> nil
    end)
  end

  test "the default is the rulebook's neighbours" do
    assert Game.default_rules().black_rule == :neighbours
    g = standing(new(4, :neighbours), [0, 10, 20, 30])
    assert Evaluation.targets(g, 0) == [3, 1]
  end

  describe "standings/1" do
    test "most VP first; a tie goes to fewer rubies, then to the lower seat" do
      g = standing(new(4), [5, 9, 5, 5], [2, 0, 1, 1])
      assert Evaluation.standings(g) == [1, 2, 3, 0]
    end
  end

  describe "targets/2 under :standings" do
    test "2 players: the other seat" do
      g = standing(new(2), [3, 8])
      assert Evaluation.targets(g, 0) == [1]
      assert Evaluation.targets(g, 1) == [0]
    end

    test "3 players: 1st → 2nd, 3rd; 2nd → 1st, 3rd; 3rd → 2nd" do
      # Ranks: seat 2 (12), seat 0 (8), seat 1 (3).
      g = standing(new(3), [8, 3, 12])
      assert Evaluation.targets(g, 2) == [0, 1]
      assert Evaluation.targets(g, 0) == [2, 1]
      assert Evaluation.targets(g, 1) == [0]
    end

    test "4 players: the 3rd compares with the two above, the last with the 3rd" do
      # Ranks: seat 3, 1, 0, 2.
      g = standing(new(4), [10, 20, 0, 30])
      assert Evaluation.targets(g, 3) == [1, 0]
      assert Evaluation.targets(g, 1) == [3, 0]
      assert Evaluation.targets(g, 0) == [3, 1]
      assert Evaluation.targets(g, 2) == [0]
    end

    test "5 players: the 4th compares with the 2nd and 3rd" do
      g = standing(new(5), [50, 40, 30, 20, 10])
      assert Evaluation.targets(g, 3) == [1, 2]
      assert Evaluation.targets(g, 4) == [3]
    end

    test "a tie on VP: fewer rubies ranks higher" do
      # Seats 0 and 1 tie on 10 VP; seat 1 has fewer rubies, so it leads.
      g = standing(new(3), [10, 10, 2], [3, 1, 0])
      assert Evaluation.standings(g) == [1, 0, 2]
      assert Evaluation.targets(g, 2) == [0]
    end

    test "solo: nobody" do
      assert Evaluation.targets(new(1), 0) == []
    end
  end

  describe "the payoff" do
    test "leader: more than both of ranks 2 and 3 → droplet and ruby" do
      # Ranks: seat 0, 1, 2, 3. Seat 3 sits next to seat 0, but does not count.
      g = new(4) |> standing([30, 20, 10, 0]) |> evaluate([2, 1, 1, 5])
      assert black(g, 0) == :droplet_ruby
    end

    test "middle: more than one of the two above → droplet" do
      g = new(4) |> standing([30, 20, 10, 0]) |> evaluate([1, 3, 2, 0])
      # Seat 2 (rank 3) compares with ranks 1 (1 black) and 2 (3 black).
      assert black(g, 2) == :droplet
    end

    test "last: more than the player directly above → droplet and ruby" do
      g = new(4) |> standing([30, 20, 10, 0]) |> evaluate([9, 9, 1, 2])
      assert black(g, 3) == :droplet_ruby
      assert me(g, 3).droplet == 1
    end

    test "last: the same count (1+) → droplet, as with one opponent" do
      g = new(3) |> standing([30, 20, 10]) |> evaluate([0, 2, 2])
      assert black(g, 2) == :droplet
    end

    test "the standings are read before the bonus die" do
      # Before: seat 0 (30), seat 1 (10, 0 rubies), seat 2 (10, 1 ruby). Seat 2 stops
      # on a higher space and alone rolls the die; a VP face would lift it over seat 1.
      # Seat 2 still compares with seat 1 only: 1 > 0 is droplet and ruby.
      g =
        Enum.find_value(1..200, fn i ->
          g =
            Game.new(
              seed: {i, i, i},
              players: 3,
              rules: %{fortune: false, black_rule: :standings, rats: false}
            )
            |> standing([30, 10, 10], [0, 0, 1])

          drawn = [{{:black, 1}, 6}, {{:white, 1}, 5}]

          g =
            g
            |> put(2, phase: :potions, drawn: drawn, pot_index: 6, bag: [{:white, 1}])
            |> apply!(2, :stop)
            |> evaluate_seats([0, 1], [5, 0])

          if {2, {:bonus_die, {:vp, 1}}} in g.log or {2, {:bonus_die, {:vp, 2}}} in g.log,
            do: g
        end)

      assert black(g, 2) == :droplet_ruby
    end
  end

  # As `evaluate/2` for some seats only.
  defp evaluate_seats(g, seats, blacks) do
    g =
      seats
      |> Enum.zip(blacks)
      |> Enum.reduce(g, fn {seat, n}, g ->
        chips = List.duplicate({:black, 1}, n) ++ [{:white, 1}]
        drawn = chips |> Enum.reverse() |> Enum.with_index(1) |> Enum.reverse()
        put(g, seat, phase: :explosion_choice, exploded?: true, drawn: drawn, pot_index: 0)
      end)

    Enum.reduce(seats, g, &apply!(&2, &1, {:explosion_choice, :buy}))
  end
end
