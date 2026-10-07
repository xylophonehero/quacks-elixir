defmodule Quacks.Game.Essence do
  @moduledoc """
  The Alchemists (`docs/research/alchemists-essences.md`): the patient choice, the
  essence phase and the patient actions of the next preparation phase. Patient data
  lives in `Quacks.Rules.Alchemists`.

  - **Patient choice** (game phase `:patient_choice`, before round 1): every seat at
    once picks one of the 3 dealt patients (`game.patients`) with `{:patient, id}`;
    start chips go in the bag; the last pick starts round 1.
  - **Essence phase** (game phase `:essence`, after the last stop and Toil and
    Trouble, before the evaluation): every seat's marker goes to 0, then to
    `reach = min(10, colours + locoweed III + white 7 + exploded neighbours)`.
    Round 9: `reach` VP and nothing else. Else the seat takes the reached space at
    once, or picks a lower one (`:essence_choice`, `{:essence, {:space, n}}`) when a
    lower space has another kind of bonus. The glass pays at once; Ear worm draws
    (`:ear_worm`, `:draw`, the pot cannot explode), Chicken eyes swaps and Vampirism
    buys (`:essence_bonus`, `{:essence, {:swap | :buy, chip}}` or `{:essence, :pass}`)
    wait for the seat. The evaluation runs when no seat is left.
  - **Preparation phase** (`:potions`): Nervousness places from `display`
    (`{:essence, {:place, chip}}`), Forgetfulness returns a pot chip
    (`{:essence, {:forget, chip}}`); Carrot nose, Wing ears and Witch's hump open an
    offer after a draw (player phase `:essence_offer`: `{:essence, :carrot | :double
    | :return | :hump}` or `{:essence, :pass}`). Every action spends essence.

  Plain functions called from `Quacks.Game`, `Quacks.Game.Fortune` and
  `Quacks.Game.Potions`.
  """

  alias Quacks.Game
  alias Quacks.Game.{Evaluation, Potions}
  alias Quacks.Player
  alias Quacks.Rules.{Alchemists, Chips, PotTrack}

  @last_round 9
  @cost %{carrot: 2, double: 2, return: 3, hump: 2}
  # Player phases that keep the essence phase open (Ear worm on-draw choices too).
  @open [:essence_choice, :essence_bonus, :ear_worm, :blue_choice, :yellow_choice, :chip_choice]

  # -- patient choice ------------------------------------------------------------------

  @doc "Deal 3 patients and wait for every seat's pick (`:patient_choice`)."
  @spec setup(Game.t()) :: Game.t()
  def setup(g) do
    patients = Alchemists.deal(g.rng)
    Game.record(%{g | patients: patients, phase: :patient_choice}, {:patients, patients})
  end

  @doc """
  The 3 patients a game with `seed` deals (`setup/1`), so a setup screen can offer
  them before the game exists.
  """
  @spec dealt({integer, integer, integer}) :: [Alchemists.id()]
  def dealt(seed), do: Alchemists.deal(:rand.seed_s(:exsss, seed))

  @doc """
  The patients picked before the game (round 26): `picks` maps a seat to one of the
  dealt patients or `:random` (one of the 3, from a jump of the seed, so the game's
  own random stream does not change). Each pick is an ordinary `{:patient, id}`
  action in the log; seats left out choose in `:patient_choice` as before. A seat
  or patient that is not in the game raises `ArgumentError`.
  """
  @spec prepick(Game.t(), %{optional(Game.seat()) => Alchemists.id() | :random} | nil) ::
          Game.t()
  def prepick(g, nil), do: g

  def prepick(g, picks) when is_map(picks) do
    rng = g.rng |> :rand.jump() |> :rand.jump() |> :rand.jump() |> :rand.jump()

    {g, _rng} =
      picks
      |> Enum.sort()
      |> Enum.reduce({g, rng}, fn {seat, pick}, {g, rng} ->
        if seat not in g.seats, do: raise(ArgumentError, "no seat #{inspect(seat)}")
        {id, rng} = resolve(pick, g.patients, rng)
        {:ok, g} = Game.apply(g, seat, {:patient, id})
        {g, rng}
      end)

    g
  end

  def prepick(_g, picks),
    do: raise(ArgumentError, "patients must be a map, got #{inspect(picks)}")

  defp resolve(:random, dealt, rng) do
    {n, rng} = :rand.uniform_s(length(dealt), rng)
    {Enum.at(dealt, n - 1), rng}
  end

  defp resolve(id, dealt, rng) do
    if id in dealt,
      do: {id, rng},
      else: raise(ArgumentError, "patient #{inspect(id)} is not dealt (#{inspect(dealt)})")
  end

  # -- legal actions -------------------------------------------------------------------

  @doc "The essence and patient actions `seat` has now (any game phase)."
  @spec legal_actions(Game.t(), Game.seat()) :: [Game.action()]
  def legal_actions(%{phase: :patient_choice} = g, seat) do
    if Game.player(g, seat).patient, do: [], else: Enum.map(g.patients, &{:patient, &1})
  end

  def legal_actions(%{phase: :essence} = g, seat) do
    case Game.player(g, seat) do
      %{phase: :essence_choice, essence_pending: {:space, reach}} ->
        for n <- 0..reach, do: space(n)

      %{phase: :ear_worm} ->
        [:draw]

      %{phase: :essence_bonus} = p ->
        bonus_actions(g, p) ++ [{:essence, :pass}]

      %{phase: phase} = p when phase in @open ->
        Potions.legal_actions(p)

      _ ->
        []
    end
  end

  def legal_actions(%{phase: :potions} = g, seat) do
    case Game.player(g, seat) do
      %{phase: :essence_offer, essence_pending: {:offers, [offer | _]}} = p ->
        offer_actions(offer, p) ++ [{:essence, :pass}]

      %{phase: :potions, witch_offer: []} = p ->
        forget_actions(p) ++ for(chip <- Enum.sort(Enum.uniq(p.display)), do: place(chip))

      _ ->
        []
    end
  end

  def legal_actions(_g, _seat), do: []

  defp space(n), do: {:essence, {:space, n}}
  defp place(chip), do: {:essence, {:place, chip}}

  defp bonus_actions(g, %{essence_pending: {:swap, 1, to}} = p),
    do: for(chip <- Enum.sort(swaps(g, p, to)), do: {:essence, {:swap, chip}})

  defp bonus_actions(g, %{essence_pending: {:buy, coins}}),
    do: for(chip <- buys(g, coins), do: {:essence, {:buy, chip}})

  defp offer_actions({:carrot, _}, _p), do: [{:essence, :carrot}]
  defp offer_actions({:hump, _}, _p), do: [{:essence, :hump}]
  defp offer_actions({:wing_bowl, _}, _p), do: [{:essence, :return}]

  defp offer_actions({:wing, _}, %{essence: e}),
    do:
      if(e >= @cost.return,
        do: [{:essence, :double}, {:essence, :return}],
        else: [{:essence, :double}]
      )

  # Forgetfulness: a coloured pot chip (not locoweed) worth at most the essence.
  defp forget_actions(%{patient: :forgetfulness, drawn: drawn, essence: e}) do
    for {{colour, value} = chip, _} <- Enum.sort(drawn),
        colour not in [:white, :locoweed] and value <= e,
        uniq: true,
        do: {:essence, {:forget, chip}}
  end

  defp forget_actions(_p), do: []

  # -- steps ---------------------------------------------------------------------------

  @doc "Apply one legal essence or patient action for `seat`. The action is already logged."
  @spec step(Game.t(), Game.seat(), Game.action()) :: Game.t()
  def step(%{phase: :patient_choice} = g, seat, {:patient, id}) do
    g = Game.update_player(g, seat, &%{&1 | patient: id})
    g = Enum.reduce(Alchemists.get(id).start_chips, g, &Game.add_from_supply(&2, seat, &1))

    if Enum.all?(g.players, fn {_seat, p} -> p.patient end),
      do: Game.start_round(%{g | phase: :potions}),
      else: g
  end

  def step(%{phase: :essence} = g, seat, action),
    do: g |> essence_step(seat, action) |> settle(seat) |> close()

  def step(g, seat, {:essence, {:place, chip}}) do
    g
    |> Game.update_player(seat, &%{&1 | display: List.delete(&1.display, chip)})
    |> Potions.resolve_draw(seat, chip)
  end

  def step(g, seat, {:essence, {:forget, {_, value} = chip}}) do
    g
    |> Game.update_player(seat, fn p ->
      drawn = List.keydelete(p.drawn, chip, 0)
      %{p | drawn: drawn, pot_index: Potions.last_index(drawn, p)}
    end)
    |> Potions.return_to_bag(seat, chip)
    |> spend(seat, value, {:forget, chip})
  end

  def step(g, seat, {:essence, choice}) do
    {:offers, [offer | rest]} = Game.player(g, seat).essence_pending

    g
    |> Game.update_player(seat, &%{&1 | essence_pending: {:offers, rest}, phase: :potions})
    |> answer(seat, choice, offer)
  end

  defp essence_step(g, seat, {:essence, {:space, n}}), do: land(g, seat, n)

  defp essence_step(g, seat, :draw) do
    {:ear_worm, n} = Game.player(g, seat).essence_pending
    g = Game.update_player(g, seat, &%{&1 | essence_pending: {:ear_worm, n - 1}})
    {[chip], g} = Potions.take_random(g, seat, 1)
    Potions.resolve_draw(g, seat, chip)
  end

  defp essence_step(g, seat, {:essence, {:swap, {colour, 1} = chip}}) do
    {:swap, 1, to} = Game.player(g, seat).essence_pending
    big = {colour, to}

    g
    |> Game.return_supply(chip)
    |> Game.take_supply(big)
    |> Game.update_player(seat, fn p ->
      {^chip, index} = List.keyfind(p.drawn, chip, 0)

      %{
        p
        | drawn: List.keyreplace(p.drawn, chip, 0, {big, index}),
          essence_pending: nil,
          phase: :done
      }
    end)
  end

  defp essence_step(g, seat, {:essence, {:buy, chip}}) do
    g
    |> Game.update_player(seat, &%{&1 | essence_pending: nil, phase: :done})
    |> Game.record(seat, {:bought, [chip]})
    |> Game.buy(seat, [], [chip])
  end

  defp essence_step(g, seat, {:essence, :pass}),
    do: Game.update_player(g, seat, &%{&1 | essence_pending: nil, phase: :done})

  # Ear worm on-draw choices (blue offer, yellow, Y6, locoweed V).
  defp essence_step(g, seat, action), do: Potions.step(g, seat, action)

  # Back from an Ear worm draw or its choice: draw on while draws and chips are left.
  defp settle(g, seat) do
    case Game.player(g, seat) do
      %{phase: phase, essence_pending: {:ear_worm, n}, bag: bag}
      when phase in [:potions, :ear_worm] ->
        if n > 0 and bag != [],
          do: Game.update_player(g, seat, &%{&1 | phase: :ear_worm}),
          else: Game.update_player(g, seat, &%{&1 | phase: :done, essence_pending: nil})

      _ ->
        g
    end
  end

  defp close(g) do
    if Enum.any?(g.seats, &(Game.player(g, &1).phase in @open)), do: g, else: Evaluation.run(g)
  end

  # -- the essence phase ---------------------------------------------------------------

  @doc """
  Every potions phase is done (and B2 paid out): the essence phase with The
  Alchemists, else straight to the evaluation.
  """
  @spec run(Game.t()) :: Game.t()
  def run(g) do
    if Game.expansion?(g, :alchemists), do: open(g), else: Evaluation.run(g)
  end

  defp open(g) do
    order = Game.turn_order(g)
    # All seats count first: the neighbours' explosions are read before any draw.
    reaches = Map.new(order, &{&1, count(g, &1)})

    g =
      Enum.reduce(order, g, fn seat, g ->
        {reach, parts} = reaches[seat]

        g
        |> Game.update_player(seat, &%{&1 | essence: 0, essence_pending: nil})
        |> Game.record(seat, {:essence, reach, parts})
      end)

    if g.round == @last_round,
      do: g |> final(order, reaches) |> Evaluation.run(),
      else: order |> Enum.reduce(%{g | phase: :essence}, &reach(&2, &1, reaches)) |> close()
  end

  # Round 9: 1 VP per space, no glass.
  defp final(g, order, reaches) do
    Enum.reduce(order, g, fn seat, g ->
      {n, _parts} = reaches[seat]

      g
      |> Game.update_player(seat, &%{&1 | essence: n, vp: &1.vp + n})
      |> Game.record(seat, {:essence_vp, n})
    end)
  end

  defp reach(g, seat, reaches) do
    {reach, _parts} = reaches[seat]

    if lower_choice?(Game.player(g, seat).patient, reach),
      do:
        Game.update_player(
          g,
          seat,
          &%{&1 | phase: :essence_choice, essence_pending: {:space, reach}}
        ),
      else: land(g, seat, reach)
  end

  @doc """
  The reached space and its parts for `seat`: the colours in the pot (not white), +1
  per locoweed with locoweed book III, +1 when the white chips in the pot add up to
  exactly 7, +1 per exploded neighbour (solo: none). At most 10.
  """
  @spec count(Game.t(), Game.seat()) ::
          {0..10,
           %{colours: non_neg_integer, locoweed: non_neg_integer, white7: 0 | 1, neighbours: 0..2}}
  def count(g, seat) do
    chips = Game.pot_chips(g, seat)
    colours = chips |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.count(&(&1 != :white))

    locoweed =
      if g.sets[:locoweed] == 3, do: Enum.count(chips, &match?({:locoweed, _}, &1)), else: 0

    white7 = if Enum.sum(for {:white, v} <- chips, do: v) == 7, do: 1, else: 0
    neighbours = Enum.count(neighbours(g, seat), &Game.player(g, &1).exploded?)
    parts = %{colours: colours, locoweed: locoweed, white7: white7, neighbours: neighbours}
    {min(colours + locoweed + white7 + neighbours, Alchemists.max_space()), parts}
  end

  # The seats left and right; with 2 players the one opponent once.
  defp neighbours(%{seats: [_]}, _seat), do: []
  defp neighbours(%{seats: [_, _] = seats}, seat), do: List.delete(seats, seat)

  defp neighbours(%{seats: seats}, seat) do
    n = length(seats)
    [rem(seat + n - 1, n), rem(seat + 1, n)]
  end

  @doc """
  Is a lower space worth offering? Only when a lower space 1..reach-1 has a bonus of
  another kind than the reached one (e.g. a rat tail instead of draws).
  """
  @spec lower_choice?(Alchemists.id(), 0..10) :: boolean
  def lower_choice?(patient, reach) do
    top = kinds(Alchemists.slot(patient, reach))
    Enum.any?(1..(reach - 1)//1, &(kinds(Alchemists.slot(patient, &1)) not in [[], top]))
  end

  defp kinds(slot), do: slot |> Enum.map(&kind/1) |> Enum.sort()
  defp kind({:chip, chip}), do: {:chip, chip}
  defp kind(term) when is_tuple(term), do: elem(term, 0)
  defp kind(term), do: term

  # The marker lands on `space`: its glass pays now.
  defp land(g, seat, space) do
    g = Game.update_player(g, seat, &%{&1 | essence: space, essence_pending: nil, phase: :done})
    Enum.reduce(Alchemists.slot(Game.player(g, seat).patient, space), g, &pay(&2, seat, &1))
  end

  # One glass (or a Witch's hump bonus). `:rat` and `{:draw, n}` act next round.
  defp pay(g, seat, term),
    do: g |> Game.record(seat, {:essence_bonus, term}) |> pay_now(seat, term)

  defp pay_now(g, seat, {:vp, n}), do: Game.update_player(g, seat, &%{&1 | vp: &1.vp + n})

  defp pay_now(g, seat, {:rubies, n}),
    do: Game.update_player(g, seat, &%{&1 | rubies: &1.rubies + n})

  defp pay_now(g, seat, {:chip, chip}), do: Game.add_from_supply(g, seat, chip)
  defp pay_now(g, seat, :flask), do: Game.update_player(g, seat, &%{&1 | flask: true})
  defp pay_now(g, seat, {:droplet, n}), do: Game.move_droplet(g, seat, n)
  defp pay_now(g, seat, {:dice, n}), do: Enum.reduce(1..n, g, fn _, g -> roll(g, seat) end)
  defp pay_now(g, seat, {:ear_worm, _} = term), do: wait(g, seat, term, :ear_worm)
  defp pay_now(g, seat, {:swap, 1, _} = term), do: wait(g, seat, term, :essence_bonus)
  defp pay_now(g, seat, {:buy, _} = term), do: wait(g, seat, term, :essence_bonus)
  defp pay_now(g, _seat, _rat_or_draw), do: g

  # The seat acts on the bonus, if it can.
  defp wait(g, seat, term, phase) do
    if can_wait?(g, Game.player(g, seat), term),
      do: Game.update_player(g, seat, &%{&1 | essence_pending: term, phase: phase}),
      else: g
  end

  defp can_wait?(_g, p, {:ear_worm, _}), do: p.bag != []
  defp can_wait?(g, p, {:swap, 1, to}), do: swaps(g, p, to) != []
  defp can_wait?(g, _p, {:buy, coins}), do: buys(g, coins) != []

  defp roll(g, seat) do
    {face, g} = Evaluation.roll(g, seat)
    Game.record(g, seat, {:bonus_die, face})
  end

  # Chicken eyes: the coloured 1-chips in the pot that have a `to`-chip in the supply.
  defp swaps(g, p, to) do
    for {{colour, 1}, _} <- p.drawn,
        colour in [:green, :blue, :red, :yellow] and Game.in_supply?(g, {colour, to}),
        uniq: true,
        do: {colour, 1}
  end

  # Vampirism: one chip for at most `coins`, from this round's shop.
  defp buys(g, coins) do
    for chip <- Chips.shop(g.expansions, g.sets),
        Chips.price(chip, g.sets) <= coins and Game.available?(g, chip),
        do: chip
  end

  # -- the next preparation phase ------------------------------------------------------

  @doc """
  Start of a round (after the rats): a rat-tail glass moves the rat stone 1 more
  (solo too); after the Fortune Teller card, Nervousness lays out its chips.
  """
  @spec rats(Game.t()) :: Game.t()
  def rats(g) do
    g.seats
    |> Enum.filter(&(:rat in glass(Game.player(g, &1))))
    |> Enum.reduce(g, fn seat, g ->
      g
      |> Game.update_player(seat, &rat/1)
      |> Game.record(seat, {:essence_rat, 1})
    end)
  end

  defp rat(p) do
    p = %{p | rat_stone: p.rat_stone + 1}
    %{p | pot_index: Player.start_index(p)}
  end

  # The glass under the marker (none before a patient is picked).
  defp glass(%{patient: nil}), do: []
  defp glass(p), do: Alchemists.slot(p.patient, p.essence)

  @doc "Nervousness: draw the glass's chips; the white ones go back, the rest lie out."
  @spec display(Game.t()) :: Game.t()
  def display(g) do
    Enum.reduce(g.seats, g, fn seat, g ->
      p = Game.player(g, seat)

      case glass(p) do
        [{:draw, n}] ->
          {chips, g} = Potions.take_random(g, seat, n)
          {whites, rest} = Enum.split_with(chips, &match?({:white, _}, &1))

          g
          |> Game.update_player(seat, &%{&1 | display: rest, bag: whites ++ &1.bag})
          |> Game.record(seat, {:display, chips})

        _ ->
          g
      end
    end)
  end

  @doc """
  A chip just landed (not exploding) in the preparation phase: queue the patient's
  offer for it. Carrot nose: a pumpkin in the pot with a ruby space ahead. Wing ears:
  a white chip. Witch's hump: a chip on a ruby space that has a hump bonus.
  """
  @spec after_place(Game.t(), Game.seat(), Chips.chip(), term) :: Game.t()
  def after_place(%{phase: :potions} = g, seat, chip, book) do
    p = Game.player(g, seat)
    in_pot? = book != :bowl

    offer =
      case {p.patient, chip} do
        {:carrot_nose, {:orange, _}} when in_pot? -> {:carrot, chip}
        {:wing_ears, {:white, _}} when in_pot? -> {:wing, chip}
        {:wing_ears, {:white, _}} -> {:wing_bowl, chip}
        {:witch_hump, _} when in_pot? -> if hump?(p, chip), do: {:hump, chip}
        _ -> nil
      end

    if offer,
      do: Game.update_player(g, seat, &%{&1 | essence_pending: {:offers, offers(&1) ++ [offer]}}),
      else: g
  end

  def after_place(g, _seat, _chip, _book), do: g

  defp offers(%{essence_pending: {:offers, offers}}), do: offers
  defp offers(_p), do: []

  defp hump?(p, chip), do: PotTrack.at(p.pot_index).ruby? and Alchemists.hump_bonus(chip) != nil

  @doc """
  Open the next waiting offer of every brewing seat (player phase `:potions` →
  `:essence_offer`); offers the seat can no longer pay for, or whose chip moved on,
  are dropped.
  """
  @spec open_offers(Game.t()) :: Game.t()
  def open_offers(g) do
    g.seats
    |> Enum.filter(&match?(%{phase: :potions, essence_pending: {:offers, _}}, Game.player(g, &1)))
    |> Enum.reduce(g, &Game.update_player(&2, &1, fn p -> open_offer(p) end))
  end

  defp open_offer(p) do
    case Enum.drop_while(offers(p), &(not valid?(&1, p))) do
      [] -> %{p | essence_pending: nil}
      offers -> %{p | essence_pending: {:offers, offers}, phase: :essence_offer}
    end
  end

  defp valid?({:carrot, chip}, %{drawn: [{chip, i} | _]} = p),
    do: p.essence >= @cost.carrot and next_ruby(i) != nil

  defp valid?({:wing, chip}, %{drawn: [{chip, _} | _]} = p), do: p.essence >= @cost.double
  defp valid?({:wing_bowl, chip}, %{bowl: [chip | _]} = p), do: p.essence >= @cost.return
  defp valid?({:hump, _}, p), do: p.essence >= @cost.hump
  defp valid?(_offer, _p), do: false

  defp next_ruby(i), do: Enum.find((i + 1)..PotTrack.last()//1, &PotTrack.at(&1).ruby?)

  defp answer(g, _seat, :pass, _offer), do: g

  # The pumpkin goes to the next ruby space; the next chip counts from there.
  defp answer(g, seat, :carrot, {:carrot, _}) do
    g
    |> Game.update_player(seat, fn %{drawn: [{chip, i} | rest]} = p ->
      j = next_ruby(i)
      %{p | drawn: [{chip, j} | rest], pot_index: j}
    end)
    |> spend(seat, @cost.carrot, :carrot)
  end

  # The white moves its value once more. ⚠️ It still counts toward the explosion.
  defp answer(g, seat, :double, {:wing, _}) do
    g
    |> Game.update_player(seat, fn %{drawn: [{{:white, v} = chip, i} | rest]} = p ->
      j = min(i + v, PotTrack.last())
      %{p | drawn: [{chip, j} | rest], pot_index: j}
    end)
    |> spend(seat, @cost.double, :double)
  end

  defp answer(g, seat, :return, _wing),
    do: g |> Potions.take_back(seat) |> spend(seat, @cost.return, :return)

  defp answer(g, seat, :hump, {:hump, chip}),
    do: g |> spend(seat, @cost.hump, :hump) |> pay(seat, Alchemists.hump_bonus(chip))

  defp spend(g, seat, n, what) do
    g
    |> Game.update_player(seat, &%{&1 | essence: &1.essence - n})
    |> Game.record(seat, {:essence_spent, n, what})
  end
end
