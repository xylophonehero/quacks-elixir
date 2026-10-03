defmodule Quacks.WitchesTest do
  @moduledoc "The Herb Witches, slice B: the 12 witches, the pennies and the choice books."
  use ExUnit.Case, async: true

  import Quacks.GameHelpers

  alias Quacks.Game
  alias Quacks.Rules.{Chips, PotTrack}
  alias Quacks.Rules.Witches, as: Cards

  @seed {1, 2, 3}
  @hw :herb_witches

  defp new(sets \\ %{}, players \\ 1),
    do: Game.new(seed: @seed, fortune: false, expansion: @hw, sets: sets, players: players)

  # The game with witch `id` turned up for her colour.
  defp with_witch(g, id), do: %{g | witches: Map.put(g.witches, Cards.card(id).colour, id)}

  # A solo game whose 3 witches are `ids` (one per colour).
  defp witches(ids, sets \\ %{}), do: Enum.reduce(ids, new(sets), &with_witch(&2, &1))

  defp witch_log?(g, seat \\ 0, id, outcome), do: {seat, {:witch, id, outcome}} in g.log

  describe "deal and pennies" do
    test "one witch per colour from the seed; 3 pennies each; none in the base game" do
      g = new(%{}, 3)
      assert Enum.sort(Map.keys(g.witches)) == [:copper, :gold, :silver]
      for {colour, id} <- g.witches, do: assert(id in Cards.ids(colour))
      assert new(%{}, 3).witches == g.witches

      assert Enum.all?(g.players, fn {_, p} ->
               p.pennies == %{silver: true, copper: true, gold: true}
             end)

      base = Game.new(seed: @seed, fortune: false)
      assert base.witches == nil and base.players[0].pennies == %{}
      assert Game.legal_actions(base) == [:draw]
    end

    test "the deal does not change the chips the seed draws" do
      base = Game.new(seed: @seed, fortune: false) |> apply!(:draw)
      hw = new() |> apply!(:draw)
      assert hd(me(base).drawn) == hd(me(hw).drawn)
    end

    test "every unused penny is 2 VP at the end; a spent one is not" do
      g = new() |> put(round: 9, phase: :rubies, rubies: 0)
      g = apply!(g, :end_round)
      assert me(g).vp == 6 and {0, {:pennies, 6}} in g.log

      g = new() |> put(round: 9, phase: :rubies, rubies: 0)
      g = put(g, pennies: %{silver: false, copper: true, gold: false}) |> apply!(:end_round)
      assert me(g).vp == 2

      base = Game.new(seed: @seed, fortune: false) |> put(round: 9, phase: :rubies)
      refute Enum.any?(apply!(base, :end_round).log, &match?({0, {:pennies, _}}, &1))
    end

    test "a witch is called once per game: the penny is spent" do
      g = witches([:s3]) |> force_draws([{:white, 1}])
      g = apply!(g, {:witch, :silver, 1})
      assert me(g).pennies.silver == false
      g = force_draws(g, [{:white, 1}])
      refute Enum.any?(Game.legal_actions(g), &match?({:witch, :silver, _}, &1))
    end
  end

  describe "silver witches" do
    test "S1: after an explosion, the full flask takes the white back; brew on" do
      g = witches([:s1]) |> force_draws([{:white, 3}, {:white, 3}, {:white, 2}])
      assert Game.phase(g, 0) == :explosion_choice
      assert {:witch, :silver} in Game.legal_actions(g)

      g = apply!(g, {:witch, :silver})
      assert Game.phase(g, 0) == :potions and not me(g).exploded? and not me(g).flask
      assert Game.white_sum(g) == 6 and {:white, 2} in me(g).bag
      assert witch_log?(g, :s1, :flask)

      # an empty flask: no S1
      g =
        witches([:s1])
        |> put(flask: false)
        |> force_draws([{:white, 3}, {:white, 3}, {:white, 2}])

      refute {:witch, :silver} in Game.legal_actions(g)
    end

    test "S2: 6 chips as an offer; place them one by one with actions, return the rest" do
      g = witches([:s2]) |> put(bag: [{:white, 1}, {:orange, 1}, {:green, 1}])
      assert {:witch, :silver} in Game.legal_actions(g)
      g = apply!(g, {:witch, :silver})
      assert Enum.sort(me(g).witch_offer) == [{:green, 1}, {:orange, 1}, {:white, 1}]
      assert me(g).bag == [] and witch_log?(g, :s2, {:offer, 3})

      assert Game.legal_actions(g) == [
               {:witch, :silver, {:place, {:green, 1}}},
               {:witch, :silver, {:place, {:orange, 1}}},
               {:witch, :silver, {:place, {:white, 1}}},
               {:witch, :silver, :return_all}
             ]

      g = apply!(g, {:witch, :silver, {:place, {:orange, 1}}})
      assert [{{:orange, 1}, 1}] = me(g).drawn
      g = apply!(g, {:witch, :silver, :return_all})
      assert me(g).witch_offer == [] and length(me(g).bag) == 2
      assert :stop in Game.legal_actions(g)
    end

    test "S2: an explosion ends the offer; the rest goes back in the bag" do
      g = witches([:s2]) |> force_draws([{:white, 3}, {:white, 3}])
      g = g |> put(bag: [{:white, 2}, {:green, 1}]) |> apply!({:witch, :silver})
      g = apply!(g, {:witch, :silver, {:place, {:white, 2}}})
      assert me(g).exploded? and me(g).witch_offer == [] and me(g).bag == [{:green, 1}]
    end

    test "S3: the last white chip, or the last 2, go back; the gaps stay" do
      g = witches([:s3]) |> force_draws([{:white, 1}, {:green, 1}, {:white, 2}, {:white, 3}])
      assert {:witch, :silver, 2} in Game.legal_actions(g)
      g = apply!(g, {:witch, :silver, 2})
      assert Game.white_sum(g) == 1 and me(g).pot_index == 2
      assert {:white, 3} in me(g).bag and {:white, 2} in me(g).bag
      assert witch_log?(g, :s3, {:return_white, 2})

      g =
        witches([:s3]) |> force_draws([{:white, 2}, {:green, 1}]) |> apply!({:witch, :silver, 1})

      assert [{{:green, 1}, 3}] = me(g).drawn
      assert me(g).pot_index == 3
    end

    test "S4: an exploded player keeps VP and coins, and rolls the die on the best space" do
      g = witches([:s4]) |> force_draws([{:white, 3}, {:white, 3}, {:white, 2}])
      assert {:witch, :silver} in Game.legal_actions(g)
      g = apply!(g, {:witch, :silver})
      assert me(g).explosion_choice == :witch and witch_log?(g, :s4, :no_penalty)
      # index 8 → scoring space 9: 9 coins, 1 VP (solo: always the best space)
      assert Game.phase(g, 0) == :buy and me(g).coins == 9
      assert {0, {:pot_vp, 1, 9}} in g.log
      assert Enum.any?(g.log, &match?({0, {:bonus_die, _}}, &1))
    end
  end

  describe "copper witches" do
    # A solo game in the shop, after an evaluation, with copper witch `id`.
    defp shop(id, fields) do
      witches([id]) |> put([phase: :buy] ++ fields)
    end

    test "C1: upgrade the last 2 chips, or 1 chip anywhere; the bigger chip goes in the bag" do
      g = shop(:c1, drawn: [{{:red, 1}, 5}, {{:green, 2}, 4}, {{:blue, 1}, 2}, {{:orange, 1}, 1}])
      actions = for {:witch, :copper, choice} <- Game.legal_actions(g), do: choice

      assert actions == [
               {:upgrade, [{:blue, 1}]},
               {:upgrade, [{:green, 2}]},
               {:upgrade, [{:red, 1}]},
               {:upgrade, [{:red, 1}, {:green, 2}]}
             ]

      g = apply!(g, {:witch, :copper, {:upgrade, [{:red, 1}, {:green, 2}]}})
      assert {:red, 2} in me(g).bag and {:green, 4} in me(g).bag
      assert Game.pot_chips(g) == [{:blue, 1}, {:orange, 1}]
      assert Game.phase(g, 0) == :buy
    end

    test "C2 doubles the coins; C4 adds 2 per ruby" do
      g = shop(:c2, coins: 7) |> apply!({:witch, :copper})
      assert me(g).coins == 14 and witch_log?(g, :c2, {:coins, 14})

      g = shop(:c4, coins: 7, rubies: 3) |> apply!({:witch, :copper})
      assert me(g).coins == 13 and me(g).rubies == 3 and witch_log?(g, :c4, {:coins, 6})
    end

    test "C3: buy and take an identical chip for free" do
      g = shop(:c3, coins: 7)

      assert {:witch, :copper, {:buy, [{:green, 1}, {:orange, 1}], {:green, 1}}} in Game.legal_actions(
               g
             )

      g = apply!(g, {:witch, :copper, {:buy, [{:green, 1}, {:orange, 1}], {:green, 1}}})
      # the starting bag has one green 1 already
      assert Enum.count(me(g).bag, &(&1 == {:green, 1})) == 3
      assert me(g).coins == 0 and Game.phase(g, 0) == :rubies
      assert witch_log?(g, :c3, {:copy, {:green, 1}})
    end

    test "an exploded player who took the VP still gets a shop turn for C1 or C4" do
      vp_shop = fn id ->
        witches([id])
        |> put(rubies: 2)
        |> force_draws([{:green, 1}, {:white, 3}, {:white, 3}, {:white, 2}])
        |> apply!({:explosion_choice, :vp})
      end

      g = vp_shop.(:c4)
      assert Game.phase(g, 0) == :buy and {:witch, :copper} in Game.legal_actions(g)
      g = apply!(g, {:witch, :copper})
      assert me(g).coins == 4

      assert Game.phase(vp_shop.(:c1), 0) == :buy
      assert Game.phase(vp_shop.(:c2), 0) == :rubies
    end

    test "round 9: C2 and C4 in the rubies turn, before the coins become VP" do
      g =
        witches([:c2]) |> put(round: 9, phase: :rubies, coins: 10, pennies: %{copper: true})

      g = g |> apply!({:witch, :copper}) |> apply!(:end_round)
      assert {0, {:final_conversion, 4, 0}} in g.log
    end
  end

  describe "gold witches" do
    # Stop after `chips` with gold witch `id`; the game waits in `:witch_choice`.
    defp gold(id, chips, fields \\ []),
      do: witches([id]) |> put(fields) |> force_draws(chips) |> apply!(:stop)

    test "G1: VP by the colours in the pot; the turn opens after step B" do
      g = gold(:g1, [{:orange, 1}, {:green, 1}, {:white, 1}, {:blue, 1}])
      assert g.phase == :witch_choice and g.turn == 0
      assert Game.legal_actions(g) == [{:witch, :gold}, :witch_done]
      vp = me(g).vp
      g = apply!(g, {:witch, :gold})
      assert me(g).vp >= vp + 3 and witch_log?(g, :g1, {:vp, 3})
      assert Game.phase(g, 0) == :buy
    end

    test "G1: the chart up to 8 colours; :witch_done keeps the penny" do
      chips =
        for c <- [:orange, :green, :blue, :red, :yellow, :purple, :black, :locoweed], do: {c, 1}

      g = gold(:g1, chips) |> apply!({:witch, :gold})
      assert witch_log?(g, :g1, {:vp, 14})

      g = gold(:g1, [{:orange, 1}]) |> apply!(:witch_done)
      assert me(g).pennies.gold and Game.phase(g, 0) == :buy
    end

    test "G2: 2 VP per coloured 2/4/6-chip, purple and locoweed chip in the bag" do
      bag = [
        {:white, 2},
        {:black, 1},
        {:green, 1},
        {:green, 2},
        {:orange, 6},
        {:purple, 1},
        {:locoweed, 1}
      ]

      g = witches([:g2]) |> force_draws([{:orange, 1}]) |> put(bag: bag) |> apply!(:stop)
      g = apply!(g, {:witch, :gold})
      assert witch_log?(g, :g2, {:vp, 8})
    end

    test "G3: on a ruby space, as many rubies as its VP (with the space's own ruby)" do
      # a ruby space worth 2+ VP (with 1 VP the witch adds nothing)
      index =
        Enum.find(
          20..52,
          &(PotTrack.at(&1).ruby? and PotTrack.at(&1).vp >= 2)
        )

      space = PotTrack.at(index)

      g =
        witches([:g3])
        |> put(drawn: [{{:orange, 1}, index - 1}], pot_index: index - 1, bag: [{:green, 1}])

      g = apply!(g, :stop)
      rubies = me(g).rubies
      g = apply!(g, {:witch, :gold})
      assert witch_log?(g, :g3, {:rubies, space.vp - 1})
      assert me(g).rubies == rubies + space.vp
    end

    test "nobody helped: no witch turn" do
      g = gold(:g3, [{:orange, 1}])
      assert Game.phase(g, 0) == :buy
    end

    test "G4: the droplet and the flask cost 1 ruby for the rest of the turn" do
      g = witches([:g4]) |> put(phase: :rubies, rubies: 2, flask: false)
      g = apply!(g, {:witch, :gold})
      g = g |> apply!({:rubies, :droplet}) |> apply!({:rubies, :flask})
      assert me(g).rubies == 0 and me(g).droplet == 1 and me(g).flask
      assert {0, {:rubies_spent, :droplet, 1}} in g.log
    end
  end

  describe "choice books" do
    test "G5: a pot chip up to the green's value becomes the first chip next round" do
      g = new(%{green: 5}) |> with_witch(:g4) |> force_draws([{:red, 1}, {:blue, 2}, {:green, 2}])
      g = apply!(g, :stop)
      assert g.phase == :chip_choice
      choices = for {:chip, {:starter, chip}} <- Game.legal_actions(g), do: chip
      assert Enum.sort(choices) == [{:blue, 2}, {:green, 2}, {:red, 1}]

      g = apply!(g, {:chip, {:starter, {:blue, 2}}})
      assert me(g).starters == [{:blue, 2}]
      g = g |> apply!({:buy, []}) |> apply!(:end_round)
      g = apply!(g, :draw)
      assert [{{:blue, 2}, 2}] = me(g).drawn
      assert me(g).starters == []
    end

    test "R6: one more chip goes aside; place it any time, and after stopping it must go in" do
      g = new(%{red: 6}) |> put(bag: [{:red, 1}, {:red, 1}]) |> apply!(:draw)
      assert me(g).aside == [{:red, 1}] and me(g).bag == []
      assert {0, {:effect, {:red, 6}, {:aside, {:red, 1}}}} in g.log
      assert {:red, {:place, {:red, 1}}} in Game.legal_actions(g)

      # placed while brewing: a normal draw (its own R6 action finds an empty bag)
      placed = apply!(g, {:red, {:place, {:red, 1}}})
      assert length(me(placed).drawn) == 2 and me(placed).aside == []

      # after stopping, placing it is the only action
      g = apply!(g, :stop)
      assert Game.legal_actions(g) == [{:red, {:place, {:red, 1}}}]
      g = apply!(g, {:red, {:place, {:red, 1}}})
      assert me(g).aside == [] and length(me(g).drawn) == 2
    end

    test "R6: a white placed after stopping can still explode the pot" do
      g = new(%{red: 6}) |> force_draws([{:white, 3}, {:white, 3}]) |> put(aside: [{:white, 2}])
      g = apply!(g, :stop)
      g = apply!(g, {:red, {:place, {:white, 2}}})
      assert me(g).exploded? and Game.phase(g, 0) == :explosion_choice
    end

    test "Y6: 1 ruby moves the yellow 3 more; :chip_done keeps the ruby" do
      g = new(%{yellow: 6}) |> force_draws([{:yellow, 1}])
      assert Game.phase(g, 0) == :chip_choice
      assert Game.legal_actions(g) == [{:chip, :yellow_ruby}, :chip_done]
      g = apply!(g, {:chip, :yellow_ruby})
      assert me(g).pot_index == 4 and me(g).rubies == 0 and Game.phase(g, 0) == :potions

      g = new(%{yellow: 6}) |> force_draws([{:yellow, 1}]) |> apply!(:chip_done)
      assert me(g).pot_index == 1 and me(g).rubies == 1

      # no ruby: no choice
      g = new(%{yellow: 6}) |> put(rubies: 0) |> force_draws([{:yellow, 1}])
      assert Game.phase(g, 0) == :potions
    end

    test "P5: the purple spaces' VP buy chips in step B; round 9 turns them into VP" do
      vp = fn i -> PotTrack.at(i).vp end
      drawn = [{{:purple, 1}, 40}, {{:purple, 1}, 30}]
      coins = vp.(40) + vp.(30)

      g =
        new(%{purple: 5})
        |> with_witch(:g4)
        |> put(drawn: drawn, pot_index: 40, bag: [{:green, 1}])

      g = apply!(g, :stop)
      assert g.phase == :chip_choice
      buys = for {:chip, {:buy, chips}} <- Game.legal_actions(g), do: chips
      assert [{:green, 1}] in buys

      assert Enum.all?(buys, fn chips ->
               Enum.sum(Enum.map(chips, &Chips.price(&1, g.sets))) <= coins
             end)

      g = apply!(g, {:chip, {:buy, [{:green, 1}]}})
      assert Enum.count(me(g).bag, &(&1 == {:green, 1})) == 2
      assert {0, {:effect, {:purple, 5}, {:bought, [{:green, 1}]}}} in g.log

      g =
        new(%{purple: 5})
        |> with_witch(:g4)
        |> put(round: 9, drawn: drawn, pot_index: 40, bag: [{:green, 1}])

      g = apply!(g, :stop)
      assert {0, {:effect, {:purple, 5}, {:vp, div(coins, 5)}}} in g.log
    end
  end
end
