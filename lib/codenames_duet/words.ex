defmodule CodenamesDuet.Words do
  @moduledoc """
  The word list of Codenames Duet: `priv/games/codenames_duet/words.txt`, one
  word in lower case per line. Source and licence: `docs/CREDITS.md`.
  """

  @path Path.join([__DIR__, "..", "..", "priv", "games", "codenames_duet", "words.txt"])
  @external_resource @path
  @words @path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&String.trim/1)

  @doc """
  All the words.

      iex> length(CodenamesDuet.Words.all()) >= 400
      true
  """
  @spec all() :: [String.t()]
  def all, do: @words
end
