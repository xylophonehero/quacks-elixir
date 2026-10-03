defmodule Quacks.AI.Stall do
  @moduledoc "Raised by `Quacks.AI.Sim` when a game cannot go on: a bug in the engine or the bot."
  defexception [:message, :game]
end
