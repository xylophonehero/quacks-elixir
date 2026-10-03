defmodule Quacks.HerbWitchesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Quacks.GameHelpers

  alias Quacks.{Game, Session}
  alias Quacks.Game.{Fortune, Potions}
  alias Quacks.Rules.Chips

  @seed {1, 2, 3}
  @hw :herb_witches
  @limited %{supply: :limited}

  defp new(sets \\ %{}, players \\ 1),
    do:
      Game.new(
        seed: @seed,
        fortune: false,
        expansion: @hw,
        sets: sets,
        players: players,
        rules: @limited
      )

  defp effect?(g, seat \\ 0, book, detail), do: {seat, {:effect, book, detail}} in g.log
  defp effects(g, seat, book), do: for({^seat, {:effect, ^book, d}} <- g.log, do: d)

  # A chip on the last space, ready for the next draw to overflow.
  defp on_spoon(g, seat \\ 0),
    do: put(g, seat, drawn: [{{:orange, 1}, 53}], pot_index: 53)

  describe "the expansion flag" do
    test "stored on the game, logged first; the base game is unchanged" do
      g = new()
      assert g.expansion == @hw
      assert List.last(g.log) == {:expansion, @hw}
      assert g.sets == %{green: 1, blue: 1, red: 1, yellow: 1, purple: 1, black: 1, locoweed: 5}

      base = Game.new(seed: @seed, fortune: false)
      assert base.expansion == nil
      refute Enum.any?(base.log, &match?({:expansion, _}, &1))
      assert_raise ArgumentError, fn -> Game.new(seed: @seed, expansion: :other) end
    end

    test "sets 5 and 6 and the black books in every game; every book is supported" do
      for colour <- [:blue, :red, :yellow, :green, :purple],
          set <- 1..4,
          do: assert(new(%{colour => set}).sets[colour] == set)

      for book <- [blue: 5, blue: 6, red: 5, yellow: 5, green: 6, purple: 6],
          do: assert(new(Map.new([book])).sets == Map.merge(new().sets, Map.new([book])))

      assert new(%{black: 5, locoweed: 6}).sets.black == 5
      assert Game.new(seed: @seed, sets: %{blue: 5}).sets.blue == 5
      assert Game.new(seed: @seed, sets: %{black: 6}).sets.black == 6
      assert_raise ArgumentError, fn -> new(%{black: 2}) end
      assert_raise ArgumentError, fn -> new(%{locoweed: 1}) end
      assert_raise ArgumentError, fn -> new(%{blue: 7}) end

      for {colour, set} <- [green: 5, red: 6, yellow: 6, purple: 5],
          do: assert(new(%{colour => set}).sets[colour] == set)
    end

    test "5 to 8 players with or without the expansion" do
      g = new(%{}, 5)
      assert g.seats == [0, 1, 2, 3, 4]
      assert Game.new(seed: @seed, players: 8).seats == Enum.to_list(0..7)
      assert_raise ArgumentError, fn -> new(%{}, 9) end
    end

    test "Session passes the expansion on, through undo too" do
      s = Session.new(@seed, 5, expansion: @hw, fortune: false, rules: @limited)
      {:ok, s} = Session.apply(s, 4, :draw)
      assert s.expansion == @hw and Session.undo(s).game.expansion == @hw
      assert Session.undo(s).game == new(%{}, 5)
    end
  end

  describe "chips, prices and supply" do
    test "the supply adds the expansion box, minus the starting bags" do
      g = new(%{}, 5)

      assert Chips.supply(@hw) |> Map.values() |> Enum.sum() ==
               (Chips.supply() |> Map.values() |> Enum.sum()) + 153

      assert g.supply[{:orange, 6}] == 20 and g.supply[{:locoweed, 1}] == 25
      assert g.supply[{:white, 1}] == 20 + 5 - 5 * 4
      refute Map.has_key?(Game.new(seed: @seed).supply, {:orange, 6})
    end

    test "orange 6 costs 22 and locoweed 8 or 10; both only in the expansion shop" do
      assert Chips.price({:orange, 6}, %{}) == 22
      assert Chips.price({:locoweed, 1}, %{locoweed: 5}) == 8
      assert Chips.price({:locoweed, 1}, %{locoweed: 6}) == 10
      assert Chips.price({:black, 1}, %{black: 6}) == 9
      assert Chips.price({:blue, 1}, %{blue: 5}) == 8
      assert Chips.price({:purple, 1}, %{purple: 6}) == 16

      assert {:orange, 6} in Chips.shop(@hw) and {:locoweed, 1} in Chips.shop(@hw)
      refute {:orange, 6} in Chips.shop() or {:locoweed, 1} in Chips.shop()

      g = put(new(), phase: :buy, coins: 22)
      assert {:buy, [{:orange, 6}]} in Game.legal_actions(g)
      assert {:buy, [{:locoweed, 1}]} in Game.legal_actions(g)
      g = apply!(g, {:buy, [{:orange, 6}]})
      assert {:orange, 6} in me(g).bag and g.supply[{:orange, 6}] == 19

      base = put(Game.new(seed: @seed, fortune: false), phase: :buy, coins: 35)
      refute Enum.any?(Game.legal_actions(base), &match?({:buy, [{:orange, 6} | _]}, &1))
    end

    test "an orange 6 moves 6 spaces" do
      assert me(force_draws(new(), [{:orange, 6}])).pot_index == 6
    end
  end

  describe "on-draw books" do
    test "R5: a red moves by the highest red value already in the pot" do
      g = force_draws(new(%{red: 5}), [{:red, 4}, {:red, 1}])
      assert me(g).pot_index == 8 and effect?(g, {:red, 5}, {:extra, 3})
      assert me(force_draws(new(%{red: 5}), [{:red, 1}, {:red, 4}])).pot_index == 5
    end

    test "Y5: the yellow moves on by the value of one more chip, which goes back" do
      g = new(%{yellow: 5}) |> put(bag: [{:yellow, 1}, {:yellow, 1}]) |> apply!(:draw)
      assert me(g).pot_index == 2 and me(g).bag == [{:yellow, 1}]
      assert [{{:yellow, 1}, 2}] = me(g).drawn
      assert effect?(g, {:yellow, 5}, {:peek, {:yellow, 1}})

      # an empty bag: nothing to peek at
      assert me(force_draws(new(%{yellow: 5}), [{:yellow, 2}])).pot_index == 2
    end

    test "B5: VP by the blue's value when the pot has that many orange chips" do
      g = force_draws(new(%{blue: 5}), [{:orange, 1}, {:orange, 6}, {:blue, 2}])
      assert me(g).vp == 2 and effect?(g, {:blue, 5}, {:vp, 2})
      assert me(force_draws(new(%{blue: 5}), [{:orange, 1}, {:blue, 2}])).vp == 0
    end

    test "B6: a ruby per white 1-chip among the `value` chips before the blue" do
      g = force_draws(new(%{blue: 6}), [{:white, 1}, {:white, 1}, {:white, 2}, {:blue, 2}])
      assert me(g).rubies == 2 and effect?(g, {:blue, 6}, {:rubies, 1})
      g = force_draws(new(%{blue: 6}), [{:white, 1}, {:white, 1}, {:blue, 2}])
      assert me(g).rubies == 3
    end

    test "L5: locoweed moves the rat stone distance + 1, at most 4; solo 1" do
      assert me(force_draws(new(), [{:locoweed, 1}])).pot_index == 1

      g = new(%{}, 2) |> put(1, rat_stone: 2, pot_index: 2) |> force_draws(1, [{:locoweed, 1}])
      assert me(g, 1).pot_index == 5 and effect?(g, 1, {:locoweed, 5}, {:moves, 3})

      g = new(%{}, 2) |> put(1, rat_stone: 6, pot_index: 6) |> force_draws(1, [{:locoweed, 1}])
      assert me(g, 1).pot_index == 10
    end

    test "L6: locoweed copies the last coloured chip's value and on-draw action" do
      g = force_draws(new(%{locoweed: 6}), [{:red, 4}, {:white, 1}, {:locoweed, 1}])
      assert [{{:locoweed, 1}, 9} | _] = me(g).drawn
      assert effect?(g, {:locoweed, 6}, {:copied, {:red, 4}})

      # the copied yellow (Set 1) action: the white just before goes back
      g = force_draws(new(%{locoweed: 6}), [{:yellow, 1}, {:white, 1}, {:locoweed, 1}])
      assert Game.phase(g, 0) == :yellow_choice
      g = apply!(g, :return_white)
      assert Game.white_sum(g) == 0

      # no coloured chip: value 1, no action; an earlier locoweed is skipped
      g = force_draws(new(%{locoweed: 6}), [{:white, 2}, {:locoweed, 1}, {:locoweed, 1}])
      assert me(g).pot_index == 4
      refute Enum.any?(g.log, &match?({0, {:effect, {:locoweed, 6}, _}}, &1))
    end
  end

  describe "step-B books" do
    test "G6: a bonus die roll per green on the last two chips" do
      g = new(%{green: 6}) |> force_draws([{:green, 1}, {:green, 2}]) |> apply!(:stop)
      assert length(effects(g, 0, {:green, 6})) == 2

      g =
        new(%{green: 6}) |> force_draws([{:green, 1}, {:white, 1}, {:white, 1}]) |> apply!(:stop)

      assert effects(g, 0, {:green, 6}) == []
    end

    test "P6: VP by the printed value of the chip after each purple" do
      chips = [{:purple, 1}, {:red, 4}, {:purple, 1}, {:green, 2}]
      g = new(%{purple: 6}) |> force_draws(chips) |> apply!(:stop)
      assert effect?(g, {:purple, 6}, {:vp, 6})

      chips = [{:purple, 1}, {:locoweed, 1}, {:purple, 1}]
      g = new(%{purple: 6}) |> force_draws(chips) |> apply!(:stop)
      assert effect?(g, {:purple, 6}, {:vp, 1})
    end

    test "Black 5, 2 players: a bought black goes to the left bag, droplet +1" do
      g = new(%{black: 5}, 2) |> put(0, phase: :buy, coins: 10)
      g = apply!(g, 0, {:buy, [{:black, 1}]})
      refute {:black, 1} in me(g, 0).bag
      assert Enum.count(me(g, 1).bag, &(&1 == {:black, 1})) == 1
      assert me(g, 0).droplet == 1 and effect?(g, {:black, 5}, {:to_left, 1})
    end

    test "Black 5 in a base game: a bought black goes to the left bag, droplet +1" do
      g =
        Game.new(seed: @seed, fortune: false, players: 2, sets: %{black: 5})
        |> put(0, phase: :buy, coins: 10)

      assert g.expansion == nil and g.witches == nil
      g = apply!(g, 0, {:buy, [{:black, 1}]})
      assert {:black, 1} in me(g, 1).bag and me(g, 0).droplet == 1
    end

    test "Black 5 solo: a bought black goes back to the supply, droplet +1" do
      g = new(%{black: 5}) |> put(phase: :buy, coins: 10)
      supply = g.supply[{:black, 1}]
      g = apply!(g, {:buy, [{:black, 1}]})
      refute {:black, 1} in me(g).bag
      assert g.supply[{:black, 1}] == supply and me(g).droplet == 1
      assert effect?(g, {:black, 5}, :to_supply)
    end

    test "Black 5: a black chip from a card (P1) goes to the left bag too" do
      g = new(%{black: 5}, 2) |> put(fortune_card: :p1) |> Fortune.resolve()
      assert g.phase == :fortune_choice and me(g, 0).phase == :fortune_choice
      g = apply!(g, 0, {:fortune, {:take, {:black, 1}}})
      assert {:black, 1} in me(g, 1).bag and me(g, 0).droplet == 1
      assert me(g, 0).pot_index == 1
    end

    test "Black 5: rubies for blacks in the left pot and my last two" do
      g =
        new(%{black: 5}, 2)
        |> force_draws(0, [{:black, 1}, {:white, 1}, {:black, 1}])
        |> force_draws(1, [{:black, 1}, {:black, 1}])
        |> apply!(0, :stop)
        |> apply!(1, :stop)

      assert effect?(g, 0, {:black, 5}, {:rubies, 3})
      assert effect?(g, 1, {:black, 5}, {:rubies, 4})

      solo = new(%{black: 5}) |> force_draws([{:black, 1}, {:white, 1}]) |> apply!(:stop)
      assert effect?(solo, {:black, 5}, {:rubies, 1})
    end

    test "Black 6, 2 players: furthest black moves the droplet, second gets a ruby" do
      stop_both = fn g -> g |> apply!(0, :stop) |> apply!(1, :stop) end

      g =
        new(%{black: 6}, 2)
        |> force_draws(0, [{:black, 1}])
        |> force_draws(1, [{:white, 3}, {:black, 1}])
        |> stop_both.()

      assert effect?(g, 1, {:black, 6}, :droplet) and effect?(g, 0, {:black, 6}, :ruby)

      tie =
        new(%{black: 6}, 2)
        |> force_draws(0, [{:black, 1}])
        |> force_draws(1, [{:black, 1}])
        |> stop_both.()

      assert effect?(tie, 0, {:black, 6}, :droplet) and effect?(tie, 1, {:black, 6}, :droplet)
    end

    test "Black 6 solo: 1 black → droplet, 2 → droplet and ruby" do
      g = new(%{black: 6}) |> force_draws([{:black, 1}]) |> apply!(:stop)
      assert effect?(g, {:black, 6}, :droplet)
      g = new(%{black: 6}) |> force_draws([{:black, 1}, {:black, 1}]) |> apply!(:stop)
      assert effect?(g, {:black, 6}, :droplet_ruby)
    end
  end

  describe "the overflow bowl" do
    test "chips after the last space go in the bowl, without actions" do
      g = new(%{blue: 5}) |> on_spoon() |> force_draws([{:orange, 1}, {:blue, 1}])
      assert me(g).bowl == [{:blue, 1}, {:orange, 1}] and me(g).pot_index == 53
      assert length(me(g).drawn) == 1 and me(g).vp == 0
      assert {0, {:overflow, {:blue, 1}}} in g.log
    end

    test "white chips in the bowl still explode the pot" do
      g = new() |> put(drawn: [{{:white, 3}, 52}, {{:white, 3}, 49}], pot_index: 52)
      g = force_draws(g, [{:orange, 1}, {:white, 1}])
      assert Game.phase(g, 0) == :potions and Game.white_sum(g) == 7
      g = force_draws(g, [{:white, 1}])
      assert Game.phase(g, 0) == :explosion_choice and Game.white_sum(g) == 8
    end

    test "the flask takes back a white chip from the bowl" do
      g = new() |> on_spoon() |> force_draws([{:white, 2}]) |> apply!(:use_flask)
      assert me(g).bowl == [] and {:white, 2} in me(g).bag and me(g).pot_index == 53
    end

    test "step D: spoon VP plus half the bowl's values, rounded down" do
      g = new() |> on_spoon() |> force_draws([{:orange, 1}, {:green, 2}]) |> apply!(:stop)
      assert {0, {:pot_vp, 15, 53}} in g.log
      assert {0, {:bowl, [{:green, 2}, {:orange, 1}], 1}} in g.log
      assert me(g).coins == 35

      g = new() |> on_spoon() |> force_draws([{:white, 1}]) |> apply!(:stop)
      assert {0, {:bowl, [{:white, 1}], 0}} in g.log

      # the bowl goes back in the bag at the end of the round
      g = g |> apply!({:buy, []}) |> apply!(:end_round)
      assert me(g).bowl == [] and {:white, 1} in me(g).bag
    end

    test "an exploded player who buys gets no bowl VP" do
      g = new() |> put(drawn: [{{:white, 3}, 53}, {{:white, 3}, 49}], pot_index: 53)
      g = g |> force_draws([{:white, 2}]) |> apply!({:explosion_choice, :buy})
      refute Enum.any?(g.log, &match?({0, {:bowl, _, _}}, &1))
    end

    test "every non-exploded player on the spoon rolls the bonus die" do
      g =
        new(%{}, 3)
        |> on_spoon(0)
        |> on_spoon(1)
        |> put(2, drawn: [{{:orange, 1}, 51}], pot_index: 51)
        |> force_draws(0, [{:green, 1}])

      g = Enum.reduce([0, 1, 2], g, &apply!(&2, &1, :stop))
      rolled = for {seat, {:bonus_die, _}} <- g.log, do: seat
      assert Enum.sort(rolled) == [0, 1]
    end

    test "a blue (Set 1) on the last space loses its offer" do
      two_blues = [drawn: [{{:orange, 1}, 51}], pot_index: 51, bag: [{:blue, 2}, {:blue, 2}]]
      g = new() |> put(two_blues) |> apply!(:draw)
      assert me(g).pot_index == 53 and Game.phase(g, 0) == :potions and me(g).pending == []

      # without the overflow bowl it still offers
      base =
        Game.new(seed: @seed, fortune: false, rules: %{overflow: false})
        |> put(two_blues)
        |> apply!(:draw)

      assert Game.phase(base, 0) == :blue_choice
    end
  end

  test "a 5-player game runs to the end" do
    g = Game.new(seed: @seed, players: 5, expansion: @hw, sets: %{black: 6, locoweed: 6})

    g =
      Enum.reduce_while(1..5000, g, fn _, g ->
        if Game.over?(g) do
          {:halt, g}
        else
          # a stopped seat does not resume
          seat = Enum.find(g.seats, &(Game.legal_actions(g, &1) not in [[], [:resume]]))
          actions = Game.legal_actions(g, seat)
          # draw up to 6 chips, then stop; otherwise the last action (end/skip)
          action =
            cond do
              :draw in actions and length(me(g, seat).drawn) < 6 -> :draw
              :stop in actions -> :stop
              true -> List.last(actions)
            end

          {:cont, apply!(g, seat, action)}
        end
      end)

    assert Game.over?(g) and g.round == 9
    assert map_size(Game.score(g)) == 5
  end

  property "random play with the expansion on or off keeps the invariants" do
    check all(
            expansion <- member_of([nil, @hw]),
            seed <- tuple({positive_integer(), positive_integer(), positive_integer()}),
            players <- integer(1..if(expansion, do: 5, else: 4)),
            sets <- sets(expansion),
            picks <- list_of(non_negative_integer(), min_length: 20, max_length: 300)
          ) do
      g =
        Game.new(seed: seed, players: players, sets: sets, expansion: expansion, rules: @limited)

      Enum.reduce_while(picks, g, fn pick, g ->
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

          for s <- next.seats, me(next, s).exploded? do
            assert Game.white_sum(next, s) > Potions.explode_above(next, s)
          end

          {:cont, next}
        end
      end)
    end
  end

  # Sets 1–4 always; with the expansion every book.
  defp sets(nil) do
    fixed_map(Map.new([:green, :blue, :red, :yellow, :purple], &{&1, integer(1..4)}))
  end

  defp sets(@hw) do
    fixed_map(%{
      green: integer(1..6),
      blue: integer(1..6),
      red: integer(1..6),
      yellow: integer(1..6),
      purple: integer(1..6),
      black: member_of([1, 5, 6]),
      locoweed: member_of([5, 6, 8, 9, 10])
    })
  end
end
