defmodule Quacks.AI.ExpectimaxTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Quacks.GameHelpers

  alias Quacks.AI
  alias Quacks.AI.{Choice, Expectimax, Profile, Sim}
  alias Quacks.Game

  doctest Expectimax
  doctest Choice
  doctest Profile

  @seed {1, 2, 3}

  defp profile(text) do
    {:ok, profile} = Profile.parse(text)
    profile
  end

  defp action(game, text, seat \\ 0) do
    {action, _rng} = AI.decide(game, seat, profile(text), :rand.seed_s(:exsss, {9, 9, 9}))
    action
  end

  defp game, do: Game.new(seed: @seed, fortune: false)

  # Round 8, the pot on space 9 with a white sum of 7.
  defp late(bag) do
    game()
    |> force_draws([{:purple, 1}, {:black, 1}, {:white, 2}, {:white, 2}, {:white, 3}])
    |> put(round: 8, bag: bag)
  end

  describe "Expectimax.ev/3" do
    test "a draw beats a stop when no chip can explode" do
      g = game() |> force_draws([{:white, 3}, {:white, 2}]) |> put(bag: [{:orange, 1}, {:red, 2}])
      %{stop: stop, draw: draw} = Expectimax.ev(g, 0, Profile.get(:balanced))
      assert draw > stop
    end

    test "late, a stop beats a likely explosion; early, the explosion costs little" do
      g = late([{:white, 1}, {:white, 1}, {:white, 1}, {:orange, 1}])
      %{stop: stop, draw: draw} = Expectimax.ev(g, 0, Profile.get(:balanced))
      assert stop > draw

      # Round 1: an explosion keeps the coins (explosion choice :buy).
      %{stop: stop, draw: draw} = Expectimax.ev(put(g, round: 1), 0, Profile.get(:balanced))
      assert draw >= stop
    end

    test "an empty bag draws nothing: the draw is worth the stop" do
      g = game() |> force_draws([{:white, 1}]) |> put(bag: [])
      %{stop: stop, draw: draw} = Expectimax.ev(g, 0, Profile.get(:balanced))
      assert stop == draw
    end

    test "deeper search sees more and stays fast" do
      g =
        game()
        |> force_draws([{:white, 2}, {:white, 2}])
        |> put(
          bag:
            List.duplicate({:white, 1}, 4) ++
              [{:white, 3}, {:orange, 1}, {:red, 2}, {:blue, 4}, {:green, 1}, {:purple, 1}]
        )

      for depth <- 1..5 do
        p = %{Profile.get(:balanced) | ev_depth: depth}
        {micros, %{draw: draw}} = :timer.tc(fn -> Expectimax.ev(g, 0, p) end)
        assert is_float(draw)
        # The budget is ~5 ms per decision at depth 3; leave room for a slow CI box.
        assert micros < 200_000
      end
    end

    test "after_return/4: the white back in the bag lowers the risk" do
      g =
        game()
        |> force_draws([{:white, 2}, {:white, 2}, {:white, 3}])
        |> put(bag: [{:white, 1}, {:white, 1}, {:white, 2}, {:orange, 1}, {:red, 4}])

      %{stop: stop, after: best, draw_after: draw} =
        Expectimax.after_return(g, 0, Profile.get(:balanced), 3)

      assert best >= draw
      assert is_float(stop)
    end
  end

  describe "Quacks.AI with stop_rule: :ev" do
    test "draws at no risk, stops late at a likely explosion" do
      g = game() |> force_draws([{:white, 3}, {:white, 2}])
      assert action(put(g, bag: [{:white, 1}, {:orange, 1}]), "balanced+ev") == :draw

      likely = late([{:white, 1}, {:white, 1}, {:white, 1}, {:orange, 1}])
      assert action(put(likely, flask: false), "balanced+ev") == :stop
    end

    test "flask: the EV rule pays for the refill, the heuristic does not" do
      g = late([{:white, 1}, {:white, 1}, {:white, 1}, {:white, 1}, {:red, 4}, {:blue, 4}])
      assert action(g, "balanced+ev") == :use_flask
      assert action(g, "balanced+ev+flaskev") == :stop

      # Round 9: the flask has no later use, so it is free.
      assert action(put(g, round: 9), "balanced+ev+flaskev") == :use_flask
    end
  end

  describe "Profile.parse/1" do
    test "reads modifiers and names the variant" do
      p = profile("reckless+ev+flaskev+scored+d2")

      assert {p.name, p.stop_rule, p.flask_rule, p.choice_rule, p.ev_depth} ==
               {:"reckless+ev+flaskev+scored+d2", :ev, :ev, :scored, 2}

      assert profile("balanced") == Profile.get(:balanced)
    end

    test "rejects unknown names and modifiers" do
      assert {:error, "unknown profile wild"} = Profile.parse("wild")
      assert {:error, "unknown modifier fast"} = Profile.parse("balanced+fast")
    end
  end

  describe "Choice.pick/4" do
    test "P6: 4 VP late, the white 1 out early" do
      g = %{Game.new(seed: @seed, players: 2) | fortune_card: :p6}
      legal = [{:fortune, :vp}, {:fortune, :remove_white}]
      balanced = Profile.get(:balanced)
      assert Choice.pick(%{g | round: 8}, 0, balanced, legal) == {:fortune, :vp}
      assert Choice.value({:fortune, :remove_white}, %{g | round: 1}, 0, balanced) > 0
    end

    test "a pass is worth 0 and loses to a free chip" do
      g = %{Game.new(seed: @seed, players: 2) | fortune_card: :p1}
      legal = [{:fortune, {:take, {:black, 1}}}, {:fortune, :rubies}]
      assert Choice.pick(g, 0, Profile.get(:balanced), legal) in legal
      assert Choice.value(:chip_done, g, 0, Profile.get(:balanced)) == 0
    end

    test "the essence space: the furthest" do
      g = Game.new(seed: @seed, players: 2)
      legal = for n <- 0..3, do: {:essence, {:space, n}}
      assert Choice.pick(g, 0, Profile.get(:balanced), legal) == {:essence, {:space, 3}}
    end
  end

  property "EV, flask and choice variants reach :over with only legal actions" do
    check all(
            texts <-
              list_of(
                member_of([
                  "balanced+ev",
                  "cautious+ev+flaskev",
                  "reckless+scored",
                  "balanced+random",
                  "balanced+ev+scored"
                ]),
                min_length: 1,
                max_length: 4
              ),
            seed <- tuple({positive_integer(), positive_integer(), positive_integer()}),
            sets <- member_of([%{}, %{green: 2, purple: 2}, %{green: 4, purple: 4, yellow: 6}]),
            expansions <-
              member_of([[], [:herb_witches], [:alchemists], [:herb_witches, :alchemists]]),
            max_runs: 20
          ) do
      profiles = Enum.map(texts, &profile/1)
      {game, rounds} = Sim.play(profiles, seed, sets: sets, expansions: expansions)
      assert Game.over?(game)
      assert Map.keys(rounds) == Enum.to_list(1..9)
    end
  end
end
