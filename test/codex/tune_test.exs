defmodule Codex.AI.TuneTest do
  @moduledoc "The Codex weight tuner: a generation, the files, resume, determinism."
  use ExUnit.Case, async: true

  alias Codex.AI.{Bench, Tune, Weights}

  @moduletag :tmp_dir

  defp opts(dir, gens) do
    [
      bot: "plan",
      field: [{:best, 2}],
      population: 2,
      elite: 1,
      generations: gens,
      jobs: 2,
      checkpoint: Path.join(dir, "checkpoint.json"),
      out: Path.join(dir, "tuned.json")
    ]
  end

  test "one generation writes the checkpoint and the weights; a second run resumes", %{
    tmp_dir: dir
  } do
    state = Tune.run(opts(dir, 1))
    assert state["generation"] == 1
    assert [%{"games" => 12}] = state["history"]
    assert {:ok, w} = Weights.load(Path.join(dir, "tuned.json"))
    assert Map.keys(w) == Map.keys(Weights.defaults())

    again = Tune.run(opts(dir, 2))
    assert again["generation"] == 2
    assert length(again["history"]) == 2
  end

  test "the same options give the same run", %{tmp_dir: dir} do
    a = Tune.run(opts(Path.join(dir, "a"), 1))
    b = Tune.run(opts(Path.join(dir, "b"), 1))
    assert a["mean"] == b["mean"]
  end

  test "the shared CEM steps: sample in [0, 1], update moves to the elite" do
    {xs, _} = Quacks.AI.Tune.sample([0.5, 0.0], [0.3, 0.3], 20, :rand.seed_s(:exsss, {1, 2, 3}))
    assert length(xs) == 20
    assert Enum.all?(List.flatten(xs), &(&1 >= 0.0 and &1 <= 1.0))
    {mean, sd} = Quacks.AI.Tune.update([0.5, 0.5], [0.1, 0.1], [[1.0, 0.5], [1.0, 0.5]])
    assert_in_delta hd(mean), 0.85, 1.0e-9
    assert_in_delta List.last(mean), 0.5, 1.0e-9
    assert Enum.all?(sd, &(&1 >= 0.02))
  end

  test "with_weights/3 puts the weights into a plan or a search bot" do
    w = %{Weights.defaults() | threat_base: 1.25}
    assert Tune.with_weights(Bench.bot("plan"), w, "x").state.weights.threat_base == 1.25
    assert Tune.with_weights(Bench.bot("search4"), w, "x").state.weights.threat_base == 1.25
  end
end
