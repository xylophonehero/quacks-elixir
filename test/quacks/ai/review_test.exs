defmodule Quacks.AI.ReviewTest do
  @moduledoc """
  The learn-from-Nick pipeline on a fixture: `Quacks.AI.Review` on the bug report
  bundle #89 (Nick in seat 0, three bots, round 5), `Quacks.AI.ShopFit`, the start
  positions and `Quacks.AI.Bench` from them, and `mix quacks.review`.
  """
  use ExUnit.Case, async: true

  alias Mix.Tasks.Quacks.Review, as: ReviewTask
  alias Quacks.AI.{Bench, Profile, Review, ShopFit}
  alias Quacks.{Archive, Game}

  @bundle Path.expand("../../fixtures/bundles/bug_89.json", __DIR__)

  setup_all do
    {:ok, game} = Archive.load(@bundle)
    %{game: game}
  end

  test "the steps replay the log to the same game", %{game: game} do
    steps = Review.steps(game)
    assert length(steps) == length(game.bundle["log"]) + 1
    assert {final, nil, nil} = List.last(steps)
    assert final == game.session.game
  end

  test "kinds: the decisions that had a choice" do
    assert Review.kind(:potions, :draw, [:draw, :stop]) == :draw_stop
    assert Review.kind(:potions, :draw, [:draw]) == nil
    assert Review.kind(:shop, {:buy, []}, [{:buy, []}]) == :buy
    assert Review.kind(:shop, :end_round, [:end_round, {:rubies, :droplet}]) == :rubies
    assert Review.kind(:shop, :end_round, [:end_round]) == nil
    assert Review.kind(:explosion_choice, {:explosion_choice, :vp}, [:a, :b]) == :explosion
    assert Review.kind(:fortune_choice, {:fortune, :vp}, [:a, :b]) == :choice
  end

  test "the review: style, agreement with the tuned bot and the bot mistakes", %{game: game} do
    report =
      Review.run([game], futures: 2, max_options: 2, bot_kinds: [:explosion, :buy], jobs: 2)

    assert %{reviewed: 1, finished: 0, human_decisions: h, bot_decisions: b} = report.games
    assert h > 20 and b > 60
    assert [%{id: "bug_89", humans: [0], round: 5, over: false}] = report.games.list

    # Nick's draw/stop: every one has the tuned bot's answer; stops by round
    assert %{n: n, agree: agree} = report.agreement.draw_stop
    assert n > 10 and agree <= n
    assert %{n: _, bust_mean: _, white_mean: _} = report.style.stops_by_round[1]
    assert report.style.buys_by_round |> Map.keys() |> Enum.sort() == [1, 2, 3, 4]

    # the bots' buys and explosions were rolled out; nothing else
    assert Map.keys(report.bot_mistakes.by_kind) -- [:buy, :explosion] == []
    assert %{n: buys} = report.bot_mistakes.by_kind.buy
    assert buys == 3 * 4

    for row <- report.differences, do: assert(row.loss > 0)

    text = Review.markdown(report)
    assert text =~ "# Review of 1 games"
    assert text =~ "## Human vs tuned bot"
    assert text =~ "## Bot mistakes"
    assert {:ok, _} = Jason.encode(report)
  end

  test "--human-won keeps only the games a human leads", %{game: game} do
    # In #89 a bot leads at round 5.
    refute Review.human_won?(game)
    assert Review.run([game], human_won: true, bot_kinds: []).games.reviewed == 0
  end

  test "buy examples and the shop fit", %{game: game} do
    examples = Review.buy_examples([game])
    assert length(examples) == 4
    assert Enum.all?(examples, &(&1.chosen in &1.options))

    tuned = Profile.get(:expert)
    fit = ShopFit.fit(examples, tuned, iterations: 10, population: 16)
    assert fit.n == 4
    assert fit.log_lik >= fit.start_log_lik
    assert fit.agreement >= fit.start_agreement
    # only the shop numbers move
    assert fit.profile.coin_weight == tuned.coin_weight
    assert fit.profile.ruby_value == tuned.ruby_value
  end

  test "start positions: round starts; the bench plays on from them", %{game: game} do
    starts = Review.start_positions([game])
    assert Enum.map(starts, & &1.round) == [2, 3, 4, 5]
    assert Enum.all?(starts, &(&1.phase != :over))

    tuned = Profile.get(:expert)
    run = fn -> Bench.run(bots: [tuned, tuned], players: 4, starts: starts, games: 8, jobs: 2) end
    result = run.()
    assert result.games == 8
    assert [%{name: :expert, seats: 32, win_rate: rate}] = result.bots
    assert_in_delta rate, 0.25, 1.0e-9
    # the same seeds give the same games (the timings differ)
    no_time = fn r -> Enum.map(r.bots, &Map.delete(&1, :decisions)) end
    assert no_time.(run.()) == no_time.(result)
  end

  @tag :tmp_dir
  test "mix quacks.review writes the report and the fitted weights", %{tmp_dir: tmp} do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    dir = Path.join(tmp, "games")
    File.mkdir_p!(dir)
    File.cp!(@bundle, Path.join(dir, "g.json"))
    out = Path.join(tmp, "out")
    fit = Path.join(tmp, "start.json")

    ReviewTask.run([dir, "--futures", "1", "--bot-kinds", "none", "--out", out, "--fit", fit])

    assert File.read!(Path.join(out, "review.md")) =~ "## Shop fit"

    assert %{"games" => %{"reviewed" => 1}} =
             out |> Path.join("review.json") |> File.read!() |> Jason.decode!()

    assert {:ok, %Profile{}} = Profile.parse("file:" <> fit)
    assert %Game{} = hd(Review.start_positions([elem(Archive.load(Path.join(dir, "g.json")), 1)]))
  end
end
