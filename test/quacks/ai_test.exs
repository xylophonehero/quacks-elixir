defmodule Quacks.AITest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Quacks.GameHelpers

  alias Quacks.AI
  alias Quacks.AI.{Names, Odds, Profile, Sim}
  alias Quacks.Game

  doctest AI
  doctest Odds
  doctest Names

  @seed {1, 2, 3}

  defp decide(game, seat, name \\ :balanced),
    do: AI.decide(game, seat, Profile.get(name), :rand.seed_s(:exsss, {9, 9, 9}))

  defp action(game, seat \\ 0, name \\ :balanced) do
    {action, _rng} = decide(game, seat, name)
    action
  end

  describe "Odds.bust/3" do
    test "counts the whites that push the sum over the limit" do
      bag = [{:white, 1}, {:white, 1}, {:white, 1}, {:white, 3}, {:green, 1}]
      assert Odds.bust(bag, 5, 7) == 0.2
      assert Odds.bust(bag, 7, 7) == 0.8
      assert Odds.bust(bag, 4, 7) == 0.0
      assert Odds.bust(bag, 5, 9) == 0.0
    end

    test "is 0 for an empty bag or a bag without whites" do
      assert Odds.bust([], 7, 7) == 0.0
      assert Odds.bust([{:orange, 1}, {:red, 2}], 7, 7) == 0.0
    end
  end

  test "Profile has three named profiles" do
    assert Profile.all() == [:cautious, :balanced, :reckless]
    assert Profile.names().balanced == "Steady Sam"

    assert %Profile{name: :reckless, bot_name: "Bold Bruno", label: "Reckless"} =
             Profile.get(:reckless)

    for name <- Profile.all(), do: assert(map_size(Profile.get(name).max_bust) == 9)
  end

  test "draws when no chip can explode, stops at bad odds" do
    game = Game.new(seed: @seed, fortune: false) |> force_draws([{:white, 3}, {:white, 2}])
    assert action(put(game, bag: [{:white, 1}, {:orange, 1}])) == :draw
    assert action(put(game, bag: [{:white, 3}, {:white, 3}, {:orange, 1}])) == :stop
  end

  test "uses the flask on a white 3 when the odds are good again after it" do
    game =
      Game.new(seed: @seed, fortune: false)
      |> force_draws([{:white, 2}, {:white, 2}, {:white, 3}])
      |> put(bag: [{:white, 1}, {:white, 1}, {:white, 2}, {:orange, 1}])

    assert action(game) == :use_flask
  end

  test "yellow returns the white; blue places the coloured chip" do
    game = Game.new(seed: @seed, fortune: false) |> force_draws([{:white, 1}])
    assert action(put(game, phase: :yellow_choice)) == :return_white

    blue = put(game, phase: :blue_choice, pending: [{:white, 3}, {:orange, 1}, {:red, 2}])
    assert action(blue) == {:place, {:red, 2}}

    whites = put(game, phase: :blue_choice, pending: [{:white, 3}, {:white, 1}])
    assert action(whites) == {:place, {:white, 3}}

    full = game |> force_draws([{:white, 3}, {:white, 3}])
    assert action(put(full, phase: :blue_choice, pending: [{:white, 2}])) == :return_all
  end

  test "explosion: coins early, VP late, always VP in round 9" do
    boom =
      Game.new(seed: @seed, fortune: false)
      |> force_draws([{:white, 3}, {:white, 3}, {:white, 2}])

    assert Game.phase(boom, 0) == :explosion_choice
    assert action(boom) == {:explosion_choice, :buy}
    assert action(put(boom, round: 7)) == {:explosion_choice, :vp}
    assert action(put(boom, round: 9), 0, :reckless) == {:explosion_choice, :vp}
  end

  test "the shop buys two chips when it can, then rubies, then ends" do
    game =
      Game.new(seed: @seed, fortune: false) |> put(round: 4, phase: :buy, coins: 20, rubies: 3)

    assert {:buy, [_, _]} = action(game)

    after_buy = put(game, bought?: true)
    assert action(after_buy) == {:rubies, :droplet}
    assert action(put(after_buy, rubies: 0)) == :end_round
  end

  test "reverse pot side: droplets and ruby droplets go to the test tube until glass 12" do
    game =
      Game.new(seed: @seed, rules: %{fortune: false, pot_side: :back})
      |> put(round: 4, phase: :buy, coins: 20, rubies: 3)

    assert action(put(game, droplet_moves: 1)) == {:droplet, :tube}
    assert action(put(game, bought?: true)) == {:rubies, :tube}
    assert action(put(game, bought?: true, tube: 12)) == {:rubies, :droplet}
  end

  test "round 9 shop turns rubies into VP, then ends" do
    game = Game.new(seed: @seed, fortune: false) |> put(round: 9, phase: :shop, rubies: 3)
    assert action(game) == {:rubies, :vp}
    assert action(put(game, rubies: 1)) == :end_round
  end

  test "a fortune choice is legal and never a dominated skip" do
    game = Game.new(seed: @seed, fortune: false, players: 2)

    p6 =
      %{game | phase: :fortune_choice, fortune_card: :p6}
      |> put(0, phase: :fortune_choice)

    for seed <- 1..20 do
      {action, _} = AI.decide(p6, 0, Profile.get(:balanced), :rand.seed_s(:exsss, {seed, 0, 0}))
      assert action in Game.legal_actions(p6, 0)
    end

    p13 =
      %{game | phase: :fortune_choice, fortune_card: :p13}
      |> put(0, phase: :fortune_choice, pending: [{:red, 1}])

    assert {:fortune, {:upgrade, _}} = action(p13)
  end

  test "a stopped seat waits; a seat without actions gets :none" do
    game = Game.new(seed: @seed, players: 2, fortune: false) |> force_draws(0, [{:orange, 1}])
    game = game |> force_draws(1, [{:orange, 1}]) |> apply!(0, :stop)
    assert Game.legal_actions(game, 0) == [:resume]
    assert decide(game, 0) == :none
    assert decide(put(game, 0, phase: :done), 0) == :none
  end

  test "decide/4 is legal in 200 random game states" do
    states =
      for seed <- 1..40, steps <- [0, 30, 90, 200, 400] do
        rng = :rand.seed_s(:exsss, {seed, steps, 1})
        {i, rng} = :rand.uniform_s(4, rng)
        sets = Enum.at([%{}, %{blue: 2, red: 2, yellow: 3}, %{red: 6, yellow: 6}, %{}], i - 1)

        expansions =
          Enum.at(
            [[:herb_witches], [], [:alchemists], [:herb_witches, :alchemists]],
            rem(div(seed, 4), 4)
          )

        game =
          Game.new(
            seed: {seed, 2, 3},
            players: rem(seed, 4) + 1,
            sets: sets,
            expansions: expansions
          )

        {game, _} = random_play(game, steps, rng)
        game
      end

    assert length(states) == 200

    for game <- states, seat <- game.seats, name <- Profile.all() do
      legal = Game.legal_actions(game, seat)

      case decide(game, seat, name) do
        :none -> assert legal in [[], [:resume]]
        {action, _rng} -> assert action in legal
      end
    end
  end

  property "any profile mix and seed reaches :over with only legal actions" do
    check all(
            profiles <- list_of(member_of(Profile.all()), min_length: 1, max_length: 5),
            seed <- tuple({positive_integer(), positive_integer(), positive_integer()}),
            sets <- member_of([%{}, %{green: 2, blue: 4, red: 3}, %{red: 2, yellow: 6}]),
            expansions <-
              member_of([[], [:herb_witches], [:alchemists], [:herb_witches, :alchemists]]),
            max_runs: 30
          ) do
      # `Sim.play/3` applies with `{:ok, _} =`, so an illegal action fails the match.
      {game, rounds} = Sim.play(profiles, seed, sets: sets, expansions: expansions)
      assert Game.over?(game)
      assert Map.keys(rounds) == Enum.to_list(1..9)
    end
  end

  test "Sim.run/1 sums up per profile" do
    summary = Sim.run(games: 4, profiles: [:balanced, :cautious], seed: 3)
    assert %{games: 4, players: 2, profiles: %{balanced: b, cautious: c}} = summary
    assert b.seats == 4 and c.seats == 4
    assert_in_delta b.win_rate + c.win_rate, 1.0, 1.0e-9
    assert Map.keys(b.explosions) == Enum.to_list(1..9)
    assert Map.keys(b.coins) == Enum.to_list(1..9)
    assert is_map(b.buys)
    assert summary == Sim.run(games: 4, profiles: [:balanced, :cautious], seed: 3)
  end
end
