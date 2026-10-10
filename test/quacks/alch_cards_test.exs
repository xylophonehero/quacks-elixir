defmodule Quacks.AlchCardsTest do
  @moduledoc "The 20 Fortune Teller cards of The Alchemists box: one test per card."
  use ExUnit.Case, async: true

  import Quacks.GameHelpers

  alias Quacks.{AI, Game}
  alias Quacks.AI.{Profile, Sim}
  alias Quacks.Game.Fortune
  alias Quacks.Rules.Alchemists
  alias Quacks.Rules.Fortune, as: Cards

  @seed {1, 2, 3}

  defp new(players \\ 1, opts \\ []) do
    Game.new([seed: @seed, players: players, fortune: false, rules: %{supply: :limited}] ++ opts)
  end

  defp alchemists(players \\ 1) do
    g = %{new(players, expansions: [:alchemists]) | patients: Alchemists.patients()}
    Enum.reduce(g.seats, g, &apply!(&2, &1, {:patient, :forgetfulness}))
  end

  defp purple(g, id), do: g |> put(fortune_card: id) |> Fortune.resolve()
  defp blue(g, id), do: put(g, fortune_card: id)
  defp logged?(g, seat, id, outcome), do: {seat, {:fortune, id, outcome}} in g.log

  defp fortune_actions(g, seat \\ 0),
    do: for({:fortune, c} <- Game.legal_actions(g, seat), do: c)

  defp essence_parts(g, seat \\ 0),
    do:
      Enum.find_value(g.log, fn
        {^seat, {:essence, _reach, parts}} -> parts
        _ -> nil
      end)

  # Round 2+: seat 1 is behind seat 0, so seat 1 has rats.
  defp with_rats(players \\ 2) do
    new(players) |> put(1, vp: 0) |> put(0, vp: 6) |> put(round: 2)
  end

  describe "the deck" do
    test "20 new cards: 14 for any game, 3 need The Herb Witches, 3 The Alchemists" do
      box = Enum.filter(Cards.all(), &Cards.alchemists?(&1.id))
      assert length(box) == 20
      assert Enum.count(box, &(&1.colour == :blue)) == 10
      assert Enum.count(box, &(&1.expansion == nil)) == 14
      assert Enum.count(box, &(&1.expansion == :herb_witches)) == 3
      assert Enum.count(box, &(&1.expansion == :alchemists)) == 3
    end

    test "the box cards are in the deck only with The Alchemists" do
      assert length(Cards.ids(4)) == 24
      # 14 + 3 Alchemists, without the 2 cards not built yet (AP8 needs no expansion).
      assert length(Cards.ids(4, [:alchemists])) == 24 + 16
      assert length(Cards.ids(4, [:alchemists, :herb_witches])) == 24 + 18
      solo = Cards.ids(1, [:alchemists, :herb_witches])
      assert Enum.all?([:ap5, :ap6, :ap8, :ap9, :ab4], &(&1 not in solo))
      refute :ap8 in Cards.ids(4, [:alchemists])
      refute :ab8 in Cards.ids(4, [:alchemists, :herb_witches])
    end

    test "the alch_cards house rule takes them out" do
      on = Game.new(seed: @seed, expansions: [:alchemists], players: 2)

      off =
        Game.new(seed: @seed, expansions: [:alchemists], players: 2, rules: %{alch_cards: false})

      assert Enum.any?(on.fortune_deck, &Cards.alchemists?/1)
      refute Enum.any?(off.fortune_deck, &Cards.alchemists?/1)
    end
  end

  describe "purple cards" do
    test "AP1 Spoiled for choice: a ruby, a roll and 3 rat tails, or a red 2" do
      g = purple(with_rats(), :ap1)
      assert fortune_actions(g, 1) == [:bundle, {:take, {:red, 2}}]
      rats = me(g, 1).rat_stone
      rubies = me(g, 1).rubies
      g = apply!(g, 1, {:fortune, :bundle})
      assert me(g, 1).rat_stone == rats + 3
      assert me(g, 1).rubies >= rubies + 1
      assert Enum.any?(g.log, &match?({1, {:fortune, :ap1, {:rolled, _}}}, &1))
      g = apply!(g, 0, {:fortune, {:take, {:red, 2}}})
      assert {:red, 2} in me(g).bag
      assert g.phase == :potions
    end

    test "AP2 Ruby fever: every seat draws 1 chip and takes its value in rubies" do
      g = new(2) |> put(0, bag: [{:green, 4}]) |> put(1, bag: [{:white, 2}]) |> purple(:ap2)
      assert me(g, 0).rubies == 1 + 4 and me(g, 1).rubies == 1 + 2
      assert me(g, 0).bag == [{:green, 4}]
      assert %{0 => %{drew: [{:green, 4}], gains: [{:rubies, 4}]}} = Fortune.reveals(g)
    end

    test "AP3 Give and take: rubies for a chip of that value, or 2 rubies" do
      g = new() |> put(rubies: 2) |> purple(:ap3)
      actions = fortune_actions(g)
      assert {:take, {:green, 2}} in actions and {:take, {:blue, 1}} in actions
      refute {:take, {:green, 4}} in actions
      assert :rubies in actions
      g = apply!(g, {:fortune, {:take, {:green, 2}}})
      assert me(g).rubies == 0 and {:green, 2} in me(g).bag

      g = new() |> purple(:ap3) |> apply!({:fortune, :rubies})
      assert me(g).rubies == 3
    end

    test "AP4 Rich offerings: 8 rat tails, 4 rolls or droplet +3" do
      g = purple(with_rats(), :ap4)
      assert fortune_actions(g, 1) == [:rats, :rolls, :droplet]
      rats = me(g, 1).rat_stone
      g = g |> apply!(1, {:fortune, :rats}) |> apply!(0, {:fortune, :rolls})
      assert me(g, 1).rat_stone == rats + 8
      assert Enum.count(g.log, &match?({0, {:fortune, :ap4, {:rolled, _}}}, &1)) == 4

      g = new() |> purple(:ap4)
      assert fortune_actions(g) == [:rolls, :droplet]
      g = apply!(g, {:fortune, :droplet})
      assert me(g).droplet == 3
    end

    test "AP5 A small donation: 2+ rat tails roll the die once" do
      g = purple(with_rats(), :ap5)
      assert me(g, 1).rat_stone >= 2
      assert Enum.any?(g.log, &match?({1, {:fortune, :ap5, {:rolled, _}}}, &1))
      refute Enum.any?(g.log, &match?({0, {:fortune, :ap5, {:rolled, _}}}, &1))
    end

    test "AP6 A rat to cherish: each ruby is 3 rat tails" do
      g = with_rats() |> put(1, rubies: 2) |> purple(:ap6)
      assert fortune_actions(g, 1) == [{:cherish, 1}, {:cherish, 2}, :skip]
      rats = me(g, 1).rat_stone
      g = apply!(g, 1, {:fortune, {:cherish, 2}})
      assert me(g, 1).rubies == 0 and me(g, 1).rat_stone == rats + 6
      assert fortune_actions(new() |> purple(:ap6)) == []
    end

    test "AP7 A quick exchange: a witch penny for any chip" do
      g = new(1, expansions: [:herb_witches]) |> purple(:ap7)
      assert {:exchange, :gold, {:green, 4}} in fortune_actions(g)
      assert :skip in fortune_actions(g)
      g = apply!(g, {:fortune, {:exchange, :gold, {:green, 4}}})
      assert me(g).pennies.gold == false and {:green, 4} in me(g).bag
      assert fortune_actions(new() |> purple(:ap7)) == []
    end

    test "AP9 Useful rodent: 2, 4 or 6 rat tails for a 1-, 2- or 4-chip" do
      g = with_rats() |> purple(:ap9)
      rats = me(g, 1).rat_stone
      assert rats == 2
      actions = fortune_actions(g, 1)
      assert {:take, {:green, 1}} in actions
      refute {:take, {:green, 2}} in actions
      refute Enum.any?(actions, &match?({:take, {:purple, _}}, &1))
      g = apply!(g, 1, {:fortune, {:take, {:green, 1}}})
      assert me(g, 1).rat_stone == 0 and {:green, 1} in me(g, 1).bag
    end

    test "AP10 A powerful tipple: droplet back 1 for a 2-chip, 2 for a 4-chip" do
      assert fortune_actions(new() |> purple(:ap10)) == []
      g = new() |> put(droplet: 1, pot_index: 1) |> purple(:ap10)
      actions = fortune_actions(g)
      assert {:take, {:red, 2}} in actions
      refute {:take, {:red, 4}} in actions
      g = apply!(g, {:fortune, {:take, {:red, 2}}})
      assert me(g).droplet == 0 and me(g).pot_index == 0 and {:red, 2} in me(g).bag
    end
  end

  describe "blue cards" do
    test "AB1 From good to better: after stop, swap a coloured 2/4 chip in the pot" do
      g = new() |> blue(:ab1) |> force_draws([{:green, 2}, {:white, 1}]) |> apply!(:stop)
      assert Game.phase(g, 0) == :fortune_choice
      assert {:better, {:green, 2}, {:blue, 4}} in fortune_actions(g)
      g = apply!(g, {:fortune, {:better, {:green, 2}, {:blue, 4}}})
      assert {:blue, 4} in Game.pot_chips(g) or {:blue, 4} in me(g).bag
      refute {:green, 2} in me(g).bag
      assert logged?(g, 0, :ab1, {:better, {:green, 2}, {:blue, 4}})
    end

    test "AB2 Sale: two chips bought give the cheaper one again" do
      g = new() |> blue(:ab2) |> put(phase: :buy, coins: 20)
      g = apply!(g, {:buy, [{:orange, 1}, {:green, 1}]})
      assert Enum.count(me(g).bag, &(&1 == {:orange, 1})) == 1 + 2
      assert logged?(g, 0, :ab2, {:free, {:orange, 1}})
    end

    test "AB3 The white blessing: a white last chip pays its value in VP" do
      g = new() |> blue(:ab3) |> force_draws([{:orange, 1}, {:white, 3}]) |> apply!(:stop)
      assert logged?(g, 0, :ab3, {:vp, 3})
    end

    test "AB4 A rat's blessing: 2 coins per rat tail" do
      g = with_rats() |> blue(:ab4) |> Game.rats()
      rats = me(g, 1).rat_stone
      g = g |> force_draws(1, [{:orange, 1}]) |> apply!(1, :stop)
      g = g |> force_draws(0, [{:orange, 1}]) |> apply!(0, :stop)
      assert logged?(g, 1, :ab4, {:coins, 2 * rats})
    end

    test "AB5 A good neighborhood: the white 3 back to the bag, left player +2 rubies" do
      g = new(2) |> blue(:ab5) |> force_draws(0, [{:white, 3}])
      assert fortune_actions(g) == [:return_white3]
      g = apply!(g, {:fortune, :return_white3})
      assert Game.pot_chips(g) == [] and {:white, 3} in me(g).bag
      assert me(g, 1).rubies == 3
      assert fortune_actions(g) == []
    end

    test "AB6 A blessing in disguise: an exploded pot gets 2 more essence" do
      g =
        alchemists()
        |> blue(:ab6)
        |> force_draws([{:orange, 1}, {:white, 3}, {:white, 3}, {:white, 2}])
        |> apply!({:explosion_choice, :vp})

      assert essence_parts(g).card == 2
    end

    test "AB7 Essential essence: the highest essence refills the flask or rolls" do
      g = alchemists() |> blue(:ab7) |> put(flask: false)
      g = g |> force_draws([{:orange, 1}, {:green, 1}]) |> apply!(:stop)
      assert logged?(g, 0, :ab7, :flask)
      assert me(g).flask
    end

    test "AB9 All's well that ends well: essence + the spaces the last chip moved" do
      g = alchemists() |> blue(:ab9) |> force_draws([{:orange, 1}, {:green, 2}]) |> apply!(:stop)
      assert essence_parts(g).card == 2
    end

    test "AB10 A joyful reunion: a spent penny comes back at the end of the round" do
      g = new(1, expansions: [:herb_witches]) |> blue(:ab10)
      g = put(g, pennies: %{silver: false, copper: true, gold: false})
      g = g |> force_draws([{:orange, 1}]) |> apply!(:stop)
      assert me(g).pennies.gold
      refute me(g).pennies.silver
      assert logged?(g, 0, :ab10, {:penny, :gold})
    end
  end

  describe "bots" do
    test "every bot answers every new card choice with a legal, sensible action" do
      rng = :rand.seed_s(:exsss, {9, 9, 9})

      for id <- [:ap1, :ap3, :ap4, :ap6, :ap7, :ap9, :ap10], name <- Profile.all() do
        g =
          new(2, expansions: [:herb_witches])
          |> put(1, vp: 0, rubies: 3)
          |> put(0, vp: 6, droplet: 2, pot_index: 2)
          |> put(round: 2)
          |> purple(id)

        for seat <- g.seats, Game.legal_actions(g, seat) != [] do
          {action, _rng} = AI.decide(g, seat, Profile.get(name), rng)
          assert action in Game.legal_actions(g, seat), "#{id} #{name}: #{inspect(action)}"
        end
      end
    end

    test "the scored pick swaps a pot chip up, not down (AB1)" do
      g = new() |> blue(:ab1) |> force_draws([{:green, 2}, {:white, 1}]) |> apply!(:stop)
      {action, _rng} = AI.decide(g, 0, Profile.get(:balanced), :rand.seed_s(:exsss, {9, 9, 9}))
      assert {:fortune, {:better, {:green, 2}, {_, 4}}} = action
    end

    test "bots play whole games with the box cards" do
      for n <- 1..12 do
        {g, _rounds} =
          Sim.play([:balanced, :cautious, :balanced], {n, 5, 7},
            expansions: [:alchemists, :herb_witches]
          )

        assert Game.over?(g)
      end
    end
  end
end
