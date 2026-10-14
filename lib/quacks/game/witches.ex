defmodule Quacks.Game.Witches do
  @moduledoc """
  The herb witches of The Herb Witches (`docs/research/herb-witches.md` §2.1; card
  data in `Quacks.Rules.Witches`).

  `Quacks.Game.new/1` turns up one witch per penny colour (`game.witches`) and gives
  every player 3 pennies (`Quacks.Player.pennies`). A player calls a witch by
  spending the penny of her colour, once per game. Unused pennies are 2 VP each at the
  end. When a witch may be called depends on her colour:

  - **silver**, potions phase: S2 (draw 6) and S3 (whites back) while brewing, S1
    (flask) and S4 (no penalty) in the explosion choice;
  - **copper**, shop: C1 (upgrade) in the seat's own `:upgrade` sub-phase of
    `:shopping`, before the shop (round 45: the pot chips are still in view there;
    `:skip_upgrade` passes); C2–C4 in the `:shop` sub-phase, before it buys (C2 and
    C4 also in round 9, before the coins become VP);
  - **gold**, evaluation: G1–G3 in the game phase `:witch_choice` (after step B, before
    steps C/D; every seat she helps at the same time), G4 in the `:upgrade` and `:shop`
    sub-phases before round 9.

  Actions: `{:witch, colour}` calls a witch that needs no choice; `{:witch, colour,
  choice}` calls one with a choice (S3 `1 | 2`, C1 `{:upgrade, chips}`, C3 `{:buy,
  chips, copy}`). S2's offer is placed with `{:witch, :silver, {:place, chip}}` and
  ended with `{:witch, :silver, :return_all}` (the penny is already spent then).
  `:witch_done` passes in `:witch_choice`, `:skip_upgrade` in `:upgrade`. Every call logs `{seat, {:witch, id,
  outcome}}`.

  AB8 Visit from a witch (`docs/research/alchemists-fortune-cards.md` §6): when the
  card comes up, `visit/1` draws one witch at random from the 9 not in
  `game.witches` (any colour) into `game.visitor`. This round every seat may call
  her once, without a penny, at the moment her colour allows: `{:witch, :visit}` and
  `{:witch, :visit, choice}` (the same choices as her own colour's).
  `game.visited` holds the seats that called her; the pennies stay as they are. She leaves at the
  end of the round (`leave/1`). A seat may call both gold witches in
  `:witch_choice`: it decides until no gold call is left or it passes.
  """

  alias Quacks.Game
  alias Quacks.Game.{Evaluation, Potions}
  alias Quacks.Player
  alias Quacks.Rules.PotTrack
  alias Quacks.Rules.Witches, as: WitchCards

  # C1: one level up. ⚠️ Only colours with 2- and 4-chips (not white, orange, locoweed).
  @upgrade for c <- [:green, :blue, :red, :yellow],
               {from, to} <- [{1, 2}, {2, 4}],
               into: %{},
               do: {{c, from}, {c, to}}

  # G1: VP by the number of different colours in the pot (white not counted).
  @g1 %{1 => 3, 2 => 3, 3 => 3, 4 => 3, 5 => 4, 6 => 7, 7 => 10, 8 => 14}

  @doc "C1: the chip one level up from `chip` (nil: C1 cannot upgrade it)."
  @spec upgrade(Quacks.Rules.Chips.chip()) :: Quacks.Rules.Chips.chip() | nil
  def upgrade(chip), do: @upgrade[chip]

  @doc "Every witch action `seat` may take now (`[]` in the base game)."
  @spec legal_actions(Game.t(), Game.seat()) :: [Game.action()]
  def legal_actions(%{witches: nil}, _seat), do: []

  def legal_actions(g, seat) do
    p = Game.player(g, seat)

    offer =
      if p.witch_offer != [] and g.phase == :potions and p.phase == :potions,
        do:
          Enum.map(Enum.sort(Enum.uniq(p.witch_offer)), &{:witch, :silver, {:place, &1}}) ++
            [{:witch, :silver, :return_all}],
        else: []

    called =
      for {colour, id} <- Enum.sort_by(g.witches, &elem(&1, 0)),
          p.pennies[colour],
          now?(g, seat, p, colour),
          action <- actions(g, p, id),
          do: action

    offer ++ called ++ visit_actions(g, seat, p)
  end

  # AB8: the visiting witch, once per seat, at her colour's moment, for free.
  defp visit_actions(%{visitor: nil}, _seat, _p), do: []

  defp visit_actions(%{visitor: id} = g, seat, p) do
    if seat not in g.visited and now?(g, seat, p, WitchCards.card(id).colour),
      do: Enum.map(actions(g, p, id), &as_visit/1),
      else: []
  end

  defp as_visit({:witch, _colour}), do: {:witch, :visit}
  defp as_visit({:witch, _colour, choice}), do: {:witch, :visit, choice}

  @doc """
  AB8 Visit from a witch: one witch not in `game.witches` (any colour), drawn with
  the game's `rng`, visits this round (`game.visitor`, logged `{:visitor, id}`).
  Without The Herb Witches nothing happens.
  """
  @spec visit(Game.t()) :: Game.t()
  def visit(%{witches: nil} = g), do: g

  def visit(g) do
    free = WitchCards.ids() -- Map.values(g.witches)
    {i, rng} = :rand.uniform_s(length(free), g.rng)
    id = Enum.at(free, i - 1)
    Game.record(%{g | visitor: id, visited: [], rng: rng}, {:visitor, id})
  end

  @doc "The end of the round: the visiting witch leaves (`{:visitor_left, id}`)."
  @spec leave(Game.t()) :: Game.t()
  def leave(%{visitor: nil} = g), do: g

  def leave(%{visitor: id} = g),
    do: Game.record(%{g | visitor: nil, visited: []}, {:visitor_left, id})

  # Is it the right moment for a witch of this colour?
  defp now?(%{phase: :potions}, _seat, p, :silver),
    do: p.phase in [:potions, :explosion_choice] and p.witch_offer == []

  defp now?(%{phase: :shopping}, _seat, %{phase: phase}, colour)
       when colour in [:copper, :gold] and phase in [:upgrade, :shop],
       do: true

  defp now?(%{phase: :witch_choice}, _seat, %{phase: :witch_choice}, :gold), do: true

  defp now?(_g, _seat, _p, _colour), do: false

  # The actions of witch `id` for `p`, already at the right moment for her colour.
  defp actions(_g, %{phase: :explosion_choice} = p, :s1),
    do: if(p.flask and Potions.last_white?(p), do: [{:witch, :silver}], else: [])

  defp actions(_g, %{phase: :potions, bag: [_ | _]}, :s2), do: [{:witch, :silver}]

  defp actions(_g, %{phase: :potions} = p, :s3) do
    case Enum.count(p.drawn, &match?({{:white, _}, _}, &1)) do
      0 -> []
      1 -> [{:witch, :silver, 1}]
      _ -> [{:witch, :silver, 1}, {:witch, :silver, 2}]
    end
  end

  defp actions(_g, %{phase: :explosion_choice}, :s4), do: [{:witch, :silver}]

  # Round 45: C1 has her own step before the shop (`:upgrade`), where the pot is in view.
  defp actions(g, %{phase: :upgrade} = p, :c1),
    do: if(Game.shop_open?(g, p), do: copper(g, p, :c1), else: [])

  # C3 belongs to the buy; C2 and C4 too, and in round 9 before the conversion.
  defp actions(g, %{phase: :shop} = p, id) when id in [:c2, :c3, :c4] do
    if Game.shop_open?(g, p) or (g.round == 9 and id in [:c2, :c4]),
      do: copper(g, p, id),
      else: []
  end

  defp actions(%{phase: :witch_choice} = g, p, id) when id in [:g1, :g2, :g3],
    do: if(gold_gain(g, p, id) > 0, do: [{:witch, :gold}], else: [])

  # G4 cheapens droplet and flask, which round 9 no longer offers. The rubies are
  # legal in `:upgrade` too (the results' rubies step), so she is.
  defp actions(%{round: round}, %{phase: phase}, :g4)
       when round < 9 and phase in [:upgrade, :shop],
       do: [{:witch, :gold}]

  defp actions(_g, _p, _id), do: []

  defp copper(g, p, :c1),
    do: for(chips <- upgrades(g, p), do: {:witch, :copper, {:upgrade, chips}})

  defp copper(_g, %{coins: coins}, :c2) when coins > 0, do: [{:witch, :copper}]

  defp copper(g, p, :c3) do
    for chips <- Game.buys(g, p.coins),
        copy <- Enum.uniq(chips),
        Game.in_supply?(g, copy, Enum.count(chips, &(&1 == copy)) + 1),
        do: {:witch, :copper, {:buy, chips, copy}}
  end

  defp copper(_g, %{rubies: rubies}, :c4) when rubies > 0, do: [{:witch, :copper}]
  defp copper(_g, _p, _id), do: []

  @doc """
  After the step-B choices: every seat that a gold witch G1–G3 helps decides now, at
  the same time (game and player phase `:witch_choice`); with nobody, steps C/D
  (`Evaluation.score/1`).
  """
  @spec open_gold(Game.t()) :: Game.t()
  def open_gold(g) do
    g = %{g | phase: :witch_choice}

    g.seats
    |> Enum.reduce(g, fn seat, g ->
      asked = Game.update_player(g, seat, &%{&1 | phase: :witch_choice})
      if legal_actions(asked, seat) != [], do: asked, else: g
    end)
    |> close_gold()
  end

  # Once no seat decides any more: steps C/D.
  defp close_gold(g) do
    if Enum.any?(g.seats, &(Game.player(g, &1).phase == :witch_choice)),
      do: g,
      else: Evaluation.score(g)
  end

  defp gold_done(g, seat),
    do: g |> Game.update_player(seat, &%{&1 | phase: :done}) |> close_gold()

  @doc """
  Round 45: the copper witch C1 (own or visiting) has her own step before the shop.
  A seat she can help now starts the shop in `:upgrade` (C1 or `:skip_upgrade`,
  then `:shop`); every other seat starts in `:shop`.
  """
  @spec open_upgrade(Game.t(), Game.seat()) :: Game.t()
  def open_upgrade(%{witches: nil} = g, _seat), do: g

  def open_upgrade(g, seat) do
    asked = Game.update_player(g, seat, &%{&1 | phase: :upgrade})
    if Enum.any?(legal_actions(asked, seat), &upgrade?/1), do: asked, else: g
  end

  defp upgrade?({:witch, _colour, {:upgrade, _chips}}), do: true
  defp upgrade?(_action), do: false

  @doc "Apply one legal witch action for `seat`. The action is already logged."
  @spec step(Game.t(), Game.seat(), Game.action()) :: Game.t()
  def step(g, seat, :witch_done), do: gold_done(g, seat)
  def step(g, seat, :skip_upgrade), do: to_shop(g, seat)

  # S2's offer: one chip goes in the pot with its action. An explosion ends the offer.
  def step(g, seat, {:witch, :silver, {:place, chip}}) do
    g =
      g
      |> Game.update_player(seat, &%{&1 | witch_offer: List.delete(&1.witch_offer, chip)})
      |> Potions.resolve_draw(seat, chip)

    if Game.player(g, seat).exploded?, do: return_offer(g, seat), else: g
  end

  def step(g, seat, {:witch, :silver, :return_all}), do: return_offer(g, seat)

  def step(g, seat, {:witch, colour}),
    do: g |> spend(seat, colour) |> call(seat, witch(g, colour))

  def step(g, seat, {:witch, colour, choice}),
    do: g |> spend(seat, colour) |> call(seat, witch(g, colour), choice)

  defp witch(g, :visit), do: g.visitor
  defp witch(g, colour), do: g.witches[colour]

  # The visiting witch costs no penny: the seat's one visit is used.
  defp spend(g, seat, :visit), do: %{g | visited: [seat | g.visited]}

  defp spend(g, seat, colour),
    do: Game.update_player(g, seat, &%{&1 | pennies: %{&1.pennies | colour => false}})

  # S1: the flask after the explosion; the player brews on.
  defp call(g, seat, :s1) do
    g
    |> Game.update_player(seat, &%{&1 | flask: false, exploded?: false, phase: :potions})
    |> Potions.take_back(seat)
    |> log(seat, :s1, :flask)
  end

  # S2: up to 6 chips out of the bag as an offer.
  defp call(g, seat, :s2) do
    {offer, g} = Potions.take_random(g, seat, 6)

    g
    |> Game.update_player(seat, &%{&1 | witch_offer: offer})
    |> log(seat, :s2, {:offer, length(offer)})
  end

  # S4: VP and coins after the explosion, and the bonus die (`explosion_choice: :witch`).
  defp call(g, seat, :s4) do
    g
    |> Game.update_player(seat, &%{&1 | explosion_choice: :witch})
    |> log(seat, :s4, :no_penalty)
    |> Potions.finish(seat)
  end

  defp call(g, seat, :c2) do
    g = Game.update_player(g, seat, &%{&1 | coins: 2 * &1.coins})
    log(g, seat, :c2, {:coins, Game.player(g, seat).coins})
  end

  defp call(g, seat, :c4) do
    n = 2 * Game.player(g, seat).rubies

    g
    |> Game.update_player(seat, &%{&1 | coins: &1.coins + n})
    |> log(seat, :c4, {:coins, n})
  end

  defp call(g, seat, id) when id in [:g1, :g2, :g3] do
    n = gold_gain(g, Game.player(g, seat), id)

    g =
      case id do
        :g3 -> Game.update_player(g, seat, &%{&1 | rubies: &1.rubies + n})
        _ -> Game.update_player(g, seat, &%{&1 | vp: &1.vp + n})
      end

    g = log(g, seat, id, if(id == :g3, do: {:rubies, n}, else: {:vp, n}))

    # AB8: the visiting gold witch may still be there for this seat (or the own one).
    if legal_actions(g, seat) == [], do: gold_done(g, seat), else: g
  end

  # G4: 1 ruby per droplet or flask for the rest of this shop.
  defp call(g, seat, :g4),
    do: g |> Game.update_player(seat, &%{&1 | ruby_price: 1}) |> log(seat, :g4, :ruby_price)

  # S3: the newest `n` white chips in the pot go back in the bag; their spaces stay
  # empty and the next chip counts from the newest chip left (as the mandrake does).
  # ⚠️ Returning 1 returns the newest white; bowl whites are not "in your pot".
  defp call(g, seat, :s3, n) do
    p = Game.player(g, seat)
    whites = p.drawn |> Enum.filter(&match?({{:white, _}, _}, &1)) |> Enum.take(n)
    drawn = p.drawn -- whites

    g =
      Game.update_player(g, seat, &%{&1 | drawn: drawn, pot_index: Potions.last_index(drawn, p)})

    whites
    |> Enum.reduce(g, fn {chip, _}, g -> Potions.return_to_bag(g, seat, chip) end)
    |> log(seat, :s3, {:return_white, n})
  end

  # C1: each chip leaves the pot for the supply; the next level up goes in the bag.
  # Then the seat's shop opens.
  defp call(g, seat, :c1, {:upgrade, chips}) do
    chips
    |> Enum.reduce(g, fn chip, g ->
      g
      |> Game.update_player(seat, &%{&1 | drawn: List.keydelete(&1.drawn, chip, 0)})
      |> Game.return_supply(chip)
      |> Game.add_from_supply(seat, @upgrade[chip])
    end)
    |> log(seat, :c1, {:upgrade, chips})
    |> to_shop(seat)
  end

  # C3: buy `chips` and take one more `copy` for free; the seat's buying ends.
  defp call(g, seat, :c3, {:buy, chips, copy}) do
    g
    |> Game.buy(seat, chips, [copy])
    |> log(seat, :c3, {:copy, copy})
    |> Game.done_buying(seat)
  end

  # C1 choices: one upgradable pot chip, or the last two chips when both are.
  defp upgrades(g, p) do
    pot = Player.pot_chips(p)
    ok? = fn chips -> Enum.all?(chips, &Map.has_key?(@upgrade, &1)) and in_supply?(g, chips) end
    ones = for chip <- Enum.sort(Enum.uniq(pot)), ok?.([chip]), do: [chip]

    case Enum.take(pot, 2) do
      [_, _] = last_two -> if ok?.(last_two), do: ones ++ [last_two], else: ones
      _ -> ones
    end
  end

  defp in_supply?(g, chips) do
    chips
    |> Enum.map(&@upgrade[&1])
    |> Enum.frequencies()
    |> Enum.all?(fn {chip, n} -> Game.in_supply?(g, chip, n) end)
  end

  # What a gold witch G1–G3 would give `p` now: VP (G1, G2) or rubies (G3).
  # ⚠️ G1: not for an exploded player who chose to buy (G2 and G3 say they are).
  defp gold_gain(_g, p, :g1) do
    colours =
      p |> Player.pot_chips() |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> List.delete(:white)

    if p.explosion_choice == :buy, do: 0, else: Map.get(@g1, length(colours), 0)
  end

  # G2: 2 VP per coloured 2/4/6-chip, purple and locoweed chip in the bag.
  defp gold_gain(_g, p, :g2) do
    2 *
      Enum.count(p.bag, fn {colour, value} ->
        colour in [:purple, :locoweed] or (colour not in [:white, :black] and value >= 2)
      end)
  end

  # G3: as many rubies as the scoring space shows VP. ⚠️ They replace the space's own
  # ruby (step C still pays that one, so the witch adds VP - 1); with B11 both count.
  defp gold_gain(_g, p, :g3) do
    space = PotTrack.at(Player.scoring_index(p))
    if space.ruby?, do: max(space.vp - 1, 0), else: 0
  end

  defp return_offer(g, seat) do
    offer = Game.player(g, seat).witch_offer
    g = Game.update_player(g, seat, &%{&1 | witch_offer: []})
    Enum.reduce(offer, g, &Potions.return_to_bag(&2, seat, &1))
  end

  defp to_shop(g, seat), do: Game.update_player(g, seat, &%{&1 | phase: :shop})

  defp log(g, seat, id, outcome), do: Game.record(g, seat, {:witch, id, outcome})
end
