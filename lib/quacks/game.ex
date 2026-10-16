defmodule Quacks.Game do
  @moduledoc """
  Pure Quacks engine for 1 to 8 players: one struct, one reducer.

  A 9-round game (see `docs/research/rulebook.md` §2, §3, §3.2, §4, §7) with the pot
  track, bags, draw/stop, explosion, flask, rats, bonus die, rubies, the Ingredient
  Set 1 chip effects, a shared chip supply, buying chips and end-game scoring.

  Each seat (`0..7`, turn order) has a `Quacks.Player`. Game phases: `:potions`, where
  every player not yet `:done` acts in any order (each has their own potions-phase
  `phase`; `:stop` only marks a player `:stopped`, and they may `:resume` while
  someone else still brews), then — as soon as nobody brews any more — the evaluation
  runs inside `apply/3` and the game moves to `:shopping`, where every seat acts at
  the same time in its own sub-phase (`:upgrade` → `:shop` → `:ready`; `:upgrade`
  only when the copper witch C1 can help the seat). Ingredient books with a
  choice in the evaluation (G2, G4, P2, P4) put the game in `:chip_choice` first,
  where every seat with a choice answers at the same time (`Quacks.Game.Evaluation`).
  Round 9 is "Stir!" (2+ players): every brewing seat picks `:draw` or `:stop` for
  the step, and the step resolves once all have picked (see `legal_actions/2`).
  After round 9 the phase is `:over`. The struct never rests without a legal action
  for some seat unless `over?/1`.

  House rules (`rules`, see `new/1`) change a few table rules: the explosion limit,
  the round-6 white chip, the cards, the rats, solo black, the die and the starting
  rubies. The defaults are the rulebook game.

  The Herb Witches (`expansion: :herb_witches`, `docs/research/herb-witches.md`) adds
  its chips to the supply, the overflow bowl (`Quacks.Player.bowl`) and the herb witches
  (`Quacks.Game.Witches`): one witch of each penny colour is turned up at `new/1`
  (`witches`), and every player may call each of them once per game with
  `{:witch, colour}` or `{:witch, colour, choice}`. Gold witches with a choice in the
  evaluation put the game in `:witch_choice` (every helped seat at once).

  Reverse pot side (`rules: %{pot_side: :back}`, `docs/research/pot-reverse-and-faq.md`
  §1): every droplet move goes through one engine helper and waits for the player's
  choice: `{:droplet, :pot}` (the pot droplet) or `{:droplet, :tube}` (one glass on the
  test-tube track, its bonus at once, `Quacks.Rules.TestTubes`), one action per move.
  While a seat has moves waiting, those two are its only actions (`phase/2` is
  `:droplet_choice`), in any game phase but the evaluation's choices (`:chip_choice`,
  `:witch_choice`): there the moves wait for the shop, so the evaluation ends and is
  logged first (round 18). The shop adds `{:rubies, :tube}`.

  The Alchemists (`expansions: [:alchemists]`, `docs/research/alchemists-essences.md`,
  `Quacks.Game.Essence`): 3 patients are dealt at `new/1` (`patients`) and every seat
  picks one in `:patient_choice` before round 1. Each round, after the potions phase
  (and B2), the `:essence` phase moves every essence marker and pays its glass before
  the evaluation; patient actions follow in the next potions phase. `expansions` is a
  `MapSet`; `expansion` is the old single field (`:herb_witches` or `nil`), kept for
  callers that only know The Herb Witches. Use `expansion?/2`.

  Fortune Teller cards (`Quacks.Game.Fortune`): each round starts by turning up a
  card. A purple card with a choice puts the game in `:fortune_choice` (every seat
  with a choice at once) before `:potions`; Toil and Trouble (B2) does the same
  between `:potions` and the evaluation.

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
  alias Quacks.Game.{Essence, Evaluation, Fortune, Potions, Round, State, Witches}

  import State,
    only: [
      add_from_supply: 3,
      buy: 4,
      buys: 2,
      done_buying: 2,
      pot_droplet: 2,
      record: 2,
      record: 3,
      update_player: 3
    ]

  alias Quacks.Player
  alias Quacks.Rules.{Alchemists, Chips, TestTubes}
  alias Quacks.Rules.Witches, as: WitchCards
  alias Table.Kit.Rng

  @rounds 9

  # Reverse pot side (round 18): in the gold witches' phase a seat's droplet moves
  # wait; they come in the shop. Round 35: in the chip actions' choices they come
  # first (rulebook §3.2 B: black, then green and purple; the die before them all).
  @droplets_wait [:witch_choice]
  # Ingredient Sets (research `ingredient-sets-and-customisation.md`): Set 1 by default.
  # Black has a book too (1 = the base book, 5, 6), in every game.
  @sets %{green: 1, blue: 1, red: 1, yellow: 1, purple: 1, black: 1}
  # ⚠️ Locoweed enters the shop in round 1 (not in the rulebook; `herb-witches.md` §1.2).
  # House rules (research `ingredient-sets-and-customisation.md` Part 2b): the rulebook game.
  # The values each house rule accepts.
  @rule_values %{
    explode_above: 5..9,
    round6_white: [true, false],
    fortune: [true, false],
    alch_cards: [true, false],
    rats: [true, false],
    black_solo: [:droplet, :droplet_ruby],
    black_rule: [:neighbours, :standings],
    die: [:standard, :no_orange],
    starting_rubies: 0..3,
    supply: [:infinite, :limited],
    overflow: [true, false],
    pot_side: [:front, :back]
  }
  @rules %{
    explode_above: 7,
    round6_white: true,
    fortune: true,
    alch_cards: true,
    rats: true,
    black_solo: :droplet,
    black_rule: :neighbours,
    die: :standard,
    starting_rubies: 1,
    supply: :infinite,
    overflow: true,
    pot_side: :front
  }

  defstruct round: 1,
            phase: :potions,
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
            expansions: MapSet.new(),
            witches: nil,
            visitor: nil,
            visited: [],
            patients: nil

  @type seat :: 0..7
  @type phase ::
          :patient_choice
          | :potions
          | :essence
          | :fortune_choice
          | :chip_choice
          | :witch_choice
          | :shopping
          | :over
  @type action ::
          :draw
          | :stop
          | :resume
          | :use_flask
          | :return_white
          | :keep
          | {:place, Chips.chip()}
          | :return_all
          | :bundle
          | :rats
          | :rolls
          | {:cherish, 1..3}
          | {:penny, WitchCards.colour()}
          | {:swap, Chips.chip()}
          | {:gift, :white | :chip}
          | :keep
          | :return_white3
          | {:explosion_choice, :vp | :buy}
          | {:buy, [Chips.chip()]}
          | {:rubies, :droplet | :tube | :flask | :vp | :skip}
          | {:droplet, :pot | :tube}
          | :end_round
          | :skip_upgrade
          | {:fortune, fortune_choice}
          | {:red, {:place | :keep | :return, Chips.chip()}}
          | {:chip, chip_choice}
          | :chip_done
          | {:witch, WitchCards.colour() | :visit}
          | {:witch, WitchCards.colour() | :visit, term}
          | :witch_done
          | {:patient, Alchemists.id()}
          | {:essence, essence_choice}
  @typedoc """
  An essence action (The Alchemists, `Quacks.Game.Essence`): `{:space, n}` in
  `:essence_choice`; `{:swap, chip}`, `{:buy, chip}` in `:essence_bonus`; `{:place,
  chip}` (Nervousness) and `{:forget, chip}` (Forgetfulness) while brewing; `:carrot`,
  `:double`, `:return`, `:hump` in `:essence_offer`; `:pass` declines a bonus or offer.
  """
  @type essence_choice ::
          {:space, 0..10}
          | {:swap, Chips.chip()}
          | {:buy, Chips.chip()}
          | {:place, Chips.chip()}
          | {:forget, Chips.chip()}
          | :carrot
          | :double
          | :return
          | :hump
          | :pass
  @typedoc """
  A chip choice: step B (G2, G4, P2, P4, G5, P5; see `Quacks.Game.Evaluation`) or on
  draw (Y6 `:yellow_ruby`, locoweed 5 `{:return, chip}`, see `Quacks.Game.Potions`).
  """
  @type chip_choice ::
          {:gain, Chips.chip()}
          | {:pay_ruby_move, 1..2}
          | {:purple_trade, 1..3}
          | {:upgrade, Chips.chip(), Chips.chip()}
          | {:starter, Chips.chip()}
          | {:buy, [Chips.chip()]}
          | :yellow_ruby
          | {:return, Chips.chip()}
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
  `{:rubies_spent, :droplet | :tube | :flask}`. Reverse pot side: `{:tube, glass, bonus}`
  when the test-tube droplet moves to `glass` and pays `bonus`.

  Evaluation is narrated too: `{:bonus_die, face}`, the chip actions (`{:black,
  :droplet | :droplet_ruby}`, `{:green_rubies, n}`, `{:purple, tier, payoff}`), the
  scoring space (`{:pot_ruby, index}`, `{:pot_vp, vp, index}`), `{:final_conversion,
  coins, coins_vp, rubies, rubies_vp}` in round 9 and `{:rats, tails}` when a player
  gets a head start. See the Log table in `docs/CONTEXT.md`.

  The Herb Witches: `{:overflow, chip}` for a chip that goes in the overflow bowl,
  `{:bowl, chips, vp}` for the bowl's VP in step D, `{:witch, id, outcome}` for what a
  witch did, `{:rubies_spent, what, 1}` for a 1-ruby spend (G4) and `{:pennies, vp}`
  for the unused witch pennies at the end.

  The Alchemists: `{:essence, space, parts}` (the reached space and its
  `%{colours:, locoweed:, white7:, neighbours:}`), `{:essence_bonus, term}` for each
  paid glass (`Quacks.Rules.Alchemists`; also a Witch's hump bonus),
  `{:essence_spent, n, what}`, `{:essence_vp, n}` in round 9, `{:essence_rat, 1}`
  for a rat-tail glass at the start of the next round and `{:display, chips}` for the
  Nervousness draw (whites included; they went back).
  """
  @type event ::
          action
          | {:drew, Chips.chip(), 0..53}
          | {:overflow, Chips.chip()}
          | {:bowl, [Chips.chip()], non_neg_integer}
          | {:returned, Chips.chip()}
          | {:exploded, non_neg_integer}
          | :stopped
          | :resumed
          | {:bought, [Chips.chip()]}
          | {:rubies_spent, :droplet | :tube | :flask | :vp}
          | {:rubies_spent, :droplet | :tube | :flask, 1}
          | {:tube, 1..12, TestTubes.bonus()}
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
          | {:final_conversion, non_neg_integer, non_neg_integer, non_neg_integer,
             non_neg_integer}
          | {:rats, pos_integer}
          | {:fortune, Quacks.Rules.Fortune.id(), term}
          | {:effect, {Chips.colour(), 2..6}, term}
          | {:essence, 0..10, map}
          | {:essence_bonus, Alchemists.term_()}
          | {:essence_spent, pos_integer, term}
          | {:essence_vp, non_neg_integer}
          | {:essence_rat, 1}
          | {:display, [Chips.chip()]}
  @typedoc """
  What happened, newest first. Player events are tagged with their seat; the only
  game-wide entries are `{:expansion, x}` (the first entries of an expansion game, The
  Herb Witches first), `{:patients, ids}` (The Alchemists' deal), `{:fortune_drawn, id}` and `{:fortune_skipped, id}` at the start of a round,
  `{:visitor, id}` (AB8 Visit from a witch: the witch that visits this round) and
  `{:visitor_left, id}` (she leaves at the end of the round), and
  `{:round_end, round}`, the last event of every round.
  `Quacks.Session` replays from its own action list, not this.
  """
  @type log_entry ::
          {seat, event}
          | {:round_end, 1..9}
          | {:expansion, :herb_witches | :alchemists}
          | {:patients, [Alchemists.id()]}
          | {:fortune_drawn, Quacks.Rules.Fortune.id()}
          | {:fortune_skipped, Quacks.Rules.Fortune.id()}
          | {:visitor, WitchCards.id()}
          | {:visitor_left, WitchCards.id()}
  @type t :: %__MODULE__{
          round: 1..9,
          phase: phase,
          supply: %{Chips.chip() => non_neg_integer},
          rng: :rand.state(),
          log: [log_entry],
          players: %{seat => Player.t()},
          seats: [seat],
          fortune_deck: [Quacks.Rules.Fortune.id()],
          fortune_card: Quacks.Rules.Fortune.id() | nil,
          sets: Chips.sets(),
          rules: rules,
          expansion: nil | :herb_witches,
          expansions: MapSet.t(expansion),
          witches: nil | %{WitchCards.colour() => WitchCards.id()},
          visitor: nil | WitchCards.id(),
          visited: [seat],
          patients: nil | [Alchemists.id()]
        }
  @type expansion :: :herb_witches | :alchemists
  @typedoc """
  House rules; the defaults (`default_rules/0`) are the rulebook game.
  `explode_above` is the white limit before chips and cards raise it, `black_solo`
  the solo black payout (rulebook §6.2 suggests `:droplet_ruby`), `black_rule`
  whom black book I compares with (`:neighbours`, the rulebook and the default
  again since round 27; `:standings`, ⚠️ unofficial: the players ranked above; see
  `Quacks.Game.Evaluation.targets/2`), `die: :no_orange`
  turns the orange face into a second ruby face (⚠️ unofficial). `supply: :infinite`
  (default) means the shop never runs out and `supply` is never counted down;
  `:limited` plays with the box's counts. `overflow: true` (default) puts chips past
  the last space in the overflow bowl; `false` keeps them on the last space.
  `pot_side: :back` plays the reverse side of the pot (the test-tube track).
  `alch_cards: true` (default) adds the Fortune Teller cards of The Alchemists box to
  the deck: its 14 general cards in every game, its expansion cards when their
  expansion is in play (see `Quacks.Rules.Fortune.ids/2`); `false` plays the 24 base
  cards only.
  """
  @type rules :: %{
          explode_above: 5..9,
          round6_white: boolean,
          fortune: boolean,
          alch_cards: boolean,
          rats: boolean,
          black_solo: :droplet | :droplet_ruby,
          black_rule: :neighbours | :standings,
          die: :standard | :no_orange,
          starting_rubies: 0..3,
          supply: :infinite | :limited,
          overflow: boolean,
          pot_side: :front | :back
        }

  @doc """
  A fresh game. `seed:` is a `{int, int, int}` tuple for `:rand.seed_s(:exsss, seed)`;
  `players:` is 1 (default) to 8. Every starting bag comes out of the shared supply
  (a limited supply stops at 0: with 5+ players the white 2s and 3s run dry).
  `sets:` picks the Ingredient Set (1..6) per colour, e.g. `%{blue: 3}`; colours left
  out use Set 1. `black:` is 1 (the base book), 2 or 3 (The Herb Witches' books),
  `orange: 2` adds the orange 6-chip and `locoweed: 1 | 2 | 4 | 5 | 6` adds locoweed
  (book III needs the essence phase), in every game (see `Quacks.Rules.Chips.set/3`). `rules:` sets house rules (`t:rules/0`), e.g.
  `%{explode_above: 9}`; rules left out keep their default. With `fortune: true`
  (default) round 1's card is turned up here. `fortune: false` is an old alias for
  `rules: %{fortune: false}`. `expansions:` is a list (or `MapSet`) of
  `:herb_witches` and `:alchemists`; `expansion: :herb_witches` is the old alias (both
  may be given). The Herb Witches: the expansion chips in the supply (the books stay
  as `sets:` says), 3 witches (`witches`, dealt from the seed; `witches:` picks one per colour,
  e.g. `%{copper: :c3, silver: nil}`, nil or left out: dealt) and 3 witch pennies per
  player. The Alchemists: locoweed book III may be picked, 3 patients are dealt
  (`patients`) and the game starts in `:patient_choice` (round 1's card comes after).
  `patients:` picks patients before the game, e.g. `%{0 => :nervousness, 1 => :random}`
  (`Quacks.Game.Essence.prepick/2`; only with The Alchemists, else ignored).
  An unknown colour, set, rule or expansion raises `ArgumentError`.
  """
  @spec new(
          seed: {integer, integer, integer},
          players: 1..8,
          sets: %{atom => 1..6 | nil},
          rules: map,
          fortune: boolean,
          expansion: nil | :herb_witches,
          expansions: Enumerable.t(expansion),
          witches: %{optional(WitchCards.colour()) => WitchCards.id() | nil} | nil,
          patients: %{optional(seat) => Alchemists.id() | :random} | nil
        ) :: t
  def new(opts) do
    seed = Keyword.fetch!(opts, :seed)
    expansions = expansions!(opts)
    herb? = MapSet.member?(expansions, :herb_witches)

    n = Keyword.get(opts, :players, 1)
    if n not in 1..8, do: raise(ArgumentError, "players must be 1..8, got #{inspect(n)}")
    sets = sets!(Keyword.get(opts, :sets, %{}), expansions)
    # `fortune:` is the old top-level option; `rules:` wins when both are given.
    alias_rules = Map.new(Keyword.take(opts, [:fortune]))
    rules = rules!(Map.merge(alias_rules, Keyword.get(opts, :rules, %{})))

    seats = Enum.to_list(0..(n - 1))
    bag = Chips.starting_bag()
    starting = List.flatten(List.duplicate(bag, n))

    # An infinite supply is the box itself, never counted down.
    box = Chips.supply(expansions, sets)

    supply =
      if rules.supply == :limited,
        do: Enum.reduce(starting, box, &Map.update!(&2, &1, fn c -> max(c - 1, 0) end)),
        else: box

    rng = Rng.seed(seed)

    deck =
      if rules.fortune, do: Fortune.deck(rng, n, expansions, rules.alch_cards), else: []

    player = %{Player.new(bag) | rubies: rules.starting_rubies}

    player =
      if herb?,
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
      expansion: if(herb?, do: :herb_witches),
      expansions: expansions,
      witches: if(herb?, do: rng |> WitchCards.deal() |> pick_witches(opts[:witches]))
    }

    game =
      Enum.reduce([:herb_witches, :alchemists], game, fn x, g ->
        if MapSet.member?(expansions, x), do: record(g, {:expansion, x}), else: g
      end)

    if MapSet.member?(expansions, :alchemists),
      do: game |> Essence.setup() |> Essence.prepick(opts[:patients]),
      else: Round.start_round(game)
  end

  # The host's picks replace the dealt witch of their colour (nil: dealt). The deal
  # itself runs first either way, so the game's random stream does not change.
  defp pick_witches(dealt, nil), do: dealt

  defp pick_witches(dealt, picks) when is_map(picks) do
    Enum.reduce(picks, dealt, fn
      {_colour, nil}, witches ->
        witches

      {colour, id}, witches when is_map_key(witches, colour) ->
        if id in WitchCards.ids(colour),
          do: Map.put(witches, colour, id),
          else: raise(ArgumentError, "no #{colour} witch #{inspect(id)}")

      {colour, _id}, _witches ->
        raise ArgumentError, "unknown witch colour #{inspect(colour)}"
    end)
  end

  defp pick_witches(_dealt, picks),
    do: raise(ArgumentError, "witches must be a map, got #{inspect(picks)}")

  defp expansions!(opts) do
    list =
      List.wrap(Keyword.get(opts, :expansion)) ++ Enum.to_list(Keyword.get(opts, :expansions, []))

    case Enum.reject(list, &(&1 in [:herb_witches, :alchemists])) do
      [] -> MapSet.new(list)
      bad -> raise ArgumentError, "unknown expansion #{inspect(hd(bad))}"
    end
  end

  @doc "Is expansion `x` (`:herb_witches`, `:alchemists`) in play?"
  @spec expansion?(t, expansion) :: boolean
  def expansion?(%__MODULE__{expansions: expansions}, x), do: MapSet.member?(expansions, x)

  # Every game: Sets 1..6, black 1, 2 or 3, orange 1 or 2 (2 = the orange 6-chip) and
  # locoweed nil, 1, 2, 4, 5 or 6; III only with The Alchemists (the essence phase).
  defp sets!(sets, expansions) do
    sets = Map.merge(@sets, sets)
    locoweed = if MapSet.member?(expansions, :alchemists), do: [3], else: []

    valid? =
      Enum.all?(sets, fn
        {:orange, set} -> set in [1, 2]
        {:locoweed, set} -> set in [nil, 1, 2, 4, 5, 6 | locoweed]
        {:black, set} -> set in [1, 2, 3]
        {colour, set} -> is_map_key(@sets, colour) and set in 1..6
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
      map_size(rules) == map_size(@rules) and
        Enum.all?(rules, fn {key, value} -> value in @rule_values[key] end)

    if not valid?, do: raise(ArgumentError, "bad rules: #{inspect(rules)}")
    rules
  end

  @doc "True after round 9's evaluation."
  @spec over?(t) :: boolean
  def over?(%__MODULE__{phase: phase}), do: phase == :over

  @doc "Victory points so far, per seat."
  @spec score(t) :: %{seat => non_neg_integer}
  def score(%__MODULE__{players: players}), do: Map.new(players, fn {seat, p} -> {seat, p.vp} end)

  @doc """
  The phase `seat` sees: `:droplet_choice` while droplet moves wait for its choice,
  else their own state in `:potions`, `:essence` and `:shopping` (`:upgrade`, `:shop`,
  `:ready`),
  or the game's phase.
  """
  @spec phase(t, seat) :: phase | Player.phase() | :droplet_choice
  def phase(%__MODULE__{phase: phase, players: players}, seat)
      when phase != :over and is_map_key(players, seat) do
    case players[seat] do
      %Player{droplet_moves: n} when n > 0 and phase not in @droplets_wait -> :droplet_choice
      p when phase in [:potions, :essence, :shopping] -> p.phase
      _p -> phase
    end
  end

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
  defdelegate start_seat(game), to: State

  # -- reads for the board and the bots (issue #79) -----------------------------------
  #
  # Callers outside the engine read the game through these functions and the struct's
  # fields. They do not call `Quacks.Game.State` or an engine submodule
  # (`test/quacks/game_facade_test.exs`).

  @doc "`seat`'s `Quacks.Player`."
  @spec player(t, seat) :: Player.t()
  defdelegate player(game, seat), to: State

  @doc "The seats from this round's start seat round the table."
  @spec turn_order(t) :: [seat]
  defdelegate turn_order(game), to: State

  @doc """
  The highest white sum that does not explode: the house rule's limit (default 7),
  or more with B5 or the Y3 mandrake. The highest of the three wins. Takes a seat, or
  a `Quacks.Player` that the page shows for this game.
  """
  @spec white_limit(t, seat | Player.t()) :: 5..9
  def white_limit(%__MODULE__{} = g, %Player{} = p),
    do: Enum.max([g.rules.explode_above, p.mods.explode_above, Fortune.explode_above(g)])

  def white_limit(%__MODULE__{} = g, seat), do: Potions.explode_above(g, seat)

  @doc "Second Chances (B3): `seat`'s next draw cannot explode the pot."
  @spec safe_draw?(t, seat) :: boolean
  def safe_draw?(%__MODULE__{} = g, seat), do: Fortune.safe_draw?(g, player(g, seat))

  @doc """
  What the round's Fortune Teller card gave each seat: the chips it drew, or the
  choice it took. See `Quacks.Game.Fortune.reveals/1` for the row shape; an empty
  map under any other card.
  """
  @spec card_reveals(t) :: %{seat => map}
  defdelegate card_reveals(game), to: Fortune, as: :reveals

  @doc """
  Why Flea Market (P13) cannot trade `chip` up now, or nil when it can: `:white`,
  `:top` (no higher value) or `:none_left` (none in the supply, or its book is not
  out yet).
  """
  @spec flea_block(t, Chips.chip()) :: nil | :white | :top | :none_left
  defdelegate flea_block(game, chip), to: Fortune

  @doc "Whether the shop sells `chip` this round: its book is out and the supply has one."
  @spec available?(t, Chips.chip()) :: boolean
  def available?(%__MODULE__{} = g, chip), do: State.available?(g, chip)

  @doc "Whether the supply has `chip` (an infinite supply has every chip of the box)."
  @spec in_supply?(t, Chips.chip()) :: boolean
  def in_supply?(%__MODULE__{} = g, chip), do: State.in_supply?(g, chip)

  @doc """
  The seats whose black chips black book I compares with `seat`'s: both neighbours,
  or the seats ranked above (`black_rule: :standings`). Empty solo.
  """
  @spec black_targets(t, seat) :: [seat]
  defdelegate black_targets(game, seat), to: Evaluation, as: :targets

  @doc """
  The seats from the leader down: most VP first; a tie goes to fewer rubies, then
  to the lower seat number.
  """
  @spec standings(t) :: [seat]
  defdelegate standings(game), to: Evaluation

  @doc """
  The Alchemists: the space `seat`'s essence marker reaches this round (at most 10)
  and its parts: the colours in the pot, locoweed (book III), white 7, exploded
  neighbours and the card.
  """
  @spec essence_reach(t, seat) ::
          {0..10,
           %{
             colours: non_neg_integer,
             locoweed: non_neg_integer,
             white7: 0 | 1,
             neighbours: 0..2,
             card: non_neg_integer
           }}
  defdelegate essence_reach(game, seat), to: Essence, as: :count

  @doc "The Alchemists: the 3 patients that seed `seed` deals at `new/1`."
  @spec dealt_patients({integer, integer, integer}) :: [Alchemists.id()]
  defdelegate dealt_patients(seed), to: Essence, as: :dealt

  @doc """
  Every action `apply/3` accepts for `seat` right now. During `:potions` every seat
  not yet done has actions (a `:stopped` seat only `:resume`, and only while another
  seat still brews); during `:shopping` every seat not yet `:ready`; in the choice
  phases every seat that still answers. Empty for every seat only when `over?/1`.

  Round 9 "Stir!" (2+ players): a brewing seat picks `:draw` or `:stop` for the step
  and waits (`:waiting_stir`, no actions) until every brewing seat has picked; then
  the step resolves in seat order from the start seat. A stop is final (no
  `:resume`).
  """
  @spec legal_actions(t, seat) :: [action]
  def legal_actions(game, seat \\ 0)

  def legal_actions(%__MODULE__{players: players}, seat) when not is_map_key(players, seat),
    do: []

  # Reverse pot side: a waiting droplet move comes first, in any phase but the gold
  # witches' (`@droplets_wait`).
  def legal_actions(%__MODULE__{phase: phase, players: players} = g, seat) when phase != :over do
    case players[seat] do
      %Player{droplet_moves: n} when n > 0 and phase not in @droplets_wait ->
        [{:droplet, :pot}, {:droplet, :tube}]

      _p ->
        phase_actions(g, seat)
    end
  end

  def legal_actions(%__MODULE__{}, _seat), do: []

  # While the silver witch S2's offer is out, placing from it is all the seat may do.
  # A patient offer (The Alchemists) waits for its answer first.
  defp phase_actions(%__MODULE__{phase: :potions} = g, seat) do
    case player(g, seat) do
      %Player{phase: :essence_offer} ->
        Essence.legal_actions(g, seat)

      %Player{phase: :potions, witch_offer: [_ | _]} ->
        Witches.legal_actions(g, seat)

      %Player{phase: :waiting_stir} ->
        []

      %Player{phase: :stopped} ->
        if not stir?(g) and Enum.any?(g.seats, &(&1 != seat and brewing?(player(g, &1)))),
          do: [:resume],
          else: []

      _ ->
        Potions.legal_actions(g, seat) ++
          Fortune.legal_actions(g, seat) ++
          Witches.legal_actions(g, seat) ++ Essence.legal_actions(g, seat)
    end
  end

  defp phase_actions(%__MODULE__{phase: phase} = g, seat)
       when phase in [:patient_choice, :essence],
       do: Essence.legal_actions(g, seat)

  defp phase_actions(%__MODULE__{phase: :fortune_choice} = g, seat),
    do: Fortune.legal_actions(g, seat)

  defp phase_actions(%__MODULE__{phase: :chip_choice} = g, seat),
    do: Evaluation.legal_actions(g, seat)

  defp phase_actions(%__MODULE__{phase: :witch_choice} = g, seat) do
    if player(g, seat).phase == :witch_choice,
      do: Witches.legal_actions(g, seat) ++ [:witch_done],
      else: []
  end

  # Two steps: first the buy (once, not in round 9), then the rubies and "Done"
  # (`{:buy, []}` buys nothing). A seat whose coins buy nothing starts at the rubies
  # ("buy nothing" stays legal). Witches in both. Round 35: the ruby uses are legal
  # in the buy step too (rulebook F after E, but coins and rubies do not pay for each
  # other's step): the page asks for them before the round's last results step.
  # Round 45: before them the copper witch C1's own step (`:upgrade`): upgrade or
  # `:skip_upgrade`; the ruby uses (and G4) are legal there too, for the same reason.
  defp phase_actions(%__MODULE__{phase: :shopping} = g, seat) do
    case player(g, seat) do
      %Player{phase: :upgrade} = p ->
        Witches.legal_actions(g, seat) ++ ruby_actions(g, p) ++ [:skip_upgrade]

      %Player{phase: :shop} = p ->
        may_buy? = may_buy?(g, p)
        buys = if may_buy?, do: buys(g, p.coins), else: []

        if buys in [[], [[]]],
          do:
            Enum.map(buys, &{:buy, &1}) ++
              ruby_actions(g, p) ++ Witches.legal_actions(g, seat) ++ [:end_round],
          else:
            Enum.map(buys, &{:buy, &1}) ++ ruby_actions(g, p) ++ Witches.legal_actions(g, seat)

      %Player{phase: :ready} ->
        []
    end
  end

  # Round 9: 2 rubies buy 1 VP; droplet and flask are worth nothing any more.
  # Round 37: on the reverse pot side a test-tube glass too (its bonus can be VP).
  defp ruby_actions(%{round: @rounds} = g, %Player{rubies: rubies, ruby_price: price} = p) do
    if(rubies >= 2, do: [{:rubies, :vp}], else: []) ++
      if(tube?(g, p) and rubies >= price, do: [{:rubies, :tube}], else: [])
  end

  defp ruby_actions(g, %Player{rubies: rubies, flask: flask, ruby_price: price} = p) do
    tube? = tube?(g, p)

    if rubies >= price,
      do:
        [{:rubies, :droplet}] ++
          if(tube?, do: [{:rubies, :tube}], else: []) ++
          if(flask, do: [], else: [{:rubies, :flask}]),
      else: []
  end

  # The test-tube droplet can still move (reverse pot side, not on the last glass).
  defp tube?(g, p), do: g.rules.pot_side == :back and p.tube < TestTubes.last()

  # An exploded player who took the VP buys nothing (unless C4 gave them coins).
  defp may_buy?(g, p), do: State.shop_open?(g, p) and (p.explosion_choice != :vp or p.coins > 0)

  @doc "`apply/3` for seat 0."
  @spec apply(t, action) :: {:ok, t} | {:error, {:illegal_action, action, phase | Player.phase()}}
  def apply(%__MODULE__{} = game, action), do: apply(game, 0, action)

  @doc """
  Apply one action for `seat`. Illegal actions (wrong phase, nothing for this seat
  to answer, unaffordable buy, empty bag, ...) return `{:error, {:illegal_action, action, phase}}`
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

  # -- reverse pot side: one waiting droplet move, in any phase ------------------------

  defp step(g, seat, {:droplet, :pot}),
    do: g |> update_player(seat, &pot_droplet(&1, 1)) |> droplet_moved(seat)

  defp step(g, seat, {:droplet, :tube}), do: g |> tube(seat) |> droplet_moved(seat)

  # -- potions: every seat in any order; evaluation when the last one is done -------

  defp step(%{phase: :potions} = g, seat, action) do
    g =
      case action do
        {:fortune, _} -> Fortune.step(g, seat, action)
        {:witch, _} -> Witches.step(g, seat, action)
        {:witch, _, _} -> Witches.step(g, seat, action)
        {:essence, _} -> Essence.step(g, seat, action)
        choice when choice in [:draw, :stop] -> stir_or_step(g, seat, choice)
        _ -> Potions.step(g, seat, action)
      end

    g = g |> Essence.open_offers() |> stir() |> Essence.open_offers() |> settle_stops()
    if Enum.all?(g.players, fn {_seat, p} -> p.done? end), do: Fortune.after_potions(g), else: g
  end

  # -- concurrent choices: Fortune Teller, step B chips, gold witches -----------------

  defp step(%{phase: :fortune_choice} = g, seat, action), do: Fortune.step(g, seat, action)

  # -- The Alchemists: the patient choice and the essence phase -----------------------

  defp step(%{phase: phase} = g, seat, action) when phase in [:patient_choice, :essence],
    do: Essence.step(g, seat, action)

  defp step(%{phase: :chip_choice} = g, seat, action), do: Evaluation.step(g, seat, action)

  # -- witches outside the potions phase (gold choice, shopping) ----------------------

  defp step(g, seat, {:witch, _} = action), do: Witches.step(g, seat, action)
  defp step(g, seat, {:witch, _, _} = action), do: Witches.step(g, seat, action)

  defp step(%{phase: :witch_choice} = g, seat, :witch_done),
    do: Witches.step(g, seat, :witch_done)

  defp step(%{phase: :shopping} = g, seat, :skip_upgrade),
    do: Witches.step(g, seat, :skip_upgrade)

  # -- shopping: every seat at once, all in one step ----------------------------------

  defp step(%{phase: :shopping} = g, seat, {:buy, chips}) do
    free = Fortune.sale(g, chips)
    g = Enum.reduce(free, g, &record(&2, seat, {:fortune, :ab2, {:free, &1}}))
    g |> buy(seat, chips, free) |> done_buying(seat)
  end

  defp step(%{phase: :shopping} = g, seat, {:rubies, :vp}) do
    g
    |> update_player(seat, &%{&1 | rubies: &1.rubies - 2, vp: &1.vp + 1})
    |> record(seat, {:rubies_spent, :vp})
  end

  defp step(%{phase: :shopping} = g, seat, {:rubies, what}) do
    price = player(g, seat).ruby_price

    g =
      update_player(g, seat, fn p ->
        case what do
          :droplet -> pot_droplet(%{p | rubies: p.rubies - price}, 1)
          :tube -> %{p | rubies: p.rubies - price}
          :flask -> %{p | rubies: p.rubies - price, flask: true}
        end
      end)

    # G4 makes it 1 ruby; the base event stays `{:rubies_spent, what}`.
    g =
      if price == 2,
        do: record(g, seat, {:rubies_spent, what}),
        else: record(g, seat, {:rubies_spent, what, price})

    if what == :tube, do: tube(g, seat), else: g
  end

  # The last seat to get `:ready` ends the round. Round 9: the seat's coins and rubies
  # become VP now.
  defp step(%{phase: :shopping} = g, seat, :end_round) do
    g = if g.round == @rounds, do: final_conversion(g, seat), else: g
    g = update_player(g, seat, &%{&1 | phase: :ready})
    if Enum.all?(g.seats, &(player(g, &1).phase == :ready)), do: end_round(g), else: g
  end

  # Round 9 "Stir!" with 2+ players: the pick waits for the other brewing seats.
  defp stir_or_step(g, seat, choice) do
    if stir?(g),
      do: update_player(g, seat, &%{&1 | phase: :waiting_stir, pending_choice: choice}),
      else: Potions.step(g, seat, choice)
  end

  defp stir?(g), do: g.round == @rounds and length(g.seats) > 1

  # Once every seat still brewing has picked (nobody is in an on-draw choice), the
  # step resolves: the picks in seat order from the start seat, on the shared rng.
  defp stir(g) do
    phases = Enum.map(g.seats, &player(g, &1).phase)

    if :waiting_stir in phases and Enum.all?(phases, &(&1 in [:waiting_stir, :stopped, :done])) do
      g
      |> turn_order()
      |> Enum.filter(&(player(g, &1).phase == :waiting_stir))
      |> Enum.reduce(g, fn seat, g ->
        choice = player(g, seat).pending_choice

        g
        |> update_player(seat, &%{&1 | phase: :potions, pending_choice: nil})
        |> Potions.step(seat, choice)
      end)
    else
      g
    end
  end

  # Soft stop: once every player is `:stopped` or `:done`, nobody can resume any more,
  # so the stops become final (B1, B7 and red chips beside the pot act now), start
  # seat first.
  defp settle_stops(g) do
    phases = Enum.map(g.seats, &player(g, &1).phase)

    if :stopped in phases and Enum.all?(phases, &(&1 in [:stopped, :done])) do
      g
      |> turn_order()
      |> Enum.filter(&(player(g, &1).phase == :stopped))
      |> Enum.reduce(g, &Potions.stop(&2, &1))
    else
      g
    end
  end

  # Still drawing (or deciding about a chip just drawn): a stopped player may resume.
  defp brewing?(%Player{phase: phase}),
    do: phase in [:potions, :yellow_choice, :blue_choice, :chip_choice, :essence_offer]

  defp end_round(%{round: @rounds} = g),
    do: g |> Witches.leave() |> Map.put(:phase, :over) |> record({:round_end, @rounds})

  defp end_round(g) do
    round = g.round + 1
    g = g |> Witches.leave() |> record({:round_end, g.round})

    g =
      Enum.reduce(g.seats, g, fn seat, g ->
        g = update_player(g, seat, &Player.reset/1)
        # Rulebook §3 step 5: before turn 6 each player adds 1 white 1-chip.
        if round == 6 and g.rules.round6_white,
          do: add_from_supply(g, seat, {:white, 1}),
          else: g
      end)

    Round.start_round(%{g | round: round, phase: :potions})
  end

  # Rulebook §7: 5 coins or 2 rubies buy 1 VP, as often as you like. Whatever the seat
  # still has at its round-9 "Done" converts by itself.
  defp final_conversion(g, seat) do
    %{coins: coins, rubies: rubies, pennies: pennies} = player(g, seat)
    {coins_vp, rubies_vp} = {div(coins, 5), div(rubies, 2)}

    g =
      g
      |> update_player(
        seat,
        &%{&1 | vp: &1.vp + coins_vp + rubies_vp, coins: rem(coins, 5), rubies: rem(rubies, 2)}
      )
      |> record(seat, {:final_conversion, coins, coins_vp, rubies, rubies_vp})

    # The Herb Witches: every unused witch penny is 2 VP.
    case 2 * Enum.count(pennies, fn {_colour, unused?} -> unused? end) do
      0 -> g
      vp -> g |> update_player(seat, &%{&1 | vp: &1.vp + vp}) |> record(seat, {:pennies, vp})
    end
  end

  # One waiting move is done; on the last glass the rest go to the pot droplet.
  defp droplet_moved(g, seat) do
    update_player(g, seat, fn p ->
      left = p.droplet_moves - 1

      if p.tube == TestTubes.last(),
        do: pot_droplet(%{p | droplet_moves: 0}, left),
        else: %{p | droplet_moves: left}
    end)
  end

  # The test-tube droplet moves 1 glass and pays its bonus at once.
  defp tube(g, seat) do
    glass = player(g, seat).tube + 1
    bonus = TestTubes.bonus(glass)
    g = update_player(g, seat, &%{&1 | tube: glass})

    g =
      case bonus do
        :ruby -> update_player(g, seat, &%{&1 | rubies: &1.rubies + 1})
        {:vp, n} -> update_player(g, seat, &%{&1 | vp: &1.vp + n})
        {:chip, chip} -> add_from_supply(g, seat, chip)
      end

    record(g, seat, {:tube, glass, bonus})
  end
end
