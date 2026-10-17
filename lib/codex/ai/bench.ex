defmodule Codex.AI.Bench do
  @moduledoc """
  The Codex bot benchmark (`docs/research/codex-bot.md` §4.4): headless games of
  two bots with the pure engine. `mix codex.bench` prints it.

  **Duplicate seating.** Every seed is played twice: bot A as P1 and bot B as P2,
  then the bots change seats. So both bots get the same cards in both seats. The
  95 % confidence interval of a win rate treats one seed (its 2 games) as one
  sample. The interval of a win rate per seat treats one game as one sample.

  **Determinism.** A game seed is `{seed, i, 11}` for seed number `i`. The bots
  have no clock and no other randomness, so the same options give the same
  numbers for any `jobs:`.

  **Bots.** A bot spec is a string (`bot/1`): `"basic"` (`Codex.Bot`) or
  `"plan"` (`Codex.Bot.Plan`) with optional rule changes, e.g.
  `"plan-patrol+surplus"` (rule `patrol` off, rule `surplus` on).

  Each bot sees only `Codex.Game.bot_view/2` (no hidden cards).
  """

  alias Codex.AI.Weights
  alias Codex.Bot.{Plan, Search}
  alias Codex.Game

  @max_actions 6000
  @z 1.96

  @typedoc "A bot: its name, its module (`choose(view, state) :: {action, state}`) and its start state."
  @type bot :: %{name: String.t(), mod: module, state: term}

  @doc "Half the scheduler threads, at least 1: the default `jobs:`."
  @spec default_jobs() :: pos_integer
  def default_jobs, do: max(div(System.schedulers_online(), 2), 1)

  @doc """
  The bot of a spec string. `"basic"`: the first bot (`Codex.Bot`). `"plan"`:
  the stage-1 bot (`Codex.Bot.Plan`); `+rule` turns a rule on, `-rule` turns it
  off (`Codex.Bot.Plan.rules/0`). `@path` reads the weights from a file
  (`Codex.AI.Weights.load/1`); `:key=value,key=value` changes weights, e.g.
  `"plan:threat_base=1,lethal=10"`. `"search"`: the stage-2 bot
  (`Codex.Bot.Search`) with no clock; a number after it is the candidates per
  turn (default 40), then `e` and the random-step chance (default 0), then
  `x` for no early stop or `p` for the early stop (default: no early stop),
  then
  rules and weights as for `plan`, e.g. `"search24e0.3:threat_base=0.5"`.

      iex> Codex.AI.Bench.bot("basic").mod
      Codex.Bot
  """
  @spec bot(String.t()) :: bot
  def bot("basic"), do: %{name: "basic", mod: Codex.Bot, state: nil}

  def bot("plan" <> rest = name) do
    {mods, weights} = split_weights(rest, Weights.defaults())
    %{name: name, mod: Plan, state: Plan.new(parse_mods(mods), weights)}
  end

  def bot("search" <> rest = name) do
    {n, rest} =
      Integer.parse(rest <> "|")
      |> then(fn
        {n, r} -> {n, String.trim_trailing(r, "|")}
        :error -> {Search.defaults().n, rest}
      end)

    {eps, rest} = parse_eps(rest)
    {prefix, rest} = parse_prefix(rest)
    {mods, weights} = split_weights(rest, Weights.search())

    state =
      Search.new(
        n: n,
        eps: eps,
        prefix: prefix,
        budget_ms: nil,
        rules: parse_mods(mods),
        weights: weights
      )

    %{name: name, mod: Search, state: state}
  end

  def bot(other), do: raise(ArgumentError, "unknown bot #{inspect(other)}")

  # "e0.3": the chance of a random step in a candidate turn.
  defp parse_eps("e" <> text) do
    {eps, rest} = Float.parse(text)
    {eps, rest}
  end

  defp parse_eps(text), do: {Search.defaults().eps, text}

  # "x": no early stop; "p": early stop.
  defp parse_prefix("x" <> rest), do: {false, rest}
  defp parse_prefix("p" <> rest), do: {true, rest}
  defp parse_prefix(text), do: {Search.defaults().prefix, text}

  # "…:key=value,key=value" changes weights; "…@path" reads a weights file.
  defp split_weights(text, default) do
    case String.split(text, ":", parts: 2) do
      [mods, changes] ->
        {strip_file(mods), Map.merge(base_weights(mods, default), parse_weights(changes))}

      [mods] ->
        {strip_file(mods), base_weights(mods, default)}
    end
  end

  defp base_weights(mods, default) do
    case String.split(mods, "@", parts: 2) do
      [_, path] ->
        case Weights.load(path) do
          {:ok, w} -> w
          {:error, reason} -> raise ArgumentError, reason
        end

      [_] ->
        default
    end
  end

  defp strip_file(mods), do: mods |> String.split("@", parts: 2) |> hd()

  defp parse_weights(text) do
    Map.new(String.split(text, ",", trim: true), fn pair ->
      [k, v] = String.split(pair, "=")
      key = String.to_existing_atom(k)

      unless Map.has_key?(Weights.defaults(), key),
        do: raise(ArgumentError, "unknown weight #{k}")

      {n, ""} = Float.parse(v)
      {key, n}
    end)
  end

  defp parse_mods(mods) do
    ~r/([+-])([a-z0-9_]+)/
    |> Regex.scan(mods)
    |> Enum.map(fn [_, sign, rule] -> {String.to_existing_atom(rule), sign == "+"} end)
  end

  @doc """
  Play the benchmark. Options:

  - `bots:` (required) two bot specs or bots, `[a, b]`.
  - `games:` games to play (default 400), rounded up to an even number.
  - `seed:` an integer (default 1). The same seed gives the same games.
  - `preset:` the set-up (default `"first"`, Bashing as P1 vs Finesse as P2);
    `"finesse_first"` swaps the specs (Finesse as P1).
  - `jobs:` games at the same time (default `default_jobs/0`).
  - `progress:` a function that gets `%{done: n, total: n, seconds: s}`.

  Returns `%{games:, seeds:, seconds:, jobs:, preset:, ties:, turns:, bots: [a, b]}`.
  `turns` is the mean game length (turns of both sides together). Per bot:
  `win_rate`, `win_ci`, `seat` (per seat: `win_rate`, `win_ci`), `builds` (tech
  buildings and add-ons started per game), `workers` (at the end), `gold_left`
  (mean gold at the end of a turn), `attack_left` (the share of turns that end
  with an attack still legal) and `ms` (mean time per decision).
  """
  @spec run(keyword) :: map
  def run(opts) do
    bots = opts |> Keyword.fetch!(:bots) |> Enum.map(&to_bot/1)
    seeds = ceil(Keyword.get(opts, :games, 400) / 2)
    seed = Keyword.get(opts, :seed, 1)
    preset = Keyword.get(opts, :preset, "first")
    jobs = Keyword.get(opts, :jobs, default_jobs())
    progress = Keyword.get(opts, :progress, fn _ -> :ok end)
    started = System.monotonic_time(:millisecond)

    results =
      1..seeds
      |> Enum.chunk_every(jobs * 4)
      |> Enum.reduce([], fn chunk, acc ->
        acc = acc ++ play_chunk(chunk, bots, seed, preset, jobs)
        progress.(%{done: 2 * length(acc), total: 2 * seeds, seconds: seconds(started)})
        acc
      end)

    games = Enum.flat_map(results, & &1)

    %{
      games: length(games),
      seeds: seeds,
      seconds: seconds(started),
      jobs: jobs,
      preset: preset,
      ties: Enum.count(games, &(&1.winner == nil)),
      turns: mean(Enum.map(games, & &1.turns)),
      bots: for(i <- [0, 1], do: summary(Enum.at(bots, i), i, results))
    }
  end

  defp to_bot(%{mod: _} = bot), do: bot
  defp to_bot(spec) when is_binary(spec), do: bot(spec)

  defp seconds(started), do: (System.monotonic_time(:millisecond) - started) / 1000

  defp play_chunk(chunk, bots, seed, preset, jobs) do
    [a, b] = bots

    chunk
    |> Task.async_stream(
      fn i ->
        game_seed = {seed, i, 11}
        # Bot A as P1, then bot B as P1. `bot` in a result: the bot index (0 = A).
        [
          tag(play([a, b], game_seed, preset), [0, 1]),
          tag(play([b, a], game_seed, preset), [1, 0])
        ]
      end,
      max_concurrency: jobs,
      timeout: :infinity,
      ordered: true
    )
    |> Enum.map(fn {:ok, pair} -> pair end)
  end

  defp tag(result, order), do: Map.put(result, :order, order)

  @doc """
  Play one game: `bots` is `[p1_bot, p2_bot]`. Returns `%{winner:, turns:,
  sides: %{seat => stats}}`; `winner` is nil when the game passes
  #{@max_actions} actions.
  """
  @spec play([bot], {integer, integer, integer}, String.t()) :: map
  def play(bots, seed, preset \\ "first") do
    {:ok, game} = Game.new(Map.put(game_opts(preset), :bot, true), seed)
    states = %{0 => Enum.at(bots, 0).state, 1 => Enum.at(bots, 1).state}
    mods = %{0 => Enum.at(bots, 0).mod, 1 => Enum.at(bots, 1).mod}
    stats = %{0 => new_stats(), 1 => new_stats()}
    loop(game, mods, states, stats, 0)
  end

  # "finesse_first": the first-game decks with the seats swapped (Finesse as P1).
  defp game_opts("finesse_first") do
    %{
      preset: "custom",
      p1_starter: "Neutral",
      p1_spec: "Finesse",
      p2_starter: "Neutral",
      p2_spec: "Bashing"
    }
  end

  defp game_opts(preset), do: %{preset: preset}

  defp new_stats,
    do: %{builds: 0, end_turns: 0, gold_left: 0, attack_left: 0, n: 0, us: 0, us_max: 0}

  defp loop(%Game{phase: :over} = game, _mods, _states, stats, _k), do: finish(game, stats)
  defp loop(game, _mods, _states, stats, k) when k >= @max_actions, do: finish(game, stats)

  defp loop(game, mods, states, stats, k) do
    s = game.active
    view = Game.bot_view(game, s)
    {us, {action, state}} = :timer.tc(fn -> mods[s].choose(view, states[s]) end)
    stats = Map.update!(stats, s, &note(&1, game, view, action, us))
    {:ok, game} = Game.apply(game, s, action)
    loop(%{game | history: []}, mods, Map.put(states, s, state), stats, k + 1)
  end

  defp note(st, game, view, action, us) do
    st = %{st | n: st.n + 1, us: st.us + us, us_max: max(st.us_max, us)}

    case action do
      {:build, _} ->
        %{st | builds: st.builds + 1}

      {:build, _, _} ->
        %{st | builds: st.builds + 1}

      :end_turn ->
        attack? = Enum.any?(view.legal, &match?({:attack, _, _}, &1))

        %{
          st
          | end_turns: st.end_turns + 1,
            gold_left: st.gold_left + game.sides[game.active].gold,
            attack_left: st.attack_left + if(attack?, do: 1, else: 0)
        }

      _ ->
        st
    end
  end

  defp finish(game, stats) do
    sides =
      Map.new(stats, fn {s, st} ->
        {s, Map.put(st, :workers, length(game.sides[s].zones.workers))}
      end)

    %{winner: game.winner, turns: game.sides[0].turn + game.sides[1].turn, sides: sides}
  end

  # -- summary --------------------------------------------------------------------------

  defp summary(bot, i, results) do
    # Per seed: the 2 games of bot i, each as {seat, win, side stats}.
    per_seed =
      for pair <- results do
        for g <- pair do
          seat = Enum.find_index(g.order, &(&1 == i))
          {seat, win(g.winner, seat), g.sides[seat]}
        end
      end

    games = Enum.flat_map(per_seed, & &1)
    sides = Enum.map(games, &elem(&1, 2))
    end_turns = max(sum(sides, :end_turns), 1)
    n = max(sum(sides, :n), 1)

    %{
      name: bot.name,
      games: length(games),
      win_rate: mean(Enum.map(games, &elem(&1, 1))),
      win_ci: ci(Enum.map(per_seed, fn pair -> mean(Enum.map(pair, &elem(&1, 1))) end)),
      seat:
        Map.new([0, 1], fn seat ->
          wins = for {^seat, w, _} <- games, do: w
          {seat, %{win_rate: mean(wins), win_ci: ci(wins)}}
        end),
      builds: sum(sides, :builds) / max(length(games), 1),
      workers: mean(Enum.map(sides, & &1.workers)),
      gold_left: sum(sides, :gold_left) / end_turns,
      attack_left: sum(sides, :attack_left) / end_turns,
      ms: sum(sides, :us) / n / 1000,
      ms_max: Enum.max(Enum.map(sides, & &1.us_max), fn -> 0 end) / 1000
    }
  end

  defp win(nil, _seat), do: 0.5
  defp win(winner, seat), do: if(winner == seat, do: 1.0, else: 0.0)

  defp sum(list, key), do: Enum.sum(Enum.map(list, &Map.fetch!(&1, key)))

  defp mean([]), do: 0.0
  defp mean(list), do: Enum.sum(list) / length(list)

  @doc """
  The half-width of a 95 % confidence interval for the mean of `samples` (normal
  approximation); `nil` for fewer than 2 samples.

      iex> Codex.AI.Bench.ci([1.0, 1.0, 1.0])
      0.0
  """
  @spec ci([number]) :: float | nil
  def ci(samples) when length(samples) < 2, do: nil

  def ci(samples) do
    n = length(samples)
    m = mean(samples)
    var = Enum.sum(Enum.map(samples, &((&1 - m) ** 2))) / (n - 1)
    @z * :math.sqrt(var / n)
  end
end
