defmodule Quacks.TestTubesTest do
  use ExUnit.Case, async: true

  import Quacks.GameHelpers

  alias Quacks.Game
  alias Quacks.Game.{Evaluation, Fortune}
  alias Quacks.Rules.TestTubes

  doctest TestTubes

  @seed {1, 2, 3}
  @choice [{:droplet, :pot}, {:droplet, :tube}]

  defp new(side, players \\ 1),
    do:
      Game.new(
        seed: @seed,
        players: players,
        rules: %{fortune: false, supply: :limited, pot_side: side}
      )

  # A rng whose next bonus-die roll is the droplet face.
  defp droplet_rng do
    Enum.find_value(1..200, fn i ->
      rng = :rand.seed_s(:exsss, {i, i, i})
      g = %{new(:front) | rng: rng}
      if elem(Evaluation.roll(g, 0), 0) == :droplet, do: rng
    end)
  end

  test "the 12 glasses and their bonuses" do
    assert TestTubes.last() == 12
    assert TestTubes.bonus(0) == nil

    assert Enum.map(1..12, &TestTubes.bonus/1) == [
             :ruby,
             {:vp, 1},
             {:chip, {:blue, 1}},
             {:vp, 2},
             {:chip, {:black, 1}},
             {:vp, 2},
             {:chip, {:red, 2}},
             {:vp, 3},
             {:chip, {:purple, 1}},
             {:vp, 3},
             {:chip, {:yellow, 4}},
             {:vp, 4}
           ]
  end

  test "pot_side defaults to the front and accepts only :front or :back" do
    assert Game.default_rules().pot_side == :front
    assert new(:back).rules.pot_side == :back
    assert_raise ArgumentError, fn -> new(:sideways) end
  end

  test "front side: every droplet move goes to the pot droplet at once" do
    {_face, g} = Evaluation.roll(%{new(:front) | rng: droplet_rng()}, 0)
    assert {me(g).droplet, me(g).droplet_moves, me(g).tube} == {1, 0, 0}
    assert Game.phase(g, 0) == :potions

    g = g |> put(phase: :rubies, rubies: 2)
    refute {:rubies, :tube} in Game.legal_actions(g)
    assert me(apply!(g, {:rubies, :droplet})).droplet == 2
  end

  test "back side: the die's droplet waits for a choice; the tube pays its glass" do
    {:droplet, g} = Evaluation.roll(%{new(:back) | rng: droplet_rng()}, 0)
    assert {me(g).droplet, me(g).droplet_moves} == {0, 1}
    assert Game.phase(g, 0) == :droplet_choice
    assert Game.legal_actions(g) == @choice

    rubies = me(g).rubies
    g = apply!(g, {:droplet, :tube})
    assert {me(g).tube, me(g).droplet, me(g).droplet_moves} == {1, 0, 0}
    assert me(g).rubies == rubies + 1
    assert {0, {:tube, 1, :ruby}} in g.log
    assert Game.legal_actions(g) == [:draw]
  end

  test "back side: a pot choice before the first draw moves the pot's start too" do
    g = new(:back, 2) |> put(fortune_card: :p2) |> Fortune.resolve()
    assert Enum.all?(g.seats, &(Game.legal_actions(g, &1) == @choice))

    g = apply!(g, 0, {:droplet, :pot})
    assert {me(g, 0).droplet, me(g, 0).pot_index} == {1, 1}
    assert Game.legal_actions(g, 0) == [:draw]
    # seat 1 still chooses; seat 0 already brews
    assert Game.legal_actions(g, 1) == @choice
  end

  test "back side: chip glasses put the chip in the bag" do
    g = new(:back) |> put(tube: 2, droplet_moves: 1)
    bag = me(g).bag
    g = apply!(g, {:droplet, :tube})
    assert me(g).bag == [{:blue, 1} | bag]
    assert {0, {:tube, 3, {:chip, {:blue, 1}}}} in g.log
  end

  test "back side: the shop sells a glass for 2 rubies (1 with G4)" do
    g = new(:back) |> put(phase: :rubies, rubies: 4, tube: 3)

    assert Enum.filter(Game.legal_actions(g), &match?({:rubies, _}, &1)) ==
             [{:rubies, :droplet}, {:rubies, :tube}]

    g = apply!(g, {:rubies, :tube})
    assert {me(g).rubies, me(g).tube, me(g).vp, me(g).droplet} == {2, 4, 2, 0}
    assert [{0, {:tube, 4, {:vp, 2}}}, {0, {:rubies_spent, :tube}} | _] = g.log

    g = g |> put(ruby_price: 1) |> apply!({:rubies, :tube})
    assert {me(g).rubies, me(g).tube} == {1, 5}
    assert {0, {:rubies_spent, :tube, 1}} in g.log

    # The pot droplet stays a plain buy, without a choice.
    g = apply!(g, {:rubies, :droplet})
    assert {me(g).droplet, me(g).droplet_moves} == {1, 0}
  end

  test "back side: the shop waits for the choice before the round can end" do
    g = new(:back) |> put(phase: :rubies, rubies: 0, droplet_moves: 1)
    assert Game.legal_actions(g) == @choice
    g = apply!(g, {:droplet, :pot})
    assert Game.legal_actions(g) == [:end_round]
  end

  test "glass 12 is the end: no tube buy, and moves go to the pot at once" do
    g = new(:back) |> put(tube: 12, phase: :rubies, rubies: 2)
    refute {:rubies, :tube} in Game.legal_actions(g)

    g = Game.move_droplet(g, 0, 2)
    assert {me(g).droplet, me(g).droplet_moves} == {2, 0}
  end

  test "a 2-space move on glass 11: the second move goes to the pot by itself" do
    g = new(:back) |> put(tube: 11) |> Game.move_droplet(0, 2)
    assert me(g).droplet_moves == 2

    g = apply!(g, {:droplet, :tube})
    assert {me(g).tube, me(g).droplet, me(g).droplet_moves} == {12, 1, 0}
    assert {0, {:tube, 12, {:vp, 4}}} in g.log
    assert Game.legal_actions(g) == [:draw]
  end

  test "round 9 offers no tube buy (rubies buy VP only)" do
    g = new(:back) |> put(round: 9, phase: :rubies, rubies: 2)
    assert Enum.filter(Game.legal_actions(g), &match?({:rubies, _}, &1)) == [{:rubies, :vp}]
  end

  describe "rubies with 2 players (Nick's round 4, 6, 7)" do
    # Both seats stop with one black chip each: the Hawkmoth tie (1 = 1) moves each
    # droplet once, for free. Then: the droplet choice, the buy, the rubies (tube, then pot).
    test "the free droplet move comes first, each ruby spend costs 2 once" do
      g =
        new(:back, 2)
        |> put(0,
          drawn: [{{:orange, 1}, 12}, {{:black, 1}, 11}],
          pot_index: 12,
          rubies: 5,
          tube: 1
        )
        |> put(1, drawn: [{{:black, 1}, 1}], pot_index: 1)
        |> apply!(0, :stop)
        |> apply!(1, :stop)

      assert {0, {:black, :droplet}} in g.log
      assert Game.phase(g, 0) == :droplet_choice
      assert Game.legal_actions(g, 0) == @choice

      rubies = me(g).rubies
      g = apply!(g, 0, {:droplet, :pot})
      assert me(g).rubies == rubies
      # Round 35: the ruby uses are legal in the buy step too.
      assert {:rubies, :tube} in Game.legal_actions(g, 0)

      g = apply!(g, 0, {:buy, []})
      assert {:rubies, :tube} in Game.legal_actions(g, 0)
      g = apply!(g, 0, {:rubies, :tube})
      assert {me(g).rubies, me(g).tube} == {rubies - 2, 2}
      g = apply!(g, 0, {:rubies, :droplet})
      assert me(g).rubies == rubies - 4
      assert Enum.count(g.log, &match?({0, {:rubies_spent, _}}, &1)) == 2
    end
  end
end
