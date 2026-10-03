defmodule Quacks.AI.Decider do
  @moduledoc """
  The contract of a bot: given the game, its seat, its profile and its own rng, pick
  one action from `Quacks.Game.legal_actions/2`, or `:none` when it does not act now.
  `Quacks.AI` is the heuristic implementation; a Jev bot can plug in later.
  """

  alias Quacks.AI.Profile
  alias Quacks.Game

  @callback decide(Game.t(), Game.seat(), Profile.t(), :rand.state()) ::
              {Game.action(), :rand.state()} | :none
end
