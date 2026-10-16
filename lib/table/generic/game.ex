defmodule Table.Generic.Game do
  @moduledoc """
  A card game that only knows zones, counters and a prompt: the rules live in a
  referee (`Table.Generic.Referee`). The engine is pure and implements the same
  contract as `Hearts.Game`: `new/2`, `legal_actions/2`, `apply/3`, `status/1`,
  `view/2`.

  ## The state

  - `zones`: `%{id => Table.Kit.Zone}`, each with an owner, a visibility and
    its cards in order (the first card is the top). `layout` keeps the zone
    specs (`Table.Generic.Spec.zones/2`) for the board.
  - `counters`: `%{id => integer | string}`; a seat's counter is `"score:2"`.
  - `turn`, `phase`: free data for the referee and the board.
  - `pending`: the prompt to one seat, `%{seat, prompt, options}`, or nil.
  - `result`: the scores when the game is over, else nil.
  - `log`: newest first. `{:op, op, detail}` for each op and
    `{:action, seat, action, seen}` for each action. `detail` and `seen` say
    which seats saw the cards (`:all` or a list), so `view/2` can hide them.
  - `rng`: advanced only by `{:shuffle, zone}` (`Table.Kit.Rng`).

  ## A turn

  A player can only answer the prompt: `{:choose, label}` or
  `{:play, zone, card}`, exactly the options of the prompt. `apply/3` records
  the action, clears the prompt, and asks the referee for ops
  (`decide(view, {seat, action})`). The engine applies them all or none. When
  no prompt is open after that and the game is not over, it asks the referee
  again with `:continue` (it may need to see a shuffle's result first). A
  referee that leaves no prompt makes the action fail: nothing changes.

  ## Replay

  The log has every op, so `replay/3` builds the same state from the options,
  the seed and the log, with no referee.
  """

  alias Table.Generic.{Ops, Referee, Spec}
  alias Table.Kit.{Rng, Zone}

  @max_rounds 20

  @type seat :: non_neg_integer
  @type action :: {:choose, String.t()} | {:play, String.t(), String.t()}
  @type pending :: %{seat: seat, prompt: String.t(), options: [Ops.option()]}

  @type t :: %__MODULE__{
          spec: Spec.t(),
          opts: map,
          seed: Rng.seed(),
          rng: Rng.t(),
          referee: module | nil,
          seats: [seat],
          layout: [Spec.zone_spec()],
          zones: %{String.t() => Zone.t()},
          counters: %{String.t() => integer | String.t()},
          turn: seat | nil,
          phase: String.t() | nil,
          pending: pending | nil,
          result: %{seat => number} | nil,
          log: [tuple]
        }

  defstruct [
    :spec,
    :opts,
    :seed,
    :rng,
    :referee,
    :turn,
    :phase,
    :pending,
    :result,
    seats: [],
    layout: [],
    zones: %{},
    counters: %{},
    log: []
  ]

  # -- new -------------------------------------------------------------------------------

  @doc """
  A new game. `opts`: `spec` (a fixture name or a spec map), `players` (default
  the spec's minimum), `referee` (a module; default the spec's referee, see
  `Table.Generic.Referee.for/1`; nil: no referee). The spec's setup ops run,
  then the referee's `decide(view, :start)`.

      iex> {:ok, game} = Table.Generic.Game.new(%{spec: "crazy_eights", players: 3}, {1, 2, 3})
      iex> Table.Generic.Game.status(game)
      {:playing, [0]}
      iex> length(game.zones["hand:1"].items)
      5
  """
  @spec new(map | keyword, Rng.seed()) :: {:ok, t} | {:error, term}
  def new(opts, seed) when is_list(opts), do: new(Map.new(opts), seed)

  def new(opts, seed) when is_map(opts) do
    with {:ok, game} <- blank(opts, seed),
         {:ok, setup} <- Spec.setup(game.spec, length(game.seats)),
         {:ok, game} <- apply_ops(game, setup) do
      if game.referee, do: run_referee(game, :start), else: {:ok, game}
    end
  end

  defp blank(opts, {a, b, c} = seed) when is_integer(a) and is_integer(b) and is_integer(c) do
    with {:ok, spec} <- Spec.normalise(Map.get(opts, :spec)),
         players = Map.get(opts, :players, spec.players.first),
         true <- (is_integer(players) and players in spec.players) || {:error, :bad_players} do
      layout = Spec.zones(spec, players)

      zones =
        Map.new(layout, fn z ->
          items = if z.deck, do: spec.cards, else: []
          {z.id, Zone.new(items, owner: z.seat, visibility: z.visibility)}
        end)

      {:ok,
       %__MODULE__{
         spec: spec,
         opts: opts,
         seed: seed,
         rng: Rng.seed(seed),
         referee: Map.get(opts, :referee, Referee.for(spec.referee)),
         seats: Enum.to_list(0..(players - 1)),
         layout: layout,
         zones: zones,
         counters: Spec.counters(spec, players)
       }}
    end
  end

  defp blank(_opts, seed), do: {:error, {:invalid_seed, seed}}

  # -- queries ---------------------------------------------------------------------------

  @doc "`{:playing, [seat]}` (the seat of the prompt), or `{:over, scores}`."
  @spec status(t) :: {:playing, [seat]} | {:over, %{seat => number}}
  def status(%__MODULE__{result: %{} = scores}), do: {:over, scores}
  def status(%__MODULE__{pending: %{seat: seat}}), do: {:playing, [seat]}
  def status(%__MODULE__{}), do: {:playing, []}

  @doc "The actions of `seat`: the options of the prompt, when it is to `seat`."
  @spec legal_actions(t, seat | :spectator) :: [action]
  def legal_actions(%__MODULE__{result: nil, pending: %{seat: seat, options: options}}, seat),
    do: Enum.map(options, &to_action/1)

  def legal_actions(%__MODULE__{}, _seat), do: []

  defp to_action({:card, zone, card}), do: {:play, zone, card}
  defp to_action(label), do: {:choose, label}

  @doc "The cards of every zone, in no order: a check that no card is lost."
  @spec all_cards(t) :: [String.t()]
  def all_cards(%__MODULE__{zones: zones}), do: Enum.flat_map(zones, fn {_, z} -> z.items end)

  # -- actions ---------------------------------------------------------------------------

  @doc """
  Applies `action` for `seat`: records it, clears the prompt and runs the
  referee. `{:error, reason}` changes nothing.
  """
  @spec apply(t, seat, action) :: {:ok, t} | {:error, term}
  def apply(%__MODULE__{result: %{}}, _seat, _action), do: {:error, :game_over}

  def apply(%__MODULE__{} = game, seat, action) do
    cond do
      action not in legal_actions(game, seat) -> {:error, :illegal_action}
      game.referee == nil -> {:error, :no_referee}
      true -> game |> record(seat, action) |> run_referee({seat, action})
    end
  end

  defp record(game, seat, action) do
    seen =
      case action do
        {:play, zone, _card} -> union(seen(game.zones[zone]), [seat])
        _ -> :all
      end

    %{game | pending: nil} |> log({:action, seat, action, seen})
  end

  defp run_referee(game, event, round \\ 0) do
    with {:ok, ops} <- decide(game, event),
         {:ok, game} <- apply_ops(game, ops) do
      cond do
        game.pending != nil or game.result != nil -> {:ok, game}
        ops == [] or round >= @max_rounds -> {:error, :stalled}
        true -> run_referee(game, :continue, round + 1)
      end
    else
      {:error, reason} -> {:error, {:referee, reason}}
    end
  end

  defp decide(game, event) do
    case game.referee.decide(referee_view(game), event) do
      ops when is_list(ops) -> {:ok, ops}
      {:ok, ops} when is_list(ops) -> {:ok, ops}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:bad_answer, other}}
    end
  end

  # -- ops -------------------------------------------------------------------------------

  @doc """
  Applies `ops` in order, all or none: `{:error, {index, op, reason}}` names the
  first op that fails, and the game does not change.
  """
  @spec apply_ops(t, [Ops.t()]) :: {:ok, t} | {:error, term}
  def apply_ops(%__MODULE__{} = game, ops) when is_list(ops) do
    ops
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, game}, fn {op, i}, {:ok, game} ->
      case apply_op(game, op) do
        {:ok, game} -> {:cont, {:ok, game}}
        {:error, reason} -> {:halt, {:error, {i, op, reason}}}
      end
    end)
  end

  @doc "Decodes JSON ops (`Table.Generic.Ops.decode/1`) and applies them, all or none."
  @spec apply_json(t, list | map) :: {:ok, t} | {:error, term}
  def apply_json(game, json) do
    with {:ok, ops} <- Ops.decode(json), do: apply_ops(game, ops)
  end

  @doc "Applies one op. `{:error, reason}` changes nothing."
  @spec apply_op(t, Ops.t()) :: {:ok, t} | {:error, term}
  def apply_op(%__MODULE__{result: %{}}, _op), do: {:error, :game_over}

  def apply_op(game, {:move, ref, from, to}) do
    with {:ok, f} <- zone(game, from),
         {:ok, t} <- zone(game, to),
         true <- from != to || {:error, :same_zone},
         {:ok, cards, rest} <- take(f.items, ref) do
      zones = %{game.zones | from => %{f | items: rest}, to => %{t | items: cards ++ t.items}}
      seen = union(seen(f), seen(t))

      {:ok,
       %{game | zones: zones} |> log({:op, {:move, ref, from, to}, %{cards: cards, seen: seen}})}
    end
  end

  def apply_op(game, {:shuffle, id} = op) do
    with {:ok, z} <- zone(game, id) do
      {items, rng} = Rng.shuffle(z.items, game.rng)

      {:ok,
       %{game | rng: rng, zones: %{game.zones | id => %{z | items: items}}} |> log({:op, op, nil})}
    end
  end

  def apply_op(game, {:deal, n, from, tos}) when is_integer(n) and n > 0 and is_list(tos) do
    tos = expand(game, tos)

    with {:ok, f} <- zone(game, from),
         :ok <- all_zones(game, tos),
         true <-
           (tos != [] and from not in tos and Enum.uniq(tos) == tos) || {:error, :bad_targets},
         true <- length(f.items) >= n * length(tos) || {:error, :not_enough_cards} do
      {dealt, rest} = Enum.split(f.items, n * length(tos))
      k = length(tos)

      by_zone =
        for {to, i} <- Enum.with_index(tos),
            do: {to, dealt |> Enum.drop(i) |> Enum.take_every(k)}

      zones =
        Enum.reduce(by_zone, %{game.zones | from => %{f | items: rest}}, fn {to, cards}, zones ->
          Map.update!(zones, to, &%{&1 | items: Enum.reverse(cards) ++ &1.items})
        end)

      detail = %{
        dealt: for({to, cards} <- by_zone, do: {to, cards, union(seen(f), seen(zones[to]))})
      }

      {:ok, %{game | zones: zones} |> log({:op, {:deal, n, from, tos}, detail})}
    end
  end

  def apply_op(game, {:flip, id, vis} = op) when vis in [:public, :owner, :hidden] do
    with {:ok, z} <- zone(game, id),
         true <- (vis != :owner or z.owner != nil) || {:error, :no_owner} do
      {:ok, %{game | zones: %{game.zones | id => %{z | visibility: vis}}} |> log({:op, op, nil})}
    end
  end

  def apply_op(game, {:set, c, v} = op) when is_binary(c) and (is_integer(v) or is_binary(v)) do
    if Map.has_key?(game.counters, c),
      do: {:ok, %{game | counters: Map.put(game.counters, c, v)} |> log({:op, op, nil})},
      else: {:error, :unknown_counter}
  end

  def apply_op(game, {:add, c, d} = op) when is_binary(c) and is_integer(d) do
    case Map.fetch(game.counters, c) do
      {:ok, v} when is_integer(v) ->
        {:ok, %{game | counters: Map.put(game.counters, c, v + d)} |> log({:op, op, nil})}

      {:ok, _} ->
        {:error, :not_a_number}

      :error ->
        {:error, :unknown_counter}
    end
  end

  def apply_op(game, {:turn, s} = op) do
    if s in game.seats,
      do: {:ok, %{game | turn: s} |> log({:op, op, nil})},
      else: {:error, :unknown_seat}
  end

  def apply_op(game, {:phase, name} = op) when is_binary(name) and name != "",
    do: {:ok, %{game | phase: name} |> log({:op, op, nil})}

  def apply_op(game, {:ask, s, prompt, options} = op)
      when is_binary(prompt) and is_list(options) do
    with true <- s in game.seats || {:error, :unknown_seat},
         true <- (options != [] and Enum.uniq(options) == options) || {:error, :bad_options},
         :ok <- options(game, s, options) do
      pending = %{seat: s, prompt: prompt, options: options}
      {:ok, %{game | pending: pending} |> log({:op, op, nil})}
    end
  end

  def apply_op(game, {:end, scores} = op) when is_map(scores) do
    if Enum.sort(Map.keys(scores)) == game.seats and
         Enum.all?(scores, fn {_, v} -> is_number(v) end),
       do: {:ok, %{game | result: scores, pending: nil} |> log({:op, op, nil})},
       else: {:error, :bad_scores}
  end

  def apply_op(_game, _op), do: {:error, :bad_op}

  defp zone(game, id) do
    case Map.fetch(game.zones, id) do
      {:ok, z} -> {:ok, z}
      :error -> {:error, {:unknown_zone, id}}
    end
  end

  defp all_zones(game, ids) do
    case Enum.find(ids, &(not Map.has_key?(game.zones, &1))) do
      nil -> :ok
      id -> {:error, {:unknown_zone, id}}
    end
  end

  # "hand:*" is every seat's "hand".
  defp expand(game, ids), do: Enum.flat_map(ids, &expand_one(game, &1))

  defp expand_one(game, id) do
    case String.split(id, ":") do
      [base, "*"] -> for z <- game.layout, z.base == base, z.seat != nil, do: z.id
      _ -> [id]
    end
  end

  defp take(items, :all), do: {:ok, items, []}

  defp take(items, {:top, n}) when is_integer(n) and n > 0 do
    if length(items) >= n,
      do: {:ok, Enum.take(items, n), Enum.drop(items, n)},
      else: {:error, :not_enough_cards}
  end

  defp take(items, card) when is_binary(card) do
    if card in items, do: {:ok, [card], List.delete(items, card)}, else: {:error, :not_in_zone}
  end

  defp take(_items, _ref), do: {:error, :bad_card_ref}

  # A card option must be in its zone, and the asked seat must see that zone.
  defp options(game, seat, options) do
    Enum.reduce_while(options, :ok, fn option, :ok ->
      case option(game, seat, option) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp option(_game, _seat, label) when is_binary(label) and label != "", do: :ok

  defp option(game, seat, {:card, id, card}) do
    with {:ok, z} <- zone(game, id) do
      cond do
        card not in z.items -> {:error, :not_in_zone}
        not Zone.visible?(z, seat) -> {:error, :not_visible}
        true -> :ok
      end
    end
  end

  defp option(_game, _seat, _option), do: {:error, :bad_options}

  defp seen(%Zone{visibility: :public}), do: :all
  defp seen(%Zone{visibility: :owner, owner: owner}), do: [owner]
  defp seen(%Zone{visibility: :hidden}), do: []

  defp union(:all, _), do: :all
  defp union(_, :all), do: :all
  defp union(a, b), do: Enum.uniq(a ++ b)

  defp log(game, entry), do: %{game | log: [entry | game.log]}

  # -- replay ------------------------------------------------------------------------------

  @doc """
  The game again from `opts`, `seed` and a `log` (newest first): every op and
  action again, with no referee. Gives a state equal to the one that wrote the log.
  """
  @spec replay(map, Rng.seed(), [tuple]) :: {:ok, t} | {:error, term}
  def replay(opts, seed, log) do
    with {:ok, game} <- blank(opts, seed), do: replay_all(game, Enum.reverse(log))
  end

  defp replay_all(game, []), do: {:ok, game}

  defp replay_all(game, [entry | rest]) do
    with {:ok, game} <- replay_entry(game, entry), do: replay_all(game, rest)
  end

  defp replay_entry(game, {:op, op, _detail}), do: apply_op(game, op)
  defp replay_entry(game, {:action, seat, action, _seen}), do: {:ok, record(game, seat, action)}

  # -- views -------------------------------------------------------------------------------

  @doc """
  What `viewer` (a seat or `:spectator`) may see: the zones with hidden cards as
  `:hidden`, the counters, the prompt (its card options only for its seat), the
  legal actions, and the log with the cards that the viewer did not see hidden.
  `names` has the names of the cards that show.
  """
  @spec view(t, seat | :spectator) :: map
  def view(%__MODULE__{} = game, viewer) do
    zones = Map.new(game.zones, fn {id, z} -> {id, Zone.view(z, viewer)} end)
    shown = for {_, z} <- zones, c <- z.items, c != :hidden, do: c

    %{
      viewer: viewer,
      name: game.spec.name,
      title: game.spec.title,
      seats: game.seats,
      layout: game.layout,
      zones: zones,
      counters: game.counters,
      counter_specs: game.spec.counters,
      turn: game.turn,
      phase: game.phase,
      pending: pending_view(game.pending, viewer),
      result: game.result,
      legal_actions: legal_actions(game, viewer),
      names: Map.take(game.spec.names, shown),
      log: Enum.map(game.log, &redact(&1, viewer))
    }
  end

  defp pending_view(nil, _viewer), do: nil
  defp pending_view(%{seat: viewer} = p, viewer), do: p
  defp pending_view(p, _viewer), do: %{p | options: Enum.map(p.options, &hide_option/1)}

  defp hide_option({:card, zone, _card}), do: {:card, zone, :hidden}
  defp hide_option(label), do: label

  defp redact({:op, {:move, ref, from, to}, %{cards: cards, seen: seen}} = entry, viewer) do
    if sees?(seen, viewer),
      do: entry,
      else:
        {:op, {:move, if(is_binary(ref), do: :hidden, else: ref), from, to},
         %{cards: length(cards), seen: seen}}
  end

  defp redact({:op, {:deal, _, _, _} = op, %{dealt: dealt}}, viewer) do
    {:op, op,
     %{
       dealt:
         for(
           {to, cards, seen} <- dealt,
           do: {to, if(sees?(seen, viewer), do: cards, else: length(cards)), seen}
         )
     }}
  end

  defp redact({:op, {:ask, viewer, _, _}, _} = entry, viewer), do: entry

  defp redact({:op, {:ask, s, p, options}, d}, _viewer),
    do: {:op, {:ask, s, p, Enum.map(options, &hide_option/1)}, d}

  defp redact({:action, s, {:play, zone, _card}, seen} = entry, viewer) do
    if sees?(seen, viewer), do: entry, else: {:action, s, {:play, zone, :hidden}, seen}
  end

  defp redact(entry, _viewer), do: entry

  defp sees?(:all, _viewer), do: true
  defp sees?(seats, viewer), do: viewer in seats

  @doc """
  What the referee sees: everything (it is the game master). Plain maps, so an
  LLM referee can get it as JSON: `zones` as `%{id => %{owner, visibility,
  cards}}`, the counters, turn, phase, the last prompt, the seats and the
  card names (`Table.Generic.Spec.standard/1` gives a standard card's rank and suit).
  """
  @spec referee_view(t) :: map
  def referee_view(%__MODULE__{} = game) do
    %{
      name: game.spec.name,
      seats: game.seats,
      zones:
        Map.new(game.zones, fn {id, z} ->
          {id, %{owner: z.owner, visibility: z.visibility, cards: z.items}}
        end),
      counters: game.counters,
      turn: game.turn,
      phase: game.phase,
      pending: game.pending,
      result: game.result,
      names: game.spec.names
    }
  end
end
