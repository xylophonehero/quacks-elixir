defmodule Quacks.IngredientSetsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Quacks.GameHelpers

  alias Quacks.Game
  alias Quacks.Game.Potions
  alias Quacks.Rules.{Chips, PotTrack}

  @seed {1, 2, 3}

  defp new(sets), do: Game.new(seed: @seed, fortune: false, sets: sets)

  defp effect?(g, book, detail), do: {0, {:effect, book, detail}} in g.log

  # The space of the newest chip.
  defp at(g), do: me(g).pot_index

  describe "sets option" do
    test "defaults to Set 1 for every colour" do
      assert Game.new(seed: @seed).sets == %{green: 1, blue: 1, red: 1, yellow: 1, purple: 1}
      assert new(%{blue: 3}).sets.blue == 3
    end

    test "unsupported or unknown sets raise" do
      for set <- [green: 2, green: 4, purple: 2, purple: 4, red: 2] do
        assert_raise ArgumentError, ~r/#{Regex.escape(inspect(set))}/, fn ->
          new(Map.new([set]))
        end
      end

      assert_raise ArgumentError, fn -> new(%{yellow: 5}) end
      assert_raise ArgumentError, fn -> new(%{orange: 2}) end
    end
  end

  describe "prices" do
    test "one spot check per colour per set" do
      checks = [
        {{:green, 4}, [14, 18, 18, 14]},
        {{:blue, 4}, [19, 19, 14, 20]},
        {{:red, 2}, [10, 8, 9, 11]},
        {{:yellow, 1}, [8, 9, 8, 8]},
        {{:purple, 1}, [9, 12, 10, 11]}
      ]

      for {{colour, _} = chip, prices} <- checks, {price, set} <- Enum.with_index(prices, 1) do
        assert Chips.price(chip, %{colour => set}) == price
      end

      assert Chips.price({:orange, 1}, %{green: 4}) == 3
      assert Chips.price({:black, 1}, %{}) == 10
      assert Chips.price({:red, 4}) == Chips.price({:red, 4}, %{red: 1})
    end

    test "the shop charges the game's set prices" do
      g = put(new(%{red: 3}), phase: :buy_chips, coins: 5)
      assert {:buy, [{:red, 1}]} in Game.legal_actions(g)
      refute {:buy, [{:red, 1}]} in Game.legal_actions(put(new(%{}), phase: :buy_chips, coins: 5))
      assert me(apply!(g, {:buy, [{:red, 1}]})).coins == 0
    end
  end

  describe "green" do
    # Whites 2+2+3 = 7, greens 1+2 = 3; the last chip is on space 10.
    @pot [
      {{:green, 2}, 10},
      {{:white, 3}, 9},
      {{:white, 2}, 7},
      {{:white, 2}, 5},
      {{:green, 1}, 3}
    ]

    test "G3: exactly 7 white moves the last chip by the green values before scoring" do
      g = new(%{green: 3}) |> put(drawn: @pot, pot_index: 10) |> apply!(:stop)
      assert hd(me(g).drawn) == {{:green, 2}, 13}
      assert at(g) == 13
      assert me(g).coins == PotTrack.at(14).coins
      assert effect?(g, {:green, 3}, {:moved_last, 3})
      refute Enum.any?(g.log, &match?({0, {:green_rubies, _}}, &1))
    end

    test "G3: not exactly 7 white does nothing" do
      pot = List.replace_at(@pot, 1, {{:white, 2}, 9})
      g = new(%{green: 3}) |> put(drawn: pot, pot_index: 10) |> apply!(:stop)
      assert at(g) == 10
    end
  end

  describe "blue" do
    test "B2: an explosion inside the window pays VP and coins, no die, no choice" do
      g = new(%{blue: 2}) |> put(drawn: [{{:white, 3}, 3}, {{:white, 3}, 0}], pot_index: 3)
      g = force_draws(g, [{:blue, 2}, {:white, 3}])
      assert effect?(g, {:blue, 2}, {:protect, 2})
      assert effect?(g, {:blue, 2}, :protected_explosion)
      p = me(g)
      assert p.exploded? and p.explosion_choice == nil
      # the evaluation already ran: scoring space 9
      space = PotTrack.at(9)
      assert p.vp == space.vp and p.coins == space.coins and p.rubies == 2
      refute Enum.any?(g.log, &match?({0, {:bonus_die, _}}, &1))
      assert g.phase == :buy_chips
    end

    test "B2: outside the window the explosion is normal; windows take the larger" do
      g = new(%{blue: 2}) |> put(drawn: [{{:white, 3}, 3}, {{:white, 3}, 0}], pot_index: 3)
      g = force_draws(g, [{:blue, 1}, {:white, 1}, {:white, 3}])
      assert Game.phase(g, 0) == :explosion_choice

      g = force_draws(new(%{blue: 2}), [{:blue, 4}, {:blue, 1}])
      assert me(g).mods.protect == 3
    end

    test "B3: landing on a ruby space gives a ruby" do
      g = new(%{blue: 3}) |> put(pot_index: 4) |> force_draws([{:blue, 1}])
      assert me(g).rubies == 2 and effect?(g, {:blue, 3}, :ruby)
      g = new(%{blue: 3}) |> put(pot_index: 3) |> force_draws([{:blue, 1}])
      assert me(g).rubies == 1
    end

    test "B4: landing on a ruby space gives VP by value" do
      g = new(%{blue: 4}) |> put(pot_index: 5) |> force_draws([{:blue, 4}])
      assert at(g) == 9 and me(g).vp == 4 and effect?(g, {:blue, 4}, {:vp, 4})
      g = new(%{blue: 4}) |> put(pot_index: 4) |> force_draws([{:blue, 4}])
      assert me(g).vp == 0
    end
  end

  describe "red" do
    test "R3: after a white chip red moves its value plus the white value" do
      g = force_draws(new(%{red: 3}), [{:white, 2}, {:red, 1}])
      assert at(g) == 5 and effect?(g, {:red, 3}, {:extra, 2})
      g = force_draws(new(%{red: 3}), [{:orange, 1}, {:red, 1}])
      assert at(g) == 2
    end

    test "R4: once a red is in the pot, white 1-chips move 2" do
      g = force_draws(new(%{red: 4}), [{:white, 1}, {:red, 1}, {:white, 1}, {:white, 2}])
      assert Enum.map(me(g).drawn, &elem(&1, 1)) == [6, 4, 2, 1]
      assert effect?(g, {:red, 4}, :white_plus1)
      assert Game.white_sum(g) == 4
    end
  end

  describe "yellow" do
    test "Y2: the next chip moves double, a yellow next chip doubles itself and re-arms" do
      g = force_draws(new(%{yellow: 2}), [{:yellow, 1}, {:green, 2}, {:green, 1}])
      assert Enum.map(me(g).drawn, &elem(&1, 1)) == [6, 5, 1]
      assert effect?(g, {:yellow, 2}, {:doubled, 4})

      g = force_draws(new(%{yellow: 2}), [{:yellow, 1}, {:yellow, 2}, {:white, 1}])
      assert Enum.map(me(g).drawn, &elem(&1, 1)) == [7, 5, 1]
      assert Game.white_sum(g) == 1
    end

    test "Y3: the white limit is 8 after the 1st yellow and 9 after the 3rd" do
      whites = [{:white, 3}, {:white, 3}, {:white, 2}]
      g = force_draws(new(%{yellow: 3}), [{:yellow, 1} | whites])
      assert Game.phase(g, 0) == :potions and effect?(g, {:yellow, 3}, {:limit, 8})
      assert Game.phase(force_draws(new(%{}), whites), 0) == :explosion_choice

      g =
        force_draws(new(%{yellow: 3}), [
          {:yellow, 1},
          {:yellow, 1},
          {:yellow, 1},
          {:white, 1} | whites
        ])

      assert Game.phase(g, 0) == :potions and Potions.explode_above(g, 0) == 9
      assert Game.phase(force_draws(g, [{:white, 1}]), 0) == :explosion_choice
    end

    test "Y3 and the B5 card: the higher limit counts" do
      g = new(%{yellow: 3}) |> put(fortune_card: :b5) |> force_draws([{:yellow, 1}])
      assert Potions.explode_above(g, 0) == 9
    end

    test "Y4: the 1st, 2nd and 3rd yellow move +1, +2, +3; the 4th nothing" do
      g = force_draws(new(%{yellow: 4}), List.duplicate({:yellow, 1}, 4))
      assert Enum.map(me(g).drawn, &elem(&1, 1)) == [10, 9, 5, 2]
      assert effect?(g, {:yellow, 4}, {:extra, 3})
    end
  end

  describe "purple" do
    test "P3: VP per purple by its pot field band" do
      pot = [{{:purple, 1}, 35}, {{:purple, 1}, 25}, {{:purple, 1}, 12}, {{:purple, 1}, 5}]

      g =
        new(%{purple: 3})
        |> put(phase: :explosion_choice, exploded?: true, drawn: pot, pot_index: 0)
        |> apply!({:explosion_choice, :buy})

      assert me(g).vp == 6 and effect?(g, {:purple, 3}, {:vp, 6})
    end
  end

  property "random play with random supported sets keeps the invariants" do
    check all(
            seed <- tuple({positive_integer(), positive_integer(), positive_integer()}),
            players <- integer(1..2),
            green <- member_of([1, 3]),
            blue <- integer(1..4),
            red <- member_of([1, 3, 4]),
            yellow <- integer(1..4),
            purple <- member_of([1, 3]),
            picks <- list_of(non_negative_integer(), min_length: 20, max_length: 200)
          ) do
      sets = %{green: green, blue: blue, red: red, yellow: yellow, purple: purple}

      Enum.reduce_while(picks, Game.new(seed: seed, players: players, sets: sets), fn pick, g ->
        active = Enum.filter(g.seats, &(Game.legal_actions(g, &1) != []))

        if Game.over?(g) do
          {:halt, g}
        else
          assert active != []
          seat = Enum.at(active, rem(pick, length(active)))
          actions = Game.legal_actions(g, seat)
          next = apply!(g, seat, Enum.at(actions, rem(div(pick, 7), length(actions))))
          assert inventory(next) == inventory(g)
          assert Enum.all?(g.seats, &(me(next, &1).droplet >= me(g, &1).droplet))
          assert Enum.all?(g.seats, &(me(next, &1).pot_index <= 53)) and next.round in 1..9

          for s <- next.seats do
            assert me(next, s).exploded? ==
                     Game.white_sum(next, s) > Potions.explode_above(next, s)
          end

          {:cont, next}
        end
      end)
    end
  end
end
