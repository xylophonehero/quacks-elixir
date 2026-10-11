defmodule Mix.Tasks.Quacks.Bench do
  @shortdoc "Benchmarks bots: win rate and VP with 95 % confidence intervals"
  @moduledoc """
  Plays headless bot games with `Quacks.AI.Bench.run/1` (duplicate seating: every
  seed once per rotation of the bots) and prints a table per bot.

      nice -n 10 mix quacks.bench --games 2000 --players 4 --bots balanced+strong,balanced --seed 1

  Options:

  - `--bots` comma list of profiles, one per bot (default `balanced,balanced+strong`).
    A profile takes `+` modifiers (`Quacks.AI.Profile.parse/1`), e.g. `balanced+ev`.
    Name a profile twice to give it more seats: `new,balanced,balanced,balanced`
    at 4 players is one `new` against three `balanced`.
  - `--players` seats per game (default: the number of bots, at least 2).
  - `--games` games (default 1000); rounded up to a multiple of the number of bots.
  - `--seed` integer (default 1). The same seed gives the same games.
  - `--jobs` games at the same time (default: half the cores, #{Quacks.AI.Bench.default_jobs()} here).
  - `--minutes` time budget: no new batch starts after it.
  - `--stats` also print the decisions per phase (count, mean and max time).
  - `--quiet` no progress line.
  - `--rules`, `--expansions`, `--sets` as in `mix quacks.sim`.

  Keep the Mac cool: run it under `nice -n 10` and keep `--jobs` at half the cores
  or less (`docs/research/bot-training.md` §6).
  """

  use Mix.Task

  alias Mix.Tasks.Quacks.Sim, as: SimTask
  alias Quacks.AI.Bench

  @impl true
  def run(argv) do
    Mix.Task.run("app.config")
    {opts, _, _} = OptionParser.parse(argv, strict: switches())
    bots = SimTask.parse_profiles(opts[:bots] || "balanced,balanced+strong")

    bench_opts =
      [
        bots: bots,
        players: opts[:players] || max(length(bots), 2),
        games: opts[:games] || 1000,
        seed: opts[:seed] || 1,
        jobs: opts[:jobs] || Bench.default_jobs(),
        minutes: opts[:minutes],
        progress: if(opts[:quiet], do: fn _ -> :ok end, else: &progress/1)
      ] ++ game_options(opts)

    result = Bench.run(bench_opts)
    unless opts[:quiet], do: IO.write(:stderr, "\n")
    print(result, opts[:stats])
  end

  defp game_options(opts) do
    [
      rules: SimTask.parse_rules(opts[:rules] || ""),
      expansions: SimTask.parse_expansions(opts[:expansions] || ""),
      sets: SimTask.parse_sets(opts[:sets] || "")
    ]
  end

  defp switches do
    [
      bots: :string,
      players: :integer,
      games: :integer,
      seed: :integer,
      jobs: :integer,
      minutes: :float,
      stats: :boolean,
      quiet: :boolean,
      rules: :string,
      expansions: :string,
      sets: :string
    ]
  end

  defp progress(%{done: done, total: total, seconds: s}) do
    rate = if s > 0, do: done / s, else: 0.0
    eta = if rate > 0, do: round((total - done) / rate), else: 0

    IO.write(
      :stderr,
      "\r#{done}/#{total} games  #{num(rate)} games/s  #{round(s)} s  eta #{eta} s   "
    )
  end

  @doc false
  def print(result, stats? \\ false) do
    info(
      "#{result.games} games (#{result.seeds} seeds x #{div(result.games, max(result.seeds, 1))} seatings), " <>
        "#{result.players} players, #{result.jobs} jobs, #{num(result.seconds)} s, " <>
        "#{num(result.games_per_s)} games/s"
    )

    info("win % parity: #{num(100 / result.players)}\n")
    info(row(["bot", "seats", "win %", "+-", "VP", "+-", "expl %", "ms/dec"], 30))

    for b <- result.bots do
      info(
        row(
          [
            b.name,
            b.seats,
            num(b.win_rate * 100),
            ci(b.win_ci, 100),
            num(b.vp_mean),
            ci(b.vp_ci, 1),
            num(b.explosion_rate * 100),
            ms_per_decision(b.decisions)
          ],
          30
        )
      )
    end

    if stats?, do: print_stats(result.bots)
    result
  end

  defp print_stats(bots) do
    for b <- bots do
      info("\n#{b.name}: decisions per phase")
      info(row(["phase", "n", "us mean", "us max"], 20))

      for {phase, d} <- Enum.sort_by(b.decisions, fn {_, d} -> -d.n end) do
        info(row([phase, d.n, num(d.us_mean), d.us_max], 20))
      end
    end
  end

  defp ms_per_decision(decisions) when map_size(decisions) == 0, do: "-"

  defp ms_per_decision(decisions) do
    {n, us} =
      Enum.reduce(decisions, {0, 0.0}, fn {_, d}, {n, us} -> {n + d.n, us + d.n * d.us_mean} end)

    :erlang.float_to_binary(us / n / 1000, decimals: 3)
  end

  defp info(text), do: Mix.shell().info(text)

  defp row([first | rest], width),
    do:
      String.pad_trailing(to_string(first), width) <>
        Enum.map_join(rest, "", &String.pad_leading(to_string(&1), 9))

  defp ci(nil, _scale), do: "-"
  defp ci(x, scale), do: num(x * scale)
  defp num(x), do: :erlang.float_to_binary(x / 1, decimals: 1)
end
