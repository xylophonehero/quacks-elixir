defmodule Codex.Game do
  @moduledoc """
  The Codex engine: pure functions over a `%Codex.Game{}` struct. Rules and card
  data: `docs/research/codex.md` (rulebook v46 and the official rulings).

  The API follows the table contract of `Hearts.Game` (`new/2`,
  `legal_actions/2`, `apply/3`, `status/1`, `view/2`).

  ## Two modes

  - **Rules mode** (the default): only the active side acts, and only with the
    actions of `Codex.Rules` (hire a worker, play a card, attack, ...).
    `legal_actions/2` lists every legal action; any other action is refused.
  - **Free mode** (`{:free_mode, true}`): the sandbox actions below also work, on
    both sides, so a player can fix a state by hand. The rules actions still
    work in free mode.

  Each mode keeps one fact: every card is in exactly one zone (card
  conservation). After every action the state checks run (`Codex.Rules.cleanup/1`):
  units and heroes with no HP left die, and a base at 0 HP ends the game.

  ## Seats

  The game has two sides, seat 0 (P1) and seat 1 (P2). It is hot-seat: one
  browser plays both sides, so the room has one table seat (`table_seats/0`) and
  its actions are those of the active side.

  ## Set-up (rulebook first game, research §2)

  Each side gets the neutral starting deck (10 cards, shuffled, 5 drawn), its
  spec's hero in the command zone and the 24 codex cards of its spec (2 copies of
  12) in the codex zone. P1 is Bashing (Troq Bashar) with 4 workers; P2 is
  Finesse (River Montoya) with 5 workers. Base 20 HP, gold 0. Then P1's first
  turn starts (`Codex.Rules.start_turn/2`): its upkeep gives it 4 gold.

  ## Zones

  Per side: `deck` (the head is the top; hidden in the view), `hand`, `discard`
  (the head is the top), `codex`, `command`, `workers` (face down), `in_play`,
  and `patrol` (5 named slots, `patrol_slots/0`, each empty or one card). One
  `trash` for the table. A zone is addressed as `{seat, name}` or `:trash`.

  ## Sandbox actions (free mode only)

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
  - `{:building, seat, building}`: a finished tech building or add-on on or off
    (`buildings/0`).

  ## In both modes

  - `{:free_mode, boolean}`: free mode on or off.
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
      iex> game.sides[0].gold
      4
  """

  alias Codex.{Cards, Rules, Zones}
  alias Table.Kit.Rng

  @history 50
  @patrol_slots Zones.patrol_slots()
  @list_zones Zones.list_zones()
  @play_zones [:in_play, :patrol]
  @buildings [:tech_1, :tech_2, :tech_3, :tower, :surplus, :tech_lab, :heroes_hall]
  @card_keys [:damage, :plus, :minus, :level]
  @max_counter 99
  @sandbox [:move, :draw, :shuffle, :adjust_card, :toggle, :adjust, :building]

  @workers %{0 => 4, 1 => 5}

  # The set-ups (research §2): the rulebook's first game (1 hero each), Red
  # against Green and Blue against Black (3-hero mode: 3 specs, 3 heroes, the
  # colour's starting deck).
  @presets %{
    "first" => %{
      0 => %{starter: "Neutral", specs: ["Bashing"]},
      1 => %{starter: "Neutral", specs: ["Finesse"]}
    },
    "red_green" => %{
      0 => %{starter: "Red", specs: ["Anarchy", "Blood", "Fire"]},
      1 => %{starter: "Green", specs: ["Balance", "Feral", "Growth"]}
    },
    "blue_black" => %{
      0 => %{starter: "Blue", specs: ["Law", "Peace", "Truth"]},
      1 => %{starter: "Black", specs: ["Demonology", "Disease", "Necromancy"]}
    },
    # The same with the seats swapped (Black as P1), for the bot bench.
    "black_blue" => %{
      0 => %{starter: "Black", specs: ["Demonology", "Disease", "Necromancy"]},
      1 => %{starter: "Blue", specs: ["Law", "Peace", "Truth"]}
    }
  }

  @type seat :: 0 | 1
  @type zone_name ::
          :deck | :hand | :discard | :codex | :command | :workers | :in_play | :patrol
  @type zone :: {seat, zone_name} | :trash
  @type slot :: :squad_leader | :elite | :scavenger | :technician | :lookout
  @type card_id :: pos_integer

  @typedoc """
  One card on the table: an instance of a card definition (`Codex.Cards`).

  - `seat`: the owner. The controller is the side whose zone holds the card.
  - `damage`, `plus` (+1/+1 runes), `minus` (-1/-1 runes), `level` (heroes).
  - `exhausted`, `face_down`.
  - `fatigued`: it came under its controller's control this turn (arrival
    fatigue); cleared in the controller's ready step.
  - `attacked`: it attacked this turn (readiness).
  - `armor_dmg`: the damage its armor absorbed this turn (armor refreshes each turn).
  - `tmp_armor`: armor until the end of the turn (Rampant Growth, Dinosize).
  - `this_turn`: card state until the end of the turn (haste given, a swapped ATK, ...).
  - `tmp_atk`, `tmp_hp`: changes until the end of the turn (Intimidate, Discord).
  - `stealth`: stealth this turn (Sneaky Pig).
  - `extra`: card state (Harmony's Dancer count, Two Step's partners).
  """
  @type card :: %{
          id: card_id,
          card: String.t(),
          seat: seat,
          damage: non_neg_integer,
          plus: non_neg_integer,
          minus: non_neg_integer,
          level: pos_integer | nil,
          exhausted: boolean,
          face_down: boolean,
          fatigued: boolean,
          attacked: boolean,
          armor_dmg: non_neg_integer,
          tmp_armor: non_neg_integer,
          this_turn: map,
          tmp_atk: integer,
          tmp_hp: integer,
          stealth: boolean,
          extra: map
        }

  @typedoc """
  One side. `tech_buildings`: finished tech buildings and add-ons; `pending`:
  started this turn, finished at the end of the turn; `building_damage`: damage
  per building; `destroyed`: tech buildings lost (rebuilt for 0 gold). `hired`:
  a worker hired this turn; `reshuffled`: the discard pile was shuffled into the
  deck in this main phase. `summon_after`: the hero cannot be summoned again
  until the side's turn count is above this. `tower_used`: the Tower detected a
  stealth or invisible attacker this turn.
  """
  @type side :: %{
          spec: String.t(),
          specs: [String.t()],
          starter: String.t(),
          tech_spec: String.t() | nil,
          gold: non_neg_integer,
          base_hp: integer,
          tech_buildings: [atom],
          pending: [atom],
          building_damage: %{atom => non_neg_integer},
          destroyed: [atom],
          turn: non_neg_integer,
          hired: boolean,
          reshuffled: boolean,
          summon_after: %{card_id => non_neg_integer},
          tower_used: boolean,
          max_at_start: [card_id],
          effects: map,
          zones: %{
            required(:patrol) => %{slot => card_id | nil},
            optional(zone_name) => [card_id]
          }
        }

  @type t :: %__MODULE__{
          seed: {integer, integer, integer},
          rng: :rand.state(),
          active: seat,
          phase: :main | :tech | :over,
          free: boolean,
          bot: seat | nil,
          winner: seat | nil,
          cards: %{card_id => card},
          sides: %{seat => side},
          trash: [card_id],
          log: [tuple],
          history: [t]
        }

  defstruct [
    :seed,
    :rng,
    :winner,
    active: 0,
    phase: :main,
    free: false,
    bot: nil,
    cards: %{},
    sides: %{},
    trash: [],
    log: [],
    history: []
  ]

  @doc "The 5 patrol slots, left to right."
  @spec patrol_slots() :: [slot]
  def patrol_slots, do: @patrol_slots

  @doc "The list zones of a side (every zone but `patrol`)."
  @spec list_zones() :: [zone_name]
  def list_zones, do: @list_zones

  @doc "The tech buildings and add-ons of `{:building, seat, building}`."
  @spec buildings() :: [atom]
  def buildings, do: @buildings

  @doc "The seats of a hot-seat room: one browser plays both sides."
  @spec table_seats() :: [0]
  def table_seats, do: [0]

  @doc "The seats of the room of `game`: `[0]` hot-seat, `[0, 1]` against the bot (seat 1)."
  @spec table_seats(t) :: [seat]
  def table_seats(%__MODULE__{bot: nil}), do: [0]
  def table_seats(%__MODULE__{}), do: [0, 1]

  @doc "How many states `:undo` can go back."
  @spec history_limit() :: pos_integer
  def history_limit, do: @history

  # -- set-up --------------------------------------------------------------------------

  @doc "A new game (the first-game set-up), in P1's first main phase. `opts` is not used yet."
  @spec new(map | keyword, {integer, integer, integer}) :: {:ok, t} | {:error, term}
  def new(opts \\ %{}, seed)

  def new(opts, seed) when is_list(opts), do: new(Map.new(opts), seed)

  def new(opts, {a, b, c} = seed)
      when is_map(opts) and is_integer(a) and is_integer(b) and is_integer(c) do
    bot = if opt(opts, :bot) in [true, "true"], do: 1

    with {:ok, setup} <- setup(opts) do
      game = %__MODULE__{seed: seed, rng: Rng.seed(seed), bot: bot}
      game = Enum.reduce([0, 1], game, &setup_side(&1, &2, setup[&1]))
      game = Rules.start_turn(%{game | log: [{:setup, seed}]}, 0)
      {:ok, game}
    end
  end

  def new(_opts, _seed), do: {:error, :invalid_seed}

  @doc ~s{The set-up presets: `"first"` (Bashing vs Finesse), `"red_green"` and `"blue_black"`.}
  @spec presets() :: map
  def presets, do: @presets

  # The set-up of `opts`: a preset (default "first"), or "custom" with a starting
  # deck and one spec per side (`p1_starter`, `p1_spec`, `p2_starter`, `p2_spec`).
  defp setup(opts) do
    case opt(opts, :preset) || "first" do
      "custom" ->
        sides = for s <- [0, 1], into: %{}, do: {s, custom(opts, s)}

        if Enum.all?(Map.values(sides), &valid?/1),
          do: {:ok, sides},
          else: {:error, :invalid_setup}

      preset ->
        preset_setup(preset)
    end
  end

  defp preset_setup(preset) do
    case Map.fetch(@presets, preset) do
      {:ok, sides} -> {:ok, sides}
      :error -> {:error, :invalid_setup}
    end
  end

  defp custom(opts, s) do
    p = "p#{s + 1}"
    %{starter: opt(opts, :"#{p}_starter"), specs: [opt(opts, :"#{p}_spec")]}
  end

  defp valid?(%{starter: starter, specs: [spec]}) do
    starter in Cards.colors() and spec in Enum.flat_map(Cards.colors(), &Cards.specs/1)
  end

  defp opt(opts, key), do: Map.get(opts, key) || Map.get(opts, Atom.to_string(key))

  defp setup_side(seat, game, %{starter: starter, specs: specs}) do
    workers = @workers[seat]
    spec = hd(specs)
    {game, deck} = add_cards(game, seat, Cards.starter(starter))
    codex_slugs = for sp <- specs, slug <- Cards.codex(sp), copy <- [slug, slug], do: copy
    {game, codex} = add_cards(game, seat, codex_slugs)
    {game, command} = add_cards(game, seat, Enum.map(specs, &Cards.hero/1))
    {game, worker_ids} = add_cards(game, seat, List.duplicate("worker", workers))

    game =
      Enum.reduce(
        worker_ids,
        game,
        &Zones.update_card(&2, &1, fn c -> %{c | face_down: true} end)
      )

    {deck, rng} = Rng.shuffle(deck, game.rng)
    {hand, deck} = Enum.split(deck, 5)

    side = %{
      spec: spec,
      specs: specs,
      starter: starter,
      tech_spec: if(length(specs) == 1, do: spec),
      gold: 0,
      base_hp: 20,
      tech_buildings: [],
      pending: [],
      building_damage: %{},
      destroyed: [],
      turn: 0,
      hired: false,
      reshuffled: false,
      summon_after: %{},
      tower_used: false,
      max_at_start: [],
      effects: %{},
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

  @doc """
  Add new cards of `slugs` for `seat` (in no zone yet). Returns the game and
  the new ids. A new id is the largest id + 1, so it is new also in a bot's
  copy of the state, where the hidden cards are not in `cards`.
  """
  @spec add_cards(t, seat, [String.t()]) :: {t, [card_id]}
  def add_cards(game, seat, slugs) do
    Enum.reduce(slugs, {game, []}, fn slug, {game, ids} ->
      id = game.cards |> Map.keys() |> Enum.max(fn -> 0 end) |> Kernel.+(1)
      card = new_card(id, slug, seat)
      {%{game | cards: Map.put(game.cards, id, card)}, ids ++ [id]}
    end)
  end

  @doc "A fresh instance of card `slug` (no tokens, level 1 for a hero)."
  @spec new_card(card_id, String.t(), seat) :: card
  def new_card(id, slug, seat) do
    %{
      id: id,
      card: slug,
      seat: seat,
      damage: 0,
      plus: 0,
      minus: 0,
      level: if(Cards.hero?(slug), do: 1),
      exhausted: false,
      face_down: false,
      fatigued: false,
      attacked: false,
      armor_dmg: 0,
      tmp_armor: 0,
      this_turn: %{},
      tmp_atk: 0,
      tmp_hp: 0,
      stealth: false,
      extra: %{}
    }
  end

  # -- the table contract ------------------------------------------------------------------

  @doc """
  The legal actions of a table seat: the rules actions of the active side
  (`Codex.Rules.legal/1`), `{:free_mode, _}` and `:undo` (when there is a state
  to go back to). In free mode also one atom per sandbox action kind.

  Hot-seat: seat 0 acts for the active side. Against the bot (`bot: 1`): each
  seat acts only on its own turn, and the bot has only the rules actions.
  """
  @spec legal_actions(t, non_neg_integer) :: [term]
  def legal_actions(%__MODULE__{} = game, seat) do
    cond do
      not acting?(game, seat) ->
        []

      seat == game.bot ->
        Rules.legal(game)

      true ->
        extra = [{:free_mode, !game.free}] ++ if(game.history == [], do: [], else: [:undo])
        sandbox = if game.free, do: @sandbox, else: []
        Rules.legal(game) ++ sandbox ++ extra
    end
  end

  # The seat that acts now: 0 in hot-seat, else the active side.
  defp acting?(%__MODULE__{bot: nil}, seat), do: seat == 0
  defp acting?(%__MODULE__{phase: :over}, seat), do: seat == 0
  defp acting?(%__MODULE__{active: active}, seat), do: seat == active

  @doc """
  `{:over, %{winner: seat}}` when a base is destroyed, else
  `{:playing, [seat]}`: seat 0 in hot-seat, the active side against the bot.
  """
  @spec status(t) :: {:playing, [seat]} | {:over, map}
  def status(%__MODULE__{phase: :over, winner: winner}), do: {:over, %{winner: winner}}
  def status(%__MODULE__{bot: nil}), do: {:playing, [0]}
  def status(%__MODULE__{active: active}), do: {:playing, [active]}

  @doc """
  Do `action` for a table seat (see `legal_actions/2` for who acts). Returns
  `{:ok, game}` or `{:error, reason}`.
  """
  @spec apply(t, non_neg_integer, term) :: {:ok, t} | {:error, term}
  def apply(%__MODULE__{} = game, seat, action) do
    cond do
      not acting?(game, seat) -> {:error, :not_your_seat}
      action in [:undo, {:undo}] and seat != game.bot -> undo(game)
      seat == game.bot and not rules_action?(action) -> {:error, :not_your_seat}
      true -> do_action(game, normalize(action))
    end
  end

  defp rules_action?(action),
    do: not match?({:free_mode, _}, action) and action not in [:undo, {:undo}]

  defp do_action(game, action) do
    case do_apply(game, action) do
      {:ok, new} ->
        new = Rules.cleanup(new)
        entry = {:action, game.active, action}
        {:ok, %{new | log: [entry | new.log], history: push(game)}}

      {:error, _} = error ->
        error
    end
  end

  defp normalize({:end_turn}), do: :end_turn
  defp normalize(action), do: action

  defp push(game), do: Enum.take([%{game | history: []} | game.history], @history)

  defp undo(%__MODULE__{history: []}), do: {:error, :nothing_to_undo}
  defp undo(%__MODULE__{history: [prev | rest]}), do: {:ok, %{prev | history: rest}}

  # -- the actions ---------------------------------------------------------------------------

  defp do_apply(game, {:free_mode, on}) when is_boolean(on), do: {:ok, %{game | free: on}}

  defp do_apply(%__MODULE__{free: false} = game, action) when elem(action, 0) in @sandbox,
    do: if(game.phase == :over, do: {:error, :game_over}, else: {:error, :free_mode_off})

  defp do_apply(%__MODULE__{free: true} = game, action)
       when is_tuple(action) and elem(action, 0) in @sandbox,
       do: sandbox(game, action)

  defp do_apply(game, action), do: Rules.act(game, action)

  defp sandbox(game, {:move, id, zone, at}) do
    with {:ok, _card} <- fetch_card(game, id),
         :ok <- check_zone(zone),
         :ok <- check_at(game, id, zone, at) do
      from = Zones.locate(game, id)
      game = Zones.move(game, id, zone, at)
      {:ok, Zones.update_card(game, id, &moved(&1, from, zone))}
    end
  end

  defp sandbox(game, {:draw, seat, n}) when n in 1..10 do
    with :ok <- check_seat(seat) do
      zones = game.sides[seat].zones

      if zones.deck == [] and zones.discard == [],
        do: {:error, :empty_deck},
        else: {:ok, Rules.draw(game, seat, n, :free)}
    end
  end

  defp sandbox(_game, {:draw, _seat, _n}), do: {:error, :invalid_count}

  defp sandbox(game, {:shuffle, seat, zone}) do
    with :ok <- check_seat(seat),
         :ok <- if(zone in @list_zones, do: :ok, else: {:error, :invalid_zone}) do
      {ids, rng} = Rng.shuffle(Zones.zone_ids(game, {seat, zone}), game.rng)
      {:ok, %{Zones.put_zone(game, {seat, zone}, ids) | rng: rng}}
    end
  end

  defp sandbox(game, {:adjust_card, id, key, delta})
       when key in @card_keys and is_integer(delta) and delta != 0 do
    with {:ok, card} <- fetch_card(game, id),
         {:ok, value} <- card_value(card, key, delta) do
      {:ok, Zones.update_card(game, id, &Map.put(&1, key, value))}
    end
  end

  defp sandbox(_game, {:adjust_card, _id, _key, _delta}), do: {:error, :invalid_adjust}

  defp sandbox(game, {:toggle, id, key}) when key in [:exhausted, :face_down] do
    with {:ok, _card} <- fetch_card(game, id) do
      {:ok, Zones.update_card(game, id, &Map.update!(&1, key, fn v -> !v end))}
    end
  end

  defp sandbox(_game, {:toggle, _id, _key}), do: {:error, :invalid_toggle}

  defp sandbox(game, {:adjust, seat, key, delta})
       when key in [:gold, :base_hp] and is_integer(delta) and delta != 0 do
    with :ok <- check_seat(seat) do
      value = game.sides[seat][key] + delta

      if value in 0..@max_counter,
        do: {:ok, put_in(game.sides[seat][key], value)},
        else: {:error, :out_of_range}
    end
  end

  defp sandbox(_game, {:adjust, _seat, _key, _delta}), do: {:error, :invalid_adjust}

  defp sandbox(game, {:building, seat, building}) when building in @buildings do
    with :ok <- check_seat(seat) do
      {:ok,
       update_in(game.sides[seat].tech_buildings, fn list ->
         if building in list, do: List.delete(list, building), else: list ++ [building]
       end)}
    end
  end

  defp sandbox(_game, {:building, _seat, _building}), do: {:error, :invalid_building}
  defp sandbox(_game, _action), do: {:error, :invalid_action}

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

  # What a card keeps after a sandbox move from zone `from` to zone `to`.
  defp moved(card, from, to) do
    card =
      if Zones.zone_name(from) in @play_zones and Zones.zone_name(to) not in @play_zones,
        do: Rules.reset(card),
        else: card

    cond do
      Zones.zone_name(to) == :workers -> %{card | face_down: true}
      Zones.zone_name(from) == :workers -> %{card | face_down: false}
      true -> card
    end
  end

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

  defp fetch_card(game, id) do
    case Map.fetch(game.cards, id) do
      {:ok, card} -> {:ok, card}
      :error -> {:error, :no_card}
    end
  end

  # -- zones (the API of `Codex.Zones`) --------------------------------------------------------

  @doc "See `Codex.Zones.locate/2`."
  @spec locate(map, card_id) :: zone | {seat, :patrol, slot} | nil
  defdelegate locate(game, id), to: Zones

  @doc "See `Codex.Zones.placements/1`."
  @spec placements(map) :: [{card_id, zone | {seat, :patrol, slot}}]
  defdelegate placements(game), to: Zones

  @doc "See `Codex.Zones.zone_ids/2`."
  @spec zone_ids(t, zone) :: [card_id]
  defdelegate zone_ids(game, zone), to: Zones

  @doc "Every card id in every zone, with repeats (the conservation check)."
  @spec all_placed(t) :: [card_id]
  def all_placed(game), do: Enum.map(Zones.placements(game), &elem(&1, 0))

  # -- the view ------------------------------------------------------------------------------

  @doc """
  What a page sees. Hot-seat: both hands, the codex and the workers are in the
  view (the board hides the other side's hand). The decks are only counts.
  `stats` has each card's ATK/HP now (`Codex.Rules.stats/2`).
  """
  @spec view(t, non_neg_integer | :spectator) :: map
  def view(%__MODULE__{} = game, seat) do
    stats = Rules.all_stats(game)
    deck_ids = Enum.flat_map(game.sides, fn {_s, side} -> side.zones.deck end)

    view = %{
      active: game.active,
      phase: game.phase,
      free: game.free,
      bot: game.bot,
      winner: game.winner,
      sides:
        Map.new(game.sides, fn {seat, side} ->
          zones = side.zones
          {seat, %{side | zones: Map.put(zones, :deck, length(zones.deck))}}
        end),
      trash: game.trash,
      cards: game.cards |> Map.drop(deck_ids) |> with_stats(stats) |> fatigue(game),
      stats: stats,
      log: Enum.take(game.log, 30),
      undo: game.history != []
    }

    # The bot's seat gets the fair view with its legal actions (`Codex.Bot`).
    if seat == game.bot and seat != nil, do: bot_view(game, seat), else: view
  end

  @doc """
  What a bot in `seat` may see: the view (`view/2`) without the hidden
  information of the rules (research §15: hand, draw pile order, face-down
  discard pile, codex picks, workers). The other side's hand, discard pile,
  codex and workers, and both decks, are only counts; those cards are not in
  `cards`. The log is empty (it names the tech picks and the hired cards). The
  bot's own hand, discard pile and codex stay. `legal` has the legal actions
  when `seat` is the active side, else `[]`.

  The board does not use it: a person in hot-seat sees both hands.
  """
  @spec bot_view(t, seat) :: map
  def bot_view(%__MODULE__{} = game, seat) when seat in [0, 1] do
    view = view(%{game | bot: nil}, :spectator)
    opp = 1 - seat
    zones = game.sides[opp].zones
    hidden_zones = [:hand, :discard, :codex, :workers]
    hidden = Enum.flat_map(hidden_zones, &Map.fetch!(zones, &1))
    counts = Map.new(hidden_zones, &{&1, length(Map.fetch!(zones, &1))})

    view
    |> Map.put(:bot, game.bot)
    |> update_in([:sides, opp, :zones], &Map.merge(&1, counts))
    |> Map.update!(:cards, &Map.drop(&1, hidden))
    |> Map.update!(:stats, &Map.drop(&1, hidden))
    |> Map.put(:log, [])
    |> Map.put(:legal, if(game.active == seat, do: Rules.legal(game), else: []))
  end

  # Arrival fatigue matters on its controller's turn only: the view shows it for the active side.
  defp fatigue(cards, game) do
    idle = Zones.in_play(game, 1 - game.active)
    Enum.reduce(idle, cards, fn id, cards -> Map.update!(cards, id, &%{&1 | fatigued: false}) end)
  end

  # Each unit and hero in play carries its ATK/HP now as `now`.
  defp with_stats(cards, stats) do
    Map.new(cards, fn {id, c} ->
      case stats do
        %{^id => now} -> {id, Map.put(c, :now, now)}
        _ -> {id, c}
      end
    end)
  end
end
