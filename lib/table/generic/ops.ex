defmodule Table.Generic.Ops do
  @moduledoc """
  The operations of `Table.Generic.Game`: a closed set of changes to the table.
  A referee (scripted now, an LLM later) never writes the state. It returns a
  list of operations, and the engine checks and applies them
  (`Table.Generic.Game.apply_ops/2`).

  ## The operations (Elixir form)

  | Operation | Effect |
  |---|---|
  | `{:move, card, from, to}` | `card` is a card id, `{:top, n}` or `:all`. The cards go on top of `to`, in their order. |
  | `{:shuffle, zone}` | A random order (the game's rng). |
  | `{:deal, n, from, [to]}` | `n` cards to each zone of `to`, one at a time, from the top. A `"hand:*"` in `to` is every seat's `hand`. |
  | `{:flip, zone, visibility}` | The zone becomes `:public`, `:owner` or `:hidden`. |
  | `{:set, counter, value}` | `value` is an integer or a string. |
  | `{:add, counter, delta}` | The counter must be an integer. |
  | `{:turn, seat}` | Whose turn it is. |
  | `{:phase, name}` | A free name (a string). |
  | `{:ask, seat, prompt, options}` | The prompt to `seat`: an option is a string (a choice) or `{:card, zone, card}` (play that card). |
  | `{:end, scores}` | The game is over: `%{seat => number}`. |

  Zones and counters are strings: `"deck"`, or `"hand:2"` for seat 2's zone.

  ## JSON

  `schema/0` is the JSON schema of `{"ops": [...]}`. An LLM referee is forced to
  it. `decode/1` makes the Elixir form from decoded JSON and checks the shape;
  `encode/1` is the inverse. The engine checks the rest (a zone exists, a card
  is in it). `decode/1` makes no atom from the input.
  """

  @type zone :: String.t()
  @type card :: String.t()
  @type seat :: non_neg_integer
  @type visibility :: :public | :owner | :hidden
  @type option :: String.t() | {:card, zone, card}

  @type t ::
          {:move, card | {:top, pos_integer} | :all, zone, zone}
          | {:shuffle, zone}
          | {:deal, pos_integer, zone, [zone]}
          | {:flip, zone, visibility}
          | {:set, String.t(), integer | String.t()}
          | {:add, String.t(), integer}
          | {:turn, seat}
          | {:phase, String.t()}
          | {:ask, seat, String.t(), [option]}
          | {:end, %{seat => number}}

  @visibilities %{"public" => :public, "owner" => :owner, "hidden" => :hidden}

  # -- JSON schema ---------------------------------------------------------------------

  @doc """
  The JSON schema of a referee's answer: `{"ops": [op, ...]}`. Every op is an
  object with an `"op"` name and no other keys than its own.
  """
  @spec schema() :: map
  def schema do
    %{
      "type" => "object",
      "properties" => %{"ops" => %{"type" => "array", "items" => %{"anyOf" => op_schemas()}}},
      "required" => ["ops"],
      "additionalProperties" => false
    }
  end

  defp op_schemas do
    zone = %{"type" => "string", "description" => "a zone id: \"deck\" or \"hand:0\""}
    seat = %{"type" => "integer", "minimum" => 0}

    [
      op("move", %{"card" => %{"type" => "string"}, "from" => zone, "to" => zone}),
      op("move", %{"top" => %{"type" => "integer", "minimum" => 1}, "from" => zone, "to" => zone}),
      op("move", %{"all" => %{"const" => true}, "from" => zone, "to" => zone}),
      op("shuffle", %{"zone" => zone}),
      op("deal", %{
        "n" => %{"type" => "integer", "minimum" => 1},
        "from" => zone,
        "to" => %{"type" => "array", "items" => zone, "minItems" => 1}
      }),
      op("flip", %{"zone" => zone, "visibility" => %{"enum" => Map.keys(@visibilities)}}),
      op("set", %{
        "counter" => %{"type" => "string"},
        "value" => %{"type" => ["integer", "string"]}
      }),
      op("add", %{"counter" => %{"type" => "string"}, "delta" => %{"type" => "integer"}}),
      op("turn", %{"seat" => seat}),
      op("phase", %{"name" => %{"type" => "string", "minLength" => 1}}),
      op("ask", %{
        "seat" => seat,
        "prompt" => %{"type" => "string"},
        "choices" => %{"type" => "array", "items" => %{"type" => "string", "minLength" => 1}},
        "cards" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{"zone" => zone, "card" => %{"type" => "string"}},
            "required" => ["zone", "card"],
            "additionalProperties" => false
          }
        }
      }),
      op("end", %{
        "scores" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{"seat" => seat, "score" => %{"type" => "number"}},
            "required" => ["seat", "score"],
            "additionalProperties" => false
          }
        }
      })
    ]
  end

  defp op(name, props) do
    %{
      "type" => "object",
      "properties" => Map.put(props, "op", %{"const" => name}),
      "required" => ["op" | Map.keys(props)],
      "additionalProperties" => false
    }
  end

  # -- decode ---------------------------------------------------------------------------

  @doc """
  The ops of a decoded JSON answer: a list of op objects, or `%{"ops" => list}`.
  `{:error, {index, reason}}` names the first bad op (from 0).

      iex> Table.Generic.Ops.decode([%{"op" => "move", "top" => 1, "from" => "deck", "to" => "hand:0"}])
      {:ok, [{:move, {:top, 1}, "deck", "hand:0"}]}
      iex> Table.Generic.Ops.decode([%{"op" => "fly"}])
      {:error, {0, :unknown_op}}
  """
  @spec decode(list | map) :: {:ok, [t]} | {:error, term}
  def decode(%{"ops" => ops}) when is_list(ops), do: decode(ops)

  def decode(ops) when is_list(ops) do
    ops
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {json, i}, {:ok, acc} ->
      case decode_op(json) do
        {:ok, op} -> {:cont, {:ok, [op | acc]}}
        {:error, reason} -> {:halt, {:error, {i, reason}}}
      end
    end)
    |> case do
      {:ok, ops} -> {:ok, Enum.reverse(ops)}
      error -> error
    end
  end

  def decode(_other), do: {:error, :not_a_list}

  @doc "One op from its JSON object."
  @spec decode_op(term) :: {:ok, t} | {:error, term}
  def decode_op(%{"op" => name} = json) do
    case only(json, keys(name, json)) do
      :ok -> do_decode(name, json)
      error -> error
    end
  end

  def decode_op(_json), do: {:error, :not_an_op}

  defp keys("move", json) do
    ref = Enum.find(~w(card top all), &Map.has_key?(json, &1))
    ["op", "from", "to" | List.wrap(ref)]
  end

  defp keys("shuffle", _), do: ~w(op zone)
  defp keys("deal", _), do: ~w(op n from to)
  defp keys("flip", _), do: ~w(op zone visibility)
  defp keys("set", _), do: ~w(op counter value)
  defp keys("add", _), do: ~w(op counter delta)
  defp keys("turn", _), do: ~w(op seat)
  defp keys("phase", _), do: ~w(op name)
  defp keys("ask", _), do: ~w(op seat prompt choices cards)
  defp keys("end", _), do: ~w(op scores)
  defp keys(_name, _), do: nil

  defp only(_json, nil), do: {:error, :unknown_op}

  defp only(json, keys) do
    case Map.keys(json) -- keys do
      [] -> :ok
      extra -> {:error, {:unknown_keys, Enum.sort(extra)}}
    end
  end

  defp do_decode("move", %{"from" => from, "to" => to} = json) do
    with {:ok, ref} <- card_ref(json),
         :ok <- zones([from, to]),
         do: {:ok, {:move, ref, from, to}}
  end

  defp do_decode("shuffle", %{"zone" => zone}) do
    with :ok <- zones([zone]), do: {:ok, {:shuffle, zone}}
  end

  defp do_decode("deal", %{"n" => n, "from" => from, "to" => [_ | _] = to})
       when is_integer(n) and n > 0 do
    with :ok <- zones([from | to]), do: {:ok, {:deal, n, from, to}}
  end

  defp do_decode("flip", %{"zone" => zone, "visibility" => vis}) do
    with :ok <- zones([zone]),
         {:ok, vis} <- Map.fetch(@visibilities, vis) |> or_error(:bad_visibility),
         do: {:ok, {:flip, zone, vis}}
  end

  defp do_decode("set", %{"counter" => c, "value" => v})
       when is_binary(c) and (is_integer(v) or is_binary(v)),
       do: {:ok, {:set, c, v}}

  defp do_decode("add", %{"counter" => c, "delta" => d}) when is_binary(c) and is_integer(d),
    do: {:ok, {:add, c, d}}

  defp do_decode("turn", %{"seat" => s}) when is_integer(s) and s >= 0, do: {:ok, {:turn, s}}

  defp do_decode("phase", %{"name" => name}) when is_binary(name) and name != "",
    do: {:ok, {:phase, name}}

  defp do_decode("ask", %{"seat" => s, "prompt" => p} = json)
       when is_integer(s) and s >= 0 and is_binary(p) do
    choices = Map.get(json, "choices", [])
    cards = Map.get(json, "cards", [])

    with true <- is_list(choices) and Enum.all?(choices, &(is_binary(&1) and &1 != "")),
         true <- is_list(cards),
         {:ok, cards} <- card_options(cards) do
      {:ok, {:ask, s, p, choices ++ cards}}
    else
      false -> {:error, :bad_options}
      error -> error
    end
  end

  defp do_decode("end", %{"scores" => scores}) when is_list(scores) do
    Enum.reduce_while(scores, {:ok, %{}}, fn
      %{"seat" => s, "score" => v} = entry, {:ok, acc}
      when map_size(entry) == 2 and is_integer(s) and s >= 0 and is_number(v) ->
        {:cont, {:ok, Map.put(acc, s, v)}}

      _, _ ->
        {:halt, {:error, :bad_scores}}
    end)
    |> case do
      {:ok, scores} -> {:ok, {:end, scores}}
      error -> error
    end
  end

  defp do_decode(_name, _json), do: {:error, :bad_fields}

  defp card_ref(%{"card" => card}) when is_binary(card) and card != "", do: {:ok, card}
  defp card_ref(%{"top" => n}) when is_integer(n) and n > 0, do: {:ok, {:top, n}}
  defp card_ref(%{"all" => true}), do: {:ok, :all}
  defp card_ref(_json), do: {:error, :bad_card_ref}

  defp card_options(cards) do
    Enum.reduce_while(cards, {:ok, []}, fn
      %{"zone" => z, "card" => c} = m, {:ok, acc}
      when map_size(m) == 2 and is_binary(z) and z != "" and is_binary(c) and c != "" ->
        {:cont, {:ok, [{:card, z, c} | acc]}}

      _, _ ->
        {:halt, {:error, :bad_options}}
    end)
    |> case do
      {:ok, cards} -> {:ok, Enum.reverse(cards)}
      error -> error
    end
  end

  defp zones(zones) do
    if Enum.all?(zones, &(is_binary(&1) and &1 != "")), do: :ok, else: {:error, :bad_zone}
  end

  defp or_error({:ok, v}, _reason), do: {:ok, v}
  defp or_error(:error, reason), do: {:error, reason}

  # -- encode ---------------------------------------------------------------------------

  @doc """
  The JSON object of an op (`decode_op/1` gives it back).

      iex> Table.Generic.Ops.encode({:flip, "deck", :public})
      %{"op" => "flip", "zone" => "deck", "visibility" => "public"}
  """
  @spec encode(t) :: map
  def encode({:move, ref, from, to}),
    do: Map.merge(%{"op" => "move", "from" => from, "to" => to}, ref(ref))

  def encode({:shuffle, zone}), do: %{"op" => "shuffle", "zone" => zone}
  def encode({:deal, n, from, to}), do: %{"op" => "deal", "n" => n, "from" => from, "to" => to}

  def encode({:flip, zone, vis}),
    do: %{"op" => "flip", "zone" => zone, "visibility" => Atom.to_string(vis)}

  def encode({:set, c, v}), do: %{"op" => "set", "counter" => c, "value" => v}
  def encode({:add, c, d}), do: %{"op" => "add", "counter" => c, "delta" => d}
  def encode({:turn, s}), do: %{"op" => "turn", "seat" => s}
  def encode({:phase, name}), do: %{"op" => "phase", "name" => name}

  def encode({:ask, s, prompt, options}) do
    %{
      "op" => "ask",
      "seat" => s,
      "prompt" => prompt,
      "choices" => for(o <- options, is_binary(o), do: o),
      "cards" => for({:card, z, c} <- options, do: %{"zone" => z, "card" => c})
    }
  end

  def encode({:end, scores}) do
    %{
      "op" => "end",
      "scores" => for({s, v} <- Enum.sort(scores), do: %{"seat" => s, "score" => v})
    }
  end

  defp ref({:top, n}), do: %{"top" => n}
  defp ref(:all), do: %{"all" => true}
  defp ref(card), do: %{"card" => card}
end
