defmodule Mix.Tasks.Quacks.Sim do
  @shortdoc "Plays bot games and prints a summary per profile"
  @moduledoc """
  Plays headless bot games with `Quacks.AI.Sim.run/1` and prints a table.

      mix quacks.sim --games 500 --profiles balanced,reckless,cautious,balanced --seed 1

  Options: `--games` (default 100), `--profiles` (comma list of cautious, balanced,
  reckless; one per seat; default balanced,balanced), `--seed` (default 1).
  """

  use Mix.Task

  alias Quacks.AI.{Profile, Sim}

  @impl true
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv, strict: [games: :integer, profiles: :string, seed: :integer])

    profiles = opts |> Keyword.get(:profiles, "balanced,balanced") |> parse_profiles()
    summary = Sim.run(games: opts[:games] || 100, profiles: profiles, seed: opts[:seed] || 1)

    Mix.shell().info("#{summary.games} games, #{summary.players} players\n")

    Mix.shell().info(
      row(["profile", "seats", "VP", "sd", "win %", "expl %"] ++ Enum.map(1..9, &"e#{&1}"))
    )

    for {name, s} <- summary.profiles do
      Mix.shell().info(
        row(
          [name, s.seats, num(s.vp_mean), num(s.vp_sd), pct(s.win_rate), pct(s.explosion_rate)] ++
            Enum.map(1..9, &pct(s.explosions[&1] || 0))
        )
      )
    end

    Mix.shell().info("\nmean coins per round")

    for {name, s} <- summary.profiles,
        do: Mix.shell().info(row([name | Enum.map(1..9, &num(s.coins[&1] || 0))]))

    Mix.shell().info("\nchips bought per game")

    for {name, s} <- summary.profiles do
      buys =
        s.buys |> Enum.sort_by(&(-elem(&1, 1))) |> Enum.map(fn {c, k} -> "#{c} #{num(k)}" end)

      Mix.shell().info("#{name}: #{Enum.join(buys, ", ")}")
    end
  end

  defp parse_profiles(text) do
    known = Map.new(Profile.all(), &{Atom.to_string(&1), &1})

    for name <- String.split(text, ",", trim: true) do
      Map.get(known, String.trim(name)) || Mix.raise("unknown profile #{inspect(name)}")
    end
  end

  defp row(cells), do: Enum.map_join(cells, "", &String.pad_leading(to_string(&1), 8))
  defp num(x), do: :erlang.float_to_binary(x / 1, decimals: 1)
  defp pct(x), do: :erlang.float_to_binary(x * 100, decimals: 1)
end
