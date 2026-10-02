defmodule Quacks.Session do
  @moduledoc """
  A game plus the `{seed, players, fortune, sets, [{seat, action}]}` that built it. Undo =
  replay minus the last action, whichever seat made it.
  """

  import Kernel, except: [apply: 2, apply: 3]
  alias Quacks.Game

  defstruct seed: nil, players: 1, fortune: true, sets: %{}, actions: [], game: nil

  @type t :: %__MODULE__{
          seed: {integer, integer, integer},
          players: 1..4,
          fortune: boolean,
          sets: Quacks.Rules.Chips.sets(),
          actions: [{Game.seat(), Game.action()}],
          game: Game.t()
        }

  @doc """
  A new session. `opts`: `fortune: false` plays without Fortune Teller cards;
  `sets: %{green: 2}` picks Ingredient Sets (see `Quacks.Game.new/1`).
  """
  @spec new({integer, integer, integer}, 1..4, fortune: boolean, sets: map) :: t
  def new(seed, players \\ 1, opts \\ []) do
    fortune = Keyword.get(opts, :fortune, true)
    sets = Keyword.get(opts, :sets, %{})

    %__MODULE__{
      seed: seed,
      players: players,
      fortune: fortune,
      sets: sets,
      game: Game.new(seed: seed, players: players, fortune: fortune, sets: sets)
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
    do: %{
      s
      | actions: rest,
        game: replay(s.seed, s.players, rest, fortune: s.fortune, sets: s.sets)
    }

  @doc "Rebuild a game from its actions (newest first). `opts` as in `new/3`."
  @spec replay({integer, integer, integer}, 1..4, [{Game.seat(), Game.action()}], keyword) ::
          Game.t()
  def replay(seed, players, actions, opts \\ []) do
    game =
      Game.new(
        seed: seed,
        players: players,
        fortune: Keyword.get(opts, :fortune, true),
        sets: Keyword.get(opts, :sets, %{})
      )

    Enum.reduce(Enum.reverse(actions), game, fn {seat, action}, game ->
      {:ok, game} = Game.apply(game, seat, action)
      game
    end)
  end
end
