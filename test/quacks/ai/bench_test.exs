defmodule Quacks.AI.BenchTest do
  use ExUnit.Case, async: true

  alias Quacks.AI.{Bench, Profile, Tune, Weights}

  doctest Bench
  doctest Weights

  defp profile(text) do
    {:ok, profile} = Profile.parse(text)
    profile
  end

  describe "Bench.run/1" do
    test "plays every seed once per rotation and pools seats by name" do
      result = Bench.run(bots: [:balanced, :cautious], players: 4, games: 6, jobs: 2)

      assert result.games == 6
      assert result.seeds == 3
      assert [%{name: :balanced, seats: 12}, %{name: :cautious, seats: 12}] = result.bots
      assert_in_delta Enum.sum(Enum.map(result.bots, &(&1.win_rate * &1.seats))), 6, 1.0e-9
      assert Enum.all?(result.bots, &(is_float(&1.win_ci) and &1.vp_mean > 0))
    end

    test "the same seed gives the same result; jobs do not matter" do
      opts = [bots: [profile("balanced+strong"), :balanced], games: 8, seed: 5]
      a = Bench.run([jobs: 1] ++ opts)
      b = Bench.run([jobs: 3] ++ opts)
      strip = fn r -> Enum.map(r.bots, &Map.drop(&1, [:decisions])) end
      assert strip.(a) == strip.(b)
    end

    test "two equal bots are exactly at parity (duplicate seating)" do
      p = Profile.get(:balanced)
      result = Bench.run(bots: [p, %{p | name: :twin}], players: 2, games: 10, jobs: 2)
      assert Enum.map(result.bots, & &1.win_rate) == [0.5, 0.5]
    end

    test "counts the decisions per phase and their time" do
      %{bots: [bot]} = Bench.run(bots: [:balanced], players: 2, games: 1, jobs: 1)
      assert %{potions: %{n: n, us_mean: us}, shop: %{n: _}} = bot.decisions
      assert n > 10 and us >= 0
    end

    test "a time budget of 0 plays nothing" do
      assert %{games: 0} = Bench.run(bots: [:balanced], games: 10, minutes: 0, jobs: 1)
    end
  end

  describe "the strong policy" do
    test "is the EV draw/stop rule plus the scored choices" do
      p = profile("balanced+strong")

      assert {p.name, p.stop_rule, p.choice_rule, p.flask_rule} ==
               {:"balanced+strong", :ev, :scored, :heuristic}
    end

    test "plays a legal game to the end against the table bot" do
      %{games: 2, bots: [strong, _]} =
        Bench.run(bots: [profile("balanced+strong"), :balanced], games: 2, jobs: 1)

      assert strong.seats == 2
    end
  end

  describe "Weights" do
    test "a weights file round-trips through Profile.parse/1", %{} do
      path =
        Path.join(System.tmp_dir!(), "quacks-weights-#{System.unique_integer([:positive])}.json")

      base = profile("balanced+strong")
      tuned = %{base | ruby_value: 1.75, explode_vp_from: 5}
      :ok = Weights.save(path, "balanced+strong", tuned, %{note: "test"})

      assert {:ok, loaded} = Profile.parse("file:" <> path)
      assert loaded.ruby_value == 1.75 and loaded.explode_vp_from == 5
      assert loaded.stop_rule == :ev and loaded.choice_rule == :scored
      assert loaded.name == path |> Path.basename(".json") |> String.to_atom()
      File.rm!(path)
    end

    test "a missing file is an error" do
      assert {:error, "cannot read " <> _} = Profile.parse("file:/no/such/file.json")
    end
  end

  describe "Tune.run/1" do
    @tag :tmp_dir
    test "writes a checkpoint and the weights, and resumes from the checkpoint", %{tmp_dir: dir} do
      opts = [
        checkpoint: Path.join(dir, "ck.json"),
        out: Path.join(dir, "tuned.json"),
        population: 2,
        elite: 1,
        seeds: 2,
        jobs: 2
      ]

      assert %{"generation" => 1} = Tune.run([generations: 1] ++ opts)
      assert {:ok, %{name: :tuned}} = Profile.parse("file:" <> opts[:out])
      assert %{"generation" => 2, "history" => [_, _]} = Tune.run([generations: 2] ++ opts)
    end
  end
end
