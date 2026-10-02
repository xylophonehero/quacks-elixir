defmodule Quacks.Game.Evaluation do
  @moduledoc """
  Steps A–D of the evaluation phase (rulebook §3.2) for every seat at once, run by
  `Quacks.Game` as soon as the last player is done drawing: bonus die, chip actions
  (black, green, purple; by Ingredient Set), rubies and VP from the scoring space. Then the shop opens.

  Seats are visited in turn order (start player first), so the shared `rng` and the
  log are deterministic.

  Some books need a choice in step B (G2, G4, P2, P4). Step B fills each player's
  `chip_choices`; then the game phase `:chip_choice` gives each seat with a choice
  the `turn`, one after the other from the start seat. A seat acts with `{:chip,
  choice}` (see `legal_actions/2`) and ends with `:chip_done`; its turn also ends
  when nothing is left to choose. Steps C and D run after the last seat. Without such
  a book nobody has a choice and the evaluation runs in one go.
  """

  alias Quacks.Game
  alias Quacks.Game.Fortune
  alias Quacks.Player
  alias Quacks.Rules.PotTrack

  # Rulebook §3.2. ⚠️ Sixth face not in any rulebook found; assumed a second "1 VP".
  @die [{:vp, 1}, {:vp, 1}, {:vp, 2}, :ruby, :droplet, :orange]

  # G2: what a green chip of each value may bring into the bag.
  @g2 %{1 => [{:orange, 1}], 2 => [{:blue, 1}, {:red, 1}], 4 => [{:yellow, 1}, {:purple, 1}]}
  # P4: swaps from a pot chip to a bigger chip of the same colour, with their tier.
  # ⚠️ Only colours with 2- and 4-chips (not white, orange, purple, black).
  @p4 for colour <- [:green, :blue, :red, :yellow],
          {from, to, tier} <- [{1, 2, 1}, {2, 4, 2}, {1, 4, 3}],
          do: {{colour, from}, {colour, to}, tier}

  @doc """
  Die → chip actions → (choices) → scoring space, for every seat; then `:buy_chips`.
  With a choice open, the game waits in `:chip_choice` instead.
  """
  @spec run(Game.t()) :: Game.t()
  def run(g) do
    order = Game.turn_order(g)
    g = bonus_die(g, order)
    g = Enum.reduce(order, g, &chip_actions(&2, &1))
    next_choice(g, order)
  end

  @doc "The `{:chip, choice}` actions and `:chip_done` for the seat whose turn it is."
  @spec legal_actions(Game.t(), Game.seat()) :: [Game.action()]
  def legal_actions(%{phase: :chip_choice, turn: seat} = g, seat),
    do: Enum.map(choices(g, seat), &{:chip, &1}) ++ [:chip_done]

  def legal_actions(_g, _seat), do: []

  @doc "Apply one legal `:chip_choice` action for `seat`. The action is already logged."
  @spec step(Game.t(), Game.seat(), Game.action()) :: Game.t()
  def step(g, seat, :chip_done) do
    g
    |> Game.update_player(seat, &%{&1 | chip_choices: []})
    |> next_choice(Game.seats_after(g, seat))
  end

  def step(g, seat, {:chip, choice}) do
    g = choose(g, seat, choice)
    if choices(g, seat) == [], do: step(g, seat, :chip_done), else: g
  end

  # Give the first of `seats` with a choice the turn; with nobody left, steps C/D.
  defp next_choice(g, seats) do
    case Enum.find(seats, &(choices(g, &1) != [])) do
      nil -> finish(g)
      seat -> %{g | phase: :chip_choice, turn: seat}
    end
  end

  defp finish(g) do
    order = Game.turn_order(g)
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
    die = die(g.rules.die)
    {i, rng} = :rand.uniform_s(length(die), g.rng)
    face = Enum.at(die, i - 1)
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

  # ⚠️ House rule `die: :no_orange`: the orange face is a second ruby face.
  defp die(:standard), do: @die
  defp die(:no_orange), do: Enum.map(@die, &if(&1 == :orange, do: :ruby, else: &1))

  # Step B (§4): black, then green and purple by their Ingredient Set. Set 1 and 3
  # are automatic (Set 1 purple: always the highest tier); Set 2 and 4 open choices.
  # Green first: G3 moves the last chip.
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

  # G2: each green chip on the last two positions may bring one chip (a choice).
  defp chip_action(g, seat, {:green, 2}),
    do: add_choices(g, seat, for({:green, v} <- last_two(g, seat), do: {:gain, v}))

  # G4: pay up to 1 ruby per green chip on the last two positions (a choice).
  defp chip_action(g, seat, {:green, 4}) do
    case count(:green, last_two(g, seat)) do
      0 -> g
      n -> add_choices(g, seat, [{:ruby_move, n}])
    end
  end

  # P2 and P4: a choice whose best tier is the number of purple chips (max 3).
  defp chip_action(g, seat, {:purple, set}) when set in [2, 4] do
    case count(:purple, Game.pot_chips(g, seat)) do
      0 -> g
      n -> add_choices(g, seat, [{if(set == 2, do: :purple_trade, else: :upgrade), min(n, 3)}])
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

  defp last_two(g, seat), do: Enum.take(Game.pot_chips(g, seat), 2)

  defp add_choices(g, seat, choices),
    do: Game.update_player(g, seat, &%{&1 | chip_choices: &1.chip_choices ++ choices})

  # -- step B choices -------------------------------------------------------------------

  # What `seat` may choose now. Gains need the chip in the supply. ⚠️ G2 may bring a
  # yellow or purple chip before that book is in the shop (no ruling; allowed).
  defp choices(g, seat) do
    p = Game.player(g, seat)
    p.chip_choices |> Enum.flat_map(&options(g, p, &1)) |> Enum.uniq()
  end

  defp options(g, _p, {:gain, v}), do: for(chip <- @g2[v], g.supply[chip] > 0, do: {:gain, chip})

  defp options(_g, p, {:ruby_move, n}),
    do: for(k <- 1..min(n, p.rubies)//1, do: {:pay_ruby_move, k})

  defp options(_g, _p, {:purple_trade, tier}), do: for(t <- 1..tier, do: {:purple_trade, t})

  # A lower tier is allowed too.
  defp options(g, p, {:upgrade, tier}) do
    pot = Player.pot_chips(p)

    for {from, to, t} <- @p4, t <= tier, from in pot, g.supply[to] > 0, do: {:upgrade, from, to}
  end

  defp choose(g, seat, {:gain, chip}) do
    {v, _} = Enum.find(@g2, fn {_v, chips} -> chip in chips end)

    g
    |> use_choice(seat, {:gain, v})
    |> Game.add_from_supply(seat, chip)
    |> Game.effect(seat, {:green, 2}, {:gain, chip})
  end

  defp choose(g, seat, {:pay_ruby_move, n}) do
    g
    |> use_choice(seat, &match?({:ruby_move, _}, &1))
    |> Game.update_player(seat, &%{&1 | rubies: &1.rubies - n, droplet: &1.droplet + n})
    |> Game.effect(seat, {:green, 4}, {:droplet, n})
  end

  # P2: `tier` purple chips leave the pot for the supply (⚠️ "discard" read as back to
  # the box) and pay out: 1 → black 1, 1 VP, 1 ruby; 2 → green 1, blue 2, 3 VP,
  # droplet +1; 3 → yellow 4, 6 VP, 1 ruby, droplet +2.
  defp choose(g, seat, {:purple_trade, tier}) do
    {chips, vp, rubies, droplet} =
      case tier do
        1 -> {[{:black, 1}], 1, 1, 0}
        2 -> {[{:green, 1}, {:blue, 2}], 3, 0, 1}
        3 -> {[{:yellow, 4}], 6, 1, 2}
      end

    g = g |> use_choice(seat, &match?({:purple_trade, _}, &1))
    g = Enum.reduce(1..tier, g, fn _, g -> discard(g, seat, {:purple, 1}) end)
    g = Enum.reduce(chips, g, &Game.add_from_supply(&2, seat, &1))

    g
    |> Game.update_player(
      seat,
      &%{&1 | vp: &1.vp + vp, rubies: &1.rubies + rubies, droplet: &1.droplet + droplet}
    )
    |> Game.effect(seat, {:purple, 2}, {:trade, tier})
  end

  # P4: the pot chip goes to the supply, the bigger one straight into the bag.
  defp choose(g, seat, {:upgrade, from, to}) do
    g
    |> use_choice(seat, &match?({:upgrade, _}, &1))
    |> discard(seat, from)
    |> Game.add_from_supply(seat, to)
    |> Game.effect(seat, {:purple, 4}, {:upgrade, from, to})
  end

  # Remove the first open choice that matches (a term or a predicate).
  defp use_choice(g, seat, match) when is_function(match),
    do: Game.update_player(g, seat, &%{&1 | chip_choices: drop_first(&1.chip_choices, match)})

  defp use_choice(g, seat, choice), do: use_choice(g, seat, &(&1 == choice))

  defp drop_first(list, fun) do
    {before, [_ | rest]} = Enum.split_while(list, &(not fun.(&1)))
    before ++ rest
  end

  # The newest `chip` in the pot goes back to the supply.
  defp discard(g, seat, chip) do
    g
    |> Game.update_player(seat, &%{&1 | drawn: List.keydelete(&1.drawn, chip, 0)})
    |> Map.update!(:supply, &Map.update!(&1, chip, fn n -> n + 1 end))
  end

  # Black (§4): compared with the opponent (2 players) or both neighbours (3–4).
  # ⚠️ Solo: no opponent; 1+ black chip pays `rules.black_solo` (default droplet +1).
  defp black(g, seat, mine) do
    others = Enum.map(neighbours(g, seat), &count(:black, Game.pot_chips(g, &1)))

    payoff =
      if others == [] and mine > 0,
        do: g.rules.black_solo,
        else: black_payoff(mine, others)

    case payoff do
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

  # My black chips against the neighbours' counts: one (2p) or two (3–4p).
  defp black_payoff(0, _others), do: nil
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
