defmodule Quacks.Game.Fortune do
  @moduledoc """
  The Fortune Teller cards (rulebook §5, card data in `Quacks.Rules.Fortune`).

  At the start of every round `Quacks.Game` draws the top card into `fortune_card`
  (`draw/1`), places the rats, then calls `resolve/1`. A purple card resolves there:
  its automatic part for every seat, then a game-level `:fortune_choice` phase where
  every seat with a choice answers at the same time (its player phase is
  `:fortune_choice` until it answers). Results only touch the seat's own state; with
  `supply: :limited` the first to take a chip gets it. A blue
  card stays on `fortune_card` for the round and changes the rules through the small
  hooks below, called from `Quacks.Game.Potions` and `Quacks.Game.Evaluation`.

  Every card action is `{:fortune, choice}`. Plain functions: they take the game and
  return it.
  """

  alias Quacks.Game
  alias Quacks.Game.{Essence, Evaluation, Potions}
  alias Quacks.Player
  alias Quacks.Rules.{Chips, ScoringTrack}
  alias Quacks.Rules.Fortune, as: Cards

  # Rulebook §6.2: in solo these two are skipped and the next card is drawn.
  @solo_skip [:p7, :p9]
  # Flea Market (P13): the next higher value of the same colour. ⚠️ White is not
  # traded up (a bigger white chip only hurts); orange, purple and black have no
  # higher value.
  @upgrade %{
    {:green, 1} => {:green, 2},
    {:green, 2} => {:green, 4},
    {:blue, 1} => {:blue, 2},
    {:blue, 2} => {:blue, 4},
    {:red, 1} => {:red, 2},
    {:red, 2} => {:red, 4},
    {:yellow, 1} => {:yellow, 2},
    {:yellow, 2} => {:yellow, 4}
  }

  @doc """
  The deck for `players`, shuffled with a jump of the game's `rng`: the deck comes
  from the seed but leaves the game's own random stream untouched, so a seed draws
  the same chips with or without cards.
  """
  @spec deck(:rand.state(), 1..8) :: [Cards.id()]
  def deck(rng, players) do
    {keyed, _rng} =
      Enum.map_reduce(Cards.ids(players), :rand.jump(rng), fn id, rng ->
        {u, rng} = :rand.uniform_s(rng)
        {{u, id}, rng}
      end)

    keyed |> Enum.sort() |> Enum.map(&elem(&1, 1))
  end

  @doc "Turn up the top card. Solo skips Infestation and Good Start."
  @spec draw(Game.t()) :: Game.t()
  def draw(%{fortune_deck: []} = g), do: %{g | fortune_card: nil}

  def draw(%{fortune_deck: [id | rest]} = g) do
    g = %{g | fortune_deck: rest}

    if id in @solo_skip and length(g.seats) == 1,
      do: g |> Game.record({:fortune_skipped, id}) |> draw(),
      else: Game.record(%{g | fortune_card: id}, {:fortune_drawn, id})
  end

  @doc "Resolve a purple card before the potions phase (after the rats). Blue: nothing."
  @spec resolve(Game.t()) :: Game.t()
  def resolve(%{fortune_card: nil} = g), do: g

  def resolve(g) do
    if Cards.card(g.fortune_card).colour == :purple,
      do: g |> auto(g.fortune_card) |> open_choices(),
      else: g
  end

  @doc """
  Every potions phase is done: Toil and Trouble pays out first, then the essence
  phase (The Alchemists) and the evaluation.
  """
  @spec after_potions(Game.t()) :: Game.t()
  def after_potions(%{fortune_card: :b2} = g), do: open_choices(g)
  def after_potions(g), do: Essence.run(g)

  @doc "The card actions `seat` has right now."
  @spec legal_actions(Game.t(), Game.seat()) :: [Game.action()]
  def legal_actions(%{phase: :fortune_choice} = g, seat) do
    if Game.player(g, seat).phase == :fortune_choice,
      do: Enum.map(choices(g, seat), &{:fortune, &1}),
      else: []
  end

  def legal_actions(%{phase: :potions} = g, seat),
    do: Enum.map(potion_choices(g.fortune_card, Game.player(g, seat)), &{:fortune, &1})

  def legal_actions(_g, _seat), do: []

  @doc "Apply one legal `{:fortune, choice}` for `seat`. The action is already logged."
  @spec step(Game.t(), Game.seat(), Game.action()) :: Game.t()
  def step(%{phase: :fortune_choice} = g, seat, {:fortune, choice}) do
    g |> choose(seat, g.fortune_card, choice) |> answered(seat) |> close_choices()
  end

  # B3 Second Chances: the whole pot goes back in the bag; start the round again.
  # Everything drawn this round returns (also the red chips set aside this round and
  # any offer) and the round modifiers (Y2, Y3, R4, B2) reset. ⚠️ Red Set 2 chips kept
  # from an earlier round stay beside the pot (house reading).
  def step(g, seat, {:fortune, :restart_round}) do
    this_round = set_aside_this_round(g, seat)
    p = Game.player(g, seat)
    back = this_round -- (this_round -- p.aside)

    g
    |> log(seat, {:drew, Enum.reverse(Player.pot_chips(p))})
    |> Game.update_player(seat, fn p ->
      %{
        p
        | bag: Player.pot_chips(p) ++ p.bowl ++ back ++ p.pending ++ p.bag,
          drawn: [],
          bowl: [],
          aside: p.aside -- back,
          pending: [],
          pot_index: Player.start_index(p),
          mods: %Player{}.mods,
          fortune_used?: true
      }
    end)
    |> log(seat, :restart_round)
  end

  # B10 Cauldron Bubble: like the flask, for the first white chip, without the flask.
  def step(g, seat, {:fortune, :return_white}) do
    g
    |> Game.update_player(seat, &%{&1 | fortune_used?: true})
    |> Potions.take_back(seat)
    |> log(seat, :return_white)
  end

  # B7 Safety Procedure: one chip of the offer goes on the pot, the rest back in the bag.
  def step(g, seat, {:fortune, {:place, chip}}) do
    rest = List.delete(Game.player(g, seat).pending, chip)

    g
    |> Game.update_player(seat, &%{&1 | pending: [], bag: rest ++ &1.bag})
    |> log(seat, {:place, chip})
    |> Potions.place_last(seat, chip)
  end

  def step(g, seat, {:fortune, :return_all}) do
    g
    |> Game.update_player(seat, &%{&1 | pending: [], bag: &1.pending ++ &1.bag})
    |> log(seat, :return_all)
    |> Potions.finish(seat)
  end

  # -- hooks for the blue cards ------------------------------------------------------

  @doc "The highest white sum that does not explode: 7, or 9 with B5."
  @spec explode_above(Game.t()) :: 0 | 9
  def explode_above(%{fortune_card: :b5}), do: 9
  def explode_above(_g), do: 0

  @doc """
  Second Chances (B3), official ruling (`herb-witches.md` §2.6): the first 5 draws of
  the round, before the player may start again, cannot explode the pot. ⚠️ The ruling
  says "draws a card asks for"; we read them as these 5. The pot may then be over the
  limit without exploding; the next normal draw explodes it.
  """
  @spec safe_draw?(Game.t(), Player.t()) :: boolean
  def safe_draw?(%{fortune_card: :b3}, %Player{fortune_used?: false, drawn: drawn}),
    do: length(drawn) < 5

  def safe_draw?(_g, _p), do: false

  @doc "Extra spaces for a placed chip: B6 moves orange chips one more."
  @spec extra_move(Game.t(), Chips.chip()) :: 0 | 1
  def extra_move(%{fortune_card: :b6}, {:orange, _}), do: 1
  def extra_move(_g, _chip), do: 0

  @doc "How often a bonus-die roll is rolled: twice with B4 (both rewards count)."
  @spec die_rolls(Game.t()) :: 1 | 2
  def die_rolls(%{fortune_card: :b4}), do: 2
  def die_rolls(_g), do: 1

  @doc "`seat` stops drawing. B1 checks for exactly 7 white; B7 opens a 5-chip offer."
  @spec on_stop(Game.t(), Game.seat()) :: Game.t()
  def on_stop(%{fortune_card: :b1} = g, seat) do
    if Game.white_sum(g, seat) == 7,
      do: g |> Game.move_droplet(seat, 1) |> log(seat, :droplet),
      else: g
  end

  def on_stop(%{fortune_card: :b7} = g, seat) do
    case Potions.take_random(g, seat, 5) do
      {[], g} ->
        g

      {offer, g} ->
        g
        |> log(seat, {:drew, offer})
        |> Game.update_player(seat, &%{&1 | pending: offer, phase: :fortune_choice})
    end
  end

  def on_stop(g, _seat), do: g

  @doc "Step C/D extra for a scoring space with a ruby: B8 gives 2 VP, B11 a ruby."
  @spec ruby_space(Game.t(), Game.seat()) :: Game.t()
  def ruby_space(%{fortune_card: :b8} = g, seat),
    do: g |> Game.update_player(seat, &%{&1 | vp: &1.vp + 2}) |> log(seat, {:vp, 2})

  def ruby_space(%{fortune_card: :b11} = g, seat),
    do: g |> Game.update_player(seat, &%{&1 | rubies: &1.rubies + 1}) |> log(seat, :ruby)

  def ruby_space(g, _seat), do: g

  @doc "After the evaluation: B9 refills every empty flask before the rubies phase."
  @spec refill_flasks(Game.t()) :: Game.t()
  def refill_flasks(%{fortune_card: :b9} = g) do
    g.seats
    |> Enum.reject(&Game.player(g, &1).flask)
    |> Enum.reduce(g, fn seat, g ->
      g |> Game.update_player(seat, &%{&1 | flask: true}) |> log(seat, :flask)
    end)
  end

  def refill_flasks(g), do: g

  # -- purple: the automatic part ------------------------------------------------------

  defp auto(g, :p2), do: each(g, &(&1 |> Game.move_droplet(&2, 1) |> log(&2, :droplet)))

  defp auto(g, :p4) do
    fewest = g |> fewest(& &1.rubies)
    Enum.reduce(fewest, g, &(&2 |> add_rubies(&1, 1) |> log(&1, :ruby)))
  end

  defp auto(g, :p5) do
    fewest = g |> fewest(& &1.vp)
    Enum.reduce(fewest, g, &take(&2, &1, {:green, 1}))
  end

  defp auto(g, :p7) do
    each(g, fn g, seat ->
      case Game.player(g, seat).rat_stone do
        0 -> g
        rats -> g |> move_rats(seat, rats) |> log(seat, {:rats, rats})
      end
    end)
  end

  # Less is More: everyone peeks at 5 random chips; the lowest sum takes a blue 2.
  defp auto(g, :p8) do
    {sums, g} =
      Enum.map_reduce(Game.turn_order(g), g, fn seat, g ->
        {chips, g} = Potions.take_random(g, seat, 5)
        sum = chips |> Enum.map(&elem(&1, 1)) |> Enum.sum()
        g = log(g, seat, {:drew, chips})
        {{seat, sum}, Game.update_player(g, seat, &%{&1 | bag: chips ++ &1.bag})}
      end)

    low = sums |> Enum.map(&elem(&1, 1)) |> Enum.min()

    Enum.reduce(sums, g, fn
      {seat, ^low}, g -> take(g, seat, {:blue, 2})
      {seat, _sum}, g -> g |> add_rubies(seat, 1) |> log(seat, :ruby)
    end)
  end

  defp auto(g, :p12) do
    each(g, fn g, seat ->
      {face, g} = Evaluation.roll(g, seat)
      log(g, seat, face)
    end)
  end

  # Flea Market: 4 chips leave the bag as the offer; without any trade, a green 1.
  defp auto(g, :p13) do
    each(g, fn g, seat ->
      {offer, g} = Potions.take_random(g, seat, 4)
      g = g |> log(seat, {:drew, offer}) |> Game.update_player(seat, &%{&1 | pending: offer})
      if upgrades(g, seat) == [], do: g |> return_offer(seat) |> take(seat, {:green, 1}), else: g
    end)
  end

  defp auto(g, _id), do: g

  # -- purple (and B2): the choices, every seat at once -----------------------------

  # Every seat with a choice answers now; with nobody, carry on.
  defp open_choices(g) do
    g.seats
    |> Enum.filter(&(choices(g, &1) != []))
    |> Enum.reduce(%{g | phase: :fortune_choice}, fn seat, g ->
      Game.update_player(g, seat, &%{&1 | phase: :fortune_choice})
    end)
    |> close_choices()
  end

  # A seat that answered goes back to brewing (purple) or to done (B2, after brewing).
  defp answered(g, seat) do
    back = if g.fortune_card == :b2, do: :done, else: :potions
    Game.update_player(g, seat, &%{&1 | phase: back})
  end

  # A seat whose choices ran out (a limited supply, first come) is through as well.
  # Once nobody answers any more, the round carries on.
  defp close_choices(g) do
    open = Enum.filter(g.seats, &(Game.player(g, &1).phase == :fortune_choice))
    g = open |> Enum.filter(&(choices(g, &1) == [])) |> Enum.reduce(g, &answered(&2, &1))

    if Enum.any?(g.seats, &(Game.player(g, &1).phase == :fortune_choice)),
      do: g,
      else: continue(%{g | phase: :potions})
  end

  defp continue(%{fortune_card: :b2} = g), do: Essence.run(g)
  defp continue(g), do: g

  defp choices(%{fortune_card: id} = g, seat), do: choices(id, g, Game.player(g, seat), seat)

  defp choices(:p1, g, _p, _seat),
    do: takes(g, &(&1 == {:black, 1} or elem(&1, 1) == 2)) ++ [:rubies]

  # ⚠️ The card says "besides purple or black"; Nick's ruling takes orange out too.
  # Locoweed has no printed value: not a "1-value chip".
  defp choices(:p3, g, %{rubies: r}, _seat) when r > 0,
    do:
      takes(g, fn {c, v} -> v == 1 and c not in [:orange, :purple, :black, :locoweed] end) ++
        [:skip]

  defp choices(:p6, _g, p, _seat),
    do: [:vp | if({:white, 1} in p.bag, do: [:remove_white], else: [])]

  defp choices(:p9, _g, %{rat_stone: r}, _seat) when r > 0,
    do: Enum.map(1..min(r, 3), &{:rats_back, &1}) ++ [:skip]

  defp choices(:p10, g, _p, seat) do
    vp = if rat_tails(g, seat) > 0, do: [:vp], else: []
    takes(g, &(elem(&1, 1) == 4)) ++ vp
  end

  # The card grants the purple chip, so the shop's "purple from round 3" does not apply.
  defp choices(:p11, g, _p, _seat),
    do: [:droplet | if(Game.in_supply?(g, {:purple, 1}), do: [{:take, {:purple, 1}}], else: [])]

  defp choices(:p13, g, %{pending: [_ | _]}, seat),
    do: Enum.map(upgrades(g, seat), &{:upgrade, &1}) ++ [:skip]

  # Toil and Trouble: the player to the right (the seat before) exploded.
  defp choices(:b2, %{seats: seats} = g, _p, seat) when length(seats) > 1 do
    right = rem(seat - 1 + length(seats), length(seats))
    if Game.player(g, right).exploded?, do: takes(g, &(elem(&1, 1) == 2)), else: []
  end

  defp choices(_id, _g, _p, _seat), do: []

  defp choose(g, seat, :p3, {:take, chip}),
    do: g |> add_rubies(seat, -1) |> take(seat, chip)

  defp choose(g, seat, :p13, {:upgrade, chip}) do
    rest = List.delete(Game.player(g, seat).pending, chip)

    g
    |> Game.update_player(seat, &%{&1 | pending: [], bag: rest ++ &1.bag})
    |> Game.return_supply(chip)
    |> Game.add_from_supply(seat, @upgrade[chip])
    |> log(seat, {:upgrade, chip})
  end

  defp choose(g, seat, _id, {:take, chip}), do: take(g, seat, chip)
  defp choose(g, seat, :p1, :rubies), do: g |> add_rubies(seat, 3) |> log(seat, :rubies)
  defp choose(g, seat, :p6, :vp), do: g |> add_vp(seat, 4) |> log(seat, {:vp, 4})

  defp choose(g, seat, :p10, :vp) do
    n = rat_tails(g, seat)
    g |> add_vp(seat, n) |> log(seat, {:vp, n})
  end

  defp choose(g, seat, :p6, :remove_white) do
    g
    |> Game.update_player(seat, &%{&1 | bag: List.delete(&1.bag, {:white, 1})})
    |> Game.return_supply({:white, 1})
    |> log(seat, :remove_white)
  end

  defp choose(g, seat, :p9, {:rats_back, n}),
    do: g |> move_rats(seat, -n) |> add_rubies(seat, n) |> log(seat, {:rats_back, n})

  defp choose(g, seat, :p11, :droplet), do: g |> Game.move_droplet(seat, 2) |> log(seat, :droplet)
  defp choose(g, seat, :p13, :skip), do: g |> return_offer(seat) |> log(seat, :skip)
  defp choose(g, seat, _id, :skip), do: log(g, seat, :skip)

  # -- potions-phase choices of the blue cards -------------------------------------------

  defp potion_choices(:b3, %Player{phase: :potions, fortune_used?: false, drawn: drawn})
       when length(drawn) == 5,
       do: [:restart_round]

  defp potion_choices(:b10, %Player{
         phase: :potions,
         fortune_used?: false,
         bowl: [],
         drawn: [{{:white, _}, _} | rest]
       }) do
    if Enum.any?(rest, &match?({{:white, _}, _}, &1)), do: [], else: [:return_white]
  end

  defp potion_choices(:b7, %Player{phase: :fortune_choice, pending: offer}),
    do: Enum.map(Enum.sort(Enum.uniq(offer)), &{:place, &1}) ++ [:return_all]

  defp potion_choices(_id, _p), do: []

  # -- helpers ---------------------------------------------------------------------------

  defp each(g, fun), do: Enum.reduce(Game.turn_order(g), g, &fun.(&2, &1))

  defp fewest(g, field) do
    values = Map.new(g.players, fn {seat, p} -> {seat, field.(p)} end)
    low = values |> Map.values() |> Enum.min()
    for seat <- Game.turn_order(g), values[seat] == low, do: seat
  end

  # The shop chips matching `fun` that can be taken now (in the shop and in supply).
  defp takes(g, fun),
    do:
      for(
        chip <- Chips.shop(g.expansions, g.sets),
        fun.(chip),
        Game.available?(g, chip),
        do: {:take, chip}
      )

  defp upgrades(g, seat) do
    Game.player(g, seat).pending
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.filter(&(Map.has_key?(@upgrade, &1) and Game.available?(g, @upgrade[&1])))
  end

  # Black book II: a black chip from a card goes to the left player; droplet +1.
  defp take(%{sets: %{black: 2}} = g, seat, {:black, 1} = chip) do
    if Game.in_supply?(g, chip),
      do:
        g
        |> log(seat, {:take, chip})
        |> Game.take_supply(chip)
        |> Game.give_black(seat)
        |> Game.move_droplet(seat, 1),
      else: g
  end

  defp take(g, seat, chip), do: g |> Game.add_from_supply(seat, chip) |> log(seat, {:take, chip})

  # The red chips (R2, R6) `seat` set aside since the round began, from the log.
  defp set_aside_this_round(g, seat) do
    g.log
    |> Enum.take_while(&(not match?({:round_end, _}, &1)))
    |> Enum.flat_map(fn
      {^seat, {:effect, {:red, _set}, {:aside, chip}}} -> [chip]
      _entry -> []
    end)
  end

  defp return_offer(g, seat),
    do: Game.update_player(g, seat, &%{&1 | pending: [], bag: &1.pending ++ &1.bag})

  defp rat_tails(g, seat) do
    leader = g.players |> Map.values() |> Enum.map(& &1.vp) |> Enum.max()
    ScoringTrack.rat_tails(Game.player(g, seat).vp, leader)
  end

  defp move_rats(g, seat, n),
    do: Game.update_player(g, seat, &restart(%{&1 | rat_stone: &1.rat_stone + n}))

  defp restart(p), do: %{p | pot_index: Player.start_index(p)}

  defp add_rubies(g, seat, n), do: Game.update_player(g, seat, &%{&1 | rubies: &1.rubies + n})
  defp add_vp(g, seat, n), do: Game.update_player(g, seat, &%{&1 | vp: &1.vp + n})

  defp log(g, seat, outcome), do: Game.record(g, seat, {:fortune, g.fortune_card, outcome})
end
