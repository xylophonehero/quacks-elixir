defmodule Quacks.Game do
  @moduledoc """
  Pure solo Quacks engine: one struct, one reducer.

  Slice 1 (see `docs/research/rulebook.md` §2, §3, §7): a 9-round beat-your-own-score
  game with the pot track, bag, draw/stop, explosion, flask, bonus die, rubies, buying
  chips and end-game scoring. Only white chips have mechanical meaning (explosion);
  coloured chips move the droplet by their value and do nothing else.

  Phases: `:potions` → (`:explosion_choice`) → `:buy_chips` → `:spend_rubies` → `:over`.
  The bonus die, ruby and VP steps have no player choice and run inside `apply/2`.
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

  defstruct round: 1,
            phase: :potions,
            bag: [],
            drawn: [],
            pot_index: 0,
            droplet: 0,
            flask: true,
            rubies: 1,
            coins: 0,
            vp: 0,
            exploded?: false,
            rng: nil,
            log: []

  @type phase :: :potions | :explosion_choice | :buy_chips | :spend_rubies | :over
  @type action ::
          :draw
          | :stop
          | :use_flask
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
          pot_index: 0..53,
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
    %__MODULE__{bag: Chips.starting_bag(), rng: :rand.seed_s(:exsss, seed)}
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

  def legal_actions(%__MODULE__{phase: :explosion_choice}),
    do: [{:explosion_choice, :vp}, {:explosion_choice, :buy}]

  def legal_actions(%__MODULE__{phase: :buy_chips, coins: coins}),
    do: Enum.map(buys(coins), &{:buy, &1})

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
    {i, rng} = :rand.uniform_s(length(g.bag), g.rng)
    {chip, bag} = List.pop_at(g.bag, i - 1)
    g = place(%{g | rng: rng, bag: bag}, [chip | g.drawn])

    if white_sum(g) > @explode_above,
      do: %{g | exploded?: true, phase: :explosion_choice},
      else: g
  end

  defp step(%{phase: :potions} = g, :use_flask) do
    [chip | rest] = g.drawn
    place(%{g | bag: [chip | g.bag], flask: false}, rest)
  end

  defp step(%{phase: :potions} = g, :stop), do: g |> bonus_die() |> evaluate(:both)

  # -- evaluation --------------------------------------------------------------

  defp step(%{phase: :explosion_choice} = g, {:explosion_choice, choice}),
    do: evaluate(g, choice)

  defp step(%{phase: :buy_chips} = g, {:buy, chips}) do
    cost = chips |> Enum.map(&Chips.price/1) |> Enum.sum()
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
    bag = g.drawn ++ g.bag
    # Rulebook §3 step 5: before turn 6 each player adds 1 white 1-chip.
    bag = if round == 6, do: [{:white, 1} | bag], else: bag

    %{
      g
      | round: round,
        bag: bag,
        drawn: [],
        coins: 0,
        exploded?: false,
        pot_index: g.droplet,
        phase: :potions
    }
  end

  # Set `drawn` and recompute the pot position from the droplet (clamped to the spoon).
  defp place(g, drawn) do
    values = for {_, v} <- drawn, reduce: 0, do: (acc -> acc + v)
    %{g | drawn: drawn, pot_index: min(g.droplet + values, PotTrack.last())}
  end

  defp bonus_die(g) do
    {i, rng} = :rand.uniform_s(length(@die), g.rng)
    face = Enum.at(@die, i - 1)
    g = record(%{g | rng: rng}, {:bonus_die, face})

    case face do
      {:vp, n} -> %{g | vp: g.vp + n}
      :ruby -> %{g | rubies: g.rubies + 1}
      :droplet -> %{g | droplet: g.droplet + 1}
      :orange -> %{g | bag: [{:orange, 1} | g.bag]}
    end
  end

  # Steps C–E of rulebook §3.2. `choice` is :both, or :vp / :buy after an explosion.
  defp evaluate(g, choice) do
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

  # Every affordable purchase: nothing, one chip, or two chips of different colours.
  # ponytail: yellow/purple enter before rounds 2/3 and supply is finite in the real
  # game; both ignored in slice 1 (timing rules are slice 2, supply is unreachable solo).
  defp buys(coins) do
    singles = Enum.filter(Chips.shop(), &(Chips.price(&1) <= coins))

    pairs =
      for {ca, _} = a <- singles,
          {cb, _} = b <- singles,
          a < b and ca != cb and Chips.price(a) + Chips.price(b) <= coins,
          do: [a, b]

    [[] | Enum.map(singles, &[&1])] ++ pairs
  end

  defp record(g, entry), do: %{g | log: [entry | g.log]}
end
