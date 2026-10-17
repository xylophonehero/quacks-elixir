defmodule Mix.Tasks.Quacks.Review do
  @shortdoc "Reviews played games: human style, human vs tuned bot, bot mistakes"
  @moduledoc """
  Runs `Quacks.AI.Review` on the game files in a directory (archive files from
  `mix quacks.games.pull`, bug report bundles, or `Quacks.Session` bundles) and
  writes `review.md` and `review.json` (`docs/research/learn-from-nick.md`).

      nice -n 10 mix quacks.review tmp/finished --human-won --jobs 4

  Options:

  - `--human-won` only games a human seat won (or leads, if the game did not end).
  - `--futures N` rollouts per option (default 16), `--max-options N` options per
    bot decision (default 10), `--seed N` (default 1), `--jobs N` (default: half the
    cores), `--top N` rows per list (default 15).
  - `--bot-kinds draw_stop,buy,...` the bot decisions to roll out (default all;
    `none` skips the bot review).
  - `--humans 0,2` the human seats, for files that do not say (bot games such as
    `test/fixtures/bundles/`); `--bot-profile NAME` the bots' profile when a bundle
    does not name it (default `expert`; `balanced` for a bundle without bots).
  - `--fit PATH` also fits the shop weights to the humans' buys
    (`Quacks.AI.ShopFit`, from `priv/bots/tuned.json`) and writes a weights file
    there: a start point for `mix quacks.tune --base file:PATH`.
  - `--out DIR` (default `tmp/review`).
  """
  use Mix.Task

  alias Quacks.{AI.Review, AI.ShopFit, AI.Weights, Archive}

  @switches [
    human_won: :boolean,
    futures: :integer,
    max_options: :integer,
    seed: :integer,
    jobs: :integer,
    top: :integer,
    bot_kinds: :string,
    humans: :string,
    bot_profile: :string,
    fit: :string,
    out: :string
  ]
  @kinds ~w(draw_stop explosion buy rubies choice)

  @impl true
  def run(argv) do
    {opts, args} = OptionParser.parse!(argv, strict: @switches)
    dir = dir!(args)
    Mix.Task.run("app.config")

    load_opts =
      [bot_profile: opts[:bot_profile], humans: seats(opts[:humans])]
      |> Enum.reject(&is_nil(elem(&1, 1)))

    {games, bad} = Archive.load_dir(dir, load_opts)
    for {path, reason} <- bad, do: Mix.shell().info("skipped #{path}: #{inspect(reason)}")
    Mix.shell().info("#{length(games)} games in #{dir}")

    review_opts =
      [
        human_won: opts[:human_won] == true,
        bot_kinds: kinds(opts[:bot_kinds])
      ] ++ Keyword.take(opts, [:futures, :max_options, :seed, :jobs, :top])

    {us, report} = :timer.tc(fn -> Review.run(games, review_opts) end)
    out = opts[:out] || "tmp/review"
    File.mkdir_p!(out)
    report = if opts[:fit], do: Map.put(report, :fit, fit(games, report, opts)), else: report
    File.write!(Path.join(out, "review.md"), Review.markdown(report) <> fit_text(report[:fit]))
    File.write!(Path.join(out, "review.json"), Jason.encode_to_iodata!(report, pretty: true))

    Mix.shell().info(
      "#{report.games.reviewed} games reviewed in #{Float.round(us / 1_000_000, 1)} s: " <>
        "#{Path.join(out, "review.md")}, #{Path.join(out, "review.json")}"
    )
  end

  defp dir!([dir]), do: dir
  defp dir!(_args), do: Mix.raise("Usage: mix quacks.review DIR [--human-won] [--futures N] ...")

  defp seats(nil), do: nil
  defp seats(text), do: text |> String.split(",", trim: true) |> Enum.map(&String.to_integer/1)

  defp kinds(nil), do: Enum.map(@kinds, &String.to_atom/1)
  defp kinds("none"), do: []

  defp kinds(text) do
    for kind <- String.split(text, ",", trim: true) do
      if kind in @kinds, do: String.to_atom(kind), else: Mix.raise("unknown kind #{kind}")
    end
  end

  defp fit(games, report, opts) do
    games =
      if report.settings.human_won, do: Enum.filter(games, &Review.human_won?/1), else: games

    examples = Review.buy_examples(games)
    {:ok, start} = Weights.load("priv/bots/tuned.json")
    result = ShopFit.fit(examples, start, seed: opts[:seed] || 1)

    Weights.save(opts[:fit], "balanced+strong", result.profile, %{
      fitted_to: "#{result.n} human buys",
      beta: result.beta
    })

    result
    |> Map.delete(:profile)
    |> Map.merge(%{
      path: opts[:fit],
      colour_weight: result.profile.colour_weight,
      value_weight: result.profile.value_weight,
      start_colour_weight: start.colour_weight,
      start_value_weight: start.value_weight
    })
  end

  defp fit_text(nil), do: ""

  defp fit_text(f) do
    """

    ## Shop fit (start point for training)

    #{f.n} human buys. Log-likelihood per buy: #{num(f.start_log_lik)} (tuned) -> #{num(f.log_lik)} (fitted). \
    Best-scored buy = the human's buy: #{pct(f.start_agreement)} (tuned) -> #{pct(f.agreement)} (fitted). \
    Weights file: `#{f.path}`.

    | weight | tuned | fitted |
    | --- | --- | --- |
    #{rows(f.start_colour_weight, f.colour_weight, "colour")}#{rows(f.start_value_weight, f.value_weight, "value")}
    """
  end

  defp rows(start, fitted, label) do
    for {k, v} <- Enum.sort(fitted),
        into: "",
        do: "| #{label} #{k} | #{num(start[k])} | #{num(v)} |\n"
  end

  defp num(nil), do: "-"
  defp num(x), do: :erlang.float_to_binary(x / 1, decimals: 2)
  defp pct(nil), do: "-"
  defp pct(x), do: "#{round(x * 100)} %"
end
