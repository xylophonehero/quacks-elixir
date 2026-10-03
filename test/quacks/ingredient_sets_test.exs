defmodule Quacks.IngredientSetsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Quacks.GameHelpers

  alias Quacks.Game
  alias Quacks.Game.Potions
  alias Quacks.Rules.{Chips, PotTrack}

  @seed {1, 2, 3}

  @limited %{supply: :limited}

  defp new(sets), do: Game.new(seed: @seed, fortune: false, sets: sets, rules: @limited)

  defp effect?(g, book, detail), do: {0, {:effect, book, detail}} in g.log

  # The space of the newest chip.
  defp at(g), do: me(g).pot_index

  describe "sets option" do
    test "defaults to Set 1 for every colour" do
      assert Game.new(seed: @seed).sets == %{
               green: 1,
               blue: 1,
               red: 1,
               yellow: 1,
               purple: 1,
               black: 1
             }

      assert new(%{blue: 3}).sets.blue == 3
    end

    test "every set 1..4 is supported; unknown sets raise" do
      for colour <- [:green, :blue, :red, :yellow, :purple], set <- 1..4 do
        assert new(%{colour => set}).sets[colour] == set
      end

      assert_raise ArgumentError, fn -> new(%{yellow: 7}) end
      assert_raise ArgumentError, fn -> new(%{orange: 3}) end
    end

    test "Session passes the sets on, through undo too" do
      s = Quacks.Session.new(@seed, 1, sets: %{green: 2}, fortune: false)
      {:ok, s} = Quacks.Session.apply(s, :draw)
      assert s.game.sets.green == 2 and Quacks.Session.undo(s).game.sets.green == 2
      assert Quacks.Session.replay(@seed, 1, [], sets: %{red: 2}).sets.red == 2
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
      g = put(new(%{red: 3}), phase: :buy, coins: 5)
      assert {:buy, [{:red, 1}]} in Game.legal_actions(g)
      refute {:buy, [{:red, 1}]} in Game.legal_actions(put(new(%{}), phase: :buy, coins: 5))
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

  # An exploded player who chose to buy: no bonus die, so step B is all that pays.
  defp evaluate(g, pot),
    do:
      g
      |> put(phase: :explosion_choice, exploded?: true, drawn: pot, pot_index: 10)
      |> apply!({:explosion_choice, :buy})

  defp chip_actions(g, seat \\ 0), do: Game.legal_actions(g, seat) -- [:chip_done]

  describe "green choices" do
    test "G2: each green on the last two chips may bring one chip into the bag" do
      g = evaluate(new(%{green: 2}), [{{:green, 2}, 10}, {{:green, 1}, 8}, {{:green, 4}, 7}])
      assert g.phase == :chip_choice and me(g).phase == :chip_choice

      # newest green first: the green 4 on space 7 is the third chip, so it does not count
      assert chip_actions(g) == [
               {:chip, {:gain, {:blue, 1}}},
               {:chip, {:gain, {:red, 1}}},
               {:chip, {:gain, {:orange, 1}}}
             ]

      g = apply!(g, {:chip, {:gain, {:red, 1}}})
      assert {:red, 1} in me(g).bag and effect?(g, {:green, 2}, {:gain, {:red, 1}})
      assert chip_actions(g) == [{:chip, {:gain, {:orange, 1}}}]

      # the last choice ends the turn; steps C/D ran and the shop is open
      g = apply!(g, {:chip, {:gain, {:orange, 1}}})
      assert Game.phase(g, 0) == :shop and me(g).chip_choices == []
      assert me(g).coins == PotTrack.at(11).coins
    end

    test "G2: :chip_done skips what is left" do
      g = evaluate(new(%{green: 2}), [{{:green, 4}, 10}])
      assert chip_actions(g) == [{:chip, {:gain, {:yellow, 1}}}, {:chip, {:gain, {:purple, 1}}}]
      bag = me(g).bag
      g = apply!(g, :chip_done)
      assert Game.phase(g, 0) == :shop and me(g).bag == bag
    end

    test "G4: pay up to 1 ruby per green on the last two chips, droplet +1 each" do
      pot = [{{:green, 1}, 10}, {{:green, 2}, 9}]
      g = new(%{green: 4}) |> put(rubies: 3) |> evaluate(pot)
      assert chip_actions(g) == [{:chip, {:pay_ruby_move, 1}}, {:chip, {:pay_ruby_move, 2}}]
      g = apply!(g, {:chip, {:pay_ruby_move, 2}})
      assert me(g).rubies == 1 and me(g).droplet == 2 and Game.phase(g, 0) == :shop
      assert effect?(g, {:green, 4}, {:droplet, 2})

      # one ruby: one move at most; no ruby: no choice at all
      g = new(%{green: 4}) |> put(rubies: 1) |> evaluate(pot)
      assert chip_actions(g) == [{:chip, {:pay_ruby_move, 1}}]
      assert new(%{green: 4}) |> put(rubies: 0) |> evaluate(pot) |> Game.phase(0) == :shop
    end

    test "every seat with a choice answers at the same time, in any order" do
      g = Game.new(seed: @seed, players: 2, fortune: false, sets: %{green: 2})
      g = put(g, 1, drawn: [{{:green, 1}, 3}], pot_index: 3) |> apply!(1, :stop)
      g = put(g, 0, drawn: [{{:green, 1}, 3}], pot_index: 3) |> apply!(0, :stop)
      assert g.phase == :chip_choice
      assert {:chip, {:gain, {:orange, 1}}} in Game.legal_actions(g, 0)
      assert {:chip, {:gain, {:orange, 1}}} in Game.legal_actions(g, 1)

      # seat 1 (not the start seat) answers first
      g = apply!(g, 1, {:chip, {:gain, {:orange, 1}}})
      assert g.phase == :chip_choice and Game.legal_actions(g, 1) == []
      g = apply!(g, 0, :chip_done)
      assert Game.phase(g, 0) == :shop
    end
  end

  describe "purple choices" do
    @purples [{{:purple, 1}, 10}, {{:purple, 1}, 8}, {{:purple, 1}, 6}, {{:purple, 1}, 3}]

    test "P2: trade purple chips for one tier; they go back to the supply" do
      g = evaluate(new(%{purple: 2}), @purples)

      assert chip_actions(g) ==
               [
                 {:chip, {:purple_trade, 1}},
                 {:chip, {:purple_trade, 2}},
                 {:chip, {:purple_trade, 3}}
               ]

      supply = g.supply
      g = apply!(g, {:chip, {:purple_trade, 2}})
      p = me(g)
      assert Enum.count(p.drawn) == 2 and g.supply[{:purple, 1}] == supply[{:purple, 1}] + 2
      assert {:green, 1} in p.bag and {:blue, 2} in p.bag
      assert p.vp == 3 and p.droplet == 1 and Game.phase(g, 0) == :shop
      assert effect?(g, {:purple, 2}, {:trade, 2})
    end

    test "P2: tiers 1 and 3 pay out" do
      g = evaluate(new(%{purple: 2}), Enum.take(@purples, 1))
      g = apply!(g, {:chip, {:purple_trade, 1}})
      assert {:black, 1} in me(g).bag and me(g).vp == 1 and me(g).rubies == 2

      g = evaluate(new(%{purple: 2}), @purples) |> apply!({:chip, {:purple_trade, 3}})
      p = me(g)
      assert {:yellow, 4} in p.bag and p.vp == 6 and p.rubies == 2 and p.droplet == 2
    end

    test "P4: swap a pot chip for a bigger one into the bag; lower tiers allowed" do
      pot = [{{:purple, 1}, 10}, {{:purple, 1}, 8}, {{:blue, 2}, 6}, {{:green, 1}, 3}]
      g = evaluate(new(%{purple: 4}), pot)

      # 2 purple: 2 → 4 or the lower 1 → 2; never 1 → 4
      assert chip_actions(g) == [
               {:chip, {:upgrade, {:green, 1}, {:green, 2}}},
               {:chip, {:upgrade, {:blue, 2}, {:blue, 4}}}
             ]

      g = apply!(g, {:chip, {:upgrade, {:blue, 2}, {:blue, 4}}})
      p = me(g)
      assert {:blue, 4} in p.bag and {:blue, 2} not in Game.pot_chips(g)
      assert effect?(g, {:purple, 4}, {:upgrade, {:blue, 2}, {:blue, 4}})
      assert Game.phase(g, 0) == :shop

      # 3+ purple: 1 → 4 too
      g = evaluate(new(%{purple: 4}), [{{:red, 1}, 11} | Enum.take(@purples, 3)])
      assert {:chip, {:upgrade, {:red, 1}, {:red, 4}}} in chip_actions(g)
    end
  end

  describe "red set 2" do
    test "a drawn red chip goes beside the pot, then is placed, kept or returned" do
      g = force_draws(new(%{red: 2}), [{:white, 1}, {:red, 2}, {:red, 1}])
      p = me(g)
      assert p.aside == [{:red, 1}, {:red, 2}] and Game.pot_chips(g) == [{:white, 1}]
      assert at(g) == 1 and effect?(g, {:red, 2}, {:aside, {:red, 2}})

      g = apply!(g, :stop)
      assert Game.phase(g, 0) == :red_choice

      assert Game.legal_actions(g) == [
               {:red, {:place, {:red, 1}}},
               {:red, {:keep, {:red, 1}}},
               {:red, {:return, {:red, 1}}},
               {:red, {:place, {:red, 2}}},
               {:red, {:keep, {:red, 2}}},
               {:red, {:return, {:red, 2}}}
             ]

      # placed: only its own value, after the last chip
      g = apply!(g, {:red, {:place, {:red, 2}}})
      assert hd(me(g).drawn) == {{:red, 2}, 3}
      assert g.phase == :potions

      g = apply!(g, {:red, {:return, {:red, 1}}})
      assert {:red, 1} in me(g).bag and Game.phase(g, 0) == :shop
    end

    test "a kept chip stays beside the pot into the next round" do
      g = force_draws(new(%{red: 2}), [{:white, 1}, {:red, 4}]) |> apply!(:stop)
      g = apply!(g, {:red, {:keep, {:red, 4}}})
      assert Game.phase(g, 0) == :shop
      g = run(g, [{:buy, []}, :end_round])
      assert g.round == 2 and me(g).aside == [{:red, 4}]
      refute {:red, 4} in me(g).bag

      g = g |> force_draws([{:white, 2}]) |> apply!(:stop)
      assert Game.legal_actions(g) |> Enum.member?({:red, {:place, {:red, 4}}})
      g = apply!(g, {:red, {:place, {:red, 4}}})
      assert hd(me(g).drawn) == {{:red, 4}, 6} and me(g).aside == []
    end

    test "after an explosion the choice comes after the explosion choice" do
      g = force_draws(new(%{red: 2}), [{:red, 1}, {:white, 3}, {:white, 3}, {:white, 2}])
      assert Game.phase(g, 0) == :explosion_choice
      g = apply!(g, {:explosion_choice, :buy})
      assert Game.phase(g, 0) == :red_choice
    end

    test "the evaluation waits until every player has decided" do
      g = Game.new(seed: @seed, players: 2, fortune: false, sets: %{red: 2})
      g = g |> force_draws(0, [{:white, 1}, {:red, 1}]) |> apply!(0, :stop)
      g = g |> force_draws(1, [{:white, 1}]) |> apply!(1, :stop)
      assert me(g, 1).done? and Game.phase(g, 0) == :red_choice
      assert g.phase == :potions

      g = apply!(g, 0, {:red, {:keep, {:red, 1}}})
      assert Game.phase(g, 0) == :shop
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
      assert Game.phase(g, 0) == :shop
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
    test "P3: VP per purple by the number printed on its space, not the track index" do
      # Track index 53/25/20/5 is printed 35/20/17/5: 3 + 2 + 1 + 0 VP.
      pot = [{{:purple, 1}, 53}, {{:purple, 1}, 25}, {{:purple, 1}, 20}, {{:purple, 1}, 5}]

      g =
        new(%{purple: 3})
        |> put(phase: :explosion_choice, exploded?: true, drawn: pot, pot_index: 0)
        |> apply!({:explosion_choice, :buy})

      assert me(g).vp == 6 and effect?(g, {:purple, 3}, {:vp, 6})
    end

    test "P3: a purple chip on track index 20 (printed 17) scores 1 VP" do
      g =
        new(%{purple: 3})
        |> put(
          phase: :explosion_choice,
          exploded?: true,
          drawn: [{{:purple, 1}, 20}],
          pot_index: 0
        )
        |> apply!({:explosion_choice, :buy})

      assert me(g).vp == 1 and effect?(g, {:purple, 3}, {:vp, 1})
    end
  end

  property "random play with random sets keeps the invariants" do
    check all(
            seed <- tuple({positive_integer(), positive_integer(), positive_integer()}),
            players <- integer(1..2),
            green <- integer(1..4),
            blue <- integer(1..4),
            red <- integer(1..4),
            yellow <- integer(1..4),
            purple <- integer(1..4),
            picks <- list_of(non_negative_integer(), min_length: 20, max_length: 200)
          ) do
      sets = %{green: green, blue: blue, red: red, yellow: yellow, purple: purple}

      Enum.reduce_while(
        picks,
        Game.new(seed: seed, players: players, sets: sets, rules: @limited),
        fn pick, g ->
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

            # B3 and B7 draws cannot explode the pot, even over the limit.
            for s <- next.seats do
              over? = Game.white_sum(next, s) > Potions.explode_above(next, s)
              assert me(next, s).exploded? == over? or next.fortune_card in [:b3, :b7]
              if me(next, s).exploded?, do: assert(over?)
            end

            {:cont, next}
          end
        end
      )
    end
  end
end
