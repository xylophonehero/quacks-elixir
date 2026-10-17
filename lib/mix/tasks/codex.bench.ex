defmodule Mix.Tasks.Codex.Bench do
  @shortdoc "Benchmarks two Codex bots: win rates with 95 % confidence intervals"
  @moduledoc """
  Plays headless Codex games of two bots with `Codex.AI.Bench.run/1`. Every
  seed is played twice, with the bots in both seats. Prints a table per bot.

      nice -n 10 mix codex.bench --a plan --b basic --games 400 --seed 1

  Options:

  - `--a`, `--b` bot specs (default `basic` and `basic`): `basic`, or `plan`
    with rule changes, e.g. `plan-patrol` (`Codex.AI.Bench.bot/1`).
  - `--games` games (default 400); rounded up to an even number.
  - `--seed` integer (default 1). The same seed gives the same games. Use seeds
    from 10001 for a final check, not the seeds that you tuned on.
  - `--preset` set-up (default `first`: Bashing as P1 vs Finesse as P2;
    `finesse_first`: Finesse as P1; `red_green`).
  - `--jobs` games at the same time (default: half the cores).
  - `--quiet` no progress line.

  Run it under `nice -n 10` and keep `--jobs` at half the cores or less.
  """

  use Mix.Task

  alias Codex.AI.Bench

  @switches [
    a: :string,
    b: :string,
    games: :integer,
    seed: :integer,
    preset: :string,
    jobs: :integer,
    quiet: :boolean
  ]

  @impl true
  def run(argv) do
    Mix.Task.run("app.config")
    {opts, _, _} = OptionParser.parse(argv, strict: @switches)

    result =
      Bench.run(
        bots: [opts[:a] || "basic", opts[:b] || "basic"],
        games: opts[:games] || 400,
        seed: opts[:seed] || 1,
        preset: opts[:preset] || "first",
        jobs: opts[:jobs] || Bench.default_jobs(),
        progress: if(opts[:quiet], do: fn _ -> :ok end, else: &progress/1)
      )

    unless opts[:quiet], do: IO.write(:stderr, "\n")
    print(result)
  end

  defp progress(%{done: done, total: total, seconds: s}) do
    rate = if s > 0, do: done / s, else: 0.0
    IO.write(:stderr, "\r#{done}/#{total} games  #{num(rate)} games/s  #{round(s)} s   ")
  end

  @doc false
  def print(r) do
    info(
      "#{r.games} games (#{r.seeds} seeds x 2 seats), preset #{r.preset}, #{r.jobs} jobs, " <>
        "#{num(r.seconds)} s; mean length #{num(r.turns)} turns; unfinished #{r.ties}\n"
    )

    info(
      row([
        "bot",
        "win %",
        "+-",
        "P1 %",
        "+-",
        "P2 %",
        "+-",
        "builds",
        "workers",
        "gold",
        "att.left",
        "ms/dec",
        "ms max"
      ])
    )

    for b <- r.bots do
      info(
        row([
          b.name,
          pct(b.win_rate),
          pct(b.win_ci),
          pct(b.seat[0].win_rate),
          pct(b.seat[0].win_ci),
          pct(b.seat[1].win_rate),
          pct(b.seat[1].win_ci),
          num(b.builds),
          num(b.workers),
          num(b.gold_left),
          pct(b.attack_left),
          num(b.ms, 3),
          num(b.ms_max, 1)
        ])
      )
    end

    r
  end

  defp info(text), do: Mix.shell().info(text)

  defp row([first | rest]),
    do:
      String.pad_trailing(to_string(first), 24) <>
        Enum.map_join(rest, "", &String.pad_leading(to_string(&1), 9))

  defp pct(nil), do: "-"
  defp pct(x), do: num(x * 100)
  defp num(x, d \\ 1), do: :erlang.float_to_binary(x / 1, decimals: d)
end
