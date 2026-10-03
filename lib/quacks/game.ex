defmodule Quacks.Game do
  @moduledoc """
  Pure Quacks engine for 1 to 4 players (5 with The Herb Witches): one struct, one reducer.

  A 9-round game (see `docs/research/rulebook.md` §2, §3, §3.2, §4, §7) with the pot
  track, bags, draw/stop, explosion, flask, rats, bonus die, rubies, the Ingredient
  Set 1 chip effects, a shared chip supply, buying chips and end-game scoring.

  Each seat (`0..3`, turn order) has a `Quacks.Player`. Game phases: `:potions`, where
  every player not yet `:done` acts in any order (each has their own potions-phase
  `phase`), then — as soon as the last player is done — the evaluation runs inside
  `apply/3` and the game moves to `:buy_chips` and `:spend_rubies`, where exactly one
  seat (`turn`) acts at a time, in seat order from the round's start player. Ingredient
  books with a choice in the evaluation (G2, G4, P2, P4) put the game in `:chip_choice`
  first, one `turn` seat at a time (`Quacks.Game.Evaluation`). After
  round 9 the phase is `:over`. The struct never rests without a legal action for
  some seat unless `over?/1`.

  House rules (`rules`, see `new/1`) change a few table rules: the explosion limit,
  the round-6 white chip, the cards, the rats, solo black, the die and the starting
  rubies. The defaults are the rulebook game.

  The Herb Witches (`expansion: :herb_witches`, `docs/research/herb-witches.md`) adds
  a 5th seat, Sets 5 and 6 for every coloured book, the black and locoweed books, the
  orange 6-chip, the overflow bowl (`Quacks.Player.bowl`) and the herb witches
  (`Quacks.Game.Witches`): one witch of each penny colour is turned up at `new/1`
  (`witches`), and every player may call each of them once per game with
  `{:witch, colour}` or `{:witch, colour, choice}`. Gold witches with a choice in the
  evaluation put the game in `:witch_choice`, one `turn` seat at a time.

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
  alias Quacks.Game.{Evaluation, Fortune, Potions, Witches}
  alias Quacks.Player
  alias Quacks.Rules.{Chips, ScoringTrack}
  alias Quacks.Rules.Witches, as: WitchCards

  @rounds 9
  # Rulebook §4: yellow enters the shop in round 2, purple in round 3.
  @from_round %{yellow: 2, purple: 3}
  # Ingredient Sets (research `ingredient-sets-and-customisation.md`): Set 1 by default.
  @sets %{green: 1, blue: 1, red: 1, yellow: 1, purple: 1}
  # The Herb Witches: black (1 = the base book, 5, 6) and locoweed (5, 6) have books too.
  # ⚠️ Locoweed enters the shop in round 1 (not in the rulebook; `herb-witches.md` §1.2).
  @expansion_sets %{black: 1, locoweed: 5}
  # House rules (research `ingredient-sets-and-customisation.md` Part 2b): the rulebook game.
  @rules %{
    explode_above: 7,
    round6_white: true,
    fortune: true,
    rats: true,
    black_solo: :droplet,
    die: :standard,
    starting_rubies: 1
  }

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
            sets: @sets,
            rules: @rules,
            expansion: nil,
            witches: nil

  @type seat :: 0..4
  @type phase ::
          :potions
          | :fortune_choice
          | :chip_choice
          | :witch_choice
          | :buy_chips
          | :spend_rubies
          | :over
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
          | {:red, {:place | :keep | :return, Chips.chip()}}
          | {:chip, chip_choice}
          | :chip_done
          | {:witch, WitchCards.colour()}
          | {:witch, WitchCards.colour(), term}
          | :witch_done
  @typedoc """
  A chip choice: step B (G2, G4, P2, P4, G5, P5; see `Quacks.Game.Evaluation`) or on
  draw (Y6 `:yellow_ruby`, see `Quacks.Game.Potions`).
  """
  @type chip_choice ::
          {:gain, Chips.chip()}
          | {:pay_ruby_move, 1..2}
          | {:purple_trade, 1..3}
          | {:upgrade, Chips.chip(), Chips.chip()}
          | {:starter, Chips.chip()}
          | {:buy, [Chips.chip()]}
          | :yellow_ruby
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

  The Herb Witches: `{:overflow, chip}` for a chip that goes in the overflow bowl,
  `{:bowl, chips, vp}` for the bowl's VP in step D, `{:witch, id, outcome}` for what a
  witch did, `{:rubies_spent, what, 1}` for a 1-ruby spend (G4) and `{:pennies, vp}`
  for the unused witch pennies at the end.
  """
  @type event ::
          action
          | {:drew, Chips.chip(), 0..53}
          | {:overflow, Chips.chip()}
          | {:bowl, [Chips.chip()], non_neg_integer}
          | {:returned, Chips.chip()}
          | {:exploded, non_neg_integer}
          | {:bought, [Chips.chip()]}
          | {:rubies_spent, :droplet | :flask}
          | {:rubies_spent, :droplet | :flask, 1}
          | {:witch, WitchCards.id(), term}
          | {:pennies, pos_integer}
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
          | {:effect, {Chips.colour(), 2..6}, term}
  @typedoc """
  What happened, newest first. Player events are tagged with their seat; the only
  game-wide entries are `{:expansion, :herb_witches}` (the first entry of an expansion
  game), `{:fortune_drawn, id}` and `{:fortune_skipped, id}` at the start of a round and
  `{:round_end, round}`, the last event of every round.
  `Quacks.Session` replays from its own action list, not this.
  """
  @type log_entry ::
          {seat, event}
          | {:round_end, 1..9}
          | {:expansion, :herb_witches}
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
          sets: Chips.sets(),
          rules: rules,
          expansion: Chips.expansion(),
          witches: nil | %{WitchCards.colour() => WitchCards.id()}
        }
  @typedoc """
  House rules; the defaults (`default_rules/0`) are the rulebook game.
  `explode_above` is the white limit before chips and cards raise it, `black_solo`
  the solo black payout (rulebook §6.2 suggests `:droplet_ruby`), `die: :no_orange`
  turns the orange face into a second ruby face (⚠️ unofficial).
  """
  @type rules :: %{
          explode_above: 5..9,
          round6_white: boolean,
          fortune: boolean,
          rats: boolean,
          black_solo: :droplet | :droplet_ruby,
          die: :standard | :no_orange,
          starting_rubies: 0..3
        }

  @doc """
  A fresh game. `seed:` is a `{int, int, int}` tuple for `:rand.seed_s(:exsss, seed)`;
  `players:` is 1 (default) to 4. Every starting bag comes out of the shared supply.
  `sets:` picks the Ingredient Set (1..4) per colour, e.g. `%{blue: 3}`; colours left
  out use Set 1. `orange: 2` adds the orange 6-chip and `locoweed: 5 | 6` adds
  locoweed, in base games too (see `Quacks.Rules.Chips.set/3`). `rules:` sets house rules (`t:rules/0`), e.g. `%{explode_above: 9}`;
  rules left out keep their default. With `fortune: true` (default) round 1's card
  is turned up here. `fortune: false` is an old alias for `rules: %{fortune: false}`.
  `expansion: :herb_witches` turns The Herb Witches on: `players:` 1 to 5, `sets:`
  1..6 per colour plus `black:` (1 = base book, 5, 6), `locoweed:` (5 default, 6, nil)
  and `orange:` (2 default, 1),
  the expansion chips in the supply and the shop, the overflow bowl, 3 witches
  (`witches`, dealt from the seed) and 3 witch pennies per player.
  An unknown colour, set, rule or expansion raises `ArgumentError`.
  """
  @spec new(
          seed: {integer, integer, integer},
          players: 1..5,
          sets: %{atom => 1..6},
          rules: map,
          fortune: boolean,
          expansion: Chips.expansion()
        ) :: t
  def new(opts) do
    seed = Keyword.fetch!(opts, :seed)
    expansion = Keyword.get(opts, :expansion)

    if expansion not in [nil, :herb_witches],
      do: raise(ArgumentError, "unknown expansion #{inspect(expansion)}")

    n = Keyword.get(opts, :players, 1)
    max = if expansion, do: 5, else: 4
    if n not in 1..max, do: raise(ArgumentError, "players must be 1..#{max}, got #{inspect(n)}")
    sets = sets!(Keyword.get(opts, :sets, %{}), expansion)
    # `fortune:` is the old top-level option; `rules:` wins when both are given.
    alias_rules = Map.new(Keyword.take(opts, [:fortune]))
    rules = rules!(Map.merge(alias_rules, Keyword.get(opts, :rules, %{})))

    seats = Enum.to_list(0..(n - 1))
    bag = Chips.starting_bag()
    starting = List.flatten(List.duplicate(bag, n))

    supply =
      Enum.reduce(
        starting,
        Chips.supply(expansion, sets),
        &Map.update!(&2, &1, fn c -> c - 1 end)
      )

    rng = :rand.seed_s(:exsss, seed)
    deck = if rules.fortune, do: Fortune.deck(rng, n), else: []
    player = %{Player.new(bag) | rubies: rules.starting_rubies}

    player =
      if expansion,
        do: %{player | pennies: %{silver: true, copper: true, gold: true}},
        else: player

    game = %__MODULE__{
      seats: seats,
      players: Map.new(seats, &{&1, player}),
      supply: supply,
      rng: rng,
      fortune_deck: deck,
      sets: sets,
      rules: rules,
      expansion: expansion,
      witches: if(expansion, do: WitchCards.deal(rng))
    }

    start_round(if expansion, do: record(game, {:expansion, expansion}), else: game)
  end

  # Base game: Sets 1..4. The expansion adds Sets 5..6 and the black book. Both may
  # pick orange 1 or 2 (2 = the orange 6-chip) and locoweed nil, 5 or 6.
  defp sets!(sets, expansion) do
    defaults = if expansion, do: Map.merge(@sets, @expansion_sets), else: @sets
    max = if expansion, do: 6, else: 4
    sets = Map.merge(defaults, sets)

    valid? =
      Enum.all?(sets, fn
        {:orange, set} -> set in [1, 2]
        {:locoweed, set} -> set in [nil, 5, 6]
        {:black, set} -> expansion != nil and set in [1, 5, 6]
        {colour, set} -> is_map_key(@sets, colour) and set in 1..max
      end)

    if not valid?, do: raise(ArgumentError, "bad sets: #{inspect(sets)}")
    sets
  end

  @doc "The house rules of the rulebook game (see `t:rules/0`)."
  @spec default_rules() :: rules
  def default_rules, do: @rules

  defp rules!(rules) do
    rules = Map.merge(@rules, rules)

    valid? =
      map_size(rules) == map_size(@rules) and rules.explode_above in 5..9 and
        is_boolean(rules.round6_white) and is_boolean(rules.fortune) and
        is_boolean(rules.rats) and rules.black_solo in [:droplet, :droplet_ruby] and
        rules.die in [:standard, :no_orange] and rules.starting_rubies in 0..3

    if not valid?, do: raise(ArgumentError, "bad rules: #{inspect(rules)}")
    rules
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

  # While the silver witch S2's offer is out, placing from it is all the seat may do.
  def legal_actions(%__MODULE__{phase: :potions} = g, seat) do
    case player(g, seat) do
      %Player{phase: :potions, witch_offer: [_ | _]} ->
        Witches.legal_actions(g, seat)

      _ ->
        Potions.legal_actions(g, seat) ++
          Fortune.legal_actions(g, seat) ++ Witches.legal_actions(g, seat)
    end
  end

  def legal_actions(%__MODULE__{phase: :fortune_choice, turn: seat} = g, seat),
    do: Fortune.legal_actions(g, seat)

  def legal_actions(%__MODULE__{phase: :chip_choice} = g, seat),
    do: Evaluation.legal_actions(g, seat)

  def legal_actions(%__MODULE__{phase: :witch_choice, turn: seat} = g, seat),
    do: Witches.legal_actions(g, seat) ++ [:witch_done]

  def legal_actions(%__MODULE__{phase: :buy_chips, turn: seat} = g, seat),
    do: Enum.map(buys(g, player(g, seat).coins), &{:buy, &1}) ++ Witches.legal_actions(g, seat)

  def legal_actions(%__MODULE__{phase: :spend_rubies, turn: seat} = g, seat) do
    %{rubies: rubies, flask: flask, ruby_price: price} = player(g, seat)

    List.flatten([
      if(rubies >= price, do: {:rubies, :droplet}, else: []),
      if(rubies >= price and not flask, do: {:rubies, :flask}, else: []),
      Witches.legal_actions(g, seat),
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
        {:witch, _} -> Witches.step(g, seat, action)
        {:witch, _, _} -> Witches.step(g, seat, action)
        _ -> Potions.step(g, seat, action)
      end

    if Enum.all?(g.players, fn {_seat, p} -> p.done? end), do: Fortune.after_potions(g), else: g
  end

  # -- Fortune Teller choices: one seat at a time -------------------------------------

  defp step(%{phase: :fortune_choice} = g, seat, action), do: Fortune.step(g, seat, action)

  # -- step B chip choices (G2, G4, P2, P4): one seat at a time ---------------------

  defp step(%{phase: :chip_choice} = g, seat, action), do: Evaluation.step(g, seat, action)

  # -- witches outside the potions phase (gold choice, shop, rubies) ----------------

  defp step(g, seat, {:witch, _} = action), do: Witches.step(g, seat, action)
  defp step(g, seat, {:witch, _, _} = action), do: Witches.step(g, seat, action)

  defp step(%{phase: :witch_choice} = g, seat, :witch_done),
    do: Witches.step(g, seat, :witch_done)

  # -- shop and rubies: one seat at a time, in turn order ---------------------------

  defp step(%{phase: :buy_chips} = g, seat, {:buy, chips}),
    do: g |> buy(seat, chips) |> to_shop(seats_after(g, seat))

  defp step(%{phase: :spend_rubies} = g, seat, {:rubies, what}) do
    price = player(g, seat).ruby_price

    g =
      update_player(g, seat, fn p ->
        case what do
          :droplet -> %{p | rubies: p.rubies - price, droplet: p.droplet + 1}
          :flask -> %{p | rubies: p.rubies - price, flask: true}
        end
      end)

    # G4 makes it 1 ruby; the base event stays `{:rubies_spent, what}`.
    if price == 2,
      do: record(g, seat, {:rubies_spent, what}),
      else: record(g, seat, {:rubies_spent, what, price})
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
        if round == 6 and g.rules.round6_white,
          do: add_from_supply(g, seat, {:white, 1}),
          else: g
      end)

    start_round(%{g | round: round, phase: :potions, turn: nil})
  end

  # Rulebook §3 steps 1–2: the Fortune Teller card, the rats, then the purple card.
  defp start_round(g), do: g |> Fortune.draw() |> place_rats() |> Fortune.resolve()

  defp final_conversion(g, seat) do
    %{coins: coins, rubies: rubies, pennies: pennies} = player(g, seat)
    {coins_vp, rubies_vp} = {div(coins, 5), div(rubies, 2)}

    g =
      g
      |> update_player(
        seat,
        &%{&1 | vp: &1.vp + coins_vp + rubies_vp, coins: rem(coins, 5), rubies: rem(rubies, 2)}
      )
      |> record(seat, {:final_conversion, coins_vp, rubies_vp})

    # The Herb Witches: every unused witch penny is 2 VP.
    case 2 * Enum.count(pennies, fn {_colour, unused?} -> unused? end) do
      0 -> g
      vp -> g |> update_player(seat, &%{&1 | vp: &1.vp + vp}) |> record(seat, {:pennies, vp})
    end
  end

  # Rulebook §3 step 2 (round 2+, 2+ players): everyone behind the leader counts the
  # rat tails up to the leader and starts that many spaces past their droplet.
  defp place_rats(%{seats: [_]} = g), do: g
  defp place_rats(%{rules: %{rats: false}} = g), do: g

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

  @doc false
  # Every purchase `coins` pay for: nothing, one chip, or two chips of different
  # colours (the shop, and purple Set 5's step-B purchase).
  def buys(g, coins) do
    price = &Chips.price(&1, g.sets)

    singles =
      Enum.filter(Chips.shop(g.expansion, g.sets), &(price.(&1) <= coins and available?(g, &1)))

    pairs =
      for {ca, _} = a <- singles,
          {cb, _} = b <- singles,
          a < b and ca != cb and price.(a) + price.(b) <= coins,
          do: [a, b]

    [[] | Enum.map(singles, &[&1])] ++ pairs
  end

  # -- shared helpers for Potions and Evaluation --------------------------------------

  @doc false
  # Pay for `chips` and put them, plus the `free` ones (the copper witch C3), in the
  # bag. Black Set 5: a black chip goes to the player on the left (`give_black/2`).
  def buy(g, seat, chips, free \\ []) do
    cost = chips |> Enum.map(&Chips.price(&1, g.sets)) |> Enum.sum()
    all = chips ++ free
    g = Enum.reduce(all, g, &take_supply(&2, &1))
    {black, mine} = Enum.split_with(all, &(&1 == {:black, 1} and g.sets[:black] == 5))
    g = update_player(g, seat, &%{&1 | coins: &1.coins - cost, bag: mine ++ &1.bag})
    g = if chips == [], do: g, else: record(g, seat, {:bought, chips})

    Enum.reduce(black, g, fn _, g ->
      g |> give_black(seat) |> update_player(seat, &%{&1 | droplet: &1.droplet + 1})
    end)
  end

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
  # The seat to the left of `seat` (the next seat in turn order); `nil` solo.
  # ⚠️ "Left" read as the next seat clockwise, the direction of play.
  def left(%__MODULE__{seats: [_]}, _seat), do: nil
  def left(%__MODULE__{seats: seats}, seat), do: rem(seat + 1, length(seats))

  @doc false
  # Black Set 5: a black chip out of the supply goes into the left player's bag
  # (solo: back to the supply). The caller moves the receiver's droplet.
  def give_black(%__MODULE__{} = g, seat) do
    case left(g, seat) do
      nil ->
        g
        |> Map.update!(:supply, &Map.update!(&1, {:black, 1}, fn n -> n + 1 end))
        |> effect(seat, {:black, 5}, :to_supply)

      left ->
        g
        |> update_player(left, &%{&1 | bag: [{:black, 1} | &1.bag]})
        |> effect(seat, {:black, 5}, {:to_left, left})
    end
  end

  @doc false
  # Log a Set 2–6 chip effect: `{seat, {:effect, {colour, set}, detail}}`.
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
  # the VP skips it, unless a copper witch still helps them: `Witches.shop_turn?/2`);
  # with nobody left, or in round 9, go to the rubies phase.
  # ponytail: round 9 skips the shop; chips bought now are useless (§7). Coins stay on
  # the player and convert to VP in `:end_round`.
  @doc false
  def to_shop(%__MODULE__{round: @rounds} = g, _seats),
    do: %{g | phase: :spend_rubies, turn: start_seat(g)}

  def to_shop(%__MODULE__{} = g, seats) do
    case Enum.find(seats, &(player(g, &1).explosion_choice != :vp or Witches.shop_turn?(g, &1))) do
      nil -> %{g | phase: :spend_rubies, turn: start_seat(g)}
      seat -> %{g | phase: :buy_chips, turn: seat}
    end
  end
end
