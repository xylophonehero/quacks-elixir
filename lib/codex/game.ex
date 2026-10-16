defmodule Codex.Game do
  @moduledoc """
  The Codex sandbox engine: pure functions over a `%Codex.Game{}` struct.

  This round is a **sandbox**: a table where the players move cards by hand. The
  engine does not enforce the rules of Codex. It keeps one fact: every card is in
  exactly one zone (card conservation). Later rounds add the rules one by one.
  Rules and card data: `docs/research/codex.md`.

  The API follows the table contract of `Hearts.Game` (`new/2`,
  `legal_actions/2`, `apply/3`, `status/1`, `view/2`).

  ## Seats

  The game has two sides, seat 0 (P1) and seat 1 (P2). It is hot-seat: one
  browser plays both sides, so the room has one table seat (`table_seats/0`) and
  the actions of that seat can change both sides.

  ## Set-up (rulebook first game, research §2)

  Each side gets the neutral starting deck (10 cards, shuffled, 5 drawn), its
  spec's hero in the command zone and the 24 codex cards of its spec (2 copies of
  12) in the codex zone. P1 is Bashing (Troq Bashar) with 4 workers; P2 is
  Finesse (River Montoya) with 5 workers. Base 20 HP, gold 0.

  ## Zones

  Per side: `deck` (the head is the top; hidden in the view), `hand`, `discard`
  (the head is the top), `codex`, `command`, `workers` (face down), `in_play`,
  and `patrol` (5 named slots, `patrol_slots/0`, each empty or one card). One
  `trash` for the table. A zone is addressed as `{seat, name}` or `:trash`.

  ## Actions (`apply/3`)

  - `{:move, card_id, zone, slot_or_index}`: move a card. For `patrol`, a slot
    (it must be empty); for a list zone, the index in the new list (0 is the top
    or the left), or `nil` for the end. A card that leaves `in_play` and `patrol`
    loses its damage, runes and exhaustion; a hero that leaves play goes back to
    level 1. A card in `workers` is face down; it turns face up when it leaves.
  - `{:draw, seat, n}`: draw `n` (1..10) cards from the top of the deck. When the
    deck is empty, the discard pile is shuffled into a new deck first.
  - `{:shuffle, seat, zone}`: shuffle a list zone of a side.
  - `{:adjust_card, card_id, key, delta}`: add `delta` to `:damage`, `:plus`
    (+1/+1 runes), `:minus` (-1/-1 runes) or `:level` (heroes, 1..max level).
  - `{:toggle, card_id, :exhausted | :face_down}`.
  - `{:adjust, seat, :gold | :base_hp, delta}`: 0..99.
  - `{:building, seat, building}`: build or remove a tech building or add-on
    (`buildings/0`).
  - `:end_turn` (also `{:end_turn}`): the other side becomes active; its turn
    count goes up by 1.
  - `:undo` (also `{:undo}`): go back to the state before the last action. The
    game keeps the last 50 states.

  Each action goes into `game.log` (newest first). An invalid action returns
  `{:error, reason}` and changes nothing.

  Randomness (the shuffles) uses only the `:rand` state in `game.rng`.

      iex> {:ok, game} = Codex.Game.new(%{}, {1, 2, 3})
      iex> length(game.sides[0].zones.hand)
      5
      iex> length(game.sides[1].zones.workers)
      5
  """

  alias Codex.Cards
  alias Table.Kit.Rng

  @history 50
  @patrol_slots [:squad_leader, :elite, :scavenger, :technician, :lookout]
  @list_zones [:deck, :hand, :discard, :codex, :command, :workers, :in_play]
  @play_zones [:in_play, :patrol]
  @buildings [:tech_1, :tech_2, :tech_3, :tower, :surplus, :tech_lab, :heroes_hall]
  @card_keys [:damage, :plus, :minus, :level]
  @max_counter 99

  @setup %{
    0 => %{spec: "Bashing", workers: 4},
    1 => %{spec: "Finesse", workers: 5}
  }

  @type seat :: 0 | 1
  @type zone_name ::
          :deck | :hand | :discard | :codex | :command | :workers | :in_play | :patrol
  @type zone :: {seat, zone_name} | :trash
  @type slot :: :squad_leader | :elite | :scavenger | :technician | :lookout
  @type card_id :: pos_integer

  @typedoc "One card on the table: an instance of a card definition (`Codex.Cards`)."
  @type card :: %{
          id: card_id,
          card: String.t(),
          seat: seat,
          damage: non_neg_integer,
          plus: non_neg_integer,
          minus: non_neg_integer,
          level: pos_integer | nil,
          exhausted: boolean,
          face_down: boolean
        }

  @type side :: %{
          spec: String.t(),
          gold: non_neg_integer,
          base_hp: non_neg_integer,
          tech_buildings: [atom],
          turn: non_neg_integer,
          zones: %{
            required(:patrol) => %{slot => card_id | nil},
            optional(zone_name) => [card_id]
          }
        }

  @type t :: %__MODULE__{
          seed: {integer, integer, integer},
          rng: :rand.state(),
          active: seat,
          cards: %{card_id => card},
          sides: %{seat => side},
          trash: [card_id],
          log: [tuple],
          history: [t]
        }

  defstruct [:seed, :rng, active: 0, cards: %{}, sides: %{}, trash: [], log: [], history: []]

  @doc "The 5 patrol slots, left to right."
  @spec patrol_slots() :: [slot]
  def patrol_slots, do: @patrol_slots

  @doc "The list zones of a side (every zone but `patrol`)."
  @spec list_zones() :: [zone_name]
  def list_zones, do: @list_zones

  @doc "The tech buildings and add-ons of `{:building, seat, building}`."
  @spec buildings() :: [atom]
  def buildings, do: @buildings

  @doc "The seats of the room: one browser plays both sides (hot-seat)."
  @spec table_seats() :: [0]
  def table_seats, do: [0]

  @doc "How many states `:undo` can go back."
  @spec history_limit() :: pos_integer
  def history_limit, do: @history

  # -- set-up --------------------------------------------------------------------------

  @doc "A new sandbox game (the first-game set-up). `opts` is not used yet."
  @spec new(map | keyword, {integer, integer, integer}) :: {:ok, t} | {:error, term}
  def new(opts \\ %{}, seed)

  def new(opts, seed) when is_list(opts), do: new(Map.new(opts), seed)

  def new(opts, {a, b, c} = seed)
      when is_map(opts) and is_integer(a) and is_integer(b) and is_integer(c) do
    game = %__MODULE__{seed: seed, rng: Rng.seed(seed)}
    game = Enum.reduce([0, 1], game, &setup_side/2)
    {:ok, %{game | log: [{:setup, seed}]}}
  end

  def new(_opts, _seed), do: {:error, :invalid_seed}

  defp setup_side(seat, game) do
    %{spec: spec, workers: workers} = @setup[seat]
    {game, deck} = add_cards(game, seat, Cards.starter())
    {game, codex} = add_cards(game, seat, Enum.flat_map(Cards.codex(spec), &[&1, &1]))
    {game, command} = add_cards(game, seat, [Cards.hero(spec)])
    {game, worker_ids} = add_cards(game, seat, List.duplicate("worker", workers))
    game = Enum.reduce(worker_ids, game, &update_card(&2, &1, fn c -> %{c | face_down: true} end))
    {deck, rng} = Rng.shuffle(deck, game.rng)
    {hand, deck} = Enum.split(deck, 5)

    side = %{
      spec: spec,
      gold: 0,
      base_hp: 20,
      tech_buildings: [],
      turn: if(seat == 0, do: 1, else: 0),
      zones: %{
        deck: deck,
        hand: hand,
        discard: [],
        codex: codex,
        command: command,
        workers: worker_ids,
        in_play: [],
        patrol: Map.new(@patrol_slots, &{&1, nil})
      }
    }

    %{game | rng: rng, sides: Map.put(game.sides, seat, side)}
  end

  defp add_cards(game, seat, slugs) do
    Enum.reduce(slugs, {game, []}, fn slug, {game, ids} ->
      id = map_size(game.cards) + 1
      card = new_card(id, slug, seat)
      {%{game | cards: Map.put(game.cards, id, card)}, ids ++ [id]}
    end)
  end

  defp new_card(id, slug, seat) do
    %{
      id: id,
      card: slug,
      seat: seat,
      damage: 0,
      plus: 0,
      minus: 0,
      level: if(Cards.hero?(slug), do: 1),
      exhausted: false,
      face_down: false
    }
  end

  # -- the table contract ------------------------------------------------------------------

  @doc """
  The action kinds of the sandbox. A sandbox action has too many forms to list
  each one, so this gives one atom per kind (`:undo` only when there is a state to
  go back to).
  """
  @spec legal_actions(t, non_neg_integer) :: [atom]
  def legal_actions(%__MODULE__{} = game, 0) do
    kinds = [:move, :draw, :shuffle, :adjust_card, :toggle, :adjust, :building, :end_turn]
    if game.history == [], do: kinds, else: kinds ++ [:undo]
  end

  def legal_actions(%__MODULE__{}, _seat), do: []

  @doc "The sandbox never ends: always `{:playing, [0]}` (the one table seat)."
  @spec status(t) :: {:playing, [0]}
  def status(%__MODULE__{}), do: {:playing, [0]}

  @doc """
  Do `action` for table seat 0. Returns `{:ok, game}` or `{:error, reason}`.
  """
  @spec apply(t, non_neg_integer, term) :: {:ok, t} | {:error, term}
  def apply(%__MODULE__{} = game, 0, action) when action in [:undo, {:undo}], do: undo(game)

  def apply(%__MODULE__{} = game, 0, action) do
    case do_apply(game, normalize(action)) do
      {:ok, new} ->
        entry = {:action, game.active, normalize(action)}
        {:ok, %{new | log: [entry | new.log], history: push(game)}}

      {:error, _} = error ->
        error
    end
  end

  def apply(%__MODULE__{}, _seat, _action), do: {:error, :not_your_seat}

  defp normalize({:end_turn}), do: :end_turn
  defp normalize(action), do: action

  defp push(game), do: Enum.take([%{game | history: []} | game.history], @history)

  defp undo(%__MODULE__{history: []}), do: {:error, :nothing_to_undo}
  defp undo(%__MODULE__{history: [prev | rest]}), do: {:ok, %{prev | history: rest}}

  # -- the actions ---------------------------------------------------------------------------

  defp do_apply(game, {:move, id, zone, at}) do
    with {:ok, _card} <- fetch_card(game, id),
         :ok <- check_zone(zone),
         :ok <- check_at(game, id, zone, at) do
      from = locate(game, id)
      game = game |> remove(id) |> insert(id, zone, at)
      {:ok, update_card(game, id, &moved(&1, from, zone))}
    end
  end

  defp do_apply(game, {:draw, seat, n}) when n in 1..10 do
    with :ok <- check_seat(seat) do
      draw(game, seat, n)
    end
  end

  defp do_apply(_game, {:draw, _seat, _n}), do: {:error, :invalid_count}

  defp do_apply(game, {:shuffle, seat, zone}) do
    with :ok <- check_seat(seat),
         :ok <- if(zone in @list_zones, do: :ok, else: {:error, :invalid_zone}) do
      {ids, rng} = Rng.shuffle(zone_ids(game, {seat, zone}), game.rng)
      {:ok, %{put_zone(game, {seat, zone}, ids) | rng: rng}}
    end
  end

  defp do_apply(game, {:adjust_card, id, key, delta})
       when key in @card_keys and is_integer(delta) and delta != 0 do
    with {:ok, card} <- fetch_card(game, id),
         {:ok, value} <- card_value(card, key, delta) do
      {:ok, update_card(game, id, &Map.put(&1, key, value))}
    end
  end

  defp do_apply(_game, {:adjust_card, _id, _key, _delta}), do: {:error, :invalid_adjust}

  defp do_apply(game, {:toggle, id, key}) when key in [:exhausted, :face_down] do
    with {:ok, _card} <- fetch_card(game, id) do
      {:ok, update_card(game, id, &Map.update!(&1, key, fn v -> !v end))}
    end
  end

  defp do_apply(_game, {:toggle, _id, _key}), do: {:error, :invalid_toggle}

  defp do_apply(game, {:adjust, seat, key, delta})
       when key in [:gold, :base_hp] and is_integer(delta) and delta != 0 do
    with :ok <- check_seat(seat) do
      value = game.sides[seat][key] + delta

      if value in 0..@max_counter,
        do: {:ok, put_in(game.sides[seat][key], value)},
        else: {:error, :out_of_range}
    end
  end

  defp do_apply(_game, {:adjust, _seat, _key, _delta}), do: {:error, :invalid_adjust}

  defp do_apply(game, {:building, seat, building}) when building in @buildings do
    with :ok <- check_seat(seat) do
      {:ok,
       update_in(game.sides[seat].tech_buildings, fn list ->
         if building in list, do: List.delete(list, building), else: list ++ [building]
       end)}
    end
  end

  defp do_apply(_game, {:building, _seat, _building}), do: {:error, :invalid_building}

  defp do_apply(game, :end_turn) do
    next = 1 - game.active
    game = %{game | active: next}
    {:ok, update_in(game.sides[next].turn, &(&1 + 1))}
  end

  defp do_apply(_game, _action), do: {:error, :invalid_action}

  # Draw one at a time; an empty deck takes the shuffled discard pile first.
  defp draw(game, seat, n) do
    zones = game.sides[seat].zones

    if zones.deck == [] and zones.discard == [],
      do: {:error, :empty_deck},
      else: {:ok, Enum.reduce(1..n, game, fn _, game -> draw_one(game, seat) end)}
  end

  defp draw_one(game, seat) do
    case game.sides[seat].zones do
      %{deck: [top | rest], hand: hand} ->
        game |> put_zone({seat, :deck}, rest) |> put_zone({seat, :hand}, hand ++ [top])

      %{deck: [], discard: []} ->
        game

      %{deck: [], discard: discard} ->
        {deck, rng} = Rng.shuffle(discard, game.rng)

        %{game | rng: rng, log: [{:reshuffle, seat} | game.log]}
        |> put_zone({seat, :discard}, [])
        |> put_zone({seat, :deck}, deck)
        |> draw_one(seat)
    end
  end

  defp card_value(card, :level, _delta) when card.level == nil, do: {:error, :not_a_hero}

  defp card_value(card, :level, delta) do
    value = card.level + delta
    max = Cards.max_level(card.card)
    if value in 1..max//1, do: {:ok, value}, else: {:error, :out_of_range}
  end

  defp card_value(card, key, delta) do
    value = Map.fetch!(card, key) + delta
    if value in 0..@max_counter, do: {:ok, value}, else: {:error, :out_of_range}
  end

  # What a card keeps after a move from zone `from` to zone `to`.
  defp moved(card, from, to) do
    card =
      if zone_name(from) in @play_zones and zone_name(to) not in @play_zones,
        do: %{card | damage: 0, plus: 0, minus: 0, exhausted: false, level: card.level && 1},
        else: card

    cond do
      zone_name(to) == :workers -> %{card | face_down: true}
      zone_name(from) == :workers -> %{card | face_down: false}
      true -> card
    end
  end

  # -- zones -------------------------------------------------------------------------------

  defp check_seat(seat) when seat in [0, 1], do: :ok
  defp check_seat(_seat), do: {:error, :invalid_seat}

  defp check_zone(:trash), do: :ok
  defp check_zone({seat, zone}) when seat in [0, 1] and zone in [:patrol | @list_zones], do: :ok
  defp check_zone(_zone), do: {:error, :invalid_zone}

  defp check_at(game, id, {seat, :patrol}, slot) when slot in @patrol_slots do
    case game.sides[seat].zones.patrol[slot] do
      nil -> :ok
      ^id -> :ok
      _other -> {:error, :slot_taken}
    end
  end

  defp check_at(_game, _id, {_seat, :patrol}, _slot), do: {:error, :invalid_slot}
  defp check_at(_game, _id, _zone, nil), do: :ok
  defp check_at(_game, _id, _zone, i) when is_integer(i) and i >= 0, do: :ok
  defp check_at(_game, _id, _zone, _at), do: {:error, :invalid_index}

  @doc """
  The zone of card `id`: `{seat, name}`, `{seat, :patrol, slot}` or `:trash`
  (nil when it is in no zone). Works on a game and on a view (`view/2`).
  """
  @spec locate(map, card_id) :: zone | {seat, :patrol, slot} | nil
  def locate(game, id), do: Enum.find_value(placements(game), fn {i, at} -> i == id && at end)

  @doc "Every card in a zone, as `{id, location}` (see `locate/2`). A view's decks are counts: left out."
  @spec placements(map) :: [{card_id, zone | {seat, :patrol, slot}}]
  def placements(%{sides: sides, trash: trash}),
    do: Enum.map(trash, &{&1, :trash}) ++ Enum.flat_map(sides, &side_placements/1)

  defp side_placements({seat, side}), do: Enum.flat_map(side.zones, &zone_placements(seat, &1))

  defp zone_placements(seat, {:patrol, slots}),
    do: for({slot, id} <- slots, id, do: {id, {seat, :patrol, slot}})

  defp zone_placements(seat, {zone, ids}) when is_list(ids),
    do: for(id <- ids, do: {id, {seat, zone}})

  defp zone_placements(_seat, {_zone, _count}), do: []

  defp zone_name(:trash), do: :trash
  defp zone_name({_seat, zone}), do: zone
  defp zone_name({_seat, :patrol, _slot}), do: :patrol
  defp zone_name(nil), do: nil

  @doc "The card ids of a list zone (`{seat, name}` or `:trash`)."
  @spec zone_ids(t, zone) :: [card_id]
  def zone_ids(game, :trash), do: game.trash
  def zone_ids(game, {seat, zone}), do: Map.fetch!(game.sides[seat].zones, zone)

  defp put_zone(game, :trash, ids), do: %{game | trash: ids}
  defp put_zone(game, {seat, zone}, ids), do: put_in(game.sides[seat].zones[zone], ids)

  defp remove(game, id) do
    case locate(game, id) do
      {seat, :patrol, slot} -> put_in(game.sides[seat].zones.patrol[slot], nil)
      zone -> put_zone(game, zone, List.delete(zone_ids(game, zone), id))
    end
  end

  defp insert(game, id, {seat, :patrol}, slot),
    do: put_in(game.sides[seat].zones.patrol[slot], id)

  defp insert(game, id, zone, nil), do: put_zone(game, zone, zone_ids(game, zone) ++ [id])

  defp insert(game, id, zone, i),
    do: put_zone(game, zone, List.insert_at(zone_ids(game, zone), i, id))

  defp fetch_card(game, id) do
    case Map.fetch(game.cards, id) do
      {:ok, card} -> {:ok, card}
      :error -> {:error, :no_card}
    end
  end

  defp update_card(game, id, fun), do: %{game | cards: Map.update!(game.cards, id, fun)}

  @doc "Every card id in every zone, with repeats (the conservation check)."
  @spec all_placed(t) :: [card_id]
  def all_placed(game), do: Enum.map(placements(game), &elem(&1, 0))

  # -- the view ------------------------------------------------------------------------------

  @doc """
  What a page sees. Hot-seat: both hands, the codex and the workers are in the
  view (the board hides the other side's hand). The decks are only counts.
  """
  @spec view(t, non_neg_integer | :spectator) :: map
  def view(%__MODULE__{} = game, _seat) do
    deck_ids = Enum.flat_map(game.sides, fn {_s, side} -> side.zones.deck end)

    %{
      active: game.active,
      sides:
        Map.new(game.sides, fn {seat, side} ->
          zones = side.zones
          {seat, %{side | zones: Map.put(zones, :deck, length(zones.deck))}}
        end),
      trash: game.trash,
      cards: Map.drop(game.cards, deck_ids),
      log: Enum.take(game.log, 30),
      undo: game.history != []
    }
  end
end
