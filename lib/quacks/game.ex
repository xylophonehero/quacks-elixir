defmodule Quacks.Game do
  @moduledoc """
  Pure solo Quacks engine: one struct, one reducer.

  A 9-round beat-your-own-score game (see `docs/research/rulebook.md` §2, §3, §4, §7)
  with the pot track, bag, draw/stop, explosion, flask, bonus die, rubies, the
  Ingredient Set 1 chip effects, a limited chip supply, buying chips and end-game
  scoring.

  Phases: `:potions` → (`:yellow_choice` | `:blue_choice` | `:explosion_choice`) →
  `:buy_chips` → `:spend_rubies` → `:over`. Red, green, purple and black effects have no
  player choice and run inside `apply/2`, as do the bonus die, ruby and VP steps.
  The struct never rests in a phase with zero legal actions unless `over?/1`.

  All randomness flows through the `rng` field (`:rand` `_s` API), so a seed plus a
  list of actions reproduces a game exactly (see `Quacks.Session`).

      iex> game = Quacks.Game.new(seed: {1, 2, 3})
      iex> Quacks.Game.legal_actions(game)
      [:draw]
      iex> {:ok, game} = Quacks.Game.apply(game, :draw)
      iex> Quacks.Game.legal_actions(game)
      [:draw, :stop, :use_flask]
  """

  import Kernel, except: [apply: 2]
  alias Quacks.Rules.{Chips, PotTrack}

  @rounds 9
  @explode_above 7
  # Rulebook §3.2. ⚠️ Sixth face not in any rulebook found; assumed a second "1 VP".
  @die [{:vp, 1}, {:vp, 1}, {:vp, 2}, :ruby, :droplet, :orange]
  # Rulebook §4: yellow enters the shop in round 2, purple in round 3.
  @from_round %{yellow: 2, purple: 3}

  defstruct round: 1,
            phase: :potions,
            bag: [],
            drawn: [],
            pending: [],
            supply: %{},
            pot_index: 0,
            prev_index: 0,
            droplet: 0,
            flask: true,
            rubies: 1,
            coins: 0,
            vp: 0,
            exploded?: false,
            rng: nil,
            log: []

  @type phase ::
          :potions
          | :yellow_choice
          | :blue_choice
          | :explosion_choice
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
  @type die_face :: {:vp, 1 | 2} | :ruby | :droplet | :orange
  @type t :: %__MODULE__{
          round: 1..9,
          phase: phase,
          bag: [Chips.chip()],
          drawn: [Chips.chip()],
          pending: [Chips.chip()],
          supply: %{Chips.chip() => non_neg_integer},
          pot_index: 0..53,
          prev_index: 0..53,
          droplet: non_neg_integer,
          flask: boolean,
          rubies: non_neg_integer,
          coins: non_neg_integer,
          vp: non_neg_integer,
          exploded?: boolean,
          rng: :rand.state(),
          log: [action | {:bonus_die, die_face}]
        }

  @doc "A fresh game. `seed:` is a `{int, int, int}` tuple for `:rand.seed_s(:exsss, seed)`."
  @spec new(seed: {integer, integer, integer}) :: t
  def new(opts) do
    seed = Keyword.fetch!(opts, :seed)
    bag = Chips.starting_bag()
    supply = Enum.reduce(bag, Chips.supply(), &Map.update!(&2, &1, fn n -> n - 1 end))
    %__MODULE__{bag: bag, supply: supply, rng: :rand.seed_s(:exsss, seed)}
  end

  @doc "True after round 9's evaluation."
  @spec over?(t) :: boolean
  def over?(%__MODULE__{phase: phase}), do: phase == :over

  @doc "Victory points so far."
  @spec score(t) :: non_neg_integer
  def score(%__MODULE__{vp: vp}), do: vp

  @doc "Sum of white chip values in the pot this round."
  @spec white_sum(t) :: non_neg_integer
  def white_sum(%__MODULE__{drawn: drawn}) do
    for({:white, v} <- drawn, reduce: 0, do: (acc -> acc + v))
  end

  @doc "The scoring space: directly after the last placed chip, clamped to the spoon."
  @spec scoring_index(t) :: 0..53
  def scoring_index(%__MODULE__{pot_index: i}), do: min(i + 1, PotTrack.last())

  @doc "Every action `apply/2` accepts right now. Empty only when `over?/1`."
  @spec legal_actions(t) :: [action]
  def legal_actions(%__MODULE__{phase: :potions, bag: bag, drawn: drawn, flask: flask}) do
    List.flatten([
      if(bag == [], do: [], else: :draw),
      if(drawn == [], do: [], else: :stop),
      if(flask and match?([{:white, _} | _], drawn), do: :use_flask, else: [])
    ])
  end

  def legal_actions(%__MODULE__{phase: :yellow_choice}), do: [:return_white, :keep]

  def legal_actions(%__MODULE__{phase: :blue_choice, pending: pending}),
    do: Enum.map(Enum.sort(Enum.uniq(pending)), &{:place, &1}) ++ [:return_all]

  def legal_actions(%__MODULE__{phase: :explosion_choice}),
    do: [{:explosion_choice, :vp}, {:explosion_choice, :buy}]

  def legal_actions(%__MODULE__{phase: :buy_chips} = g), do: Enum.map(buys(g), &{:buy, &1})

  def legal_actions(%__MODULE__{phase: :spend_rubies, rubies: rubies, flask: flask}) do
    List.flatten([
      if(rubies >= 2, do: {:rubies, :droplet}, else: []),
      if(rubies >= 2 and not flask, do: {:rubies, :flask}, else: []),
      :end_round
    ])
  end

  def legal_actions(%__MODULE__{phase: :over}), do: []

  @doc """
  Apply one action. Illegal actions (wrong phase, unaffordable buy, empty bag, ...)
  return `{:error, {:illegal_action, action, phase}}` and leave the game untouched.

  `{:buy, chips}` accepts chips in any order; `{:rubies, :skip}` equals `:end_round`.
  """
  @spec apply(t, action) :: {:ok, t} | {:error, {:illegal_action, action, phase}}
  def apply(%__MODULE__{} = game, action) do
    action = normalise(action)

    if action in legal_actions(game) do
      {:ok, game |> step(action) |> record(action)}
    else
      {:error, {:illegal_action, action, game.phase}}
    end
  end

  defp normalise({:buy, chips}), do: {:buy, Enum.sort(chips)}
  defp normalise({:rubies, :skip}), do: :end_round
  defp normalise(action), do: action

  # -- potions -----------------------------------------------------------------

  defp step(%{phase: :potions} = g, :draw) do
    {[chip], g} = take_random(g, 1)
    resolve_draw(g, chip)
  end

  defp step(%{phase: :potions} = g, :use_flask) do
    [chip | rest] = g.drawn
    %{g | bag: [chip | g.bag], drawn: rest, flask: false, pot_index: g.prev_index}
  end

  defp step(%{phase: :potions} = g, :stop), do: g |> bonus_die() |> evaluate(:both)

  # Yellow (§4): the white chip directly before the yellow goes back in the bag; its
  # space stays empty, the yellow chip does not move back, the white sum reverts.
  defp step(%{phase: :yellow_choice} = g, :return_white) do
    [yellow, white | rest] = g.drawn
    %{g | drawn: [yellow | rest], bag: [white | g.bag], phase: :potions}
  end

  defp step(%{phase: :yellow_choice} = g, :keep), do: %{g | phase: :potions}

  # Blue (§4): one of the extra chips becomes the next chip and resolves normally.
  defp step(%{phase: :blue_choice} = g, {:place, chip}) do
    rest = List.delete(g.pending, chip)
    resolve_draw(%{g | pending: [], bag: rest ++ g.bag, phase: :potions}, chip)
  end

  defp step(%{phase: :blue_choice} = g, :return_all),
    do: %{g | pending: [], bag: g.pending ++ g.bag, phase: :potions}

  # -- evaluation --------------------------------------------------------------

  defp step(%{phase: :explosion_choice} = g, {:explosion_choice, choice}),
    do: evaluate(g, choice)

  defp step(%{phase: :buy_chips} = g, {:buy, chips}) do
    cost = chips |> Enum.map(&Chips.price/1) |> Enum.sum()
    g = Enum.reduce(chips, g, &take_supply(&2, &1))
    %{g | coins: g.coins - cost, bag: chips ++ g.bag, phase: :spend_rubies}
  end

  defp step(%{phase: :spend_rubies} = g, {:rubies, :droplet}),
    do: %{g | rubies: g.rubies - 2, droplet: g.droplet + 1}

  defp step(%{phase: :spend_rubies} = g, {:rubies, :flask}),
    do: %{g | rubies: g.rubies - 2, flask: true}

  defp step(%{phase: :spend_rubies, round: @rounds} = g, :end_round) do
    # Rulebook §7: 5 coins or 2 rubies buy 1 VP, as often as you like.
    vp = g.vp + div(g.coins, 5) + div(g.rubies, 2)
    %{g | vp: vp, coins: rem(g.coins, 5), rubies: rem(g.rubies, 2), phase: :over}
  end

  defp step(%{phase: :spend_rubies} = g, :end_round) do
    round = g.round + 1
    g = %{g | bag: g.drawn ++ g.bag, drawn: []}
    # Rulebook §3 step 5: before turn 6 each player adds 1 white 1-chip.
    g = if round == 6, do: add_from_supply(g, {:white, 1}), else: g

    %{g | round: round, coins: 0, exploded?: false, pot_index: g.droplet, phase: :potions}
  end

  # Place a chip as the next chip in the pot, then run its on-draw effect (§3.1).
  defp resolve_draw(g, chip) do
    g = place(g, chip)

    if white_sum(g) > @explode_above,
      do: %{g | exploded?: true, phase: :explosion_choice},
      else: on_draw(g, chip)
  end

  defp on_draw(%{drawn: [_, {:white, _} | _]} = g, {:yellow, _}), do: %{g | phase: :yellow_choice}

  defp on_draw(g, {:blue, value}) do
    case take_random(g, value) do
      {[], g} -> g
      {extra, g} -> %{g | pending: extra, phase: :blue_choice}
    end
  end

  defp on_draw(g, _chip), do: g

  # Push a chip onto the pot `value` (+ red bonus) spaces after the previous chip.
  # ponytail: `prev_index` is a one-deep undo for the flask; it is the only revert and
  # the flask works once per round, so a position stack is not needed.
  defp place(g, {_, value} = chip) do
    index = min(g.pot_index + value + red_bonus(chip, g.drawn), PotTrack.last())
    %{g | drawn: [chip | g.drawn], pot_index: index, prev_index: g.pot_index}
  end

  # Red (§4): extra movement by the number of orange chips already in the pot.
  defp red_bonus({:red, _}, drawn) do
    case Enum.count(drawn, &match?({:orange, _}, &1)) do
      0 -> 0
      n when n <= 2 -> 1
      _ -> 2
    end
  end

  defp red_bonus(_chip, _drawn), do: 0

  # Draw up to `n` random chips from the bag (fewer when the bag runs short).
  defp take_random(g, n) do
    Enum.reduce(1..min(n, length(g.bag))//1, {[], g}, fn _, {taken, g} ->
      {i, rng} = :rand.uniform_s(length(g.bag), g.rng)
      {chip, bag} = List.pop_at(g.bag, i - 1)
      {[chip | taken], %{g | rng: rng, bag: bag}}
    end)
  end

  defp bonus_die(g) do
    {i, rng} = :rand.uniform_s(length(@die), g.rng)
    face = Enum.at(@die, i - 1)
    g = record(%{g | rng: rng}, {:bonus_die, face})

    case face do
      {:vp, n} -> %{g | vp: g.vp + n}
      :ruby -> %{g | rubies: g.rubies + 1}
      :droplet -> %{g | droplet: g.droplet + 1}
      :orange -> add_from_supply(g, {:orange, 1})
    end
  end

  # Steps B–E of rulebook §3.2. `choice` is :both, or :vp / :buy after an explosion.
  defp evaluate(g, choice) do
    g = chip_actions(g)
    space = PotTrack.at(scoring_index(g))
    g = if space.ruby?, do: %{g | rubies: g.rubies + 1}, else: g
    g = if choice == :buy, do: g, else: %{g | vp: g.vp + space.vp}

    cond do
      choice == :vp -> %{g | phase: :spend_rubies}
      # ponytail: round 9 skips the shop; chips bought now are useless (§7). Coins
      # stay on the struct and convert to VP in :end_round.
      g.round == @rounds -> %{g | coins: space.coins, phase: :spend_rubies}
      true -> %{g | coins: space.coins, phase: :buy_chips}
    end
  end

  # Step B (§4): black, green, purple. All automatic; always the highest purple tier.
  defp chip_actions(g) do
    count = fn colour, chips -> Enum.count(chips, &match?({^colour, _}, &1)) end

    # ⚠️ Solo house rule: no opponent to compare black chips with, so 1+ black chip
    # counts as "tied with the opponent": droplet +1, no ruby.
    g = if count.(:black, g.drawn) > 0, do: %{g | droplet: g.droplet + 1}, else: g
    g = %{g | rubies: g.rubies + count.(:green, Enum.take(g.drawn, 2))}

    case count.(:purple, g.drawn) do
      0 -> g
      1 -> %{g | vp: g.vp + 1}
      2 -> %{g | vp: g.vp + 1, rubies: g.rubies + 1}
      _ -> %{g | vp: g.vp + 2, droplet: g.droplet + 1}
    end
  end

  # Every affordable purchase: nothing, one chip, or two chips of different colours.
  defp buys(%{coins: coins, round: round, supply: supply}) do
    singles =
      Enum.filter(Chips.shop(), fn {colour, _} = chip ->
        Chips.price(chip) <= coins and round >= Map.get(@from_round, colour, 1) and
          Map.fetch!(supply, chip) > 0
      end)

    pairs =
      for {ca, _} = a <- singles,
          {cb, _} = b <- singles,
          a < b and ca != cb and Chips.price(a) + Chips.price(b) <= coins,
          do: [a, b]

    [[] | Enum.map(singles, &[&1])] ++ pairs
  end

  defp take_supply(g, chip), do: %{g | supply: Map.update!(g.supply, chip, &(&1 - 1))}

  # Move a chip from the supply into the bag; nothing happens when the box is empty.
  defp add_from_supply(g, chip) do
    if g.supply[chip] > 0, do: %{take_supply(g, chip) | bag: [chip | g.bag]}, else: g
  end

  defp record(g, entry), do: %{g | log: [entry | g.log]}
end
