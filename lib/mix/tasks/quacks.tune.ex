defmodule Mix.Tasks.Quacks.Tune do
  @shortdoc "Tunes bot weights by self-play (resumable, CPU-capped)"
  @moduledoc """
  Runs `Quacks.AI.Tune` (cross-entropy method over the numbers of a profile) and
  writes the result as a weights file.

      nice -n 10 mix quacks.tune --minutes 60 --jobs 4

  Options:

  - `--base` profile text to start from (default `balanced+strong`).
  - `--opponent` profile text to play against (default: the base).
  - `--checkpoint` state file (default `priv/bots/tune-checkpoint.json`). When it
    exists, the run goes on from it; delete it to start again.
  - `--out` weights file (default `priv/bots/tuned.json`), written every generation.
    Use it with `mix quacks.bench --bots file:priv/bots/tuned.json,balanced+strong`.
  - `--minutes` time budget: no new generation starts after it.
  - `--generations` stop at this generation (total, default 1000).
  - `--population` (default 24), `--elite` (default 6), `--seeds` per candidate and
    seat count (default 100), `--seed` (default 1).
  - `--starts DIR`: also play on from positions of the games in `DIR` (the start
    of each round from round 2, `Quacks.AI.Review.start_positions/1`); with
    `--starts-human-won` only from games a human won. `--start-reps` plays per
    start and seat (default 2). See `docs/research/learn-from-nick.md`.
  - `--jobs` games at the same time (default: half the cores, #{Quacks.AI.Bench.default_jobs()} here).

  The files in `priv/bots/` are not committed until reviewed.
  """

  use Mix.Task

  alias Quacks.AI.{Review, Tune}
  alias Quacks.Archive

  @impl true
  def run(argv) do
    Mix.Task.run("app.config")

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          base: :string,
          opponent: :string,
          checkpoint: :string,
          out: :string,
          minutes: :float,
          generations: :integer,
          population: :integer,
          elite: :integer,
          seeds: :integer,
          seed: :integer,
          jobs: :integer,
          starts: :string,
          starts_human_won: :boolean,
          start_reps: :integer
        ]
      )

    log = fn line -> Mix.shell().info("#{time()} #{line}") end
    opts = starts(opts, log)
    state = Tune.run([log: log] ++ opts)
    log.("stopped at generation #{state["generation"]}")
  end

  defp starts(opts, log) do
    case Keyword.pop(opts, :starts) do
      {nil, opts} ->
        opts

      {dir, opts} ->
        {won?, opts} = Keyword.pop(opts, :starts_human_won, false)
        {games, _bad} = Archive.load_dir(dir)
        games = if won?, do: Enum.filter(games, &Review.human_won?/1), else: games
        starts = Review.start_positions(games)
        log.("#{length(starts)} start positions from #{length(games)} games in #{dir}")
        Keyword.put(opts, :starts, starts)
    end
  end

  defp time, do: Time.utc_now() |> Time.truncate(:second) |> Time.to_string()
end
