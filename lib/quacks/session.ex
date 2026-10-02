defmodule Quacks.Session do
  @moduledoc """
  A game plus the `{seed, players, fortune, [{seat, action}]}` that built it. Undo =
  replay minus the last action, whichever seat made it.
  """

  import Kernel, except: [apply: 2, apply: 3]
  alias Quacks.Game

  defstruct seed: nil, players: 1, fortune: true, actions: [], game: nil

  @type t :: %__MODULE__{
          seed: {integer, integer, integer},
          players: 1..4,
          fortune: boolean,
          actions: [{Game.seat(), Game.action()}],
          game: Game.t()
        }

  @doc "A new session. `opts`: `fortune: false` plays without Fortune Teller cards."
  @spec new({integer, integer, integer}, 1..4, fortune: boolean) :: t
  def new(seed, players \\ 1, opts \\ []) do
    fortune = Keyword.get(opts, :fortune, true)

    %__MODULE__{
      seed: seed,
      players: players,
      fortune: fortune,
      game: Game.new(seed: seed, players: players, fortune: fortune)
    }
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
    do: %{s | actions: rest, game: replay(s.seed, s.players, rest, fortune: s.fortune)}

  # Actions are stored newest first.
  @spec replay({integer, integer, integer}, 1..4, [{Game.seat(), Game.action()}], keyword) ::
          Game.t()
  def replay(seed, players, actions, opts \\ []) do
    game = Game.new(seed: seed, players: players, fortune: Keyword.get(opts, :fortune, true))

    Enum.reduce(Enum.reverse(actions), game, fn {seat, action}, game ->
      {:ok, game} = Game.apply(game, seat, action)
      game
    end)
  end
end
