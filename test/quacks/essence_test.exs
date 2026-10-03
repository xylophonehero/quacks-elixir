defmodule Quacks.EssenceTest do
  use ExUnit.Case, async: true

  import Quacks.GameHelpers

  alias Quacks.AI.Sim
  alias Quacks.{Game, Session}
  alias Quacks.Game.Essence
  alias Quacks.Rules.{Alchemists, Books, Chips}

  doctest Alchemists

  @seed {1, 2, 3}
  @al [:alchemists]

  defp new(opts) do
    Game.new(
      [seed: @seed, fortune: false, expansions: @al, players: Keyword.get(opts, :players, 1)] ++
        Keyword.take(opts, [:sets, :rules])
    )
  end

  # Every seat picks `patient` (all 8 offered, so any patient can be tested).
  defp game(patient, opts \\ []) do
    g = %{new(opts) | patients: Alchemists.patients()}
    Enum.reduce(g.seats, g, &apply!(&2, &1, {:patient, patient}))
  end

  # A hand-built pot: `chips` on spaces 1, 2, 3, ...
  defp brew(g, seat \\ 0, chips) do
    drawn = chips |> Enum.with_index(1) |> Enum.reverse()
    put(g, seat, drawn: drawn, pot_index: length(chips))
  end

  defp stop(g, seat \\ 0), do: apply!(g, seat, :stop)
  defp logged?(g, seat \\ 0, event), do: {seat, event} in g.log
  defp bonuses(g, seat \\ 0), do: for({^seat, {:essence_bonus, b}} <- g.log, do: b)

  describe "data" do
    test "8 patients with 10 slots; deal gives 3 different ones from the seed" do
      assert length(Alchemists.patients()) == 8

      for id <- Alchemists.patients() do
        assert %{slots: slots, name: name} = Alchemists.get(id)
        assert Map.keys(slots) == Enum.to_list(1..10) and name != ""
      end

      for n <- 1..50 do
        dealt = Alchemists.deal(:rand.seed_s(:exsss, {n, 2, 3}))
        assert length(Enum.uniq(dealt)) == 3 and dealt -- Alchemists.patients() == []
      end

      rng = :rand.seed_s(:exsss, @seed)
      assert Alchemists.deal(rng) == Alchemists.deal(rng)
    end

    test "Witch's hump table: hawkmoth 2, ghost's breath 3, locoweed 4" do
      assert Alchemists.hump_bonus({:white, 1}) == {:rubies, 1}
      assert Alchemists.hump_bonus({:purple, 1}) == {:chip, {:yellow, 1}}
      assert Alchemists.hump_bonus({:locoweed, 1}) == {:vp, 3}
      assert Alchemists.hump_bonus({:green, 4}) == {:vp, 3}
      assert Alchemists.hump_bonus({:orange, 6}) == nil
    end

    test "locoweed III: price 11, book text, refused without The Alchemists" do
      assert Chips.price({:locoweed, 1}, %{locoweed: 3}) == 11
      assert %{trigger: :on_draw, prices: [11]} = Books.get({:locoweed, 3})
      assert new(sets: %{locoweed: 3}).sets.locoweed == 3

      assert_raise ArgumentError, fn ->
        Game.new(seed: @seed, expansion: :herb_witches, sets: %{locoweed: 3})
      end

      assert Chips.supply(MapSet.new(@al), %{locoweed: 3})[{:locoweed, 1}] == 30
      assert Chips.supply(MapSet.new([:herb_witches | @al]), %{locoweed: 3})[{:locoweed, 1}] == 55
      refute Map.has_key?(Chips.supply(MapSet.new(@al), %{}), {:locoweed, 1})
    end

    test "locoweed III moves 1 on draw" do
      g = force_draws(game(:forgetfulness, sets: %{locoweed: 3}), [{:locoweed, 1}])
      assert me(g).pot_index == 1
    end
  end

  describe "expansions as a set" do
    test "expansion: is an alias; both may be on; the log names each one" do
      g = Game.new(seed: @seed, expansion: :herb_witches, expansions: @al)
      assert g.expansions == MapSet.new([:herb_witches, :alchemists])
      assert Game.expansion?(g, :herb_witches) and Game.expansion?(g, :alchemists)
      assert g.expansion == :herb_witches and g.witches != nil

      assert [{:expansion, :herb_witches}, {:expansion, :alchemists}, {:patients, _}] =
               Enum.reverse(g.log)

      base = Game.new(seed: @seed)
      assert base.expansions == MapSet.new() and base.expansion == nil
      refute Game.expansion?(base, :alchemists)
      assert Game.new(seed: @seed, expansions: @al).expansion == nil
      assert_raise ArgumentError, fn -> Game.new(seed: @seed, expansions: [:other]) end
    end

    test "Session keeps the expansions through undo" do
      s = Session.new(@seed, 2, expansions: @al, fortune: false)
      {:ok, s} = Session.apply(s, 0, {:patient, hd(s.game.patients)})
      assert s.expansions == MapSet.new(@al)
      assert Session.undo(s).game.phase == :patient_choice
    end
  end

  describe "patient choice" do
    test "every seat picks before round 1; the card comes after" do
      g = Game.new(seed: @seed, expansions: @al, players: 2)
      assert g.phase == :patient_choice and g.fortune_card == nil
      assert Game.legal_actions(g, 1) == Enum.map(g.patients, &{:patient, &1})

      g = apply!(g, 1, {:patient, hd(g.patients)})
      assert Game.legal_actions(g, 1) == [] and g.phase == :patient_choice

      g = apply!(g, 0, {:patient, List.last(g.patients)})
      assert g.phase == :potions and g.fortune_card != nil
      assert Game.legal_actions(g, 0) == [:draw]
    end

    test "start chips: Carrot nose 10 chips, Forgetfulness 11" do
      assert length(me(game(:carrot_nose)).bag) == 10
      assert {:orange, 1} in (me(game(:carrot_nose)).bag -- Chips.starting_bag())
      assert me(game(:forgetfulness)).bag -- Chips.starting_bag() == [{:red, 1}, {:black, 1}]
    end
  end

  describe "reach" do
    test "colours, not white, locoweed counted" do
      g = brew(game(:forgetfulness), [{:white, 1}, {:orange, 1}, {:orange, 1}, {:locoweed, 1}])
      assert {2, %{colours: 2, locoweed: 0, white7: 0, neighbours: 0}} = Essence.count(g, 0)
    end

    test "locoweed III: +1 per locoweed in the pot" do
      g = game(:forgetfulness, sets: %{locoweed: 3})
      g = brew(g, [{:locoweed, 1}, {:green, 1}, {:locoweed, 1}])
      assert {4, %{colours: 2, locoweed: 2}} = Essence.count(g, 0)
    end

    test "white chips adding up to exactly 7: +1" do
      g = game(:forgetfulness)

      assert {2, %{white7: 1}} =
               Essence.count(brew(g, [{:white, 3}, {:white, 3}, {:white, 1}, {:green, 1}]), 0)

      assert {1, %{white7: 0}} =
               Essence.count(brew(g, [{:white, 3}, {:white, 3}, {:green, 1}]), 0)
    end

    test "exploded neighbours: 2 with 3+ players, 1 with 2, 0 solo" do
      g = game(:forgetfulness, players: 4)
      g = g |> put(1, exploded?: true) |> put(3, exploded?: true) |> put(2, exploded?: true)
      assert {2, %{neighbours: 2}} = Essence.count(g, 0)
      assert {1, %{neighbours: 1}} = Essence.count(g, 1)

      g = put(game(:forgetfulness, players: 2), 1, exploded?: true)
      assert {1, %{neighbours: 1}} = Essence.count(g, 0)
      assert {0, %{neighbours: 0}} = Essence.count(put(game(:forgetfulness), exploded?: true), 0)
    end

    test "capped at 10" do
      g = game(:forgetfulness, sets: %{locoweed: 3})
      chips = [:orange, :green, :blue, :red, :yellow, :purple, :black] |> Enum.map(&{&1, 1})
      g = brew(g, chips ++ [{:locoweed, 1}, {:locoweed, 1}, {:locoweed, 1}])
      assert {10, %{colours: 8, locoweed: 3}} = Essence.count(g, 0)
    end
  end

  describe "the essence phase" do
    test "runs after the last stop, before the evaluation; marker reset first" do
      g = game(:forgetfulness) |> put(essence: 5) |> brew([{:orange, 1}, {:green, 1}]) |> stop()
      assert logged?(g, {:essence, 2, %{colours: 2, locoweed: 0, white7: 0, neighbours: 0}})
      assert me(g).essence == 2 and g.phase == :shopping

      log = Enum.reverse(g.log)
      essence = Enum.find_index(log, &match?({0, {:essence, 2, _}}, &1))
      assert essence < Enum.find_index(log, &match?({0, {:bonus_die, _}}, &1))
    end

    test "no lower bonus of another kind: the reached space at once (VP now)" do
      chips = Enum.map([:orange, :green, :blue, :red, :purple, :black, :locoweed], &{&1, 1})
      g = game(:forgetfulness, sets: %{locoweed: 1}) |> brew(chips) |> stop()
      assert me(g).essence == 7 and bonuses(g) == [{:vp, 1}]
      refute Essence.lower_choice?(:forgetfulness, 7)
    end

    test "a lower space with another bonus kind: the seat picks 0..reach" do
      g =
        game(:nervousness)
        |> brew(Enum.map([:orange, :green, :blue, :red, :purple], &{&1, 1}))
        |> stop()

      assert g.phase == :essence and Game.phase(g, 0) == :essence_choice
      assert Game.legal_actions(g) == for(n <- 0..5, do: {:essence, {:space, n}})

      g = apply!(g, {:essence, {:space, 1}})
      assert me(g).essence == 1 and bonuses(g) == [:rat] and g.phase == :shopping
      refute Essence.lower_choice?(:nervousness, 1)
      refute Essence.lower_choice?(:chicken_eyes, 1)
    end

    test "Ear worm draws with the pot safe from exploding" do
      g =
        game(:ear_worm)
        |> brew([{:white, 3}, {:white, 3}, {:orange, 1}, {:green, 1}, {:red, 1}])
        |> put(bag: [{:white, 3}, {:white, 3}])
        |> stop()
        |> apply!({:essence, {:space, 3}})

      assert Game.phase(g, 0) == :ear_worm and Game.legal_actions(g) == [:draw]
      assert bonuses(g) == [{:ear_worm, 2}]
      g = g |> apply!(:draw) |> apply!(:draw)
      assert Game.white_sum(g) == 12 and not me(g).exploded?
      assert me(g).pot_index == 11 and g.phase == :shopping
    end

    test "Ear worm stops early when the bag is empty" do
      g =
        game(:ear_worm)
        |> brew([{:orange, 1}, {:green, 1}, {:red, 1}, {:blue, 1}, {:purple, 1}])
        |> put(bag: [{:white, 1}])
        |> stop()
        |> apply!({:essence, {:space, 5}})
        |> apply!(:draw)

      assert g.phase == :shopping and bonuses(g) == [{:ear_worm, 3}]
    end

    test "Chicken eyes: rubies at once; a swap waits for the seat" do
      g = game(:chicken_eyes) |> brew([{:orange, 1}]) |> stop()
      assert bonuses(g) == [{:rubies, 1}] and me(g).rubies >= 2

      g = game(:chicken_eyes) |> brew([{:orange, 1}, {:green, 1}, {:red, 1}]) |> stop()
      g = apply!(g, {:essence, {:space, 3}})
      assert Game.phase(g, 0) == :essence_bonus

      assert Game.legal_actions(g) ==
               [
                 {:essence, {:swap, {:green, 1}}},
                 {:essence, {:swap, {:red, 1}}},
                 {:essence, :pass}
               ]

      g = apply!(g, {:essence, {:swap, {:green, 1}}})
      assert {{:green, 2}, 2} in me(g).drawn and g.phase == :shopping
    end

    test "Chicken eyes: the flask, the die and the droplet" do
      g = game(:chicken_eyes) |> put(flask: false)
      g = g |> brew(Enum.map([:orange, :green, :blue, :red], &{&1, 1})) |> stop()
      g = apply!(g, {:essence, {:space, 4}})
      assert bonuses(g) == [:flask] and me(g).flask

      chips =
        Enum.map([:orange, :green, :blue, :red, :purple, :black, :locoweed, :yellow], &{&1, 1})

      g = game(:chicken_eyes, sets: %{locoweed: 1}) |> brew(chips) |> stop()
      g = apply!(g, {:essence, {:space, 8}})
      assert bonuses(g) == [{:droplet, 2}] and me(g).droplet >= 2

      g = game(:chicken_eyes, sets: %{locoweed: 1}) |> brew(chips) |> stop()
      g = apply!(g, {:essence, {:space, 7}})
      assert [{:dice, 2}] = bonuses(g)
      assert length(for {0, {:bonus_die, _}} <- g.log, do: 1) >= 2
    end

    test "Vampirism buys one chip for the space's coins" do
      g =
        game(:vampirism)
        |> brew(Enum.map([:orange, :green, :blue, :red, :purple], &{&1, 1}))
        |> stop()

      g = apply!(g, {:essence, {:space, 5}})
      legal = Game.legal_actions(g)
      assert {:essence, {:buy, {:blue, 1}}} in legal and {:essence, :pass} in legal
      refute {:essence, {:buy, {:red, 2}}} in legal

      g = apply!(g, {:essence, {:buy, {:blue, 1}}})
      assert {:blue, 1} in me(g).bag and logged?(g, {:bought, [{:blue, 1}]})
      assert g.phase == :shopping and me(g).coins >= 0
    end

    test "round 9: 1 VP per space, no glass" do
      g = game(:chicken_eyes) |> put(round: 9) |> brew([{:orange, 1}, {:green, 1}, {:red, 1}])
      g = stop(g)
      assert logged?(g, {:essence_vp, 3}) and bonuses(g) == [] and me(g).essence == 3
    end
  end

  describe "the next preparation phase" do
    # Land on `space` in round 1 and start round 2.
    defp next_round(patient, chips, space \\ nil) do
      g = game(patient) |> brew(chips) |> stop()
      g = if space, do: apply!(g, {:essence, {:space, space}}), else: g
      apply!(g, :end_round)
    end

    test "a rat-tail glass: rat stone 1 next round, solo too" do
      g = next_round(:wing_ears, [{:orange, 1}])
      assert g.round == 2 and me(g).rat_stone == 1 and me(g).pot_index == me(g).droplet + 1
      assert logged?(g, {:essence_rat, 1})
    end

    test "Nervousness lays out chips (whites back) and places them as draws" do
      g = next_round(:nervousness, [{:orange, 1}, {:green, 1}, {:red, 1}], 3)
      [chips] = for {0, {:display, chips}} <- g.log, do: chips
      assert length(chips) == 2
      assert me(g).display == Enum.reject(chips, &match?({:white, _}, &1))

      case me(g).display do
        [] ->
          :ok

        [chip | _] ->
          assert {:essence, {:place, chip}} in Game.legal_actions(g)
          g = apply!(g, {:essence, {:place, chip}})
          assert [{^chip, _}] = me(g).drawn
      end
    end

    test "Carrot nose: 2 essence put the pumpkin on the next ruby space" do
      g = game(:carrot_nose) |> put(essence: 3) |> force_draws([{:orange, 1}])
      assert Game.phase(g, 0) == :essence_offer
      assert Game.legal_actions(g) == [{:essence, :carrot}, {:essence, :pass}]
      g = apply!(g, {:essence, :carrot})
      assert me(g).drawn == [{{:orange, 1}, 5}] and me(g).pot_index == 5 and me(g).essence == 1
      assert logged?(g, {:essence_spent, 2, :carrot}) and Game.phase(g, 0) == :potions

      g = game(:carrot_nose) |> put(essence: 1) |> force_draws([{:orange, 1}])
      assert Game.phase(g, 0) == :potions
    end

    test "Wing ears: double for 2, return for 3, nothing when it explodes" do
      g = game(:wing_ears) |> put(essence: 3) |> force_draws([{:white, 2}])

      assert Game.legal_actions(g) == [
               {:essence, :double},
               {:essence, :return},
               {:essence, :pass}
             ]

      g2 = apply!(g, {:essence, :double})
      assert me(g2).drawn == [{{:white, 2}, 4}] and me(g2).essence == 1

      g3 = apply!(g, {:essence, :return})
      assert me(g3).drawn == [] and {:white, 2} in me(g3).bag and me(g3).essence == 0

      g = game(:wing_ears) |> put(essence: 2) |> force_draws([{:white, 2}])
      assert Game.legal_actions(g) == [{:essence, :double}, {:essence, :pass}]

      g = game(:wing_ears) |> put(essence: 3) |> brew([{:white, 3}, {:white, 3}])
      g = force_draws(g, [{:white, 2}])
      assert Game.phase(g, 0) == :explosion_choice and me(g).essence_pending == nil
    end

    test "Witch's hump: a chip on a ruby space, 2 essence, the table's bonus" do
      g = game(:witch_hump) |> put(essence: 2) |> force_draws([{:white, 2}, {:white, 2}])
      assert Game.phase(g, 0) == :potions
      g = force_draws(g, [{:orange, 1}])
      assert me(g).pot_index == 5 and Game.phase(g, 0) == :essence_offer
      rubies = me(g).rubies
      g = apply!(g, {:essence, :hump})
      assert me(g).rubies == rubies + 1 and me(g).essence == 0
      assert logged?(g, {:essence_spent, 2, :hump}) and logged?(g, {:essence_bonus, {:rubies, 1}})
    end

    test "Forgetfulness: a coloured chip back for its value" do
      g = game(:forgetfulness) |> put(essence: 2) |> force_draws([{:orange, 1}, {:red, 1}])
      legal = Game.legal_actions(g)

      assert {:essence, {:forget, {:red, 1}}} in legal and
               {:essence, {:forget, {:orange, 1}}} in legal

      g = apply!(g, {:essence, {:forget, {:red, 1}}})
      assert me(g).drawn == [{{:orange, 1}, 1}] and me(g).pot_index == 1 and me(g).essence == 1
      assert {:red, 1} in me(g).bag and logged?(g, {:essence_spent, 1, {:forget, {:red, 1}}})

      g = game(:forgetfulness) |> put(essence: 1) |> force_draws([{:white, 1}, {:red, 2}])
      refute Enum.any?(Game.legal_actions(g), &match?({:essence, {:forget, _}}, &1))
    end
  end

  test "both expansions together reach :over with bots" do
    for seed <- 1..3, profiles <- [[:balanced], [:balanced, :reckless, :cautious]] do
      {g, rounds} =
        Sim.play(profiles, {seed, 2, 3},
          expansions: [:herb_witches, :alchemists],
          sets: %{locoweed: 3}
        )

      assert Game.over?(g) and Map.keys(rounds) == Enum.to_list(1..9)
      assert Enum.any?(g.log, &match?({_, {:essence_vp, _}}, &1))
    end
  end
end
