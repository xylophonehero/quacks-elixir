defmodule Quacks.HouseRulesTest do
  use ExUnit.Case, async: true

  import Quacks.GameHelpers

  alias Quacks.{Game, Session}
  alias Quacks.Game.{Evaluation, Potions}

  @seed {1, 2, 3}

  defp new(rules, players \\ 1),
    do: Game.new(seed: @seed, players: players, rules: Map.put_new(rules, :fortune, false))

  test "the defaults are the rulebook game" do
    assert Game.new(seed: @seed).rules == Game.default_rules()
    assert Game.default_rules().explode_above == 7
  end

  test "fortune: false is an alias for rules: %{fortune: false}" do
    old = Game.new(seed: @seed, fortune: false)
    assert old.rules.fortune == false and old.fortune_deck == [] and old.fortune_card == nil
    assert old == Game.new(seed: @seed, rules: %{fortune: false})
    assert Game.new(seed: @seed, fortune: false, rules: %{fortune: true}).fortune_card != nil
  end

  test "an unknown rule or a bad value raises" do
    assert_raise ArgumentError, fn -> Game.new(seed: @seed, rules: %{nope: 1}) end
    assert_raise ArgumentError, fn -> Game.new(seed: @seed, rules: %{explode_above: 12}) end
  end

  test "explode_above: 9 explodes at white 10, not at 8 or 9" do
    nine = new(%{explode_above: 9})
    safe = force_draws(nine, [{:white, 3}, {:white, 3}, {:white, 3}])
    refute me(safe).exploded?
    assert Potions.explode_above(safe, 0) == 9

    assert me(force_draws(safe, [{:white, 1}])).exploded?
  end

  test "explode_above: 5 explodes at white 6; Y3 and B5 still raise it" do
    five = new(%{explode_above: 5})
    assert me(force_draws(five, [{:white, 3}, {:white, 3}])).exploded?

    yellow = Game.new(seed: @seed, sets: %{yellow: 3}, rules: %{explode_above: 5, fortune: false})
    assert Potions.explode_above(force_draws(yellow, [{:yellow, 1}]), 0) == 8
    assert Potions.explode_above(put(five, fortune_card: :b5), 0) == 9
  end

  test "round6_white: false adds no white chip before round 6" do
    g = new(%{round6_white: false}) |> put(round: 5, phase: :rubies) |> apply!(:end_round)
    assert g.round == 6
    assert Enum.count(me(g).bag, &(&1 == {:white, 1})) == 4
  end

  test "rats: false gives nobody a head start" do
    g =
      new(%{rats: false}, 2)
      |> put(0, vp: 12)
      |> put(1, vp: 3)
      |> put(phase: :rubies)
      |> apply!(0, :end_round)
      |> apply!(1, :end_round)

    assert g.round == 2 and me(g, 1).rat_stone == 0
    refute Enum.any?(g.log, &match?({_, {:rats, _}}, &1))
  end

  test "black_solo: :droplet_ruby pays droplet +1 and 1 ruby" do
    g =
      new(%{black_solo: :droplet_ruby})
      |> put(
        phase: :explosion_choice,
        exploded?: true,
        drawn: [{{:white, 2}, 2}, {{:black, 1}, 1}],
        pot_index: 0
      )
      |> apply!({:explosion_choice, :buy})

    assert {me(g).droplet, me(g).rubies} == {1, 2}
    assert {0, {:black, :droplet_ruby}} in g.log
  end

  test "die: :no_orange rolls a ruby where the orange face was" do
    faces = fn rules ->
      g = new(rules)

      for i <- 1..300,
          do: elem(Evaluation.roll(%{g | rng: :rand.seed_s(:exsss, {i, i, i})}, 0), 0)
    end

    assert :orange in faces.(%{})
    no_orange = faces.(%{die: :no_orange})
    refute :orange in no_orange
    assert Enum.count(no_orange, &(&1 == :ruby)) > Enum.count(faces.(%{}), &(&1 == :ruby))
  end

  test "starting_rubies: 0 starts every player without rubies" do
    g = new(%{starting_rubies: 0}, 3)
    assert Enum.all?(g.seats, &(me(g, &1).rubies == 0))
  end

  test "a session keeps its rules through undo" do
    s = Session.new(@seed, 1, rules: %{explode_above: 9, fortune: false})
    {:ok, s} = Session.apply(s, :draw)
    assert Session.undo(s).game.rules.explode_above == 9
  end
end
