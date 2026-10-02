defmodule Quacks.Session do
  @moduledoc """
  A game plus the `{seed, players, [{seat, action}]}` that built it. Undo = replay
  minus the last action, whichever seat made it.
  """

  import Kernel, except: [apply: 2, apply: 3]
  alias Quacks.Game

  defstruct seed: nil, players: 1, actions: [], game: nil

  @type t :: %__MODULE__{
          seed: {integer, integer, integer},
          players: 1..4,
          actions: [{Game.seat(), Game.action()}],
          game: Game.t()
        }

  @spec new({integer, integer, integer}, 1..4) :: t
  def new(seed, players \\ 1),
    do: %__MODULE__{seed: seed, players: players, game: Game.new(seed: seed, players: players)}

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
    do: %{s | actions: rest, game: replay(s.seed, s.players, rest)}

  # Actions are stored newest first.
  @spec replay({integer, integer, integer}, 1..4, [{Game.seat(), Game.action()}]) :: Game.t()
  def replay(seed, players, actions) do
    Enum.reduce(Enum.reverse(actions), Game.new(seed: seed, players: players), fn {seat, action},
                                                                                  game ->
      {:ok, game} = Game.apply(game, seat, action)
      game
    end)
  end
end
