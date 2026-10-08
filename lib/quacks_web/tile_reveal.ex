defmodule QuacksWeb.TileReveal do
  @moduledoc """
  Round 27 (experimental, branch `round-27-eval`): the evaluation played on the
  player tiles instead of the reveal overlay (the Reveal setting "On tiles").

  Pure functions over the overlay's own slides (`QuacksWeb.Reveal.slides/2`) and
  the log, never new engine data. The tiles play the scoring steps only (the bonus
  die, the books, the scoring space): at each step every tile shows what its seat
  got as a small badge (`badges/2`), and the tile's VP and rubies show the running
  totals after the step (`totals/2`). The die face stays on the roller's tile until
  the next round (`rolls/2`); in the shop the chips a seat bought and its droplet
  pushes show on its tile (`shop/2`).
  """

  alias Quacks.Game
  alias QuacksWeb.{Replay, Reveal}

  # The overlay's slides the tiles play; the results table and the standings are
  # the tiles themselves.
  @kinds [:die, :book, :space]

  # A step on the tiles lasts this many beats (`--beat-ms`, the Speed setting).
  @beats 5

  @type badge ::
          {:vp, pos_integer}
          | {:rubies, pos_integer}
          | {:droplet, pos_integer}
          | {:coins, non_neg_integer}
          | {:chip, atom}
          | {:book, atom}

  @doc "The overlay's slides that the tiles play (the scoring steps)."
  @spec slides([Reveal.slide()]) :: [Reveal.slide()]
  def slides(slides), do: Enum.filter(slides, &(&1.kind in @kinds))

  @doc "How long a step stays on the tiles in Auto mode, in ms, at `speed`."
  @spec duration(atom) :: pos_integer
  def duration(speed), do: Reveal.beat_ms(speed) * @beats

  @doc """
  The step's name for the stage pill: "Bonus die", "Black book", "Ruby space", ...
  """
  @spec label(Reveal.slide()) :: String.t()
  def label(%{kind: :die}), do: "Bonus die"
  def label(%{kind: :book, book: colour}), do: "#{String.capitalize(to_string(colour))} book"
  def label(%{kind: :space}), do: "Scoring space"

  @doc """
  What `seat` got in this step, as badges: the book's ingredient and its VP,
  rubies and droplet moves; the scoring space's VP and ruby (its coins are the
  tile's pot space already). The die slide
  gives no badge: its face shows by the crown (`rolls/2`). Nothing gained, no
  badge.
  """
  @spec badges(Reveal.slide(), Game.seat()) :: [badge]
  def badges(%{kind: :book, book: colour, rows: rows}, seat) do
    case Enum.find(rows, &(&1.seat == seat)) do
      %{scored: true} = row ->
        rewards = rewards(row)
        [{:book, colour} | if(rewards == [], do: [{:chip, colour}], else: rewards)]

      _row ->
        []
    end
  end

  def badges(%{kind: :space, rows: rows}, seat) do
    case Enum.find(rows, &(&1.seat == seat)) do
      nil -> []
      row -> row |> Map.put(:droplet, 0) |> rewards()
    end
  end

  def badges(_slide, _seat), do: []

  defp rewards(row) do
    for {kind, n} <- [vp: row.vp, rubies: row.rubies, droplet: row.droplet], n > 0, do: {kind, n}
  end

  @doc """
  Every seat's `{vp, rubies}` after the step `index` of `slides`: the totals before
  the round's results (`Replay.before/2`) plus the gains of the steps so far.
  """
  @spec totals(Game.t(), [Reveal.slide()], non_neg_integer) :: %{
          Game.seat() => {integer, integer}
        }
  def totals(game, slides, index) do
    base =
      Map.new(game.seats, fn s ->
        %{vp: vp, rubies: rubies} = Replay.before(game, s)
        {s, {vp, rubies}}
      end)

    slides
    |> Enum.take(index + 1)
    |> Enum.flat_map(&Map.to_list(Map.get(&1, :gains, %{})))
    |> Enum.reduce(base, fn {s, {vp, rubies}}, acc ->
      Map.update(acc, s, {vp, rubies}, fn {v, r} -> {v + vp, r + rubies} end)
    end)
  end

  @doc """
  Every seat's droplet position after the step `index` of `slides`: the droplet
  now less the moves of the steps still to come (a die's droplet face, a book's
  droplet move).
  """
  @spec droplets(Game.t(), [Reveal.slide()], integer) :: %{Game.seat() => non_neg_integer}
  def droplets(game, slides, index) do
    later = Enum.drop(slides, index + 1)

    Map.new(game.seats, fn s ->
      moves = later |> Enum.map(&droplet_moves(&1, s)) |> Enum.sum()
      {s, max(Game.player(game, s).droplet - moves, 0)}
    end)
  end

  defp droplet_moves(%{kind: :die, rows: rows}, seat) do
    case Enum.find(rows, &(&1.seat == seat)) do
      %{rolls: rolls} -> Enum.count(rolls, &(&1.face == :droplet))
      _row -> 0
    end
  end

  defp droplet_moves(%{kind: :book, rows: rows}, seat) do
    case Enum.find(rows, &(&1.seat == seat)) do
      %{scored: true, droplet: n} -> n
      _row -> 0
    end
  end

  defp droplet_moves(_slide, _seat), do: 0

  @doc """
  Round 28: the news on `seat`'s tile, for its bottom line (R2), or nil. While a
  step plays (`reveal` with `tiles: true`): the die faces the seat rolled, or the
  step's badges (`badges/2`). Else the chips the seat bought and its droplet
  pushes (`shop/2`: in the shop, or the last shop as the next round begins). `key` changes with every new piece of news, so the
  line plays its swap again.
  """
  @spec news(Game.t(), Game.seat(), map | nil) :: %{key: String.t(), items: [term]} | nil
  def news(game, seat, %{tiles: true, slides: slides, index: index}) do
    slide = Enum.at(slides, index)
    items = step_news(slide, seat)
    if items != [], do: %{key: "#{game.round}-#{index}", items: items}
  end

  # A card on screen (the overlay): its news waits until it is dismissed.
  def news(_game, _seat, %{key: {:card, _}}), do: nil

  def news(game, seat, _reveal) do
    %{chips: chips, droplets: droplets} = shop(game, seat)
    flea = flea(game, seat)

    items =
      Enum.map(chips, &{:bought, &1}) ++
        if(droplets > 0, do: [{:droplet, droplets}], else: []) ++ flea

    round = if game.phase == :shopping, do: game.round, else: game.round - 1

    if items != [],
      do: %{key: "#{round}-shop-#{length(chips)}-#{droplets}-#{length(flea)}", items: items}
  end

  # Round 28: Flea Market (P13): the chip `seat` traded and the chip it got, once
  # chosen (`Quacks.Game.Fortune.flea_market/1`).
  defp flea(game, seat) do
    case Quacks.Game.Fortune.flea_market(game)[seat] do
      %{choosing?: false, got: got, traded: traded} when got != nil -> [{:flea, traded, got}]
      _other -> []
    end
  end

  defp step_news(%{kind: :die, rows: rows}, seat) do
    case Enum.find(rows, &(&1.seat == seat)) do
      %{rolls: rolls} -> for %{face: face} <- rolls, face != nil, do: {:die, face}
      _row -> []
    end
  end

  defp step_news(slide, seat), do: badges(slide, seat)

  @doc "The bonus die faces `seat` rolled this round (empty before the evaluation)."
  @spec rolls(Game.t(), Game.seat()) :: [term]
  def rolls(%Game{phase: :shopping} = game, seat) do
    for %{kind: :die, face: face} <- Replay.beats(game, seat), face != nil, do: face
  end

  def rolls(_game, _seat), do: []

  @doc """
  What `seat` did in the shop: the chips it bought (oldest first) and how often it
  pushed the droplet with rubies. In the shop phase this round's shop so far; later
  (round 28) the last round's shop, since the bots' buys show only once the last
  human is done, as the next round begins. Empty in round 1 before the shop.
  """
  @spec shop(Game.t(), Game.seat()) :: %{
          chips: [Quacks.Rules.Chips.chip()],
          droplets: non_neg_integer
        }
  def shop(%Game{phase: :shopping, log: log}, seat),
    do: shop_entries(Enum.take_while(log, &(not round_end?(&1))), seat)

  def shop(%Game{log: log}, seat) do
    log
    |> Enum.drop_while(&(not round_end?(&1)))
    |> Enum.drop(1)
    |> Enum.take_while(&(not round_end?(&1)))
    |> shop_entries(seat)
  end

  defp round_end?(entry), do: match?({:round_end, _}, entry)

  defp shop_entries(round, seat) do
    %{
      chips: for({^seat, {:bought, chips}} <- Enum.reverse(round), chip <- chips, do: chip),
      droplets: Enum.count(round, &droplet?(&1, seat))
    }
  end

  defp droplet?({seat, {:rubies_spent, :droplet}}, seat), do: true
  defp droplet?({seat, {:rubies_spent, :droplet, _price}}, seat), do: true
  defp droplet?(_entry, _seat), do: false
end
