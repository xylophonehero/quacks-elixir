defmodule Quacks.AI.Sim do
  @moduledoc """
  Headless bot games for tuning (`docs/research/ai-opponents.md` §3.5). It loops the
  pure engine (`Game.new/1`, `Quacks.AI.decide/4`, `Game.apply/3`) until
  `Game.over?/1`; no processes. `mix quacks.sim` prints the summary as a table.
  """

  alias Quacks.AI
  alias Quacks.AI.{Profile, Stall}
  alias Quacks.Game

  @max_steps 20_000

  @doc """
  Play `games:` games (default 100) with one bot per entry of `profiles:` (e.g.
  `[:balanced, :cautious]`, seat order; a `Quacks.AI.Profile` struct works too, for
  tuning). `seed:` (integer, default 1) makes the run
  repeatable; `sets:`, `rules:`, `expansion:` and `expansions:` go to `Game.new/1`.

  Returns a summary per profile (seats with the same profile are pooled):

      %{games: 100, players: 2, profiles: %{balanced: %{
        seats: 100, vp_mean: 61.2, vp_sd: 9.8, win_rate: 0.55, explosion_rate: 0.31,
        explosions: %{1 => 0.4, ..., 9 => 0.2}, coins: %{1 => 9.1, ...},
        buys: %{red: 3.1, ...}}}}

  `win_rate` shares a tie; `explosions` is the share of rounds that exploded,
  `coins` the mean coins after the evaluation, `buys` the mean chips bought per game.
  """
  @spec run(keyword) :: map
  def run(opts) do
    profiles = Keyword.fetch!(opts, :profiles)
    seed = Keyword.get(opts, :seed, 1)
    game_opts = Keyword.take(opts, [:sets, :rules, :expansion, :expansions])

    seats =
      1..Keyword.get(opts, :games, 100)
      |> Task.async_stream(&seat_results(profiles, {seed, &1, 0}, game_opts),
        timeout: :infinity
      )
      |> Enum.flat_map(fn {:ok, seats} -> seats end)

    %{
      games: Keyword.get(opts, :games, 100),
      players: length(profiles),
      profiles: seats |> Enum.group_by(& &1.profile) |> Map.new(fn {p, s} -> {p, summary(s)} end)
    }
  end

  @doc """
  Play one game to the end. Returns the finished game and, per round, each seat's
  `{exploded?, coins}` after the evaluation. Raises `Quacks.AI.Stall` when nobody can
  act before the end or the game runs past #{@max_steps} actions, and `MatchError`
  on an illegal action.
  """
  @spec play([Profile.name() | Profile.t()], {integer, integer, integer}, keyword) ::
          {Game.t(), %{(1..9) => %{Game.seat() => {boolean, non_neg_integer}}}}
  def play(profiles, seed, game_opts \\ []) do
    game = Game.new([seed: seed, players: length(profiles)] ++ game_opts)
    bots = profiles |> Enum.with_index() |> Map.new(fn {p, s} -> {s, profile(p)} end)
    rngs = Map.new(bots, fn {seat, _} -> {seat, AI.new_rng(seed, seat)} end)
    loop(game, bots, rngs, %{}, 0)
  end

  defp profile(%Profile{} = profile), do: profile
  defp profile(name), do: Profile.get(name)

  defp loop(game, bots, rngs, rounds, steps) do
    cond do
      Game.over?(game) ->
        {game, rounds}

      steps > @max_steps ->
        raise Stall, message: "game ran past #{@max_steps} actions", game: game

      true ->
        {game, rngs, rounds, acted} =
          Enum.reduce(game.seats, {game, rngs, rounds, 0}, &act(&1, &2, bots))

        if acted == 0,
          do: raise(Stall, message: "nobody can act in round #{game.round}", game: game)

        loop(game, bots, rngs, rounds, steps + acted)
    end
  end

  # One action for `seat`, if it has one; note the round's results when the shop opens.
  defp act(seat, {game, rngs, rounds, acted} = acc, bots) do
    case AI.decide(game, seat, bots[seat], rngs[seat]) do
      :none ->
        acc

      {action, rng} ->
        {:ok, next} = Game.apply(game, seat, action)
        {next, Map.put(rngs, seat, rng), note(rounds, game, next), acted + 1}
    end
  end

  defp note(rounds, %{phase: :shopping}, _next), do: rounds

  defp note(rounds, _game, %{phase: :shopping} = next) do
    seats = Map.new(next.players, fn {seat, p} -> {seat, {p.exploded?, p.coins}} end)
    Map.put(rounds, next.round, seats)
  end

  defp note(rounds, _game, _next), do: rounds

  defp seat_results(profiles, seed, game_opts) do
    {game, rounds} = play(profiles, seed, game_opts)
    scores = Game.score(game)
    best = Enum.max(Map.values(scores))
    winners = Enum.count(scores, fn {_, vp} -> vp == best end)

    for {profile, seat} <- Enum.with_index(profiles) do
      %{
        profile: profile(profile).name,
        vp: scores[seat],
        win: if(scores[seat] == best, do: 1 / winners, else: 0.0),
        rounds: Map.new(rounds, fn {round, seats} -> {round, seats[seat]} end),
        buys: for({^seat, {:bought, chips}} <- game.log, {colour, _} <- chips, do: colour)
      }
    end
  end

  defp summary(seats) do
    n = length(seats)
    vps = Enum.map(seats, & &1.vp)
    mean = Enum.sum(vps) / n
    per_round = Enum.flat_map(seats, &Map.to_list(&1.rounds))

    explosions =
      per_round
      |> Enum.group_by(fn {round, _} -> round end, fn {_, {exploded?, _}} -> exploded? end)
      |> Map.new(fn {round, list} -> {round, Enum.count(list, & &1) / length(list)} end)

    coins =
      per_round
      |> Enum.group_by(fn {round, _} -> round end, fn {_, {_, coins}} -> coins end)
      |> Map.new(fn {round, list} -> {round, Enum.sum(list) / length(list)} end)

    %{
      seats: n,
      vp_mean: mean,
      vp_sd: :math.sqrt(Enum.sum(Enum.map(vps, &((&1 - mean) ** 2))) / n),
      win_rate: Enum.sum(Enum.map(seats, & &1.win)) / n,
      explosion_rate: Enum.count(per_round, fn {_, {e, _}} -> e end) / max(length(per_round), 1),
      explosions: explosions,
      coins: coins,
      buys:
        seats
        |> Enum.flat_map(& &1.buys)
        |> Enum.frequencies()
        |> Map.new(fn {c, k} -> {c, k / n} end)
    }
  end
end
