defmodule Table.Generic.Spec do
  @moduledoc """
  A game spec: the data that sets up a table for `Table.Generic.Game`. It is a
  JSON object (the fixtures are in `priv/games/generic/*.json`, read at compile
  time), or the same map in Elixir with string keys.

      {
        "name": "crazy_eights",            // the key
        "title": "Crazy Eights",
        "players": {"min": 2, "max": 5},
        "deck": "standard52",              // or a list: "QS", or {"id": "a1", "name": "Apple"}
        "referee": "crazy_eights",         // a key of the referee list, or null
        "zones": [
          {"id": "deck", "visibility": "hidden", "layout": "pile", "deck": true},
          {"id": "hand", "per_seat": true, "visibility": "owner", "layout": "hand"}
        ],
        "counters": [{"id": "score", "per_seat": true, "value": 0}],
        "setup": [{"op": "shuffle", "zone": "deck"}, ...]
      }

  - A zone with `per_seat` is one zone per seat: `"hand:0"`, `"hand:1"`, ...
    owned by that seat. `visibility`: `public`, `owner` or `hidden`. `layout`
    tells the board how to draw it: `hand` (a fan, or backs for the others),
    `pile` (the top card, or a back), `row` (every card). The zone with
    `deck: true` holds every card at the start, in deck order.
  - A counter with `per_seat` is `"score:0"`, ... `value` is the start value
    (an integer or a string). `show: false` hides it on the board.
  - `setup`: ops (`Table.Generic.Ops`, JSON form) applied by `Game.new/2`. In
    setup only, a `deal`'s `n` can depend on the player count:
    `{"2": 7, "*": 5}`, and `"hand:*"` is every seat's hand.

  A standard card id is its short text: `"QS"`, `"10H"` (rank 2..10, J, Q, K,
  A; suit C, D, H, S), as `TableWeb.Components.Cards.code/1`.
  """

  alias Table.Generic.Ops
  alias Table.Kit.PlayingCards

  @type zone_spec :: %{
          id: String.t(),
          base: String.t(),
          seat: non_neg_integer | nil,
          label: String.t(),
          visibility: :public | :owner | :hidden,
          layout: :hand | :pile | :row
        }

  @type t :: %{
          name: String.t(),
          title: String.t(),
          players: Range.t(),
          referee: String.t() | nil,
          cards: [String.t()],
          names: %{String.t() => String.t()},
          zones: [map],
          counters: [map],
          setup: [map]
        }

  @dir Path.expand("../../../priv/games/generic", __DIR__)
  @files Path.wildcard(Path.join(@dir, "*.json"))
  for file <- @files, do: @external_resource(file)

  @fixtures Map.new(@files, fn file ->
              json = file |> File.read!() |> Jason.decode!()
              {json["name"], json}
            end)

  @visibilities %{"public" => :public, "owner" => :owner, "hidden" => :hidden}
  @layouts %{"hand" => :hand, "pile" => :pile, "row" => :row}
  @suits %{"C" => :clubs, "D" => :diamonds, "H" => :hearts, "S" => :spades}
  @letters Map.new(@suits, fn {l, s} -> {s, l} end)
  @faces %{11 => "J", 12 => "Q", 13 => "K", 14 => "A"}

  @doc "The fixture specs (JSON, decoded), by name."
  @spec fixtures() :: %{String.t() => map}
  def fixtures, do: @fixtures

  @doc "The fixture spec `name` (JSON, decoded), or nil. Never makes an atom."
  @spec fixture(String.t()) :: map | nil
  def fixture(name) when is_binary(name), do: Map.get(@fixtures, name)

  # -- cards ---------------------------------------------------------------------------

  @doc """
  The id of a standard card.

      iex> Table.Generic.Spec.card_id({12, :spades})
      "QS"
  """
  @spec card_id(PlayingCards.card()) :: String.t()
  def card_id({rank, suit}), do: Map.get(@faces, rank, Integer.to_string(rank)) <> @letters[suit]

  @doc """
  The standard card of an id, or nil.

      iex> Table.Generic.Spec.standard("10H")
      {10, :hearts}
      iex> Table.Generic.Spec.standard("apple")
      nil
  """
  @spec standard(String.t()) :: PlayingCards.card() | nil
  def standard(id) when is_binary(id) do
    with {rank, letter} <- String.split_at(id, -1),
         {:ok, suit} <- Map.fetch(@suits, letter),
         r when r in 2..14 <- rank(rank) do
      {r, suit}
    else
      _ -> nil
    end
  end

  def standard(_id), do: nil

  defp rank(text) do
    case Enum.find(@faces, fn {_r, l} -> l == text end) do
      {r, _} ->
        r

      nil ->
        case Integer.parse(text) do
          {r, ""} when r in 2..10 -> r
          _ -> nil
        end
    end
  end

  # -- normalise -----------------------------------------------------------------------

  @doc """
  The spec in Elixir form, checked: a fixture name or a JSON map. Returns
  `{:ok, spec}` or `{:error, reason}`.
  """
  @spec normalise(String.t() | map) :: {:ok, t} | {:error, term}
  def normalise(name) when is_binary(name) do
    case fixture(name) do
      nil -> {:error, {:unknown_spec, name}}
      json -> normalise(json)
    end
  end

  def normalise(%{} = json) do
    with {:ok, players} <- players(json["players"]),
         {:ok, cards, names} <- deck(json["deck"]),
         {:ok, zones} <- list(json["zones"], &zone/1, :bad_zones),
         :ok <- one_deck(zones),
         {:ok, counters} <- list(Map.get(json, "counters", []), &counter/1, :bad_counters),
         setup when is_list(setup) <- Map.get(json, "setup", []) do
      {:ok,
       %{
         name: to_string(json["name"] || "custom"),
         title: to_string(json["title"] || json["name"] || "Card game"),
         players: players,
         referee: json["referee"],
         cards: cards,
         names: names,
         zones: zones,
         counters: counters,
         setup: setup
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :bad_setup}
    end
  end

  def normalise(_spec), do: {:error, :bad_spec}

  defp players(%{"min" => min, "max" => max})
       when is_integer(min) and is_integer(max) and min >= 1 and max >= min and max <= 12,
       do: {:ok, min..max}

  defp players(_), do: {:error, :bad_players}

  defp deck("standard52") do
    cards = Enum.map(PlayingCards.deck(), &card_id/1)
    {:ok, cards, Map.new(PlayingCards.deck(), &{card_id(&1), PlayingCards.name(&1)})}
  end

  defp deck([_ | _] = list) do
    entries =
      Enum.map(list, fn
        id when is_binary(id) and id != "" -> {id, default_name(id)}
        %{"id" => id} = c when is_binary(id) and id != "" -> {id, to_string(c["name"] || id)}
        _ -> nil
      end)

    ids = Enum.map(entries, &(&1 && elem(&1, 0)))

    cond do
      nil in entries -> {:error, :bad_deck}
      length(Enum.uniq(ids)) != length(ids) -> {:error, :duplicate_cards}
      true -> {:ok, ids, Map.new(entries)}
    end
  end

  defp deck(_), do: {:error, :bad_deck}

  defp default_name(id) do
    case standard(id) do
      nil -> id
      card -> PlayingCards.name(card)
    end
  end

  defp list(items, fun, error) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, x} -> {:cont, {:ok, [x | acc]}}
        :error -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, xs} -> {:ok, Enum.reverse(xs)}
      e -> e
    end
  end

  defp list(_items, _fun, error), do: {:error, error}

  defp zone(%{"id" => id} = z) when is_binary(id) and id != "" do
    per_seat = Map.get(z, "per_seat", false) == true
    vis = Map.get(@visibilities, Map.get(z, "visibility", "public"))
    layout = Map.get(@layouts, Map.get(z, "layout", "row"))

    if vis && layout && not String.contains?(id, ":") && (vis != :owner or per_seat) do
      {:ok,
       %{
         id: id,
         label: to_string(z["label"] || id),
         per_seat: per_seat,
         visibility: vis,
         layout: layout,
         deck: z["deck"] == true
       }}
    else
      :error
    end
  end

  defp zone(_), do: :error

  defp one_deck(zones) do
    case Enum.filter(zones, & &1.deck) do
      [%{per_seat: false}] -> :ok
      _ -> {:error, :one_deck_zone}
    end
  end

  defp counter(%{"id" => id} = c) when is_binary(id) and id != "" do
    value = Map.get(c, "value", 0)

    if (is_integer(value) or is_binary(value)) and not String.contains?(id, ":") do
      {:ok,
       %{
         id: id,
         label: to_string(c["label"] || id),
         per_seat: c["per_seat"] == true,
         value: value,
         show: c["show"] != false
       }}
    else
      :error
    end
  end

  defp counter(_), do: :error

  # -- per player count ------------------------------------------------------------------

  @doc """
  The zones of a table of `players` seats: `%{id => zone_spec}`. A per-seat zone
  `"hand"` gives `"hand:0"`, `"hand:1"`, ...
  """
  @spec zones(t, pos_integer) :: [zone_spec]
  def zones(spec, players) do
    Enum.flat_map(spec.zones, &seat_zones(&1, players))
  end

  defp seat_zones(%{per_seat: true} = z, players),
    do: for(s <- 0..(players - 1), do: Map.merge(z, %{id: "#{z.id}:#{s}", base: z.id, seat: s}))

  defp seat_zones(z, _players), do: [Map.merge(z, %{base: z.id, seat: nil})]

  @doc "The counters of a table of `players` seats: `%{id => start value}`."
  @spec counters(t, pos_integer) :: %{String.t() => integer | String.t()}
  def counters(spec, players) do
    Enum.reduce(spec.counters, %{}, fn c, acc ->
      if c.per_seat,
        do: Enum.reduce(0..(players - 1), acc, &Map.put(&2, "#{c.id}:#{&1}", c.value)),
        else: Map.put(acc, c.id, c.value)
    end)
  end

  @doc """
  The setup ops for `players` seats: a `deal`'s `n` taken from the player count.
  """
  @spec setup(t, pos_integer) :: {:ok, [Ops.t()]} | {:error, term}
  def setup(spec, players) do
    spec.setup
    |> Enum.map(fn
      %{"op" => "deal", "n" => %{} = by} = op ->
        Map.put(op, "n", Map.get(by, Integer.to_string(players), by["*"]))

      op ->
        op
    end)
    |> Ops.decode()
  end
end
