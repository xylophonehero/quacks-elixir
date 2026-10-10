defmodule Quacks.AI.Bench do
  @moduledoc """
  The bot benchmark (`docs/research/bot-training.md` §3): headless games with the
  pure engine, a win rate and a mean VP with a 95 % confidence interval per bot, and
  the time per decision. `mix quacks.bench` prints it.

  **Duplicate seating.** With `k` bots, every game seed is played `k` times, and the
  bots move one seat on each time (seat `s` gets bot `rem(s + r, k)` in rotation `r`).
  So every bot gets the same chips and the same seats, and luck cancels out much
  faster than with one game per seed. The confidence intervals treat one seed (its
  `k` games) as one sample.

  **CPU.** At most `jobs:` games run at a time (default: half the cores).
  """

  alias Quacks.AI
  alias Quacks.AI.{Profile, Stall}
  alias Quacks.Game

  @max_steps 20_000
  @z 1.96

  @typedoc "The summary of one bot (seats with the same profile name are pooled)."
  @type bot_summary :: %{
          name: atom,
          seats: non_neg_integer,
          win_rate: float,
          win_ci: float | nil,
          vp_mean: float,
          vp_ci: float | nil,
          explosion_rate: float,
          decisions: %{atom => %{n: non_neg_integer, us_mean: float, us_max: non_neg_integer}}
        }

  @doc "Half the scheduler threads, at least 1: the default `jobs:`."
  @spec default_jobs() :: pos_integer
  def default_jobs, do: max(div(System.schedulers_online(), 2), 1)

  @doc """
  Play the benchmark. Options:

  - `bots:` (required) a list of `Quacks.AI.Profile` structs or profile names.
  - `players:` seats per game (default: the number of bots). With more seats than
    bots, the bots repeat in order (`[a, b]` at 4 seats: `a, b, a, b`).
  - `games:` games to play (default 1000), rounded up to a multiple of the number
    of bots.
  - `seed:` an integer (default 1). The same seed gives the same games.
  - `jobs:` games at the same time (default `default_jobs/0`).
  - `minutes:` a time budget. No new batch starts after it; the result covers the
    games played.
  - `progress:` a function that gets `%{done: n, total: n, seconds: s}` after each
    batch.
  - `sets:`, `rules:`, `expansions:` go to `Quacks.Game.new/1`.

  Returns `%{games:, seeds:, players:, seconds:, games_per_s:, jobs:, bots: [bot_summary]}`,
  the bots in the order given (duplicates once).
  """
  @spec run(keyword) :: map
  def run(opts) do
    bots = opts |> Keyword.fetch!(:bots) |> Enum.map(&profile/1)
    k = length(bots)
    players = Keyword.get(opts, :players, max(k, 2))
    seeds = ceil(Keyword.get(opts, :games, 1000) / k)
    jobs = Keyword.get(opts, :jobs, default_jobs())
    seed = Keyword.get(opts, :seed, 1)
    game_opts = Keyword.take(opts, [:sets, :rules, :expansion, :expansions])
    progress = Keyword.get(opts, :progress, fn _ -> :ok end)
    started = System.monotonic_time(:millisecond)
    deadline = deadline(opts[:minutes], started)

    results =
      0..(seeds - 1)//1
      |> Enum.chunk_every(jobs * 4)
      |> Enum.reduce_while([], fn chunk, acc ->
        if past?(deadline) do
          {:halt, acc}
        else
          done =
            chunk
            |> Task.async_stream(&play_seed(bots, players, {seed, &1 + 1, 0}, game_opts),
              max_concurrency: jobs,
              timeout: :infinity,
              ordered: true
            )
            |> Enum.map(fn {:ok, seed_result} -> seed_result end)

          acc = acc ++ done
          seconds = (System.monotonic_time(:millisecond) - started) / 1000
          progress.(%{done: length(acc) * k, total: seeds * k, seconds: seconds})
          {:cont, acc}
        end
      end)

    seconds = (System.monotonic_time(:millisecond) - started) / 1000
    games = length(results) * k

    %{
      games: games,
      seeds: length(results),
      players: players,
      jobs: jobs,
      seconds: seconds,
      games_per_s: if(seconds > 0, do: games / seconds, else: 0.0),
      bots: summaries(bots, results)
    }
  end

  @doc """
  The bot in each seat for rotation `r`: seat `s` gets `rem(s + r, k)` of the `k` bots.

      iex> Quacks.AI.Bench.lineup([:a, :b], 4, 1)
      [:b, :a, :b, :a]
  """
  @spec lineup([term], pos_integer, non_neg_integer) :: [term]
  def lineup(bots, players, r) do
    k = length(bots)
    for s <- 0..(players - 1), do: Enum.at(bots, rem(s + r, k))
  end

  @doc """
  Play one game to the end with `profiles` (one per seat). Returns the finished game
  and per seat `%{exploded: rounds, rounds: rounds, decisions: %{phase => {n, us, max_us}}}`.
  """
  @spec play([Profile.t()], {integer, integer, integer}, keyword) :: {Game.t(), map}
  def play(profiles, seed, game_opts \\ []) do
    game = Game.new([seed: seed, players: length(profiles)] ++ game_opts)
    bots = profiles |> Enum.with_index() |> Map.new(fn {p, s} -> {s, p} end)
    rngs = Map.new(bots, fn {seat, _} -> {seat, AI.new_rng(seed, seat)} end)
    stats = Map.new(bots, fn {seat, _} -> {seat, %{exploded: 0, rounds: 0, decisions: %{}}} end)
    loop(game, bots, rngs, stats, 0)
  end

  defp profile(%Profile{} = profile), do: profile
  defp profile(name) when is_atom(name), do: Profile.get(name)

  defp deadline(nil, _started), do: nil
  defp deadline(minutes, started), do: started + round(minutes * 60_000)

  defp past?(nil), do: false
  defp past?(deadline), do: System.monotonic_time(:millisecond) >= deadline

  # One seed: every rotation of the bots. Per rotation, per seat: {bot index, result}.
  defp play_seed(bots, players, seed, game_opts) do
    k = length(bots)
    indexed = Enum.with_index(bots)

    for r <- 0..(k - 1) do
      seating = lineup(indexed, players, r)
      {game, stats} = play(Enum.map(seating, &elem(&1, 0)), seed, game_opts)
      scores = Game.score(game)
      best = scores |> Map.values() |> Enum.max()
      winners = Enum.count(scores, fn {_, vp} -> vp == best end)

      for {{_profile, i}, seat} <- Enum.with_index(seating) do
        win = if scores[seat] == best, do: 1 / winners, else: 0.0
        {i, Map.merge(stats[seat], %{vp: scores[seat], win: win})}
      end
    end
  end

  defp loop(game, bots, rngs, stats, steps) do
    cond do
      Game.over?(game) ->
        {game, stats}

      steps > @max_steps ->
        raise Stall, message: "game ran past #{@max_steps} actions", game: game

      true ->
        {game, rngs, stats, acted} =
          Enum.reduce(game.seats, {game, rngs, stats, 0}, &act(&1, &2, bots))

        if acted == 0,
          do: raise(Stall, message: "nobody can act in round #{game.round}", game: game)

        loop(game, bots, rngs, stats, steps + acted)
    end
  end

  defp act(seat, {game, rngs, stats, acted} = acc, bots) do
    phase = Game.phase(game, seat)
    {us, decision} = :timer.tc(fn -> AI.decide(game, seat, bots[seat], rngs[seat]) end)

    case decision do
      :none ->
        acc

      {action, rng} ->
        {:ok, next} = Game.apply(game, seat, action)
        stats = stats |> timed(seat, phase, us) |> rounds(game, next)
        {next, Map.put(rngs, seat, rng), stats, acted + 1}
    end
  end

  defp timed(stats, seat, phase, us) do
    update_in(stats, [seat, :decisions], fn d ->
      Map.update(d, phase, {1, us, us}, fn {n, sum, max} -> {n + 1, sum + us, max(max, us)} end)
    end)
  end

  # When the shop opens, note who exploded this round.
  defp rounds(stats, %{phase: :shopping}, _next), do: stats

  defp rounds(stats, _game, %{phase: :shopping} = next) do
    Map.new(stats, fn {seat, s} ->
      e = if next.players[seat].exploded?, do: 1, else: 0
      {seat, %{s | exploded: s.exploded + e, rounds: s.rounds + 1}}
    end)
  end

  defp rounds(stats, _game, _next), do: stats

  # -- summary --------------------------------------------------------------------------

  defp summaries(bots, results) do
    names = bots |> Enum.with_index() |> Enum.map(fn {p, i} -> {p.name, i} end)
    order = names |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    by_name = Enum.group_by(names, &elem(&1, 0), &elem(&1, 1))

    for name <- order do
      ids = by_name[name]
      per_seed = Enum.map(results, &seed_seats(&1, ids))
      seats = List.flatten(per_seed)
      summary(name, seats, per_seed)
    end
  end

  defp seed_seats(rotations, ids),
    do: for(rotation <- rotations, {i, s} <- rotation, i in ids, do: s)

  defp summary(name, [], _per_seed),
    do: %{
      name: name,
      seats: 0,
      win_rate: 0.0,
      win_ci: nil,
      vp_mean: 0.0,
      vp_ci: nil,
      explosion_rate: 0.0,
      decisions: %{}
    }

  defp summary(name, seats, per_seed) do
    rounds = seats |> Enum.map(& &1.rounds) |> Enum.sum()

    %{
      name: name,
      seats: length(seats),
      win_rate: mean(Enum.map(seats, & &1.win)),
      win_ci: ci(Enum.map(per_seed, fn s -> mean(Enum.map(s, & &1.win)) end)),
      vp_mean: mean(Enum.map(seats, & &1.vp)),
      vp_ci: ci(Enum.map(per_seed, fn s -> mean(Enum.map(s, & &1.vp)) end)),
      explosion_rate: Enum.sum(Enum.map(seats, & &1.exploded)) / max(rounds, 1),
      decisions: decisions(seats)
    }
  end

  defp decisions(seats) do
    seats
    |> Enum.flat_map(&Map.to_list(&1.decisions))
    |> Enum.reduce(%{}, fn {phase, {n, sum, max}}, acc ->
      Map.update(acc, phase, {n, sum, max}, fn {n0, s0, m0} ->
        {n0 + n, s0 + sum, max(m0, max)}
      end)
    end)
    |> Map.new(fn {phase, {n, sum, max}} -> {phase, %{n: n, us_mean: sum / n, us_max: max}} end)
  end

  @doc """
  The half-width of a 95 % confidence interval for the mean of `samples` (normal
  approximation); `nil` for fewer than 2 samples.

      iex> Quacks.AI.Bench.ci([1.0, 1.0, 1.0])
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

  defp mean([]), do: 0.0
  defp mean(list), do: Enum.sum(list) / length(list)
end
