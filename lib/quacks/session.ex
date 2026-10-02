defmodule Quacks.Session do
  @moduledoc """
  A game plus the `{seed, players, sets, rules, [{seat, action}]}` that built it. Undo =
  replay minus the last action, whichever seat made it.
  """

  import Kernel, except: [apply: 2, apply: 3]
  alias Quacks.Game

  defstruct seed: nil, players: 1, sets: %{}, rules: %{}, actions: [], game: nil

  @type t :: %__MODULE__{
          seed: {integer, integer, integer},
          players: 1..4,
          sets: Quacks.Rules.Chips.sets(),
          rules: Game.rules(),
          actions: [{Game.seat(), Game.action()}],
          game: Game.t()
        }

  # The `Game.new/1` options a session passes on.
  @game_opts [:sets, :rules, :fortune]

  @doc """
  A new session. `opts`: `sets: %{green: 2}` picks Ingredient Sets, `rules:
  %{explode_above: 9}` sets house rules, `fortune: false` plays without Fortune
  Teller cards (see `Quacks.Game.new/1`).
  """
  @spec new({integer, integer, integer}, 1..4, sets: map, rules: map, fortune: boolean) :: t
  def new(seed, players \\ 1, opts \\ []) do
    game = new_game(seed, players, opts)
    %__MODULE__{seed: seed, players: players, sets: game.sets, rules: game.rules, game: game}
  end

  @doc "`apply/3` for seat 0."
  @spec apply(t, Game.action()) :: {:ok, t} | {:error, term}
  def apply(%__MODULE__{} = s, action), do: apply(s, 0, action)

  @spec apply(t, Game.seat(), Game.action()) :: {:ok, t} | {:error, term}
  def apply(%__MODULE__{} = s, seat, action) do
    with {:ok, game} <- Game.apply(s.game, seat, action),
         do: {:ok, %{s | game: game, actions: [{seat, action} | s.actions]}}
  end

  @spec undo(t) :: t
  def undo(%__MODULE__{actions: []} = s), do: s

  def undo(%__MODULE__{actions: [_ | rest]} = s),
    do: %{
      s
      | actions: rest,
        game: replay(s.seed, s.players, rest, sets: s.sets, rules: s.rules)
    }

  @doc "Rebuild a game from its actions (newest first). `opts` as in `new/3`."
  @spec replay({integer, integer, integer}, 1..4, [{Game.seat(), Game.action()}], keyword) ::
          Game.t()
  def replay(seed, players, actions, opts \\ []) do
    Enum.reduce(Enum.reverse(actions), new_game(seed, players, opts), fn {seat, action}, game ->
      {:ok, game} = Game.apply(game, seat, action)
      game
    end)
  end

  defp new_game(seed, players, opts),
    do: Game.new([seed: seed, players: players] ++ Keyword.take(opts, @game_opts))
end
