defmodule Mix.Tasks.Codex.Tune do
  @shortdoc "Tunes the Codex evaluator weights by self-play (resumable, CPU-capped)"
  @moduledoc """
  Runs `Codex.AI.Tune` (the cross-entropy method over `Codex.AI.Weights`) and
  writes the mean weights to a weights file after each generation.

      nice -n 10 mix codex.tune --minutes 60 --jobs 4

  Options:

  - `--bot` the candidate bot spec (default `search8e0x`, `Codex.AI.Bench.bot/1`).
  - `--plan-games`, `--best-games`, `--basic-games` games per preset against
    each opponent of the field (default 16, 16, 4). Both presets (`first`,
    `finesse_first`) and both seats are played.
  - `--population` (default 12), `--elite` (default 4), `--seed` (default 1).
  - `--minutes` time budget: no new generation starts after it.
  - `--generations` stop at this generation (total, default 100).
  - `--checkpoint` state file (default `priv/bots/codex-tune/checkpoint.json`).
    When it exists, the run goes on from it; delete it to start again.
  - `--out` weights file (default `priv/bots/codex-tune/tuned.json`). Bench it
    with `mix codex.bench --a search@priv/bots/codex-tune/tuned.json --b plan`.
  - `--jobs` games at the same time (default: half the cores).
  - `--start` a weights file to start a fresh run from (default: the defaults).
  - `--print` print the weights of `--out` as an Elixir map (for
    `Codex.AI.Weights`) and stop.

  The files in `priv/bots/codex-tune/` are not committed. A person reviews the
  weights and copies them into `Codex.AI.Weights`.
  """

  use Mix.Task

  alias Codex.AI.{Tune, Weights}

  @impl true
  def run(argv) do
    Mix.Task.run("app.config")

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          bot: :string,
          plan_games: :integer,
          best_games: :integer,
          basic_games: :integer,
          checkpoint: :string,
          out: :string,
          minutes: :float,
          generations: :integer,
          population: :integer,
          elite: :integer,
          seed: :integer,
          jobs: :integer,
          print: :boolean,
          start: :string
        ]
      )

    if opts[:print], do: print(opts[:out] || "priv/bots/codex-tune/tuned.json"), else: tune(opts)
  end

  defp tune(opts) do
    field = [
      {"plan", opts[:plan_games] || 16},
      {:best, opts[:best_games] || 16},
      {"basic", opts[:basic_games] || 4}
    ]

    log = fn line -> Mix.shell().info("#{time()} #{line}") end
    rest = Keyword.drop(opts, [:plan_games, :best_games, :basic_games, :print, :start])
    rest = if opts[:start], do: [start: load!(opts[:start])] ++ rest, else: rest
    state = Tune.run([log: log, field: Enum.reject(field, &(elem(&1, 1) == 0))] ++ rest)
    log.("stopped at generation #{state["generation"]}")
  end

  defp load!(path) do
    case Weights.load(path) do
      {:ok, w} -> w
      {:error, reason} -> Mix.raise(reason)
    end
  end

  defp print(path) do
    {:ok, w} = Weights.load(path)
    Mix.shell().info(inspect(w, pretty: true, limit: :infinity))
  end

  defp time, do: Time.utc_now() |> Time.truncate(:second) |> Time.to_string()
end
