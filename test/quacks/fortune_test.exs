defmodule Quacks.FortuneTest do
  use ExUnit.Case, async: true

  import Quacks.GameHelpers

  alias Quacks.Game
  alias Quacks.Game.Fortune
  alias Quacks.Rules.Fortune, as: Cards

  @seed {1, 2, 3}

  defp new(players \\ 1), do: Game.new(seed: @seed, players: players, fortune: false)

  # A game with blue card `id` in force for round 1.
  defp blue(id, players \\ 1), do: put(new(players), fortune_card: id)

  # Turn up purple card `id` on a hand-built game.
  defp purple(g, id), do: g |> put(fortune_card: id) |> Fortune.resolve()

  defp logged?(g, seat, id, outcome), do: {seat, {:fortune, id, outcome}} in g.log

  defp fortune_actions(g, seat \\ 0),
    do: Enum.filter(Game.legal_actions(g, seat), &match?({:fortune, _}, &1))

  describe "the deck" do
    test "24 cards, 11 blue and 13 purple" do
      assert length(Cards.all()) == 24
      assert Enum.count(Cards.all(), &(&1.colour == :blue)) == 11
      assert Cards.card(:p6).name == "Boomberry Cleanse"
    end

    test "a solo deck leaves out the cards that need other players" do
      rng = :rand.seed_s(:exsss, @seed)
      solo = Fortune.deck(rng, 1)
      assert length(solo) == 20
      assert Enum.sort(solo) == Enum.sort(Cards.ids(1))
      assert Enum.all?([:p4, :p5, :p8, :b2], &(&1 not in solo))
      assert length(Fortune.deck(rng, 4)) == 24
      assert Fortune.deck(rng, 4) == Fortune.deck(rng, 4)
    end

    test "new/1 turns up round 1's card without touching the game's rng" do
      g = Game.new(seed: @seed)
      assert g.fortune_card != nil
      assert {:fortune_drawn, g.fortune_card} in g.log
      assert length(g.fortune_deck) == 19
      assert g.rng == new().rng
    end

    test "fortune: false yields no card" do
      g = new()
      assert g.fortune_card == nil and g.fortune_deck == [] and g.log == []
    end

    test "solo skips Infestation and Good Start and turns up the next card" do
      g = new() |> put(fortune_deck: [:p7, :p9, :p2]) |> Fortune.draw()
      assert g.fortune_card == :p2

      assert g.log == [
               {:fortune_drawn, :p2},
               {:fortune_skipped, :p9},
               {:fortune_skipped, :p7}
             ]
    end
  end

  describe "blue cards" do
    test "B1 Bubbling Over: exactly 7 white on stop moves the droplet" do
      g = blue(:b1) |> force_draws([{:white, 3}, {:white, 2}, {:white, 2}]) |> apply!(:stop)
      assert logged?(g, 0, :b1, :droplet)
      assert me(g).droplet >= 1

      g = blue(:b1) |> force_draws([{:white, 3}, {:white, 2}]) |> apply!(:stop)
      refute logged?(g, 0, :b1, :droplet)
    end

    test "B2 Toil and Trouble: the player left of an exploded pot takes a 2-value chip" do
      g =
        blue(:b2, 2)
        |> force_draws(0, [{:white, 3}, {:white, 3}, {:white, 2}])
        |> apply!(0, {:explosion_choice, :vp})
        |> force_draws(1, [{:white, 1}])
        |> apply!(1, :stop)

      assert g.phase == :fortune_choice and g.turn == 1
      assert {:fortune, {:take, {:green, 2}}} in Game.legal_actions(g, 1)
      refute {:fortune, {:take, {:yellow, 2}}} in Game.legal_actions(g, 1)
      assert Game.legal_actions(g, 0) == []

      g = apply!(g, 1, {:fortune, {:take, {:green, 2}}})
      assert {:green, 2} in me(g, 1).bag
      assert logged?(g, 1, :b2, {:take, {:green, 2}})
      assert g.phase == :buy_chips
    end

    test "B3 Second Chances: after the 5th chip, restart the round once" do
      five = [{:white, 1}, {:white, 1}, {:orange, 1}, {:white, 1}, {:white, 1}]
      g = blue(:b3) |> force_draws(Enum.take(five, 4))
      assert fortune_actions(g) == []

      g = force_draws(g, [{:white, 1}])
      assert fortune_actions(g) == [{:fortune, :restart_round}]

      g = apply!(g, {:fortune, :restart_round})
      assert me(g).drawn == [] and me(g).pot_index == 0
      assert Enum.sort(me(g).bag) == Enum.sort(five)
      assert logged?(g, 0, :b3, :restart_round)

      g = force_draws(g, five)
      assert fortune_actions(g) == []
    end

    # Official ruling (The Herb Witches rulebook): card draws cannot explode the pot.
    test "B3 Second Chances: the first 5 draws cannot explode the pot; later draws can" do
      five = [{:white, 3}, {:white, 3}, {:white, 2}, {:white, 1}, {:green, 1}]
      g = blue(:b3) |> force_draws(five)
      assert Game.white_sum(g) == 9 and Game.phase(g, 0) == :potions
      refute me(g).exploded?
      assert fortune_actions(g) == [{:fortune, :restart_round}]

      g = force_draws(g, [{:orange, 1}])
      assert Game.phase(g, 0) == :explosion_choice

      # after a restart the draws are normal draws
      g = blue(:b3) |> force_draws(Enum.take(five, 4)) |> force_draws([{:orange, 1}])
      g = g |> apply!({:fortune, :restart_round}) |> force_draws([{:white, 3}, {:white, 3}])
      g = force_draws(g, [{:white, 2}])
      assert Game.phase(g, 0) == :explosion_choice
    end

    test "B4 Double Double: the bonus die is rolled twice" do
      g = blue(:b4) |> force_draws([{:white, 1}]) |> apply!(:stop)
      assert Enum.count(g.log, &match?({0, {:bonus_die, _}}, &1)) == 2
    end

    test "B5 Portentous Potables: the pot explodes above 9, not above 7" do
      g = blue(:b5) |> force_draws([{:white, 3}, {:white, 3}, {:white, 3}])
      assert Game.phase(g, 0) == :potions

      g = force_draws(g, [{:white, 1}])
      assert Game.phase(g, 0) == :explosion_choice
    end

    test "B6 Pumpkin Party: orange chips move one extra space" do
      assert me(force_draws(blue(:b6), [{:orange, 1}])).pot_index == 2
      assert me(force_draws(blue(:b6), [{:green, 1}])).pot_index == 1
    end

    test "B7 Safety Procedure: on stop, place one of up to 5 drawn chips" do
      g = blue(:b7) |> force_draws([{:white, 1}]) |> put(bag: [{:green, 1}, {:red, 1}])
      g = apply!(g, :stop)
      assert Game.phase(g, 0) == :fortune_choice

      assert Game.legal_actions(g) == [
               {:fortune, {:place, {:green, 1}}},
               {:fortune, {:place, {:red, 1}}},
               {:fortune, :return_all}
             ]

      g = apply!(g, {:fortune, {:place, {:red, 1}}})
      assert [{{:red, 1}, 2} | _] = me(g).drawn
      assert {:green, 1} in me(g).bag
      assert g.phase == :buy_chips
    end

    # Official ruling (The Herb Witches rulebook): the placed chip cannot explode the
    # pot and has no action.
    test "B7 Safety Procedure: the placed chip cannot explode the pot and has no action" do
      g = blue(:b7) |> force_draws([{:white, 3}, {:white, 3}]) |> put(bag: [{:white, 3}])
      g = g |> apply!(:stop) |> apply!({:fortune, {:place, {:white, 3}}})
      assert Game.white_sum(g) == 9
      refute me(g).exploded?
      assert g.phase == :buy_chips and me(g).coins > 0

      # a red (Set 1) after an orange moves its printed value only
      g = blue(:b7) |> force_draws([{:orange, 1}]) |> put(bag: [{:red, 1}])
      g = g |> apply!(:stop) |> apply!({:fortune, {:place, {:red, 1}}})
      assert [{{:red, 1}, 2} | _] = me(g).drawn
    end

    test "B8 Lucky Devil: a ruby scoring space gives 2 VP" do
      # white 3, white 1 -> index 4, scoring space 5 shows a ruby
      g = blue(:b8) |> force_draws([{:white, 3}, {:white, 1}]) |> apply!(:stop)
      assert logged?(g, 0, :b8, {:vp, 2})
    end

    test "B9 Flask Rabbit: empty flasks refill for free" do
      g = blue(:b9) |> force_draws([{:white, 1}]) |> apply!(:use_flask)
      refute me(g).flask
      g = g |> force_draws([{:white, 1}]) |> apply!(:stop)
      assert me(g).flask
      assert logged?(g, 0, :b9, :flask)
    end

    test "B10 Cauldron Bubble: the first white chip may go back in the bag" do
      g = force_draws(blue(:b10), [{:white, 2}])
      assert fortune_actions(g) == [{:fortune, :return_white}]

      g = apply!(g, {:fortune, :return_white})
      assert me(g).drawn == [] and me(g).bag == [{:white, 2}] and me(g).flask
      assert logged?(g, 0, :b10, :return_white)

      assert fortune_actions(force_draws(g, [{:white, 1}])) == []
    end

    test "B11 Fire Burn: a ruby scoring space gives an extra ruby" do
      g = blue(:b11) |> force_draws([{:white, 3}, {:white, 1}]) |> apply!(:stop)
      assert logged?(g, 0, :b11, :ruby)
      assert me(g).rubies >= 3
    end
  end

  describe "purple cards" do
    test "P1 Choices, Choices: black, a 2-value chip or 3 rubies" do
      g = purple(new(), :p1)
      assert g.phase == :fortune_choice and g.turn == 0
      actions = Game.legal_actions(g)
      assert {:fortune, {:take, {:black, 1}}} in actions
      assert {:fortune, {:take, {:blue, 2}}} in actions
      refute {:fortune, {:take, {:yellow, 2}}} in actions
      assert {:fortune, :rubies} in actions

      g = apply!(g, {:fortune, :rubies})
      assert me(g).rubies == 4 and g.phase == :potions
      assert Game.legal_actions(g) == [:draw]
    end

    test "P2 Drop It: every droplet moves one space" do
      g = purple(new(2), :p2)
      assert me(g, 0).droplet == 1 and me(g, 1).droplet == 1
      assert me(g, 1).pot_index == 1
      assert logged?(g, 1, :p2, :droplet)
    end

    test "P3 Wheeling and Dealing: a ruby for a 1-value chip" do
      g = purple(new(), :p3)
      refute {:fortune, {:take, {:purple, 1}}} in Game.legal_actions(g)
      g = apply!(g, {:fortune, {:take, {:red, 1}}})
      assert me(g).rubies == 0 and {:red, 1} in me(g).bag

      assert purple(put(new(), rubies: 0), :p3).phase == :potions
    end

    test "P4 Charity: the fewest rubies take a ruby" do
      g = new(3) |> put(1, rubies: 3) |> purple(:p4)
      assert Enum.map(0..2, &me(g, &1).rubies) == [2, 3, 2]
      assert g.phase == :potions
    end

    test "P5 Beginner's Luck: the fewest VP take a green 1" do
      g = new(3) |> put(0, vp: 5) |> purple(:p5)
      assert Enum.map(0..2, &Enum.count(me(g, &1).bag, fn c -> c == {:green, 1} end)) == [1, 2, 2]
    end

    test "P6 Boomberry Cleanse: 4 VP or a white 1 out of the bag" do
      g = purple(new(), :p6)
      assert fortune_actions(g) == [{:fortune, :vp}, {:fortune, :remove_white}]
      assert me(apply!(g, {:fortune, :vp})).vp == 4

      g = apply!(g, {:fortune, :remove_white})
      assert Enum.count(me(g).bag, &(&1 == {:white, 1})) == 3
      assert g.supply[{:white, 1}] == new().supply[{:white, 1}] + 1
    end

    test "P7 Infestation: the rat stone moves as far again" do
      g = new(2) |> put(1, rat_stone: 2, pot_index: 2) |> purple(:p7)
      assert me(g, 1).rat_stone == 4 and me(g, 1).pot_index == 4
      assert me(g, 0).rat_stone == 0
      assert logged?(g, 1, :p7, {:rats, 2})
    end

    test "P8 Less is More: the lowest 5-chip sum takes a blue 2, the rest a ruby" do
      g =
        new(2)
        |> put(0, bag: List.duplicate({:white, 1}, 6))
        |> put(1, bag: List.duplicate({:white, 3}, 6))
        |> purple(:p8)

      assert {:blue, 2} in me(g, 0).bag and length(me(g, 0).bag) == 7
      assert me(g, 1).rubies == 2 and length(me(g, 1).bag) == 6
    end

    test "P9 Good Start: move the rat stone back for rubies" do
      g = new(2) |> put(1, rat_stone: 4, pot_index: 4) |> purple(:p9)
      assert g.phase == :fortune_choice and g.turn == 1

      assert Game.legal_actions(g, 1) ==
               [{:fortune, {:rats_back, 1}}, {:fortune, {:rats_back, 2}}] ++
                 [{:fortune, {:rats_back, 3}}, {:fortune, :skip}]

      g = apply!(g, 1, {:fortune, {:rats_back, 3}})
      assert me(g, 1).rat_stone == 1 and me(g, 1).pot_index == 1 and me(g, 1).rubies == 4
      assert g.phase == :potions
    end

    test "P10 Rat-a-Tat: a 4-value chip, or 1 VP per rat tail behind the leader" do
      g = new(2) |> put(1, vp: 12) |> purple(:p10)
      assert {:fortune, :vp} in Game.legal_actions(g, 0)
      g = apply!(g, 0, {:fortune, :vp})
      # 4 tails between 0 and 12: after 1, 4, 7, 10
      assert me(g, 0).vp == 4

      assert g.turn == 1
      refute {:fortune, :vp} in Game.legal_actions(g, 1)
      g = apply!(g, 1, {:fortune, {:take, {:red, 4}}})
      assert {:red, 4} in me(g, 1).bag and g.phase == :potions

      assert fortune_actions(purple(new(), :p10)) ==
               [{:fortune, {:take, {:blue, 4}}}, {:fortune, {:take, {:green, 4}}}] ++
                 [{:fortune, {:take, {:red, 4}}}]
    end

    test "P11 Decisions, Decisions: droplet 2 forward or a purple chip" do
      assert fortune_actions(purple(new(), :p11)) == [{:fortune, :droplet}]

      g = new() |> put(round: 3) |> purple(:p11)
      assert fortune_actions(g) == [{:fortune, :droplet}, {:fortune, {:take, {:purple, 1}}}]
      g = apply!(g, {:fortune, :droplet})
      assert me(g).droplet == 2 and me(g).pot_index == 2
    end

    test "P12 Take a Chance: everyone rolls the bonus die" do
      g = purple(new(2), :p12)
      assert Enum.count(g.log, &match?({_, {:fortune, :p12, _}}, &1)) == 2
      assert g.phase == :potions
    end

    test "P13 Flea Market: trade one of 4 chips one value up, else a green 1" do
      before = put(new(), bag: [{:green, 1}, {:green, 1}, {:orange, 1}, {:white, 1}])
      g = purple(before, :p13)
      assert fortune_actions(g) == [{:fortune, {:upgrade, {:green, 1}}}, {:fortune, :skip}]

      g = apply!(g, {:fortune, {:upgrade, {:green, 1}}})

      assert Enum.sort(me(g).bag) ==
               Enum.sort([{:green, 2}, {:green, 1}, {:orange, 1}, {:white, 1}])

      assert me(g).pending == [] and g.phase == :potions
      assert inventory(g) == inventory(before)

      g = new() |> put(bag: List.duplicate({:white, 1}, 4)) |> purple(:p13)
      assert {:green, 1} in me(g).bag and length(me(g).bag) == 5
      assert logged?(g, 0, :p13, {:take, {:green, 1}}) and g.phase == :potions
    end
  end
end
