defmodule QuacksWeb.Reveal do
  @moduledoc """
  The reveal overlay's slides (round 14): what the round showed, one slide at a
  time. Pure functions over the game; the data comes from `QuacksWeb.Replay`'s
  lines (`beats/3`, `updates/2`) and the log, never from new engine data.

  A *moment* is a point of the game with something to reveal (`moment/1`):

  - `{:card, round}`: a new fortune teller card (the round's start): one slide;
  - `{:results, round}`: the evaluation (the shop phase began). Round 20: one slide
    per scoring step with every seat on it, one row each in VP order: the bonus
    die (`:die`), the black, green and purple books and any other book that paid
    (`:book`), the scoring space (`:space`, with the ruby landings); a step nobody
    scores in has no slide. Then one standings slide (round 28: no results table;
    it carries the gains no step showed) (the totals; the rows glide from the old order to the new
    one). Round 29: round 9 has no standings slide;

  Round 31: a finished game has no moment. The final scoring is no slide any
  more: `final_rows/1` feeds the score chart over the pot
  (`QuacksWeb.FinalComponents`).

  `slides/2` builds the slide list of the game's moment; `GameLive` shows it in
  the overlay and keeps `%{key, slides, index}` per browser. Every slide carries
  its `gains` (`%{seat => {vp, rubies}}`) and the `standings` after it (round 16:
  the running results strip), so the overlay needs no other state.
  """

  alias Quacks.Game
  alias Quacks.Game.{Evaluation, Fortune}
  alias Quacks.Rules.PotTrack
  alias QuacksWeb.Replay

  @type moment :: {:card | :results, 1..9}

  @type slide :: %{required(:kind) => atom, optional(atom) => term}

  # The evaluation's book slides (round 20): black, green, purple, then any other
  # book that paid, in this colour order.
  @books [:black, :green, :purple]
  @other_books [:orange, :blue, :red, :yellow, :locoweed, :white]

  # How long a slide stays in Auto mode at Normal speed, in ms.
  @durations %{
    card: 3500,
    die: 3200,
    book: 3400,
    space: 3000,
    standings: 3500
  }

  # The speeds of the menu and their factor on the slide times and the CSS beats.
  @speeds [normal: 1.0, slow: 1.6, slower: 2.5]
  # The CSS beat step at Normal speed, ms (`--beat-ms`, app.css).
  @beat_ms 450

  @doc "The speeds of the menu's Speed setting, slowest last."
  @spec speeds() :: [atom]
  def speeds, do: Keyword.keys(@speeds)

  @doc "The factor of `speed` on the slide times and the CSS beats."
  @spec factor(atom) :: float
  def factor(speed), do: Keyword.fetch!(@speeds, speed)

  @doc "The CSS beat step of `speed` in ms (`--beat-ms` on `<html>`)."
  @spec beat_ms(atom) :: pos_integer
  def beat_ms(speed), do: round(@beat_ms * factor(speed))

  @doc """
  The game's moment, or nil: the results while the shop phase runs, else the
  round's new card (when there is one). A finished game has none (round 31).
  """
  @spec moment(Game.t()) :: moment | nil
  def moment(%Game{phase: :shopping, round: round}), do: {:results, round}
  def moment(%Game{phase: :over}), do: nil
  def moment(%Game{phase: :patient_choice}), do: nil
  def moment(%Game{fortune_card: nil}), do: nil
  def moment(%Game{round: round}), do: {:card, round}

  @doc """
  The slides of the game's moment for `seat`'s browser (round 20: every slide shows
  the whole table, so the seat does not change them). Empty without a moment.
  """
  @spec slides(Game.t(), Game.seat()) :: [slide]
  def slides(game, seat) do
    case moment(game) do
      {:card, round} ->
        running(
          [
            %{
              kind: :card,
              round: round,
              card: game.fortune_card,
              outcomes: card_outcomes(game, seat),
              # Round 35: a choice card's rows wait for the choices (the grown card).
              reveals:
                if(Fortune.reveal_card?(game.fortune_card), do: Fortune.reveals(game), else: %{}),
              order: Game.turn_order(game)
            }
          ],
          now(game)
        )

      {:results, round} ->
        game |> results(round) |> running(before_results(game))

      nil ->
        []
    end
  end

  @doc """
  Round 24: what this round's card did to `seat` when it came (its automatic part,
  e.g. a droplet, VP, a ruby, drawn chips), oldest first: the `{:fortune, id,
  outcome}` log entries since the card was drawn. Empty for a card that does
  nothing by itself, and for a spectator.
  """
  @spec card_outcomes(Game.t(), Game.seat() | nil) :: [term]
  def card_outcomes(_game, nil), do: []

  def card_outcomes(game, seat) do
    game.log
    |> Enum.take_while(&(not match?({:fortune_drawn, _}, &1)))
    |> Enum.flat_map(fn
      {^seat, {:fortune, _id, outcome}} when outcome != :skip -> [outcome]
      _entry -> []
    end)
    |> Enum.reverse()
  end

  @doc "How long `slide` stays in Auto mode, in ms, at speed `factor` (1, 1.6, 2.5)."
  @spec duration(slide, number) :: pos_integer
  def duration(%{kind: kind}, factor), do: round(Map.fetch!(@durations, kind) * factor)

  # -- the evaluation ------------------------------------------------------------------

  # Round 20: one slide per scoring step, every seat on it (one row each, in VP
  # order): the bonus die, the black, green and purple books, any other book that
  # paid, the scoring space; a step nobody scores in has no slide. Then the standings
  # (round 28: no results table; the player sheet lists each seat's result lines).
  defp results(game, round) do
    lines = Map.new(game.seats, &{&1, Replay.beats(game, &1)})
    order = standings_of(now(game))
    others = other_books(lines)

    books =
      Enum.map(@books, fn colour ->
        book_slide(game, lines, order, colour, &(&1.kind == colour))
      end)

    other =
      Enum.map(others, fn colour ->
        book_slide(game, lines, order, colour, &other_book_line?(&1, colour))
      end)

    steps = [die_slide(lines, order)] ++ books ++ other ++ [space_slide(game, lines, order)]

    steps = Enum.reject(steps, &is_nil/1)
    before = before_results(game)

    # The standings carry what the steps did not show (cards, essence, witches, ...),
    # so the running totals end on the seats' totals.
    shown = Enum.reduce(Enum.flat_map(steps, &Map.to_list(&1.gains)), before, &add_gain/2)

    rest =
      Map.new(now(game), fn {s, {vp, rubies}} ->
        {v, r} = shown[s]
        {s, {max(vp - v, 0), max(rubies - r, 0)}}
      end)

    # Round 29 (F1): round 9 has no standings slide; the game's end follows the
    # round's last decisions.
    if round == 9,
      do: steps,
      else: steps ++ [Map.put(standings_slide(game, round, before), :gains, rest)]
  end

  # The bonus die: every roll of the round (the base die and book G6's), a row per
  # seat with its faces side by side.
  defp die_slide(lines, order) do
    rows =
      for s <- order do
        rolls =
          for line <- lines[s],
              line.kind == :die,
              do: Map.take(line, [:face, :text, :vp, :rubies])

        %{seat: s, rolls: rolls, vp: sum(rolls, :vp), rubies: sum(rolls, :rubies)}
      end

    if Enum.any?(rows, &(&1.rolls != [])),
      do: %{kind: :die, rows: rows, gains: gains(rows)}
  end

  # One book's slide: a row per seat with the chips that count, what it is compared
  # with (black: `Evaluation.targets/2`), its result lines and the reward. `pick`
  # selects the book's lines; no seat with a line, no slide.
  defp book_slide(game, lines, order, colour, pick) do
    mine = Map.new(order, fn s -> {s, Enum.filter(lines[s], pick)} end)

    if Enum.any?(mine, fn {_s, l} -> l != [] end) do
      before = if colour == :black, do: before_game(game)

      rows =
        for s <- order do
          ls = mine[s]
          marks = ls |> Enum.flat_map(& &1.marks) |> Enum.uniq()

          %{
            seat: s,
            scored: ls != [],
            chips: counted(game, s, colour, marks),
            compare: compare(game, before, s),
            lines: Enum.map(ls, & &1.text),
            vp: sum(ls, :vp),
            rubies: sum(ls, :rubies),
            droplet: Enum.count(marks, &(&1 == :droplet))
          }
        end

      %{
        kind: :book,
        book: colour,
        set: Map.get(game.sets, colour, 1),
        rows: rows,
        gains: gains(rows)
      }
    end
  end

  # The scoring space: a row per seat with its coins, its VP and whether it landed
  # on a ruby (an exploded seat took the VP or the coins).
  defp space_slide(game, lines, order) do
    rows =
      for s <- order do
        p = Game.player(game, s)
        index = Game.scoring_index(game, s)
        space = Enum.filter(lines[s], &(&1.kind == :space))

        %{
          seat: s,
          space: index,
          coins: coins(p, index),
          vp: sum(space, :vp),
          rubies: sum(space, :rubies),
          exploded: p.exploded?,
          choice: p.explosion_choice
        }
      end

    if Enum.any?(rows, &(&1.coins > 0 or &1.vp > 0 or &1.rubies > 0)),
      do: %{kind: :space, rows: rows, gains: gains(rows)}
  end

  defp coins(%{explosion_choice: :vp}, _index), do: 0
  defp coins(_player, index), do: PotTrack.at(index).coins

  defp gains(rows), do: Map.new(rows, &{&1.seat, {&1.vp, &1.rubies}})

  # The books other than black, green and purple that paid VP or rubies this round
  # (e.g. blue III–VI while brewing), in the board's colour order.
  defp other_books(lines) do
    paid =
      for {_s, ls} <- lines, line <- ls, colour = other_book(line), do: colour

    Enum.filter(@other_books, &(&1 in paid))
  end

  defp other_book(%{kind: :other, book: {colour, _set}, vp: vp, rubies: rubies})
       when vp > 0 or rubies > 0,
       do: colour

  defp other_book(_line), do: nil

  defp other_book_line?(line, colour), do: other_book(line) == colour

  @doc """
  Whether the replay `line` belongs to the book slide of `colour` (round 31: the
  pot plays one step at a time on the tiles, `QuacksWeb.TileReveal.step_lines/3`).
  """
  @spec book_line?(Replay.line(), atom) :: boolean
  def book_line?(line, colour) when colour in @books, do: line.kind == colour
  def book_line?(line, colour), do: other_book_line?(line, colour)

  # The chips a book counted, oldest first: the chips its lines mark, else the book's
  # own rule (green: of the last two; the others: all of the colour in the pot).
  defp counted(game, seat, colour, marks) do
    drawn = Enum.reverse(Game.player(game, seat).drawn)

    case Enum.filter(marks, &is_integer/1) do
      [] ->
        drawn = if colour == :green, do: Enum.take(drawn, -2), else: drawn
        for {{^colour, _} = chip, _i} <- drawn, do: chip

      indexes ->
        for {chip, i} <- drawn, i in indexes, do: chip
    end
  end

  # Black book I compares the black chips with `Evaluation.targets/2` (both
  # neighbours, or the players ranked above): `[{seat, count}]` of the targets, with
  # the standings before this round's results (`before`, `Replay.before/2`). Not
  # black, or solo: nobody to compare with.
  defp compare(_game, nil, _seat), do: []
  defp compare(%Game{seats: [_]}, _before, _seat), do: []

  defp compare(game, before, seat),
    do: for(s <- Evaluation.targets(before, seat), do: {s, blacks(game, s)})

  # The game with every seat's VP and rubies as they were before the round's results.
  defp before_game(game) do
    Enum.reduce(before_results(game), game, fn {s, {vp, rubies}}, g ->
      Game.update_player(g, s, &%{&1 | vp: vp, rubies: rubies})
    end)
  end

  defp blacks(game, seat),
    do: Enum.count(Game.player(game, seat).drawn, &match?({{:black, _}, _}, &1))

  # The standings after the round (round 18): every seat's total VP and rubies, before
  # and after the round's results, with its rank before (`from_rank`) and after
  # (`rank`, 0 is first). The rows stay in seat order: the overlay moves each row to
  # its rank with CSS, from the old rank to the new one.
  defp standings_slide(game, round, before) do
    totals = now(game)
    from_ranks = ranks(before)
    to_ranks = ranks(totals)

    rows =
      for s <- game.seats do
        {from_vp, from_rubies} = before[s]
        {vp, rubies} = totals[s]

        %{
          seat: s,
          from_rank: from_ranks[s],
          rank: to_ranks[s],
          from_vp: from_vp,
          vp: vp,
          from_rubies: from_rubies,
          rubies: rubies
        }
      end

    %{kind: :standings, round: round, last: round == 9, rows: rows}
  end

  defp ranks(totals), do: totals |> standings_of() |> Enum.with_index() |> Map.new()

  defp sum(lines, key), do: lines |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum()

  # -- the running results (round 16) -------------------------------------------------

  # Every seat's `{vp, rubies}` now.
  defp now(game),
    do: Map.new(game.seats, &{&1, {Game.player(game, &1).vp, Game.player(game, &1).rubies}})

  # Every seat's `{vp, rubies}` before this round's results (`Replay.before/2`).
  defp before_results(game) do
    Map.new(game.seats, fn s ->
      %{vp: vp, rubies: rubies} = Replay.before(game, s)
      {s, {vp, rubies}}
    end)
  end

  # Each slide gets `standings`: `[%{seat, vp, gain}]` after the slide, in VP order;
  # `gain` is the VP this slide added (0: nothing).
  defp running(slides, base) do
    slides
    |> Enum.map_reduce(base, fn slide, totals ->
      gains = Map.get(slide, :gains, %{})

      totals = Enum.reduce(gains, totals, &add_gain/2)

      rows =
        for s <- standings_of(totals) do
          %{seat: s, vp: elem(totals[s], 0), gain: gains |> Map.get(s, {0, 0}) |> elem(0)}
        end

      {slide |> Map.put_new(:gains, %{}) |> Map.put(:standings, rows), totals}
    end)
    |> elem(0)
  end

  defp add_gain({s, {vp, rubies}}, totals),
    do: Map.update(totals, s, {vp, rubies}, fn {v, r} -> {v + vp, r + rubies} end)

  # Seats in VP order: most VP first, a tie to fewer rubies, then the lower seat (the
  # order of `Quacks.Game.Evaluation.standings/1`).
  defp standings_of(totals) do
    totals
    |> Map.keys()
    |> Enum.sort_by(fn s ->
      {v, r} = totals[s]
      {-v, r, s}
    end)
  end

  # -- the final scoring ---------------------------------------------------------------

  @doc """
  The final scoring (round 29 F1; round 31: the score chart over the pot), one row
  per seat in final order: its `place` (equal VP share a place), its round-9
  total `from_vp`, its final `parts` (coins, rubies, pennies → VP, from the log)
  and its final `vp`.
  """
  @spec final_rows(Game.t()) :: [map]
  def final_rows(game) do
    totals = now(game)
    scores = Game.score(game)

    game.seats
    |> Enum.map(fn s ->
      parts = final_parts(game, s)
      {vp, _rubies} = totals[s]
      gain = parts |> Enum.map(&elem(&1, 2)) |> Enum.sum()

      %{
        seat: s,
        from_vp: vp - gain,
        vp: vp,
        parts: parts,
        place: 1 + Enum.count(scores, fn {_s, v} -> v > scores[s] end)
      }
    end)
    |> Enum.sort_by(&{&1.place, -&1.vp, &1.seat})
  end

  defp final_parts(game, s) do
    {coins, coins_vp, rubies, rubies_vp} =
      Enum.find_value(game.log, {0, 0, 0, 0}, fn
        {^s, {:final_conversion, c, cvp, r, rvp}} -> {c, cvp, r, rvp}
        _entry -> nil
      end)

    pennies =
      Enum.find_value(game.log, 0, fn
        {^s, {:pennies, vp}} -> vp
        _entry -> nil
      end)

    Enum.reject(
      [{:coins, coins, coins_vp}, {:rubies, rubies, rubies_vp}, {:pennies, nil, pennies}],
      fn {_kind, n, vp} -> vp == 0 and n in [0, nil] end
    )
  end
end
