defmodule Quacks.Game.Evaluation do
  @moduledoc """
  Steps A–D of the evaluation phase (rulebook §3.2) for every seat at once, run by
  `Quacks.Game` as soon as the last player is done drawing: bonus die, chip actions
  (black, green, purple; by Ingredient Set), rubies and VP from the scoring space. Then the shop opens.

  Seats are visited in turn order (start player first), so the shared `rng` and the
  log are deterministic.
  """

  alias Quacks.Game
  alias Quacks.Game.Fortune
  alias Quacks.Rules.PotTrack

  # Rulebook §3.2. ⚠️ Sixth face not in any rulebook found; assumed a second "1 VP".
  @die [{:vp, 1}, {:vp, 1}, {:vp, 2}, :ruby, :droplet, :orange]

  @doc "Die → chip actions → scoring space, for every seat; then `:buy_chips`."
  @spec run(Game.t()) :: Game.t()
  def run(g) do
    order = Game.turn_order(g)
    g = bonus_die(g, order)
    g = Enum.reduce(order, g, &chip_actions(&2, &1))
    g = Enum.reduce(order, g, &payout(&2, &1))
    g |> Fortune.refill_flasks() |> Game.to_shop(order)
  end

  # Step A: among the non-exploded players the highest scoring space rolls; a true
  # tie means each of them rolls. Exploded players never roll.
  defp bonus_die(g, order) do
    candidates = Enum.reject(order, &Game.player(g, &1).exploded?)
    best = candidates |> Enum.map(&Game.scoring_index(g, &1)) |> Enum.max(fn -> nil end)

    candidates
    |> Enum.filter(&(Game.scoring_index(g, &1) == best))
    |> Enum.flat_map(&List.duplicate(&1, Fortune.die_rolls(g)))
    |> Enum.reduce(g, fn seat, g ->
      {face, g} = roll(g, seat)
      Game.record(g, seat, {:bonus_die, face})
    end)
  end

  @doc false
  # Roll the bonus die for `seat` and pay the face out; the caller logs it.
  def roll(g, seat) do
    {i, rng} = :rand.uniform_s(length(@die), g.rng)
    face = Enum.at(@die, i - 1)
    g = %{g | rng: rng}

    g =
      case face do
        {:vp, n} -> Game.update_player(g, seat, &%{&1 | vp: &1.vp + n})
        :ruby -> Game.update_player(g, seat, &%{&1 | rubies: &1.rubies + 1})
        :droplet -> Game.update_player(g, seat, &%{&1 | droplet: &1.droplet + 1})
        :orange -> Game.add_from_supply(g, seat, {:orange, 1})
      end

    {face, g}
  end

  # Step B (§4): black, then green and purple by their Ingredient Set. All automatic;
  # always the highest purple tier. Green first: G3 moves the last chip.
  defp chip_actions(g, seat) do
    g = black(g, seat, count(:black, Game.pot_chips(g, seat)))
    g = chip_action(g, seat, {:green, g.sets.green})
    chip_action(g, seat, {:purple, g.sets.purple})
  end

  defp chip_action(g, seat, {:green, 1}) do
    case count(:green, Enum.take(Game.pot_chips(g, seat), 2)) do
      0 ->
        g

      n ->
        g
        |> Game.update_player(seat, &%{&1 | rubies: &1.rubies + n})
        |> Game.record(seat, {:green_rubies, n})
    end
  end

  # G3: exactly 7 white → the last chip moves on by the sum of the green values.
  defp chip_action(g, seat, {:green, 3} = book) do
    p = Game.player(g, seat)
    n = for {{:green, v}, _} <- p.drawn, reduce: 0, do: (acc -> acc + v)

    if Game.white_sum(g, seat) == 7 and n > 0 do
      [{chip, index} | rest] = p.drawn
      index = min(index + n, PotTrack.last())

      g
      |> Game.update_player(seat, &%{&1 | drawn: [{chip, index} | rest], pot_index: index})
      |> Game.effect(seat, book, {:moved_last, n})
    else
      g
    end
  end

  defp chip_action(g, seat, {:purple, 1}) do
    case count(:purple, Game.pot_chips(g, seat)) do
      0 ->
        g

      1 ->
        g
        |> Game.update_player(seat, &%{&1 | vp: &1.vp + 1})
        |> Game.record(seat, {:purple, 1, :vp1})

      2 ->
        g
        |> Game.update_player(seat, &%{&1 | vp: &1.vp + 1, rubies: &1.rubies + 1})
        |> Game.record(seat, {:purple, 2, :vp1_ruby})

      _ ->
        g
        |> Game.update_player(seat, &%{&1 | vp: &1.vp + 2, droplet: &1.droplet + 1})
        |> Game.record(seat, {:purple, 3, :vp2_droplet})
    end
  end

  # P3: per purple chip, VP by its pot field: 0–9 → 0, 10–19 → 1, 20–29 → 2, 30+ → 3.
  defp chip_action(g, seat, {:purple, 3} = book) do
    vp =
      for {{:purple, _}, i} <- Game.player(g, seat).drawn,
          reduce: 0,
          do: (acc -> acc + min(div(i, 10), 3))

    if vp > 0,
      do:
        g
        |> Game.update_player(seat, &%{&1 | vp: &1.vp + vp})
        |> Game.effect(seat, book, {:vp, vp}),
      else: g
  end

  # Black (§4): compared with the opponent (2 players) or both neighbours (3–4).
  # ⚠️ Solo house rule: no opponent, so 1+ black chip counts as a tie: droplet +1.
  defp black(g, seat, mine) do
    others = Enum.map(neighbours(g, seat), &count(:black, Game.pot_chips(g, &1)))

    case black_payoff(mine, others) do
      nil ->
        g

      :droplet ->
        g
        |> Game.update_player(seat, &%{&1 | droplet: &1.droplet + 1})
        |> Game.record(seat, {:black, :droplet})

      :droplet_ruby ->
        g
        |> Game.update_player(seat, &%{&1 | droplet: &1.droplet + 1, rubies: &1.rubies + 1})
        |> Game.record(seat, {:black, :droplet_ruby})
    end
  end

  # My black chips against the neighbours' counts: none (solo), one (2p) or two (3–4p).
  defp black_payoff(0, _others), do: nil
  defp black_payoff(_mine, []), do: :droplet
  defp black_payoff(mine, [opp]) when mine > opp, do: :droplet_ruby
  defp black_payoff(mine, [opp]) when mine == opp, do: :droplet
  defp black_payoff(mine, [a, b]) when mine > a and mine > b, do: :droplet_ruby
  defp black_payoff(mine, [a, b]) when mine > a or mine > b, do: :droplet
  defp black_payoff(_mine, _others), do: nil

  # The seats a black chip is compared with: none solo, the other seat with 2, the
  # two adjacent seats with 3 or 4.
  defp neighbours(%{seats: [_]}, _seat), do: []
  defp neighbours(%{seats: seats}, seat) when length(seats) == 2, do: List.delete(seats, seat)

  defp neighbours(%{seats: seats}, seat) do
    n = length(seats)
    [rem(seat + n - 1, n), rem(seat + 1, n)]
  end

  # Steps C and D. An exploded player who chose to buy takes no VP; one who chose VP
  # gets no coins. Coins in round 9 convert to VP in `:end_round`.
  defp payout(g, seat) do
    choice = Game.player(g, seat).explosion_choice
    index = Game.scoring_index(g, seat)
    space = PotTrack.at(index)

    g =
      if space.ruby?,
        do:
          g
          |> Game.update_player(seat, &%{&1 | rubies: &1.rubies + 1})
          |> Game.record(seat, {:pot_ruby, index})
          |> Fortune.ruby_space(seat),
        else: g

    g =
      if choice == :buy or space.vp == 0,
        do: g,
        else:
          g
          |> Game.update_player(seat, &%{&1 | vp: &1.vp + space.vp})
          |> Game.record(seat, {:pot_vp, space.vp, index})

    Game.update_player(g, seat, &%{&1 | coins: if(choice == :vp, do: 0, else: space.coins)})
  end

  defp count(colour, chips), do: Enum.count(chips, &match?({^colour, _}, &1))
end
