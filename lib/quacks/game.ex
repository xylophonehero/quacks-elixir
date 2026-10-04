defmodule Quacks.Game do
  @moduledoc """
  Pure Quacks engine for 1 to 8 players: one struct, one reducer.

  A 9-round game (see `docs/research/rulebook.md` §2, §3, §3.2, §4, §7) with the pot
  track, bags, draw/stop, explosion, flask, rats, bonus die, rubies, the Ingredient
  Set 1 chip effects, a shared chip supply, buying chips and end-game scoring.

  Each seat (`0..3`, turn order) has a `Quacks.Player`. Game phases: `:potions`, where
  every player not yet `:done` acts in any order (each has their own potions-phase
  `phase`; `:stop` only marks a player `:stopped`, and they may `:resume` while
  someone else still brews), then — as soon as nobody brews any more — the evaluation
  runs inside `apply/3` and the game moves to `:shopping`, where every seat acts at
  the same time in its own sub-phase (`:shop` → `:ready`). Ingredient books with a
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
  §1): every droplet move goes through `move_droplet/3` and waits for the player's
  choice: `{:droplet, :pot}` (the pot droplet) or `{:droplet, :tube}` (one glass on the
  test-tube track, its bonus at once, `Quacks.Rules.TestTubes`), one action per move.
  While a seat has moves waiting, those two are its only actions (`phase/2` is
  `:droplet_choice`), in any game phase. The shop adds `{:rubies, :tube}`.

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
  alias Quacks.Game.{Essence, Evaluation, Fortune, Potions, Witches}
  alias Quacks.Player
  alias Quacks.Rules.{Alchemists, Chips, ScoringTrack, TestTubes}
  alias Quacks.Rules.Witches, as: WitchCards

  @rounds 9
  # Rulebook §4: yellow enters the shop in round 2, purple in round 3.
  @from_round %{yellow: 2, purple: 3}
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
    rats: [true, false],
    black_solo: [:droplet, :droplet_ruby],
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
    rats: true,
    black_solo: :droplet,
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
            patients: nil

  @type seat :: 0..4
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
          | {:explosion_choice, :vp | :buy}
          | {:buy, [Chips.chip()]}
          | {:rubies, :droplet | :tube | :flask | :vp | :skip}
          | {:droplet, :pot | :tube}
          | :end_round
          | {:fortune, fortune_choice}
          | {:red, {:place | :keep | :return, Chips.chip()}}
          | {:chip, chip_choice}
          | :chip_done
          | {:witch, WitchCards.colour()}
          | {:witch, WitchCards.colour(), term}
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
  Herb Witches first), `{:patients, ids}` (The Alchemists' deal), `{:fortune_drawn, id}` and `{:fortune_skipped, id}` at the start of a round and
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
          patients: nil | [Alchemists.id()]
        }
  @type expansion :: :herb_witches | :alchemists
  @typedoc """
  House rules; the defaults (`default_rules/0`) are the rulebook game.
  `explode_above` is the white limit before chips and cards raise it, `black_solo`
  the solo black payout (rulebook §6.2 suggests `:droplet_ruby`), `die: :no_orange`
  turns the orange face into a second ruby face (⚠️ unofficial). `supply: :infinite`
  (default) means the shop never runs out and `supply` is never counted down;
  `:limited` plays with the box's counts. `overflow: true` (default) puts chips past
  the last space in the overflow bowl; `false` keeps them on the last space.
  `pot_side: :back` plays the reverse side of the pot (the test-tube track).
  """
  @type rules :: %{
          explode_above: 5..9,
          round6_white: boolean,
          fortune: boolean,
          rats: boolean,
          black_solo: :droplet | :droplet_ruby,
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
  as `sets:` says), 3 witches (`witches`, dealt from the seed) and 3 witch pennies per
  player. The Alchemists: locoweed book III may be picked, 3 patients are dealt
  (`patients`) and the game starts in `:patient_choice` (round 1's card comes after).
  An unknown colour, set, rule or expansion raises `ArgumentError`.
  """
  @spec new(
          seed: {integer, integer, integer},
          players: 1..8,
          sets: %{atom => 1..6 | nil},
          rules: map,
          fortune: boolean,
          expansion: nil | :herb_witches,
          expansions: Enumerable.t(expansion)
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

    rng = :rand.seed_s(:exsss, seed)
    deck = if rules.fortune, do: Fortune.deck(rng, n), else: []
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
      witches: if(herb?, do: WitchCards.deal(rng))
    }

    game =
      Enum.reduce([:herb_witches, :alchemists], game, fn x, g ->
        if MapSet.member?(expansions, x), do: record(g, {:expansion, x}), else: g
      end)

    if MapSet.member?(expansions, :alchemists), do: Essence.setup(game), else: start_round(game)
  end

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
  else their own state in `:potions`, `:essence` and `:shopping` (`:shop`, `:ready`),
  or the game's phase.
  """
  @spec phase(t, seat) :: phase | Player.phase() | :droplet_choice
  def phase(%__MODULE__{phase: phase, players: players}, seat)
      when phase != :over and is_map_key(players, seat) do
    case players[seat] do
      %Player{droplet_moves: n} when n > 0 -> :droplet_choice
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
  def start_seat(%__MODULE__{round: round, seats: seats}), do: rem(round - 1, length(seats))

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

  # Reverse pot side: a waiting droplet move comes first, in any phase.
  def legal_actions(%__MODULE__{phase: phase, players: players} = g, seat) when phase != :over do
    case players[seat] do
      %Player{droplet_moves: n} when n > 0 -> [{:droplet, :pot}, {:droplet, :tube}]
      _p -> phase_actions(g, seat)
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

  # Two steps: first the buy (once, not in round 9), then the rubies and "Done". The
  # rubies come last, never before the buy (`{:buy, []}` buys nothing). A seat whose
  # coins buy nothing starts at the rubies ("buy nothing" stays legal). Witches in both.
  defp phase_actions(%__MODULE__{phase: :shopping} = g, seat) do
    case player(g, seat) do
      %Player{phase: :shop} = p ->
        may_buy? = may_buy?(g, p)
        buys = if may_buy?, do: buys(g, p.coins), else: []

        if buys in [[], [[]]],
          do:
            Enum.map(buys, &{:buy, &1}) ++
              ruby_actions(g, p) ++ Witches.legal_actions(g, seat) ++ [:end_round],
          else: Enum.map(buys, &{:buy, &1}) ++ Witches.legal_actions(g, seat)

      %Player{phase: :ready} ->
        []
    end
  end

  # Round 9: 2 rubies buy 1 VP; droplet and flask are worth nothing any more.
  defp ruby_actions(%{round: @rounds}, %Player{rubies: rubies}),
    do: if(rubies >= 2, do: [{:rubies, :vp}], else: [])

  defp ruby_actions(g, %Player{rubies: rubies, flask: flask, ruby_price: price} = p) do
    tube? = g.rules.pot_side == :back and p.tube < TestTubes.last()

    if rubies >= price,
      do:
        [{:rubies, :droplet}] ++
          if(tube?, do: [{:rubies, :tube}], else: []) ++
          if(flask, do: [], else: [{:rubies, :flask}]),
      else: []
  end

  @doc false
  # The seat may still buy chips (and use the copper witches C1, C3): before round 9,
  # once.
  def shop_open?(g, %Player{bought?: bought?}), do: g.round < @rounds and not bought?

  # An exploded player who took the VP buys nothing (unless C4 gave them coins).
  defp may_buy?(g, p), do: shop_open?(g, p) and (p.explosion_choice != :vp or p.coins > 0)

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

  # -- shopping: every seat at once, all in one step ----------------------------------

  defp step(%{phase: :shopping} = g, seat, {:buy, chips}),
    do: g |> buy(seat, chips) |> done_buying(seat)

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
    do: record(%{g | phase: :over}, {:round_end, @rounds})

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

    start_round(%{g | round: round, phase: :potions})
  end

  # Rulebook §3 steps 1–2: the Fortune Teller card, the rats, then the purple card.
  # The Alchemists: a rat-tail glass adds to the rats; Nervousness lays out its chips.
  @doc false
  def start_round(g) do
    g
    |> Fortune.draw()
    |> place_rats()
    |> Essence.rats()
    |> Fortune.resolve()
    |> Essence.display()
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
      Enum.filter(Chips.shop(g.expansions, g.sets), &(price.(&1) <= coins and available?(g, &1)))

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
  # bag. Black book II: a black chip goes to the player on the left (`give_black/2`).
  def buy(g, seat, chips, free \\ []) do
    cost = chips |> Enum.map(&Chips.price(&1, g.sets)) |> Enum.sum()
    all = chips ++ free
    g = Enum.reduce(all, g, &take_supply(&2, &1))
    {black, mine} = Enum.split_with(all, &(&1 == {:black, 1} and g.sets[:black] == 2))
    g = update_player(g, seat, &%{&1 | coins: &1.coins - cost, bag: mine ++ &1.bag})
    g = if chips == [], do: g, else: record(g, seat, {:bought, chips})

    Enum.reduce(black, g, fn _, g -> g |> give_black(seat) |> move_droplet(seat, 1) end)
  end

  @doc """
  Move `seat`'s droplet `n` spaces: every chip action, die face, card and book that
  moves the droplet calls this. Front side: the pot droplet moves now. Reverse side
  (`pot_side: :back`): the moves wait in `droplet_moves` for the player's
  `{:droplet, :pot | :tube}` choices; with the test-tube droplet on the last glass,
  the pot droplet takes them at once. Before the round's first draw the pot's start
  follows the droplet.
  """
  @spec move_droplet(t, seat, non_neg_integer) :: t
  def move_droplet(%__MODULE__{} = g, _seat, 0), do: g

  def move_droplet(%__MODULE__{} = g, seat, n) do
    if g.rules.pot_side == :back and player(g, seat).tube < TestTubes.last(),
      do: update_player(g, seat, &%{&1 | droplet_moves: &1.droplet_moves + n}),
      else: update_player(g, seat, &pot_droplet(&1, n))
  end

  defp pot_droplet(%Player{drawn: []} = p, n) do
    p = %{p | droplet: p.droplet + n}
    %{p | pot_index: Player.start_index(p)}
  end

  defp pot_droplet(%Player{} = p, n), do: %{p | droplet: p.droplet + n}

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
  def available?(%__MODULE__{round: round} = g, {colour, _} = chip),
    do: round >= Map.get(@from_round, colour, 1) and in_supply?(g, chip)

  # The box has `n` of `chip`; an infinite supply always has (if the chip is in the box).
  @doc false
  def in_supply?(%__MODULE__{} = g, chip, n \\ 1),
    do: Map.has_key?(g.supply, chip) and (g.rules.supply == :infinite or g.supply[chip] >= n)

  # An infinite supply is never counted: taking and returning leave it as it is.
  @doc false
  def take_supply(%__MODULE__{rules: %{supply: :infinite}} = g, _chip), do: g

  def take_supply(%__MODULE__{} = g, chip),
    do: %{g | supply: Map.update!(g.supply, chip, &(&1 - 1))}

  @doc false
  def return_supply(%__MODULE__{rules: %{supply: :infinite}} = g, _chip), do: g

  def return_supply(%__MODULE__{} = g, chip),
    do: %{g | supply: Map.update!(g.supply, chip, &(&1 + 1))}

  # Move a chip from the supply into a bag; nothing happens when the box is empty.
  @doc false
  def add_from_supply(%__MODULE__{} = g, seat, chip) do
    if in_supply?(g, chip),
      do: g |> take_supply(chip) |> update_player(seat, &%{&1 | bag: [chip | &1.bag]}),
      else: g
  end

  @doc false
  # The seat to the left of `seat` (the next seat in turn order); `nil` solo.
  # ⚠️ "Left" read as the next seat clockwise, the direction of play.
  def left(%__MODULE__{seats: [_]}, _seat), do: nil
  def left(%__MODULE__{seats: seats}, seat), do: rem(seat + 1, length(seats))

  @doc false
  # Black book II: a black chip out of the supply goes into the left player's bag
  # (solo: back to the supply). The caller moves the receiver's droplet.
  def give_black(%__MODULE__{} = g, seat) do
    case left(g, seat) do
      nil ->
        g
        |> return_supply({:black, 1})
        |> effect(seat, {:black, 2}, :to_supply)

      left ->
        g
        |> update_player(left, &%{&1 | bag: [{:black, 1} | &1.bag]})
        |> effect(seat, {:black, 2}, {:to_left, left})
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

  # Open the shop for every seat at once, in one step (`:shop`): buy once, spend
  # rubies, end. ponytail: round 9 has no buy; chips bought now are useless (§7).
  # Coins stay on the player and convert to VP at the seat's `:end_round`.
  @doc false
  def to_shop(%__MODULE__{} = g) do
    Enum.reduce(g.seats, %{g | phase: :shopping}, fn seat, g ->
      update_player(g, seat, &%{&1 | phase: :shop})
    end)
  end

  @doc false
  def done_buying(g, seat), do: update_player(g, seat, &%{&1 | bought?: true})
end
