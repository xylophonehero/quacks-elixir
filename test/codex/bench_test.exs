defmodule Codex.AI.BenchTest do
  @moduledoc "The Codex bot benchmark: duplicate seating, determinism, the stats."
  use ExUnit.Case, async: true

  alias Codex.AI.Bench

  doctest Codex.AI.Bench

  test "the same bot in both seats is at exact parity (duplicate seating)" do
    r = Bench.run(bots: ["basic", "basic"], games: 8, seed: 3, jobs: 2)
    assert r.games == 8
    assert r.seeds == 4
    [a, b] = r.bots
    assert a.win_rate == 0.5
    assert b.win_rate == 0.5
    # A's P1 games are B's P1 games, with the same cards.
    assert a.seat[0].win_rate == b.seat[0].win_rate
    assert a.seat[1].win_rate == b.seat[1].win_rate
  end

  test "the same options give the same numbers, for any number of jobs" do
    one = Bench.run(bots: ["basic", "basic"], games: 6, seed: 9, jobs: 1)
    three = Bench.run(bots: ["basic", "basic"], games: 6, seed: 9, jobs: 3)
    strip = fn r -> r |> Map.drop([:seconds, :jobs]) |> Map.update!(:bots, &drop_times/1) end
    assert strip.(one) == strip.(three)
  end

  test "the search bot with no clock: the same numbers for any number of jobs" do
    run = fn jobs ->
      Bench.run(bots: ["search4:threat_base=0.5", "plan"], games: 4, seed: 2, jobs: jobs)
    end

    strip = fn r -> r |> Map.drop([:seconds, :jobs]) |> Map.update!(:bots, &drop_times/1) end
    assert strip.(run.(1)) == strip.(run.(2))
  end

  defp drop_times(bots), do: Enum.map(bots, &Map.drop(&1, [:ms, :ms_max]))

  test "the stats per bot" do
    r = Bench.run(bots: ["basic", "basic"], games: 4, seed: 1, jobs: 2)
    [a, _] = r.bots
    assert r.turns > 0
    assert a.games == 4
    assert a.workers > 4
    assert a.gold_left >= 0
    assert a.attack_left >= 0 and a.attack_left <= 1
    assert a.ms > 0
  end

  test "a bot of a spec; an unknown spec raises" do
    assert %{name: "basic", mod: Codex.Bot} = Bench.bot("basic")
    assert_raise ArgumentError, fn -> Bench.bot("nope") end
  end

  test "a plan spec with rule and weight changes" do
    bot = Bench.bot("plan-tower:threat_base=1,lethal=10")
    assert bot.state.rules.tower == false
    assert bot.state.weights.threat_base == 1.0
    assert bot.state.weights.lethal == 10.0
    assert bot.state.weights.gold == Codex.AI.Weights.defaults().gold
    assert_raise ArgumentError, fn -> Bench.bot("plan:exhaust=1") end
  end

  test "a search spec: candidates, random-step chance, no early stop, weights" do
    bot = Bench.bot("search12e0.1x-tower:threat_base=1")
    assert bot.mod == Codex.Bot.Search
    assert %{n: 12, eps: 0.1, prefix: false, budget_ms: nil} = bot.state
    assert bot.state.plan.rules.tower == false
    assert bot.state.plan.weights.threat_base == 1.0
    assert %{n: 40, eps: 0.15, prefix: true} = Bench.bot("search").state
  end
end
