defmodule Hearts.AI.Bench do
  @moduledoc """
  Plays seeded games with one `Hearts.AI.Heuristic` seat against `Hearts.AI.Random`
  seats and counts the wins. The heuristic seat moves one place each game. A shared
  win counts as `1 / winners`.

      iex> result = Hearts.AI.Bench.run(games: 2, seed: 1)
      iex> result.games
      2
  """

  alias Hearts.AI.{Heuristic, Random}
  alias Hearts.Game

  @doc """
  Options: `games` (default 100), `seed` (default 1), `opts` (the game options,
  default `%{}`). Returns `%{games, wins, win_rate, baseline, score_heuristic,
  score_random}`; `baseline` is the win rate of a random seat (1 / players).
  """
  @spec run(keyword) :: map()
  def run(opts \\ []) do
    games = Keyword.get(opts, :games, 100)
    seed = Keyword.get(opts, :seed, 1)
    game_opts = Keyword.get(opts, :opts, %{})

    results = for i <- 1..games//1, do: play_one(game_opts, seed, i)
    n = max(games, 1)
    players = game_opts |> Map.get(:players, 4)

    %{
      games: games,
      wins: Enum.sum(Enum.map(results, & &1.win)),
      win_rate: Enum.sum(Enum.map(results, & &1.win)) / n,
      baseline: 1 / players,
      score_heuristic: Enum.sum(Enum.map(results, & &1.mine)) / n,
      score_random: Enum.sum(Enum.map(results, & &1.others)) / n
    }
  end

  defp play_one(game_opts, seed, i) do
    {:ok, game} = Game.new(game_opts, {seed, i, 0})
    me = rem(i, length(game.seats))

    bots =
      Map.new(
        game.seats,
        &{&1, if(&1 == me, do: {Heuristic, nil}, else: {Random, Random.new({seed, i, &1 + 1})})}
      )

    game = loop(game, bots)

    others = for {seat, score} <- game.scores, seat != me, do: score
    win = if me in game.winners, do: 1 / length(game.winners), else: 0.0
    %{win: win, mine: game.scores[me], others: Enum.sum(others) / length(others)}
  end

  defp loop(game, bots) do
    case Game.status(game) do
      {:over, _} ->
        game

      {:playing, [seat | _]} ->
        {bot, state} = bots[seat]
        {action, state} = bot.choose(Game.view(game, seat), state)
        {:ok, game} = Game.apply(game, seat, action)
        loop(game, Map.put(bots, seat, {bot, state}))
    end
  end
end
