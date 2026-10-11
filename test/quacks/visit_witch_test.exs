defmodule Quacks.VisitWitchTest do
  @moduledoc "AB8 Visit from a witch (The Alchemists box, needs The Herb Witches)."
  use ExUnit.Case, async: true

  import Quacks.GameHelpers

  alias Quacks.{AI, Game}
  alias Quacks.AI.{Profile, Sim}
  alias Quacks.Game.Fortune
  alias Quacks.Rules.Witches, as: WitchCards

  @seed {1, 2, 3}

  defp new(players \\ 1, seed \\ @seed),
    do: Game.new(seed: seed, players: players, fortune: false, expansions: [:herb_witches])

  # Round 1 turns up AB8.
  defp visited(players \\ 1, seed \\ @seed),
    do: new(players, seed) |> put(fortune_deck: [:ab8]) |> Fortune.draw()

  # The game with the witch `id` as this round's visitor (her colour's own witch
  # stays in play).
  defp visitor(g, id), do: %{g | visitor: id, fortune_card: :ab8}

  defp visit_actions(g, seat \\ 0),
    do:
      Enum.filter(
        Game.legal_actions(g, seat),
        &(match?({:witch, :visit} = &1, &1) or match?({:witch, :visit, _}, &1))
      )

  describe "the draw" do
    test "a random witch that is not in play visits; the log says who" do
      g = visited()
      assert g.fortune_card == :ab8
      assert g.visitor in WitchCards.ids()
      refute g.visitor in Map.values(g.witches)
      assert {:visitor, g.visitor} in g.log
      # The draw uses the game's rng.
      refute g.rng == new().rng
      assert visited().visitor == g.visitor
    end

    test "she can be of any colour" do
      colours =
        for i <- 1..60, uniq: true do
          g = visited(1, {i, i, i})
          refute g.visitor in Map.values(g.witches)
          WitchCards.card(g.visitor).colour
        end

      assert Enum.sort(colours) == [:copper, :gold, :silver]
    end

    test "only in a deck with The Herb Witches; without them nobody visits" do
      g = Game.new(seed: @seed, players: 2) |> put(fortune_deck: [:ab8]) |> Fortune.draw()
      assert g.fortune_card == :ab8 and g.visitor == nil
    end

    test "she leaves at the end of the round" do
      g = new() |> visitor(:c2) |> force_draws([{:orange, 1}]) |> apply!(:stop)
      g = g |> apply!({:buy, []}) |> apply!(:end_round)
      assert g.round == 2 and g.visitor == nil
      assert {:visitor_left, :c2} in g.log
      assert g.visited == []
      assert visit_actions(put(g, phase: :buy, coins: 5)) == []
    end
  end

  describe "the free call" do
    test "every seat may call her once, without a penny" do
      g = new(2) |> visitor(:c2) |> put(0, phase: :buy, coins: 5) |> put(1, coins: 3)
      assert {:witch, :visit} in Game.legal_actions(g, 0)
      assert {:witch, :visit} in Game.legal_actions(g, 1)

      g = apply!(g, 0, {:witch, :visit})
      assert me(g).coins == 10 and g.visited == [0]
      assert me(g).pennies == %{silver: true, copper: true, gold: true}
      assert {0, {:witch, :c2, {:coins, 10}}} in g.log
      assert visit_actions(g, 0) == []
      # The own copper witch is still there for the penny.
      own = g.witches.copper

      if own in [:c2, :c4] do
        assert Enum.any?(Game.legal_actions(g, 0), &match?({:witch, :copper}, &1))
      end

      g = apply!(g, 1, {:witch, :visit})
      assert me(g, 1).coins == 6
    end

    test "with a penny already spent on that colour she still comes" do
      g =
        new()
        |> visitor(:c4)
        |> put(phase: :buy, rubies: 2, pennies: %{silver: true, copper: false, gold: true})

      g = apply!(g, {:witch, :visit})
      assert me(g).coins == 4 and me(g).pennies.copper == false
    end

    test "a choice of her colour: S3 returns whites, C1 upgrades, C3 copies" do
      g = new() |> visitor(:s3) |> force_draws([{:white, 1}, {:white, 2}])
      assert {:witch, :visit, 1} in visit_actions(g) and {:witch, :visit, 2} in visit_actions(g)
      g = apply!(g, {:witch, :visit, 2})
      assert Game.white_sum(g) == 0 and {0, {:witch, :s3, {:return_white, 2}}} in g.log

      g = new() |> visitor(:c1) |> put(phase: :buy, drawn: [{{:green, 1}, 3}, {{:orange, 1}, 1}])
      g = apply!(g, {:witch, :visit, {:upgrade, [{:green, 1}]}})
      assert {:green, 2} in me(g).bag

      g = new() |> visitor(:c3) |> put(phase: :buy, coins: 3)
      g = apply!(g, {:witch, :visit, {:buy, [{:orange, 1}], {:orange, 1}}})
      assert me(g).bought? and me(g).pennies.copper
    end

    test "S2: her offer of 6 chips works as the own silver witch's" do
      g = new() |> visitor(:s2) |> apply!({:witch, :visit})
      assert length(me(g).witch_offer) == 6
      assert {:witch, :silver, :return_all} in Game.legal_actions(g)
      g = apply!(g, {:witch, :silver, :return_all})
      assert me(g).witch_offer == [] and me(g).pennies.silver
    end
  end

  describe "timing by colour" do
    test "silver: while brewing (S2, S3) or in the explosion choice (S1, S4)" do
      g = new() |> visitor(:s4)
      assert visit_actions(g) == []
      g = force_draws(g, [{:white, 3}, {:white, 3}, {:white, 2}])
      assert Game.phase(g, 0) == :explosion_choice
      assert visit_actions(g) == [{:witch, :visit}]
      g = apply!(g, {:witch, :visit})
      assert me(g).explosion_choice == :witch and me(g).pennies.silver
      # Not in the shop.
      assert visit_actions(put(g, phase: :buy)) == []
    end

    test "copper: in the shop, not while brewing" do
      g = new() |> visitor(:c2) |> put(coins: 4)
      assert visit_actions(g) == []
      assert visit_actions(put(g, phase: :buy)) == [{:witch, :visit}]
    end

    test "gold: G1–G3 after step B, G4 in the shop" do
      g = new() |> visitor(:g1)
      g = g |> force_draws([{:orange, 1}, {:green, 1}]) |> apply!(:stop)
      assert g.phase == :witch_choice
      assert {:witch, :visit} in Game.legal_actions(g)
      vp = me(g).vp
      g = apply!(g, {:witch, :visit})
      assert me(g).vp == vp + 3 and me(g).pennies.gold

      g = new() |> visitor(:g4) |> put(phase: :buy)
      g = apply!(g, {:witch, :visit})
      assert me(g).ruby_price == 1
    end

    test "both gold witches in one evaluation: the seat calls one, then the other" do
      g = %{new() | witches: %{silver: :s1, copper: :c1, gold: :g1}} |> visitor(:g2)
      g = g |> force_draws([{:orange, 1}, {:green, 1}]) |> put(bag: [{:blue, 2}]) |> apply!(:stop)
      assert g.phase == :witch_choice
      assert Game.legal_actions(g) == [{:witch, :gold}, {:witch, :visit}, :witch_done]
      g = apply!(g, {:witch, :gold})
      assert g.phase == :witch_choice and Game.legal_actions(g) == [{:witch, :visit}, :witch_done]
      g = apply!(g, {:witch, :visit})
      assert {0, {:witch, :g1, {:vp, 3}}} in g.log and {0, {:witch, :g2, {:vp, 2}}} in g.log
      assert Game.phase(g, 0) == :shop
    end
  end

  describe "solo and bots" do
    test "AB8 is in a solo deck with The Herb Witches, and works there" do
      assert :ab8 in Quacks.Rules.Fortune.ids(1, [:herb_witches])
      g = visited(1)
      assert g.visitor != nil
    end

    test "a bot calls a free visiting witch that only gains" do
      profile = Profile.get(:balanced)
      g = new(2) |> visitor(:c2) |> put(1, phase: :buy, coins: 5)
      assert {{:witch, :visit}, _rng} = AI.decide(g, 1, profile, AI.new_rng(@seed, 1))

      g = new(2) |> visitor(:s4) |> force_draws(1, [{:white, 3}, {:white, 3}, {:white, 2}])
      assert {{:witch, :visit}, _rng} = AI.decide(g, 1, profile, AI.new_rng(@seed, 1))

      g = new(2) |> visitor(:g1) |> force_draws(1, [{:orange, 1}, {:green, 1}])
      g = g |> force_draws(0, [{:orange, 1}]) |> apply!(0, :stop) |> apply!(1, :stop)
      assert {{:witch, :visit}, _rng} = AI.decide(g, 1, profile, AI.new_rng(@seed, 1))
    end

    test "bots play whole games with AB8 and The Herb Witches" do
      logs =
        for n <- 1..20 do
          {g, _rounds} =
            Sim.play([:balanced, :cautious, :balanced], {n, 5, 7}, expansions: [:herb_witches])

          assert Game.over?(g)
          g.log
        end

      assert Enum.any?(logs, fn log -> Enum.any?(log, &match?({:visitor, _}, &1)) end)
      assert Enum.any?(logs, fn log -> Enum.any?(log, &match?({_, {:witch, :visit}}, &1)) end)
    end
  end
end
