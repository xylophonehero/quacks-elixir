defmodule Quacks.AI.Tune do
  @moduledoc """
  Tunes the numbers of a bot profile by self-play (`docs/research/bot-training.md`
  §5) with the cross-entropy method, a simple evolution strategy:

  1. Keep a mean and a spread for every number of `Quacks.AI.Weights.spec/0`
     (scaled to `[0, 1]`).
  2. Each generation, draw `population` candidates around the mean (plus the mean
     itself) and play each in `Quacks.AI.Bench` against the opponent profile: at 4
     seats one candidate against 3 opponents, at 2 seats one against one, duplicate
     seating, the same seeds for every candidate of a generation.
  3. Fitness: the mean of the 4-seat and the 2-seat win rate, each divided by its
     parity (1.0 = as good as the opponent).
  4. The new mean and spread move towards the `elite` best candidates.

  After every generation the state goes to the checkpoint file and the mean profile
  to the weights file, so a stopped run loses at most one generation. A run with the
  same checkpoint goes on where it stopped. Deterministic per `seed`.
  """

  alias Quacks.AI.{Bench, Profile, Weights}

  @alpha 0.7
  @sd_floor 0.02
  @sd_start 0.12

  @doc """
  Run generations until `generations:` (total, default 1000) or `minutes:` (no new
  generation after it). Options: `base:` profile text (default `"balanced+strong"`),
  `opponent:` profile text (default: the base), `checkpoint:` and `out:` paths,
  `population:` (default 24), `elite:` (default 6), `seeds:` per candidate and
  seat count (default 100), `seed:`, `jobs:`, `log:` a function for one line of text.
  Returns the last state.
  """
  @spec run(keyword) :: map
  def run(opts) do
    base_text = Keyword.get(opts, :base, "balanced+strong")
    opponent_text = Keyword.get(opts, :opponent, base_text)
    checkpoint = Keyword.get(opts, :checkpoint, "priv/bots/tune-checkpoint.json")
    out = Keyword.get(opts, :out, "priv/bots/tuned.json")
    log = Keyword.get(opts, :log, fn _ -> :ok end)
    {:ok, base} = Profile.parse(base_text)
    {:ok, opponent} = Profile.parse(opponent_text)

    config = %{
      base: base_text,
      opponent: opponent_text,
      population: Keyword.get(opts, :population, 24),
      elite: Keyword.get(opts, :elite, 6),
      seeds: Keyword.get(opts, :seeds, 100),
      seed: Keyword.get(opts, :seed, 1),
      jobs: Keyword.get(opts, :jobs, Bench.default_jobs())
    }

    state = resume(checkpoint, base, log) || fresh(base)
    started = System.monotonic_time(:millisecond)
    deadline = if opts[:minutes], do: started + round(opts[:minutes] * 60_000)
    ctx = %{config: config, base: base, opponent: %{opponent | name: :opponent}, log: log}

    loop(state, ctx, Keyword.get(opts, :generations, 1000), deadline, checkpoint, out)
  end

  defp fresh(base) do
    n = length(Weights.spec())

    %{
      "generation" => 0,
      "mean" => Weights.to_unit(base),
      "sd" => List.duplicate(@sd_start, n),
      "history" => []
    }
  end

  defp resume(path, _base, log) do
    with {:ok, text} <- File.read(path),
         {:ok, state} <- Jason.decode(text) do
      log.("resume from #{path} at generation #{state["generation"]}")
      state
    else
      _ -> nil
    end
  end

  defp loop(state, ctx, max_gen, deadline, checkpoint, out) do
    if state["generation"] >= max_gen or past?(deadline) do
      state
    else
      state = generation(state, ctx)
      save(state, ctx, checkpoint, out)
      loop(state, ctx, max_gen, deadline, checkpoint, out)
    end
  end

  defp past?(nil), do: false
  defp past?(deadline), do: System.monotonic_time(:millisecond) >= deadline

  @doc false
  def generation(state, %{config: config} = ctx) do
    gen = state["generation"] + 1
    t0 = System.monotonic_time(:millisecond)
    rng = :rand.seed_s(:exsss, {config.seed, gen, 4242})
    {samples, _rng} = sample(state["mean"], state["sd"], config.population, rng)
    candidates = [state["mean"] | samples]
    seed = config.seed * 1_000_000 + gen

    scored = Enum.map(candidates, &{&1, fitness(&1, seed, ctx)})
    [{_, mean_fit} | _] = scored
    elite = scored |> Enum.sort_by(&(-elem(&1, 1))) |> Enum.take(config.elite)
    units = Enum.map(elite, &elem(&1, 0))

    mean = blend(state["mean"], column_mean(units))
    sd = state["sd"] |> blend(column_sd(units)) |> Enum.map(&max(&1, @sd_floor))
    seconds = (System.monotonic_time(:millisecond) - t0) / 1000
    best = elite |> hd() |> elem(1)

    ctx.log.(
      "gen #{gen}: mean fitness #{f(mean_fit)}, best #{f(best)}, " <>
        "spread #{f(Enum.sum(sd) / length(sd))}, #{f(seconds)} s"
    )

    entry = %{"generation" => gen, "mean_fitness" => mean_fit, "best" => best, "s" => seconds}

    %{state | "generation" => gen, "mean" => mean, "sd" => sd}
    |> Map.update!("history", &(&1 ++ [entry]))
  end

  # The candidate's fitness: 4-seat and 2-seat win rate over parity, averaged.
  defp fitness(unit, seed, %{config: config, base: base, opponent: opp}) do
    cand = %{Weights.from_unit(base, unit) | name: :candidate}

    rates =
      for players <- [4, 2] do
        bots = [cand | List.duplicate(opp, players - 1)]

        %{bots: [%{win_rate: w} | _]} =
          Bench.run(
            bots: bots,
            players: players,
            games: config.seeds * players,
            seed: seed,
            jobs: config.jobs
          )

        w * players
      end

    Enum.sum(rates) / length(rates)
  end

  defp sample(mean, sd, n, rng) do
    Enum.map_reduce(1..n, rng, fn _, rng ->
      Enum.zip(mean, sd)
      |> Enum.map_reduce(rng, fn {m, s}, rng ->
        {z, rng} = :rand.normal_s(rng)
        {min(max(m + s * z, 0.0), 1.0), rng}
      end)
    end)
  end

  defp blend(old, new), do: Enum.zip_with(old, new, &((1 - @alpha) * &1 + @alpha * &2))

  defp column_mean(rows),
    do: rows |> Enum.zip_with(& &1) |> Enum.map(&(Enum.sum(&1) / length(&1)))

  defp column_sd(rows) do
    rows
    |> Enum.zip_with(& &1)
    |> Enum.map(fn col ->
      m = Enum.sum(col) / length(col)
      :math.sqrt(Enum.sum(Enum.map(col, &((&1 - m) ** 2))) / length(col))
    end)
  end

  defp save(state, ctx, checkpoint, out) do
    File.mkdir_p!(Path.dirname(checkpoint))
    tmp = checkpoint <> ".tmp"
    File.write!(tmp, Jason.encode!(Map.put(state, "config", ctx.config)))
    File.rename!(tmp, checkpoint)

    profile = Weights.from_unit(ctx.base, state["mean"])
    last = List.last(state["history"])

    Weights.save(out, ctx.config.base, profile, %{
      generation: state["generation"],
      mean_fitness: last["mean_fitness"],
      opponent: ctx.config.opponent
    })
  end

  defp f(x), do: :erlang.float_to_binary(x / 1, decimals: 3)
end
