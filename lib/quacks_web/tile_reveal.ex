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
  alias Quacks.Game.Fortune
  alias QuacksWeb.{Replay, Reveal}

  # The overlay's slides the tiles play; the results table and the standings are
  # the tiles themselves.
  # Round 35: the standings slide too, as the last step ("Round scored").
  # Round 37 (item 4): no more. "Round scored" is the last step of the recap at the
  # next round's start, after the shop step (`Reveal.recap_slides/1`).
  @kinds [:die, :book, :space]

  # A step on the tiles lasts this many beats (`--beat-ms`, the Speed setting).
  @beats 5

  # One roll of the bonus die in beats (app.css `--die-roll`).
  @die_roll_beats 1.5556

  @type badge ::
          {:vp, pos_integer}
          | {:rubies, pos_integer}
          | {:droplet, pos_integer}
          | {:coins, non_neg_integer}
          | {:chip, atom}
          | {:book, atom}

  @doc """
  The overlay's slides that the tiles play (the scoring steps). Round 35: the
  scoring space is one step again (its coins, VP and ruby in one row each).
  """
  @spec slides([Reveal.slide()]) :: [Reveal.slide()]
  def slides(slides), do: Enum.filter(slides, &(&1.kind in @kinds))

  # The evaluation's choice phases: the steps play on the tiles from then on.
  @eval_phases [:chip_choice, :witch_choice]

  @doc """
  Round 35 (item 7): the steps to play now, from the round's result slides
  (`Reveal.result_slides/1`). In the shop: `slides/1`. While the evaluation asks
  its choices (`evaluating?/1`) the scoring space and "Round scored" are not
  there yet, and a book whose choice a seat still makes has its step already
  (no rows yet), in its place: die, black, green, purple, the other books.
  """
  @spec live(Game.t(), [Reveal.slide()]) :: [Reveal.slide()]
  def live(game, slides) do
    slides = slides(slides)

    if evaluating?(game) do
      slides = Enum.reject(slides, &(&1.kind in [:space, :standings]))
      have = for %{kind: :book, book: c} <- slides, do: c

      waiting =
        for c <- [:green, :purple],
            c not in have,
            choosing(game, c) != [],
            do: %{kind: :book, book: c, set: Map.get(game.sets, c, 1), rows: [], gains: %{}}

      Enum.sort_by(slides ++ waiting, &rank/1)
    else
      slides
    end
  end

  @doc "Whether the evaluation still asks its choices (the shop has not opened)."
  @spec evaluating?(Game.t()) :: boolean
  def evaluating?(%Game{phase: phase}), do: phase in @eval_phases

  defp rank(%{kind: :die}), do: 0
  defp rank(%{kind: :book, book: :black}), do: 1
  defp rank(%{kind: :book, book: :green}), do: 2
  defp rank(%{kind: :book, book: :purple}), do: 3
  defp rank(%{kind: :book}), do: 4
  defp rank(%{kind: :space}), do: 5
  defp rank(_slide), do: 6

  @doc "The seats that still choose in the book of `colour` (G2, G4, G5; P2, P4, P5)."
  @spec choosing(Game.t(), atom) :: [Game.seat()]
  def choosing(game, colour) do
    for s <- game.seats,
        p = Game.player(game, s),
        p.phase == :chip_choice,
        Enum.any?(p.chip_choices, &(choice_colour(&1) == colour)),
        do: s
  end

  @doc "The book colour of a chip actions' choice or `{:chip, choice}` action, or nil."
  @spec choice_colour(term) :: atom | nil
  def choice_colour({:chip, choice}), do: choice_colour(choice)

  def choice_colour({kind, _}) when kind in [:gain, :ruby_move, :pay_ruby_move, :starter],
    do: :green

  def choice_colour({kind, _}) when kind in [:purple_trade, :purple_buy, :buy, :upgrade],
    do: :purple

  def choice_colour({:upgrade, _, _}), do: :purple
  def choice_colour(_choice), do: nil

  @doc """
  How long a step stays on the tiles in Auto mode, in ms, at `speed`. Round 35:
  the die step waits for its dice to roll (app.css `.stage-die`: one roll of
  `--die-roll`, 1.5556 beats, after the other per seat) before its beats start.
  """
  @spec duration(atom, Reveal.slide() | nil) :: pos_integer
  def duration(speed, slide \\ nil)

  def duration(speed, %{kind: :die, rows: rows}) do
    rolls = rows |> Enum.map(&length(Map.get(&1, :rolls, []))) |> Enum.max(fn -> 0 end)
    duration(speed) + round(Reveal.beat_ms(speed) * @die_roll_beats * rolls)
  end

  def duration(speed, _slide), do: Reveal.beat_ms(speed) * @beats

  @doc """
  The step's name for the stage pill: "Bonus die", "Black book", "Ruby space", ...
  """
  @spec label(Reveal.slide()) :: String.t()
  def label(%{kind: :die}), do: "Bonus die"
  def label(%{kind: :book, book: colour}), do: "#{String.capitalize(to_string(colour))} book"
  def label(%{kind: :space}), do: "Scoring space"
  def label(%{kind: :standings}), do: "Round scored"
  def label(%{kind: :shop}), do: "Shop"

  # Round 37: the result columns of a stage, in this order (`columns/1`).
  @columns [:dice, :chip, :coins, :vp, :rubies, :droplet, :flask, :gain, :total]

  @doc """
  Round 37 (items 1-3): the result columns of the stage rows `rows`
  (`stage_rows/3`), in a fixed order: one column for each kind of result that
  some row has (e.g. the scoring space: coins, VP, rubies). The results stage
  puts every row's result in its kind's column, so the numbers align.
  """
  @spec columns([stage_row]) :: [atom]
  def columns(rows) do
    kinds = rows |> Enum.flat_map(& &1.got) |> Enum.map(&cell_kind/1) |> MapSet.new()
    Enum.filter(@columns, &(&1 in kinds))
  end

  @doc "The column of a result cell (`columns/1`); `:choosing` has none."
  @spec cell_kind(cell) :: atom
  def cell_kind(:choosing), do: :choosing
  def cell_kind({kind, _}), do: kind

  @typedoc """
  One part of a results stage row (`stage_rows/2`): a reason or a result, drawn as
  icons by `QuacksWeb.TileRevealComponents.results_stage/1`.
  """
  @type cell ::
          {:count, non_neg_integer, atom}
          | {:beats, [Game.seat()], :both | :some | :tie}
          | {:chips, [Quacks.Rules.Chips.chip()]}
          | {:text, String.t()}
          | {:dice, [term]}
          | {:chip, atom}
          | {:vp | :rubies | :droplet | :coins | :flask, non_neg_integer}
          | {:gain, integer}
          | {:total, integer}
          | {:rank, non_neg_integer}
          | :choosing

  @type stage_row :: %{
          optional(:shift) => integer,
          seat: Game.seat(),
          why: [cell],
          got: [cell],
          none: boolean,
          lead: boolean
        }

  @doc """
  Round 35 (direction A): the results stage's rows for the step `slide`, one per
  seat. The reason (`why`) and the result (`got`) are icons where possible. Seat
  order; the "Round scored" step (`:standings`) sorts by rank, the leader first
  (`lead`). A row with no result has `none: true` (it fades). `choosing` lists
  the seats that still choose in this book (round 35 item 7): their result is
  `:choosing`.
  """
  @spec stage_rows(Game.t(), Reveal.slide(), [Game.seat()]) :: [stage_row]
  def stage_rows(game, slide, choosing \\ [])

  # Equal VP share a place (and the lead).
  def stage_rows(_game, %{kind: :standings, rows: rows}, _choosing) do
    for r <- Enum.sort_by(rows, & &1.rank) do
      place = Enum.count(rows, &(&1.vp > r.vp))

      %{
        seat: r.seat,
        why: [{:rank, place}],
        got: [{:gain, r.vp - r.from_vp}, {:total, r.vp}],
        none: false,
        lead: place == 0,
        # Round 37 (item 3): rows up from the old place (FLIP, app.css `.stage-shift`).
        shift: r.from_rank - r.rank
      }
    end
  end

  def stage_rows(game, %{kind: :die, rows: rows}, _choosing) do
    for s <- game.seats do
      faces = rows |> row_of(s) |> Map.get(:rolls, []) |> Enum.map(& &1.face)

      why =
        cond do
          faces != [] -> [{:text, "furthest"}]
          Game.player(game, s).exploded? -> [{:text, "exploded"}]
          true -> []
        end

      got = if faces == [], do: [], else: [{:dice, faces}]
      %{seat: s, why: why, got: got, none: faces == [], lead: false}
    end
  end

  def stage_rows(game, %{kind: :book, book: colour, rows: rows}, choosing) do
    for s <- game.seats do
      row = row_of(rows, s)
      got = book_got(row, colour, s in choosing)
      %{seat: s, why: book_why(row, colour), got: got, none: got == [], lead: false}
    end
  end

  def stage_rows(game, %{kind: :space, rows: rows}, _choosing) do
    for s <- game.seats do
      row = row_of(rows, s)

      got =
        for {k, n} <- [coins: row[:coins], vp: row[:vp], rubies: row[:rubies]], n > 0, do: {k, n}

      why = if row[:exploded], do: [{:text, "exploded"}], else: []
      %{seat: s, why: why, got: got, none: got == [], lead: false}
    end
  end

  # Round 37 (item 4): what each seat did in the last shop: the chips it bought,
  # its droplet pushes and flask refills.
  def stage_rows(game, %{kind: :shop, rows: rows}, _choosing) do
    for s <- game.seats do
      row = row_of(rows, s)
      chips = Map.get(row, :chips, [])
      got = for {k, n} <- [droplet: row[:droplets], flask: row[:flasks]], (n || 0) > 0, do: {k, n}
      why = if chips == [], do: [], else: [{:chips, chips}]
      %{seat: s, why: why, got: got, none: chips == [] and got == [], lead: false}
    end
  end

  def stage_rows(_game, _slide, _choosing), do: []

  defp row_of(rows, seat), do: Enum.find(rows, %{}, &(&1.seat == seat))

  # Black book I: the black count and whom it beats ("2 [black] > both").
  defp book_why(%{chips: chips, compare: [_ | _] = targets, scored: scored}, :black) do
    mine = length(chips)
    beaten = for {t, n} <- targets, mine > n, do: t

    beats =
      cond do
        beaten != [] and length(beaten) == length(targets) and length(targets) > 1 ->
          [{:beats, beaten, :both}]

        beaten != [] ->
          [{:beats, beaten, :some}]

        scored ->
          [{:beats, Enum.map(targets, &elem(&1, 0)), :tie}]

        true ->
          []
      end

    [{:count, mine, :black} | beats]
  end

  defp book_why(%{chips: [_ | _] = chips}, _colour), do: [{:chips, chips}]
  defp book_why(_row, _colour), do: []

  defp book_got(_row, _colour, true), do: [:choosing]

  defp book_got(%{scored: true} = row, colour, false) do
    case rewards(row) do
      [] -> [{:chip, colour}]
      rewards -> rewards
    end
  end

  defp book_got(_row, _colour, false), do: []

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
      row -> space_badges(row)
    end
  end

  # Round 37: the shop step shows the chips each seat bought on its tile.
  def badges(%{kind: :shop, rows: rows}, seat) do
    case Enum.find(rows, &(&1.seat == seat)) do
      %{chips: chips, droplets: droplets} ->
        Enum.map(chips, &{:bought, &1}) ++ if(droplets > 0, do: [{:droplet, droplets}], else: [])

      _row ->
        []
    end
  end

  def badges(_slide, _seat), do: []

  defp space_badges(row), do: row |> Map.put(:droplet, 0) |> rewards()

  @doc """
  Round 31: the replay lines of `seat` (`Replay.beats/2`) that the step `slide`
  shows, renumbered from beat 0, so the pot plays this step's update only (its
  rubies fly, its VP floats, its marks light up) when the step comes. The coins
  step has no line: the pot lights its scoring space (`marks/3`).
  """
  @spec step_lines(Game.t(), Game.seat(), Reveal.slide() | nil) :: [Replay.line()]
  def step_lines(game, seat, slide) do
    lines = game |> Replay.beats(seat) |> Enum.filter(&step_line?(slide, &1))
    first = lines |> Enum.map(& &1.beat) |> Enum.min(fn -> 0 end)
    Enum.map(lines, &%{&1 | beat: &1.beat - first})
  end

  defp step_line?(%{kind: :die}, line), do: line.kind == :die
  defp step_line?(%{kind: :book, book: colour}, line), do: Reveal.book_line?(line, colour)
  defp step_line?(%{kind: :space}, line), do: line.kind == :space

  defp step_line?(_slide, _line), do: false

  @doc """
  The pot marks the step lights up (`Replay.highlights/1` of `step_lines/3`); the
  space step also lights the scoring space.
  """
  @spec marks(Game.t(), Game.seat(), Reveal.slide() | nil) :: %{Replay.mark() => integer}
  def marks(game, seat, %{kind: :space} = slide),
    do: game |> step_lines(seat, slide) |> Replay.highlights() |> Map.put_new(:ring, 0)

  def marks(game, seat, slide), do: game |> step_lines(seat, slide) |> Replay.highlights()

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
    |> Enum.take(max(index + 1, 0))
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

  @doc "The droplet moves the steps `slides` bring `seat` (die faces, book moves)."
  @spec moves_in([Reveal.slide()], Game.seat()) :: non_neg_integer
  def moves_in(slides, seat) when is_list(slides),
    do: slides |> Enum.map(&droplet_moves(&1, seat)) |> Enum.sum()

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
  line plays its swap again. Round 29 (B2): while the round brews, the seat's
  last draws (`{:drew, chip, age, id}`, newest first), with `hold: true` (the line stays on the news).
  """
  @spec news(Game.t(), Game.seat(), map | nil) ::
          %{required(:key) => String.t(), required(:items) => [term], optional(:hold) => true}
          | nil
  # Round 31: the news of the step Next scored last (`index` names the next one).
  def news(_game, _seat, %{tiles: true, index: 0}), do: nil

  def news(game, seat, %{tiles: true, slides: slides, index: index}) do
    slide = Enum.at(slides, index - 1)
    items = step_news(slide, seat)
    if items != [], do: %{key: "#{game.round}-#{index}", items: items}
  end

  # A card on screen (the overlay): its news waits until it is dismissed.
  def news(_game, _seat, %{key: {:card, _}}), do: nil

  def news(%Game{phase: :potions} = game, seat, _reveal) do
    draw_news(game, seat) || shop_news(game, seat)
  end

  def news(game, seat, _reveal), do: shop_news(game, seat)

  # How many draws fit on a tile's line at 360 px, by the players row's columns
  # (`TileComponents.loop_columns/1`): four columns 2, three 4, two 7, one 8.
  # Round 31: the line's right end holds the black count and the white sum, and
  # the draws overlap a little (`TileRevealComponents`).
  defp tile_draws(seats) do
    case QuacksWeb.TileComponents.loop_columns(length(seats)) do
      4 -> 2
      3 -> 4
      2 -> 7
      _ -> 8
    end
  end

  # Round 29 (B2): while the seat brews, its last draws (newest first, as many as
  # fit, `tile_draws/1`; the tile shows an explosion itself). `hold` keeps the line on the
  # news (no swap back): the draws are the tile's latest update until the shop.
  defp draw_news(game, seat) do
    case Game.player(game, seat) do
      %{drawn: []} ->
        nil

      %{drawn: drawn} ->
        items =
          drawn
          |> Enum.take(tile_draws(game.seats))
          |> Enum.with_index()
          |> Enum.map(fn {{chip, _space}, i} ->
            {:drew, chip, i, "#{seat}-#{game.round}-#{length(drawn)}-#{i}"}
          end)

        # Round 31 (item 5): `line` keeps the line's id for the whole brewing, so
        # a draw does not play the line's entrance again; each chip's id carries
        # the draw count, so the chips enter again: the new one pops in at the
        # left, the older ones slide one place right (app.css `.tile-draw`).
        %{
          key: "#{game.round}-draw-#{length(drawn)}",
          line: "#{game.round}-draw",
          items: items,
          hold: true
        }
    end
  end

  defp shop_news(game, seat) do
    %{chips: chips, droplets: droplets} = shop(game, seat)
    card = card_news(game, seat)

    items =
      Enum.map(chips, &{:bought, &1}) ++
        if(droplets > 0, do: [{:droplet, droplets}], else: []) ++ card

    round = if game.phase == :shopping, do: game.round, else: game.round - 1

    if items != [],
      do: %{key: "#{round}-shop-#{length(chips)}-#{droplets}-#{length(card)}", items: items}
  end

  # Round 28: Flea Market (P13): the chip `seat` traded and the chip it got, once
  # chosen. Round 30: every card that draws chips per seat (Less is More too): the
  # chip or ruby it gave (`Quacks.Game.Fortune.reveals/1`). B7's placed chip is a
  # draw: the draw news shows it.
  # Round 35: not for a choice card (its rows are for the grown card).
  defp card_news(game, seat) do
    case Fortune.reveal_card?(game.fortune_card) && Fortune.reveals(game)[seat] do
      %{choosing?: false, traded: traded, gains: gains} ->
        Enum.flat_map(gains, fn
          {:chip, chip} -> [{:card, game.fortune_card, traded, chip}]
          {:rubies, n} -> [{:rubies, n}]
          {:placed, _chip} -> []
        end)

      _other ->
        []
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
          droplets: non_neg_integer,
          flasks: non_neg_integer
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
      droplets: Enum.count(round, &spent?(&1, seat, :droplet)),
      flasks: Enum.count(round, &spent?(&1, seat, :flask))
    }
  end

  defp spent?({seat, {:rubies_spent, what}}, seat, what), do: true
  defp spent?({seat, {:rubies_spent, what, _price}}, seat, what), do: true
  defp spent?(_entry, _seat, _what), do: false
end
