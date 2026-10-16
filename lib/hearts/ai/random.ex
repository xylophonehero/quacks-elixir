defmodule Hearts.AI.Random do
  @moduledoc """
  A bot that plays a random legal action. It has its own rng, so it does not move
  the game's random stream.

      iex> {:ok, game} = Hearts.Game.new(%{}, {1, 2, 3})
      iex> view = Hearts.Game.view(game, 0)
      iex> {action, _rng} = Hearts.AI.Random.choose(view, Hearts.AI.Random.new({4, 5, 6}))
      iex> action in view.legal_actions
      true
  """

  alias Table.Kit.Rng

  @doc "A bot state (an rng) from a seed."
  @spec new(Rng.seed()) :: Rng.t()
  def new(seed), do: Rng.seed(seed)

  @doc "A random action from `view.legal_actions` (see `Hearts.Game.view/2`)."
  @spec choose(map(), Rng.t()) :: {Hearts.Game.action(), Rng.t()}
  def choose(%{legal_actions: [_ | _] = actions}, rng), do: Rng.pick(actions, rng)
end
