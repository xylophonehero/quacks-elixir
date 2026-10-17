defmodule CodenamesDuet.AI.Bench do
  @moduledoc """
  Seeded Duet games with a `CodenamesDuet.AI.Vectors` bot at both seats: how well
  two bots play together.

      iex> result = CodenamesDuet.AI.Bench.run(games: 2, seed: 1)
      iex> result.games
      2

  From a shell: `mix run -e 'IO.inspect(CodenamesDuet.AI.Bench.run(games: 200))'`.
  """

  alias CodenamesDuet.AI.Vectors
  alias CodenamesDuet.Game

  @max_steps 500

  @doc """
  Options: `games` (default 100), `seed` (default 1), `opts` (the game options,
  default `%{}`). Returns `%{games, wins, win_rate, mean_found, assassin_losses,
  assassin_rate, sudden_death_losses, mean_score, errors}` (`mean_score`: of the
  won games, rulebook §6.4).
  """
  @spec run(keyword) :: map
  def run(opts \\ []) do
    games = Keyword.get(opts, :games, 100)
    seed = Keyword.get(opts, :seed, 1)
    game_opts = Keyword.get(opts, :opts, %{})

    results = for i <- 1..games//1, do: play_one(game_opts, {seed, i, 0})
    n = max(games, 1)
    won = Enum.filter(results, &(&1.result == :won))
    assassin = Enum.count(results, &(&1.reason == :assassin))

    %{
      games: games,
      wins: length(won),
      win_rate: length(won) / n,
      mean_found: Enum.sum(Enum.map(results, & &1.found)) / n,
      assassin_losses: assassin,
      assassin_rate: assassin / n,
      sudden_death_losses: Enum.count(results, &(&1.reason == :sudden_death)),
      mean_score: if(won == [], do: nil, else: Enum.sum(Enum.map(won, & &1.score)) / length(won)),
      errors: Enum.flat_map(results, & &1.errors)
    }
  end

  @doc """
  One bot + bot game from `seed`: `%{result, reason, found, score, steps, errors}`.
  `errors` lists each action the engine refused (the game stops there: `result`
  is then `:error`).
  """
  @spec play_one(map, {integer, integer, integer}) :: map
  def play_one(game_opts, {a, b, c} = seed) do
    {:ok, game} = Game.new(game_opts, seed)
    bots = %{0 => Vectors.new({a + 1, b, c}), 1 => Vectors.new({a + 2, b, c})}
    loop(game, bots, 0)
  end

  defp loop(game, _bots, steps) when steps > @max_steps,
    do: summary(game, :error, steps, [{:too_many_steps, steps}])

  defp loop(game, bots, steps) do
    case Game.status(game) do
      {:over, %{result: result}} ->
        summary(game, result, steps, [])

      {:playing, [seat | _]} ->
        {action, bot} = Vectors.choose(Game.view(game, seat), bots[seat])

        case Game.apply(game, seat, action) do
          {:ok, game} -> loop(game, Map.put(bots, seat, bot), steps + 1)
          {:error, reason} -> summary(game, :error, steps, [{seat, action, reason}])
        end
    end
  end

  defp summary(game, result, steps, errors),
    do: %{
      result: result,
      reason: game.reason,
      found: Game.found(game),
      score: Game.score(game),
      steps: steps,
      errors: errors
    }
end
