defmodule Quacks.AI.Expert do
  @moduledoc """
  Round 43 (Nick): the "Expert" profile, the profile of the table bots
  (`Quacks.GameServer`). It is the tuned weights file `priv/bots/tuned.json`
  (`Quacks.AI.Weights`, `docs/research/bot-training.md`), read one time at compile
  time. A change to the file recompiles this module.
  """

  alias Quacks.AI.{Profile, Weights}

  @path Path.expand("../../../priv/bots/tuned.json", __DIR__)
  @external_resource @path

  {:ok, tuned} = Weights.load(@path)
  @profile %{tuned | name: :expert, bot_name: "Expert Esme", label: "Expert"}

  @doc "The tuned profile, named `:expert`."
  @spec profile() :: Profile.t()
  def profile, do: @profile
end
