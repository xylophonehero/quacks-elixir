defmodule Table do
  @moduledoc """
  The table games other than Quacks (Hearts first). The list is in config
  (`config :quacks, Table, games: ...`), so the web layer finds a game's server
  adapter, board and set-up page by its key and not by a compile-time reference
  (RFC `docs/design/table-game.md` §11, "board lookup").

  Each entry: `name`, `blurb`, `game` (a `Table.Server` adapter), `board` (a
  `TableWeb.Board`), `setup` (the path of its set-up page) and `icon` (its mark on
  the `/games` list).
  """

  @doc "Every table game, by key."
  @spec games() :: %{String.t() => map}
  def games, do: :quacks |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(:games)

  @doc "The game with key `key`, or nil. Never makes an atom from `key`."
  @spec game(String.t()) :: map | nil
  def game(key) when is_binary(key), do: Map.get(games(), key)
end
