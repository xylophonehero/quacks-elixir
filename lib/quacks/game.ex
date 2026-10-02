defmodule Quacks.Game do
  @moduledoc """
  Pure Quacks engine for 1 to 4 players: one struct, one reducer.

  A 9-round game (see `docs/research/rulebook.md` §2, §3, §3.2, §4, §7) with the pot
  track, bags, draw/stop, explosion, flask, rats, bonus die, rubies, the Ingredient
  Set 1 chip effects, a shared chip supply, buying chips and end-game scoring.

  Each seat (`0..3`, turn order) has a `Quacks.Player`. Game phases: `:potions`, where
  every player not yet `:done` acts in any order (each has their own potions-phase
  `phase`), then — as soon as the last player is done — the evaluation runs inside
  `apply/3` and the game moves to `:buy_chips` and `:spend_rubies`, where exactly one
  seat (`turn`) acts at a time, in seat order from the round's start player. After
  round 9 the phase is `:over`. The struct never rests without a legal action for
  some seat unless `over?/1`.

  Fortune Teller cards (`Quacks.Game.Fortune`): each round starts by turning up a
  card. A purple card with a choice puts the game in `:fortune_choice` (one `turn`
  seat at a time) before `:potions`; Toil and Trouble (B2) does the same between
  `:potions` and the evaluation.

  `apply/2` and `legal_actions/1` are seat-0 shortcuts for solo callers. All
  randomness flows through one shared `rng` (`:rand` `_s` API), so a seed, the player
  count and a list of `{seat, action}` reproduces a game exactly (`Quacks.Session`).

      iex> game = Quacks.Game.new(seed: {1, 2, 3}, players: 2)
      iex> Quacks.Game.legal_actions(game, 1)
      [:draw]
      iex> {:ok, game} = Quacks.Game.apply(game, 1, :draw)
      iex> Quacks.Game.legal_actions(game, 1)
      [:draw, :stop, :use_flask]
  """

  import Kernel, except: [apply: 2, apply: 3]
  alias Quacks.Game.{Fortune, Potions}
  alias Quacks.Player
  alias Quacks.Rules.{Chips, ScoringTrack}

  @rounds 9
  # Rulebook §4: yellow enters the shop in round 2, purple in round 3.
  @from_round %{yellow: 2, purple: 3}
  # Ingredient Sets (research `ingredient-sets-and-customisation.md`). These books need
  # a choice in the evaluation (G2, G4, P2, P4) or a zone beside the pot (R2).
  @sets %{green: 1, blue: 1, red: 1, yellow: 1, purple: 1}
  @unsupported [green: 2, green: 4, purple: 2, purple: 4, red: 2]

  defstruct round: 1,
            phase: :potions,
            turn: nil,
            supply: %{},
            rng: nil,
            log: [],
            players: %{},
            seats: [],
            fortune_deck: [],
            fortune_card: nil,
            sets: @sets

  @type seat :: 0..3
  @type phase :: :potions | :fortune_choice | :buy_chips | :spend_rubies | :over
  @type action ::
          :draw
          | :stop
          | :use_flask
          | :return_white
          | :keep
          | {:place, Chips.chip()}
          | :return_all
          | {:explosion_choice, :vp | :buy}
          | {:buy, [Chips.chip()]}
          | {:rubies, :droplet | :flask | :skip}
          | :end_round
          | {:fortune, fortune_choice}
  @typedoc "A Fortune Teller card choice; see `Quacks.Game.Fortune` and `docs/CONTEXT.md`."
  @type fortune_choice ::
          {:take, Chips.chip()}
          | :rubies
          | :skip
          | :vp
          | :remove_white
          | {:rats_back, 1..3}
          | :droplet
          | {:upgrade, Chips.chip()}
          | :restart_round
          | :return_white
          | {:place, Chips.chip()}
          | :return_all
  @type die_face :: {:vp, 1 | 2} | :ruby | :droplet | :orange
  @typedoc """
  An event that concerns one player; it is logged as `{seat, event}`. Every action is
  logged (tagged) and followed by the events it caused: `{:drew, chip, index}` for
  each placement (blue-placed chips too), `{:returned, chip}` for flask, mandrake and
  crow-skull returns, `{:exploded, white_sum}`, `{:bought, chips}` and
  `{:rubies_spent, :droplet | :flask}`.

  Evaluation is narrated too: `{:bonus_die, face}`, the chip actions (`{:black,
  :droplet | :droplet_ruby}`, `{:green_rubies, n}`, `{:purple, tier, payoff}`), the
  scoring space (`{:pot_ruby, index}`, `{:pot_vp, vp, index}`), `{:final_conversion,
  coins_vp, rubies_vp}` in round 9 and `{:rats, tails}` when a player gets a head
  start. See the Log table in `docs/CONTEXT.md`.
  """
  @type event ::
          action
          | {:drew, Chips.chip(), 0..53}
          | {:returned, Chips.chip()}
          | {:exploded, non_neg_integer}
          | {:bought, [Chips.chip()]}
          | {:rubies_spent, :droplet | :flask}
          | {:bonus_die, die_face}
          | {:black, :droplet | :droplet_ruby}
          | {:green_rubies, pos_integer}
          | {:purple, 1, :vp1}
          | {:purple, 2, :vp1_ruby}
          | {:purple, 3, :vp2_droplet}
          | {:pot_ruby, 0..53}
          | {:pot_vp, pos_integer, 0..53}
          | {:final_conversion, non_neg_integer, non_neg_integer}
          | {:rats, pos_integer}
          | {:fortune, Quacks.Rules.Fortune.id(), term}
          | {:effect, {Chips.colour(), 2..4}, term}
  @typedoc """
  What happened, newest first. Player events are tagged with their seat; the only
  game-wide entries are `{:fortune_drawn, id}` and `{:fortune_skipped, id}` at the
  start of a round and `{:round_end, round}`, the last event of every round.
  `Quacks.Session` replays from its own action list, not this.
  """
  @type log_entry ::
          {seat, event}
          | {:round_end, 1..9}
          | {:fortune_drawn, Quacks.Rules.Fortune.id()}
          | {:fortune_skipped, Quacks.Rules.Fortune.id()}
  @type t :: %__MODULE__{
          round: 1..9,
          phase: phase,
          turn: seat | nil,
          supply: %{Chips.chip() => non_neg_integer},
          rng: :rand.state(),
          log: [log_entry],
          players: %{seat => Player.t()},
          seats: [seat],
          fortune_deck: [Quacks.Rules.Fortune.id()],
          fortune_card: Quacks.Rules.Fortune.id() | nil,
          sets: %{(:green | :blue | :red | :yellow | :purple) => 1..4}
        }

  @doc """
  A fresh game. `seed:` is a `{int, int, int}` tuple for `:rand.seed_s(:exsss, seed)`;
  `players:` is 1 (default) to 4. Every starting bag comes out of the shared supply.
  `fortune: false` plays without Fortune Teller cards (default `true`); otherwise
  round 1's card is turned up here. `sets:` picks the Ingredient Set (1..4) per colour,
  e.g. `%{blue: 3}`; colours left out use Set 1. Green 2/4, purple 2/4 and red 2 are
  not supported yet and raise `ArgumentError`.
  """
  @spec new(
          seed: {integer, integer, integer},
          players: 1..4,
          fortune: boolean,
          sets: %{atom => 1..4}
        ) :: t
  def new(opts) do
    seed = Keyword.fetch!(opts, :seed)
    n = Keyword.get(opts, :players, 1)
    if n not in 1..4, do: raise(ArgumentError, "players must be 1..4, got #{inspect(n)}")
    sets = sets!(Keyword.get(opts, :sets, %{}))

    seats = Enum.to_list(0..(n - 1))
    bag = Chips.starting_bag()
    starting = List.flatten(List.duplicate(bag, n))
    supply = Enum.reduce(starting, Chips.supply(), &Map.update!(&2, &1, fn c -> c - 1 end))

    rng = :rand.seed_s(:exsss, seed)
    deck = if Keyword.get(opts, :fortune, true), do: Fortune.deck(rng, n), else: []

    start_round(%__MODULE__{
      seats: seats,
      players: Map.new(seats, &{&1, Player.new(bag)}),
      supply: supply,
      rng: rng,
      fortune_deck: deck,
      sets: sets
    })
  end

  defp sets!(sets) do
    sets = Map.merge(@sets, sets)

    if map_size(sets) != map_size(@sets) or Enum.any?(sets, fn {_, set} -> set not in 1..4 end),
      do: raise(ArgumentError, "sets must map #{inspect(Map.keys(@sets))} to 1..4")

    case Enum.find(sets, &(&1 in @unsupported)) do
      nil -> sets
      set -> raise ArgumentError, "ingredient set #{inspect(set)} is not supported yet"
    end
  end

  @doc "True after round 9's evaluation."
  @spec over?(t) :: boolean
  def over?(%__MODULE__{phase: phase}), do: phase == :over

  @doc "Victory points so far, per seat."
  @spec score(t) :: %{seat => non_neg_integer}
  def score(%__MODULE__{players: players}), do: Map.new(players, fn {seat, p} -> {seat, p.vp} end)

  @doc "The phase `seat` sees: their own potions-phase state, or the game's phase."
  @spec phase(t, seat) :: phase | Player.phase()
  def phase(%__MODULE__{phase: :potions, players: players}, seat) when is_map_key(players, seat),
    do: players[seat].phase

  def phase(%__MODULE__{phase: phase}, _seat), do: phase

  @doc "Sum of white chip values in `seat`'s pot this round."
  @spec white_sum(t, seat) :: non_neg_integer
  def white_sum(%__MODULE__{} = g, seat \\ 0), do: Player.white_sum(player(g, seat))

  @doc "The chips in `seat`'s pot without their positions, newest first."
  @spec pot_chips(t, seat) :: [Chips.chip()]
  def pot_chips(%__MODULE__{} = g, seat \\ 0), do: Player.pot_chips(player(g, seat))

  @doc "`seat`'s scoring space: directly after the last placed chip, clamped to the spoon."
  @spec scoring_index(t, seat) :: 0..53
  def scoring_index(%__MODULE__{} = g, seat \\ 0), do: Player.scoring_index(player(g, seat))

  @doc "The seat that starts this round; it rotates one seat per round."
  @spec start_seat(t) :: seat
  def start_seat(%__MODULE__{round: round, seats: seats}), do: rem(round - 1, length(seats))

  @doc """
  Every action `apply/3` accepts for `seat` right now. During `:potions` every seat
  not yet done has actions; in the shop and rubies phases only `turn` has. Empty for
  every seat only when `over?/1`.
  """
  @spec legal_actions(t, seat) :: [action]
  def legal_actions(game, seat \\ 0)

  def legal_actions(%__MODULE__{players: players}, seat) when not is_map_key(players, seat),
    do: []

  def legal_actions(%__MODULE__{phase: :potions} = g, seat),
    do: Potions.legal_actions(player(g, seat)) ++ Fortune.legal_actions(g, seat)

  def legal_actions(%__MODULE__{phase: :fortune_choice, turn: seat} = g, seat),
    do: Fortune.legal_actions(g, seat)

  def legal_actions(%__MODULE__{phase: :buy_chips, turn: seat} = g, seat),
    do: Enum.map(buys(g, player(g, seat)), &{:buy, &1})

  def legal_actions(%__MODULE__{phase: :spend_rubies, turn: seat} = g, seat) do
    %{rubies: rubies, flask: flask} = player(g, seat)

    List.flatten([
      if(rubies >= 2, do: {:rubies, :droplet}, else: []),
      if(rubies >= 2 and not flask, do: {:rubies, :flask}, else: []),
      :end_round
    ])
  end

  def legal_actions(%__MODULE__{}, _seat), do: []

  @doc "`apply/3` for seat 0."
  @spec apply(t, action) :: {:ok, t} | {:error, {:illegal_action, action, phase | Player.phase()}}
  def apply(%__MODULE__{} = game, action), do: apply(game, 0, action)

  @doc """
  Apply one action for `seat`. Illegal actions (wrong phase, not this seat's turn,
  unaffordable buy, empty bag, ...) return `{:error, {:illegal_action, action, phase}}`
  with the phase that seat sees (`phase/2`) and leave the game untouched.

  `{:buy, chips}` accepts chips in any order; `{:rubies, :skip}` equals `:end_round`.
  """
  @spec apply(t, seat, action) ::
          {:ok, t} | {:error, {:illegal_action, action, phase | Player.phase()}}
  def apply(%__MODULE__{} = game, seat, action) do
    action = normalise(action)

    if action in legal_actions(game, seat) do
      # The action goes in the log first, so the events it causes come after it.
      {:ok, game |> record(seat, action) |> step(seat, action)}
    else
      {:error, {:illegal_action, action, phase(game, seat)}}
    end
  end

  defp normalise({:buy, chips}), do: {:buy, Enum.sort(chips)}
  defp normalise({:rubies, :skip}), do: :end_round
  defp normalise(action), do: action

  # -- potions: every seat in any order; evaluation when the last one is done -------

  defp step(%{phase: :potions} = g, seat, action) do
    g =
      case action do
        {:fortune, _} -> Fortune.step(g, seat, action)
        _ -> Potions.step(g, seat, action)
      end

    if Enum.all?(g.players, fn {_seat, p} -> p.done? end), do: Fortune.after_potions(g), else: g
  end

  # -- Fortune Teller choices: one seat at a time -------------------------------------

  defp step(%{phase: :fortune_choice} = g, seat, action), do: Fortune.step(g, seat, action)

  # -- shop and rubies: one seat at a time, in turn order ---------------------------

  defp step(%{phase: :buy_chips} = g, seat, {:buy, chips}) do
    cost = chips |> Enum.map(&Chips.price(&1, g.sets)) |> Enum.sum()
    g = Enum.reduce(chips, g, &take_supply(&2, &1))
    g = update_player(g, seat, &%{&1 | coins: &1.coins - cost, bag: chips ++ &1.bag})
    g = if chips == [], do: g, else: record(g, seat, {:bought, chips})
    to_shop(g, seats_after(g, seat))
  end

  defp step(%{phase: :spend_rubies} = g, seat, {:rubies, :droplet}) do
    g
    |> update_player(seat, &%{&1 | rubies: &1.rubies - 2, droplet: &1.droplet + 1})
    |> record(seat, {:rubies_spent, :droplet})
  end

  defp step(%{phase: :spend_rubies} = g, seat, {:rubies, :flask}) do
    g
    |> update_player(seat, &%{&1 | rubies: &1.rubies - 2, flask: true})
    |> record(seat, {:rubies_spent, :flask})
  end

  defp step(%{phase: :spend_rubies} = g, seat, :end_round) do
    case seats_after(g, seat) do
      [next | _] -> %{g | turn: next}
      [] -> end_round(g)
    end
  end

  # Rulebook §7: 5 coins or 2 rubies buy 1 VP, as often as you like.
  defp end_round(%{round: @rounds} = g) do
    g = Enum.reduce(turn_order(g), g, &final_conversion(&2, &1))
    record(%{g | phase: :over, turn: nil}, {:round_end, @rounds})
  end

  defp end_round(g) do
    round = g.round + 1
    g = record(g, {:round_end, g.round})

    g =
      Enum.reduce(g.seats, g, fn seat, g ->
        g = update_player(g, seat, &Player.reset/1)
        # Rulebook §3 step 5: before turn 6 each player adds 1 white 1-chip.
        if round == 6, do: add_from_supply(g, seat, {:white, 1}), else: g
      end)

    start_round(%{g | round: round, phase: :potions, turn: nil})
  end

  # Rulebook §3 steps 1–2: the Fortune Teller card, the rats, then the purple card.
  defp start_round(g), do: g |> Fortune.draw() |> place_rats() |> Fortune.resolve()

  defp final_conversion(g, seat) do
    %{coins: coins, rubies: rubies} = player(g, seat)
    {coins_vp, rubies_vp} = {div(coins, 5), div(rubies, 2)}

    g
    |> update_player(
      seat,
      &%{&1 | vp: &1.vp + coins_vp + rubies_vp, coins: rem(coins, 5), rubies: rem(rubies, 2)}
    )
    |> record(seat, {:final_conversion, coins_vp, rubies_vp})
  end

  # Rulebook §3 step 2 (round 2+, 2+ players): everyone behind the leader counts the
  # rat tails up to the leader and starts that many spaces past their droplet.
  defp place_rats(%{seats: [_]} = g), do: g

  defp place_rats(g) do
    leader = g.players |> Map.values() |> Enum.map(& &1.vp) |> Enum.max()

    Enum.reduce(g.seats, g, fn seat, g ->
      case ScoringTrack.rat_tails(player(g, seat).vp, leader) do
        0 ->
          g

        tails ->
          g
          |> update_player(seat, &%{&1 | rat_stone: tails, pot_index: &1.droplet + tails})
          |> record(seat, {:rats, tails})
      end
    end)
  end

  # Every affordable purchase: nothing, one chip, or two chips of different colours.
  defp buys(g, %Player{coins: coins}) do
    price = &Chips.price(&1, g.sets)
    singles = Enum.filter(Chips.shop(), &(price.(&1) <= coins and available?(g, &1)))

    pairs =
      for {ca, _} = a <- singles,
          {cb, _} = b <- singles,
          a < b and ca != cb and price.(a) + price.(b) <= coins,
          do: [a, b]

    [[] | Enum.map(singles, &[&1])] ++ pairs
  end

  # -- shared helpers for Potions and Evaluation --------------------------------------

  @doc false
  def player(%__MODULE__{players: players}, seat), do: Map.fetch!(players, seat)

  @doc false
  def update_player(%__MODULE__{players: players} = g, seat, fun),
    do: %{g | players: Map.update!(players, seat, fun)}

  @doc false
  def record(%__MODULE__{log: log} = g, entry), do: %{g | log: [entry | log]}

  @doc false
  def record(%__MODULE__{} = g, seat, entry), do: record(g, {seat, entry})

  # A chip can be bought or taken: its book is out this round and the box has one.
  @doc false
  def available?(%__MODULE__{round: round, supply: supply}, {colour, _} = chip),
    do: round >= Map.get(@from_round, colour, 1) and Map.fetch!(supply, chip) > 0

  @doc false
  def take_supply(%__MODULE__{} = g, chip),
    do: %{g | supply: Map.update!(g.supply, chip, &(&1 - 1))}

  # Move a chip from the supply into a bag; nothing happens when the box is empty.
  @doc false
  def add_from_supply(%__MODULE__{} = g, seat, chip) do
    if g.supply[chip] > 0,
      do: g |> take_supply(chip) |> update_player(seat, &%{&1 | bag: [chip | &1.bag]}),
      else: g
  end

  @doc false
  # Log a Set 2–4 chip effect: `{seat, {:effect, {colour, set}, detail}}`.
  def effect(%__MODULE__{} = g, seat, book, detail), do: record(g, seat, {:effect, book, detail})

  # The seats from this round's start player round the table.
  @doc false
  def turn_order(%__MODULE__{seats: seats} = g) do
    {before, from} = Enum.split(seats, start_seat(g))
    from ++ before
  end

  @doc false
  def seats_after(g, seat), do: g |> turn_order() |> Enum.drop_while(&(&1 != seat)) |> tl()

  # Open the shop for the first of `seats` that may buy (an exploded player who took
  # the VP skips it); with nobody left, or in round 9, go to the rubies phase.
  # ponytail: round 9 skips the shop; chips bought now are useless (§7). Coins stay on
  # the player and convert to VP in `:end_round`.
  @doc false
  def to_shop(%__MODULE__{round: @rounds} = g, _seats),
    do: %{g | phase: :spend_rubies, turn: start_seat(g)}

  def to_shop(%__MODULE__{} = g, seats) do
    case Enum.find(seats, &(player(g, &1).explosion_choice != :vp)) do
      nil -> %{g | phase: :spend_rubies, turn: start_seat(g)}
      seat -> %{g | phase: :buy_chips, turn: seat}
    end
  end
end
