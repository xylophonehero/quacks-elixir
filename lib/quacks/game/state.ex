defmodule Quacks.Game.State do
  @moduledoc false
  # The engine's internal helpers on the `Quacks.Game` struct: the seats, the log, the
  # supply, the droplet and the shop. Only the engine (`Quacks.Game` and its
  # submodules), engine tests and the gallery fixtures call them. Callers outside the
  # engine use the reads of `Quacks.Game` (issue #79). This module calls no engine
  # submodule.

  alias Quacks.Player
  alias Quacks.Rules.{Chips, TestTubes}

  @rounds 9
  # Rulebook §4: yellow enters the shop in round 2, purple in round 3.
  @from_round %{yellow: 2, purple: 3}

  def player(%{players: players}, seat), do: Map.fetch!(players, seat)

  def update_player(%{players: players} = g, seat, fun),
    do: %{g | players: Map.update!(players, seat, fun)}

  def record(%{log: log} = g, entry), do: %{g | log: [entry | log]}

  def record(g, seat, entry), do: record(g, {seat, entry})

  # Log a Set 2–6 chip effect: `{seat, {:effect, {colour, set}, detail}}`.
  def effect(g, seat, book, detail), do: record(g, seat, {:effect, book, detail})

  # The seat that starts this round; it rotates one seat per round.
  def start_seat(%{round: round, seats: seats}), do: rem(round - 1, length(seats))

  # The seats from this round's start player round the table.
  def turn_order(%{seats: seats} = g) do
    {before, from} = Enum.split(seats, start_seat(g))
    from ++ before
  end

  # The seat to the left of `seat` (the next seat in turn order); `nil` solo.
  # ⚠️ "Left" read as the next seat clockwise, the direction of play.
  def left(%{seats: [_]}, _seat), do: nil
  def left(%{seats: seats}, seat), do: rem(seat + 1, length(seats))

  # -- the supply ---------------------------------------------------------------------

  # A chip can be bought or taken: its book is out this round and the box has one.
  def available?(%{round: round} = g, {colour, _} = chip),
    do: round >= Map.get(@from_round, colour, 1) and in_supply?(g, chip)

  # The box has `n` of `chip`; an infinite supply always has (if the chip is in the box).
  def in_supply?(g, chip, n \\ 1),
    do: Map.has_key?(g.supply, chip) and (g.rules.supply == :infinite or g.supply[chip] >= n)

  # An infinite supply is never counted: taking and returning leave it as it is.
  def take_supply(%{rules: %{supply: :infinite}} = g, _chip), do: g

  def take_supply(g, chip),
    do: %{g | supply: Map.update!(g.supply, chip, &(&1 - 1))}

  def return_supply(%{rules: %{supply: :infinite}} = g, _chip), do: g

  def return_supply(g, chip),
    do: %{g | supply: Map.update!(g.supply, chip, &(&1 + 1))}

  # Move a chip from the supply into a bag; nothing happens when the box is empty.
  def add_from_supply(g, seat, chip) do
    if in_supply?(g, chip),
      do: g |> take_supply(chip) |> update_player(seat, &%{&1 | bag: [chip | &1.bag]}),
      else: g
  end

  # Black book II: a black chip out of the supply goes into the left player's bag
  # (solo: back to the supply). The caller moves the receiver's droplet.
  def give_black(g, seat) do
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

  # -- the droplet ----------------------------------------------------------------------

  # Move `seat`'s droplet `n` spaces: every chip action, die face, card and book that
  # moves the droplet calls this. Front side: the pot droplet moves now. Reverse side
  # (`pot_side: :back`): the moves wait in `droplet_moves` for the player's
  # `{:droplet, :pot | :tube}` choices; with the test-tube droplet on the last glass,
  # the pot droplet takes them at once. Before the round's first draw the pot's start
  # follows the droplet.
  def move_droplet(g, _seat, 0), do: g

  def move_droplet(g, seat, n) do
    if g.rules.pot_side == :back and player(g, seat).tube < TestTubes.last(),
      do: update_player(g, seat, &%{&1 | droplet_moves: &1.droplet_moves + n}),
      else: update_player(g, seat, &pot_droplet(&1, n))
  end

  # The pot droplet moves `n` spaces; before the first draw the pot's start follows.
  def pot_droplet(%Player{drawn: []} = p, n) do
    p = %{p | droplet: p.droplet + n}
    %{p | pot_index: Player.start_index(p)}
  end

  def pot_droplet(%Player{} = p, n), do: %{p | droplet: p.droplet + n}

  # -- the shop -------------------------------------------------------------------------

  # The seat may still buy chips (and use the copper witches C1, C3): before round 9,
  # once.
  def shop_open?(g, %Player{bought?: bought?}), do: g.round < @rounds and not bought?

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

  def done_buying(g, seat), do: update_player(g, seat, &%{&1 | bought?: true})
end
