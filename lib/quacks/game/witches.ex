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
  - **copper**, shop: in the seat's `:buy` sub-phase of `:shopping` (C2 and C4 also in
    round 9's `:rubies` sub-phase, before the coins become VP);
  - **gold**, evaluation: G1–G3 in the game phase `:witch_choice` (after step B, before
    steps C/D; seat by seat, only seats she helps), G4 in the `:rubies` sub-phase.

  Actions: `{:witch, colour}` calls a witch that needs no choice; `{:witch, colour,
  choice}` calls one with a choice (S3 `1 | 2`, C1 `{:upgrade, chips}`, C3 `{:buy,
  chips, copy}`). S2's offer is placed with `{:witch, :silver, {:place, chip}}` and
  ended with `{:witch, :silver, :return_all}` (the penny is already spent then).
  `:witch_done` passes in `:witch_choice`. Every call logs `{seat, {:witch, id,
  outcome}}`.
  """

  alias Quacks.Game
  alias Quacks.Game.{Evaluation, Potions}
  alias Quacks.Player
  alias Quacks.Rules.PotTrack

  # C1: one level up. ⚠️ Only colours with 2- and 4-chips (not white, orange, locoweed).
  @upgrade for c <- [:green, :blue, :red, :yellow],
               {from, to} <- [{1, 2}, {2, 4}],
               into: %{},
               do: {{c, from}, {c, to}}

  # G1: VP by the number of different colours in the pot (white not counted).
  @g1 %{1 => 3, 2 => 3, 3 => 3, 4 => 3, 5 => 4, 6 => 7, 7 => 10, 8 => 14}

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

    offer ++ called
  end

  # Is it the right moment for a witch of this colour?
  defp now?(%{phase: :potions}, _seat, p, :silver),
    do: p.phase in [:potions, :explosion_choice] and p.witch_offer == []

  defp now?(%{phase: :shopping}, _seat, %{phase: :buy}, :copper), do: true
  defp now?(%{phase: :shopping, round: 9}, _seat, %{phase: :rubies}, :copper), do: true
  defp now?(%{phase: :shopping}, _seat, %{phase: :rubies}, :gold), do: true
  defp now?(%{phase: :witch_choice, turn: seat}, seat, _p, :gold), do: true

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

  defp actions(g, %{phase: :buy} = p, :c1),
    do: for(chips <- upgrades(g, p), do: {:witch, :copper, {:upgrade, chips}})

  defp actions(_g, %{coins: coins}, :c2) when coins > 0, do: [{:witch, :copper}]

  defp actions(g, %{phase: :buy} = p, :c3) do
    for chips <- Game.buys(g, p.coins),
        copy <- Enum.uniq(chips),
        Game.in_supply?(g, copy, Enum.count(chips, &(&1 == copy)) + 1),
        do: {:witch, :copper, {:buy, chips, copy}}
  end

  defp actions(_g, %{rubies: rubies}, :c4) when rubies > 0, do: [{:witch, :copper}]

  defp actions(%{phase: :witch_choice} = g, p, id) when id in [:g1, :g2, :g3],
    do: if(gold_gain(g, p, id) > 0, do: [{:witch, :gold}], else: [])

  defp actions(_g, %{phase: :rubies}, :g4), do: [{:witch, :gold}]
  defp actions(_g, _p, _id), do: []

  @doc """
  An exploded player who took the VP skips the shop, unless the copper witch C1 or
  C4 still gives them something to do there.
  """
  @spec shop_turn?(Game.t(), Game.seat()) :: boolean
  def shop_turn?(%{witches: nil}, _seat), do: false

  def shop_turn?(g, seat) do
    p = Game.player(g, seat)
    id = g.witches.copper

    p.pennies[:copper] == true and id in [:c1, :c4] and
      actions(g, %{p | phase: :buy}, id) != []
  end

  @doc """
  After the step-B choices: give the first of `seats` that a gold witch G1–G3 helps
  the `:witch_choice` turn; with nobody left, steps C/D (`Evaluation.score/1`).
  """
  @spec gold_turn(Game.t(), [Game.seat()]) :: Game.t()
  def gold_turn(g, seats) do
    turn = fn seat -> %{g | phase: :witch_choice, turn: seat} end

    case Enum.find(seats, &(legal_actions(turn.(&1), &1) != [])) do
      nil -> Evaluation.score(g)
      seat -> turn.(seat)
    end
  end

  @doc "Apply one legal witch action for `seat`. The action is already logged."
  @spec step(Game.t(), Game.seat(), Game.action()) :: Game.t()
  def step(g, seat, :witch_done), do: gold_turn(g, Game.seats_after(g, seat))

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
    do: g |> spend(seat, colour) |> call(seat, g.witches[colour])

  def step(g, seat, {:witch, colour, choice}),
    do: g |> spend(seat, colour) |> call(seat, g.witches[colour], choice)

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

    g
    |> log(seat, id, if(id == :g3, do: {:rubies, n}, else: {:vp, n}))
    |> gold_turn(Game.seats_after(g, seat))
  end

  # G4: 1 ruby per droplet or flask for the rest of this `:rubies` sub-phase.
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
  defp call(g, seat, :c1, {:upgrade, chips}) do
    chips
    |> Enum.reduce(g, fn chip, g ->
      g
      |> Game.update_player(seat, &%{&1 | drawn: List.keydelete(&1.drawn, chip, 0)})
      |> Game.return_supply(chip)
      |> Game.add_from_supply(seat, @upgrade[chip])
    end)
    |> log(seat, :c1, {:upgrade, chips})
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

  defp log(g, seat, id, outcome), do: Game.record(g, seat, {:witch, id, outcome})
end
