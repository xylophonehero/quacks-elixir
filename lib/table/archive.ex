defmodule Table.Archive do
  @moduledoc """
  The archive file of a finished `Table.Server` room (Hearts, Codenames Duet, Codex,
  the generic games): `<games_dir>/finished/<game key>/<room code>.json`, written by
  `Quacks.GameStore.archive/4` when the game is over. Quacks keeps its own games
  in `finished/quacks/` with the same retention.

  The file holds what a replay needs: the game key, the room's `opts`, the seed and
  every action as `[seat, action]`, oldest first. `replay/1` plays them through the
  game's adapter again and gives the same final game. It also holds the seats
  (name, human or bot and the bot level), the final `status`, the `winners`, the
  app version and `finished_at`.

  **JSON encoding of terms** (`encode/1`, `decode/1`): an atom is a string; a
  string is `{"s": text}`; a tuple is an array; a list is `{"l": [...]}`; a map
  is `{"m": [[key, value], ...]}`; a `MapSet` is `{"set": [...]}`; another struct
  is `{"t": module, "m": fields}`; numbers, booleans and nil stay as they are. The
  decode makes no new atoms (`String.to_existing_atom/1`): an unknown name fails
  with `ArgumentError`. An adapter can encode its actions itself with the optional
  callbacks `encode_action/1` and `decode_action/1` (`Table.Server`).
  """

  @format 1

  @doc "The archive body of a finished room (JSON-ready)."
  @spec body(map, term) :: map
  def body(room, status) do
    adapter = room.adapter

    %{
      format: @format,
      game: room.key,
      id: room.code,
      finished_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      app_version: Quacks.BugReports.app_version(),
      seed: Tuple.to_list(room.seed),
      opts: encode(room.opts),
      seats:
        for {seat, s} <- Enum.sort(room.seats) do
          %{seat: seat, name: s.name, human: s.bot == nil, bot: s.bot && Atom.to_string(s.bot)}
        end,
      status: encode(status),
      winners: winners(adapter, room.game),
      log:
        room.log
        |> Enum.reverse()
        |> Enum.map(fn {seat, action} -> [seat, encode_action(adapter, action)] end)
    }
  end

  defp winners(adapter, game) do
    if function_exported?(adapter, :winners, 1), do: adapter.winners(game)
  end

  defp encode_action(adapter, action) do
    if function_exported?(adapter, :encode_action, 1),
      do: adapter.encode_action(action),
      else: encode(action)
  end

  defp decode_action(adapter, json) do
    if function_exported?(adapter, :decode_action, 1),
      do: adapter.decode_action(json),
      else: decode(json)
  end

  @doc """
  Play an archive body (decoded JSON, string keys) through its game's adapter
  again: `{:ok, game}` with the final game, or `{:error, reason}`.
  """
  @spec replay(map) :: {:ok, term} | {:error, term}
  def replay(%{"format" => @format, "game" => key, "seed" => [a, b, c], "log" => log} = body) do
    Quacks.Session.ensure_atoms()

    with %{game: adapter} <- Table.game(key) || {:error, :unknown_game},
         {:ok, game} <- adapter.new(decode(body["opts"]), {a, b, c}) do
      Enum.reduce_while(log, {:ok, game}, &step(adapter, &1, &2))
    end
  rescue
    error in [ArgumentError, FunctionClauseError, MatchError, KeyError] ->
      {:error, {:invalid, Exception.message(error)}}
  end

  def replay(_body), do: {:error, :not_an_archive}

  defp step(adapter, [seat, json], {:ok, game}) do
    case adapter.apply(game, seat, decode_action(adapter, json)) do
      {:ok, game} -> {:cont, {:ok, game}}
      {:error, reason} -> {:halt, {:error, {:illegal, seat, json, reason}}}
    end
  end

  @doc """
  A term as JSON-ready data (see the moduledoc).

      iex> Table.Archive.encode({:play, "x", [1, %{a: :b}]})
      ["play", %{s: "x"}, %{l: [1, %{m: [["a", "b"]]}]}]
  """
  @spec encode(term) :: term
  def encode(atom) when is_atom(atom) and atom not in [nil, true, false], do: Atom.to_string(atom)
  def encode(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&encode/1)
  def encode(list) when is_list(list), do: %{l: Enum.map(list, &encode/1)}
  def encode(%MapSet{} = set), do: %{set: set |> Enum.sort() |> Enum.map(&encode/1)}

  def encode(%module{} = struct),
    do: %{t: Atom.to_string(module), m: pairs(Map.from_struct(struct))}

  def encode(map) when is_map(map), do: %{m: pairs(map)}
  def encode(string) when is_binary(string), do: %{s: string}
  def encode(term), do: term

  defp pairs(map), do: map |> Enum.sort() |> Enum.map(fn {k, v} -> [encode(k), encode(v)] end)

  @doc """
  The term that `encode/1` wrote, from decoded JSON. Makes no new atoms.

      iex> Table.Archive.decode(["play", %{"s" => "x"}, %{"l" => [1, %{"m" => [["a", "b"]]}]}])
      {:play, "x", [1, %{a: :b}]}
  """
  @spec decode(term) :: term
  def decode(string) when is_binary(string), do: String.to_existing_atom(string)
  def decode(list) when is_list(list), do: list |> Enum.map(&decode/1) |> List.to_tuple()
  def decode(%{"s" => string}), do: string
  def decode(%{"l" => list}), do: Enum.map(list, &decode/1)
  def decode(%{"set" => list}), do: MapSet.new(list, &decode/1)

  def decode(%{"t" => module, "m" => fields}),
    do: struct!(String.to_existing_atom(module), decode_pairs(fields))

  def decode(%{"m" => fields}), do: decode_pairs(fields)
  def decode(term), do: term

  defp decode_pairs(fields), do: Map.new(fields, fn [k, v] -> {decode(k), decode(v)} end)
end
