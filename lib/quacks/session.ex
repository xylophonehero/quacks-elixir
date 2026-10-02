defmodule Quacks.Session do
  @moduledoc "A game plus the `{seed, actions}` that built it. Undo = replay minus the last action."

  import Kernel, except: [apply: 2]
  alias Quacks.Game

  defstruct seed: nil, actions: [], game: nil

  @type t :: %__MODULE__{
          seed: {integer, integer, integer},
          actions: [Game.action()],
          game: Game.t()
        }

  @spec new({integer, integer, integer}) :: t
  def new(seed), do: %__MODULE__{seed: seed, game: Game.new(seed: seed)}

  @spec apply(t, Game.action()) :: {:ok, t} | {:error, term}
  def apply(%__MODULE__{} = s, action) do
    with {:ok, game} <- Game.apply(s.game, action),
         do: {:ok, %{s | game: game, actions: [action | s.actions]}}
  end

  @spec undo(t) :: t
  def undo(%__MODULE__{actions: []} = s), do: s

  def undo(%__MODULE__{actions: [_ | rest]} = s),
    do: %{s | actions: rest, game: replay(s.seed, rest)}

  # Actions are stored newest first.
  @spec replay({integer, integer, integer}, [Game.action()]) :: Game.t()
  def replay(seed, actions) do
    Enum.reduce(Enum.reverse(actions), Game.new(seed: seed), fn action, game ->
      {:ok, game} = Game.apply(game, action)
      game
    end)
  end
end
