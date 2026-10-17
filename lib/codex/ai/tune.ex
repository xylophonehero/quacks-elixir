defmodule Codex.AI.Tune do
  @moduledoc """
  Tunes the evaluator weights (`Codex.AI.Weights`) by self-play with the
  cross-entropy method (`docs/research/codex-bot.md` §4.3). The method steps are
  the ones of the Quacks tuner (`Quacks.AI.Tune.sample/4` and
  `Quacks.AI.Tune.update/3`):

  1. Keep a mean and a spread for every weight of `Codex.AI.Weights.spec/0`
     (scaled to `[0, 1]`).
  2. Each generation, draw `population` candidates around the mean (plus the
     mean itself). Each candidate is the bot `bot` (a `Codex.AI.Bench.bot/1`
     spec) with the candidate's weights.
  3. Fitness: the candidate's win rate against a field, in both presets
     (`first`, `finesse_first`) and both seats (duplicate seating): the
     stage-1 bot `plan`, the first bot `basic`, and the current best (the
     mean of the last generation). All candidates of a generation play the
     same seeds; each generation has new seeds (generation number + `seed`).
  4. The mean and the spread move towards the `elite` best candidates.

  After each generation the state goes to the checkpoint file and the mean
  weights to the weights file (`Codex.AI.Weights.save/3`), so a stopped run
  loses at most one generation and goes on from the checkpoint. The same
  options give the same run (the bots have no clock here).
  """

  alias Codex.AI.{Bench, Weights}
  alias Quacks.AI.Tune, as: CEM

  @presets ["first", "finesse_first"]

  @doc """
  Run generations until `generations:` (total, default 100) or `minutes:` (no
  new generation after it). Options: `bot:` the candidate bot spec (default
  `"search8e0x"`), `field:` `[{spec | :best, games}]` games per preset
  (default `[{"plan", 16}, {:best, 16}, {"basic", 4}]`), `population:` (default
  12), `elite:` (default 4), `seed:` (default 1), `jobs:`, `checkpoint:` and
  `out:` paths, `log:` a function for one line of text. Returns the last state.
  """
  @spec run(keyword) :: map
  def run(opts) do
    checkpoint = Keyword.get(opts, :checkpoint, "priv/bots/codex-tune/checkpoint.json")
    out = Keyword.get(opts, :out, "priv/bots/codex-tune/tuned.json")
    log = Keyword.get(opts, :log, fn _ -> :ok end)

    config = %{
      bot: Keyword.get(opts, :bot, "search8e0x"),
      field: Keyword.get(opts, :field, [{"plan", 16}, {:best, 16}, {"basic", 4}]),
      population: Keyword.get(opts, :population, 12),
      elite: Keyword.get(opts, :elite, 4),
      seed: Keyword.get(opts, :seed, 1),
      jobs: Keyword.get(opts, :jobs, Bench.default_jobs())
    }

    state = resume(checkpoint, log) || fresh(Keyword.get(opts, :start, Weights.defaults()))
    started = System.monotonic_time(:millisecond)
    deadline = if opts[:minutes], do: started + round(opts[:minutes] * 60_000)
    ctx = %{config: config, log: log, checkpoint: checkpoint, out: out}
    loop(state, ctx, Keyword.get(opts, :generations, 100), deadline)
  end

  defp fresh(start) do
    %{
      "generation" => 0,
      "mean" => Weights.to_unit(start),
      "sd" => List.duplicate(CEM.sd_start(), length(Weights.spec())),
      "history" => []
    }
  end

  defp resume(path, log) do
    with {:ok, text} <- File.read(path),
         {:ok, state} <- Jason.decode(text) do
      log.("resume from #{path} at generation #{state["generation"]}")
      Map.delete(state, "config")
    else
      _ -> nil
    end
  end

  defp loop(state, ctx, max_gen, deadline) do
    if state["generation"] >= max_gen or past?(deadline) do
      state
    else
      state = generation(state, ctx)
      save(state, ctx)
      loop(state, ctx, max_gen, deadline)
    end
  end

  defp past?(nil), do: false
  defp past?(deadline), do: System.monotonic_time(:millisecond) >= deadline

  @doc false
  def generation(state, %{config: config} = ctx) do
    gen = state["generation"] + 1
    t0 = System.monotonic_time(:millisecond)
    rng = :rand.seed_s(:exsss, {config.seed, gen, 4243})
    {samples, _rng} = CEM.sample(state["mean"], state["sd"], config.population, rng)
    candidates = [state["mean"] | samples]
    best = Weights.from_unit(state["mean"])
    seed = config.seed * 1000 + gen

    scored = Enum.map(candidates, &{&1, fitness(Weights.from_unit(&1), best, seed, config)})
    [{_, mean_fit} | _] = scored
    elite = scored |> Enum.sort_by(&(-elem(&1, 1))) |> Enum.take(config.elite)
    {mean, sd} = CEM.update(state["mean"], state["sd"], Enum.map(elite, &elem(&1, 0)))
    seconds = (System.monotonic_time(:millisecond) - t0) / 1000
    top = elite |> hd() |> elem(1)

    ctx.log.(
      "gen #{gen}: mean fitness #{f(mean_fit)}, best #{f(top)}, " <>
        "spread #{f(Enum.sum(sd) / length(sd))}, #{f(seconds)} s"
    )

    entry = %{
      "generation" => gen,
      "mean_fitness" => mean_fit,
      "best" => top,
      "s" => seconds,
      "games" => games_per_candidate(config) * length(candidates)
    }

    %{state | "generation" => gen, "mean" => mean, "sd" => sd}
    |> Map.update!("history", &(&1 ++ [entry]))
  end

  @doc "The games one candidate plays in a generation."
  @spec games_per_candidate(map) :: non_neg_integer
  def games_per_candidate(config),
    do: length(@presets) * Enum.sum(for {_, g} <- config.field, do: g)

  @doc """
  The fitness of `weights`: the win rate of the bot `config.bot` with these
  weights against the field (`best` are the weights of the current best),
  weighted by the games of each opponent.
  """
  @spec fitness(map, map, integer, map) :: float
  def fitness(weights, best, seed, config) do
    cand = with_weights(Bench.bot(config.bot), weights, "candidate")

    results =
      for {opp, games} <- config.field, preset <- @presets do
        opp_bot =
          case opp do
            :best -> with_weights(Bench.bot(config.bot), best, "best")
            spec -> Bench.bot(spec)
          end

        %{bots: [%{win_rate: w} | _]} =
          Bench.run(
            bots: [cand, opp_bot],
            games: games,
            seed: seed,
            preset: preset,
            jobs: config.jobs
          )

        {w, games}
      end

    total = Enum.sum(for {_, g} <- results, do: g)
    Enum.sum(for {w, g} <- results, do: w * g) / total
  end

  @doc "A bench bot (`Codex.AI.Bench.bot/1`) with other evaluator weights."
  @spec with_weights(map, map, String.t()) :: map
  def with_weights(%{mod: Codex.Bot.Plan} = bot, w, name),
    do: %{bot | name: name, state: %{bot.state | weights: w}}

  def with_weights(%{mod: Codex.Bot.Search} = bot, w, name),
    do: %{put_in(bot.state.weights, w) | name: name}

  defp save(state, ctx) do
    File.mkdir_p!(Path.dirname(ctx.checkpoint))
    tmp = ctx.checkpoint <> ".tmp"
    config = Map.update!(ctx.config, :field, fn f -> Enum.map(f, &Tuple.to_list/1) end)
    File.write!(tmp, Jason.encode!(Map.put(state, "config", config)))
    File.rename!(tmp, ctx.checkpoint)
    last = List.last(state["history"])

    Weights.save(ctx.out, Weights.from_unit(state["mean"]), %{
      generation: state["generation"],
      mean_fitness: last["mean_fitness"],
      bot: ctx.config.bot
    })
  end

  defp f(x), do: :erlang.float_to_binary(x / 1, decimals: 3)
end
